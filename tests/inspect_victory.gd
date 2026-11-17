extends SceneTree
## Diagnostic (not part of -Check): loads a copy of a save and lists, per active side, what keeps it in the match for
## Standard Victory (skirmish_match.gd counts_for: units and defeat-stopping buildings), then runs --seconds and reports
## the victory state.
##   Godot --headless --path . --script res://tests/inspect_victory.gd -- --save=<path> --heroes=user://inspect-heroes [--seconds=10]

func _initialize():
	call_deferred("run")

func run():
	var path := ""
	var heroes := "user://inspect-heroes"
	var seconds := 10.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.get_slice("=", 1)
		if arg.begins_with("--heroes="): heroes = arg.get_slice("=", 1)
		if arg.begins_with("--seconds="): seconds = float(arg.get_slice("=", 1))
	var Main = load("res://battle/main.gd")
	var error: String = Main.prepare_saved_game(path, heroes, "user://inspect-saves-run")
	if error != "":
		print("inspect: refused: " + error)
		quit(1)
		return
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	scene.set_physics_process(false)
	scene.set_process(false)
	var s = scene.skirmish
	var c = scene.combat
	print("inspect: local %d, time %d s, over %s, game_over %s, victory option %s, standard_victory_event %s" % [s.local, s.elapsed_ms() / 1000, s.over, s.game_over,
		s.options.get("victory", 0), s.resolved.get("standard_victory_event", "?")])
	for p in 6:
		if not s.active(p): continue
		print("side %d race %d eliminated %s counts %s allied-with-local %s" % [p, s.race(p), s.eliminated[p], s.counts_for(p), s.is_allied(s.local, p)])
		var shown := 0
		for f in c.fighters.values():
			if int(f.get("list", f.owner)) != p or f.removed: continue
			var counts: bool = f.hero or (int(f.hp) >= 1 and f.state != "dying" and f.state != "corpse" and int(f.owner) != 6 and s.is_allied(p, int(f.owner)) and not f.get("flag_30", false))
			if not counts: continue
			if shown < 12:
				var unit = scene.unit_by_id(int(f.id))
				print("   unit %d %s hp %d state %s hero %s cell %s inside %s removed-node %s visible %s" % [int(f.id), f.type_id, int(f.hp), f.state, f.hero,
					c.unit_cell(int(f.id)), unit.inside_building if unit != null else "?", unit.removed if unit != null else "?", unit.visible if unit != null else "?"])
			shown += 1
		if shown > 12: print("   ... %d counting units in all" % shown)
		for b in scene.production.buildings.values():
			if int(b.owner) != p: continue
			var sides: Array = s.stop_defeat.get(b.original_type_id, [])
			if s.race(p) < sides.size() and bool(sides[s.race(p)]):
				print("   building %d %s hp %d at %d,%d" % [int(b.entity_id), b.original_type_id, int(b.hit_points), int(b.left), int(b.top)])
	for uid in scene.production.units:
		var pu: Dictionary = scene.production.units[uid]
		if int(pu.owner) == 1:
			var ff = c.fighters.get(int(uid))
			var nn = scene.unit_by_id(int(uid))
			print("   pop unit %s %s fighter %s hp %s state %s removed %s node-removed %s inside %s" % [uid, pu.type, ff != null, ff.hp if ff != null else "-", ff.state if ff != null else "-",
				ff.removed if ff != null else "-", nn.removed if nn != null else "-", nn.inside_building if nn != null else "-"])
	var Resign = load("res://simulation/ai_resignation.gd")
	for ai in scene.ai_manager.players:
		if ai == null or not ai.get("me") is int or int(ai.me) > 5: continue
		var t: Dictionary = Resign.table(s, scene)
		print("resign test side %d difficulty %s: %s (hero %s pop %s limit %s; ai_resign option %s)" % [ai.me, ai.get("difficulty"), Resign.should_resign(ai.me, t),
			t.hero, t.population, t.limit, s.options.get("ai_resign", "missing")])
	for i in roundi(seconds * 40.0): scene.simulation_step(0.025)
	print("inspect: after %.0f s over %s outcome %s log %s" % [seconds, s.over, s.outcome, s.log.slice(-5)])
	quit(0)
