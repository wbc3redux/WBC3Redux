extends "res://tests/batch2_world_base.gd"
## B4-1: the High Elves (race 6) in the real scene (tests/batch2_world_base.gd, lists from tests/batch4_fixtures.json): the faction
## (Ancient Wisp research held back), then
## 1. the merge (E1 / E2): the cell greys before PWSP; eight Wisps with 199 crystal become one Ancient Wisp and four Wisps, 99 left;
##    four Wisps 31 cells apart show no merge cell;
## 2. an Ancient Wisp adds 4 crystal to the 4 s cycle (E3);
## 3. Elcor's Balm (E10 / R8): the Q key with the Healer unselected heals a hurt unit across the map for 400 crystal;
## 4. Holy Word (E11 / R8): the Tower of the Moon's button with only good enemies near is refused, nothing paid; the O key with an
##    unselected, unfinished Cathedral and no evil unit pays 200 and casts.
## B4-2: the casters' abilities by button and key.

func label() -> String: return "High Elf"
func race() -> int: return 6
func hall() -> String: return "BKE"
func worker() -> String: return "AEBX"
func held() -> Array: return [RacePowers.MERGE_RESEARCH]
func lists_path() -> String: return "res://tests/batch4_fixtures.json"

func powers():
	if scene.skirmish != null: scene.skirmish.resolved["standard_victory_event"] = 0
	merge()
	income()
	elcor()
	holy()
	casters()

func casters():
	caster_row("AEDX", [[0x31, 30, KEY_U], [0x39, 40, KEY_H]])
	caster_row("AENX", [[0x34, 25, KEY_W], [0x3d, 50, KEY_I]])
	caster_row("AEOX", [[0x3c, 20, KEY_X]])
	caster_row("AEGX", [[0x19, 25, KEY_T]])
	freeze()

## E13: Freeze's cell greys below 45 mana while its key casts at 20.
func freeze():
	var u = scene.add_unit("AEOX", scene.navigator.free_cell_near(home + Vector2i(12, 8)), 0)
	var f = fighter(u)
	f["max_mana"] = 200
	f["mana"] = 44
	select_units([u])
	var k := cell_with(0x56)
	check(k >= 6 and not bool(hud.cells[k].enabled), "Freeze's cell is grey at 44 mana")
	var done: Array = []
	scene.combat.spells.cast_done.connect(func(info): done.append(info))
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	root.push_input(key)
	check(done.size() == 1 and int(f.mana) == 24, "F casts Freeze for 20: %d" % int(f.mana))

func wisps(n: int, at: Vector2i, step: int = 1) -> Array:
	var out: Array = []
	for i in n: out.append(scene.add_unit(RacePowers.WISP, scene.navigator.free_cell_near(at + Vector2i((i % 4) * step, i / 4)), 0))
	return out

func merge():
	var group := wisps(8, home + Vector2i(10, 8))
	select_units(group)
	var k := cell_with(RacePowers.MERGE_ICON)
	check(k >= 6, "eight Wisps show the merge cell: %d" % k)
	if k >= 0: check(not bool(hud.cells[k].enabled), "the merge cell is grey before Ancient Wisp research")
	research_now(RacePowers.MERGE_RESEARCH)
	var price: int = int(production.price_of(0, RacePowers.ANCIENT_WISP, RacePowers.WISP)[2])   # 100 (0x40b6b0; the hero's discount applies)
	scene.economy.stockpiles[0][2] = 2 * price - 1
	select_units(group)
	k = cell_with(RacePowers.MERGE_ICON)
	check(k >= 6 and bool(hud.cells[k].enabled), "the merge cell is enabled with PWSP and 100 crystal")
	var ancient_before: int = units_of(RacePowers.ANCIENT_WISP).size()
	if k >= 0: hud.press_cell(k)
	var left: Array = group.filter(func(u): return not u.removed and not u.dying)
	check(units_of(RacePowers.ANCIENT_WISP).size() == ancient_before + 1, "one Ancient Wisp: %d" % (units_of(RacePowers.ANCIENT_WISP).size() - ancient_before))
	check(left.size() == 4 and left == group.slice(4), "the first four merged, four Wisps stay: %d" % left.size())
	check(int(scene.economy.resources(0)[2]) == price - 1, "one price paid, %d crystal left: %d" % [price - 1, int(scene.economy.resources(0)[2])])
	var apart := wisps(4, home + Vector2i(-20, 14), 0)
	var far = scene.add_unit(RacePowers.WISP, scene.navigator.free_cell_near(apart[0].cell + Vector2i(31, 0)), 0)
	var spread := [apart[0], apart[1], apart[2], far]
	check(absi(far.cell.x - apart[0].cell.x) > 30, "the fourth Wisp more than 30 cells away")
	select_units(spread)
	check(cell_with(RacePowers.MERGE_ICON) < 0, "four Wisps 31 cells apart: no merge cell")

func income():
	var n: int = units_of(RacePowers.ANCIENT_WISP).size()
	check(n >= 1, "an Ancient Wisp stands")
	var other: Dictionary = scene.other_income(0)
	check(int(other.income[2]) == 4 * n and int(other.producers[2]) == 0, "%d Ancient Wisps: + %d crystal per cycle, no producer: %s" % [n, 4 * n, other])

func elcor():
	var healers: Array = buildings_of("BPHE")
	check(not healers.is_empty(), "a Healer stands")
	check(production.research_level(0, RacePowers.ELCOR_RESEARCH) != 0, "Elcor's Balm researched")
	if healers.is_empty(): return
	select_building(healers[0])
	var k := cell_with(RacePowers.ELCOR_ICON)
	check(k == 7 and bool(hud.cells[k].enabled), "the Healer shows Elcor's Balm in cell 7: %d" % k)
	var u = scene.add_unit("AHIX", scene.navigator.free_cell_near(home + Vector2i(30, -20)), 0)
	var f = fighter(u)
	f.max_hp = 300
	f.hp = 50
	u.hp = 50
	select_units([])
	fund()
	scene.economy.stockpiles[0][2] = 1000
	var key := InputEventKey.new()
	key.keycode = KEY_Q
	key.pressed = true
	root.push_input(key)
	check(int(scene.economy.resources(0)[2]) == 600, "Q pays 400 with the Healer unselected: %d" % int(scene.economy.resources(0)[2]))
	check(int(f.hp) == 150, "the hurt unit across the map healed 100: %d" % int(f.hp))

func holy():
	var towers: Array = buildings_of("BPMT")
	check(not towers.is_empty(), "a Tower of the Moon stands")
	check(production.research_level(0, RacePowers.HOLY_RESEARCH) != 0, "Holy Word researched")
	if towers.is_empty(): return
	var t = towers[0]
	var cell: Vector2i = scene.combat._building_sprite(t).cell
	var knight = scene.add_unit("AHIX", scene.navigator.free_cell_near(cell + Vector2i(5, 3)), 1)
	fighter(knight).script = -1
	select_building(t)
	var k := cell_with(RacePowers.HOLY_ICON)
	check(k == 8 and bool(hud.cells[k].enabled), "the Tower of the Moon shows Holy Word in cell 8: %d" % k)
	fund()
	scene.economy.stockpiles[0][2] = 1000
	advance(1.1)
	if k >= 0: hud.press_cell(k)
	check(int(scene.economy.resources(0)[2]) == 1000, "only good enemies near: refused, nothing paid")
	# the O key: an unselected, unfinished Cathedral (any race may own one), no evil unit: 200 and the record
	var site := free_site("BPCA")
	check(site.x >= 0, "a site for a Cathedral")
	if site.x < 0: return
	var anchor: Vector2i = Placement.anchor(production.rules.definition("BPCA"), site)
	var cathedral = production.add_completed(0, "BPCA", anchor.x, anchor.y)
	scene.add_marker(cathedral)
	cathedral.constructing = true
	var casts: Array = []
	scene.combat.spells.cast_done.connect(func(info): casts.append(info))
	select_units([])
	var key := InputEventKey.new()
	key.keycode = KEY_O
	key.pressed = true
	root.push_input(key)
	check(int(scene.economy.resources(0)[2]) == 800, "O pays 200 at an unfinished, unselected Cathedral: %d" % int(scene.economy.resources(0)[2]))
	check(casts.any(func(i): return int(i.record.kind) == 0x10 and int(i.caster.id) == int(cathedral.entity_id)), "the Holy Word record went out")
