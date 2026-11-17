extends "res://tests/batch2_world_base.gd"
## B2-1: the Barbarians (race 3) in the real scene (tests/batch2_world_base.gd): the faction, then
## 1. the trade cell at the Mill BPMI;
## 2. the Berserker button on Barbarians ABIX and Reavers ABGX (disabled before PFAN), the state at the button, the whole
##    180 s on one unit;
## 3. Training PTRN: a unit trained after it starts with 10 experience; a Slavehorde-style message 0xfa unit has none.

func label() -> String: return "Barbarian"
func race() -> int: return 3
func hall() -> String: return "BKB"
func worker() -> String: return "ABBX"
func held() -> Array: return ["PTRA", "PFAN", "PTRN"]

func powers():
	var mill: Array = buildings_of("BPMI")
	check(not mill.is_empty(), "a Mill stands")
	if not mill.is_empty():
		trade_at(mill[0], false)
		research_now("PTRA")
		trade_at(mill[0], true)
	var barbarians: Array = units_of("ABIX")
	var reavers: Array = units_of("ABGX")
	check(not barbarians.is_empty() and not reavers.is_empty(), "Barbarians and Reavers trained")
	if barbarians.is_empty() or reavers.is_empty(): return
	var both := [barbarians[0], reavers[0]]
	berserk_at_button(both, false)
	research_now("PFAN")
	var third = train("ABIX")
	if third != null: berserk_full_length(third)
	berserk_at_button(both, true)
	check(int(fighter(both[0]).hp) > 0, "alive at the start of the drain")
	research_now("PTRN")
	var trained = train("ABIX")
	if trained != null: check(int(fighter(trained).xp) >= 10, "Training: 10 experience at creation: %d" % int(fighter(trained).xp))
	var direct: int = production.spawn_unit(0, "ABBX", home)
	check(direct >= 0 and int(scene.combat.fighters[direct].xp) == scene.combat.starting_xp(0, "ABBX"), "a unit sent straight as message 0xfa has only the starting experience 0x557d90 (R-1)")
