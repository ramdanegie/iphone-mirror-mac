import CoreGraphics
import Foundation
import Testing
@testable import CerminCore

@Suite struct MirrorPhaseTests {
    @Test func happyPathAndReconnect() {
        var s = MirrorPhase.waiting(cableDetected: false)
        s = s.reduce(.cable(present: true))
        #expect(s == .waiting(cableDetected: true))
        s = s.reduce(.deviceAppeared(name: "iPhone Egie"))
        #expect(s == .connecting(deviceName: "iPhone Egie"))
        s = s.reduce(.firstFrame)
        #expect(s.isMirroring)
        s = s.reduce(.cable(present: false)) // cable events don't interrupt a session
        #expect(s.isMirroring)
        s = s.reduce(.deviceLost)
        #expect(s == .disconnected(deviceName: "iPhone Egie"))
        s = s.reduce(.deviceAppeared(name: "iPhone Egie"))
        #expect(s == .connecting(deviceName: "iPhone Egie"))
        s = s.reduce(.reset)
        #expect(s == .waiting(cableDetected: false))
    }

    @Test func firstFrameWhileWaitingIsIgnored() {
        #expect(MirrorPhase.waiting(cableDetected: true).reduce(.firstFrame) == .waiting(cableDetected: true))
        #expect(MirrorPhase.waiting(cableDetected: false).reduce(.deviceLost) == .waiting(cableDetected: false))
    }
}

@Suite struct WindowSizingTests {
    let screen = CGSize(width: 1512, height: 944)
    let iphone = WindowSizing.defaultPixelSize

    @Test func presetsMatchDesign() {
        // Design: 300×650 window ≈ 75% of a 393×852pt iPhone.
        #expect(WindowSizing.contentSize(preset: .threeQuarter, pixelSize: iphone, visible: CGSize(width: 3000, height: 3000)) == CGSize(width: 295, height: 639))
        #expect(WindowSizing.contentSize(preset: .full, pixelSize: iphone, visible: CGSize(width: 3000, height: 3000)) == CGSize(width: 393, height: 852))
        #expect(WindowSizing.contentSize(preset: .half, pixelSize: iphone, visible: screen) == CGSize(width: 197, height: 426))
    }

    @Test func presetsNeverExceedScreen() {
        let s = WindowSizing.contentSize(preset: .full, pixelSize: iphone, visible: screen)
        #expect(s.height <= screen.height * 0.9)
        #expect(abs(s.width / s.height - iphone.width / iphone.height) < 0.01)
        let fit = WindowSizing.contentSize(preset: .fit, pixelSize: iphone, visible: screen)
        #expect(fit.height == (screen.height * 0.9).rounded(.down))
    }

    @Test func rotationKeepsLongSide() {
        let landscape = WindowSizing.resized(current: CGSize(width: 300, height: 650),
                                             newPixelSize: CGSize(width: 2556, height: 1179), visible: screen)
        #expect(landscape.width == 650)
        #expect(abs(landscape.height - 650 * 1179 / 2556) <= 1)
        let back = WindowSizing.resized(current: landscape, newPixelSize: iphone, visible: screen)
        #expect(back.height == 650)
    }

    @Test func rotationClampsToScreen() {
        let s = WindowSizing.resized(current: CGSize(width: 600, height: 1300),
                                     newPixelSize: CGSize(width: 2556, height: 1179), visible: CGSize(width: 1000, height: 800))
        #expect(s.width <= 900 && s.height <= 720)
    }

    @Test func cornerRadiusFollowsShortSide() {
        #expect(WindowSizing.cornerRadius(for: CGSize(width: 300, height: 650)) == 27)
        #expect(WindowSizing.cornerRadius(for: CGSize(width: 650, height: 300)) == 27)
        #expect(WindowSizing.pointScale(pixelSize: CGSize(width: 828, height: 1792)) == 2)
    }
}

@Suite struct ScreenshotNamingTests {
    @Test func nameAndCollisions() {
        let date = Date(timeIntervalSince1970: 1_793_698_865) // 2026-11-03 09:41:05 UTC
        let name = ScreenshotNaming.fileName(for: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Cermin 2026-11-03 09.41.05.png")
        let dir = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["Cermin 2026-11-03 09.41.05.png", "Cermin 2026-11-03 09.41.05 2.png"]
        let url = ScreenshotNaming.uniqueURL(in: dir, fileName: name) { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Cermin 2026-11-03 09.41.05 3.png")
    }
}

@Suite struct H264RTPDepacketizerTests {
    func rtp(seq: UInt16, ts: UInt32, marker: Bool, _ payload: [UInt8], padding: UInt8 = 0, ext: Bool = false) -> [UInt8] {
        var b: [UInt8] = [0x80 | (padding > 0 ? 0x20 : 0) | (ext ? 0x10 : 0), (marker ? 0x80 : 0) | 96,
                          UInt8(seq >> 8), UInt8(seq & 0xFF),
                          UInt8(ts >> 24), UInt8(ts >> 16 & 0xFF), UInt8(ts >> 8 & 0xFF), UInt8(ts & 0xFF),
                          0, 0, 0, 1]
        if ext { b += [0xBE, 0xDE, 0, 1, 9, 9, 9, 9] }
        b += payload
        if padding > 0 { b += [UInt8](repeating: 0, count: Int(padding) - 1) + [padding] }
        return b
    }

    let sps: [UInt8] = [0x67, 0x64, 0x00, 0x1F]
    let pps: [UInt8] = [0x68, 0xEE, 0x3C, 0x80]
    let idr: [UInt8] = [0x65] + (1...30).map { UInt8($0) }

    @Test func stapAThenFragmentedIDR() {
        var d = H264RTPDepacketizer()
        let stap: [UInt8] = [0x18, 0, 4] + sps + [0, 4] + pps
        #expect(d.push(rtp(seq: 10, ts: 900, marker: false, stap)).isEmpty)
        let body = Array(idr.dropFirst())
        let fu1: [UInt8] = [0x7C, 0x85] + body[0..<10]
        let fu2: [UInt8] = [0x7C, 0x05] + body[10..<20]
        let fu3: [UInt8] = [0x7C, 0x45] + body[20...]
        #expect(d.push(rtp(seq: 11, ts: 900, marker: false, fu1)).isEmpty)
        #expect(d.push(rtp(seq: 12, ts: 900, marker: false, fu2)).isEmpty)
        let out = d.push(rtp(seq: 13, ts: 900, marker: true, fu3))
        #expect(out.count == 1)
        #expect(out[0].nalus == [sps, pps, idr])
        #expect(out[0].isKeyframe)
        #expect(out[0].rtpTimestamp == 900)
        #expect(H264.avcc(out[0]) == [0, 0, 0, 31] + idr)
    }

    @Test func singleNalWithPaddingAndExtension() {
        var d = H264RTPDepacketizer()
        let nal: [UInt8] = [0x41, 1, 2, 3]
        let out = d.push(rtp(seq: 1, ts: 5, marker: true, nal, padding: 3, ext: true))
        #expect(out == [AccessUnit(nalus: [nal], rtpTimestamp: 5)])
        #expect(!out[0].isKeyframe)
    }

    @Test func timestampChangeFlushesFrameWithoutMarker() {
        var d = H264RTPDepacketizer()
        #expect(d.push(rtp(seq: 1, ts: 100, marker: false, [0x41, 1])).isEmpty)
        let out = d.push(rtp(seq: 2, ts: 200, marker: true, [0x41, 2]))
        #expect(out.map(\.rtpTimestamp) == [100, 200])
    }

    @Test func lostFragmentDropsOnlyThatNal() {
        var d = H264RTPDepacketizer()
        _ = d.push(rtp(seq: 1, ts: 7, marker: false, [0x06, 0xAA])) // SEI survives
        _ = d.push(rtp(seq: 2, ts: 7, marker: false, [0x7C, 0x85, 1, 2]))
        // seq 3 lost
        let out = d.push(rtp(seq: 4, ts: 7, marker: true, [0x7C, 0x45, 5, 6]))
        #expect(out.count == 1)
        #expect(out[0].nalus == [[0x06, 0xAA]])
    }

    @Test func rejectsGarbage() {
        var d = H264RTPDepacketizer()
        #expect(d.push([1, 2, 3]).isEmpty)
        #expect(d.push([0x40] + [UInt8](repeating: 0, count: 20)).isEmpty) // RTP version 1
        #expect(d.push(rtp(seq: 1, ts: 1, marker: true, [0x18, 0, 99, 1])).isEmpty) // STAP-A length overflow
    }
}

@Suite struct UxPlayTests {
    @Test func argumentsPerMode() {
        var c = UxPlayConfig()
        c.pin = "4719"
        c.registerPath = "/tmp/reg"
        let a = c.arguments
        #expect(a.starts(with: ["-n", "Cermin", "-nh", "-p", "7300"]))
        #expect(a.contains("-vrtp"))
        #expect(a.last(where: { $0.contains("udpsink") }) == "config-interval=1 ! udpsink host=127.0.0.1 port=5600")
        #expect(a.suffix(4) == ["-pin", "4719", "-reg", "/tmp/reg"])

        c.codeMode = .fixedPassword
        c.password = "rahasia1"
        c.audio = false
        #expect(c.arguments.suffix(4) == ["-pw", "rahasia1", "-as", "0"])

        c.password = "123" // too short for UxPlay: falls back to a PIN, never to no code at all
        #expect(!c.arguments.contains("-pw"))
        #expect(c.arguments.contains("-pin"))

        c.codeMode = .none
        c.peerToPeer = true
        #expect(!c.arguments.contains("-pin") && c.arguments.last == "-p2p")

        c.blocked = ["AA:BB"]
        #expect(c.arguments.suffix(3) == ["-p2p", "-block", "AA:BB"])
    }

    @Test func randomPINIsFourDigits() {
        for _ in 0..<200 {
            let p = UxPlayConfig.randomPIN()
            #expect(p.count == 4 && p.first != "0" && Int(p) != nil)
        }
    }

    @Test func parsesLogLines() {
        #expect(UxPlayLogParser.parse("*** CLIENT MUST NOW ENTER PIN = \"4719\" AS AIRPLAY PASSWORD") == .pinRequired("4719"))
        #expect(UxPlayLogParser.parse("connection request from iPhone Egie (iPhone16,2) with deviceID = AA:BB:CC:DD:EE:FF\n")
            == .clientRequest(name: "iPhone Egie", model: "iPhone16,2", deviceID: "AA:BB:CC:DD:EE:FF"))
        #expect(UxPlayLogParser.parse("Client authentication success") == .authenticated(true))
        #expect(UxPlayLogParser.parse("Client authentication failure") == .authenticated(false))
        #expect(UxPlayLogParser.parse("Open connections: 0") == .sessionEnded)
        #expect(UxPlayLogParser.parse("Open connections: 1") == nil)
        #expect(UxPlayLogParser.parse("*** ERROR lost connection with client (network problem?)") == .sessionEnded)
        #expect(UxPlayLogParser.parse("registered new client: iPhone Egie DeviceID = AA:BB PK = ")
            == .registered(name: "iPhone Egie", deviceID: "AA:BB"))
        #expect(UxPlayLogParser.parse("random noise") == nil)
    }

    @Test func trustedRegisterRoundTrip() {
        let text = "pk1,2026-11-03 09:41:00,AA:BB,iPhone Egie\npk2,2026-10-28 10:00:00,CC:DD,iPhone Demo, Klinik\n"
        let list = TrustedRegister.parse(text)
        #expect(list.map(\.name) == ["iPhone Egie", "iPhone Demo, Klinik"])
        #expect(list[1].lastSeen == "2026-10-28 10:00:00")
        let after = TrustedRegister.removing("AA:BB", from: text)
        #expect(TrustedRegister.parse(after).map(\.deviceID) == ["CC:DD"])
        #expect(TrustedRegister.removing("CC:DD", from: after) == "")
    }
}

@Suite struct HotKeyComboTests {
    @Test func displayAndValidity() {
        #expect(HotKeyCombo.privacyCurtainDefault.display == "⌃⌥⌘P")
        #expect(HotKeyCombo.privacyCurtainDefault.isValidGlobal)
        #expect(!HotKeyCombo(keyCode: 35, modifiers: HotKeyCombo.shift).isValidGlobal)
        #expect(!HotKeyCombo(keyCode: 200, modifiers: HotKeyCombo.cmd).isValidGlobal)
        let data = try! JSONEncoder().encode(HotKeyCombo.privacyCurtainDefault)
        #expect(try! JSONDecoder().decode(HotKeyCombo.self, from: data) == .privacyCurtainDefault)
    }
}
