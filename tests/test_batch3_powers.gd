extends "res://tests/test_hero_spells.gd"
## B3-1 (BATCH3_RESEARCH.md section 2): the batch-3 race powers against tests/batch3_fixtures.json (`building_cells`, `powers`,
## `souls`, `firebomb`, `ammunition`, `goblin`, `rabies`, `missile_kinds`, `gate`, `regeneration`) and
## tests/batch3_review_fixtures.json (`rain`, `rain_end`, `petrify`, `immunity`, `cooldown`, `regeneration`), on the hero spells'
## stand-alone combat world. The sweep (E13) has its own suite (tests/test_sweep.gd). The buttons in the scene are in the three
## batch-3 world checks.

const RacePowers = preload("res://simulation/race_powers.gd")
const DayNight = preload("res://simulation/day_night.gd")
const UnitRanks = preload("res://simulation/unit_ranks.gd")
const START := 50000

var fixtures: Dictionary = {}
var review: Dictionary = {}

func run():
	fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch3_fixtures.json"))
	review = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch3_review_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the batch 3 world")
	if centre.x >= 0:
		for part in ["cells", "powers", "rain", "rain_end", "souls", "soul_rewards", "firebomb", "ammunition", "goblin", "rabies", "immunity",
				"missile_kinds", "petrify", "gate", "regeneration", "pdbt", "saved"]:
			call(part)
	clear_world()
	if failures > 0:
		printerr("Batch 3 powers checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Batch 3 powers checks passed: %d" % checks)
	quit(0)

func now_at(ms: int):
	world.ms = ms
	world.combat.next_update_ms = ms + 25
	world.combat.now_ms = ms

func fighter(id: int):
	return world.combat.fighters[id]

class ForcedRng extends RefCounted:
	var values: Array = []
	var calls: Array = []
	func roll(count: int, sides: int, bonus: int = 0) -> int:
		calls.append([count, sides])
		if values.is_empty(): return 100
		return int(values.pop_front())

# ------------------------------------------------------------------------------------------------ the building page (E3)
func cells():
	for r in fixtures.building_cells:
		if int(r.owner) != 1 or not bool(r.finished): continue               # the HUD's own owner / construction tests
		var research: Array = r.research
		var got: Dictionary = RacePowers.b3_building_cells(String(r.building), int(r.race), func(code): return research.has(code), bool(r.rain))
		for index in [7, 8]:
			var want: Array = r.cells[index]
			var b3 := int(want[0]) in RacePowers.B3_TIP_LINE
			if not b3:
				check(not got.has(index), "%s race %d: no batch-3 cell %d" % [r.building, int(r.race), index])
				continue
			check(got.has(index) and int(got[index][0]) == int(want[0]) and bool(got[index][1]) == (int(want[2]) != 0),
				"%s race %d %s: cell %d %s, the original %s" % [r.building, int(r.race), research, index, got.get(index), want])
		var repair: Array = r.cells[6]
		var shown := int(repair[0]) == 0x11 and String(repair[1]) == "0x4d0b70"
		check(RacePowers.repair_cell_shown(int(r.race), bool(r.hurt)) == shown, "%s race %d hurt %s: Repair %s" % [r.building, int(r.race), r.hurt, shown])
	for icon in RacePowers.B3_TIP_LINE: check(int(RacePowers.B3_TIP_LINE[icon]) > 0, "tooltip line for icon 0x%x" % icon)

func powers():
	for r in fixtures.powers.brood:
		var first: Array = r.presses[0].messages
		var n := RacePowers.brood_count(int(r.command[0]), int(r.command[1]))
		var pays := n > 0 and int(r.stock[0]) >= RacePowers.BROOD_GOLD * n and String(r.building) in RacePowers.BROOD_BUILDINGS
		check(pays == not first.is_empty(), "Brood %s at %s with %d gold: %s" % [r.building, r.command, int(r.stock[0]), first.size()])
		if pays:
			check(int(first[0].payment.words[0]) == RacePowers.BROOD_GOLD * n and first.size() == n + 1, "Brood pays %d for %d" % [RacePowers.BROOD_GOLD * n, n])
			check(first.slice(1).all(func(m): return String(m.type) == RacePowers.BROOD_UNIT and int(m.no_start_xp_3b) == 0 and int(m.rally[0]) == -1), "AVBX, no rally, no flag")
		for p in r.presses.slice(1): check(p.messages.is_empty(), "a second press within 3 s does nothing")
	for row in review.cooldown:
		check((not row.messages.is_empty()) == (int(row.gap) > RacePowers.BROOD_MS), "Brood after %d ms" % int(row.gap))
	for tier in [1, 2]:
		var spirit: Dictionary = RacePowers.SPIRITS[tier]
		for r in fixtures.powers["spirit_i" if tier == 1 else "spirit_ii"]:
			var first: Array = r.presses[0].messages
			var pays: bool = String(r.building) == RacePowers.SPIRIT_HALL and mini(1, int(r.command[1]) - int(r.command[0])) > 0 and int(r.stock[2]) >= int(spirit.crystal)
			check(pays == not first.is_empty(), "Spirit %d at %s with %d crystal" % [tier, r.command, int(r.stock[2])])
			if pays:
				check(int(first[0].payment.words[3]) == int(spirit.crystal) and String(first[1].type) == String(spirit.unit) and int(first[1].no_start_xp_3b) == 1,
					"Spirit %d: %d crystal, %s without start experience" % [tier, int(spirit.crystal), spirit.unit])
	for r in fixtures.powers.stormcall:
		var first: Array = r.presses[0].messages
		var pays: bool = int(r.stock[2]) >= RacePowers.STORMCALL_CRYSTAL
		check(pays == not first.is_empty(), "Stormcall with %d crystal" % int(r.stock[2]))
		if pays:
			check(int(first[0].payment.words[3]) == RacePowers.STORMCALL_CRYSTAL, "80 crystal")
			check(int(first[1].kind) == 4 and int(first[1].amount) == RacePowers.stormcall_amount(int(r.is_night) == 1) and String(first[1].effect) == "EZ19",
				"record kind 4 amount %d" % int(first[1].amount))
		check(r.presses.size() < 2 or not r.presses[1].messages.is_empty(), "Stormcall has no throttle")

# ------------------------------------------------------------------------------------------------ rain (R2)
func weather(state: Dictionary, clock: String) -> DayNight:
	var dn := DayNight.new(true)
	if clock == "night":
		dn.hour = DayNight.NIGHT_CLOCK[0]; dn.mark_a = DayNight.NIGHT_CLOCK[1]; dn.mark_b = DayNight.NIGHT_CLOCK[2]
	dn.raining = int(state.rain) != 0
	dn.stopping = int(state.stopping) != 0
	dn.storm = int(state.lightning) != 0
	dn.rain_target = int(state.level)
	dn.drops = int(state.drops)
	dn.rain_floor = int(state.floor)
	dn.rain_step = int(state.step)
	dn.mode = int(state.fade)
	return dn

func state_of(dn: DayNight) -> Dictionary:
	return {"rain": int(dn.raining), "stopping": int(dn.stopping), "lightning": int(dn.storm), "level": dn.rain_target, "drops": dn.drops,
		"floor": dn.rain_floor, "step": dn.rain_step, "fade": dn.mode}

func same(got: Dictionary, want: Dictionary, label: String):
	for key in want: check(int(got[key]) == int(want[key]), "%s: %s %d, the original %d" % [label, key, int(got[key]), int(want[key])])

func rain():
	for r in review.rain:
		var dn := weather(r.before, String(r.clock))
		dn.apply_record(int(r.amount))
		same(state_of(dn), r.after, "amount %d %s %s" % [int(r.amount), r.clock, r.start])
		check(dn.hour == weather(r.before, String(r.clock)).hour, "the clock itself is unchanged")

func rain_end():
	var dn := DayNight.new(true)
	var rows: Array = review.rain_end
	for r in rows:
		var step := String(r.step)
		if step == "record": dn.apply_record(int(r.amount))
		elif step == "second record": dn.apply_record(4)
		elif step.begins_with("Dark Citadel"): dn.apply_record(3)
		elif step.begins_with("amount 0"): dn.apply_record(0)
		elif step == "the fade over":
			for i in int(r.ticks): dn._transition_tick()
		elif step.begins_with("Rites"): dn.apply_record(0)
		elif step.begins_with("Stormcall"):
			finish_fade(dn)
			dn = DayNight.new(true)
			dn.to_night()
			check(not dn.apply_record(RacePowers.stormcall_amount(dn.is_night())), "a fade drops Stormcall's record")
		elif step == "amount 3 from dry":
			dn = DayNight.new(true)
			dn.apply_record(3)
		elif step == "amount 2":
			finish_fade(dn)
			dn.apply_record(2)
		elif step == "frames while rising":
			for i in 400: dn.rain_frame()
		elif r.has("ended_after"):
			var frames := 0
			var limit := 6000 if r.ended_after == null else int(r.ended_after)
			while frames < limit and dn.raining:
				dn.rain_frame()
				frames += 1
			if r.ended_after == null: check(dn.raining, "%s: the rain does not end by itself" % step)
			else: check(not dn.raining and frames == int(r.ended_after), "%s: ends after %d frames (%d)" % [step, int(r.ended_after), frames])
		same(state_of(dn), r.state, step)

# ------------------------------------------------------------------------------------------------ souls (E7 / E8)
func finish_fade(dn: DayNight):
	var guard := 0
	while dn.mode != 0 and guard < 1000:
		dn._transition_tick()
		guard += 1

func souls():
	for r in fixtures.souls:
		if r.roll != null or bool(r.allied) or bool(r.hero) or String(r.victim) == RacePowers.SOUL: continue   # the forced draws: below
		new_world()
		var killer := unit(String(r.killer), Vector2i(0, 0), OWNER)
		var victim := unit(String(r.victim), Vector2i(1, 0), OWNER if int(r.victim_owner) == int(r.killer_owner) else ENEMY)
		now_at(START)
		var before: int = world.units.size()
		world.combat.apply_damage("unit", victim, 100000, killer)
		var made: Array = world.units.slice(before).map(func(u): return String(u.type_id))
		var want: Array = r.messages.map(func(m): return String(m.type))
		check(made == want, "%s kills %s: %s, the original %s" % [r.killer, r.victim, made, want])
		if not made.is_empty():
			var soul = fighter(before)
			check(int(soul.owner) == RacePowers.SOUL_OWNER and world.units[before].cell == centre + Vector2i(1, 0), "owner 6 at the victim's cell")
			check(int(soul.get("lifetime_until", 0)) == START + RacePowers.SOUL_LIFETIME_MS, "lifetime 120 s")
			run_world(RacePowers.SOUL_LIFETIME_MS + 100)
			check(not world.combat.alive(soul), "the soul is gone after 120 s")
	# an animal: 1d100 < 20
	for r in fixtures.souls:
		if r.roll == null: continue
		new_world()
		var killer := unit("AVIX", Vector2i(0, 0), OWNER)
		var victim := unit(String(r.victim), Vector2i(1, 0), 6)
		var forced := ForcedRng.new()
		forced.values = [int(r.roll)]
		var real = world.combat.rng
		world.combat.rng = forced
		var before: int = world.units.size()
		world.combat.apply_damage("unit", victim, 100000, killer)
		world.combat.rng = real
		check((world.units.size() > before) == not r.messages.is_empty(), "an animal at roll %d: soul %s" % [int(r.roll), not r.messages.is_empty()])

func soul_rewards():
	for r in fixtures.souls:
		if String(r.victim) != RacePowers.SOUL: continue
		new_world()
		var k: int = hero(String(r.killer), {}, OWNER) if bool(r.hero) else unit(String(r.killer), Vector2i(0, 0), OWNER)
		var soul := unit(RacePowers.SOUL, Vector2i(1, 0), 6)
		var kf = fighter(k)
		if r.mana_before != null:
			kf["mana"] = int(r.mana_before[0])
			kf["max_mana"] = int(r.mana_before[1])
		var xp: int = int(kf.xp)
		var events: Array = []
		world.combat.race_event.connect(func(kind, _info): events.append(kind))
		if bool(r.hero):
			kf["max_mana"] = 100
			kf["mana"] = 50
		world.combat.apply_damage("unit", soul, 100000, k)
		if r.mana_before != null:
			check([int(kf.mana), int(kf.max_mana)] == [int(r.mana[0]), int(r.mana[1])], "%s eats a soul: mana %d / %d, the original %s" % [r.killer, int(kf.mana), int(kf.max_mana), r.mana])
			check(events.has("soul_mana") == not r.killer_type_effect.is_empty(), "%s: EMLE %s" % [r.killer, not r.killer_type_effect.is_empty()])
		elif bool(r.hero):
			check(int(kf.mana) == 75, "the hero's pool + 25: %d" % int(kf.mana))
		elif String(r.killer) == RacePowers.REAPER:
			check(int(kf.xp) - xp >= RacePowers.REAPER_XP, "the Reaper gains 20 experience: %d" % (int(kf.xp) - xp))
		else:
			check(not events.has("soul_mana"), "%s gains nothing" % r.killer)

# ------------------------------------------------------------------------------------------------ the Firebomb (E9)
func firebomb():
	var data: Dictionary = fixtures.firebomb
	var ints := func(a: Array) -> Array: return a.map(func(p): return [int(p[0]), int(p[1])])
	check(ints.call(data.table.near) == RacePowers.BLAST_NEAR and ints.call(data.table.far) == RacePowers.BLAST_FAR, "the blast tables 0x611330 / 0x611370")
	for r in data.rows:
		match String(r.case):
			"ring":
				new_world()
				var bomb := unit(RacePowers.FIREBOMB, Vector2i(0, 0), OWNER)
				var victims := {}
				for c in r.cells:
					var v := unit(String(r.victim), Vector2i(int(c[0]), int(c[1])), ENEMY, {"hp": 500})
					victims[v] = int(c[2])
				world.combat.apply_damage("unit", bomb, 100000, -1)
				for v in victims: check(500 - int(fighter(v).hp) == int(victims[v]), "%s at %s: %d, the original %d" % [r.victim, world.units[v].cell - centre, 500 - int(fighter(v).hp), int(victims[v])])
			"alchemist":
				new_world()
				world.production.research[OWNER] = r.research.duplicate()
				var bomb := unit(RacePowers.FIREBOMB, Vector2i(0, 0), OWNER)
				var near := unit("AHIX", Vector2i(1, 0), ENEMY, {"hp": 500})
				var far := unit("AHIX", Vector2i(2, 0), ENEMY, {"hp": 500})
				world.combat.apply_damage("unit", bomb, 100000, -1)
				check(500 - int(fighter(near).hp) == int(r.near) and 500 - int(fighter(far).hp) == int(r.far), "%s: near %d far %d, the original %d / %d" % [r.research, 500 - int(fighter(near).hp), 500 - int(fighter(far).hp), int(r.near), int(r.far)])
			"own and building":
				new_world()
				var bomb := unit(RacePowers.FIREBOMB, Vector2i(0, 0), OWNER)
				var own := unit("AHIX", Vector2i(1, 0), OWNER, {"hp": 500})
				var enemy := unit("AHIX", Vector2i(-1, 0), ENEMY, {"hp": 500})
				world.combat.apply_damage("unit", bomb, 100000, -1)
				check(int(fighter(own).hp) == int(r.own) and int(fighter(enemy).hp) == int(r.enemy), "own %d, enemy %d" % [int(fighter(own).hp), int(fighter(enemy).hp)])
	# the hit entry: the bomb dies, the target takes no swing
	new_world()
	var bomb := unit(RacePowers.FIREBOMB, Vector2i(0, 0), OWNER)
	var target := unit("AHIX", Vector2i(1, 0), ENEMY, {"hp": 500})
	now_at(START)
	world.combat._hit(fighter(bomb), {"target_kind": "unit", "target_id": target, "ranged": false, "result": {"damage": 99, "effect": 0, "param": 0}, "hit_done": false})
	check(not world.combat.alive(fighter(bomb)), "the Firebomb dies at its hit entry")
	check(500 - int(fighter(target).hp) == 35, "the target takes the blast alone, not the swing: %d" % (500 - int(fighter(target).hp)))

# ------------------------------------------------------------------------------------------------ stored animals (E10)
func ammunition():
	for r in fixtures.ammunition.kills:
		new_world()
		var k := unit(String(r.killer), Vector2i(0, 0), OWNER)
		var v := unit(String(r.victim), Vector2i(int(r.gap), 0), 6)
		world.combat.apply_damage("unit", v, 100000, k)
		check(int(fighter(k).get("stored_animals", 0)) == int(r.stored), "%s kills %s at %d: %d stored, the original %d" % [r.killer, r.victim, int(r.gap), int(fighter(k).get("stored_animals", 0)), int(r.stored)])
	for r in fixtures.ammunition.shots:
		if r.missile_args == null: continue                     # the prey itself: a melee strike (order_range 0)
		new_world()
		var s := unit(String(r.unit), Vector2i(0, 0), OWNER)
		var t: int
		if String(r.target).begins_with("B"): t = unit("AHIX", Vector2i(6, 0), ENEMY)
		else: t = unit(String(r.target), Vector2i(6, 0), ENEMY)
		var f = fighter(s)
		f["stored_animals"] = int(r.stored_before)
		now_at(START)
		var count: int = world.combat.missiles.size()
		world.combat._hit(f, {"target_kind": "unit", "target_id": t, "ranged": true, "message_roll": 50, "result": {}, "hit_done": false})
		var m: Dictionary = world.combat.missiles[count] if world.combat.missiles.size() > count else {}
		var want_id := ""
		for i in 4: want_id += char((int(r.missile_args[0]) >> (8 * i)) & 0xff)
		var want_damage := int(r.setup[0][1]) & 0xffff
		check(int(f.get("stored_animals", 0)) == int(r.stored_after), "%s: %d stored after the shot" % [r.unit, int(f.get("stored_animals", 0))])
		check(not m.is_empty() and int(m.damage) == want_damage, "%s with %d stored: damage %s, the original %d" % [r.unit, int(r.stored_before), m.get("damage"), want_damage])
		if int(r.stored_before) > 0: check(String(m.get("id", "")) == want_id, "the missile is %s: %s" % [want_id, m.get("id")])

# ------------------------------------------------------------------------------------------------ the Gobshooter's Goblin (E12)
func goblin():
	for r in fixtures.goblin:
		new_world()
		var s := unit("ASGS", Vector2i(-6, 0), OWNER)
		set_command(OWNER, used(OWNER) + int(r.command[1]) - int(r.command[0]))
		var cell: Vector2i = centre if String(r.case) != "map edge" else Vector2i(0, centre.y)
		if String(r.case) == "cell taken": unit("AHIX", Vector2i.ZERO, ENEMY)
		var forced := ForcedRng.new()
		forced.values = [int(r.roll)]
		var real = world.combat.rng
		world.combat.rng = forced
		var before: int = world.units.size()
		var m := {"id": "EMA0" if String(r.case) == "other missile" else RacePowers.GOBLIN, "attacker": s, "cell": cell}
		world.combat._goblin_landing(m)
		world.combat.rng = real
		var made: Array = world.units.slice(before).filter(func(u): return u.type_id == RacePowers.GOBLIN)
		check(made.size() == r.messages.size(), "%s: %d Goblins, the original %d" % [r.case, made.size(), r.messages.size()])
		if not made.is_empty():
			check(int(fighter(made[0].unit_id).script) == RacePowers.GOBLIN_SCRIPT and made[0].cell == cell and made[0].owner_id == OWNER, "Rampant, at the cell, the shooter's")

# ------------------------------------------------------------------------------------------------ Rabies (E14)
func rabies():
	for r in fixtures.rabies:
		var strength := int(r.word) & 0xff
		if int(r.word) != 0 and String(r.target) == "AHIX":
			var want: int = 1 if int(r.diseased) == 1 else 0
			var chance := RacePowers.rabies_chance(strength, int(r.plague), int(r.magic_armour))
			check((int(r.roll) <= chance) == bool(want), "word 0x%x roll %d armour %d plague %d: chance %d" % [int(r.word), int(r.roll), int(r.magic_armour), int(r.plague), chance])
		if int(r.plague) != 0: continue
		new_world()
		var a := unit(RacePowers.RABID, Vector2i(0, 0), OWNER)
		var t := unit(String(r.target), Vector2i(1, 0), ENEMY)
		if int(r.word) != 0: fighter(a)["rabies"] = strength
		if r.armour_96 != null:
			fighter(t).base["mres"] = int(r.armour_96)
			fighter(t).stats["mres"] = int(r.armour_96)
		now_at(START)
		var forced := ForcedRng.new()
		forced.values = [int(r.roll)]
		var real = world.combat.rng
		world.combat.rng = forced
		world.spells.venom_hit(fighter(a), fighter(t))
		world.combat.rng = real
		check(bool(fighter(t).get("diseased", false)) == (int(r.diseased) == 1), "%s word 0x%x roll %d: diseased %d" % [r.target, int(r.word), int(r.roll), int(r.diseased)])
		if int(r.diseased) == 1: check(int(fighter(t).disease_until) == int(r.until), "until %d (%d)" % [int(r.until), int(fighter(t).disease_until)])
	# the words: 0x606 for a Wolfrider made after PRAB, 0x605 for one that stood at the research
	new_world()
	var old := unit(RacePowers.RABID, Vector2i(0, 0), OWNER)
	world.production.complete_research(OWNER, RacePowers.RABIES_RESEARCH)
	var young := unit(RacePowers.RABID, Vector2i(2, 0), OWNER)
	check(int(fighter(old).get("rabies", 0)) == RacePowers.RABIES_EXISTING and int(fighter(young).get("rabies", 0)) == RacePowers.RABIES_NEW, "0x605 for the old, 0x606 for the new")

func immunity():
	new_world()
	for i in review.immunity.size():
		var r: Dictionary = review.immunity[i]
		var id := unit(String(r.unit), Vector2i(i % 6 * 2, i / 6 * 2), ENEMY)
		check(world.spells.diseasable(fighter(id)) == (int(r.diseased) == 1), "%s: diseasable %d" % [r.unit, int(r.diseased)])
	var wolf := unit(RacePowers.RABID, Vector2i(0, 8), ENEMY)
	fighter(wolf)["rabies"] = 6
	check(not world.spells.diseasable(fighter(wolf)), "a rabid unit is immune (class 6)")

# ------------------------------------------------------------------------------------------------ missile kinds, Petrify (E11 / R3)
func missile_kinds():
	for code in RacePowers.PETRIFIERS:
		new_world()
		var s := unit(code, Vector2i(0, 0), OWNER)
		var t := unit("AHIX", Vector2i(6, 0), ENEMY)
		var count: int = world.combat.missiles.size()
		world.combat._hit(fighter(s), {"target_kind": "unit", "target_id": t, "ranged": true, "message_roll": 50, "result": {}, "hit_done": false})
		check(world.combat.missiles.size() > count and int(world.combat.missiles[count].get("kind", 0)) == 3, "%s: kind 3" % code)
	var kinds: Array = fixtures.missile_kinds.filter(func(r): return RacePowers.PETRIFIERS.has(String(r.unit)))
	check(kinds.size() == 3 and kinds.all(func(r): return int(r.kind) == 3), "the fixture's ATOX / AOXX rows are all kind 3")

func petrify():
	for r in review.petrify:
		if not bool(r.host) or String(r.case) == "effect 0x3e" or String(r.target).begins_with("B"): continue
		new_world()
		var s := unit("ATOX", Vector2i(-6, 0), ENEMY)
		var t := unit(String(r.target), Vector2i(0, 0), OWNER, {"hp": int(r.hp_before)})
		fighter(t).max_hp = maxi(int(fighter(t).max_hp), int(r.hp_before))
		world.economy.capacities[ENEMY][3] = 30000
		world.economy.stockpiles[ENEMY][3] = int(r.stone_impact_alone)
		now_at(START)
		var m := {"id": "EMA0", "attacker": s, "attacker_kind": "unit", "damage": int(r.damage), "dtype": 0, "impacts": [], "shooter_elevation": 0,
			"flags": 0, "mode": 2, "kind": int(r.kind)}
		if String(r.case) == "shooter dead": world.combat.apply_damage("unit", s, 100000, -1, "none")
		var stone_before: int = int(world.economy.resources(ENEMY)[3])
		world.combat._impact(m, {"kind": "unit", "id": t})
		var petrified: bool = r.messages.has("0x20e")
		check(bool(fighter(t).removed) == petrified, "%s: petrified %s (no corpse)" % [r.case, petrified])
		if petrified:
			check(int(world.economy.resources(ENEMY)[3]) == mini(30000, stone_before + RacePowers.PETRIFY_STONE), "%s: + 100 stone (clamped): %d" % [r.case, int(world.economy.resources(ENEMY)[3])])
		else:
			check(int(world.economy.resources(ENEMY)[3]) == stone_before, "%s: no stone" % r.case)

# ------------------------------------------------------------------------------------------------ Gate (E17), regeneration (E20 / R4), PDBT
func gate():
	for r in fixtures.gate:
		if int(r.level) != 1: continue
		new_world()
		world.production.research[OWNER] = r.research.duplicate()
		var type_id := String(r.created[0][0])
		check(world.spells.summon_start(OWNER, type_id) == int(r.experience), "%s with %s: 0x557d90 %d, the original %d" % [r.ability, r.research, world.spells.summon_start(OWNER, type_id), int(r.experience)])

func regeneration():
	new_world()
	for r in fixtures.regeneration:
		var id := unit(String(r.unit), Vector2i(int(r.rank) * 2, 0), ENEMY, {"rank": int(r.rank)})
		check(world.combat.regeneration_rate(fighter(id)) == int(r.interval), "%s rank %d: interval %d, the original %d" % [r.unit, int(r.rank), world.combat.regeneration_rate(fighter(id)), int(r.interval)])
	# The hurt Troll heals 1 hp per 2.5 s, starting 2.5 s after the hit; an unhurt unit's timer stays 0.
	new_world()
	var troll := unit("AOMX", Vector2i(0, 0), OWNER)
	var whole := unit("AOIX", Vector2i(3, 0), OWNER)
	now_at(START)
	var hp: int = int(fighter(troll).hp)
	world.combat.apply_damage("unit", troll, 10, -1, "none")
	check(int(fighter(troll).get("regen_ms", 0)) == START + 2500, "the hit arms the Troll's timer 2.5 s on: %d" % int(fighter(troll).get("regen_ms", 0)))
	run_world(2400)
	check(int(fighter(troll).hp) == hp - 10, "nothing before 2.5 s")
	run_world(200)
	check(int(fighter(troll).hp) == hp - 9, "1 hp at 2.5 s")
	run_world(2500)
	check(int(fighter(troll).hp) == hp - 8, "1 more at 5 s")
	check(int(fighter(whole).get("regen_ms", 0)) == 0, "an unhurt unit's timer stays 0")

func pdbt():
	new_world()
	var id := unit(RacePowers.PDBT_TYPE, Vector2i(0, 0), OWNER)
	var before: Array = CombatRules.armour_table(world.combat.combat_block(fighter(id))).duplicate()
	world.production.research[OWNER] = [RacePowers.PDBT_RESEARCH]
	var after: Array = CombatRules.armour_table(world.combat.combat_block(fighter(id)))
	check(int(after[3]) == int(before[3]) + RacePowers.PDBT_FIRE and int(after[0]) == int(before[0]), "PDBT: fire armour + 50 (%d -> %d)" % [int(before[3]), int(after[3])])

## The new state is plain data in the saved fighters and the weather object.
func saved():
	new_world()
	var id := unit("AOMX", Vector2i(0, 0), OWNER)
	fighter(id)["stored_animals"] = 2
	var s: Dictionary = preload("res://simulation/save_game.gd").capture(world.combat, world.combat._SAVE_SKIP)
	check(int(s.fighters[id].stored_animals) == 2, "the stored animals are in the save")
	var dn := DayNight.new(true)
	dn.apply_record(4)
	var state: Dictionary = preload("res://simulation/save_game.gd").capture(dn, ["rng", "log"])
	check(bool(state.raining) and bool(state.storm), "the rain is in the weather object's save")
