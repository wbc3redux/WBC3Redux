extends SceneTree
## Milestone AI-9 (AI_RESEARCH.md section 25), Read ports:
## * The walk-step builders (0x5377a0 at 0x538573, 0x51c7d0 at 0x51c805) move the guard point only while the head order's
##   +0x1d ("inserted": the attitude scripts' orders) is 0: a script chase leaves the post, a player order moves it.
## * The home move 0x4fbdf0 / 0x4fc020: home moves only past 300 hostile strength (profile +0x20c0 set), at most one
##   draw round per 5 s over all players, x then y drawn as 1d(W - 20) + 10, the first candidate farther than
##   min((W - 10) >> 2, 30) from the main enemy's start with strength below 50.

const AiPlayer = preload("res://simulation/ai_player.gd")
const AiManager = preload("res://simulation/ai_manager.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")

class FakeProduction extends RefCounted:
	var rules = ProductionRules.new()

class FakeRng extends RefCounted:
	var queue: Array = []
	var calls: Array = []
	func roll(count: int, sides: int, bonus: int = 0) -> int:
		calls.append([count, sides, bonus])
		return bonus + (int(queue.pop_front()) if not queue.is_empty() else 1)

class FakeCombat extends RefCounted:
	var rng = FakeRng.new()
	var fighters := {}

class FakeCollision extends RefCounted:
	var width := 128
	var height := 128

class FakeSkirmish extends RefCounted:
	var slots: Array = [{"start": Vector2i(12, 64)}, {"start": Vector2i(110, 60)}]

class FakeWorld extends Object:
	var production = FakeProduction.new()
	var combat = FakeCombat.new()
	var collision = FakeCollision.new()
	var skirmish = FakeSkirmish.new()
	var ai_manager = AiManager.new()
	var clock := 100000
	var improved_armies := false
	func game_ms() -> int: return clock

## The strength sums are 0x4fbe80's (simulation/ai_danger.gd, checked by the AI-4 danger fixtures' window rules); here a
## table stands in for them.
class TestAi extends AiPlayer:
	var strength := {}
	var asked: Array = []
	func _init(world_node): super(0, 6, world_node, 0)
	func strength_near(cell: Vector2i) -> int:
		asked.append(cell)
		return int(strength.get(cell, 0))

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("AI-9 check failed: ", label)

func _initialize():
	guard_point()
	home_move()
	if failures > 0:
		printerr("AI-9 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI-9 checks passed: %d checks" % checks)
	quit(0)

func guard_point():
	var combat := FakeCombat.new()
	var ai := UnitAI.new(combat, {"scripts": []})
	var f := {"id": 5, "guard": Vector2i(12, 64), "cur": null}
	combat.fighters[5] = f
	ai.on_step(5, Vector2i(13, 64))
	check(f.guard == Vector2i(12, 64), "no head order: the post stays")
	f.cur = {"kind": "attack", "ai": true, "finished": false, "inserted": true}
	ai.on_step(5, Vector2i(14, 64))
	check(f.guard == Vector2i(12, 64), "a script chase (0x51a470: +0x1d = 1) leaves the post")
	f.cur = {"kind": "move", "ai": true, "finished": false, "goal": Vector2i(12, 64), "inserted": true}
	ai.on_step(5, Vector2i(13, 64))
	check(f.guard == Vector2i(12, 64), "Return to Post's walk (0x508ba0: +0x1d = 0x508e60) leaves the post")
	f.cur = {"kind": "move", "ai": false, "finished": false, "goal": Vector2i(30, 30)}
	ai.on_step(5, Vector2i(15, 63))
	check(f.guard == Vector2i(15, 63), "a player move (+0x1d = 0) moves the post with each step")
	f.cur = {"kind": "attack", "ai": true, "finished": false, "inserted": false}
	ai.on_step(5, Vector2i(16, 63))
	check(f.guard == Vector2i(16, 63), "a script order from a +0x75 rule (0x508e60 = 0) moves the post")
	f.cur.finished = true
	ai.on_step(5, Vector2i(17, 63))
	check(f.guard == Vector2i(16, 63), "a finished order: the post stays")

func home_move():
	var world := FakeWorld.new()
	var ai := TestAi.new(world)
	ai.home = Vector2i(12, 64)
	ai.main_enemy = 1
	# Below the threshold: no draw.
	ai.strength = {Vector2i(12, 64): 300}
	check(ai.home_centre() == Vector2i(12, 64) and world.combat.rng.calls.is_empty(), "300 strength: home stays, no draw")
	# Profile +0x20c0 clear: no move.
	ai.profile = {"home_moves": false}
	ai.strength = {Vector2i(12, 64): 900}
	check(ai.home_centre() == Vector2i(12, 64) and world.combat.rng.calls.is_empty(), "+0x20c0 = 0: home stays")
	ai.profile = {}
	# Draws: limit min((128 - 10) >> 2, 30) = 29 from (110, 60). (100, 60) is too near; (20, 20) is safe but strong;
	# (30, 100) is the first far and quiet one.
	world.combat.rng.queue = [90, 50, 10, 10, 20, 90]       # 1d108 + 10: x 100 y 60, x 20 y 20, x 30 y 100
	ai.strength = {Vector2i(12, 64): 301, Vector2i(20, 20): 50}
	var moved := ai.home_centre()
	check(moved == Vector2i(30, 100) and ai.home == moved, "home moves to the first far, quiet candidate (got %s)" % moved)
	check(world.combat.rng.calls.size() == 6 and world.combat.rng.calls[0] == [1, 108, 10], "x then y as 1d(W - 20) + 10")
	check(not ai.asked.has(Vector2i(100, 60)), "a candidate within 29 cells of the enemy start is not measured")
	check(world.ai_manager.home_move_ms == 100000, "the round stamps the shared clock")
	# Within 5 s of the last round (any player's): no draw.
	world.clock = 104999
	ai.strength = {Vector2i(30, 100): 400}
	world.combat.rng.calls.clear()
	check(ai.home_centre() == Vector2i(30, 100) and world.combat.rng.calls.is_empty(), "within 5 s: no new round")
	# 20 failed draws: home stays.
	world.clock = 105000
	world.combat.rng.queue = []
	for i in 40: world.combat.rng.queue.append(90)           # (100, 100): 40 cells from (110, 60), but strength 60
	ai.strength = {Vector2i(30, 100): 400, Vector2i(100, 100): 60}
	check(ai.home_centre() == Vector2i(30, 100) and world.combat.rng.calls.size() == 40, "20 strong candidates: home stays")
	ai.dispose()
	world.ai_manager = null
	world.free()
