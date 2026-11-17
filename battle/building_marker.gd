extends Node2D
## Presentation of a building created by the production/combat simulation, drawn with its original sheets
## (assets/art.json, ART_RESEARCH.md). Building draw 0x53ae40 (vtable 0x5eaee0 +0x14), Read:
## * Position: anchor cell * (32, 24) + (16, 12) (0x5350a0); the sheet is drawn at that point minus the ANI pivot.
## * Sheet: ANI slot 0 standing; while under construction slot 5 ('z') column 0, then 1 from 34 % and 2 from 67 %
##   (0x52c250); completion returns to slot 0 (0x52bfd0). Each change cross-fades over 16 draw steps (0x53c130).
## * Colour: the owner's 15-step ramp over palette entries 224..238 (0x487f20), via team_colour.gdshader.
## * Depth: pixel Y + ((height * 24 - 24) >> 1), 1 when zero (0x53ab30), the key milestone 5 sorts by.
## * A destroyed building is removed at once (0x52b3e0 -> 0x52f980: state 8, 0x534220; playtest 2026-11-11, Read); only a
##   treasure tower leaves slot 5 column 0 as rubble for 120 s (building_rubble.gd). The ESMR smoke 0x52b3e0 places over
##   an ordinary building's footprint is effects_layer.gd / particle_bursts.gd (P-1); so are the damage fires EF01..EF03
##   and the explosions EX01 / EX02 (milestone 11).
## * P-2 (Read, disassembly 0x53b2b7..0x53b2d9): under fog (0x47f6a0 on and the sprite cell +0x48 / +0x4a not visible to
##   the local player, 0x47f560) the sheet is drawn with palette 6 of its eight: the grey of palette 0 (checked on every
##   sheet's palettes), drawn by team_colour.gdshader from the imported sheet; main.gd sets `fogged`.

const ArtData = preload("res://core/art_data.gd")
const FADE_STEPS := 16
const UnitAgentScript = preload("res://battle/unit_agent.gd")
static var harness := true      # false in normal play (parity pass 1): the harness text and rally line are fixture look

var building: RefCounted
## main.gd also writes this directly (building placed, click selection), so a change always redraws the ring layer: a
## deselected building whose layer was not redrawn kept its last ring and strip on screen (hand test F3).
var selected := false:
	set(value):
		if value == selected: return
		selected = value
		ring_layer.queue_redraw()
		queue_redraw()
var marked := false             # +0x14a: a target of the local player's running conversion (main.gd)
var ring_layer := UnitAgentScript.MarkerLayer.new()
var base := Sprite2D.new()     # sheet drawn normally (the cross-fade's +0x170/+0x168 sheet)
var overlay := Sprite2D.new()  # sheet faded in or out (+0x174/+0x16c)
var shown := Vector2i(0, 0)    # (ANI slot, column) of the normal draw: +0x38 / +0x3c
var shown_type := ""
var fade_level := -1           # +0x162 (-1: no cross-fade, +0x164 clear)
var fade_step := 0             # +0x166
var fade_base := Vector2i(-1, 0)
var fade_over := Vector2i(-1, 0)
var clock_ms := 0.0
var deadline_ms := 0.0
var frame := 0
var fogged := false            # P-2: palette 6 (the sprite cell not visible, fog on)

## P-2: the sprite cell of 0x53b2c0 (+0x48 / +0x4a): the anchor cell the pixel position comes from (0x5350a0).
func sprite_cell() -> Vector2i:
	return Vector2i(int(position.x) / 32, int(position.y) / 24)

func set_fogged(on: bool):
	if on == fogged: return
	fogged = on
	refresh_sprites()

func configure(state: RefCounted):
	building = state
	var width: int = state.definition.footprint[0]
	var height: int = state.definition.footprint[1]
	position = Vector2((state.left + ((width - 1) >> 1)) * 32 + 16, state.top * 24 + 12)
	z_index = preload("res://core/map_data.gd").depth(position.y) + (((height * 24 - 24) >> 1) if height > 1 else 1)
	ring_layer.painter = paint_marker
	add_child(ring_layer)                # first child: under the sheets
	for sprite in [base, overlay]:
		sprite.centered = false
		sprite.region_enabled = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.show_behind_parent = true # selection and harness text draw over the sheet
		add_child(sprite)
	shown_type = state.original_type_id
	shown = target()
	if state.constructing: start_fade(Vector2i(-1, 0), shown, FADE_STEPS - 1, -1) # 0x4a6f80: the scaffold fades in
	reset_standing()
	refresh_sprites()

func sheet(slot: int) -> Dictionary:
	return ArtData.building_sheet(building.original_type_id, slot)

func construction_stage() -> int:
	var stage := 0
	for i in range(3):
		if building.progress >= int(ArtData.data().get("construction", {}).get("stage_percent", [0, 34, 67])[i]): stage = i
	return stage

func target() -> Vector2i:
	if building.constructing and not sheet(5).is_empty(): return Vector2i(5, construction_stage())
	return Vector2i(0, frame)

func start_fade(from: Vector2i, to: Vector2i, level: int, step: int):
	fade_base = from
	fade_over = to
	fade_level = level
	fade_step = step

# Multi-frame standing sheets advance on a strict deadline (ANI slot 0 +0x18 or 100 ms), as map_object.gd does.
func reset_standing():
	frame = 0
	clock_ms = 0.0
	deadline_ms = float(ArtData.building(building.original_type_id).get("standing_interval_ms", 100))

func _process(delta: float):
	if building == null: return
	var changed := false
	if building.original_type_id != shown_type:
		shown_type = building.original_type_id # Keep upgrade: 0x53ab80 re-initialises the sheet, no cross-fade
		reset_standing()
		fade_level = -1
		changed = true
	var standing := sheet(0)
	if not building.constructing and not standing.is_empty() and int(standing.frame_count) > 1:
		clock_ms += delta * 1000.0
		if clock_ms > deadline_ms:
			frame = (frame + 1) % int(standing.frame_count)
			deadline_ms = clock_ms + float(ArtData.building(building.original_type_id).get("standing_interval_ms", 100))
			changed = true
	var wanted := target()
	if wanted != shown:
		if wanted.x == 5 and shown.x == 5:
			start_fade(shown, wanted, FADE_STEPS - 1, -1) # 0x52c40e / 0x52c440: the next stage fades in over the last
		elif wanted.x == 0 and shown.x == 5:
			start_fade(Vector2i(0, 0), shown, 0, 1)        # 0x52bfd0: the last stage fades out over the finished sheet
		shown = wanted
		changed = true
	if fade_level >= 0:
		# 0x53ae49: the level moves one step per draw; the fade ends at 0 (fading in) or 15 (fading out).
		fade_level += fade_step
		if (fade_level <= 0 and fade_step < 0) or (fade_level >= FADE_STEPS - 1 and fade_step > 0): fade_level = -1
		changed = true
	if changed: refresh_sprites()

func place(sprite: Sprite2D, at: Vector2i, alpha: float):
	var record := sheet(at.x) if at.x >= 0 else {}
	sprite.visible = not record.is_empty()
	if record.is_empty(): return
	sprite.texture = ArtData.texture(record.texture)
	sprite.region_rect = ArtData.frame_rect(record, 0, clampi(at.y, 0, int(record.sheet_columns) - 1))
	sprite.offset = ArtData.offset(record)
	sprite.material = ArtData.team_material(record, ArtData.player_colour(building.owner), fogged)
	sprite.modulate.a = alpha

func refresh_sprites():
	if fade_level >= 0:
		place(base, fade_base, 1.0)
		# HYPOTHESIS: the renderer's blend level (16 + level, mode 0xb) is drawn as opacity (16 - level) / 16.
		place(overlay, fade_over, float(FADE_STEPS - fade_level) / FADE_STEPS)
	else:
		place(base, shown, 1.0)
		overlay.visible = false
	queue_redraw()

# 0x52b3e0: a destroyed treasure tower turns into slot 5 column 0 (owner 6) for 120 s. The production/combat code frees this
# node when the building dies; the rubble is a separate node (presentation only) that also goes when the scene's
# production world is replaced (fixture reset).
func _exit_tree():
	if building == null or building.hit_points > 0 or sheet(5).is_empty() or get_parent() == null: return
	if not preload("res://battle/building_rubble.gd").leaves_rubble(String(building.original_type_id)): return
	var rubble = preload("res://battle/building_rubble.gd").new()
	rubble.setup(self, sheet(5), get_parent().get("production"))
	add_rubble.call_deferred(get_parent(), rubble)

## The marker also leaves the tree when the whole match scene is freed: then the parent is gone (or leaving) by the time
## the deferred call runs, and the rubble is freed instead of left as a stray node.
static func add_rubble(parent, rubble: Node):
	if is_instance_valid(parent) and parent.is_inside_tree() and not parent.is_queued_for_deletion(): parent.add_child(rubble)
	else: rubble.free()

## Parity pass 4: the original's ring and strip (unit_agent.gd draw_building_marker, 0x53b014), in normal play only.
func paint_marker(layer: CanvasItem):
	if building == null or harness or not (selected or marked): return
	UnitAgentScript.draw_building_marker(layer, sheet(maxi(shown.x, 0)), int(building.owner) == UnitAgentScript.local_player,
		int(building.hit_points), int(building.max_hit_points), marked)

## Called every frame by main.gd (the strip follows the hit points).
func set_marker(is_selected: bool, is_marked: bool):
	var changed := is_selected != selected or is_marked != marked
	selected = is_selected
	marked = is_marked
	if changed or selected or marked: ring_layer.queue_redraw()
	if changed: queue_redraw()

func _draw():
	if building == null or not (selected or marked): return
	var width: int = building.definition.footprint[0]
	var height: int = building.definition.footprint[1]
	var corner := Vector2(building.left * 32, building.top * 24) - position
	var box := Rect2(corner, Vector2(width * 32, height * 24))
	if not harness: return              # the ring layer draws the original's marker
	if not selected: return
	draw_rect(box, Color("ffe08a"), false, 2.0)
	if building.hit_points < building.max_hit_points and building.max_hit_points > 0:
		draw_rect(Rect2(corner + Vector2(6, height * 24 - 12), Vector2(width * 32 - 12, 6)), Color(0.1, 0.1, 0.1, 0.85))
		draw_rect(Rect2(corner + Vector2(7, height * 24 - 11), Vector2((width * 32 - 14) * float(building.hit_points) / building.max_hit_points, 4)), Color("d9534f"))
	# Harness text (not original): type, construction or production state.
	var font := ThemeDB.fallback_font
	var title := "%s %s" % [building.definition.get("display_name", building.original_type_id), building.original_type_id]
	draw_string(font, corner + Vector2(6, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	if building.constructing:
		var who := "builder inside" if building.builder_id >= 0 else "ABANDONED - decaying"
		draw_string(font, corner + Vector2(6, 38), "building %d%% · hp %d/%d · %s" % [building.progress, building.hit_points, building.max_hit_points, who], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	elif building.has_job():
		var text := "pending (cannot pay)" if building.job_pending else "%s %d%%" % [building.job_item, building.job_progress]
		if building.population_blocked: text += " · WAITING: command limit"
		draw_string(font, corner + Vector2(6, 38), "%s · queue %d" % [text, building.queue.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if building.rally.x >= 0:
		var rally := Vector2(building.rally.x * 32 + 16, building.rally.y * 24 + 12) - position
		draw_line(corner + Vector2(width * 16, height * 12), rally, Color(0.4, 1, 0.5, 0.7), 1.5)
		draw_circle(rally, 6, Color(0.4, 1, 0.5, 0.9), false, 2.0)
