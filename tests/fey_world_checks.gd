extends "res://tests/batch2_world_base.gd"
## B5-1: the Fey (race 9) in the real scene (tests/batch2_world_base.gd, lists from tests/batch5_fixtures.json): the faction, then
## 1. three Leprechauns add 6 gold to the income cycle (E8), no producer, Income research does not raise it;
## 2. the Banshee AFGX still sweeps (batch 3's melee sweep, BATCH5_RESEARCH.md section 9 step 8);
## 3. no Fey unit afflicts anything (E9: class 0).
## B5-2: the casters' abilities by button and key.

func label() -> String: return "Fey"
func race() -> int: return 9
func hall() -> String: return "BKF"
func worker() -> String: return "AFBX"
func lists_path() -> String: return "res://tests/batch5_fixtures.json"

func powers():
	if scene.skirmish != null: scene.skirmish.resolved["standard_victory_event"] = 0
	leprechauns()
	banshee()
	casters()

func casters():
	caster_row("AFGX", [[0x50, 40, KEY_S]])                # Scare (B5-2)

func leprechauns():
	var base: Dictionary = scene.other_income(0)
	var have: int = units_of("AFNX").size()
	for i in 3: scene.add_unit("AFNX", scene.navigator.free_cell_near(home + Vector2i(10 + i, 8)), 0)
	var other: Dictionary = scene.other_income(0)
	check(int(other.income[0]) - int(base.income[0]) == 6 and int(other.income[0]) == 2 * (have + 3), "three Leprechauns: + 6 gold per cycle: %s" % [other])
	check(int(other.producers[0]) == int(base.producers[0]), "Leprechauns are no producers (Income does not raise them)")

func banshee():
	check(preload("res://simulation/combat.gd").sweeps("AFGX"), "the Banshee is in the sweep list")
	var b = scene.add_unit("AFGX", scene.navigator.free_cell_near(home + Vector2i(-12, 10)), 0)
	var k = scene.add_unit("AHIX", scene.navigator.free_cell_near(scene.combat.unit_cell(b.unit_id) + Vector2i(1, 0)), 1)
	fighter(k).script = -1
	scene.combat.spells.venom_hit(fighter(b), fighter(k))
	check(not bool(fighter(k).get("poisoned", false)) and not bool(fighter(k).get("diseased", false)), "a Banshee's hit afflicts nothing (class word 0x%x)" % scene.combat.spells.class_word(fighter(b)))
