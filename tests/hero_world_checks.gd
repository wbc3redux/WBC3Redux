extends SceneTree
## Milestone 11-hero world checks in the real scene (main.tscn) on a copied profile (never user://heroes):
## a hero with combat skills deals the ported (emulated) damage, equipped items change the hero's numbers, the computer
## player's hero is a 0x42a0d0 record, quest items and a dying hero's backpack lie on the ground as treasure, and the
## items and allocated points survive the result writeback.

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Effects = preload("res://simulation/hero_effects.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const CombatRng = preload("res://simulation/combat_rng.gd")
const ComputerHero = preload("res://simulation/computer_hero.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Hero world check failed: ", label)

func _initialize():
	var directory := "user://hero-world-checks"
	var store = Store.new(directory)
	var hero = Profile.create("world-knight", "Sir World")
	hero.data.skills[0].rank = 5            # Weaponmaster 5: crit bonus 10
	hero.data.skills[1].rank = 4            # Ferocity 4: +12 combat
	hero.data.skills[4].rank = 2            # Constitution 2: +20 hit points
	hero.data.equipment[2] = {"item": 4, "source": "test"}   # Dagger of Piercing: +10 damage, piercing
	hero.data.backpack[0] = {"item": 3, "source": "test"}    # Giant's Helm: combat +12 when worn
	hero.data.backpack[1] = {"item": 2, "source": "test"}    # Boots of Speed: speed +2 when worn
	check(store.save_profile(hero), "copied test profile saved")
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)   # milestone 11a: the map's races are the default; these checks are Knights
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "world-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	check(scene.start_skirmish(setup, "world-knight", store, "world-match-1"), "match starts")
	var f = scene.combat.fighters[scene.hero_unit_id]
	# ---- 0x54fd50: skills and the record in the hero unit (Emulated formulas, HeroEffects.hero_unit)
	check(int(f.max_hp) == 240 + 21 + 20, "Constitution 2 adds 20 hit points (261 + 20)")
	check(int(f.stats.combat) == 4 + 7 + 12, "Ferocity 4 adds 12 combat (derived 0 = 11)")
	check(int(f.stats.speed) == 10 and scene.units[scene.hero_unit_id].base_speed == 10, "the hero walks at its derived speed 10 (not ARM 6)")
	var block: Dictionary = scene.combat.combat_block(f)
	check(int(block.dmg) == 27 + 10 and int(block.dtype) == 0, "the weapon's piercing power: damage 37, type 0 (0x526310)")
	check(int(block.crit_bonus) == 10, "Weaponmaster 5: crit bonus 10 (0x556ea0 x2)")
	# ---- the swing in the world equals the ported 0x42ace0 on the same generator state
	var victim = scene.add_unit("AHKX", scene.navigator.free_cell_near(scene.units[scene.hero_unit_id].cell + Vector2i(1, 0)), 1)
	var vf = scene.combat.fighters[victim.unit_id]
	check(int(vf.stats.flags) & 1 == 1, "a Swordsman carries the human STATUS bit (+0x1c0 = 0x585970(AHKX))")
	var started := {"done": false}
	scene.combat.swing_started.connect(func(id, info): if id == scene.hero_unit_id and not started.done:
		started["done"] = true
		started["info"] = info
		started["attacker"] = scene.combat.combat_block(scene.combat.fighters[id])
		started["target"] = scene.combat.combat_block(scene.combat.fighters[victim.unit_id]))
	var landed := {"done": false}
	scene.combat.damaged.connect(func(kind, id, amount, attacker): if id == victim.unit_id and not landed.done:
		landed["done"] = true
		landed["amount"] = amount)
	check(scene.combat.order_attack(scene.hero_unit_id, "unit", victim.unit_id), "attack order")
	var waited := 0.0
	while not landed.done and waited < 10.0:
		scene.simulation_step(1.0 / 60.0)
		waited += 1.0 / 60.0
	var replay = FixedRoll.new(int(started.info.result.roll) if started.done else 0)
	var expected: Dictionary = CombatRules.swing(started.get("attacker", {}), started.get("target", {}), replay, int(started.info.distance) if started.done else 0, scene.combat.game_mode) if started.done else {}
	check(started.done and landed.done and int(landed.amount) == int(expected.get("damage", -1)), "the first hit deals the ported 0x42ace0 damage with the hero terms (%s, got %s)" % [expected, landed])
	check(started.done and int(started.attacker.crit_bonus) == 10 and started.attacker.has("slayer_block"), "the world swing carried the hero terms")
	# Manslayer adds its term against the human Swordsman: same roll, +30 damage before the bands.
	var with_skill: Dictionary = scene.combat.combat_block(f)
	var own: Dictionary = with_skill.slayer_block.duplicate(true)
	own.skills.append([35, 0, 3])
	check(Effects.slayer_bonus(own, int(vf.stats.flags)) == 30 and Effects.slayer_bonus(own, 0x8000000) == 0, "Manslayer 3: +30 against human targets only")
	# ---- equipping items changes the numbers (0x55ec20 slot rule, 0x40c380 sums, 0x54fd50 refresh)
	check(not scene.hero_match.move_item(7, 2), "a helm does not fit the weapon slot (0x55ec20)")
	check(scene.hero_item_move(7, -2) and int(scene.hero_match.profile.data.equipment[0].item) == 3, "the helm goes to the head slot")
	f = scene.combat.fighters[scene.hero_unit_id]
	check(int(scene.combat.combat_block(f).combat) == int(f.stats.combat) + 12, "Giant's Helm adds 12 combat (0x51bd10 item term)")
	check(scene.hero_item_move(8, -2) and scene.units[scene.hero_unit_id].base_speed == 12, "Boots of Speed: speed 12 (0x51c460 item term)")
	check(scene.hero_item_move(6, -1) and scene.units[scene.hero_unit_id].base_speed == 10 and scene.hero_match.profile.data.equipment[6].is_empty(), "unequipped boots: speed 10 again")
	# ---- the computer's hero (0x42a0d0)
	var cpu = scene.match_heroes[1]
	check(cpu.computer and int(cpu.profile.data.level) >= 1 and int(cpu.profile.data.level) <= 5, "computer hero: level 3 +/- 2 against a level-1 human (best at least 3)")
	var cpu_fighter = scene.combat.fighters[cpu.entity.entity_id]
	check(int(cpu_fighter.max_hp) == int(Effects.hero_unit(cpu.record()).max_hp), "computer hero unit from its own class and stats (0x54fd50)")
	# ---- treasure: a dropped item lies on the ground; the hero takes it back
	check(scene.hero_item_drop(7), "drop the boots")
	var piles: Array = scene.treasures.reachable(scene.units[scene.hero_unit_id].cell)
	check(piles.size() == 1 and piles[0].items == [2], "the dropped boots lie under the hero (0x580d00)")
	check(scene.hero_item_take(int(piles[0].id), 0) and scene.treasures.piles.is_empty(), "taken back into the backpack")
	# ---- the inventory dialog (0x55e0e0 / 0x55ecc0, playtest 2026-11-11)
	var boots_slot := -1
	for i in range(7, 11):
		if int(scene.hero_match.profile.data.backpack[i - 7].get("item", 0)) == 2: boots_slot = i
	check(boots_slot >= 7 and scene.hero_item_drop(boots_slot), "drop the boots again")
	var pile_id: int = int(scene.treasures.reachable(scene.units[scene.hero_unit_id].cell)[0].id)
	scene.sync_treasure_sprites()
	check(scene.treasure_sprites.has(pile_id) and scene.treasure_sprites[pile_id].region_rect == Rect2(0, 240, 75, 60), "the pile shows IMAP's closed chest (0x4a7870: column 0, row 4)")
	check(scene.open_inventory(pile_id) and (scene.hud == null or scene.hud.dialog == "inventory") and int(scene.inventory_slot(11).get("item", 0)) == 2, "the dialog opens with the pile's boots in the ground row")
	check(scene.inventory_release(11) == "selected" and scene.inventory_release(0) == "", "a click selects the boots; the head slot refuses them (0x55ec20)")
	check(scene.inventory_release(11) == "selected" and scene.inventory_release(6) == "swapped" and int(scene.inventory_slot(6).get("item", 0)) == 2 and scene.inventory_slot(11).is_empty(), "boots from the ground to the feet slot")
	check(scene.units[scene.hero_unit_id].base_speed == 12, "the hero is rebuilt at once: speed 12")
	scene.inventory.tick = 100
	check(scene.inventory_release(6) == "selected" and scene.inventory_release(6) == "moved" and scene.inventory_slot(6).is_empty(), "a double click moves the boots to the first free slot that takes them")
	check(scene.units[scene.hero_unit_id].base_speed == 10, "unequipped: speed 10")
	var moved_to := -1
	for i in range(7, 11):
		if int(scene.inventory_slot(i).get("item", 0)) == 2: moved_to = i
	scene.inventory.tick = 100
	check(moved_to >= 7 and scene.inventory_release(moved_to) == "selected" and scene.inventory_release(13) == "swapped", "the boots go back to the ground row")
	scene.close_inventory()
	check(scene.inventory.is_empty() and scene.treasures.piles.has(pile_id) and scene.treasures.piles[pile_id].items == [2], "closing writes the ground row to the pile, compacted (0x560a00)")
	check(scene.hero_item_take(pile_id, 0) and scene.treasures.piles.is_empty(), "taken back again")
	scene.sync_treasure_sprites()
	check(scene.treasure_sprites.is_empty(), "an emptied pile's chest goes")
	# ---- the quest timer on the portrait (0x4d7710): seconds left, right to left from x + (3 n + 9) * 2
	var Hud = load("res://hud/game_hud.gd")
	check(Hud.quest_timer_digits(65999, 0) == [{"x": 30, "digit": 5}, {"x": 24, "digit": 6}], "quest timer 65 s: two digits")
	check(Hud.quest_timer_digits(0, 5000) == [{"x": 24, "digit": 0}] and Hud.quest_timer_digits(1234000, 0).size() == 3, "an overdue quest shows 0; thousands are not shown")
	# ---- victory writeback keeps the equipment and the backpack
	for unit in scene.units:
		if unit.owner_id == 1 and scene.combat.alive(scene.combat.fighters.get(unit.unit_id)):
			scene.combat.apply_damage("unit", unit.unit_id, 99999, -1)
	# Parity pass 3: the map towers are the computer Knights' own Knight Towers now (0x4a50f0), which keep its side alive.
	for b in scene.production.buildings.values().duplicate():
		if int(b.owner) == 1 and String(b.original_type_id).begins_with("BWT"): scene.combat.apply_damage("building", b.entity_id, int(b.hit_points) + 1, -1)
	waited = 0.0
	while not scene.skirmish.over and waited < 90.0:
		scene.simulation_step(0.25)
		waited += 0.25
	check(scene.skirmish.over and scene.skirmish.outcome.won, "victory")
	check(scene.accept_results(), "results accepted")
	var stored = store.load_profile("world-knight")
	check(int(stored.data.equipment[0].item) == 3 and int(stored.data.equipment[2].item) == 4 and stored.data.backpack.any(func(s): return int(s.get("item", 0)) == 2),
		"equipment and backpack written with the result")
	# ---- hero death: the backpack falls to the ground (0x4a87f0) and is lost for the profile
	check(scene.start_skirmish(setup, "world-knight", store, "world-match-2"), "second match")
	var cell: Vector2i = scene.units[scene.hero_unit_id].cell
	scene.combat.apply_damage("unit", scene.hero_unit_id, 99999, -1)
	var ground: Array = []
	for pile in scene.treasures.piles.values(): ground.append_array(pile.items)
	check(ground == [2], "the dead hero's backpack item lies on the ground (0x4a87f0)")
	check(store.load_profile("world-knight").data.backpack == [{}, {}, {}, {}], "and the saved hero lost it (0x4a8f50)")
	# ---- a unit with status 0x1a (the lair boss) drops one random treasure item (0x528300 -> 0x4a87f0)
	var boss = scene.add_unit("AMJX", scene.navigator.free_cell_near(Vector2i(60, 60)), 6)
	scene.treasure_units[boss.unit_id] = true
	var before: int = scene.treasures.piles.size()
	scene.combat.apply_damage("unit", boss.unit_id, 99999, -1)
	check(scene.treasures.piles.size() == before + 1 and scene.treasures.by_cell.has(boss.cell), "the boss's treasure lies at its death cell")
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures == 0: print("Hero world checks passed: ", checks)
	quit(0 if failures == 0 else 1)

class FixedRoll:
	var value := 0
	func _init(v: int): value = v
	func roll(count: int, sides: int, bonus: int = 0) -> int: return value
