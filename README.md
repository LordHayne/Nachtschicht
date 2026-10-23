# Nachtschicht

A free, lean game launcher for Windows games on the Mac. Press "Connect Steam" once: Nachtschicht downloads a free Wine engine, sets up its own Windows environment, installs the Windows Steam client and waits for you to sign in. Your Steam games then appear as a cover library and launch with a click, Enter or a controller. CrossOver bottles are picked up too, if you have them.

Nachtschicht doesn't stay running while you play: by default the launcher quits 2.5 seconds after launch. No login, no telemetry, no background service.

## Requirements

- Mac with Apple Silicon, macOS 14 or later
- Xcode or the Command Line Tools (`xcode-select --install`). The Command Line Tools lack SwiftUI's macro plugins for the macOS 27 SDK, so `build.sh` then builds against the macOS 26.5 SDK they also include.
- Nothing else: the engine, Steam and Rosetta (if missing) are set up from inside the app. CrossOver is optional.

## Build and install

```bash
cd Nachtschicht
chmod +x build.sh
./build.sh --install
```

The app ends up in `~/Applications/Nachtschicht.app` and starts right away. Without `--install` it only lives in `build/`.

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

## Whisky or your own Wine

In Settings, enter the bottles folder (e.g. `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles`) and the path to the `wine` binary. Without CrossOver, the bottle is passed as `WINEPREFIX`.

## Tips for less overhead

- Enable **MSync** per bottle in CrossOver.
- Compare **D3DMetal** and **DXVK** per game, using the performance HUD.
- Turn off the **Steam overlay** globally in Steam.
