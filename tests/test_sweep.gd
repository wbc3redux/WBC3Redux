extends "res://tests/test_hero_spells.gd"
## Melee sweep (BATCH3_RESEARCH.md E13): Combat.sweep_targets against tests/batch3_fixtures.json "sweep" (tools/emulate_batch3.py:
## 0x523150 state 2 under Unicorn): which objects a melee swing reaches besides its target, by attacker type; who is spared
## (own units) and who is not (allies, buildings, flyers); then the blow itself in the stand-alone combat world: every swept
## object takes the swing's one damage roll.

const Batch3Combat = preload("res://simulation/combat.gd")

var b3: Dictionary = {}

func run():
	b3 = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch3_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the sweep world")
	if centre.x >= 0:
		types()
		spared()
		blows()
		ranged()
	clear_world()
	if failures > 0:
		printerr("Sweep checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Sweep checks passed: %d" % checks)
	quit(0)

## The fixture's attacker stands at (40, 40) and the target at (41, 40): offsets from the attacker.
func names_of(swept: Array, target: Vector2i, named: Dictionary) -> Array:
	var out: Array = ["target"]
	for o in swept:
		var key := "%s:%d" % [o.kind, int(o.id)]
		out.append(String(named.get(key, "?")))
	return out

func types():
	for row in b3.sweep:
		if row.has("scene"): continue
		new_world()
		var code := String(row.unit)
		var a := unit(code, Vector2i(0, 0), OWNER)
		var tcell := Vector2i(int(row.target_cell[0]) - 40, int(row.target_cell[1]) - 40)
		var t := unit("AHIX", tcell, ENEMY)
		var named := {}
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var off := tcell + Vector2i(dx, dy)
				if off == Vector2i.ZERO or off == tcell: continue
				var id := unit("AHIX", off, ENEMY)
				named["unit:%d" % id] = "%+d,%+d" % [dx, dy]
		var f = world.combat.fighters[a]
		check(int(f.stats.range) == int(row.range), "%s range %d" % [code, int(row.range)])
		var swept: Array = world.combat.sweep_targets(f, "unit", t)
		# A ranged attacker (ATOX) never reaches the melee path: the fixture records no swing at all.
		var got: Array = names_of(swept, tcell, named) if int(row.range) <= 0 else []
		var want: Array = row.hits
		got.sort()
		want = want.duplicate()
		want.sort()
		check(got == want, "%s sweeps %s, the original %s" % [code, str(got), str(want)])

func spared():
	var row: Dictionary = {}
	for r in b3.sweep:
		if r.has("scene"): row = r
	new_world()
	var a := unit("AVDX", Vector2i(0, 0), OWNER)
	var t := unit("AHIX", Vector2i(1, 0), ENEMY)
	unit("AHIX", Vector2i(1, 1), OWNER)                           # own: spared
	var allied := unit("AHIX", Vector2i(2, 0), 2)                 # another owner allied with the attacker: swung at
	# The harness stamps the building into the one cell (42, 41) (emu.occupy): the same here, the building itself away.
	var b := building("BKO0", Vector2i(0, 14), ENEMY, {})
	world.nav.building_cells[centre + Vector2i(2, 1)] = b
	var fl := unit("AABA", Vector2i(1, 1) + Vector2i(0, 0), ENEMY)
	var node = world.units[fl]
	world.nav.release(node, centre + Vector2i(1, 1))
	node.flying = true
	world.nav.occupy(node, centre + Vector2i(1, 1))
	var named := {"unit:%d" % allied: "allied", "building:%d" % b: "building", "unit:%d" % fl: "flyer"}
	var swept: Array = world.combat.sweep_targets(world.combat.fighters[a], "unit", t)
	var got := names_of(swept, Vector2i(1, 0), named)
	var want: Array = row.hits.duplicate()
	got.sort()
	want.sort()
	check(got == want, "spared and reached: %s, the original %s" % [str(got), str(want)])

## The blow: the target and the swept units take the same damage; an attacker that does not sweep hits the target alone.
func blows():
	for code in ["AVDX", "AHKX"]:
		new_world()
		var a := unit(code, Vector2i(0, 0), OWNER)
		var t := unit("AHIX", Vector2i(1, 0), ENEMY, {"hp": 500})
		var n := unit("AHIX", Vector2i(2, 1), ENEMY, {"hp": 500})
		var f = world.combat.fighters[a]
		var result := {"damage": 7, "effect": 0, "param": 0, "ranged": false, "message_roll": 50}
		world.combat._hit(f, {"target_kind": "unit", "target_id": t, "ranged": false, "result": result, "message_roll": 50})
		check(int(world.combat.fighters[t].hp) == 493, "%s: the target takes the swing's damage" % code)
		var want := 493 if code == "AVDX" else 500
		check(int(world.combat.fighters[n].hp) == want, "%s: the neighbour at +1,+1 has %d" % [code, int(world.combat.fighters[n].hp)])

## Gornak (ATOX, range 8) and any ranged swing: no sweep.
func ranged():
	new_world()
	var a := unit("ATOX", Vector2i(0, 0), OWNER)
	var t := unit("AHIX", Vector2i(1, 0), ENEMY)
	unit("AHIX", Vector2i(2, 0), ENEMY)
	check(world.combat.sweep_targets(world.combat.fighters[a], "unit", t).is_empty(), "ATOX does not sweep")
	check(Batch3Combat.sweeps("ATEX") and Batch3Combat.sweeps("AAJX") and not Batch3Combat.sweeps("AHKX"), "the sweeper list and the titans")
