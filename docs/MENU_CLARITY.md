# Menu clarity: display-resolution rendering

Implemented locally on 1 November 2026. Committed on 2 November 2026.

Previously the menu, controls, TrueType text and overlays were flattened into an 800×600 texture, then enlarged to the presentation rectangle. The new renderer allocates the menu SubViewport at the displayed pixel size and keeps an 800×600 logical coordinate space through `size_2d_override` with `size_2d_override_stretch`. Godot's viewport oversampling then rasterizes the existing font outlines at the output scale. Controls, dropdowns, edit fields, help text and the main-menu hover animation retain the original coordinates and draw order.

`display.gd::prepare_menu_viewport` applies this to the shared `ui_screen.gd` host and the separate `hero_advance.gd` host. No font files, source artwork, XCI definitions or saved settings are changed. Smooth/Sharp filtering is applied while sampling the bitmap artwork into the larger viewport. The UI reference viewer and gameplay HUD are outside this change.

Artwork and text still composite in the correct original order, but the low-resolution background no longer forces text to render at low resolution. This does not reconstruct source bitmap detail: the logo, decorative frames and baked-in labels retain their original resolution limits. The output target uses more GPU memory than the previous fixed 800×600 target, proportional to its displayed area.

## Comparing the result

Default launches use the new renderer. Add `--legacy-menu-rendering` after Godot's `--` separator for the old fixed-resolution rendering path for that run only. This switch does not save a preference.

A before/after gallery (kept outside the repository, `Artwork_References/2026-11-01/menu-clarity-comparison.md` beside the game folder) contains real front-end captures of main menu, options, dropdowns, help, hero creation and hero selection. Both runs used the same requested 1920×1080 window; the OS may constrain the actual client size to fit the desktop. Inspect the images at their full size to see the font-edge difference. The main-menu captures include the existing animated Skirmish hover echo.

## Verification

- Menu rendering/input regression: 97 headless checks; native render-target dimensions and original logical coordinates checked at four sizes in Smooth and Sharp modes.
- Graphical path: 169 checks, including eight decoded panels at four sizes, click mapping, original-centre equality with decorative wings shown/hidden and 4:3 equality with wings shown/hidden. These compare wings within the new renderer, not old versus new text rasterization.
- Existing flows: front end 107, skirmish setup 87, loading 13, hero advance 21 and UI fixes 194 checks passed.
- Visually reviewed the main menu and options comparison, including unchanged typeface and placement, clearer text, and no new clipping.

Godot reference: [Viewport oversampling and override](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-property-oversampling). The logical SubViewport stretch enables font oversampling without altering shared font resources.
