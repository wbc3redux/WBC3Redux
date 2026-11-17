extends Sprite2D
## Rubble of a destroyed treasure tower (0x52b3e0: slot 5 column 0, owner 6, deadline 120 s). Presentation only.
## Playtest 2026-11-11 (Read): only 0x52fc50's treasure towers (and buildings holding resources, 0x52b050) take this path;
## an ordinary building is removed at once (state 8, 0x534220) and leaves no rubble, see building_marker.gd.
## P-1: with 80 s left the scaffold shows column 1, with 40 s left column 2 (0x52cc8a's countdown, Read). Not ported: the
## restore at the deadline (the tower standing again at full hit points) is a simulation rule; here the rubble goes.
const ArtData = preload("res://core/art_data.gd")
const RUBBLE_MS := 120000.0
const TREASURE_TOWERS := ["BTCE", "BTIN", "BTDR", "BTEL"]   # 0x52fc50

## Whether a destroyed building of this type leaves rubble (0x52b3e0 -> 0x52f980 false).
static func leaves_rubble(type_id: String) -> bool:
	return TREASURE_TOWERS.has(type_id)

var left_ms := RUBBLE_MS
var sheet_record: Dictionary

## The scaffold column for the time left (P-1): 0 above 80 s, 1 above 40 s, else 2.
static func column_for(left: float) -> int:
	return 0 if left > 80000.0 else (1 if left > 40000.0 else 2)
var world # the scene's production world when the building died; a fixture reset replaces it and the rubble goes

func setup(marker: Node2D, record: Dictionary, production_world):
	sheet_record = record
	world = production_world
	position = marker.position
	z_index = marker.z_index
	centered = false
	region_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = ArtData.texture(record.texture)
	region_rect = ArtData.frame_rect(record, 0, int(ArtData.data().get("construction", {}).get("rubble_column", 0)))
	offset = ArtData.offset(record)
	material = ArtData.team_material(record, ArtData.player_colour(ArtData.NEUTRAL))

func _process(delta: float):
	left_ms -= delta * 1000.0
	var column := column_for(left_ms)
	if column > 0 and column < int(sheet_record.get("sheet_columns", 1)): region_rect = ArtData.frame_rect(sheet_record, 0, column)
	if left_ms <= 0.0 or (get_parent() != null and get_parent().get("production") != world): queue_free()
