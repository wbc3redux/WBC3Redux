# Shared menu artwork extension

Implemented locally on 1 November 2026 at the user's request. Committed on 2 November 2026.

`menu_backdrop.gd` draws shared decorative wings beside the original 800×600 menu viewport. It is attached by `ui_screen.gd` and `hero_advance.gd`. The original logical coordinates, controls, coordinate conversion, fonts and source artwork are preserved. The later MENU_CLARITY.md update renders this logical centre at display resolution for clearer text; the original low-resolution viewport is no longer the default. No original installation archives or executable are modified.

The image is stored in `artwork/menu-wings.png`, outside the generated `assets/` directory so an asset reimport does not replace it. Only its outer quarters are rendered. The generated centre is never displayed. The renderer reveals each wing outward from its inner edge, scaled to the original menu height. A narrow edge blend uses the current original background's edge pixels, entirely outside the original viewport.

The allowlist covers the main menu, hero selection/creation, options, loading/credits, victory/defeat backgrounds, skirmish setup, results, retinue, graveyard, random-map setup/generation, synchronisation and multiplayer front-end artwork. This does not implement missing screen flows: the wings appear when an existing hosted screen displays a matching 800×600 background. The original UI research viewer remains an original-art reference. Campaign/map/editor layouts and in-game HUDs are unchanged.

At 4:3 there are no wings. At 16:9 and 21:9 the centre retains its original proportions. Sharp scaling keeps its existing integer-scale behaviour (including any small top/bottom gaps). At extreme aspect ratios wider than the artwork's 8:3 coverage, only the decorative wings stretch; the centre never does. Wings are decorative Node2D draws, not clickable controls.

## Validation

- `tests/test_menu_artwork.gd`: geometry, button hit mapping, background allowlist and unsupported-panel fallback.
- Run with `-- --render-capture` on a graphical renderer for captures and pixel comparisons. The 169 checks cover eight panels at 800×600, 1920×1080, 2560×1080 and 1280×800, plus Smooth/Sharp geometry. The original centre is compared byte-for-byte with wings hidden; the whole 4:3 screenshot is also compared.
- Existing regression checks: UI fixes (194), hero advance (21), skirmish setup (87), front end (107), loading screen (13), and UI viewer (386 panels / 4,179 controls / eight presets / four modes).
- Rendered captures are local in `.local/menu_artwork_*.png`; these test fixtures show decoded panels and may contain placeholder labels. Front-end `--capture` provides fully wired menu examples.

## Art provenance

The built-in image generation tool created the side artwork from the original local `assets/ui_bm_BM_MAINMENU.png`. It is a new implementation asset, not a crop of the approved reference board. The approved concept remains preserved in `../Artwork_References/2026-11-01/`.

The final generation prompt:

> Outpaint this game menu background horizontally, EXACT 8:3 canvas, e.g. 2048x768. Source original occupies middle 50% horizontally (x512..1535), full height. Preserve original center geometry exactly including original shield at RIGHT BORDER, original skull at LEFT BORDER, sword, curtains and bottom masonry. The previous attempt failed by removing the shield and duplicating a skull at the join. CRITICAL: add no skulls in extensions. Existing circular shield is cut by the original right edge; COMPLETE only its missing far-right portion in the adjacent right extension, aligning its centre at approximately output x1470,y294 and full diameter approx 240 px. Then continue the original dark vertical timber at right edge; NO purple curtain immediately adjacent to the shield, curtains only farther right at outermost edge. Left edge x512 source continues purple drapery until y420 then wooden wall, then stone at y590. No candles or skulls in LEFT extension. Match edge stone heights. No logos or text outside center. Unchanged original source in middle, seamless additions each 25% width. Muted low-resolution 2004 painted game art, not crisp modern illustration. Do not repaint, shift or scale central elements independently.
