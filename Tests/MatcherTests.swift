import Foundation

func runMatcherTests() {
    func app(_ name: String, _ id: String? = nil) -> InstalledApp {
        InstalledApp(bundleId: id ?? "com.test.\(name.lowercased().replacingOccurrences(of: " ", with: ""))", name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    test("Matcher: tiers") {
        expectEqual(Matcher.score(query: "", candidate: "Anything"), 0)
        expectEqual(Matcher.score(query: "slack", candidate: "Slack"), 0)
        expectEqual(Matcher.score(query: "sla", candidate: "Slack"), 1)
        expectEqual(Matcher.score(query: "set", candidate: "System Settings"), 2)
        expectEqual(Matcher.score(query: "term", candidate: "WezTerm"), 2, "camelCase boundary counts as a word start")
        expectEqual(Matcher.score(query: "vsc", candidate: "Visual Studio Code"), 3)
        expectEqual(Matcher.score(query: "ss", candidate: "System Settings"), 3)
        expectEqual(Matcher.score(query: "rom", candidate: "Google Chrome"), 4)
        expectEqual(Matcher.score(query: "gcm", candidate: "Google Chrome"), 5)
        expectNil(Matcher.score(query: "xyz", candidate: "Google Chrome"))
        expectNil(Matcher.score(query: "slackk", candidate: "Slack"))
    }

    test("Matcher: case and diacritics are ignored") {
        expectEqual(Matcher.score(query: "SLACK", candidate: "slack"), 0)
        expectEqual(Matcher.score(query: "cafe", candidate: "Café"), 0)
        expectEqual(Matcher.score(query: "  sla ", candidate: "Slack"), 1)
    }

    test("Matcher: multi-token queries") {
        expectEqual(Matcher.score(query: "system se", candidate: "System Settings"), 1, "still a plain prefix")
        expectEqual(Matcher.score(query: "sys set", candidate: "System Settings"), 2)
        expectEqual(Matcher.score(query: "set sys", candidate: "System Settings"), 2, "order does not matter")
        expectNil(Matcher.score(query: "sys xyz", candidate: "System Settings"))
    }

    test("Matcher: rank prefers score, then usage, then shorter name, then alphabet") {
        let apps = [app("Safari"), app("Slack"), app("System Settings"), app("Sublime Text"), app("Google Chrome"), app("Screen Sharing")]
        let usage = ["com.test.slack": 5]
        let ranked = Matcher.rank(apps, query: "s", usage: { usage[$0.bundleId] ?? 0 }).map(\.app.name)
        expectEqual(ranked, ["Slack", "Safari", "Sublime Text", "Screen Sharing", "System Settings"])

        let bySubsequence = Matcher.rank(apps, query: "sc", usage: { usage[$0.bundleId] ?? 0 }).map(\.app.name)
        expectEqual(bySubsequence, ["Screen Sharing", "Slack"], "word-prefix beats subsequence; no 'c' in the rest")
    }

    test("Matcher: empty query lists everything, most used first then alphabetical") {
        let apps = [app("Zed"), app("Alpha"), app("Slack")]
        let ranked = Matcher.rank(apps, query: "", usage: { $0.name == "Slack" ? 2 : 0 }).map(\.app.name)
        expectEqual(ranked, ["Slack", "Alpha", "Zed"])
    }

    test("Matcher: aliases match too, at their own score") {
        let apps = [app("Google Chrome"), app("Slack")]
        let ranked = Matcher.rank(apps, query: "brow", aliases: { $0.name == "Google Chrome" ? ["browser"] : [] })
        expectEqual(ranked.map(\.app.name), ["Google Chrome"])
        expectEqual(ranked.first?.score, 1)
    }

    test("Matcher: words") {
        expectEqual(Matcher.words("Visual Studio Code"), ["visual", "studio", "code"])
        expectEqual(Matcher.words("WezTerm"), ["wez", "term"])
        expectEqual(Matcher.words("iTerm2"), ["i", "term2"])
        expectEqual(Matcher.words("1Password"), ["1password"])
        expectEqual(Matcher.words("Claude Code URL Handler"), ["claude", "code", "url", "handler"])
    }
}
