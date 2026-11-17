extends RefCounted
## Original missile flight (milestone 11, EFFECTS_RESEARCH.md section 2). Ported from the missile class (vtable 0x5eafdc):
## the initialiser 0x53df60 (+0x58), the per-id table 0x53f180, the path builder 0x541120, the placement 0x541d40 and the
## flight step 0x53fbc0 (+0x18). Emulated: tests/missile_fixtures.json (tools/emulate_missiles.py) runs the unmodified
## executable for 1,720 initialisations and 260 whole flights; tests/test_missiles.gd compares this file case by case.
## Read: the impact 0x5427e0 (damage order, elevation table, arrow-versus-building divisor, impact sounds).

const TYPES := {                    # 0x53f180: flags +0x160, trail +0x680, animation frames +0x682, facings +0x684
	"EMA0": {"flags": 0x82, "trail": 5, "frames": 1, "facings": 16},     # arrow (Squire, Dwarven Tower)
	"EMM0": {"flags": 0x24, "trail": 5, "frames": 1, "facings": 16},     # Swarm Tower shot
	# Playtest 2026-11-12 (Liche fireballs flew as arrows): the rest of 0x53f180's switch, Read. Defaults trail 0, frames 1,
	# facings 16; the particle kinds (EMM1 / EMM2 / EMM4 flags 0x2021, EMF1..EMF6 0x21 with +0x82b) and the unit-shaped
	# shots (ACSH, ACCO, AOSX) are not in this table and keep the arrow (Open).
	"EMA1": {"flags": 0x82, "trail": 5, "frames": 1, "facings": 16},
	"EMAP": {"flags": 0x82, "trail": 5, "frames": 1, "facings": 16},
	"EMA2": {"flags": 0x82, "trail": 5, "frames": 3, "facings": 16},
	"EMFP": {"flags": 0x82, "trail": 5, "frames": 3, "facings": 16},
	"EMA3": {"flags": 0x224, "trail": 0, "frames": 1, "facings": 16},
	"EMA4": {"flags": 0x222, "trail": 0, "frames": 1, "facings": 16},
	"EMA6": {"flags": 0x222, "trail": 0, "frames": 1, "facings": 16},
	"EMA5": {"flags": 0x42, "trail": 5, "frames": 1, "facings": 16},
	"EMC0": {"flags": 0x44, "trail": 5, "frames": 1, "facings": 4},      # +0x67e = 1
	"EMC1": {"flags": 0x510, "trail": 5, "frames": 1, "facings": 4},     # +0x67e = 1
	"EMF0": {"flags": 0x24, "trail": 5, "frames": 1, "facings": 16},     # fireball (Liche, AUMX ...)
	"EMM5": {"flags": 0x24, "trail": 5, "frames": 1, "facings": 16},
	"EMM3": {"flags": 0x22, "trail": 0, "frames": 1, "facings": 16},
	"EMS0": {"flags": 0x222, "trail": 0, "frames": 1, "facings": 16},
	"EMTF": {"flags": 0x110, "trail": 5, "frames": 1, "facings": 16},
	"EMTM": {"flags": 0x110, "trail": 5, "frames": 1, "facings": 16},
	"EMIS": {"flags": 0x22, "trail": 0, "frames": 8, "facings": 1},
	"EMIF": {"flags": 0x224, "trail": 0, "frames": 8, "facings": 1},
}
const DX := [0, 1, 1, 1, 0, -1, -1, -1]       # 0x611e20 (8 directions, 0 = north, clockwise)
const DY := [-1, -1, 0, 1, 1, 1, 0, -1]       # 0x611e40
const ACC_UNIT := [1, 10, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 78, 81, 84, 87, 90, 92, 94, 95, 96, 97, 98, 99]       # 0x611294
const ACC_BUILDING := [10, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 78, 81, 84, 87, 90, 92, 94, 95, 96, 97, 98, 99, 99]   # 0x6114e0
const STEP_MS := [1200, 900, 800, 700, 600, 550, 525, 500, 475, 450, 430, 410, 390, 370, 350, 340, 330, 320, 310, 300, 290, 280,
	275, 270, 265, 260, 255, 250, 245, 240, 235, 230, 225, 220, 218, 216, 214, 212, 210, 208]                                   # 0x61178c
const ELEVATION_PERCENT := [20, 30, 40, 50, 60, 70, 80, 100, 120, 130, 140, 150, 200, 250, 300]                                # 0x611e60
## 0x5418a0: the angle of (dx, dy) in degrees against 16 bounds (0x5ea830 down to 0x5ea7b8) -> facing row.
const FACE_BOUNDS := [-168.75, -146.25, -123.75, -101.25, -78.75, -56.25, -33.75, -11.25, 11.25, 33.75, 56.25, 78.75, 101.25, 123.75, 146.25, 168.75]
const FACE_ROWS := [6, 14, 7, 15, 0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13]
## 0x52e790: missile ids whose damage to a building is divided by 16 (at least 1) unless 0x70d5c3[owner] is set.
const BUILDING_DIVISOR_IDS := ["EMA0", "EMA1", "EMA5", "EMM3", "EMS0", "EMAP", "EMA3", "EMA4", "EMFP", "EMA6", "EMM5"]
## 0x5427e0 -> 0x50f3e0(sound): Missile<n>.wav by id; unit target / building target.
## P-3 (Read, decompile 214821-215003): the whole switch, keyed by the missile's art +0x13c (presentation only: the sound
## of a hit; ids not listed, e.g. EMM1 / EMM2 / EMM4 / EMTF, play nothing). [object hit (not a building), building hit].
const IMPACT_SOUNDS := {"EMA0": [0, 18], "EMA1": [0, 18], "EMA2": [0, 18], "EMA3": [0, 18], "EMA4": [0, 18], "EMA5": [0, 18],
	"EMM0": [7, 25], "EMIS": [7, 25], "EMIF": [7, 25], "EMF0": [6, 24], "EMM5": [6, 24], "EMC0": [4, 22], "EMC1": [4, 22],
	"EMS0": [4, 22], "EMM3": [4, 22], "ACSH": [15, 33], "ACCO": [16, 34], "AOSX": [36, 35]}
const UNIT_FLAG_HIGH := 0x200000        # unit +0x1c0 bit 21 (flying); 0x40200000 = the two "tall" bits the probe tests
const UNIT_FLAGS_TALL := 0x40200000

static func tdiv(a: int, b: int) -> int:
	var q: int = absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

static func s16(v: int) -> int:
	v &= 0xffff
	return v - 0x10000 if v & 0x8000 else v

## 0x40a8f0: 8-way direction from a to b with the 2:1 slope test (same as UnitAI.direction).
static func direction(a: Vector2i, b: Vector2i) -> int:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var ax := absi(dx)
	var ay := absi(dy)
	if dx == 0: return 4 if dy > 0 else 0
	if dy == 0: return 2 if dx > 0 else 6
	if dx > 0 and dy > 0:
		if ay * 2 < ax: return 2
		return 4 if ax * 2 < ay else 3
	if dx < 0:
		if dy > 0:
			if ay * 2 < ax: return 6
			return 5 if ay <= ax * 2 else 4
		if ay * 2 < ax: return 6
		return 7 if ay <= ax * 2 else 0
	if ay * 2 < ax: return 2
	return 1 if ay <= ax * 2 else 0

static func facing16(x0: int, y0: int, x1: int, y1: int) -> int:
	var angle := rad_to_deg(atan2(float(y1 - y0), float(x1 - x0)))
	for i in FACE_BOUNDS.size():
		if angle < FACE_BOUNDS[i]: return FACE_ROWS[i]
	return 6

static func step_ms(speed: int) -> int:
	return STEP_MS[clampi(speed, 0, STEP_MS.size() - 1)]

## Accuracy (0x523ef0 for unit shooters, 0x52d9b0 for buildings); returns [accuracy, roll]. A building draws its roll
## here (one 1d100 of the match generator); a unit uses the roll it stored with its attack (+0x228).
static func accuracy(shooter: Dictionary, target: Dictionary, rng) -> Array:
	var c := int(shooter.combat)
	var sc: Vector2i = shooter.cell
	var tc: Vector2i = target.cell
	if target.kind == "unit":
		if absi(tc.x - sc.x) < 2 and absi(tc.y - sc.y) < 2: c = s16(c) >> 1
		c = c + tdiv(-int(target.speed), 6)
	c = s16(c)
	if shooter.kind == "unit":
		var acc: int = ACC_UNIT[clampi(c, 0, 25)] + (int(shooter.get("elevation", 0)) - int(target.get("elevation", 0))) * 10
		var bits := int(shooter.get("flags_ba", 0))
		if bits & 1: acc -= 20
		if bits & 4: acc -= 20
		if bits & 2: acc -= 20
		acc = 1 if acc < 1 else (acc if acc < 100 else 99)
		return [acc, int(shooter.roll)]
	var acc_b: int = ACC_BUILDING[0] if c < 0 else (ACC_BUILDING[c] if c < 26 else 99)
	return [acc_b, rng.roll(1, 100, 0)]

## 0x53df60 + 0x541120 + 0x541d40. shooter: kind ("unit" | "building"), owner, cell, rect [x, y, w, h] (the sprite
## rectangle +0x58..+0x5e), launch_offset (ARM +0x10c + 4 facing / BUI +0x76 + 4 direction; (0, 0) = rectangle centre),
## combat (unit: 0x51bd10(1); building: 0x52ae70(1)), roll (unit), flags_ba, high (flying), elevation. target: kind,
## cell, pixel (+0x4c - +0x96), moving (sprite +0x38 == 1), facing, speed (0x51c460(1)), high, elevation.
static func create(id: String, shooter: Dictionary, target: Dictionary, rng, time_ms: int, size := Vector2i(128, 128)) -> Dictionary:
	var t: Dictionary = TYPES.get(id, TYPES.EMA0)
	var flags: int = int(t.flags) | (0x1000 if target.kind == "unit" and bool(target.get("high", false)) else 0x800)
	var sc: Vector2i = shooter.cell
	var aim: Vector2i = target.cell
	var rect: Array = shooter.rect
	var off: Vector2i = shooter.get("launch_offset", Vector2i.ZERO)
	var launch := Vector2i((int(rect[2]) >> 1) + int(rect[0]), (int(rect[3]) >> 1) + int(rect[1])) if off.x == 0 else Vector2i(int(rect[0]) + off.x, int(rect[1]) + off.y)
	var aim_px: Vector2i = target.pixel
	var length := s16(int(sqrt(float((sc.x - aim.x) * (sc.x - aim.x) + (sc.y - aim.y) * (sc.y - aim.y))) + 0.5))   # fsqrt, + 0.5, __ftol
	length = maxi(1, length)
	var k := 6 if flags & 4 else (0xc if flags & 8 else (0xf if flags & 0x10 else 4))
	var n := clampi(length * k >> 2, 2, 80)
	# Lead on a walking unit (+0x75 == 1, +0x38 == 1): the flight time over its step time, along its facing.
	if target.kind == "unit" and bool(target.get("moving", false)) and not flags & 1:
		var duration := (25 if flags & 2 else 50) * n
		var step := step_ms(int(target.speed))
		var moved := s16(tdiv(duration, step))
		var f := int(target.facing)
		aim = Vector2i(s16(aim.x + moved * DX[f]), s16(aim.y + moved * DY[f]))
		aim_px += Vector2i(tdiv(duration * 32, step) * DX[f], tdiv(duration * 24, step) * DY[f])
		aim = Vector2i(clampi(aim.x, 0, size.x - 1), clampi(aim.y, 0, size.y - 1))
	# Accuracy: a miss moves the aim sideways (perpendicular, side by the roll's parity), more with distance and margin.
	var acc_roll := accuracy(shooter, target, rng)
	var missed: bool = int(acc_roll[0]) < int(acc_roll[1])
	if missed:
		var roll := int(acc_roll[1])
		var side := (direction(sc, aim) + (2 if roll & 1 else 6)) & 7
		var band := ((roll - int(acc_roll[0])) >> 5) + 1 + (length >> 2)
		if band == 1:
			aim_px += Vector2i(DX[side] * 8, DY[side] * 4)
		else:
			var cells := 1 if band <= 6 else 2
			var scale := mini(band, 8)
			aim += Vector2i(DX[side] * cells, DY[side] * cells)
			aim_px += Vector2i(DX[side] * 8 * scale, DY[side] * 6 * scale)
	aim = Vector2i(clampi(aim.x, 0, size.x - 1), clampi(aim.y, 0, size.y - 1))
	# 0x541120: n records from the source cell/launch pixel to the aim; "high" = shooter is a building or flies.
	var shooter_high: bool = shooter.kind == "building" or bool(shooter.get("high", false))
	var target_high: bool = flags & 0x1000 != 0
	var records: Array = []
	var prev := Vector2i(-99999, -99999)
	for i in range(1, n + 1):
		var c := Vector2i(tdiv((aim.x - sc.x) * i, n) + sc.x, tdiv((aim.y - sc.y) * i, n) + sc.y)
		var px := tdiv((aim_px.x - launch.x) * i, n) + launch.x
		var py := tdiv((aim_px.y - launch.y) * i, n) + launch.y
		var fresh := 0 if i - 1 < 1 or c == prev else 1
		var h := 2 if (shooter_high and i - 1 < n >> 1) or target_high else 0
		records.append([c.x, c.y, px, py, fresh, h, 0])
		prev = c
	if flags & 0xc0 and n > 4:
		var mag := absi(tdiv(((aim_px.y - launch.y) >> 1) - launch.x + aim_px.x, n))
		var lift := 0
		for i in n:
			var r: Array = records[i]
			if flags & 0x40:                     # low arc
				if i < tdiv(n, 5): lift -= mag >> 2; r[5] = 2 if shooter_high else 0
				elif i < tdiv(n * 2, 5): lift -= mag >> 3; r[5] = 2 if shooter_high else 1
				elif i < tdiv(n * 3, 5): r[5] = 2 if (shooter_high or target_high) else 1
				elif i < tdiv(n * 4, 5): lift += mag >> 3; r[5] = 2 if target_high else 1
				else: lift += mag >> 2; r[5] = 2 if target_high else 0
			else:                                # 0x80: arrow arc, heights 1..3
				if i < tdiv(n, 5): lift -= mag >> 1; r[5] = (1 if shooter_high else 0) + 1
				elif i < tdiv(n * 2, 5): lift -= mag >> 2; r[5] = 2
				elif i < tdiv(n * 3, 5): r[5] = 3
				elif i < tdiv(n * 4, 5): lift += mag >> 2; r[5] = 2
				else: lift += mag >> 1; r[5] = (1 if target_high else 0) + 1
			r[3] = int(r[3]) + s16(lift)
	if flags & 0x20:
		var f16 := facing16(int(records[0][2]), int(records[0][3]), int(records[n - 1][2]), int(records[n - 1][3]))
		for r in records: r[6] = f16
	else:
		for i in range(1, n):
			records[i][6] = facing16(int(records[i - 1][2]), int(records[i - 1][3]), int(records[i][2]), int(records[i][3]))
		records[0][6] = records[1][6]
	records[0][4] = 1
	var shooter_elevation := int(shooter.get("elevation", 0)) + (1 if shooter.kind == "building" else 0) + (1 if shooter.kind == "unit" and bool(shooter.get("high", false)) else 0)
	return {"id": id, "flags": flags, "trail": int(t.trail), "frames": int(t.frames), "steps": n, "length": length, "records": records,
		"index": 0, "next_ms": time_ms + (25 if flags & 2 else 50), "cell": Vector2i(int(records[0][0]), int(records[0][1])),
		"pixel": Vector2i(s16(int(records[0][2])), s16(int(records[0][3]))), "owner": int(shooter.owner), "aim": aim, "aim_pixel": aim_px,
		"launch": launch, "missed": missed, "accuracy": int(acc_roll[0]), "roll": int(acc_roll[1]), "shooter_elevation": shooter_elevation,
		"shooter_high": shooter_high, "impacts": [], "alive": true, "hard_stop": false}

## B5-1 (BATCH5_RESEARCH.md Open 1; Emulated: tests/batch5_meteor_fixtures.json "init", tools/emulate_batch5_meteor.py): the
## initialiser 0x53e960 (vtable +0x54, via 0x58bea0) as kind 0x23 calls it: no shooter (owner -1, +0x678 damage 0, no accuracy draw,
## shooter elevation 0), the source and the aim are cells (pixels their centres, 0x493940), id EMF0 with the art EMTF (0x53f180: flags
## 0x110 | 0x800, trail 5). The path 0x541120 with flag 0x100 (decompile 213548-213616): the high arc in sevenths, heights 2, 4, 5, 6,
## 5, 4, 2 and the last record 1.
static func create_sky(source: Vector2i, aim: Vector2i, time_ms: int, size := Vector2i(128, 128)) -> Dictionary:
	var t: Dictionary = TYPES.EMTF
	var flags: int = int(t.flags) | 0x800
	aim = Vector2i(clampi(aim.x, 0, size.x - 1), clampi(aim.y, 0, size.y - 1))
	var launch := Vector2i(source.x * 32 + 16, source.y * 24 + 12)
	var aim_px := Vector2i(aim.x * 32 + 16, aim.y * 24 + 12)
	var length := maxi(1, s16(int(sqrt(float((source.x - aim.x) * (source.x - aim.x) + (source.y - aim.y) * (source.y - aim.y))) + 0.5)))
	var n := clampi(length * 0xf >> 2, 2, 80)
	var records: Array = []
	var prev := Vector2i(-99999, -99999)
	for i in range(1, n + 1):
		var c := Vector2i(tdiv((aim.x - source.x) * i, n) + source.x, tdiv((aim.y - source.y) * i, n) + source.y)
		var px := tdiv((aim_px.x - launch.x) * i, n) + launch.x
		var py := tdiv((aim_px.y - launch.y) * i, n) + launch.y
		records.append([c.x, c.y, px, py, 0 if i - 1 < 1 or c == prev else 1, 2 if i - 1 < n >> 1 else 0, 0])
		prev = c
	var mag := absi(tdiv(((aim_px.y - launch.y) >> 1) - launch.x + aim_px.x, n))
	var lift := 0
	if n > 4:
		for i in n:
			var r: Array = records[i]
			var h := 0
			if i < tdiv(n, 7): lift -= mag * 2; h = 2
			elif i < tdiv(n * 2, 7): lift -= mag; h = 4
			elif i < tdiv(n * 3, 7): lift -= mag >> 1; h = 5
			elif i < tdiv(n * 4, 7): h = 6
			elif i < tdiv(n * 5, 7): lift += mag >> 1; h = 5
			elif i < tdiv(n * 6, 7): lift += mag; h = 4
			else: lift += mag * 2; h = 2
			r[3] = int(r[3]) + s16(lift)
			r[5] = h
	records[n - 1][5] = 1
	for i in range(1, n):
		records[i][6] = facing16(int(records[i - 1][2]), int(records[i - 1][3]), int(records[i][2]), int(records[i][3]))
	records[0][6] = records[1][6] if n > 1 else 0
	records[0][4] = 1
	return {"id": "EMF0", "art": "EMTF", "flags": flags, "trail": int(t.trail), "frames": int(t.frames), "steps": n, "length": length,
		"records": records, "index": 0, "next_ms": time_ms + 50, "cell": source, "pixel": Vector2i(s16(int(records[0][2])), s16(int(records[0][3]))),
		"owner": -1, "aim": aim, "aim_pixel": aim_px, "launch": launch, "missed": false, "accuracy": 0, "roll": 0, "shooter_elevation": 0,
		"shooter_high": false, "impacts": [], "alive": true, "hard_stop": false}

## 0x53fbc0: one step when time >= next (25 ms for arrows, 50 ms otherwise). Probes the first occupied cell of the 2 x 2
## block (cell, below, right, below-right); hits a hostile building over an opaque pixel while low (or always when the
## shooter is high), or a hostile living unit while low (heights 2..4 only for tall/flying units). A hit ends the flight
## at that record; the trail then fades for `trail` more steps. Returns false when the missile is finished.
## world: width, height, occupant(cell) -> {kind: "unit" | "building" | "other", id, owner, hp, tall} or {},
## hard_block(cell), allied(owner, missile_owner), building_pixel_hit(id, x, y).
static func tick(m: Dictionary, time_ms: int, world) -> bool:
	if time_ms < int(m.next_ms): return true
	m.next_ms = time_ms + (25 if int(m.flags) & 2 else 50)
	m.index = int(m.index) + 1
	var i: int = m.index
	var records: Array = m.records
	if i < int(m.steps) and int(records[i][4]) != 0:
		m.cell = Vector2i(int(records[i][0]), int(records[i][1]))
	if i < int(m.steps):
		var x: int = m.cell.x
		var y: int = m.cell.y
		var h := int(records[i][5])
		var cells: Array = [Vector2i(x, y)]
		if y < int(world.height) - 1: cells.append(Vector2i(x, y + 1))
		if x < int(world.width) - 1: cells.append(Vector2i(x + 1, y))
		if x < int(world.width) - 1 and y < int(world.height) - 1: cells.append(Vector2i(x + 1, y + 1))
		var found: Dictionary = {}
		for c in cells:
			var o: Dictionary = world.occupant(c)
			if o.is_empty(): continue
			# The high-target probe (+0x160 & 0x1000) passes over ground units without the tall bits; the slice has no air layer.
			if int(m.flags) & 0x1000 and h >= 2 and (o.kind == "other" or (o.kind == "unit" and not bool(o.get("tall", false)))): continue
			found = o
			break
		var hit := false
		if found.is_empty():
			if world.hard_block(Vector2i(x, y)):            # material 9 (+9 == 9): the missile stops (effect EMX0)
				m.steps = i
				m.hard_stop = true
		elif found.kind == "building":
			if int(found.owner) != int(m.owner) and not world.allied(int(found.owner), int(m.owner)) \
					and world.building_pixel_hit(found.id, int(records[i][2]), int(records[i][3])):
				hit = h < 2 or bool(m.shooter_high)
		elif found.kind == "unit":
			hit = not (h >= 2 and (h > 4 or not bool(found.get("tall", false)))) and int(found.owner) != int(m.owner) \
				and not world.allied(int(found.owner), int(m.owner)) and int(found.get("hp", 1)) > 0
		if hit:
			m.impacts.append({"kind": found.kind, "id": found.id, "record": i})
			m.steps = i
	if i < int(m.steps):
		m.pixel = Vector2i(s16(int(records[i][2])), s16(int(records[i][3])))
	var finished: bool = i >= int(m.steps) - 1 and i >= int(m.trail) + int(m.steps) - 1
	m.alive = not finished
	return not finished

## 0x5427e0 (Read): armour first (0x42bbf0, mode 2) unless the shooter ignores armour, then the elevation table
## 0x611e60[clamp(shooter elevation - target elevation + 7, 0, 14)], then the arrow rule against buildings.
## B1-6c (B1-6b open item 10; Emulated: tests/hero_spell_b_fixtures.json "arrows", the BKH0 rows): a positive damage of
## class 0 or 0xb (+0x67a, the rebuild's dtype) from a 0x52e790 missile becomes damage >> 4, at least 1 (class 0xb: 2),
## unless the shooter's owner has PHUN (0x70d5c3; no shooter, owner -1, is reduced); then a missile with +0x160 bit
## 0x400 doubles it, PHUN or not (disassembly 0x542a5c..0x542aae). Which of the missile's ids 0x52e790 tests (+0x34) is
## taken as the created missile's id (the harness set art and id alike: Read).
static func impact_damage(m: Dictionary, damage: int, dtype: int, target_kind: String, target_elevation: int, armour_tail: Callable,
		shooter_phun := false) -> int:
	var d: int = armour_tail.call(damage, dtype)
	if d < 0: return d                                     # FAULT_DAMAGE from the guarded tail
	var index := clampi(int(m.shooter_elevation) - target_elevation + 7, 0, 14)
	d = s16(tdiv(d * ELEVATION_PERCENT[index], 100))
	if d > 0 and (dtype == 0 or dtype == 0xb) and target_kind == "building" and String(m.id) in BUILDING_DIVISOR_IDS:
		d = building_arrow(d, dtype, int(m.get("flags", 0)), shooter_phun)
	return d

## The building half of the arrow rule (B1-6c, Emulated as above): d > 0 and class 0 / 0xb assumed by the caller.
static func building_arrow(d: int, dtype: int, flags: int, shooter_phun: bool) -> int:
	if not shooter_phun: d = maxi(d >> 4, 2 if dtype == 0xb else 1)
	if flags & 0x400: d *= 2
	return d

static func impact_sound(id: String, target_kind: String) -> int:
	var pair: Array = IMPACT_SOUNDS.get(id, [])
	if pair.is_empty(): return -1
	return int(pair[1]) if target_kind == "building" else int(pair[0])
