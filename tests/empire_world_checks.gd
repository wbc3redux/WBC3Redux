extends "res://tests/batch2_world_base.gd"
## B2-1: the Empire (race 12) in the real scene (tests/batch2_world_base.gd): the faction, then
## 1. the trade cell at the Quartermaster BPQM, disabled before Trade, the dialog after it; the seven trade buildings by type;
## 2. Foreign Mercenaries: POMA / POMB / POMC at the Quartermaster at the command limit, each one pool unit, the rally point
##    honoured, POMA bought again, no creation experience beyond the starting one (R-1);
## 3. Mysticism: PLI1 raises a White Mage's current and maximum mana by 15 at once;
## 4. B2-2: the mages' six abilities by button and by key.

func label() -> String: return "Empire"
func race() -> int: return 12
func hall() -> String: return "BKP"
func worker() -> String: return "AHBX"
func held() -> Array: return ["PTRA", "PLI1"]

func powers():
	var quartermaster: Array = buildings_of("BPQM")
	check(not quartermaster.is_empty(), "a Quartermaster stands")
	if quartermaster.is_empty(): return
	var q = quartermaster[0]
	trade_at(q, false)
	research_now("PTRA")
	trade_at(q, true)
	var own := String(q.original_type_id)
	for code in RacePowers.TRADE_RACES:                  # the rule for every trade type: with Trade every race has the cell
		q.original_type_id = code
		select_building(q)
		check(cell_with(RacePowers.TRADE_ICON) == 7, "%s has the trade cell with Trade" % code)
	q.original_type_id = own
	mysticism()                                          # first: the mercenaries' check leaves the army at its limit
	mercenaries(q)
	flamer()
	caster_row("AHGW", [[0x31, 30, KEY_U], [0x39, 40, KEY_H]])     # B2-2 (R11): Cure, Heal Group
	caster_row("AHGR", [[0x3a, 30, KEY_J], [0x3b, 40, KEY_F]])     # Resist Fire, Ring of Fire
	caster_row("AHGB", [[0x3c, 20, KEY_X], [0x35, 20, KEY_M]])     # Hand of Ice, the drain

func at_limit():
	var pop: Dictionary = production.population(0)
	var guard := 0
	while int(pop.current) < int(pop.maximum) and guard < 60:
		# The Peasant costs no command; a Titan costs a lot, so few units are enough. It needs room; infantry fills the rest.
		if production.spawn_unit(0, "ATPX", home) < 0 or int(production.population(0).maximum) - int(production.population(0).current) < 16: production.spawn_unit(0, "AHIX", home)
		pop = production.population(0)
		guard += 1
	check(int(pop.current) >= int(pop.maximum), "at the command limit: %d of %d" % [int(pop.current), int(pop.maximum)])

func mercenaries(q):
	var pools: Dictionary = RacePowers.MERCENARY_POOLS
	at_limit()
	for step in [["POMA", false], ["POMA", false], ["POMB", true], ["POMC", false]]:
		var item: String = step[0]
		fund()
		q.rally = q.cell_rect().position + Vector2i(-6, 8) if bool(step[1]) else Vector2i(-1, -1)
		var before: int = scene.units.size()
		var queued: Dictionary = production.enqueue(q.entity_id, item, scene.game_ms())
		check(queued.ok, "%s queued (again): %s" % [item, queued])
		var waited := 0.0
		while q.has_job() and waited < 300.0:
			advance(0.5)
			waited += 0.5
		var made: Array = scene.units.slice(before).filter(func(u): return u.owner_id == 0 and pools[item].has(String(u.type_id)))
		check(made.size() == 1, "%s: one pool unit despite the limit: %s" % [item, made.map(func(u): return u.type_id)])
		check(production.research_level(0, item) == 0, "%s is never listed" % item)
		if made.is_empty(): continue
		var d: Vector2i = made[0].cell - q.cell_rect().position
		check(absi(d.x) < 20 and absi(d.y) < 20, "%s appears at the Quartermaster: %s" % [item, d])
		# R-1 (COMBAT_RESEARCH.md R2): no +0x10 for a mercenary's 0xfa, but 0x557d90 (a living hero teaches) still applies.
		var taught: int = scene.combat.starting_xp(0, String(made[0].type_id))
		check(int(fighter(made[0]).xp) == taught, "%s: no creation experience beyond the starting %d: %d" % [item, taught, int(fighter(made[0]).xp)])
		if bool(step[1]): check(not made[0].orders.is_empty() or made[0].in_step or made[0].cell == q.rally, "%s walks to the rally point" % item)

## R3: a Flamer AGFL (POMB's pool) really fires EMF1, and its impact burns the unit it meets.
func flamer():
	var enemy = scene.add_unit("AHIX", scene.navigator.free_cell_near(home + Vector2i(14, 14)), 1)
	var fire = scene.add_unit("AGFL", scene.navigator.free_cell_near(enemy.cell + Vector2i(-3, 0)), 0)
	var ef = fighter(enemy)
	ef.max_hp = 2000
	ef.hp = 2000
	ef.script = -1
	check(String(fighter(fire).stats.get("missile", "")) == "EMF1", "the Flamer shoots EMF1 (Army.cfg)")
	var waited := 0.0
	while ef.get("berserk") == null and waited < 40.0:
		if fighter(fire).order == null: scene.combat.order_attack(fire.unit_id, "unit", enemy.unit_id)
		advance(0.25)
		waited += 0.25
	check(ef.get("berserk") != null and int(ef.berserk.level) == 0, "an EMF1 hit burns: level 0, Rampant")

func mysticism():
	var mage = units_of("AHGW")[0] if not units_of("AHGW").is_empty() else train("AHGW")
	check(mage != null, "a White Mage")
	if mage == null: return
	var f = fighter(mage)
	f.mana = 20
	var maximum := int(f.max_mana)
	var before_max: int = maximum
	production.complete_research(0, "PLI1")
	check(int(f.max_mana) == before_max + 15 and int(f.mana) == 35, "Mysticism: mana + 15 at once: %d / %d" % [int(f.mana), int(f.max_mana)])
	var other = train("AHGW")
	if other != null: check(int(fighter(other).max_mana) == before_max + 15, "a new White Mage has MANA + 15 x 2 from setup_unit: %d" % int(fighter(other).max_mana))
