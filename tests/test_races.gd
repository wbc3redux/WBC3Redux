extends SceneTree
# All-races research fixtures (RACES_RESEARCH.md): data and fixture consistency only, no gameplay module.
var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Races check failed: ", label)

func load_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _initialize():
	var catalogue: Dictionary = load_json("res://assets/catalogue.json")
	var fixtures: Dictionary = load_json("res://tests/races_fixtures.json")
	var production: Dictionary = load_json("res://assets/production.json")
	var collision: Dictionary = load_json("res://assets/collision.json")
	var hero_rules: Dictionary = load_json("res://simulation/hero_rules.json")
	check(catalogue.races.size() == 16, "sixteen races")
	check(catalogue.units.size() == 199 and catalogue.buildings.size() == 264, "record counts")
	# The Knights slice (milestone 7) is a subset of the catalogue.
	for code in production.definitions:
		var d: Dictionary = production.definitions[code]
		var entry: Dictionary = catalogue.units[code] if d.kind == "unit" else catalogue.buildings[code]
		var cost := [entry.decoded.cost.gold, entry.decoded.cost.metal, entry.decoded.cost.crystal, entry.decoded.cost.stone]
		check(cost == d.cost, "Knights cost " + code)
		check(int(entry.decoded.build_time_seconds) == int(d.build_time_seconds), "Knights time " + code)
	# The race x class creation matrix reproduces milestone 6's Knight/Warrior fixture.
	var knight: Dictionary = fixtures.hero_creation[0]
	check(int(knight.race) == 0 and int(knight.class_id) == 0, "matrix starts with Knight Warrior")
	check(knight.stats == hero_rules.starting_stats, "Knight Warrior stats equal hero_rules.json")
	check(fixtures.hero_creation.size() == 16 * 28, "hero matrix size")
	# Movement type 0, extent 1 passability equals the static collision grid used by the MVP.
	var open := 0
	for cell in collision.cells:
		if cell.profile_passable[0] and cell.object_indices.is_empty():
			open += 1
	check(int(fixtures.passable_cells["0/1"]) == open, "type 0 extent 1 passable cells equal collision.json")
	check(int(fixtures.passable_cells["1/1"]) == 128 * 128 and int(fixtures.passable_cells["2/1"]) == 0, "flying / water counts")
	for route in fixtures.routes:
		if not route.ok:
			continue
		var previous: Array = route.start
		for cell in route.cells:
			check(max(abs(int(cell[0]) - int(previous[0])), abs(int(cell[1]) - int(previous[1]))) == 1, "route step " + route.name)
			previous = cell
		check(route.cells.is_empty() or route.cells[-1] == route.goal, "route reaches goal " + route.name)
	check(fixtures.cost_data_model_mismatches.is_empty(), "cost function equals record + [RULES] without hero/research")
	check(fixtures.research_0x4391c0.size() == 258, "research ids")
	if failures == 0: print("Races checks passed: ", checks)
	quit(0 if failures == 0 else 1)
