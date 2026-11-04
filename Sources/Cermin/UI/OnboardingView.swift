import AVFoundation
import SwiftUI

/// D1: three steps, art panel left, content right (680 × 440).
struct OnboardingView: View {
    let model: AppModel
    @ViewState private var step: Int
    init(model: AppModel, step: Int = 0) {
        self.model = model
        _step = ViewState(wrappedValue: step)
    }
    @ViewState private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        HStack(spacing: 0) {
            ReflectionArt { art }
                .frame(width: 250)
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: "%02d / 03", step + 1))
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
                content
                Spacer(minLength: 0)
                HStack {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule().fill(i == step ? Color.primary : Color.secondary.opacity(0.35))
                                .frame(width: i == step ? 14 : 4, height: 4)
                        }
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    if step > 0 {
                        Button("Kembali") { step -= 1 }.buttonStyle(PillButtonStyle(prominent: false))
                    }
                    primaryButton
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 680, height: 440)
        .background(Color.surface)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.2), value: step)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            title("Selamat datang", "di Cermin")
            Text("Tampilkan layar iPhone di jendela Mac untuk demo dan meeting.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                benefit("i", "iPhone tetap di tangan", "tidak terkunci")
                benefit("ii", "Mac tetap bebas", "tanpa fullscreen")
                benefit("iii", "Tanpa watermark", "gratis & offline")
            }
        case 1:
            title("Izinkan akses", "Kamera")
            VStack(alignment: .leading, spacing: 6) {
                Text("Kenapa butuh akses Kamera?").font(.system(size: 12, weight: .semibold))
                Text("macOS memperlakukan layar iPhone yang dicolok sebagai perangkat kamera. Cermin tidak memakai kamera Mac kamu.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(cameraStatus == .denied ? "Akses ditolak. Izinkan Cermin di Pengaturan Sistem → Privasi → Kamera."
                                         : "Tidak ada data yang dikirim ke internet.")
                .font(.system(size: 11)).foregroundStyle(cameraStatus == .denied ? .orange : .secondary)
        default:
            title("Sambungkan", "iPhone")
            VStack(alignment: .leading, spacing: 9) {
                NumberedStep(n: 1, text: Text("Colokkan kabel data"))
                NumberedStep(n: 2, text: Text("Ketuk “Percayai” di iPhone"))
                NumberedStep(n: 3, text: Text("Buka kunci iPhone"))
            }
            Divider()
            Text("Sebelum meeting, aktifkan Focus Mode di iPhone supaya notifikasi tidak ikut tampil.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case 0:
            Button("Lanjut") { step = 1 }.buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
        case 1:
            switch cameraStatus {
            case .notDetermined:
                Button("Izinkan Akses Kamera") {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        Task { @MainActor in
                            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                            step = 2
                        }
                    }
                }
                .buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
            case .denied, .restricted:
                Button("Buka Pengaturan") { Diagnostics.open(.camera) }.buttonStyle(PillButtonStyle())
                Button("Lanjut") { step = 2 }.buttonStyle(PillButtonStyle(prominent: false))
            default:
                Button("Lanjut") { step = 2 }.buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
            }
        default:
            Button("Mulai") { model.finishOnboarding() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var art: some View {
        switch step {
        case 0:
            HStack(spacing: 10) {
                PhoneGlyph(width: 46)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .frame(width: 46, height: 94)
            }
        case 1:
            ZStack {
                Rings(count: 3, spacing: 22)
                Circle().fill(.background).frame(width: 40, height: 40).shadow(color: .black.opacity(0.1), radius: 6)
                Circle().fill(Color.accentTeal).frame(width: 14, height: 14)
            }
            .frame(height: 140)
        default:
            PhoneGlyph(width: 46)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Color.accentTeal, in: Circle())
                        .offset(x: 9, y: -9)
                }
        }
    }

    private func title(_ first: LocalizedStringKey, _ second: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(first).serif(32)
            Text(second).serif(32, italic: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func benefit(_ numeral: String, _ bold: LocalizedStringKey, _ rest: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(numeral).serif(12, italic: true).foregroundStyle(Color.accentTeal).frame(width: 18, alignment: .leading)
            (Text(bold).fontWeight(.semibold) + Text(verbatim: " — ").foregroundColor(.secondary) + Text(rest).foregroundColor(.secondary)).font(.system(size: 12))
        }
    }
}
