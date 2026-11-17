extends SceneTree
## Playtest 2026-11-11 (second round): the fixes after the user's Undead game on Desert Sands.
## * Mine workers leave the population (0x4a74f0 -> 0x51a130(0) state 8; 0x533dc0 skips state 8), so a beaten computer
##   with Peasants in its mines can resign (AI Resignation) and Standard Victory follows.
## * Naming sets (0x434e90 / 0x435060) with scripted dice; quest group members get names.
## * A destroyed ordinary building leaves no rubble; only the treasure towers do (0x52b3e0 / 0x52f980 / 0x52fc50).
## * Walking ranged units given an attack on a unit in range stop after the step and shoot (0x51da60 replaces the walk).
## * Every race's upgrade and research pictures (Powerups<race>.bmp, table 0x439050), not only the Knights'.
## * A unit trained at a building with a rally point walks there and stays (the rally move is its current order).
## * The hero's aura (+0x190): walking speed +2 (0x51c460) and the info rows' bonuses; items' "cast spell" powers (0x529d20).
## * A mine can be selected; the info area draws it; the rally line is drawn for an own building with a rally point.
##   Godot --headless --path . --script res://tests/test_playtest_1111.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const NamingSets = preload("res://simulation/naming_sets.gd")
const ArtDataRef = preload("res://core/art_data.gd")
const Rubble = preload("res://battle/building_rubble.gd")

var checks := 0
var failures := 0

class Dice:
	var faces: Array = []
	var asked: Array = []
	func roll(count: int, sides: int, bonus: int = 0) -> int:
		asked.append(sides)
		return int(faces.pop_front()) if not faces.is_empty() else 1

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("Playtest 11-11 check failed: " + label)

func run():
	naming()
	powerups()
	await world()
	await walking_ranged()
	await rally_walk()
	await hero_terms()
	if failures > 0:
		print("Playtest 11-11 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Playtest 11-11 checks passed: %d" % checks)
	quit(0)

func entries(lines: Array, header: String) -> Array:
	var out: Array = []
	var on := false
	for line in lines:
		if line == header:
			on = true
			continue
		if not on: continue
		if String(line).begins_with("["): break
		if String(line) != "": out.append(line)
	return out

func naming():
	var sets: Array = NamingSets.sets()
	check(sets.size() == 16 and String(sets[0].file).ends_with("Standard.nam"), "16 naming sets imported, Standard first (0x6085d8)")
	if sets.size() < 16: return
	var lines: Array = sets[0].lines                            # Standard: 3 [NAME] / 100 [SYL1] [SYL2]
	var syl1 := entries(lines, "[SYL1]")
	var syl2 := entries(lines, "[SYL2]")
	var names := entries(lines, "[NAME]")
	var d := Dice.new()
	d.faces = [50, 2, 1]
	check(NamingSets.generate(lines, d) == String(syl1[2]) + String(syl2[1]), "roll 50 -> [SYL1][SYL2], each line at the zero-based roll (0x434fb0)")
	check(d.asked == [100, syl1.size(), syl2.size()], "dice 1d100, then 1d(count) per section (%s)" % [d.asked])
	d = Dice.new()
	d.faces = [2, 1]
	check(NamingSets.generate(lines, d) == String(names[1]), "roll 2 < 3 -> rule 0 [NAME]")
	d = Dice.new()
	d.faces = [100, names.size()]
	check(NamingSets.generate(lines, d) == "", "roll 100 matches no rule -> rule 0; the top roll adds nothing")
	check(NamingSets.generate(["[RULES]", "3 [NAME]"], Dice.new()) == null, "end of file inside the rules: no name")
	check(NamingSets.name_for(99, Dice.new()) == "Sirian", "an unknown set gives Sirian")

## Every race's upgrade pictures (0x439050 tables, 0x4d6e00 sheets): each Powerups<race>.bmp is 90 pixels per entry of
## its table (32 on the _Small sheet), and Feast of Garo (PBUR) is the Undead column 22.
func powerups():
	var hud_script = load("res://hud/game_hud.gd")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui_layout.json"))
	var extra: Dictionary = layout.get("extra_bitmaps", {})
	var bad: Array = []
	for r in 16:
		var name: String = hud_script.POWERUP_SHEETS[r]
		var count: int = hud_script.POWERUPS[r].size()
		var big: Dictionary = extra.get("Powerups%s.bmp" % name, {})
		var small: Dictionary = extra.get("Powerups%s_Small.bmp" % name, {})
		if big.is_empty() or small.is_empty() or int(big.size[0]) != 90 * count or int(small.size[0]) != 32 * count: bad.append([r, name, count, big.get("size"), small.get("size")])
	check(bad.is_empty(), "every race's Powerups sheets match its 0x439050 table (%s)" % [bad])
	check(hud_script.POWERUPS[2].find("PBUR") == 22 and hud_script.POWERUP_SHEETS[2] == "Undead", "Feast of Garo: PowerupsUndead.bmp column 22")

func world():
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 0)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	scene.start_skirmish(setup, "", null, "playtest-1111")
	scene.combat.ai_players.erase(0)
	if scene.ai_manager != null:
		for p in scene.ai_manager.players.size(): scene.ai_manager.players[p] = null
	# ---- a worker in a mine leaves the population
	var home: Vector2i = scene.skirmish.slots[0].start
	var mine_id := -1
	var best := 1 << 30
	for id in scene.mines.mines:
		var dd: int = maxi(absi(scene.mines.mines[id].anchor.x - home.x), absi(scene.mines.mines[id].anchor.y - home.y))
		if dd < best:
			best = dd
			mine_id = id
	scene.mines.convert(mine_id, 0)
	scene.mines.mines[mine_id].entity.owner = 0
	var mine_cell: Vector2i = scene.mines.mines[mine_id].cells[0]
	var peasants: Array = []
	for k in 4:
		var p = scene.add_unit("AHBX", scene.navigator.free_cell_near(mine_cell + Vector2i(0, 3 + k)), 0)
		scene.production.register_unit(p.unit_id, "AHBX", 0)          # as a trained Peasant is (production.gd)
		peasants.append(p)
	var before: int = int(scene.production.population(0).current)
	for p in peasants: p.selected = true
	scene.mine_order(mine_id)
	var inside := false
	for i in 40 * 30:
		scene.simulation_step(0.025)
		if peasants.all(func(p): return p.inside_building):
			inside = true
			break
	check(inside, "four Peasants enter the mine")
	var after: int = int(scene.production.population(0).current)
	check(after == before - 1, "they leave the population: four Peasants count 1 (0x533dc0), %d -> %d" % [before, after])
	# ---- a click on the mine selects it; the HUD draws its panel
	var point: Vector2 = scene.navigator.center(mine_cell)
	scene.visibility._reveal(scene.local_player, mine_cell, 4)          # the mine's cell explored
	scene.normal_play = true                                           # the player's click path (off in the fixture harness)
	scene.click_release(point, {"shift": false, "ctrl": false, "alt": false})
	check(scene.selected_mine_id == mine_id and scene.selected_building() == null, "a click on a mine selects it")
	if scene.hud != null:
		scene.hud.queue_redraw()
		await process_frame
		check(true, "the HUD draws the mine panel")
	scene.set_building_selection(-1)
	check(scene.selected_mine_id == -1, "selecting anything else clears the mine")
	# ---- a quest group with +0x3e set gets names
	var r: Dictionary = {}
	for rec in scene.encounters.quest_records():
		if int(rec.get("group_named", 0)) != 0 and bool(rec.reward_group): r = rec
	check(not r.is_empty(), "a quest record with a named group (+0x3e)")
	if not r.is_empty():
		var hero_cell: Vector2i = scene.skirmish.slots[0].start + Vector2i(4, 4)
		var reward: Dictionary = scene.encounters._reward(0, -1, r, {"picked": false, "record": r, "code": "BZMA"}, null, hero_cell, 1000)
		var named: Array = reward.units.filter(func(u): return u.has("name") and int(u.unit) >= 0)
		check(named.size() == int(r.group_count) and named.all(func(u): return String(scene.combat.fighters[int(u.unit)].get("name", "")) == String(u.name)),
			"every group member carries its name (%s)" % [named.map(func(u): return u.name)])
		check(reward.units.filter(func(u): return String(u.type) == String(r.get("unit", ""))).all(func(u): return not u.has("name")), "the single unit has none (+0x50 is empty)")
	# ---- a destroyed ordinary building leaves no rubble (0x52b3e0 -> 0x52f980: state 8); only treasure towers do
	check(Rubble.leaves_rubble("BTCE") and Rubble.leaves_rubble("BTEL") and not Rubble.leaves_rubble("BKK0") and not Rubble.leaves_rubble("BAGA"),
		"rubble only for the treasure towers BTCE / BTIN / BTDR / BTEL (0x52fc50)")
	var victim = null
	for id in scene.production.buildings:
		var b = scene.production.buildings[id]
		if int(b.owner) == 1 and not ArtDataRef.building_sheet(String(b.original_type_id), 5).is_empty(): victim = b
	if victim != null:
		if not scene.building_nodes.has(victim.entity_id): scene.add_marker(victim)
		await process_frame
		var marker_parent = scene.building_nodes[victim.entity_id].get_parent()
		victim.hit_points = 0
		scene.production._destroy(victim)
		for i in 3: await process_frame
		var left: Array = marker_parent.get_children().filter(func(n): return n.get_script() == Rubble)
		check(left.is_empty(), "the destroyed %s leaves no rubble (%d rubble nodes)" % [victim.original_type_id, left.size()])
	else:
		check(false, "an enemy building with a slot-5 sheet to destroy (%s)" % [scene.production.buildings.values().map(func(b): return [b.original_type_id, b.owner, scene.building_nodes.has(b.entity_id)])])
	scene.queue_free()
	await process_frame

## Three Liches walking past an enemy get an attack order with the enemy in range: each stops after its current cell step
## and shoots (before the fix two kept walking their old route for over a second).
func walking_ranged():
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 0)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	scene.start_skirmish(setup, "", null, "playtest-1111-ranged")
	scene.combat.ai_players.erase(0)
	if scene.ai_manager != null:
		for p in scene.ai_manager.players.size(): scene.ai_manager.players[p] = null
	scene.navigator.improved = false
	var home: Vector2i = scene.skirmish.slots[0].start + Vector2i(6, 6)
	var liches: Array = []
	for k in 3: liches.append(scene.add_unit("AUMX", scene.navigator.free_cell_near(home + Vector2i(0, k)), 0))
	var foe = scene.add_unit("AHKX", scene.navigator.free_cell_near(home + Vector2i(5, 1)), 1)
	scene.combat.fighters[foe.unit_id].script = 0
	scene.combat.fighters[foe.unit_id].hp = 100000
	for u in liches: u.selected = true
	scene.issue_move(scene.navigator.center(home + Vector2i(14, 1)), false, false, false, {})
	for i in 8: scene.simulation_step(0.025)
	var walking: bool = liches.all(func(u): return u.in_step or not u.orders.is_empty())
	var starts: Array = liches.map(func(u): return u.cell)
	var t0: int = scene.game_ms()
	scene.issue_attack({"kind": "unit", "id": foe.unit_id})
	var first := {}
	for i in 60:
		scene.simulation_step(0.025)
		for k in 3:
			if scene.combat.fighters[liches[k].unit_id].state == "swing" and not first.has(k):
				first[k] = [scene.game_ms() - t0, maxi(absi(liches[k].cell.x - starts[k].x), absi(liches[k].cell.y - starts[k].y))]
	check(walking, "the Liches are walking when the attack is ordered")
	check(first.size() == 3 and first.values().all(func(v): return int(v[0]) <= 1000 and int(v[1]) <= 1),
		"each walking Liche stops after its step and shoots within a second (ms, cells walked: %s)" % [first])
	scene.queue_free()
	await process_frame

## A unit trained at a building with a rally point 12 cells away walks there and is still there 20 s later (before the fix
## the attitude script walked it back to its spawn cell after a step or two).
func rally_walk():
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 0)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	setup.players[0].race = 0                       # Knights: the Keep BKK0 trains the Peasant AHBX
	scene.start_skirmish(setup, "", null, "playtest-1111-rally")
	scene.combat.ai_players.erase(0)
	if scene.ai_manager != null:
		for p in scene.ai_manager.players.size(): scene.ai_manager.players[p] = null
	# The default map starts player 0 with towers only: a finished Keep of its race next to the start trains a Peasant.
	var home: Vector2i = scene.skirmish.slots[0].start
	var b = scene.production.add_completed(0, "BKK0", home.x + 6, home.y + 6)
	var item := "AHBX"
	var queued: Dictionary = scene.production.enqueue(b.entity_id, item, scene.game_ms()) if b != null else {"ok": false, "reason": "no Keep placed"}
	if not queued.ok:
		print("rally setup: race %s, %s" % [scene.production.races.get(0), queued])
		b = null
	check(b != null, "a unit queued at an own building")
	if b == null: return
	var rally: Vector2i = scene.navigator.free_cell_near(scene.production.spawn_target(b) + Vector2i(12, 2))
	scene.production.set_rally(b.entity_id, rally)
	var made := []
	scene.production.unit_ready.connect(func(info): made.append(int(info.unit_id)))
	var since := -1
	for i in 40 * 120:
		scene.simulation_step(0.025)
		if not made.is_empty() and since < 0: since = i
		if since >= 0 and i - since >= 40 * 30: break
	check(not made.is_empty(), "the %s is trained" % item)
	if not made.is_empty():
		var u = scene.unit_by_id(int(made[0]))
		var d: int = maxi(absi(u.cell.x - rally.x), absi(u.cell.y - rally.y))
		check(d <= 2, "the trained %s stands at the rally point %s 30 s later: %s (%d cells off)" % [item, rally, u.cell, d])
	scene.queue_free()
	await process_frame

## The hero's aura and its items' cast-spell powers (playtest 2026-11-11).
func hero_terms():
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 0)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	setup.players[0].race = 0
	scene.start_skirmish(setup, "", null, "playtest-1111-hero")
	scene.combat.ai_players.erase(0)
	if scene.ai_manager != null:
		for p in scene.ai_manager.players.size(): scene.ai_manager.players[p] = null
	check(scene.combat.heroes.has(0), "player 0 has a hero")
	if not scene.combat.heroes.has(0): return
	var hero_f = scene.combat.fighters[scene.combat.heroes[0].unit]
	var at: Vector2i = scene.combat.unit_cell(hero_f.id)
	var sword = scene.add_unit("AHKX", scene.navigator.free_cell_near(at + Vector2i(2, 0)), 0)
	var f = scene.combat.fighters[sword.unit_id]
	var before: int = int(sword.base_speed)
	for i in 50: scene.simulation_step(0.025)
	check(bool(f.get("hero_aura", false)) and int(sword.base_speed) == before + 2, "a Swordsman by its hero walks 2 faster (0x51c460): %d -> %d" % [before, int(sword.base_speed)])
	var block: Dictionary = scene.combat.combat_block(f)
	check(scene.hud == null or scene.hud.bonus_text(int(f.stats.combat), preload("res://simulation/combat_rules.gd").effective_combat(block)) == "%d +4" % int(f.stats.combat),
		"the info row shows the aura's +4 Combat (0x51bd10)")
	# Items: Staff of Pyreakon casts spell 54 at 10 %; with the chance forced to 101 every strike casts until the cooldown.
	var staff := -1
	var items: Array = preload("res://simulation/hero_effects.gd").items_data().get("items", [])
	for i in items.size():
		if String(items[i].get("name", "")) == "Staff of Pyreakon": staff = i + 1
	check(staff > 0, "Staff of Pyreakon found")
	var profile = scene.combat.heroes[0].match.profile if scene.combat.heroes[0].match != null else null
	if staff > 0 and profile != null:
		var power: Dictionary = preload("res://simulation/hero_effects.gd").item(staff).powers.filter(func(pw): return int(pw.type) == 0x62)[0]
		var chance := int(power.chance)
		power.chance = 101
		profile.data.equipment[2] = staff
		var foe = scene.add_unit("AHKX", scene.navigator.free_cell_near(at + Vector2i(0, 2)), 1)
		hero_f.cooldown_until = 0
		var cast: bool = scene.combat.spells.item_casts(hero_f, "unit", foe.unit_id)
		check(cast and int(hero_f.get("cooldown_until", 0)) > 0, "a strike casts the staff's spell and sets the hero's cooldown (0x529d20 -> 0x5777a0)")
		check(not scene.combat.spells.item_casts(hero_f, "unit", foe.unit_id), "no item cast while the cooldown runs (+0x268)")
		power.chance = chance
		profile.data.equipment[2] = 0
	# Playtest 2026-11-12: a unit's shot is its Army.cfg shoot id where 0x53f180 is ported (the Liche throws EMF0).
	check(String(scene.unit_combat_stats("AUMX").get("missile", "")) == "EMF0", "the Liche's missile is the fireball EMF0 (Army.cfg, 0x53f180)")
	check(String(scene.unit_combat_stats("AHKX").get("missile", "EMA0")) != "EMF0", "a Swordsman has no fireball")
	scene.queue_free()
	await process_frame
