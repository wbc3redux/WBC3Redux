extends SceneTree
## Milestone AI-8 (AI_RESEARCH.md section 24): a task that 0x4fd940 chooses takes the unit out of its group (0x4f84a0 ->
## 0x4fbad0 -> 0x4f66d0 -> 0x4f3ae0 -> 0x4f36b0, Read): the slot is freed, the head order stopped, the other members stay;
## a unit in no group is left alone; the opt-in Improved armies rules keep their records unchanged.

const AiPlayer = preload("res://simulation/ai_player.gd")
const Groups = preload("res://simulation/ai_groups.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")

class FakeProduction extends RefCounted:
	var rules = ProductionRules.new()

class FakeCombat extends RefCounted:
	var stopped: Array = []
	func order_stop(id: int): stopped.append(id)

class FakeWorld extends RefCounted:
	var production = FakeProduction.new()
	var combat = FakeCombat.new()
	var improved_armies := false
	func game_ms() -> int: return 100000

class FakeUnit extends RefCounted:
	var unit_id := 0
	var stops := 0
	func _init(id: int): unit_id = id
	func stop(): stops += 1

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("AI-8 check failed: ", label)

func _group(slot: int, ids: Array) -> Dictionary:
	var g := Groups.new_record(slot)
	for i in ids.size(): g.slots[i] = int(ids[i])
	g.launched = true
	Groups.sync(g)
	return g

func _initialize():
	var world := FakeWorld.new()
	var ai = AiPlayer.new(1, 6, world, 6)
	ai.groups = [_group(0, [11, 12, 13]), _group(1, [21])]
	var builder := FakeUnit.new(12)
	ai._leave_for_task(builder)
	check(not (12 in ai.groups[0].slots), "the builder's slot is freed")
	check(11 in ai.groups[0].slots and 13 in ai.groups[0].slots, "the other members stay")
	check(Groups.count(ai.groups[0]) == 2 and bool(ai.groups[0].launched), "the group keeps its launch with members left")
	check(builder.stops == 1 and world.combat.stopped == [12], "the head order is stopped (0x520c90 + 0x406600)")
	check(not ai._member(12), "the builder is a free object again")
	var lone := FakeUnit.new(21)
	ai._leave_for_task(lone)
	check(Groups.count(ai.groups[1]) == 0 and not bool(ai.groups[1].launched), "the last member out clears the launch (0x4f36b0)")
	var free := FakeUnit.new(99)
	ai._leave_for_task(free)
	check(free.stops == 0, "a unit in no group is not stopped")
	# Improved armies: the 10b records stay as they are.
	world.improved_armies = true
	ai.groups = [{"kind": 9, "members": [31, 32], "launched": true, "target_player": 0, "target": {}, "hero": false}]
	var improved := FakeUnit.new(31)
	ai._leave_for_task(improved)
	check(ai.groups[0].members == [31, 32] and improved.stops == 0, "the Improved armies rules keep the member")
	ai.dispose()
	if failures > 0:
		printerr("AI-8 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI-8 checks passed: %d checks" % checks)
	quit(0)
