extends "res://tests/test_hero_spells.gd"
## R-1 (COMBAT_RESEARCH.md section "R-1"): unit experience and rank. UnitRanks against tests/rank_fixtures.json
## (tools/emulate_ranks.py): the tables, 0x527100 -> 0x40da20 -> 0x40daa0 for all 199 ARM types, 0x557d90, 0x51b460, 0x51b820,
## 0x526e70, 0x51b580; then the fighter's consumers on the hero spells' stand-alone combat world. The real scene is in
## tests/rank_world_checks.gd.

const UnitRanks = preload("res://simulation/unit_ranks.gd")
const Advancement = preload("res://simulation/advancement.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const ResearchEffects = preload("res://simulation/research_effects.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
const SaveGame = preload("res://simulation/save_game.gd")
const GameHud = preload("res://hud/game_hud.gd")
const ResultsScreen = preload("res://menus/results_screen.gd")
const CreditsText = preload("res://menus/credits_text.gd")
const ProductionRulesRanks = preload("res://simulation/production_rules.gd")
const KEYS := ["rank", "xp", "combat", "speed", "mres", "max_hp", "hp", "dmg", "armour", "word_ae", "word_b0"]

var ranks: Dictionary = {}

func run():
	ranks = JSON.parse_string(FileAccess.get_file_as_string("res://tests/rank_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the rank world")
	if centre.x >= 0:
		for part in ["tables", "promotions", "gains", "blocks", "starting", "regeneration", "ticks", "abilities",
				"kills", "live_block", "healing", "titans", "soul_flame", "creation", "summons", "resurrection", "casters", "regen_world", "saved", "hud_rules",
				"command_limit", "attitude", "results_bars", "credits", "review_fixes"]:
			call(part)
	clear_world()
	if failures > 0:
		printerr("Rank checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Rank checks passed: %d" % checks)
	quit(0)

func block_of(row: Array) -> Dictionary:
	var out := {}
	for i in KEYS.size(): out[KEYS[i]] = int(row[i])
	return out

func row_of(block: Dictionary) -> Array:
	var out: Array = []
	for key in KEYS: out.append(int(block[key]))
	return out

func same(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if int(a[i]) != int(b[i]): return false
	return true

func tables():
	var t: Dictionary = ranks.tables
	check(same(t.thresholds, UnitRanks.THRESHOLDS), "0x5fbc50")
	check(same(t.training, UnitRanks.TRAINING_XP), "0x607d5c")
	check(same(t.regeneration, UnitRanks.REGENERATION), "0x61120c")
	for r in 8:
		check(same(t.combat[r], UnitRanks.COMBAT_ROWS[r]), "0x607d70 row %d" % r)
		check(same(t.speed[r], UnitRanks.SPEED_ROWS[r]), "0x607ed0 row %d" % r)
		check(same(t.hit_points[r], UnitRanks.HIT_POINT_ROWS[r]), "0x608030 row %d" % r)
	# The encounters' table is the thresholds behind [-1, 0].
	check(int(t.levels[2]) == 5 and int(t.levels[20]) == 1500, "0x5fbc48 holds the thresholds from index 2")

func promotions():
	var rows: Dictionary = ranks.promotions
	check(rows.size() == 199, "all ARM records: %d" % rows.size())
	var catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalogue.json"))
	for code in rows:
		var steps: Array = rows[code]
		var block := block_of(steps[0])
		var stats := CombatRules.unit_stats(String(catalogue.units[code].raw_hex))
		check(int(stats.combat) == int(block.combat) and int(stats.max_hp) == int(block.max_hp) and int(stats.dmg) == int(block.dmg) and int(stats.armour) == int(block.armour)
			and int(stats.word_ae) == int(block.word_ae) and int(stats.word_b0) == int(block.word_b0), "%s: the block is the ARM record" % code)
		var titan: bool = UnitRanks.is_titan(code)
		for i in UnitRanks.THRESHOLDS.size():
			if not titan: UnitRanks.gain(block, int(UnitRanks.THRESHOLDS[i]) - int(block.xp))
			check(same(row_of(block), steps[i + 1]), "%s: rank %d: %s against %s" % [code, i + 1, row_of(block), steps[i + 1]])

func gains():
	for row in ranks.gains:
		var hp = row.hp
		var block: Dictionary = {}
		var catalogue_row: Array = ranks.promotions[row.code][0]
		block = block_of(catalogue_row)
		if hp != null: block.hp = int(hp)
		for step in row.steps:
			var promoted := 0
			if not UnitRanks.is_titan(String(row.code)): promoted = UnitRanks.gain(block, mini(int(step.amount), UnitRanks.MAX_XP))
			var state := row_of(block)
			check(same(state, step.state), "%s: gain %d: %s against %s" % [row.code, int(step.amount), state, step.state])
			var heal: Array = step.heal
			if promoted > 0 and int(block.hp) < int(block.max_hp):
				var target := UnitRanks.healed_points(int(block.hp), int(block.max_hp))
				check(heal.size() == 1 and int(heal[0]) == target, "%s: the heal message: %s against %d" % [row.code, heal, target])
				block.hp = target
			else:
				check(heal.is_empty(), "%s: no heal message" % row.code)

func blocks():
	for row in ranks.blocks:
		var i: Array = row.i
		var block := {"rank": int(i[0]), "combat": int(i[1]), "speed": int(i[2]), "mres": int(i[3]), "max_hp": int(i[4]), "hp": int(i[4]),
			"dmg": int(i[5]), "armour": int(i[6]), "word_ae": int(i[7]), "word_b0": int(i[8])}
		UnitRanks.promote(block)
		var out: Array = [block.rank, block.combat, block.speed, block.mres, block.max_hp, block.hp, block.dmg, block.armour, block.word_ae, block.word_b0]
		check(same(out, row.o), "0x40daa0 %s: %s against %s" % [i, out, row.o])

func starting():
	for row in ranks.starting:
		var skills: Array = []
		for s in row.skills: skills.append([int(s[0]), int(s[1]), int(s[2])])
		var block := {}
		if bool(row.hero):
			block = HeroEffects.block_from_profile({"skills": skills, "stats": row.stats, "level": 10}, true, 100 if bool(row.alive) else 0)
		var aura: int = int(row.effect[1]) if row.effect != null else 0
		var value: int = Advancement.starting_xp(block, String(row.code), int(row.status), int(row.mode[0]) != 0, int(row.mode[1]) != 0, aura)
		if int(row.mode[2]) != 0 and bool(row.pgax): value += 40
		check(value == int(row.value), "0x557d90 %s %s: %d against %d" % [row.code, row.mode, value, int(row.value)])

func regeneration():
	for row in ranks.regeneration:
		var percent: int = int(UnitRanks.REGENERATION[int(row.research)]) + int(row.effect)
		if int(row.skill) != 0: percent += HeroEffects.skill_term(3, int(row.skill), 1)
		var rate: int = UnitRanks.regeneration_rate(int(row.rank), String(row.code), int(row.status), percent)
		check(rate == int(row.value), "0x51b460 %s: %d against %d" % [row, rate, int(row.value)])

func ticks():
	for row in ranks.ticks:
		var state := {"hp": int(row.hp), "max_hp": int(ranks.promotions[row.code][0][5]), "regen_ms": 0}
		var status: int = status_bits(String(row.code))
		var rate: int = UnitRanks.regeneration_rate(int(row.rank), String(row.code), status, int(UnitRanks.REGENERATION[int(row.research)]))
		for step in row.steps:
			var now := int(step[0])
			if bool(row.poison) or bool(row.disease):
				state.regen_ms = now + UnitRanks.POISON_MS      # both branches re-arm a second on; their own damage is elsewhere
				check(state.regen_ms == int(step[3]) or int(step[3]) == int(state.get("kept", -1)), "a sick unit waits a second: %s" % [step])
				state["kept"] = int(step[3])
				continue
			UnitRanks.regen_tick(state, now, rate, bool(row.garrison))
			check(int(state.hp) == int(step[2]) and int(state.regen_ms) == int(step[3]), "0x51b820 %s %s: hp %d, due %d" % [row.code, step, int(state.hp), int(state.regen_ms)])

func abilities():
	new_world()
	for row in ranks.abilities:
		if row.has("hero"): continue
		if row.has("assassin"):
			check(ResearchEffects.assassin(String(row.code), [], int(row.rank)) == int(row.assassin), "0x526e70 %s rank %d" % [row.code, int(row.rank)])
			check(int(row.level) == int(row.rank), "0x526d80 is the rank")
		else:
			var id := unit(String(row.code), Vector2i(1, 1), OWNER)
			var f = world.combat.fighters[id]
			f["max_mana"] = 50
			f["rank"] = int(row.rank)
			check(world.spells.unit_mana_interval(f) == int(row.mana_interval), "0x51b580 %s rank %d: %d" % [row.code, int(row.rank), world.spells.unit_mana_interval(f)])

func fighter_of(id: int):
	return world.combat.fighters[id]

## 0x5210b0's award reaches the rank: five kills, a block that fights better and a new unit that does not.
func kills():
	new_world()
	var a := unit("AHKX", Vector2i(0, 0), OWNER)
	var f = fighter_of(a)
	check(int(f.rank) == 0 and int(f.xp) == 0, "a new unit is rank 0")
	for i in 5:
		var v := unit("AHKX", Vector2i(3, i), ENEMY)
		world.combat.apply_damage("unit", v, 100000, a)
	check(int(f.xp) == 5 and int(f.rank) == 1, "five kills are rank 1: %d, %d" % [int(f.xp), int(f.rank)])
	check(int(f.base.combat) == 7 and int(f.stats.combat) == 7 and int(f.base.dmg) == 12 and int(f.max_hp) == 45, "the block is raised")
	check(int(world.combat.combat_block(f).combat) == 7, "the getters read it")
	check(int(world.units[a].max_hp) == 45 and int(world.units[a].hp) == 45, "the sprite's life follows")
	world.combat.gain_experience(f, 5)
	check(int(f.rank) == 2 and int(fighter_of(a).stats.armour) == 12, "the next threshold")
	var ranks_seen: Array = []
	world.combat.rank_gained.connect(func(id, rank): ranks_seen.append([id, rank]))
	world.combat.gain_experience(f, 30)
	check(ranks_seen == [[a, 4]], "one signal per gain, the new rank: %s" % [ranks_seen])

## Research and direct block changes keep their sum with a promotion (the getters add research on top of the block).
func live_block():
	new_world()
	var id := unit("AHKX", Vector2i(0, 0), OWNER)
	var f = fighter_of(id)
	f.stats.combat = int(f.stats.combat) + 3                 # a term on the live block only
	world.units[id].base_speed = 8
	world.combat.gain_experience(f, 5)
	check(int(f.stats.combat) == 10 and int(f.base.combat) == 7, "the live block moves by the promotion's difference")
	check(int(world.units[id].base_speed) == int(f.stats.speed) and int(f.stats.speed) == 9, "the walking speed follows")
	world.production.research[OWNER] = ["PAR0"]
	world.combat.refresh_research(OWNER)
	check(int(f.stats.armour) == int(f.base.armour) + 5, "research adds to the raised block")
	check(int(f.base.armour) == 11, "the block is not touched by research")

func healing():
	new_world()
	var id := unit("AHKX", Vector2i(0, 0), OWNER, {"hp": 1})
	var f = fighter_of(id)
	f.max_hp = 40
	f.base.max_hp = 40
	world.combat.gain_experience(f, 5)
	check(int(f.hp) == 45 and int(f.max_hp) == 45, "a promotion heals the unit: %d / %d" % [int(f.hp), int(f.max_hp)])
	var big := unit("AHCX", Vector2i(2, 0), OWNER)
	var g = fighter_of(big)
	g.hp = 2
	world.combat.gain_experience(g, 1500)
	var row: Dictionary = ranks.gains[15].steps[0]
	check(String(ranks.gains[15].code) == "AHCX" and int(g.hp) == int(row.heal[0]) and int(g.max_hp) == int(row.state[5]) and int(g.hp) < int(g.max_hp), "at most 100 at a time: %d / %d" % [int(g.hp), int(g.max_hp)])

func titans():
	new_world()
	var id := unit("ATKX", Vector2i(0, 0), OWNER)
	var f = fighter_of(id)
	var before: int = int(f.base.combat)
	world.combat.gain_experience(f, 1500)
	check(int(f.rank) == 0 and int(f.xp) == 0 and int(f.base.combat) == before, "a titan gains nothing (+0x1cd)")
	check(UnitRanks.is_titan("ATKX") and UnitRanks.is_titan("ATEX") and not UnitRanks.is_titan("AHKX") and not UnitRanks.is_titan("ATKY"), "A T ? X")

## Soul Flame's kind 0x11 promotes through the same routine (B1-6b's open promotions).
func soul_flame():
	new_world()
	var id := unit("AHKX", Vector2i(0, 0), OWNER)
	var o: Dictionary = world.spells.object_of("unit", id)
	check(world.spells.add_experience(o, 25, 20) == 20, "the gain stops at the cap")
	var f = fighter_of(id)
	check(int(f.xp) == 20 and int(f.rank) == 3, "and the unit rose: %d" % int(f.rank))
	check(world.spells.add_experience(o, 25, 20) == 0, "nothing at the cap")

## Message 0xfa's tail: +0x10, then 0x557d90 unless flagged; animals none; no hero none.
func creation():
	new_world()
	var h := hero("AHHX", {}, OWNER, Vector2i(8, 8), [20, 20, 20, 20])
	var f = world.combat.fighters[unit("AHKX", Vector2i(0, 0), OWNER)]
	var expected: int = world.combat.starting_xp(OWNER, "AHKX")
	check(expected > 0, "a living hero teaches: %d" % expected)
	world.combat.creation_experience(f, 3)
	check(int(f.xp) == 3 + expected, "+0x10 then the starting experience")
	check(int(f.rank) > 0 or expected + 3 < 5, "a high enough start is a rank at creation")
	var sheep = world.combat.fighters[unit("ACSH", Vector2i(1, 0), OWNER)]
	world.combat.creation_experience(sheep, 0)
	check(int(sheep.xp) == 0, "an animal has no starting experience")
	var flagged = world.combat.fighters[unit("AHKX", Vector2i(2, 0), OWNER)]
	world.combat.creation_experience(flagged, 7, false)
	check(int(flagged.xp) == 7, "+0x3b set: only the message's experience")
	var other = world.combat.fighters[unit("AHKX", Vector2i(3, 0), ENEMY)]
	world.combat.creation_experience(other, 0)
	check(int(other.xp) == 0, "no hero, no starting experience")
	world.combat.fighters[h].hp = 0
	check(world.combat.starting_xp(OWNER, "AHKX") == 0, "a dead hero teaches nothing")
	world.combat.fighters[h].hp = 100
	# Telepathy (effect 3 on the hero): the term of 0x557d90's first block.
	world.combat.fighters[h]["statuses"] = [{"kind": 3, "value": 11, "until": 100000000}]
	check(world.combat.starting_xp(OWNER, "AHKX") == expected + 11, "effect 3 adds its value")

func summons():
	new_world()
	var h := hero("AHHX", {}, OWNER, Vector2i(8, 8), [7, 5, 8, 4], [{"id": 0x5b, "unlock_level": 1, "rank": 2}])
	check(world.spells.summon_start(OWNER, "AAEF") == HeroEffects.skill_term(0x5b, 2, 1), "0x557d90(p, type, 0, 1, 1): the skill tied to the type: %d" % world.spells.summon_start(OWNER, "AAEF"))
	check(world.spells.summon_start(OWNER, "AHKX") == 0, "and no general term")
	world.combat.fighters[h].hp = 0
	check(world.spells.summon_start(OWNER, "AAEF") == 0, "a dead hero: no skill")
	world.combat.fighters[h].hp = 100
	world.production.research[OWNER] = ["PGA0", "PGA1"]
	check(world.spells.summon_start(OWNER, "AHKX") == 40, "PGAX level x 20")
	var made: Dictionary = world.spells.spawn("AHKX", centre + Vector2i(-3, 0), OWNER, 25, 0)
	var f = fighter_of(int(made.id))
	check(int(f.xp) == 25 and int(f.rank) == 3, "a summon's +0x9b is its rank, no 0x557d90 on top: %d" % int(f.xp))

func resurrection():
	new_world()
	var veteran := unit("AHKX", Vector2i(0, 0), ENEMY)
	var f = fighter_of(veteran)
	world.combat.gain_experience(f, 40)
	var rank: int = int(f.rank)
	world.combat.apply_damage("unit", veteran, 100000, -1)
	var made: Dictionary = world.spells.resurrect({"id": veteran, "cell": centre}, {"owner": OWNER})
	var g = fighter_of(int(made.id))
	check(int(g.xp) == 40 and int(g.rank) == rank, "the body's experience comes back (0x526db0)")
	var v := unit("AHKX", Vector2i(2, 2), ENEMY)
	var strip: Dictionary = world.spells.strip_flesh(world.spells.object_of("unit", v), {})
	check(int(fighter_of(int(strip.id)).xp) == 0, "Strip Flesh's Skeleton: no hero, no start")

## The rank terms already read from f.rank: ability level, scavenging, assassins, Strip / Rot's level.
func casters():
	new_world()
	check(RacePowers.scavenge_level(0) == 1 and RacePowers.scavenge_level(3) == 1 and RacePowers.scavenge_level(4) == 2 and RacePowers.scavenge_level(9) == 3, "(rank + 1) / 5 + 1")
	var id := unit("AKJX", Vector2i(0, 0), OWNER)
	var f = fighter_of(id)
	check(int(world.combat.combat_block(f).get("assassin", 0)) == 4, "assassin at rank 0")
	world.combat.gain_experience(f, 20)
	check(int(world.combat.combat_block(f).get("assassin", 0)) == 7, "4 + rank")
	check(world.spells.unit_level(world.spells.object_of("unit", id)) == 3, "0x526d80")

func regen_world():
	new_world()
	var id := unit("AHKX", Vector2i(0, 0), OWNER)
	var f = fighter_of(id)
	world.combat.now_ms = 1000
	world.combat.next_update_ms = 1000
	world.ms = 1000
	run_world(40000)
	check(int(f.hp) == 40 and int(f.get("regen_ms", 0)) == 0, "an unhurt unit never arms the timer")
	world.combat.apply_damage("unit", id, 3, -1)
	check(int(f.regen_ms) > 0 and int(f.hp) == 37, "a hit arms it (0x522860)")
	run_world(10100)
	check(int(f.hp) == 38, "one point after 10 s at rank 0: %d" % int(f.hp))
	f["garrisoned"] = true
	run_world(30100)
	check(int(f.hp) == 40 and int(f.regen_ms) == 0, "garrisoned it heals faster and stops at full: %d" % int(f.hp))
	f["garrisoned"] = false
	var b := unit("AHKX", Vector2i(2, 0), OWNER)
	var g = fighter_of(b)
	g.base.max_hp = 40
	world.combat.apply_damage("unit", b, 3, -1)
	g["poisoned"] = true
	g["poison_until_ms"] = int(world.ms) + 600000
	g["poison_next_ms"] = int(world.ms) + 500
	run_world(5000)
	check(int(g.hp) < 37, "poison bites and no regeneration: %d" % int(g.hp))

func saved():
	new_world()
	var id := unit("AHKX", Vector2i(0, 0), OWNER)
	var f = fighter_of(id)
	world.combat.gain_experience(f, 40)
	world.combat.apply_damage("unit", id, 5, -1)
	var s: Dictionary = SaveGame.capture(world.combat, world.combat._SAVE_SKIP)
	check(int(s.fighters[id].rank) == 4 and int(s.fighters[id].xp) == 40, "rank and experience are in the save")
	check(int(s.fighters[id].base.combat) == int(f.base.combat) and int(s.fighters[id].regen_ms) == int(f.regen_ms), "the raised block and the timer too")
	var restored: Dictionary = SaveGame.copy(s.fighters[id])
	check(int(restored.max_hp) == int(f.max_hp), "max hit points")

func hud_rules():
	check(GameHud.list_frame(false, 3) == 0 and GameHud.list_frame(false, 4) == 1 and GameHud.list_frame(true, 0) == 1, "0x526d80 >= 4 or a hero")
	check(GameHud.rank_medals(0) == [0, 0] and GameHud.rank_medals(4) == [0, 4] and GameHud.rank_medals(5) == [1, 0] and GameHud.rank_medals(13) == [2, 3], "large and small medals")
	check(GameHud.rank_medals(19) == [3, 4] and GameHud.rank_medals(40) == [3, 4], "at most 19")

## PARITY_BACKLOG.md 7: 0x533dc0 executed for 76 heroes, keeps, research and slots against the port's terms; one point of the
## limit is one more Charisma above an even step: the two pictures' heroes differed (COMBAT_RESEARCH.md "R-1").
func command_limit():
	var t: Dictionary = ranks.tables
	for i in 6: check(int(t.keep_command[i]) == int(ProductionRulesRanks.KEEP_COMMAND_TABLE[i]), "0x6115d4 %d" % i)
	for i in 10: check(int(t.command_research[i]) == int(world_command_research(i)), "0x6115e0 %d" % i)
	for row in ranks.command:
		new_world()
		var h := -1
		if bool(row.hero):
			var skills: Array = []
			for s in row.skills: skills.append({"id": int(s[0]), "unlock_level": int(s[1]), "rank": int(s[2])})
			h = hero("AHHX", {}, OWNER, Vector2i(8, 8), row.stats, skills)
			if not bool(row.alive): world.combat.fighters[h].hp = 0
		var p = world.production
		var f = world.combat.fighters.get(h)
		var block: Dictionary = world.combat.hero_block(OWNER)
		p.hero_commands[OWNER] = world.combat.hero_command_value(OWNER, block, f) / 2 if f != null and int(f.hp) > 0 and not block.is_empty() else 0
		p.research[OWNER] = row.research
		if row.computer != null: p.ai_players[OWNER] = int(row.computer)
		var i := 0
		for code in row.units:
			unit(String(code), Vector2i(-4 + i, -4), OWNER)
			i += 1
		var limit := int(p.population(OWNER).maximum)
		var keep_level := 0
		if row.keep != null: keep_level = ProductionRulesRanks.keep_level(String(row.keep))
		limit += int(ProductionRulesRanks.KEEP_COMMAND_TABLE[keep_level]) - int(ProductionRulesRanks.KEEP_COMMAND_TABLE[0])
		check(limit == int(row.maximum), "0x533dc0 %s: %d" % [row, limit])
		check(int(p.population(OWNER).current) == int(row.used), "0x533dc0 used %s: %d" % [row, int(p.population(OWNER).current)])

func world_command_research(i: int) -> int:
	return int(preload("res://simulation/production.gd").COMMAND_RESEARCH[i])

func attitude():
	var r: Rect2 = GameHud.attitude_place(Vector2(500, 400), 9, Vector2(1600, 900))
	check(r == Rect2(400, 390, 0x17c, 192), "0x559860: 100 left, 10 above, (9 x 18 + 35) / 16 x 16 high: %s" % [r])
	check(GameHud.attitude_place(Vector2(10, 2), 9, Vector2(1600, 900)).position == Vector2(8, 8), "8 pixels inside the view")
	check(GameHud.attitude_place(Vector2(1590, 890), 9, Vector2(1600, 900)).position == Vector2(1600 - 8 - 0x17c, 900 - 0x30 - 192), "and 0x30 above the bottom")
	check(GameHud.attitude_place(Vector2(500, 400), 1, Vector2(1600, 900)).size.y == 64, "at least four bands")

func results_bars():
	check(ResultsScreen.bar_percent(5, 5) == 100 and ResultsScreen.bar_percent(0, 0) == 100 and ResultsScreen.bar_percent(7, 0) == 100, "equal, or a top of 0: full (0x44bfa0)")
	check(ResultsScreen.bar_percent(1, 3) == 33 and ResultsScreen.bar_percent(0, 3) == 0 and ResultsScreen.bar_percent(4, 3) == 100, "a truncated percent, at most 100")
	var players := [{"total_kills": 8, "razed": 4}]
	check(ResultsScreen.bar_target(1, 1, 50, [0, 100, 0, 0, 0, 0, 200, 0, 0, 0], players) == 25, "In and Out share the higher top (0x44bfd0)")
	check(ResultsScreen.bar_target(1, 6, 50, [0, 100, 0, 0, 0, 0, 200, 0, 0, 0], players) == 25, "from either side")
	check(ResultsScreen.bar_target(2, 3, 2, [9, 9, 9, 9], players) == 25, "kills by side: of the local total")
	check(ResultsScreen.bar_target(3, 4, 1, [9, 9, 9, 9, 9], players) == 25, "razes by side: of the local total")
	check(ResultsScreen.bar_target(0, 0, 3, [6, 0, 0, 0], players) == 50, "hero page: of the column's top")

func credits():
	var path: String = CreditsText.installed_path()
	check(path != "", "the installation's Credits.xml")
	var lines: Array = CreditsText.read_lines(path)
	check(lines.size() > 40, "its lines: %d" % lines.size())
	check(bool(lines[0].heading) and String(lines[0].text) == "Infinite Interactive" and bool(lines[1].blank), "heading, blank")
	var state: Dictionary = CreditsText.new_state()
	var first: Array = CreditsText.lay_out(lines, state)
	check(first.size() == 1 and int(first[0].font) == CreditsText.HEADING_FONT and int(first[0].x) == 270 and int(first[0].y) == 150, "the first line: %s" % [first])
	for i in CreditsText.SUB_TICKS: CreditsText.tick(state)
	check(int(state.shown) == 1, "one line more every eight ticks")
	var pages := 0
	var columns := {}
	for i in 40000:
		var before := int(state.first)
		for row in CreditsText.lay_out(lines, state): columns[int(row.x)] = true
		if int(state.first) != before: pages += 1
		if pages >= 2 and int(state.first) == 0: break
		CreditsText.tick(state)
	check(columns.has(270) and columns.has(535), "both columns")
	check(pages >= 2 and int(state.first) == 0, "pages turn and the list starts again: %d" % pages)

## REVIEW_R1.md D1-D3: the 0xfd sender 0x4a5780 against tests/rank_review_fixtures.json "fd_builder"
## (tools/emulate_ranks_review.py), a 0xfd unit in the world, Morph then a promotion, poison and disease arming regeneration.
func review_fixes():
	var review: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/rank_review_fixtures.json"))
	check(same(review.levels, UnitRanks.CREATION_XP), "0x5fbc48")
	for row in review.fd_builder:
		var research: Array = row.research
		var plox := 0
		for item in research:
			if String(item).begins_with("PLO"): plox += 1
		var term: int = 0 if row.term == null else int(row.term)
		var gain := UnitRanks.creation_gain(String(row.code), research.has("PTRN"), plox, research.has("PORO"), int(row.xp), term)
		check(gain == int(row.gain), "0x4a5780 gain %s %s: %d / %d" % [row.code, str(research), gain, int(row.gain)])
		var xp := UnitRanks.creation_xp(int(row.rank), int(row.xp), bool(row.scenario))
		check(xp == int(row.out_xp), "0x4a5780 experience rank %d xp %d: %d / %d" % [int(row.rank), int(row.xp), xp, int(row.out_xp)])
	new_world()
	var a = fighter_of(unit("AHKX", Vector2i(0, 0), OWNER))
	world.combat.set_rank(a, 3, 777)
	check(int(a.rank) == 3 and int(a.xp) == 10, "a rank-3 0xfd unit arrives with 10: %d / %d" % [int(a.rank), int(a.xp)])
	var b = fighter_of(unit("AHKX", Vector2i(1, 0), OWNER))
	world.combat.set_rank(b, 0, 0)
	check(int(b.rank) == 0 and int(b.xp) == 0, "rank 0: -1 becomes 0")
	var c = fighter_of(unit("AHKX", Vector2i(2, 0), OWNER))
	world.combat.set_rank(c, 2, 0, 100)
	check(int(c.rank) == 5 and int(c.xp) == 105, "the gain promotes through 0x527100: %d / %d" % [int(c.rank), int(c.xp)])
	# D2: Morph writes the block word; the next promotion reads and clamps the morphed word.
	var mid := unit("AHKX", Vector2i(3, 0), OWNER)
	var m = fighter_of(mid)
	var start: int = int(m.base.combat)
	world.spells.morph(world.spells.object_of("unit", mid), 0, 50)
	check(int(m.base.combat) == start + 50 and int(m.stats.combat) == start + 50 and start + 50 > 50, "Morph Combat on the block: %d" % int(m.base.combat))
	world.combat.gain_experience(m, 5)
	check(int(m.base.combat) == 50 and int(m.stats.combat) == 50, "the promotion clamps the morphed word at 50: %d" % int(m.stats.combat))
	world.production.research[OWNER] = ["PAR0"]
	world.combat.refresh_research(OWNER)
	check(int(m.base.combat) == 50, "research keeps the morph")
	world.production.research[OWNER] = []
	world.combat.refresh_research(OWNER)
	# D3: poisoning and disease arm the timer of any unit (0x51bfb0, 0x51c060); after the cure the unit regenerates.
	world.combat.now_ms = 1000
	world.combat.next_update_ms = 1000
	world.ms = 1000
	var pid := unit("AHKX", Vector2i(4, 0), OWNER)
	var p = fighter_of(pid)
	p.hp = 30
	world.units[pid].hp = 30
	world.combat.set_poisoned(pid, true)
	check(int(p.get("regen_ms", 0)) > 0, "a poisoning arms the timer without a hit")
	world.combat.set_poisoned(pid, false)
	run_world(25000)
	check(int(p.hp) > 30, "cured, the unit regenerates: %d" % int(p.hp))
	var d = fighter_of(unit("AHKX", Vector2i(5, 0), OWNER))
	world.spells.set_disease(d)
	check(int(d.get("regen_ms", 0)) > 0, "a disease arms a non-hero's timer too")
