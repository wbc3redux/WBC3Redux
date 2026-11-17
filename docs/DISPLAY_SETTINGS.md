# Native resolution and modern settings

**Deliberate modern change, not original behaviour.** The original only runs at 800x600 or 1024x768 (in-game also
1280 / 1600 modes). The rebuild runs at the monitor's native resolution, has its display settings on a fourth tab of
the original Options screen, and opens that screen in a match too. Faithful parity work must keep these decisions (ask
before reverting any of them).

## Shared view scale (`display.gd`)

One scale is used by the world camera, the control panel, the in-game dialogs, the match-end box and the cursor.

* **Auto** (default): the smallest step of 1, 1.5, 2, 2.5, 3, 4 whose world view (window height / scale, minus the
  150-row panel) is at most **1050 rows**, the original's 1600x1200 mode. A higher resolution shows more map up to that
  cap and then gets sharper instead.
* **Fixed** 1x to 3x (Interface Scale).
* **Battlefield View** caps the width: Original 1600, Widescreen 1920 (default), Ultrawide 3200 world pixels. A wider
  view gets black bars at its sides; clicks in the bars do nothing.

| Window | Auto scale | World view |
|---|---|---|
| 1366x768 | 1 | 1366x618 |
| 1920x1080 | 1 | 1920x930 |
| 2560x1440 | 1.5 | 1707x810 |
| 3440x1440 | 1.5 | 1920x810 + 280-pixel bars (Widescreen), 2293x810 (Ultrawide) |
| 3840x2160 | 2 | 1920x930 |

## Control panel (`game_hud.gd`)

The 1600-mode layout on a virtual screen 1600 columns wide, at the shared scale, its bottom on the window's bottom and
centred. Wider windows repeat the bitmap's outer stone column past its ends; narrower ones cut the decorative ends (the
working part spans about columns 285 to 1315). The army counter keeps to the world view's left edge, the resource boxes
to its right edge (the original's 1600-mode places measured from that edge).

## 4:3 screens (`ui_screen.gd`, `hero_advance.gd`)

Fitted to the window and centred (side bars). Menu Scaling: **Smooth** (linear filtering) or **Sharp** (nearest
filtering, snapped to a whole multiple when that fills at least 85% of the fitted height).

## Options screen (`options_screen.gd`)

The original PNL_GAMEOPTIONS screen, one implementation for the main menu and the match.

* **Five tabs.** The original radio buttons (x 200 / 360 / 510) move to x 130 / 247 / 360 and two copies at x 466 and
  582 read **Advanced** and **Visuals** (all five inside the tab banner). Visuals holds the enhanced visuals switches
  (ENHANCED_VISUALS.md), stored in `[Visuals]`. **Advanced:** its ten rows are the original droplist buttons and lists:
  Window Mode (Windowed / Borderless / Fullscreen), Monitor, Window Size (Automatic = 80% of the monitor, common sizes
  that fit, native), Interface Scale, Battlefield View, Menu Scaling, VSync, Frame Limit, Mouse (Kept in Window /
  Free), Background Sound (Muted / Playing).
* **Window changes** (mode, monitor, size) apply when chosen; the message line reads "Okay keeps this display mode -
  reverting in N s". Okay keeps them, Cancel or the 15-second timeout puts them back. Godot 4 can't change the
  monitor's display mode: fullscreen always runs at native resolution.
* Every other choice applies at once; Okay saves, Cancel restores everything (the original options and the display
  settings) to the copy taken on entry, as the original's Cancel does.
* **Graphics:** "Resolution: Native" (the original's row) opens the Advanced tab; **Gamma Correction** (One .. Five) is
  now applied: a gamma of 1.0 .. 1.4 over the whole screen.
* **In a match:** the game menu's Options row and Alt+O open the same screen over the match, which **pauses** while it
  is open (a match paused before stays paused) and is dimmed around it; the control panel and the world get no input.
  The original in-game options sheet (EMDO, 0x566c30) is kept in `game_hud.gd` but no longer opened.
* **Alt+Enter** anywhere: windowed <-> borderless fullscreen (saved).

## Storage and command line

`[Display]` and `[Audio]` sections of the settings file (`user://settings.cfg`); `[Options]` keeps the original's
values (`simulation/game_settings.gd` keeps the other sections when it saves). First launch: borderless fullscreen at
native resolution; an exported build also opens the Options screen on its Advanced tab once (PACKAGING.md step 3).
Volumes stay the original's SFX and Music rows.

Overrides for one run (after `--`): `--windowed`, `--fullscreen`, `--exclusive`, `--window=WxH`, `--monitor=N`,
`--scale=S`, `--view=original|widescreen|ultrawide`; `launch.ps1 -Windowed`. Choosing that setting on the Options
screen drops the override.

## Checks

`tests/test_game_hud.gd`: scale steps, bars, panel mapping and view clamp at four window sizes; the in-game Options
opens the shared screen, pauses, blocks input, Cancel resumes. The front-end self-test: the five tabs and their places,
Advanced labels and choices, Resolution leads to Advanced, a window change asks to be kept and reverts, Cancel
restores the display settings. Captures with a window: `tests/capture_native.gd` (match at 1366x768 to 3840x2160 and
the screen over it, `.local/native_*.png`) and `front_end.tscn -- --capture` (`.local/menu_capture_04b/04c`).
