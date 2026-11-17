extends SceneTree
## B1-7 (AI_RESEARCH.md section 18): captures the computer heroes' state of a Desert Sands soak (ai_soak.gd's set-up:
## `--races`, `--levels`, `--hero-class`, `--hero-level`) every 2 simulated seconds, keeping the samples with an enemy unit
## within 9 cells of the hero and every 15th other one (at most `--max`, default 120), as input for tools/emulate_ai_spells.py,
## which runs 0x503c60 on each. Every sample holds the world spec the emulator rebuilds (the hero, the units within 12
## cells, alliances, command, the hero's spell table, its costs, the generator state) and the port's own answer on that
## state: AiSpells.decide on a copy of the table with the live counts, costs and effect ends, the cast / potions recorded
## but not performed and the dice drawn from a copy of the generator (the match goes on unchanged).
## `--append` adds to the existing file. Not a -Check suite:
## `tools/run_guarded.ps1 -Script res://tests/capture_ai_spells.gd -QuitAfter 0 -UserArgs @('--races=2,2', ...)`.

const Setup = preload("res://simulation/skirmish_setup.gd")
const AiSpells = preload("res://simulation/ai_spells.gd")
const ComputerHero = preload("res://simulation/computer_hero.gd")
const Rng = preload("res://simulation/combat_rng.gd")
const OUT := "res://tests/ai_spell_state.json"
const REACH := 12

class DryEnv extends AiSpells.LiveEnv:
	var log: Array = []
	var dice
	func count(radius: int, relation: int, kinds: int, hp: int, extra: int, stop: int) -> int:
		var v := super.count(radius, relation, kinds, hp, extra, stop)
		log.append(["count", radius, relation, kinds, hp, extra, stop, v])
		return v
	func cost(spell: int) -> int:
		var v := super.cost(spell)
		log.append(["cost", spell, v])
		return v
	func effect_end(spell: int):
		var v = super.effect_end(spell)
		log.append(["effect", spell, v])
		return v
	func cast(spell: int) -> bool:
		log.append(["cast", spell, 1])
		return true
	func drink():
		log.append(["drink"])
	func drink_mana():
		log.append(["drink_mana"])
	func roll(sides: int, bonus: int) -> int:
		var v: int = dice.roll(1, sides, bonus)
		log.append(["roll", sides, AiSpells.Sign.s16(bonus), AiSpells.Sign.s16(v)])
		return v

func _initialize():
	call_deferred("run")

func run():
	var races: Array = [2, 2]
	var levels: Array = [6, 6]
	var classes: Array = []
	var hero_levels: Array = []
	var minutes := 10.0
	var most := 120
	var append := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--races="): races = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--levels="): levels = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--hero-class="): classes = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--hero-level="): hero_levels = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--minutes="): minutes = float(arg.get_slice("=", 1))
		if arg.begins_with("--max="): most = int(arg.get_slice("=", 1))
		if arg == "--append": append = true
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	for i in 2:
		Setup.set_race(setup, i, int(races[i]))
		Setup.set_kind(setup, i, Setup.COMPUTER, int(levels[i]))
	scene.start_skirmish(setup, "", null, "soak")
	for p in 2:
		var klass: int = int(classes[p]) if p < classes.size() else -1
		var level: int = int(hero_levels[p]) if p < hero_levels.size() else -1
		if klass < 0 and level <= 0: continue
		var inputs := {"player": p, "local": -1, "levels": [0, 0, 0, 0, 0, 0, 0], "active": range(7).map(func(i): return i < 2),
			"computer": range(7).map(func(i): return i < 2), "race": int(races[p]), "class_field": klass, "level_override": level}
		var bound = scene.combat.heroes[p].match
		bound.bind_computer(ComputerHero.create(scene.combat.rng, inputs), bound.entity, "Computer %d" % p)
		scene.refresh_hero_unit(bound)
		var f = scene.combat.fighters[bound.entity.entity_id]
		f.hp = int(f.max_hp)
		f.erase("max_mana")
		f.erase("mana")
	var samples: Array = []
	if append and FileAccess.file_exists(OUT):
		samples = JSON.parse_string(FileAccess.get_file_as_string(OUT)).samples
	var kept := 0
	var seen := 0
	var steps := roundi(minutes * 60.0 * 40.0)
	for i in steps:
		if scene.skirmish.over or kept >= most: break
		scene.simulation_step(0.025)
		if i % 80 != 0: continue
		for ai in scene.ai_manager.players:
			if ai == null or not ai.has_method("summary") or ai.abilities == null: continue
			var t = ai.abilities.hero_table(ai)
			var c = scene.combat
			if t == null or not c.heroes.has(ai.me): continue
			var f = c.fighters.get(c.heroes[ai.me].unit)
			if f == null or f.removed or not c.alive(f): continue
			seen += 1
			var s := sample(scene, ai, f, t, races)
			var enemy_near: bool = s.spec.units.any(func(u): return int(u.owner) != ai.me and not scene.skirmish.is_allied(ai.me, int(u.owner)) and \
				maxi(absi(int(u.cell[0]) - int(s.spec.hero.cell[0])), absi(int(u.cell[1]) - int(s.spec.hero.cell[1]))) <= 9)
			if enemy_near or seen % 15 == 0:
				samples.append(s)
				kept += 1
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 1, "source": "tests/capture_ai_spells.gd (Desert Sands, ai_soak.gd set-up)", "samples": samples}) + "\n")
	file.close()
	print("captured %d samples (%d total) races %s" % [kept, samples.size(), races])
	scene.end_skirmish()
	scene.free()
	quit(0)

func sample(scene, ai, f, t: Dictionary, races: Array) -> Dictionary:
	var c = scene.combat
	var sp = c.spells
	var now: int = ai.now()
	var cell: Vector2i = c.unit_cell(int(f.id))
	var m = c.heroes[ai.me].match
	var statuses: Array = []
	for s in f.get("statuses", []):
		if int(s.until) > now: statuses.append([int(s.get("art", -1)), int(s.until)])
	var hero := {"code": String(f.type_id), "owner": int(f.owner), "cell": [cell.x, cell.y], "hp": int(f.hp), "max_hp": int(f.max_hp),
		"pool": int(f.get("mana", 0)), "max_mana": int(f.get("max_mana", 0)), "potions": int(m.potions), "mana_potions": m.mana_potion_count(),
		"statuses": statuses}
	var units: Array = []
	for id in c.fighters:
		var u = c.fighters[id]
		if int(id) == int(f.id) or u.removed or u.state == "corpse": continue
		var uc: Vector2i = c.unit_cell(int(id))
		if maxi(absi(uc.x - cell.x), absi(uc.y - cell.y)) > REACH: continue
		var unit = scene.unit_by_id(int(id))
		if unit == null or unit.removed or unit.inside_building: continue
		units.append({"code": String(u.type_id), "owner": int(u.owner), "cell": [uc.x, uc.y], "hp": int(u.hp), "max_hp": int(u.max_hp),
			"poisoned": bool(u.get("poisoned", false)), "diseased": bool(u.get("diseased", false)), "dtype": int(u.stats.get("dtype", 0)), "hidden": u.has("invisible_until")})
	var allied: Array = []
	for a in 7:
		for b in 7:
			if a != b and scene.skirmish.is_allied(a, b): allied.append([a, b])
	var pop: Dictionary = scene.production.population(ai.me)
	var rows := AiSpells.to_rows(t)
	var costs := {}
	for s in rows.slots:
		if int(s) >= 0: costs[str(s)] = int(sp.cost(f, int(s)))
	var size: Vector2i = sp.map_size()
	var state: Array = c.rng.state()
	var spec := {"case": "captured", "now": now, "local": int(scene.production.local_player), "hero": hero, "units": units, "allied": allied,
		"command": [int(pop.current), int(pop.maximum)], "table": rows, "costs": costs, "rng": state, "map": [size.x, size.y]}
	# The port's answer on this state, without acting on the match.
	var copy := AiSpells.from_rows(rows)
	var env := DryEnv.new(ai, f, ai.abilities)
	env.dice = Rng.new(int(state[0]), int(state[1]))
	var result: bool = AiSpells.decide(copy, env)
	return {"spec": spec, "source": "races %s P%d t=%d" % [races, ai.me, now / 1000],
		"port": {"calls": env.log, "result": result, "table": AiSpells.to_rows(copy), "rng": env.dice.state()}}
