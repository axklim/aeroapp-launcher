import Foundation

func runTOMLTests() {
    test("TOML: scalars and comments") {
        let doc = try TOML.parse("""
        # comment
        name = "Slack"   # trailing comment
        follow = true
        count = 3
        ratio = 1.5
        literal = 'C:\\path'
        escaped = "tab\\there \\"q\\" \\u00e9"
        """)
        expectEqual(doc["name"], .string("Slack"))
        expectEqual(doc["follow"], .bool(true))
        expectEqual(doc["count"], .integer(3))
        expectEqual(doc["ratio"], .double(1.5))
        expectEqual(doc["literal"], .string("C:\\path"))
        expectEqual(doc["escaped"], .string("tab\there \"q\" é"))
    }

    test("TOML: tables with quoted dotted headers") {
        let doc = try TOML.parse("""
        hotkey = "alt-space"

        [defaults]
        new_window = "open"

        [apps."com.tinyspeck.slackmacgap"]
        follow = true
        hotkey = "alt-shift-s"

        [apps."dev.zed.Zed"]
        new_window = ["zed", "-n"]
        """)
        let apps = doc["apps"]?.table
        expectEqual(apps?["com.tinyspeck.slackmacgap"]?.table?["follow"], .bool(true))
        expectEqual(apps?["com.tinyspeck.slackmacgap"]?.table?["hotkey"], .string("alt-shift-s"))
        expectEqual(apps?["dev.zed.Zed"]?.table?["new_window"], .array([.string("zed"), .string("-n")]))
        expectEqual(doc["defaults"]?.table?["new_window"], .string("open"))
        expectEqual(doc["hotkey"], .string("alt-space"))
    }

    test("TOML: inline tables, multi-line arrays, dotted keys") {
        let doc = try TOML.parse("""
        [apps."com.apple.finder"]
        new_window = { applescript = 'tell application "Finder" to make new Finder window' }
        aliases = [
            "files",  # comment inside
            "explorer",
        ]
        nested.key = 1
        empty = {}
        """)
        let finder = doc["apps"]?.table?["com.apple.finder"]?.table
        expectEqual(finder?["new_window"], .table(["applescript": .string("tell application \"Finder\" to make new Finder window")]))
        expectEqual(finder?["aliases"], .array([.string("files"), .string("explorer")]))
        expectEqual(finder?["nested"], .table(["key": .integer(1)]))
        expectEqual(finder?["empty"], .table([:]))
    }

    test("TOML: empty document and whitespace only") {
        expectEqual(try TOML.parse(""), [:])
        expectEqual(try TOML.parse("\n\n  # just a comment\n"), [:])
    }

    test("TOML: parent table after child table merges") {
        let doc = try TOML.parse("""
        [a.b]
        x = 1
        [a]
        y = 2
        """)
        expectEqual(doc["a"], .table(["b": .table(["x": .integer(1)]), "y": .integer(2)]))
    }

    test("TOML: errors carry line numbers") {
        expectThrows(TOMLError.self, { _ = try TOML.parse("a = 1\nb = \n") }) { $0.line == 2 }
        expectThrows(TOMLError.self, { _ = try TOML.parse("a = 1\na = 2\n") }) { $0.line == 2 && $0.message.contains("twice") }
        expectThrows(TOMLError.self, { _ = try TOML.parse("[t]\n[t]\n") }) { $0.message.contains("twice") }
        expectThrows(TOMLError.self, { _ = try TOML.parse("[[t]]\n") }) { $0.message.contains("not supported") }
        expectThrows(TOMLError.self, { _ = try TOML.parse("a = \"unterminated\n") }) { $0.message.contains("unterminated") }
        expectThrows(TOMLError.self, { _ = try TOML.parse("a = 1 b = 2\n") }) { $0.message.contains("unexpected") }
        expectThrows(TOMLError.self, { _ = try TOML.parse("a = trueish\n") })
        expectThrows(TOMLError.self, { _ = try TOML.parse("a = 1\na.b = 2\n") }) { $0.message.contains("not a table") }
    }
}
