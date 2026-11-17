extends SceneTree
## Milestone AI-6 (AI_RESEARCH.md "AI-6"): the expansion choice 0x4feba0 of tools/emulate_ai6.py (tests/ai6_fixtures.json)
## against AiPlayer._want_expansion (simulation/ai_player.gd): the taken first 0x10 node, the keep / removal rule, the entry
## walk with the menu flag and 0x4fcdd0, the score and its ties, the insert or merge at 90 and the digit bonus 90.
## Every case must match.

const AiPlayer = preload("res://simulation/ai_player.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")

class FakeProduction extends RefCounted:
	var rules = ProductionRules.new()
	func price_of(_owner: int, _item: String, _builder: String = "") -> Array: return [0, 0, 0, 0]

class FakeEconomy extends RefCounted:
	func resources(_owner: int) -> Array: return [500, 500, 500, 500]

class FakeWorld extends RefCounted:
	var production = FakeProduction.new()
	var economy = FakeEconomy.new()
	func game_ms() -> int: return 100000

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 20: printerr("AI-6 check failed: ", label)

func _initialize():
	var f = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai6_fixtures.json"))
	if not (f is Dictionary) or not f.has("expansion"):
		printerr("AI-6 fixtures missing or unreadable")
		quit(1)
		return
	var world := FakeWorld.new()
	var ai = AiPlayer.new(1, 6, world, 6)
	var cases := 0
	for c in f.expansion:
		cases += 1
		ai.building_order = c.entries.map(func(e): return String(e.id))
		ai._flags_cache = c.entries.map(func(e): return int(e.flag) != 0)
		ai.buildings = {}
		for e in c.entries:
			ai.buildings[String(e.id)] = {"count": int(e.count), "pending": int(e.pending), "desired": int(e.desired),
				"available": int(e.available) != 0, "timer": 0, "cooldown": -1}
		ai.want = []
		for n in c.want:
			ai.want.append({"id": String(n.id), "priority": int(n.priority), "cost": [0, 0, 0, 0], "categories": int(n.categories),
				"bonus": int(n.bonus), "done": false, "taken": int(n.taken) != 0})
		ai._want_expansion()
		var got: Array = ai.want.filter(func(w): return not w.done).map(func(w): return [String(w.id), int(w.priority), int(w.categories), int(w.bonus), int(bool(w.get("taken", false)))])
		var want: Array = c.want_after.map(func(n): return [String(n.id), int(n.priority), int(n.categories), int(n.bonus), int(n.taken)])
		check(got == want, "case %d: %s vs %s" % [cases, got, want])
	ai.dispose()
	if failures > 0:
		printerr("AI-6 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI-6 checks passed: %d checks over %d fixture cases" % [checks, cases])
	quit(0)
