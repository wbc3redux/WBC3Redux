extends RefCounted
## Scene-independent identity/state adapter. IDs are supplied by match initialization.
## position uses the existing original world coordinates (32 x 24 per cell).

signal ownership_changed(entity_id: int, previous_owner: int, owner: int)
signal workers_changed(entity_id: int, worker_count: int)

var entity_id: int
var original_type_id: String
var position: Vector2
var mine_level: int
var owner: int:
	set(value):
		if owner == value: return
		var previous := owner
		owner = value
		ownership_changed.emit(entity_id, previous, value)
var worker_count: int:
	set(value):
		assert(value >= 0 and value <= 8)
		if worker_count == value: return
		worker_count = value
		workers_changed.emit(entity_id, value)

func _init(id: int, type_id: String, player: int, world_position: Vector2,
		level: int = 0, workers: int = 0):
	entity_id = id
	original_type_id = type_id
	position = world_position
	owner = player
	mine_level = level
	worker_count = workers

func cell() -> Vector2i:
	return Vector2i(floori(position.x / 32.0), floori(position.y / 24.0))

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). A shared object: saved once through SaveGame.Refs, made again with "@ctor".
func save_state(_refs = null) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self)
	s["@ctor"] = [entity_id, original_type_id, owner, position, mine_level, worker_count]
	return s

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state)
