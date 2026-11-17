extends SceneTree
## Sound-rule parity (AUDIO_RESEARCH.md): simulation/audio_rules.gd against tests/audio_fixtures.json, which
## tools/emulate_audio.py records by executing 0x50ee90, 0x50eef0, 0x50ef50, 0x50f020, 0x50efa0, 0x50c2e0, 0x50c530,
## 0x50f1b0 and 0x4ca480 under Unicorn. Also checks the event-to-file rules against the imported manifest.
const Rules = preload("res://simulation/audio_rules.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		if failures < 40: push_error(label)

func _init():
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/audio_fixtures.json"))
	for volume in f.volume_tables:
		var table := Rules.volume_table(int(volume))
		for i in 25: check(table[i] == int(f.volume_tables[volume][i]), "volume %s[%d]: %d vs %d" % [volume, i, table[i], int(f.volume_tables[volume][i])])
	var pans := Rules.pan_table()
	for i in 50: check(is_equal_approx(pans[i], float(f.pan_table[i])), "pan[%d]" % i)
	var k_by_resolution := [25, 30, 35, 40]          # 0x4e7200: 800 (0), 1024 (1), 1280 (2), 1600 (3)
	for c in f.indices:
		var cam := Vector2i(int(c.cam[0]), int(c.cam[1]))
		var cell := Vector2i(int(c.cell[0]), int(c.cell[1]))
		check(Rules.distance_index(cam, cell) == int(c.distance), "distance %s %s" % [cam, cell])
		check(Rules.pan_index(cam.x, cell.x, k_by_resolution[int(c.resolution)]) == int(c.pan), "pan index r%d %s %s" % [int(c.resolution), cam, cell])
		check(Rules.voice_pan_index(cam.x, cell.x) == int(c.voice_pan), "voice pan %s %s" % [cam, cell])
	for c in f.acknowledgements:
		var played: bool = int(c.counter) > Rules.ACK_COOLDOWN
		check(played == bool(c.played), "ack cooldown %s" % c)
		check(int(c.counter_after) == (0 if played else int(c.counter)), "ack counter reset %s" % c)
		if not played:
			check(int(c.new_last) == int(c.last), "ack keeps last %s" % c)
			continue
		var count: int = 4 if bool(c.hero) else int(c.count)
		var choice: Array = Rules.choose_variant(String(c.kind), count, int(c.last), int(c.roll))
		check(choice[0] == int(c.variant), "%s variant count %d last %d roll %d: %d vs %d" % [c.kind, count, int(c.last), int(c.roll), choice[0], int(c.variant)])
		check(choice[1] == int(c.new_last), "%s last count %d last %d roll %d" % [c.kind, count, int(c.last), int(c.roll)])
		check(bool(c.voice_name) == bool(c.hero), "hero voice name passed %s" % c)
	for c in f.speech_gate:
		var last := 500 if bool(c.repeat_value_same) else 7
		var gate := Rules.speech_gate(int(c.id), int(c.counter), last, 500)
		check(gate.play == bool(c.played), "speech %d counter %d same %s" % [int(c.id), int(c.counter), c.repeat_value_same])
		check(int(gate.counter) == int(c.counter_after), "speech counter %d/%d" % [int(c.id), int(c.counter)])
		if gate.play: check(gate.no_repeat == bool(int(c.no_repeat)), "speech no-repeat %d" % int(c.id))
	for c in f.channels:
		var slots: Array = []
		for i in Rules.CHANNELS:
			var e = c.slots[i] if i < c.slots.size() else null
			slots.append(null if e == null else {"priority": int(e[0]), "protected": int(e[1]) != 0, "stream": int(e[2]) != 0})
		check(Rules.allocate(slots, int(c.priority)) == int(c.slot), "channel layout %d priority %d" % [int(c.layout), int(c.priority)])
	_test_names()
	if failures == 0: print("Audio rule checks passed: ", checks)
	else: printerr("Audio rule failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

## The slice's event names resolve to imported entries (0x511c10 naming).
func _test_names():
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio_manifest.json"))
	var ids := {}
	for e in m.entries: ids[String(e.id).to_lower()] = true
	var has := func(id: String): return ids.has(id.to_lower())
	var arm: Dictionary = m.arm_sounds
	for code in ["AHBX", "AHKX", "AHMX", "AHHX"]:
		var group: String = m.voice_archives.get(code, "")
		check(group == "voices/Knights", "%s voices in KnightsVoicesEn.xcr" % code)
		var count: int = 4 if code == "AHHX" else int(arm[code].voice_variants)
		for v in range(1, count + 1):
			check(has.call("%s/%sSelect%d" % [group, code, v]), "%s Select%d" % [code, v])
			check(has.call("%s/%sOrder%d" % [group, code, v]), "%s Order%d" % [code, v])
		if code != "AHHX": check(has.call("%s/%sReady" % [group, code]), "%s Ready" % code)
		check(int(arm[code].death_sound) <= 0 or has.call("sfx/Death%d" % int(arm[code].death_sound)), "%s death sound" % code)
		for target in ["AHBX", "AHKX", "AHMX", "AHHX"]:
			check(has.call("sfx/" + Rules.attack_sound(code, int(arm[code].attack_sound), "unit", int(arm[target].struck_sound), target)), "attack %s -> %s" % [code, target])
		check(has.call("sfx/" + Rules.attack_sound(code, int(arm[code].attack_sound), "building", 0, "BKK0")), "attack %s -> building" % code)
	check(has.call("voices/Knights/AHBXBuild") and has.call("voices/Knights/AHBXCantBuild") and has.call("voices/Knights/AHHXConversion"), "work voices")
	check(has.call("voices/Knights/AHKXDeathblow") and has.call("voices/Knights/AHHXDeathblow"), "deathblow voices")
	for code in ["BKK0", "BKK1", "BAGA", "BPFL", "BRG0", "BRS1"]:
		check(has.call("sfx/" + Rules.building_sound(code)), "building sound %s -> %s" % [code, Rules.building_sound(code)])
	check(Rules.building_sound("BWL1") == "BWLX" and Rules.building_sound("BWT0") == "BWT0", "wall/tower digit rule")
	check(String(m.terrain_ambient.name) == "Desert" and has.call("terrain/Desert"), "Desert Sands ambience")
	for name in m.soundtrack.ambient + [m.soundtrack.intro, m.soundtrack.victory, m.soundtrack.defeat]:
		check(has.call("music/" + String(name)), "track %s" % name)
	check(int(m.soundtrack.tracks) == 7, "seven ambient tracks")
	for n in [1, 4, 12, 13]: check(has.call("speech/System%d" % n) and has.call("speech/SystemF%d" % n), "speech %d" % n)
	for id in ["sfx/NewClick", "sfx/Build", "sfx/Falling0", "sfx/Falling1", "sfx/HeartBeatFast", "sfx/HeartBeatSlow",
			"sfx/Victory", "sfx/Defeat", "sfx/HeroLevelUp", "sfx/Walk", "sfx/Trot"]:
		check(has.call(id), id)
	check(int(m.counts.entries) == m.entries.size() and m.entries.size() >= 2000, "manifest entry count")
	# Parity pass 2: the advisor lines now wired and their rules (AUDIO_RESEARCH.md "Parity pass 2").
	for n in [0, 1, 2, 3, 5, 8, 9, 10, 11, 14, 15, 16, 17, 18, 19, 20, 28]:
		check(has.call("speech/System%d" % n) and has.call("speech/SystemF%d" % n), "speech %d" % n)
	check(has.call("sfx/HighlightR"), "HighlightR.wav (0x60f564, the setup and results hover)")
	check(Rules.building_attack_speech(Vector2i(20, 64), Vector2i(12, 64)) == 0 and Rules.building_attack_speech(Vector2i(32, 64), Vector2i(12, 64)) == 0x1c, "building attacked: 0 within 20 cells of home (exclusive), else 28")
	check(Rules.building_attack_speech(Vector2i(31, 83), Vector2i(12, 64)) == 0 and Rules.building_attack_speech(Vector2i(12, 84), Vector2i(12, 64)) == 0x1c, "home square bounds")
	check(Rules.resource_shortage_speech([100, 50, 10, 0], [20, 60, 0, 0]) == [0x14, 0x11], "short crystal then gold (0x524450 order crystal, metal, gold, stone)")
	check(Rules.resource_shortage_speech([100, 100, 100, 100], [0, 0, 0, 0]) == [0x14, 0x13, 0x11, 0x12] and Rules.resource_shortage_speech([1, 1, 1, 1], [1, 1, 1, 1]).is_empty(), "every short lane / none")
	check(Rules.research_speech("PHLX") == 8 and Rules.research_speech("PSPR") == 9 and Rules.research_speech("PPAR") == 9 and Rules.research_speech("POMA") == -1 and Rules.research_speech("PQKN") == -1, "research complete: 8, PSPR / PPAR 9, POM* / PQKN none (0x436500)")
	var gate := Rules.speech_gate(5, 0, -1, 0)
	check(gate.play and Rules.speech_gate(5, 0, -1, 0).play, "speech 5 (hero below 50 hit points) bypasses the 250 ms gate")
	check(not Rules.speech_gate(0x1c, 3, -1, 0).play and Rules.speech_gate(0x1c, 11, -1, 0).play, "speech 28 waits for the gate")
	# Playtest 2026-11-12: a no-repeat speech (0x510f90, age word 0xafd084 >= 0x15, one step per 900 ms) returns after ~19 s.
	check(Rules.speech_age_ok(-1, 0) and not Rules.speech_age_ok(10, 30) and Rules.speech_age_ok(10, 31) and Rules.SPEECH_AGE_STEP_MS * Rules.SPEECH_NO_REPEAT_AGE == 18900,
		"no-repeat speech: first play at once, again after 21 age steps of 900 ms (18.9 s)")
