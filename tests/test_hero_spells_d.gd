extends "res://tests/test_hero_spells_c.gd"
## Hero spells B1-6d (SPELLS_RESEARCH.md section "B1-6d") against tests/hero_spell_d_fixtures.json
## (tools/emulate_hero_spells_d.py), on B1-6a..c's world and helpers:
## 1. every builder of Summoning (10-19; Banish 18 is B1-6c's) and Illusion (30-39) at levels 1-4 equals the original
##    records cast by a hero (all fields, the full descriptors, the summon types by race, the command checks, Blink's rolled
##    cell under eight seeds and at the map edge, Home Portal's start location, Transform's roll with and without a keep);
## 2. the applier on every fixture world (targets, created units and their lifetime / illusion flag, Shadowform's block,
##    invisibility, the fear word and count, the teleports, Mutate's animals and resisting units, Transform's morphs);
## 3. the consumers: Shadowform's speed / armour / magic armour (fixture "shadow"), the illusion block (fixture
##    "illusion_data"), the lifetimes, the fear count and the halved attack rate (B1-6b's review rows), invisibility's
##    search / order / pick / reveal rules;
## 4. the cast path 0x5717e0 for the spells under eight seeds, and each spell ordered and dispatched by a hero.

## B1-3's weather object as Light/Darkness reads it (0x499a50 night, 0x49bb10 rain).
class RainDayNight extends RefCounted:
	var night := false
	var raining := false
	var records: Array = []
	func apply_record(amount: int): records.append(amount)
	func is_night() -> bool: return night

const SPELLS_D := [10, 11, 12, 13, 14, 15, 16, 17, 19, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39]
const CASTER := Vector2i(40, 40)

func run():
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_spell_d_fixtures.json"))
	for i in 8: seeds.append(fx.cast_path[i].seed)
	centre = open_ground()
	check(centre.x >= 0, "open ground for the hero spell world")
	if centre.x >= 0:
		for part in ["records_d", "applier_d", "consumers_d", "cast_path_d", "cast_all_d"]:
			var t0 := Time.get_ticks_msec()
			call(part)
			print("%s: %d ms" % [part, Time.get_ticks_msec() - t0])
	clear_world()
	if failures > 0:
		printerr("Hero spell D checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Hero spell D checks passed: %d" % checks)
	quit(0)

## The spells of the two schools this build casts (a school's builders arrive with its commit).
func built() -> Array:
	return SPELLS_D.filter(func(s): return HeroSpells.castable(s))

# ------------------------------------------------------------------------------------------------ the worlds
## tools/emulate_hero_spells_d.py world_for as [kind, code, side, offset, extra].
func fixture_world(scenario: String) -> Array:
	match scenario:
		"cavalry":
			return [["unit", "AHKX", "own", Vector2i(1, 0), {}], ["unit", "AHKX", "own", Vector2i(0, 9), {}], ["unit", "AHKX", "own", Vector2i(0, 10), {}],
				["unit", "AHIX", "own", Vector2i(-1, 0), {}], ["unit", "AHKX", "enemy", Vector2i(2, 2), {}], ["unit", "AHKX", "own", Vector2i(-2, 2), {"hp": 0}],
				["unit", "AHFX", "own", Vector2i(3, -1), {}], ["unit", "AHLX", "own", Vector2i(-3, -1), {}], ["unit", "ADLX", "own", Vector2i(2, -3), {}],
				["unit", "AEDX", "own", Vector2i(-2, -3), {}]]
		"fear":
			return [["unit", "AHIX", "enemy", Vector2i(1, 0), {}], ["unit", "AHKX", "enemy", Vector2i(2, 0), {}], ["unit", "AUIX", "enemy", Vector2i(3, 0), {}],
				["unit", "AUBX", "enemy", Vector2i(0, 2), {}], ["unit", "AADE", "enemy", Vector2i(0, 3), {}], ["unit", "AADR", "enemy", Vector2i(-3, 0), {}],
				["unit", "AHFX", "enemy", Vector2i(-2, 1), {}], ["unit", "ACSH", "enemy", Vector2i(-1, 3), {}], ["unit", "AWJX", "enemy", Vector2i(2, -2), {}],
				["unit", "ADIX", "enemy", Vector2i(-2, -2), {}], ["unit", "AEDX", "enemy", Vector2i(3, 3), {}], ["unit", "AAEF", "enemy", Vector2i(-3, 3), {}],
				["unit", "AHIX", "own", Vector2i(-1, -1), {}], ["unit", "AHIX", "enemy", Vector2i(0, 9), {}], ["unit", "AHIX", "enemy", Vector2i(0, 10), {}],
				["unit", "AUHX", "enemy", Vector2i(1, -3), {"hero": true}], ["unit", "AUJX", "enemy", Vector2i(4, 1), {}],
				["unit", "AABA", "enemy", Vector2i(4, -1), {}], ["unit", "AHLX", "enemy", Vector2i(-4, 1), {}], ["unit", "ADLX", "enemy", Vector2i(-4, -1), {}]]
		"mutate":
			return [["unit", "AHIX", "enemy", Vector2i(1, 0), {"rank": 0}], ["unit", "AHIX", "enemy", Vector2i(2, 0), {"rank": 1}],
				["unit", "AHIX", "enemy", Vector2i(3, 0), {"rank": 2}], ["unit", "AHIX", "enemy", Vector2i(4, 0), {"rank": 3}],
				["unit", "AHIX", "enemy", Vector2i(0, 2), {"rank": 5}], ["unit", "AHFX", "enemy", Vector2i(0, 3), {}],
				["unit", "AABA", "enemy", Vector2i(-2, 0), {}], ["unit", "AWJX", "enemy", Vector2i(-3, 0), {}], ["unit", "ACSH", "enemy", Vector2i(-1, 2), {}],
				["unit", "AUHX", "enemy", Vector2i(2, -2), {"hero": true}], ["unit", "AADE", "enemy", Vector2i(-2, -2), {}],
				["unit", "AUIX", "enemy", Vector2i(3, 3), {}], ["unit", "AHKX", "enemy", Vector2i(-3, 3), {}], ["unit", "AHIX", "own", Vector2i(-1, -1), {}],
				["unit", "AHIX", "enemy", Vector2i(0, 9), {}], ["unit", "AHIX", "enemy", Vector2i(0, 10), {}], ["unit", "AADR", "enemy", Vector2i(4, -3), {}]]
		"transform", "transform keep":
			var out: Array = [["unit", "AHIX", "own", Vector2i(1, 0), {}], ["unit", "AHKX", "own", Vector2i(2, 0), {}], ["unit", "AHFX", "own", Vector2i(3, 0), {}],
				["unit", "AUIX", "own", Vector2i(0, 2), {}], ["unit", "AHLX", "own", Vector2i(0, 3), {}], ["unit", "ACSH", "own", Vector2i(-1, 2), {}],
				["unit", "AADE", "own", Vector2i(-2, 0), {}], ["unit", "AHIX", "enemy", Vector2i(-3, 0), {}], ["unit", "AHIX", "own", Vector2i(0, 9), {}],
				["unit", "AHIX", "own", Vector2i(0, 10), {}], ["unit", "ADIX", "own", Vector2i(-2, -2), {}], ["unit", "AEDX", "own", Vector2i(2, -2), {}],
				["unit", "AABA", "own", Vector2i(3, 3), {}], ["unit", "AWJX", "own", Vector2i(-3, 3), {}], ["unit", "AUBX", "own", Vector2i(4, 1), {}],
				["building", "BKD0", "own", Vector2i(-5, -4), {}]]
			if scenario == "transform keep": out.append(["building", "BKH2", "own", Vector2i(6, 5), {}])
			return out
		"teleport":
			return [["unit", "AHIX", "own", Vector2i(1, 0), {}], ["unit", "AHIX", "enemy", Vector2i(-1, 0), {}]]
	return super.fixture_world(scenario)

## The world name of a scenario ("transform seed 3" -> "transform").
func base_scenario(scenario: String) -> String:
	if scenario.begins_with("transform keep"): return "transform keep"
	if scenario.begins_with("transform"): return "transform"
	if scenario.begins_with("seed ") or scenario == "edge" or scenario == "start": return "empty"
	if scenario.begins_with("race "): return "empty"
	return scenario

func build_world_d(scenario: String) -> Dictionary:
	var ids: Dictionary = build_world(base_scenario(scenario), "AUHX")
	var list := fixture_world(base_scenario(scenario))
	for i in list.size():
		var e: Array = list[i]
		if e[0] == "unit" and bool(e[4].get("hero", false)): world.combat.fighters[int(ids[str(i + 2)].id)].hero = true
	if scenario.begins_with("race "): world.production.races[OWNER] = int(scenario.split(" ")[1])
	if scenario in ["start", "teleport"]: world.host.start_cells[OWNER] = centre + Vector2i(6, 5)
	if scenario.begins_with("weather"):
		var dn := RainDayNight.new()
		dn.night = scenario.contains("night")
		dn.raining = scenario.contains("rain")
		world.host.day_night = dn
	if scenario.contains("command full"): set_command(OWNER, used(OWNER))
	elif scenario.contains("command one left"): set_command(OWNER, used(OWNER) + 1)
	world.combat.rng.seed_state(12345, 678)                    # the emulator's generator at a new world (emulate_spells SEED)
	if scenario.contains("seed "): seed_rng(int(scenario.split(" ")[-1]))
	return ids

func target_for(spell: int, choice: int = 0) -> Dictionary:
	var cell := centre + TARGET
	return {"x": cell.x, "y": cell.y, "id": -1, "extra": choice}

# ------------------------------------------------------------------------------------------------ 1. records
func records_d():
	var count := 0
	var diffs: Array = []
	# The builders change nothing in the world (the rolls aside: the generator is seeded per case): one world per scenario.
	var by_scenario := {}
	for spell in built():
		for c in cases(spell): by_scenario[String(c.scenario)] = true
	for scenario in by_scenario:
		build_world_d(scenario)
		var h: int = world.host.hero_unit_id
		var f = world.combat.fighters[h]
		var cell0: Vector2i = world.units[h].cell
		for spell in built():
			for c in cases(spell):
				if String(c.scenario) != scenario: continue
				world.units[h].cell = cell0
				world.combat.rng.seed_state(12345, 678)
				if scenario.contains("seed "): seed_rng(int(scenario.split(" ")[-1]))
				count += _record_case(spell, c, h, f, diffs)
	print("records_d: %d cases of %d spells" % [count, built().size()])
	check(diffs.is_empty(), "B1-6d: %d record cases of %d spells equal the original %s" % [count, built().size(), diffs.slice(0, 6)])
	check(count >= built().size() * 4, "every built spell compared at four levels at least (%d)" % count)

func _record_case(spell: int, c: Dictionary, h: int, f, diffs: Array) -> int:
	var scenario := String(c.scenario)
	if scenario == "edge":
		# Blink at the map edge: the caster stands at (3, 3); the rolled cell is clamped into 1 .. size - 2.
		world.units[h].cell = Vector2i(3, 3)
		var want_cell := Vector2i(int(c.free_cells[0].x), int(c.free_cells[0].y))
		var got_cell: Vector2i = world.spells.blink_cell(f)
		if got_cell != want_cell: diffs.append("Blink edge L%d: %s != %s" % [int(c.level), got_cell, want_cell])
		return 1
	var got := built_list(builder_record(spell, h, int(c.level), target_for(spell)))
	var want := records_of_case(c)
	var label := "%s %s L%d" % [fx.spells[str(spell)].name, scenario, int(c.level)]
	if got.size() != want.size():
		diffs.append("%s: %d records (original %d)" % [label, got.size(), want.size()])
		return 1
	for i in got.size():
		var d := compare_b(got[i], want[i])
		if int(want[i].kind) == SpellEffects.ILLUSIONS and text(got[i].summon) != text(want[i].summon): d.append("summon %s != %s" % [got[i].summon, text(want[i].summon)])
		if int(want[i].kind) == SpellEffects.ILLUSIONS and got[i].cells.size() != int(want[i].amount): d.append("cells %d" % got[i].cells.size())
		if int(want[i].kind) == SpellEffects.TELEPORT and scenario != "empty":
			var cell: Vector2i = got[i].cells[0]
			if spell == 13 and cell - centre != Vector2i(int(want[i].cells[0][0]), int(want[i].cells[0][1])) - CASTER: d.append("cell %s" % [cell - centre])
			if spell == 16 and cell != centre + Vector2i(6, 5): d.append("start cell %s" % [cell - centre])
		if not d.is_empty(): diffs.append("%s record %d: %s" % [label, i, d])
	if scenario.contains("seed ") or spell in [13, 39]:
		var rng := [world.combat.rng.first, world.combat.rng.second]
		if rng != [int(c.rng[1][0]), int(c.rng[1][1])]: diffs.append("%s: generator %s" % [label, rng])
	return 1

# ------------------------------------------------------------------------------------------------ 2. the applier
## The fixture's application against the rebuild's: targets, created units (0xfa) and morphs (0x1f4), per-object state.
func compare_d(spell: int, c: Dictionary, info: Dictionary, ids: Dictionary) -> Array:
	var diff: Array = []
	var results: Array = info.get("results", [info.get("result", {})])
	var want_targets: Array = []
	var made: Array = []
	var morphs: Array = []
	for st in c.applied:
		for m in st.sent:
			if m.message == "0x1f7" and st.stage == "area": want_targets.append(fixture_offsets(m.target_ids, ids))
			if m.message == "0xfa": made.append(m)
			if m.message == "0x1f4": morphs.append(String(m.type))
	var got_targets: Array = []
	var created: Array = []
	var got_morphs: Array = []
	for r in results:
		if r.is_empty() or int(r.get("kind", -1)) == SpellEffects.DAY_NIGHT: continue
		got_targets.append(offsets(r.targets, ids))
		created += r.summoned + r.mutated
		for t in r.transformed: got_morphs.append(String(t.type))
	for i in mini(got_targets.size(), want_targets.size()):
		if (not want_targets[i].is_empty() or not got_targets[i].is_empty()) and got_targets[i] != want_targets[i]:
			diff.append("targets %s != %s" % [got_targets[i], want_targets[i]])
	if created.size() != made.size(): diff.append("created %d != %d" % [created.size(), made.size()])
	elif spell == 38:
		# Mutate: ACSH / ACPE (ACCA / ACCO for flyers) by the target's even / odd index in the gather, whose order inside a
		# grid row is B1-4 Open 2 (the harness links the newest node first): the animal class and owner 6 are compared.
		var cls := func(t: String) -> String: return "air" if t in ["ACCA", "ACCO"] else ("goat" if t == "ACGO" else "ground")
		var want_c: Array = made.map(func(m): return cls.call(String(m.type)))
		var got_c: Array = created.map(func(g): return cls.call(String(g.type)))
		want_c.sort()
		got_c.sort()
		if got_c != want_c: diff.append("animals %s != %s" % [got_c, want_c])
		if created.any(func(g): return int(g.owner) != SpellEffects.NEUTRAL): diff.append("an animal not of player 6")
	else:
		for i in made.size():
			var m: Dictionary = made[i]
			var g: Dictionary = created[i]
			var gf = world.combat.fighters.get(int(g.id))
			if String(g.type) != String(m.type): diff.append("created %s != %s" % [g.type, m.type])
			if int(g.owner) != (int(m.owner) if int(m.owner) != OWNER else OWNER): diff.append("owner %d != %d" % [int(g.owner), int(m.owner)])
			if gf != null and bool(gf.get("illusion", false)) != (String(m.name) == "Illusion_Data_Only"): diff.append("illusion flag %s" % g.type)
			if int(g.get("lifetime", 0)) != int(m.lifetime): diff.append("lifetime %d != %d" % [int(g.get("lifetime", 0)), int(m.lifetime)])
	got_morphs.sort()
	morphs.sort()
	if got_morphs != morphs: diff.append("morphs %s != %s" % [got_morphs, morphs])
	var now: int = world.spells.now()
	for k in c.after:
		var want: Dictionary = c.after[k]
		var before: Dictionary = c.before[k]
		if not ids.has(k) or ids[k].kind != "unit": continue
		var f = world.combat.fighters[int(ids[k].id)]
		var o: Vector2i = ids[k].offset
		if f.removed and spell in [38, 39]: continue                    # mutated / morphed: compared through the messages
		if k != "1" and int(want.hp) != int(before.hp) and int(f.hp) != int(want.hp): diff.append("%s hp %d != %d" % [o, int(f.hp), int(want.hp)])
		var sh = world.spells.shadow_block(f)
		var want_sh: Array = want.get("shadow", [0, 0, 0, 0, 0])
		var got_sh: Array = [1, int(sh.speed), int(sh.armour), int(sh.magic), int(sh.until) - now + 50000] if sh != null else [0, 0, 0, 0, 0]
		if got_sh != want_sh.map(func(v): return int(v)): diff.append("%s shadow %s != %s" % [o, got_sh, want_sh])
		var want_inv: Array = want.get("invisible", [0, 0])
		var got_inv: Array = [1, int(f.invisible_until) - now + 50000] if f.has("invisible_until") else [0, 0]
		if got_inv != want_inv.map(func(v): return int(v)): diff.append("%s invisible %s != %s" % [o, got_inv, want_inv])
		var fear = f.get("fear")
		var got_fear: Array = [int(fear.bits), int(fear.seconds)] if fear != null else [0, 0]
		if got_fear != [int(want.get("ba16", 0)), int(want.get("b128", 0))]: diff.append("%s %s fear %s != %s" % [o, f.type_id, got_fear, [want.get("ba16"), want.get("b128")]])
		if want.has("cell") and before.has("cell") and want.cell != before.cell:
			var moved: Vector2i = world.combat.unit_cell(int(f.id)) - centre
			var want_cell := Vector2i(int(want.cell[0]), int(want.cell[1])) - CASTER
			if spell == 16: want_cell = Vector2i(6, 5)
			if moved != want_cell: diff.append("%s moved to %s, original %s" % [o, moved, want_cell])
	return diff

func applier_d():
	var compared := 0
	var diffs: Array = []
	for spell in built():
		for c in cases(spell):
			if not c.has("applied") or String(c.scenario) == "edge": continue
			if spell == 16 and String(c.scenario) == "empty": continue     # the harness's start (0, 0): no skirmish start
			var scenario := String(c.scenario)
			# levels 1 and 4 (the others only scale the same amounts); Blink's level changes nothing: level 1 per seed
			if int(c.level) in [2, 3] or (spell == 13 and int(c.level) != 1): continue
			# the races only change the type (every race's record is compared above): three races' applications
			if scenario.begins_with("race ") and not scenario in ["race 0", "race 2", "race 16"]: continue
			if scenario.contains("seed ") and spell == 39 and int(c.level) != 1: continue
			var ids := build_world_d(scenario)
			var h: int = world.host.hero_unit_id
			var record: Dictionary = builder_record(spell, h, int(c.level), target_for(spell))   # build_world_d seeds the generator
			var info: Dictionary = world.spells.cast_built(record, caster_dict(h), int(c.level), spell)
			var d := compare_d(spell, c, info, ids)
			if spell == 32 and (world.host.day_night.records.is_empty() or int(world.host.day_night.records.back()) != int(records_of_case(c)[0].amount)):
				d.append("kind 4 amount %s" % [world.host.day_night.records])
			if not d.is_empty(): diffs.append("%s %s L%d: %s" % [fx.spells[str(spell)].name, scenario, int(c.level), d])
			compared += 1
	print("applier_d: %d applications" % compared)
	check(diffs.is_empty(), "B1-6d: %d applications equal the original %s" % [compared, diffs.slice(0, 6)])

# ------------------------------------------------------------------------------------------------ 3. consumers
func consumers_d():
	# Shadowform's block (fixture "shadow": 0x51c460(1), 0x526b70(1), 0x5260a0 word 0 with +0x1e4..+0x1e7).
	var plain := {}
	for r in fx.shadow:
		if r.block == null: plain[String(r.type)] = r
	var diffs: Array = []
	for r in fx.shadow:
		if r.block == null or String(r.type) == "AUHX": continue
		build_world("empty", "AUHX")
		var id := unit(String(r.type), Vector2i(2, 0), OWNER)
		var f = world.combat.fighters[id]
		var s0: int = world.spells.speed_term(f)
		var b0: Dictionary = world.combat.combat_block(f)
		if int(r.flag) == 1: world.spells.shadow({"kind": "unit", "id": id}, int(r.block[0]), int(r.block[1]), int(r.block[2]), world.spells.now() + 60000)
		var b1: Dictionary = world.combat.combat_block(f)
		# The original's deltas against the plain unit of the same type (AHIX); for AHKX the block values the AHIX rows show
		# are added unchanged.
		var want := [int(r.block[0]) * int(r.flag), int(r.block[1]) * int(r.flag), int(r.block[2]) * int(r.flag)]
		if plain.has(String(r.type)):
			var p: Dictionary = plain[String(r.type)]
			want = [int(r.speed) - int(p.speed), int(r.armour[0]) - int(p.armour[0]), int(r.magic_armour) - int(p.magic_armour)]
		var got := [world.spells.speed_term(f) - s0, int(b1.armour) - int(b0.armour), int(b1.mres) - int(b0.mres)]
		if got != want: diffs.append("%s %s: %s != %s" % [r.type, r.block, got, want])
	check(diffs.is_empty(), "Shadowform's block: speed, armour word 0 and magic armour as 0x51c460 / 0x5260a0 / 0x526b70 %s" % [diffs])
	# Shadowform ends once now passes +0x1e8.
	build_world("empty", "AUHX")
	var h: int = world.host.hero_unit_id
	var hf = world.combat.fighters[h]
	world.spells.shadow({"kind": "unit", "id": h}, 2, 5, 5, world.spells.now() + 1000)
	run_world(1100)
	check(world.spells.shadow_block(hf) == null and not hf.has("shadow"), "Shadowform: the block clears once now passes +0x1e8")
	# The lifetime of a summon (Eye of Oros 15): +0x1ec, the unit dies once now passes it.
	if 15 in built():
		build_world("empty", "AUHX")
		h = world.host.hero_unit_id
		var info: Dictionary = world.spells.cast_built(builder_record(15, h, 1, target_for(15)), caster_dict(h), 1, 15)
		var eyes: Array = info.result.summoned
		check(eyes.size() == 2 and eyes.all(func(e): return int(e.lifetime) == 30000), "Eye of Oros level 1: two eyes living 30 s (%s)" % [eyes])
		run_world(29000)
		var alive_before: bool = eyes.all(func(e): return world.combat.alive(world.combat.fighters[int(e.id)]))
		run_world(1200)
		var dead_after: bool = eyes.all(func(e): return not world.combat.alive(world.combat.fighters[int(e.id)]))
		check(alive_before and dead_after, "Eye of Oros: alive at 29 s, dead after 30 s (0x51c7d0 +0x1ec)")
		run_world(100)
		check(eyes.all(func(e): return bool(world.combat.fighters[int(e.id)].removed)), "Eye of Oros: the timed bodies go at once (0x51a130(1), REVIEW D1)")
	# Blink and Home Portal move the caster; a blocked target cell gives the nearest reachable free one.
	if 13 in built():
		build_world("empty", "AUHX")
		h = world.host.hero_unit_id
		var blocker := unit("AHIX", Vector2i(3, 3), OWNER)
		var cell: Vector2i = world.spells.reachable_cell(world.spells.object_of("unit", h), centre + Vector2i(3, 3))
		check(cell != centre + Vector2i(3, 3) and cell.x >= 0 and world.nav.occupant(cell, null) == null,
			"0x530a90 (reachable): an occupied cell gives the nearest free reachable one (%s)" % [cell - centre])
		world.combat.rng.seed_state(int(seeds[2][0]), int(seeds[2][1]))
		var info: Dictionary = world.spells.cast_built(builder_record(13, h, 1, {}), caster_dict(h), 1, 13)
		check(info.result.moved.size() == 1 and world.combat.unit_cell(h) == info.result.moved[0].cell and blocker >= 0, "Blink: the hero stands at its new cell")
	if 16 in built():
		build_world_d("start")
		h = world.host.hero_unit_id
		world.spells.cast_built(builder_record(16, h, 1, {}), caster_dict(h), 1, 16)
		check(world.combat.unit_cell(h) == centre + Vector2i(6, 5), "Home Portal: the hero stands at its start location")
	# B1-6c's found item: Heal Self's hero skill term 0x3c (fixture "heal_self_skill").
	var heal: Array = []
	for r in fx.heal_self_skill:
		new_world()
		var hero_id := hero("AUHX", {}, OWNER, Vector2i.ZERO, [7, 5, 8, 4], [{"id": 0x3c, "unlock_level": 1, "rank": int(r.rank)}] if int(r.rank) > 0 else [])
		var rec: Dictionary = builder_record(0, hero_id, int(r.level), {})
		if int(rec.amount) != int(r.amount): heal.append("rank %d L%d: %d != %d" % [int(r.rank), int(r.level), int(rec.amount), int(r.amount)])
	check(heal.is_empty(), "Heal Self: power(50 x level) + the hero skill term 0x3c, %d rows %s" % [fx.heal_self_skill.size(), heal])
	if 34 in built(): illusion_consumers()
	if 31 in built(): fear_consumers()
	if 36 in built(): invisibility_consumers()

## The illusion block (fixture "illusion_data": 0x43c450 against 0x43bfb0) on the rebuild's fighter block.
func illusion_consumers():
	var diffs: Array = []
	var compared := 0
	for r in fx.illusion_data:
		if r.get("missing", false) or not world.production.rules.definition(String(r.type)).has("raw_hex"): continue
		build_world("empty", "AUHX")
		var id := unit(String(r.type), Vector2i(3, 0), OWNER)
		var f = world.combat.fighters[id]
		world.spells.make_illusion(f)
		var b: PackedByteArray = String(r.illusion).hex_decode()
		var want := [b.decode_s16(0x56), b.decode_s16(0x5a), b.decode_s16(0x5c), b.decode_s16(0x62), b.decode_s16(0x66), b.decode_s16(0x68),
			b.decode_s16(0x6a), b.decode_s16(0x6c)]
		var got := [int(f.base.combat), int(f.base.mres), int(f.max_hp), int(f.base.dmg), int(f.base.range), int(f.base.armour), int(f.base.res1), int(f.base.res2)]
		if got != want: diffs.append("%s %s != %s" % [r.type, got, want])
		if not bool(f.get("illusion", false)): diffs.append("%s flag" % r.type)
		compared += 1
	check(diffs.is_empty() and compared >= 16, "illusions: %d types' blocks equal 0x43c450's (combat 1, magic armour 0, hit points / 4, damage 1, range / 2, armour 0, resistances -1) %s" % [compared, diffs.slice(0, 4)])
	# Spectral Horde: the illusions die once their 120 s x level pass (+0x1ec).
	build_world("empty", "AUHX")
	var h: int = world.host.hero_unit_id
	var info: Dictionary = world.spells.cast_built(builder_record(34, h, 1, target_for(34)), caster_dict(h), 1, 34)
	var horde: Array = info.result.summoned
	run_world(119500)
	var alive_before: bool = horde.all(func(e): return world.combat.alive(world.combat.fighters[int(e.id)]))
	run_world(1000)
	check(horde.size() == 6 and alive_before and horde.all(func(e): return not world.combat.alive(world.combat.fighters[int(e.id)])),
		"Spectral Horde level 1: six illusions, gone after 120 s")
	# Resurrection (0x4aa840 case 5, Read): the bodies of illusions (+0x1f0) and timed summons (+0x1ec) do not rise.
	var dead_knight := unit("AHKX", Vector2i(-2, 1), OWNER)
	world.combat.apply_damage("unit", dead_knight, 1000, -1, "unit")
	world.combat.fighters[h].mana = 200
	var res: Dictionary = world.spells.cast_built(builder_record(9, h, 1, {}), caster_dict(h), 1, 9)
	var risen: Array = res.result.resurrected.map(func(m): return String(m.type))
	check(risen == ["AHKX"], "Resurrection: the knight rises, the illusions' bodies do not (%s)" % [risen])

## Scare / Awe: the fear count (+0x128, 1 s steps of 0x532a20) and the halved attack rate (0x51c6a0; B1-6b's review rows).
func fear_consumers():
	var review: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_spells_b_review_fixtures.json"))
	var plain := {}
	for r in review.consumers:
		if int(r.ba) == 0 and r.berserk == null and not bool(r.hero): plain["%s %s" % [r.code, r.effects]] = int(r.rate)
	var diffs: Array = []
	var compared := 0
	for r in review.consumers:
		if int(r.ba) == 0 or bool(r.hero) or r.berserk != null: continue
		build_world("empty", "AUHX")
		var id := unit(String(r.code), Vector2i(2, 0), ENEMY)
		var f = world.combat.fighters[id]
		for e in r.effects: status_on(f, int(e[0]), int(e[1]))
		f["fear"] = {"bits": int(r.ba), "seconds": 100, "next_ms": 1 << 40}
		var base: int = ResearchEffects_rate(String(r.code))
		var got: int = world.spells.attack_rate(f, base)
		if got != int(r.rate): diffs.append("%s %s ba %d: %d != %d" % [r.code, r.effects, int(r.ba), got, int(r.rate)])
		compared += 1
	check(diffs.is_empty() and compared >= 5, "fear: %d attack-rate rows with +0xba bits equal 0x51c6a0 (bits 1 / 2 / 4 halve, bit 8 does not) %s" % [compared, diffs])
	build_world_d("fear")
	var h: int = world.host.hero_unit_id
	world.spells.cast_built(builder_record(31, h, 1, {}), caster_dict(h), 1, 31)
	var scared: Array = world.combat.fighters.values().filter(func(f): return f.get("fear") != null)
	run_world(44000)
	var still: bool = scared.all(func(f): return f.get("fear") != null)
	run_world(1500)
	check(not scared.is_empty() and still and scared.all(func(f): return f.get("fear") == null), "Scare: %d enemies afraid for 45 s, then not" % scared.size())

func ResearchEffects_rate(type_id: String) -> int:
	return preload("res://simulation/research_effects.gd").attack_rate(type_id)

## Invisibility: an enemy's attack order on the invisible hero goes (0x51e670), searches skip it (0x5334f0), the local
## player who lacks See Invisible cannot see it, its own attack or damage ends it.
func invisibility_consumers():
	build_world("empty", "AUHX")
	var h: int = world.host.hero_unit_id
	world.host.visibility = Visibility.new(128, 128)
	var e := unit("AHKX", Vector2i(7, 0), ENEMY)
	check(world.combat.order_attack(e, "unit", h), "the enemy knight attacks the hero")
	world.spells.cast_built(builder_record(36, h, 1, {}), caster_dict(h), 1, 36)
	var ef = world.combat.fighters[e]
	run_world(500, func(): return ef.order == null)
	check(ef.order == null, "Invisibility: the enemy's attack order on the invisible hero is dropped (0x51e670)")
	check(world.combat.candidate_for_owner(ENEMY, e, world.combat.unit_cell(h), false) == null, "Invisibility: a search never finds the hero (0x5334f0)")
	check(world.host.visibility.invisible.has(h), "Invisibility: visibility.gd hides the hero from other players")
	world.combat.apply_damage("unit", h, 1, e, "unit")
	check(not world.spells.is_invisible(h), "Invisibility: damage ends it (0x522860)")
	world.spells.cast_built(builder_record(36, h, 1, {}), caster_dict(h), 1, 36)
	run_world(60100)
	check(not world.spells.is_invisible(h), "Invisibility level 1: ends after 60 s (+0x1f4)")

# ------------------------------------------------------------------------------------------------ 4. the cast path
func cast_path_d():
	var diff: Array = []
	var compared := 0
	var circle := ""
	build_world_d("start")
	var h: int = world.host.hero_unit_id
	for row in fx.cast_path:
		var spell := int(row.spell)
		if not HeroSpells.castable(spell): continue
		if String(row.get("world", "")) != circle:
			# rows with a Circle of Power (BMCP) at (4, 3): + 1 level, the summon next to it (0x548c30 / 0x43b4c0)
			circle = String(row.world)
			build_world_d("start")
			h = world.host.hero_unit_id
			if circle == "circle": building("BMCP", Vector2i(4, 3), OWNER, {})
		world.combat.fighters[h]["cast"] = null
		world.production.races[OWNER] = int(row.race)
		world.hs.pending = {}
		world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 10 + spell / 10, "unlock_level": 1, "rank": int(row.rank)}]
		world.combat.fighters[h].mana = 200
		world.combat.rng.seed_state(int(row.seed[0]), int(row.seed[1]))
		var result: Dictionary = world.hs.cast_request(h, spell)
		var sent: Dictionary = {}
		for m in row.sent: if m.message == "0x118": sent = m
		var f = world.combat.fighters[h]
		var ok: bool = [world.combat.rng.first, world.combat.rng.second] == [int(row.rng_after[0]), int(row.rng_after[1])]
		if not sent.is_empty():
			var c = f.get("cast")
			ok = ok and c != null and int(c.level) == int(sent.level)
			if ok and int(sent.target[3]) != 0 and circle == "circle":
				# the harness's building stamps no cells, so the original's free cell is the circle's own node cell; the
				# rebuild's stamped circle gives the free cell next to it
				var t: Vector2i = Vector2i(int(c.target.x), int(c.target.y)) - world.combat.unit_cell(h)
				ok = maxi(absi(t.x - 4), absi(t.y - 3)) <= 2 and Vector2i(int(sent.target[3]), int(sent.target[4])) - CASTER == Vector2i(4, 3)
			elif ok and int(sent.target[3]) != 0:
				ok = Vector2i(int(c.target.x), int(c.target.y)) - world.combat.unit_cell(h) == Vector2i(int(sent.target[3]), int(sent.target[4])) - CASTER
		elif row.pending != null:
			ok = ok and String(world.hs.pending.get("mode", "")) == "place" and int(world.hs.pending.level) == int(row.pending.level)
		else:
			ok = ok and not bool(result.get("cast", false))
		if not ok: diff.append("%d race %d seed %s: %s" % [spell, int(row.race), row.seed[0], result])
		compared += 1
	print("cast_path_d: %d rows" % compared)
	check(diff.is_empty() and compared > 0, "0x5717e0: %d cast-path rows of the two schools equal the original %s" % [compared, diff.slice(0, 4)])

## Every built spell cast by the hero through the human path: the request, the placement click, order 9, the event, the
## dispatcher, the record applied.
func cast_all_d():
	var failed: Array = []
	for spell in built():
		build_world_d("start")
		var h: int = world.host.hero_unit_id
		world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 10 + spell / 10, "unlock_level": 1, "rank": 15 if spell % 10 < 5 else 25}]
		var f = world.combat.fighters[h]
		f.mana = 200
		f.max_mana = 200
		world.combat.rng.seed_state(12345, 678)
		var request: Dictionary = world.hs.cast_request(h, spell)
		if request.get("pending", "") == "place": request = world.hs.place(world.combat.unit_cell(h) + Vector2i(4, 4))
		if not bool(request.get("cast", false)):
			failed.append("%d: %s" % [spell, request])
			continue
		var dispatched := {}
		var on_cast := func(info): dispatched.merge(info, true)
		world.spells.cast_done.connect(on_cast)
		run_world(4000, func(): return f.get("cast") == null)
		world.spells.cast_done.disconnect(on_cast)
		if dispatched.is_empty() or int(f.mana) >= 200: failed.append("%d: not dispatched (mana %d)" % [spell, int(f.mana)])
	check(failed.is_empty(), "all %d built spells of Summoning and Illusion cast by the hero's own path %s" % [built().size(), failed.slice(0, 6)])
