extends Node2D
const Assets = preload("res://core/asset_store.gd")

const ArtData = preload("res://core/art_data.gd")
# Per-cell step duration (game ms) by clamped effective speed, executable table 0x61178c.
const STEP_TABLE = [1200, 900, 800, 700, 600, 550, 525, 500, 475, 450, 430, 410, 390, 370, 350, 340,
	330, 320, 310, 300, 290, 280, 275, 270, 265, 260, 255, 250, 245, 240, 235]
const WALK_FRAMES := 16 # AHKX walk ANI slot 1; ARM +0xf8..+0xfe step factors are all 1.
# Per-frame displacement weights: AHKX ARM +0xd3 (copied by 0x41b3d0, returned by 0x526840).
const WALK_WEIGHTS = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
# Starting walk frame when the unit was not already walking, table 0x61174c (shared counter).
const RANDOM_PHASE = [0, 3, 1, 4, 2, 7, 4, 5, 2, 0, 1, 3, 6, 0, 2, 1]
# Vertical bob 0x611aac; 0x5377a0 adds it only uphill or with unit +0x449 set.
const BOB_TABLE = [0, 1, 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1]
static var phase_counter := 0
static var always_health := false # DELIBERATE MODERN CHANGE (modern_rules.gd "HealthBars"): strips on every unit
# A waiting unit retries on the next game update. The update 0x458bb0 runs when the periodic
# timeSetEvent(25 ms) callback 0x456500 has set its flag (Read); per-unit polling inside it is
# inferred from the walk state, not traced.
const WAIT_MS := 25.0
const DETOUR_INTERVAL_MS := 100
const DETOUR_LIMIT := 90
var unit_id := 0
var type_id := "AHKX" # Sheets come from assets/art.json by type (ART_RESEARCH.md); a type without imported art falls back to the Swordsman (tagged).
var inside_building := false # Inside an unfinished building: not drawn, not selectable, not on the grid (0x4a6f80, unit virtual +0x70).
var base_speed := 8 # AHKX ARM speed; the effective terms (statuses, research, the hero's aura +2: spells.speed_term) are added in.
var extent := 1 # ARM +0x38/+0x39 (milestone 11a): 2 for the 2x2 units; occupancy, cell checks and routes use it (navigation.gd)
var flying := false # ARM +5 == 1 (milestone 13): the second grid layer, straight flights, flyers block only flyers
var movement_type := 0 # ARM +5 (M-3): 0 ground, 2 water, 3 amphibious use the ground layer with their own cell check (navigation.gd)
var facing := 0 # Group facing byte +0x105 (0x530870), 0 at creation (0x519ae0).
var selected := false
var navigator: RefCounted
var orders: Array[Dictionary] = [] # Includes active order at index zero.
var cells: Array[Vector2i] = [] # Active segment (original path +0x30).
var segments: Array = [] # Later segments of the active order (0x42ff30 chain).
var path := PackedVector2Array() # Cell centres of the active route, for drawing.
var waypoint := 0
var cell := Vector2i(-1, -1)
var direction := 4
var elapsed := 0.0
var distance_travelled := 0.0
var moving_time := 0.0
var completed_orders := 0
var last_error := ""
var walking := false
var in_step := false
var step_from := Vector2.ZERO
var step_to := Vector2.ZERO
var step_time := 0.0
var turn_time := 0.0
var step_duration := 0.0
var step_frame_ms := 0.0
var step_offsets: Array[Vector2i] = [] # Absolute offset shown from each walk entry.
var turn_entries: Array[Vector2i] = [] # (direction, idle-sheet frame) per turn entry.
var walk_phase := 0
var walk_frame := 0
var chain_open := false # Previous step ended with this step already pending (state stays walk).
var wait_left := 0.0
var waits := 0
var waiting := false
var detour_failures := 0
# This unit's reading of the shared clock (navigation.gd `clock_ms`) for the 0x4308b0 throttle; it also runs while the
# unit is inside a building, so units made or released late share the clock of the older ones. -1 before the first advance.
var clock_ms := -1.0
var route_active := false
# DELIBERATE MODERN CHANGES (navigation.gd `improved`, COMPLAINTS_AND_FIXES.md F1/F2): march membership, the shared-route
# index of each cell of the walk, a per-unit detour clock instead of the shared one, and the nudge clock.
var march_id := -1
var marks := PackedInt32Array()
var march_wait_ms := 0.0
var next_own_detour_ms := 0
var detour_misses := 0
var nudged_ms := -100000
const OWN_DETOUR_INTERVAL_MS := 250
const MARCH_PATIENCE_MS := 4000.0     # a member stops waiting for the group after this long
const NUDGE_INTERVAL_MS := 1000
var sprite: Sprite2D
var art_type := "AHKX" # type whose sheets are drawn: type_id when imported, else the Swordsman placeholder
var own_walk_phase := 0 # first walk frame of the current step in the unit's own walk sheet (0x5377a0 p)
var own_walk_frame := 0 # last own walk frame shown (a chained step continues from it)
var step_diagonal := false
var control_group := 0
# Milestone 8 combat state (set by simulation/combat.gd). Owner 0 is the local player, owner 1 the test opponent.
var owner_id := 0
var hp := 0
var max_hp := 0
var dying := false # state 8: the d animation plays, the unit no longer occupies a cell
var removed := false # corpse gone (30.7 s after death)
var anim: Dictionary = {} # {"sheet": "AHKXf.RLE", "row": 0-7, "frame": n, "slot", "index", "frames"} while an attack or death plays
# Parity pass 3/4: ms since the unit's conversion (order 7) started, -1 when it does not convert. Order 7's step
# (0x5205d0 case 7) sends message 0x105 (0x536c70), whose handler 0x4a62e0 builds state 6 (0x536cc0, Read): with
# F = ANI slot 6's frame count, entries i = 0..F every 100 ms show slot 6 frame i, except that entries F - 1 and F show
# the idle sheet (slot 0), row 4, frame 0; it also starts EZ56 at the unit. When the last entry is due the sequence ends
# and 0x51e170 runs order 7's step again (0x51f9b0 has no case 7: true), so the pose repeats every F * 100 ms until
# the conversion ends. For AHHX (F = 37): banner frames 0..35, then 100 ms standing facing row 4.
var convert_ms := -1.0
var convert_cycle := -1
const CONVERT_FRAME_MS := 100.0

func convert_frames() -> int:
	return int(_sheet(6).get("frame_count", 0))

func convert_cycle_index() -> int:
	var count := convert_frames()
	return int(convert_ms / (count * CONVERT_FRAME_MS)) if count > 0 and convert_ms >= 0.0 else 0
# Fog arming at each step start (0x5377a0 -> 0x485c70): Callable(owner, from_cell, to_cell, facing_changed), set by the
# owner of the Visibility; empty outside the combat scenes.
var sight_step: Callable
var order_step: Callable # (unit id, new cell): the step builder moves the guard point of a unit with an unfinished order (0x5377a0)

func _ready():
	sprite = Sprite2D.new()
	art_type = type_id if ArtData.has_unit(type_id) else "AHKX"
	# The owner's colour now comes from the sheets' team entries; main.gd's per-type/per-owner tints were placeholders
	# for missing art (left in main.gd while milestone 10a edits it). Units without imported art keep the tint.
	if ArtData.has_unit(type_id): modulate = Color.WHITE
	sprite.region_enabled = true
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	update_sprite()

func _notification(what: int):
	if what == NOTIFICATION_PREDELETE and navigator != null: navigator.release(self, cell)

# Units occupy their logical cell; positions set directly (fixtures, demos) re-register here.
func sync_cell():
	if in_step or navigator == null: return
	# P-3: the position and cell the last call found matching need no new look-up (world_cell depends on the position only).
	if position == _synced_position and cell == _synced_cell and navigator == _synced_navigator: return
	var current: Vector2i = navigator.collision.world_cell(position)
	if current != cell:
		navigator.release(self, cell)
		cell = current
		navigator.occupy(self, cell)
	_synced_position = position
	_synced_cell = cell
	_synced_navigator = navigator

var _synced_position := Vector2(NAN, NAN)
var _synced_cell := Vector2i(-1, -1)
var _synced_navigator: RefCounted = null

static func step_ms(speed: int) -> Dictionary:
	var frame: int = STEP_TABLE[clampi(speed, 0, 30)] / WALK_FRAMES
	return {"frame": frame, "step": frame * WALK_FRAMES}

## A duration rounded up to the next 25 ms game update (Measured, LIVE_COMPARISON.md section 1).
static func on_update(ms: float) -> float:
	return ceilf(ms / WAIT_MS - 0.000001) * WAIT_MS

static func turn_frames(from_direction: int, to_direction: int) -> int:
	var d := absi(to_direction - from_direction) % 8
	d = mini(d, 8 - d)
	return 2 * d - 1 if d > 0 else 0

# 0x5377a0: two half-steps per 45 degrees, drawn from the idle sheet (entry slot byte 0).
# A 180 degree turn goes anticlockwise from rows 0-3 and clockwise from rows 4-7.
static func turn_sequence(from_direction: int, to_direction: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	# Guard: a direction outside 0..7 (a step that is not to a neighbouring cell) would never end the loop below.
	if to_direction < 0 or to_direction > 7 or from_direction < 0 or from_direction > 7: return out
	var diff := to_direction - from_direction
	if diff == 0: return out
	var clockwise := not ((diff > 3 and diff < 8) or (diff > -4 and diff < 0))
	var d := from_direction
	var sub := 0
	while true:
		if clockwise:
			sub += 1
			if sub > 1:
				sub = 0
				d = posmod(d + 1, 8)
		else:
			sub -= 1
			if sub < 0:
				sub = 1
				d = posmod(d - 1, 8)
		if d == to_direction and sub == 0: break
		out.append(Vector2i(d, sub))
	return out

# Absolute integer offsets after each walk entry: cumulative weights from the phase, truncated
# towards zero (C division) before differencing, so the step lands exactly on the last frame.
static func walk_offsets(delta: Vector2i, phase: int, bob: bool = false) -> Array[Vector2i]:
	var total := 0
	for i in WALK_FRAMES: total += WALK_WEIGHTS[(phase + i) % WALK_FRAMES]
	var out: Array[Vector2i] = []
	var cum := 0
	for i in WALK_FRAMES:
		cum += WALK_WEIGHTS[(phase + i) % WALK_FRAMES]
		var offset := Vector2i(int(float(delta.x * cum) / total), int(float(delta.y * cum) / total))
		if bob and i < WALK_FRAMES - 1: offset.y += BOB_TABLE[i]
		out.append(offset)
	return out

static func next_random_phase() -> int:
	var phase: int = RANDOM_PHASE[phase_counter]
	phase_counter = (phase_counter + 1) % RANDOM_PHASE.size()
	return phase

static func direction_of(step: Vector2i) -> int:
	return [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)].find(step)

func is_moving() -> bool:
	return in_step or (not orders.is_empty() and (waypoint < cells.size() or not segments.is_empty()))

func give_order(order: Dictionary, mode: String):
	sync_cell()
	last_error = ""
	if mode == "replace":
		drop_queued_marches()
		orders.clear()
		clear_route()
		leave_march()
	elif mode == "prepend":
		clear_route() # Replan interrupted order when it resumes from the new location.
		leave_march()
	if mode == "prepend": orders.push_front(order.duplicate())
	else: orders.append(order.duplicate())

func stop():
	drop_queued_marches()
	orders.clear()
	clear_route()
	leave_march()

## Orders that are dropped before they started still hold this unit's place in their march (navigation.gd marches).
func drop_queued_marches():
	if navigator == null: return
	for o in orders:
		if o.has("march"): navigator.march_leave(int(o.march), unit_id)

func leave_march():
	if march_id >= 0 and navigator != null: navigator.march_leave(march_id, unit_id)
	march_id = -1
	marks = PackedInt32Array()
	march_wait_ms = 0.0

func clear_route():
	cells.clear()
	segments.clear()
	path.clear()
	waypoint = 0
	route_active = false
	waiting = false
	waits = 0
	detour_failures = 0
	wait_left = 0.0

func activate_order() -> bool:
	clear_route()
	leave_march()
	while not orders.is_empty():
		var from: Vector2 = position if not in_step else step_to
		# Modern march (F1): the walk was planned with the group; it is used once (a re-planned order walks alone).
		if orders[0].has("cells") and navigator.improved and not flying:
			var walk: Array = orders[0].cells
			march_id = int(orders[0].get("march", -1))
			marks = PackedInt32Array(orders[0].get("marks", PackedInt32Array()))
			orders[0].erase("cells")
			orders[0].erase("marks")
			orders[0].erase("march")
			route_active = true
			segments = [walk] if not walk.is_empty() else []
			path = PackedVector2Array([from])
			for c in walk: path.append(navigator.center(c))
			if march_id >= 0 and marks.size() != walk.size(): leave_march()
			next_segment()
			return true
		orders[0].erase("cells")
		if orders[0].has("march"):
			navigator.march_leave(int(orders[0].march), unit_id)
			orders[0].erase("march")
		var route: Dictionary = navigator.plan_flight(from, orders[0].target) if flying else navigator.plan(from, orders[0].target, extent, movement_type)
		# DELIBERATE MODERN CHANGE (playtest 2026-11-11): a 2 x 2 unit standing where it does not fit (wedged into a narrow
		# gap) has no route at its own size from there; it first steps out at size 1 to the nearest cell that fits it, then
		# the order is planned again. Before, it stood still for good (an Orc giant ignored the Wights hitting it).
		if not route.ok and not flying and extent > 1 and not bool(orders[0].get("unwedge", false)):
			var here: Vector2i = navigator.collision.world_cell(from)
			if not navigator.passable_extent(here, extent, movement_type):
				var out: Vector2i = navigator.free_cell_near(here, self, extent, movement_type)
				var step: Dictionary = navigator.plan(from, navigator.center(out), 1, movement_type) if out.x >= 0 and out != here else {"ok": false}
				if step.ok:
					var leave: Dictionary = orders[0].duplicate()
					leave["target"] = navigator.center(out)
					leave["requested"] = leave.target
					leave["unwedge"] = true
					orders.push_front(leave)
					route = step
		if route.ok:
			route_active = true
			segments = route.segments.duplicate()
			path = PackedVector2Array(route.path)
			next_segment()
			return true
		last_error = route.reason
		orders.pop_front()
	return false

# The follower requests the next chained segment when the current one is used up.
func next_segment() -> bool:
	if segments.is_empty(): return false
	cells.assign(segments.pop_front())
	waypoint = 0
	return true

func complete_order():
	orders.pop_front()
	completed_orders += 1
	clear_route()
	leave_march()

func advance(delta: float):
	if navigator != null:
		clock_ms = navigator.clock_ms if clock_ms < 0.0 else clock_ms + delta * 1000.0
		if clock_ms > navigator.clock_ms: navigator.clock_ms = clock_ms
	if inside_building or removed: return
	if dying:
		if march_id >= 0: leave_march()
		update_sprite()
		if _drawn or _wants_draw(): queue_redraw()
		return
	sync_cell()
	walking = false
	var remaining := delta * 1000.0
	var safety := 0
	while remaining > 0.0000001 and safety < 4096:
		safety += 1
		if in_step:
			var t := minf(remaining, step_duration - step_time)
			step_time += t
			remaining -= t
			moving_time += t / 1000.0
			walking = true
			# 0x5394a0 applies every due entry: the unit moves in whole-frame, whole-pixel jumps.
			var entry := step_entry()
			if entry >= 0:
				position = step_from + Vector2(step_offsets[mini(entry, WALK_FRAMES - 1)])
			if step_time >= step_duration - 0.000001:
				position = step_to
				distance_travelled += step_from.distance_to(step_to)
				in_step = false
				chain_open = true
				walk_frame = (walk_phase + WALK_FRAMES - 1) % WALK_FRAMES
			continue
		if wait_left > 0.0:
			chain_open = false
			var w := minf(remaining, wait_left)
			wait_left -= w
			remaining -= w
			continue
		if orders.is_empty():
			chain_open = false
			break
		if not route_active and not activate_order():
			chain_open = false
			break
		if waypoint >= cells.size():
			if not next_segment(): complete_order()
			continue
		if not choose_step(): continue
	# Complete orders on the arrival tick, rather than one physics tick later.
	if not in_step and route_active and waypoint >= cells.size() and segments.is_empty():
		complete_order()
	elapsed += delta
	if convert_ms >= 0.0: convert_ms += delta * 1000.0
	var depth := preload("res://core/map_data.gd").depth(position.y) + 1 # 0x536400: ground 1x1 non-hero depth bias (M-2: MapData.depth, 256 maps)
	if depth != z_index: z_index = depth      # P-3: the setter always reaches the rendering server
	update_sprite()
	if _drawn or _wants_draw(): queue_redraw()   # P-3: a unit that drew nothing and has nothing to draw is not redrawn

# Port of the waypoint rules in 0x430340: adjacent-waypoint shortcut, then wait, detour or stop
# when the next cell is held. Returns true when a step started.
func choose_step() -> bool:
	for k in range(1, mini(5, cells.size() - waypoint)):
		if navigator.chebyshev(cells[waypoint + k], cell) < 2:
			waypoint += k
			break
	var next: Vector2i = cells[waypoint]
	# Guard (the original's routes never trigger it): a route cell that is not a neighbour is skipped or re-planned.
	if next == cell:
		waypoint += 1
		return false
	if not flying and navigator.chebyshev(next, cell) != 1:
		clear_route()
		return false
	if march_id >= 0 and march_hold():
		wait_left = WAIT_MS
		return false
	var blocker = navigator.air_occupant(next, self) if flying else navigator.occupant_extent(next, extent, self)
	var static_block: bool = false if flying else not navigator.passable_extent(next, extent, movement_type) # Only the accepted goal cell.
	if blocker == null and not static_block:
		start_step(next)
		return true
	# 0x51f8d0: an allied unit following a move order is transient; anything else is solid.
	var solid: bool = static_block or not blocker.is_moving()
	if not navigator.improved: return blocked_step(solid)
	if not static_block and not solid and swap_with(blocker, next): return true
	if navigator.improved and not flying and solid:
		var final := waypoint == cells.size() - 1 and segments.is_empty()
		if blocker != null and nudge(blocker):
			wait_left = WAIT_MS          # F2: the idle friend steps aside; keep the route
			return false
		if final and not orders[0].get("attack", false) and settle_near(next):
			return false                 # F2: the destination is held: take the nearest free cell instead of stopping short
	if waiting:
		waits += 1
		if waits < 5:
			wait_left = WAIT_MS
			return false
		if try_detour():
			waiting = false
			return false
		detour_failures += 1
		if detour_failures >= 100:
			if not activate_order(): return false
		waits = 0
		wait_left = WAIT_MS
		return false
	if solid:
		if waypoint == cells.size() - 1 and segments.is_empty():
			complete_order() # Final cell of the final segment held by a stationary unit: stop here.
			return false
		if try_detour(): return false
	waiting = true
	waits = 0
	wait_left = WAIT_MS
	return false

# Port of 0x430340's blocked branch (Read; the deadlock case is checked by tests/test_movement.gd). `waiting` is path
# state +0x3c == 2, `waits` the counter +0x3e, `detour_failures` the counter +0x3f. Returns true when a step started.
#   * the next waypoint ends a segment that is not the last one: wait up to 10 updates, then 0x42ff30 searches the next
#     chain segment from here (units ignored) and the unit waits again;
#   * already waiting: the 5th update tries a detour (0x4308b0). A success is checked again at once (0x42cb70): the step
#     starts if the cell is free, else the unit keeps waiting (an allied blocker; 0x42d090 returns no target). A failure
#     (no route, or the shared 100 ms clock) counts; the 100th in a row ends the order where the unit stands when the
#     segment is the last one (0x430340 returns 0 and 0x51f9b0 drops the order), else 0x42ff30 re-searches the segment;
#   * first block after a step: both counters restart (+0x3e = +0x3f = 0); only transient blockers: wait; a solid one
#     (0x42d2d0 / 0x51f8d0) on the final cell of the final segment: stop here, elsewhere detour at once.
func blocked_step(solid: bool) -> bool:
	if waypoint >= cells.size() - 1 and not segments.is_empty():
		if waiting:
			waits += 1
			if waits < 10:
				wait_left = WAIT_MS
				return false
		research_segment()
		return hold()
	if waiting:
		waits += 1
		if waits < 5:
			wait_left = WAIT_MS
			return false
		if try_detour(): return recheck_step()
		detour_failures += 1
		if detour_failures == 100:
			if segments.is_empty():
				complete_order()     # 0x430340 returns 0: the order ends, the unit stands where it is
				return false
			research_segment()
			detour_failures = 0
		return hold()
	waits = 0
	detour_failures = 0
	if not solid: return hold()
	if waypoint == cells.size() - 1 and segments.is_empty():
		complete_order()             # final cell of the final segment held by a stationary unit: stop here
		return false
	if try_detour(): return recheck_step()
	return hold()

## Path state 2 (waiting) for one update, counter +0x3e from 0.
func hold() -> bool:
	waiting = true
	waits = 0
	wait_left = WAIT_MS
	return false

## 0x430340 after a successful 0x4308b0: the spliced next cell is tested again (0x42cb70), no shortcut.
func recheck_step() -> bool:
	var next: Vector2i = cells[waypoint]
	if navigator.chebyshev(next, cell) == 1 and _layer_free(next):
		start_step(next)
		return true
	return hold()

## 0x42ff30 from the blocked branch: the next chain segment is searched from the unit's cell (f <= 150, units ignored)
## and replaces what is left of the current one. The port plans the chain up front, so its end is the next stored
## segment's last cell. A failed search leaves the route as it is.
func research_segment():
	if flying: return
	while not segments.is_empty() and (segments[0] as Array).is_empty(): segments.pop_front()
	if segments.is_empty(): return
	var found: Dictionary = navigator.search(cell, (segments[0] as Array)[-1], navigator.SEGMENT_LIMIT, false, self, extent, movement_type)
	if not found.ok: return
	segments.pop_front()
	cells.assign(found.cells)
	waypoint = 0
	path = PackedVector2Array([position])
	for c in cells: path.append(navigator.center(c))
	for s in segments:
		for c in s: path.append(navigator.center(c))

## 0x42cb70 on the unit's own layer (0x42ca40: type 1 the air layer): no material 9 / terrain block and no other unit.
func _layer_free(c: Vector2i) -> bool:
	if flying: return navigator.air_occupant(c, self) == null and navigator.passable_extent(c, 1, 1)
	return navigator.occupant_extent(c, extent, self) == null and navigator.passable_extent(c, extent, movement_type)

# 0x4308b0: sample free rejoin waypoints ahead, search a unit-aware route capped at f <= 90.
# G-3: flyers too (COMBAT_RESEARCH.md "G-3" 1). 0x4308b0 and its caller 0x430340 have no flyer branch: the follower of every
# order type (0x51ea20 / 0x51f9b0) calls the same 0x430340, whose cell tests (0x42cb70) and the detour search (0x42f650 mode
# 1, f <= 90 -> 0x42e180) take the unit's movement type, which 0x42ca40 maps to the air layer for type 1. So a flyer blocked
# by a flyer waits, detours round it on the air layer through the shared 100 ms gate, and stops after 100 failures (Read;
# the air-layer unit-aware search is Emulated, tests/flyer_detour_fixtures.json).
func try_detour() -> bool:
	var now_ms := int(elapsed * 1000.0)
	if flying and navigator.improved: return false   # modern rules: flyers keep waiting for the flyer ahead (unchanged)
	if navigator.improved: return try_detour_improved(now_ms)
	now_ms = int(clock_ms)          # the shared clock, not this unit's own `elapsed` (which starts at 0 for a new unit)
	if now_ms < navigator.next_detour_ms: return false
	navigator.next_detour_ms = now_ms + DETOUR_INTERVAL_MS
	var rejoin: Array[int] = []
	var i := waypoint + 1
	while i < cells.size():
		if _layer_free(cells[i]):
			rejoin.append(i)
			i += clampi(cells.size() - i - 2, 0, 8)
		i += 1
	if rejoin.is_empty():
		if not segments.is_empty(): return false   # 0x4308b0: no free rejoin cell and more segments to come: fail
		rejoin.append(cells.size() - 1)
	for index in rejoin:
		var found: Dictionary = navigator.search(cell, cells[index], DETOUR_LIMIT, true, self, 1 if flying else extent, 1 if flying else movement_type)
		if found.ok:
			var spliced: Array[Vector2i] = []
			spliced.assign(found.cells)
			spliced.append_array(cells.slice(index + 1))
			# B1-7: the unit stands on the last route cell it can rejoin (a search to its own cell gives no cells): no
			# detour (Provisional: 0x4308b0's handling of that case is not traced); an empty route would leave no next cell.
			if spliced.is_empty(): continue
			cells = spliced
			route_active = true
			waypoint = 0
			path = PackedVector2Array([position])
			for c in cells: path.append(navigator.center(c))
			return true
	return false

# ------------------------------------------------------------------------------------------------ modern movement
# DELIBERATE MODERN CHANGES (navigation.gd `improved`, COMPLAINTS_AND_FIXES.md F1/F2); never reached in the original mode.

## F1: hold while this member leads the slower quarter of its march by more than MARCH_HOLD route cells.
func march_hold() -> bool:
	if waypoint >= marks.size() or march_wait_ms >= MARCH_PATIENCE_MS: return false
	var mine: int = marks[waypoint]
	if mine <= navigator.march_min(march_id, unit_id) + navigator.MARCH_HOLD: return false
	if blocking_someone(): return false                       # never hold up a unit queued behind this one
	march_wait_ms += WAIT_MS
	return true

## Another unit next to this one whose next route cell is this unit's cell.
func blocking_someone() -> bool:
	for step in navigator.SEARCH_ORDER:
		var other = navigator.occupant(cell + step, self)
		if other == null or other.in_step or other.cells.is_empty() or other.waypoint >= other.cells.size(): continue
		if other.cells[other.waypoint] == cell: return true
	return false

## F2: one detour clock per unit (the original shares one detour per 100 ms among all units), and the detour search
## counts moving units as dearer cells instead of walls.
func try_detour_improved(now_ms: int) -> bool:
	if now_ms < next_own_detour_ms: return false
	# Back-off: each failed attempt doubles the wait (250 ms .. 2 s); a success resets it.
	next_own_detour_ms = now_ms + mini(OWN_DETOUR_INTERVAL_MS << mini(detour_misses, 3), 2000)
	detour_misses += 1
	var rejoin: Array[int] = []
	var i := waypoint + 1
	while i < cells.size() and rejoin.size() < 2:
		if navigator.occupant_extent(cells[i], extent, self) == null and navigator.passable_extent(cells[i], extent, movement_type): rejoin.append(i)
		i += 2
	rejoin.append(cells.size() - 1)
	for index in rejoin:
		var found: Dictionary = navigator.detour_search(cell, cells[index], self, extent, movement_type)
		if not found.ok: continue
		var spliced: Array[Vector2i] = []
		spliced.assign(found.cells)
		spliced.append_array(cells.slice(index + 1))
		if spliced.is_empty(): continue                          # B1-7: rejoin at the unit's own last cell, as above
		if not marks.is_empty():
			var held: int = marks[waypoint - 1] if waypoint > 0 else marks[0] - 1
			var new_marks := PackedInt32Array()
			for c in found.cells: new_marks.append(held)
			new_marks.append_array(marks.slice(index + 1))
			marks = new_marks
		cells = spliced
		route_active = true
		waypoint = 0
		detour_misses = 0
		path = PackedVector2Array([position])
		for c in cells: path.append(navigator.center(c))
		return true
	return false

## F2: two units of the same owner that each want the other's cell trade places in one step (otherwise they wait on
## each other until a detour succeeds, which can take long in a crowd).
func swap_with(other, next: Vector2i) -> bool:
	if extent > 1 or other.extent > 1 or other.flying or other.owner_id != owner_id or other.in_step or other.dying: return false
	if other.cells.is_empty() or other.waypoint >= other.cells.size() or other.cells[other.waypoint] != cell: return false
	if other.orders.is_empty() or other.wait_left > 0.0 and other.march_hold(): return false
	var mine := cell
	start_step(next)                     # occupies `next` (the other's cell) and frees ours
	other.start_step(mine)               # the other leaves `next` (still recorded as ours) and takes ours
	other.wait_left = 0.0
	return true

## F2: an idle unit of the same owner standing on the route steps to a free neighbouring cell off the route.
func nudge(blocker) -> bool:
	if not is_instance_valid(blocker) or blocker.owner_id != owner_id or blocker.dying or blocker.inside_building: return false
	if blocker.is_moving() or not blocker.orders.is_empty() or not blocker.anim.is_empty() or blocker.convert_ms >= 0.0: return false
	var now_ms := int(elapsed * 1000.0)
	if now_ms - blocker.nudged_ms < NUDGE_INTERVAL_MS: return false
	var ahead := {}
	for k in range(waypoint, mini(cells.size(), waypoint + 4)): ahead[cells[k]] = true
	var best := Vector2i(-1, -1)
	var best_score := 1 << 20
	for step in navigator.SEARCH_ORDER:
		var c: Vector2i = blocker.cell + step
		if c == cell or ahead.has(c): continue
		if not navigator.enterable_extent(c, blocker.extent, blocker.movement_type) or navigator.occupant_extent(c, blocker.extent, blocker) != null: continue
		var score: int = 0 if step.x == 0 or step.y == 0 else 1
		if score < best_score:
			best_score = score
			best = c
	if best.x < 0: return false
	blocker.nudged_ms = now_ms
	var target: Vector2 = navigator.center(best)
	blocker.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": blocker.base_speed,
		"individual": true, "nudge": true}, "replace")
	return true

## F2: the last cell is held by something that will not move: walk to the nearest free cell within three cells.
func settle_near(goal: Vector2i) -> bool:
	var alt: Vector2i = navigator.free_cell_near(goal, self, extent, movement_type)
	if alt.x < 0 or alt == cell or navigator.chebyshev(alt, goal) > 3: return false
	var found: Dictionary = navigator.detour_search(cell, alt, self, extent, movement_type)
	if not found.ok or found.cells.is_empty(): return false
	cells.assign(found.cells)
	marks = PackedInt32Array()
	waypoint = 0
	path = PackedVector2Array([position])
	for c in cells: path.append(navigator.center(c))
	return true

func start_step(next: Vector2i):
	if march_id >= 0 and waypoint < marks.size(): navigator.march_report(march_id, unit_id, marks[waypoint])
	var speed: int = int(orders[0].speed)
	var timing := step_ms(speed)
	var new_direction := direction_of(next - cell)
	var turned := new_direction != direction
	# AHKX type flags 0x10d allow turning both from walk (0x100) and from rest (0x1).
	turn_entries = turn_sequence(direction, new_direction)
	step_frame_ms = float(timing.frame)
	turn_time = float(turn_entries.size() * timing.frame)
	# Measured on the running original (LIVE_COMPARISON.md, speeds 4 and 10): a step ends on the 25 ms game update at or
	# after its last entry is due, and the next step starts there: 416 -> 425 ms, 592 -> 600 ms. Turn entries are taken
	# on the same timeline (Provisional: turns were not measured apart).
	step_duration = on_update(turn_time + float(timing.step))
	direction = new_direction
	# Continue the cycle only when still in walk state; otherwise take the shared random table.
	walk_phase = (walk_frame + 1) % WALK_FRAMES if chain_open else next_random_phase()
	# Presentation: the same phase rule in the unit's own walk sheet (continue from the last own frame, else the table value).
	var own_frames := own_walk_frames()
	own_walk_phase = (own_walk_frame + 1) % own_frames if chain_open else walk_phase % own_frames
	step_diagonal = (new_direction & 1) == 1
	chain_open = false
	step_from = navigator.center(cell)
	step_to = navigator.center(next)
	# Height (uphill bob, speed -8/+8) is not modelled by the rebuild route, so no bob is applied.
	step_offsets = walk_offsets(Vector2i((step_to - step_from).round()), walk_phase)
	step_time = 0.0
	in_step = true
	waiting = false
	waits = 0
	# The original occupies the target cell when the step starts.
	var from_cell := cell
	navigator.release(self, cell)
	cell = next
	navigator.occupy(self, cell)
	waypoint += 1
	if sight_step.is_valid(): sight_step.call(owner_id, from_cell, next, turned)
	if order_step.is_valid(): order_step.call(unit_id, next)

# Index of the latest due walk entry, or -1 during turn entries. Entry k is due at turn + k frames.
func step_entry() -> int:
	if step_time < turn_time - 0.000001: return -1
	return mini(int((step_time - turn_time) / step_frame_ms + 0.000001), WALK_FRAMES)

func own_walk_frames() -> int:
	var sheet := _sheet(1)
	return maxi(1, int(sheet.frame_count)) if not sheet.is_empty() else WALK_FRAMES

# Draws one ANI slot of the unit's own sheet in the owner's colour (0x538660 -> 0x487f20 with the owner's colour word).
func show_frame(slot: int, row: int, column: int):
	var sheet := _sheet(slot)
	if sheet.is_empty():
		sheet = _sheet(0) # no sheet for this slot (e.g. animals have no f): stand
		column = 0
	if sheet.is_empty(): return
	shown_slot = int(sheet.get("ani_slot", slot))
	# Performance (P-2): the same sheet, row, column and colour as last time leave the sprite as it is.
	var shown_row := clampi(row, 0, int(sheet.rows) - 1)
	var colour := ArtData.player_colour(owner_id)
	if is_same(sheet, _shown_sheet) and shown_row == _shown_row and column == _shown_column and colour == _shown_colour 			and sprite.texture != null:
		return
	sprite.texture = ArtData.texture(sheet.texture)
	sprite.region_rect = ArtData.frame_rect(sheet, shown_row, column)
	sprite.offset = ArtData.offset(sheet)
	sprite.material = ArtData.team_material(sheet, colour)
	_shown_sheet = sheet
	_shown_row = shown_row
	_shown_column = column
	_shown_colour = colour

# Frame of the unit's own `slot` sheet for an animation index the combat controller counted in `frames` entries
# (f: index == frames shows frame 0, as the last f entry does; d: the last frame is held).
func own_frame(slot: int, index: int, frames: int) -> int:
	var sheet := _sheet(slot)
	if sheet.is_empty(): return 0
	var count := int(sheet.frame_count)
	if frames <= 0 or index >= frames: return 0 if slot == 2 else count - 1
	return clampi(index * count / frames, 0, count - 1)

# Performance (P-3): the art look-ups of one art type, asked several times per unit and frame (ArtData.unit_sheet walks four
# dictionaries and builds a key string each time). The records are the same objects ArtData returns (art.json is loaded
# once), so show_frame's is_same test is unchanged. Rebuilt when art_type changes.
var _art_cache_type := ""
var _art_sheets: Dictionary = {}          # slot -> ArtData.unit_sheet(art_type, slot)
var _art_entries := PackedInt32Array()    # ArtData.walk_entries(art_type, false / true)

func _art_cache():
	_art_cache_type = art_type
	_art_sheets = {}
	_art_entries = PackedInt32Array([ArtData.walk_entries(art_type, false), ArtData.walk_entries(art_type, true)])

func _sheet(slot: int) -> Dictionary:
	if _art_cache_type != art_type: _art_cache()
	var sheet = _art_sheets.get(slot)
	if sheet == null:
		sheet = ArtData.unit_sheet(art_type, slot)
		_art_sheets[slot] = sheet
	return sheet

func _walk_entries(diagonal: bool) -> int:
	if _art_cache_type != art_type: _art_cache()
	return _art_entries[1 if diagonal else 0]

## _draw draws something: a ring, a health strip or the order marker (the conditions _draw tests first).
func _wants_draw() -> bool:
	return selected or always_health or unit_id == marker_unit

var _drawn := false                       # P-3: the last _draw had something to draw

func update_sprite():
	if sprite == null or ArtData.data().is_empty(): return # not in the tree yet (headless tests) or no import
	if not anim.is_empty():
		var sheet_name: String = anim.get("sheet", "")
		var slot: int = int(anim.get("slot", ArtData.SLOT_BY_SUFFIX.get(sheet_name.trim_suffix(".RLE").substr(4), 2)))
		var column: int
		if anim.has("index"):
			column = own_frame(slot, int(anim.index), int(anim.frames))
		else:
			# Callers without "index" count frames on the Swordsman sheet (16 f / 13 d frames).
			var base := ArtData.unit_sheet("AHKX", slot)
			column = own_frame(slot, int(anim.frame), int(base.get("frame_count", 1))) if not base.is_empty() else 0
		show_frame(slot, int(anim.row), column)
		return
	var row := direction
	if in_step:
		var entry := step_entry()
		if entry < 0:
			# Turn entries carry slot byte 0: idle sheet, column 0 or the half-turn column 1.
			var turn: Vector2i = turn_entries[mini(int(step_time / step_frame_ms + 0.000001), turn_entries.size() - 1)]
			show_frame(0, turn.x, turn.y)
			return
		walk_frame = (walk_phase + mini(entry, WALK_FRAMES - 1)) % WALK_FRAMES
		# The rebuild keeps 16 timed entries per step (movement code unchanged); entry e shows the original's entry
		# i = e * (n - 1) / 15 of n = ArtData.walk_entries (first and last coincide), frame (p + i) mod frames.
		var n := _walk_entries(step_diagonal)
		var i := mini(entry, WALK_FRAMES - 1) * (n - 1) / (WALK_FRAMES - 1)
		own_walk_frame = (own_walk_phase + i) % own_walk_frames()
		show_frame(1, row, own_walk_frame)
	elif chain_open:
		show_frame(1, row, own_walk_frame) # Completion entry leaves walk state and frame untouched while a step is pending.
	elif convert_ms >= 0.0 and convert_frames() > 0:
		var count := convert_frames()
		var entry := int(fmod(convert_ms, count * CONVERT_FRAME_MS) / CONVERT_FRAME_MS)
		if entry >= count - 1:
			direction = 4 # the shown entry's row stays the unit's facing (0x5394a0)
			show_frame(0, 4, 0)
		else:
			show_frame(6, 0, entry)
	else:
		show_frame(0, row, 0)

func hit_rect() -> Rect2:
	if inside_building or dying or removed or not visible: return Rect2(Vector2(-1.0e9, -1.0e9), Vector2.ZERO)
	# The drawn frame's opaque bounds, a few pixels wider (follows the art, so large and mounted units are picked where
	# they are drawn). The original's unit pick is Open; its building hit test 0x487c60 uses the drawn frame's opaque
	# pixels. Without imported art (headless tests) the earlier ground-projected box stays.
	if sprite != null and sprite.texture != null:
		var used := opaque_bounds(sprite.texture, sprite.region_rect)
		if used.has_area(): return Rect2(position + sprite.offset + used.position, used.size).grow(PICK_MARGIN)
	return Rect2(position - Vector2(22, 48), Vector2(44, 62))

const PICK_MARGIN := 4.0
static var _sheet_images: Dictionary = {}     # texture -> Image (decoded once per sheet)
static var _frame_bounds: Dictionary = {}     # "texture rid@region" -> opaque Rect2 within the frame

static func opaque_bounds(texture: Texture2D, region: Rect2) -> Rect2:
	var key := "%d@%s" % [texture.get_rid().get_id(), region]
	if _frame_bounds.has(key): return _frame_bounds[key]
	if not _sheet_images.has(texture): _sheet_images[texture] = texture.get_image()
	var image: Image = _sheet_images[texture]
	var bounds := Rect2()
	if image != null:
		var r := Rect2i(region).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if r.has_area(): bounds = Rect2(image.get_region(r).get_used_rect())
	_frame_bounds[key] = bounds
	return bounds

## Selection marker and health strip, parity pass 4 (Read: the unit draw 0x538660 at 0x53883d..0x538de4, not decompiled;
## the ring tables are data). A selected unit (+0x12) gets, from BM_SELECTIONRINGS (XCG bitmap 0x66, SelectionRings.bmp):
## * the ring of size s = ANI word +0x14 of the shown slot (slot 0 for ARM type flag 0x20, 0x6e401c), source
##   (x 0x611b0c / 0x611b28 [s] for own / other, y 0x611b44 / 0x611b60 [s]), size (0x611b7c, 0x611b98 [s]); an own unit of
##   size 0 or 1 adds (0x611bb4, 0x611bd8 [rank]) with rank = 8 for a hero (+0xb4), else min(+0x3c, 8): the hero's ring is
##   the yellow one at (330, 408). Its top-left is the unit pixel (+0x4c / +0x4e) minus the slot's ANI words +0x10 / +0x12.
## * the group digit: an own unit in a control group (0x425470, the first of groups 0..9) shows digit g of SkillIcons.bmp
##   (bitmap 0x141, 5x7 at ((g + 0x20) * 5, 0x21)) at the ring's bottom right (x + w - 5, y + h - 7).
## * the health strip (0x61, row * 7, 44 x 7), row = 15 - life * 15 / max clamped, 1 pixel under the ring, centred on it:
##   (x + w / 2 - 22, y + h + 1). An own unit with mana (0x51b2c0: 7 * mana / max, a hero's from its record) overlays the
##   mana strip (0x8e, (23 - v) * 7, 32 x 7) at the same point (a hero's mana: combat.gd _regenerate_mana).
## Units without imported art keep a plain circle (headless tests).
const RING_X_OWN := [0, 0, 0, 0, 0, 422, 722]
const RING_X_OTHER := [218, 218, 218, 218, 218, 422, 722]
const RING_Y_OWN := [0, 33, 82, 155, 260, 0, 0]
const RING_Y_OTHER := [0, 33, 82, 155, 260, 228, 301]
const RING_W := [44, 65, 97, 141, 197, 300, 396]
const RING_H := [33, 49, 73, 105, 147, 228, 301]
const RANK_DX := [0, 0, 66, 132, 198, 264, 264, 264, 330]
const RANK_DY := [0, 408, 408, 408, 408, 408, 408, 408, 408]
static var local_player := 0
var shown_slot := 0
var _shown_sheet = null                   # P-2: the frame show_frame last put on the sprite
var _shown_row := -1
var _shown_column := -1
var _shown_colour := -1
var ring_rank := 0          # 8 for a hero, else min(+0x3c, 8) (set by main.gd)
var group_digit := -1       # 0x425470 for an own unit, set by main.gd
var mana_level := -1        # 0x51b2c0: 7 * mana / max (0..7) for a unit with mana, -1 without (set by main.gd)

## 0x51b2c0: the mana strip level, -1 (0xffff) when the maximum is below 1.
static func mana_level_of(mana: int, maximum: int) -> int:
	if maximum < 1: return -1
	return clampi(mana * 7 / maximum, 0, 7)

## Source rectangle of the ring of size `size` (0x611b0c.. tables); `rank` applies to own rings of size 0 / 1 only.
static func ring_source(size: int, own: bool, rank: int = 0) -> Rect2:
	var s := clampi(size, 0, 6)
	var r := Rect2(RING_X_OWN[s] if own else RING_X_OTHER[s], RING_Y_OWN[s] if own else RING_Y_OTHER[s], RING_W[s], RING_H[s])
	if own and s <= 1: r.position += Vector2(RANK_DX[clampi(rank, 0, 8)], RANK_DY[clampi(rank, 0, 8)])
	return r

## ANI words +0x10 / +0x12 (ring offset) and +0x14 (ring size) of a sheet record.
static func ring_words(sheet: Dictionary) -> Dictionary:
	var w: Dictionary = sheet.get("ani_unknown_words", {})
	return {"offset": Vector2(int(w.get("0x10", 0)), int(w.get("0x12", 0))), "size": int(w.get("0x14", 0))}

## The building draw 0x53ae40 at 0x53b014..0x53b2a9 (Read, not decompiled): a selected (+0x12) or marked (+0x14a) building
## gets the ring of size = its shown slot's ANI word +0x14 (tables 0x611bfc.. = the unit tables' values, no rank), green
## when its owner (+0x88) is the local player, else red, top-left at the pixel minus ANI words +0x10 / +0x12. Unless marked,
## the 76 x 7 strip (0x8e, row * 7) follows 1 pixel under the ring at x + w / 2 - 0x26, row = min(16 - (life * 100 / max) / 6, 15).
## The ring is drawn before the building's sheet (0x53b2ae continues with the sheet), so the building nodes keep it in a
## child drawn behind them; `painter` is called with the layer.
class MarkerLayer extends Node2D:
	var painter: Callable
	func _ready():
		show_behind_parent = true
	func _draw():
		if painter.is_valid(): painter.call(self)

static func draw_building_marker(canvas: CanvasItem, record: Dictionary, own: bool, life: int, maximum: int, marked: bool):
	var sheet := rings_texture()
	if sheet == null or record.is_empty(): return
	var words := ring_words(record)
	var ring := ring_source(int(words.size), own)
	var at: Vector2 = -words.offset
	canvas.draw_texture_rect_region(sheet, Rect2(at, ring.size), ring)
	if marked: return
	var row := 16 - mini((life * 100 / maxi(maximum, 1)) / 6, 16)
	canvas.draw_texture_rect_region(sheet, Rect2(at + Vector2(int(ring.size.x) / 2 - 0x26, ring.size.y + 1), Vector2(0x4c, 7)),
		Rect2(0x8e, mini(row, 15) * 7, 0x4c, 7))

static var _digits: Texture2D
static func digits_texture() -> Texture2D:
	if _digits == null and Assets.exists("ui_bm_BM_SKILLICONS.png"): _digits = Assets.texture("ui_bm_BM_SKILLICONS.png")
	return _digits
static var _rings: Texture2D
static var _rings_loaded := false

static func rings_texture() -> Texture2D:
	if not _rings_loaded:
		_rings_loaded = true
		if Assets.exists("ui_x_SelectionRings.png"): _rings = Assets.texture("ui_x_SelectionRings.png")
	return _rings

## Parity pass 3: the order marker of 0x49c240 (Read). For the selected head unit 0x49d3b0 lists its orders; a conversion
## (order 7 running, 0xc queued; 0x49d8c0) is marked at the unit's sprite centre by a 32x32 icon of SelectionRings.bmp at
## (0x1a8, 0x1eb + 32 row), its top-left 16 pixels up and left of the point, over a pulsing square. The phase (+0x1a263a)
## steps every 100 ms through 0..15; t = phase, or 16 - phase above 8; row 0 for t 0..2 and 7..8, 1 for t 3 / 6, 2 for 4 / 5.
## Shown while Shift or Alt is held (0x41e320 -> 0x49c110) and for 500 ms after an order (0x49c150). main.gd sets the unit.
const MARKER_SOURCE := {7: Vector2(0x1a8, 0x1eb), 6: Vector2(0x188, 0x1eb), 0x11: Vector2(0x1c8, 0x1eb)}
static var marker_unit := -1
static var marker_type := 0
static var marker_phase := 0

static func marker_row(phase: int) -> int:
	var t := 16 - phase if phase > 8 else phase
	if t == 3 or t == 6: return 1
	if t == 4 or t == 5: return 2
	return 0

## 0x4d7710: strip row for the life fraction.
static func health_row(life: int, maximum: int) -> int:
	if maximum <= 0: return 0
	return clampi(15 - (life * 15) / maximum, 0, 15)

func _draw():
	_drawn = _wants_draw()
	if selected and not dying:
		var sheet := rings_texture()
		var record := ArtData.unit_sheet(art_type, 0 if int(ArtData.unit(art_type).get("type_flags_0x104", 0)) & 0x20 else shown_slot)
		if sheet != null and not record.is_empty():
			var own := owner_id == local_player
			var words := ring_words(record)
			var ring := ring_source(int(words.size), own, ring_rank)
			var at: Vector2 = -words.offset
			draw_texture_rect_region(sheet, Rect2(at, ring.size), ring)
			var digits := digits_texture()
			if own and group_digit >= 0 and digits != null:
				draw_texture_rect_region(digits, Rect2(at + ring.size - Vector2(5, 7), Vector2(5, 7)), Rect2((group_digit + 0x20) * 5, 0x21, 5, 7))
			if max_hp > 0:
				var strip_at: Vector2 = at + Vector2(int(ring.size.x) / 2 - 22, ring.size.y + 1)
				draw_texture_rect_region(sheet, Rect2(strip_at, Vector2(44, 7)), Rect2(0x61, health_row(hp, max_hp) * 7, 44, 7))
				if own and mana_level >= 0:
					draw_texture_rect_region(sheet, Rect2(strip_at, Vector2(32, 7)), Rect2(0x8e, (7 - mana_level + 0x10) * 7, 32, 7))
		else:
			draw_arc(Vector2.ZERO, 16, 0, TAU, 24, Color("29ff00") if owner_id == local_player else Color("ff0000"), 1)
	elif always_health and not dying and max_hp > 0 and not inside_building:
		# DELIBERATE MODERN CHANGE (modern_rules.gd "HealthBars", F9): the selected unit's strip on every unit, no ring.
		var sheet := rings_texture()
		var record := ArtData.unit_sheet(art_type, 0 if int(ArtData.unit(art_type).get("type_flags_0x104", 0)) & 0x20 else shown_slot)
		if sheet != null and not record.is_empty():
			var words := ring_words(record)
			var ring := ring_source(int(words.size), owner_id == local_player, ring_rank)
			var strip_at: Vector2 = -words.offset + Vector2(int(ring.size.x) / 2 - 22, ring.size.y + 1)
			draw_texture_rect_region(sheet, Rect2(strip_at, Vector2(44, 7)), Rect2(0x61, health_row(hp, max_hp) * 7, 44, 7))
	if unit_id == marker_unit and MARKER_SOURCE.has(marker_type) and not dying:
		var sheet := rings_texture()
		var r := hit_rect()
		if sheet != null and r.size.x > 0:
			var centre := r.get_center() - position
			draw_texture_rect_region(sheet, Rect2(centre - Vector2(16, 16), Vector2(32, 32)),
				Rect2(MARKER_SOURCE[marker_type] + Vector2(0, 32 * marker_row(marker_phase)), Vector2(32, 32)))

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the unit's orders, route, step and animation state, its place and visibility. The navigator and the
## step callbacks are the scene's (main.gd restore_unit sets them); the static walk-phase counter is saved by main.gd.
## shown_slot is the drawn sheet only (set again when the restored unit draws its first frame).
const _SAVE_SKIP := ["navigator", "sprite", "sight_step", "order_step", "shown_slot", "_shown_sheet", "_shown_row", "_shown_column", "_shown_colour",
	"_art_cache_type", "_art_sheets", "_art_entries", "_drawn", "_synced_position", "_synced_cell", "_synced_navigator"]

func save_state(_refs = null) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, _SAVE_SKIP)
	s["@position"] = position
	s["@visible"] = visible
	s["@modulate"] = modulate
	return s

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state, _SAVE_SKIP)
	position = state["@position"]
	visible = state["@visible"]
