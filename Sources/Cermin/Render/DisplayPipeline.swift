import AVFoundation
import CoreImage

enum SourceKind: String, Sendable, CaseIterable {
    case usb, wireless

    var label: String { self == .usb ? "USB" : "Wi-Fi" }
}

/// The single renderer both sources feed (PRD §2.1). Thread-safe: sources push from their own queues.
final class DisplayPipeline: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()
    /// Grabbed once on the main actor; AVSampleBufferVideoRenderer itself is meant to be fed from any queue.
    private let renderer: AVSampleBufferVideoRenderer

    private let lock = NSLock()
    private var active: SourceKind = .usb
    private var curtain = false
    private var wirelessGated = true // fail closed: opened only by approve / always-allowed device
    private var latest: CVPixelBuffer?
    private var lastImage: [SourceKind: CVPixelBuffer] = [:] // kept while hidden so un-hiding repaints instantly
    private var sizes: [SourceKind: CGSize] = [:]
    private var started: Set<SourceKind> = []
    private var frames = 0

    /// Set once at startup, before any source runs.
    var onFirstFrame: (@MainActor (SourceKind) -> Void)?
    var onSizeChange: (@MainActor (SourceKind, CGSize) -> Void)?

    @MainActor init() {
        renderer = layer.sampleBufferRenderer
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    /// `sampleBuffer` must carry a decoded image buffer.
    func push(_ sampleBuffer: CMSampleBuffer, from source: SourceKind) {
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image))

        lock.lock()
        let isFirst = started.insert(source).inserted
        let sizeChanged = sizes[source] != size
        sizes[source] = size
        lastImage[source] = image
        let show = source == active && isVisible
        if show {
            latest = image
            frames += 1
            Self.markDisplayImmediately(sampleBuffer)
            if renderer.status == .failed || renderer.requiresFlushToResumeDecoding { renderer.flush() }
            renderer.enqueue(sampleBuffer) // inside the lock so a curtain flush can never be overtaken
        }
        lock.unlock()

        if sizeChanged, let cb = onSizeChange { Task { @MainActor in cb(source, size) } }
        if isFirst, let cb = onFirstFrame { Task { @MainActor in cb(source) } }
    }

    func setActive(_ source: SourceKind) { update { active = source } }
    func setCurtain(_ on: Bool) { update { curtain = on } }
    func setWirelessGated(_ on: Bool) { update { wirelessGated = on } }

    /// Next frame from `source` is reported as a "first frame" again (new session).
    func sessionEnded(_ source: SourceKind) {
        lock.lock()
        started.remove(source)
        lastImage[source] = nil
        let wasActive = source == active
        lock.unlock()
        if wasActive { update {} }
    }

    func size(of source: SourceKind) -> CGSize? {
        lock.lock(); defer { lock.unlock() }
        return sizes[source]
    }

    /// Latest visible frame, nil while hidden by the curtain or the approval prompt.
    func latestFrame() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func takeFrameCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        let n = frames
        frames = 0
        return n
    }

    private var isVisible: Bool { !curtain && !(active == .wireless && wirelessGated) }

    /// Any visibility change wipes the screen, then repaints the active source's last frame if it may be shown.
    /// (iOS only sends frames when the screen changes, so waiting for the next one could leave it black.)
    private func update(_ change: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change()
        latest = nil
        renderer.flush(removingDisplayedImage: true, completionHandler: nil)
        guard isVisible, let image = lastImage[active], let sb = makeSampleBuffer(from: image) else { return }
        latest = image
        Self.markDisplayImmediately(sb)
        renderer.enqueue(sb)
    }

    private static func markDisplayImmediately(_ sb: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dict,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
}

/// Wraps a decoded frame (from VideoToolbox) so it can go through `DisplayPipeline.push`.
func makeSampleBuffer(from image: CVImageBuffer) -> CMSampleBuffer? {
    var format: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &format) == noErr,
          let format else { return nil }
    var timing = CMSampleTimingInfo(duration: .invalid,
                                    presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                    decodeTimeStamp: .invalid)
    var sb: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image, formatDescription: format,
                                             sampleTiming: &timing, sampleBufferOut: &sb)
    return sb
}
