/// One decoded-order frame worth of H.264 NAL units (no start codes, no length prefixes).
public struct AccessUnit: Equatable, Sendable {
    public var nalus: [[UInt8]]
    public var rtpTimestamp: UInt32

    public var isKeyframe: Bool { nalus.contains { H264.type(of: $0) == H264.idr } }
}

public enum H264 {
    public static let idr: UInt8 = 5, sei: UInt8 = 6, sps: UInt8 = 7, pps: UInt8 = 8, aud: UInt8 = 9

    public static func type(of nalu: [UInt8]) -> UInt8? { nalu.first.map { $0 & 0x1F } }

    /// AVCC sample payload: every non-parameter-set NAL with a 4-byte big-endian length prefix.
    public static func avcc(_ unit: AccessUnit) -> [UInt8] {
        var out: [UInt8] = []
        for nalu in unit.nalus where ![sps, pps, aud].contains(type(of: nalu)) && !nalu.isEmpty {
            let n = UInt32(nalu.count)
            out += [UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]
            out += nalu
        }
        return out
    }
}

/// RFC 3550 / RFC 6184 depacketizer for the stream UxPlay forwards via `-vrtp … rtph264pay ! udpsink`.
/// Handles single NAL, STAP-A and FU-A. Feed every UDP datagram to `push`; completed frames come back.
public struct H264RTPDepacketizer: Sendable {
    private var current: [[UInt8]] = []
    private var currentTimestamp: UInt32?
    private var fragment: [UInt8]?
    private var expectedSeq: UInt16?

    public init() {}

    /// Returns 0, 1 or 2 completed access units (2 when a timestamp change flushes a frame that had no marker bit).
    public mutating func push(_ packet: [UInt8]) -> [AccessUnit] {
        guard let rtp = RTPPacket(packet) else { return [] }
        var done: [AccessUnit] = []

        if let expected = expectedSeq, rtp.sequence != expected {
            fragment = nil // lost the middle of an FU-A; drop that NAL, keep going
        }
        expectedSeq = rtp.sequence &+ 1

        if let ts = currentTimestamp, ts != rtp.timestamp, let unit = flush() {
            done.append(unit)
        }
        currentTimestamp = rtp.timestamp
        appendPayload(rtp.payload)

        if rtp.marker, let unit = flush() {
            done.append(unit)
        }
        return done
    }

    private mutating func flush() -> AccessUnit? {
        defer { current = []; currentTimestamp = nil; fragment = nil }
        guard let ts = currentTimestamp, !current.isEmpty else { return nil }
        return AccessUnit(nalus: current, rtpTimestamp: ts)
    }

    private mutating func appendPayload(_ p: ArraySlice<UInt8>) {
        guard let first = p.first else { return }
        switch first & 0x1F {
        case 1...23:
            current.append(Array(p))
        case 24: // STAP-A: [hdr][len16][nal][len16][nal]…
            var i = p.startIndex + 1
            while i + 2 <= p.endIndex {
                let len = Int(p[i]) << 8 | Int(p[i + 1])
                i += 2
                guard len > 0, i + len <= p.endIndex else { break }
                current.append(Array(p[i..<i + len]))
                i += len
            }
        case 28: // FU-A: [indicator][fu header][fragment…]
            guard p.count >= 2 else { return }
            let indicator = p[p.startIndex], header = p[p.startIndex + 1]
            let body = p.dropFirst(2)
            if header & 0x80 != 0 {
                fragment = [indicator & 0xE0 | header & 0x1F] + body
            } else if fragment != nil {
                fragment! += body
            }
            if header & 0x40 != 0, let nal = fragment {
                current.append(nal)
                fragment = nil
            }
        default:
            break // STAP-B/MTAP/FU-B are not produced by rtph264pay
        }
    }
}

struct RTPPacket {
    let marker: Bool
    let sequence: UInt16
    let timestamp: UInt32
    let payload: ArraySlice<UInt8>

    init?(_ b: [UInt8]) {
        guard b.count >= 12, b[0] >> 6 == 2 else { return nil }
        var start = 12 + Int(b[0] & 0x0F) * 4
        if b[0] & 0x10 != 0 { // header extension
            guard b.count >= start + 4 else { return nil }
            start += 4 + (Int(b[start + 2]) << 8 | Int(b[start + 3])) * 4
        }
        var end = b.count
        if b[0] & 0x20 != 0, let pad = b.last { end -= Int(pad) }
        guard start < end else { return nil }
        marker = b[1] & 0x80 != 0
        sequence = UInt16(b[2]) << 8 | UInt16(b[3])
        timestamp = UInt32(b[4]) << 24 | UInt32(b[5]) << 16 | UInt32(b[6]) << 8 | UInt32(b[7])
        payload = b[start..<end]
    }
}
