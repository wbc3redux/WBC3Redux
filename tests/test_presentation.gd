extends SceneTree
## P-1 (EFFECTS_RESEARCH.md "P-1"): presentation rules the original's code fixes, outside the simulation.
## 1. The particle path table 0x544670 / 0x544b50: particle_bursts.gd's port equals the original run under Unicorn
##    (tests/particle_path_fixtures.json, tools/emulate_particle_paths.py) for three seeds, every byte (MD5 per pattern)
##    and the sample paths record for record.
## 2. Bursts (0x5434a0 / 0x544590 / 0x544330): sheet, path group, 25 ms steps, respawns, the end; the building smoke count
##    and placement of 0x52b3e0; an emitter bursts once, 50 ms after it is placed.
## 3. Floating text 0x53a010 / 0x5349b0 / 0x534ae0: colour rule, two slots, the 500 ms late start, the 300 ms / 40 px
##    chain, rise and fade, the end.
## 4. The strategic-map alert box 0x4dcf70 / 0x4dc850: scaling, clipping, frames 1..16, the end after 100 updates, no
##    restart while running.
## 5. Death remains: the ARM +0xf4 rule and the EDT1 / EDT2 / EDTH cycle; the treasure tower's scaffold columns.
## P-4: what shows under fog / shroud (fog_view.gd): the drawing copy 0x47f110, effects 0x53ca70, bursts and emitters
##    (+0x76 / +0x131), missiles (the creation mark and the kept mark).
const ParticleBursts = preload("res://visuals/particle_bursts.gd")
const FloatingText = preload("res://hud/floating_text.gd")
const MinimapPing = preload("res://hud/minimap_ping.gd")
const BuildingRubble = preload("res://battle/building_rubble.gd")
const EffectsLayer = preload("res://visuals/effects_layer.gd")

var checks := 0
var failures := 0

class FakeMain extends Node:
	var catalogue_data := {}

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Presentation check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	path_checks()
	burst_checks()
	text_checks()
	ping_checks()
	remains_checks()
	p2_checks()
	p3_checks()
	p4_checks()
	if failures > 0:
		printerr("Presentation checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Presentation checks passed: %d" % checks)
	quit()

# ------------------------------------------------------------------------------------------------ 1. the path table
func path_checks():
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/particle_path_fixtures.json"))
	var levels := {}
	for i in 25: levels[i - 12] = int(f.bounce_levels[i])
	check(levels == ParticleBursts.BOUNCE_LEVELS, "the bounce levels 0x611ff0 equal the executable's")
	for case in f.cases:
		var table := ParticleBursts.build_paths(int(case.seed[0]), int(case.seed[1]))
		check(table.size() == 3 * ParticleBursts.PATTERN_BYTES, "table size")
		for k in 3:
			var block := table.slice(k * ParticleBursts.PATTERN_BYTES, (k + 1) * ParticleBursts.PATTERN_BYTES)
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_MD5)
			ctx.update(block)
			check(ctx.finish().hex_encode() == String(case.md5[k]), "seed %s pattern %d: the table equals 0x544670's" % [case.seed, k])
		for sample in case.samples:
			var at: int = (int(sample.pattern) * 400 + int(sample.path)) * ParticleBursts.PATH_BYTES
			var same := true
			for i in ParticleBursts.STEPS:
				var r: Array = sample.records[i]
				var o := at + i * 12
				if table.decode_s16(o) != int(r[0]) or table.decode_s16(o + 2) != int(r[1]): same = false
				for b in 8:
					if table[o + 4 + b] != int(r[2 + b]): same = false
			check(same, "seed %s pattern %d path %d record for record" % [case.seed, int(sample.pattern), int(sample.path)])

# ------------------------------------------------------------------------------------------------ 2. bursts
func burst_checks():
	check(ParticleBursts.group_base(4, 2) == 250 and ParticleBursts.group_base(1, 1) == 0 and ParticleBursts.group_base(4, 1) == 200
		and ParticleBursts.group_base(3, 8) == 350, "0x5434a0's path groups")
	check(ParticleBursts.sheet_code(1) == "EPA0" and ParticleBursts.sheet_code(0x20) == "EPA5" and ParticleBursts.sheet_code(0) == "EPA0"
		and ParticleBursts.sheet_code(6) == "EPA1", "sheet by the lowest colour bit")
	var layer := ParticleBursts.new()
	root.add_child(layer)
	ParticleBursts.path_counter = 0
	var esmr: Array = ParticleBursts.EMITTERS.ESMR
	check(esmr.slice(0, 10) == [5, 1, 4, 2, 3, 1, 10, 2, 3, 1], "ESMR's 0x40ebd0 entry")
	var b := layer.burst(esmr.slice(0, 10), Vector2i(500, 400), 16, 0)
	check(b.count == 5 and b.base == 250 and b.pattern == 1 and b.row == 3 and b.column == -1 and b.code == "EPA0", "the ESMR burst: 5 EPA0 particles, row 3, paths 250..")
	check(b.parts.map(func(p): return p.path) == [250, 251, 252, 253, 254] and ParticleBursts.path_counter == 5, "each particle the next path of 0xb90f98")
	# 25 ms steps from the first step 50 ms after creation; respawns 3; the burst ends once every particle passed step 42.
	var t := 0
	var ends := -1
	var respawned := 0
	while t < 20000:
		t += 5
		var before: int = int(b.respawns)
		if not layer.step_burst(b, t):
			ends = t
			break
		layer.draw_burst(b)
		respawned += before - int(b.respawns)
	check(respawned == 3, "three respawns: %d" % respawned)
	check(ends > 50 + 41 * 25 and ends < 20000, "the burst ends after its steps: %d ms" % ends)
	var step0: int = int(b.parts[0].step)
	check(step0 >= ParticleBursts.STEPS, "particle 0 passed the last step")
	# smoke placement of 0x52b3e0
	layer.rng = preload("res://simulation/combat_rng.gd").new(1, 2)
	check(layer.destruction_smoke(Vector2i(10, 10), 1, 1, 0).is_empty(), "a 1 x 1 building leaves no smoke (s = 0)")
	layer.emitters.clear()
	for i in 20:
		var made := layer.destruction_smoke(Vector2i(10, 10), 3, 3, 0)
		check(made.size() == 2, "3 x 3: two emitters (s = 2 < 1d3 + 2)")
		for e in made:
			var cell := Vector2i((int(e.pixel.x) - 16) / 32, (int(e.pixel.y) - 12) / 24)
			check(cell.x >= 10 and cell.x <= 11 and cell.y >= 10 and cell.y <= 11, "smoke cell within 1d2 - 1 / 1d2 - 1: %s" % cell)
	layer.emitters.clear()
	var four := 0
	for i in 40: four = maxi(four, layer.destruction_smoke(Vector2i(10, 10), 4, 4, 0).size())
	check(four >= 3 and four <= 5, "4 x 4: 3..5 emitters (%d)" % four)
	layer.clear()
	layer.emit("ESMR", Vector2i(5, 5), 0)
	layer.step(50)
	check(layer.bursts.is_empty() and layer.emitters.size() == 1, "no burst before 50 ms")
	layer.step(51)
	check(layer.bursts.size() == 1 and layer.emitters.size() == 1 and layer.bursts[0].pixel == Vector2i(5 * 32 + 16, 5 * 24 + 12), "one burst at the emitter pixel")
	for k in 200: layer.step(61 + 10 * k)
	check(layer.emitters.is_empty() and int(layer.bursts.size()) <= 1, "P-3: the EDUM host ends after its 16 steps; period 100: no second burst")
	check(ParticleBursts.opacity(0) == 1.0 and ParticleBursts.opacity(32) == 0.0, "translucency scale")
	layer.clear()
	layer.free()

# ------------------------------------------------------------------------------------------------ 3. floating text
func text_checks():
	check(FloatingText.colour_for(2, true) == 1 and FloatingText.colour_for(2, false) == 2, "colour 2: green for a friendly object")
	check(FloatingText.colour_for(4, true) == 4 and FloatingText.colour_for(4, false) == 2 and FloatingText.colour_for(3, false) == 2, "1 / 3 / 4: red for a hostile one")
	var t := FloatingText.new()
	root.add_child(t)
	var a := t.show_text("u1", "Gained Level 2", 4, 1000, Vector2(400, 300), true, 1000)
	check(a.start == 1000 and a.end == 1000 + 1500 + 1000 and a.y0 == 260 and a.font == 41, "start now, end + 1500 + duration, 40 px up, FO_TINYMSG_LEVEL")
	check(t.show_text("u1", "x", 1, 1000, Vector2(400, 300), true, 1000, false).is_empty(), "out of view: nothing")
	var b := t.show_text("u1", "Spell Cast (Level 1)", 3, 1000, Vector2(400, 300), true, 1100)
	check(b.start == 1600 and b.y0 == 260, "second slot within 500 ms of the first: 500 ms late (600 ms apart: no chain)")
	check(t.show_text("u1", "third", 3, 1000, Vector2(400, 300), true, 1200).is_empty(), "both slots busy: dropped")
	var d := t.show_text("u3", "near", 1, 1000, Vector2(410, 310), true, 1700)
	check(d.start == 1950 and d.y0 == 290, "within 300 ms and 40 px of the last text: 250 ms later, 30 px below it")
	var c := t.show_text("u2", "far", 2, 1000, Vector2(400, 100), false, 5000)
	check(c.start == 5000 and c.font == 39, "another object, later: no chain; red")
	check(FloatingText.advance(a, 1000) and a.y == 260 and a.alpha == 1.0, "at the start")
	check(FloatingText.advance(a, 1900) and a.y == 260 - 9 and a.alpha == 1.0, "before the fade: 9 px up after 900 of 2500 ms, opaque")
	check(FloatingText.advance(a, 2250) and a.y == 260 - 12 and a.alpha == 1.0 - 2.0 / 16.0, "half way: 12 px up, fading (level 2)")
	check(FloatingText.advance(a, 3400) and a.alpha < 0.5, "fading in the last 1500 ms")
	check(not FloatingText.advance(a, 3500), "gone at the end")
	t.step(10000)
	check(t.texts.is_empty(), "all texts ended")
	t.free()

# ------------------------------------------------------------------------------------------------ 4. the strategic-map alert box
func ping_checks():
	check(MinimapPing.map_point(Vector2i(10, 20), 64) == Vector2i(20, 40) and MinimapPing.map_point(Vector2i(30, 60), 192) == Vector2i(20, 40)
		and MinimapPing.map_point(Vector2i(31, 61), 256) == Vector2i(15, 30) and MinimapPing.map_point(Vector2i(5, 6), 128) == Vector2i(5, 6), "0x4dcf70's scaling")
	var p := MinimapPing.new()
	check(p.ping(Vector2i(10, 100), 128, 0), "a ping starts")
	check(p.box == Rect2i(0, 68, 42, 60) and p.source == Vector2i(22, 0), "clipped at the left and bottom edges: %s %s" % [p.box, p.source])
	check(not p.ping(Vector2i(60, 60), 128, 0), "no new ping while one runs")
	check(p.frame() == -1, "nothing before the first update")
	p.tick(25)
	check(p.frame() == 1 and p.source_rect().position == Vector2i(64 + 22, 0), "update 1: frame 1")
	p.tick(16 * 25)
	check(p.frame() == 16, "update 16: the last frame")
	p.tick(99 * 25)
	check(p.frame() == 16 and p.active, "held until update 100")
	p.tick(100 * 25)
	check(not p.active and p.frame() == -1, "ended at update 100 (2.5 s)")
	check(p.ping(Vector2i(64, 64), 128, 3000) and p.box == Rect2i(32, 32, 64, 64), "a free ping in the middle: 64 x 64")

# ------------------------------------------------------------------------------------------------ 5. remains, rubble
func remains_checks():
	var fx := EffectsLayer.new()
	var m := FakeMain.new()
	var raw := PackedByteArray()
	raw.resize(0x14c)
	var one := raw.duplicate()
	one.encode_s16(0xf4, 1)
	var three := raw.duplicate()
	three.encode_s16(0xf4, 3)
	m.catalogue_data = {"units": {"A1": {"raw_hex": one.hex_encode()}, "A3": {"raw_hex": three.hex_encode()}, "A0": {"raw_hex": raw.hex_encode()}}}
	fx.main = m
	check([fx.remains_code("A1"), fx.remains_code("A1"), fx.remains_code("A1"), fx.remains_code("A1")] == ["EDT1", "EDT2", "EDTH", "EDT1"], "ARM +0xf4 == 1 cycles EDT1, EDT2, EDTH")
	check(fx.remains_code("A3") == "EDTH" and fx.remains_code("A0") == "" and fx.remains_code("missing") == "", "2..5: EDTH; 0: none")
	var art: Dictionary = preload("res://core/art_data.gd").data().get("effects", {})
	for code in ["EDTH", "EDT1", "EDT2"]:
		check(int(art.get(code, {}).get("interval_ms", 0)) == 10000 and int(art.get(code, {}).get("frames", 0)) == 6, "%s: six frames of 10 s (0x53c870)" % code)
	for code in ["EPA0", "EPA5"]:
		check(int(art.get(code, {}).get("rows", 0)) == 5 and int(art.get(code, {}).get("columns", 0)) == 4, "%s: the burst sheet (5 rows of 4)" % code)
	check(BuildingRubble.column_for(120000.0) == 0 and BuildingRubble.column_for(80001.0) == 0 and BuildingRubble.column_for(80000.0) == 1
		and BuildingRubble.column_for(40000.0) == 2 and BuildingRubble.column_for(100.0) == 2, "the tower's scaffold columns at 80 s / 40 s left")
	m.free()
	fx.free()

# ------------------------------------------------------------------------------------------------ P-2
## 6. P-2 (EFFECTS_RESEARCH.md "P-2"): palette 6 (the fog grey of every sheet, tests/palette6_fixtures.json from
##    tools/check_palette6.py), the order markers of 0x49c240 / 0x49d3b0, the pending job's frame, the rain and storm of
##    0x49b6d0 / 0x49b920 / 0x49a790 / 0x49b1d0, the meteor and blast bursts, the floating text lines.
func p2_checks():
	var ArtData = preload("res://core/art_data.gd")
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/palette6_fixtures.json"))
	check(int(f.mismatches) == 0 and int(f.sheets) >= 2000, "palette 6 is the grey of palette 0 in every sheet (%d sheets)" % int(f.sheets))
	var bad := 0
	for s in f.sample:
		var c0 := Color8(int(s[2][0]), int(s[2][1]), int(s[2][2]))
		var c6 := Color8(int(s[3][0]), int(s[3][1]), int(s[3][2]))
		if ArtData.palette6(c0).to_rgba32() != c6.to_rgba32(): bad += 1
	check(bad == 0 and f.sample.size() > 100, "palette6() of the 8-bit sheet colour equals palette 6 (%d sampled, %d wrong)" % [f.sample.size(), bad])
	check(ArtData.palette6(Color8(0, 0, 0, 120)).a8 == 120, "palette 6 keeps the pixel's alpha (shadow and translucency bands)")
	# Order markers (0x49c240).
	var OM = preload("res://hud/order_markers.gd")
	check([0, 1, 2, 8, 9, 15].map(func(p): return OM.triangle(p)) == [0, 1, 2, 8, 7, 1], "the marker's t: phase, 16 - phase above 8")
	check(OM.square(0) == [1, 2] and OM.square(1) == [2, 4] and OM.square(8) == [2, 4] and OM.square(7) == [3, 6]
		and OM.square(6) == [4, 8] and OM.square(4) == [5, 10] and OM.square(5) == [5, 10], "the square's sizes 2 / 4 / 6 / 8 / 10")
	check(OM.square_colour(4, 0) == Color8(0, 0xbf, 0) and OM.square_colour(4, 8) == Color8(64, 0xff, 64), "type 4: (8t, 8t + 0xbf, 8t)")
	check(OM.square_colour(6, 8) == Color8(0xff, 0, 0) and OM.square_colour(7, 0) == Color8(0, 0x7f, 0x7f), "types 6 and 7 / 0x11")
	check(OM.dots(Vector2i(0, 0), Vector2i(0, 24)) == [Vector2i(0, 0), Vector2i(0, 8), Vector2i(0, 16), Vector2i(0, 24)], "a vertical line: a dot every 8 pixels, both ends")
	check(OM.dots(Vector2i(100, 50), Vector2i(84, 50)) == [Vector2i(100, 50), Vector2i(92, 50), Vector2i(84, 50)], "a horizontal line to the left")
	# (0, 0) -> (40, 8): x major, acc += 8 * 8 per dot against 40 + 8: y steps after dots 1, 3 (64 >= 48, 64 - 48 + 64 = 80 >= 48 ...).
	var d: Array = OM.dots(Vector2i(0, 0), Vector2i(40, 8))
	check(d.size() == 6 and d[0] == Vector2i(0, 0) and d[1] == Vector2i(8, 1) and d[5].x == 40, "a shallow line: the 8 x |minor| / (|major| + 8) accumulator")
	check(OM.dots(Vector2i(5, 5), Vector2i(5, 5)).is_empty(), "start = target: no line (an in-place order)")
	var layer = OM.new()
	layer.arm(1000)
	check(layer.armed and layer.until_ms == 1500, "0x49c150: a 500 ms show")
	layer.set_held(true)
	check(not layer.armed and layer.held, "0x49c110: holding Shift / Alt ends the show")
	layer.arm(2000)
	check(not layer.armed, "0x49c150 does nothing while held")
	layer.free()
	# The pending job's picture (0x4daf0b): frame (f + 1) & 7 every 250 ms.
	var hud = preload("res://hud/game_hud.gd")
	check([0, 249, 250, 1999, 2000].map(func(ms): return hud.pending_frame(ms)) == [0, 0, 1, 7, 0], "the pending job's frame steps every 250 ms through 0..7")
	check(hud.PENDING_SOURCE == Vector2(0x188, 0x26b), "SelectionRings.bmp (0x188 + 32 f, 0x26b)")
	# Rain (0x49b920 / 0x49a790 / 0x49be40 / 0x49b1d0).
	var Rain = preload("res://visuals/rain_fx.gd")
	var rain = Rain.new()
	var view := Rect2(100, 200, 640, 480)
	var ok := true
	for i in 300:
		var drop := {}
		rain.place(drop, view)
		ok = ok and int(drop.length) >= 1 and int(drop.length) <= 40 and int(drop.limit) == int(drop.length) * 4 and int(drop.fall) == 0
		ok = ok and int(drop.x) >= 91 and int(drop.x) <= 750 and int(drop.y) >= 191 and int(drop.y) <= 690 and [1, 2, 3].has(int(drop.shift))
		var falls := 0
		while not bool(drop.landed) and falls < 20:
			var before := int(drop.fall)
			rain.fall(drop)
			ok = ok and int(drop.fall) - before >= 11 and int(drop.fall) - before <= 20
			falls += 1
		ok = ok and int(drop.length) + int(drop.fall) >= int(drop.limit)
	check(ok, "a drop: length 1..40, limit 4 L, placed in the view +- 10, falls 11..20 a step, lands at L + fall >= 4 L")
	check(Rain.rain_sound_volume(300, 120) == 18 and Rain.rain_sound_volume(300, 60) == 9 and Rain.rain_sound_volume(300, 20) == 4
		and Rain.rain_sound_volume(300, 0) == 0 and Rain.rain_sound_volume(4000, 120) == 127, "Rain.wav volume: min(drops >> 4, 127) by the effects volume")
	check(Rain.lightning_letter(79, 2, 2) == "L" and Rain.lightning_letter(100, 1, 4) == "L" and Rain.lightning_letter(100, 2, 4) == "M"
		and Rain.lightning_letter(150, 3, 1) == "L" and Rain.lightning_letter(150, 1, 3) == "M" and Rain.lightning_letter(150, 1, 5) == "H", "Lightning L / M / H by the drop count")
	var DayNightScript = preload("res://simulation/day_night.gd")
	var dn = DayNightScript.new(true)
	dn.set_rain(0x50, true)
	check(dn.raining and dn.storm and dn.drops == 30, "a storm: 30 drops to start")
	rain.lightning(dn, true)
	check(rain.flash_wait == -1, "no lightning while fog of war is on (0x49b1d0 returns on 0x47f6a0)")
	var flashes := 0
	for i in 3000:
		rain.lightning(dn, false)
		if rain.flashing: flashes += 1
	check(rain.flash_wait >= 13 and flashes > 0, "a storm flashes after 1d(150 - drops / 4) + 12 counts of three calls")
	rain.free()
	# Meteor and blast bursts (0x540bd0, 0x53fd1f, 0x529a96 / 0x529acf).
	check(ParticleBursts.sheet_code(EffectsLayer.METEOR_LANDING[1]) == "EPA1" and ParticleBursts.group_base(1, 8) == 350, "the landing burst: EPA1, paths 350..")
	check(ParticleBursts.sheet_code(EffectsLayer.METEOR_TRAIL[1]) == "EPA1" and int(EffectsLayer.METEOR_TRAIL[0]) == 15 and ParticleBursts.group_base(2, 2) == 150, "the flight's burst: 15 of EPA1, paths 150..")
	check(ParticleBursts.sheet_code(EffectsLayer.BLAST_BURSTS[1][1]) == "EPA6", "the blast's second burst: EPA6")
	var fx := EffectsLayer.new()
	check(fx.format_line(0x45f, "Mana Potion %+d", 15) == "Mana Potion +15" and fx.format_line(0x461, "Healing %d", 20) == "Healing 20", "the float lines [0x45f] / [0x461]")
	check(EffectsLayer.meteor_key({"launch_ms": 5, "from": Vector2i(1, 2), "aim": Vector2i(3, 4)}) != EffectsLayer.meteor_key({"launch_ms": 5, "from": Vector2i(1, 2), "aim": Vector2i(3, 5)}), "one key per meteor")
	fx.free()

# ------------------------------------------------------------------------------------------------ P-3
## 7. P-3 (EFFECTS_RESEARCH.md "P-3"): the emitter table 0x40ebd0 equals the executable's (tests/emitter_fixtures.json from
##    tools/emulate_emitters.py), the emitter's period rule of 0x53cc20, spawn_effect's emitter path, the record texts
##    (Spell Resisted, Critical: Stun, Petrify, Recovering), the attack / conversion entries and icons of the markers.
class FakeUnit extends Node2D:
	var unit_id := 7
	var owner_id := 0
	var cell := Vector2i(10, 10)
	var dying := false
	var removed := false
	var orders: Array = []

class FakeScene extends Node:
	var catalogue_data := {}
	var local_player := 0
	var combat = null
	var units: Dictionary = {}
	func unit_by_id(id: int): return units.get(id)

func p3_checks():
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/emitter_fixtures.json"))
	var codes: Dictionary = f.codes
	var same := 0
	var emitters := 0
	for code in codes:
		var row: Dictionary = codes[code]
		if int(row.emitter) != 1:
			check(not ParticleBursts.EMITTERS.has(code) and String(row.host) == code, "%s: not an emitter, its own host" % code)
			continue
		emitters += 1
		var want: Array = row.words.map(func(w): return int(w))
		if ParticleBursts.EMITTERS.get(code, []) == want: same += 1
		else: printerr("emitter %s: %s, executable %s" % [code, ParticleBursts.EMITTERS.get(code, []), want])
		check(String(row.host) == String(ParticleBursts.EMITTER_HOSTS.get(code, "EDUM")), "%s: host %s" % [code, row.host])
	check(emitters == 24 and same == emitters and ParticleBursts.EMITTERS.size() == emitters, "0x40ebd0: all %d emitter blocks equal the executable's (%d same)" % [emitters, same])
	check(int(codes.EMLE.words[0]) == 1 and int(codes.EMLE.words[10]) == 1, "EMLE falls through into ESVT's block (count 1, period 1)")
	# 0x53cc20: the counter starts at 1000, a burst when it reaches the period; EDUM lives 16 steps of 50 ms.
	var layer := ParticleBursts.new()
	root.add_child(layer)
	var counts := {}
	for code in ["EMLE", "ESSP", "EBLS", "EARC", "ESIV"]:
		layer.clear()
		var e := layer.emit_at(code, Vector2i(320, 240), 10, 0)
		var t := 0
		while not layer.emitters.is_empty() and t < 5000:
			t += 10
			layer.step(t)
		counts[code] = int(e.bursts)
	check(counts == {"EMLE": 16, "ESSP": 1, "EBLS": 4, "EARC": 4, "ESIV": 2}, "bursts over the 16 steps: period 1 -> 16, 100 -> 1, 5 -> 4, 4 -> 4, 10 -> 2: %s" % counts)
	layer.clear()
	var loop := layer.emit_at("EARC", Vector2i(0, 0), 0, 0, false, 2000)
	for k in 250: layer.step(10 + 10 * k)
	check(layer.emitters.is_empty() and int(loop.bursts) >= 7 and int(loop.bursts) <= 11, "a looping emitter bursts every period until its status ends: %d" % int(loop.bursts))
	layer.clear()
	layer.view_test = func(_c): return false
	var hidden := layer.emit_at("ESSP", Vector2i(0, 0), 0, 0)
	for k in 30: layer.step(60 + 50 * k)
	check(int(hidden.bursts) == 0 and layer.bursts.is_empty(), "no burst outside the view + 4 cells")
	layer.clear()
	layer.free()
	# spawn_effect resolves an emitter code through 0x40ebd0 (souls ESSP, the egg ECHE, Plague Cloud ECHC ...).
	var fx := EffectsLayer.new()
	var scene := FakeScene.new()
	fx.main = scene
	root.add_child(fx)
	var soul := fx.spawn_effect("ESSP", Vector2i(336, 252), 10, true)
	check(not soul.is_empty() and fx.bursts.emitters.size() == 1 and fx.effects.is_empty(), "ESSP: an emitter, no sheet effect")
	fx.bursts.step(51)
	check(fx.bursts.bursts.size() == 1 and String(fx.bursts.bursts[0].code) == "EPA5" and int(fx.bursts.bursts[0].row) == 0 and int(fx.bursts.bursts[0].cell_row) == 10 + 4, "the soul burst: EPA5 row 0, depth row + 4")
	fx.spawn_effect("EBLS", Vector2i(336, 252), 10, true)
	check(fx.effects.size() == 1 and String(fx.effects[0].code) == "EZ21", "EBLS: the host sheet EZ21 drawn as well")
	# The texts.
	var u := FakeUnit.new()
	u.position = Vector2(336, 252)
	scene.units[7] = u
	root.add_child(u)
	fx._present_p3({"kind": 0x10}, {"resisted": [7]})
	check(fx.texts.texts.size() == 1 and String(fx.texts.texts[0].text) == "Spell Resisted" and int(fx.texts.texts[0].colour) == 4, "0x539fb0: Spell Resisted, colour 4")
	fx.texts.clear()
	var before := fx.effects.size()
	fx._present_p3({"kind": EffectsLayer.STUN_KIND}, {"statuses": [{"id": 7, "status": {"until": 3000}}]})
	check(fx.texts.texts.size() == 1 and String(fx.texts.texts[0].text) == "Critical: Stun" and fx.effects.size() == before + 2, "0x527d10: Critical: Stun, EZ10 and EZ63")
	fx.texts.clear()
	fx.petrify_text(7)
	check(fx.texts.texts.size() == 1 and String(fx.texts.texts[0].text) == "Petrify: +100 Stone" and int(fx.texts.texts[0].colour) == 1, "0x4a9c90: Petrify +100 Stone over the shooter")
	fx.texts.clear()
	fx._on_floated({"id": 7, "line": 0x47e, "colour": 1, "ms": 1000, "owner": 1, "local_only": true})
	check(fx.texts.texts.is_empty(), "Recovering: another player's hero shows nothing")
	fx._on_floated({"id": 7, "line": 0x47e, "colour": 1, "ms": 1000, "owner": 0, "local_only": true})
	check(fx.texts.texts.size() == 1 and String(fx.texts.texts[0].text) == "Recovering from spellcasting", "Recovering for the local hero")
	fx.clear()
	fx.free()
	# The order markers (0x49d8c0 / 0x49c240).
	var OM = preload("res://hud/order_markers.gd")
	var markers = OM.new()
	markers.main = scene
	var target := FakeUnit.new()
	target.unit_id = 9
	target.position = Vector2(500, 300)
	scene.units[9] = target
	var attack: Dictionary = markers._entry({"kind": "attack", "target_kind": "unit", "target_id": 9}, Vector2i(10, 10), false)
	check(int(attack.type) == 6 and attack.target == Vector2i(500, 300), "an attack: type 6 at the target's sprite centre")
	var conv: Dictionary = markers._entry({"kind": "convert"}, Vector2i(40, 50), false)
	check(int(conv.type) == 7 and conv.target == Vector2i(40, 50), "a conversion: type 7 at the start point")
	check(markers._entry({"kind": "attack", "target_kind": "unit", "target_id": 99}, Vector2i.ZERO, false).is_empty(), "a gone target: no entry")
	check(OM.icon_source(6, 0) == Rect2(0x188, 0x1eb, 32, 32) and OM.icon_source(6, 4) == Rect2(0x188, 0x1eb + 64, 32, 32)
		and OM.icon_source(0x11, 3) == Rect2(0x1c8, 0x1eb + 32, 32, 32) and OM.icon_source(7, 0).size.x == 0, "the attack / repair icons of bitmap 0x66, rows by t")
	markers.free()
	target.free()
	u.free()
	scene.free()

# ------------------------------------------------------------------------------------------------ P-4: fog of war
class FogCombat extends RefCounted:
	var missiles: Array = []
	var fighters: Dictionary = {}
	var now_ms := 0

class FogScene extends Node:
	var catalogue_data := {}
	var local_player := 0
	var combat = FogCombat.new()
	var production = null
	var visibility
	var units: Dictionary = {}
	func unit_by_id(id: int): return units.get(id)

func p4_checks():
	var FogView = preload("res://visuals/fog_view.gd")
	var Visibility = preload("res://simulation/visibility.gd")
	# The drawing copy 0x47f110: border cells of a 3 x 3 block also look across the border.
	var v = Visibility.new(30, 30)
	v.ensure(0)
	v.visible[0][4 * 30 + 5] = 1                      # (5, 4): x % 3 == 2
	check(FogView.lit(v, 0, Vector2i(5, 4)), "a visible cell is lit")
	check(FogView.lit(v, 0, Vector2i(6, 4)), "x % 3 == 0 looks at x - 1 across the block border")
	check(not FogView.lit(v, 0, Vector2i(4, 4)), "x % 3 == 1 looks at no neighbour")
	check(not FogView.lit(v, 0, Vector2i(7, 4)) and not FogView.lit(v, 0, Vector2i(5, 3)), "no other neighbour")
	v.visible[0][4 * 30 + 5] = 0
	v.visible[0][5 * 30 + 5] = 1                      # (5, 5): a block corner
	check(FogView.lit(v, 0, Vector2i(6, 6)) and FogView.lit(v, 0, Vector2i(5, 6)) and FogView.lit(v, 0, Vector2i(6, 5)), "the 2 x 2 round a block corner")
	check(not FogView.lit(v, 0, Vector2i(4, 4)) and not FogView.lit(v, 0, Vector2i(-1, 0)), "nothing else; outside the map: not lit")
	v.fog = false
	check(not FogView.lit(v, 0, Vector2i(20, 20)), "shroud only: unexplored is not lit")
	v.explored[0][20 * 30 + 20] = 1
	check(FogView.lit(v, 0, Vector2i(20, 20)), "shroud only: explored is lit")
	check(FogView.effect_shown(v, 0, Vector2i(1, 1)), "0x53ca70: shroud only, an effect is drawn (the shroud covers it)")
	v.shroud = false
	check(FogView.lit(v, 0, Vector2i(1, 1)) and FogView.effect_shown(v, 0, Vector2i(1, 1)), "neither: everything lit")
	v.fog = true
	v.shroud = true
	check(not FogView.effect_shown(v, 0, Vector2i(1, 1)), "fog: an effect at an unlit cell is hidden")
	# Effects (kind 6): hidden while their sprite cell is not lit, shown again when it is (no memory).
	var scene := FogScene.new()
	scene.visibility = v
	var fx := EffectsLayer.new()
	fx.main = scene
	root.add_child(fx)
	var fire := fx.spawn_effect("EF01", Vector2i(10 * 32 + 16, 10 * 24 + 12), 10, false)
	check(not fire.is_empty() and not fire.node.visible, "a fire in the fog is not drawn")
	v.visible[0][10 * 30 + 10] = 1
	fx._step_effects()
	check(fire.node.visible, "the fire shows when its cell is lit")
	v.visible[0][10 * 30 + 10] = 0
	fx._step_effects()
	check(not fire.node.visible, "and hides again in the fog (0x53ca70 tests +0x76 every draw)")
	var low := fx.spawn_effect("EX02", Vector2i(10 * 32 + 16, 10 * 24 + 12), 13, true)
	v.visible[0][13 * 30 + 10] = 1
	fx._step_effects()
	check(low.node.visible and not fire.node.visible, "the sprite cell is the depth row (EX02 at row + height + 2)")
	# Particle bursts (kind 8): unseen until lit, then kept.
	var b: Dictionary = fx.bursts.burst(ParticleBursts.FIZZLE, Vector2i(20 * 32, 20 * 24), 20, 0)
	fx.bursts.step(60)
	check(not bool(b.seen) and b.draws.is_empty() and not b.node.visible, "a burst in the fog: not drawn")
	v.visible[0][20 * 30 + 20] = 1
	fx.bursts.step(90)
	check(bool(b.seen) and not b.draws.is_empty() and b.node.visible, "drawn once its cell is lit")
	v.visible[0][20 * 30 + 20] = 0
	fx.bursts.step(120)
	check(b.node.visible and not b.draws.is_empty(), "and kept in the fog (+0x131)")
	# Emitters: the host effect counts and bursts only while lit.
	fx.bursts.clear()
	var smoke: Dictionary = fx.bursts.emit_at("ESMR", Vector2i(25 * 32, 25 * 24), 25, 0)
	for k in 20: fx.bursts.step(60 + 50 * k)
	check(int(smoke.bursts) == 0, "an emitter in the fog never bursts (0x53cc20 needs +0x76)")
	var lit_smoke: Dictionary = fx.bursts.emit_at("ESMR", Vector2i(5 * 32, 5 * 24), 5, 2000)
	for k in 20: fx.bursts.step(2060 + 50 * k)
	check(int(lit_smoke.bursts) == 1, "a lit one bursts as before")
	fx.bursts.clear()
	# Missiles (kind 9): the creation mark, then drawn once lit and kept.
	var enemy := {"id": "EMA0", "owner": 1, "attacker": 3, "attacker_kind": "unit", "target_kind": "unit", "target_id": 4,
		"from": Vector2i(1, 28), "aim": Vector2i(4, 28), "launch_ms": 0, "index": 0, "steps": 3, "trail": 0, "frames": 1, "alive": true,
		"records": [[1, 28, 48, 684, 0, 0, 0], [2, 28, 80, 684, 0, 0, 0], [5, 5, 176, 132, 0, 0, 0]]}
	scene.combat.fighters[4] = {"owner": 2}
	check(not fx.missile_marked_at_creation(enemy), "enemy on enemy, both ends in the fog: not marked")
	check(fx.missile_marked_at_creation(enemy.merged({"owner": 0}, true)), "a local shooter marks it")
	scene.combat.fighters[4] = {"owner": 0}
	check(fx.missile_marked_at_creation(enemy), "a local target marks it")
	scene.combat.fighters[4] = {"owner": 2}
	check(fx.missile_marked_at_creation(enemy.merged({"meteor": true, "attacker_kind": "none"}, true)), "a sky missile (no shooter, +0x85a) is always marked")
	check(fx.missile_marked_at_creation(enemy.merged({"aim": Vector2i(5, 5)}, true)), "a visible target cell marks it (0x541b80)")
	scene.combat.missiles = [enemy]
	fx._sync_missiles()
	check(not fx.missile_nodes[0].visible, "the unmarked missile in the fog is not drawn")
	enemy.index = 2                                    # its record cell (5, 5) is visible
	fx._sync_missiles()
	check(fx.missile_nodes[0].visible, "drawn once its cell is lit")
	enemy.index = 1
	fx._sync_missiles()
	check(fx.missile_nodes[0].visible, "and kept in the fog (0x53f6b0 sets +0x131)")
	scene.combat.missiles = []
	fx._sync_missiles()
	check(fx.missile_marks.is_empty(), "the marks of gone missiles are dropped")
	fx.clear()
	fx.free()
	scene.free()
