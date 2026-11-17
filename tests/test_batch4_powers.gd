extends "res://tests/test_hero_spells.gd"
## B4-1 (BATCH4_RESEARCH.md section 2): the batch-4 race powers against tests/batch4_fixtures.json (`building_cells`, `unit_cells`,
## `powers`, `sacrifice_applied`, `merge_task`, `income`, `death`, `eggs`, `poison`, `sacrifice_units`) and
## tests/batch4_review_fixtures.json (`death_full`, `merge_box`, `keys` rows of cases 0x13 / 0x14), on the hero spells' stand-alone
## combat world. The buttons in the scene (the merge, Sacrifice, the cells) are in the three batch-4 world checks.

const RacePowers = preload("res://simulation/race_powers.gd")
const START := 50000

var fixtures: Dictionary = {}
var review: Dictionary = {}

func run():
	fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch4_fixtures.json"))
	review = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch4_review_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the batch 4 world")
	if centre.x >= 0:
		for part in ["building_cells", "unit_cells", "merge", "income", "death", "eggs", "poison", "sacrifice", "elcor_holy", "keys"]:
			call(part)
	clear_world()
	if failures > 0:
		printerr("Batch 4 powers checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Batch 4 powers checks passed: %d" % checks)
	quit(0)

func now_at(ms: int):
	world.ms = ms
	world.combat.next_update_ms = ms + 25
	world.combat.now_ms = ms

func fighter(id: int):
	return world.combat.fighters[id]

class ForcedRng extends RefCounted:
	var values: Array = []
	func roll(_count: int, _sides: int, _bonus: int = 0) -> int:
		if values.is_empty(): return 100
		return int(values.pop_front())

# ------------------------------------------------------------------------------------------------ the building page (E10 / E11)
func building_cells():
	for r in fixtures.building_cells:
		if int(r.owner) != 1 or not bool(r.finished): continue
		var research: Array = r.research
		var got: Dictionary = RacePowers.b4_building_cells(String(r.building), int(r.race), func(code): return research.has(code))
		for index in [7, 8]:
			var want: Array = r.cells[index]
			var ours := int(want[0]) in [RacePowers.ELCOR_ICON, RacePowers.HOLY_ICON]
			if not ours:
				check(not got.has(index), "%s race %d: no batch-4 cell %d" % [r.building, int(r.race), index])
				continue
			check(got.has(index) and int(got[index][0]) == int(want[0]) and bool(got[index][1]) == (int(want[2]) != 0),
				"%s race %d %s: cell %d %s, the original %s" % [r.building, int(r.race), research, index, got.get(index), want])
	for icon in RacePowers.B4_TIP_LINE: check(int(RacePowers.B4_TIP_LINE[icon]) > 0, "tooltip line for icon 0x%x" % icon)

# ------------------------------------------------------------------------------------------------ the unit row (E1, E7, E8)
func unit_cells():
	for r in fixtures.unit_cells:
		var types: Array = r.units
		var research: Array = r.research
		var cells: Array = []
		for i in types.size(): cells.append(Vector2i(40 + i % 4, 40 + i / 4))
		var icons: Array = r.cells.map(func(c): return int(c[0]))
		var merge_shown := RacePowers.merge_box(types, cells)
		check(merge_shown == icons.has(RacePowers.MERGE_ICON), "%d x %s: merge cell %s" % [types.size(), types[0], merge_shown])
		var sac_shown: bool = (int(r.race) == RacePowers.SACRIFICE_RACE or research.has(RacePowers.SACRIFICE_RESEARCH)) \
			and types.all(func(t): return RacePowers.sacrificable(status_bits(String(t)), false)) \
			and (types.size() > 1 or Spells.unit_row(String(types[0])).size() < 3)   # the bottom row holds three cells (AKNX: full)
		check(sac_shown == icons.has(RacePowers.SACRIFICE_ICON), "%s race %d %s: Sacrifice cell %s" % [types, int(r.race), research, sac_shown])
		if r.mana == null: continue                            # the stock rows: the price decides
		for c in r.cells:
			if int(c[0]) == RacePowers.MERGE_ICON: check((int(c[2]) != 0) == research.has(RacePowers.MERGE_RESEARCH), "merge enabled with PWSP")
			if int(c[0]) == RacePowers.SACRIFICE_ICON: check((int(c[2]) != 0) == research.has(RacePowers.SACRIFICE_RESEARCH), "Sacrifice enabled with PSAC")
	for r in review.merge_box:
		var cells: Array = r.cells.map(func(c): return Vector2i(int(c[0]), int(c[1])))
		check(RacePowers.merge_box(["AEBX", "AEBX", "AEBX", "AEBX"], cells) == (int(r.box) == 1), "%s: box %d" % [r.case, int(r.box)])
	for r in fixtures.sacrifice_units:
		check(RacePowers.sacrificable(String(r.status).hex_to_int(), false) == (int(r.eligible) == 1), "%s %s: eligible %d" % [r.unit, r.status, int(r.eligible)])

# ------------------------------------------------------------------------------------------------ the merge (E1 / E2)
func merge():
	for r in fixtures.powers.merge:
		var groups := RacePowers.merge_groups(int(r.wisps), int(r.crystal), 100, r.research.has(RacePowers.MERGE_RESEARCH))
		check(groups == r.leads.size() and int(r.crystal) - 100 * groups == int(r.stock_after),
			"%d Wisps, %d crystal: %d groups, the original %d (%d left)" % [int(r.wisps), int(r.crystal), groups, r.leads.size(), int(r.stock_after)])
	new_world()
	check(world.production.price_of(OWNER, RacePowers.ANCIENT_WISP, RacePowers.WISP) == [0, 0, 100, 0], "the merge's price 0x40b6b0(AEAX, AEBX): 100 crystal: %s" % [world.production.price_of(OWNER, RacePowers.ANCIENT_WISP, RacePowers.WISP)])
	for r in fixtures.merge_task:
		var made: Array = r.messages.filter(func(m): return m.message == "0xfa")
		if bool(r.stamped): check(r.messages.is_empty(), "a stamped leader does nothing")
		else: check(made.size() == 1 and String(made[0].type) == RacePowers.ANCIENT_WISP and String(made[0].effect) == RacePowers.MERGE_EFFECT, "one AEAX with EZ13 (%d alive)" % int(r.alive))

# ------------------------------------------------------------------------------------------------ income (E3)
func income():
	for r in fixtures.income.units:
		check(RacePowers.income_of([String(r.unit)], 0).income == r.income.map(func(v): return int(v)), "%s: %s" % [r.unit, r.income])
	for r in fixtures.income.buildings:
		var well := String(r.building) == RacePowers.WELL and not bool(r.flag_115) and not bool(r.state_8)
		check(RacePowers.income_of([], 1 if well else 0).income == r.income.map(func(v): return int(v)), "%s: %s" % [r.building, r.income])
	var cases := {"nothing": [[], 0, 0], "two Ancient Wisps": [["AEAX", "AEAX"], 0, 0], "one Well": [[], 1, 0], "Well, Income I": [[], 1, 1],
		"Ancient Wisp, Income I": [["AEAX"], 0, 1], "two Wells, Ancient Wisp, Income II": [["AEAX"], 2, 2]}
	for r in fixtures.income.aggregate:
		var c: Array = cases[String(r.case)]
		var e := Economy.new(0)
		e.add_player(0, [0, 0, 0, 0])
		e.research_level = func(_p, id): return int(c[2]) if id == "PIBX" else 0
		e.other_income = func(_p): return RacePowers.income_of(c[0], int(c[1]))
		check(e._calculate(0) == r.totals.map(func(v): return int(v)), "%s: %s, the original %s" % [r.case, e._calculate(0), r.totals])

# ------------------------------------------------------------------------------------------------ death spawns and eggs (E5 / E6)
func death():
	for r in review.death_full:
		new_world()
		var v := unit(String(r.victim), Vector2i(0, 0), OWNER)
		set_command(OWNER, int(r.limit))
		while used(OWNER) < int(r.used): unit("AKIX", Vector2i(-8 + used(OWNER) % 6, 5 + used(OWNER) / 6), OWNER)
		if used(OWNER) > int(r.used): set_command(OWNER, int(r.limit) + used(OWNER) - int(r.used))
		var before: int = world.units.size()
		world.combat.apply_damage("unit", v, 100000, -1)
		var made: Array = world.units.slice(before).map(func(u): return String(u.type_id))
		check(made == r.spawned, "%s dies at %d / %d: %s, the original %s" % [r.victim, int(r.used), int(r.limit), made, r.spawned])
	for code in ["AWJX", "AKNX"]:
		new_world()
		var v := unit(code, Vector2i(0, 0), OWNER)
		var before: int = world.units.size()
		world.combat.apply_damage("unit", v, 100000, -1)
		check(world.units.size() == before, "%s leaves nothing" % code)

func eggs_of(owner: int) -> Array:
	return world.production.buildings.values().filter(func(b): return String(b.original_type_id) == RacePowers.EGG and int(b.owner) == owner)

func eggs():
	for r in fixtures.death:
		if String(r.case) != "kill" or not bool(r.host): continue
		new_world()
		var k := unit(String(r.killer), Vector2i(0, 0), OWNER)
		var owner := OWNER if int(r.victim_owner) == 1 else ENEMY
		var v := unit(String(r.victim), Vector2i(2, 0), owner if String(r.victim) != "ACSH" else 6)
		if bool(r.allied): continue                            # alliances: the relation table test is combat.allied's (B1-4)
		now_at(START)
		world.combat.apply_damage("unit", v, 100000, k)
		check(eggs_of(OWNER).size() == r.records.size(), "%s kills %s of %d: %d eggs, the original %d" % [r.killer, r.victim, int(r.victim_owner), eggs_of(OWNER).size(), r.records.size()])
	for room in [[0, 40], [38, 40], [40, 40]]:
		new_world()
		var queen := unit(RacePowers.QUEEN, Vector2i(0, 0), OWNER)
		var v := unit("AHIX", Vector2i(3, 0), ENEMY)
		now_at(START)
		world.combat.apply_damage("unit", v, 100000, queen)
		check(eggs_of(OWNER).size() == 1, "the Queen's kill leaves an egg")
		set_command(OWNER, used(OWNER) + int(room[1]) - int(room[0]))
		var before: int = world.units.size()
		run_world(RacePowers.EGG_MS - 200)
		check(eggs_of(OWNER).size() == 1 and world.units.size() == before, "no hatch before 40 s")
		run_world(400)
		var made: Array = world.units.slice(before).map(func(u): return String(u.type_id))
		var want := RacePowers.hatch_count(int(room[0]), int(room[1]))
		check(made.size() == want and made.all(func(t): return t == RacePowers.HATCH_UNIT), "room %s: %d Spiders, the original %d" % [room, made.size(), want])
		check(eggs_of(OWNER).is_empty(), "the egg is removed after the hatch")
	for r in fixtures.eggs:
		if not bool(r.end_passed): continue
		check(r.messages.size() == RacePowers.hatch_count(int(r.room[0]), int(r.room[1])), "eggs row %s" % [r.room])

# ------------------------------------------------------------------------------------------------ type-class poison (E9)
func poison():
	for r in fixtures.poison:
		new_world()
		var a := unit(String(r.attacker), Vector2i(0, 0), ENEMY)
		var t := unit(String(r.target), Vector2i(1, 0), OWNER, {"hp": 500})
		var af = fighter(a)
		var tf = fighter(t)
		var word := int(af.base.get("word_ae", 0)) & 0xffff
		check(word == String(r.word).hex_to_int(), "%s carries the class word %s: 0x%x" % [r.attacker, r.word, word])
		var refused: bool = not world.spells.poisonable(tf)
		var best := 0
		if not refused: best = mini(100, RacePowers.poison_chance(word & 0xff, world.spells._hit_armour(tf, 5)))
		check(best == int(r.highest_poisoning_roll), "%s on %s: %d, the original %d" % [r.attacker, r.target, best, int(r.highest_poisoning_roll)])
		# the hit itself at the boundary roll
		if int(r.highest_poisoning_roll) > 0 and int(r.highest_poisoning_roll) < 100:
			var forced := ForcedRng.new()
			forced.values = [int(r.highest_poisoning_roll) + 1]
			var real = world.combat.rng
			world.combat.rng = forced
			world.spells.venom_hit(af, tf)
			check(not bool(tf.get("poisoned", false)), "%s on %s: a roll above the chance does not poison" % [r.attacker, r.target])
			forced.values = [int(r.highest_poisoning_roll)]
			world.spells.venom_hit(af, tf)
			world.combat.rng = real
			check(bool(tf.get("poisoned", false)), "%s on %s: the boundary roll poisons" % [r.attacker, r.target])

# ------------------------------------------------------------------------------------------------ Sacrifice (E7)
func sacrifice():
	for r in fixtures.sacrifice_applied:
		new_world()
		var ids: Array = []
		for i in r.units.size(): ids.append(unit(String(r.units[i]), Vector2i(i, 0), OWNER))
		var record: Dictionary = world.spells.sacrifice_record(OWNER, ids, int(r.roll))
		check(int(record.kind) == RacePowers.SACRIFICE_KIND and int(record.w9b) == (1 if int(r.roll) <= 4 * ids.size() else 0), "%s roll %d: +0x9b %d" % [r.units, int(r.roll), int(record.w9b)])
		var before: int = world.units.size()
		var result: Dictionary = SpellEffects.apply(record, world.spells)
		check(ids.all(func(id): return not world.combat.alive(fighter(id))), "%s: all dead" % [r.units])
		var made: Array = world.units.slice(before).map(func(u): return String(u.type_id))
		var want: Array = r.applied.filter(func(m): return m.message == "0xfa").map(func(m): return String(m.type))
		check(made == want, "%s roll %d: %s, the original %s" % [r.units, int(r.roll), made, want])
		if not made.is_empty(): check((world.units[before].cell - world.units[ids[0]].cell).length() < 2.0, "the Daemon by the first target")
	for r in fixtures.powers.sacrifice:
		if r.get("repeat") or not r.has("roll"): continue
		var n: int = r.units.size()
		var pay: Array = r.presses[0].messages[0].payment.words
		check(int(pay[3]) == RacePowers.SACRIFICE_CRYSTAL * n, "Sacrifice of %d pays %d" % [n, int(pay[3])])

# ------------------------------------------------------------------------------------------------ Elcor's Balm, Holy Word (E10 / E11)
func casts_of() -> Array:
	var out: Array = []
	world.spells.cast_done.connect(func(info): out.append(info))
	return out

func elcor_holy():
	for r in fixtures.powers.elcor:
		if not r.has("stock"): continue
		new_world()
		world.production.research[OWNER] = r.research.duplicate()
		var b := building(String(r.building), Vector2i(0, 0), OWNER, {})
		world.economy.stockpiles[OWNER][2] = int(r.stock[2])
		var casts := casts_of()
		now_at(START)
		for p in r.presses.size():
			var crystal: int = int(world.economy.stockpiles[OWNER][2])
			world.spells.elcor_balm(b)
			var want: Array = r.presses[p].messages
			check((crystal - int(world.economy.stockpiles[OWNER][2])) == (RacePowers.ELCOR_CRYSTAL if not want.is_empty() else 0), "Elcor %s press %d with %d crystal" % [r.building, p, crystal])
		check(casts.size() == r.presses.filter(func(p): return not p.messages.is_empty()).size(), "Elcor %s: %d records" % [r.building, casts.size()])
		if not casts.is_empty():
			var rec: Dictionary = casts[0].record
			check([int(rec.kind), int(rec.amount), int(rec.radius), int(rec.b9), int(rec.b12)] == [20, 100, 255, 1, 2], "Elcor's record kind 0x14, 100, radius 255")
	# the computer pays 300
	new_world()
	world.combat.ai_players[OWNER] = true
	var hb := building("BPHE", Vector2i(0, 0), OWNER, {})
	world.economy.stockpiles[OWNER][2] = 1000
	world.spells.elcor_cast(world.production.building(hb))
	check(int(world.economy.stockpiles[OWNER][2]) == 700, "a computer's Balm costs 300")
	# hurt friends anywhere heal (within the record's 255 and its 24 targets)
	new_world()
	world.production.research[OWNER] = ["PELC"]
	var heb := building("BPHE", Vector2i(0, 0), OWNER, {})
	var hurt := unit("AHIX", Vector2i(10, 10), OWNER, {"hp": 500})
	fighter(hurt).hp = 100
	world.units[hurt].hp = 100
	now_at(START)
	world.spells.elcor_balm(heb)
	check(int(fighter(hurt).hp) == 200, "a hurt friend healed 100: %d" % int(fighter(hurt).hp))
	var evil := _evil_type()
	check(evil != "", "an evil type (STATUS 0x8000000) on the rosters: %s" % evil)
	for r in fixtures.powers.holy:
		new_world()
		world.production.research[OWNER] = r.research.duplicate()
		var b := building(String(r.building), Vector2i(0, 0), OWNER, {})
		world.economy.stockpiles[OWNER][2] = int(r.stock[2])
		match String(r.get("case", "")):
			"no enemy": pass
			"good enemy": unit("AHIX", Vector2i(5, 0), ENEMY)
			"evil at 14": unit(evil, Vector2i(14, 0), ENEMY)
			"evil at 15": unit(evil, Vector2i(15, 0), ENEMY)
			_: unit(evil, Vector2i(5, 0), ENEMY)
		var casts := casts_of()
		now_at(START)
		for p in r.presses.size():
			var crystal: int = int(world.economy.stockpiles[OWNER][2])
			world.spells.holy_word(b)
			var want: Array = r.presses[p].messages
			check((crystal - int(world.economy.stockpiles[OWNER][2])) == (RacePowers.HOLY_CRYSTAL if not want.is_empty() else 0), "Holy Word %s %s press %d" % [r.building, r.get("case", ""), p])
		if not casts.is_empty():
			var rec: Dictionary = casts[0].record
			check([int(rec.kind), int(rec.amount), int(rec.radius), String(rec.summon), int(rec.w9b), int(rec.d135)] == [16, 50, 15, "EMM2", 4, RacePowers.EVIL], "Holy Word's record")

func _evil_type() -> String:
	for code in ["AKIX", "AKMX", "AUIX", "AVBX", "AKJX"]:
		if status_bits(code) & RacePowers.EVIL: return code
	return ""

# ------------------------------------------------------------------------------------------------ the O and Q keys (R8)
func keys():
	for r in review.keys:
		if int(r.case) != world.spells.HOLY_CASE and int(r.case) != world.spells.ELCOR_CASE: continue
		new_world()
		world.production.research[OWNER] = r.research.duplicate()
		var ids := {}
		for e in r.buildings:
			var cell := Vector2i(int(e[1][0]), int(e[1][1]))
			var off := (cell - Vector2i(40, 40)) / 6
			var id := building(String(e[0]), off, OWNER if int(e[4]) == 1 else ENEMY, {})
			if not bool(e[3]): world.production.building(id).constructing = true
			if bool(e[2]): world.host.selected_building_id = id
			ids["%s@%d,%d" % [e[0], cell.x, cell.y]] = id
		world.economy.stockpiles[OWNER][2] = int(r.crystal)
		var casts := casts_of()
		var key: int = int(world.spells.table.keys[int(r.case)])
		for p in r.presses.size():
			var before := casts.size()
			world.spells.hot_key(key, OWNER)
			var want: Array = r.presses[p].casts
			var got: Array = casts.slice(before).map(func(i): return int(i.caster.id))
			var want_ids: Array = want.map(func(c): return int(ids.get(String(c.caster), -2)))
			check(got == want_ids, "%s press %d: casters %s, the original %s" % [r.name, p, got, want])
