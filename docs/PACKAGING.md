# Packaging and distribution plan

## Name

**WBC3 Redux** (decided 2026-11-17): "Redux", brought back and reworked. Always presented as *an unofficial fan
reimplementation of the Warlords Battlecry III skirmish; requires the original game*, with no original logo, box art
or company names in the icon, installer or pages. Not "OpenWBC3": kirides/OpenWbc3 (Lua / LÖVE, MIT) already uses it
for a similar project. The full trademark as the name ("Warlords Battlecry Reborn") and names built on other marks
(Games Workshop's "Warcry", the "Battlelords" RPG) were considered and set aside.
- Display name "WBC3 Redux" (window title, Start menu, Apps list, installer); files without spaces: `WBC3Redux.exe`,
  `WBC3Redux-Setup-<version>.exe`, install folder `WBC3Redux`. `project.godot` `config/name` is "WBC3 Redux", so saves
  and settings live in `%APPDATA%\Godot\app_userdata\WBC3 Redux` (development: `.local\Godot\app_userdata\WBC3 Redux`,
  copied from the old "WBC3 Reference Build" folder, which stays).
- The exe's file properties (export preset, written by Godot without rcedit): product "WBC3 Redux", version 0.1.0.0,
  the unofficial / not-affiliated wording. The version there is set by hand for now; keep it equal to
  `build.ps1 -Version`.
- Main menu: a red ink "REDUX" stamp over the lower right of the title's "III" (`front_end.gd` `TitleStamp`: our own
  drawing in the 800x600 menu coordinates with the import's MainFont; the original art is unchanged; main menu only).
- Icon (2026-11-17): a bronze Roman numeral III on dark stone with a red ink REDUX stamp across its foot, the main
  menu's stamp in small; our own drawing, lettering in DejaVu Serif Condensed Bold (DejaVu licence). From 16 to 32 px
  the stamp is a plain red bar (the word is unreadable there), from 40 px it says REDUX. `packaging/make_icon.py`
  draws it and writes `artwork/icon/wbc3redux.ico` (16..256 px: exe, console wrapper, installer, uninstaller,
  shortcuts) and `wbc3redux-256.png` (window and taskbar, `config/icon`); both are kept in the project. An "R" alone
  was set aside: in a red box it reads like a film rating.
- The installer upgrades a 0.1.0 "WBC3-Godot" install in place (same AppId): it deletes the old exe, Start menu folder
  and desktop shortcut (`[InstallDelete]`, release build only).

Goal: a player who owns Warlords Battlecry III downloads one installer from a GitHub or itch.io link, points it at
their WBC3 installation (detected automatically or picked by hand), and gets a Start menu shortcut to the Godot port.
First launch opens the options screen for resolution and visual settings.

**Supported copies (2026-11-17): the GOG release only.** It is the one copy the importer has been verified on. Any other
copy (Steam, CD, a patched or modded install) is stopped by the importer's version check before anything is written,
with a report of the differing files (step 2); the game stays installed without data. Steam and CD support each need a
sample copy (Open questions).

**Rule: no original game file, and no converted asset, is ever inside the download.** The art, sound, music, maps,
fonts and text are converted on the player's machine from their own copy by the importer (`tools/import_assets.py`),
exactly as in development. The download contains our code, the Godot runtime and the importer, and two things of ours
that come from the original (decided 2026-11-17, named openly in the public README):
- The ten `simulation/*.json` **rule tables** (army setup, hero, research, spell, attack timing and unit AI numbers):
  read out of the original executable, most by running its routines under emulation in our research environment. They
  ship as they are, as other reimplementations ship rule data; regenerating them at import would need the private
  emulators (or new readers) in the importer. They are numbers, not assets.
- `artwork/menu-wings.png`, the **menu side art** for wide screens: new artwork painted with an image tool from the
  original main-menu picture (MENU_ARTWORK.md). It cannot be made again on the player's machine; it ships as our own
  upscaled menu work.

## Player flow

1. Download `WBC3Redux-Setup-<version>.exe` (0.1.0: 41.6 MB).
2. Installer page "Warlords Battlecry III location": auto-detected from the GOG registry key
   (`HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\1207658725`, value `path`), Steam library folders, or the usual install
   folders; "Browse…" otherwise. The page only continues when the folder holds `Battlecry III.exe`.
3. Installer copies the port, then runs the bundled importer with a progress page (about 1 GB written, about 5
   minutes), then `WBC3Redux.exe --headless -- --prepare-assets --pack` (about 2 minutes, see steps 1 and 4): 4 to 7
   minutes in all, measured. The original installation is only read.
4. Start menu shortcuts always; a desktop shortcut checkbox (default off); "Start WBC3 Redux now" at the end, offered
   only when the import succeeded.
5. First launch: the game opens the options screen on its Advanced tab (window mode, monitor, window size, scale)
   before the main menu; enhanced visuals are on the Visuals tab beside it, off by default. The installer has no
   settings of its own (an installer preset was considered and not built).

Also installed: a "Re-import game data" shortcut (runs the importer again, for example after moving WBC3), and an
uninstaller that removes the imported data too but never touches the original game.

## Layout on the player's machine

Per-user install (Inno Setup `PrivilegesRequired=lowest`), so no UAC prompt and re-import works without elevation:

```
%LOCALAPPDATA%\Programs\WBC3Redux\
  WBC3Redux.exe           Godot export, code and our own artwork packed inside (embedded .pck)
  wbc3-data.pck           the player's converted game data in one file (~1 GB), written on this machine
  importer\importer.exe   tools/import_assets.py frozen with PyInstaller (+ _internal\, 65 files)
  reimport.ps1            the "Re-import game data" shortcut's script
  source.cfg              the WBC3 path the player chose (for re-import)
  import-log.txt          the last import's output
```

72 files and 1.19 GB in all. The game finds its data through `asset_store.gd` (see steps 1 and 4 below): it mounts
`wbc3-data.pck` at `res://wbc3data/`. During an import the data exists as a loose `assets\` folder (about 7100 files),
which the prepare pass packs and removes.

## When the import runs, and load times

- **Once, at install:** the importer converts the player's WBC3 files into `assets\` (measured 5 min 5 s with
  importer.exe, ~1 GB), then the prepare pass bakes the alpha border fix into the PNGs (measured 131 s, 4736 PNGs). The original installation is not read again.
- **Again only on request:** "Re-import game data" (WBC3 moved or reinstalled, or a port update that changes the
  importer). Re-import is always followed by the prepare pass.
- **Every launch:** nothing is imported. The game opens the already-converted files as it needs them (menu art for the
  menus; a map and its units at match start), as a source run does today.
- **Cost against a source run:** an installed game decodes PNGs instead of Godot's imported textures. Measured on the
  60 largest sprite sheets (106 MB): 3.8 s against 2.3 s, so texture loading is about 1.5x; audio, JSON and map data
  load as before. A whole match start is still faster installed (step 3: 3.0 s against 4.0 s from source), because
  the export ships compiled scripts; loading from `wbc3-data.pck` measured the same as from the loose folder (step 4).

## Steps

1. **Asset loading from an external folder (done 2026-11-16).** Every runtime read of `res://assets/...` goes through
   `asset_store.gd` (31 game scripts converted; `tests/test_asset_store.gd` fails if a game script names `res://assets`
   again). It resolves one absolute data folder: `--assets=<dir>` on the command line, the `WBC3_ASSETS` environment
   variable, this project's `assets/` in a source run, then (exported build) `--data-pack=<file>` or `<exe
   folder>/wbc3-data.pck` (added in step 4), `<exe folder>/assets/` and `user://assets/`. JSON and audio come through `FileAccess`, fonts through `FontFile` (with the one setting the importer changes,
   subpixel positioning AUTO).
   Textures: a source run still loads through Godot's import, so development and tests are unchanged. Elsewhere PNGs are
   decoded at runtime. The importer's alpha border fix (`Image.fix_alpha_edges`) is about 10x the decode cost (60 largest
   sheets, 106 MB: 26 s of 29 s), so the installer runs a one-time **prepare pass**:
   `WBC3Redux.exe --headless -- --prepare-assets [--assets=<dir>]` bakes the fix into every imported PNG on all cores
   and writes `prepared.json`. Measured on the 60 largest sheets: prepare 24 s; loading them afterwards 3.8 s (Godot's
   import 2.3 s). A full prepare (574 MB, 4736 PNGs) measured 131 s. A menu start and a match start from a prepared
   import outside the project ran without errors (headless). Without the marker the
   fix runs at load time (slow, same pixels). The fix is idempotent. Re-import must be followed by prepare again.
   Tests keep reading `res://assets/` directly; they never ship.
2. **Importer as an executable (done 2026-11-16).** `packaging/build_importer.ps1` freezes `tools/import_assets.py` with
   PyInstaller 6.22.3 (pinned with Pillow 12.2.0 in `packaging/requirements-build.txt`, build venv `.local/pyi-venv`)
   into `.local/packaging/importer/` (31.5 MB with `_internal/`). Command line for the installer:
   `importer.exe --source "<WBC3>" --dest "<install>\assets" --progress-file "<temp>\import-progress.txt"`;
   in the exe both `--source` and `--dest` are required. Progress: `PROGRESS <percent> <label>` lines on stdout and in
   the progress file (replaced atomically, for the installer to poll). Stage weights from one timed run: scenarios,
   archives, terrain, all 22 maps, interface, quests, items and sound take about the first minute (2..72 %); the unit,
   building and effect art about 4 minutes (78 %); check and copy the rest. The installer should spread 78..92 % over
   the art stage on time, not on the label. Exit codes: 0 done, 1 failed, 3 a different version of the game.
   Measured: importer.exe 305 s, Python 5 min 17 s; both outputs byte-identical to the development import (5053 files).
   Staging happens beside `--dest` and the output is replaced only after the staged import passes its checks.
   **Other versions:** the importer reads number tables out of `Battlecry III.exe` at fixed addresses and pins the
   scenario and random-map files by hash, so accepting other versions blindly could produce wrong rules. Instead a
   preflight checks every pin before anything is written and stops with exit code 3 and a list of the differing files
   and their hashes ("Please report these files and hashes"). Supporting Steam or CD copies needs a sample of each: if
   only the exe differs, its tables have to be located again (or read from the GOG offsets if the bytes match there).
3. **Godot export (done 2026-11-16).** `packaging/build_game.ps1` exports `export_presets.cfg` "Windows Desktop"
   (x86_64, .pck embedded in the exe, console wrapper) to `.local/packaging/game/` and runs `packaging/check_pck.py`,
   which fails the build if the pack holds anything from `assets/`, `tests/`, `tools/`, `packaging/` or `.local/`, or
   lacks the rule tables. Result: `WBC3Redux.exe` (then `WBC3-Godot.exe`) 107.6 MB, of which the pack is 3.4 MB (296 files: compiled scripts,
   scenes, shaders, the ten `simulation/*.json` tables, `artwork/menu-wings.png`). Export takes about 50 s.
   - Templates: the official `Godot_v4.7.2-stable_export_templates.tpz` (github.com/godotengine/godot-builds, checked
     against its SHA-512); only the four Windows x86_64 templates were kept, in `.local/Godot/export_templates/
     4.7.2.stable/` (the launcher's Godot data folder).
   - Data folder: the exported exe finds `assets\` beside itself; the exported exe's `--prepare-assets` prepared a full
     copy there (4736 PNGs).
   - First start: `front_end.gd` opens the options screen on the Advanced tab (window mode, monitor, size) once, marked
     by `user://first_start_done`; only in an exported build (`-- --first-run` forces it in a source run).
   - No import in the data folder: a plain message screen (the menus need the import's art and fonts) naming the
     folder and "Re-import game data", with Quit. Checked in a source run with an empty `--assets` folder.
   - Timing, windowed 1280x720, three runs each, wall clock to 20 frames: menu start 2.0 s exported and from source;
     going straight into a map (`-- --open-map=<slug>`, the match scene's own set-up; Godot release builds refuse
     `--scene`) 3.0 s exported against 4.0 s from source, both on Desert Sands and on Hills to Climb (256 x 256). The
     exported build ships compiled scripts, which outweighs decoding PNGs. A captured frame of the exported match shows
     terrain, units, buildings and vegetation from the external folder.
   - Console wrapper: Godot's `WBC3Redux.console.exe` starts the main exe with an unquoted path, so it fails (error
     193) when a file exists at a prefix of the path cut at a space. On this machine a stray `G:\Games\Warlords` (a
     2026-11-15 match log) triggers it; a player's install path rarely has one. The installer calls `WBC3Redux.exe`
     directly, which works.
4. **Installer (done 2026-11-17).** `packaging/build.ps1 -Version <x.y.z>` runs the export (step 3), importer.exe
   (step 2) and Inno Setup 7.1.1 on `packaging/installer.iss`; result `.local/packaging/installer/
   WBC3Redux-Setup-<version>.exe`, 41.6 MB. Inno Setup is the official 7.1.1 x64 release (github.com/jrsoftware/issrc,
   SHA-256 checked, Authenticode signature by Pyrsys B.V. valid), installed portable in `.local/tools/innosetup7`.
   - Per-user install (`PrivilegesRequired=lowest`, `{autopf}` = `%LOCALAPPDATA%\Programs\WBC3Redux`), no UAC.
   - Page "Where is your copy of Warlords Battlecry III?" after the install folder: prefilled from `/WBC3="<folder>"`,
     then the previous install, then detection (GOG registry `1207658725` `path`, GOG's uninstall entry
     `1207658725_is1`, Steam and its `libraryfolders.vdf` libraries with `Warlords Battlecry III` / `3`, the usual
     GOG and Program Files folders); Next only with `Battlecry III.exe` in the folder. This machine's copy has no
     GOG registry entry, so here it is found only by browsing.
   - After copying: importer.exe then `WBC3Redux.exe --headless -- --prepare-assets`, on one progress page fed by
     their output lines (import 0..75 %, prepare 75..100 %; the art stage is labelled as the 4-minute step). Log in
     `{app}\import-log.txt`, WBC3 path in `{app}\source.cfg`. Exit code 3 or another failure: the game stays
     installed, a message names the cause and the "Re-import game data" shortcut, and "Start now" is not offered.
   - Start menu: the game, "Re-import game data" (`reimport.ps1`: folder dialog defaulting to the saved path, or
     `-Source`; import with Write-Progress; prepare), uninstall. Desktop shortcut optional.
   - Uninstall removes the game, `assets\`, staging leftovers, the log and `source.cfg`; saves and settings in the
     player's profile stay; the WBC3 folder is never touched.
   - Tested here (silent, `/DIR` under `.local`, `/WBC3`): install 244 s including import and prepare; 7123 data
     files, `prepared.json`; three Start menu shortcuts and the uninstall entry; `Battlecry III.exe` unchanged.
     Installed game, own profile: first start opens the options screen (Advanced), the second the main menu, no
     errors. Re-import with `-Source`: 240 s, prepared again, no staging left; a folder without the exe is refused.
     A fake WBC3 folder: game installed, import stopped with the "Unsupported game version" report in the log.
     Silent uninstall: nothing left (folder, Start menu, uninstall entry), the WBC3 folder unchanged (52 files).
     Not tested yet: Steam / GOG detection on a machine that has them.
   - **Hand test (2026-11-17, by the user, install to `C:\Temp\WBC3-Godot`):** no Windows warning, timing as
     predicted, first start on the options screen, 1.18 GB. Finding: 4000+ loose files in `assets\`.
   - **One data file (2026-11-17), from that finding:** `-- --prepare-assets --pack` (the installer and re-import
     pass it) writes the prepared folder into `wbc3-data.pck` beside the exe with Godot's PCKPacker (to a `.tmp`
     first, replaced when complete and at least as large as its files), then removes the loose folder
     (`asset_store.gd` `pack()` / `remove_loose()`, which refuse a mounted pack and this project's own `assets/`).
     The installed game mounts the pack; the prepare pass ignores an existing pack and works on the loose folder, so a
     re-import rebuilds it. Installer progress: import 0..75 %, prepare 75..92 %, pack 92..100 %. Measured: prepare
     and pack together 121 s (prepare alone was 131 s, so packing is within run-to-run spread); a whole install 402 s
     here, with the import itself between 305 and 342 s depending on disk caching. Map loads from the pack equal the
     loose folder's (Desert Sands 2.0..3.1 s, Hills to Climb 3.0 s), no errors, first start options and second start
     main menu; uninstall removes the pack. `tests/test_asset_store.gd` packs, removes, mounts and reads a sample.
   - **Test builds:** `packaging/build.ps1 -Test` (ISCC `/DTestBuild`) builds "WBC3 Redux test" with its own AppId and
     Start menu folder. Automated test installs must use it: on 2026-11-17 a silent test install with the release
     AppId took over the user's real install's registration, and its uninstall removed that install's Start menu
     shortcuts and uninstall entry (the user's files were untouched; installing again over it restores both).
     Later the same day the renamed test build's `[InstallDelete]` (meant for upgrading a real 0.1.0 install) deleted
     the user's real "WBC3-Godot" Start menu folder; that section is now in the release build only. `build_game.ps1`
     restores `APPDATA` after the export, so an installer started later from the same window sees the real folders.
5. **Clean test.** Install on a fresh Windows user account (and ideally a machine without Python or Godot), with the GOG
   copy; then a Steam copy if a tester has one. Play a skirmish, save/load, uninstall.

## Distribution

- GitHub Releases or itch.io (itch's butler gives players patch downloads). Forum post on the WBC community linking it.
- Name and wording: do not use "Warlords Battlecry" as the product name; say "requires Warlords Battlecry III". Free,
  marked as a fan project.
- Keep the decompile, emulation harnesses and research tooling out of anything published (PUBLIC_REPO.md lists what
  the public source repository holds).
- The installer is unsigned. Started on this machine it raised no warning (hand test); a copy downloaded from the web
  is expected to get Windows SmartScreen's "Windows protected your PC" until the file builds a reputation, so the post
  explains "More info" → "Run anyway". PyInstaller builds are sometimes flagged by antivirus; report false positives
  if that happens. Neither has been tried with a real download yet (step 5).

## Open questions

- Settled 2026-11-17: the rule tables and the menu wings ship (the Rule above). Considered and set aside: readers in
  the importer that rebuild the tables (a session or two of work), the emulators in the importer (publishes them and
  bundles the Unicorn engine), wings made at import from the original background (plainer) or no wings.
- Steam and CD versions: which files differ from GOG. Until a sample of each is checked, the importer refuses them.
- Version number and update channel (in-game "new version" notice or none).

## Status

- 2026-11-17: named WBC3 Redux (files, installer, exe properties, save folder); "REDUX" stamp on the main menu.
- 2026-11-17: the game data ships as one wbc3-data.pck instead of a loose folder; test builds have their own AppId.
- 2026-11-17: step 4 done (installer built and tested: install, first start, re-import, failure path, uninstall).
- 2026-11-16: step 3 done (export, pack check, first start, missing-data screen, timings).
- 2026-11-16: step 2 done (importer.exe, progress, preflight; outputs identical to the development import).
- 2026-11-16: plan written; step 1 done (asset store, prepare pass, `tests/test_asset_store.gd` in `-Check`); proven
  in the exported build in step 3 (no `assets/` file in the .pck, the game runs from the folder beside the exe).
