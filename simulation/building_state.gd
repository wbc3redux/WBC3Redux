extends "res://simulation/entity_state.gd"
## One building's construction and production state. Field names follow the original building object
## (offsets in comments, PRODUCTION_RESEARCH.md); times are absolute game milliseconds.
## `position` is the footprint's top-left cell in world units; `left`/`top` are the stamp rows.

signal construction_changed(entity_id: int)
signal production_changed(entity_id: int)

var left: int # leftmost footprint column
var top: int # anchor (top) row; the stamp runs downward from here
var constructing := false # +0xcc
var builder_id := -1 # +0xd4 (one builder at a time)
var builder_cell := Vector2i(-1, -1) # where the hidden builder re-appears (position when it went in)
var progress := 0 # +0xd0, percent 1..100 while a builder works
var started_ms := 0 # +0xd8
var finish_ms := 0 # +0xdc
var hit_points := 0 # +0x82
var max_hit_points := 0 # +0x6e
var decay_at_ms := 0 # +0xe8: next 250 ms decay tick while nobody builds
var level := 0 # +0x3c, raised by Keep upgrades
var completed_counted := false # +0x14b: dependency counters raised once
# Production job (+0x9c .. +0xb9)
var job_item := "" # +0x9c: "" idle; item ID while running
var job_pending := false # +0x9c == -1: could not afford the job it tried to start
var job_cost: Array = [0, 0, 0, 0] # +0xa2..+0xa8, refunded on cancel
var job_start_ms := 0 # +0xb0
var job_end_ms := 0 # +0xac
var job_progress := 0 # +0xaa percent
var job_paused := false # +0xb9
var population_blocked := false # +0xb8
var queue: Array[String] = [] # type-2 orders in the building's order list (+0xbc)
var repeat := false # +0x190
var rally := Vector2i(-1, -1) # +0xb4/+0xb6
# Keep conversion (milestone 12, 0x52f9b0 / 0x52fc00)
var keep_converting := false # +0x191
var keep_radius := 0 # +0x192
var keep_finish_ms := 0 # +0x194
var keep_start_ms := 0 # +0x198
var definition: Dictionary

func _init(id: int, type_id: String, player: int, world_position: Vector2, def: Dictionary = {}, anchor_left: int = 0, anchor_top: int = 0):
	super._init(id, type_id, player, world_position)
	definition = def
	left = anchor_left
	top = anchor_top
	max_hit_points = int(def.get("hit_points", 0))
	hit_points = max_hit_points

func has_job() -> bool:
	return job_item != "" or job_pending

func cell_rect() -> Rect2i:
	return Rect2i(left, top, int(definition.footprint[0]), int(definition.footprint[1]))

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). The building's fields, its definition copy and its metadata (spells.gd's "morph").
func save_state(_refs = null) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self)
	s["@ctor"] = [entity_id, original_type_id, owner, position, definition, left, top]
	var metas := {}
	for name in get_meta_list(): metas[name] = preload("res://simulation/save_game.gd").copy(get_meta(name))
	s["@meta"] = metas
	return s

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state)
	for name in state.get("@meta", {}): set_meta(name, state["@meta"][name])
