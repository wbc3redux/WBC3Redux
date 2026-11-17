extends SceneTree
## Milestone M-1 (A-1): captures the computer players' state of the Desert Sands Knights-vs-Knights soak (ai_soak.gd's
## setup: P0 Lord, P1 Emperor, fixed seed) at several times, as input for tools/emulate_keep_choice.py, which runs the
## original Peasant demand 0x4fe830 and the building choice 0x4fd940 on it. Writes tests/ai_state_fixtures.json with the
## port's own answers (Peasant priority, the Keep's candidates and their bonus + priority) next to the inputs.
## Milestone A-2: `-- --races=0,1 --times=60,120,... --out=res://tests/tech_state_fixtures.json` captures another pairing
## for tools/emulate_tech_step.py (the tech step 0x4ff0d0); every sample also holds the race, the stock, the construction
## menus, the prices of the listed buildings and research, the port's walk order and needs, and the port's tech step on
## that state (run on a copy of the lists, then restored, so the match goes on unchanged).
## B2-3: `-- --map=the-lions-den --map-races` plays another map as ai_soak.gd does (its difficulties per side, the side
## records' races), and the Keep rows hold the race's own hall (BKP for the Empire), for The Lion's Den's confirmation.
## Not a -Check suite: `tools/run_guarded.ps1 -Script res://tests/capture_ai_state.gd -QuitAfter 0`.

const Setup = preload("res://simulation/skirmish_setup.gd")
const MapData = preload("res://core/map_data.gd")
const DIFFICULTIES := [3, 6, 4, 5, 2, 2]                 # ai_soak.gd
var times: Array = [180, 240, 300, 360, 420, 480, 540, 600]

func _initialize():
	call_deferred("run")

func run():
	var races: Array = [0, 0]
	var out := "res://tests/ai_state_fixtures.json"
	var slug := "desert-sands"
	var map_races := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="): slug = arg.get_slice("=", 1)
		if arg == "--map-races": map_races = true
		if arg.begins_with("--races="): races = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--times="): times = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--out="): out = arg.get_slice("=", 1)
	MapData.select(slug)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = MapData.map() if slug != "desert-sands" else JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	if map_races: races = range(int(setup.sides)).map(func(i): return int(setup.players[i].race))
	for i in races.size():
		Setup.set_race(setup, i, int(races[i]))
		Setup.set_kind(setup, i, Setup.COMPUTER, DIFFICULTIES[i])
	scene.start_skirmish(setup, "", null, "soak")
	var samples: Array = []
	var step := 0
	for t in times:
		while step < int(t) * 40 and not scene.skirmish.over:
			scene.simulation_step(0.025)
			step += 1
		if scene.skirmish.over: break
		for ai in scene.ai_manager.players:
			if ai == null or not ai.has_method("summary"): continue
			samples.append(sample(scene, ai, int(t)))
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 1, "source": "tests/capture_ai_state.gd (%s, races %s, ai_soak.gd seed)" % [slug, races], "samples": samples}) + "\n")
	file.close()
	print("captured %d samples" % samples.size())
	scene.end_skirmish()
	scene.free()
	quit(0)

func sample(scene, ai, t: int) -> Dictionary:
	var units: Array = ai.unit_order.map(func(id): var u: Dictionary = ai.units[id]; return [id, int(u.priority), int(u.count), int(u.pending), int(u.timer), int(u.cooldown), int(bool(u.trainable))])
	var buildings: Array = ai.building_order.map(func(id): var b: Dictionary = ai.buildings[id]; return [id, int(b.count), int(b.pending), int(b.timer), int(b.cooldown), int(bool(b.available))])
	var research: Array = ai.research_order.map(func(id): return [id, int(ai.research[id].priority), int(ai._research_level(id) != 0), int(ai._research_running(id)),
		int(ai.research_eligible(id) or ai._research_running(id)), int(ai.research[id].timer), int(ai.research[id].cooldown)])
	var want: Array = ai.want.filter(func(w): return not w.done).map(func(w): return [String(w.id), int(w.priority), int(w.bonus), int(w.categories), w.cost])
	var keeps: Array = []
	for b in scene.production.buildings.values():
		if int(b.owner) != ai.me or b.constructing or not String(b.original_type_id).begins_with(String(ai.KEEPS[0]).left(3)): continue
		var menu: Array = scene.production.menu_for(b).map(func(e): return String(e.id))
		var candidates: Array = []
		for id in menu:
			var w = ai._want(id)
			if w == null or not scene.production.can_queue(b.entity_id, id).ok: continue
			candidates.append([id, int(w.bonus) + int(w.priority)])
		keeps.append({"type": String(b.original_type_id), "busy": b.has_job(), "job": String(b.job_item), "menu": menu, "candidates": candidates})
	var lanes: Array = []
	for lane in 4: lanes.append([int(ai.mine_weights[lane][0]), int(ai.mine_weights[lane][1]), int(ai.mine_slots[lane])])
	var peasant = ai._node(ai.PEASANT)
	var prices := {}
	for id in ai.building_order + ai.research_order: prices[id] = Array(scene.production.price_of(ai.me, id))
	var walk: Dictionary = ai._tech_walk()
	return {"t": t, "player": ai.me, "race": ai.race, "difficulty": ai.difficulty, "now": ai.now(), "lanes": lanes, "units": units,
		"buildings": buildings, "research": research, "want": want, "keeps": keeps, "peasant": ai.PEASANT,
		"peasant_priority": int(peasant.priority) if peasant != null else 0, "population": scene.production.population(ai.me),
		"stock": Array(scene.economy.resources(ai.me)).map(func(v): return int(v)),
		"menus": [scene.production.construction_menu(ai.me, 0), scene.production.construction_menu(ai.me, 1)],
		"prices": prices, "port_order": walk.order.map(func(i): return walk.units[i]),
		"port_needs": walk.needs.map(func(n): return n.b.map(func(j): return ai.building_order[j]) + n.r.map(func(k): return ai.research_order[k])),
		"port_tech": port_tech(ai)}

## The port's tech step on this state: the lists are copied, ai._want_tech runs, the result is read and the lists restored.
func port_tech(ai) -> Dictionary:
	var saved_want: Array = ai.want.map(func(w): return w.duplicate(true))
	var saved := {"units": ai.units.duplicate(true), "buildings": ai.buildings.duplicate(true), "research": ai.research.duplicate(true)}
	ai.want = ai.want.filter(func(w): return not w.done)          # as build_want_list does before its builders
	var choice: Dictionary = ai.tech_choice()
	ai._want_tech()
	var after: Array = ai.want.filter(func(w): return not w.done).map(func(w): return [String(w.id), int(w.priority), int(w.bonus), int(w.categories)])
	ai.want = saved_want
	ai.units = saved.units
	ai.buildings = saved.buildings
	ai.research = saved.research
	return {"choice": choice, "want_after": after}
