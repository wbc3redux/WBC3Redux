extends SceneTree
## B1-3 (B1_3_RESEARCH.md): the ports against the emulated fixtures.
## * simulation/advancement.gd against tests/batch1_review_fixtures.json "advancement" (tools/emulate_batch1_review.py):
##   the tree 0x4fd8c0, the flat prices 0x40b6b0 (through production_rules.gd), the discount 0x40c350, the advancement
##   buttons of 0x4d3200 (icon, callback, enabled) and the messages of the order 0x4cef90.
## * simulation/day_night.gd against tests/day_night_fixtures.json (tools/emulate_day_night.py): 0x499a00 / 0x499a50,
##   both transitions tick by tick, the combat getter 0x51bd10's weather block, the regeneration entry 0x51b820 and the
##   palette lighting levels.
## * race_powers.gd / advancement.gd rules that are Read (Slavehorde count, brew drinkers, morphed experience).

const Advancement = preload("res://simulation/advancement.gd")
const DayNight = preload("res://simulation/day_night.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
const Rules = preload("res://simulation/production_rules.gd")
const CombatRng = preload("res://simulation/combat_rng.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Undead powers check failed: ", label)

func _initialize():
	var review: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch1_review_fixtures.json"))
	var day: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/day_night_fixtures.json"))
	advancement(review.advancement)
	day_night(day)
	rules_read()
	if failures > 0:
		printerr("Undead powers checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Undead powers checks passed: %d" % checks)
	quit(0)

const GATES := ["BPDM", "BPBA", "BPAS", "BPCG", "BPBL"]

func scenario_state(name: String) -> Dictionary:
	var gates: Array = []
	if name.begins_with("all gates"): gates = GATES.duplicate()
	elif name.begins_with("only "): gates = [name.get_slice(" ", 1).trim_suffix(",")]
	elif name.begins_with("all but "):
		var drop := name.get_slice(" ", 2).trim_suffix(",")
		gates = GATES.filter(func(g): return g != drop)
	var stock := [5000, 5000, 5000, 5000]
	if name.ends_with("poor"): stock = [0, 0, 0, 0]
	if name.contains("metal "):
		stock[1] = int(name.get_slice("metal ", 1).get_slice(" ", 0))
		stock[2] = int(name.get_slice("crystal ", 1).get_slice(" ", 0))
	return {"gates": gates, "stock": stock}

func advancement(fx: Dictionary):
	var rules := Rules.new()
	# 0x4fd8c0
	for code in fx.tree_4fd8c0:
		check(Advancement.TREE.get(code, []) == fx.tree_4fd8c0[code], "0x4fd8c0 tree of %s: %s" % [code, fx.tree_4fd8c0[code]])
		for target in fx.tree_4fd8c0[code]: check(Advancement.SOURCE[target] == code, "0x4cef90 source of %s" % target)
	# 0x40b6b0 flat branch (race 2) and the Dark Dwarves' record prices (race 10)
	for key in fx.price_40b6b0:
		var race := int(String(key).get_slice(" ", 0).trim_prefix("race"))
		var target := String(key).get_slice(" ", 1)
		var cost: Array = fx.price_40b6b0[key].cost
		var got: Dictionary = rules.price(target, {"race": race})
		if race == 2: check(got.cost == [int(cost[0]), int(cost[1]), int(cost[2]), int(cost[3])] and int(got.seconds) == int(cost[4]), "0x40b6b0 %s: %s vs %s" % [key, got, cost])
	# 0x40c350
	for row in fx.discount_40c350:
		if row[2] is String: continue
		if int(row[1]) == -99 and int(row[0]) == 350: continue        # wraps to a negative short in the original (the port keeps it)
		check(Rules.discounted(int(row[0]), int(row[1])) == int(row[2]), "0x40c350(%d, %d) = %d" % [int(row[0]), int(row[1]), int(row[2])])
	# 0x4d3200: the advancement buttons of every recorded selection and scenario
	var callbacks := {}
	for source in Advancement.BUTTONS:
		for b in Advancement.BUTTONS[source]: callbacks[String(b.callback)] = true
	var compared := 0
	for row in fx.buttons_4d3200:
		var state := scenario_state(String(row.scenario))
		var expected: Array = row.buttons.filter(func(b): return callbacks.has(String(b.callback)))
		var got := Advancement.buttons(String(row.source), int(row.count), func(code): return state.gates.has(code),
			func(target): return rules.price(target, {"race": 2}).cost, state.stock)
		var same: bool = got.size() == expected.size()
		for i in mini(got.size(), expected.size()):
			same = same and int(got[i].icon) == int(expected[i].icon) and String(got[i].callback) == String(expected[i].callback) \
				and bool(got[i].enabled) == bool(int(expected[i].enabled))
		check(same, "0x4d3200 %s x%d %s: %s vs %s" % [row.source, int(row.count), row.scenario, got.map(func(b): return [b.icon, b.enabled]), expected])
		compared += 1
	check(compared == 154, "154 button rows compared (%d)" % compared)
	# 0x4cef90: the messages for 1 / 5 / 20 / 40 selected units
	for row in fx.order_4cef90:
		var units: Array = []
		for i in int(row.count): units.append({"id": i, "type": String(row.source), "removed": false})
		var a: Array = row.args
		var cost := [int(a[0]), int(a[1]), int(a[3]), int(a[2])]
		var got := Advancement.order(units, String(row.target), cost, row.stock)
		var expected: Array = row.messages
		var same: bool = got.size() == expected.size()
		for i in mini(got.size(), expected.size()):
			var e: Dictionary = expected[i]
			same = same and int(got[i].message) == String(e.message).hex_to_int() \
				and got[i].cost == e.costs_p3_p4_p6_p5.map(func(v): return int(v)) \
				and (got[i].units.size() == int(e.get("units", 1)))
		check(same, "0x4cef90 %s x%d stock %s: %s vs %s" % [row.target, int(row.count), row.stock, got.map(func(m): return [m.message, m.units.size(), m.cost]), expected])
	# the one-unit path ignores the unit's type; a removed unit is skipped
	check(Advancement.order([{"id": 3, "type": "AHKX"}], "AUJX", [0, 70, 0, 0], [0, 70, 0, 0]).size() == 1, "one unit: type not checked (0x4cef90)")
	check(Advancement.order([{"id": 3, "type": "AUIX", "removed": true}], "AUJX", [0, 70, 0, 0], [0, 70, 0, 0]).is_empty(), "one unit being removed: nothing")
	check(Advancement.order([{"id": 1, "type": "AUIX"}, {"id": 2, "type": "AUJX"}, {"id": 3, "type": "AUIX"}], "AUJX", [0, 70, 0, 0], [0, 500, 0, 0])[0].units == [1, 3], "a group takes only the source type")

func day_night(fx: Dictionary):
	for row in fx.tests:
		var c: Array = row.clock
		check(DayNight.day_test(int(c[0]), int(c[1]), int(c[2])) == bool(int(row.day)), "0x499a00 %s" % [c])
		check(DayNight.night_test(int(c[0]), int(c[1]), int(c[2])) == bool(int(row.night)), "0x499a50 %s" % [c])
	for name in fx.transitions:
		var t: Dictionary = fx.transitions[name]
		var dn := DayNight.new(true)
		if String(name).begins_with("day"):
			dn.hour = 1; dn.mark_a = 0; dn.mark_b = 2; dn.level = 3
			dn.to_day(int(t.param))
		else:
			dn.to_night(int(t.param))
		var changes: Array = t.changes
		var at := 0
		var ok := true
		for tick in range(0, int(t.ticks) + 1):
			if tick > 0: dn.tick()
			if at < changes.size() and int(changes[at].tick) == tick:
				var e: Dictionary = changes[at]
				var clock := [dn.hour, dn.mark_a, dn.mark_b]
				if dn.level != int(e.level) or dn.mode != int(e.mode) or dn.step != int(e.step) or clock != e.clock.map(func(v): return int(v)) or dn.target != int(e.target):
					ok = false
					printerr("  %s tick %d: level %d mode %d step %d clock %s target %d vs %s" % [name, tick, dn.level, dn.mode, dn.step, clock, dn.target, e])
				at += 1
		check(ok and at == changes.size(), "transition %s: %d ticks, every change" % [name, int(t.ticks)])
		check(dn.is_day() == bool(int(t.after.day)) and dn.is_night() == bool(int(t.after.night)), "after %s: day %s night %s" % [name, dn.is_day(), dn.is_night()])
	# 0x51bd10: the weather block (rain is never set in the rebuild: the rain rows are checked through `raining`)
	for row in fx.combat:
		var w := String(row.weather)
		var dn := DayNight.new(w != "none")
		if w.begins_with("night"):
			dn.hour = 1; dn.mark_a = 0; dn.mark_b = 2
		dn.raining = w.ends_with("rain")
		check(dn.combat_value(int(row.base), int(row.flags), String(row.unit)) == int(row.combat), "0x51bd10 %s %s %s: %d" % [row.unit, w, row.status, int(row.combat)])
	# 0x51b820's entry
	for row in fx.regeneration:
		var w := String(row.weather)
		var dn := DayNight.new(w != "none")
		if w == "night":
			dn.hour = 1; dn.mark_a = 0; dn.mark_b = 2
		var blocked := dn.blocks_regeneration(int(row.flags))
		var timer: int = int(row.now) + DayNight.UNDEAD_PAUSE_MS if blocked else 0
		check(timer == int(row.timer) and int(row.ret) == 0, "0x51b820 %s flags %x: timer %d" % [w, int(row.flags), int(row.timer)])
	# the palette levels
	for level in fx.palette:
		var p: Dictionary = fx.palette[level]
		var ok := true
		for pair in p.mixed: ok = ok and DayNight.light(int(pair[0]), int(level)) == int(pair[1])
		for r in 32: ok = ok and (DayNight.light(r << 11, int(level)) >> 11) == int(p.red[r])
		for g in 64: ok = ok and ((DayNight.light(g << 5, int(level)) >> 5) & 63) == int(p.green[g])
		for b in 32: ok = ok and (DayNight.light(b, int(level)) & 31) == int(p.blue[b])
		check(ok, "palette level %s: 512 mixed colours and every channel value" % level)
	check(DayNight.light(0x1234, 0) == 0x1234, "level 0 leaves the colour")
	# the record amounts and the setting
	var dn := DayNight.new(true)
	dn.apply_record(2)
	for i in 52: dn.tick()
	check(dn.is_night(), "a kind-4 record with amount 2 brings night after 52 ticks (2.6 s)")
	dn.apply_record(2)
	check(dn.mode == 0, "amount 2 at night does nothing")
	dn.apply_record(0)
	for i in 51: dn.tick()
	check(dn.is_night(), "still night one tick before the dawn ends")
	dn.tick()
	check(dn.is_day(), "amount 0 brings day")
	var off := DayNight.new(false)
	off.apply_record(2)
	for i in 60: off.tick()
	check(not off.is_day() and not off.is_night() and off.level == 0, "with the setting off there is no clock (no weather object)")
	check(off.combat_value(7, 0x4, "AUXX") == 7 and not off.blocks_regeneration(0x4), "setting off: no time-of-day terms")

func rules_read():
	check(RacePowers.slavehorde_count(20, 50) == 10 and RacePowers.slavehorde_count(45, 50) == 5 and RacePowers.slavehorde_count(50, 50) <= 0, "Slavehorde n = min(10, limit - count)")
	check(RacePowers.can_drink("ADIX", 0x2, false) and not RacePowers.can_drink("ADHX", 0x2, true) and RacePowers.can_drink("AMIX", 0, false) and not RacePowers.can_drink("AHKX", 0x1, false), "brew drinkers (0x528cd0)")
	check(Advancement.morphed_xp(12, 0) == 12 and Advancement.morphed_xp(3, 10) == 10 and Advancement.morphed_xp(15, 10) == 15, "morphed experience max(old, start) (0x4a8ff0 -> 0x4a49e0)")
	check(Advancement.starting_xp({}, "AUJX", 0x4) == 0, "no starting experience without a living hero (0x557d90)")
	check(RacePowers.scavenge_level(0) == 1 and RacePowers.scavenge_level(4) == 2, "scavenging level (rank + 1) / 5 + 1")
	var rng := CombatRng.new(1, 2)
	var copy := CombatRng.new(1, 2)
	var amounts: Array = RacePowers.scavenge_amounts(2, 0, 1, rng)
	check(int(amounts[0]) == copy.roll(1, 20) + copy.roll(1, 20) and amounts.slice(1) == [0, 0, 0], "two remains: two d20 of gold")
