import Foundation

func runSummonTests() {
    let here = AeroWindow(windowId: 10, workspace: "1", workspaceIsFocused: true)
    let elsewhereA = AeroWindow(windowId: 20, workspace: "S", workspaceIsFocused: false)
    let elsewhereB = AeroWindow(windowId: 21, workspace: "M", workspaceIsFocused: false)

    test("Summon: no windows → launch, regardless of follow") {
        expectEqual(SummonPlan.decide(windows: [], follow: false), .launch)
        expectEqual(SummonPlan.decide(windows: [], follow: true), .launch)
    }

    test("Summon: a window here → focus it, regardless of follow or other windows") {
        expectEqual(SummonPlan.decide(windows: [here], follow: false), .focus(windowId: 10))
        expectEqual(SummonPlan.decide(windows: [here], follow: true), .focus(windowId: 10))
        expectEqual(SummonPlan.decide(windows: [elsewhereA, here, elsewhereB], follow: true), .focus(windowId: 10))
        expectEqual(SummonPlan.decide(windows: [elsewhereA, here], follow: false), .focus(windowId: 10))
    }

    test("Summon: only elsewhere, default → new window here") {
        expectEqual(SummonPlan.decide(windows: [elsewhereA], follow: false), .newWindow(existing: [elsewhereA]))
        expectEqual(SummonPlan.decide(windows: [elsewhereA, elsewhereB], follow: false), .newWindow(existing: [elsewhereA, elsewhereB]))
    }

    test("Summon: only elsewhere, follow → move all of them here") {
        expectEqual(SummonPlan.decide(windows: [elsewhereA], follow: true), .moveHere(windowIds: [20]))
        expectEqual(SummonPlan.decide(windows: [elsewhereA, elsewhereB], follow: true), .moveHere(windowIds: [20, 21]))
    }

    test("Summon: decodes aerospace list-windows JSON") {
        let json = """
        [
          {"window-id": 4711, "workspace": "S", "workspace-is-focused": false},
          {"window-id": 4712, "workspace": "1", "workspace-is-focused": true}
        ]
        """
        let windows = try AeroWindow.decode(json: Data(json.utf8))
        expectEqual(windows, [
            AeroWindow(windowId: 4711, workspace: "S", workspaceIsFocused: false),
            AeroWindow(windowId: 4712, workspace: "1", workspaceIsFocused: true),
        ])
        expectEqual(try AeroWindow.decode(json: Data("[]".utf8)), [])
    }
}
