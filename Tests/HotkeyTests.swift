func runHotkeyTests() {
    test("Hotkey: alt-space") {
        let key = try Hotkey.parse("alt-space")
        expectEqual(key.keyCode, 0x31)
        expectEqual(key.modifiers, Hotkey.Modifier.option)
        expectEqual(key.description, "alt-space")
    }

    test("Hotkey: modifiers in any order, case-insensitive, synonyms") {
        let a = try Hotkey.parse("ctrl-alt-shift-s")
        let b = try Hotkey.parse("Shift-Option-Control-S")
        expectEqual(a.keyCode, b.keyCode)
        expectEqual(a.modifiers, b.modifiers)
        expectEqual(a.modifiers, Hotkey.Modifier.control | Hotkey.Modifier.option | Hotkey.Modifier.shift)
        expectEqual(try Hotkey.parse("cmd-1").modifiers, Hotkey.Modifier.command)
        expectEqual(try Hotkey.parse("command-1").keyCode, 0x12)
    }

    test("Hotkey: a key without modifiers is allowed") {
        let key = try Hotkey.parse("f13")
        expectEqual(key.keyCode, 0x69)
        expectEqual(key.modifiers, 0)
    }

    test("Hotkey: AeroSpace key names") {
        expectEqual(try Hotkey.parse("alt-leftSquareBracket").keyCode, 0x21)
        expectEqual(try Hotkey.parse("alt-keypadEnter").keyCode, 0x4C)
        expectEqual(try Hotkey.parse("alt-esc").keyCode, 0x35)
        expectEqual(try Hotkey.parse("alt-enter").keyCode, 0x24)
    }

    test("Hotkey: rejects bare modifiers, unknown names, empty parts") {
        expectThrows(Hotkey.ParseError.self, { _ = try Hotkey.parse("alt") }) { $0.message.contains("needs a key") }
        expectThrows(Hotkey.ParseError.self, { _ = try Hotkey.parse("alt-shift") }) { $0.message.contains("needs a key") }
        expectThrows(Hotkey.ParseError.self, { _ = try Hotkey.parse("hyper-space") }) { $0.message.contains("unknown modifier") }
        expectThrows(Hotkey.ParseError.self, { _ = try Hotkey.parse("alt-spacebar") }) { $0.message.contains("unknown key") }
        expectThrows(Hotkey.ParseError.self, { _ = try Hotkey.parse("space-alt") }) { $0.message.contains("only the last part") }
        expectThrows(Hotkey.ParseError.self, { _ = try Hotkey.parse("") })
        expectThrows(Hotkey.ParseError.self, { _ = try Hotkey.parse("alt--s") })
    }
}
