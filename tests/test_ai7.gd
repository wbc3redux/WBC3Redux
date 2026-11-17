extends SceneTree
## Milestone AI-7 (AI_RESEARCH.md "AI-7"): the recruit and group machine of tools/emulate_ai7.py (tests/ai7_fixtures.json)
## against simulation/ai_groups.gd:
## * `recruit`: passes of 0x4f5700 (with 0x4f59e0, 0x4f5570, 0x4f3470, 0x4f37f0, 0x4f6d90, 0x4f3520 live) and 0x4f5610's
##   tail; every group's slot, type, member slots, mode, launch, attacked player, leader, centre, strength, long-range
##   and converter counts, slowest speed and layer, every unit's group and every die thrown must match.
## * `state`: 0x4f3b00 (march state, mode, target) and 0x4f3da0 (spread) after 0x4f37a0.
## * `threat`: 0x4f3e70 (level and the slot's level / object) on the emulator's map rows (list order: newest first).

const Groups = preload("res://simulation/ai_groups.gd")
const PLAYER := 1

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 25: printerr("AI-7 check failed: ", label)

func _initialize():
	var f = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai7_fixtures.json"))
	if not (f is Dictionary) or not f.has("recruit"):
		printerr("AI-7 fixtures missing or unreadable")
		quit(1)
		return
	var cases := 0
	for c in f.recruit:
		cases += 1
		recruit_case(c)
	for c in f.state:
		cases += 1
		state_case(c, cases)
	for c in f.threat:
		cases += 1
		threat_case(c, cases)
	if failures > 0:
		printerr("AI-7 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI-7 checks passed: %d checks over %d fixture cases" % [checks, cases])
	quit(0)

class Dice extends RefCounted:
	var faces: Array = []
	var rolls: Array = []
	func roll(count: int, sides: int) -> int:
		var total := 0
		for i in count:
			var face: int = int(faces.pop_front()) if not faces.is_empty() else 1
			total += ((face - 1) % maxi(sides, 1)) + 1
		rolls.append([count, sides, 0, total])
		return total

static func record(u: Dictionary, spec: Dictionary) -> Dictionary:
	return {"id": int(u.id), "code": String(u.code), "cell": Vector2i(int(spec.cell[0]), int(spec.cell[1])), "hp": int(u.hp),
		"max_hp": int(u.max_hp), "speed": int(u.speed), "dmg": int(u.dmg), "range": int(u.range), "converts": int(u.converts) != 0,
		"strength": int(u.strength), "layer": int(u.layer), "size": int(u.size), "builder": int(u.builder),
		"hero": int(spec.get("hero", 0)) != 0, "general": int(spec.get("general", 0)) != 0, "task": int(spec.get("task", 0)) != 0}

func recruit_case(c: Dictionary):
	var dice := Dice.new()
	var players: Array = []
	for p in 6: players.append({"active": p == 0 or p == PLAYER, "computer": false, "eliminated": false, "allied": p == PLAYER})
	var ctx := {"difficulty": int(c.difficulty), "words": Groups.default_words(), "units": {}, "roll": dice.roll,
		"players": players, "main_enemy": int(c.main_enemy), "retreating": int(c.retreating) != 0}
	var groups: Array = []
	var nodes: Array = []           # [unit id, group slot]
	var next := 0
	for p in c.passes.size():
		var pass_row: Dictionary = c.passes[p]
		for spec in pass_row.add:
			var rec := record(c.units[next], spec)
			next += 1
			ctx.units[int(rec.id)] = rec
			nodes.append([int(rec.id), -1])
		for s in pass_row.set_launched:
			var g = Groups.by_slot(groups, int(s))
			if g != null: g.launched = true
		dice.faces = pass_row.faces.duplicate()
		dice.rolls = []
		for n in nodes:
			var u: Dictionary = ctx.units[int(n[0])]
			if bool(u.task): continue
			if bool(u.hero) and bool(ctx.retreating): continue
			if int(u.builder) != 0 and int(u.max_hp) <= 49: continue
			if int(n[1]) == -1:
				var s := Groups.recruit_one(groups, u, ctx)
				if s >= 0: n[1] = s
			elif Groups.by_slot(groups, int(n[1])) == null:
				n[1] = -1
		Groups.pass_tail(groups, ctx)
		var label := "case %d pass %d" % [int(c.case), p]
		check(dice.rolls == pass_row.rolls.map(func(r): return r.map(func(v): return int(v))), "%s dice %s vs %s" % [label, dice.rolls, pass_row.rolls])
		check(nodes.map(func(n): return int(n[1])) == pass_row.node_groups.map(func(v): return int(v)), "%s node groups %s vs %s" % [label, nodes.map(func(n): return n[1]), pass_row.node_groups])
		var got: Array = groups.map(func(g): return summary(g))
		var want: Array = pass_row.groups.map(func(g): return [int(g.slot), int(g.type), g.members.map(func(v): return int(v)), int(g.count),
			int(g.mode), int(g.launched), int(g.target_player) if int(g.launched) else 0, int(g.leader), [int(g.centre[0]), int(g.centre[1])],
			int(g.strength), int(g.ranged), int(g.converters), int(g.min_speed), int(g.layer)])
		check(got == want, "%s groups\n  port %s\n  orig %s" % [label, got, want])
		if got != want: return

static func summary(g: Dictionary) -> Array:
	return [int(g.slot), int(g.kind), g.slots.map(func(v): return int(v)), Groups.count(g), int(g.mode), int(g.launched),
		int(g.target_player) if bool(g.launched) else 0, int(g.leader), [g.centre.x, g.centre.y], int(g.strength), int(g.ranged),
		int(g.converters), int(g.min_speed), int(g.layer)]

func state_case(c: Dictionary, index: int):
	var ctx := {"difficulty": 6, "units": {}}
	var g := Groups.new_record(0)
	g.kind = int(c.type)
	for k in c.members.size():
		var m: Dictionary = c.members[k]
		var rec := {"id": k + 1, "cell": Vector2i(int(m.cell[0]), int(m.cell[1])), "hp": int(m.hp), "speed": int(m.speed), "dmg": int(m.dmg),
			"range": int(m.range), "converts": int(m.converts) != 0, "strength": int(m.strength), "layer": int(m.layer), "size": int(m.size)}
		ctx.units[k + 1] = rec
		g.slots[k] = k + 1
	g.mode = int(c.mode)
	g.state = int(c.state)
	Groups.drop_dead(g, ctx)
	check(int(g.leader) == int(c.before.leader) and [g.centre.x, g.centre.y] == c.before.centre.map(func(v): return int(v)), "state %d leader / centre" % index)
	var t: Dictionary = c.target
	var target := {}
	if t.kind != "none":
		target = {"cell": Vector2i(int(t.cell[0]), int(t.cell[1])), "dying": bool(t.dying), "allied": int(t.owner) == PLAYER, "flag_0x115": bool(t.flag_0x115)}
	if t.kind != "none": g.target = {"kind": t.kind, "id": 99}
	Groups.march(g, target, ctx)
	var a: Dictionary = c.after
	check(int(g.state) == int(a.state) and int(g.mode) == int(a.mode), "state %d: state %d mode %d vs %d %d" % [index, g.state, g.mode, a.state, a.mode])
	check((not g.target.is_empty()) == (int(a.target) != -1), "state %d: target kept %s vs %d" % [index, g.target, a.target])
	check(Groups.spread(g, ctx) == int(c.spread), "state %d: spread %d vs %d" % [index, Groups.spread(g, ctx), c.spread])

func threat_case(c: Dictionary, index: int):
	var ctx := {"difficulty": 6, "units": {}}
	var g := Groups.new_record(0)
	g.kind = int(c.type)
	var objects: Array = []      # in creation order, as the emulator links them (each row: newest first)
	for k in c.members.size():
		var m: Dictionary = c.members[k]
		var rec := {"id": k + 1, "cell": Vector2i(int(m.cell[0]), int(m.cell[1])), "hp": int(m.hp), "speed": int(m.speed), "dmg": int(m.dmg),
			"range": int(m.range), "converts": int(m.converts) != 0, "strength": int(m.strength), "layer": int(m.layer), "size": int(m.size),
			"hero": bool(m.hero)}
		ctx.units[k + 1] = rec
		g.slots[k] = k + 1
		objects.append({"ref": k + 1, "cell": rec.cell, "kind": "unit", "owner": PLAYER, "allied": true})
	for o in c.others:
		var owner := int(o.owner)
		var attacks := int(o.get("attacks", -1))
		var victim_allied := false
		if attacks != -1:
			if attacks <= c.members.size(): victim_allied = true
			else:
				for v in c.others:
					if int(v.id) == attacks: victim_allied = int(v.owner) == PLAYER
		var row := {"ref": int(o.id), "cell": Vector2i(int(o.cell[0]), int(o.cell[1])), "kind": String(o.kind), "owner": owner,
			"allied": owner == PLAYER, "dying": bool(o.get("dying", false)), "aims_at_ally": victim_allied}
		if o.kind == "unit":
			row["ground"] = int(o.movement) == 0 or int(o.movement) == 3
		else:
			var code := String(o.code)
			row["skip"] = code == "BMFL" or code[1] == "T" or code[1] == "R"
			row["flag_0x1a2"] = bool(o.get("flag_0x1a2", false))
			row["armed"] = int(o.get("damage", 0)) >= 1
		objects.append(row)
	var rows := {}
	for o in objects:
		var y: int = o.cell.y
		if not rows.has(y): rows[y] = []
		rows[y].push_front(o)
	Groups.drop_dead(g, ctx)
	var k := int(c.member)
	if c.prior != null: g.data[k].obj = int(c.prior)
	var level := Groups.look(g, k, rows, 128, 128, ctx)
	check(level == int(c.level), "threat %d: level %d vs %d" % [index, level, c.level])
	var obj = g.data[k].obj
	check([int(g.data[k].level), int(obj) if obj != null else -1] == [int(c.slot[1]), int(c.slot[2])], "threat %d: slot %s %s vs %s" % [index, g.data[k].level, obj, c.slot])
