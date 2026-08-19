import Foundation

/// Ranks apps against what the user has typed so far.
enum Matcher {
    /// Lower is better; nil means no match. An empty query matches everything.
    static func score(query rawQuery: String, candidate rawCandidate: String) -> Int? {
        let query = normalize(rawQuery).lowercased()
        guard !query.isEmpty else { return 0 }
        // Fold diacritics but keep case for the word split, so "WezTerm" still
        // exposes "term" as a word; the lowercased copy serves prefix/contains.
        let folded = normalize(rawCandidate)
        let candidate = Candidate(lowercased: folded.lowercased(), words: words(folded))

        var best = wholeQueryScore(query: query, candidate: candidate)

        // "sys set" — every token has to land somewhere; the worst token decides.
        let tokens = query.split(separator: " ").map(String.init)
        if tokens.count > 1 {
            var worst = 0
            var allMatch = true
            for token in tokens {
                guard let s = wholeQueryScore(query: token, candidate: candidate) else {
                    allMatch = false
                    break
                }
                worst = max(worst, s)
            }
            if allMatch { best = min(best ?? Int.max, worst) }
        }
        return best
    }

    private struct Candidate {
        let lowercased: String
        let words: [String]
    }

    private static func wholeQueryScore(query: String, candidate: Candidate) -> Int? {
        if candidate.lowercased == query { return 0 }
        if candidate.lowercased.hasPrefix(query) { return 1 }
        if candidate.words.contains(where: { $0.hasPrefix(query) }) { return 2 }
        let acronym = String(candidate.words.compactMap(\.first))
        if acronym.hasPrefix(query) { return 3 }
        if candidate.lowercased.contains(query) { return 4 }
        if isSubsequence(query, of: candidate.lowercased) { return 5 }
        return nil
    }

    /// Strips diacritics and surrounding whitespace; case is left to the caller.
    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Splits on anything that is not a letter or digit, and on lower→upper case
    /// boundaries so "iTerm" and "WezTerm" expose "term" as a word.
    static func words(_ s: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false
        for ch in s {
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase, previousWasLower, !current.isEmpty {
                    words.append(current.lowercased())
                    current = ""
                }
                current.append(ch)
                previousWasLower = ch.isLowercase
            } else {
                if !current.isEmpty { words.append(current.lowercased()) }
                current = ""
                previousWasLower = false
            }
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return words
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = needle.makeIterator()
        var next = it.next()
        for ch in haystack {
            guard let n = next else { return true }
            if ch == n { next = it.next() }
        }
        return next == nil
    }
}

/// An app the launcher can offer.
struct InstalledApp: Equatable, Hashable {
    let bundleId: String
    let name: String
    let url: URL
}

/// A match with the tie-breakers laid out, so callers can sort without re-scoring.
struct RankedApp: Equatable {
    let app: InstalledApp
    let score: Int
    let usage: Int
}

extension Matcher {
    /// Every app matching `query`, best first. Ties go to the more-used app, then
    /// the shorter name, then alphabetically — so "s" lists Slack above Safari once
    /// Slack has been launched from here a few times. With nothing typed, the list is
    /// most-used first and then plainly alphabetical.
    static func rank(
        _ apps: [InstalledApp],
        query: String,
        aliases: (InstalledApp) -> [String] = { _ in [] },
        usage: (InstalledApp) -> Int = { _ in 0 }
    ) -> [RankedApp] {
        var ranked: [RankedApp] = []
        for app in apps {
            let candidates = [app.name] + aliases(app)
            guard let best = candidates.compactMap({ score(query: query, candidate: $0) }).min() else { continue }
            ranked.append(RankedApp(app: app, score: best, usage: usage(app)))
        }
        let preferShort = !normalize(query).isEmpty
        return ranked.sorted { a, b in
            if a.score != b.score { return a.score < b.score }
            if a.usage != b.usage { return a.usage > b.usage }
            if preferShort, a.app.name.count != b.app.name.count { return a.app.name.count < b.app.name.count }
            let byName = a.app.name.localizedCaseInsensitiveCompare(b.app.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.app.bundleId < b.app.bundleId
        }
    }
}
