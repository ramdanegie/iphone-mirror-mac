import AppKit
import Carbon.HIToolbox
import CerminCore
import CoreImage
import CoreWLAN

/// System-wide hotkey via Carbon — works while Zoom/browser is focused and needs no Accessibility permission (PRD §F3).
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (@MainActor () -> Void)?

    @discardableResult
    func register(_ combo: HotKeyCombo, action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        Self.action = action
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.action?() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x434D_524E), id: 1) // 'CMRN'
        return RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

enum Screenshot {
    /// Saves the frame at the iPhone's native resolution as PNG (PRD §F4).
    static func save(_ image: CVPixelBuffer, to folder: URL, copyToClipboard: Bool) throws -> URL {
        let ci = CIImage(cvPixelBuffer: image)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = ScreenshotNaming.uniqueURL(in: folder, fileName: ScreenshotNaming.fileName(for: Date())) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        try png.write(to: url, options: .atomic)
        if copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
        }
        return url
    }
}

/// Facts for the "Cermin tidak muncul di iPhone?" panel (D14).
enum Diagnostics {
    enum Pane: String {
        case airDropHandoff = "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension"
        case firewall = "x-apple.systempreferences:com.apple.preference.security?Firewall"
        case localNetwork = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
        case camera = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case microphone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: pane.rawValue) { NSWorkspace.shared.open(url) }
    }

    /// nil when macOS hides the SSID (needs Location permission since macOS 14).
    static func wifiName() -> String? { CWWiFiClient.shared().interface()?.ssid() }

    /// IPv4 of the Wi-Fi/Ethernet interface the iPhone has to share.
    static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var found: [String: String] = [:]
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  ifa.ifa_flags & UInt32(IFF_UP) != 0, ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            found[String(cString: ifa.ifa_name, encoding: .utf8) ?? ""] = cString(host)
        }
        return found["en0"] ?? found["en1"] ?? found.sorted { $0.key < $1.key }.first { $0.key.hasPrefix("en") || $0.key.hasPrefix("bridge") }?.value
    }

    /// The built-in AirPlay Receiver (on by default since macOS 12) shows up next to "Cermin" and goes fullscreen.
    static func airPlayReceiverEnabled() -> Bool {
        let value = CFPreferencesCopyValue("AirplayReceiverEnabled" as CFString, "com.apple.controlcenter" as CFString,
                                           kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return (value as? Bool) ?? true
    }

    static func firewallEnabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
        p.arguments = ["--getglobalstate"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return out.contains("enabled")
    }
}
