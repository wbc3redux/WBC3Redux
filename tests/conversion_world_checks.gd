extends SceneTree
## Milestone 12: conversion in the real scene on Desert Sands (Knights vs Knights).
## 1. Human hero (the hero book's Knight) against a passive computer: the Convert order with nothing in reach shows [0065];
##    the hero walks to the nearest neutral mine and converts it; the Gnoll Lair and the Mausoleum are never targets; an
##    enemy Garrison with a queued Swordsman next to the hero converts through the Convert order (0x51cbb0(0)): the job is
##    refunded to the new owner and the queue dropped; moving cancels a running conversion; the human Keep converts the
##    mines within 28 cells after 150 s; a converted Keep's capacity moves; the results counters count the conversions.
## 2. A computer player: its hero converts a mine through its conversion group; with its hero dead its Keep starts a Keep
##    conversion within one 15 s pacing step (0x4fbb90).
## Never touches user://heroes (a fresh test directory).

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Placement = preload("res://simulation/placement.gd")
const Navigation = preload("res://battle/navigation.gd")
const MatchConversion = preload("res://simulation/match_conversion.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Conversion world check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var directory := "user://conversion-world-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	human_match(scene, store)
	if not OS.get_cmdline_user_args().has("--human-only"): computer_match(scene)
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures > 0:
		printerr("Conversion world checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Conversion world checks passed: %d" % checks)
	quit(0)

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

func hero_of(scene, owner: int):
	for unit in scene.units:
		if unit.owner_id == owner and scene.combat.fighters.has(unit.unit_id) and scene.combat.fighters[unit.unit_id].hero and not unit.dying: return unit
	return null

func setup_for(profile_id: String, computer_level: int) -> Dictionary:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	if profile_id != "":
		setup.players[0].kind = Setup.HUMAN
		setup.players[0].hero_id = profile_id
	else:
		Setup.set_kind(setup, 0, Setup.COMPUTER, 0)
	Setup.set_kind(setup, 1, Setup.COMPUTER, computer_level)
	return setup

## A finished building of `owner` on a free site near `cell` (test hook: stands in for one built earlier).
func building_near(scene, owner: int, code: String, cell: Vector2i, builder) -> Object:
	var definition: Dictionary = scene.production.rules.definition(code)
	for radius in range(2, 20):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var site := cell + Vector2i(dx, dy)
				if not Placement.check(scene.navigator, definition, site, builder).ok or not scene._clear_margin(definition, site): continue
				var at: Vector2i = Placement.anchor(definition, site)
				var b = scene.production.add_completed(owner, code, at.x, at.y)
				scene.add_marker(b)
				return b
	check(false, "a site for %s near %s" % [code, cell])
	return null

func nearest_mine(scene, cell: Vector2i, owner: int) -> int:
	var best := -1
	var best_d := 1 << 30
	for id in scene.mines.mines:
		if int(scene.mines.mines[id].entity.owner) == owner: continue
		var d: int = Navigation.chebyshev(scene.mines.mines[id].anchor, cell)
		if d < best_d:
			best_d = d
			best = id
	return best

func human_match(scene, store):
	var profile = Profile.create("test-converter", "Sir Turncoat")
	check(store.save_profile(profile), "test profile saved")
	check(scene.start_skirmish(setup_for("test-converter", 0), "test-converter", store, "conversion-match-1"), "Knights vs Knights match starts")
	var conversions = scene.conversions
	check(conversions != null, "MatchConversion is part of the match")
	var art = preload("res://core/art_data.gd")
	check(art.player_colour(0) == 1 and art.player_colour(1) == 0, "parity pass 4: Desert Sands' slot colours (0x708f9a: slot 0 blue, slot 1 red), not colour = player")
	var hero = hero_of(scene, 0)
	check(hero != null and scene.can_convert(hero), "the hero may convert (0x523af0)")
	var terms: Dictionary = scene.conversion_terms(hero)
	check(int(terms.seconds) == MatchConversion.duration_seconds(1 / 2 + 8) and int(terms.radius) == 11, "level-1 Charisma-6 hero: 39 s, radius 11 (%s)" % terms)
	advance(scene, 1.0)
	var hf = scene.combat.fighters[hero.unit_id]
	check(int(hf.get("max_mana", 0)) > 1 and int(hf.mana) == 1, "parity pass 4: the level-1 hero starts with min(max, level) = 1 mana (0x4a4560): %s / %s" % [hf.get("mana"), hf.get("max_mana")])
	var rate: int = preload("res://simulation/hero_effects.gd").mana_rate(scene.combat.hero_block(0))
	var mana_before: int = int(hf.mana)
	advance(scene, maxf(3.0, 2.0 * maxi(rate, 1000) / 1000.0 + 0.5))
	check(int(hf.mana) > mana_before, "parity pass 4: mana regenerates (0x51b6b0, rate %d ms): %d -> %d" % [rate, mana_before, int(hf.mana)])
	scene.update_order_marker()
	for u in scene.units: u.selected = u == hero
	scene.update_order_marker()
	check(hero.mana_level == preload("res://battle/unit_agent.gd").mana_level_of(int(hf.mana), int(hf.max_mana)), "parity pass 4: the selected hero's mana strip level (0x51b2c0)")
	# ---- Convert where the hero stands: a target in reach starts order 7 (Stop ends it), none shows [0065]
	for unit in scene.units: unit.selected = unit == hero
	var reach_now: Array = conversions.select(0, hero.cell, int(terms.radius))
	var started_now: bool = scene.convert_selected(0)
	if reach_now.is_empty():
		check(not started_now and scene.last_message.begins_with("There is nothing"), "Convert with nothing in reach: [0065] (%s)" % scene.last_message)
	else:
		check(started_now and conversions.converting(hero.unit_id), "Convert with %s in reach starts at once" % [reach_now.map(func(e): return e.original_type_id)])
		scene.stop_selected()
		advance(scene, 0.5)
		check(not conversions.converting(hero.unit_id), "Stop ends the conversion")
	# ---- the encounter buildings are never targets
	for id in [scene.mausoleum_id, scene.lair_id]:
		var b = scene.production.building(id)
		check(b != null and not conversions.eligible(0, b), "%s is not convertible (0x52da90: second letter)" % (b.original_type_id if b != null else "?"))
	for b in scene.production.buildings.values():
		if String(b.original_type_id).substr(0, 3) == "BWT": check(not conversions.eligible(0, b), "the tower %s is not convertible" % b.original_type_id)
	# ---- walk to the nearest neutral mine and convert it
	var mine_id: int = nearest_mine(scene, hero.cell, 0)
	check(scene.order_convert(hero, "mine", mine_id), "hero ordered to the mine")
	check(until(scene, func(): return scene.conversions.converting(hero.unit_id), 90.0), "the hero arrives and converts (order 7)")
	check(conversions.marked_buildings(0).has(mine_id), "parity pass 4: the mine is marked (+0x14a, 0x51cbb0) while the conversion runs")
	scene.update_order_marker()
	var mine_offset: int = int(scene.mines.mines[mine_id].source_offset)
	check(scene.map_objects.any(func(o): return o.is_building and int(o.get_meta("source_offset")) == mine_offset and o.marked), "parity pass 4: the mine's placement draws the target ring")
	var progress_seen: bool = false
	advance(scene, 10.0)
	progress_seen = conversions.unit_progress(hero.unit_id, scene.game_ms()) > 1
	check(progress_seen, "0x523dc0 progress rises")
	check(until(scene, func(): return int(scene.mines.mines[mine_id].entity.owner) == 0, 45.0), "the neutral mine is ours")
	check(not conversions.marked_buildings(0).has(mine_id), "parity pass 4: the marks clear when the job ends (0x520c90)")
	# Playtest 2026-11-11: an owned mine is a sight source like any building (0x546f00: sprite kind 3 with a player).
	var mine_sight: Vector2i = scene.mines.mines[mine_id].entity.cell() + Vector2i(0, (int(scene.mines.mines[mine_id].footprint.y) - 1) >> 1)
	check(scene.sight_sources().any(func(src): return int(src.player) == 0 and src.cell == mine_sight and int(src.extra) == 6), "the converted mine gives its owner sight (0x546f00)")
	check(int(scene.skirmish.stats[0].buildings_converted) >= 1, "results counter 0x744d78 counts the mine (event 0xb)")
	# ---- an enemy Garrison with a queued Swordsman within reach
	scene.economy.credit(1, [500, 500, 500, 500])
	var garrison = building_near(scene, 1, "BAGA", hero.cell + Vector2i(4, 0), hero)
	if garrison == null: return
	check(scene.production.enqueue(garrison.entity_id, "AHKX", scene.game_ms()).ok, "the enemy queues a Swordsman")
	for i in 4: scene.production.enqueue(garrison.entity_id, "AHKX", scene.game_ms())   # 100 s of Swordsmen: one still runs at the end
	# the state at the moment the owner changes (0x4a6cc0 sets +0xc before it calls 0x52d7e0)
	var at_change := {}
	var capture := func(_id, _before, _after):
		at_change.merge({"cost": garrison.job_cost.duplicate(), "job": garrison.job_item, "stock": scene.economy.resources(0).duplicate()})
	garrison.ownership_changed.connect(capture)
	hero.sync_cell()
	check(conversions.select(0, hero.cell, int(terms.radius)).has(garrison), "the Garrison is in reach (0x5489e0 footprint distance)")
	# moving cancels
	check(scene.order_convert_here(hero, 0), "Convert starts at once where the hero stands")
	for u in scene.units: u.selected = u == hero
	scene.effects.sync(scene)                                     # binds the conversion flash to this match's production
	scene.update_order_marker()
	check(preload("res://battle/unit_agent.gd").marker_unit == -1, "parity pass 4: no order-7 marker after Convert without Shift / Alt (0x49c150 follows moves only)")
	check(hero.convert_ms >= 0.0, "parity pass 3: the hero takes its conversion pose (slot 6 'c' sheet)")
	# parity pass 4: the pose repeats while order 7 runs (0x51e170 -> 0x5205d0 case 7 -> 0x536cc0), selected or not
	var frames: int = hero.convert_frames()
	if frames > 0:
		for u in scene.units: u.selected = false
		var cycle_s: float = frames * hero.CONVERT_FRAME_MS / 1000.0
		advance(scene, cycle_s + 0.25)
		scene.update_order_marker()
		check(conversions.converting(hero.unit_id) and hero.convert_cycle >= 1, "parity pass 4: the 'c' pose starts again after %.1f s (unselected hero)" % cycle_s)
		check(scene.effects.effects.any(func(e): return e.code == "EZ56"), "parity pass 4: each pose cycle starts EZ56 (0x536cc0)")
		check(hero.sprite == null or hero.sprite.texture == preload("res://core/art_data.gd").texture(preload("res://core/art_data.gd").unit_sheet(hero.art_type, 6).texture), "parity pass 4: the second cycle draws the 'c' sheet again")
		for u in scene.units: u.selected = u == hero
	var target: Vector2 = scene.navigator.center(scene.navigator.free_cell_near(hero.cell + Vector2i(-3, 0)))
	hero.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": hero.base_speed, "individual": true}, "replace")
	advance(scene, 0.5)
	check(not conversions.converting(hero.unit_id), "a move order ends the conversion (Conversion.cancel)")
	check(until(scene, func(): return hero.orders.is_empty() and not hero.in_step, 20.0), "the hero stops")
	hero.sync_cell()
	if not conversions.select(0, hero.cell, int(terms.radius)).has(garrison):
		check(false, "the Garrison left the reach after the move")
		return
	check(scene.order_convert_here(hero, 0), "Convert again")
	var finish: int = int(conversions.conversion.active[hero.unit_id].finish)
	check(finish - scene.game_ms() == int(terms.seconds) * 1000, "duration from the hero's terms")
	check(until(scene, func(): return int(garrison.owner) == 0, float(terms.seconds) + 2.0), "the enemy Garrison is ours")
	check(scene.effects.effects.any(func(e): return e.code == "EZ01"), "parity pass 3: EZ01 flashes on the converted Garrison (0x4a6cc0)")
	garrison.ownership_changed.disconnect(capture)
	check(garrison.job_item == "" and garrison.queue.is_empty(), "its job is cancelled and the queue dropped (0x52d7e0)")
	check(String(at_change.get("job", "")) == "AHKX", "a Swordsman was being trained when the Garrison changed owner")
	var refunded := not at_change.is_empty()
	for lane in 4:   # the new owner's stock grew by the running job's price (mine income may add more), unless capped
		var now_stock: int = int(scene.economy.resources(0)[lane])
		refunded = refunded and (now_stock >= int(at_change.stock[lane]) + int(at_change.cost[lane]) or now_stock == int(scene.economy.capacity(0)[lane]))
	check(refunded, "the refund goes to the new owner: %s + %s -> %s" % [at_change.get("stock"), at_change.get("cost"), scene.economy.resources(0)])
	check(int(scene.skirmish.stats[1].buildings_lost) >= 1 and int(scene.skirmish.stats[0].buildings_built) >= 2, "results counters (events 0 / 1)")
	# ---- the human Keep converts the mines within 28 cells (150 s)
	scene.economy.credit(0, [500, 500, 500, 500])
	var keep = building_near(scene, 0, "BKK0", hero.cell + Vector2i(0, 5), hero)
	if keep == null: return
	var in_reach: Array = conversions.select(0, keep.cell(), 28)
	check(not in_reach.is_empty(), "mines within 28 cells of the Keep")
	check(scene.keep_convert(keep), "the Keep's Convert button (0x52f9b0)")
	check(keep.keep_finish_ms - keep.keep_start_ms == 150000 and keep.keep_radius == 28, "human Keep: 28 cells, 150 s")
	check(not scene.production.can_queue(keep.entity_id, "AHBX").ok, "no Peasants while converting")
	scene.selected_building_id = keep.entity_id
	scene.cancel_job()
	check(not keep.keep_converting, "Cancel stops the Keep conversion (0x52fbc0)")
	check(scene.keep_convert(keep), "convert again")
	var keep_marks: Dictionary = conversions.keep_marked_buildings(0)
	check(not keep_marks.is_empty() and in_reach.all(func(e): return keep_marks.has(int(e.entity_id))) and not conversions.marked_buildings(0).has(int(in_reach[0].entity_id)),
		"Enhanced visuals ring the Keep's targets (modern); the original's marks (+0x14a) stay unit-only")
	check(until(scene, func(): return not keep.keep_converting, 152.0), "the Keep conversion completes")
	var converted_all: bool = true
	for e in in_reach: converted_all = converted_all and int(e.owner) == 0
	check(converted_all, "every target in reach is ours (%d)" % in_reach.size())
	scene.end_skirmish()

func computer_match(scene):
	check(scene.start_skirmish(setup_for("", 3), "", null, "conversion-match-2"), "computer Knights match starts")
	var ai_hero = hero_of(scene, 1)
	check(ai_hero != null, "the computer hero")
	# ---- the computer hero converts a mine (a building) through its conversion group
	var start_owned: int = scene.mines.census(1).filter(func(r): return r.owned).size()
	var got_mine: bool = until(scene, func(): return scene.mines.census(1).filter(func(r): return r.owned).size() > start_owned, 360.0)
	if not got_mine:
		for summary in scene.ai_summaries(): printerr("  ", summary)
	check(got_mine, "the computer hero converts a mine within 6 minutes")
	# ---- with its hero dead its Keep converts (0x4fbb90 -> 0x52f9b0)
	# 0x4fbc60 also needs no non-unit order at the head of the Keep's list: wait until the Keep upgrade (BKK1) is not running
	var keep_up: bool = until(scene, func(): return scene.production.buildings.values().any(func(b): return int(b.owner) == 1 and MatchConversion.is_keep(String(b.original_type_id)) and String(b.original_type_id) == "BKK1" and not b.constructing and not String(b.job_item).begins_with("B")), 600.0)
	check(keep_up, "the computer has upgraded its Keep (BKK1, the last Keep in its roster)")
	ai_hero = hero_of(scene, 1)
	if ai_hero != null: scene.combat.apply_damage("unit", ai_hero.unit_id, scene.combat.fighters[ai_hero.unit_id].hp + 1, -1)
	# 0x4fbc60 needs a mine of another owner within 32 cells: test hook, the computer's nearest mine turns neutral
	var their_keep = null
	for b in scene.production.buildings.values():
		if int(b.owner) == 1 and String(b.original_type_id) == "BKK1" and not b.constructing: their_keep = b
	var near_mine: int = -1
	var near_d := 1 << 30
	for id in scene.mines.mines:
		var d: int = Navigation.chebyshev(scene.mines.mines[id].entity.cell(), their_keep.cell()) if their_keep != null else 0
		if d < near_d:
			near_d = d
			near_mine = id
	if near_mine >= 0: scene.mines.mines[near_mine].entity.owner = 6
	check(near_d <= 20, "a mine near the computer's Keep (%d cells)" % near_d)
	# the dying hero stays in the object list until its corpse is removed (about 30 s), then one 15 s pacing step
	var started: bool = until(scene, func(): return scene.production.buildings.values().any(func(b): return int(b.owner) == 1 and b.keep_converting), 75.0)
	var by_player := {}
	for ai in scene.ai_manager.players.filter(func(p): return p != null and p.has_method("summary")): by_player[ai.me] = ai
	check(started or (by_player.has(1) and by_player[1].log.any(func(e): return e.has("keep_conversion"))), "the computer Keep starts a Keep conversion after its hero died")
	if not started:
		for b in scene.production.buildings.values():
			if int(b.owner) == 1 and MatchConversion.is_keep(String(b.original_type_id)):
				printerr("  keep ", b.original_type_id, " job ", b.job_item, " queue ", b.queue, " mines ", scene.ai_keep_has_mines(b, 1), " reach ", scene.conversions.select(1, b.cell(), 32).size())
		printerr("  units ", scene.units.filter(func(u): return u.owner_id == 1 and not u.removed).map(func(u): return [u.type_id, u.dying, scene.can_convert(u)]))
	for b in scene.production.buildings.values():
		if int(b.owner) == 1 and b.keep_converting:
			check(b.keep_radius == 32 and b.keep_finish_ms - b.keep_start_ms == 120000, "computer Keep: 32 cells, 120 s")
