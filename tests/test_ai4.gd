extends SceneTree
## Milestone AI-4 (AI_RESEARCH.md "AI-4"): the emulated fixtures of tools/emulate_ai4.py (tests/ai4_fixtures.json) against
## the port: the strength tables 0x505530 and the danger test 0x4fac00 (simulation/ai_danger.gd), the CustomAI loader
## 0x4f7460 / 0x4f76d0 and the profile's priorities (simulation/custom_ai.gd, AiPlayer), the hate add 0x4fa580, plus the
## setup record's CustomAI name (simulation/skirmish_setup.gd). Every case must match.

const AiPlayer = preload("res://simulation/ai_player.gd")
const Danger = preload("res://simulation/ai_danger.gd")
const CustomAi = preload("res://simulation/custom_ai.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")

class FakeWorld:
	var production := {"rules": null}

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 20: printerr("AI-4 check failed: ", label)

## JSON numbers are floats: nested arrays as ints for comparison.
func ints(v):
	if v is Array: return v.map(func(x): return ints(x))
	return int(v)

func _initialize():
	var f = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai4_fixtures.json"))
	if not (f is Dictionary) or not f.has("danger"):
		printerr("AI-4 fixtures missing or unreadable")
		quit(1)
		return
	var catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalogue.json"))
	# ---- 0x505530: one value per ARM / BUI record
	for code in f.strength.units:
		check(Danger.unit_strength(String(catalogue.units[code].raw_hex).hex_decode()) == int(f.strength.units[code]), "unit strength " + code)
	for code in f.strength.buildings:
		check(Danger.building_strength(String(catalogue.buildings[code].raw_hex).hex_decode()) == int(f.strength.buildings[code]), "building strength " + code)
	# ---- 0x4fac00
	var cases := 0
	for c in f.danger:
		cases += 1
		var objects: Array = []
		for o in c.objects:
			if not bool(o.has_object): continue
			var kind := int(o.kind)
			var value: int = int(c.unit_table[int(o.type)]) if kind == 0 else int(c.building_table[int(o.type)])
			var targets: bool = bool(o.targets_asker) if kind == 0 else (int(o.attack) > 0 and bool(o.armed) and bool(o.targets_asker))
			objects.append({"cell": Vector2i(int(o.cell[0]), int(o.cell[1])), "owner": int(o.owner), "hidden": bool(o.hidden),
				"kind": kind, "value": value, "targets": targets})
		var me := int(c.me)
		var relations: Array = c.relations
		var half: int = (int(c.asker_radius) + (16 if int(c.asker_kind) == 0 else 12)) if int(c.asker_kind) < 2 else -1
		var got := Danger.danger(Vector2i(int(c.centre[0]), int(c.centre[1])), half, int(c.width), int(c.height), objects,
			func(owner): return int(relations[me][owner]) != 0, bool(c.only_targeting))
		check(got == int(c.result), "danger case %d: %d vs %d" % [cases, got, int(c.result)])
	# ---- 0x4f76d0: the install's files are refused, files in the executable's own layout load
	var folder := ""
	var found: Array = CustomAi.folders()
	if found.size() > 1: folder = String(found[0])          # the install's folder (the last entry is the user folder)
	var shipped := 0
	for c in f.loader:
		cases += 1
		var label := String(c.label)
		if label.ends_with(".ai"):
			shipped += 1
			var path := folder.path_join(label)
			if not FileAccess.file_exists(path): continue        # an install without the folder: the fixture still checks the header rule
			var r := CustomAi.load_file(path)
			check(not bool(r.loaded) and not bool(c.loaded), "shipped file %s refused" % label)
			check(String(r.name) == String(c.profile.name), "shipped file %s name %s" % [label, r.name])
			var h := CustomAi.header(path)
			check(int(h.race) == int(c.race), "shipped file %s race" % label)
			continue
		if c.file_hex == null:
			check(not bool(CustomAi.load_file("").loaded), "no file")
			continue
		var bytes := String(c.file_hex).hex_decode()
		var r := CustomAi.parse(bytes)
		check(bool(r.loaded) == bool(c.loaded), "loader %s: %s" % [label, r.loaded])
		if not bool(r.loaded): continue
		var p: Dictionary = r.profile
		var e: Dictionary = c.profile
		check(int(p.word_4) == int(e.word_4), label + " word 4")
		check(ints(p.units) == ints(e.units) and ints(p.research) == ints(e.research), label + " slots")
		check(ints(p.group_min) == ints(e.group_min) and ints(p.group_max) == ints(e.group_max), label + " group sizes")
		check(int(p.danger_margin) == int(e.bytes_20b4[8]) and int(p.conversion_share) == int(e.bytes_20b4[9]) and bool(p.hero_retreats) == (int(e.bytes_20b4[13]) != 0), label + " bytes")
		check(String(r.name) == String(e.name), label + " name")
		# 0x4fc700 / 0x4fc770 through the computer player: list entry i takes slot i
		var world := FakeWorld.new()
		world.production.rules = ProductionRules.new()
		var ai = AiPlayer.new(1, 3, world, 0, p)
		var listed: Array = ai.unit_order.filter(func(id): return id != ai.HERO)
		for i in mini(listed.size(), 30):
			var want := 50 if int(e.word_4) == -1 else (int(e.units[i][1]) if int(e.units[i][0]) != 0 else -1)
			check(int(ai.units[listed[i]].priority) == want, "%s unit %d priority" % [label, i])
		for i in mini(ai.research_order.size(), 40):
			var want := 50 if int(e.word_4) == -1 else (int(e.research[i][1]) if int(e.research[i][0]) != 0 else -1)
			check(int(ai.research[ai.research_order[i]].priority) == want, "%s research %d priority" % [label, i])
		ai.dispose()
	check(shipped == 14, "14 shipped files in the fixtures")
	# the selection list's race filter (0x4eebe0): Knights (race 0) see the H_ and the G_ files
	if folder != "":
		var knights: Array = CustomAi.list(0, [folder]).map(func(e): return String(e.file))
		check(knights == ["G_Defender.ai", "G_Miner.ai", "G_Nuisance.ai", "G_Reckless.ai", "H_Knightlord.ai", "H_KnightProtector.ai", "H_LordOfTheMagi.ai"], "Knights list %s" % str(knights))
		var orcs: Array = CustomAi.list(5, [folder]).map(func(e): return String(e.label))
		check(orcs.has("Goblin King") and orcs.size() == 5, "Orc list %s" % str(orcs))
	# ---- 0x4fa580 through AiPlayer.add_hate
	var world2 := FakeWorld.new()
	world2.production.rules = ProductionRules.new()
	var hater = AiPlayer.new(1, 3, world2)
	for c in f.hate:
		cases += 1
		hater.hate = [0, 0, 0, 0, 0, 0, 0]
		hater.hate[int(c.player)] = int(c.before)
		hater.add_hate(int(c.amount), int(c.player))
		check(int(hater.hate[int(c.player)]) == int(c.after), "hate %s" % str(c))
	hater.dispose()
	# ---- the setup record: a race change clears the name (0x4eb030); resolve hands it to computer slots only
	var setup := {"players": [{"kind": Setup.COMPUTER, "race": 0, "custom_ai": ""}]}
	Setup.set_custom_ai(setup, 0, "H_Knightlord.ai")
	check(String(setup.players[0].custom_ai) == "H_Knightlord.ai", "set the CustomAI name")
	Setup.set_race(setup, 0, 3)
	check(String(setup.players[0].custom_ai) == "", "a race change clears the CustomAI name")
	if failures > 0:
		printerr("AI-4 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI-4 checks passed: %d checks over %d fixture cases" % [checks, cases])
	quit(0)
