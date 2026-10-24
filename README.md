<p align="center">
  <img src="docs/images/banner.png" alt="Nightforge – Every game. One place." width="820">
</p>

<p align="center">
  <b>Your Windows Steam games on an Apple silicon Mac. Free, one click, no fiddling.</b>
</p>

<p align="center">
  <a href="https://github.com/LordHayne/Nightforge/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/LordHayne/Nightforge?style=flat-square&color=2f7bff&label=release"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-0b0e14?style=flat-square">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-M1%20and%20newer-0b0e14?style=flat-square">
  <img alt="Free" src="https://img.shields.io/badge/price-free-2f7bff?style=flat-square">
</p>

<p align="center">
  <img src="docs/images/home.jpg" alt="Nightforge showing 7 Days to Die with the game row below" width="900">
</p>

Nightforge sets up everything a Windows game needs on your Mac and then gets out of the way. Press **Connect Steam** once, sign in, and your whole Steam library shows up as covers. Pick a game, download it, play. Steam itself stays invisible in the background.

## Why Nightforge

- **One button setup.** The game engine, a Windows environment, Steam and Rosetta (if missing) are set up for you in a few minutes. You only sign in to Steam, in Steam's own window; Nightforge never sees your login.
- **Fast graphics.** DirectX 10/11 goes straight to Metal through DXMT. On an M5, OxyRail runs at about 75 FPS instead of 45–50, and 7 Days to Die at about 63 instead of 30, compared with the Vulkan route.
- **macOS Game Mode.** Games get priority on the CPU and graphics, and controllers and headphones get half the Bluetooth latency.
- **Fixes that arrive by themselves.** A game database is rebuilt every night from the community fixes behind Proton, plus our own profiles tested on Macs. Nightforge applies the right one silently when a game starts.
- **Anti-cheat aware.** Easy Anti-Cheat and BattlEye can't run on a Mac; when Steam offers a way to start a game without them, Nightforge takes it.
- **Your whole library.** Every game you own, with search, downloads with progress, uninstall, and running games you can switch back to.
- **Made for the couch too.** Keyboard and controller work everywhere. English and German.
- **Free and quiet.** No account, no telemetry, no background service. Steam is closed when you quit Nightforge and no game or download is running.

## Install

You need a Mac with Apple silicon (M1 or newer) and macOS 14 or later. Open **Terminal** and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/LordHayne/Nightforge/main/scripts/install.sh | bash
```

That installs the newest version into Applications and opens it. Run the same line again to update.

Prefer clicking? Download the DMG from the [latest release](https://github.com/LordHayne/Nightforge/releases/latest), open it and drag Nightforge onto the Applications folder. Nightforge is free and not registered with Apple, so on first launch macOS says it can't verify it: open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. The Terminal line skips this step.

## A look inside

<p align="center">
  <img src="docs/images/dmg.jpg" alt="The DMG window: drag Nightforge onto Applications" width="560">
</p>

<p align="center">
  <img src="docs/images/library.jpg" alt="The whole library: installed games first, then everything you own" width="900">
</p>

<p align="center">
  <img src="docs/images/options.jpg" alt="Per-game options: graphics layer and launch options" width="900">
</p>

## Controls

| Action | Keyboard | Controller |
|---|---|---|
| Choose a game | ← → (Home / End to jump) | D-pad, left stick, LB/RB jump 5 |
| Play | Enter | A |
| Whole library | L | |
| Search | ⌘F | |
| Game options | O | Y or Menu |
| Uninstall | ⌘⌫ | |
| Close / back | Esc | B |
| Rescan library | ⌘R | |
| Settings | ⌘, | |

Clicking a cover selects it; a second click launches the game.

## Settings

- **Language:** English or German, or follow macOS (Settings → General).
- **Performance HUD:** frames per second and frame times in every game.
- **Game Mode:** on by default. Turn it off if a game's sound crackles.
- **Per game (O):** graphics layer (Automatic, DXMT or DXVK) and launch options.

## Good to know

- **Online play with anti-cheat** (Easy Anti-Cheat, BattlEye) doesn't work on a Mac. Single player and servers without anti-cheat do.
- **DirectX 9 to 11** is well covered. DirectX 12 games are hit or miss.
- **VR-only games** are marked as such; they can't run on a Mac.
- Saves in the **Steam Cloud** sync as usual.

## How it works

- **Engine:** a free Wine build ([Gcenx](https://github.com/Gcenx/macOS_Wine_builds)) runs Steam and the games in one Windows environment in `~/Library/Application Support/Nightforge`. DirectX 10/11 goes through [DXMT](https://github.com/3Shain/dxmt) (patched for Wine 11, built by `.github/workflows/graphics.yml`), DirectX 9 through [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) and [MoltenVK](https://github.com/KhronosGroup/MoltenVK).
- **Components:** `components/sources.json` lists what's used; a nightly workflow pins the newest releases with checksums in `components/manifest.json`, which the app downloads and verifies.
- **Steam in the background:** Steam's browser runs through a small wrapper (`wrapper/`) so it draws under Wine, and a tiny library keeps its windows out of the Dock. Games are started with Steam's own `-applaunch`, so licences, cloud saves and updates work as usual.
- **Game Mode:** macOS only grants it to app bundles marked as games, so Wine's loader runs from a small "Nightforge Game" bundle.
- **Game profiles:** `profiles/profiles.json` is built every night (`.github/workflows/profiles.yml`) from [umu-protonfixes](https://github.com/Open-Wine-Components/umu-protonfixes) plus our Mac-tested profiles in `profiles/mac.json`, which win. `scripts/build-profiles.py` reads the upstream fixes as syntax trees without running them and leaves out what only matters on Linux or would change every game in the shared environment. Profiles set the graphics layer, launch arguments, DLL overrides, Windows version, registry entries and runtimes installed with [winetricks](https://github.com/Winetricks/winetricks).
- **CrossOver and Whisky:** existing bottles are picked up too. Enter the bottles folder and, for anything but CrossOver, the path to `wine` in Settings.

## Contribute a profile

Got a game running better with a specific setting? Add it to `profiles/mac.json` with a short note on what you measured, and open a pull request:

```json
"251570": {
  "name": "7 Days to Die",
  "graphics": "dxmt",
  "note": "M5: ~63 FPS with DXMT, ~30 with DXVK."
}
```

Fields: `graphics` (`dxmt` or `dxvk`), `arguments`, `dllOverrides`, `registry`, `windowsVersion`, `winetricks`.

## Build from source

Needs Xcode or the Command Line Tools (`xcode-select --install`). Without Xcode, `build.sh` builds against the macOS 26.5 SDK the Command Line Tools include.

```bash
git clone https://github.com/LordHayne/Nightforge.git
cd Nightforge
./build.sh --install
```

The app ends up in `~/Applications/Nightforge.app` and starts right away. To publish a release, push a tag such as `v0.1.0`: `.github/workflows/release.yml` builds the app and attaches the zip (used by the installer) and the DMG. The logo and app icon are drawn by `scripts/render-brand.swift`.

## Licence

Nightforge is free software under the [GNU General Public License v3.0](LICENSE): you may use, share and change it, and anything built from it that you pass on stays open under the same licence. The game fixes in `profiles/profiles.json` are derived from umu-protonfixes and keep their [BSD-2-Clause notice](profiles/LICENSE-umu-protonfixes). Both licence files ship inside the app.

## Credits

Nightforge stands on the work of [Wine](https://www.winehq.org), [Gcenx's Wine builds and DXVK-macOS](https://github.com/Gcenx), [DXMT](https://github.com/3Shain/dxmt), [MoltenVK](https://github.com/KhronosGroup/MoltenVK), [winetricks](https://github.com/Winetricks/winetricks), [cabextract](https://www.cabextract.org.uk) and [umu-protonfixes](https://github.com/Open-Wine-Components/umu-protonfixes). Their licences apply to the components Nightforge downloads.

Nightforge is not affiliated with Valve or Apple. Steam is a trademark of Valve Corporation; Mac and macOS are trademarks of Apple Inc.
