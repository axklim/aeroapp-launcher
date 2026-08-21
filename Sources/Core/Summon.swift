import Foundation

/// One row of `aerospace list-windows --json` with the format the launcher asks for.
struct AeroWindow: Decodable, Equatable {
    let windowId: Int
    let workspace: String
    let workspaceIsFocused: Bool

    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case workspace
        case workspaceIsFocused = "workspace-is-focused"
    }

    static let format = "%{window-id}%{workspace}%{workspace-is-focused}"

    static func decode(json: Data) throws -> [AeroWindow] {
        try JSONDecoder().decode([AeroWindow].self, from: json)
    }
}

/// What summoning an app should do, given where its windows currently are.
///
///     X's windows     default            follow
///     none            launch here        launch here
///     one here        focus it           focus it
///     one elsewhere   new window here    move it here, focus
enum SummonPlan: Equatable {
    /// Nothing anywhere: launch (or reopen) the app; its window lands on the
    /// focused workspace because that is where AeroSpace puts new windows.
    case launch
    /// A window is already on the focused workspace: raise it.
    case focus(windowId: Int)
    /// Windows exist but only elsewhere; the app is not `follow`.
    case newWindow(existing: [AeroWindow])
    /// Windows exist only elsewhere and the app follows: bring every one of them
    /// here, then focus the first. All of them, because `follow` means the app
    /// lives on exactly one workspace at a time.
    case moveHere(windowIds: [Int])

    static func decide(windows: [AeroWindow], follow: Bool) -> SummonPlan {
        if let here = windows.first(where: \.workspaceIsFocused) {
            return .focus(windowId: here.windowId)
        }
        guard !windows.isEmpty else { return .launch }
        return follow ? .moveHere(windowIds: windows.map(\.windowId)) : .newWindow(existing: windows)
    }
}
