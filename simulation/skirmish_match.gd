extends RefCounted
## Skirmish match controller (milestone 10a, SKIRMISH_RESEARCH.md): the active-player table, one controller slot per
## player, the Standard Victory check, the end of the match and the result context for the hero writeback.
## Computer players plug in through `controllers[player]` (an object with update(now_ms, match)); 10a leaves them empty,
## so a computer side only defends with the attitude scripts of its units and towers.

const Setup = preload("res://simulation/skirmish_setup.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")
const Victory = preload("res://simulation/skirmish_victory.gd")
const UI_TIMER_MS := 50              # SetTimer(hWnd, 1, 0x32): the in-game panel's event 9 (REVIEW_ENCOUNTERS.md D1)
const EVENT_TICKS := 18              # 0x41e320 case 9: 0x74c414 counts to 0x12, then 0x514540
const CHECK_PASSES := 3              # 0x514540: its +4 counter counts to 3, then 0x516230 for each active player
const SHORT_MATCH_MS := 300000       # 0x41c520: 0x74b960 = (match time 0x748664 < 300 000); 0x4553f0 then pays the short award
const NEUTRAL := 6

signal player_eliminated(player: int)
signal cleanup(player: int)              # 0x534340: hand an eliminated side's objects over (main.gd applies it)
signal ended(outcome: Dictionary)
signal notice(text: String)

var resolved: Dictionary
var slots: Array
var allied: PackedByteArray          # 0x748915
var local := 0                       # 0x709100
var options: Dictionary
var controllers: Array = [null, null, null, null, null, null, null]
var eliminated: Array = [false, false, false, false, false, false, false]   # 0x748668, cleared by 0x4179f0
var hero_dead: Array = [false, false, false, false, false, false, false]    # player record +0x180 (0x709340), set by 0x5210b0
var quests_done: Array = [0, 0, 0, 0, 0, 0, 0]                              # 0x7494b6
var enemy_heroes_killed: Array = [0, 0, 0, 0, 0, 0, 0]                      # 0x744d5c
var hero_kills: Array = [0, 0, 0, 0, 0, 0, 0]                               # player record +0x176 (0x709336)
var stats: Array = []                # results-screen counters per player (0x732ee8.. and 0x739cf0..)
var combat
var production
var stop_defeat: Dictionary          # building code -> 16 side flags (Building.cfg [BUILDINGS] column at +0x48)
var match_id := ""
var started_ms := 0
var now_ms := 0
var next_tick_ms := UI_TIMER_MS
var event_counter := 0               # 0x74c414
var check_counter := 0               # event manager +4
var game_over := false               # 0x748914
var over := false
var outcome: Dictionary = {}
var result_applied := false
var retinue_units: Dictionary = {}   # str(unit id) -> retinue id: the deployed retinue (+0x1c8 / +0x1ca, 0x4406b0)
var retinue_result: Dictionary = {} # 0x43f3e0 once per match (main.run_retinue_scan): retinue, graveyard, candidates
var log: Array = []
var _building_owner: Dictionary = {}
# S-2 (skirmish_victory.gd): the victory option's event (0x41c7d0), its on-screen countdown 0x497c40 and the Capture the
# Flag table (building id -> flag number, 0x7494b4 flags). economy and mines are the world's (main.gd).
var victory_event: Dictionary = {}
var timer_total_ms := 0              # +0x232cc0, 0: no countdown; running while the elapsed time is below it (+0x232cb4)
var flag_ids: Dictionary = {}
var economy
var mines

func _init(resolved_setup: Dictionary, world_combat, world_production, catalogue: Dictionary, id: String = "match"):
	resolved = resolved_setup
	slots = resolved.slots
	allied = resolved.allied
	local = int(resolved.local)
	options = resolved.options
	combat = world_combat
	production = world_production
	match_id = id
	for row in catalogue.get("building_cfg", {}).get("buildings", []):
		stop_defeat[String(row.code)] = row.stop_defeat_sides
	for i in 7: stats.append({"troops_built": 0, "troops_lost": 0, "troops_killed": 0, "buildings_built": 0, "buildings_lost": 0, "buildings_destroyed": 0, "buildings_converted": 0})
	if combat != null:
		combat.died.connect(_on_died)
	# Method connections only: a lambda would capture this object and keep it alive through the world's signals.
	if production != null:
		production.unit_ready.connect(_on_unit_ready)
		production.building_completed.connect(_on_building_completed)
	victory_event = Victory.event_for(int(options.get("victory", 0)))
	timer_total_ms = int(victory_event.get("timer_s", 0)) * 1000

func dispose():
	controllers = [null, null, null, null, null, null, null]
	if combat != null and combat.died.is_connected(_on_died): combat.died.disconnect(_on_died)
	if production != null and production.unit_ready.is_connected(_on_unit_ready):
		production.unit_ready.disconnect(_on_unit_ready)
		production.building_completed.disconnect(_on_building_completed)
	combat = null
	production = null
	economy = null
	mines = null

func _on_unit_ready(info: Dictionary):
	_count(int(info.owner), "troops_built")

func _on_building_completed(id: int):
	if production.building(id) != null: _count(production.building(id).owner, "buildings_built")

func active(p: int) -> bool:
	return p >= 0 and p < Setup.SLOTS and bool(slots[p].active)

func is_allied(a: int, b: int) -> bool:
	return allied[b + a * 7] != 0

func race(p: int) -> int:
	return int(slots[p].race) if p >= 0 and p < 7 else 0

func elapsed_ms() -> int:
	return now_ms - started_ms

# --------------------------------------------------------------------------------------------- update
func update(time_ms: int):
	now_ms = time_ms
	for b in production.buildings.values(): _building_owner[b.entity_id] = b.owner
	for c in controllers:
		if c != null: c.update(time_ms, self)
	while next_tick_ms <= time_ms and not over:
		_timer_tick()
		next_tick_ms += UI_TIMER_MS

func _timer_tick():
	event_counter += 1
	if event_counter != EVENT_TICKS: return
	event_counter = 0
	check_counter += 1
	if check_counter != CHECK_PASSES: return
	check_counter = 0
	# 0x514540: 0x516230 for each active player that is not eliminated (players 0..5), every 54 timer ticks (2.7 s nominal).
	# 0x516230 evaluates Standard Victory only when 0x748a98 (SCN header byte 0x14c) is set.
	if int(resolved.get("standard_victory_event", 1)) == 0: return
	# S-2: 0x41c7d0 appends the option's event after the scenario's events: every map's event 0 is Standard Victory, so it
	# stays active and runs first (0x516230). On a Random Map the event table is empty and the option's event is event 0.
	var standard: bool = victory_event.is_empty() or int(resolved.get("scenario_events", 1)) > 0
	for p in Setup.SLOTS:
		if over or game_over: return
		if not active(p) or eliminated[p]: continue
		if standard: check_standard(p)
		if victory_event.is_empty() or over or game_over or eliminated[p]: continue
		check_event(p)

## S-2: one pass of 0x514670 on the option's event for side `p` (Emulated), then 0x516230's message 0x1c2 or the tie 0x1d0.
func check_event(p: int):
	var r: Dictionary = Victory.evaluate(victory_world(), victory_event, p)
	match String(r.kind):
		"defeat":
			if p == local: game_over = true
			_message(int(r.player), false, "victory_option")
		"win": _message(int(r.player), true, "victory_option")
		"tie": extend_event(Victory.TIE_EXTENSION_S)

## 0x4aecd0 (message 0x1d0): the event's delay grows and the countdown restarts with the extra time; the line 0x16f is shown.
func extend_event(seconds: int):
	victory_event.delay_s = int(victory_event.delay_s) + seconds
	timer_total_ms = elapsed_ms() + seconds * 1000
	log.append({"t": now_ms, "tie": seconds})
	notice.emit("Tie! The contest goes on.")

func timer_running() -> bool:
	return timer_total_ms > 0 and elapsed_ms() < timer_total_ms

func timer_left_ms() -> int:
	return maxi(0, timer_total_ms - elapsed_ms()) if timer_total_ms > 0 else 0

## The world of 0x514670's new conditions, in skirmish_victory.gd's shape.
func victory_world() -> Dictionary:
	var objects: Array = [[], [], [], [], [], [], []]
	var heroes: Array = [null, null, null, null, null, null, null]
	for f in combat.fighters.values():
		if f.removed: continue
		var list: int = int(f.get("list", f.owner))
		if list >= 0 and list < 7: objects[list].append({"kind": "unit", "hp": int(f.hp)})
	for owner in combat.heroes:
		var h = combat.fighters.get(combat.heroes[owner].unit)
		if h != null and not h.removed and int(owner) < 7: heroes[int(owner)] = int(h.hp)
	for b in production.buildings.values():
		if int(b.owner) < 0 or int(b.owner) >= 7: continue
		var code: String = String(b.original_type_id)
		objects[int(b.owner)].append({"kind": "building", "hp": int(b.hit_points), "resource": false, "code": code,
			"keep": code.length() == 4 and code[1] == "K", "level": ProductionRules.level_digit(code), "flag": int(flag_ids.get(b.entity_id, -1))})
	if mines != null:
		for id in mines.mines:                             # a mine's rates make it a resource building (0x52b050)
			var owner: int = int(mines.owner_of(int(id)))
			if owner >= 0 and owner < 7: objects[owner].append({"kind": "building", "hp": 1, "resource": true, "code": "", "keep": false, "level": 0})
	var rows := []
	for a in 7:
		var cols := []
		for b in 7: cols.append(allied[b + a * 7])
		rows.append(cols)
	var resources: Array = []
	var razed: Array = []
	var killed: Array = []
	for p in 7:
		resources.append(economy.resources(p).duplicate() if economy != null and active(p) else [0, 0, 0, 0])
		razed.append(int(stats[p].buildings_destroyed))
		killed.append(int(stats[p].troops_killed))
	return {"active": range(7).map(func(p): return active(p)), "eliminated": eliminated, "allied": rows, "local": local,
		"seconds": elapsed_ms() / 1000, "timer_running": timer_running(), "objects": objects, "heroes": heroes,
		"resources": resources, "razed": razed, "killed": killed, "flags": flag_ids.size()}

## 0x429c20 for the HUD: the score panel's rows (-1 hides one), empty when the option has no panel.
func score_rows() -> Array:
	if not bool(victory_event.get("score", false)) or combat == null: return []
	return Victory.scores(int(options.get("victory", 0)), victory_world())

## Per-object test of 0x514670 case 10, `obj.vtable[0x58](player)` for an object in that player's list.
## Units 0x51a1c0 (Emulated): the hero flag +0xb4 counts at once; otherwise hit points (+0x9c via vtable +0x3c) >= 1, state
## (+0x2a) not 8, owner not 6, allied with the player, and the +0x30 byte clear (Open: never set in the slice).
## Buildings 0x52a3e0 / 0x5876f0 (Emulated): owner not 6 and the Building.cfg [BUILDINGS] side flag at +0x48 + the player's race.
## A player's list ([0xafd4cc] + 4 * (player + 1)) holds that player's objects; `list` overrides it only in fixtures.
func counts_for(p: int) -> bool:
	for f in combat.fighters.values():
		if int(f.get("list", f.owner)) != p or f.removed: continue
		if f.hero: return true
		if int(f.hp) >= 1 and f.state != "dying" and f.state != "corpse" and int(f.owner) != NEUTRAL and is_allied(p, int(f.owner)) \
				and not f.get("flag_30", false): return true
	for b in production.buildings.values():
		if int(b.owner) != p or int(b.owner) == NEUTRAL: continue
		var sides: Array = stop_defeat.get(b.original_type_id, [])
		if race(p) < sides.size() and bool(sides[race(p)]): return true
	return false

## 0x514670 case 10 (Standard Victory, event 0 installed by 0x41c7d0 for victory option 0), evaluated for side `p`
## (Emulated, 1,500 cases): the side is defeated when its own list has nothing that counts; it wins when no active,
## non-eliminated, non-allied player has anything that counts. Then 0x516230 sends message 0x1c2 (handled by 0x4addc0).
func check_standard(p: int):
	if game_over: return
	var decision := evaluate_standard(p)
	if decision < 0:
		if p == local: game_over = true
		_message(p, false)
	elif decision > 0:
		_message(p, true)

## The decision of 0x514670 case 10 alone: -1 the side is defeated, 1 it has won, 0 nothing yet.
func evaluate_standard(p: int) -> int:
	var won := true
	for i in Setup.SLOTS:
		if not active(i) or eliminated[i]: continue
		var alive := counts_for(i)
		if i == p:
			if not alive: return -1
		elif alive and not is_allied(p, i):
			won = false
	return 1 if won else 0

## 0x4addc0: message 0x1c2 (player, flag). Flag 0: the player is out; flag 1: the player won.
func _message(p: int, won: bool, reason: String = "standard"):
	log.append({"t": now_ms, "player": p, "won": won})
	if p == local:
		game_over = true
		if not won: eliminated[p] = true
		_end(won, reason)
		return
	if not won:
		if eliminated[p]: return
		for q in 5:                                          # the original scans players 0..4 here
			if active(q) and not eliminated[q] and q != local:
				eliminated[p] = true
				player_eliminated.emit(p)
				cleanup.emit(p)
				notice.emit("Player %d has been defeated." % p)
				return
		game_over = true
		_end(true, reason)
		return
	game_over = true
	if not is_allied(local, p):
		eliminated[local] = true
		_end(false, reason)
	else:
		_end(true, reason)

## The in-game menu's quit (0x55ccd0 case 4): 0x514450(0) arms 0x514480, which ends the match through 0x41c520 with victory
## flag 0 after more than 10 calls; 0x458bb0 calls it once per main-loop frame, so the defeat comes 11 frames later.
const QUIT_FRAMES := 11
var quit_frames := -1

func quit():
	if over or quit_frames >= 0: return
	quit_frames = 0

## One main-loop frame (main.gd simulation_step).
func frame():
	if quit_frames < 0 or over: return
	quit_frames += 1
	if quit_frames >= QUIT_FRAMES:
		game_over = true
		eliminated[local] = true
		_end(false, "quit")

func _end(won: bool, reason: String):
	if over: return
	over = true
	outcome = {"won": won, "reason": reason, "ended_ms": now_ms, "elapsed_ms": elapsed_ms(), "short": elapsed_ms() < SHORT_MATCH_MS}
	ended.emit(outcome)

# --------------------------------------------------------------------------------------------- counters
func _count(p: int, key: String):
	if p >= 0 and p < stats.size(): stats[p][key] += 1

func _on_died(kind: String, id: int, killer_owner: int):
	if kind == "building":
		var owner: int = int(_building_owner.get(id, -1))
		_count(owner, "buildings_lost")
		if killer_owner >= 0 and killer_owner != owner: _count(killer_owner, "buildings_destroyed")
		return
	var f = combat.fighters.get(id)
	if f == null: return
	var owner: int = int(f.owner)
	if owner == NEUTRAL and combat.ai.is_animal(f.type_id): return
	_count(owner, "troops_lost")
	if killer_owner >= 0 and killer_owner != owner:
		_count(killer_owner, "troops_killed")
		var killer = combat.fighters.get(int(combat.last_killer))
		if killer != null and killer.hero: hero_kills[killer_owner] += 1
	if f.hero:
		hero_dead[owner] = true
		if killer_owner >= 0 and killer_owner != owner and killer_owner < 7: enemy_heroes_killed[killer_owner] += 1

## Milestone 12: 0x4a6cc0 -> 0x518f40 on a conversion. A resource building (0x52b050: a non-zero rate) is event 0xb for the
## new owner (0x744d78 converted +1 and Buildings Built 0x739cf0 +1); any other building is event 0 for the old owner
## (Buildings Lost 0x739cf4) and event 1 for the new owner (Buildings Built). Read.
func note_conversion(previous: int, owner: int, resource: bool):
	if resource:
		_count(owner, "buildings_converted")
		_count(owner, "buildings_built")
	else:
		_count(previous, "buildings_lost")
		_count(owner, "buildings_built")

func note_quest(p: int):
	if p >= 0 and p < 7: quests_done[p] += 1

# --------------------------------------------------------------------------------------------- hero terms
## 0x5268c0 = 0x5269a0 / 2 (Read): derived statistic 12 (0x54a6a0 -> 0x54a720 mode 1), plus Leadership (skill 8) and the
## race skill (Knights: 67 Knight Lord) through 0x556b50 / 0x556ea0 (multipliers Emulated: 8 x1, 67 x2). Item, research
## and 0x70d622 terms are 0 here (no item stat resolver; research absent; 0x70d622 starts at 0).
static func command_term(profile_data: Dictionary) -> int:
	var total := HeroRules.derived(profile_data.stats, 0xc, 1)
	for skill in profile_data.skills:
		if int(skill.id) == 8: total += int(skill.rank)
		elif int(skill.id) == 67: total += int(skill.rank) * 2
	return total / 2

# --------------------------------------------------------------------------------------------- results
## Inputs of 0x4553f0's ordinary branch for player `p` (field mapping in SKIRMISH_RESEARCH.md). `troops_lost` keeps the
## name used by HeroRules; it is fed from 0x732eea, which the results screen labels "Troops Killed".
func result_context(p: int, hero_level: int) -> Dictionary:
	var players: Array = []
	var rows: Array = []
	for i in Setup.SLOTS:
		players.append({"active": active(i), "ai": bool(slots[i].computer), "setup_points": int(slots[i].resources),
			"difficulty": int(slots[i].difficulty), "eliminated": bool(eliminated[i])})
		var row: Array = []
		for j in Setup.SLOTS: row.append(is_allied(i, j))
		rows.append(row)
	var won: bool = bool(outcome.get("won", false))
	return {"player": p, "players": players, "allied": rows, "won": won, "map_size": int(resolved.map_width),
		"quests": int(quests_done[p]), "hero_enemy_kills": int(hero_kills[p]), "troops_lost": int(stats[p].troops_killed),
		"enemy_heroes_killed": int(enemy_heroes_killed[p]), "visibility_object": true,
		"visibility_a": int(options.vision) == 1 or int(options.vision) == 2, "visibility_b": bool(options.hidden_map),
		"unit_setup": int(options.build_level), "special_victory_bonus": false, "hero_died": bool(hero_dead[p]),
		"hero_level": hero_level, "no_award": false,
		"short_match": bool(outcome.get("short", false)), "victory_option": int(options.victory),
		# Milestone 11b: the race the player plays (0x708f96) indexes the hero's per-race win counter (0x4549a7).
		"slot_race": int(slots[p].race)}

## Results acceptance (0x454b70 computes the award, the Continue button 0x4549.. counts the win and adds the queued
## levels; the save follows the allocation / retinue screens). Applies once per match: the result id is the match id.
func apply_result(store, hero_match) -> bool:
	if not over or hero_match == null or hero_match.profile == null: return false
	if result_applied: return true
	if bool(options.get("temp_hero", false)):              # S-2: a temporary hero has no hero book record (0x749c63, 0x4553f0's caller)
		result_applied = true
		return true
	var context := result_context(local, int(hero_match.profile.data.level))
	var changes: Dictionary = hero_match.inventory_changes()
	if not retinue_result.is_empty(): changes["retinue_scan"] = {"retinue": retinue_result.retinue, "graveyard": retinue_result.graveyard}
	if not hero_match.finish(store, match_id, context, changes, true): return false
	result_applied = true
	return true

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). The setup (resolved, slots, options,
## allied) and the Building.cfg flags come from the same setup when the match is started again for the load; the
## controllers are the scene's. `eliminated` is refilled in place (encounters.player_byte_748668 shares it).
const _SAVE_SKIP := ["resolved", "slots", "allied", "options", "controllers", "combat", "production", "stop_defeat", "economy", "mines"]

func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self, _SAVE_SKIP)

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state, _SAVE_SKIP)
