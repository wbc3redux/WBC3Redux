extends "res://tests/batch2_world_base.gd"
## R-1: unit ranks in the real scene (a Knights side against a passive computer on Desert Sands, tests/batch2_world_base.gd's
## helpers): a trained Peasant's starting experience, a real fight to rank 1 and past it, the block, the ring, the info rows
## and the list frames, the regeneration timer, the morph and retinue paths.

func label() -> String: return "Rank"
func race() -> int: return Setup.KNIGHT
func hall() -> String: return "BKP"
func worker() -> String: return "AHBX"

func whole_faction(store):
	var id := "test-rank-hero"
	var profile = Profile.create(id, "Rank Tester", race(), 0)
	profile.data.stats = [12, 12, 12, 12]
	check(store.save_profile(profile), "test profile saved")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_race(setup, 0, race())
	Setup.set_race(setup, 1, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = id
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)          # Passive
	check(scene.start_skirmish(setup, id, store, "rank-world"), "match starts")
	production = scene.production
	advance(1.0)
	fund()
	for u in scene.units:
		if u.owner_id == 0 and fighter(u) != null and fighter(u).hero: hero_unit = u
	check(hero_unit != null, "the hero stands")
	home = scene.skirmish.slots[0].start

func powers():
	trained()
	await_fight()
	morph_and_deploy()
	attitude()

## 0x559860 through the cell: the dialog opens, lists the nine scripts by name, a press assigns and the release closes.
func attitude():
	var u = scene.add_unit("AHKX", scene.navigator.free_cell_near(home + Vector2i(18, 12)), 0)
	select_units([u])
	var k := cell_with(0x15)
	check(k == 5 and bool(hud.cells[k].enabled), "the Attitude cell is enabled")
	if k < 0: return
	check(hud.press_cell(k), "the cell is pressed")
	check(hud.dialog == "attitude", "the dialog is open")
	var rows: Array = hud.attitude_rows()
	check(rows.size() == 9 and String(rows[0].name) == "Aggressive" and String(rows[8].name) == "Standard" and String(rows[7].name) == "Stand Ground", "nine scripts by name")
	check(hud.selection_attitude() == 2, "the unit is Defensive")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	hud.attitude_mouse(press, Vector2(40, 12))
	check(int(fighter(u).script) == int(rows[0].index), "a press on a row assigns its script")
	check(hud.selection_attitude() == int(rows[0].index), "and the list follows")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	hud.attitude_mouse(release, Vector2(40, 12))
	check(hud.dialog == "", "the release closes it")

## The training job's message 0xfa: the hero's starting experience (0x557d90) on the new unit, seen as a rank at once.
func trained():
	var start: int = scene.combat.starting_xp(0, "AHBX")
	check(start > 0, "the hero teaches: %d" % start)
	var id: int = production.spawn_unit(0, "AHBX", home + Vector2i(6, 6))
	check(id >= 0, "a Peasant is sent as message 0xfa")
	if id < 0: return
	var f = scene.combat.fighters[id]
	check(int(f.xp) == start, "the Peasant starts with %d: %d" % [start, int(f.xp)])
	var info := {"building": -1, "item": "AHBX", "owner": 0, "cell": scene.navigator.free_cell_near(home + Vector2i(7, 7)), "rally": Vector2i(-1, -1), "unit_id": -1}
	research_flag("PTRN")
	production.unit_ready.emit(info)
	check(int(scene.combat.fighters[int(info.unit_id)].xp) == start + 10, "the training job's terms come first: %d" % int(scene.combat.fighters[int(info.unit_id)].xp))
	production.research[0] = production.research[0].filter(func(r): return r != "PTRN")
	check(int(f.rank) == preload("res://simulation/unit_ranks.gd").gain({"rank": 0, "xp": 0, "combat": 1, "speed": 1, "mres": 0, "max_hp": 10, "hp": 10, "dmg": 1, "armour": 0, "word_ae": 0, "word_b0": 0}, start), "and the rank of that experience")

func research_flag(item: String):
	var list: Array = production.research.get(0, [])
	list.append(item)
	production.research[0] = list

func await_fight():
	var cell: Vector2i = scene.navigator.free_cell_near(home + Vector2i(14, 8))
	var veteran = scene.add_unit("AHKX", cell, 0)
	var f = fighter(veteran)
	check(int(f.rank) == 0 and int(f.xp) == 0, "a unit made by the scene has no experience of its own")
	f.base.dmg = 500
	f.stats.dmg = 500
	f.base.combat = 40
	f.stats.combat = 40
	var kills := 0
	var messages: Array = []
	scene.combat.rank_gained.connect(func(_id, _rank): messages.append(scene.last_message))
	for i in 12:
		var enemy = scene.add_unit("AHKX", scene.navigator.free_cell_near(cell + Vector2i(1, 0)), 1)
		check(scene.combat.order_attack(veteran.unit_id, "unit", enemy.unit_id), "the veteran attacks")
		var waited := 0.0
		while waited < 40.0 and scene.combat.alive(fighter(enemy)):
			advance(0.25)
			waited += 0.25
		check(not scene.combat.alive(fighter(enemy)), "the enemy falls")
		kills += 1
		if int(f.xp) >= 10: break
	check(int(f.xp) == 10, "the kills gave the experience: %d after %d enemies (a tower may take one)" % [int(f.xp), kills])
	check(int(f.rank) == 2, "rank 2 at 10 experience: %d" % int(f.rank))
	check(int(f.max_hp) > 40 and int(veteran.max_hp) == int(f.max_hp), "the block rose")
	check(messages == ["Gained Level 2", "Gained Level 3"], "the messages: %s" % [messages])
	select_units([veteran])
	scene.update_order_marker()
	check(int(veteran.ring_rank) == 2, "the ring shows the rank: %d" % int(veteran.ring_rank))
	check(hud.get_script().list_frame(false, int(f.rank)) == 0, "rank 2: the plain list frame")
	scene.combat.gain_experience(f, 40 - int(f.xp))
	check(int(f.rank) == 4 and hud.get_script().list_frame(false, int(f.rank)) == 1, "rank 4: the second column of frames")
	scene.update_order_marker()
	check(int(veteran.ring_rank) == 4, "the ring moves with it")
	hud.queue_redraw()
	# The regeneration timer in the scene: one hit, the next tick a while later.
	var hp: int = int(f.hp)
	scene.combat.apply_damage("unit", veteran.unit_id, 3, -1)
	check(int(f.hp) == hp - 3 and int(f.get("regen_ms", 0)) > 0, "the hit arms the timer")
	advance(12.0)
	check(int(f.hp) >= hp - 2, "a point came back: %d of %d" % [int(f.hp), hp])

func morph_and_deploy():
	var cell: Vector2i = scene.navigator.free_cell_near(home + Vector2i(14, 12))
	var u = scene.add_unit("AHKX", cell, 0)
	var f = fighter(u)
	scene.combat.gain_experience(f, 70)
	check(int(f.rank) == 5, "rank 5 at 70: %d" % int(f.rank))
	var made = scene.morph_unit(u, "AHMX", false)
	check(made != null, "the morph makes a unit")
	if made != null:
		var g = fighter(made)
		var start: int = scene.combat.starting_xp(0, "AHMX")
		check(int(g.xp) == maxi(70, start) and int(g.rank) >= 5, "the morphed unit keeps its experience: %d, rank %d" % [int(g.xp), int(g.rank)])
	var deployed = scene.add_unit("AHKX", scene.navigator.free_cell_near(home + Vector2i(16, 12)), 0)
	var d = fighter(deployed)
	scene.combat.set_rank(d, 3, 21)
	# 0x4a5780 (REVIEW_R1.md D1, Emulated "fd_builder"): the block's rank, the experience 0x5fbc48[3] = 10 outside a scenario.
	check(int(d.rank) == 3 and int(d.xp) == 10 and int(d.max_hp) == 55, "a retinue block keeps its rank, experience 0x5fbc48[rank]: %d xp, %d hp" % [int(d.xp), int(d.max_hp)])
