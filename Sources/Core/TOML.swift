import Foundation

// A deliberately small TOML reader: enough for a config file of tables, strings,
// booleans, numbers, arrays and inline tables. Not supported, and rejected with an
// error rather than mis-read: arrays of tables, multi-line strings, dates.
//
// It exists because the launcher builds with a bare `swiftc` call and ships as a
// single bundle — pulling in a TOML package would mean SwiftPM, network access at
// build time, and a different Homebrew formula shape than aerotab's.

indirect enum TOMLValue: Equatable {
    case string(String)
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case array([TOMLValue])
    case table([String: TOMLValue])

    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var integer: Int? { if case .integer(let i) = self { return i } else { return nil } }
    var array: [TOMLValue]? { if case .array(let a) = self { return a } else { return nil } }
    var table: [String: TOMLValue]? { if case .table(let t) = self { return t } else { return nil } }

    /// A short type name for error messages.
    var typeName: String {
        switch self {
        case .string: return "string"
        case .bool: return "boolean"
        case .integer: return "integer"
        case .double: return "float"
        case .array: return "array"
        case .table: return "table"
        }
    }
}

struct TOMLError: Error, CustomStringConvertible, Equatable {
    let line: Int
    let message: String

    var description: String { "line \(line): \(message)" }
}

enum TOML {
    static func parse(_ text: String) throws -> [String: TOMLValue] {
        var parser = Parser(text)
        return try parser.parseDocument()
    }
}

private struct Parser {
    private let chars: [Character]
    private var pos = 0
    private var line = 1

    /// The document being built and the table `[header]` currently in effect.
    private var root: [String: TOMLValue] = [:]
    private var currentPath: [String] = []
    /// Tables created by an explicit `[header]`; defining one twice is an error.
    private var definedTables: Set<[String]> = []

    init(_ text: String) {
        chars = Array(text)
    }

    // MARK: Document structure

    mutating func parseDocument() throws -> [String: TOMLValue] {
        while true {
            skipWhitespaceAndComments(includingNewlines: true)
            guard let c = peek() else { break }

            if c == "[" {
                try parseTableHeader()
            } else {
                let path = try parseKeyPath()
                skipWhitespace()
                try expect("=")
                skipWhitespace()
                let value = try parseValue()
                try insert(value, at: currentPath + path)
            }

            skipWhitespaceAndComments(includingNewlines: false)
            if let c = peek(), c != "\n", c != "\r" {
                throw error("unexpected '\(c)' after value")
            }
        }
        return root
    }

    private mutating func parseTableHeader() throws {
        try expect("[")
        if peek() == "[" {
            throw error("arrays of tables ([[...]]) are not supported")
        }
        skipWhitespace()
        let path = try parseKeyPath()
        skipWhitespace()
        try expect("]")

        guard !definedTables.contains(path) else {
            throw error("table [\(path.joined(separator: "."))] is defined twice")
        }
        definedTables.insert(path)

        // Materialise the table so an empty `[section]` still exists.
        try insert(.table([:]), at: path, mergingTables: true)
        currentPath = path
    }

    /// Reads `a.b."c.d"` — bare and quoted segments joined by dots.
    private mutating func parseKeyPath() throws -> [String] {
        var path: [String] = []
        while true {
            skipWhitespace()
            path.append(try parseKeySegment())
            skipWhitespace()
            if peek() == "." {
                advance()
                continue
            }
            return path
        }
    }

    private mutating func parseKeySegment() throws -> String {
        guard let c = peek() else { throw error("expected a key") }
        if c == "\"" { return try parseBasicString() }
        if c == "'" { return try parseLiteralString() }

        var key = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "_" || c == "-" {
            key.append(c)
            advance()
        }
        guard !key.isEmpty else { throw error("expected a key, found '\(c)'") }
        return key
    }

    // MARK: Values

    private mutating func parseValue() throws -> TOMLValue {
        guard let c = peek() else { throw error("expected a value") }
        switch c {
        case "\"": return .string(try parseBasicString())
        case "'": return .string(try parseLiteralString())
        case "[": return try parseArray()
        case "{": return try parseInlineTable()
        case "t", "f": return try parseBool()
        default:
            if c == "+" || c == "-" || c.isNumber { return try parseNumber() }
            throw error("unexpected '\(c)' where a value was expected")
        }
    }

    private mutating func parseBool() throws -> TOMLValue {
        if consumeWord("true") { return .bool(true) }
        if consumeWord("false") { return .bool(false) }
        throw error("expected true or false")
    }

    private mutating func parseNumber() throws -> TOMLValue {
        var text = ""
        while let c = peek(), c.isNumber || c == "+" || c == "-" || c == "_" || c == "." || c == "e" || c == "E" {
            if c != "_" { text.append(c) }
            advance()
        }
        if let i = Int(text) { return .integer(i) }
        if let d = Double(text) { return .double(d) }
        throw error("'\(text)' is not a number")
    }

    private mutating func parseArray() throws -> TOMLValue {
        try expect("[")
        var items: [TOMLValue] = []
        while true {
            skipWhitespaceAndComments(includingNewlines: true)
            if peek() == "]" {
                advance()
                return .array(items)
            }
            items.append(try parseValue())
            skipWhitespaceAndComments(includingNewlines: true)
            if peek() == "," {
                advance()
                continue
            }
            if peek() == "]" {
                advance()
                return .array(items)
            }
            throw error("expected ',' or ']' in array")
        }
    }

    private mutating func parseInlineTable() throws -> TOMLValue {
        try expect("{")
        var table: [String: TOMLValue] = [:]
        skipWhitespace()
        if peek() == "}" {
            advance()
            return .table(table)
        }
        while true {
            skipWhitespace()
            let path = try parseKeyPath()
            skipWhitespace()
            try expect("=")
            skipWhitespace()
            let value = try parseValue()
            table = try inserting(value, into: table, at: path, mergingTables: false)
            skipWhitespace()
            if peek() == "," {
                advance()
                continue
            }
            if peek() == "}" {
                advance()
                return .table(table)
            }
            throw error("expected ',' or '}' in inline table")
        }
    }

    // MARK: Strings

    private mutating func parseBasicString() throws -> String {
        try expect("\"")
        var result = ""
        while true {
            guard let c = peek() else { throw error("unterminated string") }
            if c == "\n" { throw error("unterminated string") }
            advance()
            if c == "\"" { return result }
            guard c == "\\" else {
                result.append(c)
                continue
            }
            guard let e = peek() else { throw error("unterminated string") }
            advance()
            switch e {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "u", "U":
                let width = e == "u" ? 4 : 8
                var hex = ""
                for _ in 0..<width {
                    guard let h = peek(), h.isHexDigit else { throw error("bad \\\(e) escape") }
                    hex.append(h)
                    advance()
                }
                guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
                    throw error("bad \\\(e) escape")
                }
                result.unicodeScalars.append(scalar)
            default:
                throw error("unknown escape '\\\(e)'")
            }
        }
    }

    private mutating func parseLiteralString() throws -> String {
        try expect("'")
        var result = ""
        while true {
            guard let c = peek() else { throw error("unterminated string") }
            if c == "\n" { throw error("unterminated string") }
            advance()
            if c == "'" { return result }
            result.append(c)
        }
    }

    // MARK: Insertion

    private mutating func insert(_ value: TOMLValue, at path: [String], mergingTables: Bool = false) throws {
        root = try inserting(value, into: root, at: path, mergingTables: mergingTables)
    }

    /// Returns `table` with `value` stored at `path`, creating intermediate tables.
    /// With `mergingTables`, storing a table over an existing table keeps the old
    /// contents — that is how `[a]` may follow `[a.b]`.
    private func inserting(
        _ value: TOMLValue,
        into table: [String: TOMLValue],
        at path: [String],
        mergingTables: Bool
    ) throws -> [String: TOMLValue] {
        var table = table
        let key = path[0]
        if path.count == 1 {
            if let existing = table[key] {
                guard mergingTables, case .table = existing, case .table = value else {
                    throw error("key '\(key)' is defined twice")
                }
                return table
            }
            table[key] = value
            return table
        }

        let child: [String: TOMLValue]
        switch table[key] {
        case nil: child = [:]
        case .table(let t)?: child = t
        case let other?: throw error("key '\(key)' is a \(other.typeName), not a table")
        }
        table[key] = .table(try inserting(value, into: child, at: Array(path.dropFirst()), mergingTables: mergingTables))
        return table
    }

    // MARK: Lexing helpers

    private func peek() -> Character? { pos < chars.count ? chars[pos] : nil }

    private mutating func advance() {
        if chars[pos] == "\n" { line += 1 }
        pos += 1
    }

    private mutating func expect(_ c: Character) throws {
        guard peek() == c else {
            if let found = peek() { throw error("expected '\(c)', found '\(found)'") }
            throw error("expected '\(c)', found end of file")
        }
        advance()
    }

    private mutating func consumeWord(_ word: String) -> Bool {
        let w = Array(word)
        guard pos + w.count <= chars.count, Array(chars[pos..<pos + w.count]) == w else { return false }
        // Reject a longer bare word such as `trueish`.
        if pos + w.count < chars.count, chars[pos + w.count].isLetter { return false }
        for _ in w { advance() }
        return true
    }

    private mutating func skipWhitespace() {
        while let c = peek(), c == " " || c == "\t" { advance() }
    }

    private mutating func skipWhitespaceAndComments(includingNewlines: Bool) {
        while let c = peek() {
            if c == " " || c == "\t" || c == "\r" {
                advance()
            } else if c == "#" {
                while let d = peek(), d != "\n" { advance() }
            } else if c == "\n", includingNewlines {
                advance()
            } else {
                return
            }
        }
    }

    private func error(_ message: String) -> TOMLError {
        TOMLError(line: line, message: message)
    }
}
