extends "res://tests/test_casters.gd"
## B5-2 (BATCH5_RESEARCH.md section 3): the batch-5 casters' ability cases against tests/batch5_fixtures.json `abilities`,
## `unit_cells`, `keys`, `powers.keys` (the unit cases) and `unit_mana` (tools/emulate_batch5.py) and tests/batch5_review_fixtures.json
## `key_loop` (0x427f70: the shared keys in key order). The buttons in the real scene: the three batch-5 world checks.

const RacePowers = preload("res://simulation/race_powers.gd")
var batch5: Dictionary = {}
var review5: Dictionary = {}

func run():
	batch5 = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch5_fixtures.json"))
	review5 = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch5_review_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	if centre.x >= 0:
		table_rows_b5()
		for row in batch5.abilities:
			records_b5(row)
		unit_cells_b5()
		mana_rows_b5()
		keys_b5()
		key_loop_b5()
	clear_world()
	if failures > 0:
		printerr("Batch 5 caster checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Batch 5 caster checks passed: %d" % checks)
	quit(0)

func table_rows_b5():
	var t := Spells.load_table()
	var keys: Dictionary = batch5["keys"]
	for case_key in keys:
		var row: Dictionary = t.cases.get(str(int(case_key)), {})
		check(not row.is_empty() and String(row.key) == char(int(keys[case_key])), "case %s: key %s, the original %s" % [case_key, row.get("key"), char(int(keys[case_key]))])
	for a in batch5.abilities:
		var row: Dictionary = t.cases.get(str(int(a.case)), {})
		if int(a.case) == 0xd:
			# B4-2 (R5): case 0xd's ALBX comes through the selection loop with PBLE (spells._invisibility_selection), not the row.
			check(int(row.get("mana", -1)) == int(a.unit_mana), "Invisibility: case 13, mana %d" % int(a.unit_mana))
		elif String(a.caster).begins_with("B"):
			check(Array(row.get("casters", [])).has(String(a.caster)) and int(row.get("mana", -1)) == 0, "%s: case %d at %s, no mana" % [a.ability, int(a.case), a.caster])
		else:
			check(int(row.get("mana", -1)) == int(a.unit_mana) and Array(row.get("casters", [])).has(String(a.caster)), "%s: case %d, mana %d, caster %s" % [a.ability, int(a.case), int(a.unit_mana), a.caster])
		check(Spells.CASE_BUILDERS.has(int(a.case)) or Spells.HERO_CASE_BUILDERS.has(int(a.case)), "%s has a builder" % a.ability)
	check(not Spells.SUMMON_CASES.is_empty() and Spells.SUMMON_CASES.has(0x20), "Eye of Oros summons at the caster's cell")

## Every (ability, caster) record of the fixture's scenes at each level, built as 0x426350 builds it.
func records_b5(row: Dictionary):
	for c in row.cases:
		if c.get("error") != null: continue
		var level := int(c.level)
		new_world()
		var building := String(row.caster).begins_with("B")
		var caster: Dictionary
		if building:
			world.production.research[1] = ["PCN0"] if String(row.caster) == "BKG0" else ["PCWR"]
			caster = {"kind": "building", "id": building_at(String(row.caster), Vector2i.ZERO, 1, {})}
		else:
			caster = caster_of(unit(String(row.caster), Vector2i.ZERO, 1, {"mana": [200, 200]}))
		if c.scenario == "command full": set_command(1, used(1))
		elif c.scenario == "command one left": set_command(1, used(1) + 1)
		var got: Dictionary = world.spells.build_case(int(row.case), caster, level, {"x": centre.x, "y": centre.y, "id": -1})
		var want := first_record(c)
		var label := "%s by %s level %d (%s)" % [row.ability, row.caster, level, c.scenario]
		if want.is_empty():
			check(got.is_empty(), label + ": no record")
			continue
		check(not got.is_empty(), label + ": a record")
		if got.is_empty(): continue
		var diff: Array = []
		for k in RECORD_FIELDS:
			if int(got.get(k, 0)) != int(want[k]): diff.append("%s %s != %s" % [k, got.get(k, 0), want[k]])
		if text(got.effect) != text(want.effect): diff.append("effect %s != %s" % [got.effect, text(want.effect)])
		if text(got.effect2) != text(want.effect2): diff.append("effect2 %s != %s" % [got.effect2, text(want.effect2)])
		if text(got.get("summon", "")) != text(want.summon) and text(want.summon) != "" and int(want.kind) in [6, 0x10]: diff.append("summon %s != %s" % [got.summon, text(want.summon)])
		check(diff.is_empty(), "%s: %s" % [label, diff])

func building_at(code: String, offset: Vector2i, owner: int, extra: Dictionary) -> int:
	return building(code, offset, owner, extra)

func unit_cells_b5():
	for r in batch5.unit_cells:
		if int(r.count) != 1 or r.mana == null: continue
		new_world()
		world.production.races[1] = int(r.race)
		world.production.research[1] = r.research.duplicate()
		var code := String(r.unit)
		var id := unit(code, Vector2i.ZERO, 1)
		with_mana(id, int(r.mana[0]), int(r.mana[1]))
		var rows: Array = world.spells.unit_row_for(code, 1)
		var want: Array = r.cells.filter(func(cell): return Spells.UNIT_ROW.any(func(u): return int(u[1]) == int(cell[0])))
		var got: Array = rows.map(func(u): return [int(u[1]), 1 if world.spells.unit_row_enabled(u, [world.units[id]]) else 0])
		var wanted: Array = want.map(func(cell): return [int(cell[0]), int(cell[2])])
		check(got == wanted, "%s race %d %s mana %s: %s, the original %s" % [code, int(r.race), r.research, r.mana, got, wanted])

func mana_rows_b5():
	for r in batch5.unit_mana:
		if int(r.rank) != 0 or r.get("error") != null: continue
		new_world()
		if int(r.computer): world.combat.ai_players[1] = true
		world.production.research[1] = r.research.duplicate()
		var id := unit(String(r.unit), Vector2i.ZERO, 1)
		var f = world.combat.fighters[id]
		check(int(f.get("mana", 0)) == int(r.mana) and int(f.get("max_mana", 0)) == int(r.max_mana), "%s %s computer %d: mana %s / %s (original %s / %s)" % [r.unit, r.research, int(r.computer), f.get("mana", 0), f.get("max_mana", 0), r.mana, r.max_mana])

## The unit cases of powers.keys: the caster selected, its mana, the command for Eye of Oros (pays, then the builder's one-place check).
func keys_b5():
	for r in batch5.powers["keys"]:
		if String(r.selected).begins_with("B"): continue                  # the building keys: tests/test_batch5_powers.gd
		new_world()
		world.production.races[1] = int(r.race)
		world.production.research[1] = r.research.duplicate()
		var id := unit(String(r.selected), Vector2i.ZERO, 1)
		with_mana(id, int(r.mana_before[0]), int(r.mana_before[1]))
		world.host.selection = [world.units[id]]
		set_command(1, used(1) + int(r.command[1]) - int(r.command[0]))
		var done: Array = []
		world.spells.cast_done.connect(func(info): done.append(info))
		var returned: bool = world.spells.ability(int(r.case), 1)
		var want: Array = r.messages.filter(func(m): return m.message == "0x1f7")
		var f = world.combat.fighters[id]
		var label := "case 0x%x %s %s mana %s command %s" % [int(r.case), r.selected, r.research, r.mana_before, r.command]
		check(int(f.get("mana", 0)) == int(r.mana_after[0]), "%s: mana %d, the original %d" % [label, int(f.get("mana", 0)), int(r.mana_after[0])])
		check(done.size() == want.size(), "%s: %d records, the original %d" % [label, done.size(), want.size()])
		if int(r.case) != 0xd: check(returned == (int(r.result) == 1), "%s: returns %s" % [label, r.result])
		if not done.is_empty() and not want.is_empty():
			check(int(done[0].record.kind) == int(want[0].kind) and int(done[0].record.amount) == int(want[0].amount), "%s: kind %d amount %d" % [label, int(done[0].record.kind), int(done[0].record.amount)])
			if int(r.case) == 0x20:
				var made: int = done[0].result.summoned.size() if done[0].result.has("summoned") else 0
				var room: int = int(r.command[1]) - int(r.command[0])
				check(made == (int(want[0].amount) if room > 0 else 0), "%s: %d Eyes (room %d)" % [label, made, room])

## review key_loop: 0x427f70 over the shared keys (C: Chaos Plague then Cauterize; P: Plague Cloud first).
func key_loop_b5():
	var setups := {
		"C, hall selected, Snakepriest on the map": [["BKG0", true], ["ALMX", false]],
		"C, hall selected, nothing else": [["BKG0", true]],
		"C, hall and Snakepriest selected": [["BKG0", true], ["ALMX", true]],
		"C, poor hall, Snakepriest on the map": [["BKG0", true], ["ALMX", false]],
		"W, temple selected": [["BKL0", true]],
		"P, Plague Priest and Snakepriest": [["AGGX", true], ["ALMX", true]]}
	for r in review5.key_loop:
		if not setups.has(String(r.case)): continue
		new_world()
		world.production.research[1] = ["PCN0", "PCWR"]
		var selection: Array = []
		var units: Array = []
		var e: Array = setups[String(r.case)]
		for i in e.size():
			var code := String(e[i][0])
			if code.begins_with("B"):
				var b := building(code, Vector2i(-8, 0), 1, {})
				if bool(e[i][1]): world.host.selected_building_id = b
			else:
				# a hurt friend for Cauterize, the Snakepriest 3 cells off; unselected ones stand outside any view rectangle here
				var id := unit(code, Vector2i(3 * i, 0), 1)
				with_mana(id, 200, 200)
				units.append(id)
				if bool(e[i][1]): selection.append(world.units[id])
		if units.is_empty() or String(r.case).begins_with("C"):
			var hurt := unit("AHIX", Vector2i(2, 2), 1, {"hp": 500})
			world.combat.fighters[hurt].hp = 100
		unit("AHIX", Vector2i(5, -3), 0, {"hp": 500})
		world.host.selection = selection
		world.economy.stockpiles[1] = [1000, 1000, 1000 if not String(r.case).contains("poor") else 999, 1000]
		var done: Array = []
		world.spells.cast_done.connect(func(info): done.append(info))
		var key: String = String(r.key)
		var unselected_out: bool = String(r.case).contains("on the map")
		if unselected_out:
			for id in units:
				if not selection.has(world.units[id]): world.combat.fighters[id]["mana"] = 0   # the view scan finds no caster with mana (no view here)
		world.spells.hot_key(key.unicode_at(0), 1)
		var got: Array = done.map(func(i): return [int(i.record.kind), int(i.record.amount)])
		var want: Array = r.records.map(func(x): return [int(x[0]), int(x[1])])
		check(got == want, "%s: %s, the original %s" % [r.case, got, want])
