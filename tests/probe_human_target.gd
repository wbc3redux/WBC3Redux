extends SceneTree
## Diagnostic (not part of -Check): does the computer attack a human side? Side 0 is a human who does nothing; the others
## are computer players. Every --every seconds: each computer's main enemy and groups (kind, size, launched, target
## player), the damage side 0 has taken (units / buildings) and the nearest computer unit to a side-0 object.
##   Godot --headless --path . --script res://tests/probe_human_target.gd -- --map=cavern-wars [--minutes=15] [--every=60]

const Setup = preload("res://simulation/skirmish_setup.gd")
const MapData = preload("res://core/map_data.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

var taken := {"unit": 0, "building": 0}
var hits_by := {}

func _initialize():
	call_deferred("run")

func run():
	var minutes := 15.0
	var every := 60.0
	var slug := "cavern-wars"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="): minutes = float(arg.get_slice("=", 1))
		if arg.begins_with("--every="): every = float(arg.get_slice("=", 1))
		if arg.begins_with("--map="): slug = arg.get_slice("=", 1)
	Settings.use_file("user://probe-settings.cfg")
	var store := Store.new("user://probe-heroes")
	store.save_profile(Profile.create("probe-human", "Probe"))
	MapData.select(slug)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var setup := Setup.defaults(MapData.map())
	var sides := int(setup.sides)
	for i in sides: Setup.set_race(setup, i, int(setup.players[i].race))
	for i in range(1, sides): Setup.set_kind(setup, i, Setup.COMPUTER, [3, 3, 4, 5, 2, 2][i])
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "probe-human"
	if not scene.start_skirmish(setup, "probe-human", store, "probe"):
		print("probe: the match did not start")
		quit(1)
		return
	scene.set_physics_process(false)
	scene.set_process(false)
	var c = scene.combat
	c.damaged.connect(func(kind, id, amount, attacker):
		var owner := -1
		if kind == "unit" and c.fighters.has(id): owner = int(c.fighters[id].owner)
		elif kind == "building" and scene.production.building(id) != null: owner = int(scene.production.building(id).owner)
		if owner != 0: return
		taken[kind] += int(amount)
		var by := int(c.fighters[attacker].owner) if c.fighters.has(attacker) else -1
		hits_by[by] = int(hits_by.get(by, 0)) + 1)
	print("probe: %s, %d sides, races %s, side 0 human" % [slug, sides, range(sides).map(func(i): return int(setup.players[i].race))])
	var steps := roundi(minutes * 60.0 * 40.0)
	var every_steps := roundi(every * 40.0)
	for i in steps:
		if scene.skirmish.over: break
		scene.simulation_step(0.025)
		if i % every_steps != every_steps - 1: continue
		var mine: Array = []
		for f in c.fighters.values():
			if int(f.owner) == 0 and c.alive(f): mine.append(scene.units[f.id].cell)
		for b in scene.production.buildings.values():
			if int(b.owner) == 0: mine.append(b.cell_rect().position)
		var line := "t=%4ds side0 objects %d, damage taken units %d buildings %d, hits by %s" % [roundi((i + 1) * 0.025), mine.size(), taken.unit, taken.building, hits_by]
		print(line)
		for p in scene.ai_manager.players:
			if p == null or not ("main_enemy" in p): continue
			var nearest := 9999
			for f in c.fighters.values():
				if int(f.owner) != int(p.me) or not c.alive(f): continue
				for cell in mine: nearest = mini(nearest, maxi(absi(cell.x - scene.units[f.id].cell.x), absi(cell.y - scene.units[f.id].cell.y)))
			print("   P%d main enemy %d, groups %s, nearest unit to side 0: %d cells" % [int(p.me), int(p.main_enemy),
				p.groups.map(func(g): return [int(g.kind), g.members.size(), g.launched, int(g.target_player)]), nearest])
	print("probe done: damage to side 0 units %d, buildings %d; hits by %s; over %s %s" % [taken.unit, taken.building, hits_by, scene.skirmish.over, scene.skirmish.outcome])
	quit(0)
