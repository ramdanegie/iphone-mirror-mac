/// A global shortcut stored as a Carbon virtual key code + Carbon modifier mask.
public struct HotKeyCombo: Equatable, Sendable, Codable {
    public static let cmd: UInt32 = 0x0100, shift: UInt32 = 0x0200, option: UInt32 = 0x0800, control: UInt32 = 0x1000

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥⌘P (PRD §F3).
    public static let privacyCurtainDefault = HotKeyCombo(keyCode: 35, modifiers: control | option | cmd)

    /// A global hotkey without ⌘/⌃/⌥ would swallow normal typing in every app.
    public var isValidGlobal: Bool { modifiers & (Self.cmd | Self.control | Self.option) != 0 && Self.keyNames[keyCode] != nil }

    /// "P", "5", "F1", "Space"… nil for unsupported keys.
    public var keyLabel: String? { Self.keyNames[keyCode] }

    public var display: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.cmd != 0 { s += "⌘" }
        return s + (Self.keyNames[keyCode] ?? "?")
    }

    /// ANSI key codes (kVK_ANSI_*) → label.
    static let keyNames: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        49: "Space", 44: "/", 41: ";", 39: "'", 43: ",", 47: ".", 27: "-", 24: "=",
    ]
}
