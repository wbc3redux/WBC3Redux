extends Node2D
## P-1 (EFFECTS_RESEARCH.md "P-1"): the original's particle bursts. Presentation only: it never touches the simulation's
## state or its random generator (the path table and the smoke placement draw from this layer's own generator).
## * Path table 0x544670 -> 0x544b50 (Emulated: tests/particle_path_fixtures.json, tools/emulate_particle_paths.py):
##   3 patterns (speed 1..3) x 8 groups x 50 paths of 42 steps, 12 bytes per step: x, y (s16, 666 = the path ended),
##   then 8 bytes the draw picks translucency and frame from. The original fills it once with the match generator; the
##   rebuild fills it from PATH_SEED (Deliberate: the presentation must not draw from the match generator).
## * Burst 0x58c0d0 -> init 0x5434a0 (Read): `count` particles (at most 32; the particle detail option 0x70d7d4 and the
##   load counter 0xa38c94 can halve it: not ported, full detail), sheet EPA0..EPA6 by the lowest colour bit, sheet row
##   `row`, path group by (group_a, group_b), each particle taking the next path of the global counter 0xb90f98 (mod 50).
## * Step 0x544590 (Read, disassembly): every 25 ms every particle advances one step (two without a sheet row); the burst
##   ends when every particle reached step 42.
## * Draw 0x544330 (Read): a particle at a 666 record ends, or restarts on a new path while `respawns` remain; else it is
##   drawn at the burst pixel + (x, y), column by `frame_mode` (6..9: 0..3 fixed, 10: particle index % 4, 1..5: a byte
##   of the record), translucency by `alpha_mode` (1..3: a byte of the record, 4: two summed). Depth 0x5439c0: (cell row
##   + 1) * 24 + particle 0's step.
## * Emitters (0x44ead0 / 0x44e8f0 -> 0x40ebd0 table -> an effect, 0x53c870 / 0x53cc20, Read; P-3): the effect (EDUM, the
##   invisible dummy: 16 frames of 50 ms, or the host sheet 0x40ebd0 names, EZ21 for EBLS) counts +0x16e up at each step
##   (from 1000) and bursts 0x58c0d0 when it reaches the entry's period, then restarts at 0: steps 1, 1 + period, ... while
##   the effect lives (a once effect ends at its last frame; a looping one lives with its status). Each burst at the effect
##   pixel + (dx, dy), only while the effect's cell is within the view + 4 cells, its depth row the effect's cell row +
##   the entry's depth dy when either depth offset is set (0x535150). P-1 had EDUM burst once (true for periods >= 16 only).
const ArtData = preload("res://core/art_data.gd")
const MapData = preload("res://core/map_data.gd")
const CombatRng = preload("res://simulation/combat_rng.gd")

const STEPS := 42
const PATH_BYTES := 504
const PATTERN_BYTES := 400 * PATH_BYTES
const ENDED := 0x29a
const STEP_MS := 25                      # 0x5445a7: + 0x19
const EMIT_DELAY_MS := 50                # 0x53c870: the effect's first step (+0x140 = now + 50)
const PATH_SEED := [0x1badb002, 0x2468ace0]
## 0x40ebd0 (P-3: Emulated, tests/emitter_fixtures.json, tools/emulate_emitters.py; all 24 codes it knows): emitter code ->
## [count, colour bits, group a, group b, row, pattern, frame mode, alpha mode, respawns, size, period, dx, dy, depth dx,
## depth dy]. ESMR: the building smoke 0x52b3e0 places over a destroyed building. EMLE falls through into ESVT's block in
## the original (no break after its stores at 0x40efe4): the executable's values are kept. EPOC also sets the light byte
## (+0x16a = 1, 3, 0, 0: 0x44edb0, the Lighting Effects light, not ported).
const EMITTERS := {
	"EARC": [7, 64, 4, 1, 3, 1, 8, 2, 0, 1, 4, 0, -30, 0, 2], "EBLS": [7, 32, 1, 2, 4, 1, 5, 2, 0, 1, 5, 0, -40, 0, 2],
	"ECHC": [9, 2, 4, 1, 1, 1, 4, 2, 0, 1, 20, 0, 0, 0, 2], "ECHE": [9, 2, 4, 1, 0, 1, 1, 4, 0, 1, 20, 0, 0, 0, 7],
	"ECHW": [9, 2, 4, 2, 1, 1, 4, 2, 0, 1, 20, 0, 0, 0, 7], "ECOM": [7, 64, 1, 1, 3, 0, 8, 2, 0, 1, 4, 0, -30, 0, 2],
	"EDVC": [12, 32, 4, 1, 3, 0, 5, 2, 0, 1, 20, 0, 0, 0, 2], "EIAR": [6, 16, 1, 1, 1, 0, 4, 2, 0, 0, 4, 0, -36, 0, 1],
	"EIFM": [4, 16, 4, 1, 0, 1, 1, 2, 0, 1, 5, 0, -35, 0, 2], "EILE": [6, 2, 2, 1, 0, 1, 1, 2, 0, 1, 100, 0, 0, 0, 4],
	"EILU": [6, 16, 2, 1, 0, 1, 1, 2, 0, 1, 100, 0, 0, 0, 4], "EIMM": [7, 1, 1, 2, 2, 1, 5, 2, 0, 1, 5, 0, -40, 0, 2],
	"EISP": [12, 16, 2, 1, 4, 1, 10, 2, 0, 1, 100, 0, 0, 0, 4], "EIST": [12, 16, 2, 2, 1, 2, 4, 1, 4, 2, 20, 0, -5, 0, 6],
	"EMIF": [6, 16, 2, 1, 4, 0, 10, 2, 0, 1, 5, 0, 0, 0, -2], "EMLE": [1, 4, 4, 1, 1, 0, 6, 1, 0, 0, 1, 0, 0, 0, 0],
	"EPGA": [7, 4, 2, 4, 0, 0, 1, 2, 0, 1, 5, 0, -40, 0, 2], "EPOC": [9, 4, 4, 1, 1, 1, 4, 2, 0, 1, 20, 0, 0, 0, 2],
	"ERUC": [5, 1, 2, 2, 4, 1, 10, 1, 0, 1, 50, 0, 0, 0, 2], "ESIV": [7, 64, 4, 1, 3, 0, 6, 2, 0, 1, 10, 0, -30, 0, 2],
	"ESMR": [5, 1, 4, 2, 3, 1, 10, 2, 3, 1, 100, 0, 0, 0, 0], "ESMX": [5, 1, 4, 2, 3, 1, 10, 2, 3, 1, 100, 0, 0, 0, 4],
	"ESSP": [4, 32, 4, 2, 0, 1, 1, 1, 0, 1, 100, 0, 0, 0, 4], "ESVT": [1, 4, 4, 1, 1, 0, 6, 1, 0, 0, 1, 0, 0, 0, 0],
}
## 0x40ebd0's host effect when it is not EDUM (a drawn sheet that also bursts).
const EMITTER_HOSTS := {"EBLS": "EZ21"}
const DUMMY_FRAMES := 16                 # 0x53c870: +0x13e = 16 for EDUM (+0x14a)
const DUMMY_INTERVAL_MS := 50
## 0x5777a0 (Read): the fizzle of a failed cast, straight at the caster's sprite top (0x58c0d0 without an emitter).
const FIZZLE := [12, 0x20, 4, 1, 2, 0, 1, 4, 4, 1]
## 0x5210b0 (Read, wbc3_decomp.c 196435): a unit eaten (Eating.wav) bursts at the victim's sprite.
const EATING := [11, 2, 1, 1, 4, 1, 10, 1, 0, 1]

static var paths := PackedByteArray()
static var path_counter := 0              # 0xb90f98

var bursts: Array = []                    # {pixel, cell_row, count, sheet, row, pattern, base, frame_mode, alpha_mode, respawns, next, parts, node}
var emitters: Array = []                  # {code, pixel, cell_row, due}
var rng                                   # this layer's own generator (smoke placement)

class BurstNode extends Node2D:
	var burst: Dictionary
	var tex: Texture2D
	func _draw():
		if tex == null: return
		for d in burst.get("draws", []):
			draw_texture_rect_region(tex, Rect2(d[0], d[1].size), d[1], Color(1, 1, 1, d[2]))

func _ready():
	z_as_relative = true
	if rng == null: rng = CombatRng.new(0x5eb0e4, 0x544670)

# --------------------------------------------------------------------------------------------- the path table
static func _tdiv(a: int, b: int) -> int:
	return a / b                           # GDScript truncates like the original's idiv

## 0x544b50's per-direction steps: [x accumulator step, x sign, y accumulator step (-1: unchanged), y sign].
static func _steps(d: int, p: int) -> Array:
	var t := (p * 1400) / 20
	var table := [[0, 0, p * 100, -1], [(p * 500) / 20, 1, p * 95, -1], [(p * 1000) / 20, 1, p * 85, -1], [t, 1, t, -1],
		[(p * 1700) / 20, 1, (p * 1000) / 20, -1], [(p * 1900) / 20, 1, (p * 500) / 20, -1], [(p * 2000) / 20, 1, -1, 0],
		[(p * 1900) / 20, 1, p * 25, 1], [(p * 1700) / 20, 1, (p * 1000) / 20, 1], [t, 1, t, 1], [(p * 1000) / 20, 1, p * 85, 1],
		[(p * 500) / 20, 1, p * 95, 1], [0, 0, p * 100, 1]]
	if d >= 0: return table[d] if d <= 12 else [0, 0, -1, 0]
	if d < -11: return [0, 0, -1, 0]
	var s: Array = table[-d]
	return [s[0], -1, s[2], s[3]]

const ADJUST_DOWN := {0: -7, -11: 1, -10: 1, 10: 1, 11: 1, -6: -1, 6: -1, -5: -2, 5: -2, -4: -3, 4: -3, -3: -4, 3: -4,
	-2: -5, 2: -5, -1: -6, 1: -6}
const ADJUST_UP := {12: -7, -11: -6, 11: -6, -10: -5, 10: -5, -9: -4, 9: -4, -8: -3, 8: -3, -7: -2, 7: -2, -6: -1, 6: -1,
	-2: 1, -1: 1, 1: 1, 2: 1}

static func _s16(v: int) -> int:
	return ((v + 0x8000) & 0xffff) - 0x8000

## 0x544b50(first, last, length, turn, direction, speed, out, bounce): one path into `out` at `at`.
static func _path(out: PackedByteArray, at: int, first: int, last: int, length: int, turn: int, direction: int, speed: int,
		bounce: bool, r, levels: Dictionary):
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	xs.resize(STEPS)
	ys.resize(STEPS)
	var up := turn < 0
	if up: turn = -turn
	var d := direction
	var level: int = int(levels.get(d, 0)) if bounce else 0
	var ax := 0
	var ay := 0
	var since := 0
	for i in range(1, STEPS):
		if i < first: continue
		if last < i:
			xs[i] = ENDED
			ys[i] = ENDED
			continue
		var s: Array = _steps(d, speed)
		ax += int(s[0])
		if int(s[2]) >= 0: ay += int(s[2])
		xs[i] = xs[i - 1]
		ys[i] = ys[i - 1]
		if ax > 100:
			var n := (ax - 1) / 100
			ax -= n * 100
			xs[i] = _s16(xs[i] + int(s[1]) * n)
		if ay > 100:
			var n := (ay - 1) / 100
			ay -= n * 100
			ys[i] = _s16(ys[i] + int(s[3]) * n)
		if xs[i] < -0xef or xs[i] > 0xef or ys[i] < -0xef or ys[i] > 0xef:
			xs[i] = ENDED
			ys[i] = ENDED
			last = i
		var threshold := turn
		if turn < length: threshold += int((ADJUST_UP if up else ADJUST_DOWN).get(d, 0))
		threshold = maxi(threshold, 2)
		if (i + 1) % threshold == 0 and r.roll(1, 100) < 100:
			if up:
				if d == 12: d = -11 if r.roll(1, 100) > 49 else 11
				elif d >= 1 and d <= 11: d -= 1
				elif d < 0 and d > -12: d += 1
			else:
				if d == 0: d = -1 if r.roll(1, 100) > 49 else 1
				elif d >= 1 and d <= 11: d += 1
				elif d < 0 and d > -12:
					d -= 1
					if d == -12: d = 12
		if not bounce or ys[i] <= level or since < 5 or absi(d) < 7:
			since += 1
		else:
			d = 12 - d if d > 0 else (-12 - d if d < 0 else 0)     # 0x5453f6: the mirror table
			since = 0
			level += level / 2
	for i in STEPS:
		out.encode_s16(at + i * 12, xs[i])
		out.encode_s16(at + i * 12 + 2, ys[i])
	var rising := true
	for i in STEPS:
		if i < first: continue
		if last < i: break
		var b := at + i * 12
		out[b + 4] = ((12 * (i - first)) / length) & 0xff
		var v := 12 - (last - i) / 2
		out[b + 5] = (v & 0xff) if v >= 1 else 0
		v = 2 * first + 12 - 2 * i
		out[b + 6] = (v & 0xff) if v >= 1 else 0
		var u := (i / 2) % 4
		out[b + 7] = u
		out[b + 8] = 3 - u
		v = mini((4 * i - 4 * first) / length, 3)
		out[b + 9] = v & 0xff
		out[b + 10] = (3 - v) & 0xff
		if i == first: out[b + 11] = 0
		elif rising:
			out[b + 11] = (out[b - 1] + 1) & 0xff
			if out[b + 11] == 3: rising = false
		else:
			out[b + 11] = (out[b - 1] - 1) & 0xff
			if out[b + 11] == 0: rising = true

## 0x544670: the whole table from a generator seeded with (first, second). `levels`: the bounce levels 0x611ff0 by
## start direction (-12..12), from the executable's data (tests/particle_path_fixtures.json "bounce_levels").
static func build_paths(first: int, second: int, levels: Dictionary = BOUNCE_LEVELS) -> PackedByteArray:
	var r = CombatRng.new(first, second)
	var out := PackedByteArray()
	out.resize(3 * PATTERN_BYTES)
	var divisor := 3
	var at := 0
	for speed in [1, 2, 3]:
		for group in 8:
			for k in 50:
				var a: int = r.roll(1, 4, 0)
				var b: int = r.roll(1, 0x15, 0xd if group == 6 else 0x14)
				var length := b - a + 1
				var turn: int
				if group == 6: turn = maxi(r.roll(1, 4, 0), 3)
				elif group == 1 or group == 3: turn = b - a + 3
				else:
					var t: int = r.roll(1, length / (divisor + (1 if group == 7 else 0)), -1)
					if group == 4 or group == 5:
						turn = -t
						if t != 3 and -4 < turn: turn = -3
					else: turn = maxi(t, 3)
				var direction: int = r.roll(1, 0x18, -12) if group == 0 or group == 1 or group == 4 else r.roll(1, 0xb, -6)
				_path(out, at, a, b, length, turn, direction, speed, group == 7, r, levels)
				at += PATH_BYTES
		divisor += 2
	return out

## 0x611ff0[-12..12] (read from the executable by tools/emulate_particle_paths.py; 0x544670 starts the bouncing group
## with directions -5..5 only).
const BOUNCE_LEVELS := {-12: 240, -11: 8, -10: 5, -9: 4, -8: 3, -7: 2, -6: 0, -5: -2, -4: -3, -3: -4, -2: -5, -1: -8,
	0: -10, 1: -8, 2: -5, 3: -4, 4: -3, 5: -2, 6: 0, 7: 2, 8: 3, 9: 4, 10: 5, 11: 8, 12: 10}

static func table() -> PackedByteArray:
	if paths.is_empty(): paths = build_paths(PATH_SEED[0], PATH_SEED[1])
	return paths

# --------------------------------------------------------------------------------------------- bursts
## 0x5434a0's path group base +0x1da from (group a, group b).
static func group_base(a: int, b: int) -> int:
	if a == 1 and b == 1: return 0
	if a == 2 and b == 1: return 50
	if a == 1 and b == 2: return 100
	if a == 2 and b == 2: return 150
	if a == 4 and b == 1: return 200
	if a == 4 and b == 2: return 250
	if b == 4: return 300
	if b == 8: return 350
	return 0

static func sheet_code(bits: int) -> String:
	for i in 7:
		if bits & (1 << i): return "EPA%d" % i
	return "EPA0"

## 0x58c0d0 + 0x5434a0: a burst at `pixel` (world pixels), depth cell row `cell_row`. `p`: [count, colour bits, group a,
## group b, row, pattern, frame mode, alpha mode, respawns, size].
func burst(p: Array, pixel: Vector2i, cell_row: int, now: int) -> Dictionary:
	var count := mini(int(p[0]), 32)
	if count < 1: return {}
	var code := sheet_code(int(p[1]))
	var s: Dictionary = ArtData.data().get("effects", {}).get(code, {})
	var b := {"pixel": pixel, "cell_row": cell_row, "count": count, "sheet": s, "row": int(p[4]), "pattern": clampi(int(p[5]), 0, 2),
		"base": group_base(int(p[2]), int(p[3])), "frame_mode": int(p[6]), "alpha_mode": int(p[7]), "respawns": int(p[8]),
		"next": now + EMIT_DELAY_MS, "parts": [], "column": 0, "code": code, "draws": [], "seen": false}
	var mode: int = b.frame_mode
	if mode >= 6 and mode <= 9: b.column = mode - 6
	elif mode == 10: b.column = -1
	if mode >= 6: b.frame_mode = 0
	for i in count:
		b.parts.append({"step": 0, "path": int(b.base) + path_counter, "done": false})
		path_counter = (path_counter + 1) % 50
	if not s.is_empty():
		var node := BurstNode.new()
		node.burst = b
		node.tex = ArtData.texture(s.texture)
		if String(s.get("godot_blend", "")) == "add": node.material = preload("res://visuals/effects_layer.gd").additive_material()
		add_child(node)
		b["node"] = node
	bursts.append(b)
	return b

## The table record of a particle: [x, y, bytes 4..11]. A step past the path reads on into the next path, as the original's
## flat index does (at the table's end: an ended record).
func record(b: Dictionary, part: Dictionary) -> Array:
	var t := table()
	var at: int = ((int(b.pattern) * 400 + int(part.path)) * STEPS + int(part.step)) * 12
	if at < 0 or at + 12 > t.size(): return [ENDED, ENDED, 0, 0, 0, 0, 0, 0, 0, 0]
	var out := [t.decode_s16(at), t.decode_s16(at + 2)]
	for k in range(4, 12): out.append(t[at + k])
	return out

## 0x486d50 stores the level in the low word of 0xa38b9c (0x486d70, the map emitters' 0..15 alpha, stores twice its value
## in the high word): read here as 32 steps, 0 opaque (Provisional: 0x487f20's use of the low word is not traced).
static func opacity(translucency: int) -> float:
	return 1.0 - clampi(translucency, 0, 32) / 32.0

## 0x544590: every 25 ms one step for every particle; false when the burst ended.
func step_burst(b: Dictionary, now: int) -> bool:
	if now < int(b.next): return true
	b.next = now + STEP_MS
	var alive := false
	for part in b.parts:
		part.step = int(part.step) + (2 if int(b.row) == -1 else 1)
		if int(part.step) < STEPS: alive = true
	return alive

## 0x544330: the draw list of a burst (and the respawns it performs).
func draw_burst(b: Dictionary):
	# P-4 (fog_view.gd, Read): a kind 8 burst starts unseen under fog / shroud (0x534c40 +0x76 = 0); the view draw 0x547530
	# calls 0x544330 only once a 0x547c00 pass found its cell lit (+0x131, kept from then on, also in the fog). Until then
	# nothing is drawn and nothing respawns.
	if not bool(b.get("seen", true)):
		b.seen = lit_test.is_null() or bool(lit_test.call(Vector2i(int(b.pixel.x) >> 5, int(b.cell_row))))
		if not b.seen:
			b.draws = []
			if b.has("node") and is_instance_valid(b.node): b.node.visible = false
			return
	var draws: Array = []
	var s: Dictionary = b.sheet
	for i in b.parts.size():
		var part: Dictionary = b.parts[i]
		if part.done: continue
		var r := record(b, part)
		if int(r[0]) == ENDED:
			part.done = true
			if int(b.respawns) > 0:
				part.done = false
				part.step = 0
				part.path = int(b.base) + path_counter
				path_counter = (path_counter + 1) % 50
				b.respawns = int(b.respawns) - 1
			continue
		var translucency := 0                    # r[k] is record byte k + 2 (r[2] = byte 4)
		match int(b.alpha_mode):
			1: translucency = int(r[3])
			2: translucency = int(r[2])
			3: translucency = int(r[4])
			4: translucency = int(r[4]) + int(r[3])
		var column: int = int(b.column)
		match int(b.frame_mode):
			1: column = int(r[5])
			2: column = int(r[7])
			3: column = int(r[6])
			4: column = int(r[8])
			5: column = int(r[9])
		if column < 0: column = i % 4
		if s.is_empty(): continue
		var size: Array = s.frame_size
		column = clampi(column, 0, int(s.columns) - 1)
		var row := clampi(int(b.row), 0, int(s.rows) - 1)
		var source := Rect2(column * int(size[0]), row * int(size[1]), int(size[0]), int(size[1]))
		var at := Vector2(int(b.pixel.x) + int(r[0]), int(b.pixel.y) + int(r[1])) - Vector2(int(s.pivot[0]), int(s.pivot[1]))
		draws.append([at, source, opacity(translucency)])
	b.draws = draws
	if b.has("node") and is_instance_valid(b.node):
		b.node.visible = true
		var first_step: int = int(b.parts[0].step) if not b.parts.is_empty() else 0
		b.node.z_index = MapData.depth((int(b.cell_row) + 1) * 24 + first_step)
		b.node.queue_redraw()

# --------------------------------------------------------------------------------------------- emitters
## 0x44ead0(cell x, cell y, code, once, ...): an emitter effect at the cell's pixel.
func emit(code: String, cell: Vector2i, now: int) -> Dictionary:
	return emit_at(code, Vector2i(cell.x * 32 + 16, cell.y * 24 + 12), cell.y, now)

## P-3: an emitter effect at `pixel` (0x44ead0 / 0x44e8f0 with an emitter code). `once`: the effect's own flag (ends at
## its last frame); `until` > 0: a looping status effect ends then; `follow`: a unit whose position the effect takes.
## `frames` / `interval`: the host effect's (EDUM: 16 x 50 ms).
func emit_at(code: String, pixel: Vector2i, cell_row: int, now: int, once: bool = true, until: int = 0, follow = null,
		frames: int = DUMMY_FRAMES, interval: int = DUMMY_INTERVAL_MS) -> Dictionary:
	if not EMITTERS.has(code): return {}
	var e := {"code": code, "pixel": pixel, "cell_row": cell_row, "due": now + EMIT_DELAY_MS, "counter": 1000, "frame": 0,
		"frames": maxi(1, frames), "interval": maxi(1, interval), "once": once, "until": until, "follow": follow, "bursts": 0,
		"alive": true, "node": null}
	emitters.append(e)
	return e

## 0x53cc20's emitter part for one step of `e`: true while the effect lives.
func step_emitter(e: Dictionary, now: int) -> bool:
	if not bool(e.get("alive", true)): return false
	if int(e.until) > 0 and now > int(e.until): return false
	var u = e.follow
	if u != null:
		if not is_instance_valid(u) or bool(u.get("dying")) or bool(u.get("removed")): return false
		e.pixel = Vector2i(int(u.position.x), int(u.position.y))
		e.cell_row = int(u.cell.y)
	if now <= int(e.due): return true
	var p: Array = EMITTERS[e.code]
	# P-4 (Read, 0x53cc20): the counter only runs while the host effect's +0x76 is set (its cell lit, fog_view.gd), so a
	# host in the fog never bursts.
	var host_lit := lit_test.is_null() or bool(lit_test.call(Vector2i(int(e.pixel.x) >> 5, int(e.cell_row))))
	if host_lit: e.counter = int(e.counter) + 1
	if host_lit and int(e.counter) >= int(p[10]):
		e.counter = 0
		var cell := Vector2i(int(e.pixel.x) / 32, int(e.pixel.y) / 24)
		if view_test.is_null() or bool(view_test.call(cell)):
			var row: int = int(e.cell_row) + (int(p[14]) if int(p[13]) != 0 or int(p[14]) != 0 else 0)
			burst(p.slice(0, 10), e.pixel + Vector2i(int(p[11]), int(p[12])), row, now)
			e.bursts = int(e.bursts) + 1
	e.due = now + int(e.interval)
	e.frame = int(e.frame) + 1
	if bool(e.once): return int(e.frame) < int(e.frames)
	e.frame = int(e.frame) % int(e.frames)
	return true

## The cell test of 0x53cc20's burst (view + 4 cells); unset: always.
var view_test: Callable
## P-4: 0x47f560 with the drawing copy for the local player (fog_view.gd lit): a sprite's +0x76; unset: always lit.
var lit_test: Callable

## 0x52b3e0 (Read, wbc3_decomp.c 202190-202210): the smoke over an ordinary destroyed building. s = min(width, height) - 1;
## n = 1d3 + 2, and when s >= n another 1d3 + 2, else s; each emitter at the sprite cell + (1ds - s / 2, 1ds - 1). The
## original rolls the match generator here; the rebuild rolls this layer's own (Deliberate: presentation only).
func destruction_smoke(cell: Vector2i, width: int, height: int, now: int) -> Array:
	var s := mini(width - 1, height - 1)
	var n: int = rng.roll(1, 3, 2)
	n = s if s < n else rng.roll(1, 3, 2)
	var out: Array = []
	for i in maxi(n, 0):
		var dx: int = rng.roll(1, s, -(s / 2))
		var dy: int = rng.roll(1, s, -1)
		out.append(emit("ESMR", cell + Vector2i(dx, dy), now))
	return out

func step(now: int):
	var keep: Array = []
	for e in emitters:
		if step_emitter(e, now): keep.append(e)
	emitters = keep
	var alive: Array = []
	for b in bursts:
		if step_burst(b, now):
			draw_burst(b)
			alive.append(b)
		elif b.has("node") and is_instance_valid(b.node):
			b.node.queue_free()
	bursts = alive

func clear():
	for b in bursts:
		if b.has("node") and is_instance_valid(b.node): b.node.queue_free()
	bursts.clear()
	emitters.clear()
