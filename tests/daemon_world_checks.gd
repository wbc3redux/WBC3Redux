extends "res://tests/batch2_world_base.gd"
## B3-1: the Daemons (race 11) in the real scene (tests/batch2_world_base.gd, lists from tests/batch3_fixtures.json): the faction,
## then
## 1. Brood at a Summoning Tower (E4): at 35 of 40 army five Quasits for 150 gold, a second press within 3 s nothing;
## 2. Stormcall at a Lightning Spire (E6 / R2): 80 crystal, rain with the clock unchanged, the cell greys while it rains; pressed
##    during a fade it pays and brings no rain;
## 3. souls (E7 / E8): a Succubus kill leaves a soul; a Daemon low on mana goes to it, kills it and gains 25 mana; a soul is gone
##    after 120 s.
## B3-2 adds the casters' abilities by button and key.

func label() -> String: return "Daemon"
func race() -> int: return 11
func hall() -> String: return "BKV"
func worker() -> String: return "AVBX"
func lists_path() -> String: return "res://tests/batch3_fixtures.json"

func powers():
	# These checks are not about victory: Standard Victory is off for the rest of the run (as berserk_full_length does).
	if scene.skirmish != null: scene.skirmish.resolved["standard_victory_event"] = 0
	check(scene.skirmish == null or not scene.skirmish.over, "the match is still on")
	brood()
	stormcall()
	souls()
	casters()

## B3-2 (E15 / E18): the Daemon Summoner's Daemongate and Banish, by button and key.
func casters():
	caster_row("AVGX", [[0x46, 100, KEY_D], [0x48, 30, KEY_B]])

## The army limit set to `used + free` (the hero's command term, as tests/test_hero_spells.gd set_command).
func free_command(free: int):
	production.hero_commands[0] = 0
	var pop: Dictionary = production.population(0)
	production.hero_commands[0] = int(pop.current) + free - int(pop.maximum)

func brood():
	var towers: Array = buildings_of("BAS0") + buildings_of("BAS1") + buildings_of("BAS2")
	check(not towers.is_empty(), "a Summoning Tower stands")
	if towers.is_empty(): return
	var b = towers[0]
	free_command(5)
	select_building(b)
	var k := cell_with(0x44)
	check(k == 7 and bool(hud.cells[k].enabled) if k >= 0 else false, "Brood in cell 7, enabled with PBRD: %d" % k)
	if k < 0: return
	fund()
	scene.economy.stockpiles[0][0] = 1000
	var before: Array = units_of("AVBX")
	check(hud.press_cell(k), "Brood pressed")
	var made: Array = units_of("AVBX").filter(func(u): return not before.has(u))
	check(made.size() == 5 and int(scene.economy.resources(0)[0]) == 850, "35 of 40: five Quasits for 150 gold: %d, %d gold" % [made.size(), int(scene.economy.resources(0)[0])])
	free_command(5)
	before = units_of("AVBX")
	select_building(b)
	hud.press_cell(k)
	check(units_of("AVBX").size() == before.size(), "a second press within 3 s does nothing")
	production.hero_commands[0] = 0

func stormcall():
	var spires: Array = buildings_of("BWL0") + buildings_of("BWL1")
	if spires.is_empty():
		var site := free_site("BWL0")
		if site.x >= 0:
			var anchor: Vector2i = Placement.anchor(production.rules.definition("BWL0"), site)
			spires = [production.add_completed(0, "BWL0", anchor.x, anchor.y)]
	check(not spires.is_empty(), "a Lightning Spire stands")
	if spires.is_empty(): return
	var b = spires[0]
	var dn = scene.day_night
	if production.research_level(0, "PSCL") == 0: production.complete_research(0, "PSCL")
	while dn.mode != 0: advance(0.5)
	if dn.raining:
		dn.raining = false
		dn.stopping = false
	var night: bool = dn.is_night()
	select_building(b)
	var k := cell_with(0x47)
	check(k == 7 and bool(hud.cells[k].enabled), "Stormcall in cell 7, enabled while dry: %d" % k)
	if k < 0: return
	fund()
	scene.economy.stockpiles[0][2] = 100
	check(hud.press_cell(k), "Stormcall pressed")
	check(int(scene.economy.resources(0)[2]) == 20, "80 crystal")
	check(dn.raining and dn.storm, "a thunderstorm")
	advance(5.0)
	check(dn.is_night() == night and dn.raining, "the clock is unchanged and it still rains")
	select_building(b)
	check(not bool(hud.cells[cell_with(0x47)].enabled), "the cell greys while it rains")
	# during a fade: paid, no rain
	dn.raining = false
	dn.stopping = false
	if night: dn.to_day()
	else: dn.to_night()
	select_building(b)
	scene.economy.stockpiles[0][2] = 100
	check(hud.press_cell(cell_with(0x47)), "Stormcall pressed during a fade")
	check(int(scene.economy.resources(0)[2]) == 20 and not dn.raining, "during a fade it pays and brings no rain")
	while dn.mode != 0: advance(0.5)

func souls():
	var spot: Vector2i = scene.navigator.free_cell_near((home + scene.skirmish.slots[1].start) / 2)   # between the bases, away from both
	var succubus = scene.add_unit("AVIX", spot, 0)
	var killers: Array = []
	scene.combat.died.connect(func(kind, id, _owner):
		if kind == "unit": killers.append([id, scene.combat.last_killer]))
	var victim = scene.add_unit("AHIX", scene.navigator.free_cell_near(spot + Vector2i(1, 0)), 1)
	fighter(victim).hp = 1
	fighter(victim).script = -1
	fighter(succubus).script = -1
	var count: int = scene.units.size()
	scene.combat.order_attack(succubus.unit_id, "unit", victim.unit_id)
	var waited := 0.0
	while scene.combat.alive(fighter(victim)) and waited < 20.0:
		advance(0.1)
		waited += 0.1
	var souls_made: Array = scene.units.slice(count).filter(func(u): return u.type_id == "ACSO")
	var by: Array = killers.filter(func(k): return int(k[0]) == victim.unit_id)
	check(souls_made.size() == 1, "the Succubus kill leaves a soul (killer %s, the Succubus %d)" % [by, succubus.unit_id])
	if souls_made.is_empty(): return
	var soul = souls_made[0]
	check(soul.owner_id == 6, "the soul is the neutral player's")
	var daemon = scene.add_unit("AADE", scene.navigator.free_cell_near(soul.cell + Vector2i(-4, 3)), 0)
	var df = fighter(daemon)
	df["mana"] = 5
	var maximum: int = int(df.get("max_mana", 0))
	check(maximum >= 30, "the Daemon has a mana pool: %d" % maximum)
	waited = 0.0
	while scene.combat.alive(fighter(soul)) and waited < 60.0:
		advance(0.25)
		waited += 0.25
	check(not scene.combat.alive(fighter(soul)) and int(df.mana) >= mini(maximum, 30), "a Daemon low on mana hunts the soul and gains 25 mana: %d" % int(df.mana))
	# a soul left alone is gone after 120 s
	var victim2 = scene.add_unit("AHIX", scene.navigator.free_cell_near(spot + Vector2i(0, 4)), 1)
	fighter(victim2).hp = 1
	fighter(victim2).script = -1
	count = scene.units.size()
	scene.combat.order_attack(succubus.unit_id, "unit", victim2.unit_id)
	waited = 0.0
	while scene.combat.alive(fighter(victim2)) and waited < 20.0:
		advance(0.1)
		waited += 0.1
	scene.remove_unit_quietly(daemon)
	var second: Array = scene.units.slice(count).filter(func(u): return u.type_id == "ACSO")
	if second.is_empty(): return
	advance(119.0)
	check(scene.combat.alive(fighter(second[0])) or fighter(second[0]).state == "dying", "the soul lasts about 120 s")
	advance(2.0)
	check(not scene.combat.alive(fighter(second[0])), "and is gone after 120 s")
