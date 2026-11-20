extends RefCounted
## World-level combat checks (milestone 8): stats from the ARM/BUI records, approach and swing timing, melee and
## missile damage against the emulated numeric rules, death and corpse timing, XP, building damage, automatic
## acquisition, fog of war. Rules that are Read or provisional are marked in COMBAT_RESEARCH.md.
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const Economy = preload("res://simulation/economy.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")
const Production = preload("res://simulation/production.gd")
const Placement = preload("res://simulation/placement.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Combat = preload("res://simulation/combat.gd")
const Rng = preload("res://simulation/combat_rng.gd")
const Rules = preload("res://simulation/combat_rules.gd")
const Visibility = preload("res://simulation/visibility.gd")
const HeroProfile = preload("res://simulation/hero_profile.gd")
const HeroMatch = preload("res://simulation/hero_match.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")
const EntityState = preload("res://simulation/entity_state.gd")

var t: SceneTree
var collision = CollisionData.new()
var open_cell := Vector2i(-1, -1)
var world: Dictionary

func run(tree: SceneTree):
	t = tree
	open_cell = open_ground()
	_test_stats()
	_test_duel()
	_test_death_and_corpse()
	_test_ranged()
	_test_missile_miss()
	_test_xp_and_hero()
	_test_building_siege()
	_test_building_xp()
	_test_acquisition()
	_test_fog()
	_test_rule_edges()

func check(ok: bool, label: String):
	t.call("check", ok, label) # counters live in the test script

func open_ground() -> Vector2i:
	for y in range(30, 110):
		for x in range(30, 100):
			var flat := true
			for dx in range(-8, 9):
				for dy in range(-5, 6):
					var c: Dictionary = collision.cell_data(Vector2i(x + dx, y + dy))
					if not c.profile_passable[0] or not c.object_indices.is_empty() or int(c.raw[0]) != int(collision.cell_data(Vector2i(x, y)).raw[0]): flat = false
			if flat: return Vector2i(x, y)
	return Vector2i(-1, -1)

func new_world(seed_a: int = 0x1badb002, seed_b: int = 0x2468ace0) -> Dictionary:
	if world.has("units"):
		for u in world.units:
			if is_instance_valid(u): u.free()
	var nav = Navigation.new(collision)
	var economy = Economy.new(0)
	economy.add_player(0, [500, 500, 500, 500])
	economy.add_player(1, [500, 500, 500, 500])
	var production = Production.new(ProductionRules.new(), economy, nav)
	var units: Array = []
	var combat = Combat.new(Rng.new(seed_a, seed_b), nav, production, units)
	var visibility = Visibility.new(collision.width, collision.height)
	combat.visibility = visibility
	world = {"nav": nav, "production": production, "units": units, "combat": combat, "visibility": visibility, "ms": 0}
	return world

func add_unit(type_id: String, cell: Vector2i, owner: int, hero_profile = null) -> int:
	var production = world.production
	var unit = UnitAgent.new()
	unit.unit_id = world.units.size()
	unit.type_id = type_id
	unit.owner_id = owner
	unit.base_speed = int(production.rules.definition(type_id).base_speed)
	unit.navigator = world.nav
	unit.flying = int(Rules.unit_stats(production.rules.definition(type_id).raw_hex).movement) == 1   # ARM +5 (as main_build.gd add_unit)
	if unit.flying: unit.movement_type = 1
	unit.position = world.nav.center(cell)
	t.root.add_child(unit)
	world.units.append(unit)
	unit.sync_cell()
	unit.sight_step = func(o, from_cell, to_cell, turned): world.visibility.arm_step(o, from_cell, to_cell, turned)
	var stats: Dictionary = Rules.unit_stats(production.rules.definition(type_id).raw_hex)
	var is_hero := hero_profile != null
	if is_hero:
		var match_state = HeroMatch.new()
		match_state.bind(hero_profile, EntityState.new(unit.unit_id, "AHHX", owner, unit.position))
		stats = Rules.hero_stats(hero_profile.data.stats, int(hero_profile.data.level), func(values, kind, mode): return HeroRules.derived(values, kind, mode))
		world.combat.register(unit.unit_id, owner, type_id, stats, true)
		world.combat.bind_hero(owner, unit.unit_id, match_state)
		world["hero_match_%d" % owner] = match_state
	else:
		world.combat.register(unit.unit_id, owner, type_id, stats, false)
	return unit.unit_id

func run_ms(duration: int, until: Callable = Callable()):
	var end: int = int(world.ms) + duration
	while int(world.ms) < end:
		world.ms = int(world.ms) + 25
		for unit in world.units: unit.advance(0.025)
		world.combat.update(int(world.ms))
		if world.visibility.counter >= 0: world.visibility.update(sources(), [0, 1])
		if until.is_valid() and until.call(): return

func sources() -> Array:
	var list: Array = []
	for f in world.combat.fighters.values():
		var unit = world.units[f.id]
		if f.state == "dying" or f.state == "corpse" or unit.removed: continue
		list.append({"player": f.owner, "cell": unit.cell, "radius": 10, "viewers": [f.owner]})
	return list

func f(id: int):
	return world.combat.fighters[id]

# ----------------------------------------------------------------------------------------------- tests

func _test_stats():
	check(open_cell.x >= 0, "open ground for the combat world")
	var production = ProductionRules.new()
	var knight: Dictionary = Rules.unit_stats(production.definition("AHKX").raw_hex)
	check(knight.combat == 6 and knight.dmg == 10 and knight.dtype == 6 and knight.range == 0 and knight.armour == 10 and knight.max_hp == 40 and knight.mres == 5, "Swordsman block from ARM %s" % [knight])
	var squire: Dictionary = Rules.unit_stats(production.definition("AHMX").raw_hex)
	check(squire.combat == 2 and squire.dmg == 8 and squire.dtype == 0 and squire.range == 6 and squire.armour == 5 and squire.max_hp == 30, "Squire block from ARM %s" % [squire])
	var peasant: Dictionary = Rules.unit_stats(production.definition("AHBX").raw_hex)
	check(peasant.dmg == 5 and peasant.range == 0 and peasant.max_hp == 10 and peasant.combat == 1, "Peasant block from ARM")
	var garrison: Dictionary = Rules.building_stats(production.definition("BAGA").raw_hex)
	check(garrison.max_hp == 600 and garrison.armour == 15 and garrison.mres == 15 and garrison.combat == 10, "Garrison block from BUI %s" % [garrison])
	var keep: Dictionary = Rules.building_stats(production.definition("BKK0").raw_hex)
	check(keep.max_hp == 500 and keep.armour == 15 and keep.combat == 15, "Keep block from BUI")
	var hero: Dictionary = Rules.hero_stats([7, 4, 3, 6], 1, func(values, kind, mode): return HeroRules.derived(values, kind, mode))
	check(hero.max_hp == 261 and hero.combat == 11 and hero.dmg == 27 and hero.armour == 12 and hero.speed == 10 and hero.mres == 4, "hero block from 0x54fd50 %s" % [hero])

func _test_duel():
	new_world()
	var a := add_unit("AHKX", open_cell + Vector2i(-3, 0), 0)
	var b := add_unit("AHKX", open_cell + Vector2i(3, 0), 1)
	check(world.combat.order_attack(a, "unit", b), "attack order accepted")
	check(not world.combat.order_attack(a, "unit", a), "cannot attack itself")
	var ally := add_unit("AHKX", open_cell + Vector2i(0, 3), 0)
	check(not world.combat.order_attack(a, "unit", ally), "cannot attack an own unit")
	world.combat.auto_acquire = false
	# Replay the generator: the first swing draws the message roll, then the swing roll.
	var replay = Rng.new(0x1badb002, 0x2468ace0)
	var started := {"ms": -1}
	world.combat.swing_started.connect(func(id, info): if started.ms < 0 and id == a: started.ms = info.start_ms)
	run_ms(10000, func(): return started.ms >= 0)
	check(started.ms > 0, "attacker walks to the target and starts a swing")
	var d: int = maxi(absi(world.units[a].cell.x - world.units[b].cell.x), absi(world.units[a].cell.y - world.units[b].cell.y))
	check(d <= 1, "swing starts adjacent (distance %d)" % d)
	var hp_before: int = f(b).hp
	var swing_start: int = started.ms
	replay.roll(1, 100, 0)
	var expected: Dictionary = Rules.swing(world.combat.combat_block(f(a)), Rules.unit_stats(world.production.rules.definition("AHKX").raw_hex), replay, d)
	run_ms(Rules.hit_delay_ms(93) - 25)
	check(f(b).hp == hp_before, "no damage before the hit frame")
	run_ms(100)
	check(f(b).hp == hp_before - int(expected.damage), "first melee hit applies the emulated swing damage %d (hp %d -> %d)" % [int(expected.damage), hp_before, f(b).hp])
	# Swings repeat every 16 entries (1488 ms).
	var starts: Array = []
	world.combat.swing_started.connect(func(id, info): if id == a: starts.append(info.start_ms))
	run_ms(6000)
	if starts.size() >= 2:
		var gap: int = int(starts[1]) - int(starts[0])
		check(gap >= 1488 and gap < 1488 + 100, "swing period is the 16-entry f animation (%d ms)" % gap)
	check(swing_start > 0, "swing start recorded")
	run_ms(300000, func(): return not world.combat.alive(f(a)) or not world.combat.alive(f(b)))
	check(not world.combat.alive(f(a)) != not world.combat.alive(f(b)), "exactly one duellist dies")

func _test_death_and_corpse():
	new_world()
	var a := add_unit("AHKX", open_cell + Vector2i(-1, 0), 0)
	var b := add_unit("AHKX", open_cell + Vector2i(1, 0), 1)
	world.combat.auto_acquire = false
	var cell: Vector2i = world.units[b].cell
	world.units[b].selected = true
	world.combat.apply_damage("unit", b, 9999, a)
	var death_ms: int = int(world.combat.now_ms)
	check(f(b).state == "dying" and f(b).hp == 0, "hit points at zero start the death state")
	check(world.nav.occupant(cell) == null, "dead unit leaves the occupancy grid")
	check(not world.units[b].selected and world.units[b].dying, "dead unit is deselected")
	check(world.units[b].hit_rect().size == Vector2.ZERO, "dead unit cannot be picked")
	check(not world.combat.order_attack(a, "unit", b), "dead unit is not a valid target")
	check(world.combat.kills[0] == 1, "kill counted")
	run_ms(1250)
	check(f(b).state == "dying", "d animation runs 13 frames of 100 ms")
	run_ms(100)
	check(f(b).state == "corpse" and not f(b).removed, "last d frame is held")
	check(world.units[b].anim.get("sheet", "") == "AHKXd.RLE" and world.units[b].anim.frame == 12, "corpse shows the last death frame")
	run_ms(Combat.CORPSE_MS - 1350 - 50)
	check(not f(b).removed, "corpse remains until 30.7 s")
	run_ms(100)
	check(f(b).removed and world.units[b].removed, "corpse removed after 30.7 s")
	check(Combat.CORPSE_MS == 30700, "30.7 s constant")

func _test_ranged():
	new_world(0x5a17c0de, 0x13572468)
	var squire := add_unit("AHMX", open_cell + Vector2i(-6, 0), 0)
	var knight := add_unit("AHKX", open_cell + Vector2i(1, 0), 1)
	world.combat.auto_acquire = false
	world.combat.order_attack(squire, "unit", knight)
	var launched: Array = []
	var landed: Array = []
	world.combat.missile_launched.connect(func(info): launched.append(info))
	world.combat.missile_landed.connect(func(info): landed.append(info))
	run_ms(30000, func(): return not landed.is_empty())
	check(launched.size() >= 1, "Squire launches a missile")
	if launched.is_empty() or landed.is_empty(): return
	var start_cell: Vector2i = launched[0].from
	var distance: int = maxi(absi(start_cell.x - launched[0].to.x), absi(start_cell.y - launched[0].to.y))
	check(distance <= 7 and distance >= 1, "Squire shoots from range <= 6+1 (%d)" % distance)
	var stats: Dictionary = Rules.unit_stats(world.production.rules.definition("AHKX").raw_hex)
	var want: int = Rules.armour_tail(8, 2, 0, Rules.armour_table(stats), Rules.resist_flags(stats))
	check(bool(landed[0].hit) == (landed[0].damage > 0) and (not landed[0].hit or landed[0].damage == want), "missile damage uses the impact armour reduction (%s)" % [landed[0]])
	# 0x53df60 / 0x541120 (Emulated, test_missiles.gd): one record per cell of the rounded length (at least 2), one
	# record per 25 ms arrow step; the flight ends at the record where it meets someone.
	var length: int = int(sqrt(float((start_cell.x - launched[0].aim.x) ** 2 + (start_cell.y - launched[0].aim.y) ** 2)) + 0.5)
	check(launched[0].records.size() == clampi(int(launched[0].length), 2, 80) and absi(int(launched[0].length) - length) <= 2, "arrow records = rounded length (%s)" % [launched[0].length])
	check(not bool(landed[0].hit) or int(landed[0].impacts[0].record) < launched[0].records.size(), "the arrow meets its target within its records")

func _test_missile_miss():
	new_world(0x6b2e91a4, 0x0f1e2d3c)
	var squire := add_unit("AHMX", open_cell + Vector2i(-5, 0), 0)
	var knight := add_unit("AHKX", open_cell + Vector2i(1, 0), 1)
	world.combat.auto_acquire = false
	world.combat.order_attack(squire, "unit", knight)
	var landed: Array = []
	world.combat.missile_landed.connect(func(info): landed.append(info))
	var launched: Array = []
	world.combat.missile_launched.connect(func(info): launched.append(info))
	run_ms(30000, func(): return not launched.is_empty())
	check(not launched.is_empty(), "missile launched")
	# The target steps away while the arrow flies; the arrow lands on the cell the target left.
	world.units[knight].give_order({"kind": "move", "target": world.nav.center(open_cell + Vector2i(1, 4)), "requested": world.nav.center(open_cell + Vector2i(1, 4)), "group": 0, "speed": 8, "individual": true}, "replace")
	var hp: int = f(knight).hp
	run_ms(1500, func(): return not landed.is_empty())
	if landed.is_empty(): run_ms(1500, func(): return not landed.is_empty())
	check(not landed.is_empty() and (not bool(landed[0].hit) or f(knight).hp < hp), "arrow either hits the occupant of the landing cell or nothing (%s)" % [landed])

## Missile world checks (milestone 11, run by tests/test_missiles.gd).
func run_missile_checks(tree: SceneTree):
	t = tree
	open_cell = open_ground()
	# An enemy standing under the top of the arc is flown over (height 2..3 passes units without the tall bits).
	new_world(0x0badf00d, 0x31415926)
	var squire := add_unit("AHMX", open_cell + Vector2i(-6, 0), 0)
	var middle := add_unit("AHKX", open_cell + Vector2i(-3, 0), 1)
	var knight := add_unit("AHKX", open_cell, 1)
	world.combat.auto_acquire = false
	world.combat.order_attack(squire, "unit", knight)
	var landed: Array = []
	var launched: Array = []
	world.combat.missile_launched.connect(func(info): launched.append(info))
	world.combat.missile_landed.connect(func(info): landed.append(info))
	run_ms(30000, func(): return landed.size() >= 3)
	check(launched.size() >= 3, "Squire keeps shooting (%d)" % launched.size())
	check(landed.all(func(i): return not bool(i.hit) or int(i.struck_id) != middle or int(i.impacts[0].record) <= 1),
		"arrows pass over the unit under the arc (%s)" % [landed.map(func(i): return [i.hit, i.get("struck_id", -1)])])
	check(launched.all(func(i): return int(i.flags) & 2 != 0 and String(i.id) == "EMA0"), "arrows step every 25 ms (EMA0, flags 0x82)")
	var arcs: Array = launched[0].records.map(func(r): return int(r[5]))
	check(arcs == [1, 2, 3, 2, 1, 1] or arcs.size() != 6, "6-record arrow heights 1,2,3,2,1,1 (%s)" % [arcs])
	# A friendly unit in the path never takes the arrow (owner and alliance tests of 0x53fbc0).
	new_world(0x0badf00d, 0x27182818)
	squire = add_unit("AHMX", open_cell + Vector2i(-2, 0), 0)
	var friend := add_unit("AHKX", open_cell + Vector2i(-1, 0), 0)
	knight = add_unit("AHKX", open_cell + Vector2i(1, 0), 1)
	world.combat.auto_acquire = false
	world.combat.order_attack(squire, "unit", knight)
	var hp: int = f(friend).hp
	var hits: Array = []
	world.combat.missile_landed.connect(func(info): hits.append(info))
	run_ms(20000, func(): return hits.size() >= 4)
	check(f(friend).hp == hp and hits.all(func(i): return not bool(i.hit) or int(i.struck_id) != friend), "no friendly fire")
	# Issue 11: missiles reach flying units (the Liche's bolt and the Squire's arrow against a Harpy), and a flyer's own
	# missile reaches a unit on the ground.
	for shooter_type in ["AUMX", "AHMX"]:
		new_world(0x0badf00d, 0x16180339)
		var shooter := add_unit(shooter_type, open_cell + Vector2i(-4, 0), 0)
		var harpy := add_unit("AAHA", open_cell, 1)
		check(world.units[harpy].flying, "the Harpy flies")
		world.combat.auto_acquire = false
		check(world.combat.order_attack(shooter, "unit", harpy) != false, "%s takes the attack order on a flyer" % shooter_type)
		var air_hp: int = f(harpy).hp
		var air_hits: Array = []
		world.combat.missile_landed.connect(func(info): air_hits.append(info))
		run_ms(30000, func(): return f(harpy).hp < air_hp or air_hits.size() >= 6)
		check(f(harpy).hp < air_hp, "issue 11: %s's missile hits the Harpy (hp %d of %d, %s)" % [shooter_type, f(harpy).hp, air_hp,
			air_hits.map(func(i): return [i.hit, i.get("struck_id", -1), int(i.flags) & 0x1000 != 0])])
	new_world(0x0badf00d, 0x16180339)
	var dragon := add_unit("AADU", open_cell + Vector2i(-4, 0), 0)
	var prey := add_unit("AHKX", open_cell, 1)
	world.combat.auto_acquire = false
	world.combat.order_attack(dragon, "unit", prey)
	var prey_hp: int = f(prey).hp
	run_ms(30000, func(): return f(prey).hp < prey_hp)
	check(f(prey).hp < prey_hp or int(f(dragon).stats.range) == 0, "issue 11: a flyer's missile still reaches the ground (hp %d of %d)" % [f(prey).hp, prey_hp])

func _test_xp_and_hero():
	new_world(0x3c6ef372, 0xa54ff53a)
	var profile = HeroProfile.create("t", "Sir Test")
	var hero := add_unit("AHHX", open_cell + Vector2i(-1, 0), 0, profile)
	var victim_a := add_unit("AHKX", open_cell + Vector2i(1, 0), 1)
	var victim_b := add_unit("AHKX", open_cell + Vector2i(2, 1), 1)
	var comrade := add_unit("AHKX", open_cell + Vector2i(-1, 2), 0)
	world.combat.auto_acquire = false
	var own_match = world.hero_match_0
	check(f(hero).stats.max_hp == 261 and f(hero).hero, "hero registered with derived stats")
	world.combat.apply_damage("unit", victim_a, 9999, hero)
	check(own_match.profile.data.xp == 1, "hero kill gives the hero 1 XP")
	world.combat.apply_damage("unit", victim_b, 9999, comrade)
	check(own_match.profile.data.xp == 2 and f(comrade).xp == 1 and f(hero).xp == 1, "another unit's kill gives it 1 and the hero 1")
	check(f(hero).kills == 1 and f(comrade).kills == 1, "kill counters")
	var enemy_profile = HeroProfile.create("e", "Enemy")
	var enemy_hero := add_unit("AHHX", open_cell + Vector2i(3, -2), 1, enemy_profile)
	var before: int = own_match.profile.data.xp
	world.combat.apply_damage("unit", enemy_hero, 99999, hero)
	check(own_match.profile.data.xp - before >= 5, "killing an enemy hero awards max(5, level + 1)")
	for i in 10:
		var extra := add_unit("AHKX", open_cell + Vector2i(4 + (i % 3), 3 + i / 3), 1)
		world.combat.apply_damage("unit", extra, 9999, hero)
	check(int(own_match.profile.data.xp) >= 10, "hero XP keeps rising with kills")
	check(int(own_match.profile.data.level) == 2 and int(own_match.profile.data.stat_points) == 1, "10 XP is level 2 (original threshold) and waits for point allocation")

func _test_building_siege():
	new_world(0x510e527f, 0x9b05688c)
	var site := Placement.anchor(world.production.rules.definition("BAGA"), open_cell + Vector2i(5, 0))
	var garrison = world.production.add_completed(1, "BAGA", site.x, site.y)
	world.combat.auto_acquire = false
	var swordsmen: Array = []
	for i in 3: swordsmen.append(add_unit("AHKX", open_cell + Vector2i(-4, i * 2 - 2), 0))
	for id in swordsmen: check(world.combat.order_attack(id, "building", garrison.entity_id), "attack order on an opponent building")
	check(not world.combat.order_attack(swordsmen[0], "building", 9999), "unknown building is refused")
	var hp_start: int = garrison.hit_points
	run_ms(60000)
	check(garrison.hit_points < hp_start, "units hurt the building (hp %d -> %d)" % [hp_start, garrison.hit_points])
	var damage_log: Array = []
	world.combat.damaged.connect(func(kind, id, amount, attacker): if kind == "building": damage_log.append(amount))
	run_ms(20000)
	check(damage_log.size() > 0, "building damage events")
	world.combat.apply_damage("building", garrison.entity_id, garrison.hit_points + 1, swordsmen[0])
	check(world.production.building(garrison.entity_id) == null, "destroyed building is removed")
	check(not world.nav.building_cells.has(Vector2i(site.x + 1, site.y + 1)), "footprint is cleared")
	check(f(swordsmen[0]).xp >= 3, "building kill gives XP")
	run_ms(500)
	check(f(swordsmen[1]).order == null or world.combat.target_alive(f(swordsmen[1]).order), "orders on a destroyed building end")

## D1 of REVIEW_COMBAT.md: 0x52b3e0 pushes the building amount (3, or 4 when BUI +0x38 > 0) to 0x527100 for the killer and,
## unchanged, for the killer owner's living hero when the hero is not the killer.
func _test_building_xp():
	new_world(0x6a09e667, 0xbb67ae85)
	var profile = HeroProfile.create("b", "Sir Siege")
	var hero := add_unit("AHHX", open_cell + Vector2i(-8, 4), 0, profile)
	var own_match = world.hero_match_0
	var swordsman := add_unit("AHKX", open_cell + Vector2i(-6, 0), 0)
	var garrison_def: Dictionary = world.production.rules.definition("BAGA")
	check(Rules.i16(garrison_def.raw_hex.hex_decode(), 0x38) == 0, "Garrison BUI +0x38 is 0 (amount 3)")
	var sites: Array = []
	for i in 3: sites.append(Placement.anchor(garrison_def, open_cell + Vector2i(6 + i * 12, 14)))
	var a = world.production.add_completed(1, "BAGA", sites[0].x, sites[0].y)
	var b = world.production.add_completed(1, "BAGA", sites[1].x, sites[1].y)
	var c = world.production.add_completed(1, "BAGA", sites[2].x, sites[2].y)
	world.combat.apply_damage("building", a.entity_id, a.hit_points + 1, swordsman)
	check(f(swordsman).xp == 3 and int(own_match.profile.data.xp) == 3, "a Swordsman's Garrison kill: killer 3, hero 3 (xp %d, hero %d)" % [f(swordsman).xp, int(own_match.profile.data.xp)])
	world.combat.apply_damage("building", b.entity_id, b.hit_points + 1, hero)
	check(int(own_match.profile.data.xp) == 6, "the hero's own building kill counts once: 3 (hero %d)" % int(own_match.profile.data.xp))
	var patched: Dictionary = garrison_def.duplicate()
	var raw: PackedByteArray = garrison_def.raw_hex.hex_decode()
	raw.encode_s16(0x38, 2)
	patched["raw_hex"] = raw.hex_encode()
	c.definition = patched
	world.combat.apply_damage("building", c.entity_id, c.hit_points + 1, swordsman)
	check(f(swordsman).xp == 7 and int(own_match.profile.data.xp) == 10, "BUI +0x38 > 0: 4 to the killer and 4 to the hero (xp %d, hero %d)" % [f(swordsman).xp, int(own_match.profile.data.xp)])
	world.combat.apply_damage("unit", hero, 99999, -1)
	var d = world.production.add_completed(1, "BAGA", sites[0].x, sites[0].y)
	var before: int = int(own_match.profile.data.xp)
	world.combat.apply_damage("building", d.entity_id, d.hit_points + 1, swordsman)
	check(int(own_match.profile.data.xp) == before, "a dead hero gets no share")

func _test_acquisition():
	new_world(0x1f83d9ab, 0x5be0cd19)
	var seer := add_unit("AHKX", open_cell + Vector2i(-6, 0), 0)
	var near_enemy := add_unit("AHKX", open_cell + Vector2i(2, 0), 1)
	var far_enemy := add_unit("AHKX", open_cell + Vector2i(-6, 11), 1)
	world.visibility.settle(sources(), [0, 1])
	world.combat.auto_acquire = true
	# Milestone 9: the attitude scripts decide. Stand Ground (script 1) attacks only adjacent enemies; Defensive
	# (script 2, every slice unit's default) attacks enemies in max(12, range) inside its guard box.
	f(near_enemy).script = 1
	f(far_enemy).script = 1
	f(seer).script = 1
	run_ms(1500)
	check(f(seer).order == null, "Stand Ground does not acquire an enemy 8 cells away")
	f(seer).script = 2
	check(world.visibility.is_visible(0, world.units[near_enemy].cell), "enemy within the sight circle is visible")
	check(not world.visibility.is_visible(0, world.units[far_enemy].cell), "enemy outside the sight circle is hidden")
	var found = world.combat.acquire(f(seer))
	check(found != null and found.id == near_enemy, "acquisition picks the visible enemy, not the hidden one")
	run_ms(1500)
	check(f(seer).order != null and f(seer).order.target_id == near_enemy, "an idle Defensive unit attacks the visible enemy on a script tick")
	# The scan window is max(12, range): 11 cells away is inside it, but only when the fog lets the owner see the cell.
	new_world(0x428a2f98, 0x71374491)
	var guard := add_unit("AHKX", open_cell + Vector2i(0, 0), 0)
	var edge := add_unit("AHKX", open_cell + Vector2i(11, 0), 1)
	world.combat.auto_acquire = true
	world.visibility.settle(sources(), [0, 1])
	check(not world.visibility.is_visible(0, world.units[edge].cell), "11 cells away is outside the radius-10 sight circle")
	check(world.combat.acquire(f(guard)) == null, "a hidden enemy inside the scan window is not acquired")
	world.visibility.fog = false
	world.visibility.shroud = false
	var found_edge = world.combat.acquire(f(guard))
	check(found_edge != null and found_edge.id == edge, "with fog and shroud off the window of 12 reaches it")
	# Priority: a candidate that is attacking an ally of the searcher scores higher than a nearer idle one.
	new_world(0xb5c0fbcf, 0xe9b5dba5)
	world.visibility.fog = false
	world.visibility.shroud = false
	var a0 := add_unit("AHKX", open_cell + Vector2i(0, 0), 0)
	var ally := add_unit("AHKX", open_cell + Vector2i(8, 6), 0)
	var idle_enemy := add_unit("AHKX", open_cell + Vector2i(3, 0), 1)
	var busy_enemy := add_unit("AHKX", open_cell + Vector2i(8, 4), 1)
	world.combat.auto_acquire = false
	f(busy_enemy).order = {"kind": "attack", "target_kind": "unit", "target_id": ally, "planned_cell": Vector2i(-9999, -9999)}
	var pick = world.combat.acquire(f(a0))
	check(pick != null and pick.id == busy_enemy, "an enemy fighting an ally outranks a nearer idle enemy (0x533c40)")
	f(busy_enemy).order = null
	pick = world.combat.acquire(f(a0))
	check(pick != null and pick.id == idle_enemy, "otherwise the nearer enemy wins")

func _test_fog():
	var vis = Visibility.new(40, 40)
	var lamp := [{"player": 0, "cell": Vector2i(20, 20), "radius": 10, "viewers": [0]}]
	for u in 4: vis.update(lamp, [0, 1])
	check(vis.is_visible(0, Vector2i(20, 30)) and vis.is_visible(0, Vector2i(27, 27)) and not vis.is_visible(0, Vector2i(28, 28)), "sight circle edge (trunc hypot <= 10), first sweep on the 4th update")
	check(not vis.is_visible(1, Vector2i(20, 20)), "players have separate maps")
	for u in 200: vis.update(lamp, [0, 1])
	check(vis.is_visible(0, Vector2i(20, 20)), "a stationary sprite's disc is not darkened (its cells are disarmed by the sweep)")
	vis.arm(Vector2i(20, 20), 14)
	for u in Visibility.CYCLE_UPDATES: vis.update([], [0, 1])
	check(not vis.is_visible(0, Vector2i(20, 20)) and vis.is_explored(0, Vector2i(20, 20)), "armed cells nobody re-sees go dark at the darken but stay explored")
	check(vis.is_visible(1, Vector2i(5, 5)) == false, "unexplored cells are hidden")
	vis.fog = false
	check(vis.is_visible(0, Vector2i(20, 20)) and not vis.is_visible(0, Vector2i(1, 1)), "shroud only: explored cells count as visible")
	vis.shroud = false
	check(vis.is_visible(1, Vector2i(1, 1)), "no fog and no shroud: everything is visible")
	vis.fog = true
	vis.shroud = true
	var cells: Array = [Vector2i(20, 20), Vector2i(21, 20)]
	check(not vis.placement_allows(0, cells), "placement refused on dark cells for the local player (0x435900)")
	vis.sweep(lamp, [0])
	check(not vis.placement_allows(0, cells), "a darkened cell is not re-lit until something arms it again")
	vis.arm_step(0, Vector2i(20, 20), Vector2i(20, 20), false)
	vis.sweep(lamp, [0])
	check(vis.placement_allows(0, cells), "placement allowed on lit explored cells")
	# Production (open item of PRODUCTION_RESEARCH.md): the local player's placement needs explored and visible cells.
	new_world()
	var keep_site: Vector2i = Placement.anchor(world.production.rules.definition("BKK0"), open_cell + Vector2i(-12, 0))
	world.production.add_completed(0, "BKK0", keep_site.x, keep_site.y)
	world.production.visibility = world.visibility
	var dark: Dictionary = world.production.can_place(0, "BAGA", open_cell + Vector2i(4, 0))
	check(not dark.ok and dark.reason == "cell is not visible", "placement refused in the dark: %s" % [dark])
	world.visibility.sweep([{"player": 0, "cell": open_cell + Vector2i(4, 0), "radius": 10, "viewers": [0]}], [0, 1])
	var lit: Dictionary = world.production.can_place(0, "BAGA", open_cell + Vector2i(4, 0))
	check(lit.ok, "placement allowed on lit explored cells: %s" % [lit])
	check(world.production.can_place(1, "BAGA", open_cell + Vector2i(4, 0)).reason != "cell is not visible", "the check applies to the local player only")
	world.visibility.fog = false
	world.visibility.shroud = false
	check(world.production.can_place(0, "BAGA", open_cell + Vector2i(4, 0)).ok, "no fog and no shroud: placement unchanged")
	# Allies share sight; the owner's enemies do not.
	var shared = Visibility.new(40, 40)
	shared.sweep([{"player": 1, "cell": Vector2i(10, 10), "radius": 10, "viewers": [0, 1]}], [0, 1])
	check(shared.is_visible(0, Vector2i(10, 10)) and shared.is_visible(1, Vector2i(10, 10)), "an allied sprite lights the map of every ally")

func _test_rule_edges():
	var teams := [1, 2, 0, 0, 0, 0, 0]
	check(Rules.hostile(teams, 0, 1) and not Rules.hostile(teams, 0, 0), "relations table")
	var rng = Rng.new(1, 2)
	var sq := {"combat": 2, "dmg": 8, "dtype": 0, "range": 6, "armour": 5, "mres": 0, "res1": -1, "res2": -1, "enc": 0, "near_hero": false, "building": false}
	check(Rules.swing(sq, sq, rng, 1).has("fault"), "ranged vs ranged melee swing faults in the original (0 / 0)")
	check(not Rules.swing(sq, dict_with(sq, "near_hero", true), rng, 1).has("fault"), "near its hero the divisor is not zero")
	# Damage types outside 0..6 (8-fix guard, Provisional): the swing faults before drawing, the missile tail faults.
	var knight := {"combat": 6, "dmg": 10, "dtype": 6, "range": 0, "armour": 10, "mres": 5, "res1": -1, "res2": -1, "enc": 0, "near_hero": false, "building": false}
	for bad in [7, 8, 11, 12, 100, -1, -32768]:
		var guarded = Rng.new(0xdeadbeef, 0x12345678)
		var state_before: Array = guarded.state()
		var got: Dictionary = Rules.swing(dict_with(knight, "dtype", bad), knight, guarded, 0)
		check(got.has("fault") and guarded.state() == state_before, "damage type %d: swing faults without a draw" % bad)
		var started: Dictionary = Rules.attack_start(dict_with(knight, "dtype", bad), knight, guarded, 0)
		check(started.has("fault") and not started.ranged, "damage type %d: melee attack start reports the fault" % bad)
		check(Rules.armour_tail(10, 2, bad, Rules.armour_table(knight), Rules.resist_flags(knight)) == Rules.FAULT_DAMAGE, "damage type %d: missile tail faults" % bad)
	for good in 7: check(not Rules.swing(dict_with(knight, "dtype", good), knight, Rng.new(1, 2), 0).has("fault"), "damage type %d is valid" % good)
	check(Rules.effective_combat({"combat": 6, "enc": 0, "near_hero": true}) == 10 and Rules.effective_combat({"combat": 1, "enc": 5}) == 1, "effective combat: +4 near the hero, minimum 1")

func dict_with(d: Dictionary, key: String, value) -> Dictionary:
	var copy := d.duplicate()
	copy[key] = value
	return copy
