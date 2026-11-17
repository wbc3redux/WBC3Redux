extends SceneTree
## G-2: small rule gaps for every race (COMBAT_RESEARCH.md "G-2").
## 1. Attack queue modes (0x41f0b0 commands 0x16 append / 0x17 insert -> 0x531480 -> 0x51da60) and Shift+Esc (0x4296c0) in a
##    small combat world (Read: control flow).

const ProductionRules = preload("res://simulation/production_rules.gd")
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const Economy = preload("res://simulation/economy.gd")
const Production = preload("res://simulation/production.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Combat = preload("res://simulation/combat.gd")
const Rng = preload("res://simulation/combat_rng.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const Spells = preload("res://simulation/spells.gd")

var fixtures = null

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Rule gap check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	queue_modes()
	fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/rule_gaps_fixtures.json"))
	check(fixtures is Dictionary, "tests/rule_gaps_fixtures.json (tools/emulate_rule_gaps.py)")
	if fixtures is Dictionary:
		sword_of_sirian()
		garrison_fire()
		life_drain()
	flyer_detour()
	g3_leftovers()
	for u in world.get("units", []):
		if is_instance_valid(u): u.free()
	if world.has("host") and is_instance_valid(world.host): world.host.free()
	if failures > 0:
		printerr("Rule gap checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Rule gap checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ world helpers
var world: Dictionary = {}
var collision = CollisionData.new()

func open_ground() -> Vector2i:
	for y in range(30, 110):
		for x in range(30, 100):
			var flat := true
			for dx in range(-11, 12):
				for dy in range(-5, 6):
					var c: Dictionary = collision.cell_data(Vector2i(x + dx, y + dy))
					if not c.profile_passable[0] or not c.object_indices.is_empty() or int(c.raw[0]) != int(collision.cell_data(Vector2i(x, y)).raw[0]): flat = false
			if flat: return Vector2i(x, y)
	return Vector2i(-1, -1)

class Host extends Node:
	var test
	var local_player := 0
	var selected_building_id := -1
	var economy = null
	var selection: Array = []
	func selected_units() -> Array: return selection
	func add_unit(type_id: String, cell: Vector2i, owner: int):
		return test.add_unit_node(type_id, cell, owner)

func new_world(with_spells := false):
	for u in world.get("units", []):
		if is_instance_valid(u): u.free()
	if world.has("host") and is_instance_valid(world.host): world.host.free()
	var nav = Navigation.new(collision)
	var economy = Economy.new(0)
	economy.add_player(0, [500, 500, 500, 500])
	economy.add_player(1, [500, 500, 500, 500])
	var production = Production.new(ProductionRules.new(), economy, nav)
	production.players_in_match = [0, 1]
	var units: Array = []
	var combat = Combat.new(Rng.new(0x1badb002, 0x2468ace0), nav, production, units)
	world = {"nav": nav, "production": production, "units": units, "combat": combat, "ms": 0, "economy": economy}
	if with_spells:
		combat.auto_acquire = false
		var host := Host.new()
		host.test = self
		host.economy = economy
		root.add_child(host)
		world["host"] = host
		world["spells"] = Spells.new(combat, host)
		var p = production
		for owner in 2:
			p.hero_commands[owner] = 0
			p.hero_commands[owner] = 40 - int(p.population(owner).maximum)

func add_unit_node(type_id: String, cell: Vector2i, owner: int):
	var id := add_world_unit(type_id, cell, owner)
	world.combat.fighters[id].script = -1
	return world.units[id]

func add_world_unit(type_id: String, cell: Vector2i, owner: int) -> int:
	var unit = UnitAgent.new()
	unit.unit_id = world.units.size()
	unit.type_id = type_id
	unit.owner_id = owner
	unit.base_speed = int(world.production.rules.definition(type_id).base_speed)
	unit.navigator = world.nav
	unit.position = world.nav.center(cell)
	root.add_child(unit)
	world.units.append(unit)
	unit.sync_cell()
	world.combat.register(unit.unit_id, owner, type_id, CombatRules.unit_stats(world.production.rules.definition(type_id).raw_hex), false)
	return unit.unit_id

func move_order(id: int, cell: Vector2i) -> Dictionary:
	var unit = world.units[id]
	return {"kind": "move", "target": world.nav.center(cell), "requested": world.nav.center(cell), "group": 0, "speed": unit.base_speed, "individual": true}

func world_move(id: int, cell: Vector2i):
	var move := move_order(id, cell)
	world.combat.order_stop(id)
	world.units[id].give_order(move, "replace")
	world.combat.note_move(id, cell, move)

func run_world(limit_ms: int, watch: Callable):
	var end: int = int(world.ms) + limit_ms
	while int(world.ms) < end:
		world.ms = int(world.ms) + 25
		for unit in world.units: unit.advance(0.025)
		world.combat.update(int(world.ms))
		if watch.call(): return

# ------------------------------------------------------------------------------------------------ 1. queue modes
func queue_modes():
	var open := open_ground()
	check(open.x >= 0, "open ground for the queue world")
	if open.x < 0: return
	# Append (command 0x16): the walk first, then the attack (0x4064a0 puts the attack behind the move).
	new_world()
	var walker := add_world_unit("AHKX", open + Vector2i(-9, 0), 0)
	var enemy := add_world_unit("AHKX", open + Vector2i(6, 4), 1)
	world.combat.fighters[enemy].script = -1
	var goal := open + Vector2i(6, -3)
	world_move(walker, goal)
	var f = world.combat.fighters[walker]
	check(world.combat.chain_busy(walker), "a walking unit has a chain")
	check(world.combat.order_attack_append(walker, "unit", enemy), "Shift: the attack is accepted")
	check(f.order == null and f.queue.size() == 1, "Shift on a busy chain queues the attack behind the walk")
	var seen := {"arrived_first": false, "attacked": false}
	run_world(60000, func():
		if f.order != null and not seen.attacked:
			seen.attacked = true
			seen.arrived_first = Navigation.chebyshev(world.units[walker].cell, goal) <= 1
		return not world.combat.alive(world.combat.fighters[enemy]))
	check(seen.attacked and seen.arrived_first, "the queued attack starts when the walk has arrived (%s)" % seen)
	check(not world.combat.alive(world.combat.fighters[enemy]), "the queued attack kills the enemy")
	# Append on an empty chain: the attack starts at once (0x51da60 with no head order).
	new_world()
	walker = add_world_unit("AHKX", open + Vector2i(-9, 0), 0)
	enemy = add_world_unit("AHKX", open + Vector2i(6, 4), 1)
	f = world.combat.fighters[walker]
	check(world.combat.order_attack_append(walker, "unit", enemy) and f.order != null and f.get("queue", []).is_empty(), "Shift on an idle unit attacks at once")
	# Insert (command 0x17): the attack goes first; the interrupted walk resumes afterwards (0x406530).
	new_world()
	walker = add_world_unit("AHKX", open + Vector2i(-9, 0), 0)
	enemy = add_world_unit("AHKX", open + Vector2i(-5, 3), 1)
	world.combat.fighters[enemy].script = -1
	goal = open + Vector2i(9, 0)
	world_move(walker, goal)
	f = world.combat.fighters[walker]
	check(world.combat.order_attack_insert(walker, "unit", enemy), "Alt: the attack is accepted")
	check(f.order != null and f.queue.size() == 1 and f.queue[0].kind == "move", "Alt puts the attack in front and keeps the walk behind it")
	run_world(90000, func(): return not world.combat.alive(world.combat.fighters[enemy]) and f.order == null and world.units[walker].orders.is_empty() and not world.units[walker].in_step and f.get("queue", []).is_empty())
	check(not world.combat.alive(world.combat.fighters[enemy]), "the inserted attack kills the enemy")
	check(Navigation.chebyshev(world.units[walker].cell, goal) <= 1, "the walk resumes to its goal after the attack (%s, goal %s)" % [world.units[walker].cell, goal])
	# Alt over a current attack: the old attack waits at the front of the queue.
	new_world()
	walker = add_world_unit("AHKX", open + Vector2i(-9, 0), 0)
	enemy = add_world_unit("AHKX", open + Vector2i(6, 4), 1)
	var other := add_world_unit("AHKX", open + Vector2i(6, -4), 1)
	f = world.combat.fighters[walker]
	world.combat.order_attack(walker, "unit", enemy)
	world.combat.order_attack_insert(walker, "unit", other)
	check(int(f.order.target_id) == other and f.queue.size() == 1 and int(f.queue[0].target_id) == enemy, "Alt over an attack: the new attack first, the old one queued")
	# A replacing attack (command 3) empties the chain; Stop too.
	world.combat.order_attack_append(walker, "unit", enemy)
	world.combat.order_attack(walker, "unit", enemy)
	check(f.get("queue", []).is_empty(), "command 3 replaces the chain (0x406600)")
	world.combat.order_attack_append(walker, "unit", other)
	world.combat.order_stop(walker)
	check(f.get("queue", []).is_empty() and f.order == null, "Stop empties the chain")
	# Shift+Esc (0x4296c0): the last of two or more orders goes; a single order stays.
	world.combat.order_attack(walker, "unit", enemy)
	check(not world.combat.remove_last_order(walker), "Shift+Esc keeps a lone order (head == tail)")
	world.combat.order_attack_append(walker, "unit", other)
	world.combat.queue_move(walker, move_order(walker, open))
	check(world.combat.remove_last_order(walker) and f.queue.size() == 1 and f.queue[0].kind == "attack", "Shift+Esc drops the tail (the queued move)")
	check(world.combat.remove_last_order(walker) and f.queue.is_empty() and f.order != null, "Shift+Esc again drops the queued attack, the current one stays")
	world_move(walker, open + Vector2i(5, 0))
	world.units[walker].give_order(move_order(walker, open + Vector2i(5, 3)), "append")
	check(world.combat.remove_last_order(walker) and world.units[walker].orders.size() == 1, "Shift+Esc drops the last of two walks")
	# A dead queued target is skipped (0x51e670 drops it).
	new_world()
	walker = add_world_unit("AHKX", open + Vector2i(-9, 0), 0)
	enemy = add_world_unit("AHKX", open + Vector2i(6, 4), 1)
	world.combat.fighters[enemy].script = -1
	world_move(walker, open + Vector2i(-6, 0))
	f = world.combat.fighters[walker]
	world.combat.order_attack_append(walker, "unit", enemy)
	world.combat.fighters[enemy].hp = 0
	world.combat.fighters[enemy].state = "dying"
	run_world(10000, func(): return world.units[walker].orders.is_empty() and not world.units[walker].in_step)
	world.ms = int(world.ms) + 25
	world.combat.update(int(world.ms))
	check(f.order == null and f.get("queue", []).is_empty(), "a queued attack on a dead target is dropped")

# ------------------------------------------------------------------------------------------------ 2. Sword of Sirian
func corpse_at(cell: Vector2i, owner: int = 0) -> int:
	var id: int = add_unit_node("AHKX", cell, owner).unit_id
	var f = world.combat.fighters[id]
	f.hp = 0
	f.state = "corpse"
	f.death_ms = 0
	return id

func sword_of_sirian():
	var open := open_ground()
	if open.x < 0: return
	var fx: Dictionary = fixtures.sword
	var origin := Vector2i(int(fx.shrine_cell[0]), int(fx.shrine_cell[1]))
	for c in fx.cases:
		new_world(true)
		var shrine = world.production.add_completed(0, "BPSS", open.x, open.y)
		var at: Vector2i = world.spells.object_of("building", int(shrine.entity_id)).cell
		var shift := at - origin
		for cell in c.corpses: corpse_at(Vector2i(int(cell[0]), int(cell[1])) + shift)
		var want: Dictionary = {}
		for m in c.built:
			if m.message == "0x1f7": want = m
		var record: Dictionary = world.spells._sword_of_sirian({"kind": "building", "id": int(shrine.entity_id)}, 1)
		var name := "Sword of Sirian '%s'" % c.scenario
		check(int(record.kind) == int(want.kind) and int(record.kind) == 0x27, "%s: kind 0x27 (%s)" % [name, record.kind])
		check(int(record.amount) == int(want.amount), "%s: %d remains (original %d)" % [name, int(record.amount), int(want.amount)])
		check(int(record.w9b) == int(want.w9b) and int(record.w9d) == int(want.w9d) and int(record.w9f) == int(want.w9f), "%s: +0x9b / +0x9d / +0x9f" % name)
		check(int(record.b6) == int(want.b6) and int(record.sound) == int(want.sound) and int(record.area) == int(want.area) and int(record.radius) == int(want.radius), "%s: art, sound, area, radius" % name)
		check(String(record.effect) == String(want.effect) and String(record.effect2) == String(want.effect2) and String(record.summon) == String(want.summon), "%s: EZ02 / EZ08 / AHLX" % name)
		var mine: Array = record.cells.map(func(v): return [v.x - shift.x, v.y - shift.y])
		var theirs: Array = want.cells.map(func(v): return [int(v[0]), int(v[1])])
		mine.sort()
		theirs.sort()
		check(mine == theirs, "%s: the cells (%s, original %s)" % [name, mine, theirs])
		# The applier: one AHLX per cell (0x4aa840 case 0x27 = case 0x15's loop), the remains near the Shrine go.
		var created := 0
		for s in c.applied:
			for m in s.sent:
				if m.message == "0xfa": created += 1
		var before: int = world.units.size()
		var info: Dictionary = world.spells.cast_built(record, {"kind": "building", "id": int(shrine.entity_id)}, 1)
		var made: int = world.units.size() - before
		check(made == created, "%s: %d Dancing Swords (original %d)" % [name, made, created])
		check(world.units.slice(before).all(func(u): return String(u.type_id) == "AHLX" and u.owner_id == 0), "%s: the new units are the owner's AHLX" % name)
		if c.scenario == "edges":
			var gone: Array = info.get("result", {}).get("removed_corpses", [])
			check(gone.size() == 13, "%s: the remains within 0x15 go (dx^2 + dy^2 <= 441; rows y - 21 .. y + 20): %d" % [name, gone.size()])
	# The button: PSWS, once per second (stamped before the price), 200 crystal (message 0x1fe), else nothing.
	new_world(true)
	var shrine = world.production.add_completed(0, "BPSS", open.x, open.y)
	var sp = world.spells
	check(not sp.sword_of_sirian(int(shrine.entity_id)), "the cell needs PSWS")
	world.production.complete_research(0, "PSWS")
	world.economy.stockpiles[0] = [0, 0, 250, 0]
	check(sp.sword_of_sirian(int(shrine.entity_id)) and int(world.economy.stockpiles[0][2]) == 50, "the press pays 200 crystal (%s)" % [world.economy.stockpiles[0]])
	world.economy.stockpiles[0] = [0, 0, 500, 0]
	check(not sp.sword_of_sirian(int(shrine.entity_id)) and int(world.economy.stockpiles[0][2]) == 500, "a second press within a second does nothing")
	world.combat.now_ms += 1000
	world.economy.stockpiles[0] = [0, 0, 150, 0]
	check(not sp.sword_of_sirian(int(shrine.entity_id)) and int(world.economy.stockpiles[0][2]) == 150, "below 200 crystal: the cue, nothing paid")
	world.combat.now_ms += 500
	world.economy.stockpiles[0] = [0, 0, 200, 0]
	check(not sp.sword_of_sirian(int(shrine.entity_id)), "a refused press also stamps the second (0xa47874 before the price test)")
	world.combat.now_ms += 600
	check(sp.sword_of_sirian(int(shrine.entity_id)) and int(world.economy.stockpiles[0][2]) == 0, "after the second the press works again")
	# The key 'W' (0x426350 case 0x2e): 0x57a3b0 without the payment.
	world.economy.stockpiles[0] = [0, 0, 300, 0]
	var before: int = world.units.size()
	corpse_at(world.spells.object_of("building", int(shrine.entity_id)).cell + Vector2i(2, 1))
	sp.hot_key(int(sp.table.keys[Spells.SWORD_CASE]), 0)
	check(int(world.economy.stockpiles[0][2]) == 300 and world.units.size() == before + 2, "the key raises a sword and pays nothing (%s)" % [world.economy.stockpiles[0]])
	world.economy.stockpiles[0] = [0, 0, 199, 0]
	corpse_at(world.spells.object_of("building", int(shrine.entity_id)).cell + Vector2i(-2, 1))
	before = world.units.size()
	sp.hot_key(int(sp.table.keys[Spells.SWORD_CASE]), 0)
	check(world.units.size() == before, "the key needs 200 crystal in stock")

# ------------------------------------------------------------------------------------------------ 3. tower garrisons
const AiRules = preload("res://simulation/ai_rules.gd")

func garrison_fire():
	# 0x52ae70 / 0x52b0c0 (Emulated): the rules against every case.
	var cases: Array = fixtures.garrison.cases
	var bad := 0
	for c in cases:
		var occ: Array = c.occupants.map(func(o): return {"hero": bool(o.hero), "status": int(o.status), "computer": bool(c.computer)})
		var combat1: int = int(c.base_combat) + (int(AiRules.BUILDING_COMBAT.get(int(c.difficulty), 0)) if bool(c.computer) else 0) + CombatRules.garrison_combat(occ)
		var period: int = Combat.TOWER_PERIOD_MS[mini(16, maxi(0, int(c.base_rate) + CombatRules.garrison_rate(occ)))]
		if combat1 != int(c.combat1) or period != int(c.period) or int(c.combat0) != int(c.base_combat):
			bad += 1
			printerr("garrison case %s (%d / %d): combat %d (original %d), period %d (original %d)" % [c.name, int(c.base_combat), int(c.base_rate), combat1, int(c.combat1), period, int(c.period)])
	check(cases.size() >= 40 and bad == 0, "tower garrison terms: %d emulated cases, %d differ" % [cases.size(), bad])
	check(CombatRules.building_missile_for(11, 0, "EMA0") == "EMA2" and CombatRules.building_missile_for(0, 0, "EMA0") == "EMA0" and CombatRules.building_missile_for(4, 0, "EMA0") == "EMM0", "0x40ac00 for a building descriptor")
	# In a world: a tower with Swordsmen inside shoots faster and with more combat; an archer lends its damage type.
	var open := open_ground()
	if open.x < 0: return
	new_world()
	var garrison := {}
	world.combat.garrison_of = func(id: int) -> Array: return garrison.get(id, [])
	var tower = world.production.add_completed(0, "BWTD", open.x, open.y)
	var w: int = int(tower.definition.footprint[0])
	var h: int = int(tower.definition.footprint[1])
	check(world.combat.register_tower(tower, Vector2i(tower.left + ((w - 1) >> 1), tower.top + ((h - 1) >> 1))), "BWTD shoots")
	var t: Dictionary = world.combat.towers[tower.entity_id]
	var empty_period: int = world.combat.tower_period(t)
	var empty_combat: int = int(world.combat.building_block(tower).combat)
	var a := add_world_unit("AHKX", open + Vector2i(-6, 6), 0)
	var b := add_world_unit("AHKX", open + Vector2i(-7, 6), 0)
	world.combat.fighters[a].base["flags"] = 0
	world.combat.fighters[b].base["flags"] = 0x8000
	world.units[a].inside_building = true
	world.units[b].inside_building = true
	garrison[tower.entity_id] = [a, b]
	check(world.combat.tower_period(t) == Combat.TOWER_PERIOD_MS[mini(16, int(t.level) + 3)] and world.combat.tower_period(t) < empty_period, "two inside: the rate level + 1 + 2 (%d -> %d ms)" % [empty_period, world.combat.tower_period(t)])
	check(int(world.combat.building_block(tower).combat) == empty_combat + 9, "two inside: combat + 3 + 6 (0x52ae70(1))")
	var archer := add_world_unit("AHMX", open + Vector2i(-8, 6), 0)
	world.combat.fighters[archer].base["flags"] = 0x40000
	world.combat.fighters[archer].stats["dtype"] = 11
	world.units[archer].inside_building = true
	garrison[tower.entity_id] = [a, b, archer]
	check(int(world.combat.building_block(tower).combat) == empty_combat + 9, "a shooter adds no combat")
	var enemy := add_world_unit("AHKX", open + Vector2i(2, 3), 1)
	world.combat.fighters[enemy].script = -1
	t.target_kind = "unit"
	t.target_id = enemy
	t.next_ms = 0
	world.combat.missiles.clear()
	world.ms = int(world.ms) + 25
	world.combat.update(int(world.ms))
	var shots: Array = world.combat.missiles.filter(func(m): return String(m.get("attacker_kind", "")) == "building")
	check(not shots.is_empty() and int(shots[0].dtype) == 11 and String(shots[0].id) == "EMA2" and int(shots[0].damage) == int(t.damage), "the shooter inside lends its damage type 11 and missile EMA2; the damage stays the tower's (%s)" % [shots.map(func(m): return [m.id, m.dtype, m.damage])])

# ------------------------------------------------------------------------------------------------ 5. life drain terms
const HeroEffects = preload("res://simulation/hero_effects.gd")

## 0x526f40 for a hero (Emulated): skill 0x35's term (0x556b50 rank -> 0x556ea0 mode 1) + item power 0x3c (0x40c380), the
## composition spells.drain_terms uses (effect 0x3c, Vampirism, is the third term: 0 in these cases).
func life_drain():
	var bad := 0
	var cases: Array = fixtures.drain.cases
	for c in cases:
		var b := {"skills": c.skills, "equipment": c.equipment, "hero": bool(c.living), "hp": 100, "stats": [5, 5, 5, 5], "level": 1, "class": 0, "race": 0}
		var mine: int = HeroEffects.skill_effect(b, 0x35) + HeroEffects.item_stat(b, 0x3c)
		if mine != int(c.drain):
			bad += 1
			if bad <= 3: printerr("drain case: %d, original %d (skills %s, items %s)" % [mine, int(c.drain), c.skills, c.equipment])
	var nonzero: int = cases.filter(func(c): return int(c.drain) != 0).size()
	check(cases.size() == 300 and nonzero > 50 and bad == 0, "0x526f40 hero life drain: %d cases (%d non-zero), %d differ" % [cases.size(), nonzero, bad])

# ------------------------------------------------------------------------------------------------ G-3 1. flyers' detour
class AirPlaceholder extends RefCounted:
	var flying := true

func fixture_collision(width: int, height: int):
	var c = CollisionData.new()
	c.width = width
	c.height = height
	c.data = {"cells": []}
	for i in range(width * height): c.data.cells.append({"profile_passable": [true], "object_indices": []})
	return c

func add_flyer(nav, cell: Vector2i, id: int):
	var unit = UnitAgent.new()
	unit.unit_id = id
	unit.type_id = "AAPE"
	unit.flying = true
	unit.movement_type = 1
	unit.base_speed = 8
	unit.navigator = nav
	unit.position = nav.center(cell)
	root.add_child(unit)
	unit.sync_cell()
	return unit

func fly(unit, cell: Vector2i):
	var target: Vector2 = unit.navigator.center(cell)
	unit.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": unit.base_speed, "individual": true}, "replace")

func fly_until(units: Array, limit_ms: int, watch: Array) -> int:
	var t := 0
	while t < limit_ms and units.any(func(u): return not u.orders.is_empty()):
		t += 25
		for u in units: u.advance(0.025)
		if watch.size() >= 2 and watch[0].cell == watch[1].cell: watch.append(true)
	return t

## G-3 item 3 (Read): the attack order's group speed (0x531480 -> +0x1e -> 0x51c660), the garrison shooter by 0x51bd10(0)
## (the raw +0x92), and a script attack on an idle unit whose queued player order is next (0x51da60 with a head order).
func g3_leftovers():
	var open := open_ground()
	if open.x < 0: return
	new_world()
	var a := add_world_unit("AHKX", open + Vector2i(-9, 0), 0)
	var enemy := add_world_unit("AHKX", open + Vector2i(6, 0), 1)
	world.combat.fighters[enemy].script = -1
	var f = world.combat.fighters[a]
	check(world.combat.order_attack(a, "unit", enemy, false, 4), "an attack with the group's speed 4")
	run_world(100, func(): return not world.units[a].orders.is_empty())
	check(not world.units[a].orders.is_empty() and int(world.units[a].orders[0].speed) == 4 and int(world.units[a].base_speed) != 4, "the approach walks at the order's +0x1e (0x51c660), not the unit's own speed (%s)" % [world.units[a].orders.map(func(o): return o.speed)])
	world.combat.order_attack(a, "unit", enemy)
	world.ms = int(world.ms) + 25
	for u in world.units: u.advance(0.025)
	world.combat.update(int(world.ms))
	check(world.units[a].orders.is_empty() or int(world.units[a].orders[0].speed) == int(world.units[a].base_speed), "speed -1: the unit's own speed")
	var other := add_world_unit("AHKX", open + Vector2i(6, 4), 1)
	world.combat.fighters[other].script = -1
	world.combat.order_attack(a, "unit", enemy, false, 5)
	world.combat.order_attack_insert(a, "unit", other, 6)
	check(int(f.order.speed) == 6 and int(f.queue[0].get("speed", -1)) == 5, "Alt: the deferred attack keeps its speed in the queue")
	world.combat.order_attack_append(a, "unit", enemy, 7)
	check(int(f.queue[-1].get("speed", -1)) == 7, "Shift: the queued attack carries its speed")
	# The garrison shooter: the highest 0x51bd10(0) = the raw combat (+0x92), not the effective one.
	new_world()
	var garrison := {}
	world.combat.garrison_of = func(id: int) -> Array: return garrison.get(id, [])
	var tower = world.production.add_completed(0, "BWTD", open.x, open.y)
	var w: int = int(tower.definition.footprint[0])
	var h: int = int(tower.definition.footprint[1])
	world.combat.register_tower(tower, Vector2i(tower.left + ((w - 1) >> 1), tower.top + ((h - 1) >> 1)))
	var t: Dictionary = world.combat.towers[tower.entity_id]
	var s1 := add_world_unit("AHMX", open + Vector2i(-6, 6), 0)
	var s2 := add_world_unit("AHMX", open + Vector2i(-7, 6), 0)
	for s in [s1, s2]:
		world.combat.fighters[s].base["flags"] = 0x40000
		world.units[s].inside_building = true
	world.combat.fighters[s1].base["combat"] = 3
	world.combat.fighters[s1].stats["combat"] = 30     # a large effective bonus on a low raw combat
	world.combat.fighters[s1].stats["dtype"] = 11
	world.combat.fighters[s2].base["combat"] = 6
	world.combat.fighters[s2].stats["combat"] = 6
	world.combat.fighters[s2].stats["dtype"] = 4
	garrison[tower.entity_id] = [s1, s2]
	var target := add_world_unit("AHKX", open + Vector2i(2, 3), 1)
	world.combat.fighters[target].script = -1
	t.target_kind = "unit"
	t.target_id = target
	t.next_ms = 0
	world.combat.missiles.clear()
	world.ms = int(world.ms) + 25
	world.combat.update(int(world.ms))
	var shots: Array = world.combat.missiles.filter(func(m): return String(m.get("attacker_kind", "")) == "building")
	check(not shots.is_empty() and int(shots[0].dtype) == 4, "the shooter with the higher raw combat (+0x92) lends its damage type (%s)" % [shots.map(func(m): return [m.id, m.dtype])])
	# A script attack on an idle unit with a queued player order (the original's head): refused; before an attack-move: taken.
	new_world()
	a = add_world_unit("AHKX", open + Vector2i(-9, 0), 0)
	enemy = add_world_unit("AHKX", open + Vector2i(-6, 0), 1)
	world.combat.fighters[enemy].script = -1
	f = world.combat.fighters[a]
	f.cur = null
	world.combat.queue_move(a, move_order(a, open + Vector2i(9, 0)))
	check(not world.combat.order_attack(a, "unit", enemy, true) and f.order == null and f.queue.size() == 1, "a queued plain move is the head: the script attack is refused (0x51da60 returns 0)")
	f.queue.clear()
	world.combat.order_attack_append(a, "unit", enemy)
	check(f.order != null, "(an idle unit's Shift attack starts at once)")
	f.order = null
	f.cur = null
	f.queue = [{"kind": "attack", "target_kind": "unit", "target_id": enemy, "speed": -1}]
	check(not world.combat.order_attack(a, "unit", enemy, true), "a queued player attack is the head: refused")
	var walk := move_order(a, open + Vector2i(9, 0))
	walk["attack_move"] = true
	f.queue = [{"kind": "move", "move": walk}]
	check(world.combat.order_attack(a, "unit", enemy, true) and f.queue.size() == 1, "a queued attack-move (+0x1c 1): the script attack is inserted before it")
	check(world.combat.order_attack(a, "unit", enemy, false), "a player attack is never refused by the queue")

## 0x4308b0 / 0x430340 have no flyer branch (Read); the detour's search 0x42e180 for type 1 on the air layer (Emulated,
## tools/emulate_flyer_detour.py): flyers on the counters block a unit-aware search, not a mode-0 flight; material 9 blocks both.
func flyer_detour():
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/flyer_detour_fixtures.json"))
	check(fx is Dictionary, "tests/flyer_detour_fixtures.json (tools/emulate_flyer_detour.py)")
	if fx is Dictionary:
		var bad := 0
		var placeholder := AirPlaceholder.new()
		for case in fx.cases:
			var col = fixture_collision(int(case.size[0]), int(case.size[1]))
			for c in case.material9: col.data.cells[int(c[1]) * col.width + int(c[0])]["nav_material"] = 9
			var nav = Navigation.new(col)
			for c in case.flyers: nav.occupy(placeholder, Vector2i(int(c[0]), int(c[1])))
			var found: Dictionary = nav.search(Vector2i(int(case.start[0]), int(case.start[1])), Vector2i(int(case.goal[0]), int(case.goal[1])), int(case.limit), bool(case.unit_aware), null, 1, 1)
			var same: bool = (not found.ok) if case.path == null else (found.ok and found.cells.size() == case.path.size())
			if same and case.path != null:
				for i in case.path.size():
					if found.cells[i] != Vector2i(int(case.path[i][0]), int(case.path[i][1])): same = false
			if not same:
				bad += 1
				if bad <= 3: printerr("flyer search case %s -> %s: %s, original %s" % [case.start, case.goal, found.cells, case.path])
		check(fx.cases.size() == 60 and bad == 0, "0x42e180 type 1 on the air layer (unit-aware f <= 90 and mode 0): %d emulated cases, %d differ" % [fx.cases.size(), bad])
	var open := open_ground()
	if open.x < 0: return
	# An idle flyer in the way (solid, not on the final cell): the flyer detours at once round it on the air layer and arrives.
	var nav = Navigation.new(collision)
	var a = add_flyer(nav, open + Vector2i(-6, 0), 0)
	var b = add_flyer(nav, open, 1)
	var goal := open + Vector2i(6, 0)
	fly(a, goal)
	var watch: Array = [a, b]
	var t := fly_until([a, b], 30000, watch)
	check(a.cell == goal and watch.size() == 2 and b.cell == open, "a flyer detours round an idle flyer on the air layer and arrives (%s, goal %s, %d ms)" % [a.cell, goal, t])
	check(t < 6000, "the detour is taken at the first block, not after 100 failed waits (%d ms)" % t)
	for u in [a, b]: u.free()
	# Head-on: two flyers flying at each other wait (transient blockers), detour after five waits, both arrive.
	nav = Navigation.new(collision)
	a = add_flyer(nav, open + Vector2i(-6, 0), 0)
	b = add_flyer(nav, open + Vector2i(6, 0), 1)
	fly(a, open + Vector2i(6, 0))
	fly(b, open + Vector2i(-6, 0))
	watch = [a, b]
	t = fly_until([a, b], 40000, watch)
	check(a.cell == open + Vector2i(6, 0) and b.cell == open + Vector2i(-6, 0) and watch.size() == 2 and t < 10000, "head-on flyers pass each other by a detour (%s, %s, %d ms)" % [a.cell, b.cell, t])
	for u in [a, b]: u.free()
	# The final cell held by an idle flyer: the flyer stops where it stands (0x430340, the first block on the last cell).
	nav = Navigation.new(collision)
	a = add_flyer(nav, open + Vector2i(-6, 0), 0)
	b = add_flyer(nav, open, 1)
	fly(a, open)
	t = fly_until([a], 20000, [])
	check(a.orders.is_empty() and Navigation.chebyshev(a.cell, open) == 1, "a flyer whose goal holds an idle flyer stops next to it (%s)" % a.cell)
	for u in [a, b]: u.free()
	# Ground units round the idle flyer are no obstacle: the detour searches the air layer only.
	nav = Navigation.new(collision)
	a = add_flyer(nav, open + Vector2i(-6, 0), 0)
	b = add_flyer(nav, open, 1)
	var walkers: Array = []
	for dy in [-1, 0, 1]:
		for dx in range(-1, 2):
			var g = UnitAgent.new()
			g.unit_id = 10 + walkers.size()
			g.navigator = nav
			g.position = nav.center(open + Vector2i(dx, dy))
			root.add_child(g)
			g.sync_cell()
			walkers.append(g)
	fly(a, goal)
	t = fly_until([a], 30000, [])
	check(a.cell == goal and t < 6000, "ground units do not block a flyer's detour (%s, %d ms)" % [a.cell, t])
	for u in [a, b] + walkers: u.free()
