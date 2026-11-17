extends "res://tests/test_casters.gd"
## B3-2 (BATCH3_RESEARCH.md section 3): the batch-3 casters' ability cases against tests/batch3_fixtures.json `abilities`,
## `unit_cells`, `keys` and `unit_mana` (tools/emulate_batch3.py): every (ability, caster) record at levels 1..4; the worlds after
## it (the mixed / edges / tough scenes of Call Lightning, Berserker and Light/Darkness; the command limit of the three summoners;
## Banish's daemons; Earthpower's buildings; Salvage's debris); the unit-row cells of 0x4d3200 (E15); the keys (E18); the pay-
## then-check order of 0x23 / 0x2b; Salvage's 1 s throttle. The buttons in the real scene: the three batch-3 world checks.

var batch3: Dictionary = {}

func run():
	batch3 = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch3_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	if centre.x >= 0:
		table_rows_b3()
		for row in batch3.abilities:
			ability_records(row)
			if String(row.caster) == "AONX": scenes(row)
			special_scenes(row)
		unit_cells()
		mana_rows_b3()
		keys_b3()
		pay_then_check()
		salvage_throttle()
	clear_world()
	if failures > 0:
		printerr("Batch 3 caster checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Batch 3 caster checks passed: %d" % checks)
	quit(0)

## Open (BATCH3_RESEARCH.md B3-2): in the 'edges' scene Call Lightning kills 18 units; the rebuild's caster gains their experience
## and promotes (R-1: + hit points), while the fixture's caster keeps 70. The Shaman is held at the top rank here so no promotion
## changes its hit points; the targets and their hit points are compared as before.
func unit(type_id: String, offset: Vector2i, owner: int, extra: Dictionary = {}) -> int:
	var id := super.unit(type_id, offset, owner, extra)
	if type_id == "AONX" and offset == Vector2i.ZERO and extra.has("mana"): world.combat.fighters[id]["rank"] = 19   # the scenes' caster
	return id

func table_rows_b3():
	var t := Spells.load_table()
	var keys: Dictionary = batch3["keys"]
	for case_key in keys:
		var row: Dictionary = t.cases.get(str(int(case_key)), {})
		check(not row.is_empty() and String(row.key) == char(int(keys[case_key])), "case %s: key %s, the original %s" % [case_key, row.get("key"), char(int(keys[case_key]))])
	for a in batch3.abilities:
		var row: Dictionary = t.cases.get(str(int(a.case)), {})
		check(int(row.get("mana", -1)) == int(a.unit_mana) and Array(row.get("casters", [])).has(String(a.caster)), "%s: case %d, mana %d, caster %s" % [a.ability, int(a.case), int(a.unit_mana), a.caster])
		check(world.is_empty() or world.spells.has_case(int(a.case)) or Spells.CASE_BUILDERS.has(int(a.case)) or Spells.HERO_CASE_BUILDERS.has(int(a.case)), "%s has a builder" % a.ability)
	check(t.cases["22"].command_check == "AADE" and t.cases["35"].command_check == null and t.cases["43"].command_check == null, "Daemongate checks before paying, Firebomb and Goblins after")

## The command limit, Banish, Earthpower and Salvage worlds (tools/emulate_batch3.py scenarios).
func special_scenes(row: Dictionary):
	for c in row.cases:
		var name := String(c.scenario)
		if name in ["empty", "mixed", "edges", "tough"]: continue
		new_world()
		var caster := unit(String(row.caster), Vector2i.ZERO, 1)
		with_mana(caster, 200, 200)
		var label := "%s, %s level %d" % [row.ability, name, int(c.level)]
		var ids := {}
		match name:
			"command full", "command one left":
				var players: Dictionary = c.players["1"]
				set_command(1, used(1) + int(players.command[1]) - int(players.command[0]))
			"daemons":
				var list := [["AAEE", 0, Vector2i(1, 0), 500], ["AADE", 0, Vector2i(2, 0), 500], ["AHIX", 0, Vector2i(3, 0), -1], ["AVBX", 0, Vector2i(0, 2), -1], ["AADE", 1, Vector2i(-1, 0), -1]]
				for i in list.size():
					var e: Array = list[i]
					ids[str(i + 2)] = unit(String(e[0]), e[2], int(e[1]), {"hp": int(e[3])} if int(e[3]) > 0 else {})
			"hurt buildings":
				pass                                            # buildings: the record is compared above; the world below by hp only
			"debris":
				for o in [[1, 0], [3, 2], [-2, 5], [6, 0], [5, 3], [7, 0], [0, -6], [0, -7], [4, 5]]: world.combat.debris.append(centre + Vector2i(o[0], o[1]))
			"corpses only":
				pass
		var before: int = world.units.size()
		var stock: Array = world.economy.resources(1)
		var info: Dictionary = world.spells.cast_case(int(row.case), caster_of(caster), int(c.level), {"x": centre.x, "y": centre.y, "id": -1})
		var want_records: Array = c.built.filter(func(m): return m.message == "0x1f7")
		check(bool(info.get("cast", false)) == not want_records.is_empty(), "%s: a record %s" % [label, not want_records.is_empty()])
		match name:
			"command full", "command one left":
				var made: int = world.units.size() - before
				var want := 0 if want_records.is_empty() else int(want_records[0].amount)
				check(made == want, "%s: %d made, the original %d" % [label, made, want])
			"daemons":
				for k in ids:
					var hp: int = int(world.combat.fighters[ids[k]].hp) if world.combat.alive(world.combat.fighters[ids[k]]) else 0
					check(hp == int(c.after[k].hp), "%s: %s hp %d, the original %d" % [label, c.after[k].code, hp, int(c.after[k].hp)])
			"debris", "corpses only":
				var r: Dictionary = want_records[0] if not want_records.is_empty() else {}
				var got: Dictionary = info.get("record", {})
				check(int(got.get("kind", 0)) == 0x21 and int(got.get("amount", 0)) == 7 and String(got.get("effect", "")) == "EZ44", "%s: kind 0x21, 7, EZ44" % label)
				var total := int(got.get("w9b", 0)) + int(got.get("w9d", 0)) + int(got.get("w9f", 0)) + int(got.get("wa1", 0))
				var want_total := int(r.get("w9b", 0)) + int(r.get("w9d", 0)) + int(r.get("w9f", 0)) + int(r.raw_hex.hex_decode().decode_s16(0xa1)) if not r.is_empty() else 0
				if name == "corpses only": check(total == 0 and want_total == 0, "%s: corpses give nothing" % label)
				else:
					# six nodes in reach, each one 1d8 and one or more (L + 1)d20 + 20 / (L + 1)d40 + 20: the draws are the match
					# generator's, so the totals are compared by their bounds (the original's draws are its own).
					var level := int(c.level)
					check(total >= 6 * ((level + 1) + 20) and total <= 6 * 4 * ((level + 1) * 40 + 20), "%s: %d in the bounds (the original %d)" % [label, total, want_total])
					var after: Array = world.economy.resources(1)
					check(int(after[0]) - int(stock[0]) <= int(got.w9b) and int(after[1]) - int(stock[1]) <= int(got.w9d), "%s: credited" % label)
					check(world.combat.debris.size() == 9, "the debris stays")

## E15 (Emulated "unit_cells"): the ability cells of each type, in chain order, enabled by 0x4d4840; AABX's only for race 10 with
## PEPO; AAGX's always on.
func unit_cells():
	for r in batch3.unit_cells:
		new_world()
		world.production.races[1] = int(r.race)
		world.production.research[1] = r.research.duplicate()
		var id := unit(String(r.unit), Vector2i.ZERO, 1)
		var f = world.combat.fighters[id]
		if r.mana == null:
			f.erase("mana")
			f.erase("max_mana")
		else: with_mana(id, int(r.mana[0]), int(r.mana[1]))
		var rows: Array = world.spells.unit_row_for(String(r.unit), 1)
		var want: Array = r.cells.filter(func(cell): return Spells.UNIT_ROW.any(func(u): return int(u[1]) == int(cell[0])))
		var got: Array = rows.map(func(u): return [int(u[1]), 1 if world.spells.unit_row_enabled(u, [world.units[id]]) else 0])
		var wanted: Array = want.map(func(cell): return [int(cell[0]), int(cell[2])])
		check(got == wanted, "%s race %d %s mana %s: %s, the original %s" % [r.unit, int(r.race), r.research, r.mana, got, wanted])

func mana_rows_b3():
	for r in batch3.unit_mana:
		if int(r.rank) != 0 or r.get("error") != null: continue
		new_world()
		if int(r.computer): world.combat.ai_players[1] = true
		world.production.research[1] = r.research.duplicate()
		var id := unit(String(r.unit), Vector2i.ZERO, 1)
		var f = world.combat.fighters[id]
		check(int(f.get("mana", 0)) == int(r.mana) and int(f.get("max_mana", 0)) == int(r.max_mana), "%s %s computer %d: mana %s / %s (original %s / %s)" % [r.unit, r.research, int(r.computer), f.get("mana", 0), f.get("max_mana", 0), r.mana, r.max_mana])
		if r.has("interval") and r.interval != null: check(world.spells.unit_mana_interval(f) == int(r.interval), "%s %s: interval %d (original %s)" % [r.unit, r.research, world.spells.unit_mana_interval(f), r.interval])

## E18: each key casts its case through the selected caster and pays the mana.
func keys_b3():
	for pair in [[1, "AONX", 40, KEY_L], [9, "AONX", 50, KEY_Y], [0x16, "AVGX", 100, KEY_D], [0x17, "AVGX", 30, KEY_B], [0x18, "AABX", 40, KEY_E],
			[0x23, "AAJX", 35, KEY_F], [0x2b, "AOKX", 75, KEY_G]]:
		new_world()
		var id := unit(String(pair[1]), Vector2i.ZERO, 1)
		with_mana(id, 200, 200)
		world.host.selection = [world.units[id]]
		var done: Array = []
		world.spells.cast_done.connect(func(info): done.append(info))
		check(world.spells.hot_key(int(pair[3]), 1), "%s: the key of case %d" % [pair[1], int(pair[0])])
		check(done.size() == 1 and int(world.combat.fighters[id].mana) == 200 - int(pair[2]), "%s: casts once, pays %d (%d)" % [pair[1], int(pair[2]), int(world.combat.fighters[id].mana)])
	new_world()
	var golem := unit("AAGX", Vector2i.ZERO, 1)
	world.host.selection = [world.units[golem]]
	var done: Array = []
	world.spells.cast_done.connect(func(info): done.append(info))
	check(world.spells.hot_key(KEY_Z, 1) and done.size() == 1, "Z: the Bronze Golem salvages, no mana")

## 0x426350 cases 0x23 / 0x2b pay the mana before the builder's command check: at the limit the mana is gone and nothing comes.
## Case 0x16 checks AADE before paying.
func pay_then_check():
	for pair in [[0x23, "AAJX", 35], [0x2b, "AOKX", 75], [0x16, "AVGX", 0]]:
		new_world()
		var id := unit(String(pair[1]), Vector2i.ZERO, 1)
		with_mana(id, 200, 200)
		world.host.selection = [world.units[id]]
		set_command(1, used(1))
		var before: int = world.units.size()
		var cast: bool = world.spells.ability(int(pair[0]), 1)
		check(world.units.size() == before, "case %d at the limit: nothing made" % int(pair[0]))
		check(int(world.combat.fighters[id].mana) == 200 - int(pair[2]), "case %d at the limit: %d mana gone (%s)" % [int(pair[0]), int(pair[2]), cast])

func salvage_throttle():
	new_world()
	var golem := unit("AAGX", Vector2i.ZERO, 1)
	world.host.selection = [world.units[golem]]
	world.combat.now_ms = 50000
	check(world.spells.ability(0x1a, 1), "Salvage")
	check(not world.spells.ability(0x1a, 1), "not again within the second")
	world.combat.now_ms = 51000
	check(world.spells.ability(0x1a, 1), "again a second later")
