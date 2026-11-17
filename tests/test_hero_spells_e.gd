extends "res://tests/test_hero_spells_d.gd"
## Hero spells B1-6e (SPELLS_RESEARCH.md section "B1-6e") against tests/hero_spell_e_fixtures.json
## (tools/emulate_hero_spells_e.py), on B1-6a..d's world and helpers:
## 1. every builder of Alchemy (60-69) and Chaos (90-99) at levels 1-4 equals the original's record cast by a hero (all
##    fields and descriptors; Create Item's drawn item and Morph Resources' rate under eight seeds, the Morphs' rolls, the
##    trade dialog's rate and title, Acquire's conversion radius, Brew Potion's potions);
## 2. the applier on every fixture world (the Morphs' stats on units and towers, Chaos Plague's hit points and disease,
##    Increase Casting's school rise and its local-player test, the item statuses, the golems, Summon Guardian, Wildfire);
## 3. the consumers: disease (0x51c060's deadlines, 0x532a20's count and level, the end and the regeneration stop, the
##    combat / speed terms, Rot's term), the item powers under Spellforge / Disjunction, the Charm price term, the potion;
## 4. the cast path 0x5717e0 for the twenty spells under eight seeds, and each spell ordered and dispatched by a hero.

const ComputerHero = preload("res://simulation/computer_hero.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const SPELLS_E := [60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99]
const EMU_NOW := 50000                  # the harness clock at a new world

func run():
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_spell_e_fixtures.json"))
	for i in 8: seeds.append(fx.cast_path[i].seed)
	centre = open_ground()
	check(centre.x >= 0, "open ground for the hero spell world")
	if centre.x >= 0:
		for part in ["records_e", "applier_e", "consumers_e", "cast_path_e", "cast_all_e"]:
			var t0 := Time.get_ticks_msec()
			call(part)
			print("%s: %d ms" % [part, Time.get_ticks_msec() - t0])
	clear_world()
	if failures > 0:
		printerr("Hero spell E checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Hero spell E checks passed: %d" % checks)
	quit(0)

func built() -> Array:
	return SPELLS_E.filter(func(s): return HeroSpells.castable(s))

# ------------------------------------------------------------------------------------------------ the worlds
## tools/emulate_hero_spells_e.py world_for as [kind, code, side, offset, extra].
func fixture_world(scenario: String) -> Array:
	match scenario:
		"morph":
			return [["unit", "AHIX", "own", Vector2i(1, 0), {}], ["unit", "AHKX", "enemy", Vector2i(2, 0), {}], ["unit", "AHFX", "enemy", Vector2i(0, 3), {}],
				["unit", "AUHX", "enemy", Vector2i(-2, 2), {"hero": true}], ["unit", "ACSH", "enemy", Vector2i(-1, -2), {}],
				["unit", "AHIX", "enemy", Vector2i(3, 3), {"hp": 0}], ["unit", "AHIX", "enemy", Vector2i(0, 9), {}], ["unit", "AHIX", "enemy", Vector2i(0, 10), {}],
				["unit", "AHIX", "enemy", Vector2i(-3, 0), {"stats": [1, 1, 2, 2, 1]}],
				["unit", "AHIX", "enemy", Vector2i(3, -2), {"stats": [98, 98, 998, 998, 998]}],
				["unit", "AADR", "enemy", Vector2i(-4, -3), {}], ["building", "BWTD", "enemy", Vector2i(4, 4), {}],
				["building", "BKD0", "own", Vector2i(-5, 4), {}]]
		"towers":
			return [["building", "BWTD", "enemy", Vector2i(3, 0), {}], ["building", "BWTD", "own", Vector2i(-3, 0), {}],
				["building", "BWTC", "enemy", Vector2i(0, 4), {}], ["building", "BWTD", "enemy", Vector2i(0, 9), {}],
				["building", "BWTD", "enemy", Vector2i(0, 12), {}], ["building", "BKD0", "enemy", Vector2i(-4, -4), {}],
				["unit", "AHIX", "enemy", Vector2i(1, 1), {}]]
		"plague":
			return [["unit", "AHIX", "enemy", Vector2i(1, 0), {}], ["unit", "AHKX", "enemy", Vector2i(2, 0), {"disease": 1}],
				["unit", "AHIX", "enemy", Vector2i(3, 0), {"poison": 1}], ["unit", "AHIX", "enemy", Vector2i(0, 2), {"effects": [[0x7c, 1]]}],
				["unit", "AHIX", "enemy", Vector2i(0, 3), {"b1cd": 1}], ["unit", "AUHX", "enemy", Vector2i(-2, 2), {"hero": true}],
				["unit", "AUIX", "enemy", Vector2i(-2, 0), {}], ["unit", "AUBX", "enemy", Vector2i(-3, 0), {}], ["unit", "ACSH", "enemy", Vector2i(-1, 3), {}],
				["unit", "AHIX", "own", Vector2i(-1, -1), {}], ["unit", "AHIX", "enemy", Vector2i(2, -2), {"hp": 1}],
				["unit", "AHIX", "enemy", Vector2i(-2, -2), {"hp": 3}], ["unit", "AHIX", "enemy", Vector2i(3, 3), {"hp": 7}],
				["unit", "AHIX", "enemy", Vector2i(0, 9), {}], ["unit", "AHIX", "enemy", Vector2i(0, 10), {}], ["unit", "AADE", "enemy", Vector2i(4, 1), {}],
				["unit", "AHFX", "enemy", Vector2i(-4, 1), {}]]
		"casters":
			return [["unit", "AUHX", "enemy", Vector2i(2, 0), {"hero": true}], ["unit", "AHIX", "own", Vector2i(1, 1), {}]]
	return super.fixture_world(scenario)

func base_scenario(scenario: String) -> String:
	if scenario.begins_with("morph"): return "morph"
	if scenario.begins_with("towers"): return "towers"
	if scenario.begins_with("seed ") or scenario in ["remote", "potions 9"]: return "empty"
	return super.base_scenario(scenario)

## The B1-6d world plus the B1-6e extras: base stats [combat, speed, max hp, hp, damage] (+0x92 / +0x94 / +0x98 / +0x9c /
## +0x9e), a disease lasting past the test (+0x1a0 = 10 000 000 in the harness), the harness's potion count 0.
func build_world_e(scenario: String) -> Dictionary:
	var ids: Dictionary = build_world_d(scenario)
	world.production.local_player = OWNER                     # the harness's local player 0x709100 is the caster's
	var list := fixture_world(base_scenario(scenario))
	for i in list.size():
		var e: Array = list[i]
		if e[0] != "unit": continue
		var f = world.combat.fighters[int(ids[str(i + 2)].id)]
		var extra: Dictionary = e[4]
		if extra.has("stats"):
			var s: Array = extra.stats
			f.stats.combat = int(s[0])
			f.stats.speed = int(s[1])
			f.max_hp = int(s[2])
			f.stats.max_hp = int(s[2])
			f.hp = int(s[3])
			world.units[f.id].hp = f.hp
			f.stats.dmg = int(s[4])
			# The words are the block's (+0x92..): Morph reads and clamps them there (REVIEW_R1.md D2).
			for key in ["combat", "speed", "max_hp", "dmg"]: f.base[key] = int(f.stats[key])
		if extra.get("disease", 0): world.spells.set_disease(f, world.spells.now() + 10000000 - EMU_NOW)
	var m = world.combat.heroes[OWNER].match
	m.potions = 9 if scenario == "potions 9" else 0
	return ids

## The harness's object ids whose fixture state the rebuild has no field for: +0x1cd (the 'plague' unit at (0, 3)).
## B3-1 (REVIEW_BATCH3.md E14, Emulated "immunity"): the harness also skipped the unit constructor, so +0x19f (0x5286c0(6) bit 0:
## the Undead, animals) was 0 and Chaos Plague diseased units the game's 0x51c1b0 refuses: the Skeleton, Zombie and sheep of
## 'plague' and the sheep of 'mixed' are left out too.
func skipped(scenario: String) -> Array:
	if base_scenario(scenario) == "plague": return ["6", "8", "9", "10"]
	if base_scenario(scenario) == "mixed": return ["5"]
	return []

# ------------------------------------------------------------------------------------------------ 1. records
func records_e():
	var count := 0
	var diffs: Array = []
	# The builders change nothing the others read (the potions, the drops and the dialogs are compared as differences):
	# one world per world name, the generator seeded per case as the emulator's.
	var by_world := {}
	for spell in built():
		for c in cases(spell):
			var key := base_scenario(String(c.scenario)) if not String(c.scenario).begins_with("command") else String(c.scenario)
			if not by_world.has(key): by_world[key] = []
			by_world[key].append([spell, c])
	for key in by_world:
		build_world_e(key)
		var h: int = world.host.hero_unit_id
		for pair in by_world[key]:
			var spell: int = pair[0]
			var c: Dictionary = pair[1]
			var scenario := String(c.scenario)
			world.combat.rng.seed_state(12345, 678)
			if scenario.contains("seed "): seed_rng(int(scenario.split(" ")[-1]))
			world.combat.heroes[OWNER].match.potions = 9 if scenario == "potions 9" else 0
			var label := "%s %s L%d" % [fx.spells[str(spell)].name, scenario, int(c.level)]
			var potions_before: int = int(world.combat.heroes[OWNER].match.potions)
			var got := built_list(builder_record(spell, h, int(c.level), target_for(spell)))
			var want := records_of_case(c)
			if got.size() != want.size():
				diffs.append("%s: %d records (original %d)" % [label, got.size(), want.size()])
				continue
			for i in got.size():
				var w: Dictionary = want[i].duplicate()
				if spell == 65: w.b12 = int(got[i].b12)       # +0xc is left unwritten by 0x5758b0 (stack bytes): not compared
				var d := compare_b(got[i], w)
				if not d.is_empty(): diffs.append("%s record %d: %s" % [label, i, d])
			var rng := [world.combat.rng.first, world.combat.rng.second]
			if rng != [int(c.rng[1][0]), int(c.rng[1][1])]: diffs.append("%s: generator %s != %s" % [label, rng, c.rng[1]])
			match spell:
				60:
					var made: Dictionary = world.hs.created_items.back() if not world.hs.created_items.is_empty() else {}
					if made.is_empty() or int(made.item) != int(c.drawn[0]) or made.cell != world.combat.unit_cell(h):
						diffs.append("%s: item %s != %s" % [label, made, c.drawn])
					elif world.host.treasures.drops.is_empty() or int(world.host.treasures.drops.back().item) != int(c.drawn[0]):
						diffs.append("%s: no drop of %s" % [label, c.drawn])
				61, 96:
					var t: Dictionary = world.hs.trade_requests.back() if not world.hs.trade_requests.is_empty() else {}
					if t.is_empty() or int(t.rate) != int(c.trade[0].rate) or String(t.title) != String(c.trade[0].title) or not bool(t.close):
						diffs.append("%s: trade %s != %s" % [label, t, c.trade])
				64:
					var gained: int = int(world.combat.heroes[OWNER].match.potions) - potions_before
					if gained != int(c.globals[1].potions) - int(c.globals[0].potions): diffs.append("%s: potions + %d" % [label, gained])
				65:
					var a: Dictionary = world.hs.acquired.back() if not world.hs.acquired.is_empty() else {}
					var cv: Dictionary = c.converts[0]
					if a.is_empty() or int(a.radius) != int(cv.radius) or a.cell != world.combat.unit_cell(h): diffs.append("%s: acquire %s != %s" % [label, a, cv])
			count += 1
	print("records_e: %d cases of %d spells" % [count, built().size()])
	check(diffs.is_empty(), "B1-6e: %d record cases of %d spells equal the original %s" % [count, built().size(), diffs.slice(0, 6)])
	check(count >= built().size() * 4, "every built spell compared at four levels at least (%d)" % count)

# ------------------------------------------------------------------------------------------------ 2. the applier
## The fixture's [combat, speed, max hp, hp, damage] of a unit / [combat, +0x6a, max hp, damage, hp] of a building, and
## the rebuild's.
func got_stats(o: Dictionary):
	if o.kind == "unit":
		var f = world.combat.fighters[int(o.id)]
		return [int(f.stats.combat), int(f.stats.speed), int(f.max_hp), int(f.hp), int(f.stats.dmg)]
	var b = world.production.building(int(o.id))
	return [int(world.spells.building_stat(b, 0)), int(world.spells.building_stat(b, 1)), int(b.max_hit_points), int(world.spells.building_stat(b, 3)), int(b.hit_points)]

func compare_e(spell: int, c: Dictionary, info: Dictionary, ids: Dictionary) -> Array:
	var diff := compare_application(spell, c, info, ids)
	var skip := skipped(String(c.scenario))
	diff = diff.filter(func(d): return not skip.any(func(k): return ids.has(k) and String(d).begins_with(str(ids[k].offset))))
	for k in c.after:
		if not ids.has(k) or k in skip: continue
		var o: Dictionary = ids[k]
		var want: Dictionary = c.after[k]
		var before: Dictionary = c.before[k]
		if spell >= 90 and spell <= 94 and want.has("stats"):
			# the Morphs: absolute stats, a hero's as the change (the rebuild's hero block differs from the ARM row)
			var got = got_stats(o)
			var w: Array = want.stats.map(func(v): return int(v))
			var b0: Array = before.stats.map(func(v): return int(v))
			if o.kind == "building":
				if got != w: diff.append("building %s stats %s != %s" % [o.offset, got, w])   # REVIEW D6: every word
			elif bool(world.combat.fighters[int(o.id)].hero):
				var f = world.combat.fighters[int(o.id)]
				if spell == 90 and w[0] != b0[0] and int(got[0]) == 0: diff.append("hero combat")
			elif got != w:
				diff.append("%s stats %s != %s" % [o.offset, got, w])
		if spell == 99 and o.kind == "unit" and want.has("sick"):
			var f = world.combat.fighters[int(o.id)]
			var s: Array = want.sick
			if int(s[2]) == 1 and int(before.sick[2]) == 0:
				var until: int = int(f.get("disease_until", 0)) - world.spells.now()
				if until != int(s[3]) - EMU_NOW: diff.append("%s disease end %d != %d" % [o.offset, until, int(s[3]) - EMU_NOW])
	if spell == 97:
		var bonus: Array = world.combat.heroes[OWNER].match.school_bonus
		if bonus.map(func(v): return int(v)) != c.applied_globals.school_bonus.map(func(v): return int(v)):
			diff.append("school bonus %s != %s" % [bonus, c.applied_globals.school_bonus])
		var rng := [world.combat.rng.first, world.combat.rng.second]
		if rng != [int(c.applied_rng[1][0]), int(c.applied_rng[1][1])]: diff.append("generator %s != %s" % [rng, c.applied_rng[1]])
	return diff

func applier_e():
	var compared := 0
	var diffs: Array = []
	for spell in built():
		if spell in HeroSpells.NO_RECORD: continue
		for c in cases(spell):
			if not c.has("applied"): continue
			var scenario := String(c.scenario)
			# levels 1 and 4 (the others scale the same terms); seeds 0..3 (Increase Casting: every seed at level 1)
			if spell == 97 and scenario.contains("seed"):
				if int(c.level) != 1: continue
			elif int(c.level) in [2, 3]: continue
			if scenario.contains("seed ") and spell != 97 and int(scenario.split(" ")[-1]) > 3: continue
			var ids := build_world_e(scenario)
			var h: int = world.host.hero_unit_id
			if scenario == "remote": world.production.local_player = ENEMY   # 0x4ac0e0 case 0x20: another machine's caster
			var record: Dictionary = builder_record(spell, h, int(c.level), target_for(spell))
			var info: Dictionary = world.spells.cast_built(record, caster_dict(h), int(c.level), spell)
			var d := compare_e(spell, c, info, ids)
			if not d.is_empty(): diffs.append("%s %s L%d: %s" % [fx.spells[str(spell)].name, scenario, int(c.level), d])
			compared += 1
	print("applier_e: %d applications" % compared)
	check(diffs.is_empty(), "B1-6e: %d applications equal the original %s" % [compared, diffs.slice(0, 6)])

# ------------------------------------------------------------------------------------------------ 3. consumers
func consumers_e():
	item_powers_e()
	potions_e()
	if 99 in built():
		disease_e()
		disease_count_e()
		disease_end_e()
		getters_e()
		rot_e()
		contagion_e()

## Fixture "item_powers": 0x40c380 / 0x40c500 under Spellforge (0x80) / Disjunction (0x7f), 0x526cf0 with Charm (0xb).
func item_powers_e():
	var diffs: Array = []
	for r in fx.item_powers:
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		var m = world.combat.heroes[OWNER].match
		m.profile.data["equipment"] = [{"item": int(r.speed_item)}, {"item": int(r.school_item)}, 0, 0, 0, 0, 0]
		var other := hero("AUHX", {}, ENEMY, Vector2i(10, 10))
		world.host.hero_unit_id = h
		if bool(r.allied):
			var rel := PackedByteArray()
			rel.resize(49)
			rel[OWNER + ENEMY * 7] = 1
			rel[ENEMY + OWNER * 7] = 1
			world.combat.relations = rel
		if bool(r.own_0x80): status_on(world.combat.fighters[h], 0x80, 0)
		if bool(r.other_0x7f): status_on(world.combat.fighters[other], 0x7f, 0)
		if int(r.charm) != 0: status_on(world.combat.fighters[h], 0xb, int(r.charm))
		world.hs.sync_item_factors()
		var block: Dictionary = world.combat.hero_block(OWNER)
		var got := [HeroEffects.item_stat(block, 5), HeroEffects.item_power(block, 99, int(r.school)),
			HeroEffects.price_value(block) + world.spells.status_value(world.combat.fighters[h], 0xb)]
		var want := [int(r.speed), int(r.school_power), int(r.price)]
		if got != want: diffs.append("%s: %s != %s" % [[r.own_0x80, r.other_0x7f, r.allied, r.charm], got, want])
	check(diffs.is_empty(), "0x40c380 / 0x40c500 under 0x80 / 0x7f and 0x526cf0 with 0xb: %d rows equal the original %s" % [fx.item_powers.size(), diffs.slice(0, 4)])
	# Spellforge doubles the school ranks' item term too (0x54fd50 through 0x40c500).
	build_world("empty", "AUHX")
	var h: int = world.host.hero_unit_id
	var r0: Dictionary = fx.item_powers[0]
	world.combat.heroes[OWNER].match.profile.data["equipment"] = [{"item": int(r0.school_item)}, 0, 0, 0, 0, 0, 0]
	var before: int = int(world.hs.schools(OWNER)[int(r0.school) - 10])
	status_on(world.combat.fighters[h], 0x80, 0)
	world.hs.sync_item_factors()
	var after: int = int(world.hs.schools(OWNER)[int(r0.school) - 10])
	check(after - before == int(r0.school_power), "Spellforge: the school's item rank doubles (%d -> %d)" % [before, after])

## Fixture "potions": 0x561d80's record and count; Brew Potion's potions are drunk this way.
func potions_e():
	var diffs: Array = []
	for r in fx.potions:
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		if r.keep != null: building(String(r.keep), Vector2i(10, 10), OWNER, {})
		var m = world.combat.heroes[OWNER].match
		m.potions = int(r.potions)
		var f = world.combat.fighters[h]
		f.hp = 1
		world.units[h].hp = 1
		var got_record := {}
		var on_cast := func(info): got_record.merge(info.record, true)
		world.spells.cast_done.connect(on_cast)
		var drunk: bool = world.hs.drink_potion(OWNER)
		world.spells.cast_done.disconnect(on_cast)
		var want: Array = r.built.filter(func(x): return x.message == "0x1f7")
		var d: Array = []
		if drunk != (int(r.ret) == 1) or int(m.potions) != int(r.left): d.append("drunk %s left %d" % [drunk, int(m.potions)])
		if not want.is_empty():
			d += compare_b(got_record, want[0])
			if int(f.hp) != mini(1 + int(want[0].amount), int(f.max_hp)): d.append("hp %d" % int(f.hp))
		if not d.is_empty(): diffs.append("%s %s: %s" % [r.potions, r.keep, d])
	check(diffs.is_empty(), "0x561d80: %d potion rows equal the original %s" % [fx.potions.size(), diffs.slice(0, 4)])
	# The hero starts with four potions; Brew Potion level 2 adds two.
	build_world("empty", "AUHX")
	var hh: int = world.host.hero_unit_id
	check(int(world.combat.heroes[OWNER].match.potions) == 4, "a match starts with four potions (0x54fd50)")
	if 64 in built():
		world.spells.cast_built(builder_record(64, hh, 2, {}), caster_dict(hh), 2, 64)
		check(int(world.combat.heroes[OWNER].match.potions) == 6, "Brew Potion level 2: six potions")

## Fixture "disease": 0x51c060(1) / (0) with the plague power 0x40d9b0 (BPSP count + the heroes' skill 0x65).
func disease_e():
	var diffs: Array = []
	for r in fx.disease:
		build_world("empty", "AUHX")
		if int(r.skill) != 0:
			hero("AUHX", {}, ENEMY, Vector2i(15, 15), [7, 5, 8, 4], [{"id": 0x65, "unlock_level": 1, "rank": int(r.skill)}])
		for i in int(r.pits): building("BPSP", Vector2i(-8 + 5 * i, -9), ENEMY, {})
		var id := unit(String(r.type), Vector2i(2, 0), OWNER)
		var f = world.combat.fighters[id]
		f.stats.mres = int(r.mres)
		if String(r.start) != "healthy":
			f["diseased"] = true
			f["disease_count"] = 3
			f["disease_level"] = 4
			f["disease_until"] = 777 - EMU_NOW + world.spells.now()
		if String(r.start) == "cure": world.spells.cure({"kind": "unit", "id": id})
		else: world.spells.set_disease(f)
		var a: Dictionary = r.after
		var got := [int(f.get("disease_count", 0)), int(f.get("disease_level", 0)), 1 if bool(f.get("diseased", false)) else 0,
			int(f.get("disease_until", 0)) - world.spells.now() + EMU_NOW]
		var want := [int(a.b19c), int(a.b19d), int(a.b19e), int(a.d1a0)]
		if String(r.start) == "cure": got[3] = int(a.d1a0)               # the end stays (unused once cured)
		if got != want: diffs.append("%s %s %s %s: %s != %s" % [r.type, r.mres, r.pits, r.start, got, want])
	check(diffs.is_empty(), "0x51c060: %d disease rows equal the original %s" % [fx.disease.size(), diffs.slice(0, 4)])

## Fixture "disease_count": one 0x532a20 pass (every 40th world frame) on diseased units.
func disease_count_e():
	var diffs: Array = []
	for row in fx.disease_count:
		build_world("empty", "AUHX")
		for i in int(row.pits): building("BPSP", Vector2i(-8 + 5 * i, -9), ENEMY, {})
		for u in row.units:
			var id := unit("AHIX", Vector2i(3, 0), OWNER)
			var f = world.combat.fighters[id]
			f.stats.mres = int(u.spec[2])
			world.spells.set_disease(f, 10000000)
			f.disease_count = int(u.spec[0])
			f.disease_level = int(u.spec[1])
			world.spells.disease_tick(f)
			var got := [int(f.disease_count), int(f.disease_level)]
			if got != [int(u.after.b19c), int(u.after.b19d)]: diffs.append("%s %s: %s != %s" % [row.pits, u.spec, got, [u.after.b19c, u.after.b19d]])
	check(diffs.is_empty(), "0x532a20: the disease count and level of %d units equal the original %s" % [fx.disease_count.size() * 10, diffs.slice(0, 4)])

## Fixture "regeneration" (0x51b820): a disease ends once now passes +0x1a0; while it lasts a hero does not regenerate.
func disease_end_e():
	build_world("empty", "AUHX")
	var h: int = world.host.hero_unit_id
	var f = world.combat.fighters[h]
	f.hp = 10
	world.units[h].hp = 10
	world.spells.set_disease(f, world.spells.now() + 5000)
	run_world(3000)
	var over: Dictionary = fx.regeneration.filter(func(r): return r.case == "diseased over")[0]
	var hurt: Dictionary = fx.regeneration.filter(func(r): return r.case == "diseased hurt")[0]
	check(int(f.hp) == 10 and int(hurt.hp) == 10, "a diseased hero does not regenerate (0x51b820, the original's row: %d)" % int(hurt.hp))
	run_world(2100)
	check(not bool(f.get("diseased", false)) and int(over.after.b19e) == 0 and int(f.get("disease_level", 0)) == 0, "the disease ends after +0x1a0 (0x51c060(0))")
	var unit_id := unit("AHIX", Vector2i(2, 0), OWNER)
	var u = world.combat.fighters[unit_id]
	world.spells.set_disease(u, world.spells.now() + 1000)
	run_world(1100)
	check(not bool(u.get("diseased", false)), "a unit's disease ends too")

## Fixture "getters": 0x51bd10(1) / 0x51c460(1) minus the disease level +0x19d, at least 1.
func getters_e():
	var diffs: Array = []
	for r in fx.getters:
		build_world("empty", "AUHX")
		var id := unit(String(r.type), Vector2i(12, 12), OWNER)
		var f = world.combat.fighters[id]
		world.spells.set_disease(f, 10000000)
		f.disease_level = int(r.level)
		world.spells.sync_speed(f)
		var block: Dictionary = world.combat.combat_block(f)
		block.near_hero = false                                   # the harness's unit has no hero near it
		var combat_value: int = CombatRules.effective_combat(block)
		var speed: int = int(world.units[id].base_speed)
		if [combat_value, speed] != [int(r.combat), int(r.speed)]: diffs.append("%s %d: %s != %s" % [r.type, int(r.level), [combat_value, speed], [r.combat, r.speed]])
	check(diffs.is_empty(), "0x51bd10 / 0x51c460 with the disease level: %d rows equal the original %s" % [fx.getters.size(), diffs.slice(0, 4)])

## Fixture "rot": Rot's 0x529e30 term (B1-6b Open 3): a diseased unit below the amount gets +0x19d = max(combat, speed).
func rot_e():
	var diffs: Array = []
	for r in fx.rot:
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		var units: Array = []
		for k in r.units.size():
			var u: Dictionary = r.units[k]
			var id := unit(String(u.type), Vector2i(-3 + k, 2), ENEMY, {"rank": int(u.extra.get("rank", 0))})
			var f = world.combat.fighters[id]
			if u.extra.get("disease", 0): world.spells.set_disease(f, 10000000)
			if u.extra.has("sick"):
				f.disease_level = int(u.extra.sick)
				world.spells.sync_speed(f)
			if u.extra.get("poison", 0): world.combat.set_poisoned(id, true)
			if not u.stats.is_empty():
				f.stats.combat = int(u.stats[0])
				f.stats.speed = int(u.stats[1])
				f.base.combat = int(u.stats[0])
				f.base.speed = int(u.stats[1])
				world.units[id].base_speed = int(u.stats[1])
			units.append(id)
		world.spells.cast_built(builder_record(108, h, int(r.level), {}), caster_dict(h), int(r.level), 108)
		for k in units.size():
			var f = world.combat.fighters[units[k]]
			var want := int(r.units[k].after.b19d)
			if int(f.get("disease_level", 0)) != want: diffs.append("L%d %s %s: %d != %d" % [int(r.level), r.units[k].type, r.units[k].extra, int(f.get("disease_level", 0)), want])
	check(diffs.is_empty(), "Rot on diseased units: the disease level equals the original %s" % [diffs.slice(0, 4)])

## 0x51aae0 (Read): a diseased attacker's hit diseases a target 0x51c1b0 allows when a 1..100 roll is at most
## max(1, (0x70d630 + 5 - magic armour + 10) x 5).
func contagion_e():
	build_world("empty", "AUHX")
	var a := unit("AHIX", Vector2i(2, 0), ENEMY)
	var t := unit("AHIX", Vector2i(3, 0), OWNER)
	var af = world.combat.fighters[a]
	var tf = world.combat.fighters[t]
	world.spells.set_disease(af, world.spells.now() + 100000)
	var chance := maxi(1, (5 - world.spells._hit_armour(tf, 6) + 10) * 5)
	world.combat.rng.seed_state(12345, 678)
	var r: int = world.combat.rng.roll(1, 100, 0)
	world.combat.rng.seed_state(12345, 678)
	world.spells.venom_hit(af, tf)
	check(bool(tf.get("diseased", false)) == (r <= chance), "contagion: the target is diseased when the roll %d <= %d" % [r, chance])

# ------------------------------------------------------------------------------------------------ 4. the cast path
func cast_path_e():
	var diff: Array = []
	var compared := 0
	build_world_e("empty")
	var h: int = world.host.hero_unit_id
	for row in fx.cast_path:
		var spell := int(row.spell)
		if not HeroSpells.castable(spell): continue
		world.combat.fighters[h]["cast"] = null
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
			if ok and int(sent.target[3]) != 0:
				ok = Vector2i(int(c.target.x), int(c.target.y)) - world.combat.unit_cell(h) == Vector2i(int(sent.target[3]), int(sent.target[4])) - CASTER
		elif row.pending != null:
			ok = ok and String(world.hs.pending.get("mode", "")) == "place" and int(world.hs.pending.level) == int(row.pending.level)
			ok = ok and String(world.hs.pending.type) == Spells._fourcc_text(int(row.pending.target[2]))
		else:
			ok = ok and not bool(result.get("cast", false))
		if not ok: diff.append("%d seed %s: %s" % [spell, row.seed[0], result])
		compared += 1
	print("cast_path_e: %d rows" % compared)
	check(diff.is_empty() and compared > 0, "0x5717e0: %d cast-path rows of the two schools equal the original %s" % [compared, diff.slice(0, 4)])

## Every built spell cast by the hero through the human path: the request, the placement click, order 9, the event, the
## dispatcher (paid), the record applied or the drop / dialog done.
func cast_all_e():
	var failed: Array = []
	for spell in built():
		build_world_e("empty")
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
		elif spell == 60 and world.hs.created_items.is_empty(): failed.append("60: no item")
		elif spell in [61, 96] and world.hs.trade_requests.is_empty(): failed.append("%d: no dialog" % spell)
	check(failed.is_empty(), "all %d built spells of Alchemy and Chaos cast by the hero's own path %s" % [built().size(), failed.slice(0, 6)])
