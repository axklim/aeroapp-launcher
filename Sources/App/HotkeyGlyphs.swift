import Foundation

extension Hotkey {
    /// `alt-shift-s` → `⌥⇧S`, for the results list.
    var glyphs: String {
        let parts = spelling.split(separator: "-").map { $0.lowercased() }
        guard let key = parts.last else { return spelling }
        var out = ""
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control": out += "⌃"
            case "alt", "opt", "option": out += "⌥"
            case "shift": out += "⇧"
            case "cmd", "command": out += "⌘"
            default: out += part
            }
        }
        switch key {
        case "space": out += "Space"
        case "enter": out += "↩"
        case "esc": out += "⎋"
        case "tab": out += "⇥"
        case "backspace": out += "⌫"
        case "up": out += "↑"
        case "down": out += "↓"
        case "left": out += "←"
        case "right": out += "→"
        default: out += key.count == 1 ? key.uppercased() : key
        }
        return out
    }
}
