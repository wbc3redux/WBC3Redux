extends SceneTree
## Target search timing (not part of -Check): Combat.search_rect, the cell-by-cell window scan of 0x5334f0 that every unit's
## attitude script, tower and acquisition runs, against a variant that skips empty cells by three dictionary look-ups.
## Plays a computer match and, every --every seconds of game time, runs both on every live fighter's 25 x 25 window
## (radius max(12, range)) and checks that they return the same candidate.
##   Godot --headless --path . --script res://tests/bench_search.gd -- --minutes=10 [--map=forest-lakes --map-races]

const Setup = preload("res://simulation/skirmish_setup.gd")
const MapData = preload("res://core/map_data.gd")

func _initialize():
	call_deferred("run")

func us() -> int:
	return Time.get_ticks_usec()

func fast_search(c, owner: int, from_cell: Vector2i, rect: Array, self_id: int) -> Variant:
	var best = null
	var best_score := 0
	var ground: Dictionary = c.navigator.occupants
	var air: Dictionary = c.navigator.air_occupants
	var stamped: Dictionary = c.navigator.building_cells
	var x0 := maxi(int(rect[0]), 0)
	var x1 := mini(int(rect[1]), c.navigator.collision.width - 1)
	var y0 := maxi(int(rect[2]), 0)
	var y1 := mini(int(rect[3]), c.navigator.collision.height - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell := Vector2i(x, y)
			if not ground.has(cell) and not air.has(cell) and not stamped.has(cell): continue
			var candidate = c.candidate_for_owner(owner, self_id, cell, true, from_cell)
			if candidate == null: continue
			var score: int = int(candidate.hunt) if candidate.has("hunt") else c._score(owner, from_cell, candidate)
			if score > 0 and (best == null or score > best_score):
				best = candidate
				best_score = score
	return best

func run():
	var minutes := 10.0
	var every := 60.0
	var slug := "desert-sands"
	var races: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="): minutes = float(arg.get_slice("=", 1))
		if arg.begins_with("--every="): every = float(arg.get_slice("=", 1))
		if arg.begins_with("--map="): slug = arg.get_slice("=", 1)
		if arg == "--map-races": races = ["map"]
	MapData.select(slug)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = MapData.map() if slug != "desert-sands" else JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	var sides := int(setup.sides)
	if races == ["map"]: races = range(sides).map(func(i): return int(setup.players[i].race))
	if races.is_empty(): for i in sides: races.append(0)
	for i in sides:
		Setup.set_race(setup, i, int(races[i]))
		Setup.set_kind(setup, i, Setup.COMPUTER, [3, 6, 4, 5, 2, 2][i])
	scene.start_skirmish(setup, "", null, "bench")
	var c = scene.combat
	var mismatches := 0
	var steps := roundi(minutes * 60.0 * 40.0)
	var every_steps := roundi(every * 40.0)
	for i in steps:
		if scene.skirmish.over: break
		scene.simulation_step(0.025)
		if i % every_steps != every_steps - 1: continue
		var slow_us := 0
		var fast_us := 0
		var n := 0
		for id in c.fighters:
			var f = c.fighters[id]
			if not c.alive(f) or not scene.unit_by_id(id) or c.units[id].inside_building: continue
			var here: Vector2i = c.unit_cell(id)
			var r := maxi(12, int(f.stats.range))
			var rect := [here.x - r, here.x + r, here.y - r, here.y + r]
			var t := us()
			var a = c.search_rect(f.owner, here, rect, id)
			slow_us += us() - t
			t = us()
			var b = fast_search(c, f.owner, here, rect, id)
			fast_us += us() - t
			n += 1
			if str(a) != str(b):
				mismatches += 1
				if mismatches <= 10: print("  MISMATCH fighter %d: %s vs %s" % [id, str(a), str(b)])
		print("t=%4ds fighters %d searched %d: search_rect %.2f ms (%.1f us each), skipping empty cells %.2f ms (%.1f us each)" % [
			roundi((i + 1) * 0.025), c.fighters.size(), n, slow_us / 1000.0, slow_us / maxf(n, 1), fast_us / 1000.0, fast_us / maxf(n, 1)])
	print("bench done: %d mismatches" % mismatches)
	scene.queue_free()
	quit(1 if mismatches > 0 else 0)
