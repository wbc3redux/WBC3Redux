extends SceneTree
## The review's emulated fixtures (tests/ai_review_fixtures.json, tools/emulate_ai_review.py) against the port (10-fix):
## the mine census 0x4fc280/0x4fb680 (through AiPlayer.mine_census), desired counts 0x4fc9a0/0x4fcc10 and target priority
## 0x4f5e90 (ai_rules.gd). Every case must match; any divergence fails the run.

const AiPlayer = preload("res://simulation/ai_player.gd")
const R = preload("res://simulation/ai_rules.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")

class FakeMines:
	var rows: Array = []
	func census(_owner: int) -> Array:
		return rows

class FakeWorld:
	var production := {"rules": null}
	var mines := FakeMines.new()

var cases := 0
var failures := 0

func check(value: bool, label: String):
	if not value:
		failures += 1
		if failures < 20: printerr("AI review check failed: ", label)

func _initialize():
	var f = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai_review_fixtures.json"))
	if not (f is Dictionary) or not f.has("census") or not f.has("desired") or not f.has("target_priority"):
		printerr("AI review fixtures missing or unreadable")
		quit(1)
		return
	var world := FakeWorld.new()
	var rules := ProductionRules.new()
	world.production.rules = rules
	var ai = AiPlayer.new(1, 3, world)
	# ---- 0x4fc280 mine census, on the rows the original's 0x4fb680 refresh left in the list
	for c in f.census:
		cases += 1
		ai.me = int(c.me)
		var rows: Array = []
		var head: int = int(c.head_index)
		if head >= 0:
			for i in range(head, c.nodes.size()):
				var after: Dictionary = c.nodes_after[i]
				if after.freed: continue
				rows.append({"owned": int(after.owned) != 0, "exhausted": int(after.exhausted) != 0, "level": int(c.nodes[i].level),
					"lane": int(c.nodes[i].lane), "workers": int(after.workers)})
		world.mines.rows = rows
		ai.research_level = int(c.research)
		ai.mine_census()
		for lane in 4:
			var want: Array = c.lanes[lane]
			var got := [int(ai.mine_weights[lane][0]), int(ai.mine_weights[lane][1]), int(ai.mine_slots[lane])]
			check(got == [int(want[0]), int(want[1]), int(want[2])], "census lane %d want %s got %s" % [lane, want, got])
	# ---- 0x4fc9a0 + 0x4fcc10 desired counts, every case
	for c in f.desired:
		cases += 1
		var buildings: Array = c.buildings.map(func(b): return [String(b[0]), int(b[1]), int(b[2])])
		var units: Array = c.units.map(func(u): return [String(u[0]), int(u[1]), int(u[2])])
		var got: Array = R.desired_counts(int(c.difficulty), buildings, units, int(c.special), rules.data.production)
		check(got == c.desired.map(func(v): return int(v)), "desired %s want %s got %s" % [buildings.map(func(b): return b[0]), c.desired, got])
	# ---- the port's own Knights lists through AiPlayer.desired_counts (Squire not yet available, Keep standing)
	for c in f.desired:
		var names: Array = c.buildings.map(func(b): return String(b[0]))
		if names != ["BKK0", "BKK1", "BAGA", "BPFL"] or c.units.size() < 4: continue
		ai.difficulty = int(c.difficulty)
		ai.unit_order = c.units.map(func(u): return String(u[0]))
		# AI-6: AiPlayer.desired_counts reads the menu flag +0x80 (these cases set every entry's) and the unit's +0xb (trainable).
		ai._flags_cache = ai.building_order.map(func(_id): return true)
		for u in c.units:
			if ai.units.has(String(u[0])):
				ai.units[String(u[0])].priority = int(u[1])
				ai.units[String(u[0])].available = int(u[2]) != 0
				ai.units[String(u[0])].trainable = int(u[2]) != 0
		ai.desired_counts()
		for i in names.size():
			check(int(ai.buildings[names[i]].desired) == int(c.desired[i]), "AiPlayer desired difficulty %d %s" % [int(c.difficulty), names[i]])
	# ---- 0x4f5e90 target priority, every case
	for c in f.target_priority:
		cases += 1
		check(R.target_priority(c) == int(c.priority), "target priority %s %s" % [c.code, c.priority])
	ai.dispose()
	if failures > 0:
		printerr("AI review checks failed: %d" % failures)
		quit(1)
		return
	print("AI review checks passed: %d fixture cases; divergences from the executable: 0" % cases)
	quit(0)
