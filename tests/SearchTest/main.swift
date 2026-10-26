// Checks Search: initials with numbers, word starts before mid-word hits, punctuation and umlauts:
// tests/SearchTest/run.sh
import Foundation

@main
struct SearchTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let library = [
        "Red Dead Redemption 2", "Baldur's Gate 3", "The Witcher 3: Wild Hunt", "Half-Life 2",
        "Left 4 Dead 2", "S.T.A.L.K.E.R.: Shadow of Chernobyl", "Amnesia: The Dark Descent",
        "ARK: Survival Evolved", "Batman: Arkham City GOTY", "Über Jumper", "Darkest Dungeon",
        "Gate of Thieves", "Counter-Strike 2",
    ]

    /// The names a search finds, best first (library order within a rank).
    static func search(_ query: String) -> [String] {
        let ranked = library.compactMap { name in Search.rank(name: name, query: query).map { (name, $0) } }
        return (0...2).flatMap { rank in ranked.filter { $0.1 == rank }.map(\.0) }
    }

    static func main() {
        check(search("rdr2") == ["Red Dead Redemption 2"], "rdr2: \(search("rdr2"))")
        check(search("bg3") == ["Baldur's Gate 3"], "bg3 (the apostrophe doesn't split): \(search("bg3"))")
        check(search("hl2") == ["Half-Life 2"], "hl2 (the hyphen splits): \(search("hl2"))")
        check(search("l4d2") == ["Left 4 Dead 2"], "l4d2: \(search("l4d2"))")
        check(search("cs2") == ["Counter-Strike 2"], "cs2: \(search("cs2"))")
        check(search("stalker").first == "S.T.A.L.K.E.R.: Shadow of Chernobyl", "stalker: \(search("stalker"))")
        check(search("rdr") == ["Red Dead Redemption 2"], "the start of the initials is enough: \(search("rdr"))")
        check(search("witcher") == ["The Witcher 3: Wild Hunt"], "witcher: \(search("witcher"))")
        check(search("gate 3") == ["Baldur's Gate 3"], "gate 3 needs both words: \(search("gate 3"))")
        check(search("baldurs") == ["Baldur's Gate 3"], "baldurs without the apostrophe: \(search("baldurs"))")
        check(search("über") == ["Über Jumper"] && search("uber") == ["Über Jumper"], "umlauts: \(search("über")) \(search("uber"))")
        check(search("ÜBER") == ["Über Jumper"], "case doesn't matter: \(search("ÜBER"))")
        // "ark": ARK (a word) before Batman: Arkham (a word start) – both rank 0, library order –
        // and Darkest Dungeon / The Dark Descent (mid-word) after them.
        let ark = search("ark")
        check(ark == ["Amnesia: The Dark Descent", "ARK: Survival Evolved", "Batman: Arkham City GOTY", "Darkest Dungeon"].sorted { a, b in
            (Search.rank(name: a, query: "ark")!, library.firstIndex(of: a)!) < (Search.rank(name: b, query: "ark")!, library.firstIndex(of: b)!)
        }, "ark: \(ark)")
        check(ark.prefix(2) == ["ARK: Survival Evolved", "Batman: Arkham City GOTY"], "word starts first: \(ark)")
        check(search("gate").first == "Baldur's Gate 3", "a whole word before nothing else: \(search("gate"))")
        check(search("zzz").isEmpty, "no match, nothing")
        check(search("").count == library.count, "an empty search finds everything")
        check(search("a").contains("Amnesia: The Dark Descent") && !search("a").isEmpty, "one letter: word starts")
        check(Search.initials("Battlefield™ 6") == "b6", "marks like ™ drop out: \(Search.initials("Battlefield™ 6"))")

        print(failures == 0 ? "✓ Search" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
