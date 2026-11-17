extends SceneTree
## Milestone 8 checks. Parity of the random generator, the melee swing / to-hit / damage routine, the missile armour
## reduction and the sight masks against the unmodified executable under Unicorn (tests/combat_fixtures.json,
## tools/emulate_combat.py); then combat rules (timing, acquisition, death, XP, visibility) in COMBAT_RESEARCH.md.
const Rng = preload("res://simulation/combat_rng.gd")
const Rules = preload("res://simulation/combat_rules.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/combat_fixtures.json"))
	_test_rng(fixtures)
	_test_swing(fixtures)
	_test_attack_start(fixtures)
	_test_armour(fixtures)
	_test_sight(fixtures)
	_test_rules()
	var world = preload("res://tests/combat_world_checks.gd").new()
	world.run(self)
	if failures == 0: print("Combat checks passed: ", checks)
	else: printerr("Combat failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

func _test_rng(fixtures: Dictionary):
	for case in fixtures.rng:
		var rng = Rng.new(case.seed[0], case.seed[1])
		for i in case.calls.size():
			var call: Array = case.calls[i]
			check(rng.roll(call[0], call[1], call[2]) == int(case.results[i]), "rng seed %s call %d" % [case.seed, i])
		check(rng.state() == [int(case.state_after[0]), int(case.state_after[1])], "rng state after seed %s" % [case.seed])

static func unit_block(d: Dictionary) -> Dictionary:
	return {"combat": int(d.combat), "dmg": int(d.dmg), "dtype": int(d.dtype), "range": int(d.range), "armour": int(d.armour),
		"mres": int(d.get("mres", 0)), "res1": int(d.get("res1", -1)), "res2": int(d.get("res2", -1)), "enc": int(d.get("enc", 0)),
		"near_hero": bool(d.get("near_hero", false)), "building": false}

func _test_swing(fixtures: Dictionary):
	var compared := 0
	var faults := 0
	var bands := {}
	for case in fixtures.swing:
		var rng = Rng.new(case.seed[0], case.seed[1])
		var attacker := unit_block(case.attacker)
		var target: Dictionary
		if case.building:
			target = {"combat": int(case.target.combat), "mres": int(case.target.mres), "armour": int(case.target.armour), "building": true,
				"res1": -1, "res2": -1, "range": 0}
		else:
			target = unit_block(case.target)
		var got: Dictionary = Rules.swing(attacker, target, rng, int(case.distance))
		var want: Dictionary = case.result
		if want.has("fault"):
			faults += 1
			check(got.has("fault"), "swing should fault (original divides by zero) %s" % [case.seed])
			continue
		compared += 1
		check(not got.has("fault"), "swing unexpected fault %s" % [case.seed])
		if got.has("fault"): continue
		bands[got.code] = int(bands.get(got.code, 0)) + 1
		var label := "swing %s vs %s seed %s" % [case.attacker, case.target, case.seed]
		check(got.damage == int(want.damage), label + " damage %d != %d" % [got.damage, int(want.damage)])
		check(got.effect == int(want.effect) and got.param == int(want.param), label + " effect")
		check(rng.state() == [int(want.state_after[0]), int(want.state_after[1])], label + " rng state")
	check(compared > 4000, "swing fixtures compared")
	check(faults > 0, "faulting division cases present")
	for code in range(5): check(bands.get(code, 0) > 20, "swing band %d covered" % code)

func _test_attack_start(fixtures: Dictionary):
	var faults := 0
	for case in fixtures.attack_start:
		var rng = Rng.new(case.seed[0], case.seed[1])
		var want: Dictionary = case.result
		var attacker := unit_block(case.attacker)
		var target := unit_block(case.target)
		var got: Dictionary = Rules.attack_start(attacker, target, rng, 0)
		var label := "attack start %s seed %s" % [case.attacker, case.seed]
		if want.has("fault"):
			faults += 1
			check(got.has("fault"), label + " should fault")
			continue
		check(not got.has("fault") and got.message_roll == int(want.message_roll), label + " message roll")
		if got.has("fault"): continue
		check(got.damage == int(want.damage) and got.effect == int(want.effect) and got.param == int(want.param), label + " damage field %s vs %s" % [got, want])
		check(rng.state() == [int(want.state_after[0]), int(want.state_after[1])], label + " rng state (two draws for melee, one for ranged)")
	check(fixtures.attack_start.size() - faults > 400, "attack-start fixtures compared")

func _test_armour(fixtures: Dictionary):
	for case in fixtures.armour:
		var got: int = Rules.armour_tail(int(case.damage), int(case.mode), int(case.dtype), case.armour, case.flags)
		check(got == int(case.result), "armour tail %s -> %d (want %d)" % [case, got, int(case.result)])

func _test_sight(fixtures: Dictionary):
	var tier: Dictionary = fixtures.fog.tiers["4"]
	for radius_key in tier:
		var radius := int(radius_key)
		var want := {}
		for cell in tier[radius_key][0]: want[Vector2i(int(cell[0]), int(cell[1]))] = true
		for facing in 8:
			var mask := {}
			for cell in tier[radius_key][facing]: mask[Vector2i(int(cell[0]), int(cell[1]))] = true
			if mask.is_empty():
				# Original quirk (COMBAT_RESEARCH.md): the run list of radius 14 / facing 7 is overwritten by the next slot.
				check(radius == 14 and facing == 7, "only radius 14 facing 7 has a damaged mask")
				continue
			check(mask == want, "sight mask r%d is identical for facing %d" % [radius, facing])
		var rebuilt := {}
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if Rules.sight_covers(dx, dy, radius): rebuilt[Vector2i(dx, dy)] = true
		check(rebuilt == want, "sight circle r%d matches 0x47e500" % radius)

func _test_rules():
	# Attack animation: Swordsman f slot, 16 entries; hit handler at entry 6 (ANI +0x18).
	check(Rules.attack_entry_ms(false, 0, 0) == 93, "f entry ms plain unit")
	check(Rules.hit_delay_ms(93) == 558 and Rules.swing_duration_ms(93) == 1488, "swing timing")
	check(Rules.attack_entry_ms(false, 200, 0) == 31, "attack time floor of 500")
	check(Rules.attack_entry_ms(true, 0, -2) == 63, "hero attack time from derived stat")
	check(Rules.attack_entry_ms(false, 0, 0, 20) == 46, "attack rate 20 halves the entry")
	check(Rules.in_attack_range(1, 0) and not Rules.in_attack_range(2, 0) and Rules.in_attack_range(7, 6), "range test")
	var teams := [1, 1, 0, 2, 0, 0, 0]
	check(not Rules.hostile(teams, 0, 1) and Rules.hostile(teams, 0, 3) and Rules.hostile(teams, 2, 4), "team relations")
	check(Rules.hostile(teams, 0, 6) and not Rules.hostile(teams, 0, 0), "neutral slot is hostile, self is not")
