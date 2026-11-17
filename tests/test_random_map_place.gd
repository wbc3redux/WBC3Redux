extends SceneTree
## RM-5 (RANDOM_MAP_RESEARCH.md "RM-5"): simulation/random_map_place.gd against tests/random_map_place_fixtures.json
## (tools/emulate_random_map.py --place: the original 0x583960 under Unicorn on the generated world). Per case: the starts,
## the 16-bit generator after them, the tile changes, the deleted features in order, the occupancy grid before and after
## placement, every placement search with its answer, every building, every animal try and animal, the game generator
## entering every phase and at the end. Plus the data the port reads: footprints, plain tiles, creature table.
const RandomMap = preload("res://simulation/random_map.gd")
const RandomMapPlace = preload("res://simulation/random_map_place.gd")
var checks := 0
var failures := 0
var mines := {}                            # tests/random_map_bui_load_fixtures.json: what 0x418700 passes on per mine code

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/random_map_place_fixtures.json"))
	mines = JSON.parse_string(FileAccess.get_file_as_string("res://tests/random_map_bui_load_fixtures.json")).mines
	var data := RandomMap.load_data()
	check(not data.is_empty(), "assets/random_map.json loads (run the importer)")
	if data.is_empty():
		_finish()
		return
	_test_data(fixtures, data)
	var started := Time.get_ticks_msec()
	var totals := {"cases": 0, "buildings": 0, "armies": 0, "searches": 0, "deleted": 0, "tiles": 0, "failed": 0, "blgh": 0}
	for c in fixtures.cases: _test_case(c, data, totals)
	print("Random map place: %d cases in %d ms %s" % [fixtures.cases.size(), Time.get_ticks_msec() - started, str(totals)])
	check(totals.failed > 0 and totals.deleted > 0 and totals.tiles > 0 and totals.armies > 0, "the fixtures cover failed searches, clearing and animals")
	check(totals.blgh > 0, "a case reaches the BLGH entry")
	check(int(totals.cases) == fixtures.cases.size(), "every case ran to its end")
	_finish()

func _finish():
	if failures == 0: print("Random map place checks passed: ", checks)
	else: printerr("Random map place failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

func _test_data(fixtures: Dictionary, data: Dictionary):
	var sizes := RandomMapPlace.load_building_sizes()
	for code in fixtures.building_sizes:
		check(sizes.get(code, []) == _ints([fixtures.building_sizes[code]])[0], "footprint of %s" % code)
	var plain: Dictionary = fixtures.plain_tiles
	for code in data.tiles:
		check(RandomMapPlace.PLAIN_TILES.get(code, "") == plain.get(code, ""), "plain tile of %s" % code)
	for code in RandomMapPlace.PLAIN_TILES:
		check(plain.has(code) and data.tiles.has(code) and data.tiles.has(RandomMapPlace.PLAIN_TILES[code]), "plain tile %s has TER records" % code)
	var animals_seen := false
	for c in fixtures.cases:
		if c.phases.has("animals"):
			check(Array(RandomMapPlace.ANIMALS) == Array(c.phases.animals.table), "the creature table")
			animals_seen = true
			break
	check(animals_seen, "a case records the creature table")

func _same(got, want, label: String):
	check(JSON.stringify(got) == JSON.stringify(want), "%s\n  got  %s\n  want %s" % [label, JSON.stringify(got).left(300), JSON.stringify(want).left(300)])

func _ints(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		var line: Array = []
		for v in row: line.append(int(v) if v is float else v)
		out.append(line)
	return out

func _test_case(c: Dictionary, data: Dictionary, totals: Dictionary):
	var label := "case %d %s %d seed %d" % [int(c.index), c.terrain_name, int(c.size), int(c.seed)]
	var random_map = RandomMap.new(int(c.seed), data)
	var calls := [0]
	var attempts := int(c.attempts)
	var pass_last := func(_layout):
		calls[0] += 1
		return calls[0] >= attempts
	var layout: Dictionary = random_map.generate(int(c.terrain), int(c.size), pass_last)
	check(bool(layout.ok) and int(layout.lcg_after) == int(c.lcg_before), label + ": the layout")
	check(layout.features.size() == int(c.features), label + ": the layout's features")
	var sides: Array = []
	for s in c.sides: sides.append({"slot": int(s[0]), "race": int(s[1])})
	var place = RandomMapPlace.new(random_map, data)
	var result: Dictionary = place.place(layout, sides, {"rng": c.rng_before, "temples": int(c.temples),
		"animals": RandomMapPlace.ANIMAL_COUNTS[int(c.animals)], "resources": int(c.resources), "quests": int(c.quests) != 0,
		"no_towers": int(c.no_towers) != 0, "victory": int(c.victory)})
	check(bool(result.ok), label + ": ok")
	if not bool(result.ok): return
	var starts: Array = []
	for s in result.starts: starts.append([s.side_index, s.cell[0], s.cell[1]])
	_same(starts, _ints(c.starts), label + ": starts")
	var trace: Dictionary = result.log
	check(int(trace.lcg_after_starts) == int(c.lcg_after_starts), label + ": generator after the starts")
	_same(result.tile_changes, _ints(c.maph_after_clearing), label + ": tile changes")
	_same(trace.deleted, _ints([c.deleted])[0], label + ": deleted features")
	_same(trace.occupied_before_placement, _ints(c.occupied_before_placement), label + ": occupancy before placement")
	for name in ["towers", "mines", "quest_sites", "utilities"]:
		if not c.phases.has(name):
			check(name == "towers" and (int(c.no_towers) != 0 or int(c.victory) == 11), label + ": phase " + name)
			continue
		check(trace.phases.has(name), label + ": the port ran phase " + name)
		if not trace.phases.has(name): continue
		var want: Dictionary = c.phases[name]
		var got: Dictionary = trace.phases[name]
		_same(got.rng_in, _ints([want.rng_in])[0], label + ": generator into " + name)
		_same(got.searches, _ints(want.searches), label + ": searches of " + name)
		_same(got.places, _ints(want.places), label + ": buildings of " + name)
		totals.buildings += want.places.size()
		totals.searches += want.searches.size()
		for s in want.searches:
			if int(s[7]) < 0 or int(s[8]) < 0: totals.failed += 1
			if s[0] == "BLGH": totals.blgh += 1
	var want_animals: Dictionary = c.phases.animals
	var got_animals: Dictionary = trace.phases.animals
	_same(got_animals.rng_in, _ints([want_animals.rng_in])[0], label + ": generator into the animals")
	_same(got_animals.tries, _ints(want_animals.tries), label + ": animal tries")
	_same(got_animals.placed, _ints(want_animals.placed), label + ": animals")
	totals.armies += want_animals.placed.size()
	_same(result.rng_after, _ints([c.rng_after])[0], label + ": generator after the dead roll")
	check(int(result.lcg_after) == int(c.lcg_after), label + ": 16-bit generator at the end")
	_same(trace.occupied_after, _ints(c.occupied_after), label + ": occupancy after placement")
	for b in result.buildings:
		if b.has("level"):
			var want: Dictionary = mines[b.code]
			var slot: int = "GMCS".find(String(b.code).substr(2, 1))
			check(int(b.level) == int(want.level) and int(b.stock) == int(want.stock[slot]) and int(b.rate) == int(want.rate[slot]), label + ": mine stats of " + b.code)
	totals.cases += 1
	totals.deleted += c.deleted.size()
	totals.tiles += c.maph_after_clearing.size()
	check(result.buildings.size() + result.armies.size() > 0, label + ": something was placed")
