extends "res://tests/test_casters.gd"
## B4-2 (BATCH4_RESEARCH.md section 3): the batch-4 casters' ability cases against tests/batch4_fixtures.json `abilities`,
## `unit_cells`, `keys` and `unit_mana` (tools/emulate_batch4.py) and tests/batch4_review_fixtures.json `keys` (0x426350 itself for
## cases 0xc, 0xd, 0x11, 0x28, 0x2c: the casters, the payments, the selection-only pass, Invisibility's loop, the Queen's check).
## The buttons in the real scene: the three batch-4 world checks.

var batch4: Dictionary = {}
var review4: Dictionary = {}

func run():
	batch4 = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch4_fixtures.json"))
	review4 = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch4_review_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	if centre.x >= 0:
		table_rows_b4()
		for row in batch4.abilities:
			if String(row.caster).begins_with("B"): continue        # Elcor's Balm / Holy Word: tests/test_batch4_powers.gd
			records_b4(row)
			command_rows(row)
		unit_cells_b4()
		mana_rows_b4()
		keys_b4()
	clear_world()
	if failures > 0:
		printerr("Batch 4 caster checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Batch 4 caster checks passed: %d" % checks)
	quit(0)

func table_rows_b4():
	var t := Spells.load_table()
	var keys: Dictionary = batch4["keys"]
	for case_key in keys:
		var row: Dictionary = t.cases.get(str(int(case_key)), {})
		if int(case_key) in [0x13, 0x14]:
			check(int(t.keys[int(case_key)]) == int(keys[case_key]), "case %s: key %s" % [case_key, char(int(keys[case_key]))])
			continue
		check(not row.is_empty() and String(row.key) == char(int(keys[case_key])), "case %s: key %s, the original %s" % [case_key, row.get("key"), char(int(keys[case_key]))])
	for a in batch4.abilities:
		if String(a.caster).begins_with("B"): continue
		var row: Dictionary = t.cases.get(str(int(a.case)), {})
		check(int(row.get("mana", -1)) == int(a.unit_mana) and Array(row.get("casters", [])).has(String(a.caster)), "%s: case %d, mana %d, caster %s" % [a.ability, int(a.case), int(a.unit_mana), a.caster])
		check(Spells.CASE_BUILDERS.has(int(a.case)) or Spells.HERO_CASE_BUILDERS.has(int(a.case)), "%s has a builder" % a.ability)
	check(t.cases["40"].command_check == "AKLX" and t.cases["6"].command_check == "AUBX", "Queen Spider and Raise Zombie check before paying")
	# E13: Freeze's cell asks 45, its key 20
	check(Spells.unit_row("AEOX").any(func(r): return int(r[0]) == 0x2c and int(r[2]) == 45) and int(t.cases["44"].mana) == 20, "Freeze: cell 45, key 20")

## Every (ability, caster) record of the empty scene at levels 1..4 (the first row of each level: the later rank rows below).
func records_b4(row: Dictionary):
	var seen := {}
	for c in row.cases:
		if c.scenario != "empty": continue
		var level := int(c.level)
		var rank := 0
		if seen.has(level): rank = 5                            # the Multi-Target rank row (50 + 2 x rank: 60 / 45)
		seen[level] = true
		new_world()
		var caster := unit(String(row.caster), Vector2i.ZERO, 1, {"mana": [200, 200], "rank": rank})
		var got: Dictionary = world.spells.build_case(int(row.case), caster_of(caster), level, {"x": centre.x, "y": centre.y, "id": -1})
		var want := first_record(c)
		var label := "%s by %s level %d rank %d" % [row.ability, row.caster, level, rank]
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

## The summoners at the command limit: no record from the builder (Raise Zombie, Queen Spider).
func command_rows(row: Dictionary):
	for c in row.cases:
		if c.scenario != "command full": continue
		new_world()
		var caster := unit(String(row.caster), Vector2i.ZERO, 1, {"mana": [200, 200]})
		set_command(1, used(1))
		var got: Dictionary = world.spells.build_case(int(row.case), caster_of(caster), int(c.level), {"x": centre.x, "y": centre.y, "id": -1})
		check(got.is_empty() == first_record(c).is_empty(), "%s at the limit level %d: record %s" % [row.ability, int(c.level), not got.is_empty()])

func unit_cells_b4():
	for r in batch4.unit_cells:
		if r.units.size() != 1 or r.mana == null: continue
		new_world()
		world.production.races[1] = int(r.race)
		world.production.research[1] = r.research.duplicate()
		var code := String(r.units[0])
		var id := unit(code, Vector2i.ZERO, 1)
		with_mana(id, int(r.mana[0]), int(r.mana[1]))
		var rows: Array = world.spells.unit_row_for(code, 1)
		var want: Array = r.cells.filter(func(cell): return Spells.UNIT_ROW.any(func(u): return int(u[1]) == int(cell[0])))
		var got: Array = rows.map(func(u): return [int(u[1]), 1 if world.spells.unit_row_enabled(u, [world.units[id]]) else 0])
		var wanted: Array = want.map(func(cell): return [int(cell[0]), int(cell[2])])
		check(got == wanted, "%s race %d %s mana %s: %s, the original %s" % [code, int(r.race), r.research, r.mana, got, wanted])

func mana_rows_b4():
	for r in batch4.unit_mana:
		if int(r.rank) != 0 or r.get("error") != null: continue
		new_world()
		if int(r.computer): world.combat.ai_players[1] = true
		world.production.research[1] = r.research.duplicate()
		var id := unit(String(r.unit), Vector2i.ZERO, 1)
		var f = world.combat.fighters[id]
		check(int(f.get("mana", 0)) == int(r.mana) and int(f.get("max_mana", 0)) == int(r.max_mana), "%s %s computer %d: mana %s / %s (original %s / %s)" % [r.unit, r.research, int(r.computer), f.get("mana", 0), f.get("max_mana", 0), r.mana, r.max_mana])

## The review's 0x426350 rows. The stand-alone host has no view rectangle (find_caster then scans the whole map), so a unit out of
## the rows' view (columns 30..49, rows 30..44) and not selected is left out: it never casts in the original rows.
func keys_b4():
	var view := Rect2i(30, 30, 20, 15)
	for r in review4.keys:
		if not int(r.case) in [0xc, 0xd, 0x11, 0x28, 0x2c]: continue
		new_world()
		world.production.research[1] = r.research.duplicate()
		var ids := {}
		var order: Array = []
		var selection: Array = []
		for e in r.units:
			var cell := Vector2i(int(e[1][0]), int(e[1][1]))
			if not view.has_point(cell) and not bool(e[2]): continue
			var id := unit(String(e[0]), cell - Vector2i(40, 32), 1)
			if e[3] == null:
				world.combat.fighters[id].erase("mana")
				world.combat.fighters[id].erase("max_mana")
			else: with_mana(id, int(e[3]), 200)
			if bool(e[2]): selection.append(world.units[id])
			ids["%s@%d,%d" % [e[0], cell.x, cell.y]] = id
			order.append(id)
		world.host.selection = selection
		set_command(1, used(1) + int(r.command[1]) - int(r.command[0]))
		var done: Array = []
		world.spells.cast_done.connect(func(info): done.append(info))
		var p: Dictionary = r.presses[0]
		var returned: bool = world.spells.ability(int(r.case), 1)
		check(returned == (int(p.returned) == 1), "%s: returns %d" % [r.name, int(p.returned)])
		var want: Array = p.casts.map(func(c): return int(ids.get(String(c.caster), -2)))
		var got: Array = done.map(func(i): return int(i.caster.id))
		check(got == want, "%s: casters %s, the original %s" % [r.name, got, p.casts])
		var kept: Array = []
		for i in r.units.size():
			var e: Array = r.units[i]
			var cell := Vector2i(int(e[1][0]), int(e[1][1]))
			if not view.has_point(cell) and not bool(e[2]): continue
			if p.mana[i] == null: continue
			var key := "%s@%d,%d" % [e[0], cell.x, cell.y]
			check(int(world.combat.fighters[ids[key]].get("mana", 0)) == int(p.mana[i]), "%s: %s mana %d, the original %d" % [r.name, key, int(world.combat.fighters[ids[key]].get("mana", 0)), int(p.mana[i])])
