import AppKit
import CerminCore
import SwiftUI

/// D8 + D15.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label("Umum", systemImage: "gearshape") }
            Form {
                Toggle("Sudut membulat mengikuti layar iPhone", isOn: $model.roundedCorners)
                Picker("Ukuran awal jendela", selection: $model.defaultPreset) {
                    ForEach(SizePreset.allCases) { Text($0.label).tag($0) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Tampilan", systemImage: "macwindow") }
            Form {
                Toggle("Putar audio iPhone di Mac", isOn: $model.audioEnabled)
                Slider(value: $model.volume, in: 0...1) { Text("Volume") }
                    .disabled(!model.audioEnabled)
                Text("Saat mirror lewat kabel, suara iPhone bisa pindah ke Mac. Matikan bila ingin suara tetap di iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            ShortcutTab(model: model).tabItem { Label("Shortcut", systemImage: "command") }
            WirelessTab(model: model).tabItem { Label("Wireless", systemImage: "airplayvideo") }
            AboutTab().tabItem { Label("Tentang", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 430)
        .tint(.accentTeal)
    }
}

struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Buka saat login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Selalu di atas secara default", isOn: $model.pinnedByDefault)
                Toggle("Mulai mirror otomatis saat iPhone dicolok", isOn: $model.autoStart)
            }
            Section {
                LabeledContent("Folder screenshot") {
                    HStack {
                        Text(model.screenshotFolder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Pilih…") { chooseFolder() }
                    }
                }
                Toggle("Salin screenshot ke clipboard", isOn: $model.copyScreenshot)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: (model.screenshotFolder as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            model.screenshotFolder = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

struct ShortcutTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HotKeyRecorder(combo: $model.curtainHotKey)
                } label: {
                    Text("Privacy Curtain ") + Text("· global").foregroundColor(.secondary)
                }
                LabeledContent("Ambil screenshot") { KeyCap(text: "⌘S") }
                LabeledContent("Selalu di atas") { KeyCap(text: "⌘T") }
                LabeledContent("Ukuran 50% / 75% / 100% / Fit") { KeyCap(text: "⌘1 – ⌘4") }
                LabeledContent("Sembunyikan / tampilkan jendela") { KeyCap(text: "⌥⌘M") }
            } footer: {
                Text("Klik kolom lalu tekan kombinasi baru. Shortcut global tetap bekerja saat Zoom atau browser sedang fokus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Click, then press a new combination (needs ⌘, ⌃ or ⌥). Esc cancels.
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo
    @ViewState private var recording = false
    @ViewState private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Tekan kombinasi…" : combo.display)
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 90)
                .padding(.horizontal, 10).frame(height: 24)
                .overlay(Capsule().strokeBorder(recording ? Color.accentTeal : Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shortcut Privacy Curtain: \(combo.display)")
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc
            let flags = event.modifierFlags
            var mods: UInt32 = 0
            if flags.contains(.command) { mods |= HotKeyCombo.cmd }
            if flags.contains(.shift) { mods |= HotKeyCombo.shift }
            if flags.contains(.option) { mods |= HotKeyCombo.option }
            if flags.contains(.control) { mods |= HotKeyCombo.control }
            let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            if candidate.isValidGlobal {
                combo = candidate
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

struct WirelessTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Aktifkan wireless (AirPlay)", isOn: $model.wirelessEnabled)
                LabeledContent("Status") { Text(status).foregroundStyle(.secondary) }
                TextField("Nama receiver", text: $model.receiverName)
            }
            Section("Kode koneksi") {
                Picker("Kode koneksi", selection: $model.codeMode) {
                    Text("Kode baru tiap koneksi").tag(CodeMode.newCodeEachTime)
                    Text("Password tetap").tag(CodeMode.fixedPassword)
                    Text("Tanpa kode · tidak disarankan").tag(CodeMode.none)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if model.codeMode == .fixedPassword {
                    SecureField("Password (min. 6 karakter)", text: $model.fixedPassword)
                    if model.fixedPassword.count < 6 {
                        Text("Password minimal 6 karakter. Selama belum valid, Cermin memakai kode baru tiap koneksi.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Toggle("Utamakan USB bila keduanya tersedia", isOn: $model.preferUSB)
                Toggle(isOn: $model.peerToPeer) {
                    Text("Mode langsung (P2P) ") + Text("EKSPERIMENTAL").font(.caption2.weight(.semibold)).foregroundColor(.orange)
                }
                if model.peerToPeer {
                    Text("Tanpa Wi-Fi yang sama, lewat AWDL. Butuh AirPlay Receiver bawaan tetap aktif dan UxPlay yang dibangun dengan dukungan P2P.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Perangkat Tepercaya") {
                if model.trustedDevices.isEmpty {
                    Text("Belum ada. iPhone yang berhasil memasukkan kode akan tercatat di sini.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.trustedDevices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("terakhir \(device.lastSeen)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Hapus") { model.removeTrusted(device) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.reloadTrusted() }
    }

    private var status: String {
        switch model.wirelessStatus {
        case .off: "Mati"
        case .ready: "Siap menerima"
        case .notInstalled: "UxPlay belum terpasang (lihat jendela Wireless)"
        case .failed: "Berhenti, lihat jendela Cermin"
        }
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Cermin").serif(26)
            Text("Versi \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.caption).foregroundStyle(.secondary)
            Text("Mirror iPhone ke Mac. Tanpa watermark, gratis & offline.")
                .font(.system(size: 12))
            Text("Dibuat oleh \(About.author)").font(.system(size: 12, weight: .medium)).padding(.top, 6)
            HStack(spacing: 16) {
                Link(destination: About.profile) { Label("github.com/ramdanegie", systemImage: "person.crop.circle") }
                Link(destination: About.repository) { Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
            .font(.caption)
            Text("Wireless memakai UxPlay (GPL-3.0), dijalankan sebagai program terpisah.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Who made Cermin, shown in Settings → Tentang and the standard About panel.
enum About {
    static let author = "Egie Ramdan"
    static let profile = URL(string: "https://github.com/ramdanegie")!
    static let repository = URL(string: "https://github.com/ramdanegie/iphone-mirror-mac")!

    /// The app menu's About panel, with the author and links as credits.
    @MainActor static func showPanel() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: center]
        let credits = NSMutableAttributedString(string: "Dibuat oleh \(author)\n", attributes: base)
        credits.append(NSAttributedString(string: "github.com/ramdanegie", attributes: base.merging([.link: profile]) { $1 }))
        credits.append(NSAttributedString(string: "  ·  ", attributes: base))
        credits.append(NSAttributedString(string: "Source code", attributes: base.merging([.link: repository]) { $1 }))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}
