extends SceneTree
## B2-1 (BATCH2_RESEARCH.md section 7): the shared part of the three race batch 2 world checks, in the real scene on Desert
## Sands through the control panel. A human side (of the race, with the race's hero) against a passive computer Knights side
## reaches hall level 5, builds every building of the computer's list (tests/batch2_fixtures.json `lists`: the emulated rows),
## trains every unit of it and researches every listed item, as undead_world_checks.gd does (the computer player's site rule
## and Production.enqueue; stock topped up). The research in `held()` stays back: the race's check needs the world before
## and after it. Then the race's own `powers()`.
## Never touches user://heroes (a fresh test directory).

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Rules = preload("res://simulation/production_rules.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
const Placement = preload("res://simulation/placement.gd")
const Settings = preload("res://simulation/game_settings.gd")

const NOT_LISTED := ["PSPR", "PARR", "POMA", "POMB", "POMC"]   # 0x436500 does not list these
const LIMIT_S := 3600.0
## Centres of the site search after failed walks (offsets from home, cells).
const CENTRES := [Vector2i(0, 0), Vector2i(12, 0), Vector2i(-12, 0), Vector2i(0, 12), Vector2i(0, -12), Vector2i(12, 12), Vector2i(-12, -12), Vector2i(12, -12), Vector2i(-12, 12)]

var checks := 0
var failures := 0
var scene
var production
var hud
var simulated := 0.0
var home := Vector2i.ZERO
var hero_unit = null

func label() -> String: return "Batch 2"
func race() -> int: return 0
func hall() -> String: return "BK"                # the hall's prefix, BKP / BKB / BKH + level
func worker() -> String: return ""                # the race's builder
func held() -> Array: return []
func lists_path() -> String: return "res://tests/batch2_fixtures.json"   # B3-1: batch 3 reads tests/batch3_fixtures.json
func powers(): pass

func check(value: bool, text: String):
	checks += 1
	if not value:
		failures += 1
		printerr("%s world check failed: %s" % [label(), text])

func _initialize():
	call_deferred("run")

func run():
	var settings_file := "user://batch2-world-test-settings-%d.cfg" % race()
	DirAccess.remove_absolute(settings_file)
	Settings.use_file(settings_file)
	var directory := "user://batch2-world-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	root.size = Vector2i(1920, 1080)
	scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	await process_frame
	hud = scene.hud
	var started := Time.get_ticks_msec()
	whole_faction(store)
	if failures == 0: powers()
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(settings_file)
	print("%s world run: %.0f s of game time in %.0f s" % [label(), simulated, (Time.get_ticks_msec() - started) / 1000.0])
	if failures > 0:
		printerr("%s world checks failed: %d of %d" % [label(), failures, checks])
		quit(1)
		return
	print("%s world checks passed: %d" % [label(), checks])
	quit(0)

# ------------------------------------------------------------------------------------------------ helpers
func advance(seconds: float):
	for i in roundi(seconds * 40.0):
		if scene.skirmish != null and scene.skirmish.over: return
		scene.simulation_step(0.025)
	simulated += seconds

func fund():
	scene.economy.refresh_capacity(0)
	scene.economy.stockpiles[0] = scene.economy.capacity(0).duplicate()

func buildings_of(code: String) -> Array:
	return production.buildings.values().filter(func(b): return int(b.owner) == 0 and b.original_type_id == code and not b.constructing)

func units_of(code: String) -> Array:
	return scene.units.filter(func(u): return u.owner_id == 0 and u.type_id == code and not u.removed and not u.dying)

func fighter(u):
	return scene.combat.fighters.get(u.unit_id)

func keep():
	for b in production.buildings.values():
		if int(b.owner) == 0 and String(b.original_type_id).begins_with(hall()) and not b.constructing: return b
	return null

func select_units(list: Array):
	for u in scene.units: u.selected = list.has(u)
	scene.selected_building_id = -1
	hud.refresh_cells()

func select_building(b):
	for u in scene.units: u.selected = false
	scene.selected_building_id = b.entity_id
	hud.refresh_cells()

func cell_with(icon: int) -> int:
	for k in hud.cells.size():
		if int(hud.cells[k].get("icon", -1)) == icon: return k
	return -1

## Researches `item` at a building that offers it and waits for it. Returns the building.
func research_now(item: String, limit: float = 400.0):
	var place = null
	for b in production.buildings.values():
		if int(b.owner) != 0 or b.constructing: continue
		if production.menu_for(b).any(func(m): return String(m.id) == item): place = b
	check(place != null, "%s is offered by a building" % item)
	if place == null: return null
	fund()
	var waited := 0.0
	while waited < 30.0 and not production.can_queue(place.entity_id, item).ok:
		advance(0.5)
		waited += 0.5
	var queued: Dictionary = production.enqueue(place.entity_id, item, scene.game_ms())
	check(queued.ok, "%s queued at %s: %s" % [item, place.original_type_id, queued])
	waited = 0.0
	while place.has_job() and waited < limit:
		advance(0.5)
		waited += 0.5
	check(not place.has_job(), "%s done at %s" % [item, place.original_type_id])
	return place

## Trains `code` at a building that offers it; the new unit, or null.
func train(code: String):
	var place = null
	for b in production.buildings.values():
		if int(b.owner) != 0 or b.constructing or b.has_job(): continue
		if production.menu_for(b).any(func(m): return String(m.id) == code): place = b
	check(place != null, "%s is trained by a free building" % code)
	if place == null: return null
	fund()
	var before: Array = units_of(code)
	var queued: Dictionary = production.enqueue(place.entity_id, code, scene.game_ms())
	check(queued.ok, "%s queued at %s: %s" % [code, place.original_type_id, queued])
	var waited := 0.0
	while units_of(code).size() <= before.size() and waited < 200.0:
		advance(0.5)
		waited += 0.5
	var made: Array = units_of(code).filter(func(u): return not before.has(u))
	check(not made.is_empty(), "%s trained" % code)
	return made[0] if not made.is_empty() else null

## The trade cell of R1 on a finished building: shown, disabled before Trade, then the dialog trades at the Market's rate.
func trade_at(b, researched: bool):
	select_building(b)
	var k := cell_with(RacePowers.TRADE_ICON)
	check(k == 7, "%s has the trade cell (cell %d)" % [b.original_type_id, k])
	if k < 0: return
	check(bool(hud.cells[k].enabled) == researched, "%s: the trade cell enabled with Trade only (%s)" % [b.original_type_id, researched])
	if not researched: return
	fund()
	scene.economy.stockpiles[0][0] = 1000
	scene.economy.stockpiles[0][1] = 0
	check(hud.press_cell(k), "the trade cell opens the dialog")
	check(hud.dialog == "market", "the trade dialog is open")
	hud.market_press(0)
	hud.market_press(4 + 1)
	hud.market_press(8)
	hud.market_press(14)
	var after: Array = scene.economy.resources(0)
	check(int(after[0]) == 950 and int(after[1]) == 25, "%s: 50 gold -> 25 metal: %s" % [b.original_type_id, after])
	hud.close_dialog()

## R2 / E7 at the button: `units` of a berserker type. The button is disabled before PFAN (`researched` false).
func berserk_at_button(units: Array, researched: bool):
	select_units(units)
	var k := cell_with(RacePowers.BERSERK_ICON)
	check(k >= 6, "the Berserker cell is in the unit row")
	if k < 0: return
	check(bool(hud.cells[k].enabled) == researched, "the Berserker cell enabled with PFAN only (%s)" % researched)
	if not researched: return
	check(hud.press_cell(k), "Berserker pressed")
	for u in units:
		var f = fighter(u)
		check(f.get("berserk") != null and int(f.berserk.level) == 2 and int(f.script) == 4, "%s: berserk, Rampant" % u.type_id)
	hud.refresh_cells()
	check(cell_with(RacePowers.BERSERK_ICON) < 0, "the button is gone while the state runs")

## B2-2 (R11): a caster of `code` in the real scene; each of `rows` [icon, mana, keycode] by its unit-row button and by its key: the
## cell shows, disabled below the mana; a press and the key each pay the mana and cast once.
func caster_row(code: String, rows: Array):
	var u = scene.add_unit(code, scene.navigator.free_cell_near(home + Vector2i(12, 6)), 0)
	var f = fighter(u)
	var done: Array = []
	scene.combat.spells.cast_done.connect(func(info): done.append(info))
	for row in rows:
		var icon: int = row[0]
		var mana: int = row[1]
		f["mana"] = mana - 1
		f["max_mana"] = 200
		select_units([u])
		var k := cell_with(icon)
		check(k >= 6, "%s: the cell of icon 0x%x is in the unit row: %d" % [code, icon, k])
		if k < 0: continue
		check(not bool(hud.cells[k].enabled), "%s: icon 0x%x disabled below %d mana" % [code, icon, mana])
		check(String(hud.cells[k].tip) != "", "%s: icon 0x%x has its tooltip" % [code, icon])
		f["mana"] = 200
		hud.refresh_cells()
		var before := done.size()
		check(bool(hud.cells[k].enabled) and hud.press_cell(k), "%s: icon 0x%x pressed" % [code, icon])
		check(done.size() == before + 1 and int(f.mana) == 200 - mana, "%s: the button casts and pays %d: %d" % [code, mana, int(f.mana)])
		f["mana"] = 200
		var key := InputEventKey.new()
		key.keycode = int(row[2])
		key.pressed = true
		root.push_input(key)
		check(done.size() == before + 2 and int(f.mana) == 200 - mana, "%s: the key casts and pays %d: %d" % [code, mana, int(f.mana)])
		advance(0.1)

## The full state on one unit made to last: 1 hp/s, Rampant, its script back at 180 s (E7).
func berserk_full_length(u):
	var f = fighter(u)
	# Enough hit points to outlast 180 s of Rampant fighting (2026-11-11: with 1000 the unit charged the enemy and died
	# before the end, so the script was never restored); the drain check below is a difference.
	f.max_hp = 100000
	f.hp = 100000
	# 2026-11-11: the Rampant unit (with the hero's aura, 0x51c460 / 0x51bd10) can now clear the enemy within the 180 s;
	# the match then ends and advance() stops, so the state never runs out. Standard Victory is switched off for the rest
	# of this run (0x516230 is not evaluated when the SCN byte 0x14c is clear); these checks are not about victory.
	if scene.skirmish != null: scene.skirmish.resolved["standard_victory_event"] = 0
	# 2026-11-15: a Rampant Minotaur or Barbarian hunts (R5, RacePowers.HUNTERS): an animal eaten inside the 10 s window (+20 hp,
	# capped at the maximum) hid half of the drain in the whole-faction world. The map's animals go; hunting() brings its own sheep.
	for other in scene.units:
		var of = fighter(other)
		if of != null and int(of.owner) == 6 and not other.removed and scene.combat.ai.is_animal(other.type_id): scene.remove_unit_quietly(other)
	var script_before := int(f.script)
	var armour_before: Array = preload("res://simulation/combat_rules.gd").armour_table(scene.combat.combat_block(f)).duplicate()
	# The hero's aura (+2 speed, 0x51c460) comes and goes as the Rampant unit roams: it is taken out of both readings.
	var speed_before: int = int(u.base_speed) - scene.combat.spells.aura_speed(f)
	var combat_before := int(scene.combat.combat_block(f).combat)
	var base_combat := int(f.base.combat)
	var base_speed := int(f.base.speed)
	select_units([u])
	check(hud.press_cell(cell_with(RacePowers.BERSERK_ICON)), "Berserker pressed")
	var block: Dictionary = scene.combat.combat_block(f)
	check(int(block.combat) == combat_before + 6 and int(u.base_speed) - scene.combat.spells.aura_speed(f) == speed_before + 4, "combat + 6, speed + 4")
	check(int(preload("res://simulation/combat_rules.gd").armour_table(block)[3]) == int(armour_before[3]) + 15, "fire armour + 15")
	var hp0 := int(f.hp)
	advance(10.0)
	check(hp0 - int(f.hp) >= 9 and hp0 - int(f.hp) <= 11 and int(f.script) == 4, "10 s later about 10 hp are gone: %d, script %d" % [hp0 - int(f.hp), int(f.script)])
	advance(171.0)
	check(f.get("berserk") == null, "the state is over after 180 s")
	check(int(f.script) == script_before, "the script is back: %d" % int(f.script))
	# R-1: kills during the state promote the unit for good (f.base): the bonuses are gone on top of that.
	var risen := int(f.base.combat) - base_combat
	var faster := int(f.base.speed) - base_speed
	check(combat_before + risen == int(scene.combat.combat_block(f).combat) and int(u.base_speed) - scene.combat.spells.aura_speed(f) == speed_before + faster, "the bonuses are gone: combat %d -> %d, speed %d -> %d, rank %d" % [combat_before + risen, int(scene.combat.combat_block(f).combat), speed_before + faster, int(u.base_speed) - scene.combat.spells.aura_speed(f), int(f.get("rank", 0))])

## 0x435900's cell test only (--powers-only places buildings without their requirements).
func free_site(code: String) -> Vector2i:
	var definition: Dictionary = production.rules.definition(code)
	for radius in range(4, 40, 2):
		for dy in range(-radius, radius + 1, 2):
			for dx in range(-radius, radius + 1, 2):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var cell := home + Vector2i(dx, dy)
				if cell.x < 2 or cell.y < 2 or cell.x > 125 or cell.y > 125: continue
				if Placement.check(scene.navigator, definition, cell, hero_unit).ok and scene._clear_margin(definition, cell): return cell
	return Vector2i(-1, -1)

# ------------------------------------------------------------------------------------------------ the faction
func whole_faction(store):
	var id := "test-batch2-hero-%d" % race()
	var profile = Profile.create(id, "Batch Tester", race(), 0)
	check(store.save_profile(profile), "test profile saved")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_race(setup, 0, race())
	Setup.set_race(setup, 1, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = id
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)          # Passive
	check(scene.start_skirmish(setup, id, store, "batch2-faction-%d" % race()), "match starts")
	production = scene.production
	check(production.race_of(0) == race(), "player 0 plays race %d" % race())
	advance(1.0)
	fund()
	for u in scene.units:
		if u.owner_id == 0 and fighter(u) != null and fighter(u).hero: hero_unit = u
	check(hero_unit != null and hero_unit.type_id == Rules.hero_type(race()), "the race's hero: %s" % [hero_unit.type_id if hero_unit != null else null])
	home = scene.skirmish.slots[0].start
	# The large halls do not fit inside the hero's first sight; the checks build by the computer's site rule, which has no fog.
	var fog: bool = scene.visibility.fog
	var shroud: bool = scene.visibility.shroud
	scene.visibility.fog = false
	scene.visibility.shroud = false
	var lists: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(lists_path())).lists[str(race())]
	var wanted: Array = []
	# The temples BT* are map objects (catalogue group 14), nobody builds them; their units are not this check's.
	var own_buildings: Array = lists.buildings.filter(func(c): return not String(c).begins_with("BT"))
	for code in own_buildings:
		if not String(code).begins_with(hall()) or String(code) == hall() + "0": wanted.append(String(code))
	var offered := {}
	for code in own_buildings:
		for slot in production.rules.production_slots(String(code), race()):
			if slot.id != null: offered[String(slot.id)] = true
	var trained_list: Array = lists.units.filter(func(c): return offered.has(String(c)))
	var research_list: Array = lists.research.filter(func(r): return not NOT_LISTED.has(String(r)) and not held().has(String(r)))
	# Research that no listed building offers (the Daemons' Scale Walls PSCL at the wall BWL0): the first building of the
	# construction menus that offers it is built too (not part of the "built" checks).
	var menus: Array = production.construction_menu(0) + production.construction_menu(0, 1)
	var offers := func(code: String, item: String) -> bool:
		return production.rules.production_slots(code, race()).any(func(slot): return slot.id != null and String(slot.id) == item)
	for r in research_list:
		if own_buildings.any(func(c): return offers.call(String(c), String(r))): continue
		for code in menus:
			if offers.call(String(code), String(r)):
				if not wanted.has(String(code)): wanted.append(String(code))
				break
	if OS.get_cmdline_user_args().has("--powers-only"):       # development: the same world in a few seconds, then powers()
		for code in own_buildings:
			if String(code).begins_with(hall()) and String(code) != hall() + "4": continue
			var site := free_site(String(code))
			if site.x < 0: continue
			var anchor: Vector2i = Placement.anchor(production.rules.definition(String(code)), site)
			production.add_completed(0, String(code), anchor.x, anchor.y)
		for code in trained_list: scene.add_unit(String(code), scene.navigator.free_cell_near(home + Vector2i(6, 6)), 0)
		for r in research_list: production.complete_research(0, String(r))
		scene.visibility.fog = fog
		scene.visibility.shroud = shroud
		advance(1.0)
		return
	var ordered := {}
	var walks := {}                               # builder id -> {code, site} while it walks to a site
	var tries := {}                               # code -> failed walks
	var need := {}                                # code -> buildings of it wanted standing (a second one for a branching upgrade)
	var trained := {}
	var placed: Array = []
	var waited := 0.0
	var quiet := 0.0
	while waited < LIMIT_S:
		fund()
		var builders: Array = scene.units.filter(func(u): return u.owner_id == 0 and not u.removed and not u.dying and not u.inside_building \
			and production.rules.builder_power(u.type_id) > 0 and not scene.is_hero_unit(u) and not scene.pending_builds.has(u.unit_id))
		# A match starts with the hero alone: it builds until the workers are there.
		if units_of(worker()).is_empty() and hero_unit != null and not hero_unit.inside_building and not scene.pending_builds.has(hero_unit.unit_id): builders.append(hero_unit)
		for code in wanted.duplicate():
			var have: int = production.buildings.values().filter(func(b): return int(b.owner) == 0 and Rules.satisfies(b.original_type_id, code)).size()
			if have >= int(need.get(code, 1 + placed.count(code))):
				need.erase(code)
				wanted.erase(code)
				placed.append(code)
		# A walk that ends more than three cells from its site (0x51ea20; the Daemons' southern sites, never reached) or on a cell
		# another builder's site took ("cell is occupied", the Plaguelords) fails at arrival; the ring search from the same centre
		# would pick the same cell again, so the next search for that code starts from another centre around home.
		for walker in walks.keys():
			var state: String = scene.build_state(scene.units[walker])
			if state == "pending": continue
			if state == "failed":
				var walk: Dictionary = walks[walker]
				tries[walk.code] = int(tries.get(walk.code, 0)) + 1
				print("t=%d %s: the walk to %s ended at %s, failed (%d): %s" % [int(waited), walk.code, walk.site, scene.units[walker].cell, int(tries[walk.code]), scene.last_message])
			walks.erase(walker)
		var menu: Array = production.construction_menu(0) + production.construction_menu(0, 1)
		for builder in builders:
			for code in wanted:
				# The level upgrades (BAE1, BAS2 ...) are no construction-menu entries: their building's menu offers them below.
				if not menu.has(code) or production.missing_requirement(0, code) != "": continue
				if float(ordered.get(code, -1000.0)) > waited - 45.0: continue
				ordered[code] = waited                    # a site search that fails is not repeated at once either
				var centre: Vector2i = home + CENTRES[int(tries.get(code, 0)) % CENTRES.size()]
				var site: Vector2i = scene.ai_site(0, code, centre, builder)
				if site.x < 0 or not scene.ai_build(builder, code, site): continue
				walks[builder.unit_id] = {"code": code, "site": site}
				break
		for b in production.buildings.values():
			if int(b.owner) != 0 or b.constructing or b.has_job(): continue
			for m in production.menu_for(b):
				var item := String(m.id)
				if item == worker() and units_of(worker()).size() >= 4: continue
				if item.begins_with("A") and item != worker() and trained.has(item): continue
				if item.begins_with("A") and not trained_list.has(item): continue
				if Rules.is_research(item) and (production.research_level(0, item) != 0 or NOT_LISTED.has(item) or held().has(item)): continue
				# Upgrades: one of each. A branching upgrade (the Plaguelords' Hydra Cave BPHC becomes the Ice Cave BPIC or the Fire
				# Cave BPFC) must not take the last building of its own listed code: another one is built first.
				if item.begins_with("B"):
					var standing := func(code: String) -> int:
						return production.buildings.values().filter(func(o): return int(o.owner) == 0 and Rules.satisfies(o.original_type_id, code)).size()
					if standing.call(item) > 0: continue
					var own_code := String(b.original_type_id)
					if own_buildings.has(own_code) and not Rules.satisfies(item, own_code) and standing.call(own_code) < 2:
						if not wanted.has(own_code):
							wanted.append(own_code)
							need[own_code] = standing.call(own_code) + 1
						continue
				if production.can_queue(b.entity_id, item).ok and production.enqueue(b.entity_id, item, scene.game_ms()).ok:
					if item.begins_with("A"): trained[item] = true
					break
		var top := hall() + "4"
		var done: bool = wanted.is_empty() and trained_list.all(func(c): return trained.has(c)) and research_list.all(func(r): return production.research_level(0, String(r)) != 0) \
			and keep() != null and String(keep().original_type_id) == top
		if done:
			quiet += 0.5
			if quiet > 30.0: break
		if int(waited * 2) % 240 == 0:
			var pop: Dictionary = production.population(0)
			print("t=%d hall=%s pop=%d/%d wanted=%s untrained=%s unresearched=%s" % [int(waited), keep().original_type_id if keep() != null else "-", int(pop.current), int(pop.maximum), wanted,
				trained_list.filter(func(c): return not trained.has(c)), research_list.filter(func(r): return production.research_level(0, String(r)) == 0)])
			if waited >= 600.0:                           # why a code still waits
				for code in wanted:
					print("  %s: menu %s, missing '%s', site %s" % [code, menu.has(code), production.missing_requirement(0, code),
						scene.ai_site(0, code, home + CENTRES[int(tries.get(code, 0)) % CENTRES.size()], hero_unit) if menu.has(code) else "-"])
		advance(0.5)
		waited += 0.5
	scene.visibility.fog = fog
	scene.visibility.shroud = shroud
	check(keep() != null and String(keep().original_type_id) == hall() + "4", "hall level 5 (%s)" % (keep().original_type_id if keep() != null else "none"))
	for code in own_buildings:
		check(production.buildings.values().any(func(b): return int(b.owner) == 0 and Rules.satisfies(b.original_type_id, String(code))), "%s built" % code)
	for code in trained_list: check(trained.has(code), "%s trained" % code)
	for item in research_list: check(production.research_level(0, String(item)) != 0, "%s researched" % item)
	check(waited < LIMIT_S, "everything within %.0f s (took %.0f s)" % [LIMIT_S, waited])
