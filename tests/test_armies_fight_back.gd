extends SceneTree
## Playtest 2026-11-10 (Cavern Wars): a computer army marching on its target walked past the player's army and did not
## answer its attacks. AI-7 (AI_RESEARCH.md 23, Emulated 0x4f3e70 / Read 0x4f42a0): with the original rules a group whose members see a hostile unit attacking one of them within 14 cells (level 3) attacks it, so it answers too; the 10b reading (player-level army orders, REVIEW_SKIRMISH_AI D6, no answer) is replaced. With
## "Armies: Improved" (deliberate, ai_player.gd _engage_improved) the group fights back and then goes on.
## A launched computer group (side 1) marches on a side-0 unit at side 0's start; side 0's soldiers stand in its way and attack it.
##   Godot --headless --path . --script res://tests/test_armies_fight_back.gd

const Setup = preload("res://simulation/skirmish_setup.gd")

var checks := 0
var failures := 0

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("Fight back check failed: " + label)

func play(improved: bool) -> Dictionary:
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 0)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 3)
	scene.start_skirmish(setup, "", null, "fight-back")
	scene.improved_armies = improved
	var c = scene.combat
	var p1 = null
	for p in scene.ai_manager.players:
		if p != null and "me" in p and int(p.me) == 1: p1 = p
	scene.ai_manager.players[0] = null                         # side 0 does nothing on its own
	var home0: Vector2i = scene.skirmish.slots[0].start
	var home1: Vector2i = scene.skirmish.slots[1].start
	var target = scene.add_unit("AHKX", scene.navigator.free_cell_near(home0), 0)   # the group's target: far beyond the defenders
	var mid: Vector2i = (home0 + home1) / 2
	var members: Array = []
	for i in 6:
		var u = scene.add_unit("AHKX", scene.navigator.free_cell_near(mid + Vector2i(i % 3, i / 3)), 1)
		members.append(u.unit_id)
	var g := {"kind": 0, "members": members, "launched": true, "target_player": 0, "target": {"kind": "unit", "id": target.unit_id}, "hero": false}
	p1.groups.append(g)
	p1._order_group(g, {"kind": "unit", "id": target.unit_id, "code": "AHKX"})
	var defenders: Array = []
	for i in 4:
		var u = scene.add_unit("AHKX", scene.navigator.free_cell_near(mid + Vector2i(-3, i)), 0)
		defenders.append(u.unit_id)
		c.order_attack(u.unit_id, "unit", int(members[i]), false)
	var answered := {"hits": 0}
	c.damaged.connect(func(kind, id, amount, attacker):
		if kind == "unit" and id in defenders and attacker in members: answered.hits += 1)
	for i in 40 * 25: scene.simulation_step(0.025)
	var result := {"hits": answered.hits, "fighting_flag": g.get("fighting", false), "improved": improved}
	scene.queue_free()
	await process_frame
	return result

func run():
	var faithful: Dictionary = await play(false)
	check(int(faithful.hits) > 0, "original rules (AI-7, 0x4f3e70 level 3): the marching group answers: %s" % faithful)
	var modern: Dictionary = await play(true)
	check(int(modern.hits) > 0, "improved armies: the marching group fights back: %s" % modern)
	if failures > 0:
		print("Fight back checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Fight back checks passed: %d (original %d hits back, improved %d)" % [checks, int(faithful.hits), int(modern.hits)])
	quit(0)
