extends RefCounted
## Hero spells (B1-6a, SPELLS_RESEARCH.md section "B1-6a"). Labels: Emulated = tests/hero_spell_fixtures.json
## (tools/emulate_hero_spells.py, the unmodified executable under Unicorn); Read = decompile read only; Open.
##
## * The human cast path `cast_request` = 0x5717e0 (the spell book's rows, its digit keys and the hero hot keys F1..F8):
##   the mana check against 0x529fa0, the school rank 0x51c390, the cast level and chance 0x40aae0, the level roll (each
##   failed 1..100 roll against the chance drops one level and adds 50 to the chance; all failed = level -1), the
##   targeting 0x570f80 (mode 0 at once, 8 a summon cell, 7 a building placement, 11 / 13 a choice dialog), message 0x118
##   -> 0x577730 -> unit order 9 (`Spells.order_cast`) -> event 7 -> the dispatcher (`Spells.dispatch`).
## * The schools (one builder per spell id, BUILDERS; the shared applier is SpellEffects): Necromancy 40-49 and Runes
##   70-79 here. Call the Dead (47), Doomstones (75) and Stonecall (79) are B1-4's builders (spells.gd).
## * Hero hot keys: eight spell slots (hero record +0x170, 0x74c37c / 0x709e3c; 0x4258a0 assigns, removing duplicates).

const SpellEffects = preload("res://simulation/spell_effects.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")
const Placement = preload("res://simulation/placement.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")

const SCHOOLS_BUILT := [0, 4, 5, 7, 8, 10, 2, 11, 12, 1, 3, 6, 9]   # B1-6a Necromancy, Runes; B1-6b Healing, Pyromancy, Ice, Poison; B1-6c Nature, Divination, Arcane; B1-6d Summoning, Illusion; B1-6e Alchemy, Chaos (all 13)
const BUILDERS := {40: "_raise_skeleton", 41: "_raise_zombie", 42: "_black_portal", 43: "_raise_wight", 44: "_vampirism",
	45: "_darkstorm", 46: "_strip_flesh", 48: "_ring_of_ice", 49: "_raise_champion",
	70: "_stoneskin", 71: "_gem_of_wisdom", 72: "_dig", 73: "_earthpower", 74: "_resist_magic", 76: "_summon_guardian",
	77: "_resist_missile", 78: "_rune_item",
	# B1-6b (tests/hero_spell_b_fixtures.json): Healing, Pyromancy, Ice, Poison
	0: "_heal_self", 2: "_blessing", 3: "_white_ward", 4: "_heal_group", 5: "_invigorate", 6: "_purify", 7: "_major_healing",
	8: "_life_ward", 9: "_resurrection",
	50: "_hand_of_flame", 51: "_soul_flame", 52: "_cauterize", 53: "_resist_fire", 55: "_firebreath", 56: "_berserker",
	57: "_pillar_of_fire", 59: "_armageddon",
	80: "_hand_of_ice", 81: "_storm", 82: "_ice_armor", 83: "_calm", 84: "_ring_of_ice", 85: "_freeze", 86: "_wall_of_ice",
	87: "_ice_floe", 88: "_freeze_magic", 89: "_ice_storm",
	100: "_immunity", 101: "_poison_cloud", 102: "_summon_wasp", 103: "_antidote", 104: "_venom_touch", 105: "_poison_gate",
	106: "_spray_poison", 107: "_guardian_naga", 108: "_rot", 109: "_call_of_kargoth",
	# B1-6c (tests/hero_spell_c_fixtures.json): Nature
	20: "_summon_sprite", 21: "_gemberry", 22: "_entangle", 23: "_shillelagh", 24: "_summon_unicorn", 25: "_wall_of_thorns",
	26: "_call_lightning", 27: "_summon_treant", 28: "_change_weather", 29: "_elementalism",
	# Divination (Banish 114 is Summoning's 18 too: the same function 0x581e70, Emulated in both cast paths)
	110: "_elemental_lore", 111: "_defense_lore", 112: "_see_invisible", 113: "_telepathy", 114: "_banish", 18: "_banish",
	115: "_comprehension", 116: "_call_sage", 117: "_mind_leech", 118: "_true_sight", 119: "_psychic_blast",
	# Arcane
	120: "_concentration", 121: "_command", 122: "_enervate", 123: "_extend", 124: "_mana_flow", 125: "_corruption",
	126: "_dispel", 127: "_mana_leech", 128: "_empower", 129: "_destruction",
	# B1-6d (tests/hero_spell_d_fixtures.json): Summoning (Banish 18 above; Summon Imp 14 is B1-4's)
	10: "_summon_quasit", 11: "_circle_of_power", 12: "_phantom_steed", 13: "_blink", 15: "_eye_of_oros", 16: "_home_portal",
	17: "_soulharvest", 19: "_daemongate",
	# Illusion
	30: "_shadowform", 31: "_scare", 32: "_light_darkness", 33: "_awe", 34: "_spectral_horde", 35: "_dragonfear",
	36: "_invisibility", 37: "_call_shadow", 38: "_mutate", 39: "_transform",
	# B1-6e (tests/hero_spell_e_fixtures.json): Alchemy
	60: "_create_item", 61: "_transmute", 62: "_charm", 63: "_stone_golem", 64: "_brew_potion", 65: "_acquire",
	66: "_summon_guardian_66", 67: "_disjunction", 68: "_bronze_golem", 69: "_spellforge",
	# Chaos
	90: "_morph_combat", 91: "_morph_speed", 92: "_morph_health", 93: "_morph_damage", 94: "_morph_tower", 95: "_drain_mana",
	96: "_morph_resources", 97: "_increase_casting", 98: "_wildfire", 99: "_chaos_plague"}
## B1-6e: the spells whose functions send no record (the drop, the trade dialog): a cast without one is not a refusal.
const NO_RECORD := [78, 60, 61, 96]
## Spells whose builders are B1-4's (spells.gd BUILDERS): Call the Dead, Doomstones, Stonecall; B1-6b: Cure (1), Ring of
## Fire (54), Fire Elemental (58); B1-6d: Summon Imp (14) (the same functions the batch-1 casters use, Emulated with a hero
## caster).
const FRAMEWORK_BUILT := [47, 75, 79, 1, 54, 58, 14]
const HOTKEYS := 8

## 0x570f80 (Read; the Necromancy and Runes rows Emulated through 0x5717e0 in the fixtures' cast_path):
## mode 8 with the nearest building of a type within the hero's radius (+1 level and the summon next to it when found,
## else the hero's cell + two rolls of 1..5 - 3), mode 8 at the hero's cell + two rolls, mode 7 a building placement,
## 9 / 10 / 11 / 13 dialogs. The mode-8 command check type (DAT_00bbf738) per id. B1-7: 0x570f80 sets 0xbbf738 for the local
## player's casts only, so the original checks a computer's summon against the human's last summon type (Emulated,
## REVIEW_AI_SPELLS.md R5); the port checks the summon's own type. No visible difference: slots G / H need used <= limit - 4
## and no stored type costs more than 4 points.
const SEARCH_SUMMON := {10: "BMCP", 0xe: "BMCP", 0x11: "BMCP", 0x13: "BMCP", 0x28: "BMBP", 0x29: "BMBP", 0x2b: "BMBP", 0x31: "BMBP"}
const ROLL_SUMMON := [0xf, 0x14, 0x18, 0x1b, 0x22, 0x23, 0x25, 0x3a, 0x3f, 0x44, 0x4f, 0x66, 0x6b, 0x6d, 0x74]
const PLACE := {0xb: "BMCP", 0x19: "BWBR", 0x2a: "BMBP", 0x56: "BWIC"}   # + 0x42 / 0x4c: BWGC / BWGS / BWGI by level
const CHECK_TYPE := {10: "AVBX", 0xe: "AAIM", 0xf: "AAEY", 0x11: "AVIX", 0x13: "AADE", 0x14: "AASP", 0x18: "AEDX",
	0x1b: "AWJX", 0x1d: "AAEA", 0x22: "AHKX", 0x23: "AADR", 0x25: "AUXX", 0x28: "AUIX", 0x2f: "AUIX", 0x29: "AUBX",
	0x2b: "AUJX", 0x31: "AUGX", 0x3a: "AAEF", 0x3f: "AAIX", 0x44: "AAGX", 0x4f: "AAEE", 0x66: "AAWA", 0x6b: "ALGX",
	0x6d: "AKLX", 0x74: "AHGW"}
const MODE_NOW := 0
const MODE_PLACE := 7
const MODE_SUMMON := 8
const MODE_CHAMPION := 11             # 0x5717e0 case 0xb: the four champions (DAT_0061b538 AUXX AUMX AUGX AUAX)
const MODE_RUNE := 13                 # 0x5717e0 case 0xd -> 0x5720b0: four items
const MODE_WEATHER := 9               # B1-6c: 0x5717e0 case 9: Change Weather's dialog (EWTH x 4)
const MODE_ELEMENTAL := 10            # B1-6c: 0x5717e0 case 10: Elementalism's dialog (DAT_0061b4f8)
const ELEMENTALS := ["AAEA", "AAEE", "AAEF", "AAEW"]   # 0x61b4f8: air, earth, fire, water (0x57dd20 switch on the pick)
const CHAMPIONS := ["AUXX", "AUMX", "AUGX", "AUAX"]
const STATUS_VAMPIRISM := 0x3c        # 0x526f40 life drain
const STATUS_DIG := 0x3f              # 0x40b6b0 building time - n %
const STATUS_RESIST_MAGIC := 0x51     # 0x525c80 armour word 4 (magic)
const STATUS_RESIST_MISSILE := 0x52   # 0x527040 -> 0x5427e0 (missile damage / 16)
const STATUS_RESIST_FIRE := 0x50      # 0x525c80 armour word 3
const STATUS_RESIST_ICE := 0x58       # 0x525c80 armour word 1
const STATUS_RESIST_LIGHTNING := 0x59 # 0x525c80 armour word 2
const STATUS_CHARM := 0xb             # B1-6e: 0x526cf0 (the hero's price value) adds it (Charm)
const STATUS_DISJUNCTION := 0x7f      # B1-6e: 0x40c380 / 0x40c500 give other players' item powers 0
const STATUS_SPELLFORGE := 0x80       # B1-6e: 0x40c380 / 0x40c500 double the player's item powers

var _spells: WeakRef
var spells:
	get: return _spells.get_ref() if _spells != null else null
	set(value): _spells = weakref(value) if value != null else null
var gem: Dictionary = {}              # 0x70d54c: owner -> Gem of Wisdom chance bonus (cleared by the next paid hero cast)
var pending: Dictionary = {}          # the local pending cast (0xbbf5d8) of a placement or a dialog
var rune_choice: Dictionary = {}      # 0xbbf744: owner -> the Rune Item pick (0..3)
var timed_buildings: Dictionary = {}  # building id -> ms (0x1f9 duration -> building +0x120; 0x52cd77 removes it)
var hotkeys: Dictionary = {}          # owner -> eight spell ids (-1 empty)
var casts: Dictionary = {}            # owner -> hero casts (0x518a10 case 6: 0x70933a, the results' spells cast)

func _init(owner_spells):
	spells = owner_spells

func combat():
	return spells.combat

func has_builder(spell: int) -> bool:
	return BUILDERS.has(spell)

## Whether the rebuild can cast `spell` yet (the other eleven schools come in later parts).
static func castable(spell: int) -> bool:
	return BUILDERS.has(spell) or spell in FRAMEWORK_BUILT

func build(spell: int, caster: Dictionary, level: int, target: Dictionary) -> Dictionary:
	return call(String(BUILDERS[spell]), caster, level, target)

# ------------------------------------------------------------------------------------------------ ranks and level
## 0x709300 (0x54fd50): the hero's thirteen school ranks (skills 10..22 + item powers); [] without a hero block.
func schools(owner: int) -> Array:
	var block: Dictionary = combat().hero_block(owner)
	if block.is_empty(): return []
	return Array(HeroEffects.hero_unit(block).schools)

## 0x51c390 (Read): a non-hero (or a player past 6) has rank 10 in every school; a hero its player's rank.
func school_rank(f, school: int) -> int:
	if not f.hero or int(f.owner) >= 7: return 10
	var s := schools(int(f.owner))
	return int(s[school]) if school >= 0 and school < s.size() else 0

## 0x40c6b0 (Read): another player than the local one knows every spell; else the level of spell i with rank r is
## r / 10 (+ 1 when i % 10 < r % 10), 0 = unknown.
func known_level(owner: int, spell: int, local_player: int) -> int:
	if owner != local_player or spells.cheat: return 1
	var s := schools(owner)
	var school := spell / 10
	if school < 0 or school >= s.size(): return 0
	var rank := int(s[school])
	return rank / 10 + (1 if spell % 10 <= rank % 10 - 1 else 0)

## 0x40aae0 (Emulated, fixtures "chance"): {ok, level, chance}. The cheat gives level 1 at 100 %; without a living hero, or
## when the spell's slot i % 10 is not below the rank, ok is false. level = rank / 10 + 1, or rank / 10 when rank % 10 <=
## i % 10; chance = (2 - level) x 50 + 0x54a6a0(11) (Intelligence x 3) + 0x51c2d0 + 0x70d54c + 50 for a computer, at most 100.
func cast_level(owner: int, rank: int, spell: int) -> Dictionary:
	if spells.cheat: return {"ok": true, "level": 1, "chance": 100}
	var h = spells._hero_fighter(owner)
	if h == null or int(h.hp) < 1: return {"ok": false, "level": 0, "chance": 0}
	if spell % 10 >= rank: return {"ok": false, "level": 0, "chance": 0}
	var level := rank / 10 + 1
	if rank % 10 <= spell % 10: level = rank / 10
	var block: Dictionary = combat().hero_block(owner)
	var chance := (2 - level) * 50 + HeroRules.derived(block.get("stats", [0, 0, 0, 0]), 11, 1) + chance_terms(h, block)
	chance += int(gem.get(owner, 0))
	if combat().ai_players.has(owner): chance += 50
	return {"ok": true, "level": level, "chance": mini(chance, 100)}

## 0x51c2d0 (Read; the fixtures' Ritual case Emulated): item powers and effects 0x61 and 0x1c, the Ritual skill (7) x 5
## and 10 per PMEX level.
func chance_terms(h, block: Dictionary) -> int:
	if not h.hero: return 0
	var v: int = HeroEffects.item_stat(block, 0x61) + spells.status_value(h, 0x61) + HeroEffects.item_stat(block, 0x1c) + spells.status_value(h, 0x1c)
	v += HeroEffects.skill_effect(block, 7)
	var pmex: int = spells.production.research_level(int(h.owner), "PMEX") if spells.production != null else 0
	return v + pmex * 10

## 0x5717e0's loop (Emulated): while the level is above 0 a 1..100 roll <= chance casts at that level, else the level drops by
## one and the chance rises by 50; -1 when no level is left.
func level_roll(level: int, chance: int) -> int:
	while level > 0:
		if spells.roll(1, 100, 0) <= chance: return level
		level -= 1
		chance += 50
	return -1

# ------------------------------------------------------------------------------------------------ the cast path
## 0x5717e0 (Emulated: fixtures "cast_path"): the hero's cast request. Returns {"cast": true} when an order went out,
## {"pending": "place" | "champion" | "rune"} while the placement or a dialog waits for the player, else {"cast": false,
## "reason"}. Nothing is paid here; the dispatcher pays at the cast animation's event (also for a failed level).
func cast_request(hero_id: int, spell: int) -> Dictionary:
	var c = combat()
	var f = c.fighters.get(hero_id)
	if f == null or not c.alive(f): return {"cast": false, "reason": "no caster"}
	if not castable(spell): return {"cast": false, "reason": "not built yet"}    # Temporary: the other eleven schools
	var owner := int(f.owner)
	var price: int = spells.cost(f, spell)
	if not spells.cheat and spells.hero_pool(owner) < price:
		# 0x50f2c0(1) for the local player's hero only (B1-7: a computer hero's request returns 0 silently)
		if owner == int(spells.production.local_player): spells.notice.emit("Not enough mana")
		return {"cast": false, "reason": "mana"}
	var lv := cast_level(owner, school_rank(f, spell / 10), spell)
	var level := level_roll(int(lv.level), int(lv.chance))
	var t := targeting(spell, f, level)
	# DELIBERATE MODERN FIX (B1-7, labelled; COMPLAINTS_AND_FIXES.md F11): only the local player's request touches the local
	# pending cast. The original writes 0xbbf5d8 for a computer's mode-8 summon too (Emulated, REVIEW_AI_SPELLS.md R1), and the
	# human's open placement or dialog then completes with the computer's caster and spell. No computer spell reaches the
	# placement or dialog modes below (AI_RESEARCH.md H5), so a computer request neither reads nor writes `pending`.
	if owner == int(spells.production.local_player): pending = {}
	match int(t.mode):
		MODE_SUMMON:
			if not spells.command_free(owner, String(CHECK_TYPE.get(spell, ""))): return {"cast": false, "reason": "command"}
			return order(f, spell, level + int(t.found), {"x": t.cell.x, "y": t.cell.y, "id": -1, "extra": 0})
		MODE_PLACE:
			pending = {"mode": "place", "spell": spell, "unit": hero_id, "owner": owner, "level": level, "type": String(t.type),
				"radius": placement_radius(owner), "center": c.unit_cell(hero_id)}
			return {"pending": "place", "type": String(t.type)}
		MODE_CHAMPION:
			pending = {"mode": "champion", "spell": spell, "unit": hero_id, "owner": owner, "level": level + int(t.found), "cell": t.cell,
				"choices": CHAMPIONS.duplicate()}
			return {"pending": "champion"}
		MODE_RUNE:
			pending = {"mode": "rune", "spell": spell, "unit": hero_id, "owner": owner, "level": level, "choices": rune_items(level)}
			return {"pending": "rune"}
		MODE_WEATHER:
			# B1-6c: 0x5717e0 case 9 (Emulated: the dialog 0x55bc90(spell 28's name, EWTH x 4, LAB_00571db0)): the pick goes
			# to 0xbbf5e8 = the target's +4, which the dispatcher hands Change Weather as its amount.
			pending = {"mode": "weather", "spell": spell, "unit": hero_id, "owner": owner, "level": level, "choices": [0, 1, 2, 3]}
			return {"pending": "weather"}
		MODE_ELEMENTAL:
			# B1-6c: 0x5717e0 case 10 (Emulated: 0x55bc90(spell 29's name, AAEA AAEE AAEF AAEW, LAB_00571df0)): the rolled cell
			# of 0x570f80 is kept, the pick goes to 0xbbf5f0 = the target's +0xc (as Raise Champion's).
			pending = {"mode": "elemental", "spell": spell, "unit": hero_id, "owner": owner, "level": level, "cell": t.cell,
				"choices": ELEMENTALS.duplicate()}
			return {"pending": "elemental"}
		MODE_NOW:
			return order(f, spell, level, {})
	return {"cast": false, "reason": "dialog not built yet"}

## Message 0x118 -> 0x577730 -> 0x51d3b0 (Read): the order of the pending cast.
func order(f, spell: int, level: int, target: Dictionary) -> Dictionary:
	var ok: bool = spells.order_cast(int(f.id), spell, level, target)
	return {"cast": ok, "spell": spell, "level": level, "target": target}

## 0x570f80 for the spell (Read, rows Emulated as above): {mode, cell, found, type}.
func targeting(spell: int, f, level: int) -> Dictionary:
	var c = combat()
	var hero_cell: Vector2i = c.unit_cell(int(f.id))
	var out := {"mode": MODE_NOW, "cell": Vector2i.ZERO, "found": 0, "type": ""}
	if SEARCH_SUMMON.has(spell):
		out.mode = MODE_CHAMPION if spell == 0x31 else MODE_SUMMON
		var near = nearest_building(String(SEARCH_SUMMON[spell]), hero_cell, mini(19, spells.radius_base(f)))
		if not near.is_empty():
			out.found = 1
			out.cell = spells.navigator.free_cell_near(_clamped(near.cell))
		else:
			out.cell = _rolled_cell(hero_cell)
	elif spell in ROLL_SUMMON:
		out.mode = MODE_SUMMON
		out.cell = _rolled_cell(hero_cell)
	elif spell == 0x2f:
		out.mode = MODE_SUMMON                                  # Call the Dead: the cell stays (0, 0)
	elif PLACE.has(spell):
		out.mode = MODE_PLACE
		out.type = String(PLACE[spell])
	elif spell == 0x42 or spell == 0x4c:
		out.mode = MODE_PLACE
		out.type = "BWGC" if level < 2 else ("BWGS" if level == 2 else "BWGI")
	elif spell == 0x4e:
		out.mode = MODE_RUNE
	elif spell == 0x1c:
		out.mode = MODE_WEATHER
	elif spell == 0x1d:
		out.mode = MODE_ELEMENTAL                               # B1-6c: the rolled cell as mode 8 (no building search)
		out.cell = _rolled_cell(hero_cell)
	return out

## Two 1..5 - 3 rolls (x first), then the free-cell finder 0x43b4c0 (navigator.free_cell_near).
func _rolled_cell(cell: Vector2i) -> Vector2i:
	var dx: int = spells.roll(1, 5, -3)
	var dy: int = spells.roll(1, 5, -3)
	return spells.navigator.free_cell_near(_clamped(cell + Vector2i(dx, dy)))

## 0x43b4c0 clamps the cell into the map before its search (REVIEW_HERO_SPELLS D5, Read).
func _clamped(cell: Vector2i) -> Vector2i:
	var size: Vector2i = spells.map_size()
	return Vector2i(clampi(cell.x, 0, size.x - 1), clampi(cell.y, 0, size.y - 1))

## 0x548c30 (Read; its use Emulated with a Black Portal in the fixtures): the nearest object of the type within the radius,
## any owner; rows from y + r down to y - r, each row in x order, the first at the smallest dx^2 + dy^2 wins.
func nearest_building(type_id: String, cell: Vector2i, radius: int) -> Dictionary:
	var best := {}
	var best_d := 200000
	var found: Array = []
	for id in spells.production.buildings:
		var o: Dictionary = spells.object_of("building", int(id))
		if o.is_empty() or String(o.get("code", "")) != type_id: continue
		found.append(o)
	found.sort_custom(func(a, b): return a.cell.y > b.cell.y if a.cell.y != b.cell.y else a.cell.x < b.cell.x)
	for o in found:
		var d: Vector2i = o.cell - cell
		var d2 := d.x * d.x + d.y * d.y
		if d2 <= radius * radius and d2 < best_d:
			best = o
			best_d = d2
	return best

## 0x5717e0 case 7: the placement cursor 0x425150(9, type, r, hero cell) with r = 5 without a living hero, else
## min(19, 0x5267b0) of the local player's hero.
func placement_radius(owner: int) -> int:
	var h = spells._hero_fighter(owner)
	if h == null or int(h.hp) < 1: return 5
	return mini(19, spells.radius_base(h))

## The placement click (Read: the cursor's click handler sends 0x118 with the cell at +0x14 / +0x16): inside the radius of
## the hero and on a cell the building fits (Placement.check; Provisional, the cursor's own test 0x496520 is not traced).
func place(cell: Vector2i) -> Dictionary:
	if pending.get("mode", "") != "place": return {"cast": false, "reason": "nothing pending"}
	var c = combat()
	var f = c.fighters.get(int(pending.unit))
	if f == null or not c.alive(f):
		pending = {}
		return {"cast": false, "reason": "no caster"}
	var centre: Vector2i = pending.center          # the cell 0x425150 received at the cast request (REVIEW D4)
	var d: Vector2i = cell - centre
	var r := int(pending.radius)
	if d.x * d.x + d.y * d.y > r * r: return {"cast": false, "reason": "too far"}
	var definition: Dictionary = spells.production.rules.definition(String(pending.type))
	if definition.is_empty() or not Placement.check_top(spells.navigator, definition, cell.x, cell.y).ok: return {"cast": false, "reason": "blocked"}
	var p := pending
	pending = {}
	return order(f, int(p.spell), int(p.level), {"x": cell.x, "y": cell.y, "id": -1, "extra": 0})

## A dialog pick (LAB_00571df0 / LAB_00572350: a negative pick cancels): Raise Champion sends the champion index at the
## target's +0xc, Rune Item stores the pick in 0xbbf744 for the builder.
func choose(index: int) -> Dictionary:
	var mode := String(pending.get("mode", ""))
	if not mode in ["champion", "rune", "weather", "elemental"]: return {"cast": false, "reason": "nothing pending"}
	var p := pending
	pending = {}
	if index < 0 or index > 3: return {"cast": false, "reason": "cancelled"}
	var f = combat().fighters.get(int(p.unit))
	if f == null or not combat().alive(f): return {"cast": false, "reason": "no caster"}
	if mode == "rune":
		rune_choice[int(p.owner)] = index
		return order(f, int(p.spell), int(p.level), {})
	if mode == "weather": return order(f, int(p.spell), int(p.level), {"id": index})    # B1-6c: the target's +4
	var cell: Vector2i = p.cell
	return order(f, int(p.spell), int(p.level), {"x": cell.x, "y": cell.y, "id": -1, "extra": index})

func cancel_pending():
	pending = {}

## 0x5720b0 (Emulated, fixtures "rune_item"): the four items of the level clamped to 1..5: level + 19, + 24, + 29, + 34
## (rune sword, helm, shield, mail).
static func rune_items(level: int) -> Array:
	var l := clampi(level, 1, 5)
	return [l + 19, l + 24, l + 29, l + 34]

# ------------------------------------------------------------------------------------------------ hot keys
## The profile's eight slots (hero record +0x170, copied to 0x74c37c / 0x709e3c at the match start; Read).
func set_hotkeys(owner: int, slots: Array):
	var out: Array = []
	for i in HOTKEYS: out.append(int(slots[i]) if i < slots.size() else -1)
	hotkeys[owner] = out

func hotkey_slots(owner: int) -> Array:
	if not hotkeys.has(owner):
		var profile = _profile(owner)
		set_hotkeys(owner, profile.data.get("spell_hotkeys", []) if profile != null else [])
	return hotkeys[owner]

func _profile(owner: int):
	var heroes: Dictionary = combat().heroes
	if not heroes.has(owner) or heroes[owner].match == null: return null
	return heroes[owner].match.profile

## 0x4258a0 (Read): slot i takes the spell; the spell leaves any other slot; both the runtime copy (0x74c37c) and the
## hero's (0x709e3c, written back with the hero) change.
func assign_hotkey(owner: int, slot: int, spell: int):
	var s := hotkey_slots(owner)
	for i in HOTKEYS:
		if int(s[i]) == spell: s[i] = -1
	if slot >= 0 and slot < HOTKEYS: s[slot] = spell
	var profile = _profile(owner)
	if profile != null: profile.data["spell_hotkeys"] = s.duplicate()

## Keys F1..F8 = 0x10a..0x111 (0x459c60) outside the book (Read, 0x427fb0): the slot's spell when its slot holds one and
## 0x40c6b0 knows it, cast by the local player's hero through 0x5717e0.
func hotkey(owner: int, slot: int, hero_id: int, local_player: int) -> Dictionary:
	var s := hotkey_slots(owner)
	if slot < 0 or slot >= HOTKEYS or int(s[slot]) < 0: return {"cast": false, "reason": "empty"}
	if known_level(owner, int(s[slot]), local_player) == 0: return {"cast": false, "reason": "unknown"}
	return cast_request(hero_id, int(s[slot]))

# ------------------------------------------------------------------------------------------------ the match tick
## Called by Spells.step: timed buildings (0x52cd77: removed once now passes +0x120) and the Dig effect for the build time
## (0x40b6b0: the living hero's strongest effect 0x3f, production.hero_build_skill).
func step(now: int):
	for id in timed_buildings.keys():
		if now <= int(timed_buildings[id]): continue
		timed_buildings.erase(id)
		var b = spells.production.building(int(id))
		if b != null and b.hit_points > 0 and String(b.original_type_id) == "BMEG": combat().hatch_egg(b)   # B4-1 (E6): the Queen's egg
		elif b != null and b.hit_points > 0: combat()._kill_building(b, -1)
	for owner in combat().heroes:
		var h = spells._hero_fighter(int(owner))
		spells.production.hero_build_skill[int(owner)] = spells.status_value(h, STATUS_DIG) if h != null else 0
	sync_item_factors()                               # B1-6e: Spellforge / Disjunction (0x40c380 / 0x40c500)

# ------------------------------------------------------------------------------------------------ Necromancy (40-49)
## Every builder (Emulated, fixtures "spells"): the record of its spell function as tests/hero_spell_fixtures.json names
## the fields, {} when the function sends nothing. Summons: the function's own command check 0x5776c0(owner, type);
## experience 0x557d90 (0 in the rebuild, BATCH1 R8) + (level - 1) x step; every cell the target cell.
func _summon(caster: Dictionary, level: int, target: Dictionary, type_id: String, count: int, step: int, art: int, sound: int, extra := {}) -> Dictionary:
	var owner: int = spells.object_of(String(caster.kind), int(caster.id)).get("owner", 0)
	if not spells.command_free(owner, type_id): return {}
	var cell := Vector2i(int(target.get("x", 0)), int(target.get("y", 0)))
	var cells: Array = []
	for i in count: cells.append(cell)
	var fields := {"b6": art, "sound": sound, "effect2": "EZ08", "kind": SpellEffects.SUMMON, "amount": count, "w9b": spells.summon_start(owner, type_id) + (level - 1) * step,
		"w9d": 1, "summon": type_id, "cells": cells}
	fields.merge(extra, true)
	if int(fields.kind) == SpellEffects.ILLUSIONS: fields.w9b = (level - 1) * step   # R-1: 0x57cab0 / 0x57ccd0 call 0x557d90(.., 0, 0, 0): 0
	return spells._record(caster, fields)

## 0x57dec0 Raise Skeleton (40): level + 1 Skeletons.
func _raise_skeleton(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AUIX", level + 1, 5, 0xd, 0x10)

## 0x57e010 Raise Zombie (41): level Zombies.
func _raise_zombie(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AUBX", level, 5, 0xe, 0x10)

## 0x57e350 Raise Wight (43): one Wight, experience (level - 1) x 20.
func _raise_wight(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AUJX", 1, 20, 0x11, 0x10)

## 0x57ea70 Raise Champion (49): the dialog's pick (target +0xc) of the Shadow, Liche, Vampire or Abomination.
func _raise_champion(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var pick := int(target.get("extra", 0))
	if pick < 0 or pick > 3: return {}
	return _summon(caster, level, target, String(CHAMPIONS[pick]), 1, 20, 0x16, 0x11)

## 0x57e260 Black Portal (42): kind 7, a BMBP at the placement cell for vtable +0x68(2, level - 1) = (level + 1) x 60 s.
func _black_portal(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	return spells._record(caster, {"b6": 0x10, "sound": 0x13, "d89": spells.duration(f, 2, level - 1), "effect2": "EZ05",
		"kind": SpellEffects.BUILDING, "summon": "BMBP", "cells": [Vector2i(int(target.get("x", 0)), int(target.get("y", 0)))]})

## 0x57e490 Vampirism (44): own units within vtable +0x64(level - 1), the caster too, not STATUS 0x44000, get effect 0x3c
## (life drain) level + 1 for vtable +0x68(0, level - 1) = 60 s x level; status art EZ26.
func _vampirism(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	return spells._record(caster, {"radius": spells.spell_radius(f, level - 1), "b4": 1, "b6": 0x12, "sound": 0x14, "b9": 1, "b10": 1,
		"b11": 1, "b12": 4, "d85": 0x36325a45, "d89": spells.duration(f, 0, level - 1), "effect": "EZ27", "d131": 0x44000,
		"descriptors": [[STATUS_VAMPIRISM, level + 1]]})

## 0x57e5b0 Darkstorm (45): kind 4 amount 3 (dusk and rain: B1-3's day / night).
func _darkstorm(caster: Dictionary, _level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"b6": 0x13, "sound": 0x15, "effect": "EZ27", "kind": SpellEffects.DAY_NIGHT, "amount": 3})

## 0x57e160 Strip Flesh (46): kind 0x25 on enemy units within vtable +0x64(0) with STATUS 0x30010000 and none of 0x204a04;
## a unit below level + 1 (rank, a hero's level) becomes a Skeleton of its owner (effect EZ41).
func _strip_flesh(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	return spells._record(caster, {"radius": spells.spell_radius(f, 0) if f != null else 8, "b6": 0x47, "sound": 0x1d, "b9": 2, "b10": 1,
		"b12": 4, "effect": "EZ27", "effect2": "EZ41", "kind": SpellEffects.STRIP_FLESH, "amount": level + 1, "d131": 0x204a04,
		"d135": 0x30010000})

## 0x57e950 Ring of Ice (48): enemies of every kind within 7, 0x40dd50((level + 1) x 25) ice (mode 2, type 1).
func _ring_of_ice(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var owner: int = spells.object_of(String(caster.kind), int(caster.id)).owner
	return spells._record(caster, {"radius": 7, "b6": 0x15, "sound": 0x17, "b9": 2, "b12": 4, "effect": "EZ07", "kind": SpellEffects.DAMAGE,
		"amount": spells.spell_power(owner, (level * 5 + 5) * 5), "w9b": 2, "w9d": 1})

# ------------------------------------------------------------------------------------------------ Runes (70-79)
## The caster as the record's one target (+5 = 1, +0x25 its id; no radius).
func _self_target(caster: Dictionary) -> Array:
	var o: Dictionary = spells.object_of(String(caster.kind), int(caster.id))
	return [o] if not o.is_empty() else []

## 0x5804d0 Stoneskin (70): the caster gets armour + 10 (effect 0x18) for 60 s x level; +0x97 = 6 (the node's look).
func _stoneskin(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	return spells._record(caster, {"targets": _self_target(caster), "b4": 1, "b6": 0x49, "sound": 0x21, "d89": spells.duration(f, 0, level - 1),
		"effect": "ERUC", "w97": 6, "descriptors": [[spells.STATUS_ARMOUR, 10]]})

## 0x5805c0 Gem of Wisdom (71): 0x70d54c[owner] = 0x40dd50((level + 1) x 10) before the record (no targets, no kind).
func _gem_of_wisdom(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var owner: int = spells.object_of(String(caster.kind), int(caster.id)).owner
	gem[owner] = spells.spell_power(owner, (level * 5 + 5) * 2)
	return spells._record(caster, {"b6": 0x4a, "sound": 0xd, "effect": "ERUC"})

## 0x5806a0 Dig (72): the caster gets effect 0x3f (building time - n %) (level + 1) x 10 for vtable +0x68(7, level - 1) =
## 120 s x level; status art EZ39 (+0x85; its sheet is not imported: shadow mode 5, art.json skip list).
func _dig(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	return spells._record(caster, {"targets": _self_target(caster), "b4": 1, "b6": 0x4b, "sound": 0x2a, "d85": 0x39335a45,
		"d89": spells.duration(f, 7, level - 1), "effect": "ERUC", "descriptors": [[STATUS_DIG, (level + 1) * 10]]})

## 0x5807a0 Earthpower (73): own hurt buildings within vtable +0x64(level - 1) heal 0x40dd50(200 x level) (kind 2).
func _earthpower(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	var owner: int = spells.object_of(String(caster.kind), int(caster.id)).owner
	return spells._record(caster, {"radius": spells.spell_radius(f, level - 1), "b6": 0x4c, "sound": 0x18, "b9": 1, "b10": 2, "b12": 2,
		"effect": "ERUC", "effect2": "EZ00", "kind": SpellEffects.HEAL, "amount": spells.spell_power(owner, level * 200)})

## 0x5808c0 Resist Magic (74): the caster gets effect 0x51 (magic armour) 25 x level for 60 s x level; +0x97 = 7.
func _resist_magic(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	return spells._record(caster, {"targets": _self_target(caster), "b4": 1, "b6": 0x4d, "sound": 0x24, "d89": spells.duration(f, 0, level - 1),
		"effect": "ERUC", "w97": 7, "descriptors": [[STATUS_RESIST_MAGIC, level * 25]]})

## 0x580af0 Summon Guardian (76): kind 7, BWGC / BWGS / BWGI (level 1 / 2 / 3+) at the placement cell for vtable
## +0x68(3, level - 1) = (level + 4) x 120 s; effect EZ35.
func _summon_guardian(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	var type_id := "BWGC" if level < 2 else ("BWGS" if level == 2 else "BWGI")
	return spells._record(caster, {"b6": 0x4f, "sound": 0x18, "d89": spells.duration(f, 3, level - 1), "effect": "ERUC", "effect2": "EZ35",
		"kind": SpellEffects.BUILDING, "summon": type_id, "cells": [Vector2i(int(target.get("x", 0)), int(target.get("y", 0)))]})

## 0x580c00 Resist Missile (77): the caster gets effect 0x52 (missiles / 16) for 60 s x level; status art EZ40.
func _resist_missile(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	return spells._record(caster, {"targets": _self_target(caster), "b4": 1, "b6": 0x4b, "sound": 0x27, "d85": 0x30345a45,
		"d89": spells.duration(f, 0, level - 1), "effect": "ERUC", "descriptors": [[STATUS_RESIST_MISSILE, 1]]})

## 0x5811e0 Rune Item (78, Read; the items Emulated): no record. The dialog's item (0x572390 -> 0xbbf744) is dropped at the
## hero's cell (0x580d00: its pile, else a neighbour's or a new pile; treasures.drop is the same rule) and the hero's node
## shows look 2 for 400 ms. Returns {} (nothing to apply) after the drop.
func _rune_item(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var o: Dictionary = spells.object_of(String(caster.kind), int(caster.id))
	if o.is_empty(): return {}
	var items := rune_items(level)
	var pick := int(rune_choice.get(int(o.owner), 0))
	var item := int(items[clampi(pick, 0, 3)])
	var host = spells.host
	var treasures = host.get("treasures") if host != null else null
	if treasures != null and treasures.has_method("drop"): treasures.drop(item, o.cell, "Rune Item")
	spells.dropped.emit({"item": item, "cell": o.cell, "owner": int(o.owner)})
	var f = spells._caster_fighter(caster)
	if f != null: f["look"] = {"state": 2, "until": spells.now() + 400}
	return {}

# ------------------------------------------------------------------------------------------------ B1-6b helpers
## Every B1-6b builder (Emulated, tests/hero_spell_b_fixtures.json "spells", tools/emulate_hero_spells_b.py): the record of
## its spell function as the fixture names the fields. r0 = vtable +0x64(0) (0x529ea0), rl = vtable +0x64(level - 1);
## durations vtable +0x68(kind, level - 1) (0x5199e0); "power" = 0x40dd50 (the caster's effect / item power 0x2a).
func _owner_of(caster: Dictionary) -> int:
	return int(spells.object_of(String(caster.kind), int(caster.id)).get("owner", 0))

func _r0(caster: Dictionary) -> int:
	var f = spells._caster_fighter(caster)
	return spells.spell_radius(f, 0) if f != null else 8

func _rl(caster: Dictionary, level: int) -> int:
	var f = spells._caster_fighter(caster)
	return spells.spell_radius(f, level - 1) if f != null else 8

func _dur(caster: Dictionary, kind: int, level: int) -> int:
	return spells.duration(spells._caster_fighter(caster), kind, level - 1)

func _power(caster: Dictionary, value: int) -> int:
	return spells.spell_power(_owner_of(caster), value)

## A record on the caster alone (+5 = 1, +0x25 its id), with status descriptors.
func _on_self(caster: Dictionary, fields: Dictionary) -> Dictionary:
	var r := {"targets": _self_target(caster), "b4": 1}
	r.merge(fields, true)
	return spells._record(caster, r)

## The common missile record (kind 0x10): enemies within r0, +0x9d = the radius (as Doomstones).
func _missiles(caster: Dictionary, fields: Dictionary) -> Dictionary:
	var r := _r0(caster)
	var out := {"radius": r, "b9": 2, "b12": 4, "kind": SpellEffects.MISSILES, "w9d": r}
	out.merge(fields, true)
	return spells._record(caster, out)

# ------------------------------------------------------------------------------------------------ Healing (0-9)
## 0x57b090 Heal Self (0): the caster heals power(50 x level) (kind 2) plus its owner's hero skill term 0x3c
## (0x556ea0(0x3c, 0x556b50(owner, 0x3c, 1, 1)); B1-6d, Emulated: tests/hero_spell_d_fixtures.json "heal_self_skill").
func _heal_self(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var block: Dictionary = combat().hero_block(_owner_of(caster))
	var skill: int = HeroEffects.skill_effect(block, 0x3c) if not block.is_empty() else 0
	return spells._record(caster, {"targets": _self_target(caster), "sound": 0xb, "effect": "EZ11", "kind": SpellEffects.HEAL,
		"amount": _power(caster, level * 50) + skill})

## 0x57b310 Blessing (2): the caster's effect 7 (morale, 0x5269a0) = level + 1 for 60 s x level; status art EBLS.
func _blessing(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _on_self(caster, {"b6": 2, "sound": 8, "d85": 0x534c4245, "d89": _dur(caster, 0, level), "effect": "EZ20",
		"descriptors": [[spells.STATUS_MORALE, level + 1]]})

## 0x57b410 White Ward (3): allied units within r0, the caster too, not STATUS 0x8000000 (the undead), get effect 6 (magic
## armour) 5 x level for 60 s x level; status art EZ22.
func _white_ward(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 1, "b6": 3, "sound": 7, "b9": 1, "b10": 1, "b11": 1, "b12": 4,
		"d85": 0x32325a45, "d89": _dur(caster, 0, level), "effect": "EZ20", "d131": 0x8000000,
		"descriptors": [[spells.STATUS_MAGIC_ARMOUR, level * 5]]})

## 0x57b560 Heal Group (4): hurt allied units within r0, the caster too, heal power(50 x level).
func _heal_group(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 4, "sound": 0xb, "b9": 1, "b10": 1, "b11": 1, "b12": 2,
		"effect": "EZ11", "effect2": "EZ11", "kind": SpellEffects.HEAL, "amount": _power(caster, level * 50)})

## 0x57b890 Invigorate (5): allied units within r0, the caster too, not STATUS 4, get effect 0x2e (speed and attack rate)
## level + 1 for 60 s x level; status art EZ23.
func _invigorate(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 1, "b6": 6, "sound": 0xc, "b9": 1, "b10": 1, "b11": 1, "b12": 4,
		"d85": 0x33325a45, "d89": _dur(caster, 0, level), "effect": "EZ20", "d131": 4, "descriptors": [[spells.STATUS_HASTE, level + 1]]})

## 0x57b6a0 Purify (6): two records: kind 4 amount 0 (day; B1-3's DayNight) and EMM2 missiles (damage 20 x level + 30,
## type 4, not scaled by 0x40dd50: Emulated) at enemy units within r0 that carry STATUS 0x8000000 (the undead).
func _purify(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var day: Dictionary = spells._record(caster, {"b6": 5, "sound": 0xa, "effect": "EZ19", "kind": SpellEffects.DAY_NIGHT, "amount": 0})
	var stones := _missiles(caster, {"b6": 0xff, "sound": 9, "b10": 1, "amount": level * 20 + 30, "w9b": 4, "summon": "EMM2",
		"d135": 0x8000000})
	return {"records": [day, stones]}

## 0x57b9d0 Major Healing (7): every hurt allied unit within 255 (the map), the caster too, heals power(100 x level) and
## is cured (kind 0x14).
func _major_healing(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": 255, "b6": 7, "sound": 0xb, "b9": 1, "b10": 1, "b11": 1, "b12": 2, "effect": "EZ11",
		"effect2": "EZ11", "kind": SpellEffects.HEAL_CURE, "amount": _power(caster, level * 100)})

## 0x57bb00 Life Ward (8): nothing while the caster's effect 0x3e is active with a value above 0 (Emulated 'warded');
## else the caster's effect 0x3e = 1 for 120 s x level (death prevented once, 0x522860); status art EZ24.
func _life_ward(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	if f != null and spells.status_value(f, spells.STATUS_LIFE_WARD) >= 1: return {}
	return _on_self(caster, {"b6": 8, "sound": 0xd, "d85": 0x34325a45, "d89": _dur(caster, 7, level), "effect": "EZ20",
		"descriptors": [[spells.STATUS_LIFE_WARD, 1]]})

## 0x57bc20 Resurrection (9): kind 5 on dead units within rl, own only at levels 1-2 (+9 = 1), any side's from level 3
## (+9 = 0), not STATUS 0x4004; effect EZ13 at each new unit.
func _resurrection(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _rl(caster, level), "b6": 9, "sound": 0xe, "b9": 1 if level < 3 else 0, "b10": 1, "b12": 1,
		"effect": "EZ20", "effect2": "EZ13", "kind": SpellEffects.RESURRECT, "d131": 0x4004})

# ------------------------------------------------------------------------------------------------ Pyromancy (50-59)
## 0x57f8c0 Hand of Flame (50): EMF0 at enemy units within r0, power(10 x level + 10) fire (type 3).
func _hand_of_flame(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _missiles(caster, {"b6": 0x17, "sound": 0x1b, "b10": 1, "amount": _power(caster, level * 10 + 10), "w9b": 3, "summon": "EMF0"})

## 0x57f9e0 Soul Flame (51): kind 0x11 on allied units within r0 (not the caster): experience + power(5 x level + 5) up to
## 10 x level; effects EZ30 / EF01.
func _soul_flame(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x18, "sound": 0xf, "b9": 1, "b10": 1, "b12": 4, "effect": "EZ30",
		"effect2": "EF01", "kind": SpellEffects.SOUL_FLAME, "amount": _power(caster, level * 5 + 5), "w9b": level * 10})

## 0x57fb00 Cauterize (52): hurt allied units within r0, the caster too, heal power(25 x level); effect EF04.
func _cauterize(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x19, "sound": 0xb, "b9": 1, "b10": 1, "b11": 1, "b12": 2,
		"effect": "EF04", "effect2": "EF04", "kind": SpellEffects.HEAL, "amount": _power(caster, level * 25)})

## 0x57fc10 Resist Fire (53): allied units within r0, the caster too, get effect 0x50 (fire armour word 3) 25 x level
## for 60 s x level; status art EZ28.
func _resist_fire(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 1, "b6": 0x1a, "sound": 0x19, "b9": 1, "b10": 1, "b11": 1, "b12": 4,
		"d85": 0x38325a45, "d89": _dur(caster, 0, level), "effect": "EZ29", "descriptors": [[STATUS_RESIST_FIRE, level * 25]]})

## 0x57fe80 Firebreath (55): allied units within r0 (not the caster) get effect 0x17 value 0 = the attack (5 x level + 5,
## fire 3, range 5) for 60 s x level; status art EZ33.
func _firebreath(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 1, "b6": 0x1c, "sound": 0x1a, "b9": 1, "b10": 1, "b12": 4,
		"d85": 0x33335a45, "d89": _dur(caster, 0, level), "effect": "EZ31", "descriptors": [[spells.STATUS_ATTACK, 0, level * 5 + 5, 3, 5, 0]]})

## 0x57ffe0 Berserker (56): kind 0x16 amount 2 on allied units within r0 (not the caster, not STATUS 0x4000): the berserk
## state and effects 1 (combat) level + 4 and 5 (speed) 2 x level + 3 for 120 s x level.
func _berserker(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 2, "b6": 0x1d, "sound": 0x1c, "b9": 1, "b10": 1, "b12": 4,
		"d89": _dur(caster, 7, level), "effect": "EZ30", "kind": SpellEffects.BERSERK, "amount": 2, "d131": 0x4000,
		"descriptors": [[spells.STATUS_COMBAT, level + 4], [spells.STATUS_SPEED, level * 2 + 3]]})

## 0x580140 Pillar of Fire (57): enemies of every kind within 3, power(40 x level + 60) fire (mode 2, type 3); effect EZ32.
func _pillar_of_fire(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": 3, "b6": 0x1e, "sound": 0x23, "b9": 2, "b12": 4, "effect": "EZ32", "kind": SpellEffects.DAMAGE,
		"amount": _power(caster, level * 40 + 60), "w9b": 2, "w9d": 3})

## 0x5803a0 Armageddon (59): enemies of every kind within r0, power(50 x level + 50) fire; no dialog (0x570f80 has no case
## for 0x3b: the cast path orders it at once, Emulated); effect EZ32 on each target.
func _armageddon(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x20, "sound": 9, "b9": 2, "b12": 4, "effect2": "EZ32",
		"kind": SpellEffects.DAMAGE, "amount": _power(caster, level * 50 + 50), "w9b": 2, "w9d": 3})

# ------------------------------------------------------------------------------------------------ Ice (80-89)
## 0x57bd20 Hand of Ice (80): EMIS (0x40f620 -> missile EDUM with the EMIS art) at enemy units within r0, power(10 x level
## + 10) ice (type 1); effect EISP.
func _hand_of_ice(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _missiles(caster, {"b6": 0x53, "sound": 0x1b, "b10": 1, "effect": "EISP", "amount": _power(caster, level * 10 + 10), "w9b": 1,
		"summon": "EMIS"})

## 0x57be40 Storm (81, Read for the weather test; values Emulated): kind 4, by night 3 (level 1) / 5, by day 1 / 4.
func _storm(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var amount := (3 if level < 2 else 5) if spells.is_night() else (1 if level < 2 else 4)
	return spells._record(caster, {"b6": 0x54, "sound": 0x15, "effect": "EZ27", "kind": SpellEffects.DAY_NIGHT, "amount": amount})

## 0x57bf40 Ice Armor (82): the caster's armour + 5 x level (effect 0x18) for 60 s x level; status art EIAR.
func _ice_armor(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _on_self(caster, {"b6": 0x55, "sound": 2, "d85": 0x52414945, "d89": _dur(caster, 0, level), "effect": "EISP",
		"descriptors": [[spells.STATUS_ARMOUR, level * 5]]})

## 0x57c040 Calm (83): kind 0x1d on the units of either side within rl, the caster too.
func _calm(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _rl(caster, level), "b6": 0x56, "sound": 0x28, "b10": 1, "b11": 1, "b12": 4, "effect": "EISP",
		"effect2": "EISP", "kind": SpellEffects.CALM})

## 0x57c150 Freeze (85): enemy units within r0 get effect 0x30 (speed and attack rate) level + 1 for 30 s x level, look 7.
func _freeze(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 1, "b6": 0x58, "sound": 0x28, "b9": 2, "b10": 1, "b12": 4,
		"d89": _dur(caster, 6, level), "effect": "EISP", "w97": 7, "descriptors": [[spells.STATUS_FREEZE, level + 1]]})

## 0x57c270 Wall of Ice (86): kind 7, BWIC at the placement cell for (level) x 600 s (0x5199e0 case 4); effect EISP.
func _wall_of_ice(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return spells._record(caster, {"b6": 0x59, "sound": 0x1c, "d89": _dur(caster, 4, level), "effect2": "EISP", "kind": SpellEffects.BUILDING,
		"summon": "BWIC", "cells": [Vector2i(int(target.get("x", 0)), int(target.get("y", 0)))]})

## 0x57c360 Ice Floe (87): the caster's effect 0x17 value 0 = the attack (power(15 x level + 5), ice 1, range 12, EMIF)
## for 30 s x level; status art EMIF.
func _ice_floe(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _on_self(caster, {"b6": 0x5a, "sound": 3, "d85": 0x46494d45, "d89": _dur(caster, 6, level), "effect": "EISP",
		"descriptors": [[spells.STATUS_ATTACK, 0, _power(caster, level * 15 + 5), 1, 12, 0x46494d45]]})

## 0x57c490 Freeze Magic (88): kind 0x1e amount 0 on the caster (0x7494c4 = 0: no mana regeneration anywhere) for 60 s x
## level, a [0, 0] status on the caster; status art EIFM.
func _freeze_magic(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _on_self(caster, {"b6": 0x5b, "sound": 0x24, "d85": 0x4d464945, "d89": _dur(caster, 0, level), "effect": "EISP",
		"kind": SpellEffects.MANA_GATE, "amount": 0, "descriptors": [[0, 0]]})

## 0x57c5a0 Ice Storm (89): EMM2 at enemies of every kind within r0, power(50 x level + 50) ice; effect EIST.
func _ice_storm(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _missiles(caster, {"b6": 0x5c, "sound": 9, "effect": "EIST", "effect2": "EIST", "amount": _power(caster, level * 50 + 50),
		"w9b": 1, "summon": "EMM2"})

# ------------------------------------------------------------------------------------------------ Poison (100-109)
## 0x57ec10 Immunity (100): the caster's effect 0x7c (no poison, no disease) for 120 s x level; status art EIMM.
func _immunity(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _on_self(caster, {"sound": 8, "d85": 0x4d4d4945, "d89": _dur(caster, 7, level), "effect": "EZ20",
		"descriptors": [[spells.STATUS_IMMUNITY, 1]]})

## 0x57ed00 Poison Cloud (101): kind 0xd amount 4 (poison) on enemy units within rl with a STATUS bit of 0x801cfb.
func _poison_cloud(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _rl(caster, level), "b6": 0x65, "sound": 0x12, "b9": 2, "b10": 1, "b12": 4, "effect": "EZ19",
		"effect2": "EZ25", "kind": SpellEffects.AFFLICT, "amount": 4, "d135": 0x801cfb})

## 0x57ee00 Summon Wasp (102): level wasps AAWA, experience 0.
func _summon_wasp(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AAWA", level, 0, 0x66, 0x22, {"effect2": "EZ18"})

## 0x57ef50 Antidote (103): kind 3 on allied units within rl, the caster too.
func _antidote(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _rl(caster, level), "b6": 0x67, "sound": 0xf, "b9": 1, "b10": 1, "b11": 1, "b12": 4,
		"effect": "EZ20", "effect2": "EZ20", "kind": SpellEffects.ANTIDOTE})

## 0x57f050 Venom Touch (104): allied units within r0 (not the caster) get effect 0x7d (poisoning melee hits) for 60 s x
## level; status art ESVT.
func _venom_touch(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 1, "b6": 0x68, "sound": 0x1a, "b9": 1, "b10": 1, "b12": 4,
		"d85": 0x54565345, "d89": _dur(caster, 0, level), "effect": "EPOC", "descriptors": [[spells.STATUS_VENOM, 0]]})

## 0x57f190 Poison Gate (105): the caster's effect 0x7e (units created elsewhere come out poisoned, 0x4a49e0) for 60 s x
## level; status art EPGA.
func _poison_gate(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _on_self(caster, {"b6": 0x69, "sound": 0x1a, "b9": 1, "b10": 1, "b12": 4, "d85": 0x41475045, "d89": _dur(caster, 0, level),
		"effect": "EZ19", "descriptors": [[spells.STATUS_POISON_GATE, 0]]})

## 0x57f2b0 Spray Poison (106): EMAP (0x40f620 -> missile EMA0 with the EMAP art) at enemies of every kind within r0,
## power(10 x level + 30), type 0. The poison an EMAP hit gives (0x5427e0 +0x67c) is the missile system's (G-1 Open).
func _spray_poison(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _missiles(caster, {"b6": 0x4e, "sound": 0x1b, "effect": "EPOC", "amount": _power(caster, level * 10 + 30), "summon": "EMAP"})

## 0x57f3d0 Guardian Naga (107): one ALGX, experience (level - 1) x 20.
func _guardian_naga(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "ALGX", 1, 20, 0x6b, 0x22, {"effect2": "EZ18"})

## 0x57f510 Rot (108): kind 0x26 amount level + 1 on enemy units within rl.
func _rot(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _rl(caster, level), "b6": 0x6c, "sound": 0xf, "b9": 2, "b10": 1, "b11": 1, "b12": 4,
		"effect": "EPOC", "effect2": "EPOC", "kind": SpellEffects.ROT, "amount": level + 1})

## 0x57f630 Call of Kargoth (109): two records, eight AKLX and eight AKKX, experience (level - 1) x 20 (each its own
## command check, Emulated 'command full').
func _call_of_kargoth(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var first := _summon(caster, level, target, "AKLX", 8, 20, 0x6d, 0x22, {"effect2": "EZ18"})
	var second := _summon(caster, level, target, "AKKX", 8, 20, 0x6d, 0x22, {"effect2": "EZ18"})
	var records: Array = []
	if not first.is_empty(): records.append(first)
	if not second.is_empty(): records.append(second)
	if records.is_empty(): return {}
	return {"records": records} if records.size() > 1 else records[0]

# ------------------------------------------------------------------------------------------------ B1-6c: Nature (20-29)
## Every B1-6c builder (Emulated, tests/hero_spell_c_fixtures.json "spells", tools/emulate_hero_spells_c.py): the record of
## its spell function as the fixture names the fields (r0 / rl / durations / power as in B1-6b).

## 0x57d320 Summon Sprite (20): one AASP, experience (level - 1) x 20; effect EZ14.
func _summon_sprite(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AASP", 1, 20, 0x21, 5, {"effect2": "EZ14"})

## 0x57d460 Gemberry (21): allied units within r0, the caster too, not STATUS 0x6004, heal power(25 x level): kind 2 at
## level 1, kind 0x14 (heal and cure) from level 2; effect EZ15.
func _gemberry(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x22, "sound": 0xf, "b9": 1, "b10": 1, "b11": 1, "b12": 4,
		"effect": "EZ15", "effect2": "EZ15", "kind": SpellEffects.HEAL if level < 2 else SpellEffects.HEAL_CURE,
		"amount": _power(caster, level * 25), "d131": 0x6004})

## 0x57d5b0 Entangle (22): enemy units within r0 with STATUS 0x400000 and without 0x200000 (flyers) get effect 0x38
## (slowing, 0x51c460) 2 x level + 2 for 30 s x level; status art EZ16.
func _entangle(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 1, "b6": 0x23, "sound": 0x28, "b9": 2, "b10": 1, "b12": 4,
		"d85": 0x36315a45, "d89": _dur(caster, 6, level), "effect": "EZ19", "d131": 0x200000, "d135": 0x400000,
		"descriptors": [[spells.STATUS_SLOW, level * 2 + 2]]})

## 0x57d6e0 Shillelagh (23): the caster's combat + 5 x level (effect 1) for 60 s x level; status art EZ17.
func _shillelagh(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _on_self(caster, {"b6": 0x24, "sound": 0x1d, "d85": 0x37315a45, "d89": _dur(caster, 0, level),
		"descriptors": [[spells.STATUS_COMBAT, level * 5]]})

## 0x57d7d0 Summon Unicorn (24): one AEDX, experience (level - 1) x 20; effect EZ18.
func _summon_unicorn(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AEDX", 1, 20, 0x25, 0x22, {"effect2": "EZ18"})

## 0x57d910 Wall of Thorns (25): kind 7, BWBR at the placement cell (0x570f80 mode 7) for 600 s x level; effect EZ18.
func _wall_of_thorns(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return spells._record(caster, {"b6": 0x26, "sound": 0x1c, "d89": _dur(caster, 4, level), "effect2": "EZ18", "kind": SpellEffects.BUILDING,
		"summon": "BWBR", "cells": [Vector2i(int(target.get("x", 0)), int(target.get("y", 0)))]})

## 0x57da00 Call Lightning (26): enemies of every kind within r0, power((level x 5 + 10) x 4) electricity (mode 2, type 2);
## effect EZ09 on each target.
func _call_lightning(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x27, "sound": 9, "b9": 2, "b12": 4, "effect2": "EZ09",
		"kind": SpellEffects.DAMAGE, "amount": _power(caster, (level * 5 + 10) * 4), "w9b": 2, "w9d": 2})

## 0x57db20 Summon Treant (27): one AWJX, experience (level - 1) x 20; effect EZ18.
func _summon_treant(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AWJX", 1, 20, 0x28, 0x21, {"effect2": "EZ18"})

## 0x57dc60 Change Weather (28): kind 4 with the mode 9 dialog's pick as its amount (the target's +4, "id" here): 0 / 1
## day, 2 / 3 night (DayNight.apply_record; the rain half stays the B1-3 Open item); effect EZ19.
func _change_weather(caster: Dictionary, _level: int, target := {}) -> Dictionary:
	return spells._record(caster, {"b6": 0x29, "sound": 0x11, "effect": "EZ19", "kind": SpellEffects.DAY_NIGHT, "amount": int(target.get("id", 0))})

## 0x57dd20 Elementalism (29): the mode 10 dialog's pick (target +0xc) of AAEA / AAEE / AAEF / AAEW, its own command check,
## experience (level - 1) x 50, +0x9d = 2; effect EZ14. A pick outside 0..3 leaves the type uninitialised in the original
## (Open); the rebuild sends nothing.
func _elementalism(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var pick := int(target.get("extra", 0))
	if pick < 0 or pick > 3: return {}
	return _summon(caster, level, target, String(ELEMENTALS[pick]), 1, 50, 0x2a, 0x20, {"effect2": "EZ14", "w9d": 2})

# ------------------------------------------------------------------------------------------------ B1-6c: Divination (110-119)
## A caster status of the lore kind (+0x8d effect, +0x85 status art, descriptors).
func _lore(caster: Dictionary, art: int, sound: int, d85: int, d89: int, effect: String, kind: int, descriptors: Array) -> Dictionary:
	return _on_self(caster, {"b6": art, "sound": sound, "d85": d85, "d89": d89, "effect": effect, "kind": kind, "descriptors": descriptors})

## 0x57a6b0 Elemental Lore (110): kind 100, the caster's magic armour + 10 (effect 6) for 60 s x level; status art EZ65.
func _elemental_lore(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _lore(caster, 0x6e, 0x21, 0x35365a45, _dur(caster, 0, level), "EARC", SpellEffects.STATUS_ONLY, [[spells.STATUS_MAGIC_ARMOUR, 10]])

## 0x57a7b0 Defense Lore (111): kind 100, the caster's armour + 10 (effect 0x18) for 60 s x level; status art EZ66.
func _defense_lore(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _lore(caster, 0x6f, 0x21, 0x36365a45, _dur(caster, 0, level), "EDVC", SpellEffects.STATUS_ONLY, [[spells.STATUS_ARMOUR, 10]])

## 0x57a8b0 See Invisible (112): the caster's effect 0x43 for 120 s x level (0x40dd10: the player sees invisible units);
## status art ESIV.
func _see_invisible(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _lore(caster, 0x70, 0x2a, 0x56495345, _dur(caster, 7, level), "EDVC", 0, [[spells.STATUS_SEE_INVISIBLE, 1]])

## 0x57a9a0 Telepathy (113): the caster's effect 3 = power(10 x level) for 60 s x level (0x557d90: the starting experience
## of units the player creates, Combat.starting_xp); status art EZ67.
func _telepathy(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _lore(caster, 0x71, 0x2a, 0x37365a45, _dur(caster, 0, level), "EDVC", 0, [[spells.STATUS_TRAINING, _power(caster, level * 10)]])

## 0x581e70 Banish (114, and Summoning's 18: the same function): kind 0x17 amount 2 x level on enemy units within r0
## with STATUS 0x2000 (summoned); effect EZ37.
func _banish(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x3d, "sound": 0x1e, "b9": 2, "b10": 1, "b12": 4, "effect": "EZ37",
		"effect2": "EZ37", "kind": SpellEffects.BANISH, "amount": level * 2, "d135": 0x2000})

## 0x57aab0 Comprehension (115): the caster's effect 0x25 = 5 x level + 20 (research price - n %, 0x40b6b0) for 60 s x
## level; status art ECOM.
func _comprehension(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _lore(caster, 0x73, 0x2a, 0x4d4f4345, _dur(caster, 0, level), "EDVC", 0, [[spells.STATUS_RESEARCH, level * 5 + 20]])

## 0x57abc0 Call Sage (116): a 1..3 roll (0x458e70(1, 3, 0), before the command check) picks AHGR (1), AHGB (3) or AHGW;
## one sage, experience (level - 1) x 20; effect EZ34.
func _call_sage(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var r: int = spells.roll(1, 3, 0)
	var type_id := "AHGR" if r == 1 else ("AHGB" if r == 3 else "AHGW")
	return _summon(caster, level, target, type_id, 1, 20, 0x74, 0x20, {"effect2": "EZ34"})

## 0x57ad20 Mind Leech (117): allied units within r0 (not the caster), not STATUS 0x44000, get effect 0x19 (a kill takes
## the victim's experience, 0x526fe0) for 60 s x level; status art EZ68.
func _mind_leech(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b4": 1, "b6": 0x75, "sound": 0x14, "b9": 1, "b10": 1, "b12": 4,
		"d85": 0x38365a45, "d89": _dur(caster, 0, level), "effect": "EDVC", "d131": 0x44000, "descriptors": [[spells.STATUS_MIND_LEECH, 1]]})

## 0x57ae50 True Sight (118): the owner's sight bonus 0x70d488 + level for the rest of the match (message 0x462 for the
## local player), then a record with no target and no kind; effect EDVC.
func _true_sight(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	spells.add_sight(_owner_of(caster), level)
	return spells._record(caster, {"b6": 0x76, "sound": 0xd, "effect": "EDVC"})

## 0x57af70 Psychic Blast (119): kind 0x28 on enemy units within r0, not STATUS 0x4000; amount = vtable +0x68(1, level - 1)
## / 1000 (5 x level seconds, disassembly 0x57afa3..0x57afb9): each target's combat is 1 for that long (status 0x46).
func _psychic_blast(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x77, "sound": 0x1e, "b9": 2, "b10": 1, "b12": 4, "effect": "EDVC",
		"effect2": "EDVC", "kind": SpellEffects.PSYCHIC_BLAST, "amount": _dur(caster, 1, level) / 1000, "d131": 0x4000})

# ------------------------------------------------------------------------------------------------ B1-6c: Arcane (120-129)
## The eight Arcane caster statuses (0x575e50 .. 0x576630 except Dispel): kind 100, art 0x6e, for vtable +0x68(5, level -
## 1) = (level + 1) x 60 s, effect EDVC, status art EZ70 + n; the consumers are the framework's (0x51c2d0 chance 0x1c,
## 0x529ea0 radius 0x20, 0x51b580 mana rate 0x21, 0x529f30 duration 0x23, 0x529fa0 cost 0x24, 0x4aa840 summon theft 0x28,
## 0x526de0 kill mana 0x29, 0x40dd50 power 0x2a).
func _arcane(caster: Dictionary, level: int, n: int, sound: int, kind: int, value: int) -> Dictionary:
	return _lore(caster, 0x6e, sound, 0x30375a45 + (n << 24), _dur(caster, 5, level), "EDVC", SpellEffects.STATUS_ONLY, [[kind, value]])

## 0x575e50 Concentration (120): the cast chance + 5 x level + 15 (effect 0x1c).
func _concentration(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _arcane(caster, level, 0, 0x21, 0x1c, level * 5 + 15)

## 0x575f50 Command (121): the spell radius + 25 x level % (effect 0x20).
func _command(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _arcane(caster, level, 1, 0x22, 0x20, level * 25)

## 0x576050 Enervate (122): the hero's mana rate + 50 x level % (effect 0x21).
func _enervate(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _arcane(caster, level, 2, 0x21, spells.STATUS_MANA_RATE, level * 50)

## 0x576150 Extend (123): durations + 100 % (effect 0x23).
func _extend(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _arcane(caster, level, 3, 0x21, 0x23, 100)

## 0x576250 Mana Flow (124): spell costs - 25 % (effect 0x24).
func _mana_flow(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _arcane(caster, level, 4, 0x21, spells.STATUS_MANA_COST, 25)

## 0x576350 Corruption (125): the chance to take other players' summons 10 x level + 20 (effect 0x28).
func _corruption(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _arcane(caster, level, 5, 0x21, 0x28, level * 10 + 20)

## 0x576530 Mana Leech (127): mana per kill level + 4 (effect 0x29).
func _mana_leech(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _arcane(caster, level, 6, 0x21, spells.STATUS_MANA_LEECH, level + 4)

## 0x576630 Empower (128): spell power + 25 x level + 25 % (effect 0x2a).
func _empower(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _arcane(caster, level, 7, 0x21, 0x2a, level * 25 + 25)

## 0x576450 Dispel (126): kind 0x1d (Calm's applier) on the units of either side within vtable +0x64(level) (one step
## wider than rl), the caster too; effect EARC.
func _dispel(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _rl(caster, level + 1), "b6": 0x56, "sound": 0x28, "b10": 1, "b11": 1, "b12": 4,
		"effect": "EARC", "effect2": "EARC", "kind": SpellEffects.CALM})

## 0x576730 Destruction (129): kind 0x13, power(the caster's hit points - 1) of type 4 (mode 2) on everything within rl,
## either side, the caster too (it keeps 1 hit point through its own armour, Emulated 'tough'); effects EARC / EX01.
func _destruction(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	var hp: int = int(f.hp) if f != null else 1
	return spells._record(caster, {"radius": _rl(caster, level), "b6": 0x81, "sound": 9, "b11": 1, "b12": 4, "effect": "EARC",
		"effect2": "EX01", "kind": SpellEffects.DAMAGE, "amount": _power(caster, hp - 1), "w9b": 2, "w9d": 4})

# ------------------------------------------------------------------------------------------------ B1-6d: Summoning (10-19)
## Every B1-6d builder (Emulated, tests/hero_spell_d_fixtures.json "spells", tools/emulate_hero_spells_d.py): the record of
## its spell function as the fixture names the fields (r0 / rl / durations as in B1-6b). The summons' cell is the target
## cell (0x570f80 mode 8: next to the nearest Circle of Power BMCP within the radius, + 1 level, else the rolled cell).

## 0x5813a0 Summon Quasit (10): level AVBX, experience 0x557d90 only (no level term); effect EZ34.
func _summon_quasit(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AVBX", level, 0, 0x35, 5, {"effect2": "EZ34"})

## 0x5814f0 Circle of Power (11): kind 7, BMCP at the placement cell (0x570f80 mode 7) for vtable +0x68(2, level - 1) =
## (level + 1) x 60 s; effect EZ36.
func _circle_of_power(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return spells._record(caster, {"b6": 0x36, "sound": 0x2a, "d89": _dur(caster, 2, level), "effect2": "EZ36", "kind": SpellEffects.BUILDING,
		"summon": "BMCP", "cells": [Vector2i(int(target.get("x", 0)), int(target.get("y", 0)))]})

## 0x5815e0 Phantom Steed (12): kind 0xc on allied units within r0 with STATUS 0x20000 (not the caster: +0xb = 0):
## speed + level + 1, armour and magic armour + 5 x level for 60 s x level (0x528570); effect EZ37.
func _phantom_steed(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x37, "sound": 0x22, "b9": 1, "b10": 1, "b12": 4, "kind": SpellEffects.SHADOW,
		"amount": level + 1, "w9b": level * 5, "w9d": level * 5, "d89": _dur(caster, 0, level), "effect": "EZ37", "d135": 0x20000})

## 0x581700 Blink (13): kind 0x12 on the caster to a rolled cell (Spells.blink_cell) made reachable (0x530a90 with its
## reachability flag; Spells.reachable_cell); effect EZ34.
func _blink(caster: Dictionary, _level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	if f == null: return {}
	var o: Dictionary = spells.object_of(String(caster.kind), int(caster.id))
	var cell: Vector2i = spells.reachable_cell(o, spells.blink_cell(f))
	return spells._record(caster, {"targets": _self_target(caster), "b6": 0x38, "sound": 0x27, "kind": SpellEffects.TELEPORT,
		"effect2": "EZ34", "cells": [cell]})

## 0x581a30 Eye of Oros (15): level + 1 AAEY living for vtable +0x68(6, level - 1) = 30 s x level (the 0xfa lifetime);
## experience 0x557d90 only; effect EZ34. Its 0x437f70(owner, PGAX) result is unused (Read).
func _eye_of_oros(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AAEY", level + 1, 0, 0x3a, 0x25, {"effect2": "EZ34", "d89": _dur(caster, 6, level)})

## 0x581bc0 Home Portal (16): kind 0x12 on the caster to its start location (Spells.start_cell) made reachable; effect EZ34.
func _home_portal(caster: Dictionary, _level: int, _target := {}) -> Dictionary:
	var o: Dictionary = spells.object_of(String(caster.kind), int(caster.id))
	if o.is_empty(): return {}
	var cell: Vector2i = spells.reachable_cell(o, spells.start_cell(int(o.owner)))
	return spells._record(caster, {"targets": _self_target(caster), "b6": 0x3b, "sound": 0x26, "kind": SpellEffects.TELEPORT,
		"effect2": "EZ34", "cells": [cell]})

## 0x581d20 Soulharvest (17): level AVIX (succubi), experience 0x557d90 only; effect EZ34.
func _soulharvest(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AVIX", level, 0, 0x3c, 0x20, {"effect2": "EZ34"})

## 0x581f70 Daemongate (19): one AADE, experience (level - 1) x 50; effect EZ35.
func _daemongate(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AADE", 1, 50, 0x3e, 0x15, {"effect2": "EZ35"})

# ------------------------------------------------------------------------------------------------ B1-6d: Illusion (30-39)
## 0x57cab0 (Emulated, fixtures 34 'race 0..16'): Spectral Horde's type by the caster player's race 0x708f96 (16 and above:
## AUBX).
const HORDE_TYPES := ["AHKX", "ADSX", "AUIX", "ABIX", "AMIX", "AOIX", "AEIX", "AWIX", "AKIX", "AFIX", "AAIX", "AVJX", "AHIX",
	"ALIX", "ARJX", "AGPC"]
## 0x57ccd0 (Emulated, fixtures 35): Dragonfear's dragon by race (red AADR the default).
const DRAGON_TYPES := {2: "AADW", 6: "AADW", 12: "AADW", 3: "AADB", 4: "AADB", 7: "AADB", 8: "AADB", 9: "AADG", 13: "AADG", 15: "AADG"}

func _race_of(caster: Dictionary) -> int:
	return int(spells.production.race_of(_owner_of(caster))) if spells.production != null else 0

## 0x57c6d0 Shadowform (30): kind 0xc on the caster: speed + level, armour and magic armour + 5 x level for 60 s x level
## (0x528570); effect EILU.
func _shadowform(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"targets": _self_target(caster), "b6": 0x3f, "sound": 0x16, "kind": SpellEffects.SHADOW, "amount": level,
		"w9b": level * 5, "w9d": level * 5, "d89": _dur(caster, 0, level), "effect": "EILU"})

## The fear record of Scare / Awe: enemy units within rl, not STATUS 4 (+0x131), kind 0xd with the fear amount.
func _fear(caster: Dictionary, level: int, art: int, sound: int, amount: int) -> Dictionary:
	return spells._record(caster, {"radius": _rl(caster, level), "b6": art, "sound": sound, "b9": 2, "b10": 1, "b12": 4,
		"kind": SpellEffects.AFFLICT, "amount": amount, "effect": "EILU", "effect2": "EILE", "d131": 4})

## 0x57c7c0 Scare (31): kind 0xd amount 0 -> 0x528a40(1) (+0xba bit 1 for 45 s, longer by STATUS class) on enemy units.
func _scare(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _fear(caster, level, 0x40, 0x1f, 0)

## 0x57c8c0 Light/Darkness (32): kind 4: by night (0x499a50) 1 with rain (0x49bb10) else 0; by day 3 with rain else 2
## (DayNight.apply_record: 0 / 1 day, 2 / 3 night); effect EZ19.
func _light_darkness(caster: Dictionary, _level: int, _target := {}) -> Dictionary:
	var rain: bool = spells.is_raining()
	var amount := (1 if rain else 0) if spells.is_night() else (3 if rain else 2)
	return spells._record(caster, {"b6": 0x41, "sound": 0x11, "effect": "EZ19", "kind": SpellEffects.DAY_NIGHT, "amount": amount})

## 0x57c9b0 Awe (33): kind 0xd amount 3 -> 0x528a40(4) (+0xba bit 4 for 30 s, longer by STATUS class).
func _awe(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _fear(caster, level, 0x42, 0x2b, 3)

## 0x57cab0 Spectral Horde (34): kind 0x18, 2 x level + 4 illusions of the race's type (its own command check) living
## vtable +0x68(7, level - 1) = 120 s x level; effect EZ34.
func _spectral_horde(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var race := _race_of(caster)
	var type_id: String = HORDE_TYPES[race] if race >= 0 and race < HORDE_TYPES.size() else "AUBX"
	return _summon(caster, level, target, type_id, level * 2 + 4, 0, 0x43, 0x2a, {"effect2": "EZ34", "kind": SpellEffects.ILLUSIONS,
		"d89": _dur(caster, 7, level)})

## 0x57ccd0 Dragonfear (35): kind 0x18, one illusion dragon of the race (DRAGON_TYPES) for 120 s x level; effect EZ34.
func _dragonfear(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var type_id := String(DRAGON_TYPES.get(_race_of(caster), "AADR"))
	return _summon(caster, level, target, type_id, 1, 0, 0x44, 0x2c, {"effect2": "EZ34", "kind": SpellEffects.ILLUSIONS,
		"d89": _dur(caster, 7, level)})

## 0x57ce90 Invisibility (36): kind 0xe on the caster for 60 s x level (0x5285b0: +0x1f1, until it attacks, casts or is
## hurt); effect EILU.
func _invisibility(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"targets": _self_target(caster), "b6": 0x45, "sound": 0x28, "b9": 1, "b10": 1, "b11": 1, "b12": 4,
		"kind": SpellEffects.INVISIBLE, "d89": _dur(caster, 0, level), "effect": "EILU", "d131": 0x40004000})

## 0x57cf90 Call Shadow (37): one AUXX, experience (level - 1) x 20; effect EZ08.
func _call_shadow(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AUXX", 1, 20, 0x46, 0x10)

## 0x57d0d0 Mutate (38): kind 0x19 on enemy units within r0, not STATUS 0x4200, amount level + 1 (0x526d80 below it);
## effects EILU / EZ12.
func _mutate(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return spells._record(caster, {"radius": _r0(caster), "b6": 0x47, "sound": 0x1d, "b9": 2, "b10": 1, "b12": 4, "kind": SpellEffects.MUTATE,
		"amount": level + 1, "effect": "EILU", "effect2": "EZ12", "d131": 0x4200})

## 0x57d1d0 Transform (39): kind 0x1a on own units within r0 (STATUS 0x30000000 needed, 0xc0204200 excluded): +0x99 =
## 0x458e70(2, keep + 2 x level, -2) clamped to 0..20 (keep = 0x5325d0, Spells.keep_level), +0x9b = min(3 x level, 15)
## targets; effects EILU / EILE.
func _transform(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var r := _r0(caster)
	var amount: int = clampi(spells.roll(2, spells.keep_level(_owner_of(caster)) + level * 2, -2), 0, 20)
	return spells._record(caster, {"radius": r, "b6": 0x48, "sound": 0x2a, "b9": 1, "b10": 1, "b12": 4, "kind": SpellEffects.TRANSFORM,
		"amount": amount, "w9b": mini(level * 3, 15), "effect": "EILU", "effect2": "EILE", "d131": 0xc0204200, "d135": 0x30000000})

# ------------------------------------------------------------------------------------------------ B1-6e: Alchemy (60-69)
## B1-6e (SPELLS_RESEARCH.md "B1-6e"; Emulated: tests/hero_spell_e_fixtures.json, tools/emulate_hero_spells_e.py).
## 0x574f20 Create Item (60): 0x402f90 (ComputerHero.random_item) draws a rarity-weighted item of the item levels the cast
## level allows (1: 1-2, 2: 1-3, 3: 2-4, 4: 3-5; Emulated with the real item table under eight seeds); it lies at the
## caster's cell (the inlined 0x580d00 rule: its pile, else a neighbour's or a new pile: treasures.drop, Read) and the node
## shows look 2 for 400 ms. No record (as Rune Item): 0x570f80 has no case for 60, so no dialog either (mode 0; the
## random-item dialog 0x571e30 of mode 12 has no writer in 0x570f80: Read).
const CREATE_ITEM_LEVELS := [[true, true, false, false, false], [true, true, true, false, false], [false, true, true, true, false],
	[false, false, true, true, true]]
var created_items: Array = []         # {"item", "cell", "owner"} of every Create Item cast (tests, the HUD line)
var acquired: Array = []              # {"owner", "cell", "radius", "mines"} of every Acquire cast (0x532640's arguments)
var trade_requests: Array = []        # {"title", "rate", "close"} of every Transmute / Morph Resources dialog (0x5723a0)

func _create_item(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var o: Dictionary = spells.object_of(String(caster.kind), int(caster.id))
	if o.is_empty(): return {}
	var ComputerHero = load("res://simulation/computer_hero.gd")
	var item: int = ComputerHero.random_item(combat().rng, CREATE_ITEM_LEVELS[clampi(level, 1, 4) - 1])
	var host = spells.host
	var treasures = host.get("treasures") if host != null else null
	if treasures != null and treasures.has_method("drop"): treasures.drop(item, o.cell, "Create Item")
	created_items.append({"item": item, "cell": o.cell, "owner": int(o.owner)})
	spells.dropped.emit({"item": item, "cell": o.cell, "owner": int(o.owner)})
	var f = spells._caster_fighter(caster)
	if f != null: f["look"] = {"state": 2, "until": spells.now() + 400}
	return {}

## 0x5723a0 (Emulated: the constructor's arguments): Transmute and Morph Resources open the Market's trade dialog
## (simulation/market.gd ports its trade, 0x5735e0 / 0x573750) with their rate and close it after one trade (third
## argument 1). Neither function tests the caster's owner, and the dialog trades the local player's stock (0x709100):
## a computer hero's cast opens the local player's dialog too (Read; kept, see SPELLS_RESEARCH.md B1-6e Open).
func _trade(title: String, rate: int):
	var request := {"title": title, "rate": rate, "close": true}
	trade_requests.append(request)
	var hud = spells.host.get("hud") if spells.host != null else null
	if hud != null and hud.has_method("open_spell_trade"): hud.open_spell_trade(rate, title, true)

## 0x575510 Transmute (61): the trade dialog at min(100, (5 x level + 20) x 2) % (50 / 60 / 70 / 80); its title is the
## string at 0x61832c, "Scare" (the original's own caption, Emulated). No record.
func _transmute(_caster: Dictionary, level: int, _target := {}) -> Dictionary:
	_trade("Scare", mini(100, (level * 5 + 20) * 2))
	return {}

## 0x5755b0 Charm (62): the caster's effect 0xb = 2 x level (0x526cf0: the price value, costs x 100 / (value + 100)) for
## vtable +0x68(0, level - 1) = 60 s x level; status art EZ39, effect EZ20.
func _charm(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _on_self(caster, {"b6": 0x2d, "sound": 0x2b, "d85": 0x39335a45, "d89": _dur(caster, 0, level), "effect": "EZ20",
		"descriptors": [[STATUS_CHARM, level * 2]]})

## 0x5756b0 Stone Golem (63): one AAIX (its own command check), experience 0x557d90 + (level - 1) x 20; effect EZ34. The
## cast path gives it a rolled cell near the hero (0x570f80 case 0x3f).
func _stone_golem(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AAIX", 1, 20, 0x2e, 5, {"effect2": "EZ34"})

## 0x5757f0 Brew Potion (64): the hero block's potions +0x184 + level (no cap), then a record without targets (EZ20).
func _brew_potion(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var m = _match_of(_owner_of(caster))
	if m != null: m.potions = int(m.potions) + level
	return spells._record(caster, {"b6": 0x30, "sound": 0x2e, "effect2": "EZ20"})

## 0x5758b0 Acquire (65): 0x532640(owner, the caster's cell, vtable +0x64(level - 1) / 2, 1): milestone 12's conversion
## scan 0x5489e0 limited to resource buildings (0x52b050: words +0x94..+0x9a; the rebuild's mines) converts up to eight at
## once (message 0x104, MatchConversion.transfer); then a record as Brew Potion's (+0xc is left unwritten: stack bytes).
func _acquire(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var o: Dictionary = spells.object_of(String(caster.kind), int(caster.id))
	if o.is_empty(): return {}
	var reach := CombatRules.tdiv(_rl(caster, level), 2)
	acquired.append({"owner": int(o.owner), "cell": o.cell, "radius": reach, "mines": spells.acquire_mines(int(o.owner), o.cell, reach)})
	return spells._record(caster, {"b6": 0x30, "sound": 0x2e, "effect2": "EZ20"})

## 0x5759b0 Summon Guardian (66): as 76 (kind 7, BWGC / BWGS / BWGI by level, the placement of 0x570f80 case 0x42) but its
## duration is (level + 4) x 120 s without vtable +0x68's 0x23 term; no +0x8d effect (EZ35 only).
func _summon_guardian_66(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var type_id := "BWGC" if level < 2 else ("BWGS" if level == 2 else "BWGI")
	return spells._record(caster, {"b6": 0x31, "sound": 0x18, "d89": (level + 4) * 120000, "effect2": "EZ35",
		"kind": SpellEffects.BUILDING, "summon": type_id, "cells": [Vector2i(int(target.get("x", 0)), int(target.get("y", 0)))]})

## The status-only record on the caster of Disjunction / Spellforge (kind 100, b9 / b10 1, b12 4; status art d85).
func _item_status(caster: Dictionary, d85: int, duration: int, status: int) -> Dictionary:
	return _on_self(caster, {"b6": 0x43, "sound": 0x1a, "b9": 1, "b10": 1, "b12": 4, "kind": SpellEffects.STATUS_ONLY, "d85": d85,
		"d89": duration, "effect": "EZ26", "descriptors": [[status, 0]]})

## 0x575ad0 Disjunction (67): the caster's effect 0x7f for vtable +0x68(6, level - 1) = 30 s x level: other players'
## item powers count 0 (HeroEffects.item_stat / item_power through HeroMatch's factors); status art EZ69.
func _disjunction(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _item_status(caster, 0x39365a45, _dur(caster, 6, level), STATUS_DISJUNCTION)

## 0x575bf0 Bronze Golem (68): one AAGX, experience 0x557d90 + (level - 1) x 20; effect EZ34 (rolled cell, 0x570f80 0x44).
func _bronze_golem(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon(caster, level, target, "AAGX", 1, 20, 0x2e, 5, {"effect2": "EZ34"})

## 0x575d30 Spellforge (69): the caster's effect 0x80 for 60 s x level: its own item powers count double; status art EZ80.
func _spellforge(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _item_status(caster, 0x30385a45, _dur(caster, 0, level), STATUS_SPELLFORGE)

func _match_of(owner: int):
	var c = combat()
	return c.heroes[owner].match if c.heroes.has(owner) else null

## 0x40c380 / 0x40c500's status terms (Emulated, fixtures "item_powers"), kept on each player's HeroMatch every step:
## x 2 while the player's hero object carries 0x80; 0 while another player's hero carries 0x7f (0x40c380: unless that
## player is allied with it, 0x748915[p + 7 s]; 0x40c500 tests no alliance).
func sync_item_factors():
	var c = combat()
	var holders: Array = []
	for owner in c.heroes:
		var h = spells._hero_fighter(int(owner))
		if h != null and not spells.status_entry(h, STATUS_DISJUNCTION).is_empty(): holders.append(int(owner))
	for owner in c.heroes:
		var m = c.heroes[owner].match
		if m == null: continue
		var h = spells._hero_fighter(int(owner))
		var factor := 2 if h != null and not spells.status_entry(h, STATUS_SPELLFORGE).is_empty() else 1
		var school_factor := factor
		for s in holders:
			if s == int(owner): continue
			school_factor = 0
			if not spells.allied(int(owner), s): factor = 0   # 0x748915[owner + 7 s] (0x40c48d; REVIEW D4, Emulated U2)
		m.item_factor = factor
		m.school_item_factor = school_factor

# ------------------------------------------------------------------------------------------------ B1-6e: Chaos (90-99)
## The Morphs' value roll (Emulated under eight seeds): n = 6 x level + 1, 0x458e70(1, n, -(n / 2 + 1)) again while 0.
func _morph_roll(level: int) -> int:
	var n := level * 6 + 1
	var r := 0
	while r == 0: r = spells.roll(1, n, -(CombatRules.tdiv(n, 2) + 1))
	return r

## The Morph record: kind 0x1f on every unit of either side (not the caster) within vtable +0x64(0); +0x99 the stat
## (0 combat, 1 speed, 2 hit points, 3 damage), +0x9b the change; effects ECHC.
func _morph(caster: Dictionary, art: int, stat: int, value: int, fields := {}) -> Dictionary:
	var r := {"radius": _r0(caster), "b6": art, "sound": 0x14, "b10": 1, "b12": 4, "kind": SpellEffects.MORPH, "amount": stat,
		"w9b": value, "effect": "ECHC", "effect2": "ECHC"}
	r.merge(fields, true)
	return spells._record(caster, r)

## 0x576860 Morph Combat (90): combat + the roll (0x4ac0e0 case 0x1f: clamped to 1..99).
func _morph_combat(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _morph(caster, 0x5d, 0, _morph_roll(level))

## 0x576990 Morph Speed (91): speed + the roll (1..99).
func _morph_speed(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _morph(caster, 0x5e, 1, _morph_roll(level))

## 0x576ad0 Morph Health (92): maximum and current hit points + 10 x the roll (each 1..999).
func _morph_health(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _morph(caster, 0x5d, 2, _morph_roll(level) * 10)

## 0x576c10 Morph Damage (93): damage + the roll (1..999).
func _morph_damage(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _morph(caster, 0x60, 3, _morph_roll(level))

## 0x576d50 Morph Tower (94): buildings only (+0xa 2), +0x9d 1; the stat is a 0x458e70(1, 4, -1) roll (+0x99, the
## decompile's EBX is the rolled stat: Emulated), the change as the Morphs' (x 10 for hit points).
func _morph_tower(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var stat: int = spells.roll(1, 4, -1)
	var value := _morph_roll(level)
	if stat == 2: value *= 10
	return _morph(caster, 0x61, stat, value, {"b10": 2, "w9d": 1})

## 0x576f00 Drain Mana (95) is the Harpy's 0x578b60 (B1-4): enemy units within vtable +0x64(level - 1) lose up to
## power(25 x level + 25) mana (Emulated with a hero caster).
func _drain_mana(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return spells._harpy(caster, level, target)

## 0x576f20 Morph Resources (96): Transmute's trade dialog at min(100, 0x458e70(1, 21, -11) + (5 x level + 20) x 2) %,
## titled "Morph Resources" (Emulated under eight seeds). No record.
func _morph_resources(_caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var rate: int = HeroEffects.s16(spells.roll(1, 21, -11) + (level * 5 + 20) * 2)
	_trade("Morph Resources", mini(100, rate))
	return {}

## 0x577100 Increase Casting (97): a 1..100 roll first (its result unused, before the caster test), then kind 0x20 with
## the level: 0x4ac0e0 case 0x20 completes the research PSPR for the local player only (0x436500 -> 0x438180(p, 1): a
## random school + 1 for the match; the level is not used).
func _increase_casting(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	spells.roll(1, 100, 0)
	return spells._record(caster, {"b6": 100, "sound": 0x24, "effect": "ECHC", "kind": SpellEffects.INCREASE_CASTING, "amount": level})

## 0x576fd0 Wildfire (98): kind 0x10, one EMM4 missile at every enemy within vtable +0x64(0), damage power(50 x level),
## type 3; effects ECHW.
func _wildfire(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _missiles(caster, {"b6": 0x65, "sound": 9, "effect": "ECHW", "effect2": "ECHW", "amount": _power(caster, level * 50),
		"w9b": 3, "summon": "EMM4"})

## 0x5771f0 Chaos Plague (99): kind 0x22 on enemy units (not STATUS 0x4200) within min(19, 0x5267b0) (a building caster
## 0x1c): each keeps max(5, 53 - 3 x level) % of its hit points (the host's 0x522af0; 0 kills) and is diseased when
## 0x51c1b0 allows it (0x51c060(1)); effects EZ19 / EZ25.
func _chaos_plague(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = spells._caster_fighter(caster)
	var r: int = mini(19, spells.radius_base(f)) if f != null else 0x1c
	return spells._record(caster, {"radius": r, "b6": 0x66, "sound": 0x12, "b9": 2, "b10": 1, "b12": 4, "kind": SpellEffects.PLAGUE,
		"amount": maxi(5, 53 - 3 * level), "effect": "EZ19", "effect2": "EZ25", "d131": 0x4200})

## 0x438180(p, n) (Emulated through Increase Casting under eight seeds; PSPR n = 1, PARR n = 3 by 0x436500): with the
## player's hero alive, a 0x458e70(1, 13, -1) school gains max(1, (n + 1) / 2) ranks (0x70d496, HeroMatch.school_bonus)
## and 0x54fd50 refreshes the block; the local player hears speech 9 and reads Game.txt 0x81 (0x83 without a hero).
## Returns the school, -1 without a living hero.
func raise_school(owner: int, n: int) -> int:
	var h = spells._hero_fighter(owner)
	var m = _match_of(owner)
	if h == null or m == null or int(h.hp) < 1:
		if owner == int(spells.production.local_player): spells.notice.emit("No hero to learn from the research")
		return -1
	var school: int = spells.roll(1, 13, -1)
	var add := maxi(1, CombatRules.tdiv(n + 1, 2))
	m.school_bonus[school] = int(m.school_bonus[school]) + add
	if owner == int(spells.production.local_player): spells.notice.emit("+%d to spell school %d" % [add, school])
	return school

## 0x561d80 (Emulated, fixtures "potions"): the h key's healing potion. With the hero alive and a potion left, a kind-0x14
## record on the hero (heal (0x5325d0 keep level + 5) x 10, cure; +0x9b 1: not a counted cast) goes out and one potion
## goes; with none, the advisor line (Game.txt, 0x4c9e60). Returns whether one was drunk.
func drink_potion(owner: int) -> bool:
	var h = spells._hero_fighter(owner)
	var m = _match_of(owner)
	if h == null or m == null or int(h.hp) < 1: return false
	if int(m.potions) < 1:
		spells.notice.emit("No potions left")
		return false
	var caster := {"kind": "unit", "id": int(h.id)}
	var record: Dictionary = spells._record(caster, {"targets": _self_target(caster), "b6": 3, "sound": 0xb, "effect": "EZ53",
		"kind": SpellEffects.HEAL_CURE, "amount": (spells.keep_level(owner) + 5) * 10, "w9b": 1})
	spells.cast_built(record, caster, 1, -2)
	m.potions = int(m.potions) - 1
	return true

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd).
func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self, ["_spells", "spells"])

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state, ["_spells", "spells"])

## B1-7: 0x561c30 (Emulated, REVIEW_AI_SPELLS.md), the mana potion (the computer hero's 0x503c60; the local hot key of
## 0x427fb0 and the hero panel's button, which the HUD does not bind yet): with the hero alive and a mana potion left (+0x182) the pool becomes min(maximum, pool + (0x5325d0
## keep level + 2) x 5) at once (no record), effect EZ00 with Sparkles.wav on the hero, one potion goes; with none, the
## advisor line. Returns whether one was drunk. The floating text 0x53a010 is not ported.
func drink_mana_potion(owner: int) -> bool:
	var h = spells._hero_fighter(owner)
	var m = _match_of(owner)
	if h == null or m == null or int(h.hp) < 1: return false
	if m.mana_potion_count() < 1:
		if owner == int(spells.production.local_player): spells.notice.emit("No mana potions left")
		return false
	var top := int(h.get("max_mana", 0))
	var value: int = int(h.get("mana", 0)) + (int(spells.keep_level(owner)) + 2) * 5
	var before := int(h.get("mana", 0))
	h["mana"] = mini(value, top)
	m.mana_potions = m.mana_potion_count() - 1
	# P-2 (decompile 233972-233975): Game.txt [0x45f] with the gain, colour 3, 1000 ms over the hero (presentation only).
	spells.floated.emit({"id": int(h.id), "line": 0x45f, "value": int(h.mana) - before, "colour": 3, "ms": 1000})
	return true
