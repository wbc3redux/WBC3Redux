extends SceneTree
## Independent-review checks for milestone 8 (REVIEW_COMBAT.md; fixtures from tools/emulate_combat_review.py).
## Checks that must hold are counted and fail the run. The review's known divergences were fixed in milestone 8-fix and
## are hard checks now; any line reported through `diverges` also fails the run.
const Rng = preload("res://simulation/combat_rng.gd")
const Rules = preload("res://simulation/combat_rules.gd")
const Combat = preload("res://simulation/combat.gd")
var checks := 0
var failures := 0
var divergences: Array = []

class FakeUnit:
	extends RefCounted
	var cell := Vector2i.ZERO
	var inside_building := false

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func diverges(condition: bool, label: String):
	if not condition: divergences.append(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/combat_review_fixtures.json"))
	_test_hero_swing(fixtures)
	_test_ranged_start(fixtures)
	_test_timing(fixtures)
	_test_priority(fixtures)
	_test_crit_mode(fixtures)
	check(divergences.is_empty(), "no divergences from the executable (%d reported)" % divergences.size())
	if failures == 0: print("Review checks passed: ", checks, "; known divergences from the executable: ", divergences.size())
	else: printerr("Review failures: ", failures, " / ", checks)
	for line in divergences: print("DIVERGENCE: ", line)
	quit(0 if failures == 0 else 1)

func block(d: Dictionary) -> Dictionary:
	return {"combat": int(d.combat), "dmg": int(d.dmg), "dtype": int(d.dtype), "range": int(d.range), "armour": int(d.armour), "mres": int(d.mres),
		"res1": -1, "res2": -1, "enc": 0, "near_hero": false, "building": false}

func _test_hero_swing(fixtures: Dictionary):
	for case in fixtures.hero_swing:
		var rng = Rng.new(case.seed[0], case.seed[1])
		var got: Dictionary = Rules.swing(block(case.attacker), block(case.target), rng, 0)
		if case.has("fault"):
			check(got.has("fault"), "hero swing should fault %s" % [case.seed])
			continue
		check(not got.has("fault") and got.damage == int(case.damage) and got.effect == int(case.effect) and got.param == int(case.param),
			"hero flag swing %s heroes %s -> %s want %s" % [case.seed, case.hero, got, case])
		check(rng.state() == [int(case.state_after[0]), int(case.state_after[1])], "hero swing rng state")

func _test_ranged_start(fixtures: Dictionary):
	for case in fixtures.ranged_start:
		var rng = Rng.new(case.seed[0], case.seed[1])
		var got: Dictionary = Rules.attack_start(block(case.attacker), block(case.target), rng, 0)
		var want: Dictionary = case.result
		check(got.ranged and got.message_roll == int(want.message_roll) and got.damage == int(want.damage) and got.effect == int(want.effect),
			"ranged attack start %s: %s vs %s" % [case.seed, got, want])
		check(rng.state() == [int(want.state_after[0]), int(want.state_after[1])], "ranged start draws exactly once")

func _test_timing(fixtures: Dictionary):
	for case in fixtures.timing:
		var rate: int = 10 if int(case.flags) == 0 else 5   # 0x51c6a0 halves the rate when unit flags (+0xba) & 7
		var dt: int = Rules.attack_entry_ms(false, int(case.counter), 0, rate)
		check(int(case.count) == 16 and case.times.size() == 17, "f entries: 17")
		var times_ok := true
		for i in 17: times_ok = times_ok and int(case.times[i]) == i * dt
		check(times_ok, "entry times counter %d flags %d dt %d" % [int(case.counter), int(case.flags), dt])
		var frames_ok := true
		for i in 16: frames_ok = frames_ok and int(case.frames[i]) == i
		check(frames_ok and int(case.frames[16]) == 0, "entry frames 0..15 then 0")
		if int(case.flags) == 0:
			check(int(case.trigger_ms) == Rules.hit_delay_ms(dt), "hit trigger at entry 6: %d vs %d" % [int(case.trigger_ms), Rules.hit_delay_ms(dt)])
			check(int(case.end_ms) == Rules.swing_duration_ms(dt), "sequence ends after 16 entries: %d" % int(case.end_ms))

## D3 (fixed in 8-fix): every 0x533c40 case, with and without a candidate target and with the fixture's relation table.
func _test_priority(fixtures: Dictionary):
	var combat = Combat.new(Rng.new(1, 2), null, null, [])
	var compared := 0
	var with_target := 0
	for case in fixtures.priority:
		if case.score == null: continue
		var searcher = FakeUnit.new()
		searcher.cell = Vector2i(10, 10)
		var candidate = FakeUnit.new()
		candidate.cell = Vector2i(10 + int(case.dx), 10 + int(case.dy))
		combat.units = [searcher, candidate, FakeUnit.new()]
		var order = null
		combat.fighters = {0: {"id": 0, "owner": int(case.searcher_owner), "stats": {"dmg": 10}}}
		if case.victim_owner != null:
			combat.fighters[2] = {"id": 2, "owner": int(case.victim_owner), "stats": {"dmg": 10}, "order": null}
			order = {"kind": "attack", "target_kind": "unit", "target_id": 2}
			with_target += 1
		combat.fighters[1] = {"id": 1, "owner": int(case.candidate_owner), "stats": {"dmg": int(case.candidate_damage)}, "order": order}
		var table := PackedByteArray()
		for v in case.relations: table.append(int(v))
		combat.relations = table
		var got: int = combat._priority(combat.fighters[0], {"kind": "unit", "id": 1, "owner": int(case.candidate_owner), "cell": candidate.cell})
		compared += 1
		check(got == int(case.score), "0x533c40 owner %d candidate %d dmg %d victim %s at (%d, %d): port %d, original %d" % [int(case.searcher_owner),
			int(case.candidate_owner), int(case.candidate_damage), case.victim_owner, int(case.dx), int(case.dy), got, int(case.score)])
	check(compared > 500 and with_target > 300, "priority cases compared: %d (%d with a target)" % [compared, with_target])

## 8-fix match option 0x748946: the same swings with mode 0 and mode 3 (crit side effects off).
func _test_crit_mode(fixtures: Dictionary):
	var changed := 0
	for case in fixtures.crit_mode:
		var a: Dictionary = block(case.attacker)
		var d: Dictionary = block(case.target)
		var rng = Rng.new(case.seed[0], case.seed[1])
		var got: Dictionary = Rules.swing(a, d, rng, 0, int(case.mode))
		var want: Dictionary = case.result
		if want.has("fault"):
			check(got.has("fault"), "mode %d swing should fault" % int(case.mode))
			continue
		check(not got.has("fault") and got.damage == int(want.damage) and got.effect == int(want.effect) and got.param == int(want.param),
			"0x748946 = %d swing %s: port %s, original %s" % [int(case.mode), case.seed, got, want])
		check(rng.state() == [int(want.state_after[0]), int(want.state_after[1])], "mode %d draws" % int(case.mode))
		if int(case.mode) == 3 and int(want.effect) == 0 and got.effect == 0: changed += 1
	check(changed > 300, "mode 3 cases without side effects: %d" % changed)
