# Performance

Simulation performance rounds. Every change in a round is result-identical: fixed-seed soak logs are byte-identical
before and after. P-1 and P-2 are summarised in `OPEN_ITEMS.md` ("Done since the handover").

Profiler: `tests/profile_sim.gd` (headless; calls main.gd's own simulation_step parts in order; `--combat-detail` and
`--unit-detail` replay combat.gd / the unit loop with each part timed; the timing itself adds overhead, so per-fighter
parts such as `regen_poison` read high). Run it with `tools/heavy_slot.ps1` held.

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
