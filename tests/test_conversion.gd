extends SceneTree
## Milestone 12: conversion of buildings. The emulated fixtures (tests/conversion_fixtures.json, tools/emulate_conversion.py:
## 0x52da90, the 0x5489e0 owner mask, 0x523af0, 0x52f9b0, 0x523dc0 / 0x52fc00, 0x40ad40) against MatchConversion, then the
## ownership transfer (Read 0x4a6cc0) on a real Production / Economy / Mines world.

const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const Economy = preload("res://simulation/economy.gd")
const Rules = preload("res://simulation/production_rules.gd")
const Production = preload("res://simulation/production.gd")
const Building = preload("res://simulation/building_state.gd")
const Mines = preload("res://simulation/mines.gd")
const Entity = preload("res://simulation/entity_state.gd")
const Targets = preload("res://simulation/conversion_targets.gd")
const MatchConversion = preload("res://simulation/match_conversion.gd")

var checks := 0
var failures := 0
var rules = Rules.new()
var collision = CollisionData.new()

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		if failures < 30: printerr("Conversion check failed: ", label)

func _init():
	var f = JSON.parse_string(FileAccess.get_file_as_string("res://tests/conversion_fixtures.json"))
	if not (f is Dictionary) or not f.has("eligibility"):
		printerr("Conversion fixtures missing or unreadable")
		quit(1)
		return
	fixtures(f)
	transfer_checks()
	scan_checks()
	keep_checks()
	if failures == 0: print("Conversion checks passed: ", checks)
	else: printerr("Conversion failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

# ------------------------------------------------------------------------------------------------ emulated parity
func fixtures(f: Dictionary):
	for c in f.eligibility:
		var got := MatchConversion.building_convertible(String(c.code), bool(c.constructing), int(c.hp), bool(c.rubble), int(c.capacity), int(c.occupants))
		check(got == bool(c.eligible), "0x52da90 %s" % c)
	for c in f.owner_mask:
		var got := MatchConversion.owner_allows(int(c.actor), int(c.target), bool(c.computer), bool(c.allied))
		check(got == (int(c.found) > 0), "0x5489e0 owner mask %s" % c)
	for c in f.actor_terms:
		var research := int(c.research) != 0          # the emulated 0x437f70 stub answers every research id alike
		var t := MatchConversion.actor_terms({"kind": String(c.kind), "code": String(c.code), "hero_alive": bool(c.hero_alive),
			"power": int(c.power), "radius": int(c.radius), "research": research, "pbro": research, "mode": int(c.mode), "bonus": int(c.bonus)})
		check(bool(t.ok) == bool(c.ok) and int(t.seconds) == int(c.duration) and int(t.radius) == int(c.out_radius),
			"0x523af0 %s -> %s" % [c, t])
	for c in f.progress:
		check(MatchConversion.progress(bool(c.active), int(c.start), int(c.finish), int(c.now)) == int(c.percent), "progress %s" % c)
	for c in f.duration_table:
		check(MatchConversion.duration_seconds(int(c.power)) == int(c.seconds), "0x40ad40(%d)" % int(c.power))
	# 0x52f9b0: one neutral 1x1 Gold Mine `distance` cells east of the Keep's anchor.
	for c in f.keep_start:
		var w := world()
		var keep = Building.new(900, "BKK0", 0, Vector2(40 * 32, 40 * 24), {"footprint": [1, 1], "hit_points": 500}, 40, 40)
		var mine = Building.new(901, "BRG1", 6, Vector2((40 + int(c.distance)) * 32, 40 * 24), {"footprint": [1, 1], "hit_points": 500}, 40 + int(c.distance), 40)
		keep.constructing = bool(c.constructing)
		if bool(c.job): keep.job_item = "AHBX"
		w.production.buildings[900] = keep
		w.production.buildings[901] = mine
		w.conversion.computer[0] = bool(c.computer)
		var finish: int = w.conversion.begin_keep(keep, 10000)
		check((finish >= 0) == bool(c.active), "0x52f9b0 starts %s" % c)
		if bool(c.active):
			check(keep.keep_radius == int(c.radius) and (keep.keep_finish_ms - keep.keep_start_ms) / 1000 == int(c.seconds), "0x52f9b0 terms %s" % c)
		w.conversion.dispose()

# ------------------------------------------------------------------------------------------------ worlds
func world() -> Dictionary:
	var nav = Navigation.new(collision)
	var economy = Economy.new(0)
	economy.add_player(0, [500, 500, 500, 500])
	economy.add_player(1, [500, 500, 500, 500])
	var production = Production.new(rules, economy, nav)
	var conversion = MatchConversion.new()
	conversion.setup(production, null, {"building_cfg": {"buildings": [{"code": "BWTC", "garrison": 4}]}}, {0: false, 1: true},
		func(a, b): return a == b)
	return {"nav": nav, "economy": economy, "production": production, "conversion": conversion}

class FakeMines:
	var mines: Dictionary = {}
	var converted_log: Array = []
	func convert(id: int, owner: int):
		mines[id].entity.worker_count = 0
		mines[id].entity.owner = owner
		converted_log.append([id, owner])

func hero_terms(seconds: int = 30, reach: int = 8) -> Dictionary:
	return {"ok": true, "seconds": seconds, "radius": reach}

# ------------------------------------------------------------------------------------------------ transfer (Read 0x4a6cc0)
func transfer_checks():
	var w := world()
	var production = w.production
	var economy = w.economy
	var conversion = w.conversion
	var keep = production.add_completed(1, "BKK1", 30, 60)
	var garrison = production.add_completed(1, "BAGA", 38, 60)
	economy.refresh_capacity(0)
	economy.refresh_capacity(1)
	check(economy.capacity(1)[0] == 1500 and economy.capacity(0)[0] == 1000, "the level-1 Keep raises player 1's capacity (0x52aac0)")
	check(production.enqueue(garrison.entity_id, "AHKX", 0).ok, "a Swordsman queued at the enemy Garrison")
	production.enqueue(garrison.entity_id, "AHKX", 0)
	garrison.rally = Vector2i(50, 70)
	garrison.repeat = true
	var paid: Array = garrison.job_cost.duplicate()
	var stock0: Array = economy.resources(0)
	var stock1: Array = economy.resources(1)
	var log: Array = []
	conversion.transferred.connect(func(id, before, after): log.append([id, before, after]))
	var hero := Entity.new(77, "AHHX", 0, Vector2(34 * 32 + 16, 64 * 24 + 12))
	var finish: int = conversion.begin_unit(77, 0, hero.cell(), hero_terms(30, 8), 1000)
	check(finish == 31000, "hero conversion of 30 s starts with targets in range")
	conversion.update(31000)
	check(int(keep.owner) == 1, "finish == now does not complete (0x51e670: finish < now)")
	conversion.update(31001)
	check(int(keep.owner) == 0 and int(garrison.owner) == 0, "the Keep and the Garrison change owner at completion")
	check(log.size() == 2, "two transfers")
	check(economy.capacity(0)[0] == 1500 and economy.capacity(1)[0] == 1000, "the Keep's capacity moves to the new owner")
	check(garrison.job_item == "" and garrison.queue.is_empty(), "0x52d7e0: the running job is cancelled and the queue dropped")
	var refund_to_new: bool = true
	for lane in 4:
		refund_to_new = refund_to_new and int(economy.resources(0)[lane]) == mini(int(stock0[lane]) + int(paid[lane]), int(economy.capacity(0)[lane]))
		refund_to_new = refund_to_new and int(economy.resources(1)[lane]) == int(stock1[lane])
	check(refund_to_new, "the refund goes to the new owner (0x52d7e0 runs after the owner change): %s" % [economy.resources(0)])
	check(garrison.rally == Vector2i(-1, -1) and not garrison.repeat, "rally point and repeat cleared (0x52e6b0(-1, -1), +0x190)")
	check(production.requirement_met(0, "BKK0") and not production.requirement_met(1, "BKK0"), "dependencies follow the owner (0x40b290 / 0x40b170)")
	check(production.population(0).maximum > production.population(1).maximum, "the command limit follows the Keep")
	check(not conversion.converting(77), "the job ends")
	# cancelled: nothing converts
	var keep2 = production.add_completed(1, "BKK0", 60, 60)
	conversion.begin_unit(78, 0, Vector2i(62, 64), hero_terms(10, 6), 40000)
	conversion.cancel(78)
	conversion.update(60000)
	check(int(keep2.owner) == 1, "a cancelled conversion converts nothing")
	conversion.dispose()

## The completion scan: a fresh 0x5489e0 at the actor's cell, eight at most, eligibility at completion time.
func scan_checks():
	var w := world()
	var production = w.production
	var conversion = w.conversion
	var mines := FakeMines.new()
	conversion.mines = mines
	for i in 10:
		var e := Entity.new(5000 + i, "BRG1", 6, Vector2((20 + i) * 32, 30 * 24))
		e.worker_count = 3
		mines.mines[5000 + i] = {"entity": e, "footprint": Vector2i(2, 2)}
	var tower = Building.new(6000, "BWTD", 1, Vector2(25 * 32, 34 * 24), {"footprint": [2, 2], "hit_points": 400}, 25, 34)
	production.buildings[6000] = tower                            # a tower: never convertible (second letter W)
	check(conversion.select(0, Vector2i(24, 31), 19).size() == 8, "at most eight targets (0x5489e0 limit)")
	conversion.begin_unit(80, 0, Vector2i(24, 31), hero_terms(5, 19), 0)
	conversion.update(5001)
	var owned := mines.mines.values().filter(func(m): return int(m.entity.owner) == 0)
	check(owned.size() == 8 and mines.converted_log.size() == 8, "eight mines converted")
	check(owned.all(func(m): return int(m.entity.worker_count) == 0), "converted mines lose their workers (+0xca = 0)")
	check(int(tower.owner) == 1, "the tower keeps its owner")
	# allied: a computer actor skips its ally, a human actor converts it (Emulated mask)
	var ally = production.add_completed(1, "BPFL", 70, 40)
	conversion.allied = func(a, b): return a == b or (a <= 1 and b <= 1)
	conversion.computer[0] = true
	check(not conversion.select(0, Vector2i(71, 41), 6).has(ally), "a computer player does not convert its ally's buildings")
	conversion.computer[0] = false
	check(conversion.select(0, Vector2i(71, 41), 6).has(ally), "a human player converts an ally's buildings (0x5489e0 mask)")
	# unfinished buildings resist
	var site = production.add_completed(1, "BAGA", 90, 40)
	site.constructing = true
	check(not conversion.select(0, Vector2i(91, 41), 6).has(site), "unfinished construction is not convertible (+0xcc)")
	conversion.dispose()

func keep_checks():
	var w := world()
	var production = w.production
	var conversion = w.conversion
	var keep = production.add_completed(0, "BKK0", 30, 60)
	var enemy = production.add_completed(1, "BAGA", 45, 62)
	check(conversion.begin_keep(keep, 0) == 150000, "a human Keep converts for 150 s")
	check(conversion.keep_progress(keep, 75000) == 50, "0x52fc00 at half time")
	check(not production.can_queue(keep.entity_id, "AHBX").ok, "no production while the Keep converts (0x4d2300 mode 5)")
	conversion.update(149999)
	check(int(enemy.owner) == 1, "not before the finish")
	conversion.update(150000)
	check(int(enemy.owner) == 0 and not keep.keep_converting, "the Keep converts at now >= finish (building update 0x52cf71)")
	# a converting Keep that changes owner stops (0x4a6cc0 -> 0x52fbc0)
	var their_keep = production.add_completed(1, "BKK0", 80, 60)
	var bait = production.add_completed(0, "BPFL", 95, 62)
	check(conversion.begin_keep(their_keep, 200000) > 0, "the computer Keep starts converting")
	check(their_keep.keep_radius == 32, "computer Keep radius 32")
	conversion.begin_unit(81, 0, Vector2i(82, 62), hero_terms(5, 6), 200000)
	conversion.update(205001)
	check(int(their_keep.owner) == 0 and not their_keep.keep_converting, "the converted Keep's own conversion stops")
	conversion.update(400000)
	check(int(bait.owner) == 0, "and converts nothing afterwards")
	conversion.dispose()
