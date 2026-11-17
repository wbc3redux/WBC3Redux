extends SceneTree
## Review of milestone 9 (REVIEW_ENCOUNTERS.md): the port's quest eligibility (Encounters.eligible) against the original
## 0x43dde0 executed under Unicorn (tests/quest_fixtures.json, tools/emulate_quests.py). Since 9-fix every case must
## match (the review's type 1/5/6/9 divergences are fixed); any mismatch fails.
const Encounters = preload("res://simulation/encounters.gd")
var checks := 0
var failures := 0

class FakeBuilding:
	var owner := 0
	var original_type_id := ""
	var entity_id := 0

class FakeCombat:
	signal building_hit(id: int, attacker_kind: String, attacker_id: int)
	signal died(kind: String, id: int, killer_owner: int)
	var fighters := {}
	var heroes := {}
	var ani := {}
	func alive(f) -> bool:
		return f != null and int(f.hp) > 0
	func allied(a: int, b: int) -> bool:
		return false            # the emulation keeps the image's relation table 0x748915: all zero

class FakeProduction:
	signal building_destroyed(id: int)
	var buildings := {}

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/quest_fixtures.json"))
	var data: Dictionary = Encounters.load_json("res://assets/encounters.json")
	var records: Array = data.quests.BZMA.records
	check(records.size() == int(fixtures.records), "same record count as Bzma.dat")
	var combat := FakeCombat.new()
	var production := FakeProduction.new()
	var catalogue: Dictionary = Encounters.load_json("res://assets/catalogue.json")
	var enc = Encounters.new(combat, production, null, null, catalogue, {"ani": {}, "quests": data.quests}, {"lairs": [], "xp_levels": []})
	var tally := {}
	for w in fixtures.worlds:
		combat.fighters.clear()
		combat.heroes.clear()
		production.buildings.clear()
		var next_id := 0
		for o in w.objects:
			if o[1] == "building":
				var b := FakeBuilding.new()
				b.owner = int(o[0])
				b.original_type_id = o[2]
				b.entity_id = 1000 + next_id
				production.buildings[b.entity_id] = b
			else:
				combat.fighters[next_id] = {"id": next_id, "owner": int(o[0]), "type_id": o[2], "hp": int(o[3])}
				if o[1] == "hero": combat.heroes[int(o[0])] = {"unit": next_id}
			next_id += 1
		enc.player_active = w.active.map(func(v): return int(v) != 0)
		enc.player_byte_748668 = w.flags.map(func(v): return int(v))
		enc.player_race = w.races.map(func(v): return int(v))
		for player in range(7):
			for i in records.size():
				var r: Dictionary = records[i]
				var want: bool = int(w.eligible[player][i]) != 0
				var got: bool = enc.eligible(player, r)
				var t := int(r.type)
				if not tally.has(t): tally[t] = [0, 0]
				tally[t][0] += 1
				if got != want: tally[t][1] += 1
				check(got == want, "eligibility type %d record %d player %d: port %s, original %s" % [t, i, player, got, want])
	var keys := tally.keys()
	keys.sort()
	for t in keys:
		print("type %d: %d cases, %d divergent" % [t, tally[t][0], tally[t][1]])
	enc = null
	if failures == 0: print("Encounter review checks passed: ", checks)
	else: printerr("Encounter review failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)
