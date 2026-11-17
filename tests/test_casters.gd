extends "res://tests/test_hero_spells.gd"
## B2-2 (BATCH2_RESEARCH.md section 3): the casters' ability cases against tests/batch2_fixtures.json `abilities` and `unit_mana`
## (tools/emulate_batch2.py): each (ability, caster) pair's record at levels 1..4, its targets and the world after it in the
## empty / mixed / edges / tough scenes; the unit-row table of 0x4d3200 (R11); the hot keys, the mana payment and the level.
## The buttons in the real scene: tests/empire_world_checks.gd, tests/minotaur_world_checks.gd.

var batch2: Dictionary = {}
const RECORD_FIELDS := ["area", "radius", "b4", "b6", "sound", "b9", "b10", "b11", "b12", "kind", "w97", "amount", "w9b", "w9d", "w9f", "d85", "d89", "d131", "d135"]

func run():
	batch2 = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch2_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	if centre.x >= 0:
		table_rows()
		for row in batch2.abilities:
			ability_records(row)
			scenes(row)
		mana_rows()
		key_and_mana()
		row_enabled()
	clear_world()
	if failures > 0:
		printerr("Caster checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Caster checks passed: %d" % checks)
	quit(0)

func table_rows():
	var t := Spells.load_table()
	var want := {0: ["H", 40, ["AHGW", "AEDX"]], 5: ["P", 35, ["AKNX", "AMMX"]], 10: ["X", 20, ["AHGB", "AEOX"]], 14: ["B", 25, ["AONX", "AMMX"]], 18: ["J", 30, ["AHGR"]]}
	for i in want:
		var row: Dictionary = t.cases[str(i)]
		check(String(row.key) == String(want[i][0]) and int(row.mana) == int(want[i][1]) and Array(row.casters) == Array(want[i][2]) and row.command_check == null, "case %d: %s" % [i, row])
	# R11's cells, in the chain's order.
	var cells := {"AHGW": [[0xb, 0x31, 30], [0, 0x39, 40]], "AHGR": [[0x12, 0x3a, 30], [2, 0x3b, 40]], "AHGB": [[0xa, 0x3c, 20], [4, 0x35, 20]],
		"AMMX": [[2, 0x3b, 40], [0xe, 0x3f, 25], [5, 0x41, 35]], "AAAR": [[0xb, 0x31, 30]], "ARGX": [[2, 0x3b, 40], [0x29, 0x5e, 100]], "AHIX": []}
	for code in cells:
		var got: Array = Spells.unit_row(code).map(func(r): return [int(r[0]), int(r[1]), int(r[2])])
		check(got == cells[code], "%s row %s" % [code, got])
	# Every row names a type of its case's table entry, with the case's mana.
	for row in Spells.UNIT_ROW:
		var entry = t.cases.get(str(int(row[0])))
		if entry == null: continue
		# B4-2 (BATCH4_RESEARCH.md E13): Freeze's cell asks 45, its key 20; case 0xd reaches ALBX only through its selection loop (R5).
		if int(row[0]) == 0x2c: check(int(entry.mana) == 20 and int(row[2]) == 45, "case 0x2c: cell 45, key 20")
		else: check(int(entry.mana) == int(row[2]), "case %d: mana %d" % [int(row[0]), int(row[2])])
		for code in row[3]:
			if int(row[0]) == 0xd and code == "ALBX": continue
			check(Array(entry.casters).has(code), "case %d: %s is one of its casters" % [int(row[0]), code])

func caster_of(world_caster: int) -> Dictionary:
	return {"kind": "unit", "id": world_caster}

func decode_descriptors(raw_hex: String, count: int) -> Array:
	var raw: PackedByteArray = raw_hex.hex_decode()
	var out: Array = []
	for i in count: out.append([raw.decode_s32(0x55 + 24 * i), raw.decode_s32(0x59 + 24 * i)])
	return out

func first_record(c: Dictionary) -> Dictionary:
	for m in c.built:
		if m.message == "0x1f7": return m
	return {}

## The built record of the "empty" scene, levels 1..4.
func ability_records(row: Dictionary):
	for c in row.cases:
		if c.scenario != "empty": continue
		var level := int(c.level)
		new_world()
		var caster := unit(String(row.caster), Vector2i.ZERO, 1, {"mana": [200, 200]})
		var got: Dictionary = world.spells.build_case(int(row.case), caster_of(caster), level)
		var want := first_record(c)
		var label := "%s by %s level %d" % [row.ability, row.caster, level]
		check(not got.is_empty(), label + ": a record")
		if got.is_empty(): continue
		var diff: Array = []
		for k in RECORD_FIELDS:
			if int(got.get(k, 0)) != int(want[k]): diff.append("%s %s != %s" % [k, got.get(k, 0), want[k]])
		if text(got.effect) != text(want.effect): diff.append("effect %s != %s" % [got.effect, text(want.effect)])
		if text(got.effect2) != text(want.effect2): diff.append("effect2 %s != %s" % [got.effect2, text(want.effect2)])
		var descriptors: Array = got.get("descriptors", [])
		var original := decode_descriptors(String(want.raw_hex), int(want.b4))
		for i in original.size():
			if i >= descriptors.size() or int(descriptors[i][0]) != int(original[i][0]) or int(descriptors[i][1]) != int(original[i][1]):
				diff.append("descriptor %d %s != %s" % [i, descriptors, original])
		check(diff.is_empty(), "%s: %s" % [label, diff])

## The scenes of tools/emulate_spells.py scenarios_for: [kind, code, owner, offset from the caster, extra].
func scene_rows(name: String) -> Array:
	if name == "empty": return []
	if name == "mixed":
		return [["unit", "AHKX", 0, Vector2i(1, 0), {}], ["unit", "AHKX", 0, Vector2i(3, 2), {}], ["unit", "AHKX", 0, Vector2i(12, 0), {}], ["unit", "AHKX", 1, Vector2i(-1, 1), {}],
			["building", "BKH0", 0, Vector2i(2, -2), {}], ["unit", "AHKX", 1, Vector2i(1, 0), {"hp": 5}], ["unit", "AHKX", 1, Vector2i(4, 0), {}],
			["unit", "AHKX", 0, Vector2i(0, 2), {"hp": 5}], ["unit", "AHKX", 1, Vector2i(20, 0), {"hp": 5}]]
	var out: Array = []
	if name == "edges":
		for o in EDGE: out.append(["unit", "AUMX", 0, Vector2i(o[0], o[1]), {"hp": 5, "mana": [30, 50]}])
		for o in EDGE: out.append(["unit", "AHKX", 1, Vector2i(o[0] + 1, o[1]), {"hp": 5}])
	else:
		var types := ["AHKX", "ADLX", "AAEE", "AUIX", "AHFX"]
		for i in types.size(): out.append(["unit", types[i], 0, Vector2i(i, 2), {"hp": 1000}])
		out.append(["building", "BKH0", 0, Vector2i(4, -3), {}])
		out.append(["unit", "AUGX", 0, Vector2i(-3, 0), {"hp": 1000, "mana": [3, 50]}])
	return out

const EDGE := [[0, -8], [0, 8], [-8, 0], [8, 0], [0, -6], [0, 6], [6, 0], [-6, 0], [4, 4], [5, 4], [7, 7],
	[0, -10], [0, 10], [10, 0], [-10, 0], [6, 6], [2, -9], [-5, 5]]

## The world and the targets after the cast, by the fixture's object numbers (creation order, the caster first). A building's
## or a second unit on an occupied cell is left out of the comparison where the port's world cannot hold it.
func scenes(row: Dictionary):
	for c in row.cases:
		if c.scenario == "empty": continue
		new_world()
		var caster := unit(String(row.caster), Vector2i.ZERO, 1, {"mana": [200, 200]})
		var ids := {"1": caster}
		var next := 2
		for s in scene_rows(String(c.scenario)):
			if s[0] == "unit":
				var cell: Vector2i = s[3]
				if world.combat.navigator.occupant(centre + cell) != null or (cell == Vector2i.ZERO):
					next += 1
					continue
				ids[str(next)] = unit(String(s[1]), cell, int(s[2]), s[4])
			next += 1
		var info: Dictionary = world.spells.cast_case(int(row.case), caster_of(caster), int(c.level))
		var label := "%s by %s, %s level %d" % [row.ability, row.caster, c.scenario, int(c.level)]
		check(bool(info.get("cast", false)), label + ": cast")
		var resolved_ids: Array = []
		for step in c.applied:
			for m in step.sent:
				if m.message == "0x1f7":
					for t in m.target_ids: resolved_ids.append(str(int(t)))
		var got_ids: Array = []
		for t in info.get("result", {}).get("targets", []):
			if t.get("kind", "unit") == "unit": got_ids.append(int(t.id))
		var diff: Array = []
		for k in ids:
			var targeted: bool = resolved_ids.has(k)
			if got_ids.has(ids[k]) != targeted: diff.append("%s (object %s) targeted %s, the original %s" % [c.before[k].code, k, got_ids.has(ids[k]), targeted])
			var after: int = int(world.combat.fighters[ids[k]].hp) if world.combat.fighters.has(ids[k]) else 0
			if after != int(c.after[k].hp): diff.append("%s (object %s) hp %d, the original %d" % [c.before[k].code, k, after, int(c.after[k].hp)])
		check(diff.is_empty(), "%s: %s" % [label, diff])

## E5: the four casters' mana and interval (rank 0; ranks are not modelled, section 5).
func mana_rows():
	for r in batch2.unit_mana:
		if int(r.rank) != 0 or r.has("error"): continue
		new_world()
		if int(r.computer): world.combat.ai_players[1] = true
		world.production.research[1] = r.research.duplicate()
		var id := unit(String(r.unit), Vector2i.ZERO, 1)
		var f = world.combat.fighters[id]
		check(int(f.get("mana", 0)) == int(r.mana) and int(f.get("max_mana", 0)) == int(r.max_mana), "%s %s: mana %s / %s (original %s / %s)" % [r.unit, r.research, f.get("mana", 0), f.get("max_mana", 0), r.mana, r.max_mana])
		if r.has("interval"): check(world.spells.unit_mana_interval(f) == int(r.interval), "%s %s: interval %d (original %s)" % [r.unit, r.research, world.spells.unit_mana_interval(f), r.interval])

func with_mana(id: int, mana: int, maximum: int):
	var f = world.combat.fighters[id]
	f["mana"] = mana
	f["max_mana"] = maximum
	f["mana_ms"] = 0

## The key finds the selected caster, pays its mana and casts; below the mana nothing happens.
func key_and_mana():
	for pair in [[0, "AHGW", 40, KEY_H], [18, "AHGR", 30, KEY_J], [10, "AHGB", 20, KEY_X], [14, "AMMX", 25, KEY_B], [5, "AMMX", 35, KEY_P]]:
		new_world()
		var id := unit(String(pair[1]), Vector2i.ZERO, 1)
		with_mana(id, 100, 100)
		world.host.selection = [world.units[id]]
		var done: Array = []
		world.spells.cast_done.connect(func(info): done.append(info))
		check(world.spells.hot_key(int(pair[3]), 1), "%s: key of case %d" % [pair[1], int(pair[0])])
		check(done.size() == 1 and int(done[0].level) == 1, "%s: cast at level 1" % pair[1])
		check(int(world.combat.fighters[id].mana) == 100 - int(pair[2]), "%s pays %d" % [pair[1], int(pair[2])])
		world.combat.fighters[id].mana = int(pair[2]) - 1
		check(not world.spells.hot_key(int(pair[3]), 1) and done.size() == 1, "%s below the mana: no cast" % pair[1])

## 0x4d4840: any selected unit of a row's type with the mana enables the cell; a case without a builder stays off.
func row_enabled():
	new_world()
	var poor := unit("AMMX", Vector2i.ZERO, 1)
	var rich := unit("AMMX", Vector2i(1, 0), 1)
	with_mana(poor, 10, 100)
	with_mana(rich, 40, 100)
	var units: Array = [world.units[poor], world.units[rich]]
	var rows: Array = Spells.unit_row("AMMX")
	check(rows.all(func(r): return world.spells.unit_row_enabled(r, units)), "the richer Shaman enables all three")
	check(not rows.any(func(r): return world.spells.unit_row_enabled(r, [units[0]])), "the poor Shaman none")
	var mage := unit("AEOX", Vector2i(2, 0), 1)
	with_mana(mage, 100, 100)
	var eox: Array = Spells.unit_row("AEOX")
	check(eox.size() == 2 and world.spells.unit_row_enabled(eox[0], [world.units[mage]]) and world.spells.unit_row_enabled(eox[1], [world.units[mage]]),
		"AEOX: Hand of Ice and (B4-2) Freeze are on")
