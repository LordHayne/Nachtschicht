import Foundation

/// Display language, picked in Settings. `system` follows the macOS language order.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, german

    static let storageKey = "language"

    var id: String { rawValue }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// `system` resolves to whichever of German or English comes first in the user's preferred languages.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        for code in Locale.preferredLanguages {
            if code.hasPrefix("de") { return .german }
            if code.hasPrefix("en") { return .english }
        }
        return .english
    }

    var label: String {
        switch self {
        case .system: return L10n.t("System")
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }
}

/// English strings are the keys; German is looked up from the table below.
enum L10n {
    static var locale: Locale {
        AppLanguage.current.resolved == .german ? Locale(identifier: "de_AT") : Locale(identifier: "en_US")
    }

    static func t(_ english: String) -> String {
        guard AppLanguage.current.resolved == .german else { return english }
        return german[english] ?? english
    }

    static func t(_ english: String, _ args: CVarArg...) -> String {
        String(format: t(english), locale: locale, arguments: args)
    }

    private static let german: [String: String] = [
        // Library
        "1 game": "1 Spiel",
        "%ld games": "%ld Spiele",
        "Rescan Library": "Bibliothek neu einlesen",
        "Rescan library (⌘R)": "Bibliothek neu einlesen (⌘R)",
        "Settings (⌘,)": "Einstellungen (⌘,)",
        "Last played": "Zuletzt gespielt",
        "Never": "Noch nie",
        "Play time": "Spielzeit",
        "Size": "Belegt",
        "Options for this game (O)": "Optionen für dieses Spiel (O)",
        "Show game folder in Finder": "Spielordner im Finder zeigen",
        "Play": "Spielen",
        "Launching …": "Startet …",
        "Options": "Optionen",
        "Select": "Auswählen",
        "Launch Failed": "Start fehlgeschlagen",
        "No games here yet": "Noch keine Spiele hier",
        "Nachtschicht shows the Steam games installed in your CrossOver bottles. Install Steam in a bottle, download a game there, then rescan your library.":
            "Nachtschicht zeigt die Steam-Spiele, die in deinen CrossOver-Bottles installiert sind. Installiere Steam in einer Bottle, lade dort ein Spiel herunter und lies die Bibliothek dann neu ein.",
        "Scanned: %@": "Durchsucht: %@",
        "Rescan": "Neu einlesen",
        "Choose Another Folder …": "Anderen Ordner wählen …",
        "Use This Folder": "Diesen Ordner verwenden",
        "Choose the folder that contains your bottles, or a single bottle.":
            "Wähle den Ordner mit deinen Bottles oder eine einzelne Bottle.",
        "min": "Min.",
        "hrs": "Std.",

        // Game options
        "Performance HUD in game": "Leistungsanzeige im Spiel",
        "Shows frames per second, frame times and GPU load in the top left corner of the game.": "Zeigt Bilder pro Sekunde, Frametimes und GPU-Last oben links im Spiel.",
        "Launch Options": "Startparameter",
        "e.g. -dx11 -skipintro": "z. B. -dx11 -skipintro",
        "Passed straight to the game at launch.": "Werden beim Start direkt an das Spiel übergeben.",
        "Cancel": "Abbrechen",
        "Save": "Sichern",

        // Settings
        "General": "Allgemein",
        "Language": "Sprache",
        "System": "System",
        "Library": "Bibliothek",
        "Bottles Folder": "Bottles-Ordner",
        "Choose …": "Wählen …",
        "Leave empty to use the default CrossOver folder.": "Leer lassen für den CrossOver-Standardordner.",
        "Launching": "Starten",
        "After Launch": "Nach dem Start",
        "Quit launcher": "Launcher beenden",
        "Hide launcher": "Launcher ausblenden",
        "Keep open": "Offen lassen",
        "Leave empty for CrossOver. For Whisky or your own Wine, enter the path to the wine binary; the bottle is then passed as WINEPREFIX. “Quit launcher” makes sure nothing from Nachtschicht keeps running while you play.":
            "Leer lassen für CrossOver. Für Whisky oder ein eigenes Wine den Pfad zur wine-Datei eintragen, die Bottle wird dann als WINEPREFIX übergeben. „Launcher beenden“ sorgt dafür, dass beim Spielen nichts von Nachtschicht mitläuft.",

        // Setup
        "Preparing your Mac": "Mac wird vorbereitet",
        "Downloading the game engine": "Spiele-Engine wird geladen",
        "Setting up Windows environment": "Windows-Umgebung wird eingerichtet",
        "Installing Steam": "Steam wird installiert",
        "Signing in to Steam": "Bei Steam anmelden",
        "Welcome to Nachtschicht": "Willkommen bei Nachtschicht",
        "Connecting Steam": "Steam wird verbunden",
        "Nachtschicht sets up everything your Windows games need – free, in the background, in a few minutes. You only sign in to Steam.":
            "Nachtschicht richtet alles ein, was deine Windows-Spiele brauchen – kostenlos, im Hintergrund, in wenigen Minuten. Du meldest dich nur bei Steam an.",
        "Connect Steam": "Mit Steam verbinden",
        "Windows games need Rosetta from Apple. macOS asks for your password once to install it; by installing you accept Apple's Rosetta license.":
            "Windows-Spiele brauchen Rosetta von Apple. macOS fragt einmal nach deinem Passwort, um es zu installieren; mit der Installation akzeptierst du Apples Rosetta-Lizenz.",
        "Install Rosetta": "Rosetta installieren",
        "Sign in in the Steam window – with the QR code from the Steam app on your phone or with your password. Nachtschicht never sees your login.":
            "Melde dich im Steam-Fenster an – mit dem QR-Code aus der Steam-App auf deinem Handy oder mit deinem Passwort. Nachtschicht sieht deine Anmeldedaten nie.",
        "Show Steam window again": "Steam-Fenster wieder zeigen",
        "Try again": "Erneut versuchen",
        "Steam is connected": "Steam ist verbunden",
        "Install a game in Steam – it shows up here as soon as it's on your Mac.":
            "Installiere ein Spiel in Steam – es erscheint hier, sobald es auf deinem Mac ist.",
        "Open Steam": "Steam öffnen",
        "The game engine is incomplete. Please try again.": "Die Spiele-Engine ist unvollständig. Bitte versuch es noch einmal.",
        "The Windows environment could not be created.": "Die Windows-Umgebung konnte nicht erstellt werden.",
        "Steam could not be downloaded. Check your internet connection.": "Steam konnte nicht geladen werden. Prüfe deine Internetverbindung.",
        "Steam could not be installed.": "Steam konnte nicht installiert werden.",
        "Steam keeps stopping during its first start. Please try again.": "Steam bricht beim ersten Start immer wieder ab. Bitte versuch es noch einmal.",

        // Downloads
        "Download": "Herunterladen",
        "up to %@": "bis zu %@",
        "Downloading … %ld %%": "Lädt … %ld %%",
        "Preparing download …": "Download wird vorbereitet …",

        "Confirm in the Steam window": "Bestätige im Steam-Fenster",
        "Steam couldn't start %@.": "Steam konnte %@ nicht starten.",

        "VR only": "Nur VR",
        "Needs a VR headset – this game can't be played on a Mac.": "Braucht eine VR-Brille – dieses Spiel läuft nicht auf dem Mac.",

        // Search & library
        "Search": "Suchen",
        "Search (⌘F)": "Suchen (⌘F)",
        "Clear search": "Suche löschen",
        "%ld of %ld games": "%ld von %ld Spielen",
        "No games match “%@”": "Keine Spiele zu „%@“",
        "Whole library (L)": "Ganze Bibliothek (L)",
        "Back to the game (L)": "Zurück zum Spiel (L)",
        "Installed": "Installiert",
        "Downloading": "Wird geladen",
        "In your library": "In deiner Bibliothek",
        "Open": "Öffnen",
        "Back": "Zurück",

        // Uninstall
        "Uninstall": "Deinstallieren",
        "Uninstall …": "Deinstallieren …",
        "Uninstall (⌘⌫)": "Deinstallieren (⌘⌫)",
        "Uninstall %@?": "%@ deinstallieren?",
        "Uninstalling …": "Wird deinstalliert …",
        "Cancel Download": "Download abbrechen",
        "Cancel the download of %@?": "Download von %@ abbrechen?",
        "Keep": "Behalten",
        "This removes the game from your Mac and frees %@. It stays in your Steam library, so you can download it again any time. Saves in the Steam Cloud are kept.":
            "Das Spiel wird von deinem Mac entfernt und gibt %@ frei. Es bleibt in deiner Steam-Bibliothek, du kannst es jederzeit wieder herunterladen. Spielstände in der Steam Cloud bleiben erhalten.",
        "The part downloaded so far is deleted. You can start the download again any time.":
            "Der bisher geladene Teil wird gelöscht. Du kannst den Download jederzeit neu starten.",
        "%@ could not be uninstalled: %@": "%@ konnte nicht deinstalliert werden: %@",

        "Running": "Läuft",
        "Running – switch to game": "Läuft – zum Spiel wechseln",
        "Switch to Game": "Zum Spiel wechseln",

        "Automatic": "Automatisch",
        "Graphics": "Grafik",
        "How DirectX 10/11 reaches the Mac's graphics. DXMT translates straight to Metal and is usually faster; DXVK takes a detour through Vulkan and works with more games.":
            "Wie DirectX 10/11 zur Grafik des Mac kommt. DXMT übersetzt direkt nach Metal und ist meist schneller; DXVK nimmt den Umweg über Vulkan und läuft mit mehr Spielen.",

        // Errors
        "Component list version %ld needs a newer Nachtschicht.": "Komponentenliste Version %ld braucht ein neueres Nachtschicht.",
        "No component list available. Check your internet connection.": "Keine Komponentenliste verfügbar. Prüfe deine Internetverbindung.",
        "The download of %@ is damaged. Please try again.": "Der Download von %@ ist beschädigt. Bitte versuch es noch einmal.",
        "%@ could not be unpacked (tar exit %d).": "%@ konnte nicht entpackt werden (tar-Code %d).",
        "Wine was not found at %@. Install CrossOver or enter the path to your wine binary in Settings.":
            "Wine wurde unter %@ nicht gefunden. Installiere CrossOver oder trag in den Einstellungen den Pfad zu deinem wine ein.",
    ]
}
