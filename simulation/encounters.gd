extends RefCounted
## Desert Sands neutral encounters (milestone 9): the map's neutral buildings (two Dwarven and two Swarm towers, the
## Gnoll Lair, the Mausoleum) as combat objects of the neutral player 6, the lair spawner (0x404a20 / 0x404e10 /
## 0x404b10 / 0x404ac0), the scenario animals and the Mausoleum quests (0x43d180, 0x52edb0, 0x43dde0, 0x43db30,
## 0x43d3a0, 0x43d560). Evidence labels: ENCOUNTERS_RESEARCH.md. Unit art is the Swordsman placeholder for every type.
const NamingSets = preload("res://simulation/naming_sets.gd")
const Rules = preload("res://simulation/combat_rules.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")
const Building = preload("res://simulation/building_state.gd")
const MapData = preload("res://core/map_data.gd")
const Shops = preload("res://simulation/skirmish_shops.gd")

const NEUTRAL := 6
const LAIR_CHECK_MS := 2000              # 0x404a20 runs its list at most every 2 s
const QUEST_XP := 20                     # 0x43d560: the hero gains 20 XP for a completed quest (40 with research POGL)
const QUEST_XP_POGL := 40
const LAIRS := {"BLBM": 0, "BLHN": 1, "BLGL": 2, "BLGH": 3, "BSBS": 4, "BSAL": 5}   # 0x404b70 / lair table 0x5fb338
const RESOURCE_LETTERS := {"G": 0, "M": 1, "C": 2, "S": 3}                           # 0x43d3a0 / economy lane order

signal spawned(info: Dictionary)
signal quest_event(text: String, info: Dictionary)
signal quest_lost(player: int, record: Dictionary)   # Q-1: 0x43d560 cleared another player's quest from the same giver (line 0xbc)

var combat
var production
var economy
var collision
var catalogue: Dictionary                # assets/catalogue.json
var data: Dictionary                     # assets/encounters.json
var lair_table: Array                    # unit_ai_scripts.json "lairs" (0x5fb338, Emulated)
var xp_levels: Array                     # 0x5fbc48
var spawn_unit: Callable                 # (type_id, cell, owner, xp) -> unit id (-1 when nothing was created)
var lairs: Array = []                    # 0x404a20 entries
var next_lair_check := -1
var givers: Dictionary = {}              # building id -> Mausoleum state (+0x125 picked, +0x126 resting, +0x128, +0x12c)
var quests: Dictionary = {}              # player -> active quest (0x744db8 + player * 0x818)
var static_cells: Dictionary = {}        # building id -> cells of its map placement
var log: Array = []
# S-2: the setup's Quests option 0x70ae0d (hero commands 0x11 / 0x34 / 0x35, the q dialog, the computer's visit), Tough Towers
# 0x70ae27 (0x41a8c0 on the 16 tower rows) and the shops of 0x4083c0 (building id -> skirmish_shops.gd stock).
var quests_enabled := true
var tough_towers := false
var tough_start_towers := false          # setup rows: More Options "Tough Starting Towers" (0x749c64 byte 3 = 0x749c67)
var shops: Dictionary = {}
var shops_ready := false

func _init(world_combat, world_production, world_economy, collision_data, catalogue_data: Dictionary, encounter_data: Dictionary, ai_data: Dictionary):
	combat = world_combat
	production = world_production
	economy = world_economy
	collision = collision_data
	catalogue = catalogue_data
	data = encounter_data
	lair_table = ai_data.lairs
	xp_levels = ai_data.xp_levels
	production.building_destroyed.connect(_on_building_removed)
	combat.building_hit.connect(_on_building_hit)
	combat.died.connect(_on_died)
	# Q-1: the quest events of 0x43db30 that are not deaths: 2 a converted building (0x4a6cc0), 3 a finished building (0x52bfd0).
	if production.has_signal("building_placed"): production.building_placed.connect(_note_building)
	if production.has_signal("building_converted"): production.building_converted.connect(_on_building_converted)
	if production.has_signal("building_completed"): production.building_completed.connect(_on_building_completed)
	for code in data.ani:
		var slots: Array = data.ani[code].slots
		combat.ani[code] = {"attack_frames": int(slots[2].frames) if slots[2].enabled else 16, "hit_frame": int(slots[2].word_18) if slots[2].enabled else 6,
			"death_frames": int(slots[3].frames) if slots[3].enabled else 13}

## Drops the spawn callback, which usually captures its owner (REVIEW_ENCOUNTERS.md D7); call before replacing the object.
func dispose():
	spawn_unit = Callable()

static func load_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

# --------------------------------------------------------------------------------------- definitions (catalogue)
func catalogue_record(kind: String, code: String) -> Dictionary:
	var records = catalogue[kind]
	if records is Dictionary: return records.get(code, {})
	for r in records:
		if r.code == code: return r
	return {}

## A unit definition from its ARM record: speed +0x20 (the walk table index) and the combat block.
func unit_definition(code: String) -> Dictionary:
	var r := catalogue_record("units", code)
	if r.is_empty(): return {}
	var raw: PackedByteArray = String(r.raw_hex).hex_decode()
	return {"raw_hex": r.raw_hex, "base_speed": Rules.i16(raw, 0x20), "display_name": r.display.get("name", code), "kind": "unit"}

## A building definition from its BUI record, in the production.json shape (footprint, mask rows, hit points).
func building_definition(code: String) -> Dictionary:
	var r := catalogue_record("buildings", code)
	if r.is_empty(): return {}
	var fp: Dictionary = r.footprint
	var definition := {"raw_hex": r.raw_hex, "footprint": [int(fp.size[0]), int(fp.size[1])], "mask_rows": fp.get("masks", []),
		"hit_points": int(r.decoded.hit_points), "display_name": r.display.get("name", code), "kind": "building"}
	if tough_towers and code.begins_with("BWT") and TOWER_BY_RACE.contains(code.substr(3)): toughen(definition)
	return definition

## S-2: 0x41a8c0 on a tower's BUI record (Read): damage +0x38 x 3, range +0x3c + 4, +0x24 and the hit points +0x2a x 3 / 2, the
## shot period index +0x26 + 1.
static func toughen(definition: Dictionary):
	var raw: PackedByteArray = String(definition.raw_hex).hex_decode()
	raw.encode_s16(0x38, Rules.i16(raw, 0x38) * 3)
	raw.encode_s16(0x3c, Rules.i16(raw, 0x3c) + 4)
	raw.encode_s16(0x24, Rules.i16(raw, 0x24) * 3 / 2)
	raw.encode_s16(0x2a, Rules.i16(raw, 0x2a) * 3 / 2)
	raw.encode_s16(0x26, Rules.i16(raw, 0x26) + 1)
	definition.raw_hex = raw.hex_encode()
	definition.hit_points = int(definition.hit_points) * 3 / 2

## The Building.cfg shop flag (+0x7f, 0x5877e0).
func is_shop(code: String) -> bool:
	for row in catalogue.get("building_cfg", {}).get("buildings", []):
		if row.code == code: return bool(row.shop)
	return false

## The Building.cfg searchable flag (0x52ed90 -> 0x587780): the quest sites, Mausoleum and Shrine.
func is_quest_site(code: String) -> bool:
	for row in catalogue.get("building_cfg", {}).get("buildings", []):
		if row.code == code: return bool(row.searchable)
	return false

## S-2: a finished building of `code` at `cell` that the scenario does not hold: the Capture the Flag flags (0x41c7d0 case 0xc
## -> 0x43bd50 / 0x4a50f0) and, in the checks, a shop. Neutral quest sites and shops register as the map's do.
func place_site(code: String, owner: int, cell: Vector2i) -> int:
	var definition := building_definition(code)
	if definition.is_empty(): return -1
	var id: int = production.next_building_id
	production.next_building_id += 1
	var b = Building.new(id, code, owner, combat.navigator.center(cell), definition, cell.x, cell.y)
	b.completed_counted = true
	production.buildings[id] = b
	for x in int(definition.footprint[0]):
		for y in int(definition.footprint[1]):
			combat.navigator.set_building_cell(cell + Vector2i(x, y), id)
	if owner == NEUTRAL and is_quest_site(code): givers[id] = _giver(code)
	return id

func _giver(code: String) -> Dictionary:
	return {"code": code, "picked": false, "resting": false, "until_ms": 0, "record": null}

# --------------------------------------------------------------------------------------- map placements
## The map's towers, lair and Mausoleum. Owner = BLDH record +0x64, which the scenario loader 0x4910e0 copies into its owner
## slot (0x491211, Read; carried as `owner` in map.json). The loader creates a building only when its owner's slot is active
## (0x708f94 + owner * 0x2c) or the owner is the neutral player 6 (0x49156c, Read); `active_players` stands in for that
## table until milestone 10's match start. Owner-6 buildings are the neutral encounters (lair, Mausoleum); towers belong to
## their player (Desert Sands: Dwarven Towers player 0, Swarm Towers player 1) and shoot for that player. Cells are the
## placement's occupied cells from the collision import; they are already blocked, so no new stamp is made.
##
## Parity pass 3 (0x4a50f0, disassembled; Read): the scenario building creator swaps a tower (any of the 16 BWT? codes) for
## the tower of its owner's race (race 0x708f96 + owner * 0x2c -> jump table 0x4a5674) and a wall of levels 0..2 (BWG? /
## BWN? / BWE?) for its owner's wall style (tables 0x4a56b4 / 0x4a56f4 / 0x4a5734); nothing else changes type (Keeps,
## mines, lairs keep their code). With the record's byte +0x43 clear the new type's Building.cfg values are copied into
## the record (hit points, armour, damage, range ...), and in game modes 0 / 1 a tower then gains terms from L = the
## highest level among the non-computer slots (setup level 0xa479c8 or the hero level 0x709d00 / 0x7091e8): +10 L hit
## points (current and maximum), +L / 4 damage, +L / 10 combat, +L / 20 on the shot period index (BUI +0x26). The
## fixture harness keeps the map's own codes (`races` empty); start_skirmish passes the slot races and L.
const TOWER_BY_RACE := "CDUBROMWKFAVHLEG"   # 0x4a5674: race -> BWT? letter (Knights C, Dwarves D, the Swarm E ...)
const WALL_BY_RACE := "GGENNEGNENEEGNEE"    # 0x4a56b4 (levels 0..2 alike): race -> BWG? / BWN? / BWE?

static func race_building(code: String, race: int) -> String:
	if race < 0 or race > 15 or code.length() != 4: return code
	if code.begins_with("BWT") and TOWER_BY_RACE.contains(code[3]): return "BWT" + TOWER_BY_RACE[race]
	if code.begins_with("BW") and "GNE".contains(code[2]) and "012".contains(code[3]): return "BW" + WALL_BY_RACE[race] + code[3]
	return code

## 0x4a50f0's level terms for a tower created from a record with +0x43 clear in game mode 0 or 1 (Read; Emulated in the
## setup rows, tests/setup_rows_fixtures.json "map_towers").
static func tower_level_terms(level: int) -> Dictionary:
	return {"hit_points": 10 * level, "damage": level / 4, "combat": level / 10, "period": level / 20}

## Setup rows (Emulated, "start_towers"): 0x418700 with flag 1 (the random map's race towers of 0x4183b0) adds its own level
## terms and marks the record (+0x2b = the message's +0x43), so 0x4a50f0 adds none: damage L / 5 and the shot period L / 50.
static func start_tower_level_terms(level: int) -> Dictionary:
	return {"hit_points": 10 * level, "damage": level / 5, "combat": level / 10, "period": level / 50}

## Setup rows (Emulated, "map_towers" and "start_towers"): Tough Starting Towers (0x749c67) in 0x4a50f0's tower block (a
## record with +0x43 clear: every scenario tower) and in 0x418700 (flag 1): hit points and maximum 750, shot period index
## (BUI +0x26) 3, combat (+0x24) and damage (+0x38) doubled, range (+0x3c) + 1; before the level terms, which still apply.
## The Rules row Tough Towers (0x41a8c0) has already changed the BUI record these start from.
static func toughen_start(definition: Dictionary):
	var raw: PackedByteArray = String(definition.raw_hex).hex_decode()
	raw.encode_s16(0x2a, 750)
	raw.encode_s16(0x26, 3)
	raw.encode_s16(0x24, Rules.i16(raw, 0x24) * 2)
	raw.encode_s16(0x38, Rules.i16(raw, 0x38) * 2)
	raw.encode_s16(0x3c, Rules.i16(raw, 0x3c) + 1)
	definition.raw_hex = raw.hex_encode()
	definition.hit_points = 750

## A tower's start terms as 0x4a50f0 (a scenario tower) or 0x418700 (`start_side`: a random map's race tower) leave the
## record: Tough Starting Towers first, then in game modes 0 / 1 the level terms (hit points added to the definition;
## damage, combat and shot period returned for Combat.register_tower). L = the highest non-computer level.
static func tower_start_terms(definition: Dictionary, tough: bool, level: int, game_mode: int, start_side: bool) -> Dictionary:
	if tough: toughen_start(definition)
	if game_mode > 1: return {}
	var terms := start_tower_level_terms(level) if start_side else tower_level_terms(level)
	definition["hit_points"] = int(definition.hit_points) + int(terms.hit_points)
	return terms

func adopt_map_buildings(now_ms: int, active_players: Array = [0, 1], races: Array = [], human_level: int = 0) -> Array:
	var adopted: Array = []
	var owners := {}
	var start_sides := {}                  # setup rows: random-map race towers made by 0x418700 with flag 1
	for r in MapData.map().buildings:
		owners[int(r.source_offset)] = int(r.get("owner", NEUTRAL))
		if bool(r.get("start_side", false)): start_sides[int(r.source_offset)] = true
	for o in collision.data.objects:
		# W1: every map tower (any BWT? code that 0x4a50f0 swaps; Desert Sands has BWTD / BWTE, The Hill BWTB / BWTC /
		# BWTD / BWTU), every lair of the table (S-3: 0x404b70 matches the six codes) and the Mausoleum.
		var map_tower: bool = String(o.code).begins_with("BWT") and TOWER_BY_RACE.contains(String(o.code)[3])
		# S-2: the Shrine BMSH is a quest site like the Mausoleum (Building.cfg searchable); the shop flag makes a shop.
		if o.kind != "buildings" or not (map_tower or LAIRS.has(o.code) or is_quest_site(String(o.code)) or is_shop(String(o.code))): continue
		var owner: int = owners.get(int(o.source_offset), NEUTRAL)
		if owner != NEUTRAL and not active_players.has(owner): continue
		var code: String = o.code
		if owner < races.size(): code = race_building(code, int(races[owner]))
		var definition := building_definition(code)
		var terms := {}
		if code.begins_with("BWT") and not races.is_empty():
			terms = tower_start_terms(definition, tough_start_towers, human_level, combat.game_mode, start_sides.has(int(o.source_offset)))
		var id: int = production.next_building_id
		production.next_building_id += 1
		var left: int = int(o.origin_cell[0])
		var top: int = int(o.origin_cell[1])
		var b = Building.new(id, code, owner, Vector2(float(o.world_position[0]), float(o.world_position[1])), definition, left, top)
		b.completed_counted = true
		production.buildings[id] = b
		var cells: Array = []
		for c in o.occupied_cells:
			var cell := Vector2i(int(c[0]), int(c[1]))
			combat.navigator.set_building_cell(cell, id)
			cells.append(cell)
		static_cells[id] = {"cells": cells, "object": int(o.index)}
		var anchor := Vector2i(int(o.anchor_cell[0]), int(o.anchor_cell[1]))
		var entry := {"id": id, "code": code, "map_code": o.code, "anchor": anchor, "owner": owner}
		if combat.register_tower(b, anchor, terms): entry["tower"] = true
		if LAIRS.has(o.code): lairs.append(_lair_entry(id, LAIRS[o.code], anchor, now_ms))   # 0x404b70 does not test the owner
		if owner == NEUTRAL and is_quest_site(String(o.code)): givers[id] = _giver(String(o.code))
		adopted.append(entry)
	return adopted

## 0x404b70 (first 0x404a20 pass): last = response = now; the first wave is due at now + max + (1d(max/1000) - 1) * 1000.
func _lair_entry(building_id: int, index: int, cell: Vector2i, now_ms: int) -> Dictionary:
	var lair: Dictionary = lair_table[index]
	var roll: int = combat.rng.roll(1, int(lair.max_ms) / 1000, -1)
	return {"active": true, "building": building_id, "lair": index, "last_ms": now_ms, "response_ms": now_ms,
		"next_ms": int(lair.max_ms) + roll * 1000 + now_ms, "cell": cell, "waves": 0}

## When a map building dies its placement stops blocking (0x52a870 for the occupancy; the static object leaves the grid).
var released: Array = []                 # [cell, object index] taken out of the shared collision data

func _on_building_removed(id: int):
	if not static_cells.has(id): return
	for cell in static_cells[id].cells:
		var c: Dictionary = collision.cell_data(cell)
		if c.has("object_indices") and c.object_indices.has(static_cells[id].object):
			c.object_indices.erase(static_cells[id].object)
			released.append([cell, static_cells[id].object])
	static_cells.erase(id)
	combat.navigator.build_sectors()

## Harness reset: put destroyed map placements back into the shared collision data.
func restore_static():
	for pair in released:
		var c: Dictionary = collision.cell_data(pair[0])
		if not c.object_indices.has(pair[1]): c.object_indices.append(pair[1])
	released.clear()

## Scenario animals: each ARMH record is one unit of player 6 (owner at record +0x94, Read from the 0x4910e0 loader;
## the earlier reading of record +4 as a group count was wrong).
func spawn_animals() -> Array:
	var made: Array = []
	var map: Dictionary = MapData.map()
	for a in map.armies:
		var cell := Vector2i(floori(float(a.cell_position[0])), floori(float(a.cell_position[1])))
		var id: int = spawn_unit.call(String(a.code), cell, NEUTRAL, 0)
		if id >= 0 and combat != null and combat.fighters.has(id): combat.fighters[id].may_join = false   # 0x4c34b0 clears +0xc2
		if id >= 0: made.append(id)
	return made

# --------------------------------------------------------------------------------------- lair spawner
## 0x404a20, called every game update with the clock; it acts at most every 2 s.
func update(now_ms: int):
	for b in production.buildings.values(): _note(b)
	# Q-3: the building update ends a quest site's rest at now >= +0x128 (0x52cf41 -> 0x52f7c0(1), REVIEW_ENCOUNTERS.md).
	for g in givers.values():
		if bool(g.resting) and now_ms >= int(g.until_ms): g.resting = false
	if not shops_ready: open_shops()
	if now_ms < next_lair_check: return
	next_lair_check = now_ms + LAIR_CHECK_MS
	for entry in lairs:
		if entry.active and now_ms >= int(entry.next_ms): _wave(entry, now_ms, true)    # 0x404cd0 -> 0x404e10(now, entry, 1)

## 0x408300 -> 0x4083c0: once, the neutral player's buildings with the shop flag are stocked (0x408450).
func open_shops():
	shops_ready = true
	for b in production.buildings.values():
		if int(b.owner) == NEUTRAL and is_shop(String(b.original_type_id)) and not shops.has(b.entity_id):
			shops[b.entity_id] = Shops.stock(combat.rng, shops.size(), Vector2i(b.left, b.top))

## 0x404b10 when the lair takes damage: a full wave once the response time has passed.
func _on_building_hit(id: int, attacker_kind: String, attacker_id: int):
	if shops.has(id):                                                                 # S-2: 0x52bd10 -> 0x408360
		var attacker = combat.fighters.get(attacker_id) if attacker_kind == "unit" else null
		Shops.offended(shops, id, int(attacker.owner) if attacker != null else NEUTRAL)
	for entry in lairs:
		if entry.active and entry.building == id and combat.now_ms >= int(entry.response_ms): _wave(entry, combat.now_ms, false)

func _wave(entry: Dictionary, now_ms: int, timed: bool):
	var result := lair_wave(combat.rng, now_ms, lair_table[int(entry.lair)], timed, xp_levels)
	entry.last_ms = result.times[0]
	entry.response_ms = result.times[1]
	entry.next_ms = result.times[2]
	entry.waves += 1
	var b = production.building(int(entry.building))
	var target: Vector2i = production.spawn_target(b) if b != null else entry.cell      # 0x52df30
	for s in result.spawns:
		var cell: Vector2i = combat.navigator.free_cell_near(target)                    # 0x4a49e0 -> 0x530a90
		var unit_id: int = spawn_unit.call(s.type, cell, NEUTRAL, int(s.xp)) if cell.x >= 0 else -1
		log.append({"t": now_ms, "lair": entry.building, "type": s.type, "unit": unit_id, "timed": timed})
		spawned.emit({"lair": entry.building, "type": s.type, "unit": unit_id, "xp": s.xp, "timed": timed})

## 0x404e10 (Emulated: tests/unit_ai_fixtures.json "lairs.waves"): returns the entry's new times [last, response, next]
## and the spawns [{type, xp}] in creation order. Draws: next-wave delay, wave row, then one 1d4 per spawned unit.
static func lair_wave(rng, now_ms: int, lair: Dictionary, timed: bool, levels: Array) -> Dictionary:
	var span: int = (int(lair.max_ms) - int(lair.min_ms)) / 1000
	var d: int = rng.roll(1, span, -1)
	var times := [now_ms, int(lair.response_ms) + now_ms, int(lair.min_ms) + d * 1000 + now_ms]
	var entries: Array = lair.entries
	var e: Dictionary = entries[rng.roll(1, entries.size(), -1)]
	var counts := wave_counts(now_ms, int(e.count_a), int(e.count_b), timed)
	var a: int = counts[0] if e.type_a != "" else 0
	var b: int = counts[1] if e.type_b != "" else 0
	var spawns: Array = []
	for i in a: spawns.append({"type": e.type_a, "xp": rng.roll(1, 4, -1) + int(levels[int(e.level_a)])})
	for i in b: spawns.append({"type": e.type_b, "xp": rng.roll(1, 4, -1) + int(levels[int(e.level_b)])})
	return {"times": times, "spawns": spawns}

## 0x404e10 counts: a timed wave starts from 1 + 1, an attack response from the row's counts; both grow with the match
## clock (C division). Brackets and the quirks of the B count are the original's.
static func wave_counts(now_ms: int, ca: int, cb: int, timed: bool) -> Array:
	var a := 1 if timed else ca
	var b := 1 if timed else cb
	if now_ms < 120000:
		a = maxi(a, ca / 6); b = maxi(b, ca / 6)
	elif now_ms < 240000:
		a = maxi(a, ca / 4); b = maxi(b, ca / 4)
	elif now_ms < 360000:
		a = maxi(a, ca / 3); b = maxi(b, ca / 3)
	elif now_ms < 480000:
		a = maxi(a, ca / 2); b = maxi(1, cb / 2)
	elif now_ms < 600000:
		a = maxi(a, ca * 2 / 3); b = maxi(b, cb * 2 / 3)
	elif now_ms < 840000:
		a = maxi(a, ca * 3 / 4); b = maxi(b, cb * 3 / 4)
	elif now_ms < 1200000:
		a = maxi(a, ca); b = maxi(b, cb)
	elif now_ms < 1800000:
		a = maxi(a, ca * 5 / 4); b = maxi(b, cb * 5 / 4)
	elif now_ms < 2400000:
		a = maxi(a, ca * 3 / 2); b = maxi(b, cb * 3 / 2)
	elif now_ms < 3600000:
		a = maxi(a, ca * 7 / 4); b = maxi(b, cb * 7 / 4)
	else:
		a = maxi(a, ca * 2); b = maxi(b, cb * 2)
	return [a, b]

## 0x404cf0 (Emulated: "lairs.bosses"): the boss type with 1d4 - 1 + 0x5fbc48[boss level + 1] experience, at the lair's
## cell. Milestone 11: 0x404cf0 names the spawn "_L@1R8055_", so 0x4a49e0 attaches effect EZ55 and status 0x1a (10,000 s);
## a unit with status 0x1a drops one random treasure item when it dies (0x5210b0 -> 0x528300 -> message 0x198 -> 0x4a87f0,
## 0x43e340(1, 1)); main.gd does the drop (Treasures).
static func lair_boss(rng, lair: Dictionary, levels: Array) -> Dictionary:
	if String(lair.boss) == "": return {}
	return {"type": lair.boss, "xp": rng.roll(1, 4, -1) + int(levels[int(lair.boss_level) + 1])}

func _on_died(kind: String, id: int, killer_owner: int):
	if kind == "building":
		for entry in lairs:
			if not entry.active or entry.building != id: continue
			entry.active = false                                                       # 0x404ac0
			var boss := lair_boss(combat.rng, lair_table[int(entry.lair)], xp_levels)
			if not boss.is_empty():
				var cell: Vector2i = combat.navigator.free_cell_near(entry.cell)
				var unit_id: int = spawn_unit.call(boss.type, cell, NEUTRAL, int(boss.xp))
				log.append({"t": combat.now_ms, "lair": id, "boss": boss.type, "unit": unit_id})
				spawned.emit({"lair": id, "type": boss.type, "unit": unit_id, "xp": boss.xp, "boss": true})
		if killer_owner >= 0: quest_progress(killer_owner, "building", id)
		return
	if killer_owner >= 0: quest_progress(killer_owner, "unit", id)

# --------------------------------------------------------------------------------------- quests
func quest_records(code: String = "BZMA") -> Array:
	return data.quests.get(code, {}).get("records", [])

## Match inputs of 0x43dde0 (milestone 10's match start fills them): player slot active (0x708f94 + p * 0x2c), the per-player
## byte 0x748668 (a match option, default 0) and the race word (0x708f96 + p * 0x2c, Knights = 0).
var player_active: Array = [true, true, false, false, false, false, false]
var player_byte_748668: Array = [0, 0, 0, 0, 0, 0, 0]
var player_race: Array = [0, 0, 0, 0, 0, 0, 0]
const UNBUILT_TARGETS := ["BTDR", "BTCE", "BTIN", "BTEL"]    # 0x43dde0 refuses these ids for types 8 and 9

## 0x43dde0 for player p (Emulated: tests/quest_fixtures.json, 37,800 cases, tests/test_encounters_review.gd). Objects of the
## other six players' lists count, the neutral player and animals included, with no hostility test and no hit-point test
## (dying units are still listed; removed ones are not). Type 1: at least count * 8 / 10 units (and one); 2 and 3: at least
## count buildings; 5: at least count heroes whose player slot is active, whose 0x748668 byte is clear and whose hit points
## are above 0 (and one); 6: at least count * 9 / 10 units of the target type (and one); 7: at least count target buildings
## (and one); 8: the player's race can build the target (Building.cfg build sides); 9: the race can build it, or else at least
## count (and one) target buildings of players hostile to p (0x748915); 0 and 4 always. Q-1: a record whose research reward
## the player already owns is refused (Read: the tail of 0x43dde0, +0x21 set and 0x437f70(player, +0x40) != 0).
func eligible(player: int, r: Dictionary) -> bool:
	if not _eligible_type(player, r): return false
	if bool(r.get("reward_research", false)) and _research_level(player, String(r.research)) != 0: return false
	return true

func _eligible_type(player: int, r: Dictionary) -> bool:
	var units_other := 0
	var buildings_other := 0
	var units_type := 0
	var buildings_type := 0
	var hostile_type := 0
	for f in combat.fighters.values():
		if f.owner == player or bool(f.get("removed", false)): continue
		units_other += 1
		if f.type_id == r.target: units_type += 1
	for b in production.buildings.values():
		if b.owner == player: continue
		buildings_other += 1
		if b.original_type_id == r.target:
			buildings_type += 1
			if not combat.allied(b.owner, player): hostile_type += 1
	match int(r.type):
		1:
			var need: int = int(r.count) * 8 / 10
			return units_other >= need and units_other > 0
		2, 3: return buildings_other >= int(r.count)
		5:
			var heroes := 0
			for owner in combat.heroes:
				if owner == player or not bool(player_active[owner]) or int(player_byte_748668[owner]) != 0: continue
				var h = combat.fighters.get(combat.heroes[owner].unit)
				if h != null and int(h.hp) > 0: heroes += 1
			return heroes >= int(r.count) and heroes > 0
		6: return units_type >= int(r.count) * 9 / 10 and units_type > 0
		7: return buildings_type >= int(r.count) and buildings_type > 0
		8: return race_can_build(player, String(r.target))
		9:
			if race_can_build(player, String(r.target)): return true
			return hostile_type >= int(r.count) and hostile_type > 0
	return true

## 0x40aaa0 finds the Building.cfg row of an id; its byte +0x100 + race is the BUILD side flag (catalogue "build_sides").
func race_can_build(player: int, code: String) -> bool:
	if UNBUILT_TARGETS.has(code): return false
	var rows = catalogue.get("building_cfg", {}).get("buildings", [])
	for row in rows:
		if row.code == code: return bool(row.build_sides[int(player_race[player])])
	return false

## 0x52edb0: the eligible enabled records in file order; 1d(n) - 1 picks one (match RNG); none eligible -> nothing.
func pick_quest(player: int, code: String = "BZMA") -> Variant:
	var candidates: Array = []
	for r in quest_records(code):
		if int(r.enabled) != 0 and eligible(player, r): candidates.append(r)
	if candidates.is_empty(): return null
	return candidates[combat.rng.roll(1, candidates.size(), -1)]

## Q-1: every type 0..9 is ported (0x43db30 progress, 0x43d3a0 completion); type 4 never completes, as in the original.
static func supported(r: Dictionary) -> bool:
	return int(r.type) >= 0 and int(r.type) <= 9

## 0x43d180: the hero arrives at the quest building. Returns {"mode": "none" | "busy" | "offer" | "instant" |
## "continue" | "complete" | "unsupported", "record": ...}.
func visit(player: int, building_id: int) -> Dictionary:
	var giver = givers.get(building_id)
	if giver == null or not quests_enabled: return {"mode": "none"}                    # S-2: 0x70ae0d, the offer gate
	if giver.resting and combat.now_ms >= int(giver.until_ms): giver.resting = false
	# +0x125 ("picked") is set only by an acceptance (0x52f730(0)); until then 0x43d180 calls 0x52edb0 on every visit, so the
	# offer is re-rolled each time (one 1d(n) draw when n >= 1 records are eligible, none otherwise).
	if not giver.picked:
		if giver.resting: return {"mode": "none"}
		var r = pick_quest(player, String(giver.get("code", "BZMA")))
		if r == null:
			quest_event.emit("%s has nothing to offer." % _giver_name(giver), {})
			return {"mode": "none"}
		giver.record = r
	var q = quests.get(player)
	if q != null and q.building == building_id:
		return {"mode": "complete" if completed(player, q.record, q.progress) else "continue", "record": q.record}
	if q != null: return {"mode": "busy", "record": q.record}
	var r: Dictionary = giver.record
	if not supported(r): return {"mode": "unsupported", "record": r}
	if int(r.type) == 0 and completed(player, r, 0): return {"mode": "instant", "record": r}
	return {"mode": "offer", "record": r}

## 0x43d350 -> 0x527660: the quest becomes the player's (deadline now + time limit; the deadline is only displayed,
## nothing in the code fails a quest when it passes); the giver keeps the record (0x52f730(0)).
func accept(player: int, building_id: int) -> bool:
	var giver = givers.get(building_id)
	if giver == null or giver.record == null or quests.has(player): return false
	var r: Dictionary = giver.record
	if not supported(r): return false
	quests[player] = {"record": r, "building": building_id, "progress": 0, "deadline_ms": combat.now_ms + int(r.time_limit_s) * 1000}
	giver.picked = true                                                                    # +0x125 = 1, +0x126 = 0
	quest_event.emit("Quest accepted: %s" % r.get("name", ""), {"record": r})
	return true

## 0x43d3a0 (Read): type 0 is complete when the player holds the count of the resource; 1, 2, 3, 5, 6, 7 and 8 when the
## active quest's progress reaches the count; 9 when the player owns a building of the target type (0x534020: the player's
## object list, kind 1, body type == target; a building still under construction is in the list); 4 never.
func completed(player: int, r: Dictionary, progress: int) -> bool:
	match int(r.type):
		0:
			var lane: int = RESOURCE_LETTERS.get(String(r.target), -1)
			return lane >= 0 and int(economy.resources(player)[lane]) >= int(r.count)
		4: return false
		9: return owns_building_type(player, String(r.target))
	return progress >= int(r.count)

func owns_building_type(player: int, code: String) -> bool:
	for b in production.buildings.values():
		if b.owner == player and String(b.original_type_id) == code: return true
	return false

## 0x43db30(event, player, object) (Read), the counter +0x744dc0 of the player's active quest. "player" is the acting
## player: the killer's owner (events 0 and 1), the converting player (2), the building's owner (3).
## * event 0, a unit died (0x5210b0; its caller skips animal victims, 0x528280, and needs a unit or building killer):
##   type 1 any victim of another, non-allied owner; 5 the same for a hero (+0xb4); 6 the same of the target type.
## * event 1, a building was destroyed (0x52b3e0; only when the building's owner is below 6, so the neutral player's
##   buildings never count, and the killer is a unit or building): type 2 a building of another, non-allied owner;
##   7 the same of the target type.
## * event 2, a building was converted (0x4a6cc0, before the owner changes): type 3 a building whose owner was not the
##   neutral player 6 and is not allied with p (the owner test is absent: one's own building is never converted);
##   type 9 a building of the target type (counted, though 0x43d3a0 tests ownership instead).
## * event 3, a building was finished (0x52bfd0): types 8 and 9 a building of the target type.
## The allied byte is 0x748915[p + owner * 7] = combat.allied(p, owner).
func quest_event_progress(event: int, player: int, owner: int, type_code: String, hero: bool = false):
	var q = quests.get(player)
	if q == null: return
	var t: int = int(q.record.type)
	var target := String(q.record.target)
	var hostile: bool = owner != player and not combat.allied(player, owner)
	match event:
		0:
			if t == 5 and hero and hostile: q.progress += 1
			if t == 1 and hostile: q.progress += 1
			if t == 6 and hostile and type_code == target: q.progress += 1
		1:
			if t == 2 and hostile: q.progress += 1
			if t == 7 and hostile and type_code == target: q.progress += 1
		2:
			if t == 3 and owner != NEUTRAL and not combat.allied(player, owner): q.progress += 1
			if t == 9 and type_code == target: q.progress += 1
		3:
			if (t == 9 or t == 8) and type_code == target: q.progress += 1

## The death hooks (kind "unit" / "building", the victim's id) -> events 0 and 1.
func quest_progress(player: int, kind: String, id: int):
	if kind == "unit":
		var victim = combat.fighters.get(id)
		if victim == null or UnitAI.is_animal(victim.type_id): return
		quest_event_progress(0, player, int(victim.owner), String(victim.type_id), bool(victim.get("hero", false)))
	elif kind == "building":
		var owner: int = int(last_building_owner.get(id, -1))
		if owner < 0 or owner >= NEUTRAL: return                                       # 0x52b3e0: owner < 6 only
		quest_event_progress(1, player, owner, String(last_building_type.get(id, "")))

var last_building_owner: Dictionary = {}
var last_building_type: Dictionary = {}

func note_building_owner(id: int, owner: int):
	last_building_owner[id] = owner

func _note_building(id: int):
	var b = production.building(id)
	if b != null: _note(b)

func _note(b):
	last_building_owner[b.entity_id] = int(b.owner)
	last_building_type[b.entity_id] = String(b.original_type_id)

## production.building_converted fires after the owner changed; 0x4a6cc0 calls 0x43db30(2, ...) before, with the old owner.
func _on_building_converted(id: int, previous: int):
	var b = production.building(id)
	if b == null: return
	quest_event_progress(2, int(b.owner), previous, String(b.original_type_id))
	_note_building(id)

func _on_building_completed(id: int):
	var b = production.building(id)
	if b == null: return
	quest_event_progress(3, int(b.owner), int(b.owner), String(b.original_type_id))

func _research_level(player: int, id: String) -> int:
	if production == null or not production.has_method("research_level"): return 0
	return int(production.research_level(player, id))

func _giver_name(giver) -> String:
	return {"BZMA": "The Mausoleum", "BMSH": "The Shrine"}.get(String(giver.get("code", "")), "The site")

## 0x43d560 at the giver: pay a delivered resource, then rewards: resources (+0x1e, gold/metal/crystal/stone), one unit
## (+0x1f) and a group (+0x20) of the player's at the hero's cell, an item (+0x22, 0x580d00 gives it to the hero); the
## hero gains 20 XP; the giver rests for the record's second word (0x52f730(1) / 0x52f7c0(0)).
var treasures                          # optional Treasures (milestone 11): quest items are dropped on the ground

func complete(player: int, building_id: int, hero_match = null, hero_cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var q = quests.get(player)
	var giver = givers.get(building_id)
	if q == null or giver == null or q.building != building_id or not completed(player, q.record, int(q.progress)): return {}
	return _reward(player, building_id, q.record, giver, hero_match, hero_cell, int(q.record.word_02) * 1000)

## The body of 0x43d560. `rest_ms`: 0x52f7c0(0) rests the giver for its record's +0xa2 seconds (the record's word +2), or
## 240 s when the building holds no record (+0x12c null: the computer's visit, Q-3).
func _reward(player: int, building_id: int, r: Dictionary, giver: Dictionary, hero_match, hero_cell: Vector2i, rest_ms: int) -> Dictionary:
	var paid: Array = [0, 0, 0, 0]
	if int(r.type) == 0:
		paid[RESOURCE_LETTERS[String(r.target)]] = int(r.count)
		economy.try_spend(player, paid)
	# The first loop of 0x43d560: every other player whose active quest is from the same giver (building id and owner)
	# loses it; the local one sees line 0xbc.
	for other in quests.keys():
		if int(other) == player or int(quests[other].building) != building_id: continue
		var lost: Dictionary = quests[other].record
		quests.erase(other)
		quest_lost.emit(int(other), lost)
	var xp: int = QUEST_XP_POGL if _research_level(player, "POGL") != 0 else QUEST_XP
	var reward := {"resources": [0, 0, 0, 0], "units": [], "item": -1, "xp": xp, "research": ""}
	if r.reward_resources:
		reward.resources = r.resources.map(func(v): return int(v))
		economy.credit(player, reward.resources)                                         # 0x1fd -> 0x43e9b0 (capped by the stockpile)
	# 0x43d560 (Read): the group's messages 0xfa go out first, then the single unit's. A group with +0x3e set names each
	# member from naming set +0x3f (0x434e90, simulation/naming_sets.gd; the rolls happen here, before any unit is made).
	# The single unit's name is copied from record +0x50, which lies inside the 160-byte NAME text (0x52edb0 builds the
	# record from local_90c) and is empty for every shipped quest: the single unit has no name.
	if r.reward_group and String(r.group_unit) != "":
		for i in int(r.group_count):
			var member := {"type": r.group_unit, "xp": int(r.group_xp)}
			if int(r.get("group_named", 0)) != 0: member["name"] = NamingSets.name_for(int(r.get("group_name_index", 0)), combat.rng)
			reward.units.append(member)
	if r.reward_unit and String(r.unit) != "":
		reward.units.append({"type": r.unit, "xp": int(r.unit_xp)})
	for u in reward.units:
		var cell: Vector2i = combat.navigator.free_cell_near(hero_cell)
		u["unit"] = spawn_unit.call(u.type, cell, player, int(u.xp)) if cell.x >= 0 else -1
		if u.has("name") and int(u.unit) >= 0 and combat.fighters.has(int(u.unit)): combat.fighters[int(u.unit)]["name"] = String(u.name)
	if r.reward_item and hero_match != null:
		reward.item = int(r.item)
		# 0x580d00 (milestone 11, Read): the item is put on the ground at the hero's cell as a treasure pile; the hero
		# takes it from the "Ground" list. Without a treasure world (older harnesses) it goes straight to the backpack.
		var source := "quest %s %d" % [String(giver.get("code", "BZMA")), int(r.index)]
		if treasures != null: treasures.drop(int(r.item), hero_cell, source)
		else: hero_match.receive_item(int(r.item), source)
	# +0x21: message 0xfb -> 0x438150 -> 0x436500, the research completes for the player (Read).
	if bool(r.get("reward_research", false)) and String(r.research) != "" and production != null and production.has_method("complete_research"):
		if production.complete_research(player, String(r.research)): reward.research = String(r.research)
	if hero_match != null: hero_match.award_xp(xp)
	quests.erase(player)
	giver.picked = false
	giver.record = null
	giver.resting = true
	giver.until_ms = combat.now_ms + rest_ms
	quest_event.emit("Quest complete: %s" % r.get("name", ""), {"record": r, "reward": reward, "player": player})
	return reward

# ------------------------------------------------------------------------------------------------ Q-3: computer visits
## QUESTS_RESEARCH.md "Q-3". 0x503c60 (simulation/ai_spells.gd) asks 0x5002e0(hero x, y, 2, 6, 0, 2, 4, 6, 1) for a quest
## building and hands the first one found to 0x504490. Emulated (tests/quest_ai_fixtures.json "site", the real 0x503c60 and
## 0x5002e0): the square of 2 cells around the hero's cell (map-clamped), any owner but **6** (0x5002e0 skips player 6's
## buildings: 0x5004b5..0x5004db), not rubble (second letter R), alive (hit points >= 1), searchable
## (0x52ed90 -> Building.cfg +0x7a), not resting (+0x126 set and +0x128 != now; the building update, update here, ends the
## rest at now >= +0x128: 0x52cf41, REVIEW_ENCOUNTERS.md), holding no offered record (+0x12c). The walk's order (grid rows, each row's list) picks
## among several such sites: Provisional (lowest row, then the higher id).
const COMPUTER_SITE_RADIUS := 2
const COMPUTER_REST_MS := 240000                   # 0x52f7c0(0) with +0x12c null: now + 240000
## 0x504490's tables (strings at 0x60f30c..0x60f42c, read from the image; Emulated: fixtures "reward").
const COMPUTER_RESEARCH := ["PFLA", "PME2", "PRG2", "PMR2", "PSIE", "PMAS", "PMO2", "PMIT", "PHOC", "PRE1"]   # 1d10
const COMPUTER_UNIT := ["AAAR", "AADE", "AAEA", "AAEF", "AAEE", "AUGX", "AOGX", "AEGX", "AVGX", "AHGR", "AONX", "AWGX",
	"AEAX", "AAAR", "AADE"]                                                                                      # 1d15
const COMPUTER_GROUP := ["AKCX", "AAHA", "AASP", "AAIM", "ADMX", "AUKX", "AOIX", "AEMX", "AMIX", "AHMX", "AOSX", "AEXX",
	"AEBX", "AHGW", "AAIM"]                                                                                      # the same 1d15

func computer_site(cell: Vector2i, now_ms: int) -> int:
	var found := -1
	var best := Vector2i(0, 0)
	for id in production.buildings:
		var b = production.buildings[id]
		var code := String(b.original_type_id)
		if int(b.owner) == NEUTRAL or (code.length() > 1 and code[1] == "R"): continue
		if int(b.hit_points) < 1 or not is_quest_site(code): continue
		var giver = givers.get(id)
		if giver != null and ((bool(giver.resting) and now_ms != int(giver.until_ms)) or giver.record != null): continue
		var c := _building_cell(int(id), b)
		if absi(c.x - cell.x) > COMPUTER_SITE_RADIUS or absi(c.y - cell.y) > COMPUTER_SITE_RADIUS: continue
		if found < 0 or c.y < best.y or (c.y == best.y and int(id) > found):
			found = int(id)
			best = c
	return found

func _building_cell(id: int, b) -> Vector2i:
	var spells = combat.get("spells") if combat is Object else null
	if spells != null:
		var o: Dictionary = spells.object_of("building", id)
		if not o.is_empty(): return o.cell
	return Vector2i(int(b.left), int(b.top))

## 0x504490 (Emulated: fixtures "reward"): three rolls, 1d100, 1d10, 1d15. Below 10 a research (the 1d10's id); 10..59 a
## group; 60..89 one unit; 90 and above a unit and a group. The unit (1d15's id) gains 4d20 XP; the group (the same 1d15's
## id) has 2d4+2 members, halved for the 14th (AHGW), with 4d8 XP. Rolls in that order: unit XP, group count, group XP.
## The record: type 4, count 1, no resources, no item, no group name. `roll`: (count, sides, bonus) -> 0x458e70.
static func computer_record(roll: Callable) -> Dictionary:
	var pick: int = roll.call(1, 100, 0)
	var research_roll: int = roll.call(1, 10, 0)
	var kind: int = roll.call(1, 15, 0)
	var r := {"index": -1, "name": "", "type": 4, "count": 1, "target": "", "word_02": 0, "reward_resources": false,
		"reward_unit": false, "reward_group": false, "reward_research": false, "reward_item": false, "resources": [0, 0, 0, 0],
		"unit": "", "unit_xp": 0, "group_count": 0, "group_unit": "", "group_xp": 0, "group_named": 0, "group_name_index": 0,
		"research": "", "item": 0, "computer": true}
	if pick < 10: r.reward_research = true
	elif pick < 60: r.reward_group = true
	else:
		r.reward_unit = true
		if pick > 89: r.reward_group = true
	if r.reward_research and research_roll >= 1 and research_roll <= 10: r.research = COMPUTER_RESEARCH[research_roll - 1]
	if r.reward_unit:
		if kind >= 1 and kind <= 15: r.unit = COMPUTER_UNIT[kind - 1]
		r.unit_xp = roll.call(4, 20, 0)
	if r.reward_group:
		r.group_count = roll.call(2, 4, 2)
		if kind >= 1 and kind <= 15:
			r.group_unit = COMPUTER_GROUP[kind - 1]
			if kind == 14: r.group_count = int(r.group_count) / 2                      # (short) / 2, the count is 4..10
		r.group_xp = roll.call(4, 8, 0)
	return r

## 0x504490 -> 0x43d560: the made-up quest replaces the player's active one (progress 1, giver id) and is rewarded at once
## (no completion test), the giver rests 240 s. Returns the reward (empty when the building is gone).
func computer_visit(player: int, building_id: int, roll: Callable, hero_match = null, hero_cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var b = production.buildings.get(building_id)
	if b == null: return {}
	if not givers.has(building_id): givers[building_id] = _giver(String(b.original_type_id))
	var r := computer_record(roll)
	quests[player] = {"record": r, "progress": 1, "building": building_id}
	var reward := _reward(player, building_id, r, givers[building_id], hero_match, hero_cell, COMPUTER_REST_MS)
	log.append({"t": combat.now_ms, "computer_quest": player, "building": building_id, "reward": reward})
	return reward

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). The data tables are the assets'. Map
## placements taken out of the shared collision data ("released") are taken out again from the fresh map's data.
const _SAVE_SKIP := ["combat", "production", "economy", "collision", "catalogue", "data", "lair_table", "xp_levels", "spawn_unit", "treasures"]

func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self, _SAVE_SKIP)

func load_state(state: Dictionary, _refs = null):
	restore_static()
	preload("res://simulation/save_game.gd").restore(self, state, _SAVE_SKIP)
	for pair in released:
		var c: Dictionary = collision.cell_data(pair[0])
		if c.has("object_indices"): c.object_indices.erase(pair[1])
