# Nightforge – offene Punkte

Was liegen geblieben ist und irgendwann angegangen werden kann. Stand: 26.10.2026, nach dem
Umstieg auf winecx 4.7.3 mit D3DMetal (PR #7), dem Controller-Paket (PR #8) und dem Code-Audit
(behoben in PR #4, #5 und #11, der Rest steht unten unter „Aus dem Code-Audit“).

Neue Punkte unten in den passenden Abschnitt, Erledigtes löschen (die Geschichte steht im Git-Log).
Jeder Punkt nennt, wo man anfängt.

## Nach dem Engine-Wechsel neu prüfen

Die Tests vom 26.10. liefen größtenteils noch auf Wine 11.18 (Gcenx). Seit PR #7 läuft winecx 4.7.3.

- **Getestete Spiele auf winecx gegenprüfen.** Palworld (DXMT, 60 FPS), Deadlock (DXVK, 60–120 FPS),
  Left 4 Dead 2 (WineD3D), OxyRail und 7 Days to Die. Die Ergebnisse und Profile in
  `profiles/mac.json` beziehen sich auf 11.18.
- **Left 4 Dead 2.** Auf 11.18 scheitert DXVK an seinen Puffern (`vkCreateBuffer`, MoltenVK lehnt
  externe Speicher-Handles ab). WineD3D läuft, stürzt aber nach etwa einer Minute ab, und im Spiel fehlte der Ton.
  `-vulkan` (Valves DXVK) und WineD3D mit Vulkan starten nicht. Auf winecx neu testen. Zum Ton:
  In der Cloud-Konfiguration stehen `volume "0.008"` und Quadro-Lautsprecher, also erst im Spiel unter
  Optionen → Audio hochdrehen, bevor man Wine verdächtigt.
- **Andere Source-Spiele** (Team Fortress 2, Garry's Mod): Sie bekommen jetzt dieselbe DirectX-9-Leiter wie L4D2.
  Noch kein einziges getestet.
- **Unreal-Spiele allgemein.** Bis 26.10. bekam kein Unreal-Spiel DXMT. Die Einstellungen reichten nur drei
  Ordner tief, `<Projekt>/Binaries/Win64/*-Shipping.exe` liegt auf Ebene 4. Wer ein Unreal-Spiel für
  „läuft schlecht“ hielt, sollte es erneut versuchen (z. B. Marvel Rivals).
- **msync (PR #1)** ist auf 11.18 portiert. winecx bringt ein eigenes msync mit, der Patch greift dort nicht.
  Klären, ob der 11.18-Weg noch gebraucht wird.

## DirectX 12 (D3DMetal)

- **Echtes DX12-Spiel aus den Top 100 testen.** Gemessen ist bisher nur der Wukong-Benchmark
  (D3DMetal 69 FPS im Schnitt). Kandidaten: Elden Ring (offline, ohne EAC),
  Resident Evil 4, Monster Hunter Wilds, Street Fighter 6, Space Marine 2, Planet Zoo 2.
- **Bekannte Stolpersteine, die automatisch abgefangen werden sollen** (Plan in den Notizen der DX12-Sitzung):
  `ROSETTA_ADVERTISE_AVX=1` lässt Wukong abstürzen; Unreals Hinweis „AMD driver has known issues“
  (D3DMetal meldet sich als AMD); Frame Generation und DLSS schalten sich beim ersten Start ein und stürzen ab.
- **MTL_HUD** erscheint unter D3DMetal 4.0 nicht (Metal-4-Backend?).
- **Lizenz:** GPTK 4.0b3 erlaubt die Weitergabe nur nicht-kommerziell und unverändert. Nightforge muss
  kostenlos bleiben, D3DMetal.framework wird nur ganz und unverändert weitergegeben. Kein Streaming-Dienst
  damit (2C). Apple kann die Lizenz jederzeit beenden (Abschnitt 5). Plan B wäre dann, dass Nightforge das
  Toolkit aus Apples eigenem Download holt, wie die kommerzielle App Apara es macht.

## Steam und Start

- **Steam-Fragen vor dem Start** (EULA, Controller-Firmware „ShowInterstitials“, Startoption bei
  Mac-Spielen mit mehreren Optionen wie Project Zomboid): Sie erscheinen, wenn der Spieler in Nightforge
  „Bestätige im Steam-Fenster“ klickt. Ein Klick ist für den Nutzer okay. Wünschenswert wäre, die
  Standard-Startoption automatisch zu wählen. Kandidat: `steam://launch/<id>/<Typ>` (Steam kennt die Typnamen
  Default, Option1…). Ein Versuch blieb ohne Wirkung, lief aber, während schon ein Dialog offen war.
  Also ungeklärt.
- **Windows-Steam ignoriert manchmal `steam.exe -shutdown`.** Dann hilft nur `wineserver -k`. Läuft Steam gar
  nicht, startet `-shutdown` ein neues Steam. Nightforges eigenes Beenden darauf prüfen.
- **steam-shutdown.sh** hält jeden Prozess unter `\steamapps\common\` für ein Spiel, auch in
  Test-Prefixen, und holt Nightforge dann nach vorne.
- **Steam-Anmeldung zwischen den Steams.** Steam für Mac und die Windows-Steam melden sich gegenseitig ab
  („Session Replaced“). Beobachtet wurde auch: Steam hängt, beendet sich nicht oder drängt sich nach vorne.

## Mac-Versionen

- **Windows-Fallback** hat noch nie wirklich ausgelöst (keine Mac-Version ist bisher abgestürzt).
- **Speicherplatz vor dem Download prüfen.** Steam für Mac hat Batman bei einem Auto-Update geleert und
  dann wegen Platzmangel pausiert. Nightforge zeigt das jetzt an und bietet „Weiter laden“
  (`Engine.unpauseDownload`). Besser wäre, vor einem Download oder Update vor knappem Platz zu warnen
  (`LibraryModel.freeSpace`, Steams `BytesToStage`).

## Controller

- **DualSense in Windows-Spielen auf winecx:** OxyRail funktioniert seit dem Xbox-360-ID-Patch (PR #8).
  Noch offen: Hotplug auf winecx (auf 11.18 geprüft: SDL nimmt den Pad nach Aus/An wieder auf) und weitere
  Spiele (reine XInput-Spiele, Unreal, DirectInput-Spiele).
- **Preis des Xbox-360-ID-Patches:** Windows-Spiele mit eigener DualSense-Unterstützung zeigen Xbox-Symbole,
  adaptive Trigger, Lichtleiste und Bewegungssensor fehlen. Ein besserer Weg bräuchte beides: den rohen Pad
  für solche Spiele und einen XInput-Pad für den Rest (`engine/patches/winebus-*-xbox360-ids.patch`).
- **Mac-Ports mit dem synthetischen Xbox-Pad** (`ControllerCompatibility`): bisher nur mit Batman geprüft.
  Andere alte Ports (Feral, Aspyr) wären gute Kandidaten.

## Darstellung und Leistung

- **MetalFX im Vulkan-Layer** (Retina für Vulkan-Spiele, PR #1): Die Metal-Seite ist geprüft, in einem Spiel noch nicht.
- **MoltenVK 1.4.2** (PR #1) ist in keinem Spiel getestet. 1.4.0 scheiterte an Shadern von No Man's Sky.
- **D3DM_MAX_FPS** wirkt jetzt über Steams Start-Umgebung. Prüfen, ob die gelernte Bildratengrenze
  (FramePacing) auch für D3DMetal-Spiele greift.
- **TV-Modus** (Branch `claude/external-monitor-support-cd1be5`): Der Wechsel des Hauptbildschirms ist an einem
  echten TV noch nicht getestet.

## Anti-Cheat und GeForce Now

- **Store-Suche warnt nicht vor reinen Online-Spielen mit Anti-Cheat** (z. B. Bless Unleashed). Die Sperre
  `antiCheatOnline` braucht Steams Kategorie „Einzelspieler“, die die Store-Suche nicht liefert; in der
  Bibliothek greift sie. Ansatz: `StoreSearch.details` um `categories` erweitern (appdetails, Kategorie 2).
- **GeForce-Now-Link beim allerersten Klick:** Führt er über die Anmeldung, landet man danach auf der
  Startseite statt beim Spiel (getestet 26.10.). Der Erklär-Dialog sagt deshalb, danach noch einmal zu klicken.
  Angemeldet landet der Link direkt auf der Spielseite.
- Anti-Cheat wird nie umgangen. Fortschritt gibt es nur, wenn Entwickler, Epic oder BattlEye macOS/Wine freischalten.

## Abdeckung der Top 100

Übersicht vom 26.10.: https://claude.ai/artifact/TWQ3kkV6W7szsgyPyh6dWp
(Artifact, nur für den Besitzer sichtbar.)

- Etwa 28 Spiele haben eine Mac-Version, etwa 21 laufen wahrscheinlich über Wine, 22 sind durch Anti-Cheat
  blockiert, 9 sind reine DX12-Spiele (jetzt Kandidaten für D3DMetal).
- **Launcher-Spiele** sind ungeprüft: EA app (Sims 4, FC), Rockstar Launcher (GTA V, RDR2),
  Battle.net (Overwatch), REDlauncher (Witcher 3, startet DX12 als Standard).
- **Rocket League:** Die Startoption ohne Anti-Cheat nutzt ein anderes Programm (`RocketLeague.exe`).
  `SteamCatalog.antiCheatOffArguments` übernimmt aber nur Optionen mit demselben Programm. Die Mac-Version ist
  der Stand von 2020 ohne Online-Spiel.
- Übersicht nach DX12- und winecx-Tests aktualisieren (Liste: `ISteamChartsService/GetMostPlayedGames`).

## Wartung und Community

Ziel: Mac-Gaming gemeinsam voranbringen, keine Konkurrenz und kein Geld. Nightforge soll nicht an einer
Person hängen (Whisky ist 2025 daran gescheitert).

- **Hinweis auf CrossOver.** In der README und in den Einstellungen (Über/Hilfe) erwähnen, dass CodeWeavers
  einen großen Teil der Wine-Entwicklung finanziert und CrossOver für Fortgeschrittene und Support die
  richtige Wahl ist. Freundlich, ohne Vergleichstabelle.
- **Nur geprüfte Komponenten ausliefern.** `components.yml` committet neue Versionen heute direkt ins
  `manifest.json` auf `main`. Besser: ein Bot-PR, den die Tests (`tests/*/run.sh` auf einem macOS-Runner)
  durchlaufen müssen und der erst nach einem kurzen Spieltest gemergt wird. Dazu ein Rückweg: Die vorherige
  Version bleibt im Manifest, und Nightforge kann auf sie zurückfallen (`ComponentStore`).
- **Tests in der CI.** Die Testprogramme unter `tests/` bei jedem PR auf GitHubs macOS-Runner laufen lassen
  (für öffentliche Repos kostenlos). Echte Spiele bleiben Handarbeit.
- **Problembericht ausbauen.** `ProblemReport` öffnet schon ein GitHub-Issue. Ergänzen: Komponenten-Versionen,
  Grafik-Layer und Profil mitschicken, Issue-Vorlage im Repo, der Nutzer sieht vorher alles. Nichts automatisch
  senden, kein Tracking. Vorher den Benutzernamen-Befund unter „Aus dem Code-Audit“ beheben.
- **Profile von der Community.** `profiles/` als Ort beschreiben, an dem jeder per PR ein Spiel eintragen kann:
  kurze Anleitung (`CONTRIBUTING.md`), Format erklären, Prüfung per CI (JSON gültig, Felder bekannt).
  Später überlegen, die Profile als offene Liste auch anderen Projekten anzubieten (ähnlich ProtonDB).
- **Fixes an die Ursprungsprojekte zurückgeben.** Kandidaten: DXMT-Patch für Wine 11 (3Shain/dxmt), der
  winebus-Xbox-ID-Patch und msync (Gcenx), die Patches in `engine/patches`. Was dort gemergt wird, müssen wir
  nicht bei jedem Update selbst nachziehen.
- **macOS-Betas früh testen.** Jeden Juni mit der neuen Beta Einrichtung, Steam-Start, ein DXMT-, ein D3DMetal- und
  ein Mac-Spiel durchgehen, damit der September keine Überraschung wird.
- **Ehrlich sagen, was geht.** Eine Liste „geprüft läuft“ in README oder App, alles andere als „probier es aus“.
  Schützt vor Erwartungen, die niemand allein erfüllen kann.
- **Mehr Leute mit Schreibrechten.** Sobald jemand regelmäßig beiträgt, Mitbetreuer aufnehmen. Releases und
  Komponenten-Pakete (`scripts/package-d3dmetal.sh`) so dokumentieren, dass sie nicht nur auf einem Mac gehen.

## Aus dem Code-Audit

Befunde vom 26.10., die noch nicht behoben sind. Behoben sind: Spiele, die ein Engine-Wechsel oder
das Steam-Aufräumen beendete, die Deinstallation in Zusatz-Bibliotheken, die Winetricks-Verben, die
Registry-Schlüssel aus Profilen, die Prüfung des Manifests, die CI-Rechte, der CI-Build, Wine-Aufrufe
auf dem Main-Thread und sich überholende Rescans.

### Sicherheit und Lieferkette

- **Updates sind nicht echt signiert.** `Updater.install` prüft nur `codesign --verify` auf eine Ad-hoc-Signatur,
  `scripts/install.sh` lädt ohne Prüfsumme. Entscheidung offen: einen Ed25519-Schlüssel als Repo-Secret
  (Release-Zip signieren, im Updater und in install.sh prüfen) oder einen Apple-Developer-Account (Developer ID, Notarisierung).
- **Nächtliche Daten gehen ungeprüft an alle.** `components.yml` und `profiles.yml` committen direkt auf `main`,
  umu-protonfixes und AreWeAntiCheatYet werden ab `HEAD` gelesen. Besser: Bot-PRs statt Push, Upstreams per Commit festlegen.
- **Build-Eingaben ohne Prüfsumme.** In `graphics.yml` sind das `WINE_TOOLCHAIN_URL`, das Gcenx-Archiv, der
  inotify-Header und Klone per Tag, in `tools.yml` das cabextract-Archiv. Dazu kommt `brew install … || true`.
  Die Actions sind per Tag statt per SHA festgelegt, Dependabot fehlt.
- **LGPL beim Grafik-Paket.** Das `graphics-*`-Release bringt gepatchte Wine- und DXMT-Binaries ohne Lizenztexte
  und ohne Quellarchiv. Lizenzdateien ins Tarball legen und das Quellarchiv mit Patches und Commit anhängen.
  Bei cabextract (GPL, `tools.yml`) genauso.
- **Lizenzhinweise im App-Bundle.** Es fehlen die Lizenz der Vulkan-Headers (im Vulkan-Layer einkompiliert) und
  die mingw-Runtime im `steamwebhelper.exe`. Eine `THIRD_PARTY_NOTICES` in `build.sh` mitkopieren.
- **Problembericht.** `GameLog` entfernt nur `$HOME`. Windows-Pfade wie `C:\users\<name>` oder
  `drive_c/users/<name>` landen mit dem Benutzernamen in der GitHub-URL (`ProblemReport`).
- **`SaveTransfer`** lehnt `..` in Pfaden aus `mac.json` nicht ab.

### Stabilität

- **Ersteinrichtung lädt die falsche Engine.** `SetupModel.run` installiert `manifest.component(Engine.engineID)`
  (Wine 11.18) statt `Engine.engineComponent(in:)` (winecx). Neue Nutzer laden erst 11.18 und beim ersten Start
  der Bibliothek winecx (≈1,3 GB). Setup auf `ensureEngine` umbauen und mit einem frischen Konto testen.
- **Ein Spielstart bricht nach 120 s still ab.** Die Warteschleife im Start in `LibraryModel` gibt `false` zurück,
  ohne Meldung. Es fehlen ein Hinweis („Steam reagiert nicht“, Nochmal/Steam zeigen) und ein Abbrechen mit B oder Esc.
- **Steam-Shutdown-Skript** (`Engine`, steam-shutdown): `reopened` wird nur in der Warteschleife geprüft, nicht mehr
  vor `-shutdown` und `wineserver -k`. Wird Nightforge in diesem Fenster wieder geöffnet, kann ein neues Spiel beendet werden.
- **`SteamPriority`** ruft `kill` auf die PID aus der PID-Datei auf, ohne zu prüfen, ob das noch das eigene Skript ist.
- **Migration** (`LegacyMigration`): Schlägt das Verschieben einmal fehl, legt die App den neuen Ordner trotzdem an.
  Beim nächsten Start bleibt der alte Nachtschicht-Prefix für immer zurück.
- **`installWebHelperWrapper`** tauscht nicht atomar. Scheitert das Kopieren, fehlt `steamwebhelper.exe` ganz.
- **`requestDownload`** escaped in der .acf nur `"`, nicht `\`.
- **Mac-Start und Spielstand-Übernahme** setzen `installDir` aus der Standardbibliothek zusammen statt
  `game.installDir` zu nehmen. Mac-Spiele auf externen Bibliotheken bekommen den DualSense-Fix im falschen Ordner.
- **Alte Komponenten werden nie gelöscht** (`ComponentStore`). Auf dem Entwickler-Mac sind das rund 1 GB
  (`wine-staging`, alte `graphics`-Versionen). Nach einer erfolgreichen Installation unbenutzte Versionen entfernen.
- **Logs wachsen ohne Grenze:** `winetricks.log` immer, `wine.log` während einer langen Steam-Sitzung (`GameLog`).

### Vulkan-Layer und Wrapper (`wrapper/`)

- **CAMetalLayer ohne Retain** in der Surface-Tabelle und kein Hook auf `vkDestroySurfaceKHR`. Nach einem Wechsel in den
  Vollbildmodus kann der Layer auf einen freigegebenen Layer zugreifen (Absturz). Nur mit MetalFX-Upscaling.
- **Kein `@autoreleasepool`** in `nightforge-vulkan-metalfx.m`. Pro Frame bleiben Objekte auf dem Render-Thread liegen,
  der Speicher wächst die ganze Sitzung.
- **Swapchain-Fallback** übergibt das schon verbrauchte `oldSwapchain` noch einmal. `vkDeviceWaitIdle` in
  `DestroySwapchain` kann mit anderen Threads kollidieren. Device- und Instance-Globals werden nie zurückgesetzt.
- **Die Retina-Erkennung** schaut auf den Hauptbildschirm statt auf den Bildschirm des Fensters (wichtig für den TV-Modus).
- **`steamwebhelper-wrapper.c`** startet den echten Helper ohne Job-Object. Wird der Wrapper beendet, bleibt CEF
  verwaist (passt zu den bekannten Shutdown-Hängern).

### Leistung

- **Downloads:** Alle 3 s läuft ein kompletter Rescan mit `folderSize` über `downloading/<id>`. Nur die Manifeste der
  ladenden Spiele neu lesen und die Ordnergröße cachen.
- **Dauerndes Polling:** `ps` alle 3 s auch im Leerlauf, eine 1-Hz-Schleife in `MacSteam`. Besser wären Exit-Quellen
  (`DispatchSource.makeProcessSource`) und längere Abstände im Leerlauf.
- **SwiftUI:** `LibraryModel` ist ein `ObservableObject` mit 26 `@Published`, jede Änderung zeichnet alles neu.
  `@Observable` (ab macOS 14) oder das Modell aufteilen.
- **Cover-Cache** (`Artwork`): Bilder liegen in voller Auflösung im Speicher, die Platte hat kein Limit, und
  `.missing`-Marker laufen nie ab.
- **`appinfo.vdf`** wird mehrfach ohne Cache gelesen (`SteamCatalog`). `insight(of:)` startet bei schnellem Blättern
  mehrere Analysen gleichzeitig.

### Bedienung, Controller und Sprache

- **VoiceOver:** Die ganze App hat ein einziges `accessibilityLabel`. Cover, Icon-Knöpfe (`RoundIconButton`) und das
  Zahnrad brauchen Labels und Traits.
- **Controller:**
  - „Mac-Version laden“ samt Abbrechen, „Entfernen…“, „Akku-Einstellungen“ und die Suche haben kein `.padFocus`,
    damit ist der Store mit dem Pad unerreichbar.
  - ↑/↓ im Raster rechnet `±gridColumns`, obwohl jede Sektion eine neue Zeile beginnt.
  - B löscht keine aktive Suche.
  - In Alerts trifft A den Standardknopf. „Problem melden“ öffnet dadurch den Browser.
- **Rückmeldung:** Die Rosetta-Installation zeigt weder Fortschritt noch Fehler (`SetupModel.installRosetta`).
  Die Ersteinrichtung hat kein Abbrechen.
- **Sprache:**
  - Es gibt kein `de.lproj` und keine `CFBundleLocalizations`, deshalb sind die macOS-Menüs immer englisch.
  - Rohe Systemfehler erscheinen in der Systemsprache.
  - Fachbegriffe im Hauptscreen: DXMT, „Bottle“, WebView2.
  - Kleinigkeiten: „1 hrs“ (`Format.playtime`), „1 of 1 games“, die Uhr in der Systemsprache.
- **Darstellung:** „Bewegung reduzieren“ wird ignoriert, alle Schriftgrößen sind fest. Über heller Hero-Art fehlt
  der Topbar ein Verlauf für den Kontrast.
- **README-Steuerungstabelle** stimmt nicht: X, L2/R2 und `/` fehlen, im Raster öffnet der zweite Klick die große Ansicht.

### Wartbarkeit

- `LibraryModel`, `Engine` und `LibraryView` haben je über 1000 Zeilen. Den SDK-Fallback gibt es 7-mal
  (`build.sh`, `tests/*/run.sh`), dazu etwa 10 eigene Process-Helfer und mehrfach definierte Pfadkonstanten.
- **`scripts/install.sh`:** Mit `pipefail` bricht ein leeres grep stumm ab, die Meldung „No release found“ erscheint nie.
  Das Skript steckt nicht in einer Funktion, ein abgeschnittener `curl | bash`-Download läuft deshalb halb.
- **`engine/patches`:** Die Patches werden in Glob-Reihenfolge angewendet. Nummerieren und eine README mit Upstream-Stand anlegen.
