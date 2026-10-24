# Nachtschicht

A free, lean game launcher for Windows games on the Mac. Press "Connect Steam" once: Nachtschicht downloads a free Wine engine, sets up its own Windows environment, installs the Windows Steam client and waits for you to sign in. Your Steam games then appear as a cover library and launch with a click, Enter or a controller. CrossOver bottles are picked up too, if you have them.

Nachtschicht doesn't stay running while you play: by default the launcher quits 2.5 seconds after launch. No login, no telemetry, no background service.

## Install

You need a Mac with Apple silicon (M1 or newer) and macOS 14 or later. Open Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/LordHayne/Nachtschicht/main/scripts/install.sh | bash
```

That installs the newest version into Applications and opens it; run it again to update. Everything else (game engine, Steam, Rosetta if missing) is set up from inside the app.

Prefer clicking? Download the DMG from the [latest release](https://github.com/LordHayne/Nachtschicht/releases/latest) and drag Nachtschicht into Applications. Nachtschicht is free and not registered with Apple, so on first launch macOS says it can't verify it: open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. The Terminal line above skips this step.

## Build from source

- Xcode or the Command Line Tools (`xcode-select --install`). The Command Line Tools lack SwiftUI's macro plugins for the macOS 27 SDK, so `build.sh` then builds against the macOS 26.5 SDK they also include.

```bash
cd Nachtschicht
chmod +x build.sh
./build.sh --install
```

The app ends up in `~/Applications/Nachtschicht.app` and starts right away. Without `--install` it only lives in `build/`.

To publish a release, push a tag such as `v0.1.0`: `.github/workflows/release.yml` builds the app and attaches the zip (used by the installer) and the DMG.

## Controls

| Action | Keyboard | Controller |
|---|---|---|
| Choose a game | ← → (Home / End to jump) | D-pad, left stick, LB/RB jump 5 |
| Play | Enter | A |
| Game options | O | Y or Menu |
| Close options | Esc | B |
| Rescan library | ⌘R | |
| Settings | ⌘, | |

Clicking a cover selects it; a second click launches the game.

## Language

Nachtschicht is available in English and German. Pick the language under Settings → General → Language. "System" follows your macOS language order.

## How it works

- **Setup:** the first start offers one button, "Connect Steam". It installs Rosetta if needed (macOS asks for your password), downloads the engine and DXMT from `components/manifest.json` (checksums verified), creates a prefix in `~/Library/Application Support/Nachtschicht/Prefix`, installs Steam with Valve's official installer and watches Steam's first start, restarting it if its self-update stalls. Sign-in happens in Steam's own window; Nachtschicht never sees your credentials.
- **Components:** `components/sources.json` lists the upstream projects; a nightly GitHub workflow (`.github/workflows/components.yml`) runs `scripts/update-components.py` to pin their newest releases with sha256 in `components/manifest.json`. The app bundles that file and, once `NachtschichtManifestURL` is set in `Info.plist`, fetches updates from it.
- **Library:** reads `steamapps/appmanifest_*.acf` in every bottle under `~/Library/Application Support/CrossOver/Bottles`, including additional Steam libraries from `libraryfolders.vdf`. "Last played" and play time come from Steam's `localconfig.vdf`.
- **Cover, background, logo:** taken from Steam's own cache inside the bottle first, otherwise downloaded once from the Steam CDN. After that everything comes from `~/Library/Caches/Nachtschicht`.
- **Launch:** a single call  
  `wine --bottle <Bottle> "C:\Program Files (x86)\Steam\steam.exe" -silent -applaunch <AppID>`  
  Steam starts minimized and opens the game.

## Per-game options

- **Performance HUD:** sets `MTL_HUD_ENABLED=1` so you see FPS and frame times right in the game. Handy for comparing D3DMetal and DXVK in CrossOver.
- **Launch options:** passed through to the game, e.g. `-dx11`.

## Game profiles

Known fixes are applied automatically when a game starts in Nachtschicht's own Steam: graphics layer, launch arguments, DLL overrides, Windows version, registry entries and runtimes installed with winetricks. They come from `profiles/profiles.json`, which a nightly workflow (`.github/workflows/profiles.yml`) builds from [umu-protonfixes](https://github.com/Open-Wine-Components/umu-protonfixes) (BSD-2-Clause) plus our own Mac-tested profiles in `profiles/mac.json`, which win over upstream. `scripts/build-profiles.py` reads the upstream fixes as syntax trees without running them and leaves out what only matters on Linux or would affect every game in the shared prefix. To add a Mac profile, edit `profiles/mac.json`.

## Whisky or your own Wine

In Settings, enter the bottles folder (e.g. `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles`) and the path to the `wine` binary. Without CrossOver, the bottle is passed as `WINEPREFIX`.

## Tips for less overhead

- Enable **MSync** per bottle in CrossOver.
- Compare **D3DMetal** and **DXVK** per game, using the performance HUD.
- Turn off the **Steam overlay** globally in Steam.
