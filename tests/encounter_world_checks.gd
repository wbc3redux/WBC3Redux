extends "res://tests/combat_world_checks.gd"
## World-level encounter checks (milestone 9): attitude scripts driving Combat, flight, animals, towers, the Gnoll Lair,
## Mausoleum quests and rewards on the Desert Sands grid. Emulated parity is in test_unit_ai.gd; the rules exercised
## here are labelled in ENCOUNTERS_RESEARCH.md.
const Encounters = preload("res://simulation/encounters.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")

var catalogue: Dictionary
var enc_data: Dictionary
var ai_data: Dictionary
var enc

func run(tree: SceneTree):
	t = tree
	open_cell = open_ground()
	catalogue = Encounters.load_json("res://assets/catalogue.json")
	enc_data = Encounters.load_json("res://assets/encounters.json")
	ai_data = UnitAI.load_data()
	_test_defensive()
	_test_stand_ground()
	_test_player_order_blocks()
	_test_cowardly()
	_test_animals()
	_test_ani_timing()
	_test_victim_xp()
	_test_tower()
	_test_quests()
	_test_lair()      # last: destroying the lair edits the shared collision data

func encounter_world(seed_a: int = 0x6a09e667, seed_b: int = 0xbb67ae85):
	new_world(seed_a, seed_b)
	world.visibility.fog = false
	world.visibility.shroud = false
	world.production.economy.add_player(6, [0, 0, 0, 0])
	if enc != null: enc.dispose()
	var me: WeakRef = weakref(self)   # a strong capture of this RefCounted world would be a cycle (enc -> lambda -> self -> enc)
	enc = Encounters.new(world.combat, world.production, world.production.economy, collision, catalogue, enc_data, ai_data)
	enc.spawn_unit = func(type_id, cell, owner, xp): return me.get_ref().add_any(type_id, cell, owner)

## Any unit type from the catalogue (the ARM record gives speed and the combat block).
func add_any(type_id: String, cell: Vector2i, owner: int, script: int = -1) -> int:
	var definition: Dictionary = enc.unit_definition(type_id) if enc != null else {}
	if definition.is_empty(): definition = world.production.rules.definition(type_id)
	var unit = UnitAgent.new()
	unit.unit_id = world.units.size()
	unit.type_id = type_id
	unit.owner_id = owner
	unit.base_speed = int(definition.base_speed)
	unit.navigator = world.nav
	unit.position = world.nav.center(cell)
	t.root.add_child(unit)
	world.units.append(unit)
	unit.sync_cell()
	var fighter = world.combat.register(unit.unit_id, owner, type_id, Rules.unit_stats(definition.raw_hex), false)
	unit.order_step = func(id, to_cell): world.combat.ai.on_step(id, to_cell)
	if script >= 0: fighter.script = script
	return unit.unit_id

func _test_defensive():
	encounter_world()
	var a := add_any("AHKX", open_cell, 0)
	var e := add_any("AHKX", open_cell + Vector2i(10, 0), 1, 1)
	check(f(a).script == 2 and f(a).guard == open_cell, "default attitude Defensive (ARM +0xf6 = 2), guard point at the unit's cell")
	run_ms(475)
	check(f(a).order == null, "no script pass before the 10th UI timer tick")
	run_ms(25)
	check(f(a).order != null and f(a).order.target_id == e and bool(f(a).order.ai), "Defensive attacks an enemy 10 cells away on the 10th 50 ms UI tick (500 ms), interruptible")
	encounter_world()
	var b := add_any("AHKX", open_cell, 0)
	add_any("AHKX", open_cell + Vector2i(13, 0), 1, 1)
	run_ms(1000)
	check(f(b).order == null, "an enemy 13 cells away is outside max(12, range)")
	# 0x5334f0 (9-fix): animals and buildings of the neutral player are never search candidates.
	encounter_world()
	var d := add_any("AHKX", open_cell, 0)
	add_any("ACCA", open_cell + Vector2i(3, 0), 6)
	run_ms(1000)
	check(f(d).order == null and world.combat.acquire(f(d)) == null, "a Defensive unit does not acquire a Camel 3 cells away")

func _test_stand_ground():
	encounter_world()
	var a := add_any("AHKX", open_cell, 0, 1)
	var far := add_any("AHKX", open_cell + Vector2i(4, 0), 1, 1)
	run_ms(1000)
	check(f(a).order == null and f(far).order == null, "Stand Ground ignores enemies that are not adjacent")
	var near := add_any("AHKX", open_cell + Vector2i(-1, 1), 1, 1)
	run_ms(500)
	check(f(a).order != null and f(a).order.target_id == near, "Stand Ground attacks an adjacent enemy (0x508300)")
	# 9-fix (review D5): unarmed neutrals do not count, armed ones do; choice = remembered attacker, else the scan's last.
	encounter_world()
	var g := add_any("AHKX", open_cell, 0, 1)
	var camel := add_any("ACCA", open_cell + Vector2i(1, 0), 6, 1)
	run_ms(1000)
	check(f(g).order == null and world.combat.ai.adjacent_enemy(f(g)) == null, "Stand Ground does not react to an adjacent Camel (0x507e40: neutral without damage)")
	var gnoll := add_any("AMJX", open_cell + Vector2i(0, 1), 6, 1)
	run_ms(500)
	check(f(g).order != null and f(g).order.target_id == gnoll, "an adjacent armed neutral (Gnoll) is attacked at once")
	encounter_world()
	var s := add_any("AHKX", open_cell, 0, 1)
	var first := add_any("AHKX", open_cell + Vector2i(-1, -1), 1, 1)   # scanned first (x outer, y inner)
	var last := add_any("AHKX", open_cell + Vector2i(1, 1), 1, 1)      # scanned last
	check(world.combat.ai.adjacent_target(f(s)).id == last, "without a remembered attacker the last hostile of the scan is taken")
	f(s).remembered = first
	check(world.combat.ai.adjacent_target(f(s)).id == first, "the remembered attacker (+0x140) is taken at once")

func _test_player_order_blocks():
	encounter_world()
	var a := add_any("AHKX", open_cell, 0)
	add_any("AHKX", open_cell + Vector2i(6, 3), 1, 1)
	var unit = world.units[a]
	var goal := open_cell + Vector2i(-6, 0)
	unit.give_order({"kind": "move", "target": world.nav.center(goal), "requested": world.nav.center(goal), "group": 0, "speed": unit.base_speed, "individual": true}, "replace")
	world.combat.note_move(a, goal)
	run_ms(600)
	check(f(a).order == null and f(a).cur.kind == "move" and not f(a).cur.finished, "a player move blocks rules without +0x75 (0x507560)")
	check(f(a).guard != open_cell, "the guard point follows the walking unit (0x5377a0)")
	run_ms(6000, func(): return f(a).order != null)
	check(f(a).order != null, "after arriving the Defensive unit acquires again")

func _test_cowardly():
	encounter_world()
	var a := add_any("AHBX", open_cell, 0, 0)
	add_any("AHKX", open_cell + Vector2i(3, 0), 1, 1)
	run_ms(500)
	check(f(a).cur != null and f(a).cur.kind == "move" and f(a).cur.goal.x <= open_cell.x - 4, "Cowardly flees from an enemy within 5 (flee_near, 0x522f40): goal %s" % [f(a).cur.goal if f(a).cur != null else null])
	check(f(a).cur != null and not bool(f(a).cur.ai), "two flight hops make a non-interruptible order")
	encounter_world()
	var c := add_any("AHBX", open_cell, 0, 0)
	var e := add_any("AHKX", open_cell + Vector2i(8, 0), 1, 1)
	world.combat.apply_damage("unit", c, 1, e)
	check(world.combat.ai.was_hit(c), "a surviving victim enters the hit list (0x505b90)")
	run_ms(500)
	check(f(c).cur != null and f(c).cur.kind == "move" and f(c).cur.goal.x < open_cell.x, "Cowardly flees from its attacker when hit (rule 2, priority 100)")

func _test_animals():
	encounter_world(0x3c6ef372, 0xa54ff53a)
	var killer := add_any("AHKX", open_cell, 0, 1)
	var camel := add_any("ACCA", open_cell + Vector2i(1, 0), 6)
	var turtle := add_any("ACTU", open_cell + Vector2i(-1, 0), 6)
	var gnoll := add_any("AMJX", open_cell + Vector2i(0, 4), 6, 1)
	check(f(camel).stats.dmg == 0 and f(camel).stats.max_hp == 25 and f(turtle).stats.max_hp == 15 and f(gnoll).stats.max_hp == 65 and f(gnoll).stats.dmg == 14,
		"ARM blocks: Camel 25 hp no damage, Turtle 15 hp, Gnoll 65 hp damage 14")
	check(not world.combat.order_attack(camel, "unit", killer), "an animal cannot be ordered to attack (damage 0)")
	run_ms(500)
	check(f(camel).order == null and f(turtle).order == null, "animals never search (0x51a470 starts with 0x528280)")
	var xp_before: int = f(killer).xp
	world.combat.apply_damage("unit", turtle, 9999, killer)
	check(f(killer).xp == xp_before, "killing an animal gives no XP (0x5210b0)")
	world.combat.apply_damage("unit", gnoll, 9999, killer)
	check(f(killer).xp == xp_before + 1, "killing a Gnoll gives 1 XP")
	var moved := false
	for i in 120:
		run_ms(250)
		if f(camel).cur != null and f(camel).cur.kind == "move" and Navigation.chebyshev(f(camel).cur.goal, world.units[camel].cell) > 1:
			moved = true
			check(not bool(f(camel).cur.ai), "the idle animal's walk is not interruptible (0x51a230)")
			break
	check(moved, "an idle Camel walks off to a random cell (0x51a230)")

## 0x526fe0 / 0x526db0 (9-fix): an AUKX/AUXX killer takes the victim's own XP, then the ordinary award.
func _test_victim_xp():
	encounter_world()
	var drainer := add_any("AUKX", open_cell, 1, 1)
	var victim := add_any("AHKX", open_cell + Vector2i(1, 0), 0, 1)
	f(victim).xp = 7
	world.combat.apply_damage("unit", victim, 9999, drainer)
	check(f(drainer).xp == 7 + 1, "AUKX killer: victim XP 7 + 1 for the kill (%d)" % f(drainer).xp)
	var plain := add_any("AHKX", open_cell + Vector2i(0, 2), 1, 1)
	var other := add_any("AHKX", open_cell + Vector2i(1, 2), 0, 1)
	f(other).xp = 7
	world.combat.apply_damage("unit", other, 9999, plain)
	check(f(plain).xp == 1, "an ordinary killer gets only the kill")

func _test_ani_timing():
	encounter_world()
	check(int(world.combat.ani.AHHX.attack_frames) == 23 and int(world.combat.ani.AHHX.hit_frame) == 8 and int(world.combat.ani.AMJX.attack_frames) == 18
		and int(world.combat.ani.AMJX.hit_frame) == 10 and int(world.combat.ani.AMJX.death_frames) == 12, "hero and Gnoll attack/death frames from their ANI records")
	var g := add_any("AMJX", open_cell, 6, 1)
	var target := add_any("AHKX", open_cell + Vector2i(1, 0), 0, 1)
	world.combat.order_attack(g, "unit", target)
	run_ms(25)
	var swing = f(g).swing
	var entry := Rules.attack_entry_ms(false, 0, 0, Rules.BASE_ATTACK_RATE, 18)
	check(swing != null and swing.hit_ms - swing.start_ms == entry * 10 and swing.end_ms - swing.start_ms == entry * 18, "Gnoll swing: hit at entry 10 of 18 (%d ms per entry)" % entry)

func _tower_id(code: String) -> int:
	for id in world.combat.towers:
		if world.production.building(id).original_type_id == code: return id
	return -1

func _test_tower():
	encounter_world(0x510e527f, 0x9b05688c)
	check(enc.adopt_map_buildings(0, [0]).filter(func(e): return e.code == "BWTE").is_empty(), "no tower for an inactive player slot (0x708f94 test)")
	encounter_world(0x510e527f, 0x9b05688c)
	var adopted: Array = enc.adopt_map_buildings(0)
	var codes: Array = adopted.map(func(e): return e.code)
	codes.sort()
	check(codes == ["BLGL", "BWTD", "BWTD", "BWTE", "BWTE", "BZMA"], "six map buildings adopted: %s" % [codes])
	check(world.combat.towers.size() == 4, "the four towers have an attack (BUI +0x38 > 0); lair and Mausoleum do not")
	var id := _tower_id("BWTD")
	var tower: Dictionary = world.combat.towers[id]
	check(int(tower.damage) == 30 and int(tower.dtype) == 0 and int(tower.range) == 12 and int(tower.period) == 3000, "Dwarven Tower: 30 damage type 0, range 12, every 3000 ms (0x6114bc[1])")
	var swarm_id := _tower_id("BWTE")
	var swarm: Dictionary = world.combat.towers[swarm_id]
	check(int(swarm.damage) == 20 and int(swarm.dtype) == 4, "Swarm Tower: 20 damage type 4")
	check(world.production.building(id).owner == 0 and world.production.building(swarm_id).owner == 1 and world.production.building(id).hit_points == 350,
		"BLDH +0x64: Dwarven Towers belong to player 0, Swarm Towers to player 1")
	check(world.production.building(_id_of("BLGL")).owner == 6 and world.production.building(_id_of("BZMA")).owner == 6, "lair and Mausoleum stay neutral")
	# North of the first Dwarven Tower, out of the second one's reach (its centre is 9 rows further south).
	var spot: Vector2i = world.nav.free_cell_near(tower.center + Vector2i(0, -6))
	var own := add_any("AHKX", spot, 0, 1)
	run_ms(1000)
	check(tower.target_kind == "" and int(tower.shots) == 0 and f(own).hp == f(own).max_hp, "a unit of the tower's owner is not attacked")
	var victim := add_any("AHKX", world.nav.free_cell_near(spot + Vector2i(2, 0)), 1, 1)
	var landed: Array = []
	world.combat.missile_landed.connect(func(info): landed.append(info))
	run_ms(500)
	check(tower.target_id == victim and int(tower.shots) == 1, "an enemy unit is acquired on the script pass and shot at once")
	var tower_score: int = world.combat._score(1, spot, {"kind": "building", "id": id, "owner": 0, "cell": tower.center})
	check(tower_score == 0x32 + maxi(0, 11 - Navigation.chebyshev(spot, tower.center)) + 0x1e, "a tower shooting the searcher's unit gains 0x1e (0x52a410 term)")
	var lair_score: int = world.combat._score(0, spot, {"kind": "building", "id": _id_of("BLGL"), "owner": 6, "cell": spot})
	check(lair_score == 0, "a lair is never an acquisition target (0x533c40: B+L)")
	run_ms(1000)
	# Milestone 11 (EFFECTS_RESEARCH.md): the arrow is a real missile (accuracy 0x52d9b0, displaced aim on a miss, 2 x 2
	# probe) and the impact multiplies the armoured damage by 0x611e60[7 + 1] = 120 % (towers add 1 to their elevation).
	run_ms(15000, func(): return not world.combat.alive(f(victim)))
	var hits: Array = landed.filter(func(i): return bool(i.hit) and String(i.struck_kind) == "unit" and int(i.struck_id) == victim)
	check(not hits.is_empty() and hits.all(func(i): return int(i.damage) == 30), "Dwarven arrow: 30 -> armour 25 -> x 1.2 = 30 (%s)" % [hits.map(func(i): return i.damage)])
	check(not world.combat.alive(f(victim)) and int(tower.shots) >= 2 and landed.all(func(i): return String(i.id) == "EMA0"), "arrows (EMA0) every 3000 ms kill the Swordsman (%d shots)" % int(tower.shots))
	check(world.combat.xp_log.is_empty(), "a tower kill gives nobody XP")
	# Destroying an enemy tower: a building with an attack (+0x7c > 0) is worth 4 to the killer and the owner's hero.
	var raider := add_any("AHKX", world.nav.free_cell_near(swarm.center + Vector2i(0, 8)), 0, 1)
	world.combat.apply_damage("building", swarm_id, 99999, raider)
	check(f(raider).xp == 4 and not world.combat.towers.has(swarm_id), "destroying the enemy's Swarm Tower gives 4 XP")

func _id_of(code: String) -> int:
	for b in world.production.buildings.values():
		if b.original_type_id == code: return b.entity_id
	return -1

func _test_quests():
	encounter_world(0x1f83d9ab, 0x5be0cd19)
	enc.adopt_map_buildings(0)
	var hero := add_unit("AHHX", open_cell, 0, HeroProfile.create("quest-check", "Sir Quest"))
	var hero_match = world["hero_match_0"]
	var mausoleum := _id_of("BZMA")
	var records: Array = enc.quest_records()
	check(records.size() == 45 and int(records[7].type) == 0 and records[7].target == "C" and int(records[7].count) == 300 and int(records[7].resources[0]) == 600,
		"Bzma.dat: 45 records, quest 7 trades 300 crystal for 600 gold")
	var draws_before: int = world.combat.rng.calls
	var picked = enc.pick_quest(0)
	check(picked != null and enc.eligible(0, picked) and world.combat.rng.calls == draws_before + 1, "the offer is 1d(eligible) - 1 over the eligible records (0x52edb0)")
	var giver: Dictionary = enc.givers[mausoleum]
	# 0x43d180 re-rolls the offer (0x52edb0) at every visit until a quest is accepted: one draw per visit.
	var offered := {}
	var draws_ok := true
	for i in 10:
		var before: int = world.combat.rng.calls
		var v: Dictionary = enc.visit(0, mausoleum)
		if world.combat.rng.calls != before + 1: draws_ok = false
		offered[int(v.record.index)] = true
	check(draws_ok and offered.size() >= 2 and not giver.picked, "ten visits without accepting: one draw each, %d different offers" % offered.size())
	var shown: Dictionary = enc.visit(0, mausoleum).record
	if enc.supported(shown):
		enc.accept(0, mausoleum)
		var before_accepted: int = world.combat.rng.calls
		check(giver.picked and enc.visit(0, mausoleum).record == shown and world.combat.rng.calls == before_accepted, "after acceptance the offer is fixed (+0x125) and no draw is made")
		enc.quests.erase(0)
	giver.picked = false
	giver.picked = true
	giver.record = records[7]
	var visit: Dictionary = enc.visit(0, mausoleum)
	check(visit.mode == "instant", "a resource quest the player can pay at once is offered as INST")
	check(enc.accept(0, mausoleum), "quest accepted")
	var gold_before: int = int(world.production.economy.resources(0)[0])
	var crystal_before: int = int(world.production.economy.resources(0)[2])
	var xp_before: int = int(hero_match.profile.data.xp)
	var reward: Dictionary = enc.complete(0, mausoleum, hero_match, open_cell)
	check(not reward.is_empty() and int(world.production.economy.resources(0)[0]) == mini(gold_before + 600, 1000) and int(world.production.economy.resources(0)[2]) == crystal_before - 300,
		"completion pays 300 crystal and gives 600 gold (capped at the 1000 stockpile)")
	check(int(hero_match.profile.data.xp) == xp_before + 20, "the hero gains 20 XP for a quest (0x43d560)")
	check(enc.visit(0, mausoleum).mode == "none", "the Mausoleum rests after a completed quest (300 s)")
	# Kill quest (record 5: six enemies -> 600 gold).
	giver.resting = false
	giver.picked = true
	giver.record = records[5]
	check(enc.visit(0, mausoleum).mode == "offer" and enc.accept(0, mausoleum), "kill quest offered and accepted")
	var enemies: Array = []
	for i in 6: enemies.append(add_any("AHKX", open_cell + Vector2i(3, i * 2 - 5), 1, 1))
	var camel := add_any("ACCA", open_cell + Vector2i(-3, 0), 6)
	world.combat.apply_damage("unit", camel, 9999, hero)
	check(int(enc.quests[0].progress) == 0, "animals do not count (0x43db30 is called for non-animals only)")
	for e in enemies:
		check(enc.visit(0, mausoleum).mode == "continue", "not complete yet")
		world.combat.apply_damage("unit", e, 9999, hero)
	check(int(enc.quests[0].progress) == 6 and enc.visit(0, mausoleum).mode == "complete", "six kills complete it")
	gold_before = int(world.production.economy.resources(0)[0])
	enc.complete(0, mausoleum, hero_match, open_cell)
	check(int(world.production.economy.resources(0)[0]) == mini(gold_before + 600, 1000), "600 gold (capped)")
	# Item reward (record 43: 500 gold -> item 175).
	giver.resting = false
	giver.picked = true
	giver.record = records[43]
	world.production.economy.credit(0, [500, 0, 0, 0])
	enc.visit(0, mausoleum)
	enc.accept(0, mausoleum)
	var Treasures = load("res://simulation/treasures.gd")
	enc.treasures = Treasures.new()
	enc.complete(0, mausoleum, hero_match, open_cell)
	var piles: Array = enc.treasures.reachable(open_cell)
	check(piles.size() == 1 and piles[0].cell == open_cell and piles[0].items == [175], "the item lies on the ground at the hero's cell (0x580d00)")
	check(hero_match.take_item(enc.treasures.take(int(piles[0].id), 0), "quest") == 7 and int(hero_match.profile.data.backpack[0].item) == 175
		and hero_match.inventory_changes().backpack[0].item == 175, "picked up into the backpack, ready for the writeback")
	enc.treasures = null

func _test_lair():
	encounter_world(0x9b05688c, 0x1f83d9ab)
	enc.adopt_map_buildings(0)
	var entry: Dictionary = enc.lairs[0]
	check(enc.lairs.size() == 1 and int(entry.lair) == 2, "one lair: the Gnoll Lair")
	check(int(entry.next_ms) >= 120000 and int(entry.next_ms) < 240000, "first wave at max + 0..119 s (0x404b70): %d" % int(entry.next_ms))
	var before: int = world.units.size()
	enc.update(int(entry.next_ms) - 1)
	check(world.units.size() == before, "nothing before the due time")
	enc.next_lair_check = -1
	enc.update(int(entry.next_ms))
	var gnolls: int = world.units.size() - before
	check(gnolls >= 1 and world.combat.fighters[before].type_id == "AMJX" and world.combat.fighters[before].owner == 6, "a timed wave spawns Gnolls of the neutral player (%d)" % gnolls)
	check(int(entry.next_ms) - int(entry.last_ms) >= 80000 and int(entry.next_ms) - int(entry.last_ms) <= 119000, "next wave 80..119 s later")
	var lair_id: int = int(entry.building)
	world.combat.now_ms = int(entry.response_ms)
	before = world.units.size()
	var attacker := add_any("AHKX", world.nav.free_cell_near(entry.cell + Vector2i(0, 6)), 0, 1)
	before = world.units.size()
	world.combat.apply_damage("building", lair_id, 10, attacker)
	check(world.units.size() > before, "hitting the lair after the response time calls a full wave (0x404b10)")
	before = world.units.size()
	world.combat.apply_damage("building", lair_id, 10, attacker)
	check(world.units.size() == before, "no second response within 30 s")
	before = world.units.size()
	world.combat.apply_damage("building", lair_id, 99999, attacker)
	check(world.units.size() == before + 1 and world.combat.fighters[before].type_id == "AMJX" and not entry.active, "destroying the lair releases the boss and stops the spawner")
	check(world.combat.fighters[attacker].xp == 3, "a building kill is worth 3 XP")
	var held := 0
	for cell in world.nav.building_cells:
		if world.nav.building_cells[cell] == lair_id: held += 1
	check(held == 0 and not enc.static_cells.has(lair_id), "the lair's placement cells are released")
