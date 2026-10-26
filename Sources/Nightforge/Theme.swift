import SwiftUI

/// "Nightforge": a deep night-blue room lit by a single sodium-vapour lamp.
enum Theme {
    static let night = Color(red: 0x0F / 255, green: 0x14 / 255, blue: 0x1C / 255)   // #0F141C
    static let sodium = Color(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x47 / 255)  // #FFB347
    static let ink = Color(red: 0xF3 / 255, green: 0xF1 / 255, blue: 0xEC / 255)     // #F3F1EC
    static let muted = Color(red: 0x9A / 255, green: 0xA3 / 255, blue: 0xAF / 255)   // #9AA3AF
    static let slate = Color(red: 0x1C / 255, green: 0x24 / 255, blue: 0x30 / 255)   // #1C2430

    /// Wide, heavy display face for titles and the play button.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    static let gutter: CGFloat = 56
}

enum Format {
    static func bytes(_ bytes: Int64) -> String {
        bytes > 0 ? bytes.formatted(.byteCount(style: .file).locale(L10n.locale)) : "–"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func playtime(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) " + L10n.t("min") }
        let hours = Double(minutes) / 60
        let amount = hours.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))
        return amount + " " + (amount == "1" ? L10n.t("hr") : L10n.t("hrs"))
    }
}
