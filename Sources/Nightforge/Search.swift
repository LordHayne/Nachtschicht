import Foundation

/// How a search finds games, the way players type: whole words and word starts ("witcher",
/// "gate 3"), bits of words ("dark" in "Darkest Dungeon"), and initials with their numbers
/// ("rdr2", "bg3", "hl2", "l4d2"). Case, accents and punctuation don't matter.
enum Search {
    /// Lowercased, without accents and punctuation: "Baldur's Gate 3" → "baldurs gate 3".
    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(String.init).joined()
    }

    /// The name's words: an apostrophe joins ("Baldur's"), any other mark splits ("Half-Life",
    /// "S.T.A.L.K.E.R.", "Ashes: Escalation").
    static func words(_ name: String) -> [String] {
        let joined = name.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let folded = joined.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// First letters, numbers whole: "Red Dead Redemption 2" → "rdr2", "Left 4 Dead 2" → "l4d2".
    static func initials(_ name: String) -> String {
        words(name).map { word in word.allSatisfy(\.isNumber) ? word : String(word.prefix(1)) }.joined()
    }

    /// How well `query` matches `name`, best first: 0 every word of the search starts a word of
    /// the name, 1 the search is the name's initials (or how they start), 2 its words are
    /// somewhere in the name; nil no match. An empty search matches everything.
    static func rank(name: String, query: String) -> Int? {
        let terms = key(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return 0 }
        let nameWords = words(name)
        if terms.allSatisfy({ term in nameWords.contains { $0.hasPrefix(term) } }) { return 0 }
        let compact = terms.joined()
        if compact.count >= 2, initials(name).hasPrefix(compact) { return 1 }
        let nameKey = key(name)
        if terms.allSatisfy({ nameKey.contains($0) }) { return 2 }
        return nil
    }
}
