extends "res://tests/batch2_world_base.gd"
## B5-1: the Plaguelords (race 15) in the real scene (tests/batch2_world_base.gd, lists from tests/batch5_fixtures.json): the faction
## (Contagion III-V held back), then
## 1. Chaos Plague (E4): the Hall's cell 8 with Contagion II and an enemy 14 cells away: 1000 crystal, every enemy unit within 28 at
##    47 % of its hit points; a second press within 1 s does nothing; an enemy only 15 cells away: refused, nothing paid; the C key
##    with 1000 crystal: the plague and no payment (decision 1);
## 2. a Spore next to Knights explodes at its hit entry (E7), 35 / 15 to an AHIX, its owner spared;
## 3. Ghouls disease a Knight and never a Skeleton (E9).
## B5-2: the casters' abilities by button and key.

func label() -> String: return "Plaguelord"
func race() -> int: return 15
func hall() -> String: return "BKG"
func worker() -> String: return "AUBX"
func held() -> Array: return ["PCN2", "PCN3", "PCN4"]
func lists_path() -> String: return "res://tests/batch5_fixtures.json"

func powers():
	if scene.skirmish != null: scene.skirmish.resolved["standard_victory_event"] = 0
	chaos()
	spore()
	ghouls()
	casters()

func casters():
	caster_row("AGGX", [[0x53, 30, KEY_E], [0x52, 55, KEY_P]])   # Eye of Oros, Plague Cloud (B5-2)

func enemy_at(cell: Vector2i, hp := 400):
	var u = scene.add_unit("AHIX", scene.navigator.free_cell_near(cell), 1)
	var f = fighter(u)
	f.script = -1
	f.max_hp = maxi(int(f.max_hp), hp)
	f.hp = hp
	u.hp = hp
	return u

func chaos():
	var hall_b = keep()
	check(hall_b != null and String(hall_b.original_type_id).begins_with("BKG"), "a Hall of Plague stands")
	if hall_b == null: return
	check(RacePowers.chaos_level(func(c): return production.research_level(0, c) != 0) == 2, "Contagion II held")
	var cell: Vector2i = scene.combat._building_sprite(hall_b).cell
	# After the whole-faction build other units may stand by the Hall (0x5002e0 counts any living unit that is not own or allied,
	# animals and monsters too): the checks below place their own enemies, so the square of the plague's reach is cleared first.
	var cleared: Array = []
	for f in scene.combat.fighters.values():
		if int(f.owner) == 0 or f.removed or not scene.combat.alive(f): continue
		var c: Vector2i = scene.combat.unit_cell(int(f.id))
		if maxi(absi(c.x - cell.x), absi(c.y - cell.y)) > 30: continue
		cleared.append("%s of %d at %s" % [f.type_id, int(f.owner), c - cell])
		scene.remove_unit_quietly(scene.units[int(f.id)])
	print("Chaos Plague: cleared by the Hall: %s" % [cleared])
	# an enemy only 15 cells away (on the axis): refused, nothing paid
	var far_only = enemy_at(cell + Vector2i(15, 0))
	var at: Vector2i = scene.combat.unit_cell(far_only.unit_id)
	select_building(hall_b)
	var k := cell_with(RacePowers.CHAOS_ICON)
	check(k == 8 and bool(hud.cells[k].enabled), "the Hall shows Chaos Plague in cell 8: %d" % k)
	if k < 0: return
	fund()
	scene.economy.stockpiles[0][2] = 1000
	advance(1.1)
	if maxi(absi(at.x - cell.x), absi(at.y - cell.y)) > 14:
		hud.press_cell(k)
		check(int(scene.economy.resources(0)[2]) == 1000 and int(fighter(far_only).hp) == 400, "an enemy 15 cells away: refused, nothing paid")
	var near = enemy_at(cell + Vector2i(14, 0))
	var near_at: Vector2i = scene.combat.unit_cell(near.unit_id)
	check(maxi(absi(near_at.x - cell.x), absi(near_at.y - cell.y)) <= 14, "an enemy within 14 cells: %s" % (near_at - cell))
	advance(1.1)
	var hp_far := int(fighter(far_only).hp)
	var hp_near := int(fighter(near).hp)
	select_building(hall_b)
	hud.press_cell(k)
	check(int(scene.economy.resources(0)[2]) == 0, "Chaos Plague costs 1000 crystal: %d left" % int(scene.economy.resources(0)[2]))
	check(int(fighter(near).hp) == hp_near * 47 / 100 and int(fighter(far_only).hp) == hp_far * 47 / 100, "the enemies keep 47 %%: %d, %d" % [int(fighter(near).hp), int(fighter(far_only).hp)])
	scene.economy.stockpiles[0][2] = 1000
	hud.press_cell(k)
	check(int(scene.economy.resources(0)[2]) == 1000, "a second press within 1 s does nothing")
	# the C key: free (decision 1), the hall unselected
	select_units([])
	var hp_before := int(fighter(near).hp)
	var key := InputEventKey.new()
	key.keycode = KEY_C
	key.pressed = true
	root.push_input(key)
	check(int(scene.economy.resources(0)[2]) == 1000, "C casts without payment: %d" % int(scene.economy.resources(0)[2]))
	check(int(fighter(near).hp) == hp_before * 47 / 100, "C's plague: %d -> %d" % [hp_before, int(fighter(near).hp)])

func spore():
	var at := home + Vector2i(-14, 12)
	var s = scene.add_unit("AGSP", scene.navigator.free_cell_near(at), 0)
	var c: Vector2i = scene.combat.unit_cell(s.unit_id)
	var knight = enemy_at(c + Vector2i(1, 0), 500)
	var own = scene.add_unit("AHIX", scene.navigator.free_cell_near(c + Vector2i(0, 1)), 0)
	var own_hp := int(fighter(own).hp)
	var kc: Vector2i = scene.combat.unit_cell(knight.unit_id)
	if (kc - c).abs() != Vector2i(1, 0):
		check(false, "the Knight next to the Spore: %s" % (kc - c))
		return
	# the blast is the Spore's own attack (ARM 40 + 5 per Virus level through the attack getter; here the hero's bonuses too)
	var CR = preload("res://simulation/combat_rules.gd")
	var kb: Dictionary = scene.combat.combat_block(fighter(knight))
	var want := CR.armour_tail(int(scene.combat.combat_block(fighter(s)).dmg), RacePowers.BLAST_MODE, RacePowers.BLAST_DTYPE, CR.armour_table(kb), CR.resist_flags(kb))
	var virus := 0
	for code in ["PVI0", "PVI1", "PVI2", "PVI3", "PVI4", "PVI5"]: if production.research_level(0, code) != 0: virus += 1
	scene.combat._hit(fighter(s), {"target_kind": "unit", "target_id": knight.unit_id, "ranged": false, "result": {"damage": 99, "effect": 0, "param": 0}})
	check(not scene.combat.alive(fighter(s)), "the Spore dies at its hit entry")
	check(500 - int(fighter(knight).hp) == want and want >= 35 + 5 * virus, "the Knight next to it takes the blast (Virus %d): %d, expected %d" % [virus, 500 - int(fighter(knight).hp), want])
	check(int(fighter(own).hp) == own_hp, "its owner's unit is spared")

func ghouls():
	var at := home + Vector2i(14, -12)
	var g = scene.add_unit("AGPC", scene.navigator.free_cell_near(at), 0)
	var knight = enemy_at(scene.combat.unit_cell(g.unit_id) + Vector2i(1, 0), 5000)
	var skeleton = scene.add_unit("AUIX", scene.navigator.free_cell_near(scene.combat.unit_cell(g.unit_id) + Vector2i(-1, 0)), 1)
	var other = scene.add_unit("AGPC", scene.navigator.free_cell_near(scene.combat.unit_cell(g.unit_id) + Vector2i(0, 1)), 1)
	var spells = scene.combat.spells
	var sick := 0
	for i in 60:
		spells.venom_hit(fighter(g), fighter(knight))
		if bool(fighter(knight).get("diseased", false)):
			sick += 1
			fighter(knight)["diseased"] = false
		spells.venom_hit(fighter(g), fighter(skeleton))
		spells.venom_hit(fighter(g), fighter(other))
	check(sick > 10 and sick < 45, "a Ghoul diseases a Knight about 40 %% of hits: %d of 60" % sick)
	check(not bool(fighter(skeleton).get("diseased", false)) and not bool(fighter(other).get("diseased", false)), "never a Skeleton or another Ghoul")
