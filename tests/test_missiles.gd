extends SceneTree
## Milestone 11 (EFFECTS_RESEARCH.md section 2): the missile port (simulation/missiles.gd) against the unmodified
## executable under Unicorn (tests/missile_fixtures.json from tools/emulate_missiles.py): every initialisation (launch
## point, length, lead, accuracy and miss displacement, records, arc, heights, facings, random state) and every whole
## flight (tick times, record index, end of flight, position, cell, impacts). Then the combat wiring.
const Missiles = preload("res://simulation/missiles.gd")
const Rng = preload("res://simulation/combat_rng.gd")
const Rules = preload("res://simulation/combat_rules.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		if failures < 40: push_error(label)

class FixtureWorld:
	var width := 128
	var height := 128
	var cells := {}
	var objects: Array = []
	var allies := {}
	var water := {}
	var pixel_hit := true
	func _init(world: Dictionary):
		objects = world.objects
		for i in objects.size():
			for c in objects[i].cells: cells[Vector2i(int(c[0]), int(c[1]))] = i
		for pair in world.get("allies", []): allies[Vector2i(int(pair[0]), int(pair[1]))] = true
		for entry in world.get("materials", []):
			if int(entry[1]) == 9: water[Vector2i(int(entry[0][0]), int(entry[0][1]))] = true
		pixel_hit = bool(world.get("pixel_hit", true))
	func occupant(cell: Vector2i) -> Dictionary:
		if not cells.has(cell): return {}
		var i: int = cells[cell]
		var o: Dictionary = objects[i]
		return {"kind": o.kind, "id": i, "owner": int(o.owner), "hp": int(o.get("hp", 10)), "tall": int(o.get("flags", 0)) & Missiles.UNIT_FLAGS_TALL != 0}
	func hard_block(cell: Vector2i) -> bool:
		return water.has(cell)
	func allied(a: int, b: int) -> bool:
		return allies.has(Vector2i(a, b))
	func building_pixel_hit(_id, _x: int, _y: int) -> bool:
		return pixel_hit

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/missile_fixtures.json"))
	var tables: Dictionary = fixtures.launch_tables
	_test_init(fixtures.init, tables)
	_test_flight(fixtures.flight, tables)
	_test_rules()
	var world = preload("res://tests/combat_world_checks.gd").new()
	world.run_missile_checks(self)
	if failures == 0: print("Missile checks passed: ", checks)
	else: printerr("Missile failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

static func v2(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))

static func shooter_of(case: Dictionary, tables: Dictionary) -> Dictionary:
	var s: Dictionary = case.shooter
	var t: Dictionary = case.target
	var offset := Vector2i.ZERO
	if s.kind == "unit":
		offset = v2(tables[s.type][int(s.facing)])
	else:
		offset = v2(tables[s.type][Missiles.direction(v2(s.cell), v2(t.cell))])
	var combat := int(s.combat)
	if s.kind == "unit":
		combat = Rules.effective_combat({"combat": int(s.combat), "enc": 0, "near_hero": bool(s.get("near_hero", false))})
	return {"kind": s.kind, "owner": int(s.owner), "cell": v2(s.cell), "rect": s.rect, "launch_offset": offset, "combat": combat,
		"roll": int(s.get("roll", 0)), "flags_ba": int(s.get("flags_ba", 0)), "high": false, "elevation": 0}

static func target_of(case: Dictionary) -> Dictionary:
	var t: Dictionary = case.target
	var offset: Array = t.get("offset", [0, 0])
	return {"kind": t.kind, "cell": v2(t.cell), "pixel": Vector2i(int(t.pixel[0]) - int(offset[0]), int(t.pixel[1]) - int(offset[1])),
		"moving": int(t.get("state", 0)) == 1, "facing": int(t.get("facing", 0)), "speed": int(t.get("speed", 8)),
		"high": int(t.get("flags", 0)) & Missiles.UNIT_FLAG_HIGH != 0, "elevation": 0}

func _create(case: Dictionary, tables: Dictionary) -> Dictionary:
	var rng = Rng.new(int(case.seed[0]), int(case.seed[1]))
	var m := Missiles.create(case.id, shooter_of(case, tables), target_of(case), rng, int(case.time))
	m["rng_after"] = rng.state()
	return m

func _test_init(cases: Array, tables: Dictionary):
	var same := 0
	for case in cases:
		var m := _create(case, tables)
		var want: Dictionary = case.result
		var ok: bool = m.aim == v2(want.aim) and m.launch == v2(want.launch) and m.aim_pixel == v2(want.aim_pixel) and int(m.length) == int(want.length) \
			and int(m.flags) == int(want.flags) and int(m.steps) == int(want.steps) and int(m.next_ms) == int(want.next_ms) \
			and int(m.trail) == int(want.trail) and m.cell == v2(want.cell) and m.pixel == v2(want.pixel) \
			and m.rng_after == [int(want.rng_after[0]), int(want.rng_after[1])] and int(m.shooter_elevation) == int(want.shooter_elevation)
		var records_ok: bool = m.records.size() == want.records.size()
		if records_ok:
			for i in m.records.size():
				for k in 7:
					if int(m.records[i][k]) != int(want.records[i][k]): records_ok = false
		check(ok and records_ok, "missile init %s %s->%s: got aim %s px %s len %d steps %d, want %s %s %d %d" % [case.id, case.shooter.kind, case.target.kind,
			m.aim, m.aim_pixel, m.steps, m.length, want.aim, want.aim_pixel, want.length, want.steps])
		if ok and records_ok: same += 1
	print("  missile initialisations identical to the executable: %d / %d" % [same, cases.size()])

func _test_flight(cases: Array, tables: Dictionary):
	var same := 0
	for case in cases:
		var m := _create(case, tables)
		var world := FixtureWorld.new(case.world)
		var t := int(m.next_ms)
		var ticks: Array = []
		for _i in 200:
			var step_time := t
			var alive := Missiles.tick(m, t, world)
			ticks.append([step_time, int(m.index), int(m.steps), m.pixel, m.cell, 1 if alive else 0])
			if not alive: break
			t = int(m.next_ms)
		var want: Dictionary = case.flight
		var ok: bool = ticks.size() == want.ticks.size()
		if ok:
			for i in ticks.size():
				var w: Dictionary = want.ticks[i]
				if ticks[i] != [int(w.time), int(w.index), int(w.steps), v2(w.pixel), v2(w.cell), int(w.alive)]: ok = false
		var hits: Array = m.impacts.map(func(h): return [int(h.id), int(h.record)])
		var want_hits: Array = want.impacts.map(func(h): return [int(h.object), int(h.record)])
		ok = ok and hits == want_hits
		check(ok, "missile flight %s %s: got %d ticks hits %s, want %d ticks hits %s" % [case.id, case.shooter.kind, ticks.size(), hits, want.ticks.size(), want_hits])
		if ok: same += 1
	print("  missile flights identical to the executable: %d / %d" % [same, cases.size()])

func _test_rules():
	# Elevation table (0x611e60) and the arrow divisor against buildings (0x52e790, Read).
	var plain := func(d: int, _t: int) -> int: return d
	var m := {"shooter_elevation": 0, "id": "EMA0"}
	check(Missiles.impact_damage(m, 8, 0, "unit", 0, plain) == 8, "level ground: 100 %")
	check(Missiles.impact_damage(m, 30, 0, "building", 0, plain) == 1, "arrow against a building: 30 / 16 -> 1")
	check(Missiles.impact_damage(m, 40, 0, "building", 0, plain) == 2, "arrow against a building: 40 / 16 -> 2")
	var tower := {"shooter_elevation": 1, "id": "EMA0"}
	check(Missiles.impact_damage(tower, 30, 0, "unit", 0, plain) == 36, "tower shot (shooter +1): 120 %")
	var swarm := {"shooter_elevation": 1, "id": "EMM0"}
	check(Missiles.impact_damage(swarm, 20, 4, "building", 0, plain) == 24, "EMM0 keeps its damage against buildings")
	check(Missiles.impact_damage({"shooter_elevation": 0, "id": "EMA0"}, 10, 0, "unit", 9, plain) == 2, "far below: 20 %")
	check(Missiles.impact_sound("EMA0", "unit") == 0 and Missiles.impact_sound("EMA0", "building") == 18, "arrow impact sounds Missile0 / Missile18")
	check(Missiles.impact_sound("EMM0", "unit") == 7 and Missiles.impact_sound("EMM0", "building") == 25, "Swarm shot impact sounds Missile7 / Missile25")
	check(Missiles.step_ms(8) == 475, "speed 8 step table entry (0x61178c)")
	check(Missiles.facing16(0, 0, 10, 0) == 2 and Missiles.facing16(0, 0, 0, -10) == 0 and Missiles.facing16(0, 0, -10, 0) == 6, "16-way facings")
