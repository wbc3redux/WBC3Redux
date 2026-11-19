# Performance

Simulation performance rounds. Every change in a round is result-identical: fixed-seed soak logs are byte-identical
before and after. P-1 and P-2 are summarised in `OPEN_ITEMS.md` ("Done since the handover").

Profiler: `tests/profile_sim.gd` (headless; calls main.gd's own simulation_step parts in order; `--combat-detail` and
`--unit-detail` replay combat.gd / the unit loop with each part timed; the timing itself adds overhead, so per-fighter
parts such as `regen_poison` read high). Run it with `tools/heavy_slot.ps1` held.

## P-4 part 1 (2026-11-18): frame profile and four step trims

New profiler `tests/profile_frames.gd` (a real window through `tools/run_guarded.ps1 -Windowed -QuitAfter 0`; a six-side
match stepped to `--minutes` of game time, then phases of normal play with VSync off: frame time, the time inside the
simulation step, main.gd's and the HUD's `_process`, the renderer's CPU / GPU time, memory, and single calls).

Measured on Forest Lakes six-side at 10 game minutes (about 360-390 units), 1920 x 1080 window, a mid-range desktop
graphics card. Before:
the simulation step took 60-73 % of the wall time (mean 12 ms, p95 30 ms, p99 55-75 ms, up to 8 catch-up steps in one
frame); drawing 0.7-0.8 ms of GPU time in the original look and 1.7-2.7 ms with Enhanced Visuals (soft shadows 0.33 ms
of that); textures 73 MB at the start, about 790 MB late. At most 14 units were in view, so drawing a large army on
screen is not measured.

| | before | after |
|---|---:|---:|
| `simulation_step`, single call late game | 9.6 ms | 7.2 ms (-25 %) |
| units `advance` | 2.0-2.2 ms | 1.27 ms |
| `refresh_status` | 0.49 ms | 0 (normal play) |
| sim step in normal play, mean / p95 | 12.2-12.5 / 30.2-30.6 ms | 10.7 / 28.4 ms |
| frame time in normal play, mean / p95 | 8.5-9.6 / 32-34 ms | 6.6 / 21.3 ms |

Same results: the soak logs and summary tables of Forest Lakes six-side 15 minutes (`--races=0,1,2,14,0,1 --water
--min-sides=4`, 75,226 checks) and Knights vs Dwarves 14 minutes (35,951 checks) are byte-identical before and after;
`-Check -Quick` passed.

Changes:
* `unit_agent.gd` `step_sprite`: a unit that is hidden or outside the camera's area (with a 768-pixel margin, the largest
  frame is 708) puts no frame on its sprite in its step; only the values `update_sprite` writes for the step code are
  kept (walk_frame, own_walk_frame, the facing at the end of a conversion cycle). `main.gd` `refresh_stale_sprites`
  (every drawn frame) and `hit_rect` set the frame when the unit comes into view or is asked for.
* `main.gd` `object_index`: the scenario features sorted once per map. Single-frame scenery is not stepped; its clock is
  one shared value written back before a save (`settle_object_clocks`). `sync_states`, the fog pass and the marker pass
  walk the buildings only, and the offset table is built once.
* `main.gd` `refresh_status`: the fixture harness panel's texts are not built while normal play hides the panel.

Left: the spikes (p99 still about 55 ms; see P-3's list), `effects.sync` (0.95 ms a step: loops over every unit and
fighter), the combat update (4.4-4.6 ms per 25 ms update), `update_cursor` (1.1-1.3 ms every frame), sheets loaded
during the match (the largest decode in 70-100 ms each in a shipped build).

## P-4 part 2 (2026-11-18): the slow steps

Which steps are slow, from `tests/profile_sim.gd` on Forest Lakes six-side, 12 minutes (`--map=forest-lakes --map-races
--spike-ms=40`; new: `--inside-ms=N` prints the inside breakdown for steps over N ms, `--ai-detail` times the army
parts as `army.*`, `--ai-bench` / `--save-bench` time single computer-player calls and the autosave's parts at the end).
`--ai-detail` used to leave out `plan_outpost`, `building_stopped` and the resignation step, which slowed the computer
players' build-up (97 units at 12 minutes instead of about 460): its think now makes the same calls as ai_player.gd.

Before: 334 steps over 40 ms (with `--ai-detail`), 267 of them led by the computer players' think pass (one player
every 500 ms, on the same step as the attitude scripts' `search_rect`, 11-15 ms). Inside the think: a conversion
group's target choice 16-17 ms (`ai_danger.gd danger_to_building` listed every fighter and building as dictionaries
once per candidate); `ai_site` 6.5-7 ms for a first-window find and 60-100 ms when the home has little room (up to 225
windows of 2,500 cells, three `cell_data` look-ups a cell). The timed autosave: one step of 780-820 ms (capture 683 ms:
combat 344, units 130, map objects 107; encode 83; checksums, JSON and file about 90).

| | before | after |
|---|---:|---:|
| steps over 40 ms, 12 minutes | 334 | 177 |
| of those led by the think pass | 267 | 45 |
| steps over 40 ms, 10.9 minutes (same flags both runs) | 261 | 137 |
| mean / p95 / p99 step | 6.16 / 17.8 / 36.8 ms | 5.97 / 16.7 / 33.2 ms |
| conversion target choice | 16-17 ms | 1.2-1.4 ms |
| `ai_site`, first window / crowded home | 6.5-7 / 60-100 ms | 2.4-3.5 / 25-35 ms |
| autosave step | 780-820 ms | 361 ms (capture 368 -> on the main thread with the encode) |
| window run, normal play: frame p95 / p99 | 21.3 / 49.4 ms | 15.8 / 38.8 ms |
| `simulation_step`, single call late game | 7.2 ms | 6.5 ms |

Same results: both soak logs and tables byte-identical to the P-4 baseline; `-Check -Quick` passed (AI-11 once its
stand-in danger object was allowed for). `tests/check_autosave_async.gd` (not in -Check): the threaded autosave holds
the same modules and checksums as a document made at the same moment, a read waits for it, the .bak is kept.

Changes:
* `ai_danger.gd` `building_snapshot` / `danger_to_building_in`: the counted objects gathered once per choice into packed
  arrays; `danger_to_building` goes through them too (AI-4's 1,200 danger cases).
* `ai_sites.gd` `search`: the map's level / material / permission bytes read once per cell array into packed arrays;
  the blocked test written out (same tests as `Placement.blocked`).
* `save_game.gd`: `capture` keeps each script's variable names (a node's property list holds every engine property)
  and tests purity without building a path text per element (`pure`; `impure` only for the message). `write_async` /
  `finish_pending`: the timed autosave's checksums, JSON text and file on a worker thread; every other save reader or
  writer waits for it first. `main_save.gd autosave_async` (the direct `autosave()` is unchanged).

Left:
* The think pass and the attitude scripts on the same 500 ms step (45 + 14 steps over 40 ms): moving either changes
  results (the user's call).
* Route plans (`u_plan`, 21 steps, 220 ms at t = 1 s), one production step (170-200 ms at t = 489 s), one sector build
  inside a missile hit (331 ms at t = 615 s).
* The autosave's capture (combat 258 ms: the fighters' dictionaries are walked for purity and copied).

## P-3 (2026-11-11)

Measured on Forest Lakes six-side, 10 simulated minutes (`--map=forest-lakes --map-races --unit-detail --combat-detail`,
races 12, 0, 7, 15, 14, 13; 317 units at the end). The PC was shared with other heavy runs, so the before and after
profiles below were run back to back in one slot (before: the files of `a66980c`, after: `a706c6e`). Single runs vary
by about 10 %.

| | before | after |
|---|---:|---:|
| mean step | 15.28 ms | 13.21 ms (-14 %) |
| p95 / p99 | 43.3 / 85.9 ms | 35.6 / 63.1 ms |
| steps over 8 ms | 26,878 | 22,981 |
| combat (last minute, ms per 60 s) | 24,262 | 18,869 |
| attitude scripts (`unit_ai`, whole run) | 33.6 s | 14.6 s |
| towers | 11.8 s | 5.0 s |
| `search_rect` (60,770 calls; shared by the two above and acquisition) | 40.4 s (measured in a run of 40449b5) | 15.1 s |
| `spells.step` | 39.6 s | 32.3 s |
| walking units (`advance`, 1.67 M calls) | 80.0 s (48 us) | 67.7 s (41 us) |
| idle units (1.20 M calls) | 14.6 s | 11.1 s |
| sprite probe (`update_sprite` + `queue_redraw` per live unit) | 31.1 s | 16.2 s |
| `refresh_fog_overlay` (last minute) | 978 ms | 354 ms (-64 %) |

Soak logs (`tests/ai_soak.gd`, main.gd's fixed combat seed): Forest Lakes six-side 15 minutes
(`--map=forest-lakes --races=0,1,2,14,0,1 --water --min-sides=4`, 58,906 checks) and Knights vs Dwarves 14 minutes
(`--races=0,1`, 17,954 checks) byte-identical to the baseline after each commit. Suites run: Movement, Sector rebuild,
Fog overlay (new), Modern battle rules, Armies fight back, Neutral fog, Water, Combat, Combat review, Fog, Large units,
Sweep, Unit commands, Unit AI (encounters), Skirmish, Save and load, AI rules, Missiles, Spells, Hero spells B1-6a..e.

Changes:
* `simulation/combat.gd` `search_rect`: a cell holding only a building cell can be a candidate only at that building's
  nearest cell to the searcher, and only for a living, hostile, non-neutral building (`candidate_for_owner`'s own tests).
  That cell is found once per building and search (`_building_gate`); every other building cell is skipped instead of
  running the whole candidate test (with a walk over the building's cells) per cell. The scan uses typed dictionaries.
  `_poison` is called only for a poisoned fighter. Counters `search_calls` / `search_us` (save-skipped).
* `unit_agent.gd`: art look-ups (`ArtData.unit_sheet`, `walk_entries`) cached per art type; `z_index` set only when it
  changes (the setter always reaches the rendering server); no `queue_redraw` for a unit that drew nothing and has
  nothing to draw (no selection, health strips off, not the marker unit); `sync_cell` skips an unchanged position.
* `simulation/spells.gd` `step`: `combat.alive` asked once per fighter; the per-fighter calls (unit mana, illusion
  states, disease, berserk) made only when their own first test would not return at once.
* `simulation/unit_ai.gd`: `decide` builds no trace of the conditions in the match (`trace` false; tests keep it).
* `navigation.gd`: a building stamp or removal used to drop the extent-2 layer, and the next large unit's route built
  it again over the whole map. The dropped layer is now kept with the building cells it was built from; the next
  `layer()` floods only the sectors whose anchors can have changed and renumbers the rest (`_rebuild_layer`, the
  pattern of P-2's `_rebuild_sectors`). Suite Sector rebuild compares it with a full `_build_layer` after every rebuild
  (six maps, stamps, removals and `set_building_cell`). In this profile the layer was built only once (first large
  unit route, t = 593 s), so the gain shows in longer matches with several building changes between large-unit routes.
* `main.gd` `refresh_fog_overlay`: the pixels start as the fog's alpha word (`fill`) and only visible and unexplored
  cells are visited (`find`), when the fog bytes are 0 / 1 (what visibility.gd writes); otherwise the old loop. New suite
  Fog overlay (P-3) compares the image with the old loop on random maps.
* `tests/profile_sim.gd`: prints the layer builds and `search_rect` totals, and for every step over 200 ms the combat
  and unit parts, sector build, layer build and search time inside it.

Tried and dropped (no gain): memoising the cell tests of the extent-2 layer build (as P-2 did for the sector build) and
writing out its link scan's neighbour loop; the build stays about 0.5-1.1 s.

Left (P-4 candidates):
* One-off steps: the first extent-2 layer build of a match (about 1 s, t = 593 s; P-3 avoids the later full rebuilds,
  not the first); route plans at the start (t = 1 s, about 450 ms) and every few minutes (u_plan, 300 ms);
  a production step of about 400 ms (t = 531 s) and a combat step of about 850 ms (t = 559 s): see the spike lines of
  `tests/profile_sim.gd` (it prints what a step over 200 ms spent; the breakdown run was not finished in P-3).
* `spells.step` (32 s): a per-fighter loop over dictionaries plus `_sync_invisible` (a second loop); further gains need
  fewer fighters visited (for example a set of fighters with statuses), which changes the visiting code more.
* `ai_manager` (14 s, `simulation/ai_player.gd`, not in P-3's files).
* Walking units still about 41 us a step.
