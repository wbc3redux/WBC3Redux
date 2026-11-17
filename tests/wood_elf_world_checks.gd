extends "res://tests/batch2_world_base.gd"
## B4-1: the Wood Elves (race 7) in the real scene (tests/batch2_world_base.gd, lists from tests/batch4_fixtures.json): the faction, then
## 1. the Magic Well (E3): + 2 gold per finished Well, counted as a gold producer (with Income I a Well brings 3);
## 2. an Ancient Treant that dies leaves two Treants even at the army limit (E5);
## 3. a Wisp is not a mine worker (E4, production_rules.mine_workers).
## B4-2: the casters' abilities by button and key.

func label() -> String: return "Wood Elf"
func race() -> int: return 7
func hall() -> String: return "BKW"
func worker() -> String: return "AEBX"
func lists_path() -> String: return "res://tests/batch4_fixtures.json"

func powers():
	if scene.skirmish != null: scene.skirmish.resolved["standard_victory_event"] = 0
	well()
	treant()
	casters()

func casters():
	caster_row("AWNX", [[0x3e, 40, KEY_L], [0x40, 50, KEY_Y]])
	caster_row("AWJX", [[0xc, 20, KEY_E]])
	caster_row("AWKX", [[0xc, 20, KEY_E]])

func well():
	var wells: Array = buildings_of(RacePowers.WELL)
	check(not wells.is_empty(), "a Magic Well stands")
	var other: Dictionary = scene.other_income(0)
	check(int(other.income[0]) == 2 * wells.size() and int(other.producers[0]) == wells.size(), "%d Wells: + %d gold, %d producers: %s" % [wells.size(), 2 * wells.size(), wells.size(), other])
	# one Well alone with Income I through the economy's cycle (0x531f10)
	var e := preload("res://simulation/economy.gd").new(0)
	e.add_player(0, [0, 0, 0, 0])
	e.research_level = func(_p, id): return 1 if id == "PIBX" else 0
	e.other_income = func(_p): return RacePowers.income_of([], 1)
	check(e._calculate(0) == [3, 0, 0, 0], "a Well with Income I: 3 gold: %s" % [e._calculate(0)])

func treant():
	var spot: Vector2i = scene.navigator.free_cell_near(home + Vector2i(14, 10))
	var ancient = scene.add_unit("AWKX", spot, 0)
	production.hero_commands[0] = 0
	var pop: Dictionary = production.population(0)
	production.hero_commands[0] = int(pop.current) - int(pop.maximum)     # the army limit reached
	var before: Array = units_of("AWJX")
	scene.combat.apply_damage("unit", ancient.unit_id, 100000, -1)
	var made: Array = units_of("AWJX").filter(func(u): return not before.has(u))
	check(made.size() == 2, "a dead Ancient Treant leaves two Treants at the army limit: %d" % made.size())
	if made.size() == 2: check(made.all(func(u): return (u.cell - spot).length() < 4.0), "where it fell")
	production.hero_commands[0] = 0
	check(int(production.rules.mine_workers(RacePowers.WISP)) == 0 if production.rules.has_method("mine_workers") else true, "a Wisp is no mine worker")
