// Checks Compatibility: which level each kind of game gets, the chips read from test notes, every
// game in the profile list getting a level, and the badge colours' contrast:
// tests/CompatibilityTest/run.sh
import AppKit
import SwiftUI

@main
struct CompatibilityTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func profile(_ json: String) -> GameProfile {
        try! JSONDecoder().decode(GameProfile.self, from: Data(json.utf8))
    }

    static func analysis(_ apis: Set<GameAnalysis.API>, antiCheat: [String] = []) -> GameAnalysis {
        var analysis = GameAnalysis()
        analysis.apis = apis
        analysis.antiCheat = antiCheat
        return analysis
    }

    static func level(_ facts: Compatibility.Facts) -> Compatibility.Level { Compatibility.rate(facts).level }

    /// WCAG contrast of two sRGB colours.
    static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ c: NSColor) -> Double {
            func channel(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    static func srgb(_ color: Color) -> NSColor { NSColor(color).usingColorSpace(.sRGB)! }

    /// `color` at `opacity` over `base`, as the badge's tint lies on the night background.
    static func blend(_ color: NSColor, _ opacity: CGFloat, over base: NSColor) -> NSColor {
        NSColor(srgbRed: color.redComponent * opacity + base.redComponent * (1 - opacity),
                green: color.greenComponent * opacity + base.greenComponent * (1 - opacity),
                blue: color.blueComponent * opacity + base.blueComponent * (1 - opacity), alpha: 1)
    }

    static func main() throws {
        typealias Facts = Compatibility.Facts
        let blocked = AntiCheatBlock(antiCheat: ["BattlEye"], geforceNow: nil)
        let streamable = AntiCheatBlock(antiCheat: ["BattlEye"], geforceNow: "42")

        // What stops a game.
        check(level(Facts(vrOnly: true)) == .no, "VR only doesn't run")
        check(level(Facts(antiCheatBlock: blocked)) == .no, "blocking anti-cheat doesn't run")
        let cloud = Compatibility.rate(Facts(antiCheatBlock: streamable))
        check(cloud.level == .no && cloud.note?.contains("GeForce Now") == true, "a streamable game points to GeForce Now")
        check(level(Facts(platform: .mac, antiCheatBlock: blocked)) == .great, "the Mac version isn't stopped by the Windows anti-cheat")
        check(level(Facts(platform: .mac, vrOnly: true)) == .no, "VR only stays no, even on the Mac version")

        // What a game needs.
        check(level(Facts(analysis: analysis([.d3d12]))) == .tweaks, "DirectX 12 only runs with tweaks")
        let online = Compatibility.rate(Facts(analysis: analysis([.d3d11], antiCheat: ["Easy Anti-Cheat"])))
        check(online.level == .tweaks && online.note?.contains("Easy Anti-Cheat") == true, "online-only anti-cheat runs with tweaks and says which")
        let cleared = profile(#"{"source": "mac", "antiCheat": []}"#)
        check(level(Facts(profile: cleared, analysis: analysis([.d3d11], antiCheat: ["Easy Anti-Cheat"]))) == .great,
              "a Mac profile clearing the anti-cheat runs great")
        let umu = profile(#"{"source": "umu", "winetricks": ["xact"]}"#)
        check(level(Facts(profile: umu)) == .tweaks, "an umu profile with fixes runs with tweaks")
        check(level(Facts(profile: profile(#"{"source": "umu", "saves": []}"#))) == .untested, "save folders alone aren't a fix")
        check(level(Facts(learnedFixes: true)) == .tweaks, "learned fixes run with tweaks")
        check(level(Facts(launch: (index: 1, confirmed: true))) == .tweaks, "a fallback way to start runs with tweaks")

        // What shows it runs.
        check(level(Facts(platform: .mac)) == .great, "the Mac version runs great")
        let mac = Compatibility.rate(Facts(profile: profile(#"{"source": "umu+mac", "graphics": "dxmt", "note": "Tested on M5 and M3 Pro, M5 again"}"#)))
        check(mac.level == .great, "Nightforge's own profile runs great, fixes and all")
        check(mac.testedOn == ["M5", "M3 Pro"], "chips from the note: \(mac.testedOn)")
        check(level(Facts(launch: (index: 0, confirmed: true))) == .great, "a clean confirmed start runs great")
        check(level(Facts(launch: (index: 0, confirmed: false))) == .untested, "an unconfirmed start stays untested")
        check(level(Facts()) == .untested, "nothing known is untested")
        check(Compatibility.chips(in: "MetalFX on, 4K") == [], "no chips in an ordinary note")

        // Every game in the shipped list gets a level, and the list's own Mac profiles run great.
        struct Document: Decodable { let games: [String: GameProfile] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var counts: [Compatibility.Level: Int] = [:]
        for (_, game) in document.games {
            let rating = Compatibility.rate(Facts(profile: game))
            counts[rating.level, default: 0] += 1
            if game.source == "mac" && game.antiCheat == nil { check(rating.level == .great, "\(game.name ?? "?"): Mac profile runs great") }
        }
        check(counts.values.reduce(0, +) == document.games.count, "every game has a level")
        if let l4d2 = document.games["550"] { check(Compatibility.rate(Facts(profile: l4d2)).testedOn == ["M5"], "Left 4 Dead 2 tested on M5") }
        print("Profile list: " + Compatibility.Level.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: ", "))

        // Badge text on its tint over night, and on night itself: at least 4.5:1.
        let night = srgb(Theme.night)
        for level in Compatibility.Level.allCases {
            let color = srgb(level.color)
            let onNight = contrast(color, night), onTint = contrast(color, blend(color, 0.15, over: night))
            check(onNight >= 4.5 && onTint >= 4.5, "\(level.rawValue): contrast \(onNight) on night, \(onTint) on its tint")
        }
        check(Set(Compatibility.Level.allCases.map(\.symbol)).count == 4, "every level has its own icon")

        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("✓ Compatibility")
    }
}
