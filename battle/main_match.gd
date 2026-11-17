extends RefCounted
## main.gd's match (R-1 split of main.gd, no behaviour change): the skirmish start and the setup hand-over, the setup
## rules and option units, the end of the match, the end box and the results screen, the retinue scan. The state
## stays on the scene (main.gd); `main` is the scene.

const MainScript = preload("res://battle/main.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Economy = preload("res://simulation/economy.gd")
const Rules = preload("res://simulation/production_rules.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const RetinueScan = preload("res://simulation/retinue_scan.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const ComputerHero = preload("res://simulation/computer_hero.gd")
const HeroAdvance = preload("res://menus/hero_advance.gd")
const Encounters = preload("res://simulation/encounters.gd")
const SkirmishSetup = preload("res://simulation/skirmish_setup.gd")
const SkirmishMatch = preload("res://simulation/skirmish_match.gd")
const ArmySetup = preload("res://simulation/army_setup.gd")
const HeroStore = preload("res://simulation/hero_store.gd")
const MapData = preload("res://core/map_data.gd")
const Mines = preload("res://simulation/mines.gd")
const AiManager = preload("res://simulation/ai_manager.gd")
const CustomAi = preload("res://simulation/custom_ai.gd")
const AiPlayer = preload("res://simulation/ai_player.gd")
const AiRules = preload("res://simulation/ai_rules.gd")
const ArtData = preload("res://core/art_data.gd")
const SaveGame = preload("res://simulation/save_game.gd")
const SkirmishVictory = preload("res://simulation/skirmish_victory.gd")
const RandomMapMatch = preload("res://simulation/random_map_match.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

# ------------------------------------------------------------------ milestone 10a: skirmish match

## Match start (0x4e2790 -> 0x417730 -> 0x4179f0; SKIRMISH_RESEARCH.md). `setup` is the setup screen's state; 0x4de740
## turns it into the player table. Per active player: starting resources (0x43e4d0), the map's towers of that owner
## (0x4910e0 checks 0x708f94), and the hero at the free cell nearest the side's start cell (0x43b550 -> 0x43b4c0 ->
## 0x530a90). With 0 army setup points nothing else is placed (0x417730 skips the army screen, 0x4406b0 places only
## the retinue and bought units). The local hero comes from `store`; a computer hero is a level-1 Knight Warrior until
## 0x42a0d0 (the computer's hero) is ported with the computer player (10b). Neutral encounters run as in milestone 9.
func start_skirmish(setup: Dictionary, hero_id: String, store = null, id: String = "") -> bool:
	main.hero_store = store if store != null else HeroStore.new()
	# AI-vs-AI (soak test, spectator): the local slot is a computer and no hero book profile is used.
	var spectator: bool = int(setup.players[int(setup.local)].kind) == SkirmishSetup.COMPUTER
	var profile = null if spectator else main.hero_store.load_profile(hero_id)
	if profile == null and main.restoring and main.restore_profile != null: profile = main.restore_profile   # S-1: a load of a deleted hero's save
	if profile == null and not spectator:
		main.last_message = "Cannot load the hero: " + main.hero_store.last_error
		push_error(main.last_message)
		return false
	end_skirmish()
	main.match_setup = setup.duplicate(true)       # S-1: a save carries the setup; a load starts it again
	main.match_hero_id = hero_id
	main.autosave_next_ms = -1
	main.clear_units()
	for key in main.building_nodes.keys(): main.building_nodes[key].queue_free()
	main.building_nodes.clear()
	if not main.navigator.building_cells.is_empty():
		main.navigator.building_cells.clear()
		main.navigator.build_sectors()
	main.pending_builds.clear()
	main.build_mode = ""
	main.rally_mode = false
	main.simulation_time = 0.0
	if main.map_effects != null: main.map_effects.reset(main.game_ms())
	var resolved := SkirmishSetup.resolve(setup)
	if MapData.is_generated(): resolved.scenario_events = 0   # S-2: a Random Map has no scenario events (0x41c7d0)
	main.local_player = int(resolved.local)
	var players := SkirmishSetup.active_players(resolved)
	main.economy = Economy.new(main.local_player)
	for p in players: main.economy.add_player(p, SkirmishSetup.starting_resources(int(resolved.slots[p].resources)))
	main.make_production()
	# RM-7: the match generator continues from the placement's draws (simulation/random_map_match.gd: the seed is a decision).
	if not setup.get("random_map", {}).is_empty(): main.combat_seed = setup.random_map.rng_after.duplicate()
	# The fog placement filter (0x435900) is the local human's; a computer local slot (spectator) has none.
	main.production.local_player = -1 if spectator else main.local_player
	# Milestone 11a: each player's race (0x708f96) drives its menus, prices, dependency rows and computer player.
	for p in players: main.production.races[p] = int(resolved.slots[p].race)
	# Parity pass 4: each slot draws in its colour word (0x708f9a), not colour = player.
	ArtData.colours.clear()
	for p in players: ArtData.colours[p] = clampi(int(resolved.slots[p].colour), 0, 7)
	main.production.players_in_match = players.duplicate()
	main.match_profiles.clear()
	main.match_heroes.clear()
	main.setup_combat()
	main.assaults.clear()
	main.attack_moves.clear()
	main.navigator.marches.clear()
	main.apply_modern_rules()
	main.combat.game_mode = int(resolved.game_mode)
	main.combat.relations = resolved.allied
	# W2: the target tests (Rules.hostile over combat.teams) follow the setup's teams too; team 0 is hostile to everyone
	# (0x748915 holds 1 only for the same slot or the same non-zero team, skirmish_setup.gd). The fixture harness keeps
	# its teams 1 / 2. Kill counters start at 0 for every side.
	main.combat.teams = range(7).map(func(p): return int(resolved.slots[p].team) if p < 6 and bool(resolved.slots[p].active) else 0)
	main.combat.kills = {}
	for p in players: main.combat.kills[p] = 0
	for p in players:
		if resolved.slots[p].computer: main.combat.ai_players[p] = true
	main.combat.fog_viewer = main.local_player if main.local_player >= 0 and main.local_player < 6 else 0   # 0x47f560: the machine's fog
	var options: Dictionary = resolved.options
	# 0x416ab0: the fog object is created with (vision 1 or 2, hidden map 0x70ae07); 0x47a940 arms every cell.
	main.visibility.fog = int(options.vision) >= 1
	main.visibility.shroud = bool(options.hidden_map)
	main.visibility.line_of_sight_option = int(options.vision)
	if id == "": id = "skirmish-" + Crypto.new().generate_random_bytes(8).hex_encode()
	main.skirmish = SkirmishMatch.new(resolved, main.combat, main.production, main.catalogue_data, id)
	main.skirmish.ended.connect(main._on_match_ended)
	main.skirmish.cleanup.connect(main._on_side_cleanup)
	main.skirmish.notice.connect(func(text): main.last_message = text)
	main.encounters.player_active = range(7).map(func(i): return i < 6 and bool(resolved.slots[i].active))
	main.encounters.player_race = range(7).map(func(i): return int(resolved.slots[i].race))
	main.encounters.player_byte_748668 = main.skirmish.eliminated
	main.encounters.quests_enabled = bool(options.get("quests", true))   # S-2: 0x70ae0d
	main.encounters.tough_towers = bool(options.get("tough_towers", false))
	main.encounters.tough_start_towers = bool(options.get("tough_start_towers", false))   # setup rows: 0x749c67 (0x4a50f0 / 0x418700)
	if main.day_night != null: main.day_night.random_weather = bool(options.get("random_weather", false))   # setup rows: 0x749c60 byte 0
	# Parity pass 3 (0x4a50f0): map towers take their owner's race; level terms from the highest non-computer hero level.
	var human_level := 0
	if profile != null and not spectator: human_level = int(profile.data.level)
	for entry in main.encounters.adopt_map_buildings(main.game_ms(), players, main.encounters.player_race, human_level):
		if entry.code == "BZMA": main.mausoleum_id = entry.id
		if entry.code == "BLGL": main.lair_id = entry.id
	main.encounters.spawn_animals()
	# 0x43b550: a human slot binds its hero book record; a computer slot (0x70d6a4) gets 0x42a0d0's record (milestone 11,
	# Emulated: level from the human heroes, random class, skills, stats and items) drawn from the match generator.
	var levels := [0, 0, 0, 0, 0, 0, 0]
	if profile != null: levels[main.local_player] = int(profile.data.level)
	var no_heroes: bool = bool(options.get("no_heroes", false))   # S-2: 0x70ae2d, 0x43b550 is skipped
	main.no_hero_items = bool(options.get("no_hero_items", false))       # setup rows: 0x749c68 (HeroMatch.no_items)
	for p in players:
		if no_heroes: break
		if p == main.local_player and not spectator:
			main.match_profiles[p] = profile
		else:
			var inputs := {"player": p, "local": main.local_player, "levels": levels,
				"active": range(7).map(func(i): return i < 6 and bool(resolved.slots[i].active)),
				"computer": range(7).map(func(i): return i < 6 and bool(resolved.slots[i].computer)),
				"race": int(resolved.slots[p].race)}
			inputs.merge(computer_hero_inputs(options))            # S-2: Titans, I Am The Greatest, the temporary hero level
			main.match_profiles[p] = ComputerHero.create(main.combat.rng, inputs)
			if int(options.get("victory", 0)) == 3 and main.match_profiles[p].has("backpack"):   # 0x42a0d0: no items for Assassination
				main.match_profiles[p].backpack = main.match_profiles[p].backpack.map(func(_i): return 0)
		var cell: Vector2i = main.navigator.free_cell_near(resolved.slots[p].start)
		# The hero book record's unit (record +0x5c: the hero's own race's art, 0x54bee0; milestone 11b: any race, independent
		# of the race the slot plays); a computer hero's type follows its slot's race (0x42a0d0).
		var hero_type: String = String(profile.data.original_type_id) if (p == main.local_player and not spectator) else Rules.hero_type(int(resolved.slots[p].race))
		main.add_unit(hero_type, cell, p)
	place_army_setup(resolved, players, setup.get("army", {}), setup.get("army_retinue", []))
	place_option_units(resolved, players)     # S-2: Titans, the units of No Heroes, the Capture the Flag flags
	# The map's mines (economy, conversion, workers) and the computer players (0x504a30: one AI per computer slot).
	var map_data: Dictionary = MapData.map()
	main.mines = Mines.new()
	main.mines.setup(main.economy, map_data, main.collision.data.objects, 5000)
	main.setup_conversions()
	main.skirmish.economy = main.economy                # S-2: the victory conditions read the stockpiles and the mines
	main.skirmish.mines = main.mines
	main.ai_manager = AiManager.new()
	main.combat.pre_update = main._ai_pre_update
	main.combat.hate_hook = main._ai_building_damaged
	for p in players:
		var slot: Dictionary = resolved.slots[p]
		if not slot.computer: continue
		var level: int = int(slot.difficulty)
		main.production.ai_players[p] = level
		main.combat.building_bonus[p] = int(AiRules.BUILDING_COMBAT.get(level, 0))
		# AI-4: 0x5059a0 -> 0x4ffa50: the slot's CustomAI file (setup record +0xa) is looked up in the CustomAI folders and
		# loaded by 0x4f76d0; a refused file (every file of the install) leaves the defaults.
		var custom: String = String(slot.get("custom_ai", ""))
		var loaded: Dictionary = CustomAi.load_file(CustomAi.resolve(custom)) if custom != "" else {}
		var ai = AiPlayer.new(p, level, main, int(slot.race), loaded.get("profile", {}) if bool(loaded.get("loaded", false)) else {})
		ai.custom_ai = custom
		main.ai_manager.add(ai)
		main.skirmish.controllers[p] = AiManager.Controller.new(main.ai_manager)
	# 0x4e2790: battles fought and the games of the race the player plays (milestone 11b) are counted and the hero is
	# written before the battle starts.
	if spectator or no_heroes:
		main.hero_match = null
		main.hero_unit_id = -1
	elif main.restoring or bool(options.get("temp_hero", false)):      # S-2: a temporary hero writes nothing (0x4e2790)
		pass                                  # S-1: the saved match already counted its start (0x4e2790); the load replaces the hero
	elif main.hero_match == null or not main.hero_match.begin(main.hero_store, id, int(resolved.slots[main.local_player].race)):
		main.last_message = "Hero match start failed: " + (main.hero_match.last_error if main.hero_match != null else "no hero")
		push_error(main.last_message)
	refresh_hero_commands()
	apply_setup_options(resolved)           # parity pass 2 (results section): build level, game speed, results counters
	for unit in main.units: unit.selected = unit.unit_id == main.hero_unit_id
	main.camera.zoom = Vector2.ONE * main.hud.scale_factor if main.normal_play and main.hud != null else Vector2.ONE   # the shared view scale (display.gd)
	main.home_cell = Vector2i(resolved.slots[main.local_player].start) if not spectator else Vector2i(-1, -1)
	UnitAgent.local_player = main.local_player
	main.control_groups = {}
	main.alerts = []
	main.minimap_ping.reset()
	main.patrols = {}
	main.guards = {}
	main.target_mode = 0
	if main.hero_unit_id >= 0: main.centre_view(main.units[main.hero_unit_id].position)
	main.apply_fog_to_nodes()
	main.refresh_fog_overlay()
	hide_results()
	if main.hud != null and MapData.is_generated():                # RM-7: no SM24 image on a generated map: composed once per match
		var image = RandomMapMatch.Bundle.minimap_image(MapData.terrain().draws, MapData.size_cells().x)
		if image != null: main.hud._minimap = ImageTexture.create_from_image(image)
	main.last_message = "Skirmish on %s: %s." % [String(resolved.map).get_file().get_basename(), "destroy every enemy unit and every building that counts (Standard Victory)" if int(options.get("victory", 0)) == 0 else "victory option %d" % int(options.get("victory", 0))]
	return true

func end_skirmish():
	ArtData.colours.clear()
	if main.ai_manager != null:
		main.ai_manager.dispose()
		main.ai_manager = null
	if main.conversions != null:
		main.conversions.dispose()
		main.conversions = null
	if main.mines != null:
		main.mines.dispose()
		main.mines = null
	main.mine_orders.clear()
	main.build_results.clear()
	if main.skirmish == null: return
	main.skirmish.dispose()
	main.skirmish = null
	main.match_profiles.clear()
	main.match_heroes.clear()
	hide_results()

## 0x5268c0 for each player's living hero (0 while the hero is dead; 0x556b50 requires a living hero).
## Milestone 11: with the full hero block (items, Leadership, the race's lord skill): command 0x5268c0, the price modifier
## 0x526cf0 and Engineer's building hit points (0x43bd50: x20 for buildings placed while the hero lives).
func refresh_hero_commands():
	for owner in main.match_heroes:
		var bound = main.match_heroes[owner]
		var f = main.combat.fighters.get(bound.entity.entity_id) if bound.entity != null else null
		var living: bool = main.combat.alive(f)
		var block: Dictionary = bound.block(int(f.hp) if f != null else 0)
		main.production.hero_alive[owner] = living
		main.production.hero_commands[owner] = main.combat.hero_command_value(owner, block, f) / 2 if living else 0   # B2-1: with the counter 0x70d622
		main.production.hero_discounts[owner] = (HeroEffects.price_value(block) + (main.combat.spells.status_value(f, 0xb) if main.combat.spells != null else 0)) if living else 0   # B1-6e: Charm's effect 0xb (0x526cf0, Emulated)
		main.production.hero_building_hp[owner] = HeroEffects.skill_effect(block, 0x42) if living else 0
		# REVIEW D4 (milestone 13): the research price inputs of 0x40b6b0 from the living hero: the item power 0x25
		# (0x40c380) and the ranks of skills 0x3d..0x41 (0x556b50). The 0x577520 rune / aura nodes (0x3f building time,
		# 0x25 research) stay Open (0).
		main.production.hero_research_discount[owner] = (HeroEffects.item_stat(block, 0x25) + (main.combat.spells.research_status(owner) if main.combat.spells != null else 0)) if living else 0   # B1-6c: + Comprehension 0x25
		var ranks := {}
		if living:
			for skill in range(0x3d, 0x42): ranks[skill] = HeroEffects.lookup(block, skill, 1, true)
		main.production.hero_skill_ranks[owner] = ranks

## In-game menu quit (0x55ccd0 case 4): the match ends as a defeat and the results screen follows.
func quit_match():
	if main.skirmish == null or main.skirmish.over:
		main.last_message = "No skirmish is running."
		return
	main.skirmish.quit()

func match_text() -> String:
	if main.skirmish == null: return "No skirmish (fixtures). Start one from the skirmish setup."
	var parts: Array = []
	for p in SkirmishSetup.active_players(main.skirmish.resolved):
		parts.append("P%d %s%s" % [p, "computer" if main.skirmish.slots[p].computer else "you", " (out)" if main.skirmish.eliminated[p] else ""])
	var next_ms: int = ((SkirmishMatch.CHECK_PASSES - main.skirmish.check_counter - 1) * SkirmishMatch.EVENT_TICKS + SkirmishMatch.EVENT_TICKS - main.skirmish.event_counter) * SkirmishMatch.UI_TIMER_MS
	return "Skirmish · %s · next victory check in %.1f s · %s" % [", ".join(parts), next_ms / 1000.0, "over" if main.skirmish.over else "running"]

## The match is decided (0x4addc0, parity pass 2, Read): the match-over flag 0x748914 is set at once, which stops the
## world update (0x429ec0 skips 0x42de40) and the in-game keys (0x427fb0 returns), while the view keeps drawing; open
## dialogs close and the stinger plays (0x513e00 Victory.wav / 0x513c80 Defeat.wav). Its completion callback (0x513eb0 /
## 0x513d30) opens the end box 'EZDV' / 'EZDD' (0x574b00) and the advisor says 12 / 13; a click on the box (0x574650 ->
## 0x516db0 / 0x516dc0 -> 0x41c520) tears the world down and opens the results (0x454560). Without a stinger (option off,
## effects volume 0, no sound device) the callback runs at once. Mouse clicks on the world while the stinger plays are
## ignored here (Open: the original's mouse handling in that phase is not traced).
func _on_match_ended(outcome: Dictionary):
	main.last_message = ("Victory!" if outcome.won else "Defeat.") + " (%s, %.0f s)" % [outcome.reason, outcome.elapsed_ms / 1000.0]
	main.end_won = bool(outcome.won)
	if main.normal_play and not main.restoring and SaveGame.autosave_setting() > 0 and main.end_phase == "": main.autosave(true)   # S-1 (F8): on victory / defeat
	main.end_phase = "stinger"
	ensure_results_layer()
	main.results_layer.visible = true
	main.results_screen.visible = false
	main.end_box.visible = false
	main.results_layer.get_node("Back").visible = false
	if main.hud != null and main.hud.has_method("close_dialog"): main.hud.close_dialog()       # 0x4addc0 -> 0x497a30
	var length: float = main.audio.stinger(main.end_won) if main.audio != null else -1.0
	if length <= 0.0: open_end_box()
	else: main.get_tree().create_timer(length, true).timeout.connect(func(): if main.end_phase == "stinger": open_end_box())

## 0x513eb0 / 0x513d30: the end box over the frozen view and the advisor line.
func open_end_box():
	main.end_phase = "box"
	main.end_box.visible = true
	main.end_box.queue_redraw()
	if main.audio != null: main.audio.end_box(main.end_won)

## The box rectangle in window pixels: the sheet's size in 1600-mode pixels, centred on the world view (0x574b00:
## (view size - sheet size) / 2), at the shared view scale (display.gd; DELIBERATE MODERN CHANGE).
func end_box_rect() -> Rect2:
	var view := main.view_screen_size()
	var scale: float = main.hud.scale_factor if main.hud != null else 1.0
	var sheet: Vector2 = Vector2(360, 450 if main.end_won else 360)
	return Rect2(Vector2(main.view_screen_left(), 0) + ((view - sheet * scale) / 2.0).floor(), sheet * scale)

func ensure_results_layer():
	if main.results_layer != null: return
	main.results_layer = CanvasLayer.new()
	main.results_layer.layer = 10
	main.add_child(main.results_layer)
	var back := ColorRect.new()
	back.name = "Back"
	back.color = Color.BLACK
	back.size = Vector2(4096, 4096)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.results_layer.add_child(back)
	main.results_screen = load("res://menus/results_screen.gd").new()
	main.results_screen.on_continue = func(): if accept_results(): open_after_results()
	main.results_layer.add_child(main.results_screen)
	main.results_screen.visible = false
	main.end_box = MainScript.EndBox.new()
	main.end_box.main = main
	main.results_layer.add_child(main.end_box)

# Results screen: PNL_VICTORYDEFEAT_NEW (0x143, opened at 0,0 by 0x454b70) over the stopped match, 800x600 scaled to the
# window height with black side bars (deliberate presentation change, as in the setup screen).
func show_results():
	ensure_results_layer()
	main.end_phase = "results"
	main.results_layer.visible = true
	main.results_layer.get_node("Back").visible = true
	main.end_box.visible = false
	main.results_screen.visible = true
	main.results_screen.place_view()
	if main.audio != null: main.audio.results_opened(bool(main.skirmish.outcome.get("won", false)))   # 0x41c520 / 0x454560
	main.results_screen.data = results_data()
	main.results_screen.open_main()

func hide_results():
	main.end_phase = ""
	if main.results_layer != null: main.results_layer.visible = false

## 0x454b70's texts and the advanced results' counters (results_screen.gd). The XP line shows the award 0x4553f0
## computes (short award under 300 s); levels from 0x455b40.
func results_data() -> Dictionary:
	var p: int = main.local_player
	var s: Dictionary = main.skirmish.stats[p]
	var preview := results_preview()
	var data := {"won": bool(main.skirmish.outcome.get("won", false)), "hero_name": String(main.hero_match.profile.data.name) if main.hero_match != null and main.hero_match.profile != null else "",
		"counters": [s.troops_built, s.troops_lost, s.troops_killed, s.buildings_built, s.buildings_lost, s.buildings_destroyed],
		"xp": preview.xp, "levels": preview.levels, "saved": main.skirmish.result_applied, "players": []}
	# 0x449ce0: the local player first, then the other active players in slot order.
	var order: Array = [p]
	for q in SkirmishSetup.active_players(main.skirmish.resolved):
		if q != p: order.append(q)
	for q in order:
		var st: Dictionary = main.skirmish.stats[q]
		var bound = main.match_heroes.get(q)
		var profile = bound.profile if bound != null and bound.profile != null else main.match_profiles.get(q)   # match_profiles empties once the hero spawns
		var record: Dictionary = profile.data if profile != null and "data" in profile else {}
		var levelled: bool = q == p and preview.levels > 0
		var track: Dictionary = main.results_tracking.get(q, {})
		data.players.append({"name": String(record.get("name", "")) if not record.is_empty() else "Player %d" % (q + 1),
			"colour": int(main.skirmish.slots[q].colour), "level": int(record.get("level", 1)),
			"kills": int(main.skirmish.hero_kills[q]), "spells": 0,                              # spells: none in the slice
			"games": int(record.get("history", {}).get("battles_fought", 0)),
			"xp": int(record.get("xp", 0)) + (preview.xp if q == p and not main.skirmish.result_applied else 0),
			"hero_dead": bool(main.skirmish.hero_dead[q]), "levelled": levelled,
			"res_in": results_in_out(q, true), "res_out": results_in_out(q, false),
			"produced": int(st.troops_built), "lost": int(st.troops_lost), "total_kills": int(st.troops_killed),
			"kills_by_side": int(main.results_tracking.get(p, {}).get("kills", {}).get(q, 0)),
			"built": int(st.buildings_built) - int(st.buildings_converted), "buildings_lost": int(st.buildings_lost),
			"razed": int(st.buildings_destroyed), "converted": int(st.buildings_converted),
			"razed_by_side": int(main.results_tracking.get(p, {}).get("razed", {}).get(q, 0))})
	return data

## 0x449ce0: In and Out per lane (gold, metal, crystal, stone); Out of gold or stone above In is shown as
## In - In / 100 x (1..5) (0x458e70(1, 5, 0); the rebuild draws with randi: Open).
func results_in_out(owner: int, incoming: bool) -> Array:
	var track: Dictionary = main.results_tracking.get(owner, {})
	var gin: Array = track.get("in", [0, 0, 0, 0])
	var gout: Array = track.get("out", [0, 0, 0, 0])
	if incoming: return gin.duplicate()
	var shown := gout.duplicate()
	for lane in [0, 3]:
		if int(gin[lane]) < int(gout[lane]): shown[lane] = int(gin[lane]) - int(gin[lane]) / 100 * randi_range(1, 5)
	return shown

## 0x4406b0 (skirmish setup session, simulation/army_setup.gd): after the heroes, every computer slot buys with the
## setup's army points (0x445200), then the human's units from the army setup screen are placed; each unit starts at
## 0x4402d0's cell through the free-cell finder (0x43b4c0 -> navigator.free_cell_near), with the match generator.
func place_army_setup(resolved: Dictionary, players: Array, human: Dictionary, deployed: Array = []):
	var size := Vector2i(main.collision.width, main.collision.height)
	var points := int(resolved.options.get("army_points", 0))
	for p in players:
		if not resolved.slots[p].computer: continue
		for code in ArmySetup.computer_purchase(points, int(resolved.slots[p].race), int(resolved.slots[p].difficulty), main.combat.rng):
			main.add_unit(code, main.navigator.free_cell_near(ArmySetup.placement_cell(resolved.slots[p].start, size, main.combat.rng)), p)
	if not players.has(main.local_player) or resolved.slots[main.local_player].computer: return
	for unit in deployed:                                     # S-2: 0x4406b0 places the deployed retinue (0xa245d0) first
		var cell: Vector2i = main.navigator.free_cell_near(ArmySetup.placement_cell(resolved.slots[main.local_player].start, size, main.combat.rng))
		# R-1: message 0xfd (0x4a5780 -> 0x4a4560) carries the retinue block with its rank, the experience 0x5fbc48[rank]
		# (not a scenario) and the training gain; no 0x557d90 (REVIEW_R1.md D1, Emulated "fd_builder").
		var made = main.add_unit(String(unit.original_type_id), cell, main.local_player)
		main.skirmish.retinue_units[str(made.unit_id)] = String(unit.id)      # +0x1c8 = 1, slot +0x1ca: a retinue member
		main.combat.set_rank(main.combat.fighters.get(made.unit_id), int(unit.get("medal_level", 0)), int(unit.get("xp", 0)),
			main.combat.creation_gain(main.local_player, String(unit.original_type_id)))
		# Playtest 2026-11-12 (a retinue Liche showed as "Liche"): the block 0x4a4560 builds the unit from carries the
		# member's name, which the unit panel shows for a named unit (Provisional: the name's offset in the block is untraced).
		if String(unit.get("name", "")) != "" and main.combat.fighters.has(made.unit_id): main.combat.fighters[made.unit_id]["name"] = String(unit.name)
	for code in ArmySetup.offers(int(resolved.slots[main.local_player].race)):    # 0x4406b0 walks the offers in screen order
		for i in int(human.get(code, 0)):
			main.add_unit(code, main.navigator.free_cell_near(ArmySetup.placement_cell(resolved.slots[main.local_player].start, size, main.combat.rng)), main.local_player)

## Called once by start_skirmish (parity pass 2): the setup's build level limits production (0x40c740), the setup's game
## speed starts the clock (0x60c3ee + 1), and the advanced results' counters start (0x518b90 resources in / out, the
## kills and razes by side of 0x518ce0 / 0x518f40).
func apply_setup_options(resolved: Dictionary):
	var options: Dictionary = resolved.options
	if main.production != null and main.production.rules != null:
		main.production.rules.options.build_level = int(options.get("build_level", 5))
		apply_rules_options(options)
	if main.hud != null and options.has("game_speed"):
		main.hud.speed = int(options.game_speed) + 1
		main.hud.apply_speed()
	main.results_tracking.clear()
	for q in 7: main.results_tracking[q] = {"in": [0, 0, 0, 0], "out": [0, 0, 0, 0], "kills": {}, "razed": {}}
	if main.economy != null and not main.economy.resources_changed.is_connected(main._on_results_resources):
		main.economy.resources_changed.connect(main._on_results_resources)
	if main.combat != null and not main.combat.died.is_connected(main._on_results_died):
		main.combat.died.connect(main._on_results_died)

func _on_results_resources(owner: int, before: Array, after: Array):
	if not main.results_tracking.has(owner): return
	for lane in 4:
		var delta := int(after[lane]) - int(before[lane])
		if delta > 0: main.results_tracking[owner]["in"][lane] += delta
		elif delta < 0: main.results_tracking[owner]["out"][lane] -= delta

func _on_results_died(kind: String, id: int, killer_owner: int):
	if killer_owner < 0 or not main.results_tracking.has(killer_owner): return
	var victim := -1
	if kind == "unit" and id >= 0 and id < main.units.size(): victim = int(main.units[id].owner_id)
	elif kind == "building" and main.production != null and main.production.building(id) != null: victim = int(main.production.building(id).owner)
	if victim < 0 or victim == killer_owner: return
	var table: Dictionary = main.results_tracking[killer_owner]["kills" if kind == "unit" else "razed"]
	table[victim] = int(table.get(victim, 0)) + 1

func results_preview() -> Dictionary:
	if main.hero_match == null or main.hero_match.profile == null: return {"xp": 0, "levels": 0}
	var context: Dictionary = main.skirmish.result_context(main.local_player, int(main.hero_match.profile.data.level))
	# FE-1: the mode word and Freeze Hero reach the preview as they reach hero_match.finish (0x4553f0).
	context["ironman"] = main.hero_match.profile.is_ironman()
	context["frozen"] = main.hero_match.profile.frozen()
	var xp := HeroRules.result_bonus(context)
	if context.short_match:
		xp = 0 if main.hero_match.profile.frozen() else HeroRules.short_match_bonus(bool(context.won), int(context.victory_option), int(context.unit_setup),
			main.hero_match.profile.is_ironman(), bool(context.get("hero_died", false)))
	if main.skirmish.result_applied: return {"xp": xp, "levels": 0}
	return {"xp": xp, "levels": HeroRules.result_levels(int(main.hero_match.profile.data.level), int(main.hero_match.profile.data.xp) + xp)}

## 0x43f3e0 (simulation/retinue_scan.gd), once per match for the local player's hero: the retinue's survivors, deaths and
## the recruit candidates, kept on the match for the result and the retinue screen.
func run_retinue_scan():
	if main.skirmish == null or main.hero_match == null or main.hero_match.profile == null or main.hero_match.computer: return
	if not main.skirmish.retinue_result.is_empty() or bool(main.skirmish.options.get("temp_hero", false)): return
	var members := {}
	for key in main.skirmish.retinue_units: members[int(key)] = String(main.skirmish.retinue_units[key])
	var list: Array = []
	var dead: Array = []
	var ids: Array = main.combat.fighters.keys()
	ids.sort()
	for id in ids:
		var f = main.combat.fighters[id]
		if int(f.owner) != main.local_player: continue
		var died: bool = f.state == "dying" or f.state == "corpse"
		if died and members.has(int(id)): dead.append(members[int(id)])
		var alive: bool = not died and not bool(f.removed) and int(f.hp) > 0
		list.append({"id": int(id), "type": String(f.type_id), "alive": alive, "hero": bool(f.hero), "retinue_id": String(members.get(int(id), "")),
			"may_join": bool(f.get("may_join", true)), "rank": int(f.get("rank", 0)), "xp": int(f.get("xp", 0)),
			"combat": int(f.base.get("combat", 0)), "flags": int(f.base.get("flags", 0)), "general": main.generals.has(String(f.type_id)),
			"name": String(f.get("name", ""))})
	var units_data: Dictionary = main.catalogue_data.get("units", {})
	var context := {"race": int(main.skirmish.slots[main.local_player].race), "campaign": false, "dead": dead, "rng": main.combat.rng,
		# 0x4169f0: the map's name; a random map's is "Random" (Game.txt [0083] 0, which the graveyard compares, 0x54f980).
		"text": "Random" if not main.match_setup.get("random_map", {}).is_empty() else String(main.skirmish.resolved.get("map", "")).get_file().get_basename(),
		"type_stats": func(code): return CombatRules.unit_stats(String(units_data[code].raw_hex)) if units_data.has(code) else {},
		"display_name": func(code): return String(main.production.rules.definition(code).get("display_name", code))}
	main.skirmish.retinue_result = RetinueScan.scan(list, main.hero_match.profile.data.retinue, main.hero_match.profile.data.graveyard, context)

## The results screen's Continue button (0x4b): the result is written to the hero once, then the hero book opens.
func accept_results() -> bool:
	if main.skirmish == null or not main.skirmish.over: return false
	run_retinue_scan()
	var ok: bool = main.skirmish.apply_result(main.hero_store, main.hero_match)
	# S-1: an end-of-match autosave loaded again: the result is already in the hero book (finish never applies it twice).
	if not ok and main.hero_match != null and main.hero_match.last_error.begins_with("Result already applied"):
		main.skirmish.result_applied = true
		ok = true
	if not ok:
		main.last_message = "Result writeback failed: " + main.hero_match.last_error
		push_error(main.last_message)
		return false
	if main.results_screen != null and main.end_phase == "results":
		main.results_screen.data = results_data()
		main.results_screen.refresh()
	return true

## Continue (0x4549bd): the stat / skill allocation screens and the retinue screen follow for a persistent hero
## (hero_advance.tscn, milestone 11), then the hero book.
func open_after_results():
	if main.hero_match == null or main.hero_match.profile == null or main.hero_match.computer:
		main.get_tree().change_scene_to_file(main.after_results)
		return
	HeroAdvance.pending = {"hero_id": String(main.hero_match.profile.data.id), "store_dir": String(main.hero_store.directory) if "directory" in main.hero_store else "user://heroes",
		"next": main.after_results, "candidates": main.skirmish.retinue_result.get("candidates", []).duplicate(true) if main.skirmish != null else []}
	main.get_tree().change_scene_to_file("res://menus/hero_advance.tscn")

func results_input(event: InputEvent) -> bool:
	if main.results_layer == null or not main.results_layer.visible: return false
	match main.end_phase:
		"stinger":
			return event is InputEventKey or event is InputEventMouseButton     # keys and world clicks wait (0x427fb0)
		"box":
			# 0x574650: a click on the box leaves the battle (the results open).
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and end_box_rect().has_point(event.position):
				show_results()
			return event is InputEventKey or event is InputEventMouseButton
		"results":
			main.results_screen.screen_input(event)
			return true
	return false

# ------------------------------------------------------------------ S-2: setup rules and the hero's site contexts
## S-2 (SKIRMISH_RESEARCH.md "S-2"). Rules 0x70ae21.. reach the production gates 0x40c990; Tough Towers 0x41a8c0 also changes
## the towers the sides build. Battle of Titans: every slot has its Titan (0x70d61a), so none can build another.
func apply_rules_options(options: Dictionary):
	var gates: Dictionary = main.production.rules.options
	gates.no_dragons = bool(options.get("no_dragons", false))
	gates.no_fliers = bool(options.get("no_eyries", false))
	gates.no_lords = bool(options.get("no_titans", false)) or int(options.get("victory", 0)) == SkirmishVictory.TITANS
	gates.no_towers = bool(options.get("no_towers", false))
	gates.no_walls = bool(options.get("no_walls", false))
	if bool(options.get("tough_towers", false)):
		for letter in Encounters.TOWER_BY_RACE:
			var definition: Dictionary = main.production.rules.definition("BWT" + letter)
			if not definition.is_empty() and not definition.has("toughened"):
				Encounters.toughen(definition)
				definition["toughened"] = true

## 0x42a0d0's setup terms: Battle of Titans sets level 100, I Am The Greatest raises to 100, a temporary hero fixes the level.
func computer_hero_inputs(options: Dictionary) -> Dictionary:
	var inputs := {}
	if int(options.get("victory", 0)) == SkirmishVictory.TITANS: inputs.level_override = 100
	if bool(options.get("greatest", false)): inputs.at_least_100 = true
	if bool(options.get("temp_hero", false)): inputs.fixed_level = int(options.get("temp_hero_level", 10))
	return inputs

func place_option_units(resolved: Dictionary, players: Array):
	var options: Dictionary = resolved.options
	var victory := int(options.get("victory", 0))
	var size := Vector2i(main.collision.width, main.collision.height)
	for p in players:
		var slot: Dictionary = resolved.slots[p]
		if victory == SkirmishVictory.TITANS:
			var titan := "AT%sX" % MainScript.TITAN_LETTERS[clampi(int(slot.race), 0, 15)]
			main.add_unit(titan, main.navigator.free_cell_near(slot.start), p)
		if bool(options.get("no_heroes", false)):
			var codes: Array = [MainScript.NO_HERO_UNITS[clampi(int(slot.race), 0, 15)]]
			var first: Array = ArmySetup.data().computer[clampi(int(slot.race), 0, 15)]
			codes.append(String(first[0]))
			codes.append(String(first[0]))
			for code in codes: main.add_unit(code, main.navigator.free_cell_near(ArmySetup.placement_cell(slot.start, size, main.combat.rng)), p)
		if victory == SkirmishVictory.CAPTURE_FLAG:
			var id: int = main.encounters.place_site("BMFL", p, main.navigator.free_cell_near(slot.start))
			if id >= 0:
				main.skirmish.flag_ids[id] = main.skirmish.flag_ids.size()
				main.add_marker(main.production.building(id))

