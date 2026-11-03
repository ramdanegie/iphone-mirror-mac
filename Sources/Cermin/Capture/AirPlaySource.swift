import CerminCore
import Darwin
import Foundation
import Network
import VideoToolbox

/// Wireless mirroring (PRD §F8, option A): UxPlay handles the AirPlay protocol and forwards decrypted H.264 as RTP
/// to 127.0.0.1; Cermin depacketizes, decodes with VideoToolbox and renders in its own window.
@MainActor
final class AirPlaySource {
    private let receiver: RTPReceiver
    private var process: Process?
    private var output: FileHandle?
    private var partialLine = ""
    private var stopping = false
    private(set) var recentLog: [String] = []

    var onEvent: ((UxPlayEvent) -> Void)?
    var onExit: ((String) -> Void)?

    init(pipeline: DisplayPipeline) {
        receiver = RTPReceiver(pipeline: pipeline)
        receiver.onFailure = { [weak self] message in
            Task { @MainActor in
                self?.stop()
                self?.onExit?(message)
            }
        }
    }

    /// Places `scripts/install-uxplay.sh` and Homebrew/MacPorts install to.
    static func findBinary() -> URL? {
        #if DEBUG
        if let fake = ProcessInfo.processInfo.environment["CERMIN_UXPLAY"] { return URL(fileURLWithPath: fake) }
        #endif
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/Library/Application Support/Cermin/bin/uxplay", "/opt/homebrew/bin/uxplay",
                "/usr/local/bin/uxplay", "/opt/local/bin/uxplay"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    func start(_ config: UxPlayConfig) throws {
        guard let binary = Self.findBinary() else { throw CocoaError(.fileNoSuchFile) }
        Self.killOrphan() // before stop(), which forgets the saved PID
        stop()
        receiver.start(port: config.rtpPort)

        // UxPlay logs with printf and never flushes: through a pipe its PIN/connection lines would sit in a
        // 4 KB buffer. A pseudo-terminal makes its stdout line-buffered.
        var master: Int32 = -1, slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { throw POSIXError(.EIO) }
        let output = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let childEnd = FileHandle(fileDescriptor: slave, closeOnDealloc: true)

        let p = Process()
        p.executableURL = binary
        p.arguments = config.arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin"
        p.environment = env
        p.standardOutput = childEnd
        p.standardError = childEnd
        p.standardInput = FileHandle.nullDevice
        output.readabilityHandler = { [weak self] handle in
            // Plain read(2): returns what is available now. (FileHandle.read(upToCount:) waits for EOF, and
            // availableData raises an ObjC exception on the EIO a pty gives once the child is gone.)
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let n = read(handle.fileDescriptor, &buffer, buffer.count)
            guard n > 0 else {
                handle.readabilityHandler = nil
                return
            }
            let chunk = String(decoding: buffer[0..<n], as: UTF8.self)
            Task { @MainActor in self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { @MainActor in self?.processExited(proc, status: status) }
        }
        stopping = false
        recentLog = []
        partialLine = ""
        do {
            try p.run()
        } catch {
            output.readabilityHandler = nil
            throw error
        }
        try? childEnd.close() // the child holds its own copy; ours would keep the pty open forever
        self.output = output
        process = p
        UserDefaults.standard.set(Int(p.processIdentifier), forKey: "uxplayPID")
    }

    /// Stops UxPlay and waits (≤1.5 s) for it to exit so its AirPlay ports are free for a restart.
    /// Video packets are dropped from here on, until the next `start`.
    func stop() {
        stopping = true
        receiver.pause()
        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(1.5)
            while process.isRunning, Date() < deadline { usleep(20_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process = nil
        output?.readabilityHandler = nil
        output = nil
        UserDefaults.standard.removeObject(forKey: "uxplayPID")
    }

    /// App quit / wireless switched off: also release the video port.
    func shutdown() {
        stop()
        receiver.close()
    }

    private func consume(_ chunk: String) {
        partialLine += chunk
        var lines = partialLine.components(separatedBy: "\n")
        partialLine = lines.removeLast()
        for raw in lines {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) // pty turns \n into \r\n
            guard !line.isEmpty else { continue }
            recentLog.append(line)
            if recentLog.count > 200 { recentLog.removeFirst(recentLog.count - 200) }
            if let event = UxPlayLogParser.parse(line) { onEvent?(event) }
        }
    }

    private func processExited(_ proc: Process, status: Int32) {
        guard proc === process else { return } // an instance we already stopped or replaced
        process = nil
        receiver.pause()
        if !stopping {
            let tail = recentLog.suffix(3).joined(separator: "\n")
            onExit?("UxPlay berhenti (kode \(status)).\(tail.isEmpty ? "" : "\n\(tail)")")
        }
    }

    /// A crashed Cermin can leave UxPlay holding the AirPlay ports; only kill it if the PID really is uxplay.
    private static func killOrphan() {
        let pid = pid_t(UserDefaults.standard.integer(forKey: "uxplayPID"))
        guard pid > 0 else { return }
        var name = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &name, UInt32(name.count)) > 0, cString(name) == "uxplay" {
            kill(pid, SIGTERM)
        }
        UserDefaults.standard.removeObject(forKey: "uxplayPID")
    }
}

/// UDP RTP → H264RTPDepacketizer → VideoToolbox → DisplayPipeline. All state lives on `queue`.
/// The port is bound once and kept across UxPlay restarts (re-binding right after a cancel can race).
private final class RTPReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cermin.airplay.rtp")
    private let decoder: H264Decoder
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var depacketizer = H264RTPDepacketizer()
    private var accepting = false
    /// Set once before `start`.
    var onFailure: (@Sendable (String) -> Void)?

    init(pipeline: DisplayPipeline) {
        decoder = H264Decoder(pipeline: pipeline)
    }

    func start(port: UInt16) {
        queue.sync {
            resetStream()
            accepting = true
            if listener == nil { bind(port) }
        }
    }

    /// Drop everything until the next `start` (old UxPlay may still be flushing packets).
    func pause() {
        queue.sync {
            accepting = false
            connections.forEach { $0.cancel() }
            connections = []
            resetStream()
        }
    }

    func close() {
        pause()
        queue.sync {
            listener?.cancel()
            listener = nil
        }
    }

    private func resetStream() {
        depacketizer = H264RTPDepacketizer()
        decoder.reset()
    }

    private func bind(_ port: UInt16) {
        let params = NWParameters.udp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        guard let listener = try? NWListener(using: params) else {
            onFailure?("Port video \(port) tidak bisa dibuka.")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.accepting else { connection.cancel(); return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(on: connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, listener === self.listener, case .failed(let error) = state else { return }
            listener.cancel()
            self.listener = nil
            self.onFailure?("Port video \(port) tidak bisa dipakai (\(error.localizedDescription)). Tutup app lain yang memakai port itu.")
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, self.accepting {
                for unit in self.depacketizer.push([UInt8](data)) { self.decoder.decode(unit) }
            }
            if error == nil { self.receive(on: connection) }
        }
    }
}

private final class H264Decoder: @unchecked Sendable {
    private let pipeline: DisplayPipeline
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?

    init(pipeline: DisplayPipeline) { self.pipeline = pipeline }

    func reset() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        format = nil
        sps = nil
        pps = nil
    }

    func decode(_ unit: AccessUnit) {
        for nalu in unit.nalus {
            switch H264.type(of: nalu) {
            case H264.sps? where nalu != sps: sps = nalu; format = nil
            case H264.pps? where nalu != pps: pps = nalu; format = nil
            default: break
            }
        }
        if format == nil { makeSession() } // new SPS/PPS = new resolution (e.g. rotation)
        guard let session, let format else { return }

        let bytes = H264.avcc(unit)
        guard !bytes.isEmpty else { return }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes.count,
                                                 blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes.count, flags: 0, blockBufferOut: &block) == noErr,
              let block,
              bytes.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                                                     offsetIntoDestination: 0, dataLength: bytes.count) }) == noErr
        else { return }

        var sample: CMSampleBuffer?
        var size = bytes.count
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return }

        let pipeline = self.pipeline
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
            guard status == noErr, let image, let decoded = makeSampleBuffer(from: image) else { return }
            pipeline.push(decoded, from: .wireless)
        }
        if status == kVTInvalidSessionErr { self.format = nil } // e.g. after sleep/GPU switch: rebuild on the next frame
    }

    private func makeSession() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        guard let sps, let pps else { return }
        var desc: CMVideoFormatDescription?
        let status = sps.withUnsafeBufferPointer { s in
            pps.withUnsafeBufferPointer { p in
                let pointers = [s.baseAddress!, p.baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &desc)
            }
        }
        guard status == noErr, let desc else { return }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var newSession: VTDecompressionSession?
        guard VTDecompressionSessionCreate(allocator: nil, formatDescription: desc, decoderSpecification: nil,
                                           imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
                                           decompressionSessionOut: &newSession) == noErr else { return }
        format = desc
        session = newSession
    }
}
