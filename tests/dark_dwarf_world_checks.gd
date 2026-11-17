extends "res://tests/batch2_world_base.gd"
## B3-1: the Dark Dwarves (race 10) in the real scene (tests/batch2_world_base.gd, lists from tests/batch3_fixtures.json): the
## faction, then
## 1. Ancestral Spirit I / II at the Ancestral Hall (E3 / E5): cells 7 and 8, one Wraith for 125 crystal with no experience, a
##    second press within 1 s does nothing, one Shadow for 250;
## 2. a Firebomb among enemies (E9): it explodes at its hit entry, its attack less armour next to it, half two cells out, and
##    spares its owner's unit.
## B3-2 adds the casters' abilities by button and key.

func label() -> String: return "Dark Dwarf"
func race() -> int: return 10
func hall() -> String: return "BKA"
func worker() -> String: return "AABX"
func lists_path() -> String: return "res://tests/batch3_fixtures.json"

func powers():
	spirits()
	firebomb()
	casters()

## B3-2 (E15 / E18): the Iron Golem's Firebomb and the Engineer's Earthpower by button and key; the Bronze Golem's Salvage,
## always enabled, by button and key, once a second, near a destroyed building's debris.
func casters():
	caster_row("AAJX", [[0x55, 35, KEY_F]])
	caster_row("AABX", [[0x4b, 40, KEY_E]])
	salvage()

func salvage():
	var golem = scene.add_unit("AAGX", scene.navigator.free_cell_near(home + Vector2i(-14, 10)), 0)
	scene.combat.debris.append(golem.cell + Vector2i(2, 0))
	select_units([golem])
	var k := cell_with(0x4c)
	check(k >= 6 and bool(hud.cells[k].enabled), "Salvage's cell, always enabled: %d" % k)
	if k < 0: return
	var done: Array = []
	scene.combat.spells.cast_done.connect(func(info): done.append(info))
	var before: Array = scene.economy.resources(0)
	scene.economy.refresh_capacity(0)
	check(hud.press_cell(k) and done.size() == 1, "Salvage pressed")
	check(int(done[-1].record.kind) == 0x21 if not done.is_empty() else false, "record kind 0x21")
	var key := InputEventKey.new()
	key.keycode = KEY_Z
	key.pressed = true
	root.push_input(key)
	check(done.size() == 1, "the key within the second does nothing")
	advance(1.1)
	select_units([golem])
	root.push_input(key)
	check(done.size() == 2, "a second later the key salvages")
	check(scene.combat.debris.size() >= 1, "the debris stays")

func spirits():
	var halls: Array = buildings_of("BPAH")
	check(not halls.is_empty(), "an Ancestral Hall stands")
	if halls.is_empty(): return
	var b = halls[0]
	select_building(b)
	var k7 := cell_with(0x49)
	var k8 := cell_with(0x4a)
	check(k7 == 7 and k8 == 8, "Ancestral Spirit I in cell 7, II in cell 8: %d, %d" % [k7, k8])
	if k7 < 0 or k8 < 0: return
	check(bool(hud.cells[k7].enabled) and bool(hud.cells[k8].enabled) and String(hud.cells[k7].tip) != "", "both enabled with PAS0 / PAS1, with tooltips")
	for tier in [1, 2]:
		var code: String = "AUKX" if tier == 1 else "AUXX"
		var price: int = 125 if tier == 1 else 250
		fund()
		scene.economy.stockpiles[0][2] = price + 10
		var before: Array = units_of(code)
		check(hud.press_cell(k7 if tier == 1 else k8), "Spirit %d pressed" % tier)
		var made: Array = units_of(code).filter(func(u): return not before.has(u))
		check(made.size() == 1, "one %s at once: %d" % [code, made.size()])
		check(int(scene.economy.resources(0)[2]) == 10, "%d crystal paid" % price)
		if not made.is_empty(): check(int(fighter(made[0]).xp) == 0, "%s from the button has no experience: %d" % [code, int(fighter(made[0]).xp)])
		fund()
		before = units_of(code)
		select_building(b)
		hud.press_cell(k7 if tier == 1 else k8)
		check(units_of(code).size() == before.size(), "a second press within 1 s does nothing")
		advance(1.1)
		select_building(b)

func firebomb():
	var spot: Vector2i = scene.navigator.free_cell_near(home + Vector2i(18, 14))
	var bomb = scene.add_unit("AASX", spot, 0)
	var target = scene.add_unit("AHIX", scene.navigator.free_cell_near(spot + Vector2i(1, 0)), 1)
	var far = scene.add_unit("AHIX", scene.navigator.free_cell_near(target.cell + Vector2i(1, 0)), 1)
	var own = scene.add_unit("AAIX", scene.navigator.free_cell_near(spot + Vector2i(-1, 0)), 0)
	for u in [target, far, own]:
		fighter(u).max_hp = 1000
		fighter(u).hp = 1000
		fighter(u).script = -1
	fighter(bomb).script = -1
	scene.combat.order_attack(bomb.unit_id, "unit", target.unit_id)
	var waited := 0.0
	while scene.combat.alive(fighter(bomb)) and waited < 20.0:
		advance(0.1)
		waited += 0.1
	check(not scene.combat.alive(fighter(bomb)), "the Firebomb explodes")
	var near_d: int = 1000 - int(fighter(target).hp)
	var far_d: int = 1000 - int(fighter(far).hp)
	var gap: Vector2i = far.cell - spot
	check(near_d > 0, "the target takes the blast: %d" % near_d)
	if maxi(absi(gap.x), absi(gap.y)) == 2: check(far_d > 0 and far_d < near_d, "two cells out: less (%d against %d)" % [far_d, near_d])
	check(int(fighter(own).hp) == 1000, "its owner's unit is spared")
