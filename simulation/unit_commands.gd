## Unit and building commands of the placement and right-click layers (PARITY_BACKLOG.md "Unit commands", UI_RESEARCH.md
## "Unit commands (Read)"): wall dragging (0x429820 / 0x4299b0 / command 0x2d), building repair (message 0x112:
## 0x4a4190 -> 0x52eb10, tick 0x52ebc0) and tower garrisons (0x52db10 / 0x51c240 / 0x525960 / 0x52db50 / 0x52dd70).
## Attack-move lives in combat.gd / unit_ai.gd (the move order's +0x1c flag). Everything here is Read from the decompile;
## the parts that are not are marked Open or Provisional where they are used.
extends RefCounted

# --------------------------------------------------------------------------------------------------------- wall drag
## The wall types the placement press tests for (0x422e00 compares the armed type with these nine).
const WALL_TYPES := ["BWG0", "BWG1", "BWG2", "BWN0", "BWN1", "BWN2", "BWE0", "BWE1", "BWE2"]
const MAX_SEGMENTS := 0x40          # 0x429820: 0x74c422 < 0x40
var wall_queues: Dictionary = {}    # builder unit id -> [{"type", "cell"}]: the appended build orders of a wall run

static func is_wall(type_id: String) -> bool:
	return WALL_TYPES.has(type_id)

## One drag (0x74b988 list, 8 bytes per segment: type, x, y). The press puts the clicked cell in unsnapped (0x422e49).
class WallDrag:
	var type_id: String
	var start: Vector2i                # 0x74c3dc / 0x74c3de: its parity fixes the 2-cell lattice of the later segments
	var segments: Array = []           # [{"type", "cell"}] in drag order

	func _init(armed: String, cell: Vector2i):
		type_id = armed
		start = cell
		segments = [{"type": armed, "cell": cell}]

	## 0x429820 for the cell under the cursor while the button is held: on the map, snapped to the lattice, under the
	## segment limit, a valid site for the armed type (0x4352f0) and not a duplicate. Returns whether it was added.
	func add(cell: Vector2i, map_size: Vector2i, site_ok: Callable) -> bool:
		if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y: return false
		var odd_x := (start.x & 1) == 1
		var odd_y := (start.y & 1) == 1
		if (odd_x and cell.x <= 0) or (odd_y and cell.y <= 0): return false
		var at := Vector2i(snap(cell.x, odd_x), snap(cell.y, odd_y))
		if segments.size() >= MAX_SEGMENTS: return false
		if not site_ok.call(type_id, at): return false
		for s in segments:
			if s.cell == at: return false
		segments.append({"type": type_id, "cell": at})
		pick_variants(segments)
		return true

	static func snap(v: int, odd: bool) -> int:
		return ((v + 1) / 2) * 2 - 1 if odd else (v / 2) * 2

	## 0x4299b0 (with two or more segments): each segment's variant from its neighbours two cells away. Up and down but
	## neither side: the 1x2 piece (digit 2); both sides but neither up nor down: the 2x1 piece (digit 1); else the 2x2 (0).
	static func pick_variants(list: Array):
		if list.size() < 2: return
		var cells := {}
		for s in list: cells[s.cell] = true
		for s in list:
			var c: Vector2i = s.cell
			var up: bool = cells.has(c + Vector2i(0, -2))
			var down: bool = cells.has(c + Vector2i(0, 2))
			var left: bool = cells.has(c + Vector2i(-2, 0))
			var right: bool = cells.has(c + Vector2i(2, 0))
			var digit := 0
			if up and down and not left and not right: digit = 2
			elif not up and not down and left and right: digit = 1
			s.type = String(s.type).substr(0, 3) + str(digit)

static func pick_variants(segments: Array):
	WallDrag.pick_variants(segments)

# ------------------------------------------------------------------------------------------------------------ repair
const REPAIR_SECONDS := 45          # 0x4fffe0's message: +10 = 0x2d
var repairs: Dictionary = {}        # building id -> {"mode" +0xfe, "amount" +0x102, "seconds" +0x100, "start" +0x108, "end" +0x10c, "done" +0x104, "percent" +0x110}

## 0x52eb10: a repair starts only below full hit points. The computer (0x4fffe0) sends mode 1, the missing hit points and
## 45 s at no cost; the player's Repair button's message is not located (Open), so it sends the same (Provisional).
func start_repair(b, now_ms: int, amount: int = -1, seconds: int = REPAIR_SECONDS, mode: int = 1) -> bool:
	if b == null or b.constructing or b.hit_points <= 0 or b.hit_points >= b.max_hit_points: return false
	if amount < 0: amount = b.max_hit_points - b.hit_points
	repairs[b.entity_id] = {"mode": mode, "amount": amount, "seconds": seconds, "start": now_ms, "end": now_ms + seconds * 1000, "done": 0, "percent": 0}
	return true

func repairing(id: int) -> bool:
	return repairs.has(id)

## 0x52ebc0 for one building: percent of the time elapsed (C integer division), the share of the amount restored so far,
## the hit points raised by the new part; ends at 100 % or full hit points (clamped). Returns the new hit points and
## whether the repair goes on.
static func repair_step(r: Dictionary, hp: int, max_hp: int, now_ms: int) -> Dictionary:
	if hp >= max_hp: return {"hp": hp, "active": false}
	var p: int = (now_ms - int(r.start)) * 100 / maxi(1, int(r.end) - int(r.start))
	var target: int = int(r.amount) * p / 100
	hp += target - int(r.done)
	r.done = target
	r.percent = p
	var active := p < 100
	if hp >= max_hp:
		hp = max_hp
		active = false
	return {"hp": hp, "active": active}

func update_repairs(production, now_ms: int):
	for id in repairs.keys():
		var b = production.building(int(id))
		if b == null or b.hit_points <= 0:
			repairs.erase(id)
			continue
		var out := repair_step(repairs[id], b.hit_points, b.max_hit_points, now_ms)
		b.hit_points = int(out.hp)
		if not out.active: repairs.erase(id)

# ---------------------------------------------------------------------------------------------------------- garrison
const GARRISON_LIMIT := 4           # 0x52db10(1) / 0x52db50: +0xca < 4 (the Building.cfg digit only has to be non-zero)
const GARRISON_REACH := 6           # 0x525960: |dx| < 6 and |dy| < 6 between the unit and the building
var garrisons: Dictionary = {}      # building id -> [unit ids] (+0xec slots, +0xca count)
var garrison_orders: Dictionary = {} # unit id -> building id: order 0x12 on its way

## 0x52db10(1) with 0x5877a0: a finished building of a type whose Building.cfg garrison digit is set (the towers), with room.
func can_take(b, rules) -> bool:
	if b == null or b.constructing or b.hit_points <= 0: return false
	if int(rules.definition(String(b.original_type_id)).get("garrison", 0)) == 0: return false
	return occupants(b.entity_id).size() < GARRISON_LIMIT

## 0x51c240: a one-cell unit that is not a builder (heroes may), not an animal and not AAEY. The weight +0xb2 <= 1, flag
## +0x1c0 bit 21 and +0x1f0 tests are not ported (Open: every Knights unit passes the ones that are).
static func can_garrison(type_id: String, footprint: Array, builder: bool, hero: bool, animal: bool) -> bool:
	if not footprint.is_empty() and int(footprint[0]) > 1: return false
	if builder and not hero: return false
	if animal or type_id == "AAEY": return false
	return true

func occupants(building_id: int) -> Array:
	return garrisons.get(building_id, [])

## 0x525960 on arrival: same owner, room, and within reach of the building's cell.
func can_enter_now(b, rules, owner: int, unit_cell: Vector2i, building_cell: Vector2i) -> bool:
	if not can_take(b, rules) or int(b.owner) != owner: return false
	return absi(unit_cell.x - building_cell.x) < GARRISON_REACH and absi(unit_cell.y - building_cell.y) < GARRISON_REACH

## 0x52db50: the unit goes into the next slot.
func enter(building_id: int, unit_id: int):
	if not garrisons.has(building_id): garrisons[building_id] = []
	garrisons[building_id].append(unit_id)
	garrison_orders.erase(unit_id)

## 0x52dd70 (message 0x20b, all slots when -1): the units leave in slot order.
func leave(building_id: int, unit_id: int = -1) -> Array:
	var inside: Array = occupants(building_id)
	var out: Array = inside.duplicate() if unit_id < 0 else ([unit_id] if inside.has(unit_id) else [])
	for id in out: inside.erase(id)
	if inside.is_empty(): garrisons.erase(building_id)
	return out

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd).
func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self)

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state)
