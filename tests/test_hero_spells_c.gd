extends "res://tests/test_hero_spells_b.gd"
## Hero spells B1-6c (SPELLS_RESEARCH.md section "B1-6c") against tests/hero_spell_c_fixtures.json
## (tools/emulate_hero_spells_c.py), on B1-6a / B1-6b's world and helpers:
## 1. every builder of Nature (20-29), Divination (110-119) and Arcane (120-129) at levels 1-4 equals the original records
##    cast by a hero (all fields, the full descriptors, the dialog picks of Change Weather and Elementalism, Call Sage's
##    roll under eight seeds, the command checks, the effect 0x2a scaling, Destruction's hit points, True Sight's 0x70d488);
## 2. the applier on every fixture world (targets, hit points, cures, statuses, summons, Banish with and without PBIN,
##    Psychic Blast's 0x221 statuses, Dispel);
## 3. the consumers: Psychic Blast's combat 1, Mind Leech / Mana Leech on a kill, Enervate's hero mana rate,
##    Comprehension's research discount, See Invisible's fog / pick rule, True Sight's sight bonus, the Arcane effects on
##    cost, radius, duration and power; the arrow rule on buildings (missiles.gd) against the B1-6b fixture's BKH0 rows;
## 4. the cast path 0x5717e0 for the thirty spells (and Banish 18) under eight seeds, the dialogs of modes 9 / 10, and
##    each spell ordered and dispatched by a hero through its own path (placement click, dialog pick).

const Visibility = preload("res://simulation/visibility.gd")
const Missiles = preload("res://simulation/missiles.gd")
const SPELLS_C := [20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
	120, 121, 122, 123, 124, 125, 126, 127, 128, 129]
var seeds: Array = []

func run():
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_spell_c_fixtures.json"))
	for i in 8: seeds.append(fx.cast_path[i].seed)
	centre = open_ground()
	check(centre.x >= 0, "open ground for the hero spell world")
	if centre.x >= 0:
		for part in ["records_c", "applier_c", "consumers_c", "arrows_buildings", "cast_path_c", "cast_all_c"]:
			var t0 := Time.get_ticks_msec()
			call(part)
			print("%s: %d ms" % [part, Time.get_ticks_msec() - t0])
	clear_world()
	if failures > 0:
		printerr("Hero spell C checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Hero spell C checks passed: %d" % checks)
	quit(0)

## The spells of the three schools this build casts (a school's builders arrive with its commit).
func built() -> Array:
	return SPELLS_C.filter(func(s): return HeroSpells.castable(s))

# ------------------------------------------------------------------------------------------------ the worlds
## tools/emulate_hero_spells_c.py world_for as [kind, code, side, offset, extra].
func fixture_world(scenario: String) -> Array:
	match scenario:
		"banish", "banish pbin":
			return [["unit", "AHIX", "enemy", Vector2i(1, 0), {"rank": 0}], ["unit", "AHIX", "enemy", Vector2i(2, 0), {"rank": 1}],
				["unit", "AHIX", "enemy", Vector2i(3, 0), {"rank": 2}], ["unit", "AHIX", "enemy", Vector2i(4, 0), {"rank": 3}],
				["unit", "AHKX", "enemy", Vector2i(0, 2), {"rank": 4}], ["unit", "AHKX", "enemy", Vector2i(0, 3), {"rank": 6}],
				["unit", "AAEF", "enemy", Vector2i(-2, 0), {}], ["unit", "AUIX", "enemy", Vector2i(-3, 1), {}],
				["unit", "AHIX", "own", Vector2i(-1, -1), {}], ["building", "BKH0", "enemy", Vector2i(-4, -4), {}],
				["unit", "AHIX", "enemy", Vector2i(0, 9), {}], ["unit", "AHIX", "enemy", Vector2i(0, 10), {}]]
		"leech":
			return [["unit", "AHIX", "own", Vector2i(1, 0), {}], ["unit", "AUIX", "own", Vector2i(2, 0), {}],
				["unit", "AHKX", "own", Vector2i(0, 9), {}], ["unit", "AHKX", "own", Vector2i(0, 10), {}],
				["unit", "AHIX", "enemy", Vector2i(-1, 0), {}], ["unit", "AAEF", "own", Vector2i(0, -2), {}],
				["building", "BKD0", "own", Vector2i(-4, -4), {}]]
		"entangle":
			return [["unit", "AHIX", "enemy", Vector2i(1, 0), {}], ["unit", "AHKX", "enemy", Vector2i(2, 0), {}],
				["unit", "AHFX", "enemy", Vector2i(0, 2), {}], ["unit", "AABA", "enemy", Vector2i(-2, 0), {}],
				["unit", "ADGX", "enemy", Vector2i(0, -2), {}], ["unit", "AUIX", "enemy", Vector2i(3, 3), {}],
				["unit", "AWJX", "enemy", Vector2i(-3, 2), {}], ["unit", "AHIX", "own", Vector2i(-1, -1), {}],
				["unit", "AHIX", "enemy", Vector2i(0, 9), {}], ["unit", "AHIX", "enemy", Vector2i(0, 10), {}],
				["building", "BKH0", "enemy", Vector2i(4, -3), {}]]
	return super.fixture_world(scenario)

func build_world(scenario: String, hero_type_id: String) -> Dictionary:
	var ids: Dictionary = super.build_world(scenario, hero_type_id)
	world.host.visibility = Visibility.new(128, 128)
	var h = world.combat.fighters[world.host.hero_unit_id]
	if scenario == "hero hurt":
		h.max_hp = maxi(int(h.max_hp), 40)
		h.hp = 40
		world.units[h.id].hp = 40
	if scenario == "banish pbin": world.production.research[ENEMY] = ["PBIN"]
	if scenario.begins_with("seed "): seed_rng(int(scenario.split(" ")[1]))
	return ids

func seed_rng(i: int):
	world.combat.rng.seed_state(int(seeds[i][0]), int(seeds[i][1]))

func target_for(spell: int, choice: int = 0) -> Dictionary:
	if spell == 28: return {"id": choice}                    # the dispatcher hands the target's +4 (the dialog pick)
	return super.target_for(spell, choice)

func pick_of(scenario: String) -> int:
	return int(scenario.split(" ")[1]) if scenario.begins_with("pick ") else 0

func hero_type(_spell: int) -> String:
	return "AUHX"

# ------------------------------------------------------------------------------------------------ 1. records
func records_c():
	var count := 0
	var diffs: Array = []
	var scenarios := {}
	for spell in built():
		for c in cases(spell): scenarios[String(c.scenario)] = true
	for scenario in scenarios:
		build_world(scenario, "AUHX")
		var h: int = world.host.hero_unit_id
		for spell in built():
			for c in cases(spell):
				if String(c.scenario) != scenario: continue
				if scenario.begins_with("seed "): seed_rng(int(scenario.split(" ")[1]))
				world.host.visibility.sight_bonus = {}
				var got := built_list(builder_record(spell, h, int(c.level), target_for(spell, pick_of(scenario))))
				var want := records_of_case(c)
				var label := "%s %s L%d" % [fx.spells[str(spell)].name, scenario, int(c.level)]
				if got.size() != want.size():
					diffs.append("%s: %d records (original %d)" % [label, got.size(), want.size()])
					continue
				for i in got.size():
					var d := compare_b(got[i], want[i])
					if not d.is_empty(): diffs.append("%s record %d: %s" % [label, i, d])
				# the generator after the builder (Call Sage's 1..3 roll), True Sight's 0x70d488
				if scenario.begins_with("seed "):
					var rng := [world.combat.rng.first, world.combat.rng.second]
					if rng != [int(c.rng[1][0]), int(c.rng[1][1])]: diffs.append("%s: generator %s" % [label, rng])
				if spell == 118 and int(world.host.visibility.sight_bonus.get(OWNER, 0)) != int(c.globals_built.sight[OWNER]):
					diffs.append("%s: sight bonus %s" % [label, world.host.visibility.sight_bonus])
				count += 1
	check(diffs.is_empty(), "B1-6c: %d record cases of %d spells equal the original %s" % [count, built().size(), diffs.slice(0, 6)])
	check(count >= built().size() * 4, "every built spell compared at four levels at least (%d)" % count)

# ------------------------------------------------------------------------------------------------ 2. the applier
func applier_c():
	var compared := 0
	var diffs: Array = []
	for spell in built():
		for c in cases(spell):
			if not c.has("applied"): continue
			if int(c.level) in [2, 3] and not spell in [21, 114]: continue    # Gemberry changes kind, Banish its amount
			var scenario := String(c.scenario)
			# Destruction 'edges' gathers past 24 objects: which of two objects in one grid row is taken depends on the row
			# list's order (the harness links the newest first; the original's order is B1-4 Open 2): compared separately.
			if spell == 129 and scenario == "edges": continue
			var ids := build_world(scenario, "AUHX")
			var h: int = world.host.hero_unit_id
			var record: Dictionary = builder_record(spell, h, int(c.level), target_for(spell, pick_of(scenario)))
			var info: Dictionary = world.spells.cast_built(record, caster_dict(h), int(c.level), spell)
			var label := "%s %s L%d" % [fx.spells[str(spell)].name, scenario, int(c.level)]
			var d := compare_application(spell, c, info, ids)
			if spell == 28 and not record.is_empty() and world.host.day_night.records.back() != pick_of(scenario):
				d.append("kind 4 amount %s" % [world.host.day_night.records])
			if not d.is_empty(): diffs.append("%s: %s" % [label, d])
			compared += 1
	check(diffs.is_empty(), "B1-6c: %d applications equal the original %s" % [compared, diffs.slice(0, 6)])
	if 129 in built():
		var c := fixture_case(129, "edges", 1)
		var ids := build_world("edges", "AUHX")
		var h: int = world.host.hero_unit_id
		var info: Dictionary = world.spells.cast_built(builder_record(129, h, 1, {}), caster_dict(h), 1, 129)
		var want: Array = resolved_of(c).target_ids
		var got: Array = info.result.targets
		var rows_got := {}
		var rows_want := {}
		for o in offsets(got, ids): rows_got[o.y] = int(rows_got.get(o.y, 0)) + 1
		for o in fixture_offsets(want, ids): rows_want[o.y] = int(rows_want.get(o.y, 0)) + 1
		check(got.size() == 24 and want.size() == 24 and rows_got == rows_want,
			"Destruction 'edges': 24 targets, the same count per grid row as the original (the order inside a row is B1-4 Open 2)")

# ------------------------------------------------------------------------------------------------ 3. consumers
func consumers_c():
	if 119 in built():
		# Psychic Blast: 0x46 makes the combat value 1 while it lasts (0x51bd10).
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		var k := unit("AHKX", Vector2i(2, 0), ENEMY)
		var kf = world.combat.fighters[k]
		var before := int(world.combat.combat_block(kf).combat)
		world.spells.cast_built(builder_record(119, h, 1, {}), caster_dict(h), 1, 119)
		check(int(world.combat.combat_block(kf).combat) == 1 and before > 1, "Psychic Blast: the Knight's combat is 1 for 5 s (was %d)" % before)
		var near: Dictionary = world.combat.combat_block(kf)
		near["near_hero"] = true
		near["enc"] = 0
		check(CombatRules.effective_combat(near) == 1, "Psychic Blast: exactly 1 even next to its hero (REVIEW D1)")
		run_world(5100)
		check(int(world.combat.combat_block(kf).combat) == before, "Psychic Blast: combat back after the 5 s")
	if 117 in built():
		# Mind Leech: a killer with 0x19 takes the victim's experience (0x526fe0 / 0x527100).
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		var a := unit("AHKX", Vector2i(1, 0), OWNER)
		var v := unit("AHIX", Vector2i(2, 0), ENEMY)
		world.combat.fighters[v].xp = 30
		world.spells.cast_built(builder_record(117, h, 1, {}), caster_dict(h), 1, 117)
		var xp0 := int(world.combat.fighters[a].xp)
		world.combat.apply_damage("unit", v, 1000, a, "unit")
		check(int(world.combat.fighters[a].xp) - xp0 >= 30, "Mind Leech: the Knight takes the victim's 30 experience (%d)" % (int(world.combat.fighters[a].xp) - xp0))
	if 127 in built():
		# Mana Leech: a hero kill fills the pool by level + 4, once per second (0x526de0 / 0x5210b0).
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		var hf = world.combat.fighters[h]
		world.spells.cast_built(builder_record(127, h, 2, {}), caster_dict(h), 2, 127)
		hf.mana = 100
		var v1 := unit("AHIX", Vector2i(2, 0), ENEMY)
		var v2 := unit("AHIX", Vector2i(3, 0), ENEMY)
		world.combat.apply_damage("unit", v1, 1000, h, "unit")
		var after1 := int(hf.mana)
		world.combat.apply_damage("unit", v2, 1000, h, "unit")
		check(after1 == 106 and int(hf.mana) == 106, "Mana Leech level 2: a kill gives 6 mana, a second kill in the same second none (%d, %d)" % [after1, int(hf.mana)])
	if 122 in built():
		# Enervate: the hero pool's rate gains effect 0x21 (0x51b580's hero branch).
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		var hf = world.combat.fighters[h]
		var block: Dictionary = world.combat.hero_block(OWNER)
		var r0: int = world.spells.hero_mana_rate(hf, block, [])
		world.spells.cast_built(builder_record(122, h, 1, {}), caster_dict(h), 1, 122)
		var r1: int = world.spells.hero_mana_rate(hf, block, [])
		check(r1 < r0 and r1 == CombatRules.tdiv((20000 / maxi(1, HeroSpells.HeroRules.derived(block.stats, 9, 1))) * 100, 150),
			"Enervate level 1: the hero's mana interval %d -> %d (percent 100 + 50)" % [r0, r1])
	if 115 in built():
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		world.spells.cast_built(builder_record(115, h, 2, {}), caster_dict(h), 2, 115)
		check(world.spells.research_status(OWNER) == 30, "Comprehension level 2: research price - 30 % (0x40b6b0 effect 0x25)")
	if 112 in built():
		# See Invisible: an invisible enemy (+0x1f1) is hidden from the local player until the hero sees invisible.
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		var vis = world.host.visibility
		vis.fog = false
		vis.shroud = false
		var e := unit("AHIX", Vector2i(3, 0), ENEMY)
		world.spells.set_invisible({"kind": "unit", "id": e}, 10000000)   # B1-6d: +0x1f1 lives on the fighter (synced each step)
		run_world(25)
		var hidden: bool = not vis.unit_visible(OWNER, e, ENEMY, centre + Vector2i(3, 0))
		world.spells.cast_built(builder_record(112, h, 1, {}), caster_dict(h), 1, 112)
		run_world(25)
		check(hidden and vis.unit_visible(OWNER, e, ENEMY, centre + Vector2i(3, 0)) and vis.unit_visible(ENEMY, e, ENEMY, centre),
			"See Invisible: the invisible enemy shows once the hero has effect 0x43 (0x40dd10)")
	if 118 in built():
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		world.spells.cast_built(builder_record(118, h, 3, {}), caster_dict(h), 3, 118)
		run_world(400000)
		check(int(world.host.visibility.sight_bonus.get(OWNER, 0)) == 3, "True Sight level 3: the sight bonus 0x70d488 + 3, kept")
		world.combat.visibility = world.host.visibility
		world.combat.refresh_research(OWNER)
		check(int(world.host.visibility.sight_bonus.get(OWNER, 0)) == 3, "True Sight: a research completion keeps the spell's share (REVIEW D2)")
	if 120 in built():
		# The Arcane effects through the existing consumers: Mana Flow (cost), Command (radius), Extend (duration),
		# Empower (power), Concentration (the cast chance).
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		var hf = world.combat.fighters[h]
		var cost0: int = world.spells.cost(hf, 59)
		var r0: int = world.spells.spell_radius(hf, 0)
		var d0: int = world.spells.duration(hf, 0, 0)
		var p0: int = world.spells.spell_power(OWNER, 100)
		var c0: int = world.hs.chance_terms(hf, world.combat.hero_block(OWNER))
		for spell in [120, 121, 123, 124, 128]: world.spells.cast_built(builder_record(spell, h, 1, {}), caster_dict(h), 1, spell)
		check(world.spells.cost(hf, 59) == (75 * world.spells.table_cost(59)) / 100 and cost0 == world.spells.table_cost(59), "Mana Flow: cost x 75 %")
		check(world.spells.spell_radius(hf, 0) == (25 * r0) / 100 + r0, "Command level 1: radius + 25 percent (%d -> %d)" % [r0, world.spells.spell_radius(hf, 0)])
		check(world.spells.duration(hf, 0, 0) == d0 * 2, "Extend: durations x 2")
		check(world.spells.spell_power(OWNER, 100) == p0 + 50, "Empower level 1: power + 50 %")
		check(world.hs.chance_terms(hf, world.combat.hero_block(OWNER)) == c0 + 20, "Concentration level 1: the cast chance + 20")

# ------------------------------------------------------------------------------------------------ arrows on buildings
## B1-6b open item 10: missiles.gd's building rule against the B1-6b fixture's BKH0 rows (EMA0 / EMF0 / EMAP, +0x160
## bit 0x400, PHUN). The input of the rule is the EMF0 row of the same damage (fire is not reduced).
func arrows_buildings():
	var fb: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_spell_b_fixtures.json"))
	var plain := {}
	for r in fb.arrows:
		if bool(r.building) and String(r.art) == "EMF0" and r.flags.is_empty() and int(r.b160) == 0: plain[int(r.damage)] = int(r.dealt)
	var diffs: Array = []
	var compared := 0
	for r in fb.arrows:
		if not bool(r.building): continue
		var phun := false
		for fl in r.flags: if String(fl[0]) == "PHUN": phun = true
		var m := {"id": String(r.art), "shooter_elevation": 0, "flags": int(r.b160)}
		var d: int = int(plain[int(r.damage)])
		var got := Missiles.impact_damage(m, int(r.damage), int(r.mclass), "building", 0, func(_dmg, _t): return d, phun)
		if got != int(r.dealt): diffs.append("%s %d b160 %d %s: %d != %d" % [r.art, int(r.damage), int(r.b160), r.flags, got, int(r.dealt)])
		compared += 1
	check(diffs.is_empty() and compared == 18, "arrows against buildings: %d hits equal 0x5427e0 %s" % [compared, diffs])
	# class 0xb: at least 2 (the same rule as for units)
	check(Missiles.building_arrow(15, 0xb, 0, false) == 2 and Missiles.building_arrow(15, 0, 0x400, false) == 2 and Missiles.building_arrow(150, 0, 0x400, true) == 300,
		"class 0xb keeps 2, +0x160 bit 0x400 doubles (PHUN too)")

# ------------------------------------------------------------------------------------------------ 4. the cast path
func cast_path_c():
	var diff: Array = []
	build_world("empty", "AUHX")
	var h: int = world.host.hero_unit_id
	var compared := 0
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
		var dialog := ""
		for u in row.ui: if u.call == "dialog": dialog = String(u.icons)
		if not sent.is_empty():
			var c = f.get("cast")
			ok = ok and c != null and int(c.level) == int(sent.level)
			if ok and int(sent.target[3]) != 0:
				ok = Vector2i(int(c.target.x), int(c.target.y)) - world.combat.unit_cell(h) == Vector2i(int(sent.target[3]), int(sent.target[4])) - Vector2i(40, 40)
		elif dialog == "EWTHEWTHEWTHEWTH":
			ok = ok and String(world.hs.pending.get("mode", "")) == "weather" and int(world.hs.pending.level) == int(row.pending.level)
		elif dialog == "AAEAAAEEAAEFAAEW":
			ok = ok and String(world.hs.pending.get("mode", "")) == "elemental" and int(world.hs.pending.level) == int(row.pending.level) \
				and Vector2i(world.hs.pending.cell) - world.combat.unit_cell(h) == Vector2i(int(row.pending.target[3]), int(row.pending.target[4])) - Vector2i(40, 40)
		elif row.pending != null:
			ok = ok and String(world.hs.pending.get("mode", "")) == "place" and int(world.hs.pending.level) == int(row.pending.level)
		else:
			ok = ok and not bool(result.get("cast", false))
		if not ok: diff.append("%d seed %s: %s" % [spell, row.seed[0], result])
		compared += 1
	check(diff.is_empty() and compared > 0, "0x5717e0: %d cast-path rows of the three schools equal the original %s" % [compared, diff.slice(0, 4)])

## Every built spell cast by the hero through the human path: the request, the placement click or the dialog pick,
## order 9, the event, the dispatcher, the record applied.
func cast_all_c():
	var failed: Array = []
	for spell in built() + ([18] if HeroSpells.castable(18) else []):
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 10 + spell / 10, "unlock_level": 1, "rank": 15 if spell % 10 < 5 else 25}]
		var f = world.combat.fighters[h]
		f.mana = 200
		f.max_mana = 200
		world.combat.rng.seed_state(12345, 678)
		var request: Dictionary = world.hs.cast_request(h, spell)
		if request.get("pending", "") == "place": request = world.hs.place(world.combat.unit_cell(h) + Vector2i(4, 4))
		elif request.get("pending", "") in ["weather", "elemental"]: request = world.hs.choose(2)
		if not bool(request.get("cast", false)):
			failed.append("%d: %s" % [spell, request])
			continue
		var dispatched := {}
		var on_cast := func(info): dispatched.merge(info, true)
		world.spells.cast_done.connect(on_cast)
		run_world(4000, func(): return f.get("cast") == null)
		world.spells.cast_done.disconnect(on_cast)
		if dispatched.is_empty() or int(f.mana) >= 200: failed.append("%d: not dispatched (mana %d)" % [spell, int(f.mana)])
	check(failed.is_empty(), "all %d built spells of Nature, Divination and Arcane cast by the hero's own path %s" % [built().size(), failed.slice(0, 6)])
