extends SceneTree
## Review of milestones 11a / 11b (REVIEW_RACES_HEROES.md): the port against the review's emulated fixtures
## (tests/races_review_fixtures.json, tools/emulate_races_review.py):
## * ProductionRules.price against 0x40b6b0 in every state (hero alive / dead / none, price term, computer discount,
##   builders, research, hero skills 0x3f / 0x25, item stat, skill ranks, POMA..C);
## * AiPlayer.build_want_list (category 0x40 / 1 nodes) and _started against 0x4fe830 + 0x4fe9e0 + 0x4f8750 over 40
##   sequences of 40 passes on one persistent AI object;
## * ProductionRules.slot_allowed against 0x40c740 + 0x40c990; ProductionRules.research_level against 0x437f70.
## The caller-side gating the port does outside Rules.price (the discount and the skill ranks only while the hero lives,
## main.gd / ai_player.gd) is applied here as the original does it, so a divergence is a formula divergence.
## Divergences are grouped. The groups in KNOWN are the review's reported findings (the run passes and reports them);
## a divergence in any other group fails the run.

const AiPlayer = preload("res://simulation/ai_player.gd")
const Rules = preload("res://simulation/production_rules.gd")
const KNOWN := {
	# 0x585ca0 stores '-' as 0, which 0x40c990 treats like '0' (the no-dragons option applies); the port lets '-' pass.
	# No shipped row has an item in a '-' slot, so only the review's synthetic cases reach it (REVIEW D5).
	"gate: '-' slot with a dragon": true}
	# Milestone 13 applied REVIEW D8: 0x523e10 adds 4 for AUBX once PZOM is researched (0x70d58b); no longer a divergence.
const COMPUTER_DISCOUNT := [0, 0, 0, 2, 5, 10, 20, 0]   # 0x5fbc38 (tests/ai_fixtures.json tables, Emulated)

class StubProduction:
	var rules
	var buildings := {}
	func price_discount(_owner: int) -> int: return 0          # no hero in the want-list fixtures: 0x40b6b0 discount 0
	func missing_requirement(_owner: int, _id: String) -> String: return ""
	func menu_for(_b) -> Array: return []

class StubEconomy:
	var stock := [0, 0, 0, 0]
	func resources(_owner: int) -> Array: return stock

class StubWorld:
	var production
	var economy
	var now := 0
	func game_ms() -> int: return now

var cases := 0
var groups := {}
var failures := 0

func diverge(group: String, label: String):
	groups[group] = int(groups.get(group, 0)) + 1
	if not KNOWN.has(group):
		failures += 1
		if failures < 25: printerr("Races review divergence (", group, "): ", label)

func ints(a: Array) -> Array:
	return a.map(func(v): return int(v))

func _initialize():
	var f = JSON.parse_string(FileAccess.get_file_as_string("res://tests/races_review_fixtures.json"))
	if not (f is Dictionary) or not f.has("cost_states") or not f.has("want_sequences") or not f.has("slot_gates"):
		printerr("Races review fixtures missing or unreadable")
		quit(1)
		return
	var rules := Rules.new()
	_costs(rules, f.cost_states)
	_want(rules, f.want_sequences)
	_gates(rules, f.slot_gates)
	_levels(f.research_levels)
	_workers(rules, f.mine_workers)
	var parts: Array = []
	var keys: Array = groups.keys()
	keys.sort()
	for g in keys: parts.append("%s %d" % [g, int(groups[g])])
	var total := 0
	for g in groups: total += int(groups[g])
	if failures == 0 and cases > 8000:
		print("Races review checks passed: %d fixture cases; known divergences from the executable: %d%s" % [cases, total,
			(" (" + ", ".join(parts) + ")") if not parts.is_empty() else ""])
		quit(0)
	else:
		printerr("Races review checks failed: %d unexpected divergences over %d cases (%s)" % [failures, cases, ", ".join(parts)])
		quit(1)

# ------------------------------------------------------------------------------------------------ 0x40b6b0
func _costs(rules, list: Array):
	for c in list:
		cases += 1
		var alive: bool = String(c.hero) == "alive"
		var skills: Dictionary = c.skills
		var ranks := {}
		if alive:                                              # 0x556b50(p, skill, 1, 1) answers 0 without a living hero
			for k in c.ranks: ranks[int(k)] = int(c.ranks[k])
		var context := {"race": int(c.race), "research": c.research.map(func(r): return String(r)),
			"discount": (int(c.term) + (COMPUTER_DISCOUNT[int(c.difficulty)] if int(c.computer) != 0 else 0)) if alive else 0,
			"builder": String(c.builder), "hero_alive": alive,
			"skill_3f": int(skills["63"]) if skills.get("63") != null else 0,
			"research_discount": (int(skills["37"]) if skills.get("37") != null else 0) + int(c.item_stat),
			"skill_ranks": ranks}
		var got: Dictionary = rules.price(String(c.item), context)
		if bool(got.ok) == bool(c.ok) and ints(got.cost) == ints(c.cost) and int(got.seconds) == int(c.seconds): continue
		var group := "cost: other"
		if String(c.item) == "RARB": group = "cost: RARB skill factor"
		elif String(c.item)[0] == "B": group = "cost: building"
		elif String(c.item)[0] == "A": group = "cost: unit"
		elif String(c.item)[0] in ["P", "R"]: group = "cost: research"
		diverge(group, "race %d %s builder '%s' hero %s research %s: port %s %d s, original %s %d s" % [int(c.race), c.item,
			c.builder, c.hero, c.research, got.cost, int(got.seconds), c.cost, int(c.seconds)])

# ------------------------------------------------------------------------------------------------ 0x4fe830 + 0x4fe9e0
func _want(rules, sequences: Array):
	for seq in sequences:
		var world := StubWorld.new()
		world.production = StubProduction.new()
		world.production.rules = rules
		world.economy = StubEconomy.new()
		var roster: Array = seq.roster.map(func(v): return String(v))
		var ai = AiPlayer.new(int(seq.player), int(seq.difficulty), world, int(seq.race))
		ai.unit_order = roster.duplicate()
		ai.PEASANT = roster[0]
		ai.HERO = roster[-1]
		ai.buildings = {}
		ai.building_order = []
		ai.units = {}
		for i in roster.size():
			ai.units[roster[i]] = {"priority": int(seq.priorities[i]), "count": 0, "pending": 0, "timer": -1, "cooldown": -1,
				"available": false, "trainable": false}
		for k in seq.steps.size():
			var step: Dictionary = seq.steps[k]
			cases += 1
			world.now = int(step.now)
			world.economy.stock = ints(step.stock)
			for lane in 4:
				ai.mine_weights[lane] = [int(step.mines[lane][0]), int(step.mines[lane][1])]
				ai.mine_slots[lane] = int(step.mines[lane][2])
			for i in roster.size():
				var e: Dictionary = ai.units[roster[i]]
				e.available = int(step.available[i]) != 0
				e.trainable = e.available and roster[i] != ai.HERO
			ai.units[ai.PEASANT].count = int(step.peasants[0])
			ai.units[ai.PEASANT].pending = int(step.peasants[1])
			ai.build_want_list()
			var label := "%s pass %d" % [roster, k]
			_compare_nodes(ai, step.nodes, label)
			_compare_units(ai, roster, step.units, label)
			if String(step.started) != "":
				ai._started(String(step.started))
				_compare_units(ai, roster, step.units_after_start, label + " after starting " + String(step.started))

func _compare_nodes(ai, expected: Array, label: String):
	var mine: Array = ai.want.filter(func(w): return int(w.categories) & 0x41)
	var a: Array = mine.map(func(w): return [String(w.id), int(w.priority), int(w.bonus), int(w.categories), ints(w.cost)])
	var b: Array = expected.map(func(n): return [String(n.id), int(n.priority), int(n.bonus), int(n.categories), ints(n.cost)])
	if a != b: diverge("want: nodes", "%s: port %s, original %s" % [label, a, b])

func _compare_units(ai, roster: Array, expected: Array, label: String):
	for i in roster.size():
		var e: Dictionary = ai.units[roster[i]]
		if int(e.timer) != int(expected[i][0]) or int(e.cooldown) != int(expected[i][1]):
			diverge("want: unit timers", "%s %s: port [%d, %d], original %s" % [label, roster[i], int(e.timer), int(e.cooldown), expected[i]])

# ------------------------------------------------------------------------------------------------ 0x40c740 + 0x40c990
func _gates(rules, list: Array):
	var saved: Dictionary = rules.options.duplicate()
	for c in list:
		cases += 1
		rules.options = {"build_level": int(c.build_level), "no_dragons": int(c.options.no_dragons) != 0,
			"no_fliers": int(c.options.no_fliers) != 0, "no_towers": int(c.options.no_towers) != 0,
			"no_walls": int(c.options.no_walls) != 0, "no_lords": int(c.options.no_lords) != 0}
		var got: bool = rules.slot_allowed(String(c.item), String(c.kind), {"hero_alive": String(c.hero) == "alive", "lord_built": int(c.lord_built) != 0})
		if got == bool(c.allowed): continue
		var group := "gate: other"
		if String(c.kind) == "-" and String(c.item) in Rules.DRAGONS: group = "gate: '-' slot with a dragon"
		diverge(group, "%s slot '%s' (%s) build level %d options %s hero %s lord %d: port %s, original %s" % [c.item, c.kind,
			c.source, int(c.build_level), c.options, c.hero, int(c.lord_built), got, c.allowed])
	rules.options = saved

# ------------------------------------------------------------------------------------------------ 0x523e10 / 0x523e70
func _workers(rules, list: Array):
	for c in list:
		cases += 1
		var hero: bool = int(c.hero) != 0
		var id := String(c.id)
		var power: int = rules.builder_power(id, hero, ["PZOM"] if int(c.pzom) != 0 else [])
		if power != int(c.power):
			diverge("builder power: PZOM" if int(c.pzom) != 0 and id == "AUBX" else "builder power: other",
				"%s hero %s PZOM %d: port %d, original %d" % [id, hero, int(c.pzom), power, int(c.power)])
		var can: bool = rules.can_mine(id, hero)
		if can != (int(c.workers) != 0):
			diverge("mines: can_mine", "%s hero %s: port %s, original %d workers" % [id, hero, can, int(c.workers)])
		elif rules.mine_workers(id, hero) != int(c.workers):
			diverge("mines: two workers per Smith", "%s adds %d workers in the original, %d in the port" % [id, int(c.workers), rules.mine_workers(id, hero)])

# ------------------------------------------------------------------------------------------------ 0x437f70
func _levels(list: Array):
	for c in list:
		cases += 1
		var got := Rules.research_level(c.research.map(func(r): return String(r)), String(c.query))
		if got != int(c.level): diverge("research level", "%s in %s: port %d, original %d" % [c.query, c.research, got, int(c.level)])
