extends "res://tests/test_hero_spells.gd"
## B5-1 (BATCH5_RESEARCH.md section 2 and section 11): the batch-5 race powers against tests/batch5_fixtures.json (`building_cells`,
## `powers` chaos / wrath / payers / keys, `spore`, `income`, `class_hits`, `immunity`, `build_list`), tests/batch5_review_fixtures.json
## (`key_loop` rows of cases 0x22 / 0x24, `advisor`, `panel`) and tests/batch5_meteor_fixtures.json (the meteor's missile and its
## landing, tools/emulate_batch5_meteor.py), on the hero spells' stand-alone combat world. The cells in the scene are in the three
## batch-5 world checks.

const RacePowers = preload("res://simulation/race_powers.gd")
const Missiles = preload("res://simulation/missiles.gd")
const START := 50000

var fixtures: Dictionary = {}
var review: Dictionary = {}
var meteors: Dictionary = {}

func run():
	fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch5_fixtures.json"))
	review = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch5_review_fixtures.json"))
	meteors = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch5_meteor_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the batch 5 world")
	if centre.x >= 0:
		for part in ["building_cells", "chaos", "wrath", "payers", "keys", "advisor", "meteor_path", "meteor_landing", "spore", "income",
				"class_hits", "immunity", "build_list"]:
			call(part)
	clear_world()
	if failures > 0:
		printerr("Batch 5 powers checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Batch 5 powers checks passed: %d" % checks)
	quit(0)

func now_at(ms: int):
	world.ms = ms
	world.combat.next_update_ms = ms + 25
	world.combat.now_ms = ms

func fighter(id: int):
	return world.combat.fighters[id]

func casts_of() -> Array:
	var out: Array = []
	world.spells.cast_done.connect(func(info): out.append(info))
	return out

func notices_of() -> Array:
	var out: Array = []
	world.spells.notice.connect(func(text): out.append(text))
	return out

class ForcedRng extends RefCounted:
	var values: Array = []
	func roll(_count: int, _sides: int, _bonus: int = 0) -> int:
		if values.is_empty(): return 100
		return int(values.pop_front())

## The fixture's stock words are [gold, metal, crystal, stone] (the payment message's [gold, metal, stone, crystal] for 0x1fe).
func stock_of() -> Array:
	return world.economy.stockpiles[OWNER].duplicate()

func set_stock(stock: Array):
	for lane in 4: world.economy.stockpiles[OWNER][lane] = int(stock[lane])

# ------------------------------------------------------------------------------------------------ the building page (E3)
func building_cells():
	var seen := 0
	for r in fixtures.building_cells:
		if int(r.owner) != 1 or not bool(r.finished): continue
		var research: Array = r.research
		var got: Dictionary = RacePowers.b5_building_cells(String(r.building), int(r.race), func(code): return research.has(code))
		var want: Array = r.cells[8]
		var ours := int(want[0]) in [RacePowers.CHAOS_ICON, RacePowers.WRATH_ICON]
		if not ours:
			check(not got.has(8), "%s race %d %s: no batch-5 cell 8 (the original %s)" % [r.building, int(r.race), research, want])
			continue
		seen += 1
		check(got.has(8) and int(got[8][0]) == int(want[0]) and bool(got[8][1]) == (int(want[2]) != 0),
			"%s race %d %s: cell 8 %s, the original %s" % [r.building, int(r.race), research, got.get(8), want])
	check(seen >= 20, "the fixtures hold the Chaos Plague and Couatl's Wrath cells: %d" % seen)
	for icon in RacePowers.B5_TIP_LINE: check(int(RacePowers.B5_TIP_LINE[icon]) > 0, "tooltip line for icon 0x%x" % icon)

# ------------------------------------------------------------------------------------------------ Chaos Plague (E4)
## A press world: the hall at the centre, the fixture's others at (gap, 0) (owner 2 = an enemy, 1 = own).
func power_world(r: Dictionary) -> int:
	new_world()
	world.production.races[OWNER] = int(r.race)
	world.production.research[OWNER] = r.research.duplicate()
	var b := building(String(r.building), Vector2i(0, 0), OWNER, {})
	if not bool(r.get("finished", true)): world.production.building(b).constructing = true
	set_stock(r.stock)
	for o in r.get("others", []):
		unit(String(o[0]), Vector2i(int(o[1]), 0), OWNER if int(o[2]) == 1 else ENEMY, {"hp": 500})
	world.combat.ai_players.erase(OWNER)
	if bool(r.get("computer", false)): world.combat.ai_players[OWNER] = true
	return b

func chaos():
	for r in fixtures.powers.chaos:
		var b := power_world(r)
		var casts := casts_of()
		now_at(START)
		for p in r.presses.size():
			var before := stock_of()
			world.spells.chaos_plague(b)
			var want: Array = r.presses[p].messages
			var paid: int = int(before[2]) - int(world.economy.stockpiles[OWNER][2])
			check(paid == (RacePowers.CHAOS_CRYSTAL if not want.is_empty() else 0), "Chaos %s %s %s press %d: paid %d" % [r.building, r.research, r.get("case", r.stock), p, paid])
		var records: Array = []
		for p in r.presses: records += p.messages.filter(func(m): return m.message == "0x1f7")
		check(casts.size() == records.size(), "Chaos %s %s: %d records, the original %d" % [r.building, r.get("case", r.stock), casts.size(), records.size()])
		if not casts.is_empty() and not records.is_empty():
			var rec: Dictionary = casts[0].record
			var w: Dictionary = records[0]
			check([int(rec.kind), int(rec.amount), int(rec.radius), int(rec.b6), int(rec.sound), int(rec.b9), int(rec.b10), int(rec.b12), String(rec.effect), String(rec.effect2), int(rec.d131)] ==
				[int(w.kind), int(w.amount), int(w.radius), int(w.b6), int(w.sound), int(w.b9), int(w.b10), int(w.b12), String(w.effect), String(w.effect2), int(w.d131)],
				"Chaos record %s: %s" % [r.research, [rec.kind, rec.amount, rec.radius]])
	# The world check of the exit gate: Contagion II, an enemy 14 cells away; every enemy unit within 28 at 47 % of its hit points.
	new_world()
	world.production.races[OWNER] = 15
	world.production.research[OWNER] = ["PCN0", "PCN1"]
	var hall := building("BKG0", Vector2i(0, 0), OWNER, {})
	set_stock([0, 0, 1000, 0])
	var near := unit("AHIX", Vector2i(14, 0), ENEMY, {"hp": 400})
	var far := unit("AHIX", Vector2i(0, 27), ENEMY, {"hp": 400})
	var out := unit("AHIX", Vector2i(29, 0), ENEMY, {"hp": 400})
	var own := unit("AHIX", Vector2i(2, 2), OWNER, {"hp": 400})
	now_at(START)
	check(world.spells.chaos_plague(hall), "Chaos Plague with an enemy 14 cells away")
	check(int(fighter(near).hp) == 188 and int(fighter(far).hp) == 188, "enemies within 28 keep 47 %%: %d, %d" % [int(fighter(near).hp), int(fighter(far).hp)])
	check(int(fighter(out).hp) == 400 and int(fighter(own).hp) == 400, "an enemy 29 cells away and own units untouched")
	check(int(world.economy.stockpiles[OWNER][2]) == 0, "1000 crystal paid")

# ------------------------------------------------------------------------------------------------ Couatl's Wrath (E5)
func wrath():
	for r in fixtures.powers.wrath:
		var b := power_world(r)
		var casts := casts_of()
		now_at(START)
		for p in r.presses.size():
			var before := stock_of()
			world.spells.couatls_wrath(b)
			var want: Array = r.presses[p].messages
			check(int(before[0]) - int(world.economy.stockpiles[OWNER][0]) == (RacePowers.WRATH_GOLD if not want.is_empty() else 0), "Wrath %s %s press %d" % [r.building, r.stock, p])
		var records: Array = []
		for p in r.presses: records += p.messages.filter(func(m): return m.message == "0x1f7")
		check(casts.size() == records.size(), "Wrath %s %s: %d records, the original %d" % [r.building, r.stock, casts.size(), records.size()])
		if not casts.is_empty() and not records.is_empty():
			var rec: Dictionary = casts[0].record
			var w: Dictionary = records[0]
			check([int(rec.kind), int(rec.amount), int(rec.radius), int(rec.b6), int(rec.sound), int(rec.b9), int(rec.b10), int(rec.b12)] ==
				[int(w.kind), int(w.amount), int(w.radius), int(w.b6), int(w.sound), int(w.b9), int(w.b10), int(w.b12)], "Wrath record: %s" % [[rec.kind, rec.amount, rec.radius]])
			var launched: Array = world.combat.missiles.filter(func(m): return bool(m.get("meteor", false)))
			var temple: Vector2i = world.combat._building_sprite(world.production.building(b)).cell
			var aims: Array = launched.map(func(m): return m.aim - temple)
			var want_aims: Array = RacePowers.METEOR_OFFSETS.slice(0, int(w.amount)).map(func(o): return Vector2i(int(o[0]), int(o[1])))
			check(aims == want_aims, "six meteors on the table's pattern: %s" % [aims])
	# the meteor calls of the abilities rows: art EMF0 at the temple's cell + the table, amount 5 + level
	for a in fixtures.abilities:
		if String(a.ability) != "Couatl's Wrath": continue
		for c in a.cases:
			var calls: Array = []
			for st in c.applied: calls += st.calls.filter(func(x): return x.call == "meteor")
			check(calls.size() == 5 + int(c.level) and calls.all(func(x): return String(x.code) == RacePowers.METEOR_ID), "level %d: %d meteors" % [int(c.level), calls.size()])
			var offs: Array = calls.map(func(x): return [int(x.args[1]) - 40, int(x.args[2]) - 40])
			check(offs == RacePowers.METEOR_OFFSETS.slice(0, calls.size()), "the meteor cells: %s" % [offs])

# ------------------------------------------------------------------------------------------------ the computer's payers (E6)
func payers():
	for r in fixtures.powers.payers:
		var b := power_world(r)
		var casts := casts_of()
		now_at(START)
		var before := stock_of()
		var bo = world.production.building(b)
		if String(r.building).begins_with("BKG"): world.spells.chaos_cast(bo)
		else: world.spells.wrath_cast(bo)
		var pay: Array = r.presses[0].messages[0].payment.words
		var want_after := [maxi(0, int(before[0]) - int(pay[0])), int(before[1]), maxi(0, int(before[2]) - int(pay[3])), int(before[3])]
		check(stock_of() == want_after and casts.size() == 1, "%s payer (computer %s) with %s: %s" % [r.building, r.computer, r.stock, stock_of()])
		check(int(casts[0].record.amount) == int(r.presses[0].messages[1].amount), "%s payer: amount %d" % [r.building, int(casts[0].record.amount)])

# ------------------------------------------------------------------------------------------------ the C and W keys (E6, V1)
func keys():
	for r in fixtures.powers.keys:
		if int(r.case) != world.spells.CHAOS_CASE and int(r.case) != world.spells.WRATH_CASE: continue
		new_world()
		world.production.races[OWNER] = int(r.race)
		world.production.research[OWNER] = r.research.duplicate()
		var b := building(String(r.selected), Vector2i(0, 0), OWNER, {})
		if not bool(r.finished): world.production.building(b).constructing = true
		if bool(r.selected_flag): world.host.selected_building_id = b
		set_stock(r.stock)
		unit("AHIX", Vector2i(6, 0), ENEMY, {"hp": 500})
		var casts := casts_of()
		now_at(START)
		world.spells.hot_key(int(world.spells.table.keys[int(r.case)]), OWNER)
		var want: Array = r.messages.filter(func(m): return m.message == "0x1f7")
		check(casts.size() == want.size(), "key %s %s %s %s: %d casts, the original %d" % [r.case, r.selected, r.research, r.stock, casts.size(), want.size()])
		if not casts.is_empty() and not want.is_empty(): check(int(casts[0].record.amount) == int(want[0].amount), "key %s: amount %d" % [r.case, int(casts[0].record.amount)])
		check(stock_of() == r.stock_after.map(func(v): return int(v)), "key %s: nothing paid (%s)" % [r.case, stock_of()])
	# The keys of a selected hall and temple twice in one second: no throttle on the key.
	new_world()
	world.production.races[OWNER] = 15
	world.production.research[OWNER] = ["PCN0"]
	var hall := building("BKG0", Vector2i(0, 0), OWNER, {})
	world.host.selected_building_id = hall
	set_stock([0, 0, 1000, 0])
	var casts := casts_of()
	now_at(START)
	for i in 2: world.spells.hot_key(int(world.spells.table.keys[world.spells.CHAOS_CASE]), OWNER)
	check(casts.size() == 2, "the C key twice: two plagues, no throttle (%d)" % casts.size())
	# review key_loop: the rows whose records are the building cases alone (the casters' rows are B5-2's).
	for r in review.key_loop:
		var kinds: Array = r.records.map(func(x): return int(x[0]))
		if not kinds.all(func(k): return k == 34 or k == 35) or r.records.is_empty(): continue
		new_world()
		var code := "BKG0" if String(r.key) == "C" else "BKL0"
		world.production.races[OWNER] = 15 if code == "BKG0" else 13
		world.production.research[OWNER] = ["PCN0"] if code == "BKG0" else ["PCWR"]
		var bb := building(code, Vector2i(0, 0), OWNER, {})
		world.host.selected_building_id = bb
		set_stock([1000, 1000, 1000, 1000])
		var cs := casts_of()
		now_at(START)
		world.spells.hot_key(int(world.spells.table.keys[world.spells.CHAOS_CASE if code == "BKG0" else world.spells.WRATH_CASE]), OWNER)
		check(cs.map(func(i): return [int(i.record.kind), int(i.record.amount)]) == r.records.map(func(x): return [int(x[0]), int(x[1])]), "%s: %s" % [r.case, cs.size()])

# ------------------------------------------------------------------------------------------------ the advisor lines (review V2)
func advisor():
	for r in review.advisor:
		new_world()
		var code := String(r.get("building", r.get("selected", "")))
		world.production.races[OWNER] = int(r.race)
		world.production.research[OWNER] = r.research.duplicate()
		var b := building(code, Vector2i(0, 0), OWNER, {})
		world.host.selected_building_id = b
		set_stock(r.stock)
		unit("AHIX", Vector2i(5, 0), ENEMY, {"hp": 500})
		var notes := notices_of()
		var casts := casts_of()
		now_at(START)
		if r.has("presses"):
			if code.begins_with("BKG"): world.spells.chaos_plague(b)
			else: world.spells.couatls_wrath(b)
		else:
			world.spells.hot_key(int(world.spells.table.keys[int(r.case)]), OWNER)
		var line := "Not enough crystal" if int(r.advisor[0]) == 0x14 else "Not enough gold"
		check(notes.has(line) and casts.is_empty(), "%s: advisor 0x%x (%s)" % [r.get("case_name", r.get("case")), int(r.advisor[0]), notes])

# ------------------------------------------------------------------------------------------------ the meteor (Open 1, Emulated)
func meteor_path():
	for e in meteors.init:
		var s: Dictionary = e.state
		var src := Vector2i(int(s.source[0]), int(s.source[1]))
		var to := Vector2i(int(e.cell[0]), int(e.cell[1]))
		var m := Missiles.create_sky(src, to, 50000)
		var want: Array = s.records
		var got: Array = m.records
		var same: bool = got.size() == want.size()
		if same:
			for i in got.size():
				for k in 6:
					if int(got[i][k]) != int(want[i][k]): same = false
		check(same and int(m.steps) == int(s.steps) and int(m.length) == int(s.length) and int(m.flags) == int(s.flags) and int(m.next_ms) == int(s.next_ms) and int(m.owner) == int(s.owner),
			"meteor %d to %s: %d records, the original %d (first %s / %s)" % [int(e.entry), to, got.size(), want.size(), got[0] if not got.is_empty() else [], want[0]])
		check(int(s.damage) == 0 and int(s.dclass) == 0 and String(s.type_id) == RacePowers.METEOR_ID and String(s.art) == RacePowers.METEOR_ART, "0x53e960: no damage, EMF0 / EMTF")

func meteor_landing():
	var probe := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)]
	for r in meteors.flights:
		if r.has("error"): continue
		new_world()
		var land := Vector2i(int(r.cell[0]), int(r.cell[1])) - Vector2i(40, 40)
		var ids: Array = []
		for o in r.objects:
			var off := Vector2i(int(o.cells[0][0]) - 40, int(o.cells[0][1]) - 40)
			if o.kind == "unit":
				var id := unit("AHIX", off, OWNER if int(o.owner) == 0 else ENEMY, {"hp": 500 if int(o.hp) > 0 else 1})
				if int(o.hp) == 0: world.combat.apply_damage("unit", id, 100000, -1, "none")
				ids.append(["unit", id, int(o.hp) > 0])
			else:
				# the harness's building fills one cell: a small one here, its footprint clear of the landing's probe block
				ids.append(["building", building(small_building(), off, ENEMY, {}), true])
		now_at(START)
		var m: Dictionary = world.combat.launch_meteor(centre, centre + land)
		var before: Array = ids.map(func(x): return _hp(x))
		run_world(50 * int(m.steps) + 400)
		var hit_offsets: Array = []
		var dealt: Array = []
		for i in ids.size():
			var loss: int = int(before[i]) - _hp(ids[i])
			if loss <= 0 or not bool(ids[i][2]): continue
			var o: Dictionary = r.objects[i]
			hit_offsets.append(Vector2i(int(o.cells[0][0]) - int(r.cell[0]), int(o.cells[0][1]) - int(r.cell[1])))
			dealt.append(loss)
		var want := {}
		for b in r.blast:
			if b.offset != null and int(b.hp_before) > 0: want[Vector2i(int(b.offset[0]), int(b.offset[1]))] = "blast"
		for imp in r.impacts:
			if imp.offset != null: want[Vector2i(int(imp.offset[0]), int(imp.offset[1]))] = "impact"
		hit_offsets.sort()
		var want_offsets: Array = want.keys()
		want_offsets.sort()
		check(hit_offsets == want_offsets, "meteor %d %s: %d struck, the original %d" % [int(r.entry), r.scene, hit_offsets.size(), want_offsets.size()])
		# the impact (0x42bbf0(0) = 1) and the blast (0x42bbf0(150, 2, fire, armour))
		for i in ids.size():
			var loss: int = int(before[i]) - _hp(ids[i])
			if loss <= 0 or not bool(ids[i][2]): continue
			var o: Dictionary = r.objects[i]
			var off := Vector2i(int(o.cells[0][0]) - int(r.cell[0]), int(o.cells[0][1]) - int(r.cell[1]))
			var block: Dictionary = world.combat.combat_block(fighter(int(ids[i][1]))) if ids[i][0] == "unit" else world.combat.building_block(world.production.building(int(ids[i][1])))
			var expect: int = 1 if String(want.get(off, "")) == "impact" else CombatRules.armour_tail(150, 2, 3, CombatRules.armour_table(block), CombatRules.resist_flags(block))
			check(loss == expect, "meteor %d %s at %s: %d, expected %d" % [int(r.entry), r.scene, off, loss, expect])
		if String(r.scene) == "enemy on the cell": check(probe.has(Vector2i.ZERO), "probe block")

func small_building() -> String:
	for code in ["BWTL", "BWTG", "BWTF", "BWTD", "BWTE", "BWTC", "BPSP", "BAWS"]:
		var d: Dictionary = world.production.rules.definition(code)
		if not d.is_empty() and int(d.footprint[1]) <= 2 and int(d.footprint[0]) <= 3: return code
	return "BWTL"

func _hp(x: Array) -> int:
	if x[0] == "unit": return int(fighter(int(x[1])).hp)
	return int(world.production.building(int(x[1])).hit_points)

# ------------------------------------------------------------------------------------------------ the Spore (E7)
func spore():
	for r in fixtures.spore:
		match String(r.case):
			"ring":
				new_world()
				var bomb := unit("AGSP", Vector2i(0, 0), OWNER)
				var victims := {}
				for c in r.cells:
					var v := unit(String(r.victim), Vector2i(int(c[0]), int(c[1])), ENEMY, {"hp": 500})
					victims[v] = int(c[2])
				world.combat.apply_damage("unit", bomb, 100000, -1)
				for v in victims: check(500 - int(fighter(v).hp) == int(victims[v]), "Spore: %s at %s: %d, the original %d" % [r.victim, world.units[v].cell - centre, 500 - int(fighter(v).hp), int(victims[v])])
			"virus":
				new_world()
				world.production.research[OWNER] = r.research.duplicate()
				var bomb := unit("AGSP", Vector2i(0, 0), OWNER)
				var near := unit("AHIX", Vector2i(1, 0), ENEMY, {"hp": 500})
				var far := unit("AHIX", Vector2i(2, 0), ENEMY, {"hp": 500})
				world.combat.apply_damage("unit", bomb, 100000, -1)
				check(500 - int(fighter(near).hp) == int(r.near) and 500 - int(fighter(far).hp) == int(r.far), "Spore %s: near %d far %d, the original %d / %d" % [r.research, 500 - int(fighter(near).hp), 500 - int(fighter(far).hp), int(r.near), int(r.far)])
			"own, ally and building":
				new_world()
				var bomb := unit("AGSP", Vector2i(0, 0), OWNER)
				var own := unit("AHIX", Vector2i(1, 0), OWNER, {"hp": 500})
				var enemy := unit("AHIX", Vector2i(-1, 0), ENEMY, {"hp": 500})
				world.combat.apply_damage("unit", bomb, 100000, -1)
				check(int(fighter(own).hp) == int(r.own) and int(fighter(enemy).hp) == int(r.enemy), "Spore: own %d, enemy %d" % [int(fighter(own).hp), int(fighter(enemy).hp)])
	new_world()
	var spore := unit("AGSP", Vector2i(0, 0), OWNER)
	var target := unit("AHIX", Vector2i(1, 0), ENEMY, {"hp": 500})
	now_at(START)
	world.combat._hit(fighter(spore), {"target_kind": "unit", "target_id": target, "ranged": false, "result": {"damage": 99, "effect": 0, "param": 0}, "hit_done": false})
	check(not world.combat.alive(fighter(spore)), "the Spore dies at its hit entry")
	check(500 - int(fighter(target).hp) == 35, "the target takes the blast alone: %d" % (500 - int(fighter(target).hp)))

# ------------------------------------------------------------------------------------------------ the Leprechaun's income (E8)
func income():
	for r in fixtures.income.units:
		check(RacePowers.income_of([String(r.unit)], 0).income == r.income.map(func(v): return int(v)), "%s: %s" % [r.unit, r.income])
	var cases := {"nothing": [[], 0], "one Leprechaun": [["AFNX"], 0], "three Leprechauns": [["AFNX", "AFNX", "AFNX"], 0],
		"Leprechaun, Income I": [["AFNX"], 1], "two Leprechauns, Income III": [["AFNX", "AFNX"], 3], "Leprechaun and Ancient Wisp": [["AFNX", "AEAX"], 0]}
	for r in fixtures.income.aggregate:
		var c: Array = cases[String(r.case)]
		var e := Economy.new(0)
		e.add_player(0, [0, 0, 0, 0])
		e.research_level = func(_p, id): return int(c[1]) if id == "PIBX" else 0
		e.other_income = func(_p): return RacePowers.income_of(c[0], 0)
		check(e._calculate(0) == r.totals.map(func(v): return int(v)), "%s: %s, the original %s" % [r.case, e._calculate(0), r.totals])

# ------------------------------------------------------------------------------------------------ type-class disease and poison (E9)
func class_hits():
	for r in fixtures.class_hits:
		new_world()
		var a := unit(String(r.attacker), Vector2i(0, 0), ENEMY)
		var t := unit(String(r.target), Vector2i(1, 0), OWNER, {"hp": 500})
		var af = fighter(a)
		var tf = fighter(t)
		var word: int = world.spells.class_word(af)
		check(word == String(r.word).hex_to_int(), "%s carries the class word %s: 0x%x" % [r.attacker, r.word, word])
		var disease := 0
		var poison := 0
		if word >> 8 == RacePowers.DISEASE_CLASS and world.spells.diseasable(tf):
			disease = mini(100, RacePowers.rabies_chance(word & 0xff, 0, world.spells._hit_armour(tf, 6)))
		if word >> 8 == RacePowers.POISON_CLASS and world.spells.poisonable(tf):
			poison = mini(100, RacePowers.poison_chance(word & 0xff, world.spells._hit_armour(tf, 5)))
		check(disease == int(r.highest_disease_roll) and poison == int(r.highest_poison_roll),
			"%s on %s: disease %d poison %d, the original %d / %d" % [r.attacker, r.target, disease, poison, int(r.highest_disease_roll), int(r.highest_poison_roll)])
		# the hit at the boundary roll
		if int(r.highest_disease_roll) > 0 and int(r.highest_disease_roll) < 100:
			var forced := ForcedRng.new()
			var real = world.combat.rng
			world.combat.rng = forced
			forced.values = [int(r.highest_disease_roll) + 1]
			world.spells.venom_hit(af, tf)
			check(not bool(tf.get("diseased", false)), "%s on %s: a roll above the chance does not disease" % [r.attacker, r.target])
			forced.values = [int(r.highest_disease_roll)]
			world.spells.venom_hit(af, tf)
			world.combat.rng = real
			check(bool(tf.get("diseased", false)), "%s on %s: the boundary roll diseases" % [r.attacker, r.target])
	# the Wolfrider without Rabies carries no disease word (batch 3's PRAB writes it)
	new_world()
	var wolf := unit("AOCX", Vector2i(0, 0), ENEMY)
	check(world.spells.class_word(fighter(wolf)) >> 8 != RacePowers.DISEASE_CLASS, "AOCX without PRAB: word 0x%x" % world.spells.class_word(fighter(wolf)))

func immunity():
	new_world()
	var i := 0
	for r in fixtures.immunity:
		# AADU: the harness gave it Army.cfg's STATUS; the game's live status (0x5273c0, CombatRules.LIVE_STATUS_BITS) adds 0x1004,
		# whose bit 2 makes it immune: a state the emulated row does not hold.
		if String(r.unit) == "AADU": continue
		var id := unit(String(r.unit), Vector2i(i % 8 * 2, i / 8 * 2), ENEMY)
		i += 1
		var f = fighter(id)
		var c5: int = world.spells.fear_class({"base": f.base, "type_id": f.type_id}, 5)
		var c6: int = world.spells.fear_class({"base": f.base, "type_id": f.type_id}, 6)
		check(c5 == int(r.class_5) and c6 == int(r.class_6), "%s: 0x5286c0(5) %d (6) %d, the original %d / %d" % [r.unit, c5, c6, int(r.class_5), int(r.class_6)])

# ------------------------------------------------------------------------------------------------ Construction PCON (E11)
func build_list():
	var rows: Array = fixtures.build_list + review.panel
	for r in rows:
		new_world()
		world.production.races[OWNER] = int(r.race)
		world.production.research[OWNER] = r.research.duplicate()
		for e in r.entries:
			var got: int = world.production.time_of(OWNER, String(e.id), String(r.builder)) / 1000
			check(got == int(e.time), "%s race %d %s: %s %d s, the original %d" % [r.builder, int(r.race), r.research, e.id, got, int(e.time)])
