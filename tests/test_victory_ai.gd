extends SceneTree
## OPEN_ITEMS.md to-do 2 (SKIRMISH_RESEARCH.md "Victory options and the computer player"): what the computer player does
## under each victory option.
## * Fixtures: 0x4fa990 (the monster mode's three targets, Capture the Flag's -500 flag) and 0x4fa850 (the idle units'
##   attack orders) against tests/monster_ai_fixtures.json (tools/emulate_monster_ai.py, original x86 under Unicorn).
## * Pitched Battle (option 11): both computers are Rampant and play the monster mode: no building, no groups, their
##   idle units attack the main enemy's objects and kill.
## * Capture the Flag (option 12) with Rampant computers: no target slot ever holds a flag (BMFL).
## * `-- --soak` (the -Check soak): the options that leave the computer's code alone (Read: 0x70ae12 has no other reader
##   in the computer player) give the same computer decisions as Standard Victory on the same start, minute for minute.

const Setup = preload("res://simulation/skirmish_setup.gd")
const MapData = preload("res://core/map_data.gd")
const R = preload("res://simulation/ai_rules.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 30: printerr("Victory AI check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	fixture_checks()
	await pitched_battle()
	await capture_the_flag()
	if OS.get_cmdline_user_args().has("--soak"): await unchanged_options()
	if failures > 0:
		printerr("Victory AI checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Victory AI checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ fixtures
func fixture_checks():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/monster_ai_fixtures.json"))
	var flags_ctf := 0
	var flags_other := 0
	var mismatches := 0
	for c in fixtures.targets:
		var objects: Array = c.objects.map(func(o): return {"kind": int(o.kind), "code": String(o.code), "cell": o.cell,
			"state": int(o.state), "hidden": int(o.hidden) != 0, "sprite": int(o.sprite) != 0, "movement": int(o.movement)})
		var got: Array = R.monster_targets(objects, int(c.main), c.home, int(c.height), int(c.option), int(c.strength))
		var want: Array = c.slots.map(func(v): return int(v))
		if got != want:
			mismatches += 1
			if mismatches < 5: printerr("  0x4fa990 case: got %s want %s" % [got, want])
		for s in want:
			if s >= 0 and String(c.objects[s].code) == "BMFL":
				if int(c.option) == R.CAPTURE_THE_FLAG: flags_ctf += 1
				else: flags_other += 1
	check(mismatches == 0, "0x4fa990: %d of %d target cases differ" % [mismatches, fixtures.targets.size()])
	check(flags_ctf == 0 and flags_other > 0, "0x4fa990: a flag is a target except under Capture the Flag (%d / %d)" % [flags_ctf, flags_other])
	# The strength term is the same for every object of a pass: with 0 instead of the grid's value the choice is unchanged.
	var same := 0
	for c in fixtures.targets:
		var objects: Array = c.objects.map(func(o): return {"kind": int(o.kind), "code": String(o.code), "cell": o.cell,
			"state": int(o.state), "hidden": int(o.hidden) != 0, "sprite": int(o.sprite) != 0, "movement": int(o.movement)})
		if R.monster_targets(objects, int(c.main), c.home, int(c.height), int(c.option), 0) == c.slots.map(func(v): return int(v)): same += 1
	check(same == fixtures.targets.size(), "0x4fa990 without the strength grid: %d of %d unchanged" % [same, fixtures.targets.size()])
	mismatches = 0
	for c in fixtures.attacks:
		var faces: Array = c.faces.duplicate()
		var got: Array = []
		var has0: bool = int(c.slots[0]) != 0
		var has1: bool = int(c.slots[1]) != 0
		for i in c.units.size():
			var u: Dictionary = c.units[i]
			if int(u.kind) != 0 or int(u.state) != 3: continue
			var slot := R.monster_attack_slot(int(u.layers), has0, has1, func(): return int(faces.pop_front()) - 1)
			if slot >= 0: got.append([i, slot])
		var want: Array = c.orders.map(func(o): return [int(o[0]), int(o[1])])
		if got != want or faces.size() != c.faces.size() - c.rolls.size():
			mismatches += 1
			if mismatches < 5: printerr("  0x4fa850 case: got %s want %s" % [got, want])
	check(mismatches == 0, "0x4fa850: %d of %d attack cases differ" % [mismatches, fixtures.attacks.size()])

# ------------------------------------------------------------------------------------------------ matches
func new_scene():
	MapData.select("desert-sands")
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	return scene

func close(scene):
	scene.end_skirmish()
	if scene.encounters != null: scene.encounters.dispose()
	scene.free()

## Two computer Knights on Desert Sands, spectator (no hero book), `levels` per side, the option chosen through the setup.
func setup_for(option: int, levels: Array) -> Dictionary:
	var setup := Setup.defaults(JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json")))
	for i in 2:
		Setup.set_race(setup, i, Setup.KNIGHT)
		Setup.set_kind(setup, i, Setup.COMPUTER, int(levels[i]))
	Setup.choose_victory(setup, option)
	return setup

func pitched_battle():
	var scene = await new_scene()
	check(scene.start_skirmish(setup_for(11, [3, 6]), "", null, "victory-ai-pitched"), "Pitched Battle starts")
	var ais: Array = [scene.ai_manager.players[0], scene.ai_manager.players[1]]
	check(ais.all(func(a): return a != null and int(a.difficulty) == R.RAMPANT), "Pitched Battle: both computers are Rampant (0x4eaca0)")
	var start_units: Array = ais.map(func(a): return a.my_units().size())
	var targeted := [0, 0]
	for i in roundi(120.0 * 40.0):
		if scene.skirmish.over: break
		scene.simulation_step(0.025)
		if i % 40 != 0: continue
		for p in 2:
			if ais[p].monster_slots.any(func(s): return not s.is_empty()): targeted[p] += 1
	for p in 2:
		var s: Dictionary = ais[p].summary()
		print("  Pitched Battle P%d: start units %d, %s" % [p, start_units[p], s])
		check(int(start_units[p]) > 1, "Pitched Battle P%d: an army from the 50 points" % p)
		check(targeted[p] > 0, "Pitched Battle P%d: 0x4fa990 picks targets" % p)
		check(int(s.stats.attacks) > 0, "Pitched Battle P%d: 0x4fa850 sends idle units to attack" % p)
		check(int(s.stats.builds) == 0 and int(s.stats.launches) == 0 and ais[p].groups.is_empty(), "Pitched Battle P%d: no economy, no groups" % p)
	check(int(scene.combat.kills.get(0, 0)) + int(scene.combat.kills.get(1, 0)) > 0, "Pitched Battle: the computers fight (kills %s)" % scene.combat.kills)
	close(scene)

func capture_the_flag():
	var scene = await new_scene()
	check(scene.start_skirmish(setup_for(12, [7, 7]), "", null, "victory-ai-flags"), "Capture the Flag with Rampant computers starts")
	var m = scene.skirmish
	check(m.flag_ids.size() == 2, "Capture the Flag: a flag per side")
	var flag_targets := 0
	var targets := 0
	for i in roundi(90.0 * 40.0):
		if scene.skirmish.over: break
		scene.simulation_step(0.025)
		if i % 40 != 0: continue
		for p in 2:
			for s in scene.ai_manager.players[p].monster_slots:
				if s.is_empty(): continue
				targets += 1
				if String(s.kind) == "building" and m.flag_ids.has(int(s.id)): flag_targets += 1
	print("  Capture the Flag: %d target slots filled, %d of them flags" % [targets, flag_targets])
	check(targets > 0 and flag_targets == 0, "Capture the Flag: the Rampant computers never target a flag (0x4fa990 -500)")
	close(scene)

## The options whose start equals Standard Victory's once the setup side effects are copied (build level, teams): the
## computer reads none of them, so its decisions match option 0 exactly. Raze All Buildings, Kill All Units, Raze Fest,
## Slug Fest, Fortress, King of the Castle, Merchants.
func unchanged_options():
	var minutes := 3.0
	var reference := {}
	var first_key := ""
	var first_setup := {}
	for option in [1, 2, 4, 5, 6, 7, 8]:
		var with_option := setup_for(option, [3, 6])
		var standard := setup_for(0, [3, 6])
		standard.options.build_level = int(with_option.options.build_level)
		for i in 2: standard.players[i].team = int(with_option.players[i].team)
		var key := "%d/%s" % [int(standard.options.build_level), with_option.players.map(func(p): return int(p.team))]
		if not reference.has(key): reference[key] = await trace(standard, minutes, "standard")
		if first_key == "":
			first_key = key
			first_setup = standard
		var traced: Array = await trace(with_option, minutes, "option-%d" % option)
		var differs := -1
		for t in mini(traced.size(), reference[key].size()):
			if traced[t] != reference[key][t]:
				differs = t
				break
		print("  option %d: %d samples, first difference %d" % [option, traced.size(), differs])
		check(traced.size() == reference[key].size() and differs < 0, "option %d: the computers decide as under Standard Victory" % option)
	# The trace is sensitive: the first Standard Victory start with another combat seed word decides differently.
	var reseeded: Array = await trace(first_setup, minutes, "reseeded", 4242)
	check(reseeded != reference[first_key], "the trace tells two runs apart (another seed differs)")

func trace(setup: Dictionary, minutes: float, label: String, seed: int = -1) -> Array:
	var scene = await new_scene()
	if seed >= 0: scene.combat_seed = [seed, scene.combat_seed[1]]
	check(scene.start_skirmish(setup.duplicate(true), "", null, "victory-ai-" + label), label + " starts")
	var out: Array = []
	for i in roundi(minutes * 60.0 * 40.0):
		if scene.skirmish.over: break
		scene.simulation_step(0.025)
		if i % 400 != 0: continue
		var row: Array = []
		for p in 2:
			var s: Dictionary = scene.ai_manager.players[p].summary()
			row.append(JSON.stringify([s.units, s.buildings, s.resources, s.mines, s.workers, s.groups, s.main_enemy, s.stats]))
		out.append(row)
	close(scene)
	return out
