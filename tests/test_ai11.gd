extends SceneTree
## Milestone AI-11 (AI_RESEARCH.md section 27), Read port of 0x4f6340 / 0x4f66f0 for a conversion group (type 7):
## list 7 holds every building of type B?T? / B?R? (mines) / BMFL of any player not allied with the computer, neutral
## included, wherever it stands (no fog test); score priority + 700, +100 at danger 0 else -200, -400 per other group
## (of the first ten slots) already aiming at it, - Chebyshev from the group centre, + 500 for the own target in a mode
## other than 0, else + 2d100. Other objects of the target player (towers, units, the Keep) are not candidates.

const AiPlayer = preload("res://simulation/ai_player.gd")
const AiManager = preload("res://simulation/ai_manager.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")
const Groups = preload("res://simulation/ai_groups.gd")

class FakeProduction extends RefCounted:
	var rules = ProductionRules.new()
	var buildings := {}

class FakeRng extends RefCounted:
	var calls := 0
	func roll(count: int, sides: int, bonus: int = 0) -> int:
		calls += 1
		return bonus + count                                  # 2d100 -> 2: the scores below decide

class FakeCombat extends RefCounted:
	var rng = FakeRng.new()
	var fighters := {}

class FakeCollision extends RefCounted:
	var width := 128
	var height := 128

class FakeSkirmish extends RefCounted:
	var slots: Array = []
	func _init():
		for p in 6: slots.append({"active": p < 3, "start": [Vector2i(12, 64), Vector2i(110, 60), Vector2i(64, 110)][p] if p < 3 else Vector2i(-1, -1)})
	func is_allied(a: int, b: int) -> bool: return a == b

class FakeMines extends RefCounted:
	var mines := {}
	var rows: Array = []
	func census(_owner: int) -> Array: return rows

class FakeWorld extends Object:
	var production = FakeProduction.new()
	var combat = FakeCombat.new()
	var collision = FakeCollision.new()
	var skirmish = FakeSkirmish.new()
	var mines = FakeMines.new()
	var ai_manager = AiManager.new()
	var improved_armies := false
	func game_ms() -> int: return 1000

class FakeDanger extends RefCounted:
	var values := {}
	func danger_to_building(_me: int, kind: String, id: int, _cell: Vector2i, _code: String) -> int: return int(values.get("%s:%d" % [kind, id], 0))

class TestAi extends AiPlayer:
	func _init(world_node): super(1, 6, world_node, 0)

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("AI-11 check failed: ", label)

func _initialize():
	conversion_list()
	if failures > 0:
		printerr("AI-11 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI-11 checks passed: %d checks" % checks)
	quit(0)

func building(world, id: int, code: String, owner: int, cell: Vector2i):
	world.production.buildings[id] = {"entity_id": id, "original_type_id": code, "owner": owner, "left": cell.x, "top": cell.y, "hit_points": 100}

func mine(world, id: int, code: String, owner: int, cell: Vector2i, owned := false, exhausted := false):
	world.mines.mines[id] = {"code": code, "entity": {"owner": owner}}
	world.mines.rows.append({"id": id, "cell": cell, "owned": owned, "exhausted": exhausted, "workers": 0})

func conversion_list():
	var world := FakeWorld.new()
	var ai := TestAi.new(world)
	ai.home = Vector2i(110, 60)
	var danger := FakeDanger.new()
	ai._danger = danger
	# P0 (the target player) has a tower beside the group and a Keep; a neutral mine far away; P2 a mine.
	building(world, 1, "BWTU", 0, Vector2i(100, 60))
	building(world, 2, "BKU0", 0, Vector2i(14, 64))
	mine(world, 10, "BRG2", 6, Vector2i(80, 60))
	mine(world, 11, "BRM2", 2, Vector2i(64, 100))
	mine(world, 12, "BRG2", 1, Vector2i(105, 60), true)          # own: never
	mine(world, 13, "BRG2", 6, Vector2i(104, 62), false, true)   # exhausted: left out (port assumption)
	var g := Groups.new_record(0)
	g.kind = Groups.CONVERSION
	g.leader = 7
	g.centre = Vector2i(108, 60)
	g.target_player = 0
	ai.groups = [g]
	var best: Dictionary = ai._conversion_target(g)
	check(not best.is_empty() and String(best.kind) == "mine", "a conversion group picks a mine, not the target player's tower or Keep (got %s)" % [best])
	check(int(best.get("id", -1)) == 10, "the nearer neutral mine wins (got %s)" % [best.get("id")])
	# Danger at the neutral mine: -200 against +100; the P2 mine wins.
	danger.values = {"mine:10": 5}
	best = ai._conversion_target(g)
	check(int(best.get("id", -1)) == 11, "a mine with danger loses 300 (got %s)" % [best.get("id")])
	# Another group already aims at mine 11: -400; back to mine 10.
	var other := Groups.new_record(1)
	other.target = {"kind": "mine", "id": 11, "code": "BRM2"}
	ai.groups = [g, other]
	best = ai._conversion_target(g)
	check(int(best.get("id", -1)) == 10, "a mine another group aims at loses 400 (got %s)" % [best.get("id")])
	# Its own target in Attack mode keeps +500.
	g.target = {"kind": "mine", "id": 11, "code": "BRM2"}
	g.mode = 2
	best = ai._conversion_target(g)
	check(int(best.get("id", -1)) == 11, "the group's own target in mode 2 keeps it (+500, no -400) (got %s)" % [best.get("id")])
	# No hostile convertible object at all: nothing (mode 0, the group gathers at its leader).
	world.mines.rows.clear()
	best = ai._conversion_target(g)
	check(best.is_empty(), "no list-7 entry: no target (towers and Keeps are not in list 7)")
	ai.dispose()
	world.ai_manager = null
	world.free()
