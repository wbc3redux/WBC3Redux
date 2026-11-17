extends "res://tests/batch2_world_base.gd"
## B4-1: the Dark Elves (race 8) in the real scene (tests/batch2_world_base.gd, lists from tests/batch4_fixtures.json): the faction, then
## 1. a dead Spider Priestess leaves six Spiders (E5);
## 2. a Queen Spider's kill leaves an egg; 40 s later Spiders hatch and the egg is gone (E6);
## 3. Sacrifice (E7): three Dark Infantry for 15 crystal, all dead; a second press within 3 s nothing;
## 4. class-5 poison (E9): a Spider poisons a man; never a Skeleton, a titan or a Quasit.
## B4-2: the casters' abilities by button and key.

func label() -> String: return "Dark Elf"
func race() -> int: return 8
func hall() -> String: return "BKT"
func worker() -> String: return "AEBX"
func lists_path() -> String: return "res://tests/batch4_fixtures.json"

func powers():
	if scene.skirmish != null: scene.skirmish.resolved["standard_victory_event"] = 0
	priestess()
	egg()
	sacrifice()
	poison()
	casters()

func casters():
	caster_row("AKNX", [[0x41, 35, KEY_P], [0x42, 45, KEY_Z], [0x43, 40, KEY_N]])
	caster_row("AKOX", [[0x59, 45, KEY_S]])
	caster_row("AKGX", [[0x1e, 35, KEY_V]])

func priestess():
	var p = scene.add_unit("AKOX", scene.navigator.free_cell_near(home + Vector2i(14, 10)), 0)
	var before: Array = units_of("AKKX")
	scene.combat.apply_damage("unit", p.unit_id, 100000, -1)
	var made: Array = units_of("AKKX").filter(func(u): return not before.has(u))
	check(made.size() == 6, "a dead Priestess leaves six Spiders: %d" % made.size())

func eggs() -> Array:
	return production.buildings.values().filter(func(b): return String(b.original_type_id) == RacePowers.EGG and int(b.owner) == 0)

func egg():
	var spot: Vector2i = scene.navigator.free_cell_near(home + Vector2i(-22, 18))
	var queen = scene.add_unit(RacePowers.QUEEN, spot, 0)
	var victim = scene.add_unit("AHIX", scene.navigator.free_cell_near(spot + Vector2i(3, 0)), 1)
	fighter(queen).script = -1
	fighter(victim).script = -1
	scene.combat.apply_damage("unit", victim.unit_id, 100000, queen.unit_id)
	check(eggs().size() == 1, "the Queen's kill leaves an egg: %d" % eggs().size())
	var before: Array = units_of("AKKX")
	advance(39.0)
	check(eggs().size() == 1, "the egg stands for 40 s")
	advance(2.0)
	var made: Array = units_of("AKKX").filter(func(u): return not before.has(u))
	check(made.size() >= 1 and made.size() <= 4, "Spiders hatch: %d" % made.size())
	check(eggs().is_empty(), "the egg is gone after the hatch")

func sacrifice():
	check(production.research_level(0, RacePowers.SACRIFICE_RESEARCH) != 0, "Sacrifice researched")
	var group: Array = []
	for i in 3: group.append(scene.add_unit("AKIX", scene.navigator.free_cell_near(home + Vector2i(16 + i, -12)), 0))
	select_units(group)
	var k := cell_with(RacePowers.SACRIFICE_ICON)
	check(k >= 6 and bool(hud.cells[k].enabled), "three Dark Infantry show Sacrifice, enabled: %d" % k)
	if k < 0: return
	fund()
	scene.economy.stockpiles[0][2] = 1000
	advance(3.1)
	select_units(group)
	hud.press_cell(k)
	check(group.all(func(u): return not scene.combat.alive(fighter(u))), "all three die")
	check(int(scene.economy.resources(0)[2]) == 985, "15 crystal: %d" % int(scene.economy.resources(0)[2]))
	var more: Array = [scene.add_unit("AKIX", scene.navigator.free_cell_near(home + Vector2i(16, -14)), 0)]
	select_units(more)
	k = cell_with(RacePowers.SACRIFICE_ICON)
	if k >= 0: hud.press_cell(k)
	check(scene.combat.alive(fighter(more[0])), "a second press within 3 s does nothing")
	var skeleton = scene.add_unit("AUIX", scene.navigator.free_cell_near(home + Vector2i(18, -14)), 0)
	select_units([more[0], skeleton])
	check(cell_with(RacePowers.SACRIFICE_ICON) < 0, "no Sacrifice with a Skeleton in the selection")

func poison():
	var spider = scene.add_unit("AKKX", scene.navigator.free_cell_near(home + Vector2i(-12, -16)), 0)
	check((int(fighter(spider).base.word_ae) >> 8) & 0xff == 5, "the Spider carries type class 5")
	for code in ["AUIX", "AVBX", "ATOX"]:
		var u = scene.add_unit(code, scene.navigator.free_cell_near(home + Vector2i(-14, -18)), 1)
		check(not scene.combat.spells.poisonable(fighter(u)), "%s cannot be poisoned" % code)
	var man = scene.add_unit("AHIX", scene.navigator.free_cell_near(home + Vector2i(-14, -20)), 1)
	check(scene.combat.spells.poisonable(fighter(man)), "a man can")
	var hits := 0
	for i in 40:
		scene.combat.spells.venom_hit(fighter(spider), fighter(man))
		if bool(fighter(man).get("poisoned", false)):
			hits = i + 1
			break
	check(hits > 0, "a Spider's hits poison a man (after %d)" % hits)
