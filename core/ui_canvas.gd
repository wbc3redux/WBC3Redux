extends Node2D
## Draws decoded XCI panels at original pixel coordinates (see UI_RESEARCH.md for evidence labels).
const Assets = preload("res://core/asset_store.gd")

const BUTTON := 0
const EDIT := 1
const SCROLLBAR := 2
const LISTBOX := 3
const LABEL := 4
const PROGRESS := 5
const PRIMITIVE := 6
const IMAGE := 7
const HOTSPOT_SUBTYPE := 5
const TEXT_BUTTON_SUBTYPE := 4
const BITMAP_BUTTON_SUBTYPE := 2
## FUN_0045c880 installs a text-drawing callback for these button subtypes only.
const TEXT_SUBTYPES := [0, 1, 3, 4]
## Image subtype 25 is never blitted as a plain bitmap here (runtime effect layer; Open).
const OVERLAY_SUBTYPE := 25
## Panel offsets >= 2000 are passed by FUN_004620d0 callers (e.g. the main menu); treated as "centre" (Open).
const CENTRE_SENTINEL := 2000

var layout: Dictionary
var elements := {}
var section_index := {}
var textures := {}
var fonts := {}
var resolution := Vector2i(800, 600)
var placements: Array = []  # [{panel, offset}]
var hovered := {}
var pressed := {}
var disable_buttons := false
## Run-time control text and state, keyed by item key "PANEL/CONTROL#instance": the original sets them after opening a
## panel (FUN_00464a90 / FUN_0045c4f0 text, FUN_0045c5b0 state, 3 = disabled). Multi-line text is drawn line by line.
var control_text := {}
var control_state := {}
## FUN_00466060(bitmap id, file) swaps the file behind an XCG bitmap at run time (results: VictoryBG / DefeatBG).
var bitmap_override := {}
## Frame (source row) of an image control drawn from a multi-frame bitmap, e.g. the loading bar BM_PROGRESSHT_PROGRESS
## (11 frames of 135 rows: 1 %, 10 % .. 100 %). Milestone 11-menus.
var control_frame := {}
## Parity pass 2: a progress bar's fill 0..1 (frame 0 = the empty bar, frame 1 = the full bar drawn up to the fill; a
## negative fill hides the bar), an image's source offset (BM_RESULTS_STATUS frames side by side; an offset outside the
## bitmap draws nothing, as 0x45e410(.., 100, 100) moves the frame off the image) and a per-control bitmap (0x463780 sets
## a bar's bitmap, e.g. the player's colour in the advanced results).
var control_fill := {}
## A screen's own text over everything (the credits' overlay image IM_WBC3CREDITS_TEXT, 0x406e90).
var overlay_text := Callable()
## A horizontal scrollbar's value 0..1 (setup session: the Army Setup Points slider). The bitmap holds the 170-wide track
## and, one pixel to its right, the 30-wide thumb (BM_HSBAR_170, Data); the scrollbar draw itself is not traced, so the
## thumb runs over the track's width less its own (Open).
var control_scroll := {}
const SCROLL_THUMB := 30
## F5: a listbox drawn the original's way (draw_list), keyed like control_text with the selected row (-1 = none).
var control_list := {}
## S-3: a listbox's scroll bar, shared by every list (UI_RESEARCH.md "S-3", Read): bar item key -> {list (the list's key), min,
## max, page, value, state}. The link is the element's own (0x4620d0: list +0x2c / +0x30 -> the bar of the list's instance).
## The value is the list's scroll in pixels (0x4649f0 copies it to list +0x40). A screen fills a list with set_list() and
## hands its mouse events to list_input(); list_picked says a row was chosen (message 7).
var list_bars := {}
signal list_picked(list_key: String, row: int)
const LIST_LINE := Vector2i(2, 1)         # 0x461940: rows start at (x + 2, y + 1), the text 2 lower, clipped to w - 4 x h - 2
const LIST_TEXT_DOWN := 2
const BAR_NORMAL := 0                     # 0x463ec0 by state: 0 / 4 / 5 / 6 normal, 3 disabled, 7 / 8 an arrow held, 10 / 11 at an end
const BAR_DISABLED := 3
const BAR_DOWN_HELD := 7
const BAR_UP_HELD := 8
const BAR_AT_MIN := 10
const BAR_AT_MAX := 11
const BAR_ARROW_STEP := 5                 # 0x4606a0: a list's arrow moves 5 pixels per tick (a bar without a list 1)
const BAR_WHEEL_STEP := 15                # 0x461520: a list's wheel notch moves 15 pixels (without a list 1)
const BAR_TICK := 0.05                    # the window's 50 ms timer (0x45a7b0, SetTimer 0x32) runs 0x4606a0
var bar_held := ""                        # the bar under a held button (0x37c), "" none
var bar_mode := -1                        # 0x384: the zone pressed, 0x4648c0's 0..4
var bar_point := Vector2.ZERO             # the mouse (0x4606a0 re-reads it each tick)
var bar_drag_y := 0                       # 0x38c
var bar_drag_value := 0                   # 0x390
var bar_clock := 0.0
var control_offset := {}
var control_hidden := {}        # item key -> true: not drawn (the original moves such a control off the screen, 0x45e410)
var control_align := {}         # item key -> HORIZONTAL_ALIGNMENT_*: a label's justification (0x464c60 mode 1 = centred)
var bitmap_override_by_key := {}
## Font of the text drawn on a progress bar (0x463700; the bar's own font is not traced: FO_SMALL, Open).
const PROGRESS_FONT := 2
## control_state value of a selected radio (the options tab, 0x45c740 group 9) or a ticked toggle (Tip of the day).
## HYPOTHESIS (the radio draw LAB_0045cde0 is not traced): an 8-row sheet such as BM_CHECKBOX holds the unticked states
## 0..3 and below them the ticked ones (empty ring / skull, Data), so a selected button draws its state's row + 4; a
## sheet without those rows draws the pressed row.
const SELECTED := 2
const CHECKED_ROWS := 4
## Edit text (the edit draw callback is not traced, Open): the font the XCI element names (Data), 2 pixels in from the left;
## a single-line edit centres the font's cell height in the box, a multi-line one stacks lines from the top.
const EDIT_INSET := 2
const MULTI_LINE_EDIT := 7
var show_overlay := false
var show_missing := true


func setup(data: Dictionary) -> void:
	layout = data
	for element in layout.xci.elements:
		elements[int(element.id)] = element
	for section in layout.xci.sections:
		section_index[section.name] = int(section.index)


func panel_by_name(name: String) -> Dictionary:
	for panel in layout.xci.panels:
		if panel.name == name:
			return panel
	return {}


func panel_origin(offset: Vector2i, panel_size: Vector2i) -> Vector2i:
	var origin := offset
	if offset.x >= CENTRE_SENTINEL:
		origin.x = (resolution.x - panel_size.x) / 2
	if offset.y >= CENTRE_SENTINEL:
		origin.y = (resolution.y - panel_size.y) / 2
	return origin


func panel_extent(panel: Dictionary) -> Vector2i:
	var extent := Vector2i.ZERO
	for control in panel.controls:
		var element: Dictionary = elements[int(control.element_id)]
		extent.x = maxi(extent.x, int(control.position[0]) + mini(int(element.size[0]), 800))
		extent.y = maxi(extent.y, int(control.position[1]) + mini(int(element.size[1]), 600))
	return extent


## Draw list in original order: control layer (+0x30) plus the panel layer passed to FUN_004620d0.
func items() -> Array:
	var result := []
	var order := 0
	for placement in placements:
		var panel: Dictionary = placement.panel
		var origin := panel_origin(placement.offset, panel_extent(panel)) + Vector2i(int(panel.position[0]), int(panel.position[1]))
		for control in panel.controls:
			var element: Dictionary = elements[int(control.element_id)]
			var rect := Rect2i(origin + Vector2i(int(control.position[0]), int(control.position[1])),
				Vector2i(int(element.size[0]), int(element.size[1])))
			result.append({panel = panel.name, control = control, element = element, rect = rect,
				z = int(control.layer) + int(placement.get("layer", 0)), order = order,
				key = "%s/%s#%d" % [panel.name, control.name, int(control.instance)]})
			order += 1
	result.sort_custom(func(a, b): return a.z < b.z or (a.z == b.z and a.order < b.order))
	return result


func interactive(item: Dictionary) -> bool:
	return int(item.element.type) == BUTTON


func hit(point: Vector2) -> Dictionary:
	var list := items()
	for i in range(list.size() - 1, -1, -1):
		if interactive(list[i]) and Rect2(list[i].rect).has_point(point):
			return list[i]
	return {}


## Button state: 0 normal, 1 hover, 2 pressed, 3 disabled (FUN_0045c5b0: frame row = state * height).
func state_of(item: Dictionary) -> int:
	if int(item.element.type) != BUTTON:
		return 0
	if disable_buttons or int(control_state.get(item.key, 0)) == 3:
		return 3
	if pressed.get("key", "") == item.key:
		return 2
	if hovered.get("key", "") == item.key:
		return 1
	return 0


func selected(item: Dictionary) -> bool:
	return int(item.element.type) == BUTTON and int(control_state.get(item.key, 0)) == SELECTED


## Source row of a button's sheet with `frames` rows (FUN_0045c5b0: row = state; a selected one: see SELECTED).
func button_row(item: Dictionary, frames: int) -> int:
	var state := state_of(item)
	if selected(item):
		return state + CHECKED_ROWS if frames >= 2 * CHECKED_ROWS else mini(SELECTED, frames - 1)
	return mini(state, frames - 1)


func texture(bitmap: String) -> Texture2D:
	if bitmap == "" or not layout.exported_bitmaps.has(bitmap):
		return null
	if not textures.has(bitmap):
		textures[bitmap] = Assets.texture(layout.exported_bitmaps[bitmap].file)
	return textures[bitmap]


func font(number: int) -> Dictionary:
	var name := str(number)
	if not layout.fonts.has(name):
		return {}
	if not fonts.has(name):
		var info: Dictionary = layout.fonts[name]
		fonts[name] = {font = Assets.font("ui_font_%s.ttf" % String(info.file).get_basename()), size = int(info.size), baseline = int(info.baseline),
			colour = Color8(int(info.colour[0]), int(info.colour[1]), int(info.colour[2])), shadow = info.style == "DropShadow"}
	return fonts[name]


## Font number of a Font.ini name (edit elements name their font), -1 when unknown.
func font_number(font_name: String) -> int:
	for number in layout.fonts:
		if layout.fonts[number].name == font_name:
			return int(number)
	return -1


## FUN_00464cc0(section, index): section is the XCI string-table index.
func text_of(ref: Dictionary) -> String:
	var index := int(ref.get("index", -1))
	var strings: Array = layout.strings.get(str(int(ref.get("section", -1))), [])
	return strings[index] if index >= 0 and index < strings.size() else ""


func string_id(ref: Dictionary) -> String:
	var section := int(ref.get("section", -1))
	if section < 0 or int(ref.get("index", -1)) < 0:
		return ""
	return "[%04d.%d] %s" % [section, int(ref.index), ref.get("section_name", "")]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, resolution), Color.BLACK)
	for item in items():
		draw_item(item)
	if show_overlay:
		for item in items():
			draw_overlay(item)
	if overlay_text.is_valid(): overlay_text.call()


func draw_item(item: Dictionary) -> void:
	if control_hidden.has(item.key): return
	var element: Dictionary = item.element
	var rect: Rect2i = item.rect
	var kind := int(element.type)
	var state := state_of(item)
	if kind == BUTTON and int(element.subtype) == HOTSPOT_SUBTYPE:
		return
	if kind == PRIMITIVE:
		paint_primitive(element, rect)
		return
	if kind == IMAGE and int(element.subtype) == OVERLAY_SUBTYPE:
		return
	if kind in [BUTTON, IMAGE, SCROLLBAR, PROGRESS] and element.bitmap != "" and not (kind == BUTTON and int(element.subtype) == TEXT_BUTTON_SUBTYPE):
		var tex := texture(String(bitmap_override_by_key.get(item.key, bitmap_override.get(element.bitmap, element.bitmap))))
		if tex and kind == PROGRESS and control_fill.has(item.key):
			var fill := float(control_fill[item.key])
			if fill >= 0.0:
				var h := rect.size.y
				draw_texture_rect_region(tex, Rect2(rect.position, Vector2(rect.size.x, h)), Rect2(0, 0, rect.size.x, h))
				var w := roundf(clampf(fill, 0.0, 1.0) * rect.size.x)
				if w > 0: draw_texture_rect_region(tex, Rect2(rect.position, Vector2(w, h)), Rect2(0, h, w, h))
		elif tex and kind == IMAGE and control_offset.has(item.key):
			var offset: Vector2i = control_offset[item.key]
			if offset.x < tex.get_width() and offset.y < tex.get_height():
				var size := Vector2(mini(rect.size.x, tex.get_width() - offset.x), mini(rect.size.y, tex.get_height() - offset.y))
				draw_texture_rect_region(tex, Rect2(rect.position, size), Rect2(Vector2(offset), size))
		elif tex and kind == SCROLLBAR and list_bars.has(item.key):
			draw_list_bar(item, tex)
		elif tex and kind == SCROLLBAR and control_scroll.has(item.key):
			draw_texture_rect_region(tex, Rect2(rect.position, rect.size), Rect2(Vector2.ZERO, rect.size))
			var x := roundf(clampf(float(control_scroll[item.key]), 0.0, 1.0) * (rect.size.x - SCROLL_THUMB))
			draw_texture_rect_region(tex, Rect2(rect.position + Vector2i(int(x), 0), Vector2(SCROLL_THUMB, rect.size.y)),
				Rect2(rect.size.x + 1, 0, SCROLL_THUMB, rect.size.y))
		elif tex:
			var frames := maxi(1, tex.get_height() / maxi(1, rect.size.y))
			var row := button_row(item, frames) if kind == BUTTON else mini(int(control_frame.get(item.key, 0)), frames - 1)
			# FUN_0045c880/FUN_0045c5b0: source x = column (+0x118) * width, y = state * height.
			var column := int(element.column) if kind == BUTTON and int(element.subtype) == BITMAP_BUTTON_SUBTYPE else 0
			var source := Rect2(column * rect.size.x, row * rect.size.y, mini(rect.size.x, tex.get_width()), mini(rect.size.y, tex.get_height()))
			draw_texture_rect_region(tex, Rect2(rect.position, source.size), source)
		elif show_missing and layout.missing_bitmaps.has(element.bitmap):
			draw_missing(rect, element.bitmap)
	if kind == BUTTON and int(element.subtype) in TEXT_SUBTYPES:
		# FUN_0045c9a0: font +0x18 for state 0, +0x1c for states 1-2, +0x20 for state 3; centred at w/2, top at h/4.
		var font_number := int(element.fonts[[0, 1, 1, 2][state]])
		draw_text(String(control_text.get(item.key, text_of(element.label))), font_number, Rect2i(rect.position + Vector2i(0, rect.size.y / 4), rect.size), HORIZONTAL_ALIGNMENT_CENTER)
	elif kind == LABEL:
		draw_text(String(control_text.get(item.key, text_of(element.text))), int(element.font), rect, int(control_align.get(item.key, HORIZONTAL_ALIGNMENT_LEFT)))
	elif kind == EDIT and control_text.has(item.key):
		draw_edit(item)
	elif kind == PROGRESS and control_text.has(item.key):
		if float(control_fill.get(item.key, 0.0)) >= 0.0:
			draw_text(String(control_text[item.key]), PROGRESS_FONT, Rect2i(rect.position + Vector2i(0, 2), rect.size), HORIZONTAL_ALIGNMENT_CENTER)
	elif kind == LISTBOX and control_list.has(item.key):
		draw_list(item)
	elif control_text.has(item.key):
		# Listbox rows (the list draw callback is not traced): one line per entry from the top-left, font 1.
		var y := 0
		for line in String(control_text[item.key]).split("\n"):
			draw_text(line, 1, Rect2i(rect.position + Vector2i(4, 2 + y), Vector2i(rect.size.x - 8, 20)), HORIZONTAL_ALIGNMENT_LEFT)
			y += 18


## Row height of a listbox (item_metrics[2]; 20 when the element has none).
static func list_row_height(element: Dictionary) -> int:
	var metrics: Array = element.get("item_metrics", [])
	return int(metrics[2]) if metrics.size() > 2 and int(metrics[2]) > 0 else 20


## The entry under a point of a listbox: 0x45e610, (scroll + y) / row height; -1 outside the entries.
func list_row_at(item: Dictionary, point: Vector2) -> int:
	var rect := Rect2(item.rect)
	if not rect.has_point(point): return -1
	var row := (list_scroll(item) + int(point.y - rect.position.y)) / list_row_height(item.element)
	return row if row < list_lines(item).size() else -1


func list_lines(item: Dictionary) -> PackedStringArray:
	var text := String(control_text.get(item.key, ""))
	return text.split("\n") if text != "" else PackedStringArray()


## 0x461940: the rows the draw loop reaches: [row, the row's top within the list]. First row = scroll / row height; the
## loop ends past the list's last line.
func list_rows(item: Dictionary) -> Array:
	var height := list_row_height(item.element)
	var scroll := list_scroll(item)
	var first := scroll / height
	var top := LIST_LINE.y + first * height - scroll
	var rows := []
	for row in range(first, list_lines(item).size()):
		if top > int(item.rect.size.y) - 1: break
		rows.append([row, top])
		top += height
	return rows


## 0x461940 clips to the list's inner rectangle, so a row is cut at the edge. A CanvasItem has no scissor for one draw call:
## the rebuild leaves out a row whose text would cross the edge (presentation difference, UI_RESEARCH.md "S-3" Open).
func list_row_fits(item: Dictionary, top: int, font_number: int) -> bool:
	var info := font(font_number)
	var cell := int(info.size) if not info.is_empty() else list_row_height(item.element) - LIST_TEXT_DOWN
	var y := top + LIST_TEXT_DOWN
	return y >= LIST_LINE.y and y + cell <= int(item.rect.size.y) - 1


func draw_list(item: Dictionary) -> void:
	var element: Dictionary = item.element
	var rect: Rect2i = item.rect
	var fonts: Array = element.get("fonts", [])
	var dark := font_number(String(fonts[0])) if fonts.size() > 0 else 1
	var light := font_number(String(fonts[1])) if fonts.size() > 1 else dark
	var height := list_row_height(element)
	var lines := list_lines(item)
	for entry in list_rows(item):
		var number := light if int(entry[0]) == int(control_list[item.key]) else dark
		if not list_row_fits(item, int(entry[1]), number): continue
		draw_text(lines[int(entry[0])], number, Rect2i(rect.position + Vector2i(LIST_LINE.x, int(entry[1]) + LIST_TEXT_DOWN),
			Vector2i(rect.size.x - 2 * LIST_LINE.x, height)), HORIZONTAL_ALIGNMENT_LEFT)


# ---------------------------------------------------------------------------------------- list scrolling (S-3)
## The key of a list's bar (0x4620d0), "" for a list without one in its panel.
func list_bar_key(item: Dictionary) -> String:
	var name := String(item.element.get("scrollbar", ""))
	if name == "" or int(item.element.get("subtype", 0)) != 10: return ""
	var key := "%s/%s#%d" % [item.panel, name, int(item.control.instance)]
	for candidate in items():
		if candidate.key == key and int(candidate.element.type) == SCROLLBAR: return key
	return ""


func list_scroll(item: Dictionary) -> int:
	var key := list_bar_key(item)
	return int(list_bars[key].value) if list_bars.has(key) else 0


## 0x461f50 + 0x461fe0 + 0x461d90: the list's entries and chosen row. The bar's range comes from the entries: min 0, max =
## rows * height - h + 2, page = h - height; a list that fits leaves the bar disabled (state 3), as 0x4620d0 opens it. The
## screens refresh the same entries often, so the scroll stays.
func set_list(item: Dictionary, lines: Array, row: int) -> void:
	control_text[item.key] = "\n".join(lines)
	control_list[item.key] = row
	var key := list_bar_key(item)
	if key == "": return
	var height := list_row_height(item.element)
	var h := int(item.rect.size.y)
	var total := height * lines.size()
	var bar: Dictionary = list_bars.get(key, {"list": item.key, "value": 0, "state": BAR_NORMAL})
	if total > h - 2:
		bar.merge({"min": 0, "max": total - h + 2, "page": h - height}, true)
		if int(bar.state) == BAR_DISABLED: bar.state = BAR_NORMAL
		bar.value = clampi(int(bar.value), 0, int(bar.max))
		bar_end_state(bar)
	else:
		bar.merge({"min": 0, "max": 0, "page": 0, "value": 0, "state": BAR_DISABLED}, true)
	list_bars[key] = bar


## 0x4646c0(.., 0): an enabled bar shows its end state.
func bar_end_state(bar: Dictionary) -> void:
	if int(bar.state) == BAR_DISABLED: return
	if int(bar.value) <= int(bar.min): bar.state = BAR_AT_MIN
	elif int(bar.value) >= int(bar.max): bar.state = BAR_AT_MAX
	else: bar.state = BAR_NORMAL


## The thumb's offset below the top arrow (0x463ec0, 0x4648c0): track = h - 3 w, the arrows and the thumb are w square.
func bar_thumb(bar: Dictionary, item: Dictionary) -> int:
	var track := int(item.rect.size.y) - 3 * int(item.rect.size.x)
	if int(bar.value) <= int(bar.min): return 0
	if int(bar.value) >= int(bar.max): return track
	return track * (int(bar.value) - int(bar.min)) / (int(bar.max) - int(bar.min) + 1)


## 0x4648c0: 0 top arrow, 1 track above the thumb, 2 thumb, 3 track below, 4 bottom arrow, -1 outside.
func bar_zone(item: Dictionary, point: Vector2) -> int:
	var w := int(item.rect.size.x)
	var h := int(item.rect.size.y)
	var x := int(floorf(point.x)) - int(item.rect.position.x)
	var y := int(floorf(point.y)) - int(item.rect.position.y)
	if x < 0 or y < 0 or x >= w or y >= h: return -1
	if y < w: return 0
	if y >= h - w: return 4
	var thumb := bar_thumb(list_bars[item.key], item)
	if y < thumb + w: return 1
	return 3 if y >= 2 * w + thumb else 2


## 0x463ec0 for vertical bars: the sheet holds the track (h rows), then w-square tiles: thumb, top arrow normal / held /
## disabled, bottom arrow normal / held / disabled. A disabled bar has no thumb.
func draw_list_bar(item: Dictionary, tex: Texture2D) -> void:
	var bar: Dictionary = list_bars[item.key]
	var rect: Rect2i = item.rect
	var w := rect.size.x
	var h := rect.size.y
	var state := int(bar.state)
	var tile := Vector2(w, w)
	draw_texture_rect_region(tex, Rect2(rect.position, rect.size), Rect2(Vector2.ZERO, rect.size))
	if state != BAR_DISABLED:
		draw_texture_rect_region(tex, Rect2(rect.position + Vector2i(0, w + bar_thumb(bar, item)), tile), Rect2(Vector2(0, h), tile))
	var top := 3 if state == BAR_DISABLED or state == BAR_AT_MIN else (2 if state == BAR_UP_HELD else 1)
	var bottom := 6 if state == BAR_DISABLED or state == BAR_AT_MAX else (5 if state == BAR_DOWN_HELD else 4)
	draw_texture_rect_region(tex, Rect2(rect.position, tile), Rect2(Vector2(0, h + top * w), tile))
	draw_texture_rect_region(tex, Rect2(rect.position + Vector2i(0, h - w), tile), Rect2(Vector2(0, h + bottom * w), tile))


func bar_item(key: String) -> Dictionary:
	for candidate in items():
		if candidate.key == key: return candidate
	return {}


## The list or bar under a point, top control first (0x460fd0), {} when none.
func list_control_at(point: Vector2) -> Dictionary:
	var list := items()
	for i in range(list.size() - 1, -1, -1):
		var entry: Dictionary = list[i]
		var kind := int(entry.element.type)
		if (list_bars.has(entry.key) and kind == SCROLLBAR) or (kind == LISTBOX and control_list.has(entry.key)):
			if Rect2(entry.rect).has_point(point): return entry
	return {}


## A screen's mouse events for its lists and their bars, `point` in panel pixels. True when the event was theirs: a press on
## a list or bar, a wheel notch over one, the motion and release of a held bar.
func list_input(event: InputEvent, point: Vector2) -> bool:
	bar_point = point
	if event is InputEventMouseMotion:
		if bar_mode == 2 and bar_held != "": bar_drag()
		return bar_held != ""
	if not event is InputEventMouseButton: return false
	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var target := list_control_at(point)
		if target.is_empty(): return false
		if event.pressed: bar_wheel(target, event.button_index == MOUSE_BUTTON_WHEEL_UP)
		return true
	if event.button_index != MOUSE_BUTTON_LEFT: return false
	if not event.pressed:
		if bar_held == "": return false
		bar_release()
		return true
	var target := list_control_at(point)
	if target.is_empty(): return false
	if int(target.element.type) == SCROLLBAR: bar_press(target)
	else: list_press(target)
	return true


## 0x45e610, a listbox: the row under the press becomes the choice (message 7); the chosen row again sends nothing.
func list_press(item: Dictionary) -> void:
	var row := list_row_at(item, bar_point)
	if row < 0 or row == int(control_list[item.key]): return
	control_list[item.key] = row
	queue_redraw()
	list_picked.emit(item.key, row)


## 0x45e610, a scrollbar: an arrow or track zone holds only while the value can move that way; nothing moves before a tick.
func bar_press(item: Dictionary) -> void:
	var bar: Dictionary = list_bars[item.key]
	if int(bar.state) == BAR_DISABLED: return
	var zone := bar_zone(item, bar_point)
	var value := int(bar.value)
	if (zone == 0 or zone == 1) and value <= int(bar.min): return
	if (zone == 3 or zone == 4) and value >= int(bar.max): return
	if zone < 0: return
	if zone == 0: bar.state = BAR_UP_HELD
	elif zone == 4: bar.state = BAR_DOWN_HELD
	elif zone == 2:
		bar_drag_y = int(floorf(bar_point.y))
		bar_drag_value = value
	bar_mode = zone
	bar_held = item.key
	queue_redraw()


## 0x45fa90: value = (max - min + 1) * dy / (h - 3 w) + the value at the press, clamped to the range.
func bar_drag() -> void:
	var item := bar_item(bar_held)
	var bar: Dictionary = list_bars[bar_held]
	var track := int(item.rect.size.y) - 3 * int(item.rect.size.x)
	var dy := int(floorf(bar_point.y)) - bar_drag_y
	var value := clampi((int(bar.max) - int(bar.min) + 1) * dy / track + bar_drag_value, int(bar.min), int(bar.max))
	if value == int(bar.value): return
	bar.value = value
	queue_redraw()


## 0x45eb70: the bar lets go and shows its end state.
func bar_release() -> void:
	var bar: Dictionary = list_bars.get(bar_held, {})
	bar_held = ""
	bar_mode = -1
	if not bar.is_empty():
		bar.state = BAR_NORMAL
		bar_end_state(bar)
	queue_redraw()


## 0x461520: over a list or its bar, a notch moves the value 15 pixels unless it is already at that end. Neither this nor an
## arrow tick clamps, so a list can rest a few pixels past an end, as the original's does.
func bar_wheel(item: Dictionary, up: bool) -> void:
	var key: String = item.key if list_bars.has(item.key) else list_bar_key(item)
	if not list_bars.has(key): return
	var bar: Dictionary = list_bars[key]
	if int(bar.state) == BAR_DISABLED: return
	if up and int(bar.value) <= int(bar.min): return
	if not up and int(bar.value) >= int(bar.max): return
	bar.value = int(bar.value) + (-BAR_WHEEL_STEP if up else BAR_WHEEL_STEP)
	if bar_held == "": bar_end_state(bar)
	queue_redraw()


## 0x4606a0, every 50 ms under a held button: the pressed zone repeats while the mouse stays on it (a page zone also on the
## arrow beyond it); a page step clamps to the range.
func bar_tick() -> void:
	if bar_held == "" or bar_mode == 2: return
	var item := bar_item(bar_held)
	var bar: Dictionary = list_bars[bar_held]
	var zone := bar_zone(item, bar_point)
	var value := int(bar.value)
	match bar_mode:
		0:
			if zone == 0 and value > int(bar.min): value -= BAR_ARROW_STEP
		1:
			if (zone == 1 or zone == 0) and value > int(bar.min): value = maxi(value - int(bar.page), int(bar.min))
		3:
			if (zone == 3 or zone == 4) and value < int(bar.max): value = mini(value + int(bar.page), int(bar.max))
		4:
			if zone == 4 and value < int(bar.max): value += BAR_ARROW_STEP
	if value == int(bar.value): return
	bar.value = value
	if bar_mode == 0 or bar_mode == 1:
		if value <= int(bar.min): bar.state = BAR_AT_MIN
	elif value >= int(bar.max): bar.state = BAR_AT_MAX
	queue_redraw()


func _process(delta: float) -> void:
	bar_clock += delta
	if bar_clock < BAR_TICK: return
	bar_clock = fmod(bar_clock, BAR_TICK)
	bar_tick()


func paint_primitive(element: Dictionary, rect: Rect2i) -> void:
	var c: Array = element.colours[0]
	var colour := Color8(int(c[0]), int(c[1]), int(c[2]))
	match int(element.subtype):
		18:
			draw_line(rect.position, rect.end, colour)
		19:
			draw_rect(rect, colour, false)
		20:
			draw_rect(rect, Color(colour, 0.5))
		_:
			draw_rect(rect, colour)


## Text top at rect.position.y (hypothesis for labels); baseline from Font.ini.
func draw_text(text: String, font_number: int, rect: Rect2i, align: int) -> void:
	var info := font(font_number)
	if text == "" or info.is_empty() or info.font == null:
		return
	var y: int = rect.position.y + int(info.baseline)
	if info.shadow:
		draw_string(info.font, Vector2(rect.position.x + 1, y + 1), text, align, rect.size.x, info.size, Color.BLACK)
	draw_string(info.font, Vector2(rect.position.x, y), text, align, rect.size.x, info.size, info.colour)


## Lines of an edit control's text as [text, font number, rect] (see EDIT_INSET).
func edit_lines(item: Dictionary) -> Array:
	var rect: Rect2i = item.rect
	var number := font_number(String(item.element.get("font", "")))
	var info := font(number)
	if info.is_empty():
		return []
	var lines := String(control_text.get(item.key, "")).split("\n")
	var top := 0
	if int(item.element.subtype) != MULTI_LINE_EDIT:
		lines = lines.slice(0, 1)
		top = (rect.size.y - int(info.size)) / 2
	var result := []
	for line in lines:
		if top + int(info.baseline) > rect.size.y:
			break
		result.append([line, number, Rect2i(rect.position + Vector2i(EDIT_INSET, top), Vector2i(rect.size.x - 2 * EDIT_INSET, int(info.size)))])
		top += int(info.size)
	return result


func draw_edit(item: Dictionary) -> void:
	for line in edit_lines(item):
		draw_text(line[0], line[1], line[2], HORIZONTAL_ALIGNMENT_LEFT)


func draw_missing(rect: Rect2i, bitmap: String) -> void:
	var colour := Color(1, 0, 1, 0.55)
	draw_rect(rect, colour, false, 1.0)
	for x in range(0, rect.size.x + rect.size.y, 12):
		var a := Vector2(rect.position.x + mini(x, rect.size.x), rect.position.y + maxi(0, x - rect.size.x))
		var b := Vector2(rect.position.x + maxi(0, x - rect.size.y), rect.position.y + mini(x, rect.size.y))
		draw_line(a, b, Color(colour, 0.25))
	draw_string(ThemeDB.fallback_font, Vector2(rect.position) + Vector2(3, 12), "missing " + bitmap, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, 10, colour)


func draw_overlay(item: Dictionary) -> void:
	var element: Dictionary = item.element
	var rect: Rect2i = item.rect
	var colour := Color(0.3, 1, 0.4, 0.9) if interactive(item) else Color(0.4, 0.8, 1, 0.6)
	if hovered.get("key", "") == item.key:
		colour = Color.YELLOW
	draw_rect(rect, colour, false, 1.0)
	var label := "%s#%d e%d z%d" % [item.control.name, int(item.control.instance), int(element.id), item.z]
	var ref: Dictionary = element.get("label", element.get("text", {}))
	var sid := string_id(ref) if ref is Dictionary else ""
	if sid != "":
		label += " " + sid
	draw_rect(Rect2(rect.position, Vector2(mini(rect.size.x, label.length() * 6 + 4), 11)), Color(0, 0, 0, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(rect.position) + Vector2(2, 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, colour)
