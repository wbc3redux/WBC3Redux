extends Control
## Standalone viewer for the decoded original interface (War4Int.xci). No gameplay wiring.
const Assets = preload("res://core/asset_store.gd")

const UiCanvas = preload("res://core/ui_canvas.gd")
const PRESENTATION := Vector2i(1920, 1080)
## Panel offsets per base resolution. HUD values are Read from FUN_0041e160 / FUN_004d4xxx
## (FUN_004620d0(0x7b, 0, 450|618, ...), FUN_004620d0(0x7e, 20|132, 456|624, ...)); menu panels open at 0,0.
const PRESETS := [
	{name = "Main menu", panels = [["PNL_MAINMENU", [2000, 2000], [2000, 2000], 100]]},
	{name = "Skirmish setup", panels = [["PNL_SS", [0, 0], [0, 0], 100]]},
	{name = "Hero selection", panels = [["PNL_SH", [0, 0], [0, 0], 0]]},
	{name = "Hero creation", panels = [["PNL_CREATEHERO", [0, 0], [0, 0], 0]]},
	{name = "Game options", panels = [["PNL_GAMEOPTIONS", [0, 0], [0, 0], 0]]},
	{name = "In-game HUD", panels = [["PNL_CONTROL_800", [0, 450], [0, 618], -150], ["PNL_STRATMAP_ON_CONTROL", [20, 456], [132, 624], 1000]]},
	{name = "Victory / defeat", panels = [["PNL_VICTORYDEFEAT_NEW", [0, 0], [0, 0], 0]]},
	{name = "Battle results", panels = [["PNL_RESULTS_MAIN", [0, 0], [0, 0], 0]]},
]
const MODES := [
	{name = "800x600 native", base = Vector2i(800, 600), present = false},
	{name = "1024x768 native", base = Vector2i(1024, 768), present = false},
	{name = "1920x1080 presentation of 800x600 (DELIBERATE PRESENTATION CHANGE)", base = Vector2i(800, 600), present = true},
	{name = "1920x1080 presentation of 1024x768 (DELIBERATE PRESENTATION CHANGE)", base = Vector2i(1024, 768), present = true},
]

var layout: Dictionary
var viewport := SubViewport.new()
var canvas := UiCanvas.new()
var view := TextureRect.new()
var bar := PanelContainer.new()
var info := Label.new()
var picker := OptionButton.new()
var entries: Array = []  # presets then every panel
var current := 0
var mode := 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	layout = Assets.json("ui_layout.json")
	if layout == null:
		push_error("assets/ui_layout.json missing; run launch.ps1 -ImportAssets")
		return
	canvas.setup(layout)
	for preset in PRESETS:
		entries.append(preset)
	for panel in layout.xci.panels:
		entries.append({name = "%d %s" % [int(panel.id), panel.name], panels = [[panel.name, [0, 0], [0, 0], 0]]})
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(canvas)
	add_child(viewport)
	view.texture = viewport.get_texture()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	var box := VBoxContainer.new()
	bar.add_child(box)
	picker.focus_mode = Control.FOCUS_NONE
	for entry in entries:
		picker.add_item(entry.name)
	picker.item_selected.connect(func(index): show_entry(index))
	box.add_child(picker)
	box.add_child(info)
	bar.modulate = Color(1, 1, 1, 0.92)
	add_child(bar)
	if "--self-test" in OS.get_cmdline_user_args():
		call_deferred("self_test")
		return
	apply_mode(0)
	show_entry(0)
	if "--capture" in OS.get_cmdline_user_args():
		capture.call_deferred()


## Saves every preset in every mode to user://ui_capture/ for side-by-side comparison with the original.
func capture() -> void:
	DirAccess.make_dir_recursive_absolute("user://ui_capture")
	bar.visible = false
	for m in MODES.size():
		apply_mode(m)
		for p in PRESETS.size():
			show_entry(p)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path := "user://ui_capture/%d_%s_mode%d.png" % [p, PRESETS[p].name.validate_filename(), m + 1]
			get_viewport().get_texture().get_image().save_png(path)
	print("Captured ", ProjectSettings.globalize_path("user://ui_capture"))
	get_tree().quit()


func show_entry(index: int) -> void:
	current = wrapi(index, 0, entries.size())
	picker.select(current)
	var base: Vector2i = MODES[mode].base
	canvas.placements.clear()
	for spec in entries[current].panels:
		var panel := canvas.panel_by_name(spec[0])
		var offset: Array = spec[1] if base.x == 800 else spec[2]
		canvas.placements.append({panel = panel, offset = Vector2i(offset[0], offset[1]), layer = spec[3]})
	canvas.hovered = {}
	canvas.pressed = {}
	canvas.queue_redraw()
	update_info()


func apply_mode(index: int) -> void:
	mode = index
	var spec: Dictionary = MODES[mode]
	viewport.size = spec.base
	canvas.resolution = spec.base
	var window: Vector2i = PRESENTATION if spec.present else spec.base
	if DisplayServer.get_name() != "headless":
		get_window().size = window
	size = window
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if spec.present else CanvasItem.TEXTURE_FILTER_NEAREST
	var rect := presentation_rect(spec.base, spec.present)
	view.position = rect.position
	view.size = rect.size
	view.stretch_mode = TextureRect.STRETCH_SCALE
	if current < entries.size() and not entries.is_empty():
		show_entry(current)


## 4:3 content scaled to fit the 1080 height, centred with black side bars (deliberate presentation change).
static func presentation_rect(base: Vector2i, present: bool) -> Rect2:
	if not present:
		return Rect2(Vector2.ZERO, base)
	var scale := float(PRESENTATION.y) / base.y
	var width := base.x * scale
	return Rect2(Vector2((PRESENTATION.x - width) / 2.0, 0), Vector2(width, PRESENTATION.y))


func to_native(point: Vector2) -> Vector2:
	var rect := presentation_rect(MODES[mode].base, MODES[mode].present)
	return (point - rect.position) * (Vector2(MODES[mode].base) / rect.size)


func update_info() -> void:
	var lines := ["%s   |   %s" % [entries[current].name, MODES[mode].name]]
	var item: Dictionary = canvas.hovered
	if not item.is_empty():
		var element: Dictionary = item.element
		lines.append("%s  element %d %s (%s/%s)  rect %s  z %d  state %d  string %s" % [item.key, int(element.id), element.name,
			element.type_name, element.subtype_name, item.rect, item.z, canvas.state_of(item), canvas.string_id(element.get("label", {}))])
	lines.append("[ ] or PgUp/PgDn: screen   1-4: mode   O: IDs overlay   D: disabled state   M: missing-art markers   H: hide bar   F12: screenshot")
	info.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var item := canvas.hit(to_native(event.position))
		if item.get("key", "") != canvas.hovered.get("key", ""):
			canvas.hovered = item
			canvas.queue_redraw()
			update_info()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		canvas.pressed = canvas.hit(to_native(event.position)) if event.pressed else {}
		canvas.queue_redraw()
		update_info()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_BRACKETRIGHT, KEY_PAGEDOWN:
				show_entry(current + 1)
			KEY_BRACKETLEFT, KEY_PAGEUP:
				show_entry(current - 1)
			KEY_1, KEY_2, KEY_3, KEY_4:
				apply_mode(event.keycode - KEY_1)
			KEY_O:
				canvas.show_overlay = not canvas.show_overlay
				canvas.queue_redraw()
			KEY_D:
				canvas.disable_buttons = not canvas.disable_buttons
				canvas.queue_redraw()
			KEY_M:
				canvas.show_missing = not canvas.show_missing
				canvas.queue_redraw()
			KEY_H:
				bar.visible = not bar.visible
			KEY_F12:
				var path := "user://ui_%s_%d.png" % [entries[current].name.validate_filename(), mode + 1]
				get_viewport().get_texture().get_image().save_png(path)
				print("Saved ", ProjectSettings.globalize_path(path))


var failed := false


func check(condition: bool, message: String) -> void:
	if not condition and not failed:
		failed = true
		push_error("UI viewer check failed: " + message)
		get_tree().quit(1)


func self_test() -> void:
	var xci: Dictionary = layout.xci
	check(xci.elements.size() == 1194 and xci.panels.size() == 386 and xci.screens.size() == 12 and xci.sections.size() == 347, "table counts")
	var controls := 0
	for i in range(PRESETS.size(), entries.size()):
		show_entry(i)
		var list := canvas.items()
		controls += list.size()
		for item in list:
			check(canvas.elements.has(int(item.element.id)), "unresolved element in " + entries[i].name)
	check(controls == 4179, "control count %d" % controls)
	for p in PRESETS.size():
		check(not canvas.panel_by_name(PRESETS[p].panels[0][0]).is_empty(), "preset panel " + PRESETS[p].name)
	apply_mode(0)
	show_entry(0)
	var labels := []
	for item in canvas.items():
		if int(item.element.type) == UiCanvas.BUTTON:
			labels.append(canvas.text_of(item.element.label))
	for expected in ["Skirmish", "Multiplayer", "Tutorial", "Options", "Editor", "Quit", "Campaign"]:
		check(expected in labels, "main menu label " + expected)
	var campaign := canvas.hit(Vector2(400, 175))
	check(campaign.get("control", {}).get("name", "") == "BUTT_MM_CAMPAIGN", "hit test main menu campaign button")
	check(layout.fonts[str(int(campaign.element.fonts[1]))].name == "FO_LARGE_HILIGHT", "hover font number")
	canvas.hovered = campaign
	check(canvas.state_of(campaign) == 1, "hover state")
	canvas.pressed = campaign
	check(canvas.state_of(campaign) == 2, "pressed state")
	canvas.disable_buttons = true
	check(canvas.state_of(campaign) == 3, "disabled state")
	canvas.disable_buttons = false
	check(canvas.texture("BM_MAINMENU") != null and canvas.texture("BM_BUTTON200") != null, "bitmaps load")
	check(canvas.font(1).font != null and layout.fonts["1"].name == "FO_LARGE", "font loads")
	show_entry(5)
	var hud := canvas.items()
	check(hud[0].rect.position == Vector2i(0, 450), "HUD control panel at 800x600 bottom")
	apply_mode(1)
	check(canvas.items()[0].rect.position == Vector2i(0, 618), "HUD control panel at 1024x768 bottom")
	show_entry(0)
	check(canvas.items()[0].rect.position == Vector2i(112, 84), "main menu centred at 1024x768 (centre sentinel hypothesis)")
	apply_mode(2)
	check(presentation_rect(Vector2i(800, 600), true) == Rect2(240, 0, 1440, 1080), "1080p presentation rect")
	check(to_native(Vector2(240 + 360 * 1.8, 175 * 1.8)).is_equal_approx(Vector2(360, 175)), "presentation mouse mapping")
	if failed:
		return
	print("UI viewer checks passed: %d panels, %d controls, %d presets, 4 modes" % [xci.panels.size(), controls, PRESETS.size()])
	get_tree().quit()
