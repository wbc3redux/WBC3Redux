extends SceneTree
## Hand-test fixes (HAND_TEST_FINDINGS.md): F1 edit text placement (ui_canvas.gd edit_lines), the selected state of
## radio / toggle buttons (ui_canvas.gd button_row; the options tabs) and F3 the building ring layer redrawn when the
## selection is written directly (building_marker.gd selected).
## Never touches user://settings.cfg: the options screen runs on a copied settings file.

const Canvas = preload("res://core/ui_canvas.gd")
const OptionsScreen = preload("res://menus/options_screen.gd")
const Settings = preload("res://simulation/game_settings.gd")
const BuildingMarker = preload("res://battle/building_marker.gd")
const BuildingState = preload("res://simulation/building_state.gd")
const Rules = preload("res://simulation/production_rules.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("UI fix check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui_layout.json"))
	edit_text(layout)
	selected_buttons(layout)
	await options_tabs()
	await building_ring()
	if failures == 0: print("UI fix checks passed: ", checks)
	else: printerr("UI fix failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

func canvas_with(layout: Dictionary, panels: Array) -> Canvas:
	var canvas := Canvas.new()
	canvas.setup(layout)
	for name in panels: canvas.placements.append({panel = canvas.panel_by_name(name), offset = Vector2i.ZERO})
	return canvas

func item_of(canvas: Canvas, key: String) -> Dictionary:
	for item in canvas.items():
		if item.key == key: return item
	return {}

# F1: the hero name is drawn in the edit's own font (FO_MEDIUM 15, not the listbox font FO_LARGE 28), inside the box.
func edit_text(layout: Dictionary):
	var canvas := canvas_with(layout, ["PNL_CREATEHERO"])
	var key := "PNL_CREATEHERO/EDIT_NAME#0"
	canvas.control_text[key] = "TEST_"
	var edit := item_of(canvas, key)
	var field := item_of(canvas, "PNL_CREATEHERO/IM_EDITOR256#0")
	check(not edit.is_empty() and not field.is_empty(), "creation panel has the name edit and its field")
	var lines := canvas.edit_lines(edit)
	check(lines.size() == 1 and lines[0][0] == "TEST_", "one line with the typed name")
	if lines.size() != 1: return
	var info := canvas.font(lines[0][1])
	check(layout.fonts[str(lines[0][1])].name == "FO_MEDIUM" and int(info.size) == 15, "EDIT_NAME uses its FO_MEDIUM (15)")
	var rect: Rect2i = lines[0][2]
	check(rect.position.y >= edit.rect.position.y and rect.end.y <= edit.rect.end.y, "the text cell lies inside the 17-pixel edit box")
	check(rect.position.y > field.rect.position.y and rect.end.y < field.rect.end.y, "and inside the field's frame (IM_EDITOR256)")
	check(rect.position.x == edit.rect.position.x + Canvas.EDIT_INSET, "2 pixels in from the left")
	# Every edit control of every panel: the first line's cell (at least its baseline) stays inside the box.
	var all := Canvas.new()
	all.setup(layout)
	for panel in layout.xci.panels: all.placements.append({panel = panel, offset = Vector2i.ZERO})
	var seen := 0
	for item in all.items():
		if int(item.element.type) != Canvas.EDIT: continue
		all.control_text[item.key] = "Wg"
		var first := all.edit_lines(item)
		seen += 1
		check(first.size() == 1, "%s draws a line in %s" % [item.key, item.element.font])
		if first.is_empty(): continue
		var cell: Rect2i = first[0][2]
		var baseline := cell.position.y + int(all.font(first[0][1]).baseline)
		check(cell.position.y >= item.rect.position.y and baseline <= item.rect.end.y, "%s: text top and baseline inside the box" % item.key)
	check(seen > 10, "edit controls found (%d)" % seen)
	var multi := {}
	for item in all.items():
		if int(item.element.type) == Canvas.EDIT and int(item.element.subtype) == Canvas.MULTI_LINE_EDIT and item.element.size[1] > 100:
			multi = item
			break
	if not multi.is_empty():
		all.control_text[multi.key] = "a\nb\nc"
		var stacked := all.edit_lines(multi)
		check(stacked.size() == 3 and stacked[1][2].position.y - stacked[0][2].position.y == int(all.font(stacked[0][1]).size), "a multi-line edit stacks lines from the top")
	all.free()
	canvas.free()

# A selected radio / ticked toggle (control_state 2) draws BM_CHECKBOX's ticked rows 4..7.
func selected_buttons(layout: Dictionary):
	var canvas := canvas_with(layout, ["PNL_GAMEOPTIONS"])
	var tab := item_of(canvas, "PNL_GAMEOPTIONS/BUTT_GAMEOPTIONS_OPTION#1")
	check(tab.element.bitmap == "BM_CHECKBOX", "the tabs are BM_CHECKBOX radios")
	check(canvas.button_row(tab, 8) == 0, "unselected tab: row 0")
	canvas.hovered = tab
	check(canvas.button_row(tab, 8) == 1, "unselected tab hovered: row 1")
	canvas.control_state[tab.key] = Canvas.SELECTED
	check(canvas.button_row(tab, 8) == 5, "selected tab hovered: row 5 (ticked, hover)")
	canvas.hovered = {}
	check(canvas.button_row(tab, 8) == 4, "selected tab: row 4 (ticked)")
	canvas.pressed = tab
	check(canvas.button_row(tab, 8) == 6, "selected tab pressed: row 6")
	canvas.pressed = {}
	check(canvas.button_row(tab, 4) == 2, "a sheet without ticked rows draws the pressed row")
	canvas.disable_buttons = true
	check(canvas.button_row(tab, 8) == 7, "selected and disabled: row 7")
	canvas.free()

func options_tabs():
	var settings_file := "user://ui-fixes-test-settings.cfg"
	DirAccess.remove_absolute(settings_file)
	Settings.use_file(settings_file)
	var options = OptionsScreen.new()
	root.add_child(options)
	await process_frame
	check(tab_rows(options) == [4, 0, 0, 0, 0], "the open options screen draws the Gameplay tab selected (%s)" % [tab_rows(options)])
	check(options.click(options.opt_key("BUTT_GAMEOPTIONS_OPTION", 2)) and options.page == 2, "clicking Sound selects it")
	check(tab_rows(options) == [0, 0, 4, 0, 0], "then only Sound is drawn selected (%s)" % [tab_rows(options)])
	options.queue_free()
	await process_frame
	DirAccess.remove_absolute(settings_file)

func tab_rows(options) -> Array:
	var rows := []
	for i in OptionsScreen.TAB_X.size(): rows.append(options.canvas.button_row(item_of(options.canvas, options.opt_key("BUTT_GAMEOPTIONS_OPTION", i)), 8))
	return rows

# F3: main.gd writes `selected` directly (building placed, click selection). The ring layer must redraw on that change,
# else a deselected building keeps its last ring and strip on screen.
func building_ring():
	BuildingMarker.harness = false
	var rules = Rules.new()
	var definition: Dictionary = rules.definition("BAGA")
	check(not definition.is_empty(), "Garrison definition")
	var state = BuildingState.new(1, "BAGA", 0, Vector2(20 * 32, 30 * 24), definition, 20, 30)
	state.hit_points = 100
	var marker = BuildingMarker.new()
	marker.configure(state)
	root.add_child(marker)
	var painted := {"calls": 0}
	var inner: Callable = marker.ring_layer.painter
	marker.ring_layer.painter = func(layer):
		painted.calls += 1
		inner.call(layer)
	await process_frame
	marker.selected = true                 # _on_building_placed / select_building_at
	marker.set_marker(true, false)
	await process_frame
	check(painted.calls > 0, "a selected building paints its ring and strip")
	state.hit_points = state.max_hit_points
	marker.set_marker(true, false)         # main.gd every frame while selected: the strip follows the hit points
	var before: int = painted.calls
	await process_frame
	check(painted.calls > before, "the strip is repainted every frame while selected")
	marker.selected = false                # select_building_at: another building or none
	before = painted.calls
	await process_frame
	check(painted.calls > before, "a direct deselection repaints the ring layer (clears the stale strip)")
	marker.set_marker(false, false)        # main.gd's next frame: no change
	before = painted.calls
	await process_frame
	check(painted.calls == before, "no repaint while unselected and unchanged")
	marker.queue_free()
	BuildingMarker.harness = true
	await process_frame
