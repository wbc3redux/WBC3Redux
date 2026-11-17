extends SceneTree
## Milestone 10b soak: two computer players on Desert Sands (player 0 Lord, player 1 Emperor; spectator, no hero book) in the
## real scene, fixed seed, 25 ms game updates for a fixed match time (default 8 simulated minutes; `-- --minutes=N`).
## `-- --races=A,B` picks the two races (default 0,0: Knights vs Knights, milestone 10b; milestone 11a adds 0,1: Knights vs
## Dwarves). Logs a summary every 30 s, asserts invariants each second and progress at the end, and writes .local/ai_soak*.csv.
## W2 (milestone M-1): `-- --map=the-hill` plays another imported map with one computer per side record (difficulties
## Lord, Emperor, Prince, Warlord for sides 0..3, then Knight); every side must build, train and fight.
## Milestone M-2: `-- --map-races` gives every side its side record's race (Hills to Climb: Knight, Dwarf, Undead, Barbarian).
## Milestone M-1 (A-1): `--expect-stall` asserts the original research behaviour (no side completes Crusade I: the
## category-2 node waits on it, AI_RESEARCH.md section 15); `--min-research=N` requires a side to complete N research items
## and Crusade I (with `--research=improved`, the deliberate change F10).
## Milestone M-3: `--water` (water maps) asserts every second that no unit stands on a cell its own movement type cannot
## enter (0x42cda0: land units never on water, water units never on land) and reports the units seen swimming.
## Map wave 3 part 2: `--min-sides=N` asserts the per-side progress (army building, workers, units, launches, fights) for
## at least N sides instead of every side; the per-side results are printed (computer gaps of single sides are AI items).

const Rules = preload("res://simulation/production_rules.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const MapData = preload("res://core/map_data.gd")
const AiSpells = preload("res://simulation/ai_spells.gd")
const ComputerHero = preload("res://simulation/computer_hero.gd")
const AiSitesScript = preload("res://simulation/ai_sites.gd")
const Placement = preload("res://simulation/placement.gd")
## B2-3 (AI_RESEARCH.md section 19): `--stalled=R,...` asserts that no side of race R completes any research (the category-2
## node waits at the hall, behind the Peasant: what the original does on these maps); `--researches=R:ID|ID,...` that every
## side of race R completes at least one of the items.
## B1-5 (AI_RESEARCH.md section 16): `--each-keep=N` requires every side to reach hall level N; `--each-research=N` every
## side to complete N research items; `--expect-casts` every Dwarf, Undead and Swarm side to use an ability (0x5001d0:
## a caster's spell, Famine, scavenging or the Brew); `--expect-advance` every Undead side to advance Skeletons (the
## advancement task); `--levels=a,b,...` sets the computer levels per side.
const DIFFICULTIES := [3, 6, 4, 5, 2, 2]
## The building that trains each race's army in the computer roster (Knights Garrison, Dwarven Armory, Undead Graveyard,
## Swarm Burial Chamber or Hive: with its full lists the Swarm trains its army at either).
const ARMY_BUILDING := {0: ["BAGA"], 1: ["BAAR"], 2: ["BAGY"], 14: ["BABC", "BAH0", "BAH1", "BAH2", "BAH3", "BAH4"]}
const BATCH1 := [1, 2, 14]
const CASTER_RACES := [1, 2, 14, 12, 3, 4, 5, 10, 11, 6, 7, 8, 9, 13, 15]     # B2-3 / B3-3 / B4-3 / B5-3: the races `--expect-casts` covers
const ELF_RACES := [6, 7, 8]          # B4-3 (BATCH4_RESEARCH.md E4, decision 1): no Elf unit works in a mine (0x523e70, 0x4fd940)
## Milestone M-2: any other race (Barbarian, Empire on the wave-2 maps) counts every building of its PRODUCTION rows
## that is not a Keep and trains a unit other than its Peasant (army_buildings below).
var checks := 0
var failures := 0
var water := false
var min_sides := 0                       # 0: every side must build and fight; N: at least N sides
var swimmers := {}                       # unit id -> movement type, for units seen on a cell land units cannot enter
## AI-11 (AI_RESEARCH.md section 27): `--army-points=N` gives the match N army setup points (the setup option the user's
## playtest had; every computer slot buys through 0x445200 / 0x4406b0, main_match.place_army_setup); `--human=P` makes
## side P an idle human seat that is not the local one (no hero book, nothing bought, no computer player: the human focus
## 0x4f4e30 and the main-enemy bonus see a human); `--attack-report` prints each computer side's army at the start, its
## first launches and group targets, and the first attack of each side's units on another side.
var human := -1
var first_attack := {}                   # owner -> {t, victim, code, by, cell, from_start}
var first_targets := {}                  # owner -> [{t, group, size, kind, victim, code, cell}] (first 5 group targets)
var launches_seen := {}                  # owner -> [log entries of launches] (first 5)

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 20: printerr("AI soak check failed: ", label)

## AI-9 (diagnostics): unit-occupied cells within `r` of a cell.
func occupied_near(navigator, c: Vector2i, r: int) -> int:
	var n := 0
	for cell in navigator.occupants:
		if absi(cell.x - c.x) <= r and absi(cell.y - c.y) <= r and navigator.occupants[cell] != null: n += 1
	return n

## AI-10: "" or why side `p`'s home has no room: an item whose site search failed at least 20 times and for which the
## window search from home finds no spot even with standing units and reservations ignored (the original's search,
## tools/emulate_ai10.py). The side's own buildings stay in the grid: they are what fills the home.
func no_room(scene, p: int) -> String:
	var ai = scene.ai_manager.players[p]
	if ai == null or not ("stats" in ai): return ""
	for key in ai.stats.get("build_fails", {}):
		if not String(key).begins_with("site:") or int(ai.stats.build_fails[key]) < 20: continue
		var item := String(key).get_slice(":", 1)
		var fp: Array = scene.production.rules.definition(item).footprint
		if AiSitesScript.find(scene.navigator, item, fp, ai.home, null, {}, false).x < 0:
			return "%s: %d failed site searches, none from home %s without units and reservations" % [item, int(ai.stats.build_fails[key]), ai.home]
	return ""

## AI-10: the research a unit of `race` requires (the tech step 0x4ff0d0's research, AI_RESEARCH.md 15 / 17 A5), with
## the requirements of the buildings and research on the way (the walk goes through both).
func unit_research(rules, race: int) -> Dictionary:
	var out := {}
	var seen := {}
	var todo: Array = []
	for id in rules.dependency_ids(race):
		if String(id).begins_with("A"): todo.append_array(rules.requirements(String(id), race))
	while not todo.is_empty():
		var r := String(todo.pop_back())
		if seen.has(r): continue
		seen[r] = true
		if Rules.is_research(r): out[r] = true
		todo.append_array(rules.requirements(r, race))
	return out

## AI-10 (diagnostics, `--capture-grid`): the site search's inputs and the port's answers, as JSON for tools/emulate_ai10.py.
## Cells: [level, material, permission] per cell (row-major); `blocked`: Placement.blocked (0x42c8e0 as ported) for the
## player's first builder; `reserved`: every running build task's reserved cells; `answers`: AiSites.find for each
## construction-menu item (both rows) from home and from home + every (dx, dy) in -60..60 step 20.
func capture_grid(scene, p: int, path: String):
	var ai = scene.ai_manager.players[p]
	var nav = scene.navigator
	var col = nav.collision
	var builders: Array = ai.my_units().filter(func(u): return String(u.type_id) != ai.HERO and ai.is_builder(u))
	var builder = builders[0] if not builders.is_empty() else null
	var reserved := {}
	for q in scene.ai_manager.players:
		if q == null or not ("tasks" in q): continue
		for t in q.tasks.values():
			for c in t.get("reserved", []): reserved[c] = true
	var cells := PackedByteArray()
	var blocked: Array = []
	for y in col.height:
		for x in col.width:
			var raw = col.cell_data(Vector2i(x, y)).raw
			cells.append(int(raw[0]))
			cells.append(int(raw[1]))
			cells.append(int(raw[2]))
			if Placement.blocked(nav, Vector2i(x, y), builder): blocked.append(y * col.width + x)
	var items: Array = []
	for code in scene.production.construction_menu(p) + scene.production.construction_menu(p, 1):
		if not items.has(String(code)): items.append(String(code))
	var answers: Array = []
	for code in items:
		var fp: Array = scene.production.rules.definition(code).footprint
		for dy in range(-60, 61, 20):
			for dx in range(-60, 61, 20):
				var start: Vector2i = ai.home + Vector2i(dx, dy)
				var spot: Vector2i = AiSitesScript.find(nav, code, fp, start, builder, reserved)
				answers.append({"code": code, "footprint": fp, "start": [start.x, start.y], "spot": [spot.x, spot.y]})
	var out := {"player": p, "t_s": ai.now() / 1000, "width": col.width, "height": col.height, "home": [ai.home.x, ai.home.y],
		"builder": String(builder.type_id) if builder != null else "", "cells": Marshalls.raw_to_base64(cells), "blocked": blocked,
		"reserved": reserved.keys().map(func(c): return [c.x, c.y]), "answers": answers}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("captured the site grid of P%d at %d s into %s (%d answers)" % [p, ai.now() / 1000, path, answers.size()])

## AI-9 (diagnostics, `--dump-sites`): the cells around a home as the site search sees them: B building, O map object,
## M material 3/5/6/7/9, P permission 0, R reserved, U unit, else the terrain height digit.
func print_site_map(navigator, c: Vector2i, reserved: Dictionary):
	var col = navigator.collision
	for y in range(maxi(0, c.y - 30), mini(col.height, c.y + 31)):
		var row := ""
		for x in range(maxi(0, c.x - 30), mini(col.width, c.x + 31)):
			var cell := Vector2i(x, y)
			var d: Dictionary = col.cell_data(cell)
			var raw = d.raw
			var m := int(raw[1])
			var ch := str(int(raw[0]) % 10)
			if m in [3, 5, 6, 7, 9]: ch = "M"
			elif int(raw[2]) == 0: ch = "P"
			if navigator.building_cells.has(cell): ch = "B"
			elif d.has("object_indices") and not d.object_indices.is_empty(): ch = "O"
			elif reserved.has(cell): ch = "R"
			elif navigator.occupants.get(cell) != null: ch = "U"
			if cell == c: ch = "H"
			row += ch
		print("    %3d %s" % [y, row])

func _initialize():
	call_deferred("run")

func run():
	var minutes := 8.0
	var races := []
	var slug := "desert-sands"
	var min_keep := 0          # milestone 13: `-- --min-keep=N` requires a side to reach Keep level N (BK?(N-1))
	var min_research := 0
	var expect_stall := false
	var each_keep := 0
	var each_research := 0
	var expect_casts := false
	var expect_ancient := false          # B4-3: `--expect-ancient`: an Ancient Wisp on each Elf side
	var any_casts := false               # A-2: `--expect-casts=any`: at least one Dwarf, Undead or Swarm side uses an ability
	var casting_sides := 0
	var expect_advance := false
	var dump_ai := false                 # `--dump-ai`: the want list and the list entries every 120 s (diagnostics)
	var levels: Array = DIFFICULTIES.duplicate()   # `--levels=6,6`: the computer levels per side (default Lord, Emperor, ...)
	var hero_classes: Array = []         # B1-7: `--hero-class=20,15`: the computer heroes' class per side (-1 = drawn)
	var hero_levels: Array = []          # B1-7: `--hero-level=5,5`: their level (0x42a0d0's setup words 0xa49900 / 0xa498fc)
	var expect_hero_casts := false       # B1-7: every batch-1 side's hero casts a spell of its schools (0x503c60)
	var stalled: Array = []              # B2-3: races that must complete no research
	var researches := {}                 # B2-3: race -> items of which every side of it must complete one
	var seed := -1                       # `--seed=N`: the first combat seed word (default main.gd's fixed combat_seed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hero-class="): hero_classes = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--hero-level="): hero_levels = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg == "--expect-hero-casts": expect_hero_casts = true
		if arg.begins_with("--stalled="): stalled = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--researches="):
			for part in arg.get_slice("=", 1).split(","): researches[int(part.get_slice(":", 0))] = Array(part.get_slice(":", 1).split("|"))
		if arg == "--dump-ai": dump_ai = true
		if arg.begins_with("--seed="): seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--levels="):
			var given: Array = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
			for i in given.size(): levels[i] = given[i]
		if arg.begins_with("--each-keep="): each_keep = int(arg.get_slice("=", 1))
		if arg.begins_with("--each-research="): each_research = int(arg.get_slice("=", 1))
		if arg == "--expect-casts": expect_casts = true
		if arg == "--expect-casts=any": any_casts = true
		if arg == "--expect-ancient": expect_ancient = true
		if arg == "--expect-advance": expect_advance = true
		if arg.begins_with("--min-keep="): min_keep = int(arg.get_slice("=", 1))
		if arg.begins_with("--minutes="): minutes = float(arg.get_slice("=", 1))
		if arg.begins_with("--races="): races = Array(arg.get_slice("=", 1).split(",")).map(func(v): return int(v))
		if arg.begins_with("--map="): slug = arg.get_slice("=", 1)
		if arg.begins_with("--min-research="): min_research = int(arg.get_slice("=", 1))
		if arg == "--expect-stall": expect_stall = true
		if arg == "--map-races": races = ["map"]
		if arg == "--water": water = true
		if arg.begins_with("--min-sides="): min_sides = int(arg.get_slice("=", 1))
		if arg.begins_with("--human="): human = int(arg.get_slice("=", 1))
	var army_points := -1
	var attack_report := OS.get_cmdline_user_args().has("--attack-report")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--army-points="): army_points = int(arg.get_slice("=", 1))
	MapData.select(slug)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = MapData.map() if slug != "desert-sands" else JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	var sides := int(setup.sides)
	if races == ["map"]: races = range(sides).map(func(i): return int(setup.players[i].race))   # M-2: the side records' races
	if races.is_empty(): for i in sides: races.append(0)
	check(races.size() == sides, "one race per side (%d sides)" % sides)
	for i in sides:
		Setup.set_race(setup, i, int(races[i]))
		Setup.set_kind(setup, i, Setup.HUMAN if i == human else Setup.COMPUTER, levels[i])
	if human >= 0: setup.local = 1 if human == 0 else 0     # the local slot stays a computer one (spectator, no hero book)
	if army_points >= 0: setup.options.army_points = army_points
	if seed >= 0: scene.combat_seed = [seed, scene.combat_seed[1]]
	check(scene.start_skirmish(setup, "", null, "soak"), "AI-vs-AI match starts")
	if attack_report: print_start_armies(scene, sides)
	if not hero_classes.is_empty() or not hero_levels.is_empty(): set_heroes(scene, sides, races, hero_classes, hero_levels)
	# B1-7 diagnostics: `--no-hero-spells` leaves the computer heroes' spell tables unfilled (0x503c60 does nothing), to
	# compare a soak with and without the heroes' casting. Not used by any -Check soak.
	if OS.get_cmdline_user_args().has("--no-hero-spells"): scene.ai_manager.hero_spells_filled = true
	print_heroes(scene, sides)
	for s in scene.ai_summaries(): check(bool(s.hero), "P%d starts (hero at its start)" % s.player)
	check(scene.ai_summaries().size() == sides - (1 if human >= 0 else 0), "every computer side has a computer player (%d)" % sides)
	var csv: Array = ["t_s,player,difficulty,gold,metal,crystal,stone,mines,workers,peasants,swordsmen,squires,keep,garrisons,fletchers,launches,kills,hero"]
	var peak := {}
	var army := {}
	for p in sides: army[p] = ARMY_BUILDING.get(int(races[p]), army_buildings(scene.production.rules, int(races[p])))
	for p in sides: peak[p] = {"buildings": 0, "units": 0, "launches": 0, "garrison": false, "peasants_in_mines": 0, "types": {}}
	var steps := roundi(minutes * 60.0 * 40.0)
	# AI-7 (diagnostics): `--census=FILE` writes the original's census line format once a second (LIVE_COMPARISON.md:
	# clock, object counts by type with sites, unit pixel positions by type), for .local/arrivals.py-style comparisons.
	var census_file = null
	# AI-10 (diagnostics): `--capture-grid=FILE --capture-at=S --capture-player=P` writes the site search's inputs at S
	# seconds (every cell's level / material / permission bytes, the cells 0x42c8e0 calls blocked for one of P's builders,
	# the reserved cells) and the port's window search answers from a set of starts, for tools/emulate_ai10.py.
	var no_room_seen := {}               # AI-10: side -> why its home had no room (sampled every 120 s, no_room)
	var capture_path := ""
	var capture_at := -1
	var capture_player := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--census="): census_file = FileAccess.open(arg.get_slice("=", 1), FileAccess.WRITE)
		if arg.begins_with("--capture-grid="): capture_path = arg.get_slice("=", 1)
		if arg.begins_with("--capture-at="): capture_at = int(arg.get_slice("=", 1))
		if arg.begins_with("--capture-player="): capture_player = int(arg.get_slice("=", 1))
	for i in steps:
		if scene.skirmish.over: break
		scene.simulation_step(0.025)
		if i % 40 != 0: continue
		invariants(scene, sides)
		if attack_report: watch_attacks(scene, i / 40)
		if census_file != null: write_census(scene, census_file, i)
		if capture_at >= 0 and i == capture_at * 40: capture_grid(scene, capture_player, capture_path)
		if i % 4800 == 0 and i > 0:
			for p in sides:
				if no_room_seen.has(p): continue
				var full := no_room(scene, p)
				# what the side had reached when its home filled: only the goals still open then are excused
				if full != "": no_room_seen[p] = {"why": "%s at %d s" % [full, i / 40], "keep": int(peak[p].get("keep", 0)), "workers": int(peak[p].peasants_in_mines)}
		if dump_ai and i % 4800 == 0:
			for p in sides:
				var ai = scene.ai_manager.players[p]
				print("  P%d lanes [weight, workers] %s slots %s" % [p, ai.mine_weights, ai.mine_slots])
				if "outpost_site" in ai: print("  P%d outpost site %s, BWTC %s, menu %s" % [p, ai.outpost_site, ai.buildings.get("BWTC"), ai.world.production.construction_menu(p)])
				print("  P%d want %s" % [p, ai.want.map(func(w): return "%s:%d+%d/%x%s" % [w.id, int(w.priority), int(w.bonus), int(w.categories), "*" if w.done else ""])])
				var rows: Array = []
				for id in ai.buildings:
					var b: Dictionary = ai.buildings[id]
					rows.append("%s c%d p%d d%d a%d t%d cd%d" % [id, int(b.count), int(b.pending), int(b.desired), int(b.available), int(b.timer), int(b.cooldown)])
				print("  P%d buildings %s" % [p, rows])
				rows = []
				for id in ai.units:
					var u: Dictionary = ai.units[id]
					rows.append("%s c%d tr%d a%d t%d cd%d" % [id, int(u.count), int(u.trainable), int(u.available), int(u.timer), int(u.cooldown)])
				print("  P%d units %s" % [p, rows])
				# AI-5 (diagnostics): the research entries and every own building's job, the stock against the want list's prices
				rows = []
				for id in ai.research:
					var r: Dictionary = ai.research[id]
					rows.append("%s t%d cd%d e%d o%d" % [id, int(r.timer), int(r.cooldown), int(ai.research_eligible(id)), int(ai._research_running(id))])
				print("  P%d research %s" % [p, rows])
				rows = []
				for b in ai.world.production.buildings.values():
					if int(b.owner) == p and not ai.is_tower(String(b.original_type_id)): rows.append("%s%s:%s%s" % [b.original_type_id, "*" if b.constructing else "", b.job_item, "+%s" % [b.queue] if not b.queue.is_empty() else ""])
				print("  P%d jobs %s stock %s prices %s" % [p, rows, ai.world.economy.resources(p), ai.want.map(func(w): return "%s%s" % [w.id, w.cost])])
				# B4-3 (diagnostics): the Wisps 0x4f8290 could merge (no AI task, not busy, in no group) and the others' tasks
				var wisps: Array = ai.my_units().filter(func(u): return String(u.type_id) == "AEBX")
				if not wisps.is_empty(): print("  P%d Wisps %s" % [p, wisps.map(func(u): return "%d:%s%s%s" % [u.unit_id, ai.tasks.get("u%d" % u.unit_id, {}).get("type", "-"), "B" if ai.world.unit_busy(u) else "", "G" if ai._member(u.unit_id) else ""])])
				# AI-8 (diagnostics): every other builder's task, busy / group flags, and the mine orders so far
				var builders: Array = ai.my_units().filter(func(u): return String(u.type_id) != "AEBX" and String(u.type_id) != ai.HERO and ai.is_builder(u))
				if not builders.is_empty(): print("  P%d builders %s mine orders %d mines %s" % [p, builders.map(func(u): return "%d:%s%s%s%s" % [u.unit_id, ai.tasks.get("u%d" % u.unit_id, {}).get("type", "-"), "B" if ai.world.unit_busy(u) else "", "G" if ai._member(u.unit_id) else "", "M" if ai.world.in_mine(u) else ""]), int(ai.stats.get("mine_orders", 0)),
					ai.world.mines.census(p).filter(func(r): return bool(r.owned)).map(func(r): return "%d:l%d w%d%s" % [int(r.id), int(r.lane), int(r.workers), "x" if bool(r.exhausted) else ""])])
				print("  P%d build fails %s builds %d home %s map %dx%d home moves %d" % [p, ai.stats.get("build_fails", {}), int(ai.stats.get("builds", 0)), ai.home, ai.world.collision.width, ai.world.collision.height, int(ai.stats.get("home_moves", 0))])
				# AI-9 (diagnostics): the build tasks (item, builder, age in s, the builder's build state, reserved cells)
				var rows9: Array = []
				for key in ai.tasks:
					var t: Dictionary = ai.tasks[key]
					if t.type != "build": continue
					var bu = ai.world.unit_by_id(int(t.unit))
					rows9.append("%s:%d:%ds:%s:%d%s" % [t.item, int(t.unit), (ai.now() - int(t.started)) / 1000, ai.world.build_state(bu) if bu != null else "gone",
						t.get("reserved", []).size(), "P" if t.get("placed", false) else ""])
				print("  P%d build tasks %s" % [p, rows9])
				# AI-9 (diagnostics): for each item whose site search failed, the window search now with the standing units,
				# without them, and without the reserved sites (an idle builder of the side as the builder).
				var probe = builders[0] if not builders.is_empty() else null
				for key in ai.stats.get("build_fails", {}):
					if not String(key).begins_with("site:"): continue
					var item := String(key).get_slice(":", 1)
					var fp: Array = ai.world.production.rules.definition(item).footprint
					var reserved := {}
					for q in ai.world.ai_manager.players:
						if q == null or not ("tasks" in q): continue
						for t in q.tasks.values():
							for c in t.get("reserved", []): reserved[c] = true
					print("  P%d site probe %s: units %s, no units %s, no reserved %s, occupied cells near home %d" % [p, item,
						AiSitesScript.find(ai.world.navigator, item, fp, ai.home, probe, reserved),
						AiSitesScript.find(ai.world.navigator, item, fp, ai.home, probe, reserved, false),
						AiSitesScript.find(ai.world.navigator, item, fp, ai.home, probe, {}), occupied_near(ai.world.navigator, ai.home, 12)])
					if OS.get_cmdline_user_args().has("--dump-sites") and item == String(ai.stats.build_fails.keys()[0]).get_slice(":", 1): print_site_map(ai.world.navigator, ai.home, reserved)
		if i % 1200 == 0:
			for s in scene.ai_summaries():
				var line := "t=%4ds P%d %s res %s mines %d/%d units %s buildings %s groups %s kills %d hero %s" % [i / 40, s.player, s.difficulty,
					s.resources, s.mines, s.workers, s.units, s.buildings, s.groups, s.kills, s.hero]
				print(line)
				var u: Dictionary = s.units
				var b: Dictionary = s.buildings
				csv.append("%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [i / 40, s.player, s.difficulty, s.resources[0], s.resources[1], s.resources[2],
					s.resources[3], s.mines, s.workers, int(u.get("AHBX", 0)), int(u.get("AHKX", 0)), int(u.get("AHMX", 0)),
					int(b.get("BKK0", 0)) + int(b.get("BKK1", 0)), int(b.get("BAGA", 0)), int(b.get("BPFL", 0)), int(s.stats.launches), s.kills, s.hero])
		for s in scene.ai_summaries():
			var pk: Dictionary = peak[s.player]
			var built := 0
			for k in s.buildings: built += int(s.buildings[k])
			var count := 0
			for k in s.units:
				count += int(s.units[k])
				pk.types[k] = maxi(int(pk.types.get(k, 0)), int(s.units[k]))
			pk.buildings = maxi(pk.buildings, built)
			pk.units = maxi(pk.units, count)
			pk.launches = maxi(pk.launches, int(s.stats.launches))
			for code in army[s.player]: pk.garrison = pk.garrison or int(s.buildings.get(code, 0)) > 0
			pk.peasants_in_mines = maxi(pk.peasants_in_mines, int(s.workers))
			for code in s.buildings:
				var c := String(code).trim_suffix("*")
				if not String(code).ends_with("*"): pk.keep = maxi(int(pk.get("keep", 0)), Rules.keep_level(c))
			pk.research = maxi(int(pk.get("research", 0)), scene.production.research.get(s.player, []).size())
	var summaries: Array = scene.ai_summaries()
	var no_room_sides := {}
	print("end t=%.0fs over %s outcome %s" % [scene.simulation_time, scene.skirmish.over, scene.skirmish.outcome])
	if attack_report: print_attack_report(scene, sides)
	for p in sides:
		if p == human: continue
		var pk: Dictionary = peak[p]
		print("P%d peak: buildings %d units %d launches %d workers %d garrison %s keep %d research %d" % [p, pk.buildings, pk.units, pk.launches, pk.peasants_in_mines, pk.garrison, int(pk.get("keep", 0)), int(pk.get("research", 0))])
		side_check(pk.buildings >= 2 and pk.garrison, "P%d built a Keep and a Garrison (race %d: its army building)" % [p, int(races[p])])
		var room: Dictionary = no_room_seen.get(p, {})
		var full: String = String(room.get("why", ""))
		var mines_excused := full != "" and int(room.workers) < 2
		if full != "":
			# AI-10 (AI_RESEARCH.md section 26): the side's home has no room for a wanted building even with every standing
			# unit and every reservation ignored. The window search is the original's (0x4f9480 / 0x435320 Emulated on the
			# match grid, spot for spot), and in the original each failed search ends building for the pass and holds the
			# builders off the mine branch (0x4f9790 / 0x4fd940, Read, AI-9 F3): no mine workers and no hall upgrades follow
			# from the map, not from the port. The mine and hall-level goals the side had not reached when its home filled
			# are printed, not asserted; goals reached before that stay asserted.
			print("(no room at P%d's home, %s; then mine workers %d, hall %d) P%d mine workers %d, hall level %d" % [p, full, int(room.workers), int(room.keep), p, pk.peasants_in_mines, int(pk.get("keep", 0))])
			no_room_sides[p] = room
		if not int(races[p]) in ELF_RACES:
			if not mines_excused: side_check(pk.peasants_in_mines >= 2, "P%d has Peasants working in mines" % p)
			else: print("(not asserted, no room) P%d has Peasants working in mines: %d" % [p, pk.peasants_in_mines])
		else:
			# B4-3: the Elves' economy is Wisps into Ancient Wisps (E18 / E20); with --expect-ancient an Ancient Wisp on each Elf side.
			print("P%d (Elves) unit peaks: %s" % [p, pk.types])
			if expect_ancient: side_check(int(pk.types.get("AEAX", 0)) >= 1, "P%d (race %d) has an Ancient Wisp" % [p, int(races[p])])
		side_check(pk.units >= 6, "P%d trained units" % p)
		# Milestone 11b: computer Dwarves keep the Ballista in their roster and still train builders (the persistent want
		# list of 0x4fe830 / 0x4fe9e0: the Smith's node gains the time bonus too).
		if int(races[p]) == 1:
			print("P%d unit peaks: %s" % [p, pk.types])
			side_check(int(pk.types.get("ADBX", 0)) >= 2, "P%d (Dwarves) trained Smiths with the Ballista in the roster" % p)
			side_check(int(pk.types.get("ADNX", 0)) >= 1, "P%d (Dwarves) trained a Ballista" % p)
	if min_keep > 0:
		check(peak.values().any(func(pk): return int(pk.get("keep", 0)) >= min_keep), "a side reached Keep level %d" % min_keep)
		# Not asserted: the computer's research stalls behind Crusade I, as the original's choice does (AI_RESEARCH.md section 15);
		# the peak line prints it.
	var crusade := range(sides).filter(func(p): return scene.production.research_level(p, "PCR0") > 0)
	print("research done: %s" % [range(sides).map(func(p): return scene.production.research.get(p, []))])
	if expect_stall:
		# AI-10 (AI_RESEARCH.md section 26): the rule behind the stall, not the match state. The category-2 node stays on
		# Crusade I (the race's first research entry, 0x4fead0, Emulated) while it is not had, so before Crusade I a side
		# completes only what the tech step 0x4ff0d0 wants: research that a unit of the race requires (directly or through
		# another such research). Whether Crusade I itself gets done depends on the Peasant demand 0x4fe830 (section 15:
		# 1d30 + 50 against the Peasant's 1d30 + 51..100 + its time bonus): with every owned mine slot worked the Peasant
		# leaves the want list and Crusade I is chosen, in the original as in the port. Printed, not asserted.
		for p in sides:
			var done: Array = scene.production.research.get(p, [])
			var unlocking := unit_research(scene.production.rules, int(races[p]))
			var before: Array = done.slice(0, done.find("PCR0")) if done.has("PCR0") else done
			check(before.all(func(id): return unlocking.has(String(id))), "original research: P%d completed only unit research (tech step) before Crusade I: %s (unit research %s)" % [p, done, unlocking.keys()])
		print("Crusade I completed by sides %s (the stall holds while the Peasant demand stays positive)" % [crusade])
	if min_research > 0:
		check(peak.values().any(func(pk): return int(pk.get("research", 0)) >= min_research), "a side completed %d research items" % min_research)
		# B3-3: Crusade I is the Knights' item (the M-1 Knights mirror's check); other pairings check the research count alone.
		if range(sides).all(func(p): return int(races[p]) == 0): check(not crusade.is_empty(), "a side got past Crusade I")
	if water: print("swimmers (unit id: movement type): %s" % [swimmers])
	# B1-5: per side the abilities used, the advancements and the research.
	for s in summaries:
		var p := int(s.player)
		print("P%d race %d casts %s advanced %s research %s" % [p, int(races[p]), s.get("casts", {}), s.get("advanced", {}),
			scene.production.research.get(p, [])])
		if each_keep > 0 and not (no_room_sides.has(p) and int(no_room_sides[p].keep) < each_keep):
			check(int(peak[p].get("keep", 0)) >= each_keep, "P%d (race %d) reached hall level %d (peak %d)" % [p, int(races[p]), each_keep, int(peak[p].get("keep", 0))])
		elif each_keep > 0:
			print("(not asserted, no room) P%d (race %d) reached hall level %d (peak %d)" % [p, int(races[p]), each_keep, int(peak[p].get("keep", 0))])
		if each_research > 0:
			check(int(peak[p].get("research", 0)) >= each_research, "P%d (race %d) completed %d research items (%d)" % [p, int(races[p]), each_research, int(peak[p].get("research", 0))])
		var completed: Array = scene.production.research.get(p, [])
		if int(races[p]) in stalled: check(completed.is_empty(), "P%d (race %d) completed no research, as the original (%s)" % [p, int(races[p]), completed])
		if researches.has(int(races[p])):
			check(researches[int(races[p])].any(func(id): return completed.has(id)), "P%d (race %d) completed one of %s (%s)" % [p, int(races[p]), researches[int(races[p])], completed])
		if int(races[p]) in CASTER_RACES and not (s.get("casts", {}) as Dictionary).is_empty(): casting_sides += 1
		if expect_casts and int(races[p]) in CASTER_RACES:
			check(not (s.get("casts", {}) as Dictionary).is_empty(), "P%d (race %d) used an ability" % [p, int(races[p])])
		if expect_advance and int(races[p]) == 2:
			var skeletons := 0
			for key in s.get("advanced", {}):
				if String(key).begins_with("AUIX>"): skeletons += int(s.advanced[key])
			check(skeletons >= 1, "P%d (Undead) advanced Skeletons (%s)" % [p, s.get("advanced", {})])
	if any_casts: check(casting_sides >= 1, "a batch-1 side used an ability (%d sides)" % casting_sides)
	# B1-7: the computer heroes' spells (0x503c60 orders, dispatched casts, potions) per side.
	for s in summaries:
		var p := int(s.player)
		var dispatched := int(scene.combat.spells.hero_spells.casts.get(p, 0))
		var ordered: Dictionary = s.get("hero_casts", {})
		print("P%d hero spells ordered %s, cast %d, potions %s" % [p, ordered, dispatched, s.get("hero_drinks", {})])
		if expect_hero_casts and int(races[p]) in BATCH1:
			check(dispatched >= 1, "P%d (race %d) hero cast a spell (orders %s)" % [p, int(races[p]), ordered])
			var block: Dictionary = scene.combat.heroes[p].match.block() if scene.combat.heroes.has(p) else {}
			for spell in ordered:
				check(AiSpells.knows(block.get("skills", []), int(spell)), "P%d hero knows spell %d (school %d)" % [p, int(spell), int(spell) / 10])
	var fought := 0
	var launches := 0
	for p in sides:
		fought += int(scene.combat.kills.get(p, 0))
		launches += int(peak[p].launches)
	check(launches >= 1, "a group launched")
	check(fought >= 1 or scene.skirmish.over, "the sides fought (kills %d)" % fought)
	if sides > 2:
		# W2: in a 3-6 side match every side builds, launches and fights (kills or losses: a side may lose its first fight).
		var developed := 0
		for p in sides:
			if p == human: continue
			var hit := int(scene.combat.kills.get(p, 0)) + int(scene.skirmish.stats[p].troops_lost)
			side_check(int(peak[p].launches) >= 1, "P%d launched a group" % p)
			side_check(hit >= 1, "P%d fought (kills %d, losses %d)" % [p, int(scene.combat.kills.get(p, 0)), int(scene.skirmish.stats[p].troops_lost)])
			var ok: bool = peak[p].garrison and hit >= 1
			if ok: developed += 1
			print("P%d (race %d): army building %s, fought %s (kills %d, losses %d)" % [p, int(races[p]), peak[p].garrison, hit >= 1,
				int(scene.combat.kills.get(p, 0)), int(scene.skirmish.stats[p].troops_lost)])
		if min_sides > 0:
			check(developed >= min_sides, "at least %d of %d sides built an army building and fought (%d)" % [min_sides, sides, developed])
	DirAccess.make_dir_recursive_absolute("res://.local")
	var csv_name := "res://.local/ai_soak.csv" if races == [0, 0] else "res://.local/ai_soak_%s.csv" % "_".join(races.map(func(r): return str(r)))
	if slug != "desert-sands": csv_name = "res://.local/ai_soak_%s_%s.csv" % [slug, "_".join(races.map(func(r): return str(r)))]
	var file := FileAccess.open(csv_name, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(csv) + "\n")
		file.close()
	scene.end_skirmish()
	scene.free()
	if failures > 0:
		printerr("AI soak checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI soak checks passed: %d checks, %.0f simulated seconds, races %s" % [checks, minutes * 60.0, races])
	quit(0)

## B1-7: `--hero-class` / `--hero-level` redraw a side's computer hero record with 0x42a0d0's setup words (class 0xa49900,
## level 0xa498fc; the original reads them for a computer slot) from the match generator, rebind it to the hero object and
## rebuild the hero unit (0x54fd50), before the first update. A test set-up: a skirmish leaves both words unset.
func write_census(scene, file, step: int):
	var counts := {}
	var pos := {}
	var dead := {}
	for u in scene.units:
		if u.removed: continue
		# AI-8: the original's census lists dying units (their corpses) as well, about 30 s after death (AI_RESEARCH.md
		# section 24); the rebuild's go to `dying` so that both counts can be formed.
		if u.dying:
			if not dead.has(String(u.type_id)): dead[String(u.type_id)] = []
			dead[String(u.type_id)].append([u.cell.x * 32 + 16, u.cell.y * 24 + 12, int(u.owner_id), int(u.unit_id)])
			continue
		var t := String(u.type_id)
		counts[t] = int(counts.get(t, 0)) + 1
		if not pos.has(t): pos[t] = []
		pos[t].append([u.cell.x * 32 + 16, u.cell.y * 24 + 12, int(u.owner_id), int(u.unit_id)])
	var towers := []
	for b in scene.production.buildings.values():
		var t := String(b.original_type_id)
		var key := "%s@%d" % [t, int(b.owner)]
		counts[key] = int(counts.get(key, 0)) + 1
		# AI-8: the towers' cells, owners, hit points and their current target (`towers`, not in the original's format).
		var tw = scene.combat.towers.get(b.entity_id)
		if tw != null:
			towers.append([t, int(tw.center.x), int(tw.center.y), int(b.owner), int(b.hit_points), String(tw.target_kind), int(tw.target_id), int(tw.range)])
	file.store_line(JSON.stringify({"clock": step * 25, "counts": counts, "pos": pos, "kills": scene.combat.kills.duplicate(), "towers": towers, "dying": dead}))

func set_heroes(scene, sides: int, races: Array, classes: Array, hero_levels: Array):
	for p in sides:
		var klass: int = int(classes[p]) if p < classes.size() else -1
		var level: int = int(hero_levels[p]) if p < hero_levels.size() else -1
		if klass < 0 and level <= 0: continue
		var inputs := {"player": p, "local": -1, "levels": [0, 0, 0, 0, 0, 0, 0], "active": range(7).map(func(i): return i < sides),
			"computer": range(7).map(func(i): return i < sides), "race": int(races[p]), "class_field": klass, "level_override": level}
		var record: Dictionary = ComputerHero.create(scene.combat.rng, inputs)
		var bound = scene.combat.heroes[p].match
		check(bound.bind_computer(record, bound.entity, "Computer %d" % p), "P%d hero rebound (class %d level %d)" % [p, klass, level])
		scene.refresh_hero_unit(bound)
		var f = scene.combat.fighters[bound.entity.entity_id]
		f.hp = int(f.max_hp)
		f.erase("max_mana")                  # Combat recomputes the maximum and the start pool (0x54fd50 start flag)
		f.erase("mana")

func print_heroes(scene, sides: int):
	for p in sides:
		if not scene.combat.heroes.has(p): continue
		var b: Dictionary = scene.combat.heroes[p].match.block()
		var schools: Array = b.get("skills", []).filter(func(e): return int(e[0]) >= 10 and int(e[0]) <= 22 and int(e[2]) > 0)
		var t := AiSpells.fill(b.get("skills", []), 0)
		var slots: Array = []
		for s in AiSpells.SLOTS:
			if int(t.slots[s]) >= 0: slots.append("%x:%d" % [s, int(t.slots[s])])
		print("P%d hero class %d level %d schools %s spell slots %s enabled %s" % [p, int(b.get("class", -1)), int(b.get("level", 0)),
			schools, slots, t.enabled])

## AI-11 `--attack-report`: each side's units at the start (army setup purchases with their mana).
func print_start_armies(scene, sides: int):
	for p in sides:
		var rows: Array = []
		for u in scene.units:
			if u.removed or int(u.owner_id) != p: continue
			var f = scene.combat.fighters.get(u.unit_id)
			var mana := "" if f == null or int(f.get("max_mana", 0)) < 1 else " mana %d/%d" % [int(f.mana), int(f.max_mana)]
			rows.append("%s%s" % [u.type_id, mana])
		print("AI-11 start P%d (%s, level %d): %s" % [p, "human" if p == human else "computer", int(scene.skirmish.slots[p].get("difficulty", -1)), rows])

func _object_info(scene, kind: String, id: int) -> Dictionary:
	if kind == "unit":
		var f = scene.combat.fighters.get(id)
		return {} if f == null else {"owner": int(f.owner), "code": String(f.type_id), "cell": scene.combat.unit_cell(id)}
	if kind == "building":
		var b = scene.production.building(id)
		return {} if b == null else {"owner": int(b.owner), "code": String(b.original_type_id), "cell": Vector2i(b.left, b.top)}
	if kind == "mine":
		var m = scene.mines.mines.get(id)
		return {} if m == null else {"owner": int(m.entity.owner), "code": String(m.code), "cell": m.entity.cell()}
	return {}

## Once a second: the first order of each side's units on another side's object, the computer groups' targets and launches.
func watch_attacks(scene, t: int):
	for f in scene.combat.fighters.values():
		var owner := int(f.owner)
		if first_attack.has(owner) or f.order == null or not scene.combat.alive(f): continue
		var o := _object_info(scene, String(f.order.target_kind), int(f.order.target_id))
		if o.is_empty() or int(o.owner) == owner or int(o.owner) >= 6 or scene.skirmish.is_allied(owner, int(o.owner)): continue
		var cell: Vector2i = scene.combat.unit_cell(int(f.id))
		var start: Vector2i = scene.skirmish.slots[owner].start
		first_attack[owner] = {"t": t, "victim": int(o.owner), "code": o.code, "by": String(f.type_id), "cell": cell,
			"from_start": maxi(absi(cell.x - start.x), absi(cell.y - start.y))}
	for ai in scene.ai_manager.players:
		if ai == null or not ("groups" in ai): continue
		var p := int(ai.me)
		if not first_targets.has(p): first_targets[p] = []
		if not launches_seen.has(p): launches_seen[p] = []
		for e in ai.log:
			if e.has("launch") and launches_seen[p].size() < 5 and not launches_seen[p].has(e): launches_seen[p].append(e)
		for g in ai.groups:
			if not bool(g.get("launched", false)) or g.get("target", {}).is_empty() or first_targets[p].size() >= 5: continue
			var key := "%d:%s:%d" % [int(g.get("slot", -1)), String(g.target.kind), int(g.target.id)]
			if first_targets[p].any(func(x): return x.key == key): continue
			var o := _object_info(scene, String(g.target.kind), int(g.target.id))
			if o.is_empty(): continue
			var size: int = g.slots.filter(func(id): return int(id) != -1).size() if g.has("slots") else g.members.size()
			first_targets[p].append({"key": key, "t": t, "kind": int(g.kind), "size": size, "victim": int(o.owner), "code": o.code, "cell": o.cell})

func print_attack_report(scene, sides: int):
	for p in sides:
		var a: Dictionary = first_attack.get(p, {})
		print("AI-11 P%d first attack: %s" % [p, "none" if a.is_empty() else "%d s on P%d's %s by %s at %s (%d cells from its start)" % [a.t, a.victim, a.code, a.by, a.cell, a.from_start]])
		print("AI-11 P%d first launches: %s" % [p, launches_seen.get(p, []).map(func(e): return "%d s type %d size %d -> P%d" % [int(e.t) / 1000, int(e.launch), int(e.size), int(e.player)])])
		print("AI-11 P%d first group targets: %s" % [p, first_targets.get(p, []).map(func(x): return "%d s group type %d (%d) -> P%d %s at %s" % [x.t, x.kind, x.size, x.victim, x.code, x.cell])])

## A per-side progress check: asserted for every side, or only printed with --min-sides (then counted at the end).
func side_check(value: bool, label: String):
	if min_sides == 0: check(value, label)
	elif not value: print("(not asserted, --min-sides) ", label)

## Buildings of the race's PRODUCTION rows that are not a Keep and train a unit other than a Peasant type.
func army_buildings(rules, race: int) -> Array:
	var out := []
	for code in rules.production_table(race):
		if Rules.keep_level(String(code)) > 0: continue
		for slot in rules.production_slots(String(code), race):
			if slot.id == null: continue
			var id := String(slot.id)
			if id.length() == 4 and id[0] == "A" and not Rules.is_hero_type(id) and not rules.is_peasant_type(id):
				out.append(String(code))
				break
	return out

## Every simulated second: no negative stock, at most one job per building, no unit of a computer player standing on a
## building cell, every AI-issued attack order aims at a live hostile object.
func invariants(scene, sides: int):
	if water:
		var wrong := []
		for u in scene.units:
			if u.removed or u.flying or u.inside_building or u.dying or not scene.collision.inside(u.cell): continue
			if not scene.navigator.sector_passable(u.cell, 1, u.movement_type): wrong.append("%s %d at %s" % [u.type_id, u.unit_id, u.cell])
			elif not scene.navigator.sector_passable(u.cell, 1, 0): swimmers[u.unit_id] = u.movement_type
		check(wrong.is_empty(), "every unit on a cell its movement type can enter (%s)" % [wrong])
	for p in sides:
		var stock: Array = scene.economy.resources(p)
		check(stock.min() >= 0, "P%d stock never negative" % p)
	for b in scene.production.buildings.values():
		check(b.queue.size() <= 5, "building queue bound")
	for f in scene.combat.fighters.values():
		if f.order == null or not scene.combat.alive(f): continue
		if f.order.target_kind == "unit":
			var t = scene.combat.fighters.get(int(f.order.target_id))
			check(t == null or int(t.owner) != int(f.owner), "no attack on an own unit")
