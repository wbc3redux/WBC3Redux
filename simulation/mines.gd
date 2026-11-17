extends RefCounted
## The map's resource mines in a match (milestone 10b; MINES section of AI_RESEARCH.md): economy registration, hero
## conversion and Peasants entering a mine. The output, depletion and conversion geometry are the milestone 6 kernels
## (Economy, Conversion, ConversionTargets); this file only wires them to the map.
##
## * Reserve and rate (Data): the BLDH record holds the saved building object from +0x24: reserves G M C S at record
##   +0x68..+0x6e and rates at +0x70..+0x76, the object fields +0x8c / +0x94 that the emulated output code 0x52aac0 reads.
##   Desert Sands: level 2 mines 8000 / 2, level 3 mines 15000 / 4. The copy inside 0x4910e0 is not traced.
## * Conversion (milestone 12): MatchConversion scans the mines together with the production buildings and calls
##   `convert` for each converted mine (0x4a6cc0).
## * Workers (Read, 0x524d10): a unit of the mine's owner enters while fewer than 8 work there; it leaves the map.
##   A captured mine loses its workers (0x4a6cc0 sets +0xca to 0; the workers left play on entry, 0x51a130).

const Entity = preload("res://simulation/entity_state.gd")
const NEUTRAL := 6
const LANES := {"G": 0, "M": 1, "C": 2, "S": 3}
const MAX_WORKERS := 8

signal converted(mine_id: int, owner: int)

var economy
var mines: Dictionary = {}               # id -> {"entity", "lane", "level", "anchor", "cells", "footprint", "code"}
var workers: Dictionary = {}             # mine id -> [unit ids]

## Registers every BR?? placement of the map (owner from BLDH +0x64, normally 6) with ids from `first_id`.
func setup(world_economy, map: Dictionary, collision_objects: Array, first_id: int) -> int:
	economy = world_economy
	var by_offset := {}
	for r in map.buildings: by_offset[int(r.source_offset)] = r
	var id := first_id
	for o in collision_objects:
		if o.kind != "buildings" or not String(o.code).begins_with("BR"): continue
		var r: Dictionary = by_offset.get(int(o.source_offset), {})
		if r.is_empty(): continue
		var raw: PackedByteArray = String(r.raw_hex).hex_decode()
		var lane: int = LANES.get(String(o.code).substr(2, 1), -1)
		if lane < 0: continue
		var reserve: int = raw.decode_s16(0x68 + lane * 2)
		var rate: int = raw.decode_s16(0x70 + lane * 2)
		var level: int = int(r.get("level", raw.decode_s16(0x66)))
		var entity := Entity.new(id, String(o.code), int(r.get("owner", NEUTRAL)), Vector2(float(o.world_position[0]), float(o.world_position[1])), level)
		if not economy.register_mine(entity, lane, rate, reserve): continue
		var cells: Array = o.get("occupied_cells", []).map(func(c): return Vector2i(int(c[0]), int(c[1])))
		mines[id] = {"entity": entity, "lane": lane, "level": level, "code": String(o.code),
			"anchor": Vector2i(int(o.anchor_cell[0]), int(o.anchor_cell[1])), "cells": cells, "footprint": Vector2i(int(o.size[0]), int(o.size[1])),
			"source_offset": int(o.source_offset)}
		workers[id] = []
		id += 1
	return id

func dispose():
	economy = null
	mines.clear()

## 0x4a6cc0 for a mine: the owner changes and the workers are cleared (+0xca = 0; they left play on entry). A resource
## building has no garrison flag, so +0xca stays 0 (the -1 branch needs 0x52e710).
func convert(mine_id: int, owner: int):
	if not mines.has(mine_id): return
	var e: Entity = mines[mine_id].entity
	e.worker_count = 0
	e.owner = owner
	workers[mine_id].clear()
	converted.emit(mine_id, owner)

func owner_of(mine_id: int) -> int:
	return int(mines[mine_id].entity.owner) if mines.has(mine_id) else -1

func mine_at(cell: Vector2i) -> int:
	for id in mines:
		if cell in mines[id].cells: return id
	return -1

## 0x524d10: a unit of the mine's owner enters while fewer than 8 work there; it adds its 0x523e70 workers (a Smith 2),
## capped at 8 (REVIEW_RACES_HEROES.md D1).
func enter(mine_id: int, unit_id: int, owner: int, count: int = 1) -> bool:
	if not mines.has(mine_id): return false
	var e: Entity = mines[mine_id].entity
	if e.owner != owner or e.worker_count >= MAX_WORKERS: return false
	e.worker_count = mini(MAX_WORKERS, e.worker_count + count)
	workers[mine_id].append(unit_id)
	return true

func worker_count(mine_id: int) -> int:
	return int(mines[mine_id].entity.worker_count)

## Mine census rows for the computer player (0x4fc280 node fields: cell, lane, owned, workers, level, exhausted).
func census(owner: int) -> Array:
	var rows: Array = []
	for id in mines:
		var m: Dictionary = mines[id]
		rows.append({"id": id, "cell": m.anchor, "lane": m.lane, "owned": m.entity.owner == owner, "owner": m.entity.owner,
			"workers": m.entity.worker_count, "level": m.level, "exhausted": bool(economy.mines[id].exhausted)})
	return rows

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd).
func save_state(refs) -> Dictionary:
	var SG = preload("res://simulation/save_game.gd")
	var s: Dictionary = SG.capture(self, ["economy", "mines"])
	var rows := {}
	for id in mines:
		var m := {}
		for k in mines[id]: m[k] = refs.ref(mines[id][k]) if k == "entity" else SG.copy(mines[id][k])
		rows[id] = m
	s["mines"] = rows
	return s

func load_state(state: Dictionary, refs):
	var SG = preload("res://simulation/save_game.gd")
	SG.restore(self, state, ["mines"])
	mines.clear()
	for id in state.mines:
		var m := {}
		for k in state.mines[id]: m[k] = refs.get_obj(int(state.mines[id][k])) if k == "entity" else SG.copy(state.mines[id][k])
		mines[id] = m
