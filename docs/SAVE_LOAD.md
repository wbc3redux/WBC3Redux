# In-match Save / Load (milestone S-1)

PARITY_BACKLOG.md #20, COMPLAINTS_AND_FIXES.md F8 / S1. A skirmish can be saved from the game menu or with Alt+S and
loaded from the game menu or with Alt+L; the match continues exactly as it would have without the save. The format is
the rebuild's own (decided earlier, as for the hero book): the original's binary `.WB3` save is not read or written.

## 1. The original (evidence)

Labels: **Read** = control flow read in the decompile (`G:\Tools\ghidra_work\wbc3_decomp.c`), **Disassembled** = read in
the executable with capstone where Ghidra has no function (`0x565a10`). Nothing in this milestone is Emulated: the save
and load paths write files, swap the whole world and are not self-contained routines.

| Behaviour | Where | Label |
|---|---|---|
| One saved game per hero: `"%s\%s.WB3"` from the save folder (`0x40e160(0)`) and the hero's name (`0x709ce8`); `0x40d950` tests that it exists | `0x40d950`, `0x4481d0` | Read |
| Game menu rows (`0x566020` hit test): Load Game (row 0) only while a save exists (`+0x138` = `0x40d950()` when the menu opens) and not in game modes 1 / 3; Save Game (row 1) in every other mode; drawn in font 5, 7 when disabled, 6 under the cursor (`0x566160`) | `0x565670`, `0x566020`, `0x566160` | Read |
| The menu's release handler `0x565a10` jumps through the table at `0x565f44`: row 0 (`0x565b4f`) closes the menu and opens the load sheet `0x564c20(1)`; row 1 (`0x565bb6`) closes the menu, redraws the view (`0x48fb80`), notes whether a save existed, saves (`0x445c20`) and shows [0753] "Game Saved (previous savegame overwritten)" or [0304] "Game Saved", [0305] "Error - Game NOT Saved" on failure; both do nothing once the match is decided (`0x748914`); rows 2..6 Pause, Options, Victory, Resign, Quit as before | `0x565a10` | Disassembled |
| Alt+S (`0x427fb0` case 0x13): the same save and messages, only in a match (`0x608478 == 2`), with no dialog open, not after the end; Alt+L (case 0x14): the load sheet, only while a save exists | `0x427fb0` | Read |
| The save's header (`0x4482f0`): line 1 `"%s - %s"` (hero name, map name or [0287] for a random map), line 2 the time `"%H:%M:%S - %a %b %d %Y"` (`"%H:%M:%S - %d/%m/%Y"` with another locale flag), a 242 x 173 picture of the screen's centre at half size | `0x4482f0` | Read |
| The load sheet `0x564c20`: `EMDL` 400 x 431 at (1025, 350) in 1600 mode, pauses the match while open (`0x429590(0)`), reads the header (`0x4481d0`); `0x5653f0` draws the title [0306] in font 1 centred at x + 0xc1, y + 0x19, the picture at (+0x4b, +0x49), the two lines in font 2 centred at x + 0xc4, y + 0x105 / + 0x119, the Load Game button [0306] at (+0xc4, +0x149) in font 5 (6 under the cursor), close at (+0xb6, +0x171); hit test `0x5653b0`: x 0x84..0x104, y 0x13e..0x15f; Load Game (`0x565140`) loads (`0x446150(0, 1)`) | `0x564c20`, `0x5653b0`, `0x5653f0`, `0x565140` | Read |

## 2. The rebuild's format (version 1)

One file per hero: `user://saves/<hero id>.wbcsave` (the original's one save per hero), and the autosave beside it,
`<hero id>-autosave.wbcsave` (modern). An AI-only match saves as `spectator`. Headless runs (the checks, soaks, captures) save in
`user://saves-headless` instead, so a check never adds a save to the player's folder (`SaveGame.default_directory`). A file is a JSON document:

| Key | Content |
|---|---|
| `format` | `"wbc3-rebuild-skirmish-save"` |
| `version` | `1` (`SaveGame.VERSION`) |
| `saved_at`, `line_1`, `line_2`, `name` | the time; "hero - map" and the time for the load sheet |
| `map`, `map_name`, `match_id`, `hero_id`, `game_ms`, `players`, `engine` | readable summary (the map slug decides the scene) |
| `random_map` | generated maps only: the generation inputs (RM-7); the file is refused without them |
| `thumbnail` | optional PNG (base64) of the view, 242 x 173, taken after the menu closed |
| `modules` | one blob per module: `Marshalls.variant_to_base64` of the Dictionary its `save_state()` returns |
| `checksums` | SHA-256 of each blob; a blob that does not match is never decoded |

The blobs are Godot's Variant binary encoding: ints, floats, `Vector2` / `Vector2i`, packed arrays, typed arrays and int
dictionary keys survive bit for bit (JSON numbers and string keys would not). Module order (`main.gd SAVE_MODULES`):
`main, units, navigation, economy, production, combat, visibility, encounters, treasures, mines, conversions, ai,
skirmish, day_night, unit_commands, map_objects`, then `refs`.

**Shared objects** (`SaveGame.Refs`): an object held by several modules is saved once, by identity, in the `refs` table
(`{"script": path, "state": {...}}`, made again from `"@ctor"` arguments on load) and referred to by its index:
EntityState (mines, conversion actors, a hero's entity), BuildingState (`production.buildings` and `economy.entities`
hold the same objects) and HeroMatch (`main.match_heroes` and `combat.heroes`). Unit nodes go by unit id.

**Plain data only**: `SaveGame.capture` takes a module's script variables except the ones it names (links to other
modules, callables, data tables) and refuses an object, callable, signal or RID left in them (`SaveGame.errors`; the
suite fails on any). A variable added to a module later is saved without further work.

**Versioning**: a reader accepts only its own `version`; any other is refused with "This save was made by another
version of the game (save version n, this game reads 1)". A later format change raises `VERSION` and either converts
older documents in `check_document` or refuses them. A blob field missing in a module (a save from an older build of
the same version) leaves the field as the fresh match set it, with a warning.

**Writing** (`SaveGame.write`, as `hero_store.gd`): `<file>.tmp`, the previous save copied to `<file>.bak`, rename.

## 3. What each module saves

| Module | State (each next to its own variables: `save_state` / `load_state`) |
|---|---|
| `main.gd` | the match fields (`SAVED_FIELDS`: clock, mine and garrison orders, patrols, guards, groups, alerts, the modern assaults and attack-moves, results counters, Undead / Dwarf power timers, autosave schedule), the setup the match was started with, the statics the simulation reads (the walk-phase counter `UnitAgent.phase_counter`, `UnitAgent.local_player`, the slot colours), the hero links (Refs), building marker ids, the HUD speed |
| units (`unit_agent.gd`) | every variable (orders, route, segments, step and turn state, waits, detours, march, animation, conversion pose, combat mirror) plus position, visibility and tint; not the drawn sheet (`shown_slot`) |
| `navigation.gd` | occupancy by unit id (ground and air, in insertion order), building stamps, regions and sectors, the static caches as they are (a cache made before a map building fell keeps its cells), marches, detour clock; not the search buffers |
| `economy.gd` | stockpiles, capacities, mines, pending income, cycle clock; entities through Refs |
| `production.gd` | buildings (Refs, insertion order), registered units, research, races, hero terms, AI discounts, quests, the rules' match options |
| BuildingState / EntityState | every field, the definition copy, metadata (spells' `morph`) |
| `combat.gd` | fighters (orders, swings, statuses, mana, cooldowns, casts), towers, missiles in flight, kills, XP log, the generator (`combat_rng.gd`), the attitude scripts (`unit_ai.gd`: hit list, timers), spells (`spells.gd`: gates, famine stamps, sight spells) and hero spells (`hero_spells.gd`: pending cast, gems, rune choice, timed buildings, hot keys); heroes' HeroMatch through Refs |
| HeroMatch | the in-match profile copy (XP, items, skills as changed in the match), potions, school bonus, item factors, match items, its entity |
| `visibility.gd` | explored / visible / armed maps per player, counters, invisible units, sight bonus |
| `encounters.gd` | lairs, Mausoleum givers, quests, static cells, the map placements taken out of the collision data (taken out again on load) |
| `treasures.gd`, `mines.gd`, `match_conversion.gd` (+ `conversion.gd` jobs), `day_night.gd`, `unit_commands.gd` | every variable; mine and actor entities through Refs; a conversion job's target scan is the owner's `select` again |
| `ai_manager.gd`, `ai_player.gd`, `ai_abilities.gd` | the round-robin slot and timers; each player's lists, tasks, groups, research and mine weights, caches, stats, and its abilities' timer and casts (functions at the end of each file) |
| `skirmish_match.gd` | eliminations, hero deaths, quests, kills, results stats, clocks, quit countdown, outcome; the setup comes from the saved setup |
| `map_object.gd` | a placement's code after a retype, owner colour, rubble, animation clock and its link to the adopted building |

Not saved (presentation, rebuilt on load): the effects layer (fires, explosions, missile sprites), the enhanced visuals,
the HUD's dialogs and selection page, the camera (centred on the hero), building marker fades, the cursor.

**Load** (`main.gd load_match`): the saved setup is started again on a fresh scene with `start_skirmish` (so every
signal, callback and computer player is wired as at a match start; the hero's start write is skipped, the save already
made it), then every module's state is replaced with the saved one in `SAVE_MODULES` order; nothing in between runs the
simulation. A load from the game menu changes the scene first (`open_saved_game`: the save's map is selected, the new
`main.tscn` loads the document in `_ready`). The modern battle rules follow the current options, as at any match start.

## 4. Determinism results

`tests/test_save_load.gd`, in `.\launch.ps1 -Check` (suite "Save and load (S-1)"). Each run: the match plays N seconds
(1/60 s steps), fights are set up across the save (units next to an enemy tower, a melee and Dwarf Crossbows in the open),
the save is made with missiles in flight, written, read back and checked; the first scene plays M more seconds; a fresh
scene loads the save and plays the same M seconds. Checked bit for bit, every module blob: a second save of the same
moment equals the first (saving changes nothing), the save made right after the load equals the loaded save, and both
scenes' states after the M seconds are equal (and differ from the saved state: the run did change the match).

| Match | Saved at (full / `-Quick`) | Run after the load | State at the save | Result |
|---|---|---|---|---|
| Desert Sands, Knights (human) vs Knights (computer, level 6) | 92.6 s / 47.6 s; 789 KB | 30 s | 28 units, 7 buildings, 8 missiles in flight, 11 swings, a conversion running | equal bit for bit |
| The Hill, Undead (human) vs Dwarves, Swarm (level 6), Knights (level 5) | 78.1 s / 43.1 s; 1,055 KB | 30 s | 29 units, 12 buildings, 8 missiles, 10 swings, the hero's Stoneskin / Resist Magic cast running, two conversions | equal bit for bit |
| Four Bridges (water), Knights vs Dwarves | 65.5 s / 35.5 s; 770 KB | 25 s | 19 units, a Naga swimming across the lake | equal bit for bit |
| Random Map, Plains 128, Knights vs Dwarves (RM-7): the load rebuilds the map from the file | 62.5 s (full run); 925 KB | 25 s | 41 units, 11 buildings, 8 missiles in flight, 11 swings | equal bit for bit |

Longer runs (`-- --scale=3`, development option): saves at 272.6 s (Desert Sands, 1,195 KB, 42 units), 228.1 s (The
Hill, 1,429 KB, 45 units) and 185.5 s (Four Bridges), 90 / 90 / 75 s after the load: equal bit for bit.

Bugs the suite found while it was written (each a save_state gap, fixed): the conversion's marker order is one
dictionary shared by the fighter (`cur`) and main.gd's mine order (re-linked on load, `shared_cur`); a building's job
cost is a typed `Array[int]` (kept typed on load); the drawn sheet `shown_slot` (left out). The suite's checkpoints (one
per second of the run) report the first second and the paths of any difference, and `-- --aliases` lists containers the
live match shares between two places (the remaining ones are read-only data tables, the setup's slots and
`encounters.player_byte_748668` / `skirmish.eliminated`, which the load refills in place).

The format checks: an unknown version, another format, a damaged blob (checksum), a save without checksums and a damaged
file are refused with a message and the running match goes on; the second write keeps a `.bak`; no `.tmp` is left.
Normal play: the menu's Save Game ([0304], then [0753]), Alt+S, Load Game greyed without a save, Alt+L opens the sheet
with "hero - map", the autosave line, the autosave on its schedule and at the end of the match (Quit), Load Game opens
the save in a new scene at the saved moment, no Save once the match is decided.

## 5. Deliberate modern changes (labelled)

* Autosave (COMPLAINTS_AND_FIXES.md F8): every 5 / 10 / 15 minutes of game time or off, default every 10 minutes
  (Options, Gameplay tab, row "Autosave", the extra droplist under the right column; `[Modern] Autosave` in the settings
  file), and when the match is decided (victory, defeat, resign, quit). Normal play only.
* The load sheet has a line at y + 0x12d choosing the hero's saved game or the autosave; the Load Game button is greyed
  (font 7) when the shown file is missing or refused, and a refused save's reason is the message line's.
* The save's picture is a PNG of the world view after the menu has closed (the original redraws the view, `0x48fb80`,
  and stores 16-bit pixels at half size).
* Saves live in `user://saves`, one per hero id (the original: one per hero name in its save folder).
* An end-of-match autosave opens on its end box again; Continue does not apply the result twice (`hero_match.finish`
  refuses a result already in the hero book; the rebuild then counts it as applied).

## 6. Open items

1. Done in S-2: the hero book's Load Game (`0x5536e0` / `0x553bc0` case 4, `front_end.gd`) opens the selected hero's saved game,
   else its autosave; the button is greyed without one (`0x5563a0`).
2. The original's `.WB3` files are not read (by decision).
3. Done in RM-7: on a generated map the header's map name is [0287] "Random Map"; `random_map` holds the map's generation
   inputs and a load rebuilds the map from them (`simulation/random_map_match.gd`, RANDOM_MAP_RESEARCH.md R7-4).
4. A save is refused once the match is decided, as the original; an end-of-match autosave exists only as the modern
   addition above.
5. The save takes about 0.7-1.0 MB (128 maps) and is written on the main thread; an autosave can cost a frame or two on
   256 maps (not measured on the slowest machine).
6. Interface state is not saved: an open dialog, a placement or wall drag in progress, the spell placement cursor (the
   hero spells' pending cast itself is saved).
7. `combat.research` (research_effects.json) and building definitions are taken as constant data: a module that changed
   them during a match would need them saved.

## 7. Hand-test steps

1. `.\launch.ps1 -ImportAssets` once (the load sheet's bitmap EMDL is new), then start a skirmish (Desert Sands, Knights
   vs Knights). Expected: the match starts as before.
2. Alt+G: the game menu. Expected: Load Game greyed (no save yet), Save Game enabled.
3. Click Save Game. Expected: the menu closes, the message line shows "Game Saved".
4. Press Alt+S. Expected: "Game Saved (previous savegame overwritten)".
5. Give orders (move the hero, queue a Peasant), wait a minute, then Alt+L. Expected: the match pauses; the EMDL sheet
   shows "Load Game", the picture of the view at the save, "<hero> - Desert Sands", the time, the "Saved game" /
   "Autosave" line and the Load Game button.
6. Click Load Game. Expected: the match reopens at the saved moment: the same units, buildings, resources, research,
   fog, day / night, the hero's items and mana; the message line shows "Game loaded." (the rebuild's line); the match goes on.
7. Escape on the sheet (or its close button). Expected: the sheet closes and the match resumes at its speed.
8. Options, Gameplay tab. Expected: a row "Autosave: Every 10 min" under the right column; choose "Every 5 min", Okay;
   play 5 minutes. Expected: `user://saves/<hero>-autosave.wbcsave` appears (`.local/Godot/app_userdata/...` when
   started from launch.ps1); the sheet's "Autosave" line shows it.
9. Play The Hill with Undead, Dwarves and Swarm computers, cast a hero spell, save while it runs, load. Expected: the
   spell's status and the computers' groups continue as before.
10. Copy a save file, edit `"version": 1` to `2`, put it in place of the hero's save, Alt+L. Expected: the sheet's line
    shows "This save was made by another version of the game ...", Load Game is greyed; nothing crashes.
11. Resign. Expected: the autosave is written at the end; loading it shows the end box and the results again; Continue
    does not give the XP twice.
