import Foundation

/// A global keyboard chord such as `alt-space` or `ctrl-alt-shift-s`, in the key
/// naming AeroSpace uses so a binding reads the same in both configs.
struct Hotkey: Equatable, Hashable, CustomStringConvertible {
    let keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    let modifiers: UInt32
    /// The spelling as written in the config, kept for messages.
    let spelling: String

    var description: String { spelling }

    struct ParseError: Error, CustomStringConvertible, Equatable {
        let message: String
        var description: String { message }
    }

    /// Carbon `Events.h` modifier bits — spelled out so Core stays free of Carbon.
    enum Modifier {
        static let command: UInt32 = 0x0100
        static let shift: UInt32 = 0x0200
        static let option: UInt32 = 0x0800
        static let control: UInt32 = 0x1000
    }

    /// Parses `mod-mod-key`. Modifiers may come in any order; the key comes last.
    /// A bare modifier is rejected: `RegisterEventHotKey` cannot express one, and
    /// supporting it would need a CGEventTap and Accessibility permission.
    static func parse(_ spec: String) throws -> Hotkey {
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map { $0.lowercased() }
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else {
            throw ParseError(message: "'\(spec)' is not a hotkey; expected e.g. alt-space")
        }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            guard let bit = modifierNames[part] else {
                if keyCodes[part] != nil {
                    throw ParseError(message: "'\(spec)': '\(part)' is a key, and only the last part may be a key")
                }
                throw ParseError(message: "'\(spec)': unknown modifier '\(part)'")
            }
            modifiers |= bit
        }

        let keyName = parts[parts.count - 1]
        guard let keyCode = keyCodes[keyName] else {
            if modifierNames[keyName] != nil {
                throw ParseError(message: "'\(spec)': a hotkey needs a key after the modifiers")
            }
            throw ParseError(message: "'\(spec)': unknown key '\(keyName)'")
        }

        return Hotkey(keyCode: keyCode, modifiers: modifiers, spelling: spec)
    }

    private static let modifierNames: [String: UInt32] = [
        "alt": Modifier.option, "opt": Modifier.option, "option": Modifier.option,
        "ctrl": Modifier.control, "control": Modifier.control,
        "cmd": Modifier.command, "command": Modifier.command,
        "shift": Modifier.shift,
    ]

    /// Virtual key codes for the ANSI layout (`kVK_*` in Carbon's Events.h).
    /// Names follow AeroSpace's key list.
    private static let keyCodes: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "equal": 0x18,
        "9": 0x19, "7": 0x1A, "minus": 0x1B, "8": 0x1C, "0": 0x1D, "rightsquarebracket": 0x1E,
        "o": 0x1F, "u": 0x20, "leftsquarebracket": 0x21, "i": 0x22, "p": 0x23, "enter": 0x24,
        "l": 0x25, "j": 0x26, "quote": 0x27, "k": 0x28, "semicolon": 0x29, "backslash": 0x2A,
        "comma": 0x2B, "slash": 0x2C, "n": 0x2D, "m": 0x2E, "period": 0x2F, "tab": 0x30,
        "space": 0x31, "backtick": 0x32, "backspace": 0x33, "esc": 0x35, "sectionsign": 0x0A,

        "keypaddecimalmark": 0x41, "keypadmultiply": 0x43, "keypadplus": 0x45, "keypadclear": 0x47,
        "keypaddivide": 0x4B, "keypadenter": 0x4C, "keypadminus": 0x4E, "keypadequal": 0x51,
        "keypad0": 0x52, "keypad1": 0x53, "keypad2": 0x54, "keypad3": 0x55, "keypad4": 0x56,
        "keypad5": 0x57, "keypad6": 0x58, "keypad7": 0x59, "keypad8": 0x5B, "keypad9": 0x5C,

        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62,
        "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F, "f13": 0x69, "f14": 0x6B,
        "f15": 0x71, "f16": 0x6A, "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,

        "home": 0x73, "pageup": 0x74, "forwarddelete": 0x75, "end": 0x77, "pagedown": 0x79,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
}
