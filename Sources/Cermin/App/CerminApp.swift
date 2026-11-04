import AppKit
import CerminCore
import SwiftUI

@main
struct CerminApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.curtain ? "iphone.slash" : "iphone")
                .accessibilityLabel(model.curtain ? "Cermin, layar disembunyikan" : "Cermin")
        }
        Settings {
            SettingsView(model: model)
        }
        .commands { MirrorCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Snapshots.runIfRequested() { exit(0) }
        #endif
        // kill/Ctrl-C/logout: quit through NSApp so UxPlay is stopped instead of left advertising "Cermin".
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        AppModel.shared.start()
    }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showWindow()
        return true
    }
}

/// D7: menu bar menu.
struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(model.phase.deviceName ?? "Belum ada iPhone")
        Text(statusLine)
        Divider()
        Button(model.windowVisible ? "Sembunyikan Jendela" : "Tampilkan Jendela") { model.toggleWindow() }
            .keyboardShortcut("m", modifiers: [.option, .command])
        Toggle("Selalu di Atas", isOn: Binding(get: { model.pinned }, set: { _ in model.togglePinned() }))
            .keyboardShortcut("t")
        curtainToggle
        Button("Ambil Screenshot") { model.screenshot() }
            .keyboardShortcut("s")
            .disabled(model.curtain || !model.phase.isMirroring)
        Divider()
        Picker("Sumber", selection: Binding(get: { model.source }, set: { newSource in
            if newSource == .wireless, !model.wirelessEnabled { model.wirelessEnabled = true }
            model.setSource(newSource)
        })) {
            Text("USB").tag(SourceKind.usb)
            Text("Wireless (AirPlay)").tag(SourceKind.wireless)
        }
        SettingsLink { Text("Pengaturan…") }
            .keyboardShortcut(",")
        Divider()
        Button("Keluar dari Cermin") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var curtainToggle: some View {
        let toggle = Toggle("Privacy Curtain", isOn: Binding(get: { model.curtain }, set: { _ in model.toggleCurtain() }))
        if let shortcut = model.curtainHotKey.keyboardShortcut { toggle.keyboardShortcut(shortcut) } else { toggle }
    }

    private var statusLine: String {
        switch model.phase {
        case .waiting: model.source == .usb ? "Menunggu iPhone · USB" : "Siap menerima · AirPlay"
        case .connecting: "Menyambungkan…"
        case .mirroring: model.curtain ? "Mirroring · layar disembunyikan" : "Mirroring · \(model.source == .usb ? "USB" : "AirPlay")"
        case .disconnected: "Terputus"
        }
    }
}

/// Main-menu shortcuts while the mirror window is focused.
struct MirrorCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .appInfo) {
            Button("Tentang Cermin") { About.showPanel() }
        }
        CommandMenu("Mirror") {
            Button(model.pinned ? "Lepas dari Atas" : "Selalu di Atas") { model.togglePinned() }
                .keyboardShortcut("t")
            // No key equivalent here: the global hotkey already handles it and would toggle twice.
            Button(model.curtain ? "Tampilkan Layar (\(model.curtainHotKeyDisplay))" : "Privacy Curtain (\(model.curtainHotKeyDisplay))") {
                model.toggleCurtain()
            }
            Button("Ambil Screenshot") { model.screenshot() }
                .keyboardShortcut("s")
            Divider()
            ForEach(Array(SizePreset.allCases.enumerated()), id: \.element) { index, preset in
                Button("Ukuran \(preset.label)") { model.apply(preset) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Button(model.windowVisible ? "Sembunyikan Jendela" : "Tampilkan Jendela") { model.toggleWindow() }
                .keyboardShortcut("m", modifiers: [.option, .command])
        }
    }
}

extension HotKeyCombo {
    /// The same combo as a SwiftUI shortcut, so menus show it. nil for keys SwiftUI cannot express.
    var keyboardShortcut: KeyboardShortcut? {
        guard let label = keyLabel, label.count == 1, let key = label.first else { return nil }
        var mods: EventModifiers = []
        if modifiers & Self.cmd != 0 { mods.insert(.command) }
        if modifiers & Self.shift != 0 { mods.insert(.shift) }
        if modifiers & Self.option != 0 { mods.insert(.option) }
        if modifiers & Self.control != 0 { mods.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(Character(key.lowercased())), modifiers: mods)
    }
}
