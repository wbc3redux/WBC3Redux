extends RefCounted
## Skirmish setup state and its hand-over to the match (milestone 10a, SKIRMISH_RESEARCH.md).
## Setup records follow 0xa47a14 + slot * 0x38 and the options block 0xa479e8; resolve() follows 0x4de740, which copies
## both into the active-player table 0x708f94 (stride 0x2c), the options 0x70ae04 and the relation table 0x748915.

const NEUTRAL := 6
const SLOTS := 6
## 0xa498dc per slot: 0 open, 1 human, 2 computer (0x4eac50 active = 1 or 2, 0x4eac40 computer = 2). Closed (3) is the
## fourth state of the player button (0x4eb4d0 case 0x80 cycles 0..3); it is not active.
const OPEN := 0
const HUMAN := 1
const COMPUTER := 2
const CLOSED := 3
const RANDOM_RACE := 0x10                  # 0x4e45c0 default race 0x10; 0x4de740 replaces it with the pre-rolled 0x60f0f0 entry
const KNIGHT := 0                          # race index of the Knights (Building.cfg side letter H)
const GAME_MODE_SKIRMISH := 0              # 0x41da80 case 1 (main-menu button 0x98 "Skirmish") stores 0x748946 = 0
## Hand-over from the setup screen to main.tscn (the original keeps the same state in globals between the screens).
static var pending: Dictionary = {}
## RM-7: why a Random Map did not start (the loading screen's way back to the setup screen, which shows it).
static var start_error := ""

## 0x43e4d0 (Emulated, tests/skirmish_fixtures.json): +0x20..+0x26 per resource setting; other values keep 100/50/50/50.
static func starting_resources(setting: int) -> Array:
	match setting:
		0: return [20, 20, 20, 20]
		1: return [100, 100, 100, 100]
		2: return [300, 300, 300, 300]
		3: return [600, 600, 600, 600]
		4: return [1000, 1000, 1000, 1000]
	return [100, 50, 50, 50]

## 0x4e45c0 defaults plus 0x4e7760's copy of the scenario's side records (0xa496c0 + side * 0x2c, the SCN start records):
## race from side +2, colour +6, team +8, resources +0xc. The original's registry values (FogOfWar, HiddenMap, Quests,
## BuildLevel, ArmyPoints, Handicapping via 0x450970) replace the code defaults; the code defaults are used here.
static func defaults(map: Dictionary) -> Dictionary:
	var players: Array = []
	for i in SLOTS:
		players.append({"kind": OPEN, "race": RANDOM_RACE, "map_race": RANDOM_RACE, "colour": i, "team": 0, "resources": 2,
			"difficulty": 0, "start": Vector2i(-1, -1), "hero_id": "", "name": "", "custom_ai": ""})
	var starts: Array = map.get("starts", [])
	for s in starts:
		var i: int = int(s.side_index)
		if i < 0 or i >= SLOTS: continue
		var raw: PackedByteArray = String(s.raw_hex).hex_decode()
		var p: Dictionary = players[i]
		p.map_race = raw.decode_s16(2)
		p.colour = raw.decode_s16(6)
		p.team = raw.decode_s16(8)
		p.resources = raw.decode_s16(0xc)
		p.side_ai = raw.decode_s16(0x10)
		p.side_ai_fixed = raw[0x12] != 0
		# 0x4e7760 (map selection, line 149990): the side record's AI value, 2 when above 5 (Desert Sands: 2, Knight).
		p.difficulty = 2 if int(p.side_ai) > 5 else int(p.side_ai)
		p.start = Vector2i(int(s.cell[0]), int(s.cell[1]))
		# Milestone 11a: 0x4e7760 copies the side record's race into the setup record (+0x24 of 0xa47a14 + slot * 0x38), so
		# a slot plays the map's race until the race list changes it (Desert Sands: Dwarf and The Swarm).
		p.race = int(p.map_race)
	return {"map": String(map.get("source", "")), "map_width": int(map.get("size_cells", [128, 128])[0]),
		"sides": starts.size(), "local": 0, "players": players,
		# SCN header byte 0x14c (0x748a98): Standard Victory is evaluated only when set (Emulated copy 0x456370: 1 on Desert Sands).
		"standard_victory_event": 1,
		# 0x60f0f0: the race each slot plays when its setup race is Random (static 0..5 until Okay rolls them).
		"random_races": [0, 1, 2, 3, 4, 5],
		# S-2: scenarios hold Standard Victory as event 0 (Data: EVSH), so an option's event comes after it; a Random Map's
		# table is empty (0x41c7d0), main.gd clears this for a generated map.
		"scenario_events": 1,
		"options": {"vision": 1, "hidden_map": true, "quests": true, "build_level": 5, "army_points": 0, "handicap": false,
			"victory": 0, "no_dragons": false, "no_eyries": false, "no_titans": false, "tough_towers": false, "no_towers": false,
			"no_walls": false, "no_heroes": false, "random_weather": false, "resign_kills": true, "ai_resign": true,
			"temp_hero": false, "temp_hero_level": 10, "greatest": false, "tough_start_towers": false, "no_hero_items": false,
			# RM-6: the block 0xa48ec0, 0x450970's defaults for a missing registry value (Read, asm 0x450ab4..0x450b37). The value
			# one past each list is its "Random" entry (RANDOM_MAP_RESEARCH.md S2).
			"map_size": 2, "terrain": 0, "temples": 0, "critters": 1, "resource_level": 1, "no_starting_towers": false}}

## RM-6 (0x4e4000, 0x4e7760's Random Map branch, Read; .local/reference/original_skirmish_setup_1024x768.png): "Random Map" is
## chosen: six rows, every slot Open, nobody seated (0x60f198 = -1, here local = -1) and no side records. `random_map` marks
## the setup; the match start fills it with the generation inputs (simulation/random_map_match.gd).
static func random_setup(options: Dictionary = {}) -> Dictionary:
	var setup := defaults({"source": "Random Map", "size_cells": [128, 128], "starts": []})
	if not options.is_empty(): setup.options = options
	setup.sides = SLOTS
	setup.local = -1
	setup.random_map = {}
	return setup

static func is_random(setup: Dictionary) -> bool:
	return setup.has("random_map")

## The slots that will play: [{slot, race}] in slot order, what 0x583960 walks. Random races come from Okay's roll.
static func random_sides(setup: Dictionary) -> Array:
	var out: Array = []
	var rolled: Array = setup.get("random_races", [0, 1, 2, 3, 4, 5])
	for i in SLOTS:
		var p: Dictionary = setup.players[i]
		if int(p.kind) == HUMAN or int(p.kind) == COMPUTER:
			out.append({"slot": i, "race": int(rolled[i]) if int(p.race) == RANDOM_RACE else int(p.race)})
	return out

## 0x4eacd0 on a Random Map (Read): a seat, two active slots or more, and not all of them on one non-zero team.
static func can_start_random(setup: Dictionary) -> bool:
	if int(setup.local) < 0: return false
	var count := 0
	var mixed := false
	var previous := -1
	for i in SLOTS:
		var p: Dictionary = setup.players[i]
		if int(p.kind) != HUMAN and int(p.kind) != COMPUTER: continue
		count += 1
		var team := int(p.team)
		if team == 0 or (previous != -1 and team != previous): mixed = true
		previous = team
	return count >= 2 and mixed

## S-2: Rules (PNL_SS_GAMEMODS 0x132, rows 0x11d #0..6, strings 0xee [1..7]; 0xa47a05 + row * 2 -> 0x70ae21 + row * 2). The
## setup clears them when it opens (0x4e45c0), so they are not saved.
const RULES := ["no_dragons", "no_eyries", "no_titans", "tough_towers", "no_towers", "no_walls", "no_heroes"]
## S-2: More Options (PNL_SS_ADVANCEDOPTIONS 0x12f, rows 0x105 #0..6: strings 0xe9 [1..5], 0xec [0..1]): 0xa48ed0 ..,
## copied to 0x749c60 by 0x4de740 and saved by 0x450b80 under "Advanced Options" (registry names below).
const MORE_OPTIONS := ["random_weather", "resign_kills", "ai_resign", "temp_hero", "greatest", "tough_start_towers", "no_hero_items"]
const SAVED_MORE := {"random_weather": "RandomWeather", "ai_resign": "AICanResign", "greatest": "IAmTheGreatest", "resign_kills": "ResignationKillsSide",
	"tough_start_towers": "ThoughTowers", "temp_hero": "TournamentMode", "no_hero_items": "NoItems"}
const SAVED_MORE_SECTION := "Advanced Options"
const TEMP_HERO_MIN := 4                   # 0x4e9570: slider 0x177b range 4..0x32
const TEMP_HERO_MAX := 50

## S-2: 0x4dfec0 / 0x4e3c60 case 4, the victory list's side effects. Options 4..9 take the teams over (team 0, the shield
## disabled; Against the Horde: slot 0 team 1, the rest team 2) and give them back afterwards; 1, 4, 6 need a Keep level,
## 7 and 8 force Keep Level 5, Pitched Battle forces No Building and 50 army points (restored on leaving), Battle of Titans
## clears No Titans and No Heroes (restored on leaving).
static func choose_victory(setup: Dictionary, option: int):
	var o: Dictionary = setup.options
	var old := int(o.victory)
	if old == option: return
	if old == 10 and setup.has("saved_titan_rules"):
		o.no_titans = setup.saved_titan_rules[0]
		o.no_heroes = setup.saved_titan_rules[1]
		setup.erase("saved_titan_rules")
	if old == 0xb and option != 0xb and setup.has("saved_army_points"):
		o.army_points = int(setup.saved_army_points)
		setup.erase("saved_army_points")
	if setup.has("saved_build_level") and not (option in [7, 8, 0xb]):
		o.build_level = int(setup.saved_build_level)
		setup.erase("saved_build_level")
	match option:
		1, 4, 6:
			if int(o.build_level) == 0: o.build_level = 1
		7, 8:
			if not setup.has("saved_build_level"): setup.saved_build_level = int(o.build_level)
			o.build_level = 5
		0xb:
			if not setup.has("saved_army_points"): setup.saved_army_points = int(o.army_points)
			if not setup.has("saved_build_level"): setup.saved_build_level = int(o.build_level)
			o.army_points = 50
			o.build_level = 0
		10:
			setup.saved_titan_rules = [bool(o.no_titans), bool(o.no_heroes)]
			o.no_titans = false
			o.no_heroes = false
	if option >= 4 and option <= 9:
		if not setup.has("saved_teams"): setup.saved_teams = setup.players.map(func(p): return int(p.team))
		for i in setup.players.size():
			setup.players[i].team = 0 if option != 9 else (1 if i == 0 else 2)
	elif setup.has("saved_teams"):
		for i in setup.players.size(): setup.players[i].team = int(setup.saved_teams[i])
		setup.erase("saved_teams")
	o.victory = option

static func teams_locked(setup: Dictionary) -> bool:
	return int(setup.options.victory) >= 4 and int(setup.options.victory) <= 9

## 0x4e9ab0 row 4: "I Am The Greatest" ticks Resignation Kills Side... rows 0, 1 on, 2, 3 off and disables the hero level.
static func tick_greatest(edit: Dictionary):
	edit.random_weather = true
	edit.resign_kills = true
	edit.ai_resign = false
	edit.temp_hero = false

## 0x4ea050 with 0xa48ed6 set: the challenge preset (the setup is kept for a later untick): fixed options, the local slot on
## Very Low, every other side a computer Emperor on Very High, Random race, allied on team 1. While it is on the option
## buttons are locked (0x4e3c60 returns).
static func apply_greatest(setup: Dictionary, on: bool):
	if on:
		if setup.has("saved_greatest"): return
		setup.saved_greatest = {"options": setup.options.duplicate(true), "players": setup.players.duplicate(true), "local": int(setup.local)}
		if is_random(setup):                   # 0x4e7760's Random Map branch: seat 0, slots 1..3 computers, 4 and 5 closed
			setup.local = 0
			setup.players[0].kind = HUMAN
		var o: Dictionary = setup.options
		o.hidden_map = true
		o.quests = false
		o.army_points = 5
		o.vision = 2
		o.build_level = 5
		o.victory = 0
		o.handicap = false
		for rule in RULES: o[rule] = false
		for i in int(setup.sides):
			var p: Dictionary = setup.players[i]
			p.race = RANDOM_RACE
			if i == int(setup.local):
				p.resources = 0
				p.team = 0
			else:
				p.kind = CLOSED if is_random(setup) and i > 3 else COMPUTER
				p.difficulty = 6
				p.resources = 4
				p.team = 1
	elif setup.has("saved_greatest"):
		var keep := {}
		for key in MORE_OPTIONS: keep[key] = setup.options[key]
		keep.temp_hero_level = setup.options.temp_hero_level
		setup.options = setup.saved_greatest.options
		setup.players = setup.saved_greatest.players
		setup.local = int(setup.saved_greatest.get("local", setup.local))
		for key in keep: setup.options[key] = keep[key]
		setup.erase("saved_greatest")

## Okay on the setup screen (0x4e6af4..0x4e6b4c): six races of 1d16 - 1 (0..15) are rolled for the Random slots and
## stored in 0x60f0f0 (message 0xbe4 -> 0x4e0360). `roll` returns 1..sides.
static func roll_random_races(setup: Dictionary, roll: Callable):
	var races: Array = []
	for i in SLOTS: races.append(int(roll.call(16)) - 1)
	setup.random_races = races

## "Random Map Data" (0x450970 loads it when the setup opens, 0x4e45c0; 0x450760 saves it on Okay, 0x4e6bec): the
## original's registry values; the rebuild keeps them in its own file next to the settings file. ArmyPoints and
## BuildLevel are not saved when the victory is Pitched Battle (0xb). A value missing from the file keeps the code
## default of 0x4e45c0 (Decision: what the original reads for a missing registry value is Open).
const SAVED_SECTION := "Random Map Data"
## RM-6: option -> [value name, its "Random" value]. 0x450970 reads NoStartingTowers too, but 0x4e45c0 does not copy it to
## 0xa48eca, which no single-player control writes: it is saved (0x450760) and never read back here.
const SAVED_RANDOM := {"map_size": ["MapSize", 4], "terrain": ["TerrainType", 10], "temples": ["Temples", 5],
	"critters": ["CritterLevel", 5], "resource_level": ["ResourceLevel", 3]}

static func saved_options_path() -> String:
	return preload("res://simulation/game_settings.gd").file_path.get_basename() + "_randommap.cfg"

static func load_saved_options(options: Dictionary):
	var config := ConfigFile.new()
	if config.load(saved_options_path()) != OK: return
	var get_int := func(key: String, fallback: int) -> int:
		var v = config.get_value(SAVED_SECTION, key, fallback)
		return int(v) if (v is int or v is float) else fallback
	options.handicap = get_int.call("Handicapping", int(options.handicap)) != 0
	options.hidden_map = get_int.call("HiddenMap", int(options.hidden_map)) != 0
	options.quests = get_int.call("Quests", int(options.quests)) != 0
	options.army_points = clampi(get_int.call("ArmyPoints", int(options.army_points)), 0, 50)
	options.build_level = clampi(get_int.call("BuildLevel", int(options.build_level)), 0, 5)
	options.vision = clampi(get_int.call("FogOfWar", int(options.vision)), 0, 2)
	for key in SAVED_RANDOM:
		if options.has(key): options[key] = clampi(get_int.call(SAVED_RANDOM[key][0], int(options[key])), 0, int(SAVED_RANDOM[key][1]))
	# S-2: 0x450d00 reads the Advanced Options values (the defaults are 0x4531e0's 0x10100, hero level 10).
	for key in SAVED_MORE:
		if options.has(key):
			var v = config.get_value(SAVED_MORE_SECTION, SAVED_MORE[key], int(options[key]))
			options[key] = int(v) != 0 if (v is int or v is float) else bool(options[key])
	if options.has("temp_hero_level"):
		options.temp_hero_level = clampi(int(config.get_value(SAVED_MORE_SECTION, "TournamentModePoints", int(options.temp_hero_level))), TEMP_HERO_MIN, TEMP_HERO_MAX)

static func save_options(options: Dictionary) -> bool:
	var config := ConfigFile.new()
	config.load(saved_options_path())
	config.set_value(SAVED_SECTION, "Handicapping", int(options.handicap))
	config.set_value(SAVED_SECTION, "HiddenMap", int(options.hidden_map))
	config.set_value(SAVED_SECTION, "Quests", int(options.quests))
	if int(options.victory) != 0xb:
		config.set_value(SAVED_SECTION, "ArmyPoints", int(options.army_points))
		config.set_value(SAVED_SECTION, "BuildLevel", int(options.build_level))
	config.set_value(SAVED_SECTION, "FogOfWar", int(options.vision))
	config.set_value(SAVED_SECTION, "NoStartingTowers", int(bool(options.get("no_starting_towers", false))))
	for key in SAVED_RANDOM:
		if options.has(key): config.set_value(SAVED_SECTION, SAVED_RANDOM[key][0], int(options[key]))
	return config.save(saved_options_path()) == OK

## 0x4ea040 -> 0x450b80: More Options' Okay saves its values at once.
static func save_more_options(options: Dictionary) -> bool:
	var config := ConfigFile.new()
	config.load(saved_options_path())
	for key in SAVED_MORE: config.set_value(SAVED_MORE_SECTION, SAVED_MORE[key], int(bool(options.get(key, false))))
	config.set_value(SAVED_MORE_SECTION, "TournamentModePoints", int(options.get("temp_hero_level", 10)))
	return config.save(saved_options_path()) == OK

## The side row's shield (0x4eb4d0 case 0x7e): each click steps the slot's team 0..3 and wraps.
static func next_team(setup: Dictionary, slot: int):
	var p: Dictionary = setup.players[slot]
	p.team = (int(p.team) + 1) % 4

## The player button (0x4eb4d0 case 0x80, lines 152644-152653): a slot that becomes a computer gets the side record's AI value
## when side byte +0x12 is set, else 1 (Squire) when the value is non-zero, else 0. `level` >= 0 overrides it; KEEP_LEVEL keeps
## the slot's current level (the map's level from 0x4e7760, used when the screen opens with the slot already a computer).
const KEEP_LEVEL := -2
## The race list of the side row (0x4eb4d0 case 0x7b): string tables 0xf (races 0..7) and 0x68 (8..15), then "Random"
## (0x53 / 0) = 0x10; the choice is stored in the setup record (0x4eb030) and clears the slot's CustomAI name.
const RACE_CHOICES := 17
static func set_race(setup: Dictionary, slot: int, race: int):
	setup.players[slot].race = clampi(race, 0, RANDOM_RACE)
	setup.players[slot].custom_ai = ""                        # 0x4eb030 clears the CustomAI name (setup record +0xa)

## AI-4: the CustomAI file of a computer row (setup record 0xa498f8 + slot * 0x2a, +0xa = 0xa49902; chosen in
## PNL_SELECTAIFILE, simulation/custom_ai.gd). "" = none.
static func set_custom_ai(setup: Dictionary, slot: int, file: String):
	setup.players[slot].custom_ai = file

static func next_race(race: int) -> int:
	return (race + 1) % RACE_CHOICES

static func set_kind(setup: Dictionary, slot: int, kind: int, level: int = -1):
	var p: Dictionary = setup.players[slot]
	p.kind = kind
	if kind != COMPUTER or level == KEEP_LEVEL: return
	if level >= 0: p.difficulty = level
	elif p.get("side_ai_fixed", false): p.difficulty = int(p.get("side_ai", 0))
	else: p.difficulty = 1 if int(p.get("side_ai", 0)) != 0 else 0

## 0x4de740: the setup records become the player table. Returns the resolved match setup used by the match start.
static func resolve(setup: Dictionary) -> Dictionary:
	var slots: Array = []
	var options: Dictionary = setup.options
	if int(options.victory) == 0xb: options.army_points = 50  # 0x4de740: Pitched Battle, 0xa47a02 = 0x32
	for i in 7:
		var slot := {"active": false, "computer": false, "race": 0, "colour": 0, "team": 0, "resources": 0, "difficulty": 2,
			"start": Vector2i(-1, -1), "hero_id": "", "name": ""}
		if i < SLOTS and i < setup.players.size():
			var p: Dictionary = setup.players[i]
			slot.start = p.start
			if p.kind == HUMAN or p.kind == COMPUTER:
				slot.active = p.start.x >= 0                      # a slot needs a start record of the map
				slot.computer = p.kind == COMPUTER                # 0x70d6a4
				var rolled: Array = setup.get("random_races", [0, 1, 2, 3, 4, 5])
				slot.race = int(rolled[i]) if int(p.race) == RANDOM_RACE else int(p.race)
				slot.colour = int(p.colour)
				slot.team = int(p.team)
				slot.resources = int(p.resources)
				# 0x4eaca0 / 0x4de740: slot +0x10 = 0xa49888, or 7 (Rampant) for a non-zero value when the victory option is
				# 0xb (Pitched Battle, 0x4eaca0) or BuildLevel is 0 (0x4de740).
				var d: int = int(p.difficulty)
				slot.difficulty = 7 if ((int(options.build_level) == 0 or int(options.victory) == 0xb) and d != 0) else d
				slot.hero_id = String(p.get("hero_id", ""))
				slot.name = String(p.get("name", ""))
				slot.custom_ai = String(p.get("custom_ai", "")) if p.kind == COMPUTER else ""   # AI-4: 0x5059a0 reads 0xa49902
		slots.append(slot)
	# 0x748915 [a + b * 7]: 1 for the same slot or the same non-zero team; the neutral row and column are 0 except (6,6),
	# which the loop writes as 0x748945 = 1. Six slots plus the neutral player.
	var allied := PackedByteArray()
	allied.resize(49)
	for a in 7:
		for b in 7:
			if a == NEUTRAL and b == NEUTRAL: allied[48] = 1
			elif a == NEUTRAL or b == NEUTRAL: allied[b + a * 7] = 0
			elif a == b or (int(slots[a].team) != 0 and slots[a].team == slots[b].team): allied[b + a * 7] = 1
	return {"slots": slots, "allied": allied, "local": int(setup.local), "game_mode": GAME_MODE_SKIRMISH,
		"standard_victory_event": int(setup.get("standard_victory_event", 1)), "scenario_events": int(setup.get("scenario_events", 1)),
		"options": options.duplicate(true), "map_width": int(setup.map_width), "map": setup.map}

static func active_players(resolved: Dictionary) -> Array:
	var result: Array = []
	for i in SLOTS:
		if resolved.slots[i].active: result.append(i)
	return result
