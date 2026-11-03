#if DEBUG
import AppKit
import CerminCore
import SwiftUI

/// Renders every screen offscreen to PNG, light + dark, so the UI can be checked without Screen Recording permission.
@MainActor
enum Snapshots {
    /// Keeps snapshot runs from launching UxPlay.
    static var active = false

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        active = true
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = AppModel.shared
        let window = CGSize(width: 300, height: 650)
        let mirror = { MirrorOverlay(model: m).background(Color.black) }

        let cases: [(String, CGSize, () -> Void, () -> AnyView)] = [
            ("D2-waiting", window, { m.debugState() }, { AnyView(mirror()) }),
            ("D2-cable", window, { m.debugState(usb: .waiting(cableDetected: true)) }, { AnyView(mirror()) }),
            ("D2-camera-denied", window, { m.debugState(problem: .cameraDenied) }, { AnyView(mirror()) }),
            ("D3-connecting", window, { m.debugState(usb: .connecting(deviceName: "iPhone Egie")) }, { AnyView(mirror()) }),
            ("D4-hover", window, { m.debugState(usb: .mirroring(deviceName: "iPhone Egie"), hovering: true) }, { AnyView(mirror()) }),
            ("D4-toolbar", CGSize(width: 56, height: 400), { m.debugState(usb: .mirroring(deviceName: "iPhone Egie")) }, { AnyView(MirrorToolbar(model: m).padding(8)) }),
            ("D5-curtain", window, { m.debugState(usb: .mirroring(deviceName: "iPhone Egie"), curtain: true) }, { AnyView(mirror()) }),
            ("D6-disconnected", window, { m.debugState(usb: .disconnected(deviceName: "iPhone Egie")) }, { AnyView(mirror()) }),
            ("D9-toast", window, { m.debugState(usb: .mirroring(deviceName: "iPhone Egie"), toast: "Screenshot tersimpan") }, { AnyView(mirror()) }),
            ("D10-ready", window, { m.wirelessEnabled = true; m.debugState(source: .wireless, wirelessStatus: .ready) }, { AnyView(mirror()) }),
            ("D10-not-installed", window, { m.debugState(source: .wireless, wirelessStatus: .notInstalled) }, { AnyView(mirror()) }),
            ("D11-hover-wireless", window, { m.debugState(wireless: .mirroring(deviceName: "iPhone Egie"), source: .wireless, hovering: true, wirelessStatus: .ready) }, { AnyView(mirror()) }),
            ("D12-pin", window, { m.debugState(wireless: .connecting(deviceName: "iPhone Egie"), source: .wireless, pin: "4719", wirelessStatus: .ready) }, { AnyView(mirror()) }),
            ("D13-prompt", window, { m.debugState(wireless: .connecting(deviceName: "iPhone Egie"), source: .wireless, request: ConnectionRequest(name: "iPhone Egie", deviceID: "AA"), wirelessStatus: .ready) }, { AnyView(mirror()) }),
            ("D14-diagnostics", CGSize(width: 340, height: 520), { m.debugState(source: .wireless, wirelessStatus: .ready) }, { AnyView(DiagnosticsView(model: m).background(Color.surface)) }),
            ("D1-step1", CGSize(width: 680, height: 440), { m.debugState() }, { AnyView(OnboardingView(model: m, step: 0)) }),
            ("D1-step2", CGSize(width: 680, height: 440), { m.debugState() }, { AnyView(OnboardingView(model: m, step: 1)) }),
            ("D1-step3", CGSize(width: 680, height: 440), { m.debugState() }, { AnyView(OnboardingView(model: m, step: 2)) }),
            ("D8-general", CGSize(width: 520, height: 380), { m.debugState() }, { AnyView(GeneralTab(model: m)) }),
            ("D8-shortcut", CGSize(width: 520, height: 380), { m.debugState() }, { AnyView(ShortcutTab(model: m)) }),
            ("D15-wireless", CGSize(width: 520, height: 560), { m.debugState(wirelessStatus: .ready) }, { AnyView(WirelessTab(model: m)) }),
        ]
        for (name, size, setup, view) in cases {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                setup()
                render(view(), size: size, appearance: appearance, to: dir.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
        print("snapshots written to \(dir.path)")
        return true
    }

    private static func render(_ view: AnyView, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderBack(nil) // must be in the window list for materials/controls to draw; stays behind everything
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}
#endif
