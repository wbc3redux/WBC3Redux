extends "res://tests/batch2_world_base.gd"
## B3-1: the Orcs (race 5) in the real scene (tests/batch2_world_base.gd, lists from tests/batch3_fixtures.json): the faction, then
## 1. no Repair cell on a damaged building of a local Orc player (E3);
## 2. a Troll that killed a sheep stores it and fires one x 3 shot with the sheep as its missile (E10);
## 3. the Gobshooter fires the Goblin AOSX (E12);
## 4. Rabies (E14): the Wolfriders carry it; a Skeleton and a Golem cannot catch it;
## 5. Gornak's kill is petrified: + 100 stone and no corpse (R3).
## B3-2 adds the casters' abilities by button and key.

func label() -> String: return "Orc"
func race() -> int: return 5
func hall() -> String: return "BKO"
func worker() -> String: return "AOBX"
func lists_path() -> String: return "res://tests/batch3_fixtures.json"

func powers():
	no_repair()
	troll()
	gobshooter()
	rabies()
	petrify()
	casters()

## B3-2 (E15 / E18): the Shaman's three and the Goblin Chief's Goblins, by button and key.
func casters():
	caster_row("AONX", [[0x3e, 40, KEY_L], [0x3f, 25, KEY_B], [0x40, 50, KEY_Y]])
	caster_row("AOKX", [[0x5a, 75, KEY_G]])

func no_repair():
	var b = keep()
	check(b != null, "a hall stands")
	if b == null: return
	b.hit_points = maxi(1, int(b.max_hit_points) - 50)
	select_building(b)
	check(cell_with(0x11) < 0, "a local Orc player has no Repair cell on a damaged building")
	b.hit_points = int(b.max_hit_points)

func troll():
	var spot: Vector2i = scene.navigator.free_cell_near(home + Vector2i(16, -10))
	var troll = scene.add_unit("AOMX", spot, 0)
	var sheep = scene.add_unit("ACSH", scene.navigator.free_cell_near(spot + Vector2i(2, 0)), 6)
	var tf = fighter(troll)
	tf.script = -1
	check(scene.combat.order_attack(troll.unit_id, "unit", sheep.unit_id), "the Troll attacks the sheep")
	var waited := 0.0
	while scene.combat.alive(fighter(sheep)) and waited < 30.0:
		advance(0.25)
		waited += 0.25
	check(int(tf.get("stored_animals", 0)) == 1, "the Troll stored the sheep: %d" % int(tf.get("stored_animals", 0)))
	var enemy = scene.add_unit("AHIX", scene.navigator.free_cell_near(troll.cell + Vector2i(5, 0)), 1)
	fighter(enemy).max_hp = 5000
	fighter(enemy).hp = 5000
	fighter(enemy).script = -1
	var shots: Array = []
	var watch := func(m):
		if int(m.get("attacker", -1)) == troll.unit_id: shots.append(m)
	scene.combat.missile_launched.connect(watch)
	scene.combat.order_attack(troll.unit_id, "unit", enemy.unit_id)
	waited = 0.0
	while shots.size() < 2 and waited < 30.0:
		advance(0.25)
		waited += 0.25
	scene.combat.missile_launched.disconnect(watch)
	check(shots.size() >= 2, "the Troll shoots twice: %d" % shots.size())
	if shots.size() >= 2:
		check(String(shots[0].id) == "ACSH" and int(shots[0].damage) == 3 * int(shots[1].damage), "the first shot is the sheep at x 3: %s %d / %d" % [shots[0].id, int(shots[0].damage), int(shots[1].damage)])
	check(int(tf.get("stored_animals", 0)) == 0, "the store is used up")

func gobshooter():
	var g = scene.add_unit("ASGS", scene.navigator.free_cell_near(home + Vector2i(-12, 12)), 0)
	check(String(fighter(g).stats.get("missile", "")) == "AOSX", "the Gobshooter fires the Goblin AOSX: %s" % fighter(g).stats.get("missile", ""))

func rabies():
	check(production.research_level(0, "PRAB") != 0, "Rabies researched")
	var wolves: Array = units_of("AOCX")
	if wolves.is_empty(): wolves = [scene.add_unit("AOCX", scene.navigator.free_cell_near(home + Vector2i(8, 14)), 0)]
	check(int(fighter(wolves[0]).get("rabies", 0)) in [5, 6], "a Wolfrider carries Rabies: %d" % int(fighter(wolves[0]).get("rabies", 0)))
	var fresh = scene.add_unit("AOCX", scene.navigator.free_cell_near(home + Vector2i(10, 14)), 0)
	check(int(fighter(fresh).get("rabies", 0)) == 6, "a Wolfrider made after Rabies: strength 6")
	for code in ["AUIX", "AAIX"]:
		var u = scene.add_unit(code, scene.navigator.free_cell_near(home + Vector2i(12, 16)), 1)
		check(not scene.combat.spells.diseasable(fighter(u)), "%s cannot catch Rabies" % code)
	var man = scene.add_unit("AHIX", scene.navigator.free_cell_near(home + Vector2i(12, 18)), 1)
	check(scene.combat.spells.diseasable(fighter(man)), "a man can")

func petrify():
	var spot: Vector2i = scene.navigator.free_cell_near(home + Vector2i(-26, -22))   # away from the Orcs, who would kill first
	var gornak = scene.add_unit("ATOX", spot, 0)
	fighter(gornak).script = -1
	var victim = scene.add_unit("AHIX", scene.navigator.free_cell_near(spot + Vector2i(5, 0)), 1)
	fighter(victim).hp = 1
	fighter(victim).script = -1
	scene.economy.capacities[0][3] = 100000
	var stone: int = int(scene.economy.resources(0)[3])
	var killers: Array = []
	var shots: Array = []
	var watch_death := func(kind, id, _owner):
		if kind == "unit" and id == victim.unit_id: killers.append(scene.combat.last_killer)
	var watch_shot := func(m):
		if int(m.get("attacker", -1)) == gornak.unit_id: shots.append(int(m.get("kind", 0)))
	scene.combat.died.connect(watch_death)
	scene.combat.missile_launched.connect(watch_shot)
	scene.combat.order_attack(gornak.unit_id, "unit", victim.unit_id)
	var waited := 0.0
	while scene.combat.alive(fighter(victim)) and waited < 30.0:
		advance(0.25)
		waited += 0.25
	scene.combat.died.disconnect(watch_death)
	scene.combat.missile_launched.disconnect(watch_shot)
	check(not scene.combat.alive(fighter(victim)), "Gornak kills")
	check(not killers.is_empty() and int(killers[0]) == gornak.unit_id, "the killer is Gornak: %s, his shots' kinds %s, range %d" % [killers, shots, int(fighter(gornak).stats.range)])
	check(bool(fighter(victim).removed) and not victim.visible, "petrified: no corpse")
	check(int(scene.economy.resources(0)[3]) >= stone + 100, "+ 100 stone: %d -> %d" % [stone, int(scene.economy.resources(0)[3])])
