extends RefCounted
## Construction and production tables of every race, read from assets/catalogue.json (tools/catalogue_data.py): ARM/BUI
## records plus the Building.cfg PRODUCTION / CONSTRUCTION / DEPENDENCIES / RULES rows (milestone 11a, RACES_RESEARCH.md).
## Milestone 7's Knights tables (assets/production.json) are no longer read; tests/test_race_rules.gd checks that the
## definitions built here equal them field for field.
## Cost order is gold, metal, crystal, stone (record order). Times are whole seconds; the original stores job deadlines
## as seconds * 1000 on the game clock (0x52e1d0, 0x4a6f80).
##
## Lookups follow the original keys: PRODUCTION rows by (player race, building) (0x587970), CONSTRUCTION rows by (race,
## row digit) (0x5878b0 / 0x587910), dependencies by (id, race) (0x40b660 / 0x40aaa0), [RULES] by (id, race) (0x587aa0,
## first matching row). The cost function is a port of 0x40b6b0 (all branches; Emulated for every race's production and
## construction items and the research-gated cases in tests/races_fixtures.json).
const Assets = preload("res://core/asset_store.gd")
static var CATALOGUE_PATH: String = Assets.path("catalogue.json")
## 0x4391c0 (a code switch, not data): emulated price and time of every research id named in Building.cfg, written by
## tools/emulate_races.py from the same run as tests/races_fixtures.json.
const RESEARCH_PATH := "res://simulation/research_prices.json"
## Match option DAT_0070ae16 (BuildLevel, default 5): 0x40c740 clamps it to 0..5; a slot digit must be below it (0x40c990).
const KEEP_LEVEL_OPTION := 5
## 0x5325d0 maps the highest Keep (4th ID character - 0x2f) through the table at 0x6115d4.
const KEEP_COMMAND_TABLE = [2, 5, 10, 15, 20, 30]
const RACE_LETTERS := "HDUBMOEWKFAVPLRG"     # 0x5873a0: race letter -> index; unknown letters -> 0
const KNIGHT := 0
const DWARF := 1
const DARK_DWARF := 10
const SWARM := 14
const LANES := ["gold", "metal", "crystal", "stone"]
## 0x40b6b0: units priced by code (lane, amount) for every race except the Dark Dwarves (race 10).
const FLAT_PRICES := {"AEAX": [2, 100], "AUJX": [1, 70], "AUKX": [2, 60], "AULX": [1, 250], "AUAX": [1, 350], "AUMX": [2, 150], "AUXX": [2, 120]}
const DAEMON_UNITS := ["AADE", "AAIM", "AVBX", "AVIX", "AVCX", "AVDX"]
const SWARM_UNITS := ["ARBX", "ARMX", "ARIX", "ARCX", "ARGX"]
const DRAGONS := ["AADR", "AADU", "AADW", "AADB", "AADC", "AADG"]      # 0x40c990 "no dragons" option
const FLIER_BUILDINGS := ["BAV0", "BAV1", "BAV2", "BAN0", "BAN1", "BAN2", "BAE0", "BAE1", "BAE2"]
## 0x40b6b0 research branch: hero-skill price reductions of these research ids (0x556b50 skill numbers).
const RESEARCH_SKILLS := {"RARB": 0x3e, "RCIE": 0x3f, "RMAN": 0x41, "RVIV": 0x3d, "RMOR": 0x40}
## Hero unit type by race: the switch in 0x42a0d0 (computer heroes, jump table 0x42ac5c; Read from the disassembly) and the
## same codes in the hero book's table at 0x54bee0. Index = race (Barbarians use AMHX, Minotaurs ABHX, Plaguelords AHH1).
const HERO_TYPES := ["AHHX", "ADHX", "AUHX", "AMHX", "ABHX", "AOHX", "AEHX", "AWHX", "AKHX", "AFHX", "AAHX", "AVHX", "APHX", "ALHX", "ARHX", "AHH1"]
const MECHANICAL_BIT := 0x4000               # Army.cfg STATUS race/kind character C (0x5856e0)
const MISSILE_BIT := 0x40000                 # Army.cfg STATUS M

static var _catalogue_cache: Dictionary = {}
static var _research_cache: Dictionary = {}

var catalogue: Dictionary
var research_prices: Dictionary              # id -> {"cost": [4], "seconds"}
## Compatibility view for callers written against production.json (AI desired counts, producer lookup): the Knights'
## PRODUCTION rows keyed by building.
var data: Dictionary
var options := {"build_level": KEEP_LEVEL_OPTION, "no_dragons": false, "no_fliers": false, "no_towers": false, "no_walls": false, "no_lords": false}
var _definitions: Dictionary = {}
var _production: Dictionary = {}             # race -> {building: {"slots", "requires", "last_field", "raw"}}
var _construction: Dictionary = {}           # race -> {row digit: slots}
var _dependencies: Dictionary = {}           # race -> {id: requires}
var _dependency_order: Dictionary = {}       # race -> ids in the merged table order (0x585ca0: DEPENDENCIES rows, then PRODUCTION rows)
var _rules: Dictionary = {}                  # "id/race" -> first [RULES] row
var _status: Dictionary = {}                 # id -> STATUS bits of the first Army.cfg row (0x585970)
var _buildings_cfg: Dictionary = {}          # code -> [BUILDINGS] row

static func load_catalogue() -> Dictionary:
	if _catalogue_cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE_PATH))
		_catalogue_cache = parsed if parsed is Dictionary else {}
	return _catalogue_cache

static func load_research() -> Dictionary:
	if _research_cache.is_empty() and FileAccess.file_exists(RESEARCH_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(RESEARCH_PATH))
		if parsed is Dictionary: _research_cache = parsed.get("prices", {})
	return _research_cache

func _init(source: Dictionary = {}):
	catalogue = source if not source.is_empty() else load_catalogue()
	research_prices = load_research()
	var cfg: Dictionary = catalogue.get("building_cfg", {})
	for row in cfg.get("buildings", []): _buildings_cfg[String(row.code)] = row
	for row in cfg.get("production", []):
		var race := int(row.race_index)
		if not _production.has(race): _production[race] = {}
		var slots: Array = row.slots.map(func(s): return {"kind": String(s.kind), "id": s.id})
		_production[race][String(row.building)] = {"slots": slots, "requires": row.requires, "last_field": String(row.last_field), "raw": String(row.raw)}
	for row in cfg.get("construction", []):
		var race := int(row.race_index)
		if not _construction.has(race): _construction[race] = {}
		_construction[race][String(row.row).substr(1)] = row.slots.map(func(s): return {"kind": String(s.kind), "id": s.id})
	for row in cfg.get("dependencies", []):
		var race := int(row.race_index)
		if not _dependencies.has(race):
			_dependencies[race] = {}
			_dependency_order[race] = []
		if not _dependencies[race].has(String(row.id)):
			_dependencies[race][String(row.id)] = row.requires
			_dependency_order[race].append(String(row.id))
	for row in cfg.get("production", []):
		var race := int(row.race_index)
		if not _dependency_order.has(race):
			_dependencies[race] = {}
			_dependency_order[race] = []
		_dependency_order[race].append(String(row.building))
	for row in cfg.get("rules", []):
		var key := "%s/%d" % [String(row.id), int(row.race_index)]
		if not _rules.has(key): _rules[key] = row
	for section in ["armies", "heroes"]:
		for row in catalogue.get("army_cfg", {}).get(section, []):
			if not _status.has(String(row.code)): _status[String(row.code)] = int(row.status_fields.bits)
	data = {"production": production_table(KNIGHT), "race": "H"}

# ------------------------------------------------------------------------------------------------ records

static func race_index(letter: String) -> int:
	var i := RACE_LETTERS.find(letter)
	return i if i >= 0 and letter.length() == 1 else 0

static func race_letter(race: int) -> String:
	return RACE_LETTERS[clampi(race, 0, 15)]

static func hero_type(race: int) -> String:
	return HERO_TYPES[clampi(race, 0, 15)]

static func is_hero_type(id: String) -> bool:
	return id in HERO_TYPES

static func is_building(id: String) -> bool:
	return id.begins_with("B")

static func is_research(id: String) -> bool:
	return id.begins_with("P") or id.begins_with("R")

static func _u16(raw: PackedByteArray, at: int) -> int:
	return raw.decode_u16(at) if at + 2 <= raw.size() else 0

static func _s16(raw: PackedByteArray, at: int) -> int:
	return raw.decode_s16(at) if at + 2 <= raw.size() else 0

## The definition of a unit or building in the production.json shape (milestone 7's field names): units from the ARM record
## (0x41b3d0 copies it unchanged; cost +0x5e.., time +0x1c, speed +0x20, hit points +0x24, extent +0x38/+0x39, builder
## ability +0x68 / power +0x6c, command cost +0xc8), buildings from the BUI record (time +26, cost +28.., hit points +42,
## armour +44, footprint +62/+63 and mask rows) and the Building.cfg [BUILDINGS] row (army limit, level field, name).
func definition(id: String) -> Dictionary:
	if _definitions.has(id): return _definitions[id]
	var out := {}
	if id.begins_with("A") and catalogue.get("units", {}).has(id):
		var r: Dictionary = catalogue.units[id]
		var raw: PackedByteArray = String(r.raw_hex).hex_decode()
		var src: Dictionary = r.sources[0] if not r.sources.is_empty() else {}
		out = {"kind": "unit", "display_name": String(r.display.name) if r.get("display") is Dictionary else id,
			"source": {"archive": src.get("archive", ""), "entry": src.get("entry", ""), "offset": src.get("offset", 0), "sha256": src.get("sha256", "")},
			"raw_hex": String(r.raw_hex), "movement_type": raw[5], "footprint": [raw[0x38], raw[0x39]],
			"build_time_seconds": _u16(raw, 28), "cost": [_u16(raw, 94), _u16(raw, 96), _u16(raw, 98), _u16(raw, 100)],
			"population": _s16(raw, 200), "builder_ability": _u16(raw, 104), "builder_speed": _u16(raw, 108),
			"base_speed": raw[32], "hit_points": _u16(raw, 36)}
	elif id.begins_with("B") and catalogue.get("buildings", {}).has(id):
		var r: Dictionary = catalogue.buildings[id]
		var raw: PackedByteArray = String(r.raw_hex).hex_decode()
		var src: Dictionary = r.sources[0] if not r.sources.is_empty() else {}
		var cfg: Dictionary = _buildings_cfg.get(id, {})
		var width: int = raw[62]
		var height: int = raw[63]
		var masks: Array = []
		for row in range(height): masks.append(_u16(raw, 64 + 2 * row))
		var tokens: PackedStringArray = String(cfg.get("raw", "")).split(" ", false)
		out = {"kind": "building", "display_name": String(cfg.get("name", id)) if not cfg.is_empty() else (String(r.display.name) if r.get("display") is Dictionary else id),
			"source": {"archive": src.get("archive", ""), "entry": src.get("entry", ""), "offset": src.get("offset", 0), "sha256": src.get("sha256", "")},
			"raw_hex": String(r.raw_hex), "build_time_seconds": _u16(raw, 26),
			"cost": [_u16(raw, 28), _u16(raw, 30), _u16(raw, 32), _u16(raw, 34)], "footprint": [width, height], "mask_rows": masks,
			"hit_points": _u16(raw, 42), "armour": _u16(raw, 44), "army_limit": int(cfg.get("army_limit", 0)),
			"level_field": tokens[2] if tokens.size() > 2 else "",
			# Garrison digit (column 12, record +0x7c, 0x5877a0): the towers' 4 makes them garrisonable (unit_commands.gd).
			"garrison": int(cfg.get("garrison", int(tokens[11]) if tokens.size() > 11 and tokens[11].is_valid_int() else 0))}
	_definitions[id] = out
	return out

## Name shown for an item: units and buildings from their definition, research from English/Help.cfg ([XXXX_Name],
## catalogue "help"; milestone 13), else the id.
func display_name(id: String) -> String:
	if id.begins_with("A") or id.begins_with("B"):
		var d := definition(id)
		if not d.is_empty(): return String(d.display_name)
	return String(catalogue.get("help", {}).get(id, {}).get("name", id))

## English/Help.cfg description and requirement lines of an item ({"name", "desc", "requ"} or {}).
func help(id: String) -> Dictionary:
	return catalogue.get("help", {}).get(id, {})

## Army.cfg STATUS bits of the type's first row (0x585970 returns the first match), 0 when the type has none.
func status_bits(id: String) -> int:
	return int(_status.get(id, 0))

## Builder power (0x523e10): the value of the ARM ability slot whose id is 50 (+0x68 + i * 0x18, value at +0x6c); heroes 10;
## the Undead AUBX +4 once its owner completed PZOM (0x70d58b, REVIEW D8, Emulated; `research` = the owner's list).
func builder_power(id: String, hero: bool = false, research: Array = []) -> int:
	var power := 10 if hero else _builder_slot(id)
	if id == "AUBX" and research.has("PZOM"): power += 4         # also for an AUBX hero unit (Emulated)
	return power

func _builder_slot(id: String) -> int:
	var d := definition(id)
	if d.is_empty() or not d.has("raw_hex"): return 0
	var raw: PackedByteArray = String(d.raw_hex).hex_decode()
	var power := 0
	for i in 4:
		if raw.size() >= 0x6c + i * 0x18 + 2 and raw.decode_u32(0x68 + i * 0x18) == 50: power = raw.decode_u16(0x6c + i * 0x18)
	return power

## 0x523e70: whether a unit can work in a mine. Hard-coded types first (Elven builders and AAEG cannot; the Dwarven Smith and
## the Dark Dwarf builder can), then any unit with builder power. Heroes never enter mines.
func can_mine(id: String, hero: bool = false) -> bool:
	return mine_workers(id, hero) > 0

## 0x523e70's value: the workers a unit adds to a mine (+0xca grows by it, line 112229): 0 for heroes and the types above,
## 2 for the Dwarven Smith and the Dark Dwarf builder, otherwise 1 for a unit with builder power (Emulated, REVIEW D1).
func mine_workers(id: String, hero: bool = false) -> int:
	if hero: return 0
	if id in ["AEBX", "AEAX", "AWJX", "AWKX", "AAEG"]: return 0
	if id in ["ADBX", "AABX"]: return 2
	return 1 if builder_power(id) != 0 else 0

## 0x4fd060's "Peasant" of a race's unit list: movement type 0, an ability slot of id 50, ARM +0x24 below 81, +0x32 below 21.
func is_peasant_type(id: String) -> bool:
	var d := definition(id)
	if d.is_empty() or d.kind != "unit": return false
	var raw: PackedByteArray = String(d.raw_hex).hex_decode()
	if raw[5] != 0 or _s16(raw, 0x24) >= 0x51 or _s16(raw, 0x32) >= 0x15: return false
	for i in 4:
		if raw.decode_u32(0x68 + i * 0x18) == 50: return true
	return false

## Level digit of IDs whose fourth character is 0..4 (Keep levels BKK0..BKK4, BAV0, ...), else -1.
static func level_digit(id: String) -> int:
	if id.length() != 4 or not (id[3] >= "0" and id[3] <= "4"): return -1
	return int(id[3])

## Main halls are BK?0..BK?4 for every race (RACES_RESEARCH.md 2.4): the 0x5325d0 test reads the second ID character 'K'.
static func keep_level(id: String) -> int:
	return level_digit(id) + 1 if id.length() == 4 and id[1] == "K" and level_digit(id) >= 0 else 0

# ------------------------------------------------------------------------------------------------ Building.cfg tables

## PRODUCTION rows of one race keyed by building (the production.json shape the AI's desired counts read).
func production_table(race: int) -> Dictionary:
	return _production.get(race, {})

## PRODUCTION row slots of a building for the owner's race (0x587970 matches race and id; nine entries).
func production_slots(building_id: String, race: int = KNIGHT) -> Array:
	return _production.get(race, {}).get(building_id, {}).get("slots", [])

## 0x40c990 for one slot. `kind` is the slot character: digit = BuildLevel gate, H hero alive, T towers, W walls, L lords.
func slot_allowed(item: String, kind: String, context: Dictionary = {}) -> bool:
	var level: int = clampi(int(options.build_level), 0, 5)        # 0x40c740
	if level == 0: return false
	match kind:
		"-", "0":
			if kind == "-" or not bool(options.no_dragons): return true
			return not (item in DRAGONS)
		"H": return bool(context.get("hero_alive", true))
		"T": return not bool(options.no_towers)
		"W": return not bool(options.no_walls)
		"L": return not bool(options.no_lords) and not bool(context.get("lord_built", false))
	if bool(options.no_fliers) and item in FLIER_BUILDINGS: return false
	if bool(options.no_dragons) and item in DRAGONS: return false
	return kind.is_valid_int() and int(kind) < level

## Items a building can produce for the owner's race: [{"id", "slot", "digit", "kind"}] (gates of 0x40c990).
func menu(building_id: String, race: int = KNIGHT, context: Dictionary = {}) -> Array:
	var out: Array = []
	var slots := production_slots(building_id, race)
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if slot.id == null: continue
		var kind := String(slot.kind)
		if not slot_allowed(String(slot.id), kind, context): continue
		out.append({"id": String(slot.id), "slot": i, "digit": int(kind) if kind.is_valid_int() else 0, "kind": kind})
	return out

## Four dependency slots (0x40b660 per race): units and research from DEPENDENCIES, buildings from the "|" part of their
## PRODUCTION row (0x585ca0 merges both into one table keyed by (race, id)).
func requirements(id: String, race: int = KNIGHT) -> Array:
	var raw: Array = []
	if is_building(id): raw = _production.get(race, {}).get(id, {}).get("requires", [])
	else: raw = _dependencies.get(race, {}).get(id, [])
	return raw.filter(func(r): return r != null)

## The race's merged dependency table in file order (DEPENDENCIES rows, then PRODUCTION rows): the source of the
## computer player's unit, building and research lists (0x4fcfa0 / 0x4fd060 / 0x4fd140).
func dependency_ids(race: int) -> Array:
	return _dependency_order.get(race, [])

## 0x40b350 / 0x40b170: completing a building whose ID ends in digit d (0..4) counts as every level 0..d of that ID; any
## other ID counts as itself. Returns whether `have` satisfies `required`.
static func satisfies(have: String, required: String) -> bool:
	if have == required: return true
	var d := level_digit(have)
	var r := level_digit(required)
	return d >= 0 and r >= 0 and have.substr(0, 3) == required.substr(0, 3) and r <= d

## Buildings an army (hero or builder) may place: CONSTRUCTION row <letter>0 (ordinary buildings). Row 1 (towers, walls) is
## the second menu of 0x4fd940 for non-heroes; it is not offered here (walls and wall segments are Open).
func construction_menu(race: int = KNIGHT, row: int = 0, context: Dictionary = {}) -> Array:
	var out: Array = []
	for slot in _construction.get(race, {}).get(str(row), []):
		if slot.id != null and slot_allowed(String(slot.id), String(slot.kind), context): out.append(String(slot.id))
	return out

## 0x587800 'A' column of Building.cfg; completed buildings add it to the command-point limit.
func army_limit(building_id: String) -> int:
	return int(definition(building_id).get("army_limit", 0))

## Building.cfg [BUILDINGS] row (side flags, resource, shoot), or {}.
func building_row(code: String) -> Dictionary:
	return _buildings_cfg.get(code, {})

## 0x587aa0: the first [RULES] row for (id, race), or {}.
func rule(id: String, race: int) -> Dictionary:
	return _rules.get("%s/%d" % [id, race], {})

# ------------------------------------------------------------------------------------------------ 0x437f70

## 0x437f70(player, id) over a completed-research list: a 'P..X' id returns the highest level present (P..0 -> 1 .. P..8 -> 9),
## any other id 1 when listed, else 0.
static func research_level(list: Array, id: String) -> int:
	if id.length() == 4 and id[0] == "P" and id[3] == "X":
		var level := 0
		for r in list:
			var s := String(r)
			if s.length() == 4 and s.substr(0, 3) == id.substr(0, 3) and s[3] >= "0" and s[3] <= "8":
				level = maxi(level, int(s[3]) + 1)
		return level
	return 1 if list.has(id) else 0

# ------------------------------------------------------------------------------------------------ 0x40b6b0

## 0x40c350: cost * 100 / (discount + 100), at least 1 for a positive cost.
static func discounted(value: int, discount: int) -> int:
	var out: int = (value * 100) / (discount + 100) if discount != -100 else value
	if out < 1 and value > 0: out = 1
	return out

static func _wrap16(v: int) -> int:
	v = v & 0xffff
	return v - 0x10000 if v >= 0x8000 else v

static func _tdiv(a: int, b: int) -> int:
	var q: int = absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

## 0x40b6b0(item, builder, player, out): price [gold, metal, crystal, stone] and seconds, {"ok", "cost", "seconds"}.
## `context` holds the player's state the original reads: "race" (0x708f96), "research" (completed list 0x70ae40),
## "discount" (0x526cf0 of the living hero + the computer discount 0x5fbc38; 0 when the hero is dead), "builder" (ARM id of
## the building unit, "" = -1), "hero_alive", "skill_3f" (hero skill 0x3f value, building time), "research_discount" (hero
## skill 0x25 + item stat 0x25), "skill_ranks" ({skill: rank} for the research ids of RESEARCH_SKILLS).
func price(item: String, context: Dictionary = {}) -> Dictionary:
	var race := int(context.get("race", KNIGHT))
	var research: Array = context.get("research", [])
	var discount := int(context.get("discount", 0))
	if item.begins_with("A"): return _unit_price(item, race, research, discount)
	if item.begins_with("B"): return _building_price(item, race, research, discount, context)
	if is_research(item): return _research_price(item, race, research, discount, context)
	return {"ok": true, "cost": [0, 0, 0, 0], "seconds": 0}        # other ids: the output is left untouched (here zero)

func _apply_rule(item: String, race: int, cost: Array, seconds: int) -> int:
	var r := rule(item, race)
	if r.is_empty(): return seconds
	for lane in 4:
		var v = r.cost.get(LANES[lane])
		if v != null and int(v) >= 0: cost[lane] = int(v)
	if r.time != null and int(r.time) >= 0: seconds = int(r.time)
	return seconds

func _unit_price(item: String, race: int, research: Array, discount: int) -> Dictionary:
	if FLAT_PRICES.has(item) and race != DARK_DWARF:
		var entry: Array = FLAT_PRICES[item]
		var cost := [0, 0, 0, 0]
		cost[entry[0]] = maxi(1, discounted(int(entry[1]), discount))
		return {"ok": true, "cost": cost, "seconds": 0}            # the time words are cleared too
	var d := definition(item)
	if d.is_empty(): return {"ok": false, "cost": [0, 0, 0, 0], "seconds": 0}
	var record: Array = d.cost.duplicate()
	var cost: Array = record.duplicate()
	var seconds := _apply_rule(item, race, cost, int(d.build_time_seconds))
	for lane in 4:
		if cost[lane] != 0: cost[lane] = maxi(1, discounted(int(cost[lane]), discount))
	var status := status_bits(item)
	var fast := false            # time x 3/4
	var quarter := false         # price x 3/4
	var third := false           # price x 2/3
	var half := false            # price x 1/2
	if (item == "ABIX" or item == "ABGX") and research_level(research, "PJIH") != 0: fast = true
	if (item == "AAIX" or item == "AAGX" or (status & MECHANICAL_BIT) != 0) and research_level(research, "PSPP") != 0: fast = true
	if item in DAEMON_UNITS:
		if research_level(research, "PSU0") != 0: fast = true
		if research_level(research, "PSU1") != 0: quarter = true
	if item == "AHCX":
		match research_level(research, "PFMX"):
			1: quarter = true
			2: third = true
			3: half = true
	if race == SWARM:
		var level := research_level(research, "PIUX")
		var percent := (level + 1) * 5 if level > 0 else 0
		if item in SWARM_UNITS: seconds = _wrap16(seconds + _tdiv(_wrap16(seconds) * percent, -100))
	var out: Array = cost.duplicate()
	if half:
		for lane in 4: out[lane] = int(out[lane]) >> 1
	elif third:
		for lane in 4: out[lane] = _tdiv(int(out[lane]) * 2, 3)
	elif quarter:
		for lane in 4: out[lane] = (int(out[lane]) * 3) >> 2
	var time := _wrap16(seconds)
	if fast: time = (time * 3) >> 2
	for lane in 4:
		if int(record[lane]) != 0: out[lane] = maxi(1, int(out[lane]))
	return {"ok": true, "cost": out, "seconds": time}

func _building_price(item: String, race: int, research: Array, discount: int, context: Dictionary) -> Dictionary:
	var d := definition(item)
	if d.is_empty(): return {"ok": false, "cost": [0, 0, 0, 0], "seconds": 0}
	var cost: Array = d.cost.duplicate()
	var seconds := _apply_rule(item, race, cost, int(d.build_time_seconds))
	for lane in 4:
		if cost[lane] != 0: cost[lane] = maxi(1, discounted(int(cost[lane]), discount))
	var speed := 10
	var builder := String(context.get("builder", ""))
	if builder != "":
		var b := definition(builder)
		if not b.is_empty() and b.kind == "unit" and int(b.get("builder_ability", 0)) == 50: speed = _wrap16(int(b.builder_speed))
	var engineering := 25 if research_level(research, "PENG") != 0 else 0
	var skill := int(context.get("skill_3f", 0)) if bool(context.get("hero_alive", false)) else 0
	var t: int = _wrap16(seconds)
	t = t - _tdiv((speed - 10) * t, 10)
	t = t - _tdiv(engineering * t, 100)
	t = t - _tdiv(skill * t, 100)
	return {"ok": true, "cost": cost, "seconds": t}

func _research_price(item: String, race: int, research: Array, discount: int, context: Dictionary) -> Dictionary:
	var entry: Dictionary = research_prices.get(item, {})
	var cost: Array = entry.get("cost", [0, 0, 0, 0]).map(func(v): return int(v))
	var seconds := _wrap16(_apply_rule(item, race, cost, int(entry.get("seconds", 0))))
	for lane in 4:
		if cost[lane] != 0: cost[lane] = maxi(1, discounted(int(cost[lane]), discount))
	var scaled := false
	var factor := 0
	if RESEARCH_SKILLS.has(item):
		var rank := int(context.get("skill_ranks", {}).get(RESEARCH_SKILLS[item], 0))
		if rank != 0:
			scaled = true
			factor = maxi(0, 100 - 10 * rank)
	var reduction := 0
	if bool(context.get("hero_alive", false)): reduction = mini(75, int(context.get("research_discount", 0)))
	for lane in 4:
		if cost[lane] != 0: cost[lane] = _tdiv((100 - reduction) * int(cost[lane]), 100)
	var mercenary := 0
	if item in ["POMA", "POMB", "POMC"]:
		match research_level(research, "PFMX"):
			1: mercenary = 25
			2: mercenary = 33
			3: mercenary = 50
	for lane in 4:
		if cost[lane] != 0: cost[lane] = _wrap16(_tdiv((100 - mercenary) * int(cost[lane]), 100))
	if scaled:
		for lane in 4:
			if cost[lane] != 0: cost[lane] = maxi(1, _tdiv(int(cost[lane]) * factor, 100))
	return {"ok": true, "cost": cost, "seconds": seconds}

## Price only (milestone 7 signature): the Knights with a discount and no research.
func cost(id: String, discount: int = 0, context: Dictionary = {}) -> Array[int]:
	var c := context.duplicate()
	c.discount = discount
	var out: Array[int] = []
	for v in price(id, c).cost: out.append(int(v))
	return out

## Job time in game milliseconds; buildings pass the builder's ARM id (0x40b6b0 builder speed), upgrades their own ID.
func time_ms(id: String, builder_id: String = "", context: Dictionary = {}) -> int:
	var c := context.duplicate()
	c.builder = builder_id
	return int(price(id, c).seconds) * 1000
