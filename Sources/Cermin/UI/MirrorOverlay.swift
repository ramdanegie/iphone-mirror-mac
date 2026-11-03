import CerminCore
import SwiftUI

/// Everything drawn on top of the video layer inside the mirror window (D2–D6, D9–D13). The toolbar lives outside, see `MirrorToolbar`.
struct MirrorOverlay: View {
    let model: AppModel

    var body: some View {
        ZStack {
            WindowDragArea()
            content
            VStack(spacing: 8) {
                if let toast = model.toast { StatusCapsule(text: toast, dot: false).transition(.opacity) }
                if model.statusPillVisible {
                    StatusCapsule(text: "\(model.source == .usb ? "USB" : "Wireless") · \(model.fps) fps", dot: true)
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity, alignment: .bottom)
            if model.source == .wireless, !model.curtain {
                if let code = model.pinCode, model.pendingRequest == nil { PinCodeView(model: model, code: code) }
                if let request = model.pendingRequest { ConnectionPromptView(model: model, request: request) }
            }
        }
        .ignoresSafeArea() // draw under the transparent titlebar; layout pads for the traffic lights itself
        .animation(.easeOut(duration: 0.15), value: model.hovering)
        .animation(.easeOut(duration: 0.15), value: model.toast)
        .onHover { model.setHovering($0) }
    }

    @ViewBuilder private var content: some View {
        if model.curtain {
            CurtainView(hotKey: model.curtainHotKeyDisplay) // swapped instantly: no transition (PRD §F3 ≤100 ms)
        } else {
            switch model.phase {
            case .waiting:
                if model.source == .usb { USBWaitingView(model: model) } else { WirelessReadyView(model: model) }
            case .connecting(let name):
                ConnectingView(name: name, via: model.source == .usb ? "USB" : "AirPlay")
            case .mirroring:
                Color.clear
            case .disconnected(let name):
                DisconnectedView(name: name)
            }
        }
    }
}

// MARK: - D4 toolbar

/// Vertical toolbar in its own panel beside the mirror window, so it never covers the iPhone screen.
struct MirrorToolbar: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 2) {
            pin; shot; curtain; audio
            divider
            sizeMenu
            divider
            ForEach(SourceKind.allCases, id: \.self) { source($0) }
            divider
            settings
        }
        .padding(.vertical, 5)
        .frame(width: 40)
        .glassCapsule()
    }

    private var divider: some View { Divider().frame(width: 18).padding(.vertical, 3) }

    private var pin: some View {
        ToolbarIcon(symbol: model.pinned ? "pin.fill" : "pin", active: model.pinned,
                    help: model.pinned ? "Lepas dari atas (⌘T)" : "Selalu di atas (⌘T)") { model.togglePinned() }
    }

    private var shot: some View {
        ToolbarIcon(symbol: "camera.viewfinder", help: "Ambil screenshot (⌘S)") { model.screenshot() }
            .disabled(model.curtain)
    }

    private var curtain: some View {
        ToolbarIcon(symbol: "eye.slash", active: model.curtain,
                    help: "Privacy Curtain (\(model.curtainHotKeyDisplay))") { model.toggleCurtain() }
    }

    private var audio: some View {
        ToolbarIcon(symbol: model.audioEnabled ? "speaker.wave.2" : "speaker.slash",
                    help: model.audioEnabled ? "Matikan audio iPhone" : "Putar audio iPhone di Mac") {
            model.audioEnabled.toggle()
        }
    }

    private var sizeMenu: some View {
        Menu {
            ForEach(SizePreset.allCases) { preset in
                Button(preset.label) { model.apply(preset) }
            }
        } label: {
            Text(model.preset.label).font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(height: 30)
        .help("Ukuran jendela (⌘1–⌘4)")
    }

    /// D11 as two icons: the toolbar is too narrow for the segmented picker.
    private func source(_ kind: SourceKind) -> some View {
        ToolbarIcon(symbol: kind == .usb ? "cable.connector" : "wifi", active: model.source == kind,
                    help: "Sumber: \(kind.label)") {
            if kind == .wireless, !model.wirelessEnabled { model.wirelessEnabled = true }
            model.setSource(kind)
        }
    }

    private var settings: some View {
        SettingsLink {
            Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 30, height: 30).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Pengaturan (⌘,)")
        .accessibilityLabel("Pengaturan")
    }
}

struct ToolbarIcon: View {
    let symbol: String
    var active = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(active ? Color.accentTeal : Color.primary)
                .frame(width: 30, height: 30)
                .background(active ? Color.accentTeal.opacity(0.15) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// D11: USB / Wi-Fi segmented control.
struct SourcePicker: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SourceKind.allCases, id: \.self) { kind in
                Button {
                    if kind == .wireless, !model.wirelessEnabled { model.wirelessEnabled = true }
                    model.setSource(kind)
                } label: {
                    Text(kind.label)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .foregroundStyle(model.source == kind ? Color.primary : Color.secondary)
                        .background(model.source == kind ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.source == kind ? .isSelected : [])
            }
        }
        .padding(3)
    }
}

/// D4 pill and D9 toast.
struct StatusCapsule: View {
    let text: String
    let dot: Bool

    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(Color.accentTeal).frame(width: 6, height: 6) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .glassCapsule()
    }
}

// MARK: - D2 waiting for USB

struct USBWaitingView: View {
    let model: AppModel
    @ViewState private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.wirelessEnabled { SourcePicker(model: model).glassCapsule().frame(maxWidth: .infinity) }
            ReflectionArt { CablePhone() }
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Colokkan iPhone kamu").serif(23)
            (Text("Pakai kabel data. Buka kunci iPhone dan ketuk ") + Text("Percayai").italic() + Text(" bila diminta."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            problemOrChecklist
            Spacer(minLength: 0)
            Button("Tidak terdeteksi?") { showHelp = true }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.accentTeal)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showHelp, arrowEdge: .top) { USBHelp(model: model) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 48)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surface)
    }

    @ViewBuilder private var problemOrChecklist: some View {
        switch model.usbProblem {
        case .cameraDenied?:
            VStack(alignment: .leading, spacing: 8) {
                Label("Akses Kamera ditolak", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                Text("macOS menganggap layar iPhone sebagai kamera. Izinkan Cermin di Pengaturan Sistem → Privasi → Kamera.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Buka Pengaturan Kamera") { model.retryCamera() }.buttonStyle(PillButtonStyle())
            }
        case .captureFailed(let message)?:
            VStack(alignment: .leading, spacing: 8) {
                Label("Gagal menampilkan layar", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Coba lagi") { model.retryCamera() }.buttonStyle(PillButtonStyle())
            }
        case nil:
            if model.usbDeviceWaiting {
                Button("Mulai Mirror") { model.startUSBNow() }.buttonStyle(PillButtonStyle())
            } else {
                let cable = { if case .waiting(let c) = model.usbPhase { return c } else { return false } }()
                VStack(alignment: .leading, spacing: 9) {
                    ChecklistRow(text: "Kabel terdeteksi", state: cable ? .done : .active)
                    ChecklistRow(text: "Buka kunci iPhone", state: cable ? .active : .pending)
                    ChecklistRow(text: "Ketuk “Percayai”", state: .pending)
                }
            }
        }
    }
}

struct ChecklistRow: View {
    enum State { case done, active, pending }
    let text: String
    let state: State

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(Color.accentTeal)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                case .active:
                    ProgressView().controlSize(.mini)
                case .pending:
                    Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .frame(width: 16, height: 16)
            Text(text)
                .font(.system(size: 12, weight: state == .active ? .semibold : .regular))
                .strikethrough(state == .done)
                .foregroundStyle(state == .pending ? .secondary : state == .done ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .done ? "selesai" : state == .active ? "sedang menunggu" : "belum")
    }
}

private struct CablePhone: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PhoneGlyph(width: 52)
            Path { p in
                p.move(to: CGPoint(x: 26, y: 106))
                p.addCurve(to: CGPoint(x: 70, y: 118), control1: CGPoint(x: 26, y: 120), control2: CGPoint(x: 40, y: 118))
                p.addLine(to: CGPoint(x: 120, y: 118))
            }
            .stroke(Color.accentTeal, lineWidth: 2)
            .frame(width: 130, height: 120, alignment: .topLeading)
            .offset(x: 104, y: 6)
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentTeal).frame(width: 10, height: 8).offset(x: 104, y: 2)
            }
        }
        .frame(width: 52, height: 107)
        .padding(.bottom, 1)
    }
}

private struct USBHelp: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iPhone tidak terdeteksi?").font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("• Pakai kabel **data**, bukan kabel charge saja.")
                Text("• Buka kunci iPhone, lalu ketuk **Percayai** dan masukkan passcode.")
                Text("• Cabut lalu colok lagi kabelnya.")
                Text("• Pastikan Cermin diizinkan di Pengaturan Sistem → Privasi → Kamera.")
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Button("Pakai Wireless (AirPlay)") {
                model.wirelessEnabled = true
                model.setSource(.wireless)
            }
            .buttonStyle(PillButtonStyle(prominent: false))
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: - D3 / D5 / D6

struct ConnectingView: View {
    let name: String
    let via: String

    var body: some View {
        ZStack {
            ReflectionArt(horizon: 0.55) {
                ZStack {
                    Circle().fill(Color.orbTeal.opacity(0.5)).frame(width: 130).blur(radius: 24)
                    Rings(count: 2, spacing: 36)
                    PhoneGlyph(width: 56)
                }
                .frame(height: 190)
            }
            VStack(spacing: 4) {
                Text("Menyambungkan…").serif(20)
                Text("\(name) · \(via)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 56)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CurtainView: View {
    let hotKey: String

    var body: some View {
        ZStack {
            Color.surface
            Rings(count: 7, spacing: 30, color: .primary, opacity: 0.08)
            VStack(spacing: 14) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 22))
                    .frame(width: 58, height: 58)
                    .background(.background, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                Text("Layar disembunyikan\nsementara").serif(22).multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    KeyCap(text: hotKey)
                    Text("untuk menampilkan").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Text("Cermin").serif(12, italic: true).foregroundStyle(.tertiary)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Layar disembunyikan sementara")
    }
}

struct DisconnectedView: View {
    let name: String

    var body: some View {
        ZStack {
            Color.surface
            VStack(spacing: 10) {
                Image(systemName: "iphone.slash").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("\(name) terputus.").serif(20).multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Menunggu tersambung kembali…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }
}
