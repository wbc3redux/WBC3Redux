extends Control
## Shared host: original 800x600 logical coordinates, rendered at display resolution with native-size glyphs.
## Shared decorative side wings are outside the centred interface (MENU_ARTWORK.md, MENU_CLARITY.md).
## Buttons answer on release, play NewClick (0x60f558) and call press(key); state 3 (disabled) never answers
## (FUN_0045c5b0 / FUN_0045c880). Full-screen hotspots (subtype 5 pads) are not clickable targets.
##
## Parity pass 2 (UI_RESEARCH.md "Parity pass 2"):
## * Drop-down lists (0x45cfe0, PNL_DROPDOWNLIST 0x130, Read): the entries are one '\n'-separated string, at most 39
##   characters each; the list is one column of 0x14 (20) pixel rows, as wide as the widest entry in font 5 plus 20, opened
##   at the caller's point (the click: setup options at the mouse, side rows at the mouse x - 15), moved left / up so it
##   ends at x 795 / y 595; listbox text colour (199, 145, 100); the 800x600 BUTT_DROPDOWNLIST behind it closes it on a
##   click outside. The listbox frame and the highlight (IM_DROPLIST_HIGHLIGHT, an image drawn at run time) are not
##   traced: a dark fill, a thin border and a lighter row (Open).
## * Screen help (0x448870 -> 0x448cf0, PNL_SCREENHELP 0x10 at layer 32000, Read): English/ScreenHelp.txt lines
##   [SCREENnn_TEXTkk] in order; "<x,y> text" points at (x, y), "<> text" has no pointer, a line without '<' is a heading.
##   Each line is wrapped in font 0xf to 0x171 (369) pixels, at most 8 rows, into a box at x 0xd0 (208), 0x177 (375)
##   wide, rows x (text height + 2) + 6 high; boxes start at y 0x96 (150) with a gap of (0x122 - total height) / (n - 1),
##   at most 0x17; the pointer starts at the box corner nearest to its target. Shown on the first visit of a screen
##   (0x448a80: one flag per screen, saved with the options) or with F1 (key code 0x10a) on screens whose callback
##   handles it; any click closes it (PAD_FULLSCREEN800x600). The box and pointer drawing is not traced (Open: dark
##   box, light border, a line to the target); the first-visit flags live in <settings file>_screenhelp.cfg.
## * Keys (0x459c60 -> 0x460510, Read): the window procedure turns keys into codes (F1 0x10a, Enter 0xd, Esc 0x1b) and
##   hands them to the focused edit control, else to the button whose element byte +0x60 equals the code (0x4631d0; that
##   byte is the disabled-state font number, so only buttons with font 27 answer Esc), else to the panel callbacks as
##   message 5. No menu maps Enter to Okay or Esc to Cancel.
const Assets = preload("res://core/asset_store.gd")

const UiCanvas = preload("res://core/ui_canvas.gd")
const DisplayConfig = preload("res://core/display.gd")
const BASE := Vector2i(800, 600)
const PRESENTATION := Vector2i(1920, 1080)
const LIST_ROW := 0x14
const LIST_FONT := 5
const LIST_TEXT := Color8(199, 145, 100)
const LIST_CHARS := 39
const HELP_FONT := 0xf
const HELP_WRAP := 0x171
const HELP_X := 0xd0
const HELP_W := 0x177
const HELP_TOP := 0x96
const HELP_SPAN := 0x122
const HELP_MAX_GAP := 0x17
const KEY_F1 := 0x10a

var layout: Dictionary
var viewport := SubViewport.new()
var canvas := UiCanvas.new()
var view := TextureRect.new()
var backdrop := preload("res://menus/menu_backdrop.gd").new()
var overlay := Overlay.new()
var ignored_controls: Array = ["BUTT_SS_FULLSCREEN", "BUTT_SH_FULLSCREEN", "PAD_FULLSCREEN800x600", "BUTT_HEROLEVELUP_PAD"]
var last_point := Vector2(400, 300)        # the latest mouse position in 800x600 coordinates (lists open there)

# Drop-down list state (0x45cfe0).
var list_labels: Array = []
var list_rect := Rect2()
var list_hover := -1
var list_callback := Callable()

# Screen help state (0x448870).
var help_screen := -1                      # the screen id whose help is open, -1 = closed
var help_boxes: Array = []                 # [{"lines", "rect", "target", "anchor", "heading"}]
var help_click_text := ""

class Overlay extends Node2D:
	## Draws the open list and the screen help above the panels.
	var owner_screen
	func _draw():
		if owner_screen != null: owner_screen.draw_overlay(self)

## The window follows the Display & Audio settings (DELIBERATE MODERN CHANGE, display.gd): the DisplayManager autoload
## applies them once at start; a scene started without it (a direct launch of one scene) applies them here.
static func fit_window(window: Window):
	if window == null: return
	var display_script = load("res://core/display.gd")
	if display_script.window_applied: return
	display_script.window_applied = true
	display_script.apply_window(window)

func setup_screen():
	RenderingServer.set_default_clear_color(Color.BLACK)
	layout = Assets.json("ui_layout.json")
	canvas.setup(layout)
	for key in layout.get("extra_bitmaps", {}):      # interface art loaded by file name (tools/ui_extra.py)
		layout.exported_bitmaps["X:" + key] = layout.extra_bitmaps[key]
	viewport.size = BASE
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.resolution = BASE
	viewport.add_child(canvas)
	overlay.owner_screen = self
	overlay.z_index = 20
	viewport.add_child(overlay)
	add_child(viewport)
	view.texture = viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = DisplayConfig.menu_filter()
	view.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(backdrop)
	backdrop.bind(canvas, view)
	add_child(view)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # a full-window STOP root would eat every click before _unhandled_input
	get_viewport().size_changed.connect(place_view)
	var display_manager = DisplayConfig.node(get_tree())
	if display_manager != null: display_manager.changed.connect(place_view)
	place_view()

## The 800x600 screen fitted to the window and centred; Sharp menu scaling snaps to a whole multiple (display.gd).
func place_view():
	var window: Vector2 = get_viewport_rect().size
	if window.x <= 0 or window.y <= 0: window = Vector2(PRESENTATION)
	var rect: Rect2 = DisplayConfig.menu_rect(window, Vector2(BASE))
	view.size = rect.size
	view.position = rect.position
	view.texture_filter = DisplayConfig.menu_filter()
	DisplayConfig.prepare_menu_viewport(viewport, view, BASE)
	backdrop.place(window)

func to_native(point: Vector2) -> Vector2:
	return (point - view.position) * (Vector2(BASE) / view.size)

func strings(section: int) -> Array:
	return layout.strings.get(str(section), [])

func string_at(section: int, index: int) -> String:
	var list := strings(section)
	return String(list[index]) if index >= 0 and index < list.size() else ""

## English/Game.txt line [NNNN] (0x44f4a0), imported into the layout.
func game_text(id: int) -> String:
	return String(layout.get("game_text", {}).get(str(id), ""))

func place(panel: String, offset: Vector2i = Vector2i.ZERO, layer: int = 0):
	canvas.placements.append({panel = canvas.panel_by_name(panel), offset = offset, layer = layer})

func item(key: String) -> Dictionary:
	for i in canvas.items():
		if i.key == key: return i
	return {}

func has_item(key: String) -> bool:
	return not item(key).is_empty()

func enabled(key: String) -> bool:
	var i := item(key)
	return not i.is_empty() and canvas.state_of(i) != 3

func hit(point: Vector2) -> Dictionary:
	var list := canvas.items()
	for i in range(list.size() - 1, -1, -1):
		var entry: Dictionary = list[i]
		if not canvas.interactive(entry) or String(entry.control.name) in ignored_controls: continue
		if Rect2(entry.rect).has_point(point) and canvas.state_of(entry) != 3: return entry
	return {}

## Screens override: called with "PANEL/CONTROL#instance" for a released, enabled button.
func press(_key: String) -> void:
	pass

## Screens override: hover help (message 0x12: the control id on entry, -1 when the mouse leaves it).
func hovered_changed(_entry: Dictionary) -> void:
	pass

## Screens override: key codes the panel callback handles (message 5). Return true when used.
func key_code(_code: int) -> bool:
	return false

## Screens override: the screen help id F1 opens on this screen, or -1 (0x448870 callers).
func help_id() -> int:
	return -1

## Pushes a left press and release at the button's window position through the viewport, as the mouse does.
func real_click(key: String) -> bool:
	if not has_item(key): return false
	var point: Vector2 = view.position + Rect2(item(key).rect).get_center() * (view.size / Vector2(BASE))
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		event.global_position = point
		get_viewport().push_input(event)
	return true

## Where a list opens: the click point (0x4e6688: the message's mouse x / y); the button's centre without a mouse.
func list_point(key: String) -> Vector2:
	var button := item(key)
	if button.is_empty(): return last_point
	return last_point if Rect2(button.rect).has_point(last_point) else Rect2(button.rect).get_center()

## Presses a button by key the way a click does (tests use this); returns false when absent or disabled.
func click(key: String) -> bool:
	if not enabled(key): return false
	press(key)
	return true

func audio():
	return preload("res://core/audio_manager.gd").instance(get_tree())

## 0x459c60's key codes for a Godot key event (F1..F12 -> 0x10a.., Enter 0xd, Esc 0x1b, Tab 9), else 0.
static func original_code(event: InputEventKey) -> int:
	if event.keycode >= KEY_F1 and event.keycode <= KEY_F12: return KEY_F1 + (event.keycode - KEY_F1)
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER: return 0xd
		KEY_ESCAPE: return 0x1b
		KEY_TAB: return 9
		KEY_SPACE: return 0x20
	return 0

## 0x4631d0: the buttons whose element byte +0x60 (the disabled font number) equals the key code answer it.
func hotkey_buttons(code: int) -> Array:
	var out: Array = []
	for i in canvas.items():
		if not canvas.interactive(i): continue
		var raw := String(i.element.get("raw", "")).hex_decode()
		if raw.size() > 0x60 and raw[0x60] == code: out.append(i.key)
	return out

## Key handling shared by the screens; the screens' _unhandled_input calls it (headless runs: tests call handle_key).
func handle_key(code: int) -> bool:
	if code == 0: return false
	if help_screen >= 0:
		close_screen_help()
		return true
	if is_list_open():
		return true
	if code == KEY_F1 and help_id() >= 0:
		open_screen_help(help_id(), true)
		return true
	var used := false
	for key in (hotkey_buttons(code) if code != 0x20 else []):   # 0x460510 skips 0x4631d0 for Space
		press(key)                                 # 0x4631d0 sends the release message (msg 2) even to a disabled button
		used = true
	return key_code(code) or used

func screen_input(event: InputEvent) -> bool:
	if event is InputEventMouse: last_point = to_native(event.position)
	if help_screen >= 0:
		if event is InputEventMouseButton and event.pressed:
			close_screen_help()
		return true
	if is_list_open():
		return list_input(event)
	# The press that chose a list entry (or closed the list) owns its release: without this the release fell through to
	# the button under the list and pressed it too (playtest 2026-11-10).
	if swallow_release and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		swallow_release = false
		canvas.pressed = {}
		canvas.queue_redraw()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return handle_key(original_code(event))
	if event is InputEventMouseMotion:
		var entry := hit(to_native(event.position))
		if entry.get("key", "") != canvas.hovered.get("key", ""):
			canvas.hovered = entry
			hovered_changed(entry)
			canvas.queue_redraw()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var entry := hit(to_native(event.position))
		canvas.pressed = entry if event.pressed else {}
		canvas.queue_redraw()
		if not event.pressed and not entry.is_empty():
			audio().click()   # NewClick (0x60f558)
			press(entry.key)
		return true
	return false

# ------------------------------------------------------------------------------------------------ drop-down lists
var swallow_release := false              # the left release after a press handled by the open list

func is_list_open() -> bool:
	return not list_labels.is_empty()

func text_width(text: String, font_number: int) -> float:
	var info: Dictionary = canvas.font(font_number)
	if info.is_empty() or info.font == null: return text.length() * 8.0
	return info.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, info.size).x

## 0x45cfe0: opens the list at `at` (800x600); `callback` receives the chosen index.
func open_list(labels: Array, at: Vector2, callback: Callable, current: int = -1):
	list_labels = labels.map(func(l): return String(l).left(LIST_CHARS))
	var width := 0.0
	for l in list_labels: width = maxf(width, text_width(l, LIST_FONT))
	var size := Vector2(width + 20.0, LIST_ROW * list_labels.size())
	var pos := at
	if pos.x + size.x > 799.0: pos.x = 795.0 - size.x
	if pos.y + size.y > 599.0: pos.y = 595.0 - size.y
	pos = pos.max(Vector2.ZERO)
	list_rect = Rect2(pos, size)
	list_hover = current
	list_callback = callback
	overlay.queue_redraw()

func close_list():
	list_labels = []
	list_hover = -1
	list_callback = Callable()
	overlay.queue_redraw()

func list_index(point: Vector2) -> int:
	if not list_rect.has_point(point): return -1
	var index := int((point.y - list_rect.position.y) / LIST_ROW)
	return index if index < list_labels.size() else -1

## Chooses entry `index` of the open list (the listbox callback), as a click on it does.
func choose_list(index: int):
	var callback := list_callback
	close_list()
	if callback.is_valid() and index >= 0: callback.call(index)

func list_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var index := list_index(to_native(event.position))
		if index != list_hover:
			list_hover = index
			overlay.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index := list_index(to_native(event.position))
		audio().click()
		swallow_release = true
		if index >= 0: choose_list(index)
		else: close_list()                     # BUTT_DROPDOWNLIST: a click outside the list
	return true

# ------------------------------------------------------------------------------------------------ screen help
static func help_flags_path() -> String:
	var settings_path: String = load("res://simulation/game_settings.gd").file_path
	return settings_path.get_basename() + "_screenhelp.cfg"

## 0x448a80: true (and the flag is set and saved) the first time a screen asks; false afterwards.
static func first_visit(screen_id: int) -> bool:
	var config := ConfigFile.new()
	config.load(help_flags_path())
	var key := "Screen%02d" % screen_id
	if int(config.get_value("ScreenHelp", key, 0)) != 0: return false
	config.set_value("ScreenHelp", key, 1)
	config.save(help_flags_path())
	return true

## Marks every screen as seen (tests and captures start without first-visit popups).
static func mark_all_seen():
	var config := ConfigFile.new()
	for i in 15: config.set_value("ScreenHelp", "Screen%02d" % i, 1)
	config.save(help_flags_path())

func help_lines(screen_id: int) -> Array:
	var source: Dictionary = layout.get("screen_help", {})
	var out: Array = []
	var k := 0
	while source.has("SCREEN%02d_TEXT%02d" % [screen_id, k]):
		out.append(String(source["SCREEN%02d_TEXT%02d" % [screen_id, k]]))
		k += 1
	return out

## Word wrap to `width` pixels in `font_number` (the 0x46dde0 / 0x44f770 family; break at spaces).
func wrap_text(text: String, font_number: int, width: float, max_lines: int = 64) -> Array:
	var lines: Array = []
	var current := ""
	for word in text.split(" ", false):
		var candidate := word if current == "" else current + " " + word
		if current != "" and text_width(candidate, font_number) > width:
			lines.append(current)
			current = word
		else:
			current = candidate
		if lines.size() >= max_lines: break
	if current != "" and lines.size() < max_lines: lines.append(current)
	return lines

## 0x448870(screen, force): opens the screen help; without force only on the first visit. Returns true when shown.
func open_screen_help(screen_id: int, force: bool) -> bool:
	if not force and not first_visit(screen_id): return false
	var entries := help_lines(screen_id)
	if entries.is_empty(): return false
	close_list()
	var info: Dictionary = canvas.font(HELP_FONT)
	var line_height: float = (info.font.get_height(info.size) if not info.is_empty() and info.font != null else 14.0) + 2.0
	help_boxes = []
	var total := 0.0
	for entry in entries:
		var text: String = entry
		var target := Vector2.ZERO
		var heading := not text.begins_with("<")
		if text.begins_with("<>"): text = text.substr(2).strip_edges()
		elif text.begins_with("<"):
			var close := text.find(">")
			var numbers := text.substr(1, close - 1).split(",")
			if numbers.size() == 2: target = Vector2(int(numbers[0]), int(numbers[1]))
			text = text.substr(close + 1).strip_edges()
		var lines := wrap_text(text, HELP_FONT, HELP_WRAP, 8)
		var height := lines.size() * line_height + 6.0
		total += height
		help_boxes.append({"lines": lines, "rect": Rect2(HELP_X, 0, HELP_W, height), "target": target, "anchor": Vector2.ZERO,
			"heading": heading, "line_height": line_height})
	var gap := 0.0
	if help_boxes.size() > 1: gap = minf(float(int(HELP_SPAN - total) / (help_boxes.size() - 1)), HELP_MAX_GAP)
	var y := float(HELP_TOP)
	for box in help_boxes:
		box.rect.position.y = y
		y += box.rect.size.y + gap
		if box.target.x != 0:
			var r: Rect2 = box.rect
			var corners := [r.position, Vector2(r.end.x - 1, r.position.y), Vector2(r.position.x, r.end.y - 1), r.end - Vector2.ONE]
			var best := 0
			for c in 4:
				if corners[c].distance_squared_to(box.target) < corners[best].distance_squared_to(box.target): best = c
			box.anchor = corners[best]
	help_click_text = String(layout.get("screen_help", {}).get("CLICKTOCONTINUE", "Click to Continue..."))
	help_screen = screen_id
	overlay.queue_redraw()
	return true

func close_screen_help():
	help_screen = -1
	help_boxes = []
	overlay.queue_redraw()

# ------------------------------------------------------------------------------------------------ drawing
func overlay_text(node: CanvasItem, text: String, font_number: int, position: Vector2, colour = null, width: float = -1.0,
		align: int = HORIZONTAL_ALIGNMENT_LEFT):
	var info: Dictionary = canvas.font(font_number)
	if info.is_empty() or info.font == null: return
	var c: Color = info.colour if colour == null else colour
	if info.shadow:
		node.draw_string(info.font, position + Vector2(1, int(info.baseline) + 1), text, align, width, info.size, Color.BLACK)
	node.draw_string(info.font, position + Vector2(0, int(info.baseline)), text, align, width, info.size, c)

func draw_overlay(node: Node2D):
	if is_list_open():
		node.draw_rect(list_rect, Color(0.06, 0.04, 0.02, 0.96))
		node.draw_rect(list_rect, Color(0.55, 0.42, 0.25), false, 1.0)
		for i in list_labels.size():
			var row := Rect2(list_rect.position + Vector2(0, LIST_ROW * i), Vector2(list_rect.size.x, LIST_ROW))
			if i == list_hover: node.draw_rect(row.grow(-1), Color(0.35, 0.22, 0.1))
			overlay_text(node, String(list_labels[i]), LIST_FONT, row.position + Vector2(10, 1), LIST_TEXT)
	if help_screen >= 0:
		node.draw_rect(Rect2(Vector2.ZERO, BASE), Color(0, 0, 0, 0.35))
		for box in help_boxes:
			if box.target.x != 0:
				node.draw_line(box.anchor, box.target, Color(0.9, 0.8, 0.55), 2.0)
				node.draw_circle(box.target, 3.0, Color(0.9, 0.8, 0.55))
			node.draw_rect(box.rect, Color(0.05, 0.03, 0.02, 0.9))
			node.draw_rect(box.rect, Color(0.75, 0.62, 0.4), false, 1.0)
			var y: float = box.rect.position.y + 3
			for line in box.lines:
				overlay_text(node, String(line), HELP_FONT, Vector2(box.rect.position.x + 3, y))
				y += box.line_height
		var last: Rect2 = help_boxes[-1].rect if not help_boxes.is_empty() else Rect2(HELP_X, HELP_TOP, HELP_W, 0)
		overlay_text(node, help_click_text, HELP_FONT, Vector2(HELP_X, minf(last.end.y + 8, 580)), null, HELP_W, HORIZONTAL_ALIGNMENT_CENTER)

func capture_png(path: String):
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
