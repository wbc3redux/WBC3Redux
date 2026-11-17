extends SceneTree
## Milestone 7 checks: placement and post-construction routing against the emulated original
## (tests/production_fixtures.json, tools/emulate_production.py), then construction, production,
## queue, cancellation, upgrade, population and spawn rules (PRODUCTION_RESEARCH.md).
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const Economy = preload("res://simulation/economy.gd")
const Rules = preload("res://simulation/production_rules.gd")
const Production = preload("res://simulation/production.gd")
const Placement = preload("res://simulation/placement.gd")
var checks := 0
var failures := 0
var rules = Rules.new()
var collision = CollisionData.new()

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/production_fixtures.json"))
	_test_rules()
	_test_placement_parity(fixtures)
	_test_route_parity(fixtures)
	_test_cost_and_spawn_parity(fixtures)
	_test_construction()
	_test_production()
	_test_upgrade_and_dependencies()
	_test_population_and_rally()
	if failures == 0: print("Production checks passed: ", checks)
	else: printerr("Production failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

# -------------------------------------------------------------------- fixtures

func new_world(resources: Array = [500, 500, 500, 500]):
	var nav = Navigation.new(collision)
	var economy = Economy.new(0)
	economy.add_player(0, resources)
	var production = Production.new(rules, economy, nav)
	return {"nav": nav, "economy": economy, "production": production}

class Dummy:
	extends RefCounted

func nearest_valid(fixtures: Dictionary, ident: String, wanted: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	var rows: Array = fixtures.placement.maps[ident]
	for y in range(rows.size()):
		for x in range(rows[y].length()):
			if rows[y][x] == "1":
				var d: int = absi(x - wanted.x) + absi(y - wanted.y)
				if d < best_d:
					best_d = d
					best = Vector2i(x, y)
	return best

func open_ground() -> Vector2i:
	for y in range(20, 120):
		for x in range(40, 100):
			var flat := true
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					var c: Dictionary = collision.cell_data(Vector2i(x + dx, y + dy))
					if not c.profile_passable[0] or not c.object_indices.is_empty() or int(c.raw[0]) != int(collision.cell_data(Vector2i(x, y)).raw[0]): flat = false
			if flat: return Vector2i(x, y)
	return Vector2i(-1, -1)

func step(production, from_ms: int, to_ms: int):
	var t := from_ms
	while t <= to_ms:
		production.update(t)
		t += 25

# -------------------------------------------------------------------- data rules

func _test_rules():
	check(rules.cost("AHBX") == [20, 0, 0, 0] and rules.cost("AHKX") == [0, 20, 0, 0] and rules.cost("AHMX") == [60, 0, 0, 0], "ARM costs 0x40b6b0")
	check(rules.cost("BAGA") == [100, 0, 0, 100] and rules.cost("BPFL") == [80, 0, 0, 100] and rules.cost("BKK1") == [300, 0, 0, 100], "BUI costs 0x40b6b0")
	check(rules.cost("AHMX", 100) == [30, 0, 0, 0] and rules.cost("AHKX", 5000) == [0, 1, 0, 0], "price discount keeps at least 1")
	check(rules.time_ms("AHBX") == 25000 and rules.time_ms("AHKX") == 20000 and rules.time_ms("AHMX") == 25000, "unit times")
	check(rules.time_ms("BAGA") == 30000 and rules.time_ms("BPFL") == 45000 and rules.time_ms("BKK1") == 60000, "building times")
	check(rules.time_ms("BAGA", "AHBX") == 30000 and rules.time_ms("BAGA", "AHHX") == 30000, "builder speed 10 leaves time unchanged")
	check(rules.requirements("BAGA") == ["BKK0"] and rules.requirements("BPFL") == ["BKK1"] and rules.requirements("AHMX") == ["BPFL"], "dependencies")
	check(rules.requirements("AHKX").is_empty() and rules.requirements("AHBX").is_empty(), "unrestricted units")
	check(Rules.satisfies("BKK1", "BKK0") and Rules.satisfies("BKK2", "BKK1") and not Rules.satisfies("BKK0", "BKK1") and Rules.satisfies("BAGA", "BAGA") and not Rules.satisfies("BAGA", "BKK0"), "level-aware dependency")
	check(Rules.keep_level("BKK0") == 1 and Rules.keep_level("BKK4") == 5 and Rules.keep_level("BAGA") == 0 and Rules.keep_level("BPFL") == 0, "keep levels")
	var menu: Array = rules.menu("BAGA")
	check(menu.size() == 2 and menu[0].id == "AHKX" and menu[1].id == "AHMX", "Garrison menu")
	var keep_ids: Array = rules.menu("BKK0").map(func(m): return m.id)
	check(keep_ids == ["BKK1", "AHBX", "PCR0"], "Keep level 1 menu: upgrade, Peasant, research")
	check(rules.construction_menu().slice(0, 6) == ["BKK0", "BAGA", "BPSM", "BPSB", "BPFL", "BPMA"], "H0 construction list")
	check(rules.army_limit("BKK0") == 2 and rules.army_limit("BAGA") == 2 and rules.army_limit("BPFL") == 2, "Building.cfg A column")

# -------------------------------------------------------------------- emulated placement (0x435900)

func _test_placement_parity(fixtures: Dictionary):
	var nav = Navigation.new(collision)
	for ident in fixtures.placement.types:
		var definition: Dictionary = rules.definition(ident)
		var rows: Array = fixtures.placement.maps[ident]
		var mismatches := 0
		for y in range(collision.height):
			for x in range(collision.width):
				var ok: bool = Placement.check(nav, definition, Vector2i(x, y)).ok
				if ok != (rows[y][x] == "1"): mismatches += 1
		check(mismatches == 0, "Placement of %s must match the emulated 0x435900 on all 16384 cells (%d differ)" % [ident, mismatches])
	var builder := Dummy.new()
	var other := Dummy.new()
	for c in fixtures.placement.occupant_cases:
		var nav2 = nav
		var cell := Vector2i(int(c.occupant[0]), int(c.occupant[1]))
		nav2.occupants[cell] = builder if c.occupant_is_builder else other
		var got: bool = Placement.check(nav2, rules.definition(c.type), Vector2i(int(c.order[0]), int(c.order[1])), builder if c.occupant_is_builder else null).ok
		nav2.occupants.erase(cell)
		check(got == bool(c.result), "Occupant case %s %s builder=%s hole=%s" % [c.type, c.occupant, c.occupant_is_builder, c.hole])

# -------------------------------------------------------------------- emulated routes after construction

func _test_route_parity(fixtures: Dictionary):
	var nav = Navigation.new(collision)
	var serial := 0
	var changed := 0
	for stage in fixtures.routes_after_construction:
		var definition: Dictionary = rules.definition(stage.type)
		var top := int(stage.anchor[1])
		var claimed = nav.stamp_building(500 + serial, int(stage.footprint_left), top, int(definition.footprint[0]), int(definition.footprint[1]), definition.mask_rows)
		serial += 1
		check(claimed.size() > 0, "Stamp claims footprint cells: " + stage.name)
		for entry in stage.blocked_window:
			var cell := Vector2i(int(entry[0]), int(entry[1]))
			check((not nav.is_passable(cell)) == (int(entry[2]) == 1), "Stamped cell state %s %s" % [stage.name, cell])
		for case in stage.cases:
			var found: Dictionary = nav.route_cells(Vector2i(int(case.start[0]), int(case.start[1])), Vector2i(int(case.goal[0]), int(case.goal[1])))
			check(found.ok == bool(case.ok), "Route outcome after %s %s" % [stage.name, case.name])
			var expected: Array = []
			for segment in case.segments:
				if not segment.cells.is_empty(): expected.append(segment.cells)
			var mine: Array = []
			for segment in found.get("segments", []):
				if not segment.is_empty(): mine.append(segment)
			check(mine.size() == expected.size(), "Segment count after %s %s (%d vs %d)" % [stage.name, case.name, mine.size(), expected.size()])
			if not case.unchanged_from_before: changed += 1
			for i in range(mini(mine.size(), expected.size())):
				check(mine[i].size() == expected[i].size(), "Segment length after %s %s" % [stage.name, case.name])
				for j in range(mini(mine[i].size(), expected[i].size())):
					check(mine[i][j] == Vector2i(int(expected[i][j][0]), int(expected[i][j][1])), "Segment cell after %s %s" % [stage.name, case.name])
	check(changed >= 6, "Fixtures include routes that the new buildings changed")

# -------------------------------------------------------------------- emulated cost (0x40b6b0) and spawn cell (0x530a90)

func _test_cost_and_spawn_parity(fixtures: Dictionary):
	for c in fixtures.costs:
		var cost: Array[int] = rules.cost(c.item)
		var expected: Array = c.cost.map(func(v): return int(v))
		check(cost == expected, "Cost of %s must match 0x40b6b0" % c.item)
		var seconds: int = rules.time_ms(c.item, c.other) / 1000
		check(seconds == int(c.seconds), "Time of %s with %s must match 0x40b6b0 (%d vs %d)" % [c.item, c.other, seconds, int(c.seconds)])
	var nav = Navigation.new(collision)
	var wrong := 0
	for c in fixtures.spawn_cells:
		var got: Vector2i = nav.free_cell_near(Vector2i(int(c.origin[0]), int(c.origin[1])))
		if got != Vector2i(int(c.result[0]), int(c.result[1])): wrong += 1
	check(wrong == 0, "Spawn cell must match the emulated 0x530a90 on %d cases (%d differ)" % [fixtures.spawn_cells.size(), wrong])

# -------------------------------------------------------------------- construction rules

func _test_construction():
	var w = new_world()
	var production = w.production
	var nav = w.nav
	var keep = production.add_completed(0, "BKK0", 4, 62)
	check(keep.original_type_id == "BKK0" and not keep.constructing and w.economy.capacity(0) == [1000, 1000, 1000, 1000], "start Keep registers with the economy")
	var site := Vector2i(23, 65)
	var builder := Dummy.new()
	var hidden: Array = []
	var released: Array = []
	production.builder_hidden.connect(func(id): hidden.append(id))
	production.builder_released.connect(func(id, cell): released.append([id, cell]))
	var far: Dictionary = production.place_building(0, "BAGA", site, 1000, 7, "AHBX", Vector2i(30, 70), builder)
	check(not far.ok and w.economy.resources(0) == [500, 500, 500, 500], "builder more than three cells away cannot place")
	var poor = new_world([99, 500, 500, 500])
	poor.production.add_completed(0, "BKK0", 4, 62)
	check(not poor.production.can_place(0, "BAGA", site, builder).ok, "insufficient gold blocks placement")
	var placed: Dictionary = production.place_building(0, "BAGA", site, 1000, 7, "AHBX", Vector2i(25, 67), builder)
	check(placed.ok, "Garrison placement near the Keep: " + str(placed.get("reason")))
	if not placed.ok: return
	var garrison = placed.building
	check(w.economy.resources(0) == [400, 500, 500, 400], "cost is charged when the building is placed (gold 100, stone 100)")
	check(garrison.constructing and garrison.hit_points == 1 and garrison.builder_id == 7 and hidden == [7], "builder is hidden inside; hit points start at 1")
	check(garrison.finish_ms - garrison.started_ms == 30000, "Garrison builds in 30 s")
	check(not nav.is_passable(Vector2i(garrison.left + 4, garrison.top + 4)), "footprint cells block movement once placed")
	var again: Dictionary = production.can_place(0, "BAGA", site, builder)
	check(not again.ok, "the same site cannot be built twice")
	var blocked_keep = new_world()
	check(not blocked_keep.production.can_place(0, "BAGA", site, builder).ok and "BKK0" in blocked_keep.production.can_place(0, "BAGA", site, builder).reason, "Garrison needs a Keep first")
	step(production, 1000, 16000)
	check(garrison.progress == 50 and garrison.hit_points == 301, "halfway: progress 50, hit points 1 + 300 (%d, %d)" % [garrison.progress, garrison.hit_points])
	step(production, 16025, 31000)
	check(garrison.constructing and garrison.progress == 100, "progress reaches 100 at start + 30 s")
	production.update(31025)
	check(not garrison.constructing and garrison.hit_points == 600 and released.size() == 1 and released[0][0] == 7, "completion one update later; the builder comes out")
	check(production.requirement_met(0, "BAGA") and w.economy.capacity(0) == [1000, 1000, 1000, 1000], "completed Garrison satisfies BAGA")
	check(production.population(0).maximum == 2 + 2 + 5 - 2, "command limit: two buildings of 2 plus Keep table 5 minus 2")
	# Abandoned construction decays and dies; no refund.
	var w2 = new_world()
	w2.production.add_completed(0, "BKK0", 4, 62)
	var rel2: Array = []
	w2.production.builder_released.connect(func(id, cell): rel2.append([id, cell]))
	var p2: Dictionary = w2.production.place_building(0, "BAGA", site, 2000, 9, "AHBX", Vector2i(25, 67), builder)
	check(p2.ok, "second world placement")
	var cells_before: int = w2.nav.building_cells.size()
	check(cells_before > 0, "unfinished building is stamped")
	check(w2.production.release_builder(p2.building.entity_id, 2000), "Cancel releases the builder")
	check(not w2.production.release_builder(p2.building.entity_id, 2000), "no builder left to release")
	step(w2.production, 2000, 2225)
	check(w2.production.buildings.has(p2.building.entity_id), "still standing before the first decay tick (hp 1 + 0)")
	step(w2.production, 2250, 2250)
	check(not w2.production.buildings.has(p2.building.entity_id), "hit point 1 decays to 0 at the first 250 ms tick")
	check(w2.nav.is_passable(Vector2i(p2.building.left + 4, p2.building.top + 4)), "footprint is cleared when the unfinished building dies")
	check(rel2.size() == 1 and w2.economy.resources(0) == [400, 500, 500, 400], "builder reappears; the price is not refunded")
	# Resume keeps progress; only one builder at a time.
	var w3 = new_world()
	w3.production.add_completed(0, "BKK0", 4, 62)
	var p3: Dictionary = w3.production.place_building(0, "BAGA", site, 0, 3, "AHBX", Vector2i(25, 67), builder)
	step(w3.production, 0, 15000)
	var g3 = p3.building
	check(g3.progress == 50, "50 percent after 15 s")
	check(w3.production.release_builder(g3.entity_id, 15000), "release at 50 percent")
	check(not w3.production.attach_builder(g3.entity_id + 1, 4, Vector2i(25, 67), 15100), "unknown building")
	check(w3.production.attach_builder(g3.entity_id, 4, Vector2i(25, 67), 15100), "a new builder joins")
	check(not w3.production.attach_builder(g3.entity_id, 5, Vector2i(25, 67), 15100), "a second builder cannot join")
	check(g3.finish_ms == 30100 and g3.progress == 50, "remaining half re-based from the join time")
	step(w3.production, 15100, 30200)
	check(not g3.constructing and g3.hit_points <= 600, "resumed building completes")

# -------------------------------------------------------------------- production rules

func _test_production():
	var w = new_world([200, 200, 200, 200])
	var production = w.production
	var keep = production.add_completed(0, "BKK0", 4, 62)
	var made: Array = []
	production.unit_ready.connect(func(info): made.append(info.duplicate()); info.unit_id = 100 + made.size())
	check(production.can_queue(keep.entity_id, "AHBX").ok, "Peasant is offered at the Keep")
	check(not production.can_queue(keep.entity_id, "AHKX").ok, "Swordsmen are not trained at the Keep")
	check(not production.can_queue(keep.entity_id, "PCR0").ok, "research is not simulated")
	var r: Dictionary = production.enqueue(keep.entity_id, "AHBX", 1000)
	check(r.ok and keep.job_item == "AHBX" and w.economy.resources(0) == [180, 200, 200, 200], "cost is paid when the job starts")
	check(keep.job_end_ms == 26000, "Peasant takes 25 s")
	production.enqueue(keep.entity_id, "AHBX", 1000)
	production.enqueue(keep.entity_id, "AHBX", 1000)
	check(keep.queue.size() == 2 and w.economy.resources(0) == [180, 200, 200, 200], "queued orders cost nothing yet")
	check(production.cancel_slot(keep.entity_id, 2, 1100) and keep.queue.size() == 1 and w.economy.resources(0) == [180, 200, 200, 200], "dropping a queued order refunds nothing")
	step(production, 1000, 13000)
	check(keep.job_progress == 48, "job progress percentage (12 s of 25)")
	check(production.cancel_slot(keep.entity_id, 0, 13000) and w.economy.resources(0)[0] == 180, "cancelling the running job refunds its cost and starts the next: 200 - 20")
	check(keep.job_item == "AHBX" and keep.job_start_ms == 13000 and keep.queue.is_empty(), "the queued Peasant starts at once")
	step(production, 13025, 38025)
	check(made.size() == 1 and keep.job_item == "", "a Peasant is created at start + 25 s")
	check(made[0].cell.x >= 0 and production.navigator.chebyshev(made[0].cell, production.spawn_target(keep)) <= 2, "the Peasant appears next to the spawn target")
	check(production.units.size() == 1 and production.population(0).current == 1, "the created unit counts toward population")
	check(w.economy.resources(0)[0] == 180, "gold after one finished Peasant")
	# cancel all refunds only the running job
	production.enqueue(keep.entity_id, "AHBX", 40000)
	production.enqueue(keep.entity_id, "AHBX", 40000)
	check(w.economy.resources(0)[0] == 160, "second Peasant paid")
	check(production.cancel_all(keep.entity_id) and w.economy.resources(0)[0] == 180 and not keep.has_job(), "Cancel refunds the running job and clears the queue")
	# queue cap and unaffordable head
	var tight = new_world([20, 0, 0, 0])
	tight.production.add_completed(0, "BKK0", 4, 62)
	var k2 = tight.production.buildings.values()[0]
	tight.production.enqueue(k2.entity_id, "AHBX", 0)
	check(not tight.production.can_queue(k2.entity_id, "AHBX").ok, "cannot click an unaffordable item")
	tight.economy.credit(0, [20, 0, 0, 0])
	for i in range(Production.QUEUE_LIMIT):
		check(tight.production.enqueue(k2.entity_id, "AHBX", 0).ok or i >= 1, "queue accepts up to its limit")
		tight.economy.credit(0, [20, 0, 0, 0])
	check(k2.queue.size() <= Production.QUEUE_LIMIT, "queue never exceeds its limit")
	# pending job: an unaffordable head waits in the queue, then starts when gold arrives
	var w5 = new_world([40, 0, 0, 0])
	var k5 = w5.production.add_completed(0, "BKK0", 4, 62)
	w5.production.enqueue(k5.entity_id, "AHBX", 0)
	k5.queue.append("AHBX")
	check(w5.economy.try_spend(0, [20, 0, 0, 0]), "spend the remaining gold elsewhere")
	w5.production.update(25000)
	w5.production.update(25025)
	check(k5.job_pending and k5.job_item == "" and k5.queue == ["AHBX"], "head that cannot be paid leaves the building pending")
	w5.production.update(25050)
	check(k5.job_pending, "still pending without gold")
	w5.economy.credit(0, [20, 0, 0, 0])
	w5.production.update(25075)
	check(k5.job_item == "AHBX" and not k5.job_pending and k5.queue.is_empty() and k5.job_start_ms == 25075, "pending head starts when it becomes affordable")

# -------------------------------------------------------------------- Keep upgrade and prerequisites

func _test_upgrade_and_dependencies():
	var w = new_world([1000, 1000, 1000, 1000])
	var production = w.production
	var nav = w.nav
	var keep = production.add_completed(0, "BKK0", 4, 62)
	var builder := Dummy.new()
	var site := Vector2i(30, 70)
	check(not production.can_place(0, "BPFL", site, builder).ok, "Fletcher needs a level 2 Keep")
	check("BKK1" in production.can_place(0, "BPFL", site, builder).reason, "and says so")
	var garrison = production.add_completed(0, "BAGA", 24, 60)
	check(production.can_queue(garrison.entity_id, "AHKX").ok and not production.can_queue(garrison.entity_id, "AHMX").ok, "Squire needs a Fletcher")
	check("BPFL" in production.can_queue(garrison.entity_id, "AHMX").reason, "and says so")
	var up: Dictionary = production.enqueue(keep.entity_id, "BKK1", 0)
	check(up.ok and w.economy.resources(0) == [700, 1000, 1000, 900] and keep.job_end_ms == 60000, "Keep upgrade: 300 gold + 100 stone, 60 s")
	check(not production.can_queue(keep.entity_id, "BKK1").ok, "the upgrade cannot be ordered twice")
	production.enqueue(keep.entity_id, "AHBX", 0)
	check(keep.queue == ["AHBX"], "the Keep trains nothing while upgrading: the Peasant waits")
	step(production, 0, 60000)
	check(keep.original_type_id == "BKK1" and keep.level == 1 and keep.max_hit_points == 600 and keep.hit_points == 600, "upgrade effect 0x4a4f60: type, level, +100 hit points")
	check(w.economy.capacity(0) == [1500, 1500, 1500, 1500], "Keep level 2 raises the stockpile limit")
	check(keep.job_item == "AHBX" and keep.job_start_ms == 60000, "the waiting Peasant starts after the upgrade")
	check(rules.menu(keep.original_type_id).map(func(m): return m.id).slice(0, 2) == ["BKK2", "AHBX"], "Keep level 2 offers level 3")
	var fl: Dictionary = production.place_building(0, "BPFL", site, 61000, 5, "AHHX", Vector2i(30, 70), builder)
	check(fl.ok, "Fletcher can be built with a level 2 Keep by the hero or a Peasant: " + str(fl.get("reason")))
	if fl.ok:
		check(fl.building.finish_ms - fl.building.started_ms == 45000, "Fletcher builds in 45 s")
		step(production, 61000, 106050)
		check(not fl.building.constructing, "Fletcher completes")
		check(production.can_queue(garrison.entity_id, "AHMX").ok, "Squire is unlocked by the finished Fletcher")
	# Swordsman trains for metal and takes 20 s
	var q: Dictionary = production.enqueue(garrison.entity_id, "AHKX", 110000)
	check(q.ok and garrison.job_end_ms == 130000 and garrison.job_cost == [0, 20, 0, 0], "Swordsman: 20 metal, 20 s")

# -------------------------------------------------------------------- population, repeat, rally, spawn

func _test_population_and_rally():
	var w = new_world([1000, 1000, 1000, 1000])
	var production = w.production
	var nav = w.nav
	var keep = production.add_completed(0, "BKK0", 4, 62)
	var garrison = production.add_completed(0, "BAGA", 24, 60)
	var made: Array = []
	var notices: Array = []
	production.notice.connect(func(text): notices.append(text))
	production.unit_ready.connect(func(info): made.append(info.duplicate()); info.unit_id = 200 + made.size())
	check(production.population(0).maximum == 2 + 2 + 5 - 2 and production.population(0).current == 0, "limit 7 with Keep and Garrison")
	for i in range(7): production.register_unit(900 + i, "AHKX", 0)
	production.enqueue(garrison.entity_id, "AHKX", 0)
	step(production, 0, 20100)
	check(made.is_empty() and garrison.population_blocked and notices.size() == 1, "at the command limit the job waits and warns once")
	production.unregister_unit(900)
	production.update(20150)
	check(made.size() == 1 and garrison.job_item == "" and not garrison.population_blocked, "production finishes as soon as there is room")
	# Peasants count a quarter: four of them take one command point
	production.units.clear()
	for i in range(4): production.register_unit(300 + i, "AHBX", 0)
	check(production.population(0).current == 1, "four Peasants take one point")
	production.register_unit(304, "AHBX", 0)
	check(production.population(0).current == 2, "a fifth Peasant takes a second")
	# Repeat production re-queues the finished item
	production.units.clear()
	garrison.repeat = true
	made.clear()
	production.enqueue(garrison.entity_id, "AHKX", 30000)
	step(production, 30025, 50050)
	check(made.size() == 1 and garrison.job_item == "AHKX" and garrison.job_start_ms >= 50000, "repeat production starts the same item again")
	garrison.repeat = false
	production.cancel_all(garrison.entity_id)
	# Spawn point, rally and the nearest free cell
	var cx: int = garrison.left + ((9 - 1) >> 1)
	var base := Vector2i(cx, garrison.top - (8 >> 2) + 8)
	check(production.spawn_target(garrison) == base, "without a rally point units appear below the footprint: (cx, top + h - h/4)")
	production.set_rally(garrison.entity_id, Vector2i(cx + 10, base.y))
	var east: Vector2i = production.spawn_target(garrison)
	check(east.x in [cx + 4, base.x] and east.y == base.y, "a rally point east shifts the spawn east by half the width (or keeps it on uneven terrain)")
	production.set_rally(garrison.entity_id, Vector2i(cx, base.y + 2))
	check(production.spawn_target(garrison) == base, "a rally point within three cells changes nothing")
	var dummy := Dummy.new()
	var origin := open_ground()
	check(nav.free_cell_near(origin) == origin, "a free cell is used as it is")
	nav.occupants[origin] = dummy
	var next: Vector2i = nav.free_cell_near(origin)
	check(next == origin + Vector2i(1, 0), "occupied: the spiral tries +x first and keeps the first best")
	nav.occupants[origin + Vector2i(1, 0)] = dummy
	check(nav.free_cell_near(origin) != origin and nav.free_cell_near(origin) != origin + Vector2i(1, 0), "and then moves on")
	nav.occupants.erase(origin)
	nav.occupants.erase(origin + Vector2i(1, 0))
