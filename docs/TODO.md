# Nightforge – offene Punkte

Was liegen geblieben ist und irgendwann angegangen werden kann. Stand: 26.10.2026, nach dem
Umstieg auf winecx 4.7.3 mit D3DMetal (PR #7), dem Controller-Paket (PR #8) und dem Code-Audit
(behoben in PR #4, #5, #11, #12, #14–#19, der Rest steht unten unter „Aus dem Code-Audit“).

Neue Punkte unten in den passenden Abschnitt, Erledigtes löschen (die Geschichte steht im Git-Log).
Jeder Punkt nennt, wo man anfängt.

## Nach dem Engine-Wechsel neu prüfen

Die Tests vom 26.10. liefen größtenteils noch auf Wine 11.18 (Gcenx). Seit PR #7 läuft winecx 4.7.3.

- **Getestete Spiele auf winecx gegenprüfen.** Palworld (DXMT, 60 FPS), Deadlock (DXVK, 60–120 FPS),
  Left 4 Dead 2 (WineD3D), OxyRail und 7 Days to Die. Die Ergebnisse und Profile in
  `profiles/mac.json` beziehen sich auf 11.18.
- **Left 4 Dead 2.** Auf 11.18 scheitert DXVK an seinen Puffern (`vkCreateBuffer`, MoltenVK lehnt
  externe Speicher-Handles ab). WineD3D läuft, stürzt aber nach etwa einer Minute ab, und im Spiel fehlte der Ton.
  `-vulkan` (Valves DXVK) und WineD3D mit Vulkan starten nicht. Auf winecx (26.10.) scheitert DXVK schon früher:
  `VK_ERROR_FEATURE_NOT_PRESENT` bei `vkCreateDevice`, weil der Vulkan-Layer dort nicht geladen wird (siehe
  „Aus dem Code-Audit“ → Vulkan-Layer). WineD3D bleibt der Weg. Zum Ton:
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
- **TV-Modus an einem echten TV** (`GameDisplay.swift`, PR #6): Mit einem Monitor am MacBook bestätigt (Fenster
  wandert beim Anstecken, Windows-Spiel öffnet dort, Hauptbildschirm kommt danach zurück). Am TV noch offen: die
  Erkennung am Namen (`Candidate.isTV`, Liste der Marken) und das Vollbild des Launchers.
- **Hinweis „Spielt auf: …“** neben Play, wenn ein externer Bildschirm das Spiel bekommt, damit man weiß, wo es
  aufgeht. Ansatz: `GameDisplay.screen?.localizedName` in `LibraryView`, nur bei mehr als einem Bildschirm.
- **Ton über HDMI.** macOS stellt meist selbst auf den TV um, aber nicht immer. Erst am TV prüfen; falls nötig beim
  Spielstart das Audiogerät des Spiel-Bildschirms wählen (CoreAudio, Transport HDMI/DisplayPort) und danach zurück,
  wie `GameDisplay.enterGame`/`leaveGame` es mit dem Hauptbildschirm machen.
- **Ziel fürs Sofa (28.10.):** MacBook anstecken, Controller einschalten, alles läuft, ohne Maus und Tastatur.
  Was dafür noch fehlt:
  - **Steam-Dialoge per Pad.** EULA, Startoptionen, „Bestätige im Steam-Fenster“ (siehe „Steam und Start“) brauchen
    heute einen Mausklick. Am TV ist das der Moment, in dem man aufstehen muss. Nightforge soll sie per Controller
    bedienbar machen oder die Standardoption selbst wählen.
  - **Zugeklapptes MacBook.** macOS braucht dafür ein Netzteil, und ein Bluetooth-Controller weckt den Mac nicht aus
    dem Ruhezustand. Prüfen, was zugeklappt geht, und Nightforge im Zweifel einen kurzen Hinweis geben lassen
    (Netzteil fehlt, Mac schläft).
  - **Systemabfragen in die Ersteinrichtung.** Rechte für Bluetooth, Bildschirm oder Bedienungshilfen sind mit dem
    Controller nicht erreichbar. Alles, was macOS einmal fragt, in `Setup` erledigen, solange man noch am Mac sitzt.

## Das Maximum aus dem Chip

Ziel (Entscheidung 28.10.): Leistung zuerst. Deshalb bleiben mehrere Übersetzer, und die direkten Wege nach
Metal stehen vorne: Mac-Version (nativ für Apple Silicon) → DXMT/D3DMetal → DXVK über Vulkan → WineD3D.
Ein einheitlicher Vulkan-Stapel wäre einfacher, aber langsamer, und kommt nur als unterste Stufe in Frage
(siehe „Fehlende Engines“).

- **Schnellsten Übersetzer pro Spiel messen statt schätzen.** „Automatisch“ nimmt für DirectX 11 DXMT, D3DMetal
  kann DX11 aber auch und ist bei manchen Spielen schneller. Beim ersten Spielen beide kurz messen und den Sieger
  pro Spiel merken, wie es die gelernte Bildratengrenze schon tut (`FramePacing`, `LearnedFixes` in `LaunchHealth.swift`).
  Größter Gewinn ohne Kosten. Unsichtbar für den Spieler: kein Menü, kein Dialog, kein Neustart mitten im Spiel.
  Ansatz: eine Sitzung mit DXMT, die nächste mit D3DMetal, Bildzeiten aus den Logs vergleichen (DXMT hat dafür
  den `frame-log`-Patch, für D3DMetal einen Weg finden) und danach immer den Sieger nehmen. Stürzt ein Weg ab,
  fällt er still raus. Der Spieler soll nie selbst vergleichen müssen.
- **Leise zeigen, was die Automatik gewählt hat.** In den Spieloptionen eine Zeile wie „Nightforge spielt dieses
  Spiel mit D3DMetal, das lief auf deinem Mac flüssiger“. Kein Regler, aber nachvollziehbar, und hilfreich in
  Problemberichten (`SettingsViews.swift`, `ProblemReport`).
- **Rückweg pro Spiel bei Komponenten-Updates.** Wird ein Spiel mit einem neuen DXMT oder D3DMetal schlechter, bleibt
  es bei der vorherigen Version, statt die schnellere Engine aufzugeben. Baut auf „Nur geprüfte Komponenten
  ausliefern“ auf (vorherige Version bleibt im Manifest, `ComponentStore`).
- **„Mac zuerst“ nur für native Apple-Silicon-Versionen.** Alte Intel-Ports laufen über Rosetta und meist altes
  OpenGL; die Windows-Version über D3DMetal kann deutlich schneller sein. Regel in `MacVersion.swift` anpassen:
  nativ → Mac-Version, Intel-Port → messen oder Windows-Version vorziehen.
- **Render-Auflösung und MetalFX.** Spiele sollen in Punkt-Auflösung rendern (Retina kostet das Vierfache) und
  MetalFX hochrechnen lassen. Wo ein Spiel DLSS anbietet, temporales MetalFX (über `nvngx.dll`) dem räumlichen
  vorziehen, es ist schärfer. Ansatz: `Engine.writeGameConfigs`, Profile.
- **Shader-Caches erhalten.** Für Flüssigkeit zählen die Caches von DXMT (`DXMT_SHADER_CACHE_PATH`) und D3DMetal mehr
  als die FPS im Schnitt. Prüfen, dass sie Spiel- und Komponenten-Updates überleben und nie unnötig gelöscht werden.
- **Hinweis bei Stromsparmodus oder Akku.** macOS drosselt dann spürbar. Vor dem Start kurz sagen
  (`ProcessInfo.isLowPowerModeEnabled`, Netzteil über IOKit `IOPSCopyPowerSourcesInfo`).
- **Spielmodus von macOS sicherstellen.** Er springt nur im Vollbild an. Prüfen, dass Windows-Spiele über
  `Nightforge Game.app` wirklich im Vollbild landen und der Spielmodus aktiv wird.
- **Speicher freimachen.** Bei gemeinsamem Speicher zählt jedes GB. Für schwere Spiele Steam beenden statt nur
  verstecken (`AfterLaunch`), vielleicht automatisch, wenn der Mac wenig RAM hat.
- **MetalFX Frame Generation (ab macOS 26)** als Option für schwere Spiele, die unter dem 60-FPS-Lock bleiben
  (30–40 FPS). Kostet etwas Eingabeverzögerung, deshalb nicht für alle. GPTK 4 nennt Frame Generation als Funktion;
  prüfen, ob D3DMetal sie Spielen anbietet.
- Grenze, die bleibt: Windows-Spiele sind x86-Code und laufen über Rosetta. Schneller geht es nur mit echten
  Apple-Silicon-Ports.

## Fehlende Engines

Recherche vom 27.10. (Stand der Projekte: DXMT 0.80 ist aktuell, D3DMetal 4.0b3 neuer als in CrossOver 26).

- **KosmicKrisp (LunarG, Mesa) als unterste Stufe prüfen.** Vulkan 1.4 auf Metal 4, konform, seit Okt. 2026
  „production ready“ auf Apple Silicon ab macOS 26. Könnte auf einen Schlag DXVK 2.x (mit d8vk für DirectX 8),
  vkd3d-proton (DX12 ohne Apples Lizenz, Plan B) und Zink (OpenGL über Vulkan) möglich machen, vielleicht auch
  bestehende DXVK-Spiele schneller als MoltenVK. Öffentlich hat das noch niemand mit Wine gezeigt. Passt zum
  Vulkan-Loader für winecx (siehe „Aus dem Code-Audit“): KosmicKrisp per ICD-JSON neben MoltenVK. Kommt im Vulkan
  SDK mit (`libvulkan_kosmickrisp.dylib`, `libkosmickrisp_icd.json`).
- **DirectX 12 hat keinen Rückfall.** Scheitert D3DMetal, ist Schluss. winecx bringt Wines `d3d12.dll` (vkd3d) mit,
  das läuft aber über Vulkan und hängt am Vulkan-Loader; vkd3d auf MoltenVK ist früher gescheitert.
  Mit KosmicKrisp neu prüfen.
- **DirectX 9 ist die schwächste Stelle.** Kein Weg direkt nach Metal (DXMT: nur 10/11, D3DMetal: 11/12), nur WineD3D
  über Apples OpenGL 4.1 und DXVK 1.10.3. Betrifft viele Source- und Unity-Klassiker. Wege: DXVK 2.x auf KosmicKrisp,
  langfristig bei DirectX 9 in DXMT mithelfen.
- **DirectX 8 und älter (ddraw)** laufen nur über WineD3D. dgVoodoo2 (DX1–8 → D3D11 → DXMT) wäre ein Weg; erst
  die Lizenz für die Weitergabe prüfen.
- **OpenGL-Spiele** sind auf macOS OpenGL 4.1 begrenzt; was 4.3+ braucht, startet nicht. Weg: Zink auf KosmicKrisp.
- **Winetricks-Zuordnung ergänzen** (`GameLog.winetricksVerb`): XNA Framework (`xna40`) und echtes .NET Framework
  (`dotnet48`) für Spiele und Launcher, bei denen wine-mono nicht reicht.
- **Spuren bei GameSir (GameHub für Mac, github.com/gamesir-labs) beobachten.** GameSir baut wie wir direkt
  auf Metal, ohne KosmicKrisp. Stand 28.10., alles ohne Release:
  - `gamesir-labs/dxmt` (LGPL, Fork von 3Shain): Beschreibung nennt D3D12, D3D11, D3D10 und D3D9, dazu ein
    Testplan „D3D12 auf Metal 4“. Wird das reif, wäre es der Metal-Weg für DirectX 9 und ein DX12-Rückfall ohne
    Apples Lizenz. Austauschbar wie heute DXMT (`components/sources.json`).
  - `gamesir-labs/MGL` (Fork von openglonmetal/MGL): OpenGL 4.6 auf Metal, gegen die OpenGL-4.1-Grenze.
    Lizenz vorher prüfen.
  - `gamesir-labs/rosettax87_jit` (MIT): schnellere x87-Rechnung unter Rosetta für alte 32-Bit-Spiele. Braucht
    eine Debugger-Freigabe (Systemabfrage), also nur, wenn das ohne Hürde für den Nutzer geht.
  Unser Unterschied bleibt das Bedienkonzept: GameHub zeigt viele Regler, Nightforge wählt, misst und lernt selbst.
- **Video im Spiel testen.** winecx bringt `winegstreamer` mit GStreamer und `gptk-video` mit; Zwischensequenzen
  (Media Foundation, H.264 in Unreal/Unity) sind noch nicht gezielt geprüft.

## Voreinstellungen aus offenen Daten und Lernen

Ziel (28.10.): kaum noch einzeln testen. Offene Datenbanken liefern den Start, jeder Mac verfeinert ihn, das
Gelernte fließt zurück in die Profile. Geprüft am 28.10.:

- **Quellen, die gehen** (in `scripts/build-profiles.py` einbauen, nächtlich wie umu-protonfixes):
  - **Steam Deck Verified** (Valve hat tausende Windows-Spiele mit Proton getestet: läuft, Controller komplett,
    Standardeinstellungen flüssig, Text lesbar). Pro Spiel unter
    `store.steampowered.com/saleaction/ajaxgetdeckappcompatibilityreport?nAppID=<id>` (nicht offiziell dokumentiert,
    funktioniert) und lokal in Steams `appinfo.vdf`.
  - **AppleGamingWiki**: 1892 Spiele mit Mac-Bewertung (nativ, Rosetta 2, CrossOver, Wine, Parallels). Export per
    `index.php?title=Special:CargoExport&tables=Compatibility_macOS&fields=_pageName,native,rosetta_2,crossover,wine&format=json`
    (`cargoquery` über die API ist gesperrt). Lizenz CC BY-NC-SA 3.0. Spiele stehen unter ihrem Namen, nicht mit
    Steam-ID: Zuordnung über den Namen braucht Sorgfalt.
  - **ProtonDB**: monatlicher Datensatz `bdefore/protondb-data` (`reports_piiremoved.json`), ODbL + DbCL.
    Startoptionen, Winetricks, Basteleien pro Spiel.
  - Schon im Einsatz: umu-protonfixes, AreWeAntiCheatYet, GeForce Now. DXVK, DXMT und vkd3d haben eigene
    Spiel-Listen eingebaut, die automatisch greifen.
- **Quellen, die nicht gehen:** CrossOver-Datenbank (rund 22.000 Programme, geschlossen), GameHub (geschlossen),
  MacGameDB (App ohne offenen Zugang). PCGamingWiki (DirectX-Version, Engine) blockt automatische Abfragen mit
  einer Bot-Sperre; nicht umgehen, sondern dort um Zugang fragen.
- **Was das Vorab-Profil entscheidet:** Mac-Version oder Windows (AppleGamingWiki), läuft es unter Wine
  (Steam Deck + CrossOver-Bewertung; „unspielbar“ bekommt vor dem Download einen ehrlichen Hinweis wie beim
  Anti-Cheat), Fixes (ProtonDB, umu-protonfixes), Controller (Steam Deck), Anti-Cheat und GeForce Now.
  Beim Installieren kommt `GameAnalysis` dazu (DirectX-Version aus der `.exe`).
- **Lizenzen:** Wegen Share-Alike (CC BY-NC-SA, ODbL) gehören abgeleitete Daten in eigene Dateien mit eigener
  Lizenz und Namensnennung, wie heute `profiles/LICENSE-umu-protonfixes`. NC passt nur, solange Nightforge kostenlos ist.
- **Die Lücke schließt Nightforge selbst.** Keine offene Quelle sagt, ob DXMT oder D3DMetal schneller ist. Das
  übernimmt die Leiter (Absturz → nächste Engine) und die stille Messung (siehe „Das Maximum aus dem Chip“).
- **Nicht nach einem Absturz für immer abschreiben.** Abstürze können am Spiel, an einem Update oder am Netz liegen.
  Eine Engine gilt erst als ungeeignet, wenn sie zweimal am selben Punkt scheitert und die nächste dann läuft
  (`LaunchHealth`, `LearnedFixes`). Sonst lernt die Automatik das Falsche und bleibt auf einem langsameren Weg.
- **Gelerntes veraltet.** Ein Ergebnis gilt nur für einen Stand: Spiel-Build (`buildid` im `appmanifest_<id>.acf`) plus
  Komponenten-Versionen (Engine, DXMT, D3DMetal). Ändert sich einer davon, misst Nightforge still neu.
- **Fair messen.** Die erste Sitzung kompiliert Shader und ruckelt immer. Erst vergleichen, wenn beide Engines einmal
  mit warmem Cache gelaufen sind. Nicht den Durchschnitt vergleichen, sondern die Ausreißer (1-%-Werte), weil
  Flüssigkeit vor FPS geht. Nur Sitzungen mit gleicher Stromversorgung vergleichen (Akku gegen Netzteil verfälscht).
- **Der Chip zählt.** Ein M1 und ein M4 können verschiedene Sieger haben (ab M3 Raytracing in Hardware, dynamischer
  Grafikspeicher). Geteilte Profile nach Chip-Generation trennen.
- **Geteilten Berichten nicht blind trauen.** Die Voreinstellung ändert sich erst, wenn mehrere Berichte von
  verschiedenen Macs übereinstimmen; eigene Messungen gelten mehr als fremde. Prüfung in der GitHub Action.
- **Shader-Caches nicht teilen** (bewusst verworfen): Unter Linux verteilt Steam vorkompilierte Shader, auf dem Mac
  hängen die Caches an GPU und macOS-Version, die Weitergabe wäre technisch und rechtlich heikel. Stattdessen Caches
  nie unnötig verlieren (siehe „Das Maximum aus dem Chip“).
- **Gelerntes teilen, ohne Server und ohne Nutzerdaten.** Ein Bericht enthält nur Spiel-ID, Engine, läuft ja/nein,
  Bildzeit, Chip, macOS- und Nightforge-Version. Kein Name, keine Geräte-ID, keine Bibliothek.
  1. **Jetzt:** nur abholen. Ein Skript exportiert die eigenen gelernten Ergebnisse (des Entwicklers) als
     Profil-PR, Beiträge kommen per PR. Null Nutzerdaten.
  2. **Sobald es Nutzer gibt:** nach einem gelernten Ergebnis einmal „Ergebnis teilen?“, dann öffnet sich ein
     fertig ausgefülltes GitHub-Issue im Browser (wie `ProblemReport`), der Nutzer sieht alles und schickt selbst
     ab. Eine GitHub Action sammelt nachts und macht Profil-Updates. Nightforge speichert nichts, die IP sieht nur
     GitHub. Haken: braucht ein GitHub-Konto, der Benutzername steht am Bericht.
  3. **Nur falls die Konto-Hürde zu viele Berichte verhindert:** anonyme Annahmestelle (z. B. Cloudflare Worker,
     speichert nichts, loggt keine IP), offen dokumentiert. Ist technisch doch ein Mini-Server, der gepflegt werden muss.
  Vorteil der GitHub-Wege: Die Daten liegen öffentlich, jeder sieht, was gesammelt wird, andere Projekte können
  sie nutzen.

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

## Blick von außen: die ersten 15 Minuten

Einschätzung vom 28.10. aus Code, Notizen und Tests (die App wurde dafür nicht neu durchgespielt): Ist ein Spiel
installiert und läuft es, ist der Weg sehr gut, besser als bei der Konkurrenz. Am schwächsten ist der Anfang, und
genau dort entscheidet ein neuer Nutzer, ob er bleibt.

- **Installation per Terminal.** Die README schickt Nutzer zu `curl … | bash`. Für normale Mac-Nutzer ist das
  fremd und wirkt unsicher. Die DMG ist nicht notarisiert, also blockt Gatekeeper beim ersten Öffnen. Hängt an der
  Entscheidung zur Signatur (siehe „Aus dem Code-Audit“ → Entscheidungen): Mit Developer ID und Notarisierung wäre
  es „DMG laden, in Programme ziehen, fertig“. Bis dahin mindestens die DMG als ersten Weg in der README, mit
  einem Satz und Bild zu „Rechtsklick → Öffnen“.
- **Ersteinrichtung ist lang und hat Hürden:** Passwort für Rosetta, rund 11 Minuten Steam-Update auf einem frischen
  Prefix (siehe „Aus dem Code-Audit“ → Steam und Start), Anmeldung. Jeder Schritt braucht eine ehrliche
  Fortschrittsanzeige und einen Grund, warum er nötig ist (ROADMAP 1.1).
- **Zwei Steams melden sich gegenseitig ab** („Session Replaced“, siehe „Steam und Start“). Für den Nutzer wirkt
  das wie ein Fehler. Nightforge sollte das abfangen oder in einem Satz erklären.
- **Erster Start eines Spiels ruckelt** wegen der Shader und sieht ohne Erklärung kaputt aus (ROADMAP 1.1,
  „Preparing shaders …“).
- **Nur Steam.** Epic kommt (Branch `claude/ux-roadmap-next`), GOG, EA app, Ubisoft und Battle.net fehlen noch.
- **Wenig nachweislich geprüfte Spiele.** Eine kleine Liste „geprüft läuft“ schafft Vertrauen (siehe
  „Ehrlich sagen, was geht“), die Vorab-Profile aus offenen Daten machen sie schnell länger.

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
- **Tests in der CI** laufen seit PR #5 (`ci.yml`: Build, alle `tests/*/run.sh`, Profil- und Manifest-Prüfung).
  Offen: dieselben Tests als Pflicht für die Bot-PRs aus dem Punkt darüber. Echte Spiele bleiben Handarbeit.
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

Befunde vom 26.10., die noch offen sind. Alles andere ist behoben (PR #4, #5, #11, #12, #14–#19).

### Entscheidungen

- **Updates sind nicht echt signiert.** `Updater.install` prüft nur `codesign --verify` auf eine Ad-hoc-Signatur,
  `scripts/install.sh` lädt ohne Prüfsumme. Bewusst offen gelassen. Wege: ein Ed25519-Schlüssel als Repo-Secret
  (Release-Zip signieren, im Updater und in install.sh prüfen) oder ein Apple-Developer-Account (Developer ID, Notarisierung).

### Vulkan-Layer und winecx

- **winecx hat keinen Vulkan-Loader, der Layer wird nie geladen.** Seine `winevulkan.so` lädt `libMoltenVK.dylib`
  direkt (Gcenx' 11.18 ging über `libvulkan.1.dylib`), also findet sich kein Layer aus
  `Nightforge Game.app/…/implicit_layer.d`. Seit PR #7 fehlen damit für Vulkan- und DXVK-Spiele: das Aussortieren
  nicht unterstützter Funktionen (No Man's Sky, DXVK in L4D2 scheitert genau daran), die Sampler-Grenze, der HDR-Filter
  und MetalFX. Ansatz: den Khronos-Loader (aus der Gcenx-Engine oder MoltenVK-Release) in die winecx-Engine legen und
  winevulkan auf ihn lenken (Name `libMoltenVK.dylib` → Loader, MoltenVK per ICD-JSON), dabei die „MoltenVK-ICD-Falle“
  aus den Game-Mode-Notizen beachten. Erst danach lässt sich PR #13 im Spiel prüfen.
- **PR #13** (Entwurf): Layer-Fixes (freigegebene `CAMetalLayer`, Speicherleck pro Frame, Abbau, Retina pro Fenster).
  Kompiliert, aber ungetestet, weil der Layer unter winecx nicht läuft (siehe oben).
- **MetalFX auf der exportierten Metal-Queue** verlässt sich darauf, dass MoltenVK synchron einreicht. Mit
  `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0` könnte das Upscaling ein halbfertiges Bild lesen.
- **`steamwebhelper-wrapper.c`** startet den echten Helper ohne Job-Object. Wird der Wrapper beendet, bleibt CEF
  verwaist (passt zu den bekannten Shutdown-Hängern).

### Lieferkette

- **Nächtliche Daten gehen ungeprüft an alle.** `components.yml` und `profiles.yml` committen direkt auf `main`,
  umu-protonfixes und AreWeAntiCheatYet werden ab `HEAD` gelesen. Siehe „Nur geprüfte Komponenten ausliefern“ oben.
- **Build-Eingaben ohne Prüfsumme.** In `graphics.yml` `WINE_TOOLCHAIN_URL`, das Gcenx-Archiv, der inotify-Header und
  Klone per Tag, in `tools.yml` das cabextract-Archiv; dazu `brew install … || true`. Die Actions selbst sind seit dem
  Audit auf Commit-SHAs festgelegt, Dependabot hält sie aktuell.
- **Dependabot-PRs #21–#26** (cache 4→6, upload-artifact 4→7, download-artifact 4→8, setup-python 5→7) erst nach
  einem Release- oder Grafik-Build mergen. Ihre grünen Checks laufen nicht durch `release.yml` und `graphics.yml`, die
  diese Actions nutzen. upload- und download-artifact zusammen hochziehen.
- **Erster Lauf der Lizenz-Pakete (PR #14).** Nach den ersten Releases mit Lizenzen und Quellarchiv prüfen, dass
  `update-components.py` weiter genau ein Asset pro Komponente findet. Beim nächsten DXMT-Update die Lizenz prüfen
  (v0.80 ist MIT, neuere DXMT-Versionen LGPL).

### Steam und Start

- **Steams erstes Update auf einem frischen winecx-Prefix dauert rund 11 Minuten**: Der alte Bootstrapper startet alle
  13 s neu (164 Installationsläufe, „Bad NTFS transaction canary“), bis das Update durch ist. Die Einrichtung wartet
  das ab, aber für neue Nutzer ist es lang. Mit 11.18 vergleichen; vielleicht hilft ein Neustart von Steam durch
  Nightforge, sobald das Paket geladen ist.

### Leistung

- **Downloads:** Alle 3 s läuft ein kompletter Rescan mit `folderSize` über `downloading/<id>`. Nur die Manifeste der
  ladenden Spiele neu lesen und die Ordnergröße cachen.
- **SwiftUI:** `LibraryModel` ist ein `ObservableObject` mit 26 `@Published`, jede Änderung zeichnet alles neu.
  `@Observable` (ab macOS 14) oder das Modell aufteilen.
- **`MacSteam`** hat eine 1-Hz-Schleife; eine Exit-Quelle (`DispatchSource.makeProcessSource`) wäre ruhiger.

### Wartbarkeit

- `LibraryModel`, `Engine` und `LibraryView` haben je über 1000 Zeilen. Den SDK-Fallback gibt es 7-mal
  (`build.sh`, `tests/*/run.sh`), dazu etwa 10 eigene Process-Helfer und mehrfach definierte Pfadkonstanten.
- **`engine/patches`:** Die Patches werden in Glob-Reihenfolge angewendet (`frame-log` baut auf `metalfx-fit-window`
  auf, sortiert aber davor). Nummerieren und eine README mit Upstream-Stand anlegen; ein Umbenennen löst auf `main`
  einen neuen Grafik-Build aus.
