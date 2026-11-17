extends SceneTree
## Milestone 10b: simulation/ai_rules.gd against every case of tests/ai_fixtures.json (original x86, tools/emulate_ai.py).

const R = preload("res://simulation/ai_rules.gd")
var checks := 0
var failures := 0
var cases := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 30: printerr("AI check failed: ", label)

func ints(a: Array) -> Array:
	return a.map(func(v): return int(v) if not v is Array else ints(v))

func _initialize():
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai_fixtures.json"))
	var t: Dictionary = f.tables
	check(ints(t.enemy_base_vs_human) == R.ENEMY_BASE_HUMAN and ints(t.enemy_base_vs_computer) == R.ENEMY_BASE_COMPUTER, "enemy base tables")
	check(ints(t.price_discount) == R.PRICE_DISCOUNT, "price discount table")
	var p: Dictionary = f.default_profile.fields
	check(ints(p.group_min_size) == R.GROUP_MIN and ints(p.group_max_size) == R.GROUP_MAX, "default group sizes")
	check(int(p.named.conversion_share_pct) == 20 and int(p.named.hero_retreats) == 1, "default profile flags")
	cases += 6
	for c in f.category_pct:
		cases += 1
		check(R.category_pct(int(c.category), int(c.difficulty), c.custom) == int(c.result), "category pct %s" % c)
	for c in f.delay:
		cases += 1
		check(R.pacing_delay(int(c.difficulty)) == int(c.result), "delay %s" % c)
	for c in f.income:
		cases += 1
		check(R.income(int(c.lane), int(c.weight), int(c.workers), int(c.difficulty)) == int(c.result), "income %s" % c)
	for c in f.afford:
		cases += 1
		check(int(R.afford(ints(c.stock), ints(c.cost), ints(c.mines), int(c.difficulty))) == int(c.result), "afford %s" % c)
	for c in f.cooldown:
		cases += 1
		var b: Array = c.buildings.map(func(e): return [e[0], int(e[1]), int(e[2]), int(e[3]), int(e[4])])
		var u: Array = c.units.map(func(e): return [e[0], int(e[1]), int(e[2]), int(e[3]), int(e[4])])
		var r: Array = c.research.map(func(e): return [e[0], int(e[1]), int(e[2]), int(e[3]), int(e[4])])
		var ok := R.cooldown_gate(String(c.item), int(c.now), b, u, r)
		check(int(ok) == int(c.result), "cooldown gate %s" % c.item)
		var after := {"buildings": b.map(func(e): return [e[3], e[4]]), "units": u.map(func(e): return [e[3], e[4]]), "research": r.map(func(e): return [e[3], e[4]])}
		check(after.buildings == ints(c.after.buildings) and after.units == ints(c.after.units) and after.research == ints(c.after.research), "cooldown write-back %s" % c.item)
	for c in f.pacing:
		cases += 1
		var maps := {"buildings": {}, "units": {}, "research": {}}
		var lists := {"buildings": [], "units": [], "research": []}
		for key in lists:
			for e in c[key]:
				var entry := [int(e[3]), int(e[4])]
				maps[key][e[0]] = entry
				lists[key].append(entry)
		var want: Array = c.want.map(func(w): return [w[0], int(w[1]), ints(w[2]), int(w[3])])
		R.pacing(int(c.category), int(c.difficulty), ints(c.mines), want, maps.buildings, maps.units, maps.research)
		check(lists.buildings == ints(c.after.buildings) and lists.units == ints(c.after.units) and lists.research == ints(c.after.research), "pacing %s" % c.category)
	for c in f.demand:
		cases += 1
		var want: Array = c.want.map(func(w): return [w[0], int(w[1]), ints(w[2]), int(w[3])])
		var arm := {}
		for k in c.arm_word_0x1c: arm[k] = int(c.arm_word_0x1c[k])
		check(R.demand(want, ints(c.mines), int(c.difficulty), arm) == ints(c.weights), "demand %s" % c)
	for c in f.main_enemy:
		cases += 1
		var players: Array = c.players.map(func(q): return {"active": bool(q.active), "computer": bool(q.computer), "difficulty": int(q.difficulty),
			"start": ints(q.start), "eliminated": bool(q.eliminated), "objects": bool(q.objects)})
		var hate: Array = ints(c.hate)
		var roll := int(c.rolls[0][3]) if not c.rolls.is_empty() else 0
		var main := R.main_enemy(int(c.me), players, c.relations.map(func(row): return row.map(func(v): return int(v) != 0)), hate, ints(c.adjust), int(c.previous), roll)
		check(main == int(c.main) and hate == ints(c.hate_after), "main enemy me %d" % int(c.me))
	for c in f.group_launch:
		cases += 1
		check(group_launch(c) == [int(c.launched), int(c.flag_0xe), int(c.target_player)], "group launch %s" % c)
	var base := {}
	for c in f.computer_price:
		if not c.computer or not c.hero_alive: base[c.item + c.other] = ints(c.cost)
	for c in f.computer_price:
		cases += 1
		var plain: Array = base[c.item + c.other]
		var expected: Array = R.discounted(plain, int(c.difficulty)) if (c.computer and c.hero_alive) else plain
		check(expected == ints(c.cost), "computer price %s" % c)
	# Milestone M-1 (A-1): the research choice 0x4fead0 after the recount 0x4f7f60 (tests/research_fixtures.json,
	# tools/emulate_research.py): keep / remove the category-2 node, the offered entry, the affordability gate.
	var research: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/research_fixtures.json"))
	check(String(research.research_order[0]) == "PCR0", "the Knights research list starts with Crusade I")
	for c in research.cases:
		cases += 1
		var listed := ""
		for w in c.want_before:
			if int(w[2]) & 2:
				listed = String(w[0])
				break
		var entries: Array = c.entries.map(func(e): return {"id": String(e[0]), "priority": int(e[1]), "have": int(e[2]) != 0,
			"ordered": c.ordered.has(e[0]), "eligible": int(e[4]) != 0})
		var pick: Dictionary = R.research_pick(listed, entries)
		var after := ""
		for w in c.want_after:
			if int(w[2]) & 2:
				after = String(w[0])
				break
		var expected := listed if pick.keep else ""
		if not pick.keep and String(pick.offer) != "" and R.afford(ints(c.stock), ints(c.prices[pick.offer]), c.mines, int(c.difficulty)):
			expected = String(pick.offer)
		check(after == expected and (not pick.keep or c.want_after.size() == c.want_before.size()), "research choice %s -> %s, expected %s" % [listed, after, expected])
	batch1()
	tech_step()
	if failures > 0:
		printerr("AI checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI rule checks passed: %d checks over %d fixture cases" % [checks, cases])
	quit(0)

## B1-5 (tests/ai_batch1_fixtures.json, tools/emulate_ai_batch1.py): the Undead pacing 0x50b2c0 with the advancement flow,
## and the computer's lists (0x4fcfa0 / 0x4fd060 / 0x4fd140) of the Knights, Dwarves, Undead and Swarm against
## ai_player.gd's lists (no roster limit) built over the real production rules.
func batch1():
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai_batch1_fixtures.json"))
	for c in f.undead_pacing:
		cases += 1
		var maps := {"buildings": {}, "units": {}, "research": {}}
		var lists := {"buildings": [], "units": [], "research": []}
		var order: Array = []
		for key in lists:
			for e in c[key]:
				var entry := [int(e[3]), int(e[4])]
				maps[key][e[0]] = entry
				lists[key].append(entry)
				if key == "units": order.append(String(e[0]))
		var want: Array = c.want.map(func(w): return [w[0], int(w[1]), ints(w[2]), int(w[3])])
		var chain := R.undead_chain(c.prices) if int(c.category) == 1 else {}
		R.pacing_undead(int(c.category), int(c.difficulty), ints(c.mines), want, maps.buildings, maps.units, maps.research, chain)
		if int(c.category) == 1: R.advancement_flow(maps.units, order)
		check(lists.buildings == ints(c.after.buildings) and lists.units == ints(c.after.units) and lists.research == ints(c.after.research),
			"Undead pacing category %d difficulty %d" % [int(c.category), int(c.difficulty)])
	var rules = preload("res://simulation/production_rules.gd").new()
	var world := FakeWorld.new()
	world.production = FakeProduction.new()
	world.production.rules = rules
	for race in f.lists:
		cases += 1
		var l: Dictionary = f.lists[race]
		var ai = preload("res://simulation/ai_player.gd").new(1, 3, world, int(race))
		var hero: String = rules.hero_type(int(race))
		check(ai.building_order == l.buildings, "race %s buildings %s, original %s" % [race, ai.building_order, l.buildings])
		check(ai.unit_order == l.units + [hero], "race %s units %s, original %s + the hero" % [race, ai.unit_order, l.units])
		check(ai.research_order == l.research, "race %s research %s, original %s" % [race, ai.research_order, l.research])
		check(ai.PEASANT == String(l.peasant), "race %s Peasant %s, original %s" % [race, ai.PEASANT, l.peasant])
		ai.dispose()

## A-2 (tests/tech_step_fixtures.json, tools/emulate_tech_step.py): the original's enabling matrix 0x4fd1b0, the
## +0x80 flags, the command buildings, the unit orders of 0x4ff5f0 / 0x4fc7e0 and the tech step 0x4ff0d0 (node test,
## walk choice, the unit it stopped at) on the port's captured soak state, against ai_player.gd's inputs and
## ai_rules.tech_order / tech_keep / tech_step.
func tech_step():
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/tech_step_fixtures.json"))
	var rules = preload("res://simulation/production_rules.gd").new()
	for s in f.samples:
		cases += 1
		var world := FakeWorld.new()
		world.production = FakeProduction.new()
		world.production.rules = rules
		world.production.menus = s.inputs.menus
		var ai = preload("res://simulation/ai_player.gd").new(int(s.player), 3, world, int(s.race))
		var label := "%s t=%d P%d race %d" % [s.input, int(s.t), int(s.player), int(s.race)]
		for i in s.units.size(): ai.units[s.units[i]].priority = int(s.inputs.priorities[i])
		var walk: Dictionary = ai._tech_walk()
		check(walk.units == s.units, "%s: unit list" % label)
		var needs: Array = walk.needs.map(func(n): return n.b.map(func(j): return ai.building_order[j]) + n.r.map(func(k): return ai.research_order[k]))
		check(needs == s.matrix, "%s: enabling matrix %s, original %s" % [label, needs, s.matrix])
		check(ai._menu_flags().map(func(v): return int(v)) == ints(s.flags), "%s: +0x80 flags" % label)
		var command: Array = []
		for j in ai.building_order.size():
			if walk.expensive[j]: command.append(ai.building_order[j])
		var original: Array = s.command.filter(func(c): return c != "")
		command.sort()
		original.sort()
		check(command == original, "%s: command buildings %s, original %s" % [label, command, original])
		check(walk.by_cost.map(func(i): return walk.units[i]) == s.by_cost, "%s: +0x3b02 %s, original %s" % [label, walk.by_cost.map(func(i): return walk.units[i]), s.by_cost])
		check(walk.order.map(func(i): return walk.units[i]) == s.order, "%s: +0x3ac6" % label)
		var b_rows: Array = []
		var by_id := {}
		for j in s.inputs.buildings.size():
			var b: Array = s.inputs.buildings[j]
			b_rows.append({"id": b[0], "have": int(b[1]) + int(b[2]), "available": int(b[3]) != 0, "flag": ai._menu_flags()[j]})
			by_id[b[0]] = {"available": int(b[3]) != 0, "count": int(b[1])}
		var r_rows: Array = []
		var r_by_id := {}
		for r in s.inputs.research:
			r_rows.append({"id": r[0], "had": int(r[1]) != 0, "ordered": int(r[2]) != 0, "eligible": int(r[3]) != 0 and int(r[2]) == 0})
			r_by_id[r[0]] = {"eligible": int(r[3]) != 0, "had": int(r[1]) != 0}
		var kept := false
		for w in s.inputs.want:
			if int(w[3]) & 4:
				kept = R.tech_keep(String(w[0]), by_id.get(w[0]), r_by_id.get(w[0]))
				break
		check(kept == bool(s.kept), "%s: node test kept %s, original %s" % [label, kept, s.kept])
		var step: Dictionary = R.tech_step(walk.order, walk.needs, b_rows, r_rows, ai._producer_id(ai.PEASANT))
		if not kept:
			check(String(step.offer) == String(s.offer) and int(step.stop) == int(s.stop), "%s: walk %s, original offer %s stop %d" % [label, step, s.offer, int(s.stop)])
		# The same state without the listed category-4 node: the walk always runs.
		check(String(step.offer) == String(s.walk_offer) and int(step.stop) == int(s.walk_stop), "%s: walk without the node %s, original %s stop %d" % [label, step, s.walk_offer, int(s.walk_stop)])
		ai.dispose()

class FakeWorld:
	var production
class FakeProduction:
	var rules
	var menus := [[], []]
	func construction_menu(_owner: int, row: int = 0) -> Array: return Array(menus[row])

## The fixture world of 0x4f3520 -> 0x4f3640 -> 0x4f4e30: players 0 (human), 1 (this AI), 2 (computer, main enemy).
func group_launch(c: Dictionary) -> Array:
	if c.already: return [1, 0, -1]
	if not R.launches(int(c.kind), int(c.size), bool(c.hero), int(c.difficulty)): return [0, 1, -1]
	var rolls: Array = c.rolls.map(func(r): return int(r[3]))
	if rolls[0] > R.human_focus(int(c.difficulty), 2): return [1, 0, 2]
	var best := 0
	var target := -1
	if rolls.size() > 1 and best < rolls[1]: target = 0
	return [1, 0, 2 if target == -1 else target]
