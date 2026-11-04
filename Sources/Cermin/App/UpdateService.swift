import AppKit
import CerminCore
import SwiftUI

/// Update check against GitHub Releases, and What's New from the CHANGELOG bundled in the app.
/// Cermin works offline: the network is only used when the user turns on daily checks or presses "Check now".
@MainActor @Observable
final class UpdateService {
    static let shared = UpdateService()
    static let api = URL(string: "https://api.github.com/repos/ramdanegie/iphone-mirror-mac/releases?per_page=20")!
    static let releasesPage = URL(string: "https://github.com/ramdanegie/iphone-mirror-mac/releases")!

    enum State: Equatable { case idle, checking, upToDate, available(ReleaseInfo), failed }
    var state: State = .idle

    private let d = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var autoCheck: Bool {
        get { d.bool(forKey: "update.auto") }
        set { d.set(newValue, forKey: "update.auto"); if newValue { checkIfDue() } }
    }

    func launched() {
        showWhatsNewIfUpdated()
        checkIfDue()
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { _ in MainActor.assumeIsolated { UpdateService.shared.checkIfDue() } }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func checkIfDue() {
        guard autoCheck, Updates.isDue(lastCheck: d.object(forKey: "update.lastCheck") as? Date, now: Date()) else { return }
        check(manual: false)
    }

    func check(manual: Bool) {
        guard state != .checking else { return }
        state = .checking
        var req = URLRequest(url: Self.api, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Cermin/\(current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { @Sendable data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let releases = ok ? data.flatMap { try? JSONDecoder().decode([ReleaseInfo].self, from: $0) } : nil
            Task { @MainActor in UpdateService.shared.finished(releases, manual: manual) }
        }.resume()
    }

    private func finished(_ releases: [ReleaseInfo]?, manual: Bool) {
        guard let releases else {
            state = .failed
            if manual { UpdateWindow.show() }
            return
        }
        d.set(Date(), forKey: "update.lastCheck")
        // "Check now" ignores a skipped version; the daily check respects it.
        let skipped = manual ? nil : d.string(forKey: "update.skip")
        guard let r = Updates.newest(releases, current: current, skipped: skipped, includePrerelease: false) else {
            state = .upToDate
            if manual { UpdateWindow.show() }
            return
        }
        state = .available(r)
        // The daily check opens the window once per new version, not every day.
        let v = r.version?.description ?? r.tag
        if manual || d.string(forKey: "update.announced") != v {
            d.set(v, forKey: "update.announced")
            UpdateWindow.show()
        }
    }

    func skip(_ r: ReleaseInfo) {
        d.set(r.version?.description ?? r.tag, forKey: "update.skip")
        state = .idle
    }

    // MARK: What's New

    func showWhatsNewIfUpdated() {
        let last = d.string(forKey: "update.lastSeenVersion")
        d.set(current, forKey: "update.lastSeenVersion")
        if Changelog.shouldShowWhatsNew(lastSeen: last, current: current), whatsNew() != nil { WhatsNewWindow.show() }
    }

    /// This version's section of the bundled CHANGELOG, in the app's language.
    func whatsNew() -> String? {
        let indonesian = Bundle.main.preferredLocalizations.first?.hasPrefix("id") == true
        let name = indonesian ? "CHANGELOG.id" : "CHANGELOG"
        guard let url = Bundle.main.url(forResource: name, withExtension: "md") ?? Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let md = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Changelog.section(md, version: current)
    }
}

// MARK: - Windows

@MainActor enum UpdateWindow {
    private static var window: NSWindow?
    static func show() { window = present(window, title: String(localized: "Pembaruan"), UpdateView { window?.close() }) }
}

@MainActor enum WhatsNewWindow {
    private static var window: NSWindow?
    static func show() {
        window = present(window, title: String(localized: "Yang baru di Cermin \(UpdateService.shared.current)"), WhatsNewView { window?.close() })
    }
}

@MainActor private func present<V: View>(_ existing: NSWindow?, title: String, _ view: V) -> NSWindow {
    let w = existing ?? NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.title = title
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: view)
    if existing == nil { w.center() }
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
    return w
}

private struct UpdateView: View {
    var done: () -> Void
    private var s: UpdateService { UpdateService.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch s.state {
            case .checking, .idle:
                HStack { ProgressView().controlSize(.small); Text("Memeriksa…") }
                Spacer()
            case .upToDate:
                Label("Cermin \(s.current) sudah versi terbaru.", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
                Spacer()
                HStack { Spacer(); Button("Oke") { done() }.keyboardShortcut(.defaultAction) }
            case .failed:
                Label("Tidak bisa memeriksa pembaruan. Periksa koneksi internet.", systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                Spacer()
                HStack { Spacer(); Button("Nanti") { done() }; Button("Coba lagi") { s.check(manual: true) }.keyboardShortcut(.defaultAction) }
            case .available(let r):
                Text("Cermin \(r.version?.description ?? r.tag) tersedia").font(.title2.bold())
                Text("Kamu memakai \(s.current).").foregroundStyle(.secondary)
                ScrollView { ChangelogText(markdown: r.body ?? "").frame(maxWidth: .infinity, alignment: .leading) }
                    .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                Text("Build ini belum dinotarisasi: setelah memasang, buka System Settings → Privacy & Security → Open Anyway.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Lewati versi ini") { s.skip(r); done() }
                    Spacer()
                    Button("Nanti") { done() }.keyboardShortcut(.cancelAction)
                    Button("Unduh") { NSWorkspace.shared.open(r.downloadURL); done() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 460, alignment: .topLeading)
    }
}

private struct WhatsNewView: View {
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yang baru di Cermin \(UpdateService.shared.current)").font(.title2.bold())
            ScrollView { ChangelogText(markdown: UpdateService.shared.whatsNew() ?? "").frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Link("Semua perubahan", destination: UpdateService.releasesPage)
                Spacer()
                Button("Oke") { done() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 460, alignment: .topLeading)
    }
}

/// Just enough markdown for changelogs and release notes: headings, bullets, inline bold/code/links.
struct ChangelogText: View {
    var markdown: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.split(separator: "\n", omittingEmptySubsequences: true).enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Text(inline(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))).font(.headline).padding(.top, 4)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "•")
                        Text(inline(String(line.dropFirst(2)))).fixedSize(horizontal: false, vertical: true)
                    }
                } else if !line.hasPrefix("```"), !line.hasPrefix("---") {
                    Text(inline(line)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
