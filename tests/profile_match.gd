extends SceneTree
## Frame-time profile of a human-vs-computer Knights match on Desert Sands (not part of -Check). Replays main.gd
## simulation_step part by part at 60 steps per second of match time and reports every step slower than SPIKE_MS with the
## parts that took the time, plus a per-30-second summary. Headless: rendering is not measured.
##   Godot --headless --path . --script res://tests/profile_match.gd -- --minutes=4

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const SPIKE_MS := 8.0

func _initialize():
	call_deferred("run")

var think_parts := {}
var probed := false

## One ai_site search with the time and pass count of each check (same loop as main.gd ai_site).
func probe_site(p):
	var w = p.world
	for id in w.production.construction_menu(p.me):
		var definition: Dictionary = w.production.rules.definition(id)
		var builder = null
		for u in p.my_units():
			if p.is_builder(u): builder = u
		var c := {"cells": 0, "placement": [0, 0], "margin": [0, 0], "can_place": [0, 0]}
		var found := Vector2i(-1, -1)
		for radius in range(4, 36, 2):
			for dy in range(-radius, radius + 1, 2):
				for dx in range(-radius, radius + 1, 2):
					if maxi(absi(dx), absi(dy)) != radius or found.x >= 0: continue
					var cell: Vector2i = p.home + Vector2i(dx, dy)
					if cell.x < 2 or cell.y < 2 or cell.x > w.collision.width - 3 or cell.y > w.collision.height - 3: continue
					c.cells += 1
					var t := us()
					var ok: bool = w.Placement.check(w.navigator, definition, cell, builder).ok
					c.placement[0] += us() - t; c.placement[1] += int(ok)
					if not ok: continue
					t = us()
					ok = w._clear_margin(definition, cell)
					c.margin[0] += us() - t; c.margin[1] += int(ok)
					if not ok: continue
					t = us()
					var answer: Dictionary = w.production.can_place(p.me, id, cell, builder)
					ok = answer.ok
					c.can_place[0] += us() - t; c.can_place[1] += int(ok)
					if not ok: c["reason"] = String(answer.get("reason", ""))
					if ok: found = cell
		print("  site %s: %d cells, found %s | placement %.1f ms (%d pass) | margin %.1f ms (%d pass) | can_place %.1f ms (%d pass)" % [id, c.cells, found,
			c.placement[0] / 1000.0, c.placement[1], c.margin[0] / 1000.0, c.margin[1], c.can_place[0] / 1000.0, c.can_place[1]] + " | " + String(c.get("reason", "")) + " | stock %s" % [w.economy.resources(p.me)])
var think_report: Array = []

## ai_manager.update / _pass with ai_player.think split into its steps (same calls, same order).
func timed_ai(scene, now_ms: int):
	var m = scene.ai_manager
	if m == null or scene.skirmish == null or scene.skirmish.over: return
	var UnitAI = preload("res://simulation/unit_ai.gd")
	while m.next_tick_ms <= now_ms:
		var tick_ms: int = m.next_tick_ms
		m.next_tick_ms += UnitAI.UI_TIMER_MS
		m.timer_ticks += 1
		if m.timer_ticks < UnitAI.PASS_TICKS: continue
		m.timer_ticks = 0
		m.calls += 1
		m.passes += 1
		for i in 7:
			m.slot = (m.slot + 1) % 7
			var p = m.players[m.slot]
			if p == null: continue
			if m.slot == 6 or not scene.skirmish.eliminated[m.slot]: think(p, tick_ms)
			break

func think(p, now_ms: int):
	var R = preload("res://simulation/ai_rules.gd")
	if p.get("difficulty") == null:            # the neutral player (slot 6) has its own think
		var t0 := us()
		p.think(now_ms)
		if us() - t0 > 20000: print("  neutral think %.1f ms at %d ms" % [(us() - t0) / 1000.0, now_ms])
		return
	if p.difficulty == R.PASSIVE or p.difficulty == R.RAMPANT: return
	if p.first_pass:
		p.first_pass = false
		p.home = p.world.skirmish.slots[p.me].start
	var steps := {}
	var clock := {"t": us()}
	var mark = func(name):
		steps[name] = us() - int(clock.t)
		clock.t = us()
	p.refresh_cheats(); mark.call("cheats")
	p.choose_main_enemy(); mark.call("main_enemy")
	p.hero_retreat(); mark.call("hero_retreat")
	p.base_defence(); mark.call("base_defence")
	p.advance_tasks(now_ms); mark.call("advance_tasks")
	p.recount(); mark.call("recount")
	p.research_level = p._research_level("PIBX"); mark.call("research")
	p.mine_census(); mark.call("mine_census")
	p.desired_counts(); mark.call("desired")
	p.build_want_list(); mark.call("want_list")
	p.army(now_ms); mark.call("army")
	if p.next_pace_ms == 0 or p.next_pace_ms < now_ms:
		p.next_pace_ms = now_ms + p.PACE_MS
		p.pace(); mark.call("pace")
		p.keep_conversion(); mark.call("keep_conversion")
	p.give_tasks(now_ms); mark.call("give_tasks")
	var total := 0
	for k in steps: total += steps[k]
	if total > 200000 and not probed:
		probed = true
		probe_site(p)
	if total > 20000:
		var keys: Array = steps.keys()
		keys.sort_custom(func(a, b): return steps[a] > steps[b])
		print("  think %.1f ms at %d ms: %s" % [total / 1000.0, now_ms, ", ".join(keys.slice(0, 3).map(func(k): return "%s %.1f" % [k, steps[k] / 1000.0]))])

func us() -> int:
	return Time.get_ticks_usec()

func run():
	var minutes := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="): minutes = float(arg.get_slice("=", 1))
	Settings.use_file("user://profile-settings.cfg")
	var store := Store.new("user://profile-heroes")
	store.save_profile(Profile.create("profile-knight", "c"))
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "profile-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 3)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "profile-knight", store, "profile")
	scene.set_physics_process(false)          # this script drives the steps
	scene.combat.pre_update = func(now_ms): timed_ai(scene, now_ms)
	var dt := 1.0 / 60.0
	var steps := roundi(minutes * 60.0 / dt)
	var window: Dictionary = {}
	var window_max := 0.0
	var spikes := 0
	for i in steps:
		var parts := {}
		var t0 := us()
		var t := t0
		for object in scene.map_objects: object.advance(dt)
		preload("res://battle/map_object.gd").sync_states(scene.map_objects, scene.production, scene.encounters)
		parts["map_objects"] = us() - t; t = us()
		for unit in scene.units: unit.advance(dt)
		scene.simulation_time += dt
		parts["units"] = us() - t; t = us()
		if scene.combat != null:
			var now: int = scene.game_ms()
			var c = scene.combat
			for k in ["c.ai_manager", "c.unit_ai", "c.towers", "c.fighters", "c.missiles"]: parts[k] = 0
			while c.next_update_ms <= now:
				c.now_ms = c.next_update_ms
				t = us()
				if c.pre_update.is_valid(): c.pre_update.call(c.now_ms)
				parts["c.ai_manager"] += us() - t; t = us()
				c.ai.on_update(c.now_ms)
				parts["c.unit_ai"] += us() - t; t = us()
				c._update_towers()
				parts["c.towers"] += us() - t; t = us()
				var ids: Array = c.fighters.keys()
				ids.sort()
				for id in ids:
					var f = c.fighters[id]
					if f.removed: continue
					match f.state:
						"dying": c._update_dying(f)
						"corpse": c._update_dying(f)
						"swing": c._update_swing(f)
						_: c._update_active(f)
					if f.hero and f.state != "dying" and f.state != "corpse":
						c._regenerate_hero(f)
						c._regenerate_mana(f)
				parts["c.fighters"] += us() - t; t = us()
				c._update_missiles()
				for id in ids: c._animate(c.fighters[id])
				parts["c.missiles"] += us() - t; t = us()
				c.next_update_ms += c.UPDATE_MS
			c.now_ms = now
			t = us()
			if scene.encounters != null: scene.encounters.update(now)
			parts["encounters"] = us() - t; t = us()
			var moved := false
			while scene.fog_next_ms <= now:
				scene.visibility_update()
				scene.fog_next_ms += scene.Combat.UPDATE_MS
				moved = true
			parts["visibility"] = us() - t; t = us()
			if moved:
				scene.apply_fog_to_nodes()
				if scene.visibility.dirty: scene.refresh_fog_overlay()
			parts["fog_draw"] = us() - t; t = us()
		if scene.effects != null and scene.combat != null: scene.effects.sync(scene)
		parts["effects"] = us() - t; t = us()
		if scene.production != null:
			scene.economy.update(scene.game_ms())
			parts["economy"] = us() - t; t = us()
			scene.production.update(scene.game_ms())
			scene.resolve_pending_builds()
			parts["production"] = us() - t; t = us()
			for node in scene.building_nodes.values(): node.queue_redraw()
		if scene.mines != null: scene.resolve_mine_orders()
		if not scene.patrols.is_empty() or not scene.guards.is_empty(): scene.update_patrols()
		if scene.conversions != null: scene.conversions.update(scene.game_ms())
		parts["mines_conversions"] = us() - t; t = us()
		if scene.skirmish != null and not scene.skirmish.over:
			scene.skirmish.frame()
			scene.refresh_hero_commands()
			scene.skirmish.update(scene.game_ms())
		parts["skirmish_ai"] = us() - t; t = us()
		scene.refresh_status()
		if scene.visibility != null and scene.visibility.dirty: scene.refresh_fog_overlay()
		parts["status_fog"] = us() - t
		var total := (us() - t0) / 1000.0
		for k in parts: window[k] = float(window.get(k, 0.0)) + parts[k] / 1000.0
		window_max = maxf(window_max, total)
		if total > SPIKE_MS:
			spikes += 1
			if spikes <= 60:
				var top: Array = parts.keys()
				top.sort_custom(func(a, b): return parts[a] > parts[b])
				print("spike t=%6.2fs %6.1f ms  %s" % [i * dt, total, ", ".join(top.slice(0, 3).map(func(k): return "%s %.1f" % [k, parts[k] / 1000.0]))])
		if i % roundi(30.0 / dt) == roundi(30.0 / dt) - 1:
			var keys: Array = window.keys()
			keys.sort_custom(func(a, b): return window[a] > window[b])
			print("t=%4ds units %d  max step %.1f ms  time per part (ms over 30 s): %s" % [roundi((i + 1) * dt), scene.units.size(), window_max,
				", ".join(keys.map(func(k): return "%s %.0f" % [k, window[k]]))])
			window = {}
			window_max = 0.0
		if scene.skirmish.over: break
	print("profile done: %d spikes over %d ms" % [spikes, SPIKE_MS])
	scene.queue_free()
	quit(0)
