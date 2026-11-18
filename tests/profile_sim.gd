extends SceneTree
## Frame-time profile of a match (not part of -Check). Unlike profile_match.gd (a copy of an older simulation_step), this
## calls main.gd's own functions: the parts of simulation_step in its order, combat.update with the AI manager timed
## through Combat.pre_update, then the per-frame work of _physics_process (refresh_status) and _process. Every physics
## step slower than --spike-ms is printed with its three largest parts; every 60 s a summary of time per part. Headless:
## rendering and drawing are not measured.
##   Godot --headless --path . --script res://tests/profile_sim.gd -- --minutes=20 [--map=forest-lakes --map-races]
##     [--races=0,1] [--levels=6,6] [--human] [--spike-ms=8]
## --human makes side 0 the local human player (Desert Sands default: Knights human vs Knights computer, as profile_match).

const Setup = preload("res://simulation/skirmish_setup.gd")
const MapData = preload("res://core/map_data.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

var parts := {}
var clock := 0
var ai_detail := false          # --ai-detail: the AI manager pass replayed with each think step timed (a copy of ai_manager.gd
var combat_detail := false      # --combat-detail: Combat.update / _step replayed with each part timed (a copy of combat.gd)
var combat_parts := {}
var unit_detail := false        # --unit-detail: each unit.advance timed by the unit's state before the call (idle, planning,
var unit_parts := {}            # walking, dying), plus a probe: one extra update_sprite + queue_redraw per live unit, timed apart
var ai_steps := {}              # update / _pass and ai_player.gd think, same calls in the same order)

func _initialize():
	call_deferred("run")

func us() -> int:
	return Time.get_ticks_usec()

func mark(name: String):
	var now := us()
	parts[name] = int(parts.get(name, 0)) + now - clock
	clock = now

func run():
	var minutes := 4.0
	var slug := "desert-sands"
	var races: Array = []
	var levels: Array = [3, 6, 4, 5, 2, 2]
	var human := false
	var spike_ms := 8.0
	var inside_ms := 200.0        # P-4: steps over this print what they spent inside combat and the units (--inside-ms=)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="): minutes = float(arg.get_slice("=", 1))
		if arg.begins_with("--map="): slug = arg.get_slice("=", 1)
		if arg == "--map-races": races = ["map"]
		if arg.begins_with("--races="): races = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--levels="):
			var given: Array = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
			for i in given.size(): levels[i] = given[i]
		if arg == "--human": human = true
		if arg.begins_with("--spike-ms="): spike_ms = float(arg.get_slice("=", 1))
		if arg.begins_with("--inside-ms="): inside_ms = float(arg.get_slice("=", 1))
		if arg == "--ai-detail": ai_detail = true
		if arg == "--combat-detail": combat_detail = true
		if arg == "--unit-detail": unit_detail = true
	Settings.use_file("user://profile-settings.cfg")
	var store := Store.new("user://profile-heroes")
	store.save_profile(Profile.create("profile-knight", "c"))
	MapData.select(slug)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = MapData.map() if slug != "desert-sands" else JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	var sides := int(setup.sides)
	if races == ["map"]: races = range(sides).map(func(i): return int(setup.players[i].race))
	if races.is_empty(): for i in sides: races.append(0)
	for i in sides:
		Setup.set_race(setup, i, int(races[i]))
		Setup.set_kind(setup, i, Setup.COMPUTER, levels[i])
	if human:
		setup.players[0].kind = Setup.HUMAN
		setup.players[0].hero_id = "profile-knight"
	if not scene.start_skirmish(setup, "profile-knight" if human else "", store if human else null, "profile"):
		printerr("profile: the match did not start")
		quit(1)
		return
	scene.set_physics_process(false)
	scene.set_process(false)
	var ai_hook: Callable = scene.combat.pre_update
	scene.combat.pre_update = func(now_ms):
		var t := us()
		if ai_detail: timed_ai(scene, now_ms)
		else: ai_hook.call(now_ms)
		parts["ai_manager"] = int(parts.get("ai_manager", 0)) + us() - t
	print("profile: %s, %d sides, races %s, %s minutes, human %s" % [slug, sides, str(races), minutes, human])
	var dt := 1.0 / 60.0
	var steps := roundi(minutes * 60.0 / dt)
	var window := {}
	var window_max := 0.0
	var spikes := 0
	var all_steps := PackedFloat32Array()
	for i in steps:
		parts = {}
		# P-3: what a step over 200 ms spent inside combat, the units, the sector builds and the extent-2 layer
		var before_combat: Dictionary = combat_parts.duplicate()
		var before_units: Dictionary = unit_parts.duplicate()
		var before_nav := [scene.navigator.sector_build_us, scene.navigator.layer_build_us, scene.combat.search_us if scene.combat != null else 0]
		var t0 := us()
		clock = t0
		# main.gd simulation_step, part by part (same calls, same order)
		for object in scene.map_objects: object.advance(dt)
		preload("res://battle/map_object.gd").sync_states(scene.map_objects, scene.production, scene.encounters)
		mark("map_objects")
		if unit_detail: timed_units(scene, dt)
		else:
			for unit in scene.units: unit.advance(dt)
		scene.simulation_time += dt
		mark("units")
		if scene.combat != null:
			var now: int = scene.game_ms()
			if combat_detail: timed_combat(scene.combat, now)
			else: scene.combat.update(now)
			mark("combat")
			if scene.encounters != null: scene.encounters.update(now)
			mark("encounters")
			var moved := false
			while scene.fog_next_ms <= now:
				scene.visibility_update()
				scene.fog_next_ms += scene.Combat.UPDATE_MS
				moved = true
			mark("visibility")
			if moved:
				scene.apply_fog_to_nodes()
				mark("apply_fog")
				if scene.visibility.dirty: scene.refresh_fog_overlay()
				mark("fog_overlay")
		scene.update_race_powers()
		mark("race_powers")
		if scene.effects != null and scene.combat != null: scene.effects.sync(scene)
		if scene.map_effects != null: scene.map_effects.step(scene.game_ms())
		mark("effects")
		if scene.production != null:
			scene.economy.update(scene.game_ms())
			mark("economy")
			scene.production.update(scene.game_ms())
			mark("production")
			scene.resolve_pending_builds()
			mark("pending_builds")
			scene.unit_commands.update_repairs(scene.production, scene.game_ms())
			if not scene.unit_commands.garrison_orders.is_empty(): scene.resolve_garrison_orders()
			if not scene.site_orders.is_empty(): scene.resolve_site_orders()
			for node in scene.building_nodes.values(): node.queue_redraw()
			mark("orders")
		if scene.mines != null: scene.resolve_mine_orders()
		if not scene.patrols.is_empty() or not scene.guards.is_empty(): scene.update_patrols()
		if scene.navigator.improved and scene.combat != null and (not scene.assaults.is_empty() or not scene.attack_moves.is_empty()): scene.update_modern_orders()
		if scene.conversions != null: scene.conversions.update(scene.game_ms())
		mark("mines_conversions")
		if scene.skirmish != null and not scene.skirmish.over:
			scene.skirmish.frame()
			scene.refresh_hero_commands()
			scene.skirmish.update(scene.game_ms())
			scene.update_autosave()
		mark("skirmish")
		# the rest of _physics_process, then _process
		scene.refresh_status()
		mark("refresh_status")
		scene._process(dt)
		mark("process")
		var total := (us() - t0) / 1000.0
		all_steps.append(total)
		if parts.has("ai_manager"): parts["combat"] = int(parts.combat) - int(parts.ai_manager)   # combat without the AI
		for k in parts: window[k] = float(window.get(k, 0.0)) + parts[k] / 1000.0
		window_max = maxf(window_max, total)
		if total > spike_ms:
			spikes += 1
			if spikes <= 80 or total > inside_ms:
				var top: Array = parts.keys()
				top.sort_custom(func(a, b): return parts[a] > parts[b])
				print("spike t=%7.2fs %6.1f ms  %s" % [i * dt, total, ", ".join(top.slice(0, 3).map(func(k): return "%s %.1f" % [k, parts[k] / 1000.0]))])
				if total > inside_ms:
					print("  inside: %s; sectors %.1f ms, layer %.1f ms, search_rect %.1f ms" % [", ".join(_top_diff(combat_parts, before_combat) + _top_diff(unit_parts, before_units)),
						(scene.navigator.sector_build_us - before_nav[0]) / 1000.0, (scene.navigator.layer_build_us - before_nav[1]) / 1000.0,
						((scene.combat.search_us if scene.combat != null else 0) - before_nav[2]) / 1000.0])
		if i % roundi(60.0 / dt) == roundi(60.0 / dt) - 1:
			var keys: Array = window.keys()
			keys.sort_custom(func(a, b): return window[a] > window[b])
			print("t=%4ds units %d fighters %d  max step %.1f ms  ms per 60 s: %s" % [roundi((i + 1) * dt), scene.units.size(), scene.combat.fighters.size(), window_max,
				", ".join(keys.map(func(k): return "%s %.0f" % [k, window[k]]))])
			window = {}
			window_max = 0.0
		if scene.skirmish.over: break
	if OS.get_cmdline_user_args().has("--ai-bench"): ai_bench(scene)
	if OS.get_cmdline_user_args().has("--save-bench"): save_bench(scene)
	var sorted := all_steps.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	for v in sorted: sum += v
	if combat_detail:
		var ckeys: Array = combat_parts.keys()
		ckeys.sort_custom(func(a, b): return combat_parts[a] > combat_parts[b])
		print("combat parts, ms over the run: %s" % ", ".join(ckeys.map(func(k): return "%s %.0f" % [k, combat_parts[k] / 1000.0])))
	print("build_sectors: %d calls, %.0f ms" % [scene.navigator.sector_builds, scene.navigator.sector_build_us / 1000.0])
	print("extent-2 layer: %d builds, %.0f ms" % [scene.navigator.layer_builds, scene.navigator.layer_build_us / 1000.0])   # P-3
	print("search_rect: %d calls, %.0f ms" % [scene.combat.search_calls, scene.combat.search_us / 1000.0])   # P-3
	if unit_detail:
		var ukeys: Array = unit_parts.keys()
		ukeys.sort_custom(func(a, b): return unit_parts[a] > unit_parts[b])
		print("unit parts, ms over the run (calls): %s" % ", ".join(ukeys.map(func(k): return "%s %.0f" % [k, unit_parts[k] / 1000.0])))
	if ai_detail:
		var keys: Array = ai_steps.keys()
		keys.sort_custom(func(a, b): return ai_steps[a] > ai_steps[b])
		print("think steps, ms over the run: %s" % ", ".join(keys.map(func(k): return "%s %.0f" % [k, ai_steps[k] / 1000.0])))
	print("profile done: %d steps, mean %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.1f ms, %d steps over %.0f ms" % [n, sum / maxi(n, 1),
		sorted[int(n * 0.95)] if n > 0 else 0.0, sorted[int(n * 0.99)] if n > 0 else 0.0, sorted[n - 1] if n > 0 else 0.0, spikes, spike_ms])
	scene.queue_free()
	quit(0)

func timed_units(scene, dt: float):
	for unit in scene.units:
		var kind := "u_walk"
		if unit.inside_building or unit.removed: kind = "u_inside"
		elif unit.dying: kind = "u_dying"
		elif unit.orders.is_empty() and not unit.in_step and unit.wait_left <= 0.0: kind = "u_idle"
		elif not unit.orders.is_empty() and not unit.route_active and not unit.in_step: kind = "u_plan"
		var t := us()
		unit.advance(dt)
		var spent := us() - t
		unit_parts[kind] = int(unit_parts.get(kind, 0)) + spent
		unit_parts[kind + "_n"] = int(unit_parts.get(kind + "_n", 0)) + 1000
	var t2 := us()
	for unit in scene.units:
		if unit.inside_building or unit.removed or unit.dying: continue
		unit.update_sprite()
		unit.queue_redraw()
	var probe := us() - t2
	unit_parts["probe_sprite"] = int(unit_parts.get("probe_sprite", 0)) + probe
	clock += probe                                  # the probe is not counted in "units"

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
	if p.get("difficulty") == null:
		var t0 := us()
		p.think(now_ms)
		ai_steps["neutral"] = int(ai_steps.get("neutral", 0)) + us() - t0
		return
	if p.difficulty == R.PASSIVE or p.difficulty == R.RAMPANT: return
	if p.first_pass:
		p.first_pass = false
		p.home = p.world.skirmish.slots[p.me].start
	p.building_stopped = false
	var steps := {}
	var c := {"t": us()}
	var step = func(name):
		steps[name] = us() - int(c.t)
		c.t = us()
	p.refresh_cheats(); step.call("cheats")
	p.choose_main_enemy(); step.call("main_enemy")
	p.hero_retreat(); step.call("hero_retreat")
	p.base_defence(); step.call("base_defence")
	p.advance_tasks(now_ms); step.call("advance_tasks")
	p.recount(); step.call("recount")
	p.research_level = p._research_level("PIBX"); step.call("research")
	p.mine_census(); step.call("mine_census")
	p.plan_outpost(); step.call("outpost")
	p.desired_counts(); step.call("desired")
	p.build_want_list(); step.call("want_list")
	if p._improved(): p.army(now_ms)
	else: timed_army(p, now_ms, steps)
	step.call("army")
	if p.next_pace_ms == 0 or p.next_pace_ms < now_ms:
		p.next_pace_ms = now_ms + p.PACE_MS
		p.pace(); step.call("pace")
		p.keep_conversion(); step.call("keep_conversion")
	p.give_tasks(now_ms); step.call("give_tasks")
	if p.abilities != null: p.abilities.tick(now_ms)
	step.call("abilities")
	preload("res://simulation/ai_resignation.gd").after_think(p, p.world.skirmish)
	var total := 0
	for k in steps:
		if not String(k).begins_with("army."): total += steps[k]
		ai_steps[k] = int(ai_steps.get(k, 0)) + steps[k]
	if total > 15000:
		var keys: Array = steps.keys()
		keys.sort_custom(func(a, b): return steps[a] > steps[b])
		print("  think P%d %.1f ms at %d ms: %s" % [p.me, total / 1000.0, now_ms, ", ".join(keys.slice(0, 6).map(func(k): return "%s %.1f" % [k, steps[k] / 1000.0]))])

## ai_player.gd _army_faithful with its parts timed (same calls, same order); the parts go into `steps` as "army.*".
func timed_army(p, now_ms: int, steps: Dictionary):
	var Groups = p.Groups
	var clock := {"t": us()}
	var lap = func(name):
		steps[name] = int(steps.get(name, 0)) + us() - int(clock.t)
		clock.t = us()
	for g in p.groups.duplicate():
		if not g.has("slots"): p._faithful_record(g)
	var ctx: Dictionary = p._group_ctx()
	lap.call("army.ctx")
	var before := {}
	for g in p.groups: before[int(g.slot)] = bool(g.launched)
	var scene := {}
	for g in p.groups.duplicate():
		# _update_group
		if Groups.count(g) == 0:
			for id in g.slots.duplicate(): if int(id) != -1: Groups.leave(g, int(id))
			p.groups.erase(g)
			continue
		Groups.drop_dead(g, ctx)
		var pop: Dictionary = p.world.production.population(p.me)
		if int(pop.maximum) - 4 < int(pop.current) and not bool(g.launched): Groups.launch(g, ctx)
		Groups.march(g, p._target_info(g), ctx)
		lap.call("army.march")
		p._scene_rows(scene)
		lap.call("army.scene_rows")
		p._group_orders(g, ctx, scene)
		lap.call("army.group_orders")
	if not p.groups.is_empty():
		var tries := 0
		while Groups.by_slot(p.groups, p.group_cursor) == null and tries < Groups.GROUPS:
			p.group_cursor = (p.group_cursor + 1) % Groups.GROUPS
			tries += 1
		if tries < Groups.GROUPS:
			for g in p.groups.duplicate():
				if int(g.slot) != p.group_cursor and not Groups.has_hero(g, ctx) and int(g.mode) != 0: continue
				if bool(g.launched): p._plan_faithful(g)
			p.group_cursor = (p.group_cursor + 1) % Groups.GROUPS
	lap.call("army.plan")
	p._recruit(ctx)
	lap.call("army.recruit")
	Groups.pass_tail(p.groups, ctx)
	for g in p.groups:
		if bool(g.launched) and not bool(before.get(int(g.slot), false)):
			p.stats.launches += 1
			p.log.append({"t": now_ms, "launch": g.kind, "size": Groups.count(g), "player": g.target_player})
	lap.call("army.tail")

## P-4: where an autosave's time goes (main_save.gd save_document and save_game.gd write, part by part).
func save_bench(scene):
	var SaveGame = preload("res://simulation/save_game.gd")
	var MainScript = preload("res://battle/main.gd")
	SaveGame.errors.clear()
	var refs = SaveGame.Refs.new()
	var states := {}
	var parts: Array = []
	var t := us()
	for key in MainScript.SAVE_MODULES:
		var t1 := us()
		states[key] = scene._save.module_state(key, refs)
		parts.append([key, (us() - t1) / 1000.0])
	var capture_ms := (us() - t) / 1000.0
	parts.sort_custom(func(x, y): return x[1] > y[1])
	t = us()
	var modules := {}
	for key in states: modules[key] = SaveGame.encode(states[key])
	modules["refs"] = SaveGame.encode(refs.table)
	var encode_ms := (us() - t) / 1000.0
	t = us()
	var sums: Dictionary = SaveGame.checksums(modules)
	var sums_ms := (us() - t) / 1000.0
	t = us()
	var text := JSON.stringify({"modules": modules, "checksums": sums}, "	", false)
	var json_ms := (us() - t) / 1000.0
	t = us()
	var error: String = SaveGame.write("user://profile-save-bench.sav", {"modules": modules, "checksums": sums})
	var write_ms := (us() - t) / 1000.0
	t = us()
	scene._save.save_document()
	var whole_ms := (us() - t) / 1000.0
	print("SAVE BENCH: capture %.0f ms (%s), encode %.0f ms, checksums %.0f ms, stringify %.0f ms (%.1f MB), write incl. stringify %.0f ms %s; save_document %.0f ms" % [capture_ms,
		", ".join(parts.slice(0, 5).map(func(x): return "%s %.0f" % x)), encode_ms, sums_ms, json_ms, text.length() / 1048576.0, write_ms, error, whole_ms])

## P-4: single calls of the computer players' heavy parts at the end state (the calls draw random numbers and may give
## orders, so the match is not continued after them).
func ai_bench(scene):
	var time = func(call: Callable) -> float:
		var t := us()
		call.call()
		return (us() - t) / 1000.0
	for p in scene.ai_manager.players:
		if p == null or p.get("difficulty") == null or scene.skirmish.eliminated[p.me]: continue
		var w = p.world
		print("AI BENCH P%d race %d: %d units, %d groups, want %d" % [p.me, p.race, p.my_units().size(), p.groups.size(), p.want.size()])
		print("  recount %.2f  mine_census %.2f  outpost %.2f  desired %.2f  want_list %.2f  ctx %.2f" % [time.call(p.recount), time.call(p.mine_census),
			time.call(p.plan_outpost), time.call(p.desired_counts), time.call(p.build_want_list), time.call(p._group_ctx)])
		var by_kind := {}
		for g in p.groups:
			if not g.has("slots") or not bool(g.launched): continue
			var ms: float = time.call(func(): p._best_target(g))
			var k := "kind %d%s" % [int(g.kind), " (conversion)" if int(g.kind) == p.Groups.CONVERSION else ""]
			if not by_kind.has(k): by_kind[k] = []
			by_kind[k].append(ms)
		for k in by_kind: print("  _best_target %s: %s ms" % [k, ", ".join(by_kind[k].map(func(v): return "%.2f" % v))])
		print("  ai_targets(enemy %d) %.2f ms, %d entries; mines.census %.2f ms" % [p.main_enemy, time.call(func(): w.ai_targets(p.main_enemy)), w.ai_targets(p.main_enemy).size(),
			time.call(func(): w.mines.census(p.me))])
		var builder = null
		for u in p.my_units():
			if p.is_builder(u) and not u.inside_building: builder = u
		if builder == null: continue
		var sites: Array = []
		for id in w.production.construction_menu(p.me) + w.production.construction_menu(p.me, 1):
			var found := {"cell": Vector2i(-1, -1)}
			var ms: float = time.call(func(): found.cell = w.ai_site(p.me, id, p.home_centre(), builder))
			sites.append("%s %.1f%s" % [id, ms, "" if found.cell.x >= 0 else " (none)"])
		print("  ai_site: %s" % ", ".join(sites))
		print("  give_tasks %.2f ms" % time.call(func(): p.give_tasks(scene.game_ms())))

## The three largest growths of a part table since `before` (microsecond parts; "_n" call counts left out).
static func _top_diff(now_parts: Dictionary, before: Dictionary) -> Array:
	var grown := {}
	for k in now_parts:
		if String(k).ends_with("_n"): continue
		var d: int = int(now_parts[k]) - int(before.get(k, 0))
		if d > 1000: grown[k] = d
	var keys: Array = grown.keys()
	keys.sort_custom(func(a, b): return grown[a] > grown[b])
	return keys.slice(0, 3).map(func(k): return "%s %.1f" % [k, grown[k] / 1000.0])

func cpart(name: String, t: int) -> int:
	var now := us()
	combat_parts[name] = int(combat_parts.get(name, 0)) + now - t
	return now

func timed_combat(c, time_ms: int):
	while c.next_update_ms <= time_ms:
		c.now_ms = c.next_update_ms
		var t := us()
		if c.pre_update.is_valid(): c.pre_update.call(c.now_ms)
		t = cpart("ai_manager", t)
		c.ai.on_update(c.now_ms)
		t = cpart("unit_ai", t)
		c._update_towers()
		t = cpart("towers", t)
		var ids: Array = c.fighters.keys()
		ids.sort()
		for id in ids:
			var f = c.fighters[id]
			if f.removed: continue
			var t1 := us()
			var state: String = f.state
			match f.state:
				"dying": c._update_dying(f)
				"corpse": c._update_dying(f)
				"swing": c._update_swing(f)
				_: timed_active(c, f)
			t1 = cpart("f_" + state, t1)
			if f.hero and f.state != "dying" and f.state != "corpse":
				c._regenerate_hero(f)
				c._regenerate_mana(f)
			elif not f.hero and int(f.get("regen_ms", 0)) != 0 and c.now_ms > int(f.regen_ms) and f.state != "dying" and f.state != "corpse":
				c._regenerate_unit(f)
			if bool(f.get("poisoned", false)): c._poison(f)
			cpart("regen_poison", t1)
		t = us()
		if c.spells != null: c.spells.step()
		t = cpart("spells", t)
		c._update_missiles()
		t = cpart("missiles", t)
		for id in ids: c._animate(c.fighters[id])
		cpart("animate", t)
		c.next_update_ms += c.UPDATE_MS
	c.now_ms = time_ms

## combat.gd _update_active with its parts timed (a copy: same calls, same order).
func timed_active(c, f):
	var unit = c.units[f.id]
	if unit.inside_building: return
	if f.order == null:
		f.state = "idle"
		if f.resume != null: c._resume_attack_move(f, unit)
		return
	var order: Dictionary = f.order
	var t := us()
	if not c.target_alive(order) or (c.spells != null and c.spells.hidden_target(order)):
		f.order = null
		f.state = "idle"
		return
	t = cpart("a_alive", t)
	var distance: int = c.distance_to(f, order)
	t = cpart("a_distance_" + String(order.target_kind), t)
	if preload("res://simulation/combat_rules.gd").in_attack_range(distance, c.order_range(f, order)):
		if unit.in_step: return
		unit.stop()
		c._start_swing(f, order, distance)
		cpart("a_start_swing", t)
		return
	f.state = "approach"
	var goal: Vector2i = c.approach_cell(f, order)
	t = cpart("a_approach_cell_" + String(order.target_kind), t)
	if goal != order.planned_cell or (unit.orders.is_empty() and not unit.in_step):
		order["planned_cell"] = goal
		var target: Vector2 = c.navigator.center(goal)
		unit.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": unit.base_speed, "individual": true, "attack": true,
			"ai": bool(order.get("ai", false))}, "replace")
		cpart("a_give_order", t)
		combat_parts["a_orders_given"] = int(combat_parts.get("a_orders_given", 0)) + 1000
