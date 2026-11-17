# Enhanced visuals

A deliberate modern change, like native resolution (see the modernization decisions): an optional presentation layer
over the untouched original sheets. **Off by default.** Presentation only: nothing reads or changes the simulation, and
with the option off every frame is drawn exactly as before (no material on features, `soft_shadows` false on the
team-colour materials, the extra layers hidden, the fog overlay and camera as before).

## Settings

The Options screen's fifth tab, **Visuals** (`options_screen.gd`, rows from `display.gd` `visual_rows`), stored in the
`[Visuals]` section of `user://settings.cfg` next to `[Display]` and `[Audio]`. Okay saves, Cancel restores. **F9** in a
match flips the master switch and saves it.

| Row | Choices (default first where it matters) | Drives |
|---|---|---|
| Enhanced Visuals | **Off** / On | the master switch; every other row is disabled while it is off |
| Shadows | Original / **Soft** | soft shadows |
| Colour Grade | Off / **Subtle** (60 %) / Full | colour grade, cloud shadows, vignette |
| Effect Glow | Off / **Subtle** (65 %) / Full | effect glows, the additive boost and halo on effect frames |
| Fog Edges | Blocky / **Smooth** | fog overlay filtered between cells |
| Camera | Instant / **Smooth** | Camera2D smoothing (speed 9); jumps of more than two views snap |
| Hover Outline | Off / **On** | outline of the unit or building under the cursor |
| Terrain | Original / Detailed / **Detailed + Plants** | terrain detail shader; ground scatter |
| Dust and Sand | Off / **On** | dust puffs and drifting sand |
| Combat Effects | Off / **Subtle** (60 % of the particle counts) / Full | combat_fx.gd: embers, sparks, smoke, debris, scorch marks, hit flashes, missile trails, death dust, corpse fade |
| Weather | **Off** / Match Map / Rain / Snow / Fog / Sandstorm | weather_fx.gd + weather.gdshader (round 3) |
| Weather Strength | **Light** / Heavy | the weather's density; disabled while Weather is Off |

The Visuals tab has twelve rows: `options_screen.gd` adds two droplists (instances 10 and 11, y 389, 35 below the
original fifth row of each column) on this tab only, and leaves the processor / memory / version lines under them empty
there.

## What it does

| Part | Where | How |
|---|---|---|
| Soft shadows | `team_colour.gdshader` (`soft_shadows`), `ArtData.set_soft_shadows`, `ArtData.plain_material` for map features | The importer turns the RL shadow band into black pixels whose alpha is the darkening (`tools/rl.py`). Those pixels are averaged over a 5 x 5 tent (body pixels count as "shadow continues", empty pixels as 0) and tinted a dark violet-brown. Removes the hard, stair-stepped shadow outline; body pixels are never touched. |
| Colour grade | `enhanced_grade.gdshader` on a `CanvasLayer` (layer 2: above the world, below the HUD at 5) | Split toning (warm light, cooler shade), saturation x1.08, contrast x1.05, slow fbm cloud shadows anchored to world coordinates (max 11 % darker), light vignette over the world view only. |
| Effect glows | `enhanced_visuals.gd` `paint_glow`, z 3990 (under the fog at 4000) | Additive radial glow at live effects from `effects_layer.gd`: EF01..03 fires (flicker), EX01/EX02 explosions and EZ01 conversion flashes (fade over their frames), EZ08 spawns (cool blue). |
| Dust | `paint_dust`, z 3970 | A puff at the feet of each visible ground unit in a cell step every ~120 ms; 0.9 s life. Flyers, units inside buildings and dying units make none. |
| Drifting sand | `paint_sand`, z 3980 | 36 faint streaks blowing across the view. |
| Effect boost and halo | `effect_boost.gdshader` on a `Boost` child of each EF / EX / EZ effect node (`effects_layer.gd`) | The frame drawn once more additively (20 % at Full) plus a 16-tap halo of its bright, saturated parts (40 % at Full), sampled only inside the frame's own region of the sheet. Grey smoke and dust are left out by a saturation gate. |
| Fog edges | main.gd `fog_overlay` filter | Linear instead of nearest: one-cell gradients at the fog and shroud edges. Hidden units stay hidden (`apply_fog_to_nodes` is unchanged); only half a cell of terrain shows through the gradient. |
| Camera | main.gd `camera` | Godot's position smoothing. Mouse picking uses the canvas transform, so clicks always match what is drawn. |
| Combat effects | `combat_fx.gd` (additive layer z 3992, smoke layer z 3975, decals z -1) | Watches combat.gd fighters (hit points down -> a flash and sparks; state dying -> a dust burst; corpse -> sprite alpha fades over the last 2.5 s before removal), production buildings (hit points down -> sparks and chips), combat.gd missiles (a fading trail; a glow and a coloured trail when the missile sheet's average colour is bright and saturated, decided once per sheet) and effects_layer.gd effects (fires: embers and smoke; explosions, once: spark burst, falling debris, smoke, a scorch mark fading over 25 s). CPU particles on their own clock, capped at 700 (30 scorch marks). |
| Hover outline | `hover_outline.gdshader` on one Sprite2D in `enhanced_visuals.gd` | Copies the hovered unit's (or building's base) sheet frame from main.gd `hover_info` and draws a 1.5-pixel line just outside the body (not the shadow band): own warm white, enemy red, others grey. |
| Terrain detail | `terrain_detail.gdshader` on main.gd's terrain sprite | Per pixel, from the painted colour: sand gets world-pixel grain, noise-bent wind ripples and a slow pale / warm drift that breaks up the repeated panels; grass gets short blade streaks and drier / lusher patches. Rock, cliffs, road and rubble are left as painted. Patterns are squashed 3:4 like the 32 x 24 cells. |
| Weather | `weather_fx.gd`, `weather.gdshader` on a `CanvasLayer` (layer 3: above the grade, below the HUD) | One full-screen pass, nothing on the CPU but the uniforms, everything made from noise and hashed cells in world coordinates (it scrolls with the map; nearer rain / snow layers move a little faster with the camera). Masked to the world view. It never reads the terrain renderer or the simulation, so per-tile maps change nothing for it. **Rain**: slate overcast tint, three depths of slanted streaks, small squashed splash rings. **Snow**: a pale veil and three depths of swaying flakes. **Fog**: a thin haze plus drifting banks and wisps. **Sandstorm**: a red-brown haze in long moving bands, darker than the sand so it reads on desert, and fast grains blowing across. All swell and ease over about a minute. Light = 0.55, Heavy = 1.0 of the density. |
| Match Map | `weather_fx.gd` `for_map` (Provisional; the original has no weather) | Words in the scenario name and the terrain record names: snow / winter / ice / frost -> snow; jungle / swamp / marsh -> rain; lava / cavern / volcano -> fog; then the ground most records name: desert / sand -> sandstorm (Desert Sands); grass / plains with coast / water / river / lake records -> rain; else clear. Revisit once the per-tile maps (W1) carry terrain set names. |
| Ground scatter | `ground_scatter.gd`, `scatter_sway.gdshader`, z -1 (just above the terrain, under everything else) | Generated atlas (34 ms, twice world resolution): four grass tufts, two dry stalks, a small scrub, three pebbles, a contact shadow. Placed per cell from the raw TER material (0 plateau grass: clumps of 2-4 tufts; 2 sand: sparse stalks, scrub, pebbles) and the painted colour under the point (nothing on road, rock or cliff). One seed per cell. Cells of map buildings and features stay empty; cells of buildings placed later (and one cell around) are cleared twice a second. Tufts sway in the vertex shader. |

## Not done / next

* Option 3 of the terrain plan (rebuild the ground from material textures with the painting as the colour layer) is not
  started; decide after hand-testing the detail shader and scatter.
* Scatter is never restored when a building's rubble is gone (the ground stays bare).
* Missile glows (fireball-type missiles need their ids identified).
* Round 3, water: not started on purpose. The water shader goes on top of the per-tile terrain drawing (MAPH tile
  records drawn at load time, W1), so it waits for that.
* Weather sound (`SoundFX/Weather/*.wav`, AUDIO_RESEARCH.md) is not played with the weather.
* Round 4: material terrain, terrain transitions and GPU-made effects.
* Performance: the soft-shadow pass samples 25 texels for every transparent or shadow pixel of every unit and building
  sprite while on. Fine on the dev machine; needs a check with a full late-game army on screen.

## Performance

`tests/bench_weather.gd` (window, not part of `-Check`; `tools/run_guarded.ps1 -Script res://tests/bench_weather.gd
-Windowed -QuitAfter 0`): Desert Sands, 60 against 60 units fighting in view, enhanced visuals at their defaults, VSync
off, 1920 x 1009, Compatibility renderer, RX 6700 XT. Each weather at Heavy right after a pass with the weather off
(150 frames each). 2026-11-01:

| Pass | GPU mean / p95 (ms) | CPU frame mean (ms) |
|---|---|---|
| weather off | 2.61-2.72 / 3.24-3.33 | 8.1-8.8 (first pass 14.5: the fight starting) |
| rain | 2.91 / 3.68 | 15.8 (still the fight's opening) |
| snow | 2.86 / 3.65 | 8.8 |
| fog | 2.77 / 3.84 | 7.9 |
| sandstorm | 2.78 / 3.90 | 7.9 |
| enhanced visuals off | 0.93 / 1.28 | 6.9 |

The weather adds about 0.15-0.3 ms of GPU time and nothing measurable on the CPU; the frame time in a big fight is the
simulation's. (The rest of the enhanced visuals add about 1.7 ms GPU over the plain renderer.)

## Captures

`tests/capture_visuals.gd` (run with a window, not part of `-Check`) writes `.local/visuals_<view>_<on|off>.png` for the
base, a marching group and a burning spot beside the towers. `tests/bench_weather.gd` writes `.local/weather_<kind>.png`
of the fight in each weather.
