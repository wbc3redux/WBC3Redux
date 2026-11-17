extends SceneTree
## The end-of-battle retinue scan 0x43f3e0 (simulation/retinue_scan.gd), pure: the candidate test, the eight-place
## replacement, the general for hire, names, survivors, the graveyard.
##   Godot --headless --path . --script res://tests/test_retinue_scan.gd

const Scan = preload("res://simulation/retinue_scan.gd")

var checks := 0
var failures := 0

class Dice:
	var faces: Array = []
	func roll(count: int, sides: int, bonus: int = 0) -> int:
		return int(faces.pop_front()) if not faces.is_empty() else 1

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("Retinue scan check failed: " + label)

func unit(id: int, type: String, rank: int, combat: int, extra: Dictionary = {}) -> Dictionary:
	var u := {"id": id, "type": type, "alive": true, "hero": false, "retinue_id": "", "may_join": true, "rank": rank,
		"xp": [0, 5, 10, 20, 40, 70][mini(rank, 5)], "combat": combat, "flags": 0, "general": false, "name": "Named %d" % id}
	u.merge(extra, true)
	return u

func context(extra: Dictionary = {}) -> Dictionary:
	var dice := Dice.new()
	dice.faces = [3]
	var c := {"race": 0, "campaign": false, "dead": [], "text": "Desert Sands", "rng": dice,
		"type_stats": func(code): return {"combat": 12 if String(code).ends_with("GX") or String(code).ends_with("GW") else 9, "flags": 0},
		"display_name": func(code): return "The " + String(code)}
	c.merge(extra, true)
	return c

func codes(list: Array) -> Array:
	return list.map(func(c): return String(c.original_type_id))

func run():
	# The test (0x43f3e0): rank above 1, Combat above 7, not AAEY, STATUS bit 14 clear.
	check(not Scan.qualifies(unit(1, "AHKX", 1, 10)) and Scan.qualifies(unit(1, "AHKX", 2, 8)), "rank 2 qualifies, rank 1 does not")
	check(not Scan.qualifies(unit(1, "AHKX", 3, 7)) and not Scan.qualifies(unit(1, "AAEY", 3, 12)) and not Scan.qualifies(unit(1, "AHKX", 3, 12, {"flags": 0x4000})),
		"Combat 7, AAEY and STATUS 0x4000 do not")
	# Heroes, members, units that may not join and dead units are skipped; a general blocks the offer.
	var r := Scan.scan([unit(1, "AHHX", 5, 20, {"hero": true}), unit(2, "AHKX", 3, 10, {"may_join": false}), unit(3, "AHKX", 3, 10, {"alive": false}),
		unit(4, "AHKX", 3, 10, {"general": true})], [], [], context())
	check(codes(r.candidates) == ["AHKX"] and String(r.candidates[0].name) == "Named 4", "only the living, joinable non-hero; it keeps its name")
	# No general: the hire table at race x 10 + roll (Knights, roll 3 -> AHGW), rank 0, 1 experience.
	r = Scan.scan([unit(4, "AHKX", 3, 10)], [], [], context())
	check(codes(r.candidates) == ["AHKX", "AHGW"] and int(r.candidates[1].xp) == 1 and int(r.candidates[1].medal_level) == 0, "a general for hire from 0x609330 (race 0, roll 3)")
	check(String(r.candidates[1].name) != "", "the general gets a name (0x434e90)")
	r = Scan.scan([], [], [], context({"race": 15, "rng": (func():
		var d := Dice.new()
		d.faces = [10]
		return d).call()}))
	check(r.candidates.is_empty(), "the Plaguelords' roll of 10 would read past the table: no offer")
	r = Scan.scan([], [], [], context({"campaign": true}))
	check(r.candidates.is_empty(), "no offer in the campaign")
	# Eight places: a type held twice loses its weakest to the newcomer.
	var list: Array = []
	for i in 8: list.append(unit(10 + i, ["AHKX", "AHMX", "AHFX", "AHDX", "AHEX", "AHLX", "AHGX", "AHKX"][i], 2 + (i % 3), 9 + i, {"general": i == 6}))
	list.append(unit(30, "AHCX", 2, 8))
	r = Scan.scan(list, [], [], context())
	check(r.candidates.size() == 8 and codes(r.candidates).count("AHKX") == 1 and codes(r.candidates).has("AHCX"), "the newcomer replaces the weaker of the two AHKX")
	check(int(r.candidates[0].permanent_state.combat) == 9 or codes(r.candidates)[0] == "AHCX", "the weaker AHKX (rank 2, Combat 9) was the one replaced")
	# All different: the weakest goes only when rank x 3 + Combat beats its rank x 5 + Combat.
	list = []
	for i in 8: list.append(unit(10 + i, ["AHKX", "AHMX", "AHFX", "AHDX", "AHEX", "AHLX", "AHGX", "AHBX"][i], 2, 20, {"general": i == 6}))
	list.append(unit(30, "AHCX", 2, 25))      # 6 + 25 = 31 > 10 + 20
	list.append(unit(31, "AHIX", 2, 15))      # 6 + 15 = 21 < 30 (the weakest is now AHCX's 35 or another 30)
	r = Scan.scan(list, [], [], context())
	check(codes(r.candidates).has("AHCX") and not codes(r.candidates).has("AHIX") and not codes(r.candidates).has("AHKX"), "a stronger newcomer replaces the weakest; a weaker one does not")
	# Survivors, battles, the dead to the graveyard.
	var retinue := [{"id": "r1", "original_type_id": "AHKX", "xp": 10, "medal_level": 2, "battles": 3, "permanent_state": {}},
		{"id": "r2", "original_type_id": "AHMX", "xp": 70, "medal_level": 5, "battles": 1, "name": "Archer Ann", "permanent_state": {"combat": 14}},
		{"id": "r3", "original_type_id": "AHFX", "xp": 0, "medal_level": 0, "battles": 0, "permanent_state": {}}]
	r = Scan.scan([unit(5, "AHKX", 4, 13, {"retinue_id": "r1"}), unit(6, "AHMX", 5, 14, {"retinue_id": "r2", "alive": false})], retinue, [],
		context({"dead": ["r2"]}))
	check(r.retinue.size() == 2 and String(r.retinue[0].id) == "r1" and int(r.retinue[0].medal_level) == 4 and int(r.retinue[0].xp) == 40
		and int(r.retinue[0].battles) == 4 and int(r.retinue[1].battles) == 1, "a survivor writes its rank back; every living member counts a battle")
	check(r.graveyard.size() == 1 and String(r.graveyard[0].name) == "Archer Ann" and int(r.graveyard[0].battles) == 2 and int(r.graveyard[0].age) == 1
		and String(r.graveyard[0].text) == "Desert Sands", "the dead member's grave: battles + 1, the battle text, age 1")
	check(not codes(r.candidates).has("AHKX"), "a member is no candidate")
	# A full graveyard: the oldest grave goes; the strongest grave comes first.
	var graves: Array = []
	for g in 10: graves.append({"original_type_id": "AHKX", "xp": g, "medal_level": 0, "battles": 1, "text": "", "age": 20 - g, "permanent_state": {"combat": 8}})
	r = Scan.scan([], [{"id": "r9", "original_type_id": "AHLX", "xp": 500, "medal_level": 9, "battles": 7, "permanent_state": {"combat": 30}}], graves,
		context({"dead": ["r9"]}))
	check(r.graveyard.size() == 10 and String(r.graveyard[0].original_type_id) == "AHLX" and not r.graveyard.any(func(g): return int(g.xp) == 0 and String(g.original_type_id) == "AHKX"),
		"the oldest grave is replaced and the strongest moves to the front")
	if failures > 0:
		print("Retinue scan checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Retinue scan checks passed: %d" % checks)
	quit(0)
