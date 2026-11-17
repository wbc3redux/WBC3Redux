extends SceneTree
## Setup rows (OPEN_ITEMS.md to-do 3, SKIRMISH_RESEARCH.md "Setup rows"): Random Weather, AI Resignation, Tough Starting
## Towers and No Hero Items against tests/setup_rows_fixtures.json (tools/emulate_setup_rows.py, the original under
## Unicorn), then each row in a headless match on Desert Sands in the real scene. Never touches user://heroes.

const DayNight = preload("res://simulation/day_night.gd")
const AiResignation = preload("res://simulation/ai_resignation.gd")
const Encounters = preload("res://simulation/encounters.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const MapData = preload("res://core/map_data.gd")

const SETTERS := {"0x49bfb0": [0x50, false], "0x49bf60": [0x96, false], "0x49bf10": [0x200, false], "0x49c0a0": [0x50, true],
	"0x49c050": [0x96, true], "0x49c000": [0x200, true]}
const STARTS := {"day dry": [false, ""], "day rain": [false, "0x49bfb0"], "day storm": [false, "0x49c0a0"],
	"night dry": [true, ""], "night rain": [true, "0x49bfb0"], "night storm": [true, "0x49c0a0"],
	"day heavy rain": [false, "0x49bf10"], "night heavy storm": [true, "0x49c000"]}

var checks := 0
var failures := 0
var store
var directory := ""

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Setup rows check failed: ", label)

## The match generator 0x458e70 with forced draws (each must be (1, 100, 0)); an extra draw returns -999.
class Forced:
	var values: Array = []
	var calls: Array = []
	func _init(list: Array = []):
		values = list.duplicate()
	func roll(count: int, sides: int, bonus: int = 0) -> int:
		calls.append([count, sides, bonus])
		return int(values.pop_front()) if not values.is_empty() else -999

func _initialize():
	call_deferred("run")

func run():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/setup_rows_fixtures.json"))
	weather_checks(fixtures)
	resign_checks(fixtures)
	tower_checks(fixtures)
	item_checks()
	directory = "user://setup-rows-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	store = Store.new(directory)
	var profile = Profile.create("test-knight", "Sir Test")
	profile.data.equipment[0] = {"item": 3}                 # Giant's Helm: combat + 12 (item power type 1)
	profile.data.equipment[2] = {"item": 10}                # Dwarven Shortsword: combat + 3, piercing damage + 10 (0x5a)
	check(store.save_profile(profile), "copied test profile saved")
	Settings.use_file(directory.path_join("settings.cfg"))
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	match_checks(scene)
	scene.end_skirmish()
	if scene.encounters != null: scene.encounters.dispose()
	scene.free()
	Settings.use_file(Settings.DEFAULT_PATH)
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures > 0:
		printerr("Setup rows checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Setup rows checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ Random Weather
func weather(name: String) -> DayNight:
	var dn := DayNight.new(true)
	var start: Array = STARTS[name]
	if bool(start[0]):
		dn.hour = DayNight.NIGHT_CLOCK[0]
		dn.mark_a = DayNight.NIGHT_CLOCK[1]
		dn.mark_b = DayNight.NIGHT_CLOCK[2]
	if String(start[1]) != "":
		var s: Array = SETTERS[String(start[1])]
		dn.set_rain(int(s[0]), bool(s[1]))
		steady(dn)
	return dn

## tools/emulate_setup_rows.py frames_until_steady: draws until the (drops, raining) pair repeats.
func steady(dn: DayNight) -> int:
	var last := []
	for n in 2000:
		dn.rain_frame()
		var now := [dn.drops, dn.raining]
		if now == last: return n
		last = now
	return 2000

func weather_checks(fixtures: Dictionary):
	var bad := 0
	for r in fixtures.weather_roll:
		var dn := weather(String(r.start))
		dn.random_weather = int(r.option) == 1
		dn.weather_timer_ms = 0
		dn.clock_ms = 500000
		if dn.state_code() != int(r.code): bad += 1
		var forced: Array = []
		for d in r.draws: forced.append(int(r.chances[int(d[0])]) if int(d[0]) < 4 else int(r.last))
		dn.rng = Forced.new(forced)
		var sent := dn.weather_roll(500000)
		var want := -1
		if not r.sent.is_empty():
			var raw: PackedByteArray = String(r.sent[0][1]).hex_decode()
			want = raw.decode_s16(0)
		if sent != want or dn.rng.calls.size() != r.draws.size() or dn.weather_timer_ms != int(r.timer) and sent < 0: bad += 1
		elif dn.rng.calls.any(func(c): return c != [1, 100, 0]): bad += 1
	check(bad == 0, "0x49e360: %d weather rolls (draws, message 0x1ff, timer): %d differ" % [fixtures.weather_roll.size(), bad])
	bad = 0
	var paused := 0
	for r in fixtures.weather_timer:
		if int(r.speed) < 1:
			paused += 1                       # game speed 0: the rebuild's clock does not run (Provisional, the header)
			continue
		var dn := weather("night dry" if bool(r.night) else "day dry")
		dn.random_weather = int(r.option) == 1
		dn.weather_timer_ms = int(r.stored)
		dn.rng = Forced.new([100, 100, 100, 100, 100])
		dn.weather_roll(int(r.now))
		if dn.weather_timer_ms != int(r.timer) or (dn.rng.calls.size() > 0) != (int(r.draws) > 0): bad += 1
	check(bad == 0 and paused == 3, "0x49e360's timer: due at +0x1cd628 + 100000, then now + 100000: %d differ" % bad)
	bad = 0
	for r in fixtures.weather_apply:
		var dn := weather(String(r.start))
		dn.clock_ms = 700000
		dn.weather_timer_ms = 123
		dn.apply_weather(int(r.target))
		var a: Dictionary = r.after
		var got := [int(dn.raining), int(dn.stopping), int(dn.storm), dn.rain_target, dn.rain_floor, dn.drops, dn.mode, dn.weather_timer_ms]
		var want := [int(a.rain), int(a.stopping), int(a.storm), int(a.target), int(a.floor), int(a.drops), int(a.fade), int(a.timer)]
		var ticks := 0
		while dn.mode != 0 and ticks < 4000:
			dn._transition_tick()
			ticks += 1
		var frames := steady(dn)
		var s: Dictionary = r.settled
		got.append_array([ticks, frames, int(dn.is_night()), int(dn.raining), dn.drops, dn.state_code()])
		want.append_array([int(r.fade_ticks), int(r.frames), int(s.night), int(s.rain), int(s.drops), int(s.code)])
		if got != want:
			bad += 1
			if bad < 4: printerr("apply %s %d: %s != %s" % [r.start, r.target, got, want])
	check(bad == 0, "0x49e690: %d weather messages from eight starts (clock, rain, storm, drops, timer, fade): %d differ" % [fixtures.weather_apply.size(), bad])
	bad = 0
	for c in fixtures.rain_frames:
		var dn := DayNight.new(true)
		for step in c.steps:
			if String(step.setter) == "0x49bd90": dn.stopping = true if dn.raining else dn.stopping
			else:
				var s: Array = SETTERS[String(step.setter)]
				dn.set_rain(int(s[0]), bool(s[1]))
			for d in step.drops:
				dn.rain_frame()
				if dn.drops != int(d[0]) or int(dn.raining) != int(d[1]): bad += 1
			var st: Dictionary = step.state
			if dn.rain_target != int(st.target) or dn.rain_floor != int(st.floor) or int(dn.storm) != int(st.storm): bad += 1
	check(bad == 0, "0x49b6d0: the drop count frame by frame over %d rain lives: %d differ" % [fixtures.rain_frames.size(), bad])
	# Off (DayNight setting): no weather object, nothing rolls or rains (0x41e9xx calls 0x49e360 only with DAT_00a38cc0).
	var off := DayNight.new(false)
	off.random_weather = true
	off.rng = Forced.new([1, 1])
	check(off.weather_roll(500000) == -1 and off.rng.calls.is_empty() and not off.raining, "Day / Night Off: no weather roll")
	# Rain's combat term reaches the getter (0x51bd10, B1-3 fixtures): a STATUS 0x2 unit is 1 lower while it rains.
	var dn := weather("day rain")
	check(dn.raining and dn.combat_value(5, 0x2, "AHKX") == 4 and weather("day dry").combat_value(5, 0x2, "AHKX") == 5, "raining: the rain term of 0x51bd10")
	# Save: the generator reference stays out of the state.
	var state := dn.save_state()
	check(not state.has("rng") and bool(state.raining) and int(state.drops) == 300, "save state: rain kept, no generator reference")

# ------------------------------------------------------------------------------------------------ AI Resignation
func resign_checks(fixtures: Dictionary):
	var bad := 0
	var yes := 0
	for r in fixtures.resign:
		var t := {"active": r.active, "out": r.out, "computer": r.computer, "hero": r.hero, "population": r.population,
			"limit": r.limit, "allied": r.allied, "victory": int(r.victory)}
		var got := AiResignation.should_resign(int(r.me), t)
		if got != (int(r.resign) == 1): bad += 1
		if got: yes += 1
	check(bad == 0 and yes > 50, "0x4fc5a0(1): %d tables, %d resign: %d differ" % [fixtures.resign.size(), yes, bad])

# ------------------------------------------------------------------------------------------------ Tough Starting Towers
func level_of(lv: Dictionary) -> int:
	var level := 0
	for i in 6:
		if bool(lv.computer[i]): continue
		level = maxi(level, int(lv.setup[i]))
		level = maxi(level, int(lv.local_level) if int(lv.local) == i else int(lv.heroes[i]))
	return level

## A BUI-shaped definition from the record fields (0x43bd50's layout, tools/emulate_setup_rows.py tower_record).
func definition_of(f: Dictionary) -> Dictionary:
	var raw := PackedByteArray()
	raw.resize(200)
	raw.encode_s16(0x24, int(f.combat))
	raw.encode_s16(0x26, int(f.period))
	raw.encode_s16(0x28, int(f.mres))
	raw.encode_s16(0x2a, int(f.hp))
	raw.encode_s16(0x2e, int(f.armour))
	raw.encode_s16(0x38, int(f.damage))
	raw.encode_s16(0x3a, int(f.dtype))
	raw.encode_s16(0x3c, int(f.range))
	return {"raw_hex": raw.hex_encode(), "hit_points": int(f.hp)}

func tower_fields(definition: Dictionary, terms: Dictionary) -> Array:
	var raw: PackedByteArray = String(definition.raw_hex).hex_decode()
	return [raw.decode_s16(0x24) + int(terms.get("combat", 0)), raw.decode_s16(0x26) + int(terms.get("period", 0)), raw.decode_s16(0x28),
		int(definition.hit_points), raw.decode_s16(0x2e), raw.decode_s16(0x38) + int(terms.get("damage", 0)), raw.decode_s16(0x3a),
		raw.decode_s16(0x3c), int(definition.hit_points)]

func fixture_fields(f: Dictionary) -> Array:
	return [int(f.combat), int(f.period), int(f.mres), int(f.hp), int(f.armour), int(f.damage), int(f.dtype), int(f.range), int(f.max_hp)]

func tower_checks(fixtures: Dictionary):
	var bad := 0
	var tough := 0
	for r in fixtures.start_towers:
		if int(r.flag) == 0:
			if fixture_fields(r.after) != fixture_fields(r.before): bad += 1      # flag 0 (mines, sites): no start terms
			continue
		var definition := definition_of(r.before)
		var terms := Encounters.tower_start_terms(definition, int(r.tough) == 1, level_of(r.levels), int(r.mode), true)
		if int(r.tough) == 1: tough += 1
		if tower_fields(definition, terms) != fixture_fields(r.after):
			bad += 1
			if bad < 4: printerr("start tower: %s != %s" % [tower_fields(definition, terms), fixture_fields(r.after)])
	check(bad == 0 and tough > 50, "0x418700 (flag 1): %d race towers of a random map, %d tough: %d differ" % [fixtures.start_towers.size(), tough, bad])
	bad = 0
	tough = 0
	for r in fixtures.map_towers:
		if Encounters.race_building(String(r.code), int(r.race)) != String(r.swapped): bad += 1
		if int(r.flag) == 1:
			if fixture_fields(r.after) != fixture_fields(r.message): bad += 1      # +0x43 set: 0x4a50f0 keeps the record
			continue
		var raw: PackedByteArray = String(r.bui).hex_decode()
		var definition := {"raw_hex": r.bui, "hit_points": raw.decode_s16(0x2a)}
		var terms := Encounters.tower_start_terms(definition, int(r.tough) == 1, level_of(r.levels), int(r.mode), false)
		if int(r.tough) == 1: tough += 1
		if tower_fields(definition, terms) != fixture_fields(r.after):
			bad += 1
			if bad < 4: printerr("map tower: %s != %s" % [tower_fields(definition, terms), fixture_fields(r.after)])
	check(bad == 0 and tough > 100, "0x4a50f0: %d scenario towers (race swap, copy, tough, level terms), %d tough: %d differ" % [fixtures.map_towers.size(), tough, bad])

# ------------------------------------------------------------------------------------------------ No Hero Items
func item_checks():
	var block := {"skills": [[0x22, 0, 2]], "equipment": [3, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0], "hero": true, "hp": 50,
		"stats": [1, 1, 1, 1], "level": 1, "class": 0, "race": 0}
	check(HeroEffects.item_stat(block, 1) == 15 and HeroEffects.attack(10, 6, block).dtype == 0, "with items: combat + 15, the sword's piercing damage")
	var plain: Dictionary = HeroEffects.attack(10, 6, block)
	block["no_items"] = true
	check(HeroEffects.item_stat(block, 1) == 0 and HeroEffects.item_power(block, 1, 12) == 0, "No Hero Items: 0x40c380 / 0x40c500 read 0 (0x749c68)")
	var none: Dictionary = HeroEffects.attack(10, 6, block)
	check(none.dtype == 6 and int(none.dmg) == 10 + HeroEffects.skill_effect(block, 0x22) and int(plain.dmg) == int(none.dmg) + 10,
		"No Hero Items: 0x526310 skips the weapon (damage type stays slashing), Mighty Blow stays")
	block.skills = [[0x22, 0, 0]]
	block.equipment = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var skill_item := -1
	for id in range(1, int(HeroEffects.items_data().get("count", 0)) + 1):
		for p in HeroEffects.item(id).get("powers", []):
			if int(p.type) == HeroEffects.TYPE_HERO_SKILL and int(p.data) == 0x22 and skill_item < 0: skill_item = id
	if skill_item > 0:
		block.equipment[0] = skill_item
		check(HeroEffects.lookup(block, 0x22) > 0, "No Hero Items: 0x556b50 does not read the flag, an item's skill rank stays")

# ------------------------------------------------------------------------------------------------ in a match
func new_setup(edit: Callable = Callable()) -> Dictionary:
	MapData.select("desert-sands")
	var setup := Setup.defaults(MapData.map())
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 3)
	if edit.is_valid(): edit.call(setup)
	return setup

func start(scene, edit: Callable = Callable()):
	check(scene.start_skirmish(new_setup(edit), "test-knight", store, "setup-rows-%d" % randi()), "the match starts")
	return scene.skirmish

func step(scene, seconds: float):
	for i in roundi(seconds * 60.0):
		if scene.skirmish.over: return
		scene.simulation_step(1.0 / 60.0)

func towers_of(scene) -> Array:
	return scene.production.buildings.values().filter(func(b): return String(b.original_type_id).begins_with("BWT"))

func hero_of(scene, owner: int):
	for unit in scene.units:
		if unit.owner_id == owner and scene.is_hero_unit(unit): return unit
	return null

func match_checks(scene):
	# Tough Starting Towers: every scenario tower (0x4a50f0, +0x43 clear), owner's race (Knights: BWTC), level 1 hero.
	start(scene)
	var plain: Array = towers_of(scene)
	var bui: Dictionary = scene.encounters.catalogue_record("buildings", "BWTC")
	var raw: PackedByteArray = String(bui.raw_hex).hex_decode()
	var level := 1
	check(plain.size() == 4 and plain.all(func(b): return int(b.definition.hit_points) == int(bui.decoded.hit_points) + 10 * level), "off: Building.cfg hit points + 10 L")
	start(scene, func(setup): setup.options.tough_start_towers = true)
	var tough: Array = towers_of(scene)
	var mine: Array = tough.filter(func(b): return int(b.owner) == 0)     # player 1's towers carry the computer's combat term
	var t = mine[0] if not mine.is_empty() else null
	check(tough.size() == 4 and tough.all(func(b): return int(b.definition.hit_points) == 750 + 10 * level), "Tough Starting Towers: 750 + 10 L hit points (0x4a50f0)")
	if t != null:
		var tower: Dictionary = scene.combat.towers[t.entity_id]
		check(int(tower.damage) == CombatRules.i16(raw, 0x38) * 2 + level / 4 and int(tower.range) == CombatRules.i16(raw, 0x3c) + 1, "Tough Starting Towers: damage x 2, range + 1")
		check(int(tower.period) == scene.combat.TOWER_PERIOD_MS[3 + level / 20], "Tough Starting Towers: shot period index 3")
		check(int(scene.combat.building_block(t).combat) == CombatRules.i16(raw, 0x24) * 2, "Tough Starting Towers: combat x 2")
	# No Hero Items: the bound heroes' blocks carry the flag; the helm's + 12 and the sword are gone.
	var hero = hero_of(scene, 0)
	var with_items: Dictionary = scene.combat.hero_block(0)
	check(hero != null and HeroEffects.item_stat(with_items, 1) == 15 and not with_items.has("no_items"), "items count by default")
	start(scene, func(setup): setup.options.no_hero_items = true)
	var no_items: Dictionary = scene.combat.hero_block(0)
	check(bool(no_items.get("no_items", false)) and HeroEffects.item_stat(no_items, 1) == 0 and bool(scene.combat.hero_block(1).get("no_items", false)),
		"No Hero Items: both heroes' item terms read 0 in the match (0x749c68)")
	# Random Weather: the option and the generator reach the weather object; on a clear day the roll draws only with it.
	start(scene)
	var dn = scene.day_night
	check(dn != null and not dn.random_weather and dn.rng == scene.combat.rng, "the weather object rolls with the match generator")
	var spy := Forced.new([100, 100, 100, 100, 100])
	dn.rng = spy
	dn.weather_timer_ms = scene.game_ms() - DayNight.ROLL_PERIOD_MS
	step(scene, 0.2)
	check(dn.weather_timer_ms > scene.game_ms() and spy.calls.is_empty(), "off, clear day: due, but no draw (0x49e360)")
	start(scene, func(setup): setup.options.random_weather = true)
	dn = scene.day_night
	spy = Forced.new([1, 50])                                # the first chance (< 12): kind 2 -> a clear day stays clear
	dn.rng = spy
	dn.weather_timer_ms = scene.game_ms() - DayNight.ROLL_PERIOD_MS
	step(scene, 0.2)
	check(dn.random_weather and dn.weather_timer_ms > scene.game_ms() and spy.calls.size() == 2, "Random Weather: the clear day rolls (0x749c60)")
	spy = Forced.new([100, 100, 1, 74])                      # the third chance (< 20): kind 0xff, last <= 74 -> night
	dn.rng = spy
	dn.weather_timer_ms = scene.game_ms() - DayNight.ROLL_PERIOD_MS
	step(scene, 4.0)
	check(dn.is_night() and spy.calls.size() == 4 and dn.log.any(func(e): return e.get("event") == "weather" and int(e.code) == 7), "Random Weather: night falls in the match")
	spy = Forced.new([100, 100, 1, 1])                       # night: kind 0xff -> 8, rain by night
	dn.rng = spy
	dn.weather_timer_ms = scene.game_ms() - DayNight.ROLL_PERIOD_MS
	step(scene, 0.2)
	check(dn.raining and not dn.storm and dn.state_code() == 8, "Random Weather: rain by night (code 8)")
	# AI Resignation: the computer's hero falls; once its corpse is gone, with nothing above 5 / 15 and an enemy with more
	# than ten times its population, it resigns on its next update.
	for on in [true, false]:
		var m = start(scene, func(setup): setup.options.ai_resign = on)
		# Thirty Swordsmen for the human side, counted as trained ones are (0x533dc0 reads them through production).
		for i in 30:
			var u = scene.add_unit("AHKX", scene.navigator.free_cell_near(Vector2i(m.slots[0].start)), 0)
			scene.production.register_unit(u.unit_id, "AHKX", 0)
		# A finished Keep keeps the computer in for Standard Victory (0x514670 counts it) once its hero is gone.
		scene.encounters.place_site("BKK0", 1, Vector2i(m.slots[1].start) + Vector2i(-8, 6))
		var enemy = hero_of(scene, 1)
		scene.combat.apply_damage("unit", enemy.unit_id, 1000000, -1)
		var waited := 0.0
		while AiResignation.hero_present(scene.combat, 1) and waited < 40.0:
			step(scene, 1.0)
			waited += 1.0
		var t1: Dictionary = AiResignation.table(m, scene)
		check(not AiResignation.hero_present(scene.combat, 1) and int(t1.population[1]) <= 5 and int(t1.limit[1]) <= 15 and int(t1.population[0]) > 10 * int(t1.population[1]),
			"the computer is down to nothing (population %s, limit %s)" % [t1.population, t1.limit])
		for i in 30:
			if bool(m.eliminated[1]): break
			step(scene, 0.1)
		if on:
			check(bool(m.eliminated[1]) and m.log.any(func(e): return bool(e.get("resigned", false))), "AI Resignation: the computer resigns (0x4fc5a0 -> 0x534340, 0x21c)")
			check(String(scene.last_message).contains("has resigned"), "the message line: %s" % scene.last_message)
			check(scene.production.buildings.values().all(func(b): return int(b.owner) != 1 or int(b.hit_points) <= 0), "its towers are handed over (0x534340)")
			step(scene, 3.0)
			check(m.over and bool(m.outcome.won), "the next victory check: the human side wins")
		else:
			check(not bool(m.eliminated[1]) and not m.over, "AI Resignation off: the computer stays")
