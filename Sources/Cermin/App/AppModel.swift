import AppKit
import AVFoundation
import CerminCore
import Observation
import Security
import ServiceManagement

struct ConnectionRequest: Equatable {
    let name: String
    let deviceID: String
}

enum WirelessStatus: Equatable {
    case off, notInstalled, ready, failed(String)
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Live state

    private(set) var usbPhase = MirrorPhase.waiting(cableDetected: false)
    private(set) var wirelessPhase = MirrorPhase.waiting(cableDetected: false)
    private(set) var source: SourceKind = .usb
    var phase: MirrorPhase { source == .usb ? usbPhase : wirelessPhase }

    private(set) var fps = 0
    private(set) var curtain = false
    private(set) var pinned: Bool
    private(set) var preset: SizePreset
    private(set) var windowVisible = false
    private(set) var hovering = false
    private(set) var recentlyStarted = false
    private(set) var toast: String?
    private(set) var usbProblem: USBSource.Problem?
    /// An iPhone is available but "mulai otomatis" is off.
    private(set) var usbDeviceWaiting = false
    private(set) var pinCode: String?
    private(set) var pendingRequest: ConnectionRequest?
    private(set) var wirelessStatus = WirelessStatus.off
    private(set) var trustedDevices: [TrustedDevice] = []
    private(set) var wifiName: String?
    private(set) var ipAddress: String?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    var statusPillVisible: Bool { phase.isMirroring && !curtain && (hovering || recentlyStarted) }
    var curtainHotKeyDisplay: String { curtainHotKey.display }

    // MARK: Settings (persisted)

    var pinnedByDefault: Bool { didSet { defaults.set(pinnedByDefault, forKey: "pinnedByDefault") } }
    var autoStart: Bool { didSet { defaults.set(autoStart, forKey: "autoStart"); usb.autoConnect = autoStart; usb.scan() } }
    var screenshotFolder: String { didSet { defaults.set(screenshotFolder, forKey: "screenshotFolder") } }
    var copyScreenshot: Bool { didSet { defaults.set(copyScreenshot, forKey: "copyScreenshot") } }
    var roundedCorners: Bool { didSet { defaults.set(roundedCorners, forKey: "roundedCorners"); window?.applyCorners() } }
    var defaultPreset: SizePreset { didSet { defaults.set(defaultPreset.rawValue, forKey: "defaultPreset") } }
    var audioEnabled: Bool {
        didSet {
            defaults.set(audioEnabled, forKey: "audioEnabled")
            usb.audioEnabled = audioEnabled
            wirelessConfigChanged()
        }
    }
    var volume: Double { didSet { defaults.set(volume, forKey: "volume"); usb.volume = Float(volume) } }
    var curtainHotKey: HotKeyCombo {
        didSet {
            defaults.set(try? JSONEncoder().encode(curtainHotKey), forKey: "curtainHotKey")
            registerHotKey()
        }
    }
    var wirelessEnabled: Bool {
        didSet {
            defaults.set(wirelessEnabled, forKey: "wirelessEnabled")
            wirelessEnabled ? startWireless() : stopWireless()
        }
    }
    var receiverName: String { didSet { defaults.set(receiverName, forKey: "receiverName"); wirelessConfigChanged() } }
    var codeMode: CodeMode { didSet { defaults.set(codeMode.rawValue, forKey: "codeMode"); wirelessConfigChanged() } }
    var fixedPassword: String { didSet { Keychain.set(fixedPassword, account: "airplay-password"); wirelessConfigChanged() } }
    var preferUSB: Bool { didSet { defaults.set(preferUSB, forKey: "preferUSB") } }
    var peerToPeer: Bool { didSet { defaults.set(peerToPeer, forKey: "peerToPeer"); wirelessConfigChanged() } }
    private(set) var alwaysAllow: [String] { didSet { defaults.set(alwaysAllow, forKey: "alwaysAllow") } }
    private(set) var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }

    // MARK: Components

    @ObservationIgnored let pipeline: DisplayPipeline
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let usb: USBSource
    @ObservationIgnored private let airplay: AirPlaySource
    @ObservationIgnored private let hotKey = GlobalHotKey()
    @ObservationIgnored private(set) var window: MirrorWindowController?
    @ObservationIgnored private var onboarding: NSWindowController?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var toastID = 0
    @ObservationIgnored private var deniedIDs: Set<String> = []
    @ObservationIgnored private var approvedThisSession: Set<String> = []
    @ObservationIgnored private var configChangeID = 0
    @ObservationIgnored private var promptTimeoutID = 0

    private init() {
        let pipeline = DisplayPipeline()
        self.pipeline = pipeline
        usb = USBSource(pipeline: pipeline)
        airplay = AirPlaySource(pipeline: pipeline)
        let d = UserDefaults.standard
        func load<T>(_ key: String, _ fallback: T) -> T { d.object(forKey: key) as? T ?? fallback }
        pinnedByDefault = load("pinnedByDefault", true)
        pinned = load("pinnedByDefault", true)
        autoStart = load("autoStart", true)
        screenshotFolder = load("screenshotFolder", "~/Pictures/Cermin")
        copyScreenshot = load("copyScreenshot", true)
        roundedCorners = load("roundedCorners", true)
        defaultPreset = SizePreset(rawValue: load("defaultPreset", 75)) ?? .threeQuarter
        preset = SizePreset(rawValue: load("defaultPreset", 75)) ?? .threeQuarter
        audioEnabled = load("audioEnabled", false)
        volume = load("volume", 1.0)
        curtainHotKey = (d.data(forKey: "curtainHotKey")).flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) }
            ?? .privacyCurtainDefault
        wirelessEnabled = load("wirelessEnabled", false)
        receiverName = load("receiverName", "Cermin")
        codeMode = CodeMode(rawValue: load("codeMode", CodeMode.newCodeEachTime.rawValue)) ?? .newCodeEachTime
        fixedPassword = Keychain.get(account: "airplay-password") ?? ""
        preferUSB = load("preferUSB", true)
        peerToPeer = load("peerToPeer", false)
        alwaysAllow = load("alwaysAllow", [String]())
        onboarded = load("onboarded", false)
    }

    // MARK: Lifecycle

    func start() {
        pipeline.onFirstFrame = { [weak self] source in self?.firstFrame(from: source) }
        pipeline.onSizeChange = { [weak self] source, size in
            guard let self, source == self.source else { return }
            self.window?.applyPixelSize(size)
        }
        usb.onDeviceAppeared = { [weak self] device in self?.usbDeviceAppeared(device) }
        usb.onDeviceLost = { [weak self] in self?.usbLost() }
        usb.onProblem = { [weak self] problem in self?.usbProblem = problem }
        usb.autoConnect = autoStart
        usb.audioEnabled = audioEnabled
        usb.volume = Float(volume)
        airplay.onEvent = { [weak self] event in self?.handle(event) }
        airplay.onExit = { [weak self] message in
            self?.wirelessStatus = .failed(message)
            self?.endWirelessSession()
        }

        window = MirrorWindowController(model: self)
        window?.setPinned(pinned)
        registerHotKey()
        reloadTrusted()
        usb.start()
        if wirelessEnabled { startWireless() }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        onboarded ? showWindow() : showOnboarding()
    }

    func shutdown() {
        airplay.shutdown()
        usb.teardown()
    }

    private func tick() {
        ticks += 1
        fps = pipeline.takeFrameCount()
        if usb.device == nil {
            let cable = USBSource.iPhoneOnUSB()
            if case .waiting = usbPhase, usbPhase != .waiting(cableDetected: cable) {
                usbPhase = usbPhase.reduce(.cable(present: cable))
            }
            usbDeviceWaiting = !autoStart && usb.availableDevice != nil
            if cable { usb.scan() } // trust/unlock/replug → AVFoundation may expose it without a notification
        }
        if wirelessEnabled, ticks % 5 == 1 { refreshNetwork() }
        #if DEBUG
        if ProcessInfo.processInfo.environment["CERMIN_LOG"] != nil {
            let size = pipeline.size(of: source).map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"
            print("[tick] source=\(source) usb=\(usbPhase) wireless=\(wirelessPhase) fps=\(fps) size=\(size) pin=\(pinCode ?? "-") request=\(pendingRequest?.name ?? "-") status=\(wirelessStatus) window=\(window.map { "\($0.window.frame.size)" } ?? "-") uxplay=\(airplay.recentLog.last ?? "-")")
            fflush(stdout)
        }
        if pendingRequest != nil, let answer = ProcessInfo.processInfo.environment["CERMIN_AUTOANSWER"] {
            answer == "deny" ? deny() : approve(always: false)
        }
        #endif
    }

    // MARK: USB

    func startUSBNow() {
        usb.connectAvailable()
        usbDeviceWaiting = false
    }

    private func usbDeviceAppeared(_ device: AVCaptureDevice) {
        usbPhase = usbPhase.reduce(.deviceAppeared(name: device.localizedName))
        usbDeviceWaiting = false
        if source == .wireless, preferUSB || !wirelessPhase.isMirroring { setSource(.usb) }
        if source == .usb { window?.useDevice(key: "usb:\(device.uniqueID)", name: device.localizedName) }
    }

    private func usbLost() {
        usbPhase = usbPhase.reduce(.deviceLost)
        if source == .usb, wirelessPhase.isMirroring { setSource(.wireless) }
        // Not back within a few seconds (cable pulled for good) → back to the D2 checklist.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, case .disconnected = self.usbPhase, self.usb.device == nil else { return }
            self.usbPhase = self.usbPhase.reduce(.reset)
        }
    }

    func retryCamera() {
        usbProblem = nil
        if AVCaptureDevice.authorizationStatus(for: .video) == .denied { Diagnostics.open(.camera) }
        usb.retry()
    }

    // MARK: Frames

    private func firstFrame(from source: SourceKind) {
        if source == .usb {
            usbPhase = usbPhase.reduce(.firstFrame)
            usbProblem = nil
            usb.recovered()
            if self.source == .wireless, preferUSB { setSource(.usb) }
        } else {
            pinCode = nil
            wirelessPhase = wirelessPhase.reduce(.firstFrame)
            if self.source == .usb, !usbPhase.isMirroring { setSource(.wireless) }
        }
        guard source == self.source else { return }
        // A restored frame may be in the other orientation than the phone is now.
        if let size = pipeline.size(of: source) { window?.applyPixelSize(size) }
        recentlyStarted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.recentlyStarted = false }
    }

    func setSource(_ newSource: SourceKind) {
        guard newSource != source else { return }
        source = newSource
        pipeline.setActive(newSource)
        if let size = pipeline.size(of: newSource) { window?.applyPixelSize(size) }
        window?.updateTitle()
    }

    // MARK: Wireless

    private var registerURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cermin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("uxplay.register")
    }

    /// Generated once: iOS remembers pairings per receiver ID, so it must never change between launches.
    private var airPlayDeviceID: String {
        if let id = defaults.string(forKey: "airplayDeviceID") { return id }
        let id = UxPlayConfig.randomDeviceID()
        defaults.set(id, forKey: "airplayDeviceID")
        return id
    }

    func startWireless() {
        #if DEBUG
        if Snapshots.active { return }
        #endif
        guard AirPlaySource.findBinary() != nil else {
            wirelessStatus = .notInstalled
            return
        }
        var config = UxPlayConfig()
        config.name = receiverName.isEmpty ? "Cermin" : receiverName
        config.codeMode = codeMode
        config.pin = UxPlayConfig.randomPIN()
        config.password = fixedPassword
        config.registerPath = registerURL.path
        config.keyPath = registerURL.deletingLastPathComponent().appendingPathComponent("uxplay.pem").path
        config.deviceID = airPlayDeviceID
        config.audio = audioEnabled
        config.peerToPeer = peerToPeer
        config.blocked = deniedIDs.sorted()
        do {
            try airplay.start(config)
            wirelessStatus = .ready
            refreshNetwork()
        } catch {
            wirelessStatus = .failed("UxPlay gagal dijalankan: \(error.localizedDescription)")
        }
    }

    func stopWireless() {
        airplay.shutdown()
        endWirelessSession()
        wirelessStatus = .off
        if source == .wireless { setSource(.usb) }
    }

    /// Order matters: stop the stream first, then reset gate/UI, then relaunch — so no frame of the old
    /// connection can arrive after the gate state was reset.
    func restartWirelessIfRunning() {
        guard wirelessEnabled, wirelessStatus != .off else { return }
        airplay.stop()
        endWirelessSession()
        startWireless()
    }

    private var wirelessIdle: Bool {
        wirelessPhase == .waiting(cableDetected: false) && pinCode == nil && pendingRequest == nil
    }

    /// UxPlay reads its options only at launch. Apply now if nobody is connected (debounced for typing);
    /// otherwise the restart after the current session picks the change up.
    private func wirelessConfigChanged() {
        guard wirelessEnabled, wirelessStatus != .off else { return }
        configChangeID += 1
        let id = configChangeID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.configChangeID == id, self.wirelessIdle else { return }
            self.restartWirelessIfRunning()
        }
    }

    private func handle(_ event: UxPlayEvent) {
        switch event {
        case .pinRequired(let pin):
            pinCode = pin
            schedulePromptTimeout()
            if source == .usb, !usbPhase.isMirroring { setSource(.wireless) }
            if source == .wireless { showWindow() } // never cover a live USB presentation with someone's PIN
        case .clientRequest(let name, _, let deviceID):
            if !wirelessPhase.isMirroring {
                pipeline.sessionEnded(.wireless) // stray packets of an old stream must not count as this session's first frame
                wirelessPhase = wirelessPhase.reduce(.deviceAppeared(name: name))
            }
            if alwaysAllow.contains(deviceID) || approvedThisSession.contains(deviceID) {
                if pendingRequest?.deviceID != deviceID { pendingRequest = nil } // someone else's stale prompt
                pipeline.setWirelessGated(false)
            } else if pendingRequest?.deviceID != deviceID {
                pendingRequest = ConnectionRequest(name: name, deviceID: deviceID)
                pipeline.setWirelessGated(true)
                schedulePromptTimeout()
            }
            if source == .usb, !usbPhase.isMirroring { setSource(.wireless) }
            if source == .wireless {
                window?.useDevice(key: "airplay:\(deviceID)", name: name)
                showWindow()
            }
        case .authenticated(let ok):
            if ok { pinCode = nil } else if source == .wireless { showToast("Kode salah. Coba lagi di iPhone.") }
        case .sessionEnded:
            // UxPlay also logs this between the short connections iOS makes while pairing; only a real stream counts.
            // Always relaunch afterwards: fresh PIN, and settings changed mid-session take effect.
            if wirelessPhase.isMirroring { restartWirelessIfRunning() }
        case .registered:
            reloadTrusted()
        case .fatal(let message):
            wirelessStatus = .failed(message)
        }
    }

    /// Clears session UI and closes the gate: the next device stays invisible until approved or always-allowed.
    private func endWirelessSession() {
        pinCode = nil
        pendingRequest = nil
        approvedThisSession = []
        pipeline.setWirelessGated(true)
        pipeline.sessionEnded(.wireless)
        if wirelessPhase != .waiting(cableDetected: false) {
            wirelessPhase = wirelessPhase.reduce(.deviceLost)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, case .disconnected = self.wirelessPhase else { return }
                self.wirelessPhase = self.wirelessPhase.reduce(.reset)
            }
        }
        if source == .wireless, usbPhase.isMirroring { setSource(.usb) }
    }

    /// A PIN or prompt nobody answers (iPhone gave up) must not sit on the shared screen forever.
    private func schedulePromptTimeout() {
        promptTimeoutID += 1
        let id = promptTimeoutID
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            guard let self, self.promptTimeoutID == id,
                  self.pendingRequest != nil || (self.pinCode != nil && !self.wirelessPhase.isMirroring) else { return }
            self.restartWirelessIfRunning()
        }
    }

    func approve(always: Bool) {
        guard let request = pendingRequest else { return }
        if always, !alwaysAllow.contains(request.deviceID) { alwaysAllow.append(request.deviceID) }
        approvedThisSession.insert(request.deviceID)
        pendingRequest = nil
        pipeline.setWirelessGated(false)
    }

    func deny() {
        guard let request = pendingRequest else { return }
        deniedIDs.insert(request.deviceID) // relaunch with -block keeps it out
        restartWirelessIfRunning()
    }

    func cancelPin() { restartWirelessIfRunning() }

    func reloadTrusted() {
        let text = (try? String(contentsOf: registerURL, encoding: .utf8)) ?? ""
        trustedDevices = TrustedRegister.parse(text)
    }

    func removeTrusted(_ device: TrustedDevice) {
        let text = (try? String(contentsOf: registerURL, encoding: .utf8)) ?? ""
        try? TrustedRegister.removing(device.deviceID, from: text).write(to: registerURL, atomically: true, encoding: .utf8)
        alwaysAllow.removeAll { $0 == device.deviceID }
        reloadTrusted()
        restartWirelessIfRunning() // UxPlay reads the register only at launch
    }

    func refreshNetwork() {
        wifiName = Diagnostics.wifiName()
        ipAddress = Diagnostics.localIPv4()
    }

    // MARK: Actions

    func toggleCurtain() {
        curtain.toggle()
        pipeline.setCurtain(curtain)
    }

    func togglePinned() {
        pinned.toggle()
        window?.setPinned(pinned)
    }

    func apply(_ newPreset: SizePreset) {
        preset = newPreset
        window?.applyPreset(newPreset)
    }

    func screenshot() {
        guard !curtain, let frame = pipeline.latestFrame() else {
            showToast("Belum ada layar untuk di-screenshot")
            return
        }
        let folder = URL(fileURLWithPath: (screenshotFolder as NSString).expandingTildeInPath, isDirectory: true)
        do {
            _ = try Screenshot.save(frame, to: folder, copyToClipboard: copyScreenshot)
            showToast("Screenshot tersimpan")
        } catch {
            showToast("Gagal menyimpan screenshot")
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showToast("Tidak bisa mengubah login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setHovering(_ on: Bool) {
        hovering = on
        window?.setTrafficLights(visible: on)
    }

    func showToast(_ message: String) {
        toastID += 1
        let id = toastID
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.toastID == id { self?.toast = nil }
        }
    }

    // MARK: Windows

    func showWindow() {
        guard onboarded else { return }
        window?.show()
        windowVisible = true
    }

    func hideWindow() {
        window?.hide()
        windowVisible = false
    }

    func toggleWindow() { windowVisible ? hideWindow() : showWindow() }

    func windowWasClosed() { windowVisible = false }

    private func showOnboarding() {
        let controller = NSWindowController(window: OnboardingWindow.make(model: self))
        onboarding = controller
        controller.window?.center()
        controller.showWindow(nil)
        NSApp.activate()
    }

    func finishOnboarding() {
        onboarded = true
        onboarding?.close()
        onboarding = nil
        showWindow()
        usb.scan()
    }

    private func registerHotKey() {
        if !hotKey.register(curtainHotKey, action: { [weak self] in self?.toggleCurtain() }) {
            showToast("Shortcut \(curtainHotKey.display) sudah dipakai app lain")
        }
    }
}

/// AirPlay password lives in the Keychain, not in UserDefaults.
enum Keychain {
    private static func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "Cermin", kSecAttrAccount: account]
    }

    static func get(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = query(account)
        q[kSecValueData] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}

#if DEBUG
/// Puts the model into a given UI state for offscreen snapshots (`Cermin --snapshot <dir>`, debug builds only).
extension AppModel {
    func debugState(usb: MirrorPhase = .waiting(cableDetected: false), wireless: MirrorPhase = .waiting(cableDetected: false),
                    source: SourceKind = .usb, curtain: Bool = false, hovering: Bool = false, toast: String? = nil,
                    pin: String? = nil, request: ConnectionRequest? = nil, wirelessStatus: WirelessStatus = .off,
                    problem: USBSource.Problem? = nil, deviceWaiting: Bool = false) {
        usbPhase = usb
        wirelessPhase = wireless
        self.source = source
        self.curtain = curtain
        self.hovering = hovering
        self.toast = toast
        pinCode = pin
        pendingRequest = request
        self.wirelessStatus = wirelessStatus
        usbProblem = problem
        usbDeviceWaiting = deviceWaiting
        fps = 60
        recentlyStarted = true
        wifiName = "Kantor-5G"
        ipAddress = "192.168.1.24"
        onboarded = true
    }
}
#endif
