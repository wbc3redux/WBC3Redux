extends RefCounted
## Conversion in a match (milestone 12, ECONOMY_RESEARCH.md "Milestone 12"): the area conversion of buildings by a hero,
## a flagged general or the AAPH Phoenix (order 7, 0x51cbb0 / 0x520c90) and by a Keep (0x52f9b0 / building update), with
## the original eligibility and the ownership transfer. The milestone 6 kernels do the timing (Conversion) and the
## footprint geometry and scan order (ConversionTargets); this file supplies the targets (the map's mines and every
## production building), the eligibility callback and the transfer, and holds the Keep jobs (building +0x191..+0x198).
##
## * Eligibility (Emulated, tests/conversion_fixtures.json): 0x52da90 = BMFL always; otherwise finished (+0xcc clear),
##   second type letter K / A / P / R / T (upper-cased), no garrison resistance (Building.cfg +0x7c capacity 0 or nobody
##   inside +0xca), hit points > 0, not rubble (+0x115). The owner mask of 0x5489e0: never the actor's own buildings;
##   neutral (6) always; another player's unless the actor is a computer player (0x70d6a4) allied with it. So towers (BW..),
##   walls, the Gnoll Lair (BLGL) and the Mausoleum (BZMA) are never converted; mines, Keeps and the Knights' other
##   buildings are.
## * Actor terms (Emulated 0x523af0): a hero with its owner's hero alive: seconds 0x40ad40(0x526c80 power), radius 0x5267b0
##   capped at 19; a general: 45 s, or 45 - power + 10 (at least 20) when the owner's hero has power > 10, radius 4; AAPH 45
##   s, radius 4; a dead hero 45 s, radius 4. PHOC research (and AWGX, AAGX + PBRO for generals) take 3/4; 0x51cbb0 adds 3
##   to the radius of a computer player's actor.
## * Keep (Emulated 0x52f9b0): radius 28 / 150 s for a human, 32 / 120 s for a computer player; only a finished Keep without
##   a job; the scan uses the Keep's anchor. Completion (Read, building update at 0x52cf71): now >= finish (not strict).
## * Transfer (Read 0x532640 -> 0x4a6be0 -> 0x4a6cc0): Production.convert_building / Mines.convert for each target.

const Conversion = preload("res://simulation/conversion.gd")
const Targets = preload("res://simulation/conversion_targets.gd")
const Entity = preload("res://simulation/entity_state.gd")
const NEUTRAL := 6
const LETTERS := ["K", "A", "P", "R", "T"]
const FLAG := "BMFL"
const DEFAULT_SECONDS := 45              # 0x523af0 defaults (0x2d, radius 4)
const DEFAULT_RADIUS := 4
const MAX_RADIUS := 19                   # 0x13
const COMPUTER_RADIUS := 3               # 0x51cbb0: +3 for a 0x70d6a4 player
const NOTHING_TEXT := 65                 # Game.txt [0065] "There is nothing here to convert..." (0x44f4a0(0x41))
# 0x60782c via 0x40ad40: conversion seconds by power (index 6 below 6, clamped at 99). Emulated (duration_table).
const DURATION := [100, 80, 70, 60, 50, 48, 45, 42, 39, 36, 33, 32, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15,
	14, 13, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
	9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]

signal started(actor_id: int, owner: int, finish_ms: int)
signal finished(actor_id: int, owner: int, converted: Array)        # 0x520c90 order 7 (event 0xf for the local player)
signal keep_started(building_id: int, owner: int, finish_ms: int)
signal keep_finished(building_id: int, owner: int, converted: Array)  # KeepConversion.wav for the local player
signal transferred(entity_id: int, previous: int, owner: int)        # one per converted building or mine

var production
var mines
var allied: Callable                     # (a, b) -> bool: 0x748915[b + a * 7] != 0
var computer: Dictionary = {}            # owner -> 0x70d6a4
var conversion := Conversion.new()
var actors: Dictionary = {}              # unit id -> Entity (the actor's cell for the kernel)
var garrison: Dictionary = {}            # building code -> Building.cfg +0x7c capacity
var radius_bonus: Dictionary = {}        # unit id -> 0x51cbb0 +3 (kept in the order like the original's +0xc)

# ------------------------------------------------------------------------------------------------ rules (Emulated)
static func duration_seconds(power: int) -> int:
	if power < 6: return DURATION[6]
	return DURATION[mini(power, 99)]

## 0x52da90 for one building.
static func building_convertible(code: String, constructing: bool, hp: int, rubble: bool, capacity: int, occupants: int) -> bool:
	if code == FLAG: return true
	if constructing or code.length() < 2 or not (code[1].to_upper() in LETTERS): return false
	if capacity != 0 and occupants >= 1: return false
	return hp > 0 and not rubble

## The owner mask of 0x5489e0 (8 bytes on the stack; byte 6, the neutral slot, is always 1).
static func owner_allows(actor: int, target: int, actor_computer: bool, target_allied: bool) -> bool:
	if target == actor: return false
	if target == NEUTRAL: return true
	return not target_allied or not actor_computer

## 0x523af0 with its inputs resolved: kind "hero" / "general" / "phoenix" / other, code (the unit type), hero_alive (the owner's
## hero object with hit points > 0), power (0x526c80 of the owner's hero), radius (0x5267b0 of the actor), research (PHOC),
## pbro, mode (0x748946), bonus (0x7494ea / 0x7495c4 record value, 0 = none). Returns {ok, seconds, radius}.
static func actor_terms(t: Dictionary) -> Dictionary:
	var kind := String(t.get("kind", ""))
	var code := String(t.get("code", ""))
	var seconds := DEFAULT_SECONDS
	var reach := DEFAULT_RADIUS
	if code == "AAPH": return {"ok": true, "seconds": seconds, "radius": reach}
	var alive := bool(t.get("hero_alive", false))
	var power := int(t.get("power", 0))
	if kind == "hero":
		if alive:
			seconds = duration_seconds(power)
			reach = mini(int(t.get("radius", 0)), MAX_RADIUS)
		if bool(t.get("research", false)): seconds = _three_quarters(seconds)
	elif kind == "general":
		if alive and power > 10: seconds = maxi(20, seconds - power + 10)
		if bool(t.get("research", false)): seconds = _three_quarters(seconds)
		if code == "AWGX": seconds = _three_quarters(seconds)
		if code == "AAGX" and bool(t.get("pbro", false)): seconds = _three_quarters(seconds)
	else:
		return {"ok": false, "seconds": seconds, "radius": reach}
	if int(t.get("mode", 0)) == 3: seconds = _three_quarters(seconds)
	var bonus := int(t.get("bonus", 0))
	if bonus != 0:
		seconds = seconds - (bonus * seconds) / 10
		if seconds < 1: seconds = 1
	return {"ok": true, "seconds": seconds, "radius": reach}

static func _three_quarters(value: int) -> int:
	return maxi(1, (value * 3) / 4)

## 0x52f9b0's two cases.
static func keep_terms(is_computer: bool) -> Dictionary:
	return {"radius": 32, "seconds": 120} if is_computer else {"radius": 28, "seconds": 150}

## 0x523dc0 (unit) / 0x52fc00 (Keep): 0 when idle, else (now - start) * 100 / (finish - start) within 1..100.
static func progress(active: bool, start_ms: int, finish_ms: int, now_ms: int) -> int:
	if not active: return 0
	var span := finish_ms - start_ms
	var value := 100 if span <= 0 else ((now_ms - start_ms) * 100) / span
	return clampi(value, 1, 100)

## A Keep in the sense of 0x52b030 / 0x4fbb90: second type letter K.
static func is_keep(code: String) -> bool:
	return code.length() >= 2 and code[0] == "B" and code[1].to_upper() == "K"

# ------------------------------------------------------------------------------------------------ match wiring
func setup(world_production, world_mines, catalogue: Dictionary, computer_flags: Dictionary, allied_test: Callable):
	production = world_production
	mines = world_mines
	computer = computer_flags.duplicate()
	allied = allied_test
	for row in catalogue.get("building_cfg", {}).get("buildings", []):
		garrison[String(row.code)] = int(row.get("garrison", 0))
	conversion.transfer = transfer
	conversion.targets_converted.connect(on_unit_finished)

func dispose():
	conversion.transfer = Callable()
	if conversion.targets_converted.is_connected(on_unit_finished): conversion.targets_converted.disconnect(on_unit_finished)
	conversion.active.clear()
	production = null
	mines = null

func is_computer(owner: int) -> bool:
	return bool(computer.get(owner, false))

func is_allied(a: int, b: int) -> bool:
	return allied.is_valid() and bool(allied.call(a, b))

## The scan candidates: the map's mines and every production building, each with its BUI footprint.
func records() -> Array:
	var out: Array = []
	if mines != null:
		for id in mines.mines:
			out.append({"entity": mines.mines[id].entity, "footprint": mines.mines[id].footprint, "order": int(id)})
	if production != null:
		for b in production.buildings.values():
			out.append({"entity": b, "footprint": Vector2i(int(b.definition.footprint[0]), int(b.definition.footprint[1])), "order": int(b.entity_id)})
	return out

func eligible(actor_owner: int, entity) -> bool:
	if not owner_allows(actor_owner, int(entity.owner), is_computer(actor_owner), is_allied(actor_owner, int(entity.owner))): return false
	var code := String(entity.original_type_id)
	if mines != null and mines.mines.has(entity.entity_id):
		return building_convertible(code, false, 1, false, int(garrison.get(code, 0)), int(entity.worker_count))
	return building_convertible(code, bool(entity.constructing), int(entity.hit_points), false, int(garrison.get(code, 0)), 0)

## 0x5489e0 with the eligibility above: at most eight targets in the original scan order.
func select(owner: int, origin: Vector2i, reach: int) -> Array:
	return Targets.select_from(records(), owner, origin, reach, func(o, e): return eligible(o, e))

func anchor_cell(entity) -> Vector2i:
	return entity.cell()

# ------------------------------------------------------------------------------------------------ unit conversion (order 7)
## 0x51cbb0(0) for a unit whose terms 0x523af0 resolved. Returns the finish time or -1 when nothing in range can be
## converted (the local player then sees Game.txt [0065]).
func begin_unit(unit_id: int, owner: int, cell: Vector2i, terms: Dictionary, now_ms: int, role: String = "hero") -> int:
	if not bool(terms.get("ok", false)): return -1
	if conversion.active.has(unit_id): return int(conversion.active[unit_id].finish)
	var actor: Entity = actors.get(unit_id)
	if actor == null:
		actor = Entity.new(unit_id, "AHHX", owner, Vector2.ZERO)
		actors[unit_id] = actor
	actor.owner = owner
	actor.position = Vector2(cell.x * 32 + 16, cell.y * 24 + 12)
	var reach: int = int(terms.radius) + (COMPUTER_RADIUS if is_computer(owner) else 0)
	if not conversion.begin(actor, role, int(terms.seconds), reach, now_ms, select): return -1
	conversion.active[unit_id]["start"] = now_ms
	started.emit(unit_id, owner, int(conversion.active[unit_id].finish))
	return int(conversion.active[unit_id].finish)

func converting(unit_id: int) -> bool:
	return conversion.active.has(unit_id)

## Parity pass 4: the target marks (+0x14a, Read). 0x51cbb0 marks the targets its scan found when a local player's unit
## starts converting (table 0x681118); 0x520c90 clears them when the job completes and the sweep 0x4062b0 when the actor
## no longer converts. The building draw 0x53b014 then rings a marked building (red for another owner's) without a strip.
func marked_buildings(owner: int) -> Dictionary:
	var out := {}
	for id in conversion.active:
		var job: Dictionary = conversion.active[id]
		if int(job.owner) != owner: continue
		for target in job.get("targets", []): out[int(target)] = true
	return out

## Deliberate modern addition (playtest 2026-11-11, Enhanced visuals only): the Keep's conversion (0x52f9b0) marks nothing
## in the original; with Enhanced visuals the buildings and mines a converting Keep of `owner` would take now (the same scan
## 0x52fc00's completion uses) are ringed like a unit conversion's targets.
func keep_marked_buildings(owner: int) -> Dictionary:
	var out := {}
	if production == null: return out
	for b in production.buildings.values():
		if not b.keep_converting or int(b.owner) != owner: continue
		for target in select(owner, anchor_cell(b), int(b.keep_radius)): out[int(target.entity_id)] = true
	return out

func move_actor(unit_id: int, cell: Vector2i):
	if actors.has(unit_id): actors[unit_id].position = Vector2(cell.x * 32 + 16, cell.y * 24 + 12)

func cancel(unit_id: int):
	conversion.cancel(unit_id)

func unit_progress(unit_id: int, now_ms: int) -> int:
	if not conversion.active.has(unit_id): return 0
	var job: Dictionary = conversion.active[unit_id]
	return progress(true, int(job.get("start", job.finish)), int(job.finish), now_ms)

# ------------------------------------------------------------------------------------------------ Keep conversion
## 0x52f9b0: the Keep's convert button (the human player) or the computer player's 0x4fbb90. Returns the finish time or
## -1 (an unfinished Keep or one with a job does nothing; an empty area shows [0065] to the local player).
func begin_keep(b, now_ms: int) -> int:
	if b == null or b.constructing or b.has_job() or b.keep_converting: return -1
	var terms := keep_terms(is_computer(int(b.owner)))
	if select(int(b.owner), anchor_cell(b), int(terms.radius)).is_empty(): return -1
	b.keep_converting = true
	b.keep_radius = int(terms.radius)
	b.keep_start_ms = now_ms
	b.keep_finish_ms = now_ms + int(terms.seconds) * 1000
	b.production_changed.emit(b.entity_id)
	keep_started.emit(b.entity_id, int(b.owner), b.keep_finish_ms)
	return b.keep_finish_ms

## 0x52fbc0 (the Cancel button, or the Keep changing owner).
func cancel_keep(b):
	if b == null or not b.keep_converting: return
	b.keep_converting = false
	b.production_changed.emit(b.entity_id)

func keep_progress(b, now_ms: int) -> int:
	return progress(b.keep_converting, b.keep_start_ms, b.keep_finish_ms, now_ms)

# ------------------------------------------------------------------------------------------------ update and transfer
func update(now_ms: int):
	conversion.update(now_ms)
	if production == null: return
	for b in production.buildings.values():
		if not b.keep_converting or now_ms < b.keep_finish_ms: continue
		b.keep_converting = false
		var owner: int = int(b.owner)
		var targets := select(owner, anchor_cell(b), b.keep_radius)
		transfer(targets, owner)
		b.production_changed.emit(b.entity_id)
		keep_finished.emit(b.entity_id, owner, targets.map(func(e): return int(e.entity_id)))

## The kernel's completion hook (0x520c90 -> 0x532640 with the order's radius): the targets of the fresh scan change owner.
func on_unit_finished(unit_id: int, owner: int, targets: Array):
	finished.emit(unit_id, owner, targets.map(func(e): return int(e.entity_id)))

## 0x4a6be0 -> 0x4a6cc0 for each target, in scan order.
func transfer(targets: Array, owner: int):
	for entity in targets:
		var previous: int = int(entity.owner)
		if previous == owner: continue
		if mines != null and mines.mines.has(entity.entity_id): mines.convert(entity.entity_id, owner)
		elif production != null and production.buildings.has(entity.entity_id):
			cancel_keep(production.buildings[entity.entity_id])
			production.convert_building(entity.entity_id, owner)
		else:
			entity.owner = owner
		transferred.emit(int(entity.entity_id), previous, owner)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). Actors are shared entities (Refs).
const _SAVE_SKIP := ["production", "mines", "allied", "conversion", "actors"]

func save_state(refs) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, _SAVE_SKIP)
	s["conversion"] = conversion.save_state(refs)
	s["actors"] = actors.keys().map(func(id): return [id, refs.ref(actors[id])])
	return s

func load_state(state: Dictionary, refs):
	preload("res://simulation/save_game.gd").restore(self, state, _SAVE_SKIP)
	actors.clear()
	for pair in state.actors: actors[pair[0]] = refs.get_obj(int(pair[1]))
	conversion.load_state(state.conversion, refs, select)
