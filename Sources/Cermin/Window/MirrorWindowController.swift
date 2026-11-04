import AppKit
import CerminCore
import SwiftUI

/// The presentation window (PRD §F2): never fullscreen, aspect-locked, optional always-on-top, rounded like the iPhone.
@MainActor
final class MirrorWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    /// D4 toolbar: a child panel beside the window, never on top of the iPhone screen. As a separate window it also
    /// stays out of a meeting's "share window" capture.
    private let toolbar: NSPanel
    private unowned let model: AppModel
    private let container = NSView()
    private var pixelSize = WindowSizing.defaultPixelSize
    private var deviceKey = "default"

    init(model: AppModel) {
        self.model = model
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = WindowSizing.contentSize(preset: model.preset, pixelSize: pixelSize, visible: visible.size)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        let host = FirstClickHostingView(rootView: MirrorToolbar(model: model).padding(8)) // padding: room for the shadow
        toolbar = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        toolbar.contentView = host
        toolbar.isOpaque = false
        toolbar.backgroundColor = .clear
        toolbar.hasShadow = false
        toolbar.hidesOnDeactivate = false // NSPanel default would hide it while you click around in Zoom
        toolbar.isMovable = false
        toolbar.isReleasedWhenClosed = false
        super.init()

        window.delegate = self
        window.title = "Cermin"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone, .managed] // FR-5: the green button zooms, it never goes fullscreen
        // aspectRatio (frame), not contentAspectRatio: with fullSizeContentView the video covers the titlebar too.
        window.aspectRatio = size
        window.minSize = NSSize(width: 150, height: 150)

        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.cornerCurve = .continuous
        let video = VideoView(displayLayer: model.pipeline.layer)
        let overlay = NSHostingView(rootView: MirrorOverlay(model: model))
        overlay.sizingOptions = [] // SwiftUI must not fight the aspect-ratio lock
        for view in [video, overlay] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        window.contentView = container
        applyCorners()
        setTrafficLights(visible: false)

        // Default spot: right side of the screen, next to whatever is being presented.
        let restored = UserDefaults.standard.string(forKey: "frame.\(deviceKey)").map(NSRectFromString)
            .flatMap(Self.onScreen)
        window.setFrame(restored ?? NSRect(x: visible.maxX - size.width - 80, y: visible.midY - size.height / 2,
                                           width: size.width, height: size.height), display: false)
    }

    // MARK: Public

    func show() {
        window.makeKeyAndOrderFront(nil)
        attachToolbar()
        NSApp.activate()
    }

    func hide() {
        detachToolbar()
        window.orderOut(nil)
    }

    func setPinned(_ pinned: Bool) {
        window.level = pinned ? .floating : .normal
        toolbar.level = window.level
    }

    func setTrafficLights(visible: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.animator().alphaValue = visible ? 1 : 0
        }
    }

    func updateTitle() {
        window.title = model.phase.deviceName.map { "Cermin — \($0)" } ?? "Cermin"
    }

    /// FR-10: each device remembers where its window was.
    func useDevice(key: String, name: String) {
        deviceKey = key
        updateTitle()
        if let frame = UserDefaults.standard.string(forKey: "frame.\(key)").map(NSRectFromString).flatMap(Self.onScreen) {
            window.setFrame(frame, display: true)
        }
    }

    /// FR-3: rotation or a different iPhone → new aspect, long side kept.
    func applyPixelSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        pixelSize = size
        // Compare with the window as it is (it may have been restored in another orientation), not the last frame size.
        let current = window.frame.size
        guard abs(size.width / size.height - current.width / current.height) > 0.01 else { return }
        let target = WindowSizing.resized(current: window.frame.size, newPixelSize: size, visible: visibleSize)
        window.aspectRatio = size
        setContentSize(target, animate: true)
    }

    func applyPreset(_ preset: SizePreset) {
        setContentSize(WindowSizing.contentSize(preset: preset, pixelSize: pixelSize, visible: visibleSize), animate: true)
    }

    func applyCorners() {
        let radius = model.roundedCorners ? WindowSizing.cornerRadius(for: window.frame.size) : 10
        container.layer?.cornerRadius = radius
        window.invalidateShadow()
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        model.windowWasClosed()
        return false // closing only hides; the app stays in the menu bar
    }

    func windowDidResize(_ notification: Notification) {
        applyCorners()
        placeToolbar()
    }

    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
        placeToolbar() // may flip sides after a drag towards the screen edge
    }

    func windowWillMiniaturize(_ notification: Notification) { detachToolbar() }
    func windowDidDeminiaturize(_ notification: Notification) { attachToolbar() }

    /// Green button = "Fit" (largest size that fits), centered on the current position.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let size = WindowSizing.contentSize(preset: .fit, pixelSize: pixelSize, visible: visibleSize)
        return centered(size)
    }

    // MARK: Private

    private func attachToolbar() {
        toolbar.level = window.level
        window.addChildWindow(toolbar, ordered: .above) // moves with the window while it is dragged
        placeToolbar()
    }

    private func detachToolbar() {
        window.removeChildWindow(toolbar)
        toolbar.orderOut(nil)
    }

    /// Right of the window; left when the screen edge is too close. Vertically centered, kept on screen.
    private func placeToolbar() {
        let frame = window.frame, size = toolbar.frame.size
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? frame
        var x = frame.maxX
        if x + size.width > visible.maxX { x = max(frame.minX - size.width, visible.minX) }
        let y = min(max(frame.midY - size.height / 2, visible.minY), visible.maxY - size.height)
        toolbar.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Saved frames from a monitor that is no longer attached are ignored.
    private static func onScreen(_ frame: NSRect) -> NSRect? {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) } ? frame : nil
    }

    private var visibleSize: CGSize { (window.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900) }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "frame.\(deviceKey)")
    }

    private func setContentSize(_ size: CGSize, animate: Bool) {
        window.setFrame(centered(size), display: true, animate: animate)
        saveFrame()
    }

    private func centered(_ size: CGSize) -> NSRect {
        let current = window.frame
        var frame = NSRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2,
                           width: size.width, height: size.height)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        return frame
    }
}

/// Hosts the shared AVSampleBufferDisplayLayer.
final class VideoView: NSView {
    init(displayLayer: CALayer) {
        super.init(frame: .zero)
        layer = displayLayer // layer-hosting: set before wantsLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { true }
}

/// Toolbar clicks work on the first click, even while another app is active.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// SwiftUI background that lets the user drag the chromeless window from anywhere.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum OnboardingWindow {
    @MainActor static func make(model: AppModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = String(localized: "Selamat datang di Cermin")
        window.contentView = NSHostingView(rootView: OnboardingView(model: model))
        window.setFrame(NSRect(x: 0, y: 0, width: 680, height: 440), display: false) // frame, titlebar included
        window.delegate = OnboardingCloseHandler.shared
        return window
    }
}

/// Closing onboarding early counts as finishing it, otherwise the app would have no window at all.
@MainActor
final class OnboardingCloseHandler: NSObject, NSWindowDelegate {
    static let shared = OnboardingCloseHandler()

    func windowWillClose(_ notification: Notification) {
        if !AppModel.shared.onboarded { AppModel.shared.finishOnboarding() }
    }
}
