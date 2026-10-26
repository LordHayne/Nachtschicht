# Nightforge – UX-Roadmap

> Ziel: **ein wirklich nahtloses Erlebnis – eine App, die man gerne verwendet.**
> Diese Roadmap ist so geschrieben, dass Claude Code (CC) sie Punkt für Punkt abarbeiten kann.
> Stand: 26.10.2026 · Basis: `main@9fc8467`

---

## So arbeitest du damit mit Claude Code

1. **Ein Punkt pro Sitzung/Branch.** Prompt-Vorlage:
   > Lies `docs/ROADMAP.md` und den Abschnitt „Regeln für jeden Punkt“. Setz Punkt **1.3** um. Schau dir vorher das Design dazu an (`npx -y magicpath-ai inspect solidly-valley-2097 -o json`, Datei siehe „Design“). Arbeite auf einem eigenen Branch, schreib Tests wie in `tests/`, und hak den Punkt hier ab, wenn alle „Fertig wenn“-Kriterien erfüllt sind.
2. **Reihenfolge:** Phase 0 zuerst – darauf bauen fast alle anderen Punkte auf. Innerhalb einer Phase ist die Reihenfolge frei, außer bei „Braucht“.
3. **Abhaken:** `- [ ]` → `- [x]` und den Commit/PR dahinter schreiben.

### Design-Referenz

- **Klickbarer Entwurf (MagicPath):** https://www.magicpath.ai/files/464423826076372992 – Komponente `solidly-valley-2097` („Nachtschicht Library“). Quellcode lesen: `npx -y magicpath-ai inspect solidly-valley-2097 -o json`. Der Entwurf ist React/Tailwind und **nur Vorlage** – in SwiftUI nachbauen, nicht übernehmen. Dateien im Entwurf:
  - `NachtschichtLibrary.tsx` – Navigation, Startablauf, Downloads, Sitzungsende (die ganze Logik als Referenz)
  - `Home.tsx`, `Library.tsx`, `Detail.tsx` – die drei Ebenen
  - `Parts.tsx` – Play-Button-Zustände (`playLabel`, `playHint`), Kompatibilitäts-Abzeichen
  - `Cover.tsx` – Cover-Abzeichen
  - `Dialogs.tsx` – Optionen, Einstellungen (Tabs), Deinstallieren, Fehlstart
  - `Overlays.tsx` – Sitzungsabschluss, Platz-Dialog, Download-Panel, Ersteinrichtung
  - `data.ts` – Datenmodell (Provider, Kompatibilität, Spielstände, Laufwerke …)
- **Design-System (Tokens, Typo, Logos):** https://claude.ai/code/artifact/7e195660-f21f-4d6a-92ed-b22a7ec8355d – Werte stammen aus `Theme.swift` und den Views.

### Regeln für jeden Punkt

- **Texte:** Jeder sichtbare Text über `L10n.t`, **Englisch und Deutsch**. Layout muss die längere deutsche Fassung tragen.
- **Couch:** Jede neue Steuerung bekommt `.padFocus(…)`; jede Aktion hat einen Tasten- und einen Controller-Weg; die `HintBar` zeigt, was gerade gilt.
- **Farben/Typo:** nur aus `Theme` (night, slate, ink, muted, sodium). `sodium` = die eine Hauptaktion / Auswahl / Fokus – nie Deko. Neue Farben (z. B. Kompatibilität) als benannte `Theme`-Konstanten, nie inline.
- **Kein Warten ohne Erklärung, kein Fehler ohne Ausweg.** Jeder Ladezustand sagt, worauf er wartet; jede Fehlermeldung bietet mindestens eine Aktion.
- **Datenschutz:** kein Account, keine Telemetrie. Alles, was den Mac verlässt, nur nach ausdrücklichem Opt-in.
- **Offline zuerst:** UI reagiert sofort aus lokalen Daten; Netzwerk lädt im Hintergrund nach.
- **Tests:** Logik ohne UI (Sortierung, Suche, Kompatibilität, Speicherprüfung …) als Test unter `tests/<Name>Test/` mit `run.sh`, wie die bestehenden.
- **Nordstern-Messwert:** Zeit vom App-Start bis das Spiel läuft – Ziel **< 10 s** bei einem installierten Spiel. Kein Punkt darf das verschlechtern.

### Größen

`S` ≈ eine Sitzung · `M` ≈ 2–3 Sitzungen · `L` ≈ eine Woche oder mehr / braucht Recherche

---

## Phase 0 – Fundament

- [x] **0.1 Navigation in drei Ebenen** · `L` · Branch `claude/ux-navigation-0-1`
  - **Warum:** Heute zeigt die Leiste alle Spiele (bei 100+ Spielen unbenutzbar), der zweite Klick startet/lädt sofort (versehentliche 50-GB-Downloads), und die Bibliothek ist ein Schalter statt einer Ebene – Zurück führt nicht dorthin, wo man herkam.
  - **Was:** `LibraryModel.showingLibrary` durch eine Route ersetzen: `home` → `library` → `detail(gameID, from:)`. Esc/B geht immer eine Ebene zurück (zuerst Suche leeren, dann Ebene).
    - **Home:** Hero des gewählten Spiels + Leiste „Continue playing“ (siehe 1.7) + letzte Kachel „All games“.
    - **Library:** bestehendes `LibraryGrid` als eigene Ebene (Filter kommen in 2.1).
    - **Detail:** heutige Hero-Ansicht als Spielseite, mit Zurück-Pille („← Home“ / „← Library“).
    - **Klickverhalten:** Klick auf Cover = auswählen, zweiter Klick = **Detailseite**, nie Start. Gestartet wird nur über den Play-Button oder Enter/A.
    - Top-Bar: Segment „Home | Library (Anzahl)“.
  - **Wo:** `LibraryView.swift` (TopBar, CoverRail, GameDetail), `LibraryGrid.swift`, `LibraryModel.swift` (`toggleLibrary`, `showSelectedGame`, `primaryAction`), `InputRouter.swift`.
  - **Design:** `NachtschichtLibrary.tsx` (View-State, `back()`), `Home.tsx`, `Detail.tsx`.
  - **Fertig wenn:** Doppelklick auf ein nicht installiertes Cover startet keinen Download; Esc aus einer Detailseite, die aus der Bibliothek geöffnet wurde, landet in der Bibliothek an derselben Scroll-Position; alles per Controller erreichbar.
  - **Stand:** `Route` (`home` / `library` / `detail(gameID, from:)`) in `Navigation.swift`, Übergänge in `LibraryModel` (`goHome`, `goLibrary`, `openDetail`, `back`, `activate`); jede Ebene merkt sich ihre Auswahl. Home-Leiste vorläufig `HomeRail.pick` (Downloads, dann installiert nach „zuletzt gespielt“, max. 12) + Kachel „All games“ – Pins und 90 Tage kommen mit 1.7. Die Bibliothek bleibt hinter einer aus ihr geöffneten Detailseite stehen (unsichtbar), daher dieselbe Scroll-Position. Suche springt in die Bibliothek. Tasten: ↩ spielt (Home) / öffnet (Bibliothek) / spielt (Detail), I Details, L Home ↔ Bibliothek, Esc zurück. Pad: A wie ↩, X Details, ☰ Home ↔ Bibliothek, Y Optionen, B zurück; ↑ von der Leiste/obersten Rasterzeile in die Knöpfe, auf der Detailseite steuert der Stick die Knöpfe. Test `tests/NavigationTest/` (Leiste, Ebenen); die Übergänge mit dem echten Model gegen die echte Bibliothek durchgespielt. Nebenbei behoben: lange Hinweistexte (`fixedSize` vertikal) konnten das Fenster auf über 2500 pt Höhe ziehen (z. B. Mac-Hinweis bei 7 Days to Die) – sie haben jetzt eine Mindestbreite.

- [ ] **0.2 Anbieter-neutrales Spielmodell** · `M`
  - **Warum:** `Game.appID` ist eine Steam-ID. Für Epic/GOG (Phase 7) und „ein Spiel in zwei Stores = eine Karte“ braucht es eine neutrale ID – vor dem großen UI-Umbau, sonst doppelte Arbeit.
  - **Was:** `GameID { provider, id }`, `Game.providers: [Provider]` (erster = Standard zum Starten), `ArtworkStore`/Caches/Optionen auf die neue ID umstellen, Migration bestehender Einstellungen (`GameOptionsStore`, Insights) wie in `Migration.swift`.
  - **Wo:** `Library.swift`, `LibraryModel.swift`, `Artwork.swift`, `Launcher.swift` (`GameOptionsStore`), `Migration.swift`.
  - **Design:** `data.ts` (`Game`, `Provider`).
  - **Fertig wenn:** Nur Steam funktioniert wie vorher; bestehende Spieloptionen bleiben nach dem Update erhalten (Test).

- [x] **0.3 Toasts mit Aktion** · `S` · PR #9, benutzt seit `claude/ux-hide-pin-1-4`
  - **Was:** Leichtgewichtige Meldung unten mittig mit optionalem Button („Undo“, „Play“, „Show“), Auto-Ausblenden (2,8 s, mit Aktion 5 s), per Controller erreichbar.
  - **Design:** `NachtschichtLibrary.tsx` (`notify`), Toast-Markup.
  - **Fertig wenn:** Wird von 1.4 (Undo), 4.4 (Download fertig → Play) benutzt.
  - **Stand:** Komponente fertig – `Toast.swift` (`Toasts.shared.show(_:action:)`, `ToastHost` im Hauptfenster, Aktion per ⌘↩ oder Pad, HintBar zeigt sie, VoiceOver liest vor, „Reduce motion“ nur Überblenden). Benutzt von 1.4 (Ausblenden → „Undo“, Anheften) und vom fertigen Download („<Spiel> is ready to play“ → „Play“, Teil von 4.4).

---

## Phase 1 – Schnelle Gewinne mit vorhandenen Daten

- [ ] **1.1 Ehrliche Wartezustände beim Start** · `M` · braucht 0.1
  - **Warum:** Ein Launcher, der 40 s „Launching …“ zeigt, wirkt kaputt. Shader-Kompilierung beim ersten Start/nach Updates ist normal – man muss es nur sagen.
  - **Was:** Startphasen auf dem Play-Button, je mit Erklärzeile darunter:
    - „Starting Steam …“ (Steam unsichtbar im Hintergrund)
    - „Preparing shaders … N %“ (erster Start / nach Grafik-Update; Fortschritt wenn ermittelbar, sonst unbestimmt)
    - „Launching …“
  - **Wo:** `LibraryModel.launchStatus` existiert bereits → zu einem Enum `LaunchPhase` ausbauen; Quellen: `Launcher.swift` (Steam-Konsolen-Log), `GameLog.swift`, DXMT/DXVK-Shader-Cache-Ordner (prüfen, ob leer/neu).
  - **Design:** `Parts.tsx` → `LaunchPhase`, `playLabel`, `playHint`.
  - **Fertig wenn:** Jede Phase > 2 s hat einen eigenen Text; nach einem Grafik-Update zeigt der erste Start „Preparing shaders“, der zweite nicht.

- [ ] **1.2 Fehlstart mit Lösung statt Sackgasse** · `M`
  - **Was:** Das heutige Alert „didn't start“ wird zum Sheet: Erklärung + **„Start with ‚Most compatible‘“** (Primär) + **„Start through <anderer Store>“** (wenn vorhanden) + „Report problem“ (bestehend).
  - **Wo:** `LibraryView.swift` (`failedLaunch`-Alert), `LaunchHealth.swift` (Attempts), `ProblemReport.swift`.
  - **Design:** `Dialogs.tsx` → `LaunchFailedDialog`.
  - **Fertig wenn:** Kein Fehlstart endet ohne mindestens eine Aktion außer „OK“.

- [ ] **1.3 Kompatibilitäts-Abzeichen („Runs great“)** · `M`
  - **Warum:** „Läuft das überhaupt?“ ist die erste Frage. Steam Deck Verified hat gezeigt, wie viel klare Stufen bringen – für den Mac gibt es so etwas nicht.
  - **Was:** Stufen `great` / `tweaks` / `no` / `untested`, immer **Icon + Wort** (nie nur Farbe). Ableitung lokal:
    - `no`: `AntiCheatBlock` (ohne GeForce Now), VR-only
    - `tweaks`: Profil mit Fixes / `LearnedFixes` / Anti-Cheat nur online / D3D12-only
    - `great`: Nightforge-eigenes Profil oder erfolgreiche Starts ohne Fixes
    - `untested`: sonst
    - Optional Zeile „Tested on M2, M3“ (wenn das Profil das hergibt).
  - **Wo:** neu `Compatibility.swift`; Quellen `Profiles.swift`, `LaunchHealth.swift` (`LearnedFixes`), `GameAnalysis.swift`. Anzeige: Hero-Metazeile, Detail-Karte „On a Mac“, Rasterkarte, Filter (2.1).
  - **Design:** `Parts.tsx` → `CompatBadge`; `Detail.tsx` → `CompatCard`.
  - **Fertig wenn:** Jedes Spiel hat eine Stufe; Unit-Test für die Ableitung; Kontrast ≥ 4,5:1 auf `night`.
  - **Stand:** Ableitung, Abzeichen und Test fertig – `Compatibility.swift` (`Compatibility.of(game, profile:, analysis:)`, `CompatibilityBadge`), `tests/CompatibilityTest/` (inkl. Kontrast). Farben `Theme.runsGreat / runsWithTweaks / runsNot`; „Tweaks“ bewusst blasser als `sodium`. Mit GeForce Now bleibt die Stufe `no`, die Notiz verweist auf GeForce Now (wie im Entwurf). Angezeigt in Home-Hero (Abzeichen), Detailseite (Abzeichen + Notiz + „Tested on“) und Rasterkarte (Symbol vor dem Namen) seit 0.1. Filter „Runs great“ seit 2.1.

- [x] **1.4 Spiele ausblenden & anpinnen** · `S` · braucht 0.3 · Branch `claude/ux-hide-pin-1-4`
  - **Was:** Detailseite: „Hide from library“ (Taste H) mit Undo-Toast; Bibliothek: Umschalter „Hidden (n)“ zum Zurückholen. „Pin to Home“ (Taste P): bleibt in der Home-Leiste, auch wenn lange nicht gespielt; Pin-Abzeichen auf dem Cover.
  - **Wo:** `Prefs` (UserDefaults), `LibraryModel`, `LibraryGrid`.
  - **Design:** `Detail.tsx` (Buttons), `Library.tsx` (Hidden-Toggle), `Cover.tsx` (Pin).
  - **Fertig wenn:** Ausgeblendete Spiele erscheinen weder in Home noch in Suche/Raster (außer im Hidden-Filter); bleibt über Neustarts erhalten.
  - **Stand:** `GameMarks.swift` (UserDefaults `library.hidden` / `library.pinned`, nach App-ID – überlebt den Wechsel Mac ↔ Windows-Version). Detailseite: Augen- und Pin-Knopf (H / P, per Pad erreichbar), „Hidden“-Chip; Ausblenden schließt die Seite und zeigt einen Toast mit „Undo“ (holt auch den Pin zurück). Bibliothek: Leiste über dem Raster mit Schalter „Hidden n“ (nur wenn es welche gibt); Esc schaltet ihn zuerst aus. Angeheftete Spiele stehen vorne in der Home-Leiste (nach Name), Pin-Abzeichen auf dem Cover. Zähler (Bibliothek, „All games“) ohne ausgeblendete Spiele. Tests in `tests/NavigationTest/` (Pins in der Leiste, Speichern/Laden); Ablauf mit dem echten Model durchgespielt.

- [x] **1.5 Suche mit Abkürzungen** · `S` · Branch `claude/ux-search-1-5`
  - **Was:** „rdr2“ → Red Dead Redemption 2, „bg3“ → Baldur's Gate 3 (Anfangsbuchstaben + Ziffern), Wortanfänge zuerst. Store-Treffer bleiben eigener Abschnitt.
  - **Wo:** `LibraryModel.searchKey` / `applyFilter`.
  - **Design:** `data.ts` → `searchMatches`, `searchRank`.
  - **Fertig wenn:** Test mit rdr2, bg3, „witcher“, „gate 3“, Umlauten.
  - **Stand:** `Search.swift` (`Search.rank(name:query:)`: 0 Wortanfänge, 1 Initialen mit Zahlen, 2 irgendwo im Namen). Apostroph verbindet („Baldur's“ → bg3), andere Zeichen trennen („Half-Life“ → hl2, „S.T.A.L.K.E.R.“ → stalker). `applyFilter` sortiert danach, innerhalb gleicher Stufe Bibliotheksreihenfolge. Test `tests/SearchTest/`.

- [ ] **1.6 „Credits & Lizenzen“ + Datenschutz-Seite** · `S` · (Teil von 2.2)
  - **Was:** Liste aus `components/manifest.json` (Name, Version, Lizenz – Felder sind schon da) plus umu-protonfixes (BSD-2) und AreWeAntiCheatYet (MIT); Satz „No account. No telemetry. No background service.“
  - **Design:** `Dialogs.tsx` → Tab „About“.
  - **Fertig wenn:** Jede mitgelieferte Komponente steht mit Lizenz drin, automatisch aus dem Manifest.

- [x] **1.7 Home-Leiste = „Continue playing“** · `S` · braucht 0.1, 1.4 · Branch `claude/ux-continue-1-7`
  - **Was:** Angepinnte zuerst, dann installiert/ladend und in den letzten 90 Tagen gespielt, max. 12; letzte Kachel „All games · N“.
  - **Design:** `data.ts` → `continuePlaying`; `Home.tsx` → `Rail`.
  - **Fertig wenn:** Bei 100+ Spielen enthält die Leiste ≤ 13 Elemente.
  - **Stand:** `HomeRail.pick` – Angeheftete (nach Name), dann Downloads, dann installiert und in den letzten 90 Tagen gespielt (neueste zuerst), max. 12, plus Kachel „All games“. Abweichung: Sind es weniger als 3 (neue Bibliothek), füllen andere installierte Spiele auf, damit Home nie leer ist. Überschrift „Continue playing · Pinned, then what you played lately“. Kopfzeile: Bereichsschalter schrumpft nicht mehr, die Suche wird bei schmalem Fenster schmaler. Test in `tests/NavigationTest/`.

- [ ] **1.8 „Update & Play“** · `M`
  - **Warum:** „Play“ wird sonst überraschend zu einem 8-GB-Download.
  - **Was:** Steht ein Pflicht-Update an, zeigt der Button vorher „Update & Play · 1.2 GB“; nach dem Update startet das Spiel von selbst. Update-Abzeichen auf dem Cover.
  - **Wo:** `Library.swift` (appmanifest – `StateFlags`/`UpdateResult`/`BytesToDownload` prüfen und verifizieren), `LibraryModel.primaryAction`.
  - **Design:** `Parts.tsx` (`Update & Play`), `NachtschichtLibrary.tsx` (`playAfterUpdate`).
  - **Fertig wenn:** Update-Größe ist vor dem Klick sichtbar; nach Ende des Updates startet das Spiel ohne weiteren Klick.

---

## Phase 2 – Bibliothek, Einstellungen, Optionen

- [x] **2.1 Bibliothek mit Filtern & Sortierung** · `M` · braucht 0.1, 1.3 · Branch `claude/ux-library-filters-2-1`
  - **Was:**
    - **Filter:** „All / On this Mac / Not downloaded“, pro Store (mit Anzahl, Warnsymbol bei Sync-Fehler), „Runs great“, „Controller“, „Mac version“, „Hidden“.
    - **Sortierung:** Recently played / Name / Size.
    - **Suche:** Treffer in einer Liste, beste zuerst.
  - **Wo:** `LibraryGrid.swift` (Sections), `LibraryModel`.
  - **Design:** `Library.tsx`.
  - **Fertig wenn:** Filter kombinierbar, Zustand bleibt beim Wechsel Detail ↔ Bibliothek erhalten, alles per Controller bedienbar.
  - **Stand:** `LibraryFilters.swift` (Status All / On this Mac / Not downloaded, „Runs great“, „Controller“ = volle Unterstützung, „Mac version“; Sortierung Recently played / Name / Disk space) und `LibrarySection.make` (Suche = eine Trefferliste, beste zuerst; Hidden = nach Name; „Recently played“ gruppiert nach Installiert / Lädt / Rest; Name/Größe eine Liste; Store-Treffer zuletzt). Leiste über dem Raster (nicht mitscrollend): Titel + „n von m Spielen“, Hidden-Schalter, Sortierung; darunter Status und Filter – jedes Segment ein eigener Pad-Knopf (↑ aus der obersten Rasterzeile). Filter gelten nur in der Bibliothek (Home bleibt vollständig) und bleiben über Detailseite und Home hinweg erhalten. Leeres Ergebnis: „No games match these filters“ + „Clear filters“. Pro-Store-Filter kommt mit Phase 7 (heute nur Steam). Test `tests/LibraryFiltersTest/`.

- [ ] **2.2 Einstellungen in Tabs** · `M` · Branch `claude/ux-settings-2-2` (2 von 5 Tabs)
  - **Was:** Tabs `Stores` · `General` · `Controller` · `Storage` · `About`. Inhalte siehe 1.6, 4.3, 5.4, 2.5.
  - **Wo:** `SettingsViews.swift` (`SettingsView`).
  - **Design:** `Dialogs.tsx` → `SettingsDialog`.
  - **Stand:** `SettingsView.swift` mit Tab-Leiste (eigene Pad-Knöpfe): **Stores** (Steam: angemeldet/Spiele, „Open Steam“; CrossOver/Whisky/eigenes Wine), **General** (wie bisher). `SettingsView(tab:)` öffnet direkt einen Tab. Offen: Tabs **About** (kommt mit 1.6), **Storage** (4.3) und **Controller** (5.4), Schalter aus 2.5/3.4/5.1 in General.

- [ ] **2.3 Grafik-Voreinstellungen in Klartext + Profil-Herkunft** · `M`
  - **Was:** In den Spieloptionen statt Einzelschaltern zuerst vier Voreinstellungen:
    - **Automatic (recommended):** bisheriges Verhalten.
    - **Fastest / Balanced / Most compatible:** werden auf `GraphicsLayer`, Frame-Limit und MetalFX gemappt.
    - **Expertenoptionen** darunter.
    - **Kopfzeile:** „Tested by Nightforge · updated 5 days ago“ bzw. „Community fix · from umu-protonfixes“, dazu „Reset to profile“.
    - **Detailseite:** Karte „This game“ zeigt Store, Version, Grafik, HUD, Startoptionen, Engine, Offline-Status sowie „Your own settings … Back to the profile“.
  - **Wo:** `SettingsViews.swift` (`GameOptionsSheet`), `Launcher.swift` (`GameOptions`, `GraphicsLayer`), `Profiles.swift`.
  - **Design:** `Dialogs.tsx` → `GameOptionsDialog`; `Detail.tsx` → `OptionsSummary`; `data.ts` → `PRESETS`.

- [ ] **2.4 „Bereit für offline“** · `M` · Recherche
  - **Was:** Pro Spiel: „Ready“ oder „Start online once“. Steams Offline-Modus muss vorher online aktiviert worden sein – herausfinden, woran man das erkennt (z. B. `loginusers.vdf`, letzter erfolgreicher Online-Start).
  - **Design:** `Detail.tsx` → Zeile „Offline“.

- [ ] **2.5 Barrierefreiheit** · `S`
  - **Was:** „Reduce motion“ (folgt `NSWorkspace.accessibilityDisplayShouldReduceMotion`, abschaltbar): kein Lampen-Flackern, kein Cover-Zoom, nur Überblenden. „Larger text“ (eine Stufe größer). VoiceOver-Labels für alle Icon-Buttons und Abzeichen.
  - **Design:** `Dialogs.tsx` → Tab „General › Accessibility“; `index.css` (`.ns-reduce`).

---

## Phase 3 – Der Kreis ums Spielen

- [ ] **3.1 Sitzungsabschluss („Welcome back“)** · `M`
  - **Warum:** Wir denken bisher nur bis zum Start. Am Ende will man wissen: Ist der Spielstand sicher, kann ich zuklappen?
  - **Was:** Wenn das Spiel endet (Nightforge kommt ja schon nach vorne), Sheet mit:
    - Spielzeit dieser Sitzung und gesamt
    - Spielstand-Status: „Uploading to Steam Cloud …“ → „Save is in Steam Cloud. You can close your Mac.“ (bzw. „Saved on this Mac only“)
    - „How did it run?“ 👍/👎 (als Icons) mit Gründen (Stutters, Crashed, Low frame rate …); bei Abstürzen/Ruckeln das Angebot „Use ‚Most compatible‘ next time“
    - Buttons „Play again“ / „Done“
  - **Wo:** `LibraryModel` (Erkennung Spielende), Steam-Cloud-Status aus dem Steam-Log/`remotecache.vdf` (recherchieren), `SaveTransfer.swift` (Speicherorte).
  - **Design:** `Overlays.tsx` → `SessionSummary`.
  - **Fertig wenn:** Erscheint nach jedem Spielende; die Bewertung wird lokal gespeichert und fließt in 1.3 (eigene Erfahrung schlägt Profil).

- [ ] **3.2 Spielstand-Konflikt lösen, bevor etwas überschrieben wird** · `L` · Recherche
  - **Was:** Weichen lokaler und Cloud-Spielstand voneinander ab: Vor dem Start „Keep this Mac · today 14:02 (Newer)“ vs. „Keep the cloud · yesterday“; der andere wird als Backup im Spielordner behalten. Play zeigt bis dahin „Choose a save first“.
  - **Wo:** `SaveTransfer.swift`, `SteamCatalog.SaveRule`.
  - **Design:** `Detail.tsx` → `SaveChoice` (+ kompakte Variante in `Home.tsx`).
  - **Fertig wenn:** Kein Szenario, in dem Nightforge stillschweigend einen neueren Spielstand verliert (Test mit Fake-Ordnern).

- [ ] **3.3 Automatisches Zurückrollen der Engine** · `L` · braucht 1.1
  - **Warum:** macOS-/Wine-Updates machen Spiele kaputt, die gestern liefen (siehe Whisky). Selbst-Heilung ist ein echtes Alleinstellungsmerkmal.
  - **Was:**
    - Pro Spiel die letzte funktionierende Kombination aus Engine und Grafikschicht merken.
    - Die vorige Engine-Version bleibt installiert (`ComponentStore`).
    - Stürzt ein Spiel nach einem Update beim Start ab: automatisch mit der alten Version starten. Phase „Trying last week's engine …“, danach Hinweis „Runs with last week's engine … Try the newest now“.
    - Nach dem nächsten Engine-Update wird automatisch wieder die neue versucht.
  - **Wo:** `Components.swift` (`ComponentStore`, Versionen), `LaunchHealth.swift`, `Engine.swift`.
  - **Design:** `Parts.tsx` (`rollback`-Phase), `Detail.tsx` (Engine-Hinweis, Zeile „Engine … (held back)“).
  - **Fertig wenn:** Ein simuliertes kaputtes Engine-Update führt zu einem erfolgreichen Start mit der alten Version, ohne dass der Nutzer etwas tun muss.

- [ ] **3.4 Akku-Modus** · `S`
  - **Was:** Ohne Netzteil (IOKit `IOPSCopyPowerSourcesInfo`): Bildrate auf 30 FPS begrenzen, Hinweis „On battery: capped at 30 FPS – about 1 h 40 min of play“, Akkustand in der Top-Bar. Abschaltbar in General. Grundlage für die Begrenzung: `FramePacing.swift`.
  - **Design:** `Parts.tsx` (`playHint` mit `onBattery`), Top-Bar-Akku.

---

## Phase 4 – Speicherplatz & Downloads

- [ ] **4.1 Platz prüfen vor dem Download** · `M`
  - **Was:** Ist zu wenig Platz frei: Dialog „<Spiel> needs 49.5 GB – 18.5 GB short“ mit (a) „Install on <externe SSD>“ und (b) „Make room“. Vorgeschlagen werden lange nicht gespielte Spiele (Größe, zuletzt gespielt, „saves stay in the cloud“), vorausgewählt bis es reicht → „Uninstall n & download“.
  - **Design:** `Overlays.tsx` → `SpaceDialog`.
  - **Fertig wenn:** Kein Download startet, der mangels Platz abbrechen würde.

- [ ] **4.2 Spiele auf externen Laufwerken** · `L` · Recherche
  - **Was:** Steam-Bibliotheksordner auf externen Volumes anlegen/erkennen (`libraryfolders.vdf`), Spiele dorthin installieren und zwischen Laufwerken verschieben. Ist das Laufwerk nicht angeschlossen: Spiel ausgegraut mit „Connect Samsung T7 to play“.
  - **Design:** `Detail.tsx` (Stat „On“), `Dialogs.tsx` → Tab „Storage“ (Move to …).

- [ ] **4.3 Speicher-Übersicht & sauber entfernen** · `M`
  - **Was:** Tab „Storage“:
    - **Balken pro Laufwerk:** Spiele / Nightforge / Rest.
    - **Installierte Spiele:** nach Größe sortiert, jeweils mit „Move to …“.
    - **Shader-Caches:** „Clear“ mit Größe.
    - **Komplett entfernen:** „Remove Nightforge completely …“ löscht Engine, Windows-Umgebung und Caches; nur lokal gespeicherte Spielstände werden vorher nach `Documents/Nightforge Saves` kopiert.
  - **Design:** `Dialogs.tsx` → Tab „Storage“.

- [ ] **4.4 Download-Warteschlange & Ruhezustand** · `M` · braucht 0.3
  - **Was:**
    - **Top-Bar:** Download-Ring mit Anzahl (Taste D).
    - **Panel:** Reihenfolge („Download this next“), Pause/Fortsetzen, Geschwindigkeit/Restzeit, „Only download overnight (1–7 am)“.
    - **Ruhezustand:** Während eines Downloads verhindert eine `IOPMAssertion` das Einschlafen, mit Hinweis.
    - **Fertig:** Download fertig → Toast mit „Play“ + macOS-Mitteilung (5.1). *(Toast erledigt mit 1.4.)*
  - **Wo:** Steam-Download-Warteschlange über Steam steuern (recherchieren, was von außen geht), sonst eigene Reihenfolge.
  - **Design:** `Overlays.tsx` → `DownloadsPanel`.

---

## Phase 5 – macOS-Integration & Controller

- [ ] **5.1 Mitteilungen** · `S` — `UNUserNotificationCenter`: „<Spiel> is ready to play“ mit Aktion „Play“, auch wenn Nightforge geschlossen ist. Abschaltbar (General).
- [ ] **5.2 Dock-Menü** · `S` — `applicationDockMenu`: die letzten 5 Spiele direkt startbar.
- [ ] **5.3 Spiele als Kurzbefehle** · `M`
  - **Verknüpfungen:** `~/Applications/Nightforge Games/<Spiel>.app` (kleiner Starter mit Cover-Icon, der `nightforge://play/<id>` öffnet), damit Spotlight und Launchpad die Spiele finden.
  - **URL-Schema:** `nightforge://play/<id>` registrieren.
  - **Siri/Kurzbefehle:** App Intents für „Siri, play Hades II“.
  - **Detailseite:** Button „Add to Applications“.
- [ ] **5.4 Controller-Tab** · `M`
  - **Anzeige:** Verbundene Controller mit Akkustand (`GCController.battery`).
  - **Koppeln:** „Pair a controller“ mit Anleitung je Hersteller. Direktes Bluetooth-Koppeln ist eingeschränkt → bei Bedarf die Bluetooth-Einstellungen öffnen und dort warten, bis der Controller erscheint.
  - **Tastensymbole:** „Like my controller / Xbox / PlayStation“ (`InputRouter.PadSymbols`).
  - **Design:** `Dialogs.tsx` → Tab „Controller“; HintBar zeigt „DualSense · 80 %“.

---

## Phase 6 – Ersteinrichtung mit Aha-Moment

- [ ] **6.1 Erster Start** · `M` · braucht 1.3
  - **Was:** `SetupView` erweitern:
    - **Ablauf:** Welcome → Checkliste (vorhanden) → Steam-Login mit QR-Hinweis → „Checking your library … N of M games“.
    - **Die Enthüllung:** „**87 of your 104 games run here**“ mit Balken (great / tweaks / untested / need Windows) und den Gründen.
    - **Abschluss:** „Let's play“ + „Also add Epic Games or GOG“.
    - **Wiederholbar:** „Show the first start again“ in About.
  - **Wo:** `SetupView.swift`, `Setup.swift`.
  - **Design:** `Overlays.tsx` → `Onboarding`.

---

## Phase 7 – Mehrere Stores (groß)

- [ ] **7.1 Store-Abstraktion** · `L` · braucht 0.2 — Protokoll `StoreProvider`: Bibliothek laden (offline-Cache zuerst), installieren, starten, Cloud-Spielstände, Sync-Status. Steam wird die erste Implementierung.
- [ ] **7.2 Epic Games ohne Epic-Launcher** · `L` · Recherche — Weg wie Heroic: [legendary](https://github.com/derrod/legendary) (GPL-3.0, passt zu Nightforges GPL-3.0). Login im eigenen Fenster, Download/Start direkt.
- [ ] **7.3 GOG ohne Galaxy** · `L` · Recherche — Weg wie Heroic (`gogdl`) bzw. GOG-API; DRM-freie Installer direkt.
- [ ] **7.4 Doppelt gekaufte Spiele zusammenführen** · `M`
  - **Anzeige:** eine Karte pro Spiel.
  - **Detailseite:** „Start through Steam | GOG“ und der Hinweis „saves stay with each store“.
  - **Matching:** über Titel-Normalisierung und IGDB-/Store-IDs.
- [ ] **7.5 Sync-Status pro Store** · `S`
  - **Fehlerfall:** Banner „Couldn't reach Epic Games – your games are from 3 days ago and still play. Try again“; nie still verschwundene Spiele.
  - **Design:** `Library.tsx` → `SyncBanner`; Tab „Stores“.

---

## Phase 8 – Gemeinsame Bewertungen (optional, nur Opt-in)

- [ ] **8.1 „Help rate games“** · `L`
  - **Opt-in:** standardmäßig aus.
  - **Gesendet wird nur:** Spiel, Chip (M1–M4), gestartet ja/nein, 👍/👎 aus 3.1 – ohne ID.
  - **Auswertung:** Ein kleiner Server sammelt; einmal pro Nacht entsteht eine öffentliche, aggregierte JSON (wie `profiles.json`), aus der 1.3 die Zeile „Tested on M2, M3 · 9 reports“ füllt.
  - **Design:** `Dialogs.tsx` → About (Schalter), `Detail.tsx` → `CompatCard`.

---

## Bewusst geparkt

- **Gatekeeper / Notarisierung** (Apple-Developer-Konto, 99 $/Jahr) – später entscheiden. Bis dahin: Installationsskript prominent, Weg „Open Anyway“ mit Screenshots erklären.
- **Soziales** (Freunde, Chat, Overlay) – bewusst nicht; höchstens Mitteilung bei Steam-Einladungen. Steam-Overlay ist unter Wine unzuverlässig.
- **Mehrere Steam-Konten / Familienfreigabe** – lieber klar „nicht unterstützt“ als halb.

---

## Woher die Punkte kommen

- **UX-Analyse des bestehenden Codes:**
  - Leiste mit allen Spielen
  - Zweiter Klick startet sofort
  - Bibliothek als Schalter
  - Starke Entsättigung nicht installierter Cover
- **Recherche zu den größten Launcher-Problemen:**
  - [PCWorld](https://www.pcworld.com/article/2627128/enough-with-the-game-launchers-its-dragging-pc-gaming-down.html): zu viele Launcher, Launcher-im-Launcher
  - [VGC](https://www.videogameschronicle.com/news/epic-games-store-exec-admits-the-launcher-sucks-says-improvements-are-on-the-way): Epic-Launcher langsam
  - [Tech Insider](https://tech-insider.org/gog-galaxy-vs-playnite-2026/): kaputte Integrationen in GOG Galaxy/Playnite
  - [GamingOnLinux](https://www.gamingonlinux.com/guides/view/what-steam-deck-steam-machine-steam-frame-and-steamos-verified-ratings-mean/): Steam Deck Verified als Vorbild
  - [TechSpot](https://www.techspot.com/article/2629-shader-compilation-explained/): Shader-Wartezeiten
  - [Neowin](https://www.neowin.net/news/whisky-a-popular-tool-for-playing-windows-games-on-mac-is-almost-dead/): Whisky eingestellt
- **GameHub (GameSir):**
  - [Android Authority](https://www.androidauthority.com/gamehub-lite-3608539/), [Tech Insider](https://tech-insider.org/winlator-vs-gamenative-vs-gamehub-2026/): Vorbild bei „läuft ohne Basteln“ und Voreinstellungen in Klartext
  - Abschreckendes Beispiel: undurchsichtige Profile, Tracking, fehlende Nennung von Open-Source-Code
- **Eigene Erfahrung/Ergänzungen:** Speicherplatz, Sitzungsabschluss, Rollback, Ersteinrichtung, Downloads/Ruhezustand, macOS-Integration, Akku, Controller, Offline, Barrierefreiheit.
