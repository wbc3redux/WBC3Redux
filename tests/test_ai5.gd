extends SceneTree
## Milestone AI-5 (AI_RESEARCH.md "AI-5"): the emulated fixtures of tools/emulate_ai5.py (tests/ai5_fixtures.json) against
## the port: the want list's timer and cooldown writes 0x4fafd0 (listing and removal), 0x4faea0 (removal) and 0x4f8750 (a
## started job) by id letter, each followed by the cooldown gate 0x4f8600 (simulation/ai_player.gd), and the stock debit
## 0x43eb80 of a placed building (simulation/economy.gd debit_clamped, used by production.place_building for a computer).
## Every case must match.

const AiPlayer = preload("res://simulation/ai_player.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")
const Economy = preload("res://simulation/economy.gd")

class FakeWorld:
	var production := {"rules": null}
	var ms := 0
	func game_ms() -> int: return ms

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 20: printerr("AI-5 check failed: ", label)

func ints(v):
	if v is Array: return v.map(func(x): return ints(x))
	return int(v)

## The fixture's lists as the computer player's dictionaries.
func load_lists(ai, c: Dictionary):
	ai.buildings = {}
	ai.units = {}
	ai.research = {}
	for e in c.buildings: ai.buildings[String(e[0])] = {"count": int(e[1]), "pending": int(e[2]), "timer": int(e[3]), "cooldown": int(e[4]), "desired": -1, "available": true}
	for e in c.units: ai.units[String(e[0])] = {"count": int(e[1]), "pending": int(e[2]), "timer": int(e[3]), "cooldown": int(e[4]), "priority": 50, "available": true, "trainable": true}
	for e in c.research: ai.research[String(e[0])] = {"timer": int(e[3]), "cooldown": int(e[4]), "priority": 50}
	ai.want = []
	for id in c.want: ai.want.append({"id": String(id), "priority": 50, "cost": [0, 0, 0, 0], "categories": 1, "bonus": 0, "done": false})

func lists_of(ai, c: Dictionary) -> Dictionary:
	return {"buildings": c.buildings.map(func(e): return [int(ai.buildings[String(e[0])].timer), int(ai.buildings[String(e[0])].cooldown)]),
		"units": c.units.map(func(e): return [int(ai.units[String(e[0])].timer), int(ai.units[String(e[0])].cooldown)]),
		"research": c.research.map(func(e): return [int(ai.research[String(e[0])].timer), int(ai.research[String(e[0])].cooldown)])}

func _initialize():
	var f = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai5_fixtures.json"))
	if not (f is Dictionary) or not f.has("lists"):
		printerr("AI-5 fixtures missing or unreadable")
		quit(1)
		return
	var world := FakeWorld.new()
	world.production.rules = ProductionRules.new()
	var ai = AiPlayer.new(1, 6, world, 7)
	var cases := 0
	for c in f.lists:
		cases += 1
		load_lists(ai, c)
		world.ms = int(c.now)
		var id := String(c.item)
		match String(c.op):
			"listed1": ai._listed(id)
			"listed0": ai._unlisted(id)
			"remove": ai.want_remove(id)
			"started": ai._started(id)
		var label := "%s %s case %d" % [c.op, id, cases]
		var got := lists_of(ai, c)
		check(ints(got.buildings) == ints(c.after.buildings) and ints(got.units) == ints(c.after.units) and ints(got.research) == ints(c.after.research), label + " lists %s vs %s" % [got, c.after])
		var remaining: Array = ai.want.filter(func(w): return not w.done).map(func(w): return String(w.id))
		check(remaining == Array(c.want_after).map(func(x): return String(x)), label + " want %s vs %s" % [remaining, c.want_after])
		check(int(ai.gate(id)) == int(c.gate_after), label + " gate")
		got = lists_of(ai, c)
		check(ints(got.buildings) == ints(c.lists_after_gate.buildings) and ints(got.units) == ints(c.lists_after_gate.units) and ints(got.research) == ints(c.lists_after_gate.research), label + " lists after the gate")
	ai.dispose()
	# ---- 0x43eb80: every lane clamped at zero; nothing while the game state is 1 or below (not a match)
	for c in f.debit:
		cases += 1
		var economy = Economy.new(6)
		economy.add_player(int(c.player), ints(c.stock))
		if int(c.state) > 1: economy.debit_clamped(int(c.player), ints(c.cost))
		check(ints(economy.resources(int(c.player))) == ints(c.after), "debit %s" % str(c))
	if failures > 0:
		printerr("AI-5 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI-5 checks passed: %d checks over %d fixture cases" % [checks, cases])
	quit(0)
