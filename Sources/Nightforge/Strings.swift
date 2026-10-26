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
        "Something went wrong": "Etwas ist schiefgelaufen",

        // Steam store & Mac versions
        "View in Steam Store": "Im Steam-Store ansehen",
        "In the Steam Store": "Im Steam-Store",
        "Price": "Preis",
        "Free": "Kostenlos",
        "Coming soon": "Demnächst",

        // Performance
        "Frame limit": "FPS-Limit",
        "Off": "Aus",
        "MetalFX upscaling": "MetalFX-Hochskalierung",
        "On": "An",
        "Automatic (%@)": "Automatisch (%@)",
        "Automatic follows “Sharp & smooth” in Settings. The frame limit keeps frames even; MetalFX upscales the picture to full Retina sharpness (not with WineD3D) – set a lower resolution in the game for more FPS.":
            "Automatisch folgt „Schön & flüssig“ in den Einstellungen. Das FPS-Limit hält die Bilder gleichmäßig; MetalFX skaliert das Bild auf volle Retina-Schärfe hoch (nicht mit WineD3D) – für mehr FPS im Spiel eine niedrigere Auflösung wählen.",
        "Sharp & smooth": "Schön & flüssig",
        "Update to %@": "Auf %@ aktualisieren",
        "Updating …": "Wird aktualisiert …",
        "Installs the new version and restarts Nightforge. Your games and settings stay.":
            "Installiert die neue Version und startet Nightforge neu. Deine Spiele und Einstellungen bleiben.",
        "The update could not be downloaded. Check your internet connection.":
            "Das Update konnte nicht geladen werden. Prüfe deine Internetverbindung.",
        "The update download is damaged. Please try again.": "Der Update-Download ist beschädigt. Bitte versuch es noch einmal.",
        "The update isn't signed correctly, so it wasn't installed.":
            "Das Update ist nicht korrekt signiert und wurde deshalb nicht installiert.",
        "Nightforge can't replace itself in this folder. Download the update from the release page instead.":
            "Nightforge kann sich in diesem Ordner nicht selbst ersetzen. Lade das Update stattdessen von der Release-Seite.",
        "This game didn't start with %@, so Nightforge uses %@ for it automatically.":
            "Mit %@ ist dieses Spiel nicht gestartet, deshalb nutzt Nightforge dafür automatisch %@.",
        "Starting again with %@ …": "Neuer Start mit %@ …",
        "Setting up .NET for the game …": ".NET wird für das Spiel eingerichtet …",
        "Starts through another launcher: %@. Under Wine its window can stay empty or fail to sign in; if the game doesn't come up, a problem report helps.":
            "Startet über einen weiteren Launcher: %@. Unter Wine kann dessen Fenster leer bleiben oder die Anmeldung scheitern; wenn das Spiel nicht kommt, hilft eine Problemmeldung.",
        "Draws some windows (sign-in, news) with Microsoft WebView2, which can stay empty on a Mac.":
            "Zeigt manche Fenster (Anmeldung, News) mit Microsoft WebView2, die auf dem Mac leer bleiben können.",
        "For games that draw through Vulkan, on the XDR display. Off by default: under Wine HDR mostly looks washed out.":
            "Für Spiele, die über Vulkan zeichnen, auf dem XDR-Display. Standardmäßig aus: Unter Wine wirkt HDR meist blass.",
        "%@ didn't start": "%@ ist nicht gestartet",
        "Report problem": "Problem melden",
        "Report problem …": "Problem melden …",
        "It ended right after starting, with every way Nightforge knows: %@. A problem report helps get it running – it opens on GitHub, filled in with what Nightforge found.":
            "Es hat sich direkt nach dem Start beendet, mit jedem Weg, den Nightforge kennt: %@. Eine Problemmeldung hilft, es zum Laufen zu bringen – sie öffnet sich auf GitHub, schon ausgefüllt mit dem, was Nightforge herausgefunden hat.",
        "This game uses DirectX 12 only, which runs on a Mac in part at best.":
            "Dieses Spiel nutzt nur DirectX 12, das auf dem Mac bestenfalls teilweise läuft.",
        "Uses %@: online play with it doesn't work on a Mac, single player usually does.":
            "Nutzt %@: Online-Spiel damit geht auf dem Mac nicht, Einzelspieler meistens schon.",
        "Opens a problem report on GitHub, filled in with what Nightforge knows about the game. Nothing is sent until you submit it there.":
            "Öffnet eine Problemmeldung auf GitHub, ausgefüllt mit dem, was Nightforge über das Spiel weiß. Gesendet wird erst, wenn du sie dort abschickst.",
        "This game uses %@. DXMT translates DirectX 10/11 straight to Metal and is usually faster; DXVK takes a detour through Vulkan and works with more games. Automatic switches by itself if a game doesn't start.":
            "Dieses Spiel nutzt %@. DXMT übersetzt DirectX 10/11 direkt in Metal und ist meist schneller; DXVK nimmt den Umweg über Vulkan und läuft mit mehr Spielen. Automatisch wechselt von selbst, wenn ein Spiel nicht startet.",
        "This game uses %@. DXVK is usually faster; WineD3D runs some older games DXVK can't. Automatic switches by itself if a game doesn't start.":
            "Dieses Spiel nutzt %@. DXVK ist meist schneller; WineD3D bringt manche ältere Spiele zum Laufen, die mit DXVK nicht gehen. Automatisch wechselt von selbst, wenn ein Spiel nicht startet.",
        "This game uses %@ and draws without a DirectX layer, so there's nothing to choose here.":
            "Dieses Spiel nutzt %@ und braucht keine DirectX-Übersetzung, hier gibt es also nichts auszuwählen.",
        "Advanced": "Erweitert",
        "CrossOver, Whisky and your own Wine": "CrossOver, Whisky und eigenes Wine",
        "Nightforge brings everything it needs. Fill this in only to also show games from CrossOver or Whisky bottles: leave Wine empty for CrossOver, or enter the path to the wine binary of Whisky or your own Wine.":
            "Nightforge bringt alles selbst mit. Nur ausfüllen, wenn auch Spiele aus CrossOver- oder Whisky-Bottles erscheinen sollen: Wine leer lassen für CrossOver, sonst den Pfad zur wine-Datei von Whisky oder deinem eigenen Wine eintragen.",
        "Every game gets Apple's MetalFX upscaling to full Retina sharpness and an even frame rate that fits your display (60 FPS on a 120 Hz screen). Change it per game in its options.":
            "Jedes Spiel bekommt Apples MetalFX-Hochskalierung auf volle Retina-Schärfe und eine gleichmäßige Bildrate passend zum Bildschirm (60 FPS auf einem 120-Hz-Display). Pro Spiel in dessen Optionen änderbar.",
        "Low Power Mode is on – games run much slower with it.": "Der Stromsparmodus ist an – Spiele laufen damit deutlich langsamer.",
        "Battery Settings": "Batterie-Einstellungen",
        "Steam also has a Mac version": "Steam hat auch eine Mac-Version",
        "Steam also has a Mac version of this game. Nightforge uses it once you own the game, if it runs on current Macs.":
            "Steam hat dieses Spiel auch als Mac-Version. Nightforge nutzt sie, sobald dir das Spiel gehört – wenn sie auf aktuellen Macs läuft.",

        // Mac versions through Steam for Mac
        "Version": "Version",
        "Uses the Mac version": "Nutzt die Mac-Version",
        "Nightforge uses the Mac version of this game, made for Apple silicon – no Windows translation needed.":
            "Nightforge nutzt die Mac-Version dieses Spiels, gemacht für Apple Silicon – ganz ohne Windows-Übersetzung.",
        "Nightforge uses the Mac version of this game – no Windows translation needed. It's made for Intel Macs, so Rosetta runs it.":
            "Nightforge nutzt die Mac-Version dieses Spiels – ganz ohne Windows-Übersetzung. Sie ist für Intel-Macs gemacht, deshalb läuft sie über Rosetta.",
        "There's a Mac version of this game that runs without any Windows translation. Nightforge switches to it as soon as it's on your Mac – until then you play the Windows version.":
            "Von diesem Spiel gibt es eine Mac-Version, die ganz ohne Windows-Übersetzung läuft. Nightforge wechselt zu ihr, sobald sie auf deinem Mac ist – bis dahin spielst du die Windows-Version.",
        "Load Mac Version (%@)": "Mac-Version laden (%@)",
        "Load Mac Version": "Mac-Version laden",
        "Loading the Mac version … %ld %%": "Mac-Version wird geladen … %ld %%",
        "Preparing the Mac version …": "Mac-Version wird vorbereitet …",
        "Steam also has a Mac version, but the Windows version runs better, so Nightforge uses that.":
            "Steam hat auch eine Mac-Version, aber die Windows-Version läuft besser, deshalb nutzt Nightforge diese.",
        "Steam's Mac version of this game is too old for current Macs, so Nightforge uses the Windows version.":
            "Die Mac-Version dieses Spiels auf Steam ist zu alt für aktuelle Macs, deshalb nutzt Nightforge die Windows-Version.",
        "The Mac version didn't start, so Nightforge uses the Windows version. You can switch back in the game's options.":
            "Die Mac-Version ist nicht gestartet, deshalb nutzt Nightforge die Windows-Version. In den Optionen des Spiels kannst du zurückwechseln.",
        "The Windows version is still installed and takes %@.": "Die Windows-Version ist noch installiert und belegt %@.",
        "Remove …": "Entfernen …",
        "Remove": "Entfernen",
        "Remove the Windows version of %@?": "Windows-Version von %@ entfernen?",
        "Nightforge uses the Mac version of this game now. Removing the Windows version frees %@; you can switch back and download it again any time.":
            "Nightforge nutzt jetzt die Mac-Version dieses Spiels. Das Entfernen der Windows-Version gibt %@ frei; du kannst jederzeit zurückwechseln und sie wieder herunterladen.",
        "Mac runs Steam's native Mac version through Steam for Mac, without any Windows translation; its graphics settings are in the game itself. Windows runs the Windows version through Wine. Automatic takes the Mac version when it runs on current Macs.":
            "Mac startet die echte Mac-Version über Steam für Mac, ganz ohne Windows-Übersetzung; ihre Grafikeinstellungen findest du im Spiel selbst. Windows startet die Windows-Version über Wine. Automatisch nimmt die Mac-Version, wenn sie auf aktuellen Macs läuft.",
        "Mac runs Steam's native Mac version through Steam for Mac, without any Windows translation. Windows runs the Windows version through Wine. Automatic takes the Mac version when it runs on current Macs.":
            "Mac startet die echte Mac-Version über Steam für Mac, ganz ohne Windows-Übersetzung. Windows startet die Windows-Version über Wine. Automatisch nimmt die Mac-Version, wenn sie auf aktuellen Macs läuft.",
        "Steam for Mac": "Steam für Mac",
        "%@ has a Mac version. It runs without any Windows translation, so it usually looks and runs better. To get it, Nightforge sets up Valve's Steam for Mac – once, in a few minutes.":
            "%@ gibt es auch als Mac-Version. Sie läuft ganz ohne Windows-Übersetzung und sieht deshalb meist besser aus und läuft flüssiger. Dafür richtet Nightforge Valves Steam für Mac ein – einmalig, in wenigen Minuten.",
        "Downloading Steam for Mac": "Steam für Mac wird geladen",
        "You sign in in Steam's own window – Nightforge never sees your login. By installing you accept Valve's Steam Subscriber Agreement.":
            "Du meldest dich in Steams eigenem Fenster an – Nightforge sieht deine Anmeldedaten nie. Mit der Installation akzeptierst du Valves Steam-Nutzungsvertrag.",
        "Steam updates itself first, then asks you to sign in – with the QR code from the Steam app on your phone or with your password. Nightforge never sees your login.":
            "Steam aktualisiert sich zuerst selbst und fragt dann nach deiner Anmeldung – mit dem QR-Code aus der Steam-App auf deinem Handy oder mit deinem Passwort. Nightforge sieht deine Anmeldedaten nie.",
        "Use the Windows Version": "Windows-Version verwenden",
        "Set Up Steam for Mac": "Steam für Mac einrichten",
        "Starting Steam for Mac …": "Steam für Mac startet …",
        "Controller": "Controller",
        "Full": "Voll",
        "Partial": "Teilweise",
        "Mouse & keyboard": "Maus & Tastatur",
        "Full controller support – playable from the couch": "Volle Controller-Unterstützung – spielbar von der Couch",
        "Partial controller support – some menus need a mouse or keyboard":
            "Teilweise Controller-Unterstützung – manche Menüs brauchen Maus oder Tastatur",
        "Made for mouse and keyboard": "Für Maus und Tastatur gemacht",
        "Signing in to Steam …": "Anmeldung bei Steam …",
        "%@ is still running and needs Steam. Steam can be signed in only once at a time, so quit the game first.":
            "%@ läuft noch und braucht Steam. Steam kann immer nur einmal angemeldet sein – beende das Spiel zuerst.",
        "Sign in in the Steam window": "Melde dich im Steam-Fenster an",
        "Steam for Mac could not be downloaded. Check your internet connection.":
            "Steam für Mac konnte nicht geladen werden. Prüfe deine Internetverbindung.",
        "The Steam for Mac download isn't signed by Valve, so it wasn't installed.":
            "Der Download von Steam für Mac ist nicht von Valve signiert und wurde deshalb nicht installiert.",
        "Steam for Mac could not be installed.": "Steam für Mac konnte nicht installiert werden.",
        "No games here yet": "Noch keine Spiele hier",
        "Nightforge shows the Steam games installed in your CrossOver bottles. Install Steam in a bottle, download a game there, then rescan your library.":
            "Nightforge zeigt die Steam-Spiele, die in deinen CrossOver-Bottles installiert sind. Installiere Steam in einer Bottle, lade dort ein Spiel herunter und lies die Bibliothek dann neu ein.",
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
        "After Launch": "Nach dem Start",
        "Quit launcher": "Launcher beenden",
        "Hide launcher": "Launcher ausblenden",
        "Keep open": "Offen lassen",

        // Setup
        "Preparing your Mac": "Mac wird vorbereitet",
        "Downloading the game engine": "Spiele-Engine wird geladen",
        "Setting up Windows environment": "Windows-Umgebung wird eingerichtet",
        "Installing Steam": "Steam wird installiert",
        "Signing in to Steam": "Bei Steam anmelden",
        "Welcome to Nightforge": "Willkommen bei Nightforge",
        "Connecting Steam": "Steam wird verbunden",
        "Nightforge sets up everything your Windows games need – free, in the background, in a few minutes. You only sign in to Steam.":
            "Nightforge richtet alles ein, was deine Windows-Spiele brauchen – kostenlos, im Hintergrund, in wenigen Minuten. Du meldest dich nur bei Steam an.",
        "Connect Steam": "Mit Steam verbinden",
        "Windows games need Rosetta from Apple. macOS asks for your password once to install it; by installing you accept Apple's Rosetta license.":
            "Windows-Spiele brauchen Rosetta von Apple. macOS fragt einmal nach deinem Passwort, um es zu installieren; mit der Installation akzeptierst du Apples Rosetta-Lizenz.",
        "Install Rosetta": "Rosetta installieren",
        "Sign in in the Steam window – with the QR code from the Steam app on your phone or with your password. Nightforge never sees your login.":
            "Melde dich im Steam-Fenster an – mit dem QR-Code aus der Steam-App auf deinem Handy oder mit deinem Passwort. Nightforge sieht deine Anmeldedaten nie.",
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
        "Setting up the game …": "Spiel wird eingerichtet …",
        "Restarting Steam …": "Steam wird neu gestartet …",
        "Steam couldn't start %@.": "Steam konnte %@ nicht starten.",

        "VR only": "Nur VR",
        "Doesn't run on a Mac": "Läuft nicht auf dem Mac",
        "This game's anti-cheat (%@) stops it on a Mac: it needs Windows itself, and getting around it would get your account banned.":
            "Der Anti-Cheat dieses Spiels (%@) verhindert es auf dem Mac: Er braucht Windows selbst, und ihn zu umgehen würde deinen Account sperren lassen.",
        "Nightforge plays it on GeForce Now, NVIDIA's cloud gaming, with your Steam copy (own NVIDIA account; free sessions last an hour).":
            "Nightforge spielt es über GeForce Now, NVIDIAs Cloud-Gaming, mit deinem Steam-Spiel (eigenes NVIDIA-Konto; kostenlos je eine Stunde).",
        "Play on GeForce Now": "Über GeForce Now spielen",
        "Plays on GeForce Now – its anti-cheat doesn't run on a Mac": "Läuft über GeForce Now – sein Anti-Cheat läuft nicht auf dem Mac",
        "Play %@ on GeForce Now?": "%@ über GeForce Now spielen?",
        "Continue to GeForce Now": "Weiter zu GeForce Now",
        "Its anti-cheat doesn't run on a Mac, so it runs on NVIDIA's servers and streams to your Mac – with the copy you own on Steam. The first time, sign in to GeForce Now with an NVIDIA account and link Steam there. Free play lasts an hour at a time, with ads and a queue; GeForce Now's paid plans lift that.":
            "Sein Anti-Cheat läuft nicht auf dem Mac, deshalb läuft das Spiel auf NVIDIAs Servern und wird auf deinen Mac gestreamt – mit deinem Steam-Spiel. Beim ersten Mal meldest du dich bei GeForce Now mit einem NVIDIA-Konto an und verknüpfst dort Steam. Kostenlos geht es je eine Stunde, mit Werbung und Warteschlange; die Bezahl-Tarife von GeForce Now heben das auf.",
        "Anti-cheat stops this game on a Mac": "Anti-Cheat verhindert dieses Spiel auf dem Mac",
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

        "Performance HUD in games": "Leistungsanzeige in Spielen",
        "Shows frames per second and frame times while you play. Takes effect at the next game start.":
            "Zeigt Bilder pro Sekunde und Frametimes beim Spielen. Gilt ab dem nächsten Spielstart.",

        "Game Mode": "Spielmodus",
        "Gives games priority on the CPU and graphics and halves Bluetooth latency for controllers and headphones. Turn it off if a game's sound crackles.":
            "Gibt Spielen Vorrang bei CPU und Grafik und halbiert die Bluetooth-Latenz für Controller und Kopfhörer. Schalte ihn aus, wenn der Ton eines Spiels knackt.",

        // Errors
        "Component list version %ld needs a newer Nightforge.": "Komponentenliste Version %ld braucht ein neueres Nightforge.",
        "No component list available. Check your internet connection.": "Keine Komponentenliste verfügbar. Prüfe deine Internetverbindung.",
        "The download of %@ is damaged. Please try again.": "Der Download von %@ ist beschädigt. Bitte versuch es noch einmal.",
        "%@ could not be unpacked (tar exit %d).": "%@ konnte nicht entpackt werden (tar-Code %d).",
        "Wine was not found at %@. Install CrossOver or enter the path to your wine binary in Settings.":
            "Wine wurde unter %@ nicht gefunden. Installiere CrossOver oder trag in den Einstellungen den Pfad zu deinem wine ein.",
    ]
}
