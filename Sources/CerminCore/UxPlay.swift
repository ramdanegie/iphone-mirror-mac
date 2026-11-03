import Foundation

/// Connection-code mode for the AirPlay receiver (FR-24).
public enum CodeMode: String, CaseIterable, Sendable {
    case newCodeEachTime, fixedPassword, none
}

public struct UxPlayConfig: Equatable, Sendable {
    public var name = "Cermin"
    public var basePort: UInt16 = 7300 // not 7000: the built-in macOS AirPlay Receiver owns that one
    public var rtpPort: UInt16 = 5600
    public var codeMode: CodeMode = .newCodeEachTime
    public var pin = "0000"
    public var password = ""
    public var registerPath = ""
    public var audio = true
    public var peerToPeer = false
    /// Devices the user rejected with "Tolak" (D13); UxPlay refuses them until restarted without the flag.
    public var blocked: [String] = []

    public init() {}

    /// Arguments for the `uxplay` binary. Video is never rendered by UxPlay itself; it is forwarded as RTP to Cermin.
    public var arguments: [String] {
        var a = ["-n", name, "-nh", "-p", String(basePort), "-fps", "60", "-d", "1",
                 "-vrtp", "config-interval=1 ! udpsink host=127.0.0.1 port=\(rtpPort)"]
        switch codeMode {
        case .fixedPassword where password.count >= 6:
            a += ["-pw", password]
        case .newCodeEachTime, .fixedPassword: // a too-short password falls back to a PIN, never to no code
            a += ["-pin", pin]
            if !registerPath.isEmpty { a += ["-reg", registerPath] }
        case .none:
            break
        }
        if !audio { a += ["-as", "0"] }
        if peerToPeer { a.append("-p2p") }
        for id in blocked { a += ["-block", id] }
        return a
    }

    /// 4 digits, never starting with 0 (UxPlay parses `-pin` as a number).
    public static func randomPIN() -> String { String(Int.random(in: 1000...9999)) }
}

/// What Cermin cares about in UxPlay's log output.
public enum UxPlayEvent: Equatable, Sendable {
    case pinRequired(String)
    case clientRequest(name: String, model: String, deviceID: String)
    case authenticated(Bool)
    case sessionEnded
    case registered(name: String, deviceID: String)
    case fatal(String)
}

public enum UxPlayLogParser {
    public static func parse(_ line: String) -> UxPlayEvent? {
        if let pin = capture(line, after: "CLIENT MUST NOW ENTER PIN = \"", until: "\"") {
            return .pinRequired(pin)
        }
        if let rest = capture(line, after: "connection request from ", until: nil),
           let open = rest.range(of: " ("), let close = rest.range(of: ") with deviceID = ") {
            let name = String(rest[..<open.lowerBound])
            let model = String(rest[open.upperBound..<close.lowerBound])
            let id = String(rest[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return .clientRequest(name: name, model: model, deviceID: id)
        }
        if line.contains("Client authentication success") { return .authenticated(true) }
        if line.contains("Client authentication failure") { return .authenticated(false) }
        if line.contains("Open connections: 0") || line.contains("lost connection with client") {
            return .sessionEnded
        }
        if let rest = capture(line, after: "registered new client: ", until: nil),
           let r = rest.range(of: " DeviceID = ") {
            let id = rest[r.upperBound...].split(separator: " ").first.map(String.init) ?? ""
            return .registered(name: String(rest[..<r.lowerBound]), deviceID: id)
        }
        for marker in ["Address already in use", "failed to start", "Error initializing", "could not open"] where line.contains(marker) {
            return .fatal(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func capture(_ s: String, after start: String, until end: String?) -> String? {
        guard let a = s.range(of: start) else { return nil }
        let tail = s[a.upperBound...]
        guard let end else { return String(tail) }
        guard let b = tail.range(of: end) else { return nil }
        return String(tail[..<b.lowerBound])
    }
}

/// Clients that passed the PIN once (`-reg` file). Line format: `pk,YYYY-MM-DD HH:MM:SS,deviceID,name`.
public struct TrustedDevice: Equatable, Sendable, Identifiable {
    public var id: String { deviceID }
    public let deviceID: String
    public let name: String
    public let lastSeen: String
    let line: String
}

public enum TrustedRegister {
    public static func parse(_ text: String) -> [TrustedDevice] {
        text.split(separator: "\n").compactMap { raw in
            let parts = raw.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            return TrustedDevice(deviceID: String(parts[2]), name: String(parts[3]),
                                 lastSeen: String(parts[1]), line: String(raw))
        }
    }

    /// The register text with every entry for `deviceID` removed (unparseable lines are kept as-is).
    public static func removing(_ deviceID: String, from text: String) -> String {
        let kept = text.split(separator: "\n").filter { line in
            parse(String(line)).first?.deviceID != deviceID
        }
        return kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n"
    }
}
