extends "res://tests/batch2_world_base.gd"
## B5-1: the Ssrathi (race 13) in the real scene (tests/batch2_world_base.gd, lists from tests/batch5_fixtures.json): the faction
## (Construction held back), then
## 1. Couatl's Wrath (E5): the Sun Temple's cell 8, 750 gold, six meteors on the table's pattern round the temple; the W key free;
## 2. Construction (E11, decision 4): a Chameleon's building takes half its time once PCON is researched;
## 3. Snakemen poison a Knight and never a Snakeman (E9).
## B5-2: the casters' abilities by button and key.

func label() -> String: return "Ssrathi"
func race() -> int: return 13
func hall() -> String: return "BKL"
func worker() -> String: return "ALBX"
func held() -> Array: return [RacePowers.CONSTRUCTION_RESEARCH]
func lists_path() -> String: return "res://tests/batch5_fixtures.json"

func powers():
	if scene.skirmish != null: scene.skirmish.resolved["standard_victory_event"] = 0
	# The meteors' blast hits every owner (E5, Emulated): the hero by the temple would die and end the match (2026-11-13 run).
	if hero_unit != null and fighter(hero_unit) != null:
		fighter(hero_unit).max_hp = 100000
		fighter(hero_unit).hp = 100000
	construction()                                       # before the meteors, whose blast can wreck the Sects
	wrath()
	snakemen()
	casters()

func casters():
	caster_row("ALMX", [[0x58, 25, KEY_P], [0x5c, 30, KEY_C]])   # Poison Cloud, Cauterize (B5-2)
	caster_row("ALBX", [[0x1e, 35, KEY_V]])                # Invisibility with Blending (B5-2; PBLE researched)

func wrath():
	var temple = keep()
	check(temple != null and String(temple.original_type_id).begins_with("BKL"), "a Sun Temple stands")
	if temple == null: return
	check(production.research_level(0, RacePowers.WRATH_RESEARCH) != 0, "Couatl's Wrath researched")
	select_building(temple)
	var k := cell_with(RacePowers.WRATH_ICON)
	check(k == 8 and bool(hud.cells[k].enabled), "the Sun Temple shows Couatl's Wrath in cell 8: %d" % k)
	if k < 0: return
	fund()
	scene.economy.stockpiles[0][0] = 1000
	advance(1.1)
	var before: int = scene.combat.missiles.size()
	hud.press_cell(k)
	check(int(scene.economy.resources(0)[0]) == 250, "Couatl's Wrath costs 750 gold: %d left" % int(scene.economy.resources(0)[0]))
	var meteors: Array = scene.combat.missiles.slice(before).filter(func(m): return bool(m.get("meteor", false)))
	var cell: Vector2i = scene.combat._building_sprite(temple).cell
	var want: Array = RacePowers.METEOR_OFFSETS.slice(0, 6).map(func(o): return cell + Vector2i(int(o[0]), int(o[1])))
	check(meteors.map(func(m): return m.aim) == want, "six meteors on the pattern round the temple: %s" % [meteors.map(func(m): return m.aim - cell)])
	advance(4.0)
	check(scene.combat.missiles.filter(func(m): return bool(m.get("meteor", false))).is_empty(), "the meteors have landed")
	# the W key, the temple unselected: free
	select_units([])
	scene.economy.stockpiles[0][0] = 750
	before = scene.combat.missiles.size()
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	root.push_input(key)
	check(int(scene.economy.resources(0)[0]) == 750, "W is free: %d" % int(scene.economy.resources(0)[0]))
	check(scene.combat.missiles.slice(before).filter(func(m): return bool(m.get("meteor", false))).size() == 6, "W's six meteors")

func construction():
	var plain: int = production.time_of(0, "BAKS", worker())
	research_now(RacePowers.CONSTRUCTION_RESEARCH)
	var fast: int = production.time_of(0, "BAKS", worker())
	check(fast == (plain / 1000 >> 1) * 1000, "Construction halves the Chameleon's time: %d -> %d ms" % [plain, fast])
	var builder = null
	for u in units_of(worker()):
		if not u.inside_building: builder = u
	var site := free_site("BAKS")
	check(builder != null and site.x >= 0, "a Chameleon and a site for a Worker Sect")
	if builder == null or site.x < 0: return
	var cell: Vector2i = scene.navigator.free_cell_near(site)
	builder.position = scene.navigator.center(cell)
	builder.sync_cell()
	var seen = production.visibility
	production.visibility = null                         # the site rule of the faction build (no fog test), as whole_faction
	var placed: Dictionary = production.place_building(0, "BAKS", site, scene.game_ms(), builder.unit_id, worker(), builder.cell, builder)
	production.visibility = seen
	check(placed.get("ok", false), "the Worker Sect placed: %s" % placed.get("reason", ""))
	if placed.get("ok", false):
		var b = production.building(int(placed.id)) if placed.has("id") else placed.get("building")
		if b != null: check(int(b.finish_ms) - int(b.started_ms) == fast, "it takes the halved time: %d ms" % (int(b.finish_ms) - int(b.started_ms)))

func snakemen():
	var s = scene.add_unit("ALIX", scene.navigator.free_cell_near(home + Vector2i(-14, 12)), 0)
	var knight = scene.add_unit("AHIX", scene.navigator.free_cell_near(scene.combat.unit_cell(s.unit_id) + Vector2i(1, 0)), 1)
	var other = scene.add_unit("ALIX", scene.navigator.free_cell_near(scene.combat.unit_cell(s.unit_id) + Vector2i(0, 1)), 1)
	fighter(knight).script = -1
	var spells = scene.combat.spells
	var hit := 0
	for i in 60:
		spells.venom_hit(fighter(s), fighter(knight))
		if bool(fighter(knight).get("poisoned", false)):
			hit += 1
			scene.combat.set_poisoned(knight.unit_id, false)
		spells.venom_hit(fighter(s), fighter(other))
	check(hit > 8 and hit < 40, "a Snakeman poisons a Knight about 35 %% of hits: %d of 60" % hit)
	check(not bool(fighter(other).get("poisoned", false)), "never another Snakeman")
