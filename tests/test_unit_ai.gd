extends SceneTree
## Milestone 9 checks. Parity with the unmodified executable under Unicorn (tests/unit_ai_fixtures.json,
## tools/emulate_unit_ai.py): the nine built-in attitude scripts, the executor's rule choice, the self-contained
## conditions, flight on Desert Sands and the lair waves and bosses; then world checks of the encounters
## (tests/encounter_world_checks.gd). Read and provisional rules are marked in ENCOUNTERS_RESEARCH.md.
const UnitAI = preload("res://simulation/unit_ai.gd")
const Encounters = preload("res://simulation/encounters.gd")
const Rng = preload("res://simulation/combat_rng.gd")
const CollisionData = preload("res://core/collision_data.gd")
var checks := 0
var failures := 0

class FakeCombat:
	var now_ms := 0

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/unit_ai_fixtures.json"))
	var data: Dictionary = UnitAI.load_data()
	_test_scripts(fixtures, data)
	_test_executor(fixtures, data)
	_test_conditions(fixtures)
	_test_flight(fixtures)
	_test_lairs(fixtures, data)
	var world = preload("res://tests/encounter_world_checks.gd").new()
	world.run(self)
	if failures == 0: print("Encounter checks passed: ", checks)
	else: printerr("Encounter failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

func _test_scripts(fixtures: Dictionary, data: Dictionary):
	check(data.scripts.size() == 9 and int(data.count) == 9, "nine built-in scripts (0x506c40 sets the count to 9)")
	var names := ["Cowardly", "Stand Ground", "Defensive", "Aggressive", "Rampant", "Scout", "Standard", "Guardian", "Magic Guardian"]
	for s in range(9):
		var emulated: Dictionary = fixtures.scripts[s]
		var shipped: Dictionary = data.scripts[s]
		check(shipped.name == names[s] and int(shipped.name_string) == 537 + [0, 2, 4, 8, 10, 12, 6, 14, 16][s], "script %d name and Game.txt string" % s)
		check(JSON.stringify(shipped.rules) == JSON.stringify(emulated.rules) and JSON.stringify(shipped.default) == JSON.stringify(emulated.default)
			and int(shipped.radius) == int(emulated.radius) and int(shipped.uses_leader) == int(emulated.uses_leader), "script %d tables equal the emulated builder" % s)
	var defensive: Dictionary = data.scripts[2]
	check(defensive.rules[0].conditions[0].name == "enemy_near" and int(defensive.rules[0].conditions[0].flag) == 1 and defensive.rules[0].action.name == "attack_near"
		and defensive.default.name == "return_post" and int(defensive.radius) == 20, "Defensive: leashed enemy_near -> attack_near, default return_post, radius 20")
	var cowardly: Dictionary = data.scripts[0]
	check(cowardly.rules[2].conditions[0].name == "was_hit" and cowardly.rules[2].action.name == "flee" and int(cowardly.rules[2].priority) == 100
		and cowardly.rules[0].action.name == "flee_near", "Cowardly: hit -> flee (100), enemy near -> flee_near (90), away from post -> return (80)")

func _state(case: Dictionary) -> Dictionary:
	var order: String = case.order
	if order == "finished_chain": order = "finished"
	return {"order": order, "leader": case.leader, "leader_flag": int(case.leader_flag), "hero": bool(case.hero)}

func _test_executor(fixtures: Dictionary, data: Dictionary):
	var n := 0
	for case in fixtures.executor:
		var outcomes: Array = case.outcomes.duplicate()
		var result := UnitAI.decide(data.scripts[int(case.script)], _state(case), func(c, tag): return int(outcomes.pop_front() if not outcomes.is_empty() else 0) != 0)
		var calls_ok: bool = result.calls.size() == case.calls.size()
		if calls_ok:
			for i in result.calls.size():
				var got: Dictionary = result.calls[i]
				var want: Dictionary = case.calls[i]
				if got.cond != want.cond or got.subject != want.subject or got.flag != int(want.flag) or got.expected != int(want.expected): calls_ok = false
				if want.has("value") and got.value != int(want.value): calls_ok = false
		check(calls_ok, "executor case %d: condition calls %s vs %s" % [n, result.calls, case.calls])
		var set_script := -1
		var popped := false
		for e in case.events:
			if e.has("set_script"): set_script = int(e.set_script)
			if e.has("pop"): popped = true
		check(result.set_script == set_script, "executor case %d: leader-lost switch" % n)
		check(result.pop == popped, "executor case %d: finished-order clean-up %s vs %s" % [n, result.pop, popped])
		var action_ok := false
		if case.actions.is_empty(): action_ok = result.action == null
		elif result.action != null:
			var want: Dictionary = case.actions[0]
			action_ok = result.action.name == want.action
			if want.has("subject") and want.subject != null: action_ok = action_ok and result.action.subject == want.subject
			if want.has("param"): action_ok = action_ok and result.action.param == int(want.param)
		check(action_ok, "executor case %d (script %d): action %s vs %s" % [n, int(case.script), result.action, case.actions])
		var last: int = int(case.last_action_before) if result.action == null else int(result.action.type)
		check(last == int(case.last_action_after), "executor case %d: +0x132 last action" % n)
		n += 1

func _test_conditions(fixtures: Dictionary):
	var size := Vector2i(128, 128)
	for c in fixtures.conditions.distance:
		var me := Vector2i(int(c.me[0]), int(c.me[1]))
		var other := Vector2i(int(c.other[0]), int(c.other[1]))
		var guard := Vector2i(int(c.guard[0]), int(c.guard[1]))
		var leash := UnitAI.leash_contains(other, guard, me, int(c.radius), size, bool(c.same))
		var got := UnitAI.distance_below(me, other, bool(c.same), int(c.flag) != 0, guard, int(c.radius), size, int(c.value), int(c.expected) != 0, leash)
		check(got == (int(c.result) != 0), "distance_below %s" % [c])
	for c in fixtures.conditions.hp:
		check(UnitAI.hp_below(int(c.hp), int(c.maxhp), int(c.value), int(c.expected) != 0) == (int(c.result) != 0), "hp_below %s" % [c])
	for steps in fixtures.conditions.hit_list:
		var fake := FakeCombat.new()            # UnitAI holds its world weakly: keep the fake alive here
		var ai = UnitAI.new(fake, UnitAI.load_data())
		for s in steps:
			ai.combat.now_ms = int(s.t)
			if s.has("hit"):
				ai.record_hit("unit", 0 if s.hit[0] == "other" else 2, 1 if s.hit[1] == "self" else 3, int(s.t))
			else:
				var found: bool = ai.was_hit(1 if s.ask == "self" else 3)
				check((found == (int(s.expected) != 0)) == (int(s.result) != 0), "hit list at %d: %s" % [int(s.t), s])
	for c in fixtures.conditions.area:
		var rect := UnitAI.area_window(Vector2i(int(c.subject_cell[0]), int(c.subject_cell[1])), Vector2i(int(c.subject_guard[0]), int(c.subject_guard[1])),
			int(c.range), int(c.flag) != 0, Vector2i(int(c.guard[0]), int(c.guard[1])), Vector2i(int(c.me[0]), int(c.me[1])), 20, c.routine == "enemy_near_post")
		var want: Array = c.events[0].search
		check(rect == [int(want[0]), int(want[1]), int(want[2]), int(want[3])], "%s window %s vs %s" % [c.routine, rect, want])
		check(((int(c.found) != 0) == (int(c.expected) != 0)) == (int(c.result) != 0), "%s result" % c.routine)

func _test_flight(fixtures: Dictionary):
	var collision = CollisionData.new()
	for c in fixtures.flight:
		var me := Vector2i(int(c.me[0]), int(c.me[1]))
		var threat := Vector2i(int(c.threat[0]), int(c.threat[1]))
		var dest = UnitAI.flight_destination(me, threat, func(cell): return UnitAI.flight_cell_static(cell, collision))
		if c.move == null:
			check(dest == null, "flight %s: no destination" % [c])
			continue
		check(dest != null and dest.cell == Vector2i(int(c.move[0]), int(c.move[1])) and dest.interruptible == (int(c.p5) != 0),
			"flight from %s away from %s: %s vs %s" % [me, threat, dest, c.move])
	# 0x40a8f0 on the eight neighbours and the 2:1 slopes.
	var dirs := [[Vector2i(0, -1), 0], [Vector2i(1, -1), 1], [Vector2i(1, 0), 2], [Vector2i(1, 1), 3], [Vector2i(0, 1), 4], [Vector2i(-1, 1), 5],
		[Vector2i(-1, 0), 6], [Vector2i(-1, -1), 7], [Vector2i(3, 1), 2], [Vector2i(1, 3), 4], [Vector2i(-3, 1), 6], [Vector2i(-1, -3), 0]]
	for d in dirs: check(UnitAI.direction(Vector2i.ZERO, d[0]) == d[1], "direction to %s" % d[0])

func _test_lairs(fixtures: Dictionary, data: Dictionary):
	var table: Array = data.lairs
	check(table.size() == 6 and table[2].entries.size() == 3 and table[2].entries[0].type_a == "AMJX" and int(table[2].min_ms) == 80000
		and int(table[2].max_ms) == 120000 and int(table[2].response_ms) == 30000 and table[2].boss == "AMJX", "Gnoll Lair row of 0x5fb338")
	for w in fixtures.lairs.waves:
		var rng = Rng.new(int(w.seed[0]), int(w.seed[1]))
		var got := Encounters.lair_wave(rng, int(w.now), table[int(w.lair)], int(w.first) != 0, data.xp_levels)
		check(got.times == [int(w.times_after[0]), int(w.times_after[1]), int(w.times_after[2])], "lair %d at %d: times %s vs %s" % [int(w.lair), int(w.now), got.times, w.times_after])
		var same: bool = got.spawns.size() == w.spawns.size()
		if same:
			for i in got.spawns.size():
				if got.spawns[i].type != w.spawns[i].type or int(got.spawns[i].xp) != int(w.spawns[i].xp) or int(w.spawns[i].owner) != 6: same = false
		check(same, "lair %d at %d (timed %d): spawns %s vs %s" % [int(w.lair), int(w.now), int(w.first), got.spawns, w.spawns])
		check(rng.state() == [int(w.rng_after[0]), int(w.rng_after[1])], "lair wave draws")
	for b in fixtures.lairs.bosses:
		var rng = Rng.new(int(b.seed[0]), int(b.seed[1]))
		var boss := Encounters.lair_boss(rng, table[int(b.lair)], data.xp_levels)
		check(b.spawns.size() == 1 and boss.type == b.spawns[0].type and int(boss.xp) == int(b.spawns[0].xp), "boss of lair %d: %s vs %s" % [int(b.lair), boss, b.spawns])
		check(rng.state() == [int(b.rng_after[0]), int(b.rng_after[1])], "boss draws")
