extends "res://tests/batch2_world_base.gd"
## B2-1: the Minotaurs (race 4) in the real scene (tests/batch2_world_base.gd): the faction, then
## 1. the Berserker button (disabled before PFAN), a Minotaur made to last runs its 180 s: 1 hp/s, Rampant, script back;
## 2. Training PTRN (+ 10 experience);
## 3. eating and hunting: a wounded, poisoned Minotaur kills a sheep on its own, gains 20 hit points and is cured; an Axe
##    Thrower walks adjacent before it throws at a sheep;
## 4. Farseeing PFAR: fog and hidden map off for the local player;
## 5. B2-2: the Shaman's three abilities by button and by key.

func label() -> String: return "Minotaur"
func race() -> int: return 4
func hall() -> String: return "BKH"
func worker() -> String: return "ABBX"
func held() -> Array: return ["PFAN", "PTRN", "PFAR"]

func powers():
	var minotaurs: Array = units_of("AMIX")
	check(not minotaurs.is_empty(), "Minotaurs trained")
	if minotaurs.is_empty(): return
	berserk_at_button([minotaurs[0]], false)
	research_now("PFAN")
	berserk_full_length(minotaurs[0])
	research_now("PTRN")
	var trained = train("AMIX")
	if trained != null: check(int(fighter(trained).xp) >= 10, "Training: 10 experience at creation: %d" % int(fighter(trained).xp))
	hunting()
	farseeing()
	caster_row("AMMX", [[0x3b, 40, KEY_F], [0x3f, 25, KEY_B], [0x41, 35, KEY_P]])   # B2-2 (R11): Ring of Fire, Berserker, Pillar of Fire

func sheep_near(cell: Vector2i, owner: int = 0):
	var free: Vector2i = scene.navigator.free_cell_near(cell)
	return scene.add_unit("ACSH", free, owner)

func quiet_others(keep_list: Array):
	for u in scene.units:
		var f = fighter(u)
		if f == null or keep_list.has(u) or u.type_id != "AMIX" and u.type_id != "AMNX": continue
		f.script = -1                                     # nobody else may eat the sheep

func hunting():
	var eater = train("AMIX")
	var thrower = units_of("AMNX")[0] if not units_of("AMNX").is_empty() else train("AMNX")
	check(eater != null and thrower != null, "an eater and an Axe Thrower")
	if eater == null or thrower == null: return
	quiet_others([eater, thrower])
	scene.combat.ai.animal_idle = false                   # the sheep stays where it is put
	var f = fighter(eater)
	var other = fighter(thrower)
	other.script = -1
	f.script = 2
	f.hp = int(f.max_hp) - 30
	scene.units[f.id].hp = f.hp
	scene.combat.set_poisoned(int(f.id), true)
	var sheep = sheep_near(eater.cell + Vector2i(3, 0))
	var eaten := []
	scene.combat.eaten.connect(func(k, _c): eaten.append(k))
	var hp0 := int(f.hp)
	var waited := 0.0
	while eaten.is_empty() and waited < 60.0:
		advance(0.25)
		waited += 0.25
	check(eaten.has(int(f.id)), "the wounded Minotaur hunts its own sheep and eats it")
	check(sheep.dying or sheep.removed, "the sheep is dead")
	check(int(f.hp) >= hp0 + 20 - int(waited) * 2 and int(f.hp) <= int(f.max_hp), "20 hit points gained: %d from %d" % [int(f.hp), hp0])
	check(not bool(f.get("poisoned", false)), "poison cured")
	# The Axe Thrower (range 4) walks up.
	other.script = 2
	f.script = -1
	other.hp = int(other.max_hp) - 20
	scene.units[other.id].hp = other.hp
	var far: Vector2i = thrower.cell + Vector2i(0, 4)
	# A map animal (player 6): the flight 0x53fbc0 passes allied units, so a thrower's axes cannot hit its own sheep (Read).
	var sheep2 = sheep_near(far, 6)
	var near_first := []
	var swings := []
	scene.combat.swing_started.connect(func(id, swing):
		if id == int(other.id) and int(swing.target_id) == sheep2.unit_id:
			near_first.append(int(swing.distance))
			swings.append(swing))
	waited = 0.0
	while near_first.is_empty() and waited < 60.0:
		advance(0.25)
		waited += 0.25
	check(not near_first.is_empty() and int(near_first[0]) <= 1, "the first throw comes from beside the sheep: %s" % [near_first])
	var kills := 0.0
	while not sheep2.dying and not sheep2.removed and kills < 30.0:
		advance(0.25)
		kills += 0.25
	check(sheep2.dying or sheep2.removed, "the Axe Thrower kills it: sheep hp %d of %d after %d throws" % [int(fighter(sheep2).hp), int(fighter(sheep2).max_hp), swings.size()])
	scene.combat.ai.animal_idle = true

func farseeing():
	check(scene.visibility.fog or scene.visibility.shroud, "the map is fogged before Farseeing")
	research_now("PFAR")
	check(not scene.visibility.fog and not scene.visibility.shroud, "Farseeing: no fog, no hidden map")
	check(scene.visibility.is_visible(0, Vector2i(1, 1)), "every cell is visible")
