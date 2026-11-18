extends Node2D
## A building or feature placed by the scenario (milestone 5), drawn from its original standing sheet at the source
## position minus the ANI pivot. Buildings carry their owner's colour (BLDH +0x64 in map.json; 0x487f20 recolours palette
## entries 224..238) and, once the encounter code owns them, follow its state (ART_RESEARCH.md):
## * destroyed: a treasure tower shows slot 5 column 0 as rubble for 120 s (0x52b3e0); every other building is gone at
##   once (0x52f980 path, playtest 2026-11-11, Read), as is a type without slot 5 (Gnoll Lair);
## * Mausoleum resting after a quest: slot 5 (0x52f7c0 -> 0x53b810).
const Assets = preload("res://core/asset_store.gd")
const ArtData = preload("res://core/art_data.gd")
const RUBBLE_MS := 120000.0

var definition: Dictionary
var frame := 0
var clock_ms := 0.0
var deadline_ms := 0.0
var sheet: Texture2D
var code := ""
var map_code := ""       # the scenario record's code (code changes when the encounter code retypes the placement)
var is_building := false
var owner_player := 6
var state := "standing" # standing | resting | rubble | gone
var rubble_left_ms := 0.0
var link_id := -1        # production building id of this placement while the encounter code owns it
var link_building: RefCounted
var link_world: Object   # the Encounters instance that made the link
# Parity pass 4: selection ring / conversion target mark of the linked building (unit_agent.gd draw_building_marker,
# 0x53b014), drawn under the sheet. main.gd calls set_marker every frame.
var selected := false
var marked := false
var ring_layer = null     # unit_agent.gd MarkerLayer, made on first use

var marker_entity = null  # a mine's entity (mines are not production buildings), else the linked building

func set_marker(is_selected: bool, is_marked: bool, entity = null):
	marker_entity = entity
	if ring_layer == null and (is_selected or is_marked):
		ring_layer = preload("res://battle/unit_agent.gd").MarkerLayer.new()
		ring_layer.painter = paint_marker
		add_child(ring_layer)
	var changed := is_selected != selected or is_marked != marked
	selected = is_selected
	marked = is_marked
	if ring_layer != null and (changed or selected or marked): ring_layer.queue_redraw()

func paint_marker(layer: CanvasItem):
	var b = marker_entity if marker_entity != null else link_building
	if not (selected or marked) or b == null or state == "rubble" or state == "gone": return
	var life: int = int(b.get("hit_points")) if b.get("hit_points") != null else 0
	var maximum: int = int(b.get("max_hit_points")) if b.get("max_hit_points") != null else 0
	preload("res://battle/unit_agent.gd").draw_building_marker(layer, ArtData.building_sheet(code, 5 if state == "resting" else 0),
		int(b.owner) == preload("res://battle/unit_agent.gd").local_player, life, maximum, marked)

func configure(placement: Dictionary, data: Dictionary):
	definition = data
	code = placement.code
	map_code = code
	is_building = placement.kind == "buildings"
	position = Vector2(placement.world_position[0], placement.world_position[1])
	sheet = Assets.texture(data.texture)
	deadline_ms = data.first_interval_ms
	z_index = preload("res://core/map_data.gd").depth(position.y) + int(data.depth_offset)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_meta("source_offset", placement.source_offset)
	if is_building: owner_player = ArtData.map_owner(int(placement.source_offset))
	apply_material()

## Parity pass 3: the encounter code created this placement as another type (0x4a50f0: a tower takes its owner's race).
## The original draws the building of the new type at the same pixel, so the placement switches to that type's sheet
## (art.json slot 0) with its pivot, depth and standing interval.
func retype(new_code: String) -> bool:
	var record := ArtData.building_sheet(new_code, 0)
	if record.is_empty(): return false
	var info := ArtData.building(new_code)
	code = new_code
	definition = definition.duplicate()
	definition.merge({"texture": record.texture, "frame_size": record.frame_size, "pivot": record.pivot,
		"frames": int(record.get("sheet_columns", record.frame_count)), "interval_ms": int(info.get("standing_interval_ms", 100)),
		"depth_offset": int(info.get("depth_offset", definition.depth_offset))}, true)
	sheet = ArtData.texture(record.texture)
	frame = 0
	z_index = preload("res://core/map_data.gd").depth(position.y) + int(definition.depth_offset)
	apply_material()
	queue_redraw()
	return true

var applied_colour := -1   # the colour the material was built for (slot colours change when a skirmish starts)
var fogged := false        # P-2: a scenario building drawn with palette 6 (its sprite cell not visible, 0x53b2b7)

func set_fogged(on: bool):
	if on == fogged or not is_building: return
	fogged = on
	apply_material()

func apply_material():
	if not is_building:
		material = ArtData.plain_material()   # enhanced visuals' soft shadows; null (original) while they are off
		return
	var slot := 5 if state == "resting" or state == "rubble" else 0
	var colour := ArtData.player_colour(ArtData.NEUTRAL if state == "rubble" else owner_player)
	applied_colour = colour
	material = ArtData.team_material(ArtData.building_sheet(code, slot), colour, fogged)

func set_state(value: String):
	if value == state: return
	state = value
	if state == "rubble": rubble_left_ms = RUBBLE_MS
	if state == "rubble" and (ArtData.building_sheet(code, 5).is_empty() or not preload("res://battle/building_rubble.gd").leaves_rubble(code)): state = "gone"
	apply_material()
	queue_redraw()

## A feature whose advance() only counts its clock: not a building (no rubble, no retype) and a single frame. main.gd
## steps the others and keeps one shared clock for these (P-4).
func is_still() -> bool:
	return not is_building and int(definition.frames) <= 1

func advance(delta: float):
	clock_ms += delta * 1000.0
	if state == "rubble":
		rubble_left_ms -= delta * 1000.0
		if rubble_left_ms <= 0.0: set_state("gone")
	# Original object updates advance once, with a strict deadline; no catch-up loop.
	if state == "standing" and int(definition.frames) > 1 and clock_ms > deadline_ms:
		frame = (frame + 1) % int(definition.frames)
		deadline_ms = clock_ms + float(definition.interval_ms)
		queue_redraw()

## Links the scenario placements to the buildings the encounter code adopted (Encounters.static_cells) and mirrors their
## owner, death and Mausoleum rest. Without encounters (or after a fixture reset) every placement is intact again.
## Performance (P-4): `lists` (main.gd object_index: {"by_offset", "buildings"}, built once per map) saves building the
## offset table and walking every feature each step; without it both are made here as before.
static func sync_states(objects: Array, production, encounters, lists = null):
	var by_offset: Dictionary = lists.by_offset if lists != null else {}
	if lists == null:
		for object in objects: by_offset[int(object.get_meta("source_offset"))] = object
	if encounters != null and production != null:
		for id in encounters.static_cells:
			var index: int = int(encounters.static_cells[id].object)
			var object = by_offset.get(int(encounters.collision.data.objects[index].source_offset))
			if object != null and (object.link_id != id or object.link_world != encounters):
				object.link_id = id
				object.link_building = production.building(id)
				object.link_world = encounters
				object.set_state("standing")
	for object in (lists.buildings if lists != null else objects):
		if not object.is_building: continue
		if object.link_id < 0: continue
		if encounters == null or object.link_world != encounters or production == null:
			object.link_id = -1
			object.link_building = null
			object.link_world = null
			if object.code != object.map_code: object.retype(object.map_code)
			object.owner_player = ArtData.map_owner(int(object.get_meta("source_offset")))
			object.set_state("standing")
			object.apply_material()
			continue
		var b = production.building(object.link_id)
		if b == null or b != object.link_building or b.hit_points <= 0:
			if object.state == "standing" or object.state == "resting": object.set_state("rubble")
			continue
		if String(b.original_type_id) != object.code: object.retype(String(b.original_type_id))
		if int(b.owner) != object.owner_player or (object.state != "rubble" and object.applied_colour != ArtData.player_colour(int(b.owner))):
			object.owner_player = int(b.owner)
			object.apply_material()
		var giver = encounters.givers.get(object.link_id)
		object.set_state("resting" if giver != null and giver.resting else "standing")

func _draw():
	if sheet == null or state == "gone": return
	if state == "resting" or state == "rubble":
		var record := ArtData.building_sheet(code, 5)
		if record.is_empty(): return
		draw_texture_rect_region(ArtData.texture(record.texture), Rect2(ArtData.offset(record), Vector2(record.frame_size[0], record.frame_size[1])),
			ArtData.frame_rect(record, 0, 0))
		return
	var size := Vector2(definition.frame_size[0], definition.frame_size[1])
	var pivot := Vector2(definition.pivot[0], definition.pivot[1])
	draw_texture_rect_region(sheet, Rect2(-pivot, size), Rect2(Vector2(frame * size.x, 0), size))

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: a scenario placement's look (code after a retype, owner colour, rubble, animation clock) and its link to
## the adopted building (by id; the link is made again with the restored production building).
const _SAVE_SKIP := ["definition", "sheet", "link_building", "link_world", "ring_layer", "marker_entity", "selected", "marked", "applied_colour"]

func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self, _SAVE_SKIP)

func load_state(state: Dictionary, production, encounters):
	if String(state.get("code", code)) != code: retype(String(state.code))
	preload("res://simulation/save_game.gd").restore(self, state, _SAVE_SKIP)
	link_building = production.building(link_id) if link_id >= 0 and production != null else null
	link_world = encounters if link_id >= 0 else null
	apply_material()
	queue_redraw()
