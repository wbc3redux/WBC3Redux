# WBC3 Redux

An unofficial fan reimplementation of the **Warlords Battlecry III** skirmish game in the Godot engine. It is not
affiliated with or endorsed by the game's developers or rights holders.

**You need your own copy of Warlords Battlecry III.** Nothing from the original game's art, sound, music, maps or text
is included here or in the installer: on install, the importer converts them from your own installation on your own
computer.

## What it is

- **Skirmish only:** all 16 races, heroes and their hero book, the 22 skirmish maps and the Random Map, computer
  players at every level, save and load.
- **Faithful by default:** the rules follow the original game closely; the original battle rules are the default.
- **Upgraded presentation:** the game runs at your monitor's native resolution, with display options and optional
  enhanced visuals (soft shadows, glows, weather and more; off by default).
- **Not included:** the campaign, tutorial, map editor, multiplayer and videos.

This is a hobby project. Expect differences from the original and bugs; reports are welcome.

## Why Godot

- **Open source with no strings:** Godot is MIT-licensed, with no fees or royalties, so it fits a GPL project that
  anyone can build, change and share.
- **Built for 2D:** the original is a sprite game. Godot draws sprites natively at any resolution, which is what makes
  native-resolution play, sharp scaling and the optional shader effects straightforward.
- **Testable:** the game runs headless from the command line, so the rules, the computer players and long
  computer-vs-computer matches are checked by automated test suites without opening a window.
- **Small and self-contained:** one executable and one data pack; the download is about 42 MB before your game's data is
  converted.

Only Windows is built and tested today. Godot itself also targets Linux and macOS, but the installer and test runner
are Windows-only, and the importer has only been run on Windows.

## Requirements

- Windows 10 or 11, 64-bit.
- **The GOG release of Warlords Battlecry III.** It is the only copy the importer has been checked against so far.
  Other copies (Steam, CD, patched or modded installs) are stopped by a version check before anything is written,
  with a list of the files that differ; reporting that list helps add support for them.
- About 2.5 GB of free disk space while installing; 1.2 GB once installed.

## Install

1. Download `WBC3Redux-Setup-<version>.exe` from the Releases page.
2. Run it. The installer is not code-signed, so Windows SmartScreen may warn you: choose "More info", then "Run
   anyway".
3. Pick your Warlords Battlecry III folder (the installer looks for it, or use Browse). It must hold
   `Battlecry III.exe`.
4. The installer converts the game data (4 to 7 minutes). Your original installation is only read, never changed.

The first start opens the options screen so you can choose the window mode and size. "Re-import game data" in the
Start menu converts the data again, for example after moving your game. Uninstalling removes the converted data too;
your saves and settings stay in `%APPDATA%\Godot\app_userdata\WBC3 Redux`.

## Build from source

- Godot 4.7.2 (standard build), Python 3.12 with `pip install -r requirements.txt`, and your own installation of the
  game.
- `.\launch.ps1 -ImportAssets` converts your game's data into `assets\` (about 5 minutes; the game folder is found one
  folder above this project, or pass `-Source <folder>`). Then `.\launch.ps1` starts the game.
- `.\launch.ps1 -Check -Quick` runs the test suites (about 40 minutes). Suites whose fixture files are not in this
  repository are skipped with a note: those fixtures contain bytes of the original game.
- Installer: `packaging\build.ps1 -Version <x.y.z>` (needs the Godot export templates, Inno Setup 7 and the packages in
  `packaging\requirements-build.txt`). See [docs/PACKAGING.md](docs/PACKAGING.md).

## Layout

| Folder | Holds |
| --- | --- |
| `battle/` | The battle scene: `main.tscn`, its parts (`main_*.gd`), units, movement and selection |
| `simulation/` | The game rules, the computer players and the save format, plus the rule tables |
| `hud/` | The in-battle control panel, dialogs, minimap pings and markers |
| `menus/` | The front end, skirmish and army setup, hero screens, loading, options and results |
| `visuals/` | Terrain, effects, weather, fog and the shaders, including the optional enhanced visuals |
| `core/` | The asset store and readers for the converted data, display settings, audio, cursors and the original UI panels |
| `devtools/` | Viewers for animations, collision, UI panels and sound, and a movement benchmark |
| `tools/` | The importer (Python) and its tests |
| `tests/` | Godot test suites, run by `launch.ps1 -Check` |
| `packaging/` | The installer build |
| `artwork/` | The icon and the menu wings |
| `docs/` | Packaging, display, visuals, performance, save and menu notes |

Each Godot script has a `.uid` file beside it: Godot uses it to keep references working when files move.

## What comes from the original

The project's code, tools and documentation are new work. Two things in this repository are derived from the
original game, and both ship in the installer:

- `simulation/*.json`: rule tables (army setup, hero, research, spell, attack timing and unit AI numbers) read out of
  the original executable.
- `artwork/menu-wings.png`: decorative side art for wide screens, painted with an image tool from the original main
  menu picture ([docs/MENU_ARTWORK.md](docs/MENU_ARTWORK.md)).

Comments in the code name the original's functions by address where the behaviour was taken from. The research notes
and tools behind those findings are not part of this repository; comments that name a `*_RESEARCH.md`, `REVIEW_*.md`
or `tools/emulate_*.py` file refer to them.

## Licence

The code is licensed under the [GNU General Public License v3.0](LICENSE). The licence covers this project's own work
only. Warlords Battlecry III, its name, art, sound, music, maps and text belong to their rights holders and are not
licensed here.

## Credits

- Warlords Battlecry III was developed by Infinite Interactive. Please support the original: it is still sold on GOG.
- Built with [Godot Engine](https://godotengine.org) (MIT licence). The importer uses Pillow; the installer is made
  with Inno Setup and PyInstaller.
- The icon lettering uses DejaVu Serif (Bitstream Vera / DejaVu licence).
- Developed with the help of Claude (Anthropic).
