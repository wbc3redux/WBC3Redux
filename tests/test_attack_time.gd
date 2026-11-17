extends "res://tests/test_hero_spells.gd"
## B2-2 first task (BATCH2_RESEARCH.md "Attack time"): the port against tests/attack_time_fixtures.json
## (tools/emulate_attack_time.py): X = 0x40dc80 with a living, dead and no hero, the entry times of 0x537060 for every unit
## (per-unit frames, Army.cfg latency, the floor), the hero branch and the hit entry through the real swing.

const HeroRules = preload("res://simulation/hero_rules.gd")
const ResearchEffects = preload("res://simulation/research_effects.gd")
var fixtures_time: Dictionary = {}

func run():
	fixtures_time = JSON.parse_string(FileAccess.get_file_as_string("res://tests/attack_time_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	if centre.x >= 0:
		x_rows()
		unit_rows()
		hero_rows()
		swings()
		animation()
	clear_world()
	if failures > 0:
		printerr("Attack time checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Attack time checks passed: %d" % checks)
	quit(0)

func x_world(row: Dictionary) -> int:
	new_world()
	var owner := int(row.owner)
	world.production.races[owner] = int(row.race)
	world.production.research[owner] = row.research.duplicate()
	var id := -1
	if row.hero != null:
		var skills: Array = []
		for s in row.skills: skills.append({"id": int(s[0]), "unlock_level": int(s[1]), "rank": int(s[2])})
		id = hero(String(row.code), {}, owner, Vector2i.ZERO, row.stats, skills)
		var m = world.combat.heroes[owner].match
		m.profile.data.race_id = int(row.race)
		m.profile.data.level = int(row.level)
		var equipment: Array = []
		for item in row.equipment: equipment.append(int(item))
		m.profile.data.equipment = equipment
		for value in row.effects:
			world.spells.add_status({"kind": "unit", "id": id}, {"kind": 7, "value": int(value), "until": 100000000, "art": row.effects.find(value)})
		if row.hero == "dead": world.combat.apply_damage("unit", id, 1000000, -1)
		elif row.has("hp") and row.hp != null: world.combat.fighters[id].hp = int(row.hp)
	world.combat.lord_counter[owner] = int(row.counter)
	return id

func x_rows():
	for row in fixtures_time.x:
		var label := "X owner %d hero %s research %s counter %d effects %s race %d skills %s items %s" % [int(row.owner), row.hero, row.research, int(row.counter), row.effects, int(row.race), row.skills, row.equipment]
		if int(row.owner) > 6:
			new_world()
			check(world.combat.morale_value(int(row.owner)) == int(row.x), label)
			continue
		x_world(row)
		var got: int = world.combat.morale_value(int(row.owner))
		check(got == int(row.x), "%s: %d, the original %d" % [label, got, int(row.x)])

func times(entry: int, frames: int, latency: Array) -> Array:
	var out: Array = []
	for i in frames + 1: out.append(CombatRules.attack_entry_time(i, entry, latency))
	return out

func same(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if int(a[i]) != int(b[i]): return false
	return true

func unit_rows():
	new_world()
	var combat = world.combat
	var rows: Array = fixtures_time.units.duplicate()
	rows.append_array(fixtures_time.floor)
	for row in rows:
		var code := String(row.unit)
		if int(row.count) == 0: continue          # no ANI slot 2
		var frames: int = combat.attack_frames(code)
		var latency: Array = combat.attack_latency(code)
		check(ResearchEffects.attack_rate(code) == int(row.rate), "%s rate %d, the original %d" % [code, ResearchEffects.attack_rate(code), int(row.rate)])
		check(frames == int(row.count), "%s frames %d, the original %d" % [code, frames, int(row.count)])
		var entry: int = CombatRules.attack_entry_ms(false, int(row.x), 0, int(row.rate), frames)
		check(same(times(entry, frames, latency), row.times), "%s %s: %s, the original %s" % [code, row.scenario, times(entry, frames, latency), row.times])
		for sample in [0, 1, entry, entry + 1, int(row.times[frames]) - 1]:
			var i: int = CombatRules.attack_entry_at(sample, entry, latency)
			check(int(row.times[i]) <= sample and (i >= frames or sample < int(row.times[i + 1])), "%s: %d ms is entry %d" % [code, sample, i])

func hero_rows():
	new_world()
	var combat = world.combat
	for row in fixtures_time.heroes:
		if row.get("ranged", false): continue      # slot 7: the port has no ranged hero (SPELLS_RESEARCH.md open 2)
		var code := String(row.unit)
		var frames: int = combat.attack_frames(code)
		check(frames == int(row.count), "%s frames" % code)
		var derived: int = HeroRules.derived(row.stats, 16, 1)
		check(derived == int(row.derived_16), "%s derived 16 %s" % [code, row.stats])
		var entry: int = CombatRules.attack_entry_ms(true, 99, derived, int(row.rate), frames)
		check(same(times(entry, frames, [0, 0]), row.times), "%s %s hero times" % [code, row.stats])

## The real swing: the units of the trigger rows through `_start_swing`, hit and end at the original's times.
func swings():
	for row in fixtures_time.triggers:
		new_world()
		world.combat.auto_acquire = false
		world.host.local_player = OWNER
		if row.hero != null: hero("AHHX", {}, OWNER, Vector2i(-6, -6))
		var a := unit(String(row.unit), Vector2i.ZERO, OWNER)
		var b := unit("AHKX", Vector2i(1, 0), ENEMY)
		var f = fighter_of(a)
		var order := {"target_kind": "unit", "target_id": b}
		world.combat.now_ms = 1000
		var got: int = world.combat.morale_value(OWNER)
		check(got == int(row.x), "%s X %d, the original %d" % [row.unit, got, int(row.x)])
		world.combat._start_swing(f, order, 1)
		check(int(f.swing.hit_ms) - 1000 == int(row.trigger_ms), "%s hit %d ms, the original %d" % [row.unit, int(f.swing.hit_ms) - 1000, int(row.trigger_ms)])
		check(int(f.swing.end_ms) - 1000 == int(row.times[int(row.count)]), "%s end %d ms, the original %d" % [row.unit, int(f.swing.end_ms) - 1000, int(row.times[int(row.count)])])

func fighter_of(id: int):
	return world.combat.fighters[id]

func animation():
	var latency := [4, 80]
	check(CombatRules.attack_entry_at(0, 115, latency) == 0 and CombatRules.attack_entry_at(194, 115, latency) == 0, "the first delayed entry")
	check(CombatRules.attack_entry_at(195, 115, latency) == 1 and CombatRules.attack_entry_at(585, 115, latency) == 3, "the delayed entries")
	check(CombatRules.attack_entry_at(699, 115, latency) == 3 and CombatRules.attack_entry_at(700, 115, latency) == 4, "then the even spacing")
