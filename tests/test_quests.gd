extends SceneTree
## Q-1 (QUESTS_RESEARCH.md): every quest type of Quest.xcr through the port's events, against the original's control flow
## read from 0x43db30 (progress), 0x43d3a0 (completion), 0x43d560 (rewards) and the tail of 0x43dde0 (research owned). The
## world is a set of fakes so each event can be raised alone; the real records of Bzma.dat and Bmsh.dat drive the checks.
## Evidence label: Read (the eligibility of these records stays Emulated in test_encounters_review.gd).
const Encounters = preload("res://simulation/encounters.gd")
var checks := 0
var failures := 0

class FakeBuilding:
	var owner := 0
	var original_type_id := ""
	var entity_id := 0
	var hit_points := 500
	var left := 0
	var top := 0

class FakeRng:
	func roll(_count: int, _sides: int, bias: int) -> int:
		return 1 + bias

class FakeNavigator:
	func free_cell_near(_cell: Vector2i) -> Vector2i:
		return Vector2i(-1, -1)        # unit rewards are not placed in this world

class FakeCombat:
	signal building_hit(id: int, attacker_kind: String, attacker_id: int)
	signal died(kind: String, id: int, killer_owner: int)
	var fighters := {}
	var heroes := {}
	var ani := {}
	var now_ms := 0
	var rng := FakeRng.new()
	var allies := {}               # "a,b" -> true (0x748915)
	var navigator := FakeNavigator.new()
	func alive(f) -> bool:
		return f != null and int(f.hp) > 0
	func allied(a: int, b: int) -> bool:
		return allies.has("%d,%d" % [a, b])

class FakeEconomy:
	var stock := {}
	func resources(p: int) -> Array:
		return stock.get(p, [0, 0, 0, 0])
	func credit(p: int, amount: Array):
		var s: Array = resources(p).duplicate()
		for i in 4: s[i] += int(amount[i])
		stock[p] = s
	func try_spend(p: int, cost: Array) -> bool:
		var s: Array = resources(p).duplicate()
		for i in 4: s[i] -= int(cost[i])
		stock[p] = s
		return true

class FakeProduction:
	signal building_destroyed(id: int)
	signal building_placed(id: int)
	signal building_converted(id: int, previous: int)
	signal building_completed(id: int)
	var buildings := {}
	var research := {}             # player -> Array of ids
	func building(id: int):
		return buildings.get(id)
	func research_level(p: int, id: String) -> int:
		return 1 if research.get(p, []).has(id) else 0
	func complete_research(p: int, id: String) -> bool:
		if research_level(p, id) != 0: return false
		var list: Array = research.get(p, [])
		list.append(id)
		research[p] = list
		return true

class FakeHero:
	var xp := 0
	var items: Array = []
	func award_xp(amount: int) -> bool:
		xp += amount
		return true
	func receive_item(id: int, _source: String):
		items.append(id)

var combat: FakeCombat
var production: FakeProduction
var economy: FakeEconomy
var enc
var next_id := 100
const SITE := 1

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func add_building(owner: int, code: String) -> int:
	var b := FakeBuilding.new()
	b.owner = owner
	b.original_type_id = code
	b.entity_id = next_id
	next_id += 1
	production.buildings[b.entity_id] = b
	production.building_placed.emit(b.entity_id)
	return b.entity_id

func add_unit(owner: int, code: String, hero := false) -> int:
	var id := next_id
	next_id += 1
	combat.fighters[id] = {"id": id, "owner": owner, "type_id": code, "hp": 10, "hero": hero}
	return id

func kill_unit(id: int, killer_owner: int):
	combat.died.emit("unit", id, killer_owner)
	combat.fighters.erase(id)

func raze(id: int, killer_owner: int):
	production.buildings.erase(id)
	combat.died.emit("building", id, killer_owner)

func convert_to(id: int, owner: int):
	var b = production.buildings[id]
	var previous: int = b.owner
	b.owner = owner
	production.building_converted.emit(id, previous)

func fresh():
	combat = FakeCombat.new()
	production = FakeProduction.new()
	economy = FakeEconomy.new()
	var data: Dictionary = Encounters.load_json("res://assets/encounters.json")
	var catalogue: Dictionary = Encounters.load_json("res://assets/catalogue.json")
	enc = Encounters.new(combat, production, economy, null, catalogue, {"ani": {}, "quests": data.quests}, {"lairs": [], "xp_levels": []})
	enc.givers[SITE] = enc._giver("BZMA")
	enc.givers[SITE + 1] = enc._giver("BMSH")

## Accepts `record` for player 0 at the site, bypassing the offer roll (the roll and eligibility have their own suites).
func take(r: Dictionary, player := 0, site := SITE) -> Dictionary:
	enc.givers[site].record = r
	enc.givers[site].picked = false
	check(enc.accept(player, site), "accept %s %d '%s' (type %d)" % [enc.givers[site].code, int(r.index), r.get("name", ""), int(r.type)])
	return enc.quests[player]

func first(code: String, type: int) -> Dictionary:
	for r in enc.quest_records(code):
		if int(r.type) == type and int(r.enabled) != 0: return r
	return {}

func _init():
	fresh()
	var all: Array = enc.quest_records("BZMA") + enc.quest_records("BMSH")
	check(all.size() == 88, "Bzma.dat 45 + Bmsh.dat 43 records")
	var types := {}
	for r in all:
		check(Encounters.supported(r), "record %d type %d is supported" % [int(r.index), int(r.type)])
		types[int(r.type)] = true
	for t in [0, 1, 2, 3, 5, 6, 7, 9]: check(types.has(t), "the data holds type %d" % t)

	# Type 1: kills of units of other, non-allied owners (0x43db30 event 0); allies, own units and animals do not count.
	fresh()
	var q := take(first("BZMA", 1))
	combat.allies["0,2"] = true
	kill_unit(add_unit(0, "AHKX"), 0)
	kill_unit(add_unit(2, "AHKX"), 0)
	kill_unit(add_unit(6, "ACCA"), 0)
	check(int(q.progress) == 0, "type 1: own, allied and animal victims do not count")
	kill_unit(add_unit(1, "AHKX"), 0)
	kill_unit(add_unit(6, "AMJX"), 0)
	check(int(q.progress) == 2, "type 1: an enemy and a neutral Gnoll count (no owner test against 6)")
	kill_unit(add_unit(1, "AHKX"), 1)
	check(int(q.progress) == 2, "type 1: a kill by another player does not count")

	# Type 5: heroes (+0xb4) only.
	fresh()
	q = take(first("BZMA", 5))
	kill_unit(add_unit(1, "AHKX"), 0)
	check(int(q.progress) == 0, "type 5: an ordinary unit does not count")
	kill_unit(add_unit(1, "AHHX", true), 0)
	check(int(q.progress) == 1 and enc.completed(0, q.record, int(q.progress)), "type 5: an enemy hero counts and completes a count-1 quest")

	# Type 6: units of the target type.
	fresh()
	var r6 := first("BZMA", 6)
	q = take(r6)
	kill_unit(add_unit(1, "AHKX" if String(r6.target) != "AHKX" else "AHFX"), 0)
	check(int(q.progress) == 0, "type 6: another type does not count")
	for i in int(r6.count): kill_unit(add_unit(1, String(r6.target)), 0)
	check(int(q.progress) == int(r6.count) and enc.completed(0, r6, int(q.progress)), "type 6: %d x %s complete '%s'" % [int(r6.count), r6.target, r6.get("name", "")])

	# Type 2: destroyed buildings of other, non-allied owners below 6 (0x52b3e0: owner < 6).
	fresh()
	q = take(first("BZMA", 2))
	raze(add_building(6, "BLGL"), 0)
	check(int(q.progress) == 0, "type 2: a neutral building does not count (0x52b3e0 owner < 6)")
	raze(add_building(0, "BKKA"), 0)
	check(int(q.progress) == 0, "type 2: one's own building does not count")
	combat.allies["0,2"] = true
	raze(add_building(2, "BKKA"), 0)
	check(int(q.progress) == 0, "type 2: an ally's building does not count")
	raze(add_building(1, "BKKA"), 0)
	check(int(q.progress) == 1, "type 2: an enemy building counts")
	raze(add_building(1, "BKKA"), -1)
	check(int(q.progress) == 1, "type 2: a building with no killer does not count")

	# Type 7: destroyed buildings of the target type.
	fresh()
	var r7 := first("BZMA", 7)
	q = take(r7)
	raze(add_building(1, "BKKA"), 0)
	check(int(q.progress) == 0, "type 7: another type does not count")
	raze(add_building(1, String(r7.target)), 0)
	check(int(q.progress) == 1 and enc.completed(0, r7, 1), "type 7: a %s of an enemy completes '%s'" % [r7.target, r7.get("name", "")])

	# Type 3: converted buildings whose owner was not 6 and is not allied (0x4a6cc0 -> event 2).
	fresh()
	var r3 := first("BZMA", 3)
	q = take(r3)
	convert_to(add_building(6, "BMGM"), 0)
	check(int(q.progress) == 0, "type 3: a neutral building converted does not count")
	combat.allies["0,2"] = true
	convert_to(add_building(2, "BKKA"), 0)
	check(int(q.progress) == 0, "type 3: an ally's building does not count")
	for i in int(r3.count): convert_to(add_building(1, "BKKA"), 0)
	check(int(q.progress) == int(r3.count) and enc.completed(0, r3, int(q.progress)), "type 3: %d enemy buildings converted complete '%s'" % [int(r3.count), r3.get("name", "")])
	convert_to(add_building(1, "BKKA"), 1)
	check(int(q.progress) == int(r3.count), "type 3: a conversion by another player does not count")

	# Type 9: complete while the player owns a building of the target type (0x534020); events 2 and 3 only count.
	fresh()
	var r9 := first("BZMA", 9)
	q = take(r9)
	check(not enc.completed(0, r9, int(q.progress)), "type 9: not complete without a %s" % r9.target)
	var b9 := add_building(1, String(r9.target))
	convert_to(b9, 0)
	check(int(q.progress) == 1 and enc.completed(0, r9, int(q.progress)), "type 9: a converted %s counts and completes" % r9.target)
	convert_to(b9, 1)
	check(not enc.completed(0, r9, int(q.progress)), "type 9: lost again, not complete though progress is %d (0x43d3a0 tests ownership)" % int(q.progress))
	var built := add_building(0, String(r9.target))
	production.building_completed.emit(built)
	check(int(q.progress) == 2 and enc.completed(0, r9, int(q.progress)), "type 9: a finished %s of one's own counts and completes" % r9.target)

	# Type 8 (no record ships it): finished buildings of the target type (event 3).
	fresh()
	var r8 := first("BZMA", 9).duplicate()
	r8.type = 8
	r8.count = 2
	q = take(r8)
	production.building_completed.emit(add_building(0, String(r8.target)))
	production.building_completed.emit(add_building(1, String(r8.target)))
	check(int(q.progress) == 1 and not enc.completed(0, r8, 1), "type 8: only one's own finished building counts")
	production.building_completed.emit(add_building(0, String(r8.target)))
	check(enc.completed(0, r8, int(q.progress)), "type 8: two finished %s complete" % r8.target)

	# Type 4 never completes.
	var r4 := r8.duplicate()
	r4.type = 4
	check(not enc.completed(0, r4, 99), "type 4: never complete")

	# Rewards: research (+0x21 -> 0xfb -> 0x436500) and the research eligibility test of 0x43dde0.
	fresh()
	var rr: Dictionary = {}
	for r in enc.quest_records("BMSH"):
		if bool(r.reward_research): rr = r
	check(not rr.is_empty(), "Bmsh.dat holds a research reward (%s)" % rr.get("name", ""))
	check(enc.eligible(0, rr) == enc._eligible_type(0, rr), "research reward not owned: the type test decides")
	q = take(rr)
	for i in int(rr.count): kill_unit(add_unit(1, String(rr.target)), 0)
	var hero := FakeHero.new()
	var reward: Dictionary = enc.complete(0, SITE, hero, Vector2i(-1, -1))
	check(String(reward.get("research", "")) == String(rr.research) and production.research_level(0, String(rr.research)) == 1, "the research reward %s completes for the player" % rr.research)
	check(not enc.eligible(0, rr), "a record whose research reward the player owns is refused (0x43dde0 tail)")
	check(hero.xp == 20, "the hero gains 20 XP")

	# POGL doubles the quest XP; other players' quests from the same giver are cleared (0x43d560's first loop).
	fresh()
	production.research[0] = ["POGL"]
	var lost := []
	enc.quest_lost.connect(func(p, _r): lost.append(p))
	var r5 := first("BZMA", 5)
	take(r5, 1)
	take(r5, 2, SITE + 1)
	take(r5, 0)
	kill_unit(add_unit(1, "AHHX", true), 0)
	hero = FakeHero.new()
	reward = enc.complete(0, SITE, hero, Vector2i(-1, -1))
	check(int(reward.get("xp", 0)) == 40 and hero.xp == 40, "POGL: the hero gains 40 XP")
	check(not enc.quests.has(1) and lost == [1], "the other player's quest from the same giver is cleared (line 0xbc)")
	check(enc.quests.has(2), "a quest from another giver stays")
	check(enc.givers[SITE].resting and not enc.givers[SITE].picked, "the giver rests after the completion")

	q3_checks()
	enc = null
	if failures == 0: print("Quest checks passed: ", checks)
	else: printerr("Quest failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

# ------------------------------------------------------------------------------------------------ Q-3
## The 0x503c60 answers a fixture case needs: Quests, local, the site search and the visit; nothing else happens (the spell
## table is disabled, no potions).
class SiteEnv:
	var enc
	var spec: Dictionary
	var visits: Array = []
	func _init(e, s):
		enc = e
		spec = s
	func local() -> bool: return int(spec.get("local", 7)) == int(spec.owner)
	func morphing() -> bool: return false
	func deleted() -> bool: return false
	func now() -> int: return int(spec.now)
	func quests() -> bool: return bool(enc.quests_enabled)
	func quest_site() -> int: return enc.computer_site(Vector2i(40, 40), int(spec.now))
	func quest_visit(id: int): visits.append(id)
	func count(_r: int, _rel: int, _k: int, _hp: int, _x: int, _stop: int) -> int: return 0
	func potions() -> int: return 0
	func mana_potions() -> int: return 0

class ScriptedRoll:
	var rolls: Array
	var bad := 0
	func _init(r: Array):
		rolls = r.duplicate()
	func roll(count: int, sides: int, bonus: int) -> int:
		if rolls.is_empty():
			bad += 1
			return 1
		var r: Array = rolls.pop_front()
		if int(r[0]) != count or int(r[1]) != sides or int(r[2]) != bonus: bad += 1
		return int(r[3])

class SpawnNavigator extends FakeNavigator:
	func free_cell_near(cell: Vector2i) -> Vector2i:
		return cell

const AiSpells = preload("res://simulation/ai_spells.gd")

func q3_checks():
	var fx: Dictionary = Encounters.load_json("res://tests/quest_ai_fixtures.json")
	check(fx.get("site", []).size() == 74 and fx.get("reward", []).size() == 400, "Q-3 fixtures: 74 site cases, 400 rewards")
	# "site": the real 0x503c60 with Quests on and one building near the hero (0x5002e0's filter 6).
	var site_bad := 0
	for row in fx.get("site", []):
		var spec: Dictionary = row.spec
		fresh()
		enc.givers.clear()
		enc.quests_enabled = int(spec.get("quests", 1)) != 0
		if spec.has("site"):
			var s: Dictionary = spec.site
			enc.catalogue = {"building_cfg": {"buildings": [{"code": String(s.code), "searchable": bool(spec.get("searchable", true))}]}}
			if not bool(s.get("deleted", false)):                       # a deleted building (+0x30) is gone from the port's list
				var id := add_building(int(s.owner), String(s.code))
				var b = production.buildings[id]
				b.hit_points = int(s.get("hp", 500))
				b.left = int(s.cell[0])
				b.top = int(s.cell[1])
				if bool(s.get("resting", false)) or bool(s.get("record", false)):
					var g: Dictionary = enc._giver(String(s.code))
					g.resting = bool(s.get("resting", false))
					g.until_ms = int(s.get("until", 0))
					if bool(s.get("record", false)): g.record = {}
					enc.givers[id] = g
		var env := SiteEnv.new(enc, spec)
		var t := AiSpells.empty_table(int(spec.now))
		var result := AiSpells.decide(t, env)
		var want_result := int(row.out.result) != 0
		var want_visits := int(row.out.visits)
		if result != want_result or env.visits.size() != want_visits:
			site_bad += 1
			push_error("Q-3 site '%s': port %s / %d visits, original %s / %d" % [spec.label, result, env.visits.size(), want_result, want_visits])
	check(site_bad == 0, "Q-3: the computer hero's site search matches the original in every case")
	# "reward": 0x504490's record from the same rolls.
	var reward_bad := 0
	var fields := ["type", "count", "unit", "unit_xp", "group_count", "group_unit", "group_xp", "research"]
	var flags := ["reward_resources", "reward_unit", "reward_group", "reward_research", "reward_item"]
	for row in fx.get("reward", []):
		var o: Dictionary = row.out
		var roller := ScriptedRoll.new(o.rolls)
		var r := Encounters.computer_record(roller.roll)
		var ok := roller.bad == 0 and roller.rolls.is_empty() and int(o.progress) == 1 and int(o.rewards) == 1
		for k in fields: ok = ok and str(r[k]) == str(o[k]).replace(".0", "")
		for k in flags: ok = ok and bool(r[k]) == (int(o[k]) != 0)
		ok = ok and int(o.group_named) == 0 and int(r.group_named) == 0
		if not ok:
			reward_bad += 1
			if reward_bad <= 3: push_error("Q-3 reward %s: port %s, original %s" % [row.spec.label, r, o])
	check(reward_bad == 0, "Q-3: 0x504490's record matches the original for all 400 roll sequences")

	# The visit applied (0x504490 -> 0x43d560): research, XP, the 240 s rest, rivals at the same building lose their quest.
	fresh()
	var lost := []
	enc.quest_lost.connect(func(p, _r): lost.append(p))
	var shrine := add_building(0, "BMSH")
	check(enc.computer_site(Vector2i(0, 0), 0) == shrine, "Q-3: a player's Shrine within 2 cells answers")
	production.buildings[shrine].owner = 6
	check(enc.computer_site(Vector2i(0, 0), 0) == -1, "Q-3: the neutral Shrine never answers (0x5002e0 skips player 6)")
	production.buildings[shrine].owner = 0
	enc.givers[shrine] = enc._giver("BMSH")
	take(first("BMSH", 5), 2, shrine)
	var hero := FakeHero.new()
	combat.now_ms = 5000
	var roller := ScriptedRoll.new([[1, 100, 0, 5], [1, 10, 0, 8], [1, 15, 0, 3]])
	var reward: Dictionary = enc.computer_visit(1, shrine, roller.roll, hero, Vector2i(3, 3))
	check(String(reward.get("research", "")) == "PMIT" and production.research_level(1, "PMIT") == 1, "Q-3: a research reward (1d100 < 10, 1d10 = 8: PMIT) completes")
	check(hero.xp == 20 and not enc.quests.has(1), "Q-3: the hero gains 20 XP; no quest stays active")
	check(lost == [2] and not enc.quests.has(2), "Q-3: another player's quest from the same building is cleared")
	check(enc.givers[shrine].resting and int(enc.givers[shrine].until_ms) == 245000, "Q-3: the site rests 240 s (0x52f7c0, no record held)")
	check(enc.computer_site(Vector2i(0, 0), 244999) == -1 and enc.computer_site(Vector2i(0, 0), 245000) == shrine, "Q-3: a resting site is skipped but at the exact end time (+0x128 != now)")
	check(enc.computer_site(Vector2i(0, 0), 246000) == -1, "Q-3: past the end, still resting until the building update runs")
	enc.update(246000)
	check(enc.computer_site(Vector2i(0, 0), 246000) == shrine, "Q-3: the building update (0x52cf41) ends the rest")
	# A unit and a group: 1d100 >= 90; the 14th entry, AAAR and AHGW, the group halved.
	fresh()
	combat.navigator = SpawnNavigator.new()
	var spawned := []
	enc.spawn_unit = func(t, _c, o, xp): spawned.append([t, o, xp]); return 1
	var site := add_building(3, "BZMA")
	roller = ScriptedRoll.new([[1, 100, 0, 95], [1, 10, 0, 2], [1, 15, 0, 14], [4, 20, 0, 50], [2, 4, 2, 9], [4, 8, 0, 20]])
	enc.computer_visit(1, site, roller.roll, FakeHero.new(), Vector2i(3, 3))
	check(roller.bad == 0 and roller.rolls.is_empty(), "Q-3: unit and group roll in the original's order")
	# 0x43d560 sends the group's messages before the single unit's (playtest 2026-11-11, Read).
	check(spawned == [["AHGW", 1, 20], ["AHGW", 1, 20], ["AHGW", 1, 20], ["AHGW", 1, 20], ["AAAR", 1, 50]], "Q-3: 9 / 2 = 4 AHGW (4d8 XP), then AAAR (4d20 XP) join player 1: %s" % [spawned])