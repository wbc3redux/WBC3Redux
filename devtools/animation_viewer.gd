extends Node2D
## Original sheet inspector: every unit and building sheet the importer writes (assets/art.json, ART_RESEARCH.md).
## The Swordsman stays the default subject; its five sheets are the ones the original viewer self-test checks.
const Assets = preload("res://core/asset_store.gd")

const AnimationData = preload("res://core/animation_data.gd")
const ArtData = preload("res://core/art_data.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const BuildingMarker = preload("res://battle/building_marker.gd")
const Building = preload("res://simulation/building_state.gd")
const ROLE := {0: "idle / standing", 1: "walk", 2: "f (attack)", 3: "d (death)", 4: "a", 5: "z (construction stages, rubble, rest)", 6: "c", 7: "s"}
var subjects: Array = []      # [{code, kind, name}]
var subject := 0
var sheets: Array = []        # sheet records of the current subject, in slot order
var animation := 0
var row := 0
var frame := 0
var playing := false
var loop_preview := false
var preview_fps := 10.0
var derived_timing := true
var walk_speed := 8
var accumulator := 0.0
var zoom := 3.0
var colour := -1              # -1: the sheet's own palette 0 (green team entries)
var status := Label.new()
var details := Label.new()
var subject_choice := OptionButton.new()
var animation_choice := OptionButton.new()
var row_choice := OptionButton.new()
var colour_choice := OptionButton.new()
var play_button := Button.new()
var bounds := true

func _ready():
	var art := ArtData.data()
	for code in ["AHKX"] + art.get("units", {}).keys().filter(func(c): return c != "AHKX"):
		if art.units.has(code): subjects.append({"code": code, "kind": "unit", "name": art.units[code].name})
	for code in art.get("buildings", {}).keys():
		subjects.append({"code": code, "kind": "building", "name": art.buildings[code].name})
	# Milestone 11 (EFFECTS_RESEARCH.md): the decoded RL sheets: missiles, fires, explosions, spawn/item effects, item
	# pictures, and every unit/building icon sheet.
	for code in art.get("effects", {}).keys():
		subjects.append({"code": code, "kind": "effect", "name": art.effects[code].role})
	for code in art.get("icons", {}).keys():
		subjects.append({"code": code, "kind": "icon", "name": "icon sheet (ANI slot 8)"})
	RenderingServer.set_default_clear_color(Color("20252b"))
	var ui := VBoxContainer.new()
	ui.position = Vector2(24, 18)
	add_child(ui)
	var title := Label.new()
	title.text = "ORIGINAL SHEET INSPECTOR — units and buildings"
	title.add_theme_font_size_override("font_size", 24)
	ui.add_child(title)
	var note := Label.new()
	note.text = "ANI geometry and pivots decoded. Facing labels follow artwork. Derived ms/frame come from the executable's sequence builders (static, unmeasured); f timing and action events remain open."
	ui.add_child(note)
	var controls := HBoxContainer.new()
	ui.add_child(controls)
	for s in subjects: subject_choice.add_item("%s %s" % [s.code, s.name])
	subject_choice.item_selected.connect(set_subject)
	controls.add_child(subject_choice)
	animation_choice.item_selected.connect(set_animation)
	controls.add_child(animation_choice)
	row_choice.item_selected.connect(set_row)
	controls.add_child(row_choice)
	add_button(controls, "◀ Frame", func(): step_frame(-1))
	add_button(controls, "Frame ▶", func(): step_frame(1))
	play_button.text = "Play preview"
	play_button.pressed.connect(toggle_play)
	controls.add_child(play_button)
	colour_choice.add_item("Palette 0 (sheet green)")
	for c in ["red", "blue", "green", "purple", "black", "orange", "grey", "yellow"]: colour_choice.add_item("Team colour %d %s" % [colour_choice.item_count - 1, c])
	colour_choice.item_selected.connect(func(index): colour = index - 1; refresh())
	controls.add_child(colour_choice)
	var options := HBoxContainer.new()
	ui.add_child(options)
	var fps_label := Label.new()
	fps_label.text = "Preview FPS (unmeasured): "
	options.add_child(fps_label)
	var fps := SpinBox.new()
	fps.min_value = 1
	fps.max_value = 60
	fps.value = preview_fps
	fps.value_changed.connect(func(value): preview_fps = value; accumulator = 0.0; refresh())
	options.add_child(fps)
	var derived := CheckButton.new()
	derived.text = "Derived original ms/frame"
	derived.button_pressed = derived_timing
	derived.toggled.connect(func(value): derived_timing = value; accumulator = 0.0; refresh())
	options.add_child(derived)
	var speed_label := Label.new()
	speed_label.text = "Walk speed index: "
	options.add_child(speed_label)
	var speed := SpinBox.new()
	speed.min_value = 0
	speed.max_value = 30
	speed.value = walk_speed
	speed.value_changed.connect(func(value): walk_speed = int(value); accumulator = 0.0; refresh())
	options.add_child(speed)
	var loop := CheckButton.new()
	loop.text = "Loop preview (not original policy)"
	loop.toggled.connect(func(value): loop_preview = value)
	options.add_child(loop)
	var box := CheckButton.new()
	box.text = "Frame bounds"
	box.button_pressed = true
	box.toggled.connect(func(value): bounds = value; queue_redraw())
	options.add_child(box)
	add_button(options, "Zoom −", func(): zoom = maxf(1, zoom - 1); queue_redraw())
	add_button(options, "Zoom +", func(): zoom = minf(4, zoom + 1); queue_redraw())
	ui.add_child(status)
	ui.add_child(details)
	var help := Label.new()
	help.text = "← / → step frames · ↑ / ↓ direction · Tab next sheet · PgUp / PgDn subject · Space play/pause · Home first · End last\nPaused on entry. Cyan cross = ANI ground anchor; cyan box = source frame. All eight facings share the same anchor."
	help.position = Vector2(24, 735)
	add_child(help)
	set_subject(0)
	if "--self-test" in OS.get_cmdline_user_args():
		call_deferred("self_test")
	if "--art-self-test" in OS.get_cmdline_user_args():
		call_deferred("art_self_test")
	if "--capture-preview" in OS.get_cmdline_user_args():
		call_deferred("capture_preview")

func add_button(parent: Node, text: String, callback: Callable):
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)

func current() -> Dictionary:
	return subjects[subject] if not subjects.is_empty() else {}

func is_building() -> bool:
	return current().get("kind", "") == "building"

func meta() -> Dictionary:
	return sheets[animation]

func rows() -> int:
	return int(meta().get("rows", 8))

## Frames a sheet is stepped through: the ANI count, except slot 5 of buildings, whose columns are the construction
## stages 0..2 (0x52c250) although the ANI count says 1.
func frame_total(m: Dictionary = {}) -> int:
	if m.is_empty(): m = meta()
	if is_building() and int(m.ani_slot) == 5: return int(m.sheet_columns)
	return int(m.frame_count)

## Effect and icon sheets as viewer records (same fields as the unit/building sheets; no team mask).
func rl_record(entry: Dictionary) -> Dictionary:
	var src: Dictionary = ArtData.data().get("effects" if entry.kind == "effect" else "icons", {}).get(entry.code, {})
	var size: Array = src.verified_sheet_size
	var icon: bool = entry.kind == "icon"
	var frame: Array = [int(size[0]), int(size[1])] if icon else src.frame_size
	var rows_n: int = 1 if icon else int(src.rows)
	var labels: Array = []
	for i in rows_n: labels.append("facing %d" % i if rows_n == 16 else "-")
	return {"texture": src.texture, "frame_size": frame, "pivot": [0, 0] if icon else src.pivot, "offset": [0, 0] if icon else [-int(src.pivot[0]), -int(src.pivot[1])],
		"frame_count": 1 if icon else maxi(int(src.frames), int(src.columns)), "sheet_columns": 1 if icon else int(src.columns), "rows": rows_n,
		"verified_sheet_size": size, "direction_labels": labels, "ani_slot": 8 if icon else 0, "ani_byte_offset": 0xd0 if icon else 0,
		"blend_bytes": src.blend_bytes, "team_pixels": 0, "ani_raw_word_02": 0, "ani_unknown_words": {"0x18": 0}, "interval_ms": int(src.get("interval_ms", 0)), "rl": true,
		"godot_blend": String(src.get("godot_blend", ""))}

## G-2: mode 0x10 sheets (0x48f130 adds the colour to the screen) are written opaque and drawn with additive blending.
static var _additive: CanvasItemMaterial = null
static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive

func sheet_records(entry: Dictionary) -> Array:
	if entry.kind == "effect" or entry.kind == "icon": return [rl_record(entry)]
	var record: Dictionary = ArtData.unit(entry.code) if entry.kind == "unit" else ArtData.building(entry.code)
	var out: Array = []
	var keys: Array = record.get("sheets", {}).keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys: out.append(record.sheets[key])
	return out

func set_subject(index: int):
	subject = posmod(index, maxi(1, subjects.size()))
	subject_choice.select(subject)
	sheets = sheet_records(current())
	animation_choice.clear()
	for m in sheets:
		var role: String = ROLE.get(int(m.ani_slot), "")
		if is_building() and int(m.ani_slot) in [1, 3, 4]: role = "state variant (selection Open)"
		animation_choice.add_item("%s — ANI slot %d %s" % [m.texture.trim_suffix(".png"), int(m.ani_slot), role])
	zoom = 1.0 if is_building() else 3.0
	set_animation(0)

func set_animation(index: int):
	animation = posmod(index, maxi(1, sheets.size()))
	animation_choice.select(animation)
	row_choice.clear()
	for i in range(rows()):
		row_choice.add_item("Row %d / %s" % [i, meta().direction_labels[i]])
	row = mini(row, rows() - 1)
	row_choice.select(row)
	frame = 0
	playing = false
	accumulator = 0.0
	refresh()

# Milliseconds per frame from the sequence builders at Medium game speed (1 game ms = 1 real ms).
# 0 = no frame advance (single-frame idle); -1 = not derivable without match state (slot 2).
func original_frame_ms(index: int) -> float:
	if sheets[index].get("rl", false):
		return float(sheets[index].interval_ms) if current().kind == "effect" and int(sheets[index].frame_count) > 1 else 0.0
	if is_building():
		if int(meta().ani_slot) == 0 and int(meta().frame_count) > 1: return float(ArtData.building(current().code).standing_interval_ms) # 0x53b54d
		return 0.0 # static sheet; slot 5 columns change with construction progress
	match int(sheets[index].ani_slot):
		0: return 0.0 # One ANI frame; 0x5394a0 animates idle only when ANI has more (+0x438).
		1: return float(walk_frame_ms()) # 0x5377a0: table[speed] / walk entries.
		2: return -1.0 # 0x537060: ((max(500,(150-X)*10)*10)/attack rate)/frames; X, rate are match state.
		3: return 100.0 # 0x5374a0: 100 ms frames, last frame held until +30.7 s.
		4: return 100.0 # 0x536b40: 100 ms frames, then frame 0 and back to idle.
	return -1.0

# 0x5377a0: dt = table[speed] / n, n = walk frames * ARM +0xf8 / +0xfa for an orthogonal step (16 for the Swordsman).
func walk_frame_ms() -> int:
	return UnitAgent.STEP_TABLE[clampi(walk_speed, 0, 30)] / ArtData.walk_entries(current().code, false)

func frame_interval() -> float:
	var ms := original_frame_ms(animation) if derived_timing else -1.0
	if ms > 0.0: return ms / 1000.0
	if ms == 0.0 and derived_timing: return INF
	return 1.0 / preview_fps

func timing_source() -> String:
	if not derived_timing: return "preview %.1f ms/frame (unmeasured)" % (1000.0 / preview_fps)
	if meta().get("rl", false):
		if current().kind == "icon": return "icon sheet: 0x487f20 slot 8 regions (portrait, 32x50 x2, 90x90 x2, face)"
		if int(meta().rows) == 16: return "missile: rows = 16 facings (0x5418a0), column 0 head, columns 1..5 trail (0x53f6b0)"
		return "original %d ms/frame (effect class 0x53c870)" % int(meta().interval_ms)
	if is_building():
		var ms := original_frame_ms(animation)
		if ms > 0.0: return "original %d ms/frame (ANI +0x18 or 100), strict deadline" % ms
		return "static sheet (slot 5 column follows construction progress: 0 / 34 / 67 %)" if int(meta().ani_slot) == 5 else "static sheet"
	match int(meta().ani_slot):
		0: return "original: single frame, no advance (turn half-steps use column 1)"
		1: return "original %d ms/frame = table[%d] %d / %d walk entries (Medium)" % [walk_frame_ms(), walk_speed, UnitAgent.STEP_TABLE[clampi(walk_speed, 0, 30)], ArtData.walk_entries(current().code, false)]
		2: return "OPEN: depends on player/attack-rate state; preview %.1f ms/frame" % (1000.0 / preview_fps)
		3: return "original 100 ms/frame, last frame held (sequence ends +30.7 s)"
		4: return "original 100 ms/frame (action role unverified)"
	return "OPEN: role and timing of this slot not traced; preview %.1f ms/frame" % (1000.0 / preview_fps)

func set_row(index: int):
	row = posmod(index, rows())
	row_choice.select(row)
	refresh()

func step_frame(amount: int):
	playing = false
	accumulator = 0.0
	frame = posmod(frame + amount, frame_total())
	refresh()

func toggle_play():
	if not playing and frame == frame_total() - 1:
		frame = 0
	playing = not playing
	accumulator = 0.0
	refresh()

func _input(event: InputEvent):
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_LEFT: step_frame(-1)
		KEY_RIGHT: step_frame(1)
		KEY_UP: set_row(row - 1)
		KEY_DOWN: set_row(row + 1)
		KEY_TAB: set_animation(animation + 1)
		KEY_PAGEUP: set_subject(subject - 1)
		KEY_PAGEDOWN: set_subject(subject + 1)
		KEY_SPACE: toggle_play()
		KEY_HOME: frame = 0; playing = false; refresh()
		KEY_END: frame = frame_total() - 1; playing = false; refresh()
		_: return
	get_viewport().set_input_as_handled()

func _process(delta: float):
	if not playing:
		return
	accumulator += delta
	var interval := frame_interval()
	while accumulator >= interval and playing:
		accumulator -= interval
		if frame + 1 >= frame_total():
			if loop_preview:
				frame = 0
			else:
				playing = false
		else:
			frame += 1
	refresh()

func refresh():
	if sheets.is_empty(): return
	var m := meta()
	material = ArtData.team_material(m, colour) if m.has("team_mask") else additive_material() if m.get("godot_blend", "") == "add" else null
	play_button.text = "Pause" if playing else "Play preview"
	status.text = "%s %s  |  %s  |  Row %d / %s  |  Frame %d of %d (zero-based)  |  %s" % [current().code, current().name, m.texture.trim_suffix(".png"), row, m.direction_labels[row], frame, frame_total(), timing_source()]
	details.text = "ANI +0x%02x  ·  frame %s px  ·  pivot %s  ·  draw offset %s  ·  blend bytes %s\nSheet %s px / %d columns x %d rows (ANI uses %d)  ·  %d team-colour pixels (palette entries 224..238)  ·  %s\nNo uniform ANI FPS: durations come from per-state builders. ANI +02 = %d / +18 = %d (not FPS)." % [int(m.ani_byte_offset), str(m.frame_size), str(m.pivot), str(m.offset), str(m.blend_bytes), str(m.verified_sheet_size), int(m.sheet_columns), rows(), int(m.frame_count), int(m.team_pixels), "palette 0" if colour < 0 else "team colour %d (player colour = player index: decision)" % colour, int(m.ani_raw_word_02), int(m.ani_unknown_words["0x18"])]
	queue_redraw()

func draw_frame(origin: Vector2, scale_factor: float, direction: int, chosen: bool):
	var m := meta()
	var size := Vector2(m.frame_size[0], m.frame_size[1])
	var top_left := origin + AnimationData.sprite_offset(m) * scale_factor
	var destination := Rect2(top_left, size * scale_factor)
	draw_texture_rect_region(ArtData.texture(m.texture), destination, AnimationData.frame_rect(m, direction, frame))
	if bounds:
		draw_rect(destination, Color(0.4, 0.75, 0.8, 0.65), false)
	var color := Color("7ce2d0") if chosen else Color("82949c")
	draw_line(origin - Vector2(7, 0), origin + Vector2(7, 0), color)
	draw_line(origin - Vector2(0, 7), origin + Vector2(0, 7), color)

func _draw():
	if sheets.is_empty():
		return
	if rows() == 1:
		draw_frame(Vector2(640, 520), zoom, 0, true)
		return
	draw_frame(Vector2(625, 490), zoom, row, true)
	for i in range(8):
		var origin := Vector2(90 + i * 154, 675)
		if row == i:
			draw_rect(Rect2(origin - Vector2(73, 102), Vector2(148, 137)), Color(0.2, 0.35, 0.38), false, 2)
		draw_frame(origin, 1.0, i, row == i)
		draw_string(ThemeDB.fallback_font, origin + Vector2(-36, 28), "%d / %s" % [i, meta().direction_labels[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

func self_test():
	var checked := 0
	derived_timing = false
	set_subject(0)
	assert(current().code == "AHKX" and sheets.size() == 5)
	for a in range(sheets.size()):
		set_animation(a)
		var m := meta()
		var sheet_size: Vector2 = ArtData.texture(m.texture).get_size()
		for r in range(8):
			set_row(r)
			for f in range(int(m.frame_count)):
				frame = f
				var rect := AnimationData.frame_rect(m, row, frame)
				if not Rect2(Vector2.ZERO, sheet_size).encloses(rect):
					push_error("Animation rectangle exceeds sheet")
					get_tree().quit(1)
					return
				checked += 1
		frame = 0
		step_frame(-1)
		assert(frame == int(m.frame_count) - 1)
		step_frame(1)
		assert(frame == 0)
		playing = true
		loop_preview = false
		_process((int(m.frame_count) + 1) / preview_fps)
		assert(not playing and frame == int(m.frame_count) - 1)
		frame = 0
		accumulator = 0.0
		loop_preview = true
		playing = true
		_process((int(m.frame_count) + 0.25) / preview_fps)
		assert(frame == 0 and playing)
	for r in range(8):
		var angle := (r - 2) * PI / 4
		assert(AnimationData.direction_from_vector(Vector2.from_angle(angle)) == r)
	print("Animation viewer checks passed: %d ANI frame/direction rectangles; wrap, stop, loop and facing mapping" % checked)
	print("Animation timing checks passed: %d" % timing_self_test())
	get_tree().quit()

func timing_self_test() -> int:
	var checks := 0
	derived_timing = true
	set_subject(0)
	for a in range(8):
		for b in range(8):
			var turn := UnitAgent.turn_sequence(a, b)
			assert(turn.size() == UnitAgent.turn_frames(a, b))
			for entry in turn: assert(entry.y == 0 or entry.y == 1)
			checks += 1
	assert(UnitAgent.turn_sequence(0, 4)[0] == Vector2i(7, 1) and UnitAgent.turn_sequence(4, 0)[0] == Vector2i(4, 1))
	for step in [Vector2i(32, 0), Vector2i(-32, 24), Vector2i(0, -24), Vector2i(-32, -24)]:
		for phase in range(UnitAgent.WALK_FRAMES):
			var offsets := UnitAgent.walk_offsets(step, phase)
			assert(offsets[-1] == step and offsets[0] != Vector2i.ZERO)
			for i in range(1, offsets.size()):
				assert(absi(offsets[i].x) >= absi(offsets[i - 1].x) and absi(offsets[i].y) >= absi(offsets[i - 1].y))
			checks += 1
	assert(UnitAgent.walk_offsets(Vector2i(0, 24), 0, true)[1].y == 3 + 1)
	set_animation(1)
	walk_speed = 8
	playing = true
	_process(0.029 * 5 + 0.001)
	assert(frame == 5)
	checks += 1
	for a in [3, 4]:
		set_animation(a)
		playing = true
		_process(0.1 * 3 + 0.001)
		assert(frame == 3)
		checks += 1
	set_animation(0)
	playing = true
	_process(10.0)
	assert(frame == 0)
	checks += 1
	derived_timing = false
	return checks

## Every imported unit and building sheet: texture and team mask sizes match the record, every frame rectangle of every
## row fits, team materials build, unit_agent picks each unit's own sheet by type, the building presentation follows
## construction stages, fades, upgrades and the recovered position/depth, and the team ramps match 0x494450.
func art_self_test():
	var tally := {"checks": 0} # lambdas capture locals by value; a dictionary is shared
	var failures: Array = []
	var expect := func(condition: bool, text: String):
		tally.checks += 1
		if not condition: failures.append(text)
	var sheet_count := 0
	for s in range(subjects.size()):
		set_subject(s)
		expect.call(not sheets.is_empty(), "%s has sheets" % current().code)
		for a in range(sheets.size()):
			set_animation(a)
			var m := meta()
			sheet_count += 1
			var size: Vector2 = ArtData.texture(m.texture).get_size()
			expect.call(size == Vector2(m.verified_sheet_size[0], m.verified_sheet_size[1]), "%s size" % m.texture)
			if not m.get("rl", false):
				var mask: Texture2D = ArtData.texture(m.team_mask)
				expect.call(mask != null and mask.get_size() == size, "%s team mask size" % m.texture)
				expect.call(ArtData.team_material(m, 0) != null, "%s team material" % m.texture)
				# Milestone 11a: siege engines (ASBA, ASCA) die in one row; every other unit sheet has eight directions,
				# except the temple elementals' (B1-1: every facing drawn from row 0, art.json one_row_facings).
				var one_row: bool = is_building() or int(m.ani_slot) == 6 or (String(m.suffix) == "d" and int(m.rows) == 1) or m.get("one_row_facings", false)
				expect.call(int(m.rows) == (1 if one_row else 8), "%s rows" % m.texture)
			for r in range(rows()):
				for f in range(frame_total()):
					expect.call(Rect2(Vector2.ZERO, size).encloses(ArtData.frame_rect(m, r, f)), "%s r%d f%d inside" % [m.texture, r, f])
			if current().kind == "unit":
				expect.call(ArtData.unit_sheet(current().code, int(m.ani_slot)) == m, "%s picked by type" % m.texture)
		# G-2: about 2 600 sheets; drop the cached textures between subjects so the run stays small (headless keeps images).
		ArtData._textures.clear()
		ArtData._materials.clear()
	coverage_checks(expect)
	# Team ramps (0x494450): colour 0 starts at R 0x28, colour 1 is blue, 15 steps each.
	var red := ArtData.ramp(0)
	var blue := ArtData.ramp(1)
	expect.call(red.size() == 15 and ArtData.ramp(7).size() == 15 and ArtData.ramp(8).is_empty(), "ramp sizes")
	expect.call(red[0].r8 == 41 and red[0].g8 == 0 and blue[14].b8 > blue[14].r8, "ramp values")
	# Walk entries per step (0x5377a0): frames * num / den.
	expect.call(ArtData.walk_entries("AHKX", false) == 16 and ArtData.walk_entries("AMJX", false) == 8 and ArtData.walk_entries("ACCA", true) == 7, "walk entries")
	unit_checks(expect)
	building_checks(expect)
	effect_checks(expect)
	if not failures.is_empty():
		for f in failures.slice(0, 20): push_error("Art check failed: " + f)
		get_tree().quit(1)
		return
	print("Art browser checks passed: %d over %d subjects and %d sheets; unit sheet selection, team colour, building stages and fades" % [tally.checks, subjects.size(), sheet_count])
	get_tree().quit()

## G-2 (ART_RESEARCH.md "G-2"): the browser lists every ARM / BUI code of catalogue.json; every slot an ANI enables is an
## imported sheet or on art.json's reasoned skip list; translucent (mode 0xd), tinted (lighting 2) and additive (0x10)
## sheets arrive as such.
func coverage_checks(expect: Callable):
	var art := ArtData.data()
	var catalogue = Assets.json("catalogue.json")
	var listed := {}
	for s in subjects: listed["%s:%s" % [s.kind, s.code]] = true
	for code in catalogue.units: expect.call(listed.has("unit:" + code), "catalogue unit %s listed" % code)
	for code in catalogue.buildings: expect.call(listed.has("building:" + code), "catalogue building %s listed" % code)
	var skipped := {}
	for entry in art.get("skip_list", []):
		skipped["%s:%d" % [entry.code, int(entry.slot)]] = true
		expect.call(String(entry.get("reason", "")) != "", "%s slot %d skip has a reason" % [entry.code, int(entry.slot)])
	for kind in ["units", "buildings"]:
		for code in art[kind]:
			var record: Dictionary = art[kind][code]
			for slot in record.get("ani_enabled", []):
				var done: bool = record.sheets.has(str(int(slot))) if int(slot) < 8 else art.icons.has(code)
				expect.call(done or skipped.has("%s:%d" % [code, int(slot)]), "%s slot %d imported or skip-listed" % [code, int(slot)])
	for code in art.get("effects_skipped", {}): expect.call(skipped.has("%s:0" % code), "effect %s skip listed" % code)
	for code in art.get("roster_gaps", {}): expect.call(not catalogue.units.has(code) and not catalogue.buildings.has(code), "%s has no record" % code)
	# Translucent: the Shadow's idle sheet carries the 50 % band (mode 0xd); the Elf hero's 'a' sheet the lighting-2 tint.
	var shadow: Image = ArtData.texture(ArtData.unit_sheet("AUXX", 0).texture).get_image()
	var half := 0
	for y in range(0, shadow.get_height(), 2):
		for x in range(0, shadow.get_width(), 2):
			if absf(shadow.get_pixel(x, y).a - 128.0 / 255.0) < 0.01: half += 1
	expect.call(half > 100, "Shadow (AUXX) has half-transparent pixels (%d)" % half)
	expect.call(not ArtData.unit_sheet("AEHX", 4).is_empty(), "AEHX attack 'a' (modes 1, 2) imported")
	var additive: Array = art.effects.keys().filter(func(c): return art.effects[c].get("godot_blend", "") == "add")
	expect.call(additive.has("EPF0") and additive.has("EPF1"), "mode 0x10 effects drawn additively (%s)" % str(additive))
	for i in subjects.size():
		if subjects[i].code == "EPF1" and subjects[i].kind == "effect":
			set_subject(i)
			expect.call(material is CanvasItemMaterial and material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "EPF1 additive material")
	for code in art.get("shoot_codes", {}):
		var shot: Dictionary = art.shoot_codes[code]
		expect.call(bool(shot.imported) or String(shot.get("reason", "")) != "", "shoot code %s imported or explained" % code)

func unit_checks(expect: Callable):
	for code in ["AHBX", "AHMX", "AHHX", "AMJX", "ACCA", "ACTU", "AHKX"]:
		var unit = UnitAgent.new()
		unit.type_id = code
		unit.owner_id = 1
		add_child(unit)
		expect.call(unit.art_type == code and unit.modulate == Color.WHITE, "%s uses its own art" % code)
		expect.call(unit.sprite.texture == ArtData.texture(ArtData.unit_sheet(code, 0).texture), "%s stands on its idle sheet" % code)
		expect.call(unit.sprite.material == ArtData.team_material(ArtData.unit_sheet(code, 0), 1), "%s in colour 1" % code)
		# Death index counted by the combat controller in its own frame count: the unit's last d frame is held.
		var death := ArtData.unit_sheet(code, 3)
		unit.anim = {"sheet": "AHKXd.RLE", "row": 2, "frame": 12, "slot": 3, "index": int(death.frame_count) - 1, "frames": int(death.frame_count)}
		unit.update_sprite()
		expect.call(unit.sprite.region_rect == ArtData.frame_rect(death, 2, int(death.frame_count) - 1), "%s corpse frame" % code)
		var attack := ArtData.unit_sheet(code, 2)
		unit.anim = {"sheet": "AHKXf.RLE", "row": 0, "frame": 0, "slot": 2, "index": 16, "frames": 16}
		unit.update_sprite()
		var expected: Dictionary = attack if not attack.is_empty() else ArtData.unit_sheet(code, 0)
		expect.call(unit.sprite.texture == ArtData.texture(expected.texture) and unit.sprite.region_rect.position.x == 0, "%s last f entry shows frame 0" % code)
		unit.anim = {}
		unit.queue_free()
	var stranger = UnitAgent.new()
	stranger.type_id = "AZZZ" # a type without art (G-2 imports every catalogue unit): Swordsman placeholder, tagged
	add_child(stranger)
	expect.call(stranger.art_type == "AHKX", "unimported type falls back to the Swordsman")
	stranger.queue_free()

func building_checks(expect: Callable):
	var definition := {"footprint": ArtData.building("BKK0").footprint, "mask_rows": [0, 0, 0, 0, 0, 0, 0, 0], "display_name": "Keep"}
	var state = Building.new(99, "BKK0", 1, Vector2.ZERO, definition, 10, 20)
	state.constructing = true
	state.progress = 1
	var marker = BuildingMarker.new()
	marker.configure(state)
	add_child(marker)
	expect.call(marker.position == Vector2((10 + 4) * 32 + 16, 20 * 24 + 12), "building anchor position (0x5350a0)")
	expect.call(marker.z_index == 20 * 24 + 12 + 84, "building depth key (0x53ab30)")
	expect.call(marker.shown == Vector2i(5, 0) and marker.fade_level == 15 and marker.fade_step == -1, "placed: z column 0 fades in")
	for i in 16: marker._process(0.016)
	expect.call(marker.fade_level == -1 and marker.base.visible and not marker.overlay.visible, "fade ends after 16 draws")
	state.progress = 34
	marker._process(0.016)
	expect.call(marker.shown == Vector2i(5, 1) and marker.fade_base == Vector2i(5, 0) and marker.fade_over == Vector2i(5, 1), "34 %: column 1 fades in")
	state.progress = 67
	marker._process(0.016)
	expect.call(marker.shown == Vector2i(5, 2), "67 %: column 2")
	expect.call(marker.base.material == ArtData.team_material(ArtData.building_sheet("BKK0", 5), 1), "owner colour on the scaffold")
	state.constructing = false
	state.progress = 100
	marker._process(0.016)
	expect.call(marker.shown == Vector2i(0, 0) and marker.fade_base == Vector2i(0, 0) and marker.fade_over == Vector2i(5, 2) and marker.fade_step == 1, "completion: column 2 fades out over the standing sheet")
	for i in 16: marker._process(0.016)
	expect.call(marker.base.texture == ArtData.texture(ArtData.building_sheet("BKK0", 0).texture) and not marker.overlay.visible, "finished Keep standing sheet")
	state.original_type_id = "BKK1"
	marker._process(0.016)
	expect.call(marker.base.texture == ArtData.texture(ArtData.building_sheet("BKK1", 0).texture) and marker.fade_level == -1, "upgrade swaps to BKK1 without a fade")
	state.owner = 0
	marker._process(0.016)
	marker.refresh_sprites()
	expect.call(marker.base.material == ArtData.team_material(ArtData.building_sheet("BKK1", 0), 0), "owner change recolours")
	marker.queue_free()

## --capture-preview [--subject=CODE] [--sheet=N] [--frame=N] [--colour=N]: saves .local/animation_viewer.png.
func capture_preview():
	var options := {"subject": "AHKX", "sheet": "1", "frame": "5", "colour": "-1"}
	for arg in OS.get_cmdline_user_args():
		for key in options:
			if arg.begins_with("--%s=" % key): options[key] = arg.get_slice("=", 1)
	for i in subjects.size():
		if subjects[i].code == options.subject: set_subject(i)
	set_animation(int(options.sheet))
	if rows() > 3: set_row(3)
	frame = clampi(int(options.frame), 0, frame_total() - 1)
	colour = int(options.colour)
	refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.local/animation_viewer.png")
	get_tree().quit()

## RL sheets (EFFECTS_RESEARCH.md section 1): geometry from ANI, the translucency band as alpha (mode 0xf), the arrow's
## shadow band as dark alpha (mode 1), icon regions inside their sheets, the production icon size.
func effect_checks(expect: Callable):
	var fx: Dictionary = ArtData.data().get("effects", {})
	for code in ["EMA0", "EMM0", "EF01", "EF02", "EF03", "EX01", "EX02", "EZ08", "EZ55", "IDLG"]:
		expect.call(fx.has(code), "effect %s imported" % code)
	expect.call(int(fx.EMA0.verified_sheet_size[0]) == 120 and int(fx.EMA0.verified_sheet_size[1]) == 320 and int(fx.EMA0.rows) == 16 and int(fx.EMA0.columns) == 6, "arrow sheet: 16 facings x (head + 5 trail)")
	expect.call(int(fx.EF01.blend_bytes[0]) == 15 and int(fx.EF01.blend_bytes[1]) == 15 and int(fx.EF01.frames) == 16 and int(fx.EX02.interval_ms) == 120 and int(fx.EF01.interval_ms) == 50, "fire / explosion timing and modes")
	var fire: Image = ArtData.texture(fx.EF01.texture).get_image()
	var translucent := 0
	var opaque := 0
	for y in range(0, fire.get_height(), 2):
		for x in range(0, 104, 2):
			var a := fire.get_pixel(x, y).a
			if a > 0.0 and a < 0.99: translucent += 1
			elif a >= 0.99: opaque += 1
	expect.call(translucent > 50 and opaque > 50, "fire frame has translucent (0xef..0xfe) and opaque pixels (%d / %d)" % [translucent, opaque])
	var arrow: Image = ArtData.texture(fx.EMA0.texture).get_image()
	var dark := 0
	for y in arrow.get_height():
		for x in arrow.get_width():
			var c := arrow.get_pixel(x, y)
			if c.a > 0.0 and c.a < 0.99 and c.r < 0.02 and c.g < 0.02 and c.b < 0.02: dark += 1
	expect.call(dark > 0, "arrow shadow band drawn as dark alpha (mode 1, Shadows option on)")
	for code in ArtData.data().get("icons", {}):
		var record: Dictionary = ArtData.data().icons[code]
		var size: Vector2 = ArtData.texture(record.texture).get_size()
		for key in record.regions:
			var r: Array = record.regions[key]
			expect.call(Rect2(Vector2.ZERO, size).encloses(Rect2(int(r[0]), int(r[1]), int(r[2]), int(r[3]))), "%s icon region %s inside" % [code, key])
	var button_icon: AtlasTexture = ArtData.icon("AHMX", 1)
	expect.call(button_icon != null and button_icon.region.size == Vector2(32, 50), "production icon 32 x 50")
	expect.call(ArtData.icon("BKK1", 3) != null and ArtData.icon("BKK1", 3).region.size == Vector2(90, 90), "building portrait 90 x 90")
	expect.call(ArtData.item_icon(0, 0) != null and ArtData.skill_icon(Rect2i(319, 108, 12, 12)) != null, "item and skill atlases")
