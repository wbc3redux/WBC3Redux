extends SceneTree
## B1-7 (AI_RESEARCH.md section 18): the computer hero's spell choice against tests/ai_spell_fixtures.json
## (tools/emulate_ai_spells.py, the unmodified executable under Unicorn):
## 1. "fill": 0x502ed0 over six players per run (the 400 computer hero records of 0x42a0d0, one-school ranks, random skill
##    sets, players off / eliminated / without a hero / local): AiSpells.fill equals every computer player's table;
## 2. "choice": 0x503c60 on the synthetic worlds and the port's captured soak state: AiSpells.decide, answered with the
##    original's recorded counts, costs, effect ends and cast results (the dice drawn here from the case's generator
##    state), makes the same calls in the same order with the same arguments, returns the same and leaves the same table
##    and generator state;
## 3. the captured samples: the port's own answer recorded live by tests/capture_ai_spells.gd equals the original's
##    (the counts 0x5002e0 included, computed by the original on the reconstructed world).

const AiSpells = preload("res://simulation/ai_spells.gd")
const Rng = preload("res://simulation/combat_rng.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 30: printerr("AI spell check failed: ", label)

func _initialize():
	var fx: Dictionary = ints(JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai_spell_fixtures.json")))
	var filled := 0
	for run in fx.fill: filled += fill_run(run)
	var cases := 0
	var captured := 0
	for c in fx.choice:
		choice(c)
		cases += 1
		if c.has("port") and c.port != null:
			captured += 1
			port_answer(c)
	if failures > 0:
		printerr("AI spell checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI spell checks passed: %d checks over %d fill tables, %d choice cases (%d captured soak samples)" % [checks, filled, cases, captured])
	quit(0)

## JSON numbers as ints (every fixture value is an integer), so arrays and tables compare by value.
static func ints(v):
	if v is float: return int(v)
	if v is Array: return v.map(func(x): return ints(x))
	if v is Dictionary:
		var d := {}
		for k in v: d[k] = ints(v[k])
		return d
	return v

func fill_run(run: Dictionary) -> int:
	var out: Dictionary = run.out
	check(not out.has("error"), "fill ran: %s" % out.get("error", ""))
	check(int(out.filled) == 1, "0x7486fe set")
	var n := 0
	for p in run.players.size():
		var spec: Dictionary = run.players[p]
		var table: Dictionary = out.tables[p]
		var skipped: bool = not bool(spec.get("on", true)) or bool(spec.get("eliminated", false)) or not bool(spec.get("hero", true))
		if skipped:
			check(int(table.threshold) == -4370, "P%d skipped: the table keeps its residue (%s)" % [p, table])
			continue
		if not bool(spec.get("computer", true)):
			check(int(table.enabled) == 0, "P%d local branch: never enabled" % p)
			continue
		var port := AiSpells.to_rows(AiSpells.fill(spec.skills, 123456))
		check(port == table, "P%d fill %s: port %s original %s" % [p, spec.skills, port, table])
		n += 1
	return n

## Replays the original's recorded answers; records the port's calls.
class FixtureEnv:
	var spec: Dictionary
	var calls: Array
	var at := 0
	var rng
	var errors: Array = []
	func _init(case_spec: Dictionary, recorded: Array):
		spec = case_spec
		calls = recorded
		rng = Rng.new(int(spec.rng[0]), int(spec.rng[1]))
	func _next(kind: String, args: Array):
		if at >= calls.size():
			errors.append("extra %s %s" % [kind, args])
			return null
		var c: Array = calls[at]
		at += 1
		if String(c[0]) != kind or c.slice(1, 1 + args.size()) != args:
			errors.append("call %d: port %s %s, original %s" % [at - 1, kind, args, c])
			return null
		return c
	func local() -> bool:
		return int(spec.get("local", 7)) == int(spec.hero.owner)
	func morphing() -> bool:
		return bool(spec.hero.get("morph", false))
	func deleted() -> bool:
		return bool(spec.hero.get("deleted", false))
	func now() -> int:
		return int(spec.now)
	func count(radius: int, relation: int, kinds: int, hp: int, extra: int, stop: int) -> int:
		var c = _next("count", [radius, relation, kinds, hp, extra, stop])
		return int(c[7]) if c != null else 0
	func hp() -> int:
		return int(spec.hero.hp)
	func max_hp() -> int:
		return int(spec.hero.max_hp)
	func pool() -> int:
		return int(spec.hero.pool)
	func max_mana() -> int:
		return int(spec.hero.max_mana)
	func potions() -> int:
		return int(spec.hero.potions)
	func mana_potions() -> int:
		return int(spec.hero.mana_potions)
	func drink():
		_next("drink", [])
	func drink_mana():
		_next("drink_mana", [])
	func cost(spell: int) -> int:
		var c = _next("cost", [spell])
		return int(c[2]) if c != null else 0
	func effect_end(spell: int):
		var c = _next("effect", [spell])
		return null if c == null or c[2] == null else int(c[2])
	func cast(spell: int) -> bool:
		var c = _next("cast", [spell])
		return c != null and int(c[2]) != 0
	func command() -> Array:
		return spec.get("command", [0, 40])
	func roll(sides: int, bonus: int) -> int:
		var c = _next("roll", [sides, AiSpells.Sign.s16(bonus)])
		var v: int = rng.roll(1, sides, bonus)
		if c != null and AiSpells.Sign.s16(v) != int(c[3]): errors.append("roll(1, %d, %d): port %d original %d" % [sides, bonus, v, int(c[3])])
		return v

func choice(c: Dictionary):
	var spec: Dictionary = c.spec
	var out: Dictionary = c.out
	var label := String(spec.get("case", c.get("source", "captured")))
	check(not out.has("error"), "%s ran: %s" % [label, out.get("error", "")])
	var t := AiSpells.from_rows(spec.table)
	var env := FixtureEnv.new(spec, out.calls)
	var result: bool = AiSpells.decide(t, env)
	if env.at < out.calls.size(): env.errors.append("missing calls from %d: %s" % [env.at, out.calls.slice(env.at)])
	check(env.errors.is_empty(), "%s calls: %s" % [label, env.errors])
	check(result == (int(out.result) != 0), "%s result: port %s original %s" % [label, result, out.result])
	check(AiSpells.to_rows(t) == out.table, "%s table: port %s original %s" % [label, AiSpells.to_rows(t), out.table])
	check(env.rng.state() == out.rng.map(func(v): return int(v)), "%s generator: port %s original %s" % [label, env.rng.state(), out.rng])

## 0x5002e0 returns once its total reaches the stop value, so a total past it depends on the walk order (grid rows and their
## lists in the original, fighter ids in the port); every caller compares it with values up to the stop only. A count at
## or past its stop is compared as the stop.
static func canonical(calls: Array) -> Array:
	return calls.map(func(c): return c.slice(0, 7) + [mini(int(c[7]), int(c[6]))] if String(c[0]) == "count" else c)

## The port's live answer on the captured state (calls with its own counts) against the original's.
func port_answer(c: Dictionary):
	var port: Dictionary = c.port
	var out: Dictionary = c.out
	var label := "captured %s" % c.get("source", "")
	check(canonical(port.calls) == canonical(out.calls), "%s calls: port %s original %s" % [label, port.calls, out.calls])
	check(bool(port.result) == (int(out.result) != 0), "%s result" % label)
	check(port.table == out.table, "%s table: port %s original %s" % [label, port.table, out.table])
	check(port.rng.map(func(v): return int(v)) == out.rng.map(func(v): return int(v)), "%s generator" % label)
