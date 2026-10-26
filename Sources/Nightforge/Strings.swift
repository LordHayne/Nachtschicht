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
        "Move": "Bewegen",
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
        "This game didn't start the usual way, so Nightforge now starts it another way, automatically.":
            "Dieses Spiel ist auf dem üblichen Weg nicht gestartet, deshalb startet Nightforge es jetzt automatisch anders.",
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
        "It ended right after starting, with every way Nightforge knows to start it. A problem report helps get it running – it opens on GitHub, filled in with what Nightforge found.":
            "Es hat sich direkt nach dem Start beendet, mit jedem Weg, den Nightforge kennt. Eine Problemmeldung hilft, es zum Laufen zu bringen – sie öffnet sich auf GitHub, schon ausgefüllt mit dem, was Nightforge herausgefunden hat.",
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
        "hr": "Std.",

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
        "Continue Download": "Weiter laden",
        "Not enough space: Steam needs %@ to download this game, your Mac has %@ free. Make some room, then continue.": "Zu wenig Speicherplatz: Steam braucht %@ für den Download, dein Mac hat %@ frei. Mach etwas Platz und lade dann weiter.",
        "There's still not enough space: Steam needs %@ for %@, your Mac has %@ free.": "Noch immer zu wenig Platz: Steam braucht %@ für %@, dein Mac hat %@ frei.",
        "Preparing download …": "Download wird vorbereitet …",

        "Confirm in the Steam window": "Bestätige im Steam-Fenster",
        "Setting up the game …": "Spiel wird eingerichtet …",
        "Restarting Steam …": "Steam wird neu gestartet …",
        "Steam couldn't start %@.": "Steam konnte %@ nicht starten.",
        "Steam didn't respond, so %@ didn't start. Please try again.": "Steam hat nicht reagiert, deshalb ist %@ nicht gestartet. Bitte versuch es noch einmal.",

        "VR only": "Nur VR",
        "Doesn't run on a Mac": "Läuft nicht auf dem Mac",
        "This game's anti-cheat (%@) stops it on a Mac: it needs Windows itself, and getting around it would get your account banned.":
            "Der Anti-Cheat dieses Spiels (%@) verhindert es auf dem Mac: Er braucht Windows selbst, und ihn zu umgehen würde deinen Account sperren lassen.",
        "Nightforge plays it on GeForce Now, NVIDIA's cloud gaming, with your Steam copy (own NVIDIA account; free sessions last an hour).":
            "Nightforge spielt es über GeForce Now, NVIDIAs Cloud-Gaming, mit deinem Steam-Spiel (eigenes NVIDIA-Konto; kostenlos je eine Stunde).",
        "Play on GeForce Now": "Über GeForce Now spielen",
        "Plays on": "Läuft über",
        "Plays on GeForce Now – its anti-cheat doesn't run on a Mac": "Läuft über GeForce Now – sein Anti-Cheat läuft nicht auf dem Mac",
        "Play %@ on GeForce Now?": "%@ über GeForce Now spielen?",
        "Continue to GeForce Now": "Weiter zu GeForce Now",
        "Its anti-cheat doesn't run on a Mac, so it runs on NVIDIA's servers and streams to your Mac – with the copy you own on Steam. The first time, sign in to GeForce Now with an NVIDIA account and link Steam there. Free play lasts an hour at a time, with ads and a queue; GeForce Now's paid plans lift that. GeForce Now forgets the game while you sign in: afterwards, press Play on GeForce Now here once more.":
            "Sein Anti-Cheat läuft nicht auf dem Mac, deshalb läuft das Spiel auf NVIDIAs Servern und wird auf deinen Mac gestreamt – mit deinem Steam-Spiel. Beim ersten Mal meldest du dich bei GeForce Now mit einem NVIDIA-Konto an und verknüpfst dort Steam. Kostenlos geht es je eine Stunde, mit Werbung und Warteschlange; die Bezahl-Tarife von GeForce Now heben das auf. Beim Anmelden vergisst GeForce Now das Spiel: Klick danach hier noch einmal auf „Über GeForce Now spielen“.",
        "Anti-cheat stops this game on a Mac": "Anti-Cheat verhindert dieses Spiel auf dem Mac",
        "Needs a VR headset – this game can't be played on a Mac.": "Braucht eine VR-Brille – dieses Spiel läuft nicht auf dem Mac.",

        // Search & library
        "Search": "Suchen",
        "Search (⌘F)": "Suchen (⌘F)",
        "Clear search": "Suche löschen",
        "%ld of %ld games": "%ld von %ld Spielen",
        "%ld of 1 game": "%ld von 1 Spiel",
        "Settings": "Einstellungen",
        "Bottle": "Bottle",
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

        // Navigation
        "Home": "Startseite",
        "Sections": "Bereiche",
        "Home – what you play (L)": "Startseite – was du spielst (L)",
        "Details": "Details",
        "Details (I)": "Details (I)",
        "Back (Esc)": "Zurück (Esc)",
        "Back to Home": "Zurück zur Startseite",
        "Back to the library": "Zurück zur Bibliothek",
        "All games": "Alle Spiele",
        "All %ld games": "Alle %ld Spiele",
        "Your game": "Dein Spiel",
        "1 in your library": "1 in deiner Bibliothek",
        "%ld in your library": "%ld in deiner Bibliothek",
        "All games, %ld in your library": "Alle Spiele, %ld in deiner Bibliothek",
        "Everything in your library – installed or not – in one place.":
            "Alles aus deiner Bibliothek – installiert oder nicht – an einem Ort.",
        "Open Library": "Bibliothek öffnen",
        "%@ – click again for details": "%@ – noch einmal klicken für Details",
        "Tested on %@": "Getestet auf %@",

        "Continue playing": "Weiterspielen",
        "Pinned, then what you played lately": "Angeheftet, dann was du zuletzt gespielt hast",

        // Settings tabs
        "Stores": "Stores",
        "About": "Über",
        "Not set up yet – Nightforge does it at the first start.": "Noch nicht eingerichtet – Nightforge macht das beim ersten Start.",
        "Signed in · %@": "Angemeldet · %@",
        "Not signed in · %@": "Nicht angemeldet · %@",
        "Controllers": "Controller",
        "No controller connected.": "Kein Controller verbunden.",
        "Controller battery": "Akku des Controllers",
        "Connected · works in every game and in Nightforge": "Verbunden · funktioniert in jedem Spiel und in Nightforge",
        "Pair a Controller …": "Controller koppeln …",
        "PlayStation: hold PS and Create until the light flashes. Xbox: hold the pair button on top until the logo flashes. Nintendo: hold the sync button. Then choose it in the Bluetooth settings.":
            "PlayStation: PS und Create halten, bis das Licht blinkt. Xbox: die Kopplungstaste oben halten, bis das Logo blinkt. Nintendo: die Sync-Taste halten. Dann in den Bluetooth-Einstellungen auswählen.",
        "Button labels": "Tastensymbole",
        "Like my controller": "Wie mein Controller",
        "What the hints at the bottom of Nightforge show for the buttons: ✕ ○ □ △ or A B X Y.":
            "Was die Hinweise unten in Nightforge für die Tasten zeigen: ✕ ○ □ △ oder A B X Y.",
        "No account. No telemetry. No background service.": "Kein Konto. Keine Telemetrie. Kein Hintergrunddienst.",
        "Nothing leaves your Mac unless you send it – a problem report opens on GitHub, filled in, and goes nowhere until you submit it.":
            "Nichts verlässt deinen Mac, außer du schickst es ab – ein Problembericht öffnet sich ausgefüllt auf GitHub und geht nirgendwohin, bis du ihn absendest.",
        "Nightforge %@": "Nightforge %@",
        "Nightforge is free software under the GPL-3.0. It stands on these projects – thank you to everyone behind them. Their licence files ship inside the app.":
            "Nightforge ist freie Software unter der GPL-3.0. Es baut auf diesen Projekten auf – danke an alle, die dahinterstehen. Ihre Lizenzdateien liegen in der App.",
        "Built on": "Gebaut auf",
        "Show Licence Files": "Lizenzdateien zeigen",
        "Fixes for single games": "Korrekturen für einzelne Spiele",
        "Which games' anti-cheat runs where": "Welches Anti-Cheat wo läuft",
        "Wine with controller support": "Wine mit Controller-Unterstützung",
        "Wine with DXMT": "Wine mit DXMT",
        "Runs Windows games on the Mac": "Lässt Windows-Spiele auf dem Mac laufen",
        "DirectX 12 on Metal (Apple)": "DirectX 12 auf Metal (Apple)",
        "DirectX 10 and 11 on Metal": "DirectX 10 und 11 auf Metal",
        "DirectX 9 to 11 on Vulkan": "DirectX 9 bis 11 auf Vulkan",
        "Vulkan on Metal": "Vulkan auf Metal",
        "Installs what games need from Windows": "Installiert, was Spiele von Windows brauchen",
        "Unpacks Windows installers": "Entpackt Windows-Installer",
        "Tool": "Werkzeug",

        "The download is done.": "Der Download ist fertig.",
        "Notify me when downloads finish": "Mitteilung, wenn Downloads fertig sind",
        "A macOS notification with a Play button while Nightforge is in the background. Your last five games are in the Dock menu, too.":
            "Eine macOS-Mitteilung mit „Spielen“-Knopf, während Nightforge im Hintergrund ist. Deine letzten fünf Spiele stehen auch im Dock-Menü.",

        "Accessibility": "Bedienungshilfen",
        "Reduce motion": "Bewegung reduzieren",
        "No zoom on covers, no sliding – plain cross-fades. Follows “Reduce motion” in macOS until you change it here.":
            "Kein Zoom auf Covern, kein Gleiten – nur Überblenden. Folgt „Bewegung reduzieren“ in macOS, bis du es hier änderst.",

        // Not enough space
        "%@ needs up to %@": "%@ braucht bis zu %@",
        "Your Mac has %@ free – %@ short. Nothing is downloaded until there's room, so nothing stops halfway.":
            "Dein Mac hat %@ frei – es fehlen %@. Geladen wird erst, wenn Platz ist, damit nichts auf halbem Weg abbricht.",
        "No game here has gone unplayed for a month. Remove games or other files you don't need, then try again.":
            "Kein Spiel hier wurde seit einem Monat nicht gespielt. Entferne Spiele oder andere Dateien, die du nicht brauchst, und versuch es dann noch einmal.",
        "Make room – these haven't been played for a while. They stay in your Steam library, and saves in the Steam Cloud are kept.":
            "Platz schaffen – diese wurden länger nicht gespielt. Sie bleiben in deiner Steam-Bibliothek, Spielstände in der Steam Cloud bleiben erhalten.",
        "Last played %@": "Zuletzt gespielt %@",
        "Never played": "Noch nie gespielt",
        "Frees %@ – enough": "Macht %@ frei – reicht",
        "Frees %@ of %@": "Macht %@ von %@ frei",
        "Uninstall %ld & Download": "%ld deinstallieren & laden",

        // Storage
        "Storage": "Speicher",
        "Games": "Spiele",
        "Other": "Anderes",
        "%@ free": "%@ frei",
        "Measuring Nightforge …": "Nightforge wird gemessen …",
        "“Nightforge” is the game engine, the Windows environment and Steam itself – everything besides the games.":
            "„Nightforge“ ist die Spiel-Engine, die Windows-Umgebung und Steam selbst – alles außer den Spielen.",
        "No games on this Mac yet.": "Noch keine Spiele auf diesem Mac.",
        "Games on this Mac": "Spiele auf diesem Mac",

        // Didn't start
        "It ended right after starting, with every way Nightforge knows to start it.": "Es hat sich gleich nach dem Start beendet – mit jedem Weg, den Nightforge kennt.",
        "Tried: %@": "Versucht: %@",
        "Try Again From the First Way": "Nochmal mit dem ersten Weg versuchen",
        "Helps when something got in the way the first time – Steam updating, a window asking something.":
            "Hilft, wenn beim ersten Mal etwas dazwischenkam – ein Steam-Update oder ein Fenster mit einer Frage.",
        "Choose Graphics by Hand …": "Grafik selbst wählen …",
        "Still no luck? A problem report opens on GitHub, filled in with what Nightforge tried – nothing is sent until you submit it there.":
            "Immer noch nicht? Ein Problembericht öffnet sich auf GitHub, ausgefüllt mit dem, was Nightforge versucht hat – nichts wird gesendet, bis du ihn dort abschickst.",
        "Close": "Schließen",

        // Launch phases
        "Starting Steam …": "Steam startet …",
        "Steam runs invisibly in the background – it only has to start once.": "Steam läuft unsichtbar im Hintergrund – es muss nur einmal starten.",
        "The Mac version starts through Steam for Mac, which runs in the background.": "Die Mac-Version startet über Steam für Mac, das im Hintergrund läuft.",
        "Steam signs in again, so your cloud saves come along.": "Steam meldet sich neu an, damit deine Cloud-Spielstände mitkommen.",
        "Steam needs you to sign in – its window is open.": "Steam möchte, dass du dich anmeldest – sein Fenster ist offen.",
        "Installing what the game needs from Windows. Only the first time.": "Installiert, was das Spiel von Windows braucht. Nur beim ersten Mal.",
        "Installing .NET, which this game needs. Only the first time.": "Installiert .NET, das dieses Spiel braucht. Nur beim ersten Mal.",
        "Steam got stuck while starting – a fresh start fixes that.": "Steam ist beim Starten hängen geblieben – ein Neustart behebt das.",
        "It closed right away – Nightforge starts it the next way and remembers what works.":
            "Es hat sich sofort beendet – Nightforge startet es auf dem nächsten Weg und merkt sich, was funktioniert.",
        "First start with this graphics version: shaders are prepared, so it can take a minute. Next time it's quicker.":
            "Erster Start mit dieser Grafikversion: Shader werden vorbereitet, das kann eine Minute dauern. Beim nächsten Mal geht es schneller.",
        "Steam asks something before the game starts – answer it in its window.": "Steam fragt vor dem Start etwas – antworte in seinem Fenster.",

        // Shortcuts
        "%@ is in Applications now – Spotlight finds it": "%@ ist jetzt in den Programmen – Spotlight findet es",
        "%@ couldn't be added to Applications: %@": "%@ konnte nicht zu den Programmen hinzugefügt werden: %@",
        "In Applications – show it": "In den Programmen – zeigen",
        "Add to Applications – Spotlight and Launchpad find it": "Zu den Programmen hinzufügen – Spotlight und Launchpad finden es",

        // Welcome back
        "Welcome back": "Willkommen zurück",
        "%@ this time · %@ in total": "%@ diesmal · %@ insgesamt",
        "How did it run?": "Wie lief es?",
        "Well": "Gut",
        "Not well": "Nicht gut",
        "Stutters": "Ruckelt",
        "Crashed": "Abgestürzt",
        "Low frame rate": "Niedrige Bildrate",
        "Graphics glitches": "Grafikfehler",
        "Sound": "Ton",
        "Thanks – noted on this Mac. It shapes how Nightforge rates the game for you.":
            "Danke – auf diesem Mac vermerkt. Es fließt in Nightforges Bewertung des Spiels für dich ein.",
        "Play Again": "Nochmal spielen",
        "Done": "Fertig",
        "You said it runs well.": "Du hast gesagt, es läuft gut.",
        "You said it didn't run well.": "Du hast gesagt, es lief nicht gut.",
        "You said: %@.": "Du hast gesagt: %@.",

        // Update & Play
        "Update & Play · %@": "Aktualisieren & spielen · %@",
        "Update & Play": "Aktualisieren & spielen",
        "Updating … %ld %%": "Aktualisiert … %ld %%",
        "Steam updates the game first – it starts by itself when the update is done.": "Steam aktualisiert das Spiel zuerst – es startet von selbst, sobald das Update fertig ist.",
        "An update is waiting – Steam downloads it before the game starts": "Ein Update wartet – Steam lädt es, bevor das Spiel startet",
        "Installed, update waiting": "Installiert, Update wartet",

        // Downloads
        "Nightforge is downloading %@": "Nightforge lädt %@",
        "1 download (D)": "1 Download (D)",
        "%ld downloads (D)": "%ld Downloads (D)",
        "1 download": "1 Download",
        "%ld downloads": "%ld Downloads",
        "Downloads": "Downloads",
        "Nothing is downloading.": "Gerade lädt nichts.",
        "Your Mac stays awake while games download. The display can still turn off.": "Dein Mac bleibt wach, solange Spiele laden. Der Bildschirm darf trotzdem ausgehen.",
        "Paused – not enough space": "Pausiert – zu wenig Platz",
        "%ld %% of %@": "%ld %% von %@",
        "Preparing …": "Wird vorbereitet …",

        // First start
        "Your library on this Mac": "Deine Bibliothek auf diesem Mac",
        "%ld of your 1 game runs here": "%ld von deinem 1 Spiel läuft hier",
        "%ld of your %ld games run here": "%ld deiner %ld Spiele laufen hier",
        "Tested by Nightforge, a Mac version, or it started fine here.": "Von Nightforge getestet, eine Mac-Version oder hier schon gut gestartet.",
        "Nightforge applies what they need by itself, at every start.": "Nightforge wendet bei jedem Start selbst an, was sie brauchen.",
        "Nobody has tried them on a Mac with Nightforge yet – most still run. The first start tells, and Nightforge remembers what works.":
            "Noch niemand hat sie mit Nightforge auf dem Mac probiert – die meisten laufen trotzdem. Der erste Start zeigt es, und Nightforge merkt sich, was funktioniert.",
        "Their anti-cheat needs Windows itself – %ld of them play on GeForce Now instead.": "Ihr Anti-Cheat braucht Windows selbst – %ld davon laufen stattdessen auf GeForce Now.",
        "Their anti-cheat needs Windows itself.": "Ihr Anti-Cheat braucht Windows selbst.",
        "1 needs a VR headset.": "1 braucht eine VR-Brille.",
        "%ld need a VR headset.": "%ld brauchen eine VR-Brille.",
        "Let's Play": "Los geht's",
        "Show the First Start Again": "Ersten Start noch einmal zeigen",

        // Battery
        "Save battery when unplugged": "Akku sparen ohne Netzteil",
        "On battery, games are capped at 30 FPS so the battery lasts longer. Plugged in, everything runs at full speed. Takes effect at the next game start.":
            "Im Akkubetrieb laufen Spiele mit höchstens 30 FPS, damit der Akku länger hält. Am Netzteil läuft alles mit voller Geschwindigkeit. Gilt ab dem nächsten Spielstart.",
        "On battery – games are capped at 30 FPS to last longer": "Im Akkubetrieb – Spiele laufen mit höchstens 30 FPS, damit der Akku länger hält",
        "On battery – “Save battery when unplugged” in Settings caps games at 30 FPS": "Im Akkubetrieb – „Akku sparen ohne Netzteil“ in den Einstellungen begrenzt Spiele auf 30 FPS",
        "On battery: games are capped at 30 FPS to last longer.": "Im Akkubetrieb: Spiele laufen mit höchstens 30 FPS, damit der Akku länger hält.",

        // Cloud saves
        "Your save is in the Steam Cloud. You can close your Mac.": "Dein Spielstand ist in der Steam Cloud. Du kannst den Mac zuklappen.",
        "Steam syncs your save in the background.": "Steam gleicht deinen Spielstand im Hintergrund ab.",
        "Steam is syncing your save with the Steam Cloud …": "Steam gleicht deinen Spielstand mit der Steam Cloud ab …",
        "No Steam Cloud for this game – its saves are on this Mac.": "Keine Steam Cloud für dieses Spiel – seine Spielstände liegen auf diesem Mac.",

        // Library filters
        "Sort": "Sortieren",
        "Recently played": "Zuletzt gespielt",
        "Name": "Name",
        "Disk space": "Speicherplatz",
        "All": "Alle",
        "On this Mac": "Auf diesem Mac",
        "Not downloaded": "Nicht geladen",
        "Mac version": "Mac-Version",
        "Your games": "Deine Spiele",
        "A – Z": "A – Z",
        "Largest first": "Größte zuerst",
        "%ld hidden": "%ld ausgeblendet",
        "Only games that run great on a Mac": "Nur Spiele, die auf dem Mac super laufen",
        "Full controller support": "Volle Controller-Unterstützung",
        "Runs as its Mac version": "Läuft als Mac-Version",
        "Games you hid from your library": "Spiele, die du aus der Bibliothek ausgeblendet hast",
        "No games match these filters": "Keine Spiele passen zu diesen Filtern",
        "Clear filters": "Filter zurücksetzen",

        // Hide & pin
        "Hidden": "Ausgeblendet",
        "Hidden games": "Ausgeblendete Spiele",
        "Hide": "Ausblenden",
        "Show": "Einblenden",
        "Hide from library (H)": "Aus der Bibliothek ausblenden (H)",
        "Show in library again (H)": "Wieder in der Bibliothek zeigen (H)",
        "Pin to Home – stays on the rail (P)": "An die Startseite heften – bleibt in der Leiste (P)",
        "Unpin from Home (P)": "Von der Startseite lösen (P)",
        "Pinned to Home": "An die Startseite geheftet",
        "Undo": "Rückgängig",
        "%@ is hidden from your library": "%@ ist aus deiner Bibliothek ausgeblendet",
        "%@ is back in your library": "%@ ist wieder in deiner Bibliothek",
        "%@ stays on Home – even when you haven't played it for a while": "%@ bleibt auf der Startseite – auch wenn du es länger nicht gespielt hast",
        "%@ is no longer pinned": "%@ ist nicht mehr angeheftet",
        "Open a game to bring it back.": "Öffne ein Spiel, um es zurückzuholen.",

        "%@ is ready to play": "%@ ist bereit zum Spielen",
        "%ld games are ready to play": "%ld Spiele sind bereit zum Spielen",

        // Compatibility
        "Runs great": "Läuft super",
        "Runs with tweaks": "Läuft mit Anpassungen",
        "Not tested yet": "Noch nicht getestet",
        "Needs a VR headset.": "Braucht eine VR-Brille.",
        "Its anti-cheat needs Windows itself.": "Sein Anti-Cheat braucht Windows selbst.",
        "Its anti-cheat needs Windows – playable on GeForce Now instead.":
            "Sein Anti-Cheat braucht Windows – stattdessen auf GeForce Now spielbar.",
        "DirectX 12 only: it runs through Apple's D3DMetal, which not every game likes.":
            "Nur DirectX 12: Es läuft über Apples D3DMetal, das nicht jedes Spiel mag.",
        "Online play with %@ doesn't work on a Mac.": "Online-Spiel mit %@ geht auf dem Mac nicht.",
        "Starts with fixes from umu-protonfixes, applied automatically.":
            "Startet mit Korrekturen aus umu-protonfixes, die automatisch angewendet werden.",
        "Nightforge found what it needs by itself and applies it at every start.":
            "Nightforge hat selbst herausgefunden, was es braucht, und wendet es bei jedem Start an.",

        // Errors
        "Component list version %ld needs a newer Nightforge.": "Komponentenliste Version %ld braucht ein neueres Nightforge.",
        "No component list available. Check your internet connection.": "Keine Komponentenliste verfügbar. Prüfe deine Internetverbindung.",
        "The download of %@ is damaged. Please try again.": "Der Download von %@ ist beschädigt. Bitte versuch es noch einmal.",
        "%@ could not be unpacked (tar exit %d).": "%@ konnte nicht entpackt werden (tar-Code %d).",
        "Wine was not found at %@. Install CrossOver or enter the path to your wine binary in Settings.":
            "Wine wurde unter %@ nicht gefunden. Installiere CrossOver oder trag in den Einstellungen den Pfad zu deinem wine ein.",
    ]
}
