extends RefCounted
## Milestone AI-4: the computer player's danger test 0x4fac00 and its strength tables 0x505530 (AI_RESEARCH.md "AI-4").
## Emulated: tests/ai4_fixtures.json "strength" (every unit and building record) and "danger" (1,200 cases), checked in
## tests/test_ai4.gd.
##
## 0x505530 (run once by the manager constructor 0x504a30) fills one value per unit type (0xa4eb38, ARM record shorts)
## and per building type (0xa4ecc8, BUI record shorts). 0x4fac00(AI, object, only_targeting) sums them over the map rows
## around the object: a window of ARM +0x39 + 16 cells around a unit (BUI +0x3f + 12 around a building; any other kind
## answers 0), clamped to the map. Every object in it counts unless it is hidden (+0x30), allied with the AI's player
## (0x748915[owner + me * 7], which includes its own objects) or neutral (owner 6). A unit whose attack target (+0x158) is
## the object counts twice; a building counts twice when it is armed with a target (0x52e780: +0x7c > 0; 0x52a410) that
## is the object. With `only_targeting` only those count, once. No hit-point or state test is made.

static func _i16(raw: PackedByteArray, at: int) -> int:
	return raw.decode_s16(at) if raw.size() >= at + 2 else 0

static func _s16(v: int) -> int:
	v = v & 0xffff
	return v - 0x10000 if v >= 0x8000 else v

## 0xa4eb38[type]: (+0x32 >> 1) + (+0x24 >> 2) + +0x36 + +0x1e + +0x20 of the ARM record.
static func unit_strength(raw: PackedByteArray) -> int:
	return _s16((_i16(raw, 0x32) >> 1) + (_i16(raw, 0x24) >> 2) + _i16(raw, 0x36) + _i16(raw, 0x1e) + _i16(raw, 0x20))

## 0xa4ecc8[type]: 0 while the BUI damage +0x38 is below 1, else ((+0x24 + +0x26 + +0x38) * 2 + +0x2a) * 2.
static func building_strength(raw: PackedByteArray) -> int:
	if _i16(raw, 0x38) < 1: return 0
	return _s16(((_i16(raw, 0x24) + _i16(raw, 0x26) + _i16(raw, 0x38)) * 2 + _i16(raw, 0x2a)) * 2)

## The window half-size: ARM +0x39 + 16 for a unit (kind 0), BUI +0x3f + 12 for a building (kind 1), -1 otherwise.
static func reach(kind: int, raw: PackedByteArray) -> int:
	if kind == 0: return (raw[0x39] if raw.size() > 0x39 else 0) + 16
	if kind == 1: return (raw[0x3f] if raw.size() > 0x3f else 0) + 12
	return -1

## 0x4fac00 over prepared objects. `objects`: [{cell, owner, hidden, kind (0 unit, 1 building, other ignored), value
## (the type's table value), targets (true when its target is the asking object; for a building: armed, +0x7c > 0 and
## aimed at it)}]; `allied` = Callable(owner) -> bool (0x748915[owner + me * 7]); width / height = the map.
static func danger(centre: Vector2i, half: int, width: int, height: int, objects: Array, allied: Callable, only_targeting: bool) -> int:
	if half < 0: return 0
	var x_lo := maxi(0, centre.x - half)
	var x_hi := mini(centre.x + half, width - 1)
	var y_lo := maxi(0, centre.y - half)
	var y_hi := mini(centre.y + half, height - 1)
	var total := 0
	for o in objects:
		var c: Vector2i = o.cell
		if c.y < y_lo or c.y > y_hi or c.x < x_lo or c.x > x_hi or bool(o.get("hidden", false)): continue
		var owner := int(o.owner)
		if owner == 6 or allied.call(owner): continue
		var kind := int(o.kind)
		if kind != 0 and kind != 1: continue
		var hit := bool(o.get("targets", false))
		var value := int(o.value)
		if only_targeting: total += value if hit else 0
		else: total += value * 2 if hit else value
	return total

# ------------------------------------------------------------------------------------------------ the port's world
## The 0x505530 tables for the port's record definitions (cached per type id).
var _unit_values := {}
var _building_values := {}
var _reach := {}
var world

func _init(world_node) -> void:
	world = world_node

func unit_value(type_id: String) -> int:
	if not _unit_values.has(type_id):
		var d: Dictionary = world.production.rules.definition(type_id)
		_unit_values[type_id] = unit_strength(String(d.get("raw_hex", "")).hex_decode())
	return int(_unit_values[type_id])

func building_value(type_id: String) -> int:
	if not _building_values.has(type_id):
		var d: Dictionary = world.production.rules.definition(type_id)
		_building_values[type_id] = building_strength(String(d.get("raw_hex", "")).hex_decode())
	return int(_building_values[type_id])

func unit_reach(type_id: String) -> int:
	if not _reach.has(type_id):
		var d: Dictionary = world.production.rules.definition(type_id)
		_reach[type_id] = reach(0, String(d.get("raw_hex", "")).hex_decode())
	return int(_reach[type_id])

## AI-9 (Read, 0x4fbe80, decompile 166211-166280): the hostile strength around a cell for the home move 0x4fbdf0: the
## map rows centre.y +- 30 and columns centre.x +- 30 (clamped to the map), every object not hidden, not allied with `me`
## (own objects included) and not neutral; a unit adds its 0x5055f0 value (0xa4eb38), a building its 0x505610 value
## (0xa4ecc8) only while 0x52e780 holds (+0x7c > 0: armed, the port's tower damage >= 1), any other object 0. No
## doubling for targets (that is 0x4fac00's). The same objects and window rules as `danger_to_unit`.
const HOME_REACH := 30

func strength_near(me: int, centre: Vector2i) -> int:
	var c = world.combat
	var objects: Array = []
	for f in c.fighters.values():
		if not c.alive(f): continue
		var u = world.unit_by_id(int(f.id))
		if u == null or u.removed or u.inside_building: continue
		objects.append({"cell": c.unit_cell(int(f.id)), "owner": int(f.owner), "hidden": bool(f.get("flag_30", false)), "kind": 0,
			"value": unit_value(String(f.type_id))})
	for b in world.production.buildings.values():
		var tower = c.towers.get(int(b.entity_id))
		var armed: bool = tower != null and int(tower.damage) >= 1
		objects.append({"cell": Vector2i(int(b.left), int(b.top)), "owner": int(b.owner), "hidden": false, "kind": 1,
			"value": building_value(String(b.original_type_id)) if armed else 0})
	var width: int = int(world.collision.width) if world.collision != null and "width" in world.collision else 1 << 20
	var height: int = int(world.collision.height) if world.collision != null and "height" in world.collision else 1 << 20
	return danger(centre, HOME_REACH, width, height, objects, func(owner): return c.allied(owner, me), false)

## AI-11: 0x4fac00(AI of `me`, a building or mine, 0) as 0x4f6340 stores it in a conversion-list entry (+0x1a2): the
## window BUI +0x3f + 12 around the object's cell (its anchor, as above), every hostile unit and building in it; a unit
## whose attack order is the object counts twice (a building's tower target is never a building or mine here).
func danger_to_building(me: int, kind: String, id: int, cell: Vector2i, code: String) -> int:
	var c = world.combat
	var objects: Array = []
	for f in c.fighters.values():
		if not c.alive(f): continue
		var u = world.unit_by_id(int(f.id))
		if u == null or u.removed or u.inside_building: continue
		var order = f.get("order")
		var targets: bool = order != null and String(order.get("target_kind", "")) == kind and int(order.get("target_id", -1)) == id
		objects.append({"cell": c.unit_cell(int(f.id)), "owner": int(f.owner), "hidden": bool(f.get("flag_30", false)), "kind": 0,
			"value": unit_value(String(f.type_id)), "targets": targets})
	for b in world.production.buildings.values():
		objects.append({"cell": Vector2i(int(b.left), int(b.top)), "owner": int(b.owner), "hidden": false, "kind": 1,
			"value": building_value(String(b.original_type_id)), "targets": false})
	var raw: PackedByteArray = String(world.production.rules.definition(code).get("raw_hex", "")).hex_decode()
	var width: int = int(world.collision.width) if world.collision != null and "width" in world.collision else 1 << 20
	var height: int = int(world.collision.height) if world.collision != null and "height" in world.collision else 1 << 20
	return danger(cell, reach(1, raw), width, height, objects, func(owner): return c.allied(owner, me), false)

## 0x4fac00(AI of `me`, unit `asker_id`, only_targeting) on the port's world. The map rows hold the units on the map
## (living fighters not inside a building; a worker in a mine has left play, state 8) and the buildings (by their
## anchor cell, the sprite cell +0x48 / +0x4a of a building is Open: the anchor stands in). A unit's target +0x158 is its
## current attack order or script target; a building's is its tower target.
func danger_to_unit(me: int, asker_id: int, only_targeting: bool) -> int:
	var c = world.combat
	var asker = c.fighters.get(asker_id)
	if asker == null: return 0
	var centre: Vector2i = c.unit_cell(asker_id)
	var objects: Array = []
	for f in c.fighters.values():
		if int(f.id) == asker_id or not c.alive(f): continue
		var u = world.unit_by_id(int(f.id))
		if u == null or u.removed or u.inside_building: continue
		var order = f.get("order")
		var targets: bool = order != null and String(order.get("target_kind", "")) == "unit" and int(order.get("target_id", -1)) == asker_id
		objects.append({"cell": c.unit_cell(int(f.id)), "owner": int(f.owner), "hidden": bool(f.get("flag_30", false)), "kind": 0,
			"value": unit_value(String(f.type_id)), "targets": targets})
	for b in world.production.buildings.values():
		var tower = c.towers.get(int(b.entity_id))
		var armed: bool = tower != null and int(tower.damage) > 0 and String(tower.target_kind) == "unit" and int(tower.target_id) == asker_id
		objects.append({"cell": Vector2i(int(b.left), int(b.top)), "owner": int(b.owner), "hidden": false, "kind": 1,
			"value": building_value(String(b.original_type_id)), "targets": armed})
	var width: int = int(world.collision.width) if world.collision != null and "width" in world.collision else 1 << 20
	var height: int = int(world.collision.height) if world.collision != null and "height" in world.collision else 1 << 20
	return danger(centre, unit_reach(String(asker.type_id)), width, height, objects, func(owner): return c.allied(owner, me), only_targeting)
