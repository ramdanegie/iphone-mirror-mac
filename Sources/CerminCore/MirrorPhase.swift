/// Where a mirror source is in its lifecycle (PRD §F1 state machine).
public enum MirrorPhase: Equatable, Sendable {
    /// D2 – nothing to show yet. `cableDetected` = an iPhone is on USB but not yet capturable (locked / not trusted).
    case waiting(cableDetected: Bool)
    /// D3 – device is known, waiting for the first frame.
    case connecting(deviceName: String)
    /// D4 – frames are flowing.
    case mirroring(deviceName: String)
    /// D6 – device went away mid-session; waits for it to come back.
    case disconnected(deviceName: String)

    public var deviceName: String? {
        switch self {
        case .waiting: nil
        case .connecting(let n), .mirroring(let n), .disconnected(let n): n
        }
    }

    public var isMirroring: Bool {
        if case .mirroring = self { return true }
        return false
    }
}

public enum MirrorEvent: Equatable, Sendable {
    case cable(present: Bool)
    case deviceAppeared(name: String)
    case firstFrame
    case deviceLost
    case reset
}

public extension MirrorPhase {
    func reduce(_ event: MirrorEvent) -> MirrorPhase {
        switch (self, event) {
        case (.waiting, .cable(let present)):
            return .waiting(cableDetected: present)
        case (_, .deviceAppeared(let name)):
            return .connecting(deviceName: name)
        case (.connecting(let n), .firstFrame), (.disconnected(let n), .firstFrame):
            return .mirroring(deviceName: n)
        case (.connecting(let n), .deviceLost), (.mirroring(let n), .deviceLost):
            return .disconnected(deviceName: n)
        case (_, .reset):
            return .waiting(cableDetected: false)
        default:
            return self
        }
    }
}
