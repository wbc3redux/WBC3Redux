extends SceneTree
## Milestone 11b (HERO_RESEARCH.md "Milestone 11b"): hero races and classes.
## 1. Creation: HeroProfile.create for all 16 races x 28 classes equals the emulated creation screen
##    (tests/hero_creation_fixtures.json: 0x54b770(1) then 0x54bfe0 / 0x54bee0 under Unicorn), and the records validate.
## 2. The slot-race rule (Read: 0x4e7760, 0x4eb4d0, 0x4ef650, 0x4de740, 0x43b550, 0x4e2790 line 147302, 0x4549a7): the
##    slot plays the setup race (the map's by default, changed by the race list), the hero stays its own race's unit, the
##    lord skill follows the slot race (0x5269a0), and the per-race games / wins counters are indexed by the slot race.
## 3. A Dwarf hero created, saved, spawned as ADHX in main.tscn with its class's numbers, an item equipped in the match,
##    a victory and the writeback (XP, battles won, the Dwarf win counter), reloaded as a Dwarf.
## Never touches user://heroes (fresh test directories, removed at the end).

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")
const Effects = preload("res://simulation/hero_effects.gd")
const Rules = preload("res://simulation/production_rules.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Hero races check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	creation_matrix()
	validation()
	var directory := "user://hero-races-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	dwarf_match(scene, store)
	slot_race_rule(scene, store)
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures > 0:
		printerr("Hero races checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Hero races checks passed: %d" % checks)
	quit(0)

func ints(values: Array) -> Array:
	return values.map(func(v): return int(v))

# -------------------------------------------------------------------------------------------- 1. creation
func creation_matrix():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_creation_fixtures.json"))
	check(bool(fixtures.order_independent), "class-then-race equals race-then-class (0x54bee0 / 0x54bfe0)")
	var opened: Dictionary = fixtures.opened
	check(int(opened.race) == 0 and int(opened.class_id) == 0 and String(opened.art) == "AHHX", "the screen opens on Knight / Warrior")
	check(HeroRules.race_droplist() == ints(fixtures.tables.race_droplist) and HeroRules.class_droplist() == ints(fixtures.tables.class_droplist), "shipped droplists equal the fixtures")
	check(HeroRules.race_droplist().size() == 16 and HeroRules.class_droplist().size() == 28, "every race and every class is offered")
	var knight: Dictionary = HeroRules.definitions()
	var cases: Array = fixtures.cases
	check(cases.size() == 448, "448 creation cases")
	for c in cases:
		var race := int(c.race)
		var klass := int(c.class_id)
		var p = Profile.create("c-%d-%d" % [race, klass], "Hero %d %d" % [race, klass], race, klass)
		var d: Dictionary = p.data
		var label := "race %d class %d" % [race, klass]
		check(int(d.race_id) == race and int(d.class_id) == klass, label + ": race +0x30 / class +0x32")
		check(int(d.level) == int(c.level) and int(d.xp) == int(c.xp) and HeroRules.xp_threshold(int(d.level) + 1) == int(c.next_threshold), label + ": level 1, XP 0, next 10")
		check(d.original_type_id == String(c.art) and d.voice_id == String(c.voice) and int(d.portrait_id) == int(c.portrait), label + ": art +0x5c, voice +0x60, portrait +0x58")
		check(d.original_type_id == Rules.hero_type(race), label + ": the art is the race's hero unit (0x42a0d0's table)")
		check(ints(d.stats) == ints(c.stats), label + ": stats +0x64")
		var skills: Array = d.skills.map(func(s): return [int(s.id), int(s.unlock_level), int(s.rank)])
		var expected: Array = c.skills.map(func(s): return ints(s))
		check(skills == expected, label + ": skills +0xfc")
		check(ints(d.spell_hotkeys) == ints(c.hotkeys) and bool(c.items_empty) and d.equipment.all(func(s): return s.is_empty()), label + ": hotkeys -1, no items")
		check(p.validate() == "", label + ": validates (%s)" % p.validate())
	var k = Profile.create("knight", "Sir Knight")
	check(k.data.stats == knight.starting_stats.map(func(v): return int(v)) and int(k.data.portrait_id) == int(knight.portrait_id), "the default is milestone 6b's Knight Warrior")

func validation():
	var dwarf = Profile.create("dwarf", "Thane", 1, 0)
	dwarf.data.original_type_id = "AHHX"
	check(dwarf.validate() != "", "a Dwarf record with the Knight art is refused")
	dwarf = Profile.create("dwarf", "Thane", 1, 0)
	dwarf.data.original_type_id = "AAHX"
	check(dwarf.validate() == "", "a Dwarf may hold an art of its Customize list (0x6140f8: ADHX, AAHX)")
	dwarf.data.portrait_id = 0
	check(dwarf.validate() != "", "a Dwarf with a portrait outside its list (0x612178) is refused")
	dwarf = Profile.create("dwarf", "Thane", 1, 0)
	dwarf.data.skills[2].id = 67
	check(dwarf.validate() != "", "a Dwarf with the Knight Lord skill is refused (the creation list is the class restriction)")
	var empire = Profile.create("empire", "Imperator", 12, 0)
	check(empire.data.original_type_id == "APHX" and empire.data.voice_id == "AXH2" and int(empire.data.portrait_id) == 27 and empire.validate() == "", "Empire: APHX art, AXH2 voice, portrait 27")
	var swarm = Profile.create("swarm", "Queen", 14, 0)
	check(swarm.data.original_type_id == "ARHX" and swarm.data.voice_id == "AUHX", "The Swarm's hero speaks with the AUHX voices (0x54f1d0)")
	var old = Profile.create("old", "Sir Old")
	old.data.history.erase("games_by_race")
	old.data.history.erase("wins_by_race")
	check(old.validate() == "", "a profile saved before milestone 11b still loads")
	var bad = Profile.create("bad", "Sir Bad")
	bad.data.history.games_by_race = [1, 2]
	check(bad.validate() != "", "per-race counters need 16 entries")
	bad = Profile.create("bad", "Sir Bad", 0, 0)
	bad.data.race_id = 16
	check(bad.validate() != "", "race 16 is refused")

# -------------------------------------------------------------------------------------------- helpers
func advance(scene, seconds: float):
	for i in roundi(seconds * 20.0):
		if scene.skirmish != null and scene.skirmish.over: return
		scene.simulation_step(0.05)

func win(scene) -> bool:
	for unit in scene.units:
		if unit.owner_id == 1 and scene.combat.alive(scene.combat.fighters.get(unit.unit_id)):
			scene.combat.apply_damage("unit", unit.unit_id, 99999, -1)
	# The Swarm's towers count for its side (Building.cfg side flag, 0x52a3e0): raze them too.
	for b in scene.production.buildings.values():
		if int(b.owner) == 1 and int(b.hit_points) > 0: scene.combat.apply_damage("building", b.entity_id, 99999, -1)
	var waited := 0.0
	while not scene.skirmish.over and waited < 90.0:
		scene.simulation_step(0.25)
		waited += 0.25
	return scene.skirmish.over and bool(scene.skirmish.outcome.get("won", false))

func setup_for(hero_id: String, race: int) -> Dictionary:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	if race >= 0: Setup.set_race(setup, 0, race)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = hero_id
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)          # Passive opponent
	return setup

# -------------------------------------------------------------------------------------------- 3. a Dwarf hero end to end
func dwarf_match(scene, store):
	var created = Profile.create("test-dwarf-hero", "Thane Ironfist", 1, 0)
	created.data.backpack[0] = {"item": 3, "source": "test"}       # Giant's Helm: combat +12 when worn
	check(store.save_profile(created), "Dwarf hero saved")
	var saved = store.load_profile("test-dwarf-hero")
	check(saved != null and int(saved.data.race_id) == 1 and saved.data.original_type_id == "ADHX", "Dwarf hero reloaded as a Dwarf")
	var setup := setup_for("test-dwarf-hero", -1)               # the map's race for slot 0: Dwarf (0x4e7760)
	check(int(setup.players[0].race) == Rules.DWARF, "Desert Sands' west side plays the Dwarves by default")
	check(scene.start_skirmish(setup, "test-dwarf-hero", store, "hero-races-1"), "the Dwarf hero's match starts")
	var hero = scene.units[scene.hero_unit_id]
	check(hero.type_id == "ADHX" and scene.hero_match.profile.data.original_type_id == "ADHX", "the hero spawns as the Dwarven hero ADHX")
	check(scene.production.race_of(0) == Rules.DWARF, "the player plays the Dwarves")
	var f = scene.combat.fighters[scene.hero_unit_id]
	var unit_stats: Dictionary = Effects.hero_unit(scene.hero_match.record())
	check(int(f.max_hp) == int(unit_stats.max_hp) and int(f.max_hp) == 240 + 9 * 3 + 30, "Dwarf Warrior hit points: class 240 + 3 x Strength 9 + Constitution 3 x 10 (0x54fd50)")
	check(int(f.stats.combat) == int(unit_stats.combat) and int(f.stats.combat) == 4 + 9 + 9, "combat: derived 4 + Strength 9, Ferocity 3 x 3")
	check(int(f.stats.flags) == Effects.HERO_RACE_FLAGS[1], "the Dwarven hero's race flags")
	var block: Dictionary = scene.hero_match.block(int(f.hp))
	block.race = 1
	check(int(scene.production.hero_commands[0]) == Effects.command_value(block) / 2 and Effects.command_value(block) == 5 / 2 + 2, "command: Charisma 5 / 2 + Dwarf Lord (0x44) rank 1 x2 through the player's race (0x5269a0)")
	var before := int(scene.combat.combat_block(f).combat)
	check(scene.hero_item_move(7, -2) and int(scene.hero_match.profile.data.equipment[0].get("item", 0)) == 3, "the helm goes to the head slot (0x55ec20)")
	check(int(scene.combat.combat_block(scene.combat.fighters[scene.hero_unit_id]).combat) == before + 12, "Giant's Helm adds 12 combat to the Dwarven hero (0x51bd10)")
	check(scene.production.construction_menu(0).has("BKD0"), "the Dwarven hero builds the Dwarven row")
	var started = store.load_profile("test-dwarf-hero")
	check(int(started.data.history.battles_fought) == 1 and int(started.data.history.games_by_race[1]) == 1, "the start counts the battle and a Dwarf game (0x4e2790)")
	advance(scene, 5.0)
	check(win(scene), "victory")
	check(scene.accept_results(), "results accepted")
	var stored = store.load_profile("test-dwarf-hero")
	check(stored != null and stored.validate() == "", "the written hero validates")
	check(int(stored.data.race_id) == 1 and int(stored.data.class_id) == 0 and stored.data.original_type_id == "ADHX", "still a Dwarf Warrior")
	check(int(stored.data.history.battles_won) == 1 and int(stored.data.history.wins_by_race[1]) == 1 and int(stored.data.history.wins_by_race[0]) == 0, "the win counts for the Dwarves (0x4549a7)")
	check(int(stored.data.xp) > 0 and "hero-races-1" in stored.data.applied_results, "XP written once")
	check(int(stored.data.equipment[0].get("item", 0)) == 3, "the equipped helm is written with the result")

# -------------------------------------------------------------------------------------------- 2. the slot-race rule
func slot_race_rule(scene, store):
	# The local row's race list (0x4eb4d0 case 0x7b -> 0x4eb030) sets the slot to Knight; the hero stays a Dwarf.
	var setup := setup_for("test-dwarf-hero", Setup.KNIGHT)
	var resolved := Setup.resolve(setup)
	check(int(resolved.slots[0].race) == Rules.KNIGHT, "0x4de740: the player table takes the setup race, not the hero's")
	check(scene.start_skirmish(setup, "test-dwarf-hero", store, "hero-races-2"), "a Dwarf hero leading Knights")
	var hero = scene.units[scene.hero_unit_id]
	check(hero.type_id == "ADHX", "the hero is still the Dwarven hero unit (record +0x5c, 0x43b550)")
	check(scene.production.race_of(0) == Rules.KNIGHT and scene.production.construction_menu(0).has("BKK0") and not scene.production.construction_menu(0).has("BKD0"), "the player builds the Knights' row")
	var f = scene.combat.fighters[scene.hero_unit_id]
	var block: Dictionary = scene.hero_match.block(int(f.hp))
	block.race = Rules.KNIGHT
	check(int(scene.production.hero_commands[0]) == Effects.command_value(block) / 2 and Effects.command_value(block) == 5 / 2, "the lord skill follows the slot race: Knight Lord (0x43) is not a Dwarf skill, so only Charisma counts")
	var started = store.load_profile("test-dwarf-hero")
	check(int(started.data.history.games_by_race[0]) == 1 and int(started.data.history.games_by_race[1]) == 1, "the game counts for the Knights (+0x9a + 0x708f96 * 2)")
	# Random (0x10) takes the slot's 0x60f0f0 entry (static 0..5 until the setup's Okay rolls them): slot 0 -> Knights,
	# independent of the hero.
	var random_setup := setup_for("test-dwarf-hero", Setup.RANDOM_RACE)
	check(int(Setup.resolve(random_setup).slots[0].race) == Setup.KNIGHT, "Random resolves without looking at the hero")
	scene.end_skirmish()
	# A computer slot's hero follows its slot race (0x42a0d0 on 0x708f96): Dwarf on Desert Sands' west, Swarm on the east.
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var spectate := Setup.defaults(map)
	Setup.set_kind(spectate, 0, Setup.COMPUTER, 0)
	Setup.set_kind(spectate, 1, Setup.COMPUTER, 0)
	check(scene.start_skirmish(spectate, "", null, "hero-races-3"), "computer-only match")
	var types := {}
	for owner in scene.match_heroes:
		var bound = scene.match_heroes[owner]
		types[owner] = [bound.entity.original_type_id, String(bound.profile.data.voice_id), int(bound.profile.data.portrait_id)]
	check(types.get(0, []) == ["ADHX", "ADHX", 1] and types.get(1, []) == ["ARHX", "AUHX", 14], "computer heroes: their slot race's art, voice and portrait (%s)" % [types])
