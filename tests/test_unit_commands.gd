extends SceneTree
## Unit commands (PARITY_BACKLOG.md "Unit commands", UI_RESEARCH.md "Unit commands (Read)"):
## 1. the rules of simulation/unit_commands.gd: the wall lattice and segment limit (0x429820), the segment variants
##    (0x4299b0), the repair tick (0x52ebc0), who may garrison (0x51c240) and which buildings take a garrison (0x5877a0);
## 2. attack-move in a combat world: a plain move walks past an enemy (0x507560 blocks the Defensive rule), an attack-move
##    fights it and walks on (0x51da60 inserts the script attack before the move); script moves over an attack-move;
## 3. the real scene on Desert Sands (Knights vs a passive computer): the Attack-mode ground click, a dragged wall run built
##    segment by segment, a tower garrison with its limit of four and Unload, the building repair over 45 s.
## Never touches user://heroes (a fresh test directory).

const UnitCommands = preload("res://simulation/unit_commands.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const Economy = preload("res://simulation/economy.gd")
const Production = preload("res://simulation/production.gd")
const Placement = preload("res://simulation/placement.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Combat = preload("res://simulation/combat.gd")
const Rng = preload("res://simulation/combat_rng.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const Visibility = preload("res://simulation/visibility.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Unit command check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	wall_rules()
	repair_rules()
	garrison_rules()
	attack_move_world()
	var directory := "user://unit-command-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene_commands(scene, store)
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	for u in world.get("units", []):
		if is_instance_valid(u): u.free()
	if failures > 0:
		printerr("Unit command checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Unit command checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ 1. rules
func wall_rules():
	var any := func(_type, _cell): return true
	var size := Vector2i(100, 100)
	var drag = UnitCommands.WallDrag.new("BWG0", Vector2i(10, 20))
	check(drag.segments.size() == 1 and drag.segments[0].cell == Vector2i(10, 20), "the press puts the clicked cell in (0x422e49)")
	check(drag.add(Vector2i(13, 21), size, any) and drag.segments[1].cell == Vector2i(12, 20), "even start: x / 2 * 2 (13, 21) -> (12, 20)")
	check(not drag.add(Vector2i(11, 21), size, any), "(11, 21) snaps onto the start cell: a duplicate")
	check(not drag.add(Vector2i(-1, 3), size, any) and not drag.add(Vector2i(100, 3), size, any), "cells off the map are refused")
	check(not drag.add(Vector2i(20, 20), size, func(_t, _c): return false), "a cell that fails the site test (0x4352f0) is refused")
	var odd = UnitCommands.WallDrag.new("BWE0", Vector2i(11, 21))
	check(odd.add(Vector2i(14, 24), size, any) and odd.segments[1].cell == Vector2i(13, 23), "odd start: ((v + 1) / 2) * 2 - 1 (14, 24) -> (13, 23)")
	check(not odd.add(Vector2i(0, 25), size, any), "odd lattice: x 0 is refused (0x429820 needs x > 0)")
	var long = UnitCommands.WallDrag.new("BWG0", Vector2i(0, 0))
	for k in range(1, 80): long.add(Vector2i(2 * k, 0), Vector2i(400, 10), any)
	check(long.segments.size() == UnitCommands.MAX_SEGMENTS, "at most 0x40 segments (%d)" % long.segments.size())
	# 0x4299b0 variants
	var row := [{"type": "BWG0", "cell": Vector2i(10, 10)}, {"type": "BWG0", "cell": Vector2i(12, 10)}, {"type": "BWG0", "cell": Vector2i(14, 10)}]
	UnitCommands.pick_variants(row)
	check(row.map(func(s): return s.type) == ["BWG0", "BWG1", "BWG0"], "a row: the middle is the 2x1 piece, the ends 2x2 (%s)" % [row.map(func(s): return s.type)])
	var column := [{"type": "BWE0", "cell": Vector2i(10, 10)}, {"type": "BWE0", "cell": Vector2i(10, 12)}, {"type": "BWE0", "cell": Vector2i(10, 14)}]
	UnitCommands.pick_variants(column)
	check(column.map(func(s): return s.type) == ["BWE0", "BWE2", "BWE0"], "a column: the middle is the 1x2 piece, in the armed family (%s)" % [column.map(func(s): return s.type)])
	var corner := [{"type": "BWG0", "cell": Vector2i(10, 10)}, {"type": "BWG0", "cell": Vector2i(12, 10)}, {"type": "BWG0", "cell": Vector2i(12, 12)}]
	UnitCommands.pick_variants(corner)
	check(corner[1].type == "BWG0", "a corner stays the 2x2 piece")
	var single := [{"type": "BWG1", "cell": Vector2i(10, 10)}]
	UnitCommands.pick_variants(single)
	check(single[0].type == "BWG1", "one segment keeps the armed type (0x4299b0 needs two)")
	check(UnitCommands.is_wall("BWN2") and not UnitCommands.is_wall("BWRA") and not UnitCommands.is_wall("BWTC"), "the nine wall types of 0x422e00")

class FakeBuilding:
	var entity_id := 7
	var constructing := false
	var hit_points := 100
	var max_hit_points := 400

func repair_rules():
	var r := {"start": 0, "end": 45000, "amount": 300, "done": 0}
	var out: Dictionary = UnitCommands.repair_step(r, 100, 400, 1000)
	check(int(out.hp) == 106 and out.active, "1 s of 45: 1000 * 100 / 45000 = 2 percent, 300 * 2 / 100 = 6 (%s)" % out)
	out = UnitCommands.repair_step(r, int(out.hp), 400, 22500)
	check(int(out.hp) == 250 and int(r.done) == 150 and out.active, "half time: half the amount (%s)" % out)
	out = UnitCommands.repair_step(r, int(out.hp), 400, 45000)
	check(int(out.hp) == 400 and not out.active, "100 percent: done (%s)" % out)
	out = UnitCommands.repair_step({"start": 0, "end": 45000, "amount": 300, "done": 0}, 390, 400, 22500)
	check(int(out.hp) == 400 and not out.active, "clamped to the maximum and ended")
	check(not UnitCommands.repair_step({"start": 0, "end": 45000, "amount": 1, "done": 0}, 400, 400, 1000).active, "already full: ends (0x52ebc0)")
	var commands = UnitCommands.new()
	var b := FakeBuilding.new()
	check(commands.start_repair(b, 5000) and commands.repairs[7].amount == 300 and commands.repairs[7].end == 50000, "start: the missing 300 over 45 s (0x4fffe0's message)")
	b.hit_points = 400
	check(not commands.start_repair(b, 5000), "0x52eb10: nothing to repair at full hit points")
	b.hit_points = 10
	b.constructing = true
	check(not commands.start_repair(b, 5000), "an unfinished building is not repaired")

func garrison_rules():
	check(UnitCommands.can_garrison("AHKX", [1, 1], false, false, false), "a Swordsman may garrison")
	check(not UnitCommands.can_garrison("AHBX", [1, 1], true, false, false), "a Peasant (builder) may not (0x51c240)")
	check(UnitCommands.can_garrison("AHHX", [1, 1], true, true, false), "the hero builds but may garrison")
	check(not UnitCommands.can_garrison("AHDX", [2, 2], false, false, false), "a two-cell unit may not")
	check(not UnitCommands.can_garrison("ACSO", [1, 1], false, false, true) and not UnitCommands.can_garrison("AAEY", [1, 1], false, false, false), "animals and AAEY may not")
	var rules := ProductionRules.new()
	check(int(rules.definition("BWTC").garrison) == 4 and int(rules.definition("BWTD").garrison) == 4, "towers carry the garrison digit 4 (Building.cfg +0x7c)")
	check(int(rules.definition("BKK0").garrison) == 0 and int(rules.definition("BAGA").garrison) == 0 and int(rules.definition("BWG0").garrison) == 0, "Keep, Garrison and walls take none")

# ------------------------------------------------------------------------------------------------ 2. attack-move
var world: Dictionary = {}
var collision = CollisionData.new()

func open_ground() -> Vector2i:
	for y in range(30, 110):
		for x in range(30, 100):
			var flat := true
			for dx in range(-11, 12):
				for dy in range(-5, 6):
					var c: Dictionary = collision.cell_data(Vector2i(x + dx, y + dy))
					if not c.profile_passable[0] or not c.object_indices.is_empty() or int(c.raw[0]) != int(collision.cell_data(Vector2i(x, y)).raw[0]): flat = false
			if flat: return Vector2i(x, y)
	return Vector2i(-1, -1)

func new_world():
	for u in world.get("units", []):
		if is_instance_valid(u): u.free()
	var nav = Navigation.new(collision)
	var economy = Economy.new(0)
	economy.add_player(0, [500, 500, 500, 500])
	economy.add_player(1, [500, 500, 500, 500])
	var production = Production.new(ProductionRules.new(), economy, nav)
	var units: Array = []
	var combat = Combat.new(Rng.new(0x1badb002, 0x2468ace0), nav, production, units)
	world = {"nav": nav, "production": production, "units": units, "combat": combat, "ms": 0}

func add_world_unit(type_id: String, cell: Vector2i, owner: int) -> int:
	var unit = UnitAgent.new()
	unit.unit_id = world.units.size()
	unit.type_id = type_id
	unit.owner_id = owner
	unit.base_speed = int(world.production.rules.definition(type_id).base_speed)
	unit.navigator = world.nav
	unit.position = world.nav.center(cell)
	root.add_child(unit)
	world.units.append(unit)
	unit.sync_cell()
	world.combat.register(unit.unit_id, owner, type_id, CombatRules.unit_stats(world.production.rules.definition(type_id).raw_hex), false)
	return unit.unit_id

func world_move(id: int, cell: Vector2i, attack_move: bool):
	var unit = world.units[id]
	var move := {"kind": "move", "target": world.nav.center(cell), "requested": world.nav.center(cell), "group": 0, "speed": unit.base_speed, "individual": true}
	if attack_move: move["attack_move"] = true
	world.combat.order_stop(id)
	unit.give_order(move, "replace")
	world.combat.note_move(id, cell, move)

## Steps the world; `watch` is called every update and returns true to stop.
func run_world(limit_ms: int, watch: Callable):
	var end: int = int(world.ms) + limit_ms
	while int(world.ms) < end:
		world.ms = int(world.ms) + 25
		for unit in world.units: unit.advance(0.025)
		world.combat.update(int(world.ms))
		if watch.call(): return

func attack_move_world():
	var open := open_ground()
	check(open.x >= 0, "open ground for the attack-move world")
	if open.x < 0: return
	var start := open + Vector2i(-9, 0)
	var goal := open + Vector2i(9, 0)
	# A plain move: the Defensive rule (enemy near -> attack near, no +0x75) may not interrupt a +0x1c = 0 move.
	new_world()
	var walker := add_world_unit("AHKX", start, 0)
	var enemy := add_world_unit("AHKX", open + Vector2i(0, 2), 1)
	world.combat.fighters[enemy].script = -1          # a passive target: it never acts
	world_move(walker, goal, false)
	var fought := [false]
	run_world(30000, func():
		if world.combat.fighters[walker].order != null: fought[0] = true
		return world.units[walker].orders.is_empty() and not world.units[walker].in_step)
	check(not fought[0] and int(world.combat.fighters[enemy].hp) == int(world.combat.fighters[enemy].max_hp), "a plain move walks past the enemy (0x507560)")
	check(Navigation.chebyshev(world.units[walker].cell, goal) <= 1, "the plain move arrives (%s, goal %s)" % [world.units[walker].cell, goal])
	# The same walk as an attack-move: the rule fires on the way; the script attack is inserted and the walk resumes.
	new_world()
	walker = add_world_unit("AHKX", start, 0)
	enemy = add_world_unit("AHKX", open + Vector2i(0, 2), 1)
	world.combat.fighters[enemy].script = -1
	world_move(walker, goal, true)
	var f = world.combat.fighters[walker]
	check(f.cur.ai and f.cur.has("attack_move"), "the attack-move is the scripts' interruptible order (+0x1c = 1)")
	var attacked := [false, false]                    # attacked the enemy, kept the attack-move behind the attack
	run_world(90000, func():
		if f.order != null and int(f.order.target_id) == enemy:
			attacked[0] = true
			if f.resume != null and f.resume.has("attack_move"): attacked[1] = true
		return attacked[0] and not world.combat.alive(world.combat.fighters[enemy]) and f.order == null and world.units[walker].orders.is_empty() and not world.units[walker].in_step and f.resume == null)
	check(attacked[0], "the attack-move attacks the enemy on the way (attack near)")
	check(attacked[1], "the attack-move waits behind the script attack (0x51da60 inserts it)")
	check(not world.combat.alive(world.combat.fighters[enemy]), "the enemy is killed")
	check(Navigation.chebyshev(world.units[walker].cell, goal) <= 1, "after the fight the walk resumes to the goal (%s, goal %s)" % [world.units[walker].cell, goal])
	# Script moves over an attack-move (0x51d6b0): none to the unit's own guard point; another goal is inserted.
	new_world()
	walker = add_world_unit("AHKX", start, 0)
	world_move(walker, goal, true)
	f = world.combat.fighters[walker]
	var before = f.cur
	world.combat.ai.move(f, f.guard, true)
	check(f.cur == before and f.resume == null, "Return to Post on the way does nothing (the guard point walks with the unit)")
	world.combat.ai.move(f, start + Vector2i(0, 3), true)
	check(f.resume == before and f.cur.kind == "move" and not f.cur.has("attack_move"), "another script move is inserted before the attack-move")
	world.combat.note_move(walker, goal, {})
	check(f.resume == null, "a player order drops the waiting attack-move")

# ------------------------------------------------------------------------------------------------ 3. the scene
func advance(scene, seconds: float):
	for i in roundi(seconds * 60.0):
		if scene.skirmish != null and scene.skirmish.over: return
		scene.simulation_step(1.0 / 60.0)

func until(scene, condition: Callable, limit_s: float) -> bool:
	var waited := 0.0
	while not condition.call() and waited < limit_s:
		advance(scene, 0.5)
		waited += 0.5
	return condition.call()

func top_up(scene):
	scene.economy.refresh_capacity(0)
	scene.economy.stockpiles[0] = scene.economy.capacity(0).duplicate()

func hero_of(scene):
	for unit in scene.units:
		if unit.owner_id == 0 and scene.combat.fighters.has(unit.unit_id) and scene.combat.fighters[unit.unit_id].hero and not unit.dying: return unit
	return null

func building_near(scene, owner: int, code: String, cell: Vector2i) -> Object:
	var definition: Dictionary = scene.production.rules.definition(code)
	for radius in range(2, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var site := cell + Vector2i(dx, dy)
				if not Placement.check(scene.navigator, definition, site, null).ok or not scene._clear_margin(definition, site): continue
				var at: Vector2i = Placement.anchor(definition, site)
				var b = scene.production.add_completed(owner, code, at.x, at.y)
				scene.add_marker(b)
				return b
	check(false, "a site for %s near %s" % [code, cell])
	return null

func select(scene, chosen: Array):
	for u in scene.units: u.selected = chosen.has(u)

func scene_commands(scene, store):
	var profile = Profile.create("test-commander", "Sir Orders")
	check(store.save_profile(profile), "test profile saved")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-commander"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	check(scene.start_skirmish(setup, "test-commander", store, "unit-commands-1"), "Knights vs Knights match starts")
	var hero = hero_of(scene)
	check(hero != null, "the human hero exists")
	if hero == null: return
	var no_mods := {"shift": false, "ctrl": false, "alt": false}
	# ---- Attack mode on the ground (0x422836): an attack-move, unless the modern rules replace it
	var soldiers: Array = []
	for k in 5:
		var cell: Vector2i = scene.navigator.free_cell_near(hero.cell + Vector2i(2 + k, 3))
		soldiers.append(scene.add_unit("AHKX", cell, 0))
	select(scene, [soldiers[0]])
	scene.target_mode = 2
	scene.target_click(scene.navigator.center(soldiers[0].cell + Vector2i(0, 6)), no_mods)
	var cur = scene.combat.fighters[soldiers[0].unit_id].cur
	if scene.navigator.improved: check(scene.attack_moves.has(soldiers[0].unit_id), "modern rules: the F3 attack-move")
	else: check(cur != null and cur.has("attack_move") and cur.ai, "Attack mode, ground click: an attack-move order (commands 0x1a / 0x39)")
	check(scene.target_mode == 0, "the target mode ends after the click")
	scene.stop_selected()
	# ---- a tower garrison: four of five Swordsmen go in, the Peasant may not, Unload brings them out
	var tower = building_near(scene, 0, "BWTC", hero.cell + Vector2i(4, -6))
	if tower == null: return
	var peasant = scene.add_unit("AHBX", scene.navigator.free_cell_near(hero.cell + Vector2i(-3, 2)), 0)
	scene.production.register_unit(peasant.unit_id, "AHBX", 0)
	var inside_point: Vector2 = scene.navigator.center(tower.cell_rect().get_center())
	check(scene.can_garrison_into(soldiers[0], {"kind": "building", "object": tower}), "the cursor offers the tower to a Swordsman (cursor 13)")
	check(not scene.can_garrison_into(peasant, {"kind": "building", "object": tower}), "not to a Peasant (0x51c240)")
	select(scene, [peasant])
	scene.right_click(inside_point, no_mods)
	check(not scene.unit_commands.garrison_orders.has(peasant.unit_id), "a Peasant's right-click on the tower is a move")
	select(scene, soldiers)
	scene.right_click(inside_point, no_mods)
	check(scene.unit_commands.garrison_orders.size() == 5, "five Swordsmen ordered into the tower (commands 0x2a, order 0x12)")
	check(until(scene, func(): return scene.unit_commands.garrison_orders.is_empty(), 40.0), "the garrison walks end")
	var inside: Array = scene.unit_commands.occupants(tower.entity_id)
	check(inside.size() == 4, "four enter (0x52db10: +0xca < 4): %d" % inside.size())
	var outside: Array = soldiers.filter(func(u): return not inside.has(u.unit_id))
	check(outside.size() == 1 and not outside[0].inside_building and outside[0].visible, "the fifth stays outside")
	check(inside.all(func(id): return scene.units[id].inside_building and not scene.units[id].visible), "the occupants are hidden")
	check(not scene.unit_commands.can_take(tower, scene.production.rules), "a full tower takes no more")
	scene.selected_building_id = tower.entity_id
	var cells: Array = scene.hud.building_cells(tower) if scene.hud != null else []
	check(cells.is_empty() or (not cells[5].is_empty() and int(cells[5].get("id", cells[5].get("icon", -1))) == 0x20), "the tower's grid shows Unload (icon 0x20)")
	check(scene.unload_building(tower) == 4, "Unload releases all four (message 0x20b)")
	check(inside.all(func(id): return not scene.units[id].inside_building and scene.units[id].visible), "they are back on the map")
	check(scene.unit_commands.occupants(tower.entity_id).is_empty(), "the tower is empty")
	# ---- repair: the missing hit points over 45 s
	tower.hit_points = maxi(1, tower.max_hit_points - 300)
	var start_hp: int = tower.hit_points
	var amount: int = tower.max_hit_points - start_hp
	cells = scene.hud.building_cells(tower) if scene.hud != null else []
	check(cells.is_empty() or (not cells[6].is_empty() and int(cells[6].get("id", cells[6].get("icon", -1))) == 0x11 and cells[6].enabled), "a damaged building's grid shows Repair enabled (icon 0x11)")
	check(scene.repair_building(tower), "Repair starts (message 0x112)")
	cells = scene.hud.building_cells(tower) if scene.hud != null else []
	check(cells.is_empty() or not cells[6].enabled, "Repair is disabled while it runs")
	advance(scene, 22.5)
	var expected: int = start_hp + amount * 50 / 100
	check(absi(tower.hit_points - expected) <= amount / 20 + 1, "half way: %d (expected about %d)" % [tower.hit_points, expected])
	advance(scene, 23.0)
	check(tower.hit_points == tower.max_hit_points and not scene.unit_commands.repairing(tower.entity_id), "after 45 s: full (%d / %d)" % [tower.hit_points, tower.max_hit_points])
	# ---- a dragged wall run: four segments on the lattice, built one after another
	top_up(scene)
	select(scene, [peasant])
	var start := Vector2i(-1, -1)
	for radius in range(4, 20):
		for dx in range(-radius, radius + 1):
			var c: Vector2i = peasant.cell + Vector2i(dx, radius)
			var clear := true
			for k in range(0, 8):
				if not scene.wall_site_ok("BWG0", c + Vector2i(k, 0)) or not scene._clear_margin(scene.production.rules.definition("BWG0"), c + Vector2i(k, 0)): clear = false
			if clear:
				start = c
				break
		if start.x >= 0: break
	check(start.x >= 0, "an open row for the wall")
	if start.x < 0: return
	scene.build_mode = "BWG0"
	scene.wall_drag = UnitCommands.WallDrag.new("BWG0", start)
	for k in range(1, 8): scene.wall_drag.add(start + Vector2i(k, 0), Vector2i(scene.collision.width, scene.collision.height), scene.wall_site_ok)
	var planned: Array = scene.wall_drag.segments.map(func(s): return s.type)
	check(planned.size() == 4 and planned == ["BWG0", "BWG1", "BWG1", "BWG0"], "the drag makes four segments: ends 2x2, middle 2x1 (%s)" % [planned])
	scene.finish_wall_drag()
	check(scene.build_mode == "" and scene.wall_drag == null, "the release ends the placement mode")
	check(scene.pending_builds.has(peasant.unit_id) and scene.unit_commands.wall_queues.get(peasant.unit_id, []).size() == 3, "the first segment replaces the Peasant's orders, three are appended")
	var walls := func(): return scene.production.buildings.values().filter(func(b): return String(b.original_type_id).begins_with("BWG") and int(b.owner) == 0)
	check(until(scene, func():
		top_up(scene)
		return walls.call().size() == 4 and walls.call().all(func(b): return not b.constructing), 400.0), "all four segments are built (%d)" % walls.call().size())
	var built: Array = walls.call().map(func(b): return String(b.original_type_id))
	built.sort()
	check(built == ["BWG0", "BWG0", "BWG1", "BWG1"], "the built pieces are the planned variants (%s)" % [built])
	check(not scene.unit_commands.wall_queues.has(peasant.unit_id), "the Peasant's wall run is done")
