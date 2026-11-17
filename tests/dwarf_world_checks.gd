extends SceneTree
## Milestone 11a: the Dwarves (race 1) through the same code paths as the Knights, in the real scene on Desert Sands.
## 1. A human Dwarf side (a Knight hero leading Dwarves) against a passive computer: the hero builds the Citadel and the
##    Foundry, the Foundry trains a Smith (the Dwarven builder), the Smith builds an Armory faster (builder power 13), the
##    Armory trains Runners, the Foundry researches PWE0 and trains a 2x2 Ballista that walks with its own extent, and Dwarf
##    infantry kill the enemy hero for a Standard Victory.
## 2. The setup's default (the map's races: Dwarf vs The Swarm) with computer players: each side's hero is its race's hero
##    (0x42a0d0), its creation record comes from its race, and both computer players start building their own halls.
## Never touches user://heroes (a fresh test directory).

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Rules = preload("res://simulation/production_rules.gd")
const Navigation = preload("res://battle/navigation.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Dwarf world check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var directory := "user://dwarf-world-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	human_dwarves(scene, store)
	computer_races(scene)
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures > 0:
		printerr("Dwarf world checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Dwarf world checks passed: %d" % checks)
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
		if unit.owner_id == owner and scene.combat.fighters.has(unit.unit_id) and scene.combat.fighters[unit.unit_id].hero: return unit
	return null

func building_of(scene, owner: int, code: String):
	for b in scene.production.buildings.values():
		if int(b.owner) == owner and b.original_type_id == code: return b
	return null

func units_of(scene, owner: int, code: String) -> Array:
	return scene.units.filter(func(u): return u.owner_id == owner and u.type_id == code and not u.removed and not u.dying)

## The click box follows the drawn frame: the centre of the hero's opaque pixels picks the hero (the mounted hero's art
## sits well above its ground cell, outside the old fixed box).
func pick_checks(scene, hero):
	var Selection = load("res://battle/selection.gd")
	check(hero.sprite != null and hero.sprite.texture != null, "the hero draws its imported sheet")
	if hero.sprite == null or hero.sprite.texture == null: return
	var used: Rect2 = hero.opaque_bounds(hero.sprite.texture, hero.sprite.region_rect)
	check(used.has_area(), "the hero frame has opaque pixels")
	var drawn := Rect2(hero.position + hero.sprite.offset + used.position, used.size)
	check(hero.hit_rect().encloses(drawn), "the hit box covers the drawn hero")
	check(Selection.hit(scene.units, drawn.get_center()) == hero, "a click on the drawn hero picks it")
	check(Selection.hit(scene.units, drawn.position + Vector2(2, 2)) == hero, "a click near the frame's top corner picks it")

## The builder walks to a site the computer player's site rule finds, then the building runs until finished.
## AI-10: the site rule (0x4f9480 / 0x435320, AI-7) has no fog, and its spot may lie outside the human hero's sight, where
## the local side may not place; fog and shroud are off from the search until the building stands (as batch2_world_base.gd).
func build(scene, builder, code: String) -> Object:
	var fog: bool = scene.visibility.fog
	var shroud: bool = scene.visibility.shroud
	scene.visibility.fog = false
	scene.visibility.shroud = false
	var site: Vector2i = scene.ai_site(0, code, Vector2i(12, 64), builder)
	check(site.x >= 0, "a site for %s" % code)
	check(scene.ai_build(builder, code, site), "%s ordered" % code)
	check(until(scene, func(): return building_of(scene, 0, code) != null, 60.0), "%s placed" % code)
	scene.visibility.fog = fog
	scene.visibility.shroud = shroud
	return building_of(scene, 0, code)

func human_dwarves(scene, store):
	var profile = Profile.create("test-dwarf-lord", "Sir Stonebeard")
	check(store.save_profile(profile), "copied test profile saved")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	check(int(setup.players[0].race) == Rules.DWARF and int(setup.players[1].race) == Rules.SWARM, "the setup defaults to the map's races")
	Setup.set_race(setup, 1, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-dwarf-lord"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)          # Passive: this match tests the Dwarven side, not the AI
	check(scene.start_skirmish(setup, "test-dwarf-lord", store, "dwarf-match-1"), "Dwarf match starts")
	var production = scene.production
	check(production.race_of(0) == Rules.DWARF and production.race_of(1) == Rules.KNIGHT, "player races (0x708f96)")
	var hero = hero_of(scene, 0)
	check(hero != null and hero.type_id == "AHHX", "the hero book's Knight leads the Dwarves")
	check(production.construction_menu(0) == ["BKD0", "BAAR", "BPFO", "BPWS", "BPTP", "BWMO", "BPBR", "BAV0", "BPCL"], "Dwarven D0 construction row")
	check(not production.can_place(0, "BAGA", hero.cell, hero).ok, "the Knights' Garrison is not in the Dwarves' list")
	advance(scene, 1.0)                                   # the first fog sweeps (the local player places on explored, visible cells)
	pick_checks(scene, hero)
	scene.economy.credit(0, [2000, 2000, 2000, 2000])     # test hook: enough stock for the whole sequence
	scene.economy.refresh_capacity(0)
	# ---- the hero builds the Citadel (100 gold + 100 stone, 60 s) and then the Foundry
	var before: Array = scene.economy.resources(0).duplicate()
	var citadel = build(scene, hero, "BKD0")
	check(citadel != null and citadel.constructing, "Citadel under construction")
	if citadel == null: return                            # AI-10: nothing below can run without it (was a SCRIPT ERROR)
	var paid := [int(before[0]) - int(scene.economy.resources(0)[0]), 0, 0, int(before[3]) - int(scene.economy.resources(0)[3])]
	check(paid == production.price_of(0, "BKD0") and int(paid[0]) <= 100 and int(paid[0]) >= 90, "Citadel price 0x40b6b0 (100 gold + 100 stone less the hero's price modifier 0x526cf0) charged at placement: %s" % [paid])
	check(citadel.finish_ms - citadel.started_ms == 60000, "Citadel 60 s with the hero (builder speed 10)")
	check(until(scene, func(): return not citadel.constructing, 70.0), "Citadel completed")
	check(production.population(0).maximum >= 5, "the Citadel is a main hall (command table 0x5325d0)")
	check(production.menu_for(citadel).map(func(m): return m.id) == ["BKD1", "PMSG"], "the Citadel trains nothing (upgrade, research)")
	check(until(scene, func(): return not hero.inside_building, 5.0), "hero released")
	var foundry = build(scene, hero, "BPFO")
	if foundry == null: return
	check(until(scene, func(): return not foundry.constructing, 45.0), "Foundry completed")
	check(until(scene, func(): return not hero.inside_building, 5.0), "hero released again")
	# ---- the Foundry trains the Smith (40 metal + 40 stone, 35 s)
	check(production.enqueue(foundry.entity_id, "ADBX", scene.game_ms()).ok, "Smith queued at the Foundry")
	check(foundry.job_end_ms - foundry.job_start_ms == 35000, "Smith 35 s")
	check(until(scene, func(): return not units_of(scene, 0, "ADBX").is_empty(), 40.0), "Smith trained")
	var smith = units_of(scene, 0, "ADBX")[0]
	check(production.population(0).current == 1, "the Smith costs its ARM +0xc8 (no quarter rule for Dwarves)")
	check(scene.is_builder(smith) and production.rules.can_mine(smith.type_id), "the Smith builds and can work mines (0x523e10 / 0x523e70)")
	# ---- the Smith builds the Armory in 21 s instead of 30 (ARM +0x6c = 13)
	var armory = build(scene, smith, "BAAR")
	if armory == null: return
	check(armory.finish_ms - armory.started_ms == 21000, "Armory 21 s with the Smith (0x40b6b0 builder speed)")
	check(until(scene, func(): return not armory.constructing, 30.0), "Armory completed")
	# ---- the Armory trains Runners; the Foundry researches PWE0 and trains a Ballista
	for i in 2: check(production.enqueue(armory.entity_id, "ADSX", scene.game_ms()).ok, "Runner %d queued" % i)
	check(production.enqueue(foundry.entity_id, "PWE0", scene.game_ms()).ok, "research PWE0 queued")
	check(not production.can_queue(foundry.entity_id, "PWE0").ok, "the same research cannot be ordered twice (0x569200 code 5)")
	check(not production.can_queue(foundry.entity_id, "PWE1").ok, "PWE1 needs PWE0 first (0x5690b0)")
	check(production.enqueue(foundry.entity_id, "ADNX", scene.game_ms()).ok, "Ballista queued after the research")
	check(until(scene, func(): return production.research_level(0, "PWE0") == 1, 70.0), "PWE0 researched (0x436500)")
	var pwe1: Dictionary = production.can_queue(foundry.entity_id, "PWE1")
	check(production.research.get(0, []) == ["PWE0"] and not String(pwe1.reason).begins_with("requires"), "PWE1 no longer waits for PWE0: %s" % pwe1)
	check(units_of(scene, 0, "ADSX").size() == 2, "two Runners trained")
	check(until(scene, func(): return not units_of(scene, 0, "ADNX").is_empty(), 110.0), "Ballista trained")
	var ballista = units_of(scene, 0, "ADNX")[0]
	check(scene.navigator.enterable_extent(ballista.cell, 2), "the Ballista appears on a cell its extent may stand on (0x530a90 with ARM +0x39): %s" % ballista.cell)
	check(ballista.extent == 2, "the Ballista is a 2x2 unit (ARM +0x38)")
	var held: int = Navigation.footprint(ballista.cell, 2).filter(func(c): return scene.navigator.occupant(c) == ballista).size()
	check(held == 4, "it holds its four cells (0x51bb80)")
	check(production.population(0).current == 1 + 2 + 4, "Ballista command cost 4")
	var goal := Vector2i(30, 72)
	var plan: Dictionary = scene.navigator.route_cells(ballista.cell, goal, 2)
	check(plan.ok and plan.target == goal, "an extent-2 route from the Foundry to %s" % goal)
	var target: Vector2 = scene.navigator.center(goal)
	ballista.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": ballista.base_speed, "individual": true}, "replace")
	scene.combat.note_move(ballista.unit_id, goal)        # a player order: the attitude script keeps the new guard point
	check(until(scene, func(): return ballista.orders.is_empty() and not ballista.in_step, 90.0), "the Ballista arrives (%s)" % ballista.last_error)
	check(Navigation.chebyshev(ballista.cell, goal) <= 2 and scene.navigator.enterable_extent(ballista.cell, 2), "on a cell its extent may stand on: %s" % ballista.cell)
	# ---- fight and win: Dwarf infantry next to the computer's hero (test hook as in test_skirmish.gd)
	var theirs = hero_of(scene, 1)
	var m = scene.skirmish
	for i in 30: scene.add_unit("ADIX", scene.navigator.free_cell_near(theirs.cell + Vector2i(-3 - i / 8, (i % 8) - 4)), 0)
	for unit in scene.units: unit.selected = unit.owner_id == 0 and unit.type_id == "ADIX"
	var hp_before: int = int(scene.combat.fighters[theirs.unit_id].hp)
	scene.issue_attack({"kind": "unit", "id": theirs.unit_id})
	advance(scene, 6.0)
	check(int(scene.combat.fighters[theirs.unit_id].hp) < hp_before, "Dwarf Infantry wound the enemy hero")
	var waited := 0.0
	while not m.over and waited < 240.0:
		advance(scene, 1.0)
		waited += 1.0
	check(m.over and m.outcome.won and m.outcome.reason == "standard", "Standard Victory for the Dwarves: %s" % m.outcome)
	check(m.stats[0].troops_built >= 4 and m.stats[0].buildings_built >= 3, "results counters: %s" % m.stats[0])
	check(scene.accept_results(), "results accepted")
	var stored = store.load_profile("test-dwarf-lord")
	check(stored != null and int(stored.data.history.battles_won) == 1, "the hero's win is written back")

func computer_races(scene):
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)                      # the map's races: Dwarf (west) and The Swarm (east)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 3)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 3)
	check(scene.start_skirmish(setup, "", null, "dwarf-match-2"), "Dwarf vs Swarm computer match starts")
	var dwarf = hero_of(scene, 0)
	var swarm = hero_of(scene, 1)
	check(dwarf != null and dwarf.type_id == "ADHX" and swarm != null and swarm.type_id == "ARHX", "heroes by race (0x42a0d0 race switch)")
	var d_profile = scene.match_heroes[0].profile.data
	var s_profile = scene.match_heroes[1].profile.data
	check(int(d_profile.race_id) == Rules.DWARF and int(s_profile.race_id) == Rules.SWARM, "hero records carry the slot race")
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://simulation/hero_races.json"))
	var created: Dictionary = table.creation["1"][int(d_profile.class_id)]
	var skill_ids: Array = d_profile.skills.map(func(s): return int(s.id))
	check(skill_ids.has(int(created.skills[0][0])), "the Dwarf hero's skills come from the Dwarf creation record")
	var ais: Array = scene.ai_manager.players.filter(func(p): return p != null and p.has_method("summary"))
	var by_player := {}
	for ai in ais: by_player[ai.me] = ai
	check(by_player.has(0) and by_player[0].PEASANT == "ADBX" and by_player[0].KEEPS == ["BKD0", "BKD1", "BKD2", "BKD3", "BKD4"] and by_player[0].HERO == "ADHX", "Dwarf computer lists (0x4fcfa0 / 0x4fd060; B1-5: the full lists, every hall level)")
	check(by_player.has(1) and by_player[1].PEASANT == "ARBX" and by_player[1].KEEPS == ["BKR0", "BKR1", "BKR2", "BKR3", "BKR4"] and by_player[1].HERO == "ARHX", "Swarm computer lists")
	check(until(scene, func(): return building_of(scene, 0, "BKD0") != null and building_of(scene, 1, "BKR0") != null, 90.0), "both computer heroes start their halls")
	var foundry_up := until(scene, func(): return building_of(scene, 0, "BPFO") != null, 240.0)
	if not foundry_up:
		for summary in scene.ai_summaries(): printerr("  ", summary)
		printerr("  want P0: ", by_player[0].want.map(func(w): return [w.id, w.priority, w.categories]), " tasks ", by_player[0].tasks)
	check(foundry_up, "the Dwarf hero builds the Foundry too (0x4fe190: no Smith producer yet)")
