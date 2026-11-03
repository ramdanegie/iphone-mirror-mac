import AppKit
import SwiftUI

// MARK: - D10 ready to receive

struct WirelessReadyView: View {
    let model: AppModel
    @ViewState private var builtInReceiverOn = false
    @ViewState private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SourcePicker(model: model).glassCapsule().frame(maxWidth: .infinity)
            switch model.wirelessStatus {
            case .ready: ready
            case .notInstalled: notInstalled
            case .failed(let message): failed(message)
            case .off: off
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 44)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surface)
        .task {
            while !Task.isCancelled {
                builtInReceiverOn = Diagnostics.airPlayReceiverEnabled()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var wifiLabel: String { model.wifiName ?? "Wi-Fi yang sama dengan Mac" }

    @ViewBuilder private var ready: some View {
        HStack(spacing: 8) {
            Circle().fill(.green).frame(width: 8, height: 8)
            Text("Siap menerima").serif(23)
        }
        Text("iPhone harus di Wi-Fi yang sama: \(wifiLabel).")
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 4) {
            InfoRow(label: "Wi-Fi", value: model.wifiName ?? "—")
            InfoRow(label: "IP", value: model.ipAddress ?? "tidak ada jaringan")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 9) {
            NumberedStep(n: 1, text: Text("Buka Control Center di iPhone"))
            NumberedStep(n: 2, text: Text("Ketuk **Screen Mirroring**"))
            NumberedStep(n: 3, text: Text("Pilih **\(model.receiverName)**"))
        }
        if builtInReceiverOn, !model.peerToPeer {
            VStack(alignment: .leading, spacing: 6) {
                Label("AirPlay Receiver bawaan masih aktif", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                Text("iPhone akan melihat dua tujuan; yang bawaan selalu fullscreen. Matikan di Pengaturan Sistem → Umum → AirDrop & Handoff.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Buka Pengaturan") { Diagnostics.open(.airDropHandoff) }.buttonStyle(PillButtonStyle(prominent: false))
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        Button("Cermin tidak muncul di iPhone? →") { showDiagnostics = true }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.accentTeal)
            .popover(isPresented: $showDiagnostics, arrowEdge: .bottom) { DiagnosticsView(model: model) }
    }

    @ViewBuilder private var notInstalled: some View {
        Image(systemName: "airplayvideo").font(.system(size: 28)).foregroundStyle(Color.accentTeal)
        Text("Komponen AirPlay belum terpasang").serif(20)
        Text("Wireless memakai UxPlay (open source). Pasang sekali lewat Terminal dari folder proyek Cermin:")
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        CopyableCommand(command: "./scripts/install-uxplay.sh")
        HStack {
            Button("Periksa lagi") { model.startWireless() }.buttonStyle(PillButtonStyle())
            Button("Pakai USB") { model.setSource(.usb) }.buttonStyle(PillButtonStyle(prominent: false))
        }
    }

    @ViewBuilder private func failed(_ message: String) -> some View {
        Label("AirPlay berhenti", systemImage: "exclamationmark.triangle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
        ScrollView {
            Text(message).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
        HStack {
            Button("Coba lagi") { model.startWireless() }.buttonStyle(PillButtonStyle())
            Button("Diagnosa") { showDiagnostics = true }.buttonStyle(PillButtonStyle(prominent: false))
                .popover(isPresented: $showDiagnostics) { DiagnosticsView(model: model) }
        }
    }

    @ViewBuilder private var off: some View {
        Image(systemName: "airplayvideo").font(.system(size: 28)).foregroundStyle(Color.accentTeal)
        Text("Wireless belum aktif").serif(20)
        Text("Aktifkan supaya iPhone bisa mirror lewat AirPlay tanpa kabel.").font(.system(size: 12)).foregroundStyle(.secondary)
        Button("Aktifkan Wireless") { model.wirelessEnabled = true }.buttonStyle(PillButtonStyle())
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}

struct NumberedStep: View {
    let n: Int
    let text: Text

    var body: some View {
        HStack(spacing: 9) {
            Text("\(n)").font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(.quaternary, in: Circle())
            text.font(.system(size: 12))
        }
    }
}

struct CopyableCommand: View {
    let command: String
    @ViewState private var copied = false

    var body: some View {
        HStack {
            Text(command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button(copied ? "Tersalin" : "Salin") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            }
            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentTeal)
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - D12 connection code

struct PinCodeView: View {
    let model: AppModel
    let code: String

    var body: some View {
        ZStack {
            Color.surface
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    Text("Masukkan kode ini").serif(22)
                    Text("di iPhone").serif(22, italic: true)
                }
                HStack(spacing: 8) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 40, weight: .regular, design: .serif))
                            .frame(width: 50, height: 64)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kode \(code.map(String.init).joined(separator: " "))")
                if let name = model.wirelessPhase.deviceName {
                    Text("\(name) meminta koneksi").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Button("Batal") { model.cancelPin() }.buttonStyle(PillButtonStyle(prominent: false))
            }
            .padding(20)
        }
    }
}

// MARK: - D13 allow / deny

struct ConnectionPromptView: View {
    let model: AppModel
    let request: ConnectionRequest
    @ViewState private var always = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 12) {
                Image(systemName: "iphone").font(.system(size: 22)).frame(width: 46, height: 46)
                    .background(.quaternary, in: Circle())
                Text("\(request.name) ingin mirror ke \(model.receiverName)")
                    .font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
                Text("Lewat Wi-Fi \(model.wifiName ?? "lokal")").font(.system(size: 12)).foregroundStyle(.secondary)
                Toggle("Selalu izinkan perangkat ini", isOn: $always).toggleStyle(.checkbox).font(.system(size: 12))
                HStack {
                    Button("Tolak") { model.deny() }.buttonStyle(PillButtonStyle(prominent: false))
                    Button("Izinkan") { model.approve(always: always) }.buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(maxWidth: 250)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(16)
        }
    }
}

// MARK: - D14 diagnostics

struct DiagnosticsView: View {
    let model: AppModel
    @ViewState private var firewallOn: Bool?
    @ViewState private var builtInReceiverOn = false
    @ViewState private var showHotspotTip = false

    private var installed: Bool { AirPlaySource.findBinary() != nil }
    private var problems: Int {
        (installed ? 0 : 1) + (firewallOn == true ? 1 : 0) + (builtInReceiverOn && !model.peerToPeer ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cermin tidak muncul di iPhone?").serif(19)
            Text("Beberapa Wi-Fi kantor memblokir AirPlay. Cara paling pasti: pakai kabel USB.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(problems == 0 ? "Tidak ada masalah terdeteksi" : "\(problems) masalah ditemukan")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).frame(height: 20)
                .background((problems == 0 ? Color.green : Color.orange).opacity(0.15), in: Capsule())

            VStack(spacing: 0) {
                CheckRow(ok: nil, title: "Wi-Fi sama?",
                         detail: "Mac di \(model.wifiName ?? "jaringan ini") (\(model.ipAddress ?? "—")), pastikan iPhone juga")
                CheckRow(ok: installed, title: "UxPlay terpasang",
                         detail: installed ? "Ditemukan" : "Jalankan ./scripts/install-uxplay.sh")
                CheckRow(ok: nil, title: "Izin Local Network",
                         detail: "macOS tidak memberi tahu statusnya; cek Cermin diizinkan", action: ("Periksa", { Diagnostics.open(.localNetwork) }))
                CheckRow(ok: firewallOn.map { !$0 }, title: "Firewall",
                         detail: firewallOn == true ? "Aktif; izinkan koneksi masuk untuk uxplay" : "Tidak memblokir",
                         action: firewallOn == true ? ("Buka Firewall", { Diagnostics.open(.firewall) }) : nil)
                CheckRow(ok: !(builtInReceiverOn && !model.peerToPeer), title: "AirPlay Receiver bawaan",
                         detail: builtInReceiverOn ? "Masih aktif; iPhone melihat dua tujuan" : "Mati",
                         action: builtInReceiverOn && !model.peerToPeer ? ("Matikan", { Diagnostics.open(.airDropHandoff) }) : nil)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            Text("MASIH TIDAK MUNCUL?").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            HStack {
                Button("Pakai kabel USB") { model.setSource(.usb) }.buttonStyle(PillButtonStyle(prominent: false))
                Button("Pakai Personal Hotspot") { showHotspotTip.toggle() }.buttonStyle(PillButtonStyle(prominent: false))
            }
            if showHotspotTip {
                Text("Nyalakan Personal Hotspot di iPhone, sambungkan Mac ke hotspot itu, lalu pilih Cermin di Screen Mirroring.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Periksa ulang") { Task { await refresh() } }.buttonStyle(PillButtonStyle())
        }
        .padding(16)
        .frame(width: 340)
        .task { await refresh() }
    }

    private func refresh() async {
        model.refreshNetwork()
        builtInReceiverOn = Diagnostics.airPlayReceiverEnabled()
        firewallOn = await Task.detached { Diagnostics.firewallEnabled() }.value
    }
}

private struct CheckRow: View {
    let ok: Bool?
    let title: String
    let detail: String
    var action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: ok == nil ? "info.circle" : ok! ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok == nil ? Color.secondary : ok! ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let action {
                Button(action.0, action: action.1).buttonStyle(PillButtonStyle(prominent: false))
            }
        }
        .padding(10)
    }
}
