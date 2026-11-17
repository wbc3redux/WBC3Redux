extends Node2D
const Assets = preload("res://core/asset_store.gd")

const CollisionData = preload("res://core/collision_data.gd")
const MODES = ["walk", "build", "height", "material", "objects"]
var collision = CollisionData.new()
var camera := Camera2D.new()
var overlay := Sprite2D.new()
var mode := 0
var show_prefabs := true
var show_footprints := true
var inspector := Label.new()
var result_label := Label.new()
var choice := OptionButton.new()
var selected_cell := Vector2i(12, 64)
var probe_start := Vector2(400, 1548)
var probe_end := Vector2(720, 1548)
var probe: Dictionary = {}

func _ready():
	RenderingServer.set_default_clear_color(Color("20252b"))
	var terrain := Sprite2D.new()
	terrain.texture = Assets.texture("terrain.png")
	terrain.centered = false
	terrain.z_index = -2
	add_child(terrain)
	overlay.centered = false
	overlay.z_index = -1
	overlay.scale = Vector2(32, 24)
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(overlay)
	add_child(camera)
	full_map()
	var layer := CanvasLayer.new()
	add_child(layer)
	var top := Panel.new()
	top.size = Vector2(1280, 154)
	layer.add_child(top)
	var box := VBoxContainer.new()
	box.position = Vector2(16, 10)
	top.add_child(box)
	var title := Label.new()
	title.text = "DESERT SANDS / TERRAIN & OCCUPANCY INSPECTOR"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var note := Label.new()
	note.text = "VERIFIED: TER fields, quadrants and object masks. HYPOTHESIS: profile 0 represents Swordsman movement. Runtime fidelity unverified."
	box.add_child(note)
	var controls := HBoxContainer.new()
	box.add_child(controls)
	for text in ["Walkability / profile 0", "Necessary build gates", "TER height", "TER material ID", "Object occupancy"]:
		choice.add_item(text)
	choice.focus_mode = Control.FOCUS_NONE
	choice.item_selected.connect(set_mode)
	controls.add_child(choice)
	button(controls, "Overlay [V]", func(): overlay.visible = not overlay.visible)
	button(controls, "Full map [F]", full_map)
	button(controls, "West start", func(): focus_cell(Vector2i(12, 64)))
	button(controls, "East start", func(): focus_cell(Vector2i(113, 64)))
	button(controls, "Prefabs [G]", func(): show_prefabs = not show_prefabs; queue_redraw())
	button(controls, "Footprints [B]", func(): show_footprints = not show_footprints; queue_redraw())
	var legend := Label.new()
	legend.text = "Walk: red = terrain rejects profile 0 · amber = occupied · green = terrain admits. Build: blue = necessary gates pass, not final permission.\nWheel zoom · arrows pan · left-click probe start · right-click probe end · O cycles overlay. Probe: point unit, straight line, conservative corners."
	box.add_child(legend)
	var panel := Panel.new()
	panel.position = Vector2(12, 168)
	panel.size = Vector2(312, 438)
	layer.add_child(panel)
	inspector.position = Vector2(24, 180)
	inspector.size = Vector2(288, 416)
	inspector.add_theme_font_size_override("font_size", 14)
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(inspector)
	result_label.position = Vector2(24, 630)
	result_label.add_theme_font_size_override("font_size", 14)
	result_label.size = Vector2(285, 155)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(result_label)
	set_mode(0)
	update_probe()
	if "--self-test" in OS.get_cmdline_user_args():
		call_deferred("self_test")
	if "--capture-collision" in OS.get_cmdline_user_args():
		call_deferred("capture_preview")

func button(parent: Node, text: String, callback: Callable):
	var control := Button.new()
	control.text = text
	control.focus_mode = Control.FOCUS_NONE
	control.pressed.connect(callback)
	parent.add_child(control)

func full_map():
	camera.position = Vector2(2048, 1536)
	camera.zoom = Vector2(0.175, 0.175)
	camera.offset = -Vector2(140, 80) / camera.zoom

func focus_cell(cell: Vector2i):
	camera.position = Vector2(cell.x * 32 + 16, cell.y * 24 + 12)
	camera.zoom = Vector2(0.9, 0.9)
	camera.offset = -Vector2(140, 80) / camera.zoom

func set_mode(index: int):
	mode = index
	choice.select(index)
	overlay.texture = Assets.texture("collision_" + MODES[mode] + ".png")
	queue_redraw()

func update_probe():
	probe = collision.trace_segment(probe_start, probe_end)
	result_label.text = "STRAIGHT-LINE PROBE\n%s\nStart %s → end %s\n%s\nNo pathfinding or unit radius. No dynamic army occupancy.\nBuildings: 26 · features: 40" % ["Clear for profile-0 point preview" if probe.clear else "Rejected by static grid", str(collision.world_cell(probe_start)), str(collision.world_cell(probe_end)), "" if probe.clear else "First blocked cell: %s" % str(probe.blocked_cell)]
	queue_redraw()

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.2).clamp(Vector2(0.15, 0.15), Vector2(2, 2))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.2).clamp(Vector2(0.15, 0.15), Vector2(2, 2))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			probe_start = get_global_mouse_position()
			update_probe()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			probe_end = get_global_mouse_position()
			update_probe()
		camera.offset = -Vector2(140, 80) / camera.zoom
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F: full_map()
			KEY_V: overlay.visible = not overlay.visible
			KEY_G: show_prefabs = not show_prefabs
			KEY_B: show_footprints = not show_footprints
			KEY_O: set_mode((mode + 1) % MODES.size())
	queue_redraw()

func _process(delta: float):
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	camera.position += pan * 650 * delta / camera.zoom.x
	var hover: Vector2i = collision.world_cell(get_global_mouse_position())
	if collision.inside(hover):
		selected_cell = hover
	var c: Dictionary = collision.cell_data(selected_cell)
	var record = collision.data.quadrant_checks[int(c.terrain_record)]
	var names: Array[String] = []
	for index in c.object_indices:
		var object = collision.data.objects[int(index)]
		names.append("%s / %s" % [object.code, object.name])
	inspector.text = "CELL %s / %s\n\nTER: %s / q%d / prefab #%d\nSource cell: %s\nTER byte offset: 0x%x\n\nHeight: %d [source]\nMaterial: %d [source]\nPermission: %d [source]\nReserved: %d [unknown]\n\nProfile-0 terrain: %s\nBuild terrain gate: %s\n\nOccupants:\n%s\n\nMask: 1 = hole; 0 = occupied." % [str(selected_cell), MODES[mode], record.code, int(record.quadrant), int(c.terrain_record), str(c.source_cell), int(c.source_byte_offset), int(c.raw[0]), int(c.raw[1]), int(c.raw[2]), int(c.raw[3]), "admits" if c.profile_passable[0] else "rejects", "passes" if c.terrain_build_gate else "rejects", "None" if names.is_empty() else "\n".join(names)]
	queue_redraw()

func _draw():
	if show_prefabs:
		for r in collision.data.quadrant_checks:
			var index := int(r.index)
			var origin := Vector2(index % 13 * 320, index / 13 * 240)
			draw_rect(Rect2(origin, Vector2(320, 240)), Color(0.7, 0.9, 1, 0.6), false, 1 / camera.zoom.x)
			if camera.zoom.x > 0.4:
				draw_string(ThemeDB.fallback_font, origin + Vector2(6, 18), "%s / q%d / #%d" % [r.code, int(r.quadrant), index], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	if show_footprints:
		for o in collision.data.objects:
			var origin := Vector2(o.origin_cell[0] * 32, o.origin_cell[1] * 24)
			var size := Vector2(o.size[0] * 32, o.size[1] * 24)
			var color := Color("efbd50") if o.kind == "buildings" else Color("cc8df0")
			draw_rect(Rect2(origin, size), color, false, 1 / camera.zoom.x)
			var point := Vector2(o.world_position[0], o.world_position[1])
			draw_line(point - Vector2(6, 0), point + Vector2(6, 0), Color.WHITE, 1 / camera.zoom.x)
			draw_line(point - Vector2(0, 6), point + Vector2(0, 6), Color.WHITE, 1 / camera.zoom.x)
			if camera.zoom.x > 0.4:
				draw_string(ThemeDB.fallback_font, origin - Vector2(0, 5), o.code, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	for start in [Vector2(384, 1536), Vector2(3616, 1536)]:
		draw_circle(start, 15 / camera.zoom.x, Color.WHITE, false, 2 / camera.zoom.x)
	if not probe.is_empty():
		draw_line(probe_start, probe_end, Color.GREEN if probe.clear else Color.RED, 2 / camera.zoom.x)
		if not probe.clear:
			var c: Vector2i = probe.blocked_cell
			draw_rect(Rect2(Vector2(c.x * 32, c.y * 24), Vector2(32, 24)), Color.RED, false, 3 / camera.zoom.x)
	draw_rect(Rect2(Vector2(selected_cell.x * 32, selected_cell.y * 24), Vector2(32, 24)), Color.WHITE, false, 2 / camera.zoom.x)

func self_test():
	var rejects := 0
	var occupied := 0
	for y in range(collision.height):
		for x in range(collision.width):
			var cell := Vector2i(x, y)
			var c: Dictionary = collision.cell_data(cell)
			if not c.profile_passable[0]: rejects += 1
			if not c.object_indices.is_empty(): occupied += 1
			assert(collision.is_passable(cell) == (c.profile_passable[0] and c.object_indices.is_empty()))
	assert(rejects == int(collision.data.summary.terrain_profile0_blocked))
	assert(occupied == int(collision.data.summary.object_occupied_cells))
	assert(not collision.is_passable(Vector2i(-1, 0)))
	assert(not collision.is_passable(Vector2i(128, 0)))
	var original: Dictionary = collision.data
	# Synthetic obstacle grid tests isolate the line probe from map assumptions.
	collision.data = {"cells": []}
	collision.width = 4
	collision.height = 4
	for i in range(16): collision.data.cells.append({"profile_passable": [true], "object_indices": []})
	var clear := collision.trace_segment(Vector2(16, 12), Vector2(112, 84))
	assert(clear.clear)
	collision.data.cells[5].object_indices = [0]
	assert(not collision.trace_segment(Vector2(16, 12), Vector2(112, 84)).clear)
	assert(not collision.trace_segment(Vector2(112, 84), Vector2(16, 12)).clear)
	assert(collision.trace_segment(Vector2(16, 12), Vector2(112, 12)).clear)
	assert(not collision.trace_segment(Vector2(16, 12), Vector2(144, 12)).clear)
	assert(collision.trace_segment(Vector2(16, 12), Vector2(16, 12)).clear)
	collision.data.cells[1].object_indices = [0]
	assert(not collision.trace_segment(Vector2(16, 12), Vector2(48, 36)).clear)
	collision.data = original
	collision.width = 128
	collision.height = 128
	for index in range(MODES.size()):
		set_mode(index)
		assert(overlay.texture.get_size() == Vector2(128, 128))
	print("Collision viewer checks passed: 16384 cells, five overlays, bounds and straight-line probe cases")
	get_tree().quit()

func capture_preview():
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.local/collision_viewer.png")
	get_tree().quit()
