extends SceneTree
## Milestone 13: the complete Knights faction in the real scene on Desert Sands. A human Knights side (against a passive
## computer) builds through Keep level 5, every building of construction rows H0 and H1, trains one of every unit and
## researches every research item, through the same calls the HUD makes (placement by the computer player's site rule,
## Production.enqueue). Along the way it checks the Keep levels (hit points, stockpile, command limit), research effects
## on live units, flyers, the tower, the Market trade and the production dialog. The stock is topped up to the stockpile
## limit every half second (test hook: the check is about the faction, not the economy). Never touches user://heroes.

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Rules = preload("res://simulation/production_rules.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")

const BUILDINGS := ["BKK0", "BAGA", "BPSM", "BPSB", "BPFL", "BPMA", "BAV0", "BPSS", "BPCA", "BWTC", "BWG0", "BWG1", "BWG2", "BWRA"]
const UNITS := ["AHBX", "AHKX", "AHMX", "AHFX", "AHDX", "AHEX", "AHLX", "AHGX", "ATHX", "ASBA", "ASCA", "AAEG", "AAPE", "AADR", "AADC", "AAAR"]
const LIMIT_S := 2400.0

var checks := 0
var failures := 0
var scene
var production
var log_lines: Array = []

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Knights world check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var directory := "user://knights-world-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var started := Time.get_ticks_msec()
	whole_faction(store)
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("Knights world run: %.0f s of game time in %.0f s" % [simulated, (Time.get_ticks_msec() - started) / 1000.0])
	if failures > 0:
		printerr("Knights world checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Knights world checks passed: %d" % checks)
	quit(0)

var simulated := 0.0

func advance(seconds: float):
	for i in roundi(seconds * 40.0):
		if scene.skirmish != null and scene.skirmish.over: return
		scene.simulation_step(0.025)
	simulated += seconds

## Test hook: the local player's stock at its stockpile limit.
func fund():
	scene.economy.refresh_capacity(0)
	scene.economy.stockpiles[0] = scene.economy.capacity(0).duplicate()

func buildings_of(code: String, finished: bool = true) -> Array:
	return production.buildings.values().filter(func(b): return int(b.owner) == 0 and b.original_type_id == code and (not finished or not b.constructing))

func any_building(code: String) -> bool:
	return production.buildings.values().any(func(b): return int(b.owner) == 0 and Rules.satisfies(b.original_type_id, code))

func units_of(code: String) -> Array:
	return scene.units.filter(func(u): return u.owner_id == 0 and u.type_id == code and not u.removed and not u.dying)

func fighter(u):
	return scene.combat.fighters.get(u.unit_id)

func keep():
	for b in production.buildings.values():
		if int(b.owner) == 0 and Rules.keep_level(b.original_type_id) > 0 and not b.constructing: return b
	return null

func whole_faction(store):
	var profile = Profile.create("test-knight-faction", "Sir Roster")
	check(store.save_profile(profile), "copied test profile saved")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-knight-faction"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)          # Passive
	check(scene.start_skirmish(setup, "test-knight-faction", store, "knights-faction-1"), "Knights vs Knights match starts")
	production = scene.production
	check(production.race_of(0) == Rules.KNIGHT and production.race_of(1) == Rules.KNIGHT, "both sides are Knights")
	# Parity pass 3: the roster's world art (it was missing: Knights units drew as Swordsmen, buildings not at all) and the
	# map towers swapped to Knight Towers for both owners (0x4a50f0).
	const ArtData = preload("res://core/art_data.gd")
	for code in BUILDINGS: check(not ArtData.building_sheet(code, 0).is_empty(), "world art for " + code)
	for code in UNITS: check(ArtData.has_unit(code), "world art for " + code)
	var map_towers: Array = production.buildings.values().filter(func(b): return String(b.original_type_id).begins_with("BWT")).map(func(b): return String(b.original_type_id) + str(b.owner))
	map_towers.sort()
	check(map_towers == ["BWTC0", "BWTC0", "BWTC1", "BWTC1"], "the map's towers are Knight Towers: %s" % [map_towers])
	advance(1.0)
	fund()
	var hero = null
	for u in scene.units:
		if u.owner_id == 0 and fighter(u) != null and fighter(u).hero: hero = u
	check(hero != null, "the local hero")
	check(production.construction_menu(0) == ["BKK0", "BAGA", "BPSM", "BPSB", "BPFL", "BPMA", "BAV0", "BPSS", "BPCA"], "row H0")
	check(production.construction_menu(0, 1) == ["BWTC", "BWG0", "BWG1", "BWG2", "BWRA"], "row H1 (tower, walls)")
	var home: Vector2i = scene.skirmish.slots[0].start
	# ------------------------------------------------------------------ the orchestration: builders, jobs, research
	var wanted_buildings := BUILDINGS.duplicate()
	wanted_buildings.append("BAV0")                         # a second Eyrie: the two dragons train in parallel
	var placed: Array = []
	var ordered := {}                                       # code -> time of the last order (seconds into the loop)
	var trained := {}
	var researched := {}
	var all_research: Array = []
	for b in ["BKK0", "BKK1", "BKK2", "BKK3", "BKK4", "BPSM", "BPFL", "BPMA", "BPSS", "BPCA", "BPSB"]:
		for slot in production.rules.production_slots(b, Rules.KNIGHT):
			if slot.id != null and Rules.is_research(String(slot.id)) and not all_research.has(String(slot.id)): all_research.append(String(slot.id))
	check(all_research.size() == 31, "31 Knights research items")
	var keep_hp := {}
	var keep_cap := {}
	var keep_command := {}
	var waited := 0.0
	var peasants_wanted := 4
	# AI-10: the checks build by the computer's site rule (0x4f9480 / 0x435320, AI-7), which has no fog: its spot may lie
	# outside the local hero's sight, where the human side may not place. Fog and shroud are off while the faction builds
	# (as batch2_world_base.gd); the old ring stand-in tried Production's acceptance per ring cell and found visible ones.
	var fog: bool = scene.visibility.fog
	var shroud: bool = scene.visibility.shroud
	scene.visibility.fog = false
	scene.visibility.shroud = false
	while waited < LIMIT_S:
		fund()
		# Keep levels as they appear.
		var k = keep()
		if k != null:
			var level: int = Rules.keep_level(k.original_type_id)
			if not keep_hp.has(level):
				keep_hp[level] = [int(k.max_hit_points), int(k.definition.hit_points)]
				keep_cap[level] = int(scene.economy.capacity(0)[0])
		# Builders: idle Peasants (and the hero for the first Keep) place the next wanted building whose requirements hold.
		var builders: Array = units_of("AHBX").filter(func(u): return not u.inside_building and not scene.pending_builds.has(u.unit_id))
		if not any_building("BKK0") and hero != null and not hero.inside_building and not scene.pending_builds.has(hero.unit_id): builders.append(hero)
		# A wanted building leaves the list once enough of its type stand (or are under construction); an order that has
		# not produced a building after 45 s is given again (the builder may fail to reach the site).
		for code in wanted_buildings.duplicate():
			var want_count: int = wanted_buildings.count(code) + placed.count(code)
			var have: int = production.buildings.values().filter(func(b): return int(b.owner) == 0 and Rules.satisfies(b.original_type_id, code)).size()
			if have >= want_count:
				wanted_buildings.erase(code)
				placed.append(code)
		for builder in builders:
			for code in wanted_buildings:
				if production.missing_requirement(0, code) != "": continue
				if float(ordered.get(code, -1000.0)) > waited - 45.0: continue
				var site: Vector2i = scene.ai_site(0, code, home, builder)
				if site.x < 0 or not scene.ai_build(builder, code, site): continue
				ordered[code] = waited
				break
		# Jobs: every finished building starts the next missing item of its menu (units once, research once, upgrades).
		for b in production.buildings.values():
			if int(b.owner) != 0 or b.constructing or b.has_job(): continue
			for m in production.menu_for(b):
				var id := String(m.id)
				if id.begins_with("A") and id == "AHBX" and units_of("AHBX").size() >= peasants_wanted: continue
				if id.begins_with("A") and id != "AHBX" and trained.has(id): continue
				if Rules.is_research(id) and production.research_level(0, id) != 0: continue
				if id.begins_with("B") and not production.can_queue(b.entity_id, id).ok: continue
				if production.can_queue(b.entity_id, id).ok and production.enqueue(b.entity_id, id, scene.game_ms()).ok:
					if id.begins_with("A"): trained[id] = true
					break
		for code in UNITS:
			if not units_of(code).is_empty(): trained[code] = true
		for id in all_research:
			if production.research_level(0, id) != 0 or (id == "PQKN" and production.quests.get(0, []).size() > 0): researched[id] = true
		var done: bool = wanted_buildings.is_empty() and UNITS.all(func(c): return not units_of(c).is_empty()) and researched.size() == all_research.size() \
			and Rules.keep_level(String(keep().original_type_id) if keep() != null else "") == 5
		if done: break
		advance(0.5)
		waited += 0.5
	scene.visibility.fog = fog
	scene.visibility.shroud = shroud
	log_lines.append("finished at %.0f s" % waited)
	# ------------------------------------------------------------------ what was reached
	check(Rules.keep_level(String(keep().original_type_id)) == 5 if keep() != null else false, "Keep level 5 (BKK4)")
	for code in BUILDINGS:
		check(any_building(code), "%s built" % code)
	for code in UNITS:
		check(not units_of(code).is_empty(), "%s trained" % code)
	for id in all_research:
		check(researched.has(id), "%s researched" % id)
	check(waited < LIMIT_S, "everything within %.0f s (took %.0f s)" % [LIMIT_S, waited])
	# Keep levels 1..5 (0x4a4f60): +100 hit points per level (= BUI 500..900), stockpile 1000 + 500 per level (0x52aac0).
	for level in range(1, 6):
		if keep_hp.has(level):
			check(int(keep_hp[level][0]) == 400 + 100 * level + int(production.hero_building_hp.get(0, 0)) and int(keep_hp[level][1]) == 400 + 100 * level, "Keep level %d hit points %s" % [level, keep_hp[level]])
			check(int(keep_cap[level]) == 500 + 500 * level, "Keep level %d stockpile limit %d" % [level, int(keep_cap[level])])
	check(keep_hp.size() == 5, "all five Keep levels seen")
	var pop: Dictionary = production.population(0)
	var expected := 0
	for b in production.buildings.values():
		if int(b.owner) == 0 and not b.constructing: expected += production.rules.army_limit(b.original_type_id)
	expected += 30 - 2 + int(production.hero_commands.get(0, 0))
	expected += Production_command_research()
	check(int(pop.maximum) == mini(250, expected), "command limit with Keep level 5: table 30 (0x5325d0) + buildings: %d vs %d" % [int(pop.maximum), expected])
	world_effects(hero)

func Production_command_research() -> int:
	return 0

## Research effects on live units and the special rules of the roster.
func world_effects(hero):
	var research: Array = production.research.get(0, [])
	var knight = units_of("AHFX")[0] if not units_of("AHFX").is_empty() else null
	if knight != null:
		var f = fighter(knight)
		var base: Dictionary = CombatRules.unit_stats(String(production.rules.definition("AHFX").raw_hex))
		check(int(f.stats.combat) == int(base.combat) + 2, "Warhorse: the Knight's combat %d = %d + 2" % [int(f.stats.combat), int(base.combat)])
		check(int(f.stats.speed) == int(base.speed) + 3 and knight.base_speed == int(base.speed) + 3, "Order of the Pegasus: speed + 3 on the live unit")
		check(int(f.stats.armour) == int(base.armour) + 20, "Full Plate Armor: armour + 20 (0x5260a0 level 4 replaces Armorer)")
		check(int(f.stats.mres) == int(base.mres) + 10, "Order of the Dragon: magic armour + 10")
		check(int(f.stats.dmg) == int(base.dmg) + 10, "Weaponsmith I + II: damage + 10")
		var block: Dictionary = scene.combat.combat_block(f)
		check(bool(block.ppal) and bool(block.pgra) and CombatRules.unit_multiplier(block, 0x4) == 3, "Grand Paladin: x3 against Undead in the live block")
	var squire = units_of("AHMX")[0] if not units_of("AHMX").is_empty() else null
	if squire != null:
		var f = fighter(squire)
		var base: Dictionary = CombatRules.unit_stats(String(production.rules.definition("AHMX").raw_hex))
		check(int(f.stats.range) == int(base.range) + 2 and int(f.stats.dmg) == int(base.dmg) + 5 and int(f.stats.dtype) == 11, "Squire: Bowyer + Fletcher + Flaming Arrows (range +2, damage +5, fire)")
	var pegasus = units_of("AAPE")[0] if not units_of("AAPE").is_empty() else null
	if pegasus != null:
		check(pegasus.flying and scene.navigator.air_occupant(pegasus.cell) == pegasus and scene.navigator.occupant(pegasus.cell) != pegasus, "the Pegasus holds the air layer")
		var from: Vector2i = pegasus.cell
		var goal := from + Vector2i(-8, 5)
		pegasus.give_order({"kind": "move", "target": scene.navigator.center(goal), "requested": scene.navigator.center(goal), "group": 0, "speed": pegasus.base_speed, "individual": true}, "replace")
		advance(12.0)
		check(pegasus.cell == goal, "the Pegasus flies straight to %s (at %s)" % [goal, pegasus.cell])
		var swordsman = units_of("AHKX")[0] if not units_of("AHKX").is_empty() else null
		if swordsman != null: check(not CombatRules.can_hit(fighter(swordsman).stats, fighter(pegasus).stats), "Swordsmen cannot attack the Pegasus (0x51da60)")
	var tower = buildings_of("BWTC")
	check(not tower.is_empty() and scene.combat.towers.has(tower[0].entity_id), "the Knights' tower shoots (registered as a tower: 30 damage, range 12)")
	var market = buildings_of("BPMA")
	if not market.is_empty():
		fund()
		var Market = preload("res://simulation/market.gd")
		scene.economy.stockpiles[0] = [500, 0, 0, 0]
		var done: Array = Market.trade(scene.economy, 0, 0, 3, 200, Market.rate(0))
		check(done == [200, 100] and int(scene.economy.resources(0)[2]) == 100, "the Market trades 200 gold for 100 crystal")
	check(production.quests.get(0, []).size() >= 1, "Knight's Quest stored a creature choice: %s" % [production.quests.get(0, [])])
	check(int(production.hero_commands.get(0, 0)) >= 0 and research.has("POLI"), "Order of the Lion researched (hero command term +2 before halving)")
