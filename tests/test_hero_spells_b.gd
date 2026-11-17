extends "res://tests/test_hero_spells.gd"
## Hero spells B1-6b (SPELLS_RESEARCH.md section "B1-6b") against tests/hero_spell_b_fixtures.json
## (tools/emulate_hero_spells_b.py), on B1-6a's world and helpers (tests/test_hero_spells.gd):
## 1. every builder of Healing (0-9), Pyromancy (50-59), Ice (80-89) and Poison (100-109) at levels 1-4 equals the original
##    records cast by a hero (all fields, the full status descriptors, both records of Purify and Call of Kargoth, Storm by
##    day and by night, the effect 0x2a scaling, Life Ward refused while warded, the summons' command checks);
## 2. the applier on every fixture world: targets, hit points, poison / disease, statuses, summons and resurrections,
##    experience, berserk, Calm, Rot, the mana gate, missiles;
## 3. the status consumers (combat, magic armour, attack 0x17, speed and attack rate, Life Ward, Venom Touch, Poison Gate,
##    Freeze Magic) and the arrow resistance (Rules.arrow_damage) against every unit row of the "arrows" fixture;
## 4. the cast path 0x5717e0 for all forty spells under eight seeds, and each spell ordered and dispatched by a hero.

const SPELLS_B := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
	80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109]

class NightDayNight extends RefCounted:
	var night := false
	var records: Array = []
	func apply_record(amount: int): records.append(amount)
	func is_night() -> bool: return night

func run():
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_spell_b_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the hero spell world")
	if centre.x >= 0:
		for part in ["records_b", "applier_b", "consumers_b", "arrows_b", "cast_path_b", "cast_all_b"]:
			var t0 := Time.get_ticks_msec()
			call(part)
			print("%s: %d ms" % [part, Time.get_ticks_msec() - t0])
	clear_world()
	if failures > 0:
		printerr("Hero spell B checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Hero spell B checks passed: %d" % checks)
	quit(0)

func hero_type(_spell: int) -> String:
	return "AUHX"

# ------------------------------------------------------------------------------------------------ the worlds
## tools/emulate_hero_spells_b.py world_for as [kind, code, side, offset, extra].
func fixture_world(scenario: String) -> Array:
	match scenario:
		"hurt":
			return [["unit", "AHIX", "own", Vector2i(2, 0), {"hp": 3}], ["unit", "AHKX", "own", Vector2i(0, -9), {"hp": 10}],
				["unit", "AHKX", "own", Vector2i(9, 0), {"hp": 10}], ["unit", "AHIX", "own", Vector2i(0, 13), {"hp": 2}],
				["unit", "AHIX", "own", Vector2i(-13, 0), {"hp": 2}], ["unit", "AHIX", "own", Vector2i(30, 30), {"hp": 1}],
				["unit", "AHIX", "own", Vector2i(1, 1), {}], ["unit", "AHIX", "enemy", Vector2i(-2, 0), {"hp": 3}],
				["unit", "AHIX", "own", Vector2i(0, 2), {"hp": 0}], ["building", "BKD0", "own", Vector2i(-4, -4), {"hp": 100}],
				["unit", "AHIX", "own", Vector2i(14, 0), {"hp": 2}], ["unit", "AHIX", "own", Vector2i(0, -14), {"hp": 2}]]
		"dead":
			return [["unit", "AHIX", "own", Vector2i(1, 0), {"hp": 0}], ["unit", "AHKX", "own", Vector2i(3, 3), {"hp": 0}],
				["unit", "AHIX", "enemy", Vector2i(-2, 1), {"hp": 0}], ["unit", "AUIX", "own", Vector2i(0, 9), {"hp": 0}],
				["unit", "AHIX", "own", Vector2i(0, -13), {"hp": 0}], ["unit", "AHIX", "own", Vector2i(13, 0), {"hp": 0}],
				["unit", "AHIX", "own", Vector2i(0, 14), {"hp": 0}], ["unit", "AHIX", "own", Vector2i(-1, -1), {}],
				["unit", "AHIX", "own", Vector2i(20, 0), {"hp": 0}], ["unit", "AHFX", "own", Vector2i(-3, 2), {"hp": 0}]]
		"poison":
			return [["unit", "AHIX", "own", Vector2i(2, 0), {"poison": 1, "hp": 20}], ["unit", "AHKX", "own", Vector2i(0, 3), {"disease": 1}],
				["unit", "AHIX", "own", Vector2i(-2, 1), {}], ["unit", "AHIX", "enemy", Vector2i(3, 1), {}],
				["unit", "AHIX", "enemy", Vector2i(1, -3), {"poison": 1}], ["unit", "AHKX", "enemy", Vector2i(-3, -2), {"disease": 1}],
				["unit", "AUIX", "enemy", Vector2i(4, 0), {}], ["unit", "AUBX", "enemy", Vector2i(0, -4), {}],
				["unit", "AHIX", "enemy", Vector2i(5, 5), {"rank": 4, "poison": 1}], ["unit", "AHFX", "enemy", Vector2i(-4, 3), {}],
				["unit", "AHIX", "enemy", Vector2i(2, 4), {"effects": [[0x7c, 1]]}], ["unit", "ACSH", "enemy", Vector2i(-5, 0), {}],
				["unit", "AHIX", "own", Vector2i(-1, 4), {"poison": 1, "rank": 6}]]
		"ranks":
			return [["unit", "AHIX", "own", Vector2i(1, 0), {"exp": 0}], ["unit", "AHIX", "own", Vector2i(2, 0), {"exp": 10}],
				["unit", "AHIX", "own", Vector2i(3, 0), {"exp": 18}], ["unit", "AHIX", "own", Vector2i(4, 0), {"exp": 25}],
				["unit", "AHIX", "own", Vector2i(0, 9), {"exp": 0}], ["unit", "AHIX", "enemy", Vector2i(-1, 0), {"exp": 0}],
				["unit", "AHKX", "own", Vector2i(0, -2), {"exp": 5}], ["unit", "AHIX", "own", Vector2i(-2, 0), {"exp": 39}]]
		"undead":
			return [["unit", "AUIX", "enemy", Vector2i(2, 0), {"hp": 1000}], ["unit", "AUBX", "enemy", Vector2i(0, 3), {"hp": 1000}],
				["unit", "AUJX", "enemy", Vector2i(-3, 0), {"hp": 1000}], ["unit", "AHIX", "enemy", Vector2i(0, -2), {"hp": 1000}],
				["unit", "AUIX", "own", Vector2i(1, 1), {"hp": 1000}], ["unit", "AUIX", "enemy", Vector2i(0, 9), {"hp": 1000}],
				["unit", "AUIX", "enemy", Vector2i(0, 10), {"hp": 1000}], ["building", "BKH0", "enemy", Vector2i(4, -3), {"hp": 2000}]]
		"statuses":
			return [["unit", "AHIX", "own", Vector2i(1, 0), {"effects": [[0x2e, 3], [0x18, 10]]}],
				["unit", "AHIX", "enemy", Vector2i(-1, 0), {"effects": [[0x2e, 3]]}],
				["unit", "AHKX", "enemy", Vector2i(0, 13), {"effects": [[1, 6]]}], ["unit", "AHKX", "enemy", Vector2i(0, 14), {"effects": [[1, 6]]}],
				["unit", "AHFX", "own", Vector2i(2, 2), {}], ["building", "BKD0", "own", Vector2i(-4, -4), {}]]
		"tough":
			var tough: Array = []
			var types := ["AHKX", "ADLX", "AAEE", "AUIX", "AHFX"]
			for i in types.size(): tough.append(["unit", types[i], "enemy", Vector2i(i, 2), {"hp": 1000}])
			tough.append(["building", "BKH0", "enemy", Vector2i(4, -3), {"hp": 2000}])
			return tough
		"edges":
			var out: Array = []
			var edge := [Vector2i(0, -8), Vector2i(0, 8), Vector2i(-8, 0), Vector2i(8, 0), Vector2i(0, -6), Vector2i(0, 6), Vector2i(6, 0),
				Vector2i(-6, 0), Vector2i(4, 4), Vector2i(5, 4), Vector2i(7, 7), Vector2i(0, -10), Vector2i(0, 10), Vector2i(10, 0),
				Vector2i(-10, 0), Vector2i(6, 6), Vector2i(2, -9), Vector2i(-5, 5), Vector2i(0, 13), Vector2i(9, 9), Vector2i(12, 5), Vector2i(0, -14)]
			for o in edge: out.append(["unit", "AHIX", "enemy", o, {"hp": 5}])
			for o in edge: out.append(["unit", "AUIX", "own", o + Vector2i(1, 0), {"hp": 5}])
			return out
	return super.fixture_world(scenario)

## Builds the world (the parent's scenarios plus this file's), then the extras the parent does not know.
func build_world(scenario: String, hero_type_id: String) -> Dictionary:
	var ids: Dictionary = super.build_world(scenario, hero_type_id)
	var h = world.combat.fighters[world.host.hero_unit_id]
	if scenario == "hurt": h.hp = 5
	if scenario == "warded": status_on(h, 0x3e, 1)
	if scenario == "power": status_on(h, 0x2a, 50)
	if scenario.begins_with("weather"):
		var dn := NightDayNight.new()
		dn.night = scenario == "weather night"
		world.host.day_night = dn
	var list := fixture_world(scenario)
	for i in list.size():
		var e: Array = list[i]
		if e[0] != "unit": continue
		var f = world.combat.fighters[int(ids[str(i + 2)].id)]
		var extra: Dictionary = e[4]
		if int(extra.get("hp", 1)) == 0:
			f.state = "corpse"
			f["death_ms"] = int(world.combat.now_ms)
		if extra.get("poison", 0): world.combat.set_poisoned(int(f.id), true)
		if extra.get("disease", 0): f["diseased"] = true
		if extra.has("exp"): f["xp"] = int(extra.exp)
		for s in extra.get("effects", []): status_on(f, int(s[0]), int(s[1]))
	return ids

func status_on(f, kind: int, value: int):
	world.spells.add_status({"kind": "unit", "id": int(f.id)}, {"kind": kind, "value": value, "until": 10000000, "art": 0})

func records_of_case(c: Dictionary) -> Array:
	return c.get("built", []).filter(func(m): return m.message == "0x1f7")

func built_list(got: Dictionary) -> Array:
	if got.is_empty(): return []
	return got.records if got.has("records") else [got]

## The parent's comparison plus the full descriptors (all six words).
func compare_b(got: Dictionary, want: Dictionary) -> Array:
	var diff := compare_record(got, want)
	if got.is_empty() or want.is_empty(): return diff
	var gd: Array = got.get("descriptors", [])
	var wd: Array = want.get("descriptors6", [])
	for i in mini(gd.size(), wd.size()):
		for k in 6:
			var g: int = int(gd[i][k]) if k < gd[i].size() else 0
			if g != int(wd[i][k]): diff.append("descriptor %d word %d %d != %d" % [i, k, g, int(wd[i][k])])
	return diff

func builder_record(spell: int, caster: int, level: int, target: Dictionary) -> Dictionary:
	if world.hs.has_builder(spell): return world.hs.build(spell, caster_dict(caster), level, target)
	return world.spells.call(String(Spells.BUILDERS[spell]), caster_dict(caster), level, target)

# ------------------------------------------------------------------------------------------------ 1. records
func records_b():
	var count := 0
	var diffs: Array = []
	# The builders read the world only for the command checks, Life Ward's own ward, the weather and the caster's effect
	# 0x2a, and change nothing: one world per scenario serves every spell and level.
	for scenario in ["empty", "power", "warded", "weather day", "weather night", "weather rain", "command full", "command one left", "undead"]:
		build_world(scenario, "AUHX")
		var h: int = world.host.hero_unit_id
		for spell in SPELLS_B:
			for c in cases(spell):
				if String(c.scenario) != scenario: continue
				var got := built_list(builder_record(spell, h, int(c.level), target_for(spell)))
				var want := records_of_case(c)
				if got.size() != want.size():
					diffs.append("%s %s L%d: %d records (original %d)" % [fx.spells[str(spell)].name, scenario, int(c.level), got.size(), want.size()])
					continue
				for i in got.size():
					var d := compare_b(got[i], want[i])
					if not d.is_empty(): diffs.append("%s %s L%d record %d: %s" % [fx.spells[str(spell)].name, scenario, int(c.level), i, d])
				count += 1
	check(diffs.is_empty(), "B1-6b: %d record cases of the four schools equal the original %s" % [count, diffs.slice(0, 6)])
	check(count >= 220, "at least 220 record cases compared (%d)" % count)

# ------------------------------------------------------------------------------------------------ 2. the applier
func by_offset(ids: Dictionary) -> Dictionary:
	var out := {}
	for k in ids: out["%s:%d" % [ids[k].kind, int(ids[k].id)]] = k
	return out

func applier_b():
	var compared := 0
	var diffs: Array = []
	for spell in SPELLS_B:
		for c in cases(spell):
			if not c.has("applied") or String(c.scenario) == "empty" and not spell in [0, 2, 8, 82, 87, 88, 100, 105, 102, 107, 109, 58, 86]: continue
			# levels 1 and 4 (every level where the record's filters change with it: Resurrection)
			if int(c.level) in [2, 3] and spell != 9: continue
			var ids := build_world(String(c.scenario), "AUHX")
			var h: int = world.host.hero_unit_id
			var info: Dictionary = world.spells.cast_built(builder_record(spell, h, int(c.level), target_for(spell)), caster_dict(h), int(c.level), spell)
			var label := "%s %s L%d" % [fx.spells[str(spell)].name, c.scenario, int(c.level)]
			var d := compare_application(spell, c, info, ids)
			if not d.is_empty(): diffs.append("%s: %s" % [label, d])
			compared += 1
	check(diffs.is_empty(), "B1-6b: %d applications equal the original %s" % [compared, diffs.slice(0, 6)])

## Compares one application with the fixture's: the gathered targets, created units, the per-object state.
func compare_application(spell: int, c: Dictionary, info: Dictionary, ids: Dictionary) -> Array:
	var diff: Array = []
	var results: Array = info.get("results", [info.get("result", {})])
	# targets of every record (the host's re-broadcast copies)
	var want_targets: Array = []
	var made_want := 0
	var missiles_want := 0
	for st in c.applied:
		for m in st.sent:
			if m.message == "0x1f7" and st.stage == "area": want_targets.append(fixture_offsets(m.target_ids, ids))
			if m.message == "0xfa": made_want += 1
		for call in st.get("calls", []):
			if call.call == "missile": missiles_want += 1
	var got_targets: Array = []
	var made_got := 0
	var missiles_got := 0
	for r in results:
		if r.is_empty() or int(r.get("kind", -1)) == SpellEffects.DAY_NIGHT: continue   # kind 4 is not applied by the emulator
		got_targets.append(offsets(r.targets, ids))
		made_got += r.summoned.size() + r.resurrected.size() + r.stripped.size()
		missiles_got += r.missiles.size()
	# records without a radius list no targets in the rebuild's result unless pre-filled: compare only area gathers
	for i in mini(got_targets.size(), want_targets.size()):
		if not want_targets[i].is_empty() or not got_targets[i].is_empty():
			if got_targets[i] != want_targets[i]: diff.append("targets %s != %s" % [got_targets[i], want_targets[i]])
	if made_got != made_want: diff.append("created %d != %d" % [made_got, made_want])
	if missiles_got != missiles_want: diff.append("missiles %d != %d" % [missiles_got, missiles_want])
	for k in c.after:
		var want: Dictionary = c.after[k]
		var before: Dictionary = c.before[k]
		if not ids.has(k): continue
		var o: Dictionary = ids[k]
		if o.kind == "building":
			var b = world.production.building(int(o.id))
			var hp_b: int = int(b.hit_points) if b != null else 0
			if int(want.hp) != int(before.hp) and hp_b != int(want.hp) and not (int(want.hp) >= int(b.max_hit_points) and hp_b == int(b.max_hit_points)):
				diff.append("building %s hp %d != %d" % [o.offset, hp_b, int(want.hp)])
			continue
		var f = world.combat.fighters[int(o.id)]
		# hit points: the hero's maximum and promotions (Soul Flame) differ in the rebuild; full counts as full
		if k != "1" and spell != 51 and int(want.hp) != int(before.hp) and int(f.hp) != int(want.hp):
			diff.append("%s hp %d != %d" % [o.offset, int(f.hp), int(want.hp)])
		if k == "1" and int(want.hp) != int(before.hp) and int(f.hp) != int(f.max_hp) and int(f.hp) != int(want.hp):
			diff.append("hero hp %d (original %d)" % [int(f.hp), int(want.hp)])
		if bool(f.get("poisoned", false)) != (int(want.poison) != 0): diff.append("%s poison %s" % [o.offset, f.get("poisoned", false)])
		if bool(f.get("diseased", false)) != (int(want.disease) != 0): diff.append("%s disease %s" % [o.offset, f.get("diseased", false)])
		if int(want.exp) != int(before.exp) and int(f.get("xp", 0)) != int(want.exp): diff.append("%s exp %d != %d" % [o.offset, int(f.get("xp", 0)), int(want.exp)])
		if want.has("berserk") != (f.get("berserk") != null): diff.append("%s berserk" % [o.offset])
		var got_s: Array = []
		for s in f.get("statuses", []): got_s.append([int(s.kind), int(s.value)] + Array(s.get("data", [0, 0, 0, 0])).map(func(v): return int(v)))
		var want_s: Array = []
		for e in want.get("effects6", []): want_s.append([int(e[0]), int(e[1]), int(e[2]), int(e[3]), int(e[4]), int(e[5])])
		got_s.sort()
		want_s.sort()
		if got_s != want_s: diff.append("%s statuses %s != %s" % [o.offset, got_s, want_s])
	if spell == 88 and int(world.spells.mana_gate) != int(c.globals.mana_gate): diff.append("mana gate %d" % world.spells.mana_gate)
	return diff

# ------------------------------------------------------------------------------------------------ 3. consumers
func consumers_b():
	# Freeze Magic: no unit or hero mana regeneration while the gate is below 1; back to 100 once its time passed.
	build_world("empty", "AUHX")
	var h: int = world.host.hero_unit_id
	var liche := unit("AUMX", Vector2i(3, 0), OWNER)
	var lf = world.combat.fighters[liche]
	lf.mana = 0
	world.spells.cast_built(builder_record(88, h, 1, {}), caster_dict(h), 1, 88)
	run_world(30000)
	check(int(lf.mana) == 0 and world.spells.mana_gate == 0, "Freeze Magic: no unit mana regenerates while 0x7494c4 = 0")
	run_world(40000)
	check(world.spells.mana_gate == 100 and int(lf.mana) > 0, "Freeze Magic: 0x532330 restores the gate after 60 s; mana flows again (%d)" % int(lf.mana))
	# Invigorate / Freeze: speed and attack rate terms; the walking speed follows.
	build_world("empty", "AUHX")
	h = world.host.hero_unit_id
	var sw := unit("AHKX", Vector2i(1, 0), OWNER)
	var sf = world.combat.fighters[sw]
	var speed0: int = int(world.units[sw].base_speed)
	status_on(sf, 0x2e, 3)                                  # Invigorate level 2's descriptor
	check(world.spells.speed_term(sf) == 3 and world.spells.rate_term(sf) == 3 and int(world.units[sw].base_speed) == speed0 + 3,
		"Invigorate level 2: speed and attack rate + 3 (0x51c460 / 0x51c6a0 effect 0x2e)")
	status_on(sf, 0x30, 5)
	check(world.spells.speed_term(sf) == -2 and int(world.units[sw].base_speed) == speed0 - 2, "Freeze over Invigorate: 3 - 5 = -2")
	# Blessing / White Ward / Berserker: morale effect 7 on the hero, magic armour + 5 x level, combat + level + 4.
	build_world("empty", "AUHX")
	h = world.host.hero_unit_id
	var ww := unit("AHKX", Vector2i(1, 0), OWNER)
	var wf = world.combat.fighters[ww]
	var block0: Dictionary = world.combat.combat_block(wf)
	status_on(wf, 6, 10)                                    # White Ward level 2
	status_on(wf, 1, 6)                                     # Berserker level 2's combat descriptor
	world.spells.berserk({"kind": "unit", "id": ww}, 2)
	var block1: Dictionary = world.combat.combat_block(wf)
	check(int(block1.mres) == int(block0.mres) + 10 and int(block1.combat) == int(block0.combat) + 12 and wf.get("berserk") != null
		and world.spells.speed_term(wf) == 4, "White Ward (+10 magic armour) and Berserker (+6 effect 1, +6 / +4 speed for the berserk flag of level 2) on a Knight")
	# B2-1 (BATCH2_RESEARCH.md E7, tests/test_batch2_powers.gd): the state is timed, drains and runs Rampant.
	check(int(wf.berserk.drain) == 1 and int(wf.berserk.period) == 1000 and int(wf.berserk.until) == int(world.combat.now_ms) + 180000 and int(wf.script) == 4,
		"Berserker's state: 1 hp per second for 180 s on script 4 (Rampant)")
	# Firebreath: effect 0x17 value 0 replaces the Knight's attack with (15, fire) at level 2.
	world.spells.add_status({"kind": "unit", "id": ww}, {"kind": 0x17, "value": 0, "until": 10000000, "art": 0x1c, "data": [15, 3, 5, 0]})
	var block2: Dictionary = world.combat.combat_block(wf)
	var bonus: int = int(block0.dmg) - int(wf.base.dmg)
	check(int(block2.dtype) == 3 and int(block2.dmg) == 15 + bonus, "Firebreath level 2: the Knight's attack becomes damage 15 fire (0x526310 effect 0x17)")
	# Calm takes them all away.
	world.spells.cast_built(builder_record(83, h, 1, {}), caster_dict(h), 1, 83)
	check(wf.get("statuses", []).is_empty() and wf.get("berserk") != null, "Calm: the Knight's effects are gone, the berserk block stays (0x4ad018)")
	# Life Ward: a killing blow leaves the hero standing at full hit points once.
	build_world("empty", "AUHX")
	h = world.host.hero_unit_id
	var hf = world.combat.fighters[h]
	world.spells.cast_built(builder_record(8, h, 1, {}), caster_dict(h), 1, 8)
	world.combat.apply_damage("unit", h, int(hf.hp) + 50, -1, "spell")
	check(int(hf.hp) == int(hf.max_hp) and world.combat.alive(hf) and world.spells.status_value(hf, 0x3e) == 0, "Life Ward: the killing blow restores the hero (0x522860), the ward goes")
	world.combat.apply_damage("unit", h, int(hf.hp) + 50, -1, "spell")
	check(int(hf.hp) == 0, "Life Ward: the second killing blow kills")
	# Venom Touch: a poisoning melee hit (0x51aae0), chance (10 - magic armour + 10) x 5.
	build_world("empty", "AUHX")
	h = world.host.hero_unit_id
	var a := unit("AHKX", Vector2i(1, 0), OWNER)
	var t := unit("AHIX", Vector2i(2, 0), ENEMY)
	world.spells.cast_built(builder_record(104, h, 1, {}), caster_dict(h), 1, 104)
	var poisoned := 0
	for i in 40:
		world.combat.set_poisoned(t, false)
		world.spells.venom_hit(world.combat.fighters[a], world.combat.fighters[t])
		if bool(world.combat.fighters[t].get("poisoned", false)): poisoned += 1
	check(poisoned > 0, "Venom Touch: melee hits poison the target (%d of 40)" % poisoned)
	status_on(world.combat.fighters[t], 0x7c, 1)
	world.combat.set_poisoned(t, false)
	world.spells.venom_hit(world.combat.fighters[a], world.combat.fighters[t])
	check(not bool(world.combat.fighters[t].get("poisoned", false)), "Immunity (0x7c): 0x51c130 refuses the poison")
	# Poison Gate: an enemy hero's gate poisons units created for other players.
	build_world("empty", "AUHX")
	h = world.host.hero_unit_id
	world.spells.cast_built(builder_record(105, h, 1, {}), caster_dict(h), 1, 105)
	var own_new := unit("AHIX", Vector2i(2, 0), OWNER)
	var enemy_new := unit("AHIX", Vector2i(3, 0), ENEMY)
	check(not bool(world.combat.fighters[own_new].get("poisoned", false)) and bool(world.combat.fighters[enemy_new].get("poisoned", false)),
		"Poison Gate: a new enemy unit comes out poisoned, an own one does not (0x4a49e0)")

# ------------------------------------------------------------------------------------------------ arrows
func arrows_b():
	var diffs: Array = []
	var compared := 0
	for r in fx.arrows:
		if bool(r.building): continue
		var flags: Dictionary = {}
		for fl in r.flags: flags["%s:%d" % [fl[0], int(fl[1])]] = true
		var target_owner := int(r.target_owner)
		var shooter := int(r.shooter_owner)
		var resisting := CombatRules.arrow_resistant(String(r.target), bool(r.hero_resist), flags.has("PNOP:%d" % target_owner), flags.has("PDEF:%d" % target_owner))
		var phun: bool = shooter >= 0 and flags.has("PHUN:%d" % shooter)
		# The fixture's damage before the rule: the same hit without resistance is the plain row of a non-resisting type;
		# the rule itself is pinned by its effect on the armour result, so compare the resisted rows' arithmetic.
		var plain := plain_damage(r)
		if plain < 0: continue
		var got := CombatRules.arrow_damage(plain, int(r.mclass), resisting, phun)
		if got != int(r.dealt): diffs.append("%s %d class %d %s: %d != %d" % [r.target, int(r.damage), int(r.mclass), r.flags, got, int(r.dealt)])
		compared += 1
	check(diffs.is_empty() and compared > 150, "arrow resistance: %d unit hits equal 0x5427e0 %s" % [compared, diffs.slice(0, 4)])

## The damage before the arrow rule for the row: the row with PHUN (or the class-3 row of the same type) has none of
## it; for unflagged rows the rule's input is the armour result, taken from the resisted row's class-3 twin is not
## possible, so the input is recomputed with the rebuild's armour tail against the type's armour block.
func plain_damage(r: Dictionary) -> int:
	var stats := CombatRules.unit_stats(world.production.rules.definition(String(r.target)).raw_hex) if not world.is_empty() else {}
	if stats.is_empty(): return -1
	if bool(r.hero_resist) and String(r.target) == "AUHX": return -1    # the hero's armour block is its hero block's (not the ARM row)
	var block: Dictionary = stats.duplicate()
	var mclass := int(r.mclass)
	var d: int
	if mclass == 0xb:
		d = CombatRules.armour_tail(int(r.damage), 2, 0, CombatRules.armour_table(block), CombatRules.resist_flags(block)) + \
			CombatRules.armour_tail(int(r.damage) / 2, 2, 3, CombatRules.armour_table(block), CombatRules.resist_flags(block))
	else:
		d = CombatRules.armour_tail(int(r.damage), 2, mclass, CombatRules.armour_table(block), CombatRules.resist_flags(block))
	return d

# ------------------------------------------------------------------------------------------------ 4. the cast path
func cast_path_b():
	var diff: Array = []
	build_world("empty", "AUHX")                         # one world: each row clears the order and the pending cast
	var h: int = world.host.hero_unit_id
	for row in fx.cast_path:
		var spell := int(row.spell)
		world.combat.fighters[h]["cast"] = null
		world.hs.pending = {}
		world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 10 + spell / 10, "unlock_level": 1, "rank": int(row.rank)}]
		world.combat.fighters[h].mana = 200
		world.combat.rng.seed_state(int(row.seed[0]), int(row.seed[1]))
		var result: Dictionary = world.hs.cast_request(h, spell)
		var sent: Dictionary = {}
		for m in row.sent: if m.message == "0x118": sent = m
		var f = world.combat.fighters[h]
		var rng: Array = [world.combat.rng.first, world.combat.rng.second]
		var ok: bool = rng == [int(row.rng_after[0]), int(row.rng_after[1])]
		if not sent.is_empty():
			var c = f.get("cast")
			ok = ok and c != null and int(c.level) == int(sent.level)
			if ok and int(sent.target[3]) != 0:
				ok = Vector2i(int(c.target.x), int(c.target.y)) - world.combat.unit_cell(h) == Vector2i(int(sent.target[3]), int(sent.target[4])) - Vector2i(40, 40)
		elif row.pending != null:
			ok = ok and String(world.hs.pending.get("mode", "")) == "place" and int(world.hs.pending.level) == int(row.pending.level)
		else:
			ok = ok and not bool(result.get("cast", false))
		if not ok: diff.append("%d seed %s: %s" % [spell, row.seed[0], result])
	check(diff.is_empty(), "0x5717e0: %d cast-path rows of the four schools equal the original %s" % [fx.cast_path.size(), diff.slice(0, 4)])

## Every spell of the four schools cast by the hero through the human path: the request, order 9, the event, the
## dispatcher, the record applied (Wall of Ice by its placement click).
func cast_all_b():
	var failed: Array = []
	for spell in SPELLS_B:
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 10 + spell / 10, "unlock_level": 1, "rank": 15 if spell % 10 < 5 else 25}]
		var f = world.combat.fighters[h]
		f.mana = 200
		f.max_mana = 200
		world.combat.rng.seed_state(12345, 678)
		var request: Dictionary = world.hs.cast_request(h, spell)
		if request.get("pending", "") == "place":
			request = world.hs.place(world.combat.unit_cell(h) + Vector2i(4, 4))
		if not bool(request.get("cast", false)):
			failed.append("%d: %s" % [spell, request])
			continue
		var dispatched := {}
		var on_cast := func(info): dispatched.merge(info, true)    # a lambda captures by value: mutate the dictionary
		world.spells.cast_done.connect(on_cast)
		run_world(4000, func(): return f.get("cast") == null)
		world.spells.cast_done.disconnect(on_cast)
		if dispatched.is_empty() or int(f.mana) >= 200: failed.append("%d: not dispatched (mana %d)" % [spell, int(f.mana)])
	check(failed.is_empty(), "all forty spells of Healing, Pyromancy, Ice and Poison cast by the hero's own path %s" % [failed.slice(0, 6)])
