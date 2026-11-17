extends SceneTree
## B1-3 (B1_3_RESEARCH.md): the Undead (race 2) in the real scene on Desert Sands, through the control panel.
## 1. A human Undead side (an Undead hero) against a passive computer Knights side builds through Deathkeep level 5, every
##    building of rows U0 and U1, trains one of every unit the buildings train and researches every listed research item
##    (as knights_world_checks.gd: the computer player's site rule and Production.enqueue; stock topped up).
## 2. Advancement through the HUD (0x4d3200 buttons): 5 Skeletons -> Wights for 5 x 70 metal (disabled at 349 metal), a
##    Skeleton -> Wraith, a Wraith -> Shadow, Wights -> Slayer Knight and Liche, a Slayer Knight -> Doom Knight: all six
##    advanced types obtained by advancement; experience kept, full hit points of the new type, old units gone.
## 3. Gravestone -> Skeleton (cell 7, icon 0xe), Slavehorde spawns min(10, free command) thralls for 25 gold each and waits
##    3 s, Dark Citadel (cell 7 of the Deathkeep, 100 crystal) brings night after 2.6 s: the Shadow fights at +7, the
##    Skeleton at +2, the Undead hero stops regenerating by day only, the world view is lit at level 3.
## 4. A Knights side: Rites of Dawn (Cathedral cell 7, PROD, 40 crystal) brings day; with Options "Day / Night: Off"
##    nothing turns to night.
## Never touches user://heroes (a fresh test directory).

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Rules = preload("res://simulation/production_rules.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const DayNight = preload("res://simulation/day_night.gd")
const Settings = preload("res://simulation/game_settings.gd")

const BUILDINGS := ["BKU0", "BAGY", "BPDM", "BAGR", "BPBA", "BAE0", "BPAS", "BPCG", "BPBL", "BWTU", "BWE0", "BWE1", "BWE2", "BWRA"]
const TRAINED := ["AUBX", "AUIX", "AUCX", "ASBC", "AUGX", "ATUX", "AABA", "AAHA", "AADU", "AADW"]
const ADVANCED := ["AUJX", "AUKX", "AUXX", "AULX", "AUMX", "AUAX"]
const NOT_LISTED := ["PSPR", "PARR"]         # 0x436500 does not list these (production.gd complete_research)
const LIMIT_S := 2400.0

var checks := 0
var failures := 0
var scene
var production
var hud
var simulated := 0.0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Undead world check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var settings_file := "user://undead-world-test-settings.cfg"
	DirAccess.remove_absolute(settings_file)
	Settings.use_file(settings_file)
	DayNight.set_setting(true)
	var directory := "user://undead-world-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
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
	if failures == 0:
		advancement()
		building_powers()
		night_and_day()
	knights_dawn(store)
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(settings_file)
	print("Undead world run: %.0f s of game time in %.0f s" % [simulated, (Time.get_ticks_msec() - started) / 1000.0])
	if failures > 0:
		printerr("Undead world checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Undead world checks passed: %d" % checks)
	quit(0)

func advance(seconds: float):
	for i in roundi(seconds * 40.0):
		if scene.skirmish != null and scene.skirmish.over: return
		scene.simulation_step(0.025)
	simulated += seconds

func fund():
	scene.economy.refresh_capacity(0)
	scene.economy.stockpiles[0] = scene.economy.capacity(0).duplicate()

func any_building(code: String) -> bool:
	return production.buildings.values().any(func(b): return int(b.owner) == 0 and Rules.satisfies(b.original_type_id, code))

func buildings_of(code: String) -> Array:
	return production.buildings.values().filter(func(b): return int(b.owner) == 0 and b.original_type_id == code and not b.constructing)

func units_of(code: String) -> Array:
	return scene.units.filter(func(u): return u.owner_id == 0 and u.type_id == code and not u.removed and not u.dying)

func fighter(u):
	return scene.combat.fighters.get(u.unit_id)

func keep():
	for b in production.buildings.values():
		if int(b.owner) == 0 and String(b.original_type_id).begins_with("BKU") and not b.constructing: return b
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

# ------------------------------------------------------------------------------------------------ 1. the faction
func whole_faction(store):
	var profile = Profile.create("test-undead-lord", "Lord Rattle", 2, 0)
	check(store.save_profile(profile), "copied Undead test profile saved")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_race(setup, 0, 2)
	Setup.set_race(setup, 1, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-undead-lord"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)          # Passive
	check(scene.start_skirmish(setup, "test-undead-lord", store, "undead-faction-1"), "Undead vs Knights match starts")
	production = scene.production
	check(production.race_of(0) == 2, "player 0 plays the Undead (0x708f96 = 2)")
	check(scene.day_night != null and scene.day_night.enabled and scene.day_night.is_day(), "the match starts by day (0x498b10)")
	advance(1.0)
	fund()
	var hero = null
	for u in scene.units:
		if u.owner_id == 0 and fighter(u) != null and fighter(u).hero: hero = u
	check(hero != null and hero.type_id == "AUHX", "the Undead hero (AUHX)")
	check(production.construction_menu(0) == ["BKU0", "BAGY", "BPDM", "BAGR", "BPBA", "BAE0", "BPAS", "BPCG", "BPBL"], "row U0: %s" % [production.construction_menu(0)])
	var home: Vector2i = scene.skirmish.slots[0].start
	var wanted := BUILDINGS.duplicate()
	var placed: Array = []
	var ordered := {}
	var trained := {}
	var all_research: Array = []
	for b in ["BKU0", "BKU1", "BKU2", "BKU3", "BKU4", "BAGY", "BPDM", "BPBA", "BPAS", "BPCG", "BPBL", "BAE0", "BAE1", "BAE2"]:
		for slot in production.rules.production_slots(b, 2):
			if slot.id != null and Rules.is_research(String(slot.id)) and not all_research.has(String(slot.id)) and not NOT_LISTED.has(String(slot.id)):
				all_research.append(String(slot.id))
	check(all_research.size() == 19, "19 listed Undead research items: %s" % [all_research])
	# AI-10: the checks build by the computer's site rule (0x4f9480 / 0x435320, AI-7), which has no fog: its spot may lie
	# outside the local hero's sight, where the human side may not place. Fog and shroud are off while the faction builds
	# (as batch2_world_base.gd); the old ring stand-in tried Production's acceptance per ring cell and found visible ones.
	var fog: bool = scene.visibility.fog
	var shroud: bool = scene.visibility.shroud
	scene.visibility.fog = false
	scene.visibility.shroud = false
	var waited := 0.0
	while waited < LIMIT_S:
		fund()
		var builders: Array = scene.units.filter(func(u): return u.owner_id == 0 and not u.removed and not u.dying and not u.inside_building \
			and production.rules.builder_power(u.type_id) > 0 and not scene.is_hero_unit(u) and not scene.pending_builds.has(u.unit_id))
		# The Deathkeep trains no builder: the hero builds until the Graveyard's Zombies (AUBX) are there.
		if units_of("AUBX").is_empty() and hero != null and not hero.inside_building and not scene.pending_builds.has(hero.unit_id): builders.append(hero)
		for code in wanted.duplicate():
			var have: int = production.buildings.values().filter(func(b): return int(b.owner) == 0 and Rules.satisfies(b.original_type_id, code)).size()
			if have >= wanted.count(code) + placed.count(code):
				wanted.erase(code)
				placed.append(code)
		for builder in builders:
			for code in wanted:
				if production.missing_requirement(0, code) != "": continue
				if float(ordered.get(code, -1000.0)) > waited - 45.0: continue
				var site: Vector2i = scene.ai_site(0, code, home, builder)
				if site.x < 0 or not scene.ai_build(builder, code, site): continue
				ordered[code] = waited
				break
		for b in production.buildings.values():
			if int(b.owner) != 0 or b.constructing or b.has_job(): continue
			for m in production.menu_for(b):
				var id := String(m.id)
				if id == "AUBX" and units_of("AUBX").size() >= 4: continue
				if id.begins_with("A") and id != "AUBX" and trained.has(id) and id != "AUIX": continue
				if id == "AUIX" and units_of("AUIX").size() >= 8: continue
				if Rules.is_research(id) and (production.research_level(0, id) != 0 or NOT_LISTED.has(id)): continue
				if production.can_queue(b.entity_id, id).ok and production.enqueue(b.entity_id, id, scene.game_ms()).ok:
					if id.begins_with("A"): trained[id] = true
					break
		var done: bool = wanted.is_empty() and TRAINED.all(func(c): return trained.has(c) and not units_of(c).is_empty()) \
			and all_research.all(func(r): return production.research_level(0, r) != 0) and keep() != null and String(keep().original_type_id) == "BKU4" \
			and units_of("AUIX").size() >= 8
		if done: break
		advance(0.5)
		waited += 0.5
	scene.visibility.fog = fog
	scene.visibility.shroud = shroud
	check(keep() != null and String(keep().original_type_id) == "BKU4", "Deathkeep level 5 (BKU4)")
	for code in BUILDINGS: check(any_building(code), "%s built" % code)
	for code in TRAINED: check(not units_of(code).is_empty(), "%s trained" % code)
	for id in all_research: check(production.research_level(0, id) != 0, "%s researched" % id)
	check(waited < LIMIT_S, "everything within %.0f s (took %.0f s)" % [LIMIT_S, waited])
	for code in ADVANCED:
		check(production.rules.menu("BKU4", 2).all(func(m): return String(m.id) != code), "%s is in no production row" % code)

# ------------------------------------------------------------------------------------------------ 2. advancement
func advance_through_hud(sources: Array, icon: int, target: String) -> Array:
	select_units(sources)
	var k := cell_with(icon)
	check(k >= 6 and bool(hud.cells[k].enabled), "the %s button (icon 0x%x) is in the unit row, enabled: cell %d" % [target, icon, k])
	var before: int = scene.units.size()
	var xp: Array = sources.map(func(u): return int(fighter(u).xp))
	check(k >= 0 and hud.press_cell(k), "%s pressed" % target)
	var made: Array = scene.units.slice(before).filter(func(u): return u.type_id == target)
	check(made.size() == sources.size(), "%d %s made" % [made.size(), target])
	check(sources.all(func(u): return u.removed and not u.selected), "the old units are gone")
	for i in mini(made.size(), xp.size()):
		var f = fighter(made[i])
		check(f != null and int(f.hp) == int(f.max_hp) and int(f.xp) >= int(xp[i]), "%s: full hit points %d, experience %d >= %d" % [target, int(f.hp), int(f.xp), int(xp[i])])
		check(made[i].selected, "the new unit is selected")
	if made.size() == sources.size() and not made.is_empty(): obtained[target] = true
	return made

var obtained := {}

func advancement():
	fund()
	var skeletons: Array = units_of("AUIX")
	check(skeletons.size() >= 8, "8 Skeletons for the advancement checks (%d)" % skeletons.size())
	if skeletons.size() < 8: return
	fighter(skeletons[0]).xp = 7
	var five: Array = skeletons.slice(0, 5)
	select_units(five)
	var k := cell_with(0x2e)
	# 0x40b6b0's flat Wight price is 70 metal; the living hero's price modifier 0x526cf0 applies through 0x40c350.
	var price: int = int(production.price_of(0, "AUJX")[1])
	check(int(production.rules.price("AUJX", {"race": 2}).cost[1]) == 70 and price == Rules.discounted(70, production.price_discount(0)), "Wight: 70 metal, %d with the hero's modifier %d" % [price, production.price_discount(0)])
	check(k >= 0 and String(hud.cells[k].tip).contains("%d metal" % (5 * price)), "5 Skeletons: the Wight button costs 5 x %d metal: %s" % [price, hud.cells[k].get("tip", "") if k >= 0 else hud.cells])
	check(cell_with(0x2c) >= 0, "and the Wraith button follows")
	scene.economy.stockpiles[0][1] = 349
	hud.refresh_cells()
	check(k >= 0 and not bool(hud.cells[k].enabled), "disabled with 349 metal (0x4d3200 one lane x count)")
	scene.economy.stockpiles[0][1] = 1000
	var metal: int = int(scene.economy.resources(0)[1])
	var wights := advance_through_hud(five, 0x2e, "AUJX")
	check(int(scene.economy.resources(0)[1]) == metal - 5 * price, "5 x %d metal charged (0x4a9400 -> 0x43eb80)" % price)
	advance(1.0)
	fund()
	var wraith := advance_through_hud([skeletons[5]], 0x2c, "AUKX")
	fund()
	if not wraith.is_empty(): advance_through_hud(wraith, 0x2d, "AUXX")
	fund()
	var slayers: Array = advance_through_hud(wights.slice(0, 2), 0x2f, "AULX") if wights.size() >= 3 else []
	fund()
	if wights.size() >= 3: advance_through_hud([wights[2]], 0x30, "AUMX")
	fund()
	if not slayers.is_empty(): advance_through_hud([slayers[0]], 0x37, "AUAX")
	for code in ADVANCED: check(obtained.has(code), "%s obtained by advancement" % code)
	check(units_of("AUKX").is_empty() and not units_of("AUXX").is_empty(), "the Wraith became the Shadow")
	# a hero in the selection: no advancement (0x4d3200 bVar4)
	var hero = scene.unit_by_id(scene.hero_unit_id)
	select_units([skeletons[6], hero])
	check(cell_with(0x2e) < 0, "no advancement buttons with a hero selected")

# ------------------------------------------------------------------------------------------------ 3. building powers
func building_powers():
	fund()
	var stones: Array = buildings_of("BAGR")
	check(not stones.is_empty(), "a finished Gravestone")
	if not stones.is_empty():
		select_building(stones[0])
		check(int(hud.cells[7].get("icon", -1)) == 0xe and bool(hud.cells[7].enabled), "Gravestone page cell 7: icon 0xe, enabled under the limit")
		var before := units_of("AUIX").size()
		var pop: int = int(production.population(0).current)
		check(hud.press_cell(7), "Gravestone pressed")
		check(production.building(stones[0].entity_id) == null, "the gravestone is gone (0x40ada0)")
		check(units_of("AUIX").size() == before + 1 and int(production.population(0).current) == pop + 1, "Gravestone -> Skeleton (0x4a9230)")
	var cages: Array = buildings_of("BPCG")
	check(not cages.is_empty() and production.research_level(0, "PSLH") != 0, "a Cage with Slavehorde")
	if not cages.is_empty():
		advance(4.0)
		fund()
		select_building(cages[0])
		check(int(hud.cells[7].get("icon", -1)) == 0x14 and bool(hud.cells[7].enabled), "Cage page cell 7: Slavehorde icon 0x14")
		var pop: Dictionary = production.population(0)
		var expected: int = mini(10, int(pop.maximum) - int(pop.current))
		var gold: int = int(scene.economy.resources(0)[0])
		var thralls := units_of("ABBX").size()
		check(hud.press_cell(7), "Slavehorde pressed")
		check(units_of("ABBX").size() == thralls + expected and expected > 0, "Slavehorde: min(10, free command) = %d thralls (ABBX), %d made" % [expected, units_of("ABBX").size() - thralls])
		check(int(scene.economy.resources(0)[0]) == gold - 25 * expected, "for 25 gold each")
		fund()
		select_building(cages[0])
		if bool(hud.cells[7].get("enabled", false)):
			var again := units_of("ABBX").size()
			hud.press_cell(7)
			check(units_of("ABBX").size() == again, "a second Slavehorde within 3 s does nothing")

# ------------------------------------------------------------------------------------------------ 3b. night
func night_and_day():
	fund()
	var dn = scene.day_night
	var shadow = units_of("AUXX")[0] if not units_of("AUXX").is_empty() else null
	var skeleton = units_of("AUIX")[0] if not units_of("AUIX").is_empty() else null
	var day_shadow: int = int(scene.combat.combat_block(fighter(shadow)).combat) if shadow != null else 0
	var day_skeleton: int = int(scene.combat.combat_block(fighter(skeleton)).combat) if skeleton != null else 0
	# the Undead hero by day: no regeneration (0x51b820: +0x164 = now + 5 s)
	var hero_f = scene.combat.fighters.get(scene.hero_unit_id)
	hero_f.hp = int(hero_f.max_hp) - 20
	scene.units[scene.hero_unit_id].hp = hero_f.hp
	var hp_day: int = int(hero_f.hp)
	advance(20.0)
	check(int(hero_f.hp) == hp_day, "the Undead hero does not regenerate by day (%d -> %d)" % [hp_day, int(hero_f.hp)])
	var k = keep()
	select_building(k)
	check(int(hud.cells[7].get("icon", -1)) == 0x17 and bool(hud.cells[7].enabled), "Deathkeep cell 7: Dark Citadel (icon 0x17, PDKC, by day)")
	var crystal: int = int(scene.economy.resources(0)[2])
	check(hud.press_cell(7), "Dark Citadel pressed")
	check(int(scene.economy.resources(0)[2]) == crystal - 100, "100 crystal")
	check(not dn.is_night() and dn.mode == 1, "a dusk runs; still day")
	advance(1.0)
	check(scene.night_layer != null and scene.night_layer.visible and int(dn.level) == 4, "the world view lit at level 4 during the dusk (%d)" % int(dn.level))
	advance(2.0)
	check(dn.is_night() and int(dn.level) == 3, "night after the dusk's 52 ticks; level 3")
	select_building(k)
	check(int(hud.cells[7].get("icon", -1)) == 0x17 and not bool(hud.cells[7].enabled), "Dark Citadel disabled at night")
	if shadow != null: check(int(scene.combat.combat_block(fighter(shadow)).combat) == day_shadow + 7, "the Shadow at night: combat +7 (Undead +2, AUXX +5)")
	if skeleton != null: check(int(scene.combat.combat_block(fighter(skeleton)).combat) == day_skeleton + 2, "the Skeleton at night: combat +2")
	var hp_night: int = int(hero_f.hp)
	advance(20.0)
	check(int(hero_f.hp) > hp_night, "at night the Undead hero regenerates (%d -> %d)" % [hp_night, int(hero_f.hp)])

# ------------------------------------------------------------------------------------------------ 4. Rites of Dawn, setting off
func knights_dawn(store):
	var profile = Profile.create("test-dawn-knight", "Sir Dawn")
	check(store.save_profile(profile), "Knights test profile saved")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-dawn-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	check(scene.start_skirmish(setup, "test-dawn-knight", store, "undead-dawn-2"), "Knights match starts")
	production = scene.production
	var site: Vector2i = scene.find_site("BPCA", Vector2i(20, 60))
	var cathedral = production.add_completed(0, "BPCA", site.x, site.y)          # test hook: a finished Cathedral
	scene.add_marker(cathedral)
	production.complete_research(0, "PROD")
	fund()
	var dn = scene.day_night
	select_building(cathedral)
	check(int(hud.cells[7].get("icon", -1)) == 9 and not bool(hud.cells[7].enabled), "Cathedral cell 7: Rites of Dawn (icon 9), disabled by day")
	dn.apply_record(2)                                                            # a night record (as the Dark Citadel)
	advance(3.0)
	check(dn.is_night(), "night")
	select_building(cathedral)
	check(bool(hud.cells[7].enabled), "Rites of Dawn enabled at night (PROD)")
	var crystal: int = int(scene.economy.resources(0)[2])
	check(hud.press_cell(7), "Rites of Dawn pressed")
	check(int(scene.economy.resources(0)[2]) == crystal - 40, "40 crystal")
	advance(3.0)
	check(dn.is_day() and int(dn.level) == 0 and not scene.night_layer.visible, "day again (record amount 0), the world unlit")
	brew()
	# Options "Day / Night: Off" (modern): no clock
	DayNight.set_setting(false)
	scene.apply_modern_rules()
	dn.apply_record(2)
	advance(3.0)
	check(not dn.is_night() and not dn.is_day() and int(dn.level) == 0, "setting off: no night (no weather object)")
	select_building(cathedral)
	check(not bool(hud.cells[7].enabled), "setting off: Rites of Dawn stays disabled")
	DayNight.set_setting(true)

## Dwarven Brew (Open 6, Read): Dwarf infantry (STATUS 0x2) of the local player drink for 10 gold each after PDRU.
func brew():
	var dwarves: Array = []
	for i in 3: dwarves.append(scene.add_unit("ADIX", scene.navigator.free_cell_near(Vector2i(20, 66) + Vector2i(i, 0)), 0))
	for u in dwarves: production.register_unit(u.unit_id, "ADIX", 0)
	select_units(dwarves)
	var k := cell_with(0x16)
	check(k < 0, "no Brew (icon 0x16) for a Knights player without PDRU (0x4d3200: PDRU or race 1)")
	production.complete_research(0, "PDRU")
	fund()
	select_units(dwarves)
	k = cell_with(0x16)
	check(k >= 6 and bool(hud.cells[k].enabled), "Brew enabled with PDRU")
	var f = fighter(dwarves[0])
	# 2026-11-11: new units get the hero's aura (+2 speed, 0x51c460) on the next one-second pass (0x532a20); let it settle
	# before the baseline is read.
	advance(1.1)
	var combat_before: int = int(scene.combat.combat_block(f).combat)
	var speed_before: int = int(dwarves[0].base_speed)
	var gold: int = int(scene.economy.resources(0)[0])
	check(k >= 0 and hud.press_cell(k), "Brew pressed")
	check(int(scene.economy.resources(0)[0]) == gold - 30, "10 gold each (0x5285d0)")
	check(int(scene.combat.combat_block(f).combat) == combat_before + 4 and int(dwarves[0].base_speed) == speed_before + 4, "drunk: combat +4, speed +4")
	advance(121.0)
	check(int(scene.combat.combat_block(f).combat) == combat_before and int(dwarves[0].base_speed) == speed_before, "sober after 120 s: combat %d -> %d, speed %d -> %d" % [combat_before, int(scene.combat.combat_block(f).combat), speed_before, int(dwarves[0].base_speed)])
