extends SceneTree
## S-3 (ENCOUNTERS_RESEARCH.md "S-3"): every lair code a map places joins the spawner (0x404b70) with its own row of the lair
## table: BLBM, BLHN, BLGL, BLGH and BSBS on Random Maps from fixed generator words, each through a real match start, a timed
## wave, an attack response and its boss. BSAL is on no imported map and no Random Map's site list: the table check covers it.
## Never touches user://heroes or the player's settings.

const MapData = preload("res://core/map_data.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const RandomMapMatch = preload("res://simulation/random_map_match.gd")
const Encounters = preload("res://simulation/encounters.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")

const HERO := "test-lair-knight"
const CODES := ["BLBM", "BLHN", "BLGL", "BLGH", "BSBS"]
const MAX_MAPS := 24
## Row index -> the table's boss (tools/emulate_unit_ai.py, Emulated): the row belongs to its code.
const BOSSES := {"BLBM": "AUAX", "BLHN": "AAHA", "BLGL": "AMJX", "BLGH": "AONX", "BSBS": "AKOX", "BSAL": "AKJX"}

var checks := 0
var failures := 0
var store
var covered := {}

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Lair code check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var tag := Crypto.new().generate_random_bytes(8).hex_encode()
	var directory := "user://lair-tests-" + tag
	store = Store.new(directory)
	check(store.save_profile(Profile.create(HERO, "Sir Lair")), "test profile saved")
	Settings.use_file("user://lair-settings-%s.cfg" % tag)
	table_checks()
	RandomMapMatch.reset_session()
	RandomMapMatch.clock_due = false       # fixed words: the same maps on every run
	var made_maps := 0
	while covered.size() < CODES.size() and made_maps < MAX_MAPS:
		var setup := setup_for(1 + made_maps % 2, 1 + made_maps % 8)
		var made := RandomMapMatch.prepare(setup)
		made_maps += 1
		if not bool(made.ok): continue
		var fresh: Array = placed_lairs(made).filter(func(code): return not covered.has(code))
		if not fresh.is_empty(): await play(made, setup, made_maps)
	check(covered.size() == CODES.size(), "every code met in %d maps: %s" % [made_maps, covered.keys()])
	RandomMapMatch.reset_session()
	MapData.select(MapData.DEFAULT)
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(Setup.saved_options_path())
	DirAccess.remove_absolute("user://lair-settings-%s.cfg" % tag)
	if failures > 0:
		printerr("Lair code checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Lair code checks passed: %d" % checks)
	quit()

func setup_for(size: int, terrain: int) -> Dictionary:
	var setup := Setup.random_setup()
	var o: Dictionary = setup.options
	o.map_size = size
	o.terrain = terrain
	o.temples = 4                          # 0x159: the most utilities
	o.critters = 0
	o.resource_level = 1
	setup.local = 0
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = HERO
	Setup.set_kind(setup, 1, Setup.COMPUTER, 2)
	Setup.roll_random_races(setup, func(sides): return 5 % sides + 1)
	return setup

func placed_lairs(made: Dictionary) -> Array:
	return made.placed.buildings.map(func(b): return String(b.code)).filter(func(code): return Encounters.LAIRS.has(code))

## The six codes against the six rows (0x404b70's comparisons, the table 0x5fb338).
func table_checks():
	var table: Array = UnitAI.load_data().lairs
	check(table.size() == 6 and Encounters.LAIRS.size() == 6, "six rows, six codes")
	for code in Encounters.LAIRS:
		var row: Dictionary = table[int(Encounters.LAIRS[code])]
		check(String(row.boss) == String(BOSSES[code]), "%s is row %d, boss %s" % [code, int(Encounters.LAIRS[code]), BOSSES[code]])

func play(made: Dictionary, setup: Dictionary, number: int):
	MapData.select_generated(made.bundle)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.start_skirmish(setup, HERO, store, "lair-test-%d" % number), "map %d: the match starts" % number)
	var enc = scene.encounters
	var codes: Array = placed_lairs(made)
	check(enc.lairs.size() == codes.size(), "map %d: all %d lairs adopted (%s)" % [number, codes.size(), codes])
	var now: int = scene.combat.now_ms
	for entry in enc.lairs:
		var b = scene.production.building(int(entry.building))
		var code := String(b.original_type_id)
		var row: Dictionary = enc.lair_table[int(entry.lair)]
		check(int(entry.lair) == int(Encounters.LAIRS[code]) and int(b.owner) == Encounters.NEUTRAL, "%s: its row, neutral" % code)
		check(int(entry.next_ms) >= now + int(row.max_ms) and int(entry.next_ms) < now + 2 * int(row.max_ms), "%s: first wave at max + 1d(max / 1000) - 1 s (0x404b70)" % code)
		lair_behaviour(scene, enc, entry, code, row)
		covered[code] = true
	scene.advance_seconds(1.0)
	check(enc.lairs.all(func(e): return not e.active), "map %d: destroyed lairs stay out of the spawner" % number)
	scene.end_skirmish()
	scene.queue_free()
	await process_frame
	await process_frame

## A timed wave from the table's row, a full wave when the lair is hit, the boss when it falls.
func lair_behaviour(scene, enc, entry: Dictionary, code: String, row: Dictionary):
	var types := {}
	for e in row.entries:
		types[String(e.type_a)] = true
		types[String(e.type_b)] = true
	var logged: int = enc.log.size()
	entry.next_ms = 0
	enc.next_lair_check = -1
	enc.update(scene.combat.now_ms)
	check(int(entry.waves) == 1 and enc.log.size() > logged, "%s: a timed wave" % code)
	var spawned: Array = enc.log.slice(logged)
	check(spawned.all(func(s): return types.has(String(s.type)) and int(s.unit) >= 0), "%s: units of its row, all created" % code)
	check(spawned.all(func(s): return int(scene.units[int(s.unit)].owner_id) == Encounters.NEUTRAL), "%s: the wave is neutral" % code)
	entry.response_ms = 0
	var id := int(entry.building)
	scene.combat.apply_damage("building", id, 1, scene.hero_unit_id)
	check(int(entry.waves) == 2, "%s: a hit calls a wave (0x404b10)" % code)
	logged = enc.log.size()
	var b = scene.production.building(id)
	scene.combat.apply_damage("building", id, int(b.hit_points) + 1, scene.hero_unit_id)
	check(not bool(entry.active), "%s: destroyed, the spawner stops (0x404ac0)" % code)
	var after: Array = enc.log.slice(logged)
	check(after.any(func(s): return s.has("boss") and String(s.boss) == String(row.boss) and int(s.unit) >= 0), "%s: its boss %s appears" % [code, row.boss])
	check(scene.production.building(id) == null, "%s: the building is gone" % code)
