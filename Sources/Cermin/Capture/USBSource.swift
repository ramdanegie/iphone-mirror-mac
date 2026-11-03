import AVFoundation
import CoreMediaIO
import IOKit

/// iPhone screen over USB — the same CoreMediaIO path QuickTime uses (PRD §F1).
@MainActor
final class USBSource {
    enum Problem: Equatable { case cameraDenied, captureFailed(String) }

    private let pipeline: DisplayPipeline
    private let forwarder: FrameForwarder
    private let queue = DispatchQueue(label: "cermin.usb.capture")
    private let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
    private var session: AVCaptureSession?
    private var audioOutput: AVCaptureAudioPreviewOutput?
    private(set) var device: AVCaptureDevice?
    private var observers: [NSObjectProtocol] = []
    private var requestingAccess = false
    /// Consecutive capture failures; auto-retry stops at 3 until replug or a manual retry (no silent loops).
    private var failures = 0

    var onDeviceAppeared: ((AVCaptureDevice) -> Void)?
    var onDeviceLost: (() -> Void)?
    var onProblem: ((Problem?) -> Void)?
    /// Off = "Mulai mirror otomatis saat iPhone dicolok" disabled: devices are reported but not captured until `connectAvailable()`.
    var autoConnect = true
    var audioEnabled = false { didSet { if oldValue != audioEnabled { configureAudio() } } }
    var volume: Float = 1 { didSet { audioOutput?.volume = volume } }

    init(pipeline: DisplayPipeline) {
        self.pipeline = pipeline
        forwarder = FrameForwarder(pipeline: pipeline)
    }

    /// Any iPhone that is plugged in, trusted and visible to AVFoundation.
    var availableDevice: AVCaptureDevice? { discovery.devices.first { $0.isConnected && !$0.isSuspended } }

    func start() {
        Self.allowScreenCaptureDevices()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.retry() }
        })
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] note in
            let goneID = (note.object as? AVCaptureDevice)?.uniqueID
            MainActor.assumeIsolated { self?.deviceDisconnected(goneID) }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: nil, queue: .main) { [weak self] note in
            let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "Capture error"
            let failedSession = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.sessionFailed(failedSession, message: message) }
        })
        scan()
        // Screen-capture devices appear 1–3 s after enabling CoreMediaIO, sometimes without a notification.
        for delay in [1.0, 2.5, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scan() }
        }
    }

    func scan() {
        guard device == nil, failures < 3, let candidate = availableDevice else { return }
        if autoConnect { connect(candidate) }
    }

    func connectAvailable() {
        failures = 0
        guard device == nil, let candidate = availableDevice else { return }
        connect(candidate)
    }

    /// Replug or user "Coba lagi": start over with a clean failure count.
    func retry() {
        failures = 0
        scan()
    }

    /// Frames are flowing again.
    func recovered() { failures = 0 }

    private func connect(_ candidate: AVCaptureDevice) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard !requestingAccess else { return } // scan() runs every second while waiting
            requestingAccess = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor in
                    self?.requestingAccess = false
                    self?.scan()
                }
            }
            return
        default:
            onProblem?(.cameraDenied)
            return
        }

        device = candidate
        onDeviceAppeared?(candidate)
        let session = AVCaptureSession()
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: candidate)
            guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            device = nil
            failures += 1
            onProblem?(.captureFailed(error.localizedDescription))
            onDeviceLost?()
            return
        }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [:] // macOS: empty = device-native format, no conversion
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(forwarder, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        self.session = session
        configureAudio()
        if failures == 0 { onProblem?(nil) } // after a failure, the message stays until frames flow again
        let box = UncheckedBox(session)
        queue.async { box.value.startRunning() }
    }

    private func deviceDisconnected(_ goneID: String?) {
        guard let current = device, goneID == nil || goneID == current.uniqueID else { return }
        teardown()
        onDeviceLost?()
        scan()
    }

    /// Only errors of *our current* session count; a late error from a torn-down one must not kill the new one.
    private func sessionFailed(_ failed: ObjectIdentifier?, message: String) {
        guard let session, failed == ObjectIdentifier(session) else { return }
        failures += 1
        onProblem?(.captureFailed(message))
        teardown()
        onDeviceLost?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.scan() } // backoff
    }

    func teardown() {
        let pipeline = self.pipeline
        if let session {
            let box = UncheckedBox(session)
            // After stopRunning on the capture queue: no frame of this session can be delivered afterwards.
            queue.async {
                box.value.stopRunning()
                pipeline.sessionEnded(.usb)
            }
        } else {
            pipeline.sessionEnded(.usb)
        }
        session = nil
        audioOutput = nil
        device = nil
    }

    private func configureAudio() {
        guard let session else { return }
        session.beginConfiguration()
        if let audioOutput { session.removeOutput(audioOutput) }
        audioOutput = nil
        if audioEnabled {
            let out = AVCaptureAudioPreviewOutput()
            out.volume = volume
            if session.canAddOutput(out) {
                session.addOutput(out)
                audioOutput = out
            }
        }
        session.commitConfiguration()
    }

    /// Makes iOS devices show up as capture devices (off by default on macOS).
    private static func allowScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
                                  UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    /// True when an iPhone/iPad is on the USB bus, even if it is locked or not trusted yet (D2 checklist).
    nonisolated static func iPhoneOnUSB() -> Bool {
        guard let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary? else { return false }
        matching["idVendor"] = 0x05AC
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(service, &name)
            let s = cString(name)
            if s.contains("iPhone") || s.contains("iPad") { return true }
        }
        return false
    }
}

private final class FrameForwarder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let pipeline: DisplayPipeline
    init(pipeline: DisplayPipeline) { self.pipeline = pipeline }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        pipeline.push(sampleBuffer, from: .usb)
    }
}

/// For handing AVFoundation objects to their own serial queue.
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// NUL-terminated C buffer → String.
func cString(_ buffer: [CChar]) -> String {
    String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
