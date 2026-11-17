extends RefCounted
## B1-5 (AI_RESEARCH.md section 16): the computer player's ability use, 0x5001d0 / 0x500830 (Read). Each AI pass (0x4fa120
## calls 0x5001d0 after the new tasks) a player whose timer 0x70d5d4[p] is due walks its object list; the first object
## with the scan flag +0x31, not deleted, alive, for which 0x500830 casts ends the walk and the timer advances by 250 ms,
## else by 1000 ms (added to the timer, not to the clock). At Squire and Knight a pass runs only when 1d20 is 1 (a failed
## roll leaves the timer).
##
## The scan flag +0x31: a unit's Army.cfg AI column (0x528cd0 -> 0x585ae0, record +0x50); the halls and temples BPHE,
## BPCA, BPMT, BPHO, BKG0-4, BKR0-4, BKL0-4 (0x52a090); a computer unit that may drink when it is hit (0x522860) or fights
## (0x537060). 0x500830 per type (the casters call the spell functions directly, like the ability keys, at level
## (rank + 1) / 5 + 1, paying the unit's own mana 0x51b370; DAT_0060f308 = 7 cells for a player other than the local one):
##
## | Type | Helper | Condition | Cast |
## |---|---|---|---|
## | hero | 0x503c60 | B1-7: simulation/ai_spells.gd (the computer hero's spell choice) | the slot's spell through 0x5717e0 |
## | drinker (+0x204) | 0x500830 | first, before the type's helper | message 0x202 (Dwarven Brew), clears +0x204 and +0x31 |
## | AUMX Liche | 0x502c40 | 1d2 = 1; used + 2 < limit; corpses (EDTH effects, any owner) within 5: more than 2, or one and own hp < 30 | Call the Dead (no mana test; pays 45) |
## | AUBX Zombie | 0x502ba0 | 1d2 = 1; PZOM; a dead unit or corpse within 4 | scavenging 0x578e10 (no 0x4cfc90 throttle) |
## | AUGX Vampire | 0x502170 | 1d5 = 1; mana 40; used + 4 < limit | bats 0x579a10 at its cell |
## | AADE Daemon | 0x5024e0 | 1d5 = 1; mana 40; used + 4 < limit | Summon Imp 0x5818f0 at its cell |
## | ADOX Runelord | 0x501d40, 0x502640 | mana 40; enemies of any kind within 7: weight > 2, or > 0 and own hp < 40; else 1d5 = 1, mana 100, used + 4 < limit | Doomstones; else Stonecall at its cell |
## | ARGX Scorpionpriest | 0x502910, 0x502000 | mana 40; enemies within 4: weight > 2, or = 1 and own hp < 40; else 1d4 = 1, mana 100, used + 4 < limit | Ring of Fire; else Fire Elemental |
## | AAHA Harpy | 0x501350 | mana 20; enemy units within 7 with 20 mana (a hero: pool 8) | the Harpy's drain 0x578b60 |
## | AHGW White Mage | 0x5016c0, 0x501210 | mana 40; hurt friendly units (hp < max - 40, the caster too) within 7: weight > 1 (weight 1 and own hp < 40: unreachable, a unit so hurt weighs 2); else the Archon's Cure | Heal Group (spell 4) |
## | AHGR Red Mage | 0x502910, 0x5026f0 | the Scorpionpriest's Ring of Fire; else mana 30; a living fire enemy unit (damage type 3) within 9; else 1d10000 = 1 and friendly units weight > 7 within 9 | Resist Fire (spell 53) |
## | AHGB Black Mage | 0x501350, 0x501e90 | the Harpy's drain; else 1d3 = 1; mana 20; enemy units within 7: weight > 2, or > 0 and own hp < 40 | Hand of Ice (spell 80) |
## | AMMX Shaman | 0x502910, 0x501df0, 0x501050 | Ring of Fire; else mana 35; enemies of any kind within 2: weight > 1, or > 0 and own hp < 50: Pillar of Fire (spell 57); else, not for the local player, 1d12 = 1; mana 25; within 7 enemies of any kind weight > 3 and friendly units weight > 3 | Berserker (spell 56) |
## | AAAR Archon | 0x501210 | 1d8 = 1; mana 30; poisoned friendly units within 7 | Cure |
## | ALGX Naga | 0x501130 | 1d8 = 1; mana 40; within 4: enemies weight > 2 and friendly units weight > 2 | the Naga's armour 0x578930 |
## | AONX Goblin Shaman | 0x501b30, 0x501aa0, 0x501050 | B3-3: mana 40; enemies of any kind within 7: weight > 2, or exactly 1 and own hp < 40; else, not for the local player, 1d500 = 1, mana 50, by day: Light/Darkness; else Berserker | Call Lightning (26) |
## | AOKX / AAJX / AVGX | 0x502220 / 0x502430 / 0x502590 | B3-3: 1d4 / 1d3 / 1d5; mana 75 / 35 / 100; used + 6 / + 2 / + 4 < limit; not for the local player | Goblins / Firebomb / Daemongate at its cell |
## | AVGX Daemon Summoner | 0x502d90 | B3-3: after Daemongate; mana 30; enemy units with STATUS 0x2000 within 4: weight > 1, or > 0 and own hp < 40 | Banish (114) |
## | AABX Engineer | 0x500fa0 | B3-3: 1d30; mana 40; a friendly building below max - 40 within 7 | Earthpower (73) |
## | AAGX Bronze Golem | 0x502d10 | B3-3: 1d2; a debris node within 4 | Salvage 0x579410 (no throttle) |
## | BKR0-4 Dunekeep | 0x5019d0 | 1d150 = 1; Famine level (PFAn); crystal >= 700 | Famine 0x57a2e0 (free: the 500 crystal is the button's) |
## | BPCA / BPMT | 0x501820, 0x502800 | PHOL power (0x4d1ef0, not ported: Open); else 1d100 = 1, PROD, day / night on and not day | Rites of Dawn: a kind-4 record (day; free) |
##
## "Weight" is 0x5002e0's count: each matching unit or building adds 1 + (maximum hit points >> 5), an effect 1.
## B2-3: the four casters' helpers are Emulated (tests/batch2_review_fixtures.json `abilities`, 120 rows through the real
## 0x500830; tests/test_ai_batch2.gd). Those rows also run the owner = local player branches, which a match reaches only
## through script 8 (not wired, AI_RESEARCH.md 16.1 C6): `helper(ai, f, true)`.
## Other types of 0x500830 (other races' casters) are not ported here. The object list order is Provisional (units by
## id, then buildings by id); it decides only which caster acts first.
const Assets = preload("res://core/asset_store.gd")

const RacePowers = preload("res://simulation/race_powers.gd")
const AiSpells = preload("res://simulation/ai_spells.gd")
const HEAL_GROUP := 4                    # the hero spells the mages and the Shaman call directly (BATCH2_RESEARCH.md E4)
const RESIST_FIRE := 53
const BERSERKER := 56
const PILLAR_OF_FIRE := 57
const HAND_OF_ICE := 80
const CAST_STEP_MS := 250                # 0x5001d0: timer += 0xfa after a cast
const IDLE_STEP_MS := 1000               # ... += 1000 otherwise
const RADIUS := 7                        # DAT_0060f308 = 7 - (owner == local player)
const BUILDINGS := ["BPHE", "BPCA", "BPMT", "BPHO", "BKG0", "BKG1", "BKG2", "BKG3", "BKG4", "BKR0", "BKR1", "BKR2", "BKR3",
	"BKR4", "BKL0", "BKL1", "BKL2", "BKL3", "BKL4"]
const FAMINE_CRYSTAL := 700              # 0x5019d0: crystal (0x708fb8) >= 700
# 0x5002e0 filters
const FRIENDS := 1
const ENEMIES := 2
const ANYONE := 0
const UNITS := 1
const EFFECTS := -1                      # neither units nor buildings: effect objects only
const BOTH := 0
const ALIVE := 4
const DEAD := 1

static var _ai_flags: Dictionary = {}

var _ai: WeakRef
var _radius := RADIUS                    # DAT_0060f308 as this pass set it
var _local := false                      # 0x500830's bVar5: the object belongs to the local player (script 8 only)
var next_ms := 0                         # 0x70d5d4[player]
var casts: Dictionary = {}               # what was cast -> count
var log: Array = []
var hero_casts: Dictionary = {}          # B1-7: spell id -> 0x5717e0 calls by this player's hero (0x503c60)
var hero_drinks: Dictionary = {}         # B1-7: "healing" / "mana" -> potions drunk by 0x503c60
var hero_spells_filled := false          # B1-7: the table holder's fields when the world has no AI manager (test stubs)
var hero_spell_tables: Dictionary = {}

func _init(ai_player):
	_ai = weakref(ai_player)

## Army.cfg AI column by type (the first [ARMIES] row of a code, as 0x585970 finds it).
static func ai_flag(type_id: String, catalogue: Dictionary = {}) -> bool:
	if _ai_flags.is_empty():
		var data: Dictionary = catalogue
		if data.is_empty():
			var parsed = Assets.json("catalogue.json")
			if parsed is Dictionary: data = parsed
		# B1-7: the [HEROES] rows follow the [ARMIES] rows in the merged table 0x58e400c (0x584810); every hero type has
		# the AI column "x", so a hero is scanned and 0x500830 hands it to 0x503c60.
		for row in data.get("army_cfg", {}).get("armies", []) + data.get("army_cfg", {}).get("heroes", []):
			if not _ai_flags.has(row.code): _ai_flags[row.code] = bool(row.get("ai_flag", false))
		_ai_flags["__loaded"] = true
	return bool(_ai_flags.get(type_id, false))

func _world():
	var ai = _ai.get_ref()
	return ai.world if ai != null else null

# ------------------------------------------------------------------------------------------------ 0x5001d0
func tick(now_ms: int):
	var ai = _ai.get_ref()
	if ai == null or not (ai.world is Object) or not ai.world.has_method("drink"): return     # test stubs have no scene
	if ai.world.combat == null or ai.world.combat.spells == null: return
	if next_ms > now_ms: return
	if (ai.difficulty == 1 or ai.difficulty == 2) and ai.roll(1, 20) != 1: return
	_drink_triggers(ai)
	_fill_hero_spells(ai)                                   # B1-7: 0x502ed0 once per match (0x7486fe), every player at once
	var cast := false
	for o in _objects(ai):
		if _try(ai, o):
			cast = true
			break
	next_ms += CAST_STEP_MS if cast else IDLE_STEP_MS

## The player's objects with the scan flag, in the Provisional list order.
func _objects(ai) -> Array:
	var world = ai.world
	var out: Array = []
	var ids: Array = world.combat.fighters.keys()
	ids.sort()
	for id in ids:
		var f = world.combat.fighters[id]
		if int(f.owner) != ai.me or f.removed or not world.combat.alive(f) or int(f.hp) <= 0: continue
		if bool(f.get("wants_drink", false)) or (ai_flag(String(f.type_id), _catalogue(world)) and not bool(f.get("ai_scan_off", false))):
			out.append({"kind": "unit", "f": f})
	var bids: Array = world.production.buildings.keys()
	bids.sort()
	for id in bids:
		var b = world.production.buildings[id]
		if int(b.owner) == ai.me and int(b.hit_points) > 0 and String(b.original_type_id) in BUILDINGS: out.append({"kind": "building", "b": b})
	return out

func _catalogue(world) -> Dictionary:
	var c = world.get("catalogue_data")
	return c if c is Dictionary else {}

## 0x522860 / 0x537060 (Read): a computer unit that may drink (+0x1f9), is not drunk (+0x1f8) and whose owner has
## Dwarven Brew is flagged (+0x204, +0x31) when it is hit or fights. The rebuild samples it once per pass: hit in the
## UnitAI hit memory or swinging (Provisional for the moment of the test).
func _drink_triggers(ai):
	var world = ai.world
	if world.production.research_level(ai.me, RacePowers.BREW_RESEARCH) == 0: return
	for u in ai.my_units():
		var f = world.combat.fighters.get(u.unit_id)
		if f == null or bool(f.get("wants_drink", false)) or int(f.get("drunk_until", 0)) > 0 or not world.drinker(u): continue
		if world.combat.ai.was_hit(u.unit_id) or f.get("swing") != null: f["wants_drink"] = true

# ------------------------------------------------------------------------------------------------ 0x500830
func _try(ai, o: Dictionary) -> bool:
	if o.kind == "building": return _building(ai, o.b)
	var f = o.f
	if f.hero: return _hero(ai, f)                           # 0x503c60, the computer hero's spells (B1-7)
	if bool(f.get("wants_drink", false)):
		f.wants_drink = false
		f["ai_scan_off"] = true                              # +0x31 cleared (a caster that drank is not scanned again)
		var u = ai.world.unit_by_id(int(f.id))
		if u != null and ai.world.drink(u): _note(ai, "Brew", f)
		return true
	return helper(ai, f)

## 0x500830's switch on the type. `local`: the object belongs to the local player (the Emulated rows; script 8).
func helper(ai, f, local: bool = false) -> bool:
	_local = local
	_radius = RADIUS - int(local)
	match String(f.type_id):
		"AUMX": return _liche(ai, f)
		"AUBX": return _zombie(ai, f)
		"AUGX": return _summoner(ai, f, 5, 40, "_bats", "Vampire bats")
		"AADE": return _summoner(ai, f, 5, 40, "_summon_imp", "Summon Imp")
		"ADOX": return _runelord(ai, f)
		"ARGX": return _scorpionpriest(ai, f)
		"AAHA": return _harpy(ai, f)
		"AAAR": return _archon(ai, f)
		"ALGX": return _naga(ai, f)
		"AHGW": return _heal_group(ai, f) or _archon(ai, f)
		"AHGR": return _ring_of_fire(ai, f) or _resist_fire(ai, f)
		"AHGB": return _harpy(ai, f, "Drain") or _hand_of_ice(ai, f)
		"AMMX": return _ring_of_fire(ai, f) or _pillar_of_fire(ai, f) or (not _local and _berserker(ai, f))
		# B3-3 (BATCH3_RESEARCH.md E19, Emulated "ai_abilities": 152 rows through the real 0x500830)
		"AONX": return _call_lightning(ai, f) or (not _local and (_light_darkness(ai, f) or _berserker(ai, f)))
		"AOKX": return _summon_b3(ai, f, 4, 75, 6, "_goblins", "Goblins")
		"AAJX": return _summon_b3(ai, f, 3, 35, 2, "_firebomb", "Firebomb")
		"AVGX": return _summon_b3(ai, f, 5, 100, 4, "_daemongate", "Daemongate") or _banish(ai, f)
		"AABX": return _earthpower(ai, f)
		"AAGX": return _salvage(ai, f)
		# B4-3 (BATCH4_RESEARCH.md E22, Emulated "ai_abilities": 232 rows through the real 0x500830)
		"AEGX", "ASSC": return _multi_target(ai, f)
		"AWJX", "AWKX": return _entangle(ai, f)
		"AWNX": return _call_lightning(ai, f) or (not _local and _light_darkness(ai, f))
		"AENX": return _ring_of_ice(ai, f) or (not _local and _white_ward(ai, f))
		"AEOX": return _freeze(ai, f) or _hand_of_ice(ai, f)
		"AEDX": return _heal_group(ai, f) or _archon(ai, f)
		"AKNX": return _pillar_of_fire(ai, f) or _summon_b3(ai, f, 5, 45, 4, "_raise_zombie", "Raise Zombie") or (not _local and _darkstorm(ai, f))
		"AKOX": return _summon_b3(ai, f, 5, 45, 3, "_queen_spider", "Queen Spider")
		"AKGX": return _invisibility(ai, f)
		# B5-3 (BATCH5_RESEARCH.md E17, Emulated "ai_abilities": 249 rows through the real 0x500830). No case for ALBX, AFNX, AGSP, AFIX,
		# ALIX, AGPC (a computer Chameleon never turns invisible, decision 5); AEDX, ALGX, AAAR and AUBX as ported.
		"AFGX": return _scare(ai, f)
		"AGGX": return _plague_cloud(ai, f) or (not _local and _eye_of_oros(ai, f))
		"ALMX": return _cauterize(ai, f) or _poison_cloud(ai, f)
	return false

# ------------------------------------------------------------------------------------------------ B4-3: race batch 4
## 0x501be0: Multi-Target (mana 25): enemies of any kind, alive, within the radius: weight > 2, or > 0 and own hp < 40.
func _multi_target(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 25): return false
	var n := count(ai, _cell(ai, f), _radius, ENEMIES, BOTH, ALIVE, 0, 3)
	if n > 2 or (n > 0 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_multi_target", "Volley", 25)
	return false

## 0x5014a0: Entangle (mana 20): enemy units within the radius: weight > 2, or exactly 1 and own hp < 40.
func _entangle(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 20): return false
	var n := count(ai, _cell(ai, f), _radius, ENEMIES, UNITS, ALIVE, 0, 3)
	if n > 2 or (n == 1 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_entangle", "Entangle", 20)
	return false

## 0x502a50: Ring of Ice (mana 50): enemies within 4: weight > 2, or exactly 1 and own hp < 40.
func _ring_of_ice(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 50): return false
	var n := count(ai, _cell(ai, f), 4, ENEMIES, BOTH, ALIVE, 0, 3)
	if n > 2 or (n == 1 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_ring_of_ice", "Ring of Ice", 50)
	return false

## 0x502af0: White Ward (1d200, mana 25): friendly units' weight within the radius at least 8 (the caster's own counts).
func _white_ward(ai, f) -> bool:
	if ai.roll(1, 200) != 1 or not _spells(ai).has_unit_mana(f, 25): return false
	if count(ai, _cell(ai, f), _radius, FRIENDS, UNITS, ALIVE, 0, 8) < 8: return false
	return _cast_hero_builder(ai, f, "_white_ward", "White Ward", 25)

## 0x501550: Freeze (mana 45, the cell's price; the key asks 20): enemy units as Entangle.
func _freeze(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 45): return false
	var n := count(ai, _cell(ai, f), _radius, ENEMIES, UNITS, ALIVE, 0, 3)
	if n > 2 or (n == 1 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_freeze", "Freeze", 45)
	return false

## 0x5012c0: Darkstorm (1d500, mana 40) by day; not for the local player.
func _darkstorm(ai, f) -> bool:
	if ai.roll(1, 500) != 1 or not _spells(ai).has_unit_mana(f, 40): return false
	var dn = ai.world.get("day_night")
	if dn == null or not dn.is_day(): return false
	return _cast_hero_builder(ai, f, "_darkstorm", "Darkstorm", 40)

## 0x501a40: Invisibility (mana 35), no other test.
func _invisibility(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 35): return false
	return _cast_hero_builder(ai, f, "_invisibility", "Invisibility", 35)

## 0x5013e0 (BPHE; BPHO has no case): PELC, crystal >= 400, and friendly hurt units' weight >= 8 anywhere (filter 2, radius 200) or
## the owner's hero below half its hit points: 0x4d2030 (300 crystal for a computer).
const HEALER_REACH := 200
func _healer(ai, b) -> bool:
	var world = ai.world
	if world.production.research_level(ai.me, RacePowers.ELCOR_RESEARCH) == 0: return false
	if int(world.economy.resources(ai.me)[2]) < RacePowers.ELCOR_CRYSTAL: return false
	var cell: Vector2i = _spells(ai).object_of("building", int(b.entity_id)).get("cell", Vector2i.ZERO)
	var hurt := count(ai, cell, HEALER_REACH, FRIENDS, UNITS, 2, 0, 8) >= 8
	if not hurt:
		var h = _spells(ai)._hero_fighter(ai.me)
		hurt = h != null and world.combat.alive(h) and int(h.hp) < int(h.max_hp) / 2
	if not hurt: return false
	_spells(ai).elcor_cast(b)
	_note(ai, "Elcor Balm", null)
	return true

## 0x501820 (BPCA and BPMT, decompile 170219-170230): PHOL, crystal >= 200, evil enemy units (filter 3, STATUS 0x8000000) within
## 12: weight > 2, or > 0 with the building below 100 hit points: 0x4d1ef0 (200 crystal and the record).
const HOLY_AI_REACH := 12
func _holy_word(ai, b) -> bool:
	var world = ai.world
	if world.production.research_level(ai.me, RacePowers.HOLY_RESEARCH) == 0: return false
	if int(world.economy.resources(ai.me)[2]) < RacePowers.HOLY_CRYSTAL: return false
	var cell: Vector2i = _spells(ai).object_of("building", int(b.entity_id)).get("cell", Vector2i.ZERO)
	var n := count(ai, cell, HOLY_AI_REACH, ENEMIES, UNITS, ALIVE, 3, 3)
	if not (n > 2 or (n > 0 and int(b.hit_points) < 100)): return false
	_spells(ai)._holy_cast(b)
	_note(ai, "Holy Word", null)
	return true

## B4-3 (R3 / R6, Emulated review "recount"; decision 9): 0x4f7d80 makes a list entry whose producer 0x4f7f20 is -1 (no [PRODUCTION]
## row of the race holds it) available on its requirement words alone (AEAX, the Wood Elves' AAIM, the Undead tree).
static func produced(rules, race: int, id: String) -> bool:
	var table: Dictionary = rules.production_table(race)
	for building in table:
		for s in table[building].get("slots", []):
			var slot = s.get("id")
			if slot is Array and Array(slot).has(id): return true
			if slot is String and slot == id: return true
	return false

## B4-3 (E24, Emulated review "groups"): 0x4f5700 offers an idle unit (no AI task) to the group choice when its builder power is 0 or
## its maximum hit points (vtable +0x5c(1) = +0x98) exceed 49.
## B4-3 (E18, Emulated "peasant"): 0x4fe830's Elven branch (Peasant AEBX; the mine demand is not read): before AEAX is available
## 100 while count + pending < 4, else 0 (the node goes); after it always 100.
static func elven_peasant_priority(count_pending: int, ancient_available: bool) -> int:
	if ancient_available: return 100
	return 100 if count_pending < 4 else 0

static func joins_army(builder_power: int, max_hp: int) -> bool:
	return builder_power == 0 or max_hp > 49

## B4-3 (E20, Emulated "ai_merge"): 0x4f8290 from the Elven Peasant pass: with PWSP, the first four Wisps of the list that are idle
## (state 3) and in no group (+0x30) merge as the button's group; the price is paid only when the stock holds it (a poor computer
## merges free). Fewer than four: nothing. Returns whether a group merged.
func merge_wisps(ai) -> bool:
	var world = ai.world
	if world.production.research_level(ai.me, RacePowers.MERGE_RESEARCH) == 0 or not world.has_method("merge_group"): return false
	var four: Array = []
	for u in ai.my_units():
		if String(u.type_id) != RacePowers.WISP or ai.busy(u) or ai._member(u.unit_id): continue
		four.append(int(u.unit_id))
		if four.size() == RacePowers.MERGE_GROUP: break
	if four.size() < RacePowers.MERGE_GROUP: return false
	var price: Array = world.production.price_of(ai.me, RacePowers.ANCIENT_WISP, RacePowers.WISP)
	var stock: Array = world.economy.resources(ai.me)
	var can := true
	for lane in 4:
		if int(stock[lane]) < int(price[lane]): can = false
	if can: world.economy.debit_clamped(ai.me, price)
	var made: int = world.merge_group(ai.me, four)
	if made >= 0: _note(ai, "Merge", null)
	return made >= 0

# ------------------------------------------------------------------------------------------------ B5-3: race batch 5
## BATCH5_RESEARCH.md E17 / E18 (Emulated "ai_abilities": 249 rows through the real 0x500830; the helpers re-read from the decompile,
## 171138 / 171757 / 171339 / 170867 / 170796 / 170965 / 170933 / 171669).
const EYE_CLOCK_MS := 600000             # 0x5020b0: DAT_00a27db0 < 0x927c1
const TEMPLE_REACH := 12                 # 0x501940 / 0x5018b0

## 0x501c90: Scare (mana 40): enemies of any kind, alive, not already afraid (filter 8: a unit's +0xba fear word 0; buildings count)
## within the radius: weight > 2, or > 0 with own hp < 40.
func _scare(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 40): return false
	var n := count(ai, _cell(ai, f), _radius, ENEMIES, BOTH, ALIVE, 8, 3)
	if n > 2 or (n > 0 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_scare", "Scare", 40)
	return false

## 0x5029b0: Plague Cloud (mana 55): enemies of any kind within 4, the walk stopped at 3: weight > 3, or exactly 1 with own hp < 40.
func _plague_cloud(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 55): return false
	var n := count(ai, _cell(ai, f), 4, ENEMIES, BOTH, ALIVE, 0, 3)
	if n > 3 or (n == 1 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_plague_cloud", "Plague Cloud", 55)
	return false

## 0x5020b0: Eye of Oros (1d20, the first 10 minutes, mana 30, used + 4 < limit) at the caster's cell; not for the local player.
func _eye_of_oros(ai, f) -> bool:
	if ai.roll(1, 20) != 1 or int(ai.world.combat.now_ms) > EYE_CLOCK_MS: return false
	if not _spells(ai).has_unit_mana(f, 30) or not _free(ai, 4): return false
	var c := _cell(ai, f)
	return _cast_hero_builder(ai, f, "_eye_of_oros", "Eye of Oros", 30, {"x": c.x, "y": c.y, "id": -1})

## 0x501770: Cauterize (mana 30): friendly units below maximum - 40 within the radius (stop 2): weight > 1, or exactly 1 with own
## hp < 40 (a 40-hp unit is never below its maximum - 40 and alive: it never counts).
func _cauterize(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 30): return false
	var n := count(ai, _cell(ai, f), _radius, FRIENDS, UNITS, 2, 0, 2)
	if n > 1 or (n == 1 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_cauterize", "Cauterize", 30)
	return false

## 0x501600: Poison Cloud (1d10, mana 25): enemy units within the radius (stop 8): weight > 7, or > 1 with own hp < 40.
func _poison_cloud(ai, f) -> bool:
	if ai.roll(1, 10) != 1 or not _spells(ai).has_unit_mana(f, 25): return false
	var n := count(ai, _cell(ai, f), _radius, ENEMIES, UNITS, ALIVE, 0, 8)
	if n > 7 or (n > 1 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_poison_cloud", "Poison Cloud", 25)
	return false

## 0x501940 (BKG0-4): PCN0 (0x437f70 'PCNX'), crystal >= 1000, enemy units within 12 (stop 5): weight > 4, or > 0 with the hall below
## 100 hit points: 0x4d20b0 (1000 crystal, clamped, and Chaos Plague at the PCN level). No Rites of Dawn after it.
func _plague_hall(ai, b) -> bool:
	var world = ai.world
	if world.production.research_level(ai.me, RacePowers.CHAOS_RESEARCH) == 0: return false
	if int(world.economy.resources(ai.me)[2]) < RacePowers.CHAOS_CRYSTAL: return false
	var cell: Vector2i = _spells(ai).object_of("building", int(b.entity_id)).get("cell", Vector2i.ZERO)
	var n := count(ai, cell, TEMPLE_REACH, ENEMIES, UNITS, ALIVE, 0, 5)
	if not (n > 4 or (n > 0 and int(b.hit_points) < 100)): return false
	_spells(ai).chaos_cast(b)
	_note(ai, "Chaos Plague", null)
	return true

## 0x5018b0 (BKL0-4): PCWR, gold >= 750, enemy units within 12 with stop 3 (weight > 4 only when one unit takes the total past 4 at
## once, e.g. a weight-3 unit after another), or > 0 with the temple below 100: 0x4d2190 (750 gold and the meteors); else 0x502800.
func _sun_temple(ai, b) -> bool:
	var world = ai.world
	if world.production.research_level(ai.me, RacePowers.WRATH_RESEARCH) != 0 and int(world.economy.resources(ai.me)[0]) >= RacePowers.WRATH_GOLD:
		var cell: Vector2i = _spells(ai).object_of("building", int(b.entity_id)).get("cell", Vector2i.ZERO)
		var n := count(ai, cell, TEMPLE_REACH, ENEMIES, UNITS, ALIVE, 0, 3)
		if n > 4 or (n > 0 and int(b.hit_points) < 100):
			_spells(ai).wrath_cast(b)
			_note(ai, "Couatl's Wrath", null)
			return true
	return _rites(ai)

## 0x502800: 1d100, PROD, day / night on and not day: a kind-4 record (dawn); free.
func _rites(ai) -> bool:
	var world = ai.world
	if ai.roll(1, 100) != 1 or world.production.research_level(ai.me, RacePowers.RITES_RESEARCH) == 0: return false
	var dn = world.get("day_night")
	if dn == null or not dn.enabled or dn.is_day(): return false
	dn.apply_record(0)
	_note(ai, "Rites of Dawn", null)
	return true

# ------------------------------------------------------------------------------------------------ B3-3: race batch 3
const SUMMONED_STATUS := 0x2000          # STATUS bit 13: a summoned unit (Banish's filter, kind 9)
const SALVAGE_REACH := 4

## 0x501b30: Call Lightning (mana 40): enemies of any kind, alive, within the radius: weight > 2, or exactly 1 with own hp < 40
## (weight 2 does nothing).
func _call_lightning(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 40): return false
	var n := count(ai, _cell(ai, f), _radius, ENEMIES, BOTH, ALIVE, 0, 3)
	if n > 2 or (n == 1 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_call_lightning", "Call Lightning", 40)
	return false

## 0x501aa0: Light/Darkness (1d500, mana 50) by day; not for the local player.
func _light_darkness(ai, f) -> bool:
	if ai.roll(1, 500) != 1 or not _spells(ai).has_unit_mana(f, 50): return false
	var dn = ai.world.get("day_night")
	if dn == null or not dn.is_day(): return false            # 0x499a00 (no weather object, or the setting off: never day)
	return _cast_hero_builder(ai, f, "_light_darkness", "Light/Darkness", 50)

## 0x502220 (AOKX: 1d4, mana 75, used + 6 < limit), 0x502430 (AAJX: 1d3, 35, + 2), 0x502590 (AVGX: 1d5, 100, + 4): a summon at
## the caster's cell; never for the local player's object.
func _summon_b3(ai, f, sides: int, mana: int, margin: int, builder: String, label: String) -> bool:
	if _local or ai.roll(1, sides) != 1: return false
	if not _spells(ai).has_unit_mana(f, mana) or not _free(ai, margin): return false
	var c := _cell(ai, f)
	return _cast_hero_builder(ai, f, builder, label, mana, {"x": c.x, "y": c.y, "id": -1})

## 0x502d90: Banish (mana 30): enemy units with STATUS 0x2000 within 4 (kind 9): weight > 1, or > 0 and own hp < 40.
func _banish(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 30): return false
	var n := count(ai, _cell(ai, f), 4, ENEMIES, UNITS, ALIVE, 9, 2)
	if n > 1 or (n > 0 and _own_hp(f) < 40): return _cast_hero_builder(ai, f, "_banish", "Banish", 30)
	return false

## 0x500fa0: Earthpower (1d30, mana 40): a friendly building down by more than 40 within the radius (stop at 1).
func _earthpower(ai, f) -> bool:
	if ai.roll(1, 30) != 1 or not _spells(ai).has_unit_mana(f, 40): return false
	if count(ai, _cell(ai, f), _radius, FRIENDS, 2, 2, 0, 1) <= 0: return false
	return _cast_hero_builder(ai, f, "_earthpower", "Earthpower", 40)

## 0x502d10: Salvage (1d2): a debris node within 4 cells; 0x579410 straight (no 0x4cfce0 throttle, no mana).
func _salvage(ai, f) -> bool:
	if ai.roll(1, 2) != 1: return false
	var c := _cell(ai, f)
	var near := false
	for d in ai.world.combat.debris_cells():
		if absi(int(d.x) - c.x) <= SALVAGE_REACH and absi(int(d.y) - c.y) <= SALVAGE_REACH: near = true
	if not near: return false
	return _cast_hero_builder(ai, f, "_salvage", "Salvage", 0)

## The case builders as the keys call them (spells.gd CASE_BUILDERS / HERO_CASE_BUILDERS), at level (rank + 1) / 5 + 1, after the
## unit's mana is paid (0x51b370).
func _cast_hero_builder(ai, f, builder: String, label: String, mana: int, target: Dictionary = {}) -> bool:
	var sp = _spells(ai)
	# A caster off the map (in a mine or a tower) has no map object: the builders read its owner and cell from it (soak 2026-11-13).
	if sp.object_of("unit", int(f.id)).is_empty(): return false
	if mana > 0: sp.pay_unit_mana(f, mana)
	var caster := {"kind": "unit", "id": int(f.id)}
	var record: Dictionary = sp.hero_spells.call(builder, caster, _level(f), target) if sp.hero_spells.has_method(builder) else sp.call(builder, caster, _level(f), target)
	var result: Dictionary = sp.cast_built(record, caster, _level(f))
	_note(ai, label, f, bool(result.get("cast", false)))
	return true

func _level(f) -> int:
	return (int(f.get("rank", 0)) + 1) / 5 + 1

func _cell(ai, f) -> Vector2i:
	return ai.world.combat.unit_cell(int(f.id))

func _free(ai, points: int) -> bool:
	var pop: Dictionary = ai.world.production.population(ai.me)
	return int(pop.current) + points < int(pop.maximum)

func _spells(ai):
	return ai.world.combat.spells

func _cast(ai, f, builder: String, label: String, mana: int, target: Dictionary = {}) -> bool:
	var sp = _spells(ai)
	sp.pay_unit_mana(f, mana)                                # 0x51b370 (clamped at 0)
	var result: Dictionary = sp.cast_record(builder, {"kind": "unit", "id": int(f.id)}, _level(f), target)
	_note(ai, label, f, bool(result.get("cast", false)))
	return true

## The hero spells' builders, called as the ability keys call them (E4): the caster's type does not enter them.
func _cast_spell(ai, f, spell: int, label: String, mana: int) -> bool:
	var sp = _spells(ai)
	sp.pay_unit_mana(f, mana)
	var caster := {"kind": "unit", "id": int(f.id)}
	var result: Dictionary = sp.cast_built(sp.hero_spells.build(spell, caster, _level(f), {}), caster, _level(f))
	_note(ai, label, f, bool(result.get("cast", false)))
	return true

func _note(ai, label: String, f, applied: bool = true):
	casts[label] = int(casts.get(label, 0)) + 1
	if log.size() < 200: log.append({"t": ai.now(), "cast": label, "type": String(f.type_id) if f != null else "", "applied": applied})

func _own_hp(f) -> int:
	return int(f.hp)

## 0x502c40: Call the Dead.
func _liche(ai, f) -> bool:
	if ai.roll(1, 2) != 1 or not _free(ai, 2): return false
	var n := count(ai, _cell(ai, f), 5, ANYONE, EFFECTS, 0, 5, 3)
	if n > 2 or (n > 0 and _own_hp(f) < 30): return _cast(ai, f, "_call_the_dead", "Call the Dead", 45)
	return false

## 0x502ba0: scavenging, straight to 0x578e10.
func _zombie(ai, f) -> bool:
	if ai.roll(1, 2) != 1 or ai.world.production.research_level(ai.me, RacePowers.SCAVENGE_RESEARCH) == 0: return false
	if count(ai, _cell(ai, f), 4, ANYONE, UNITS, DEAD, 5, 1) <= 0: return false
	var u = ai.world.unit_by_id(int(f.id))
	if u != null: ai.world.scavenge(u, false)
	_note(ai, "Scavenging", f)
	return true

## 0x502170 / 0x5024e0: a summon at the caster's cell. 0x500830 never calls one for the local player's object.
func _summoner(ai, f, sides: int, mana: int, builder: String, label: String) -> bool:
	if _local or ai.roll(1, sides) != 1: return false
	if not _spells(ai).has_unit_mana(f, mana) or not _free(ai, 4): return false
	var c := _cell(ai, f)
	return _cast(ai, f, builder, label, mana, {"x": c.x, "y": c.y, "id": -1})

## 0x501d40 then 0x502640.
func _runelord(ai, f) -> bool:
	var sp = _spells(ai)
	if sp.has_unit_mana(f, 40):
		var n := count(ai, _cell(ai, f), _radius, ENEMIES, BOTH, ALIVE, 0, 3)
		if n > 2 or (n > 0 and _own_hp(f) < 40): return _cast(ai, f, "_doomstones", "Doomstones", 40)
	return _summoner(ai, f, 5, 100, "_stonecall", "Stonecall")

## 0x502910 then 0x502000.
func _scorpionpriest(ai, f) -> bool:
	return _ring_of_fire(ai, f) or _summoner(ai, f, 4, 100, "_fire_elemental", "Fire Elemental")

## 0x502910 (the Scorpionpriest, the Red Mage, the Shaman).
func _ring_of_fire(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 40): return false
	var n := count(ai, _cell(ai, f), 4, ENEMIES, BOTH, ALIVE, 0, 3)
	if n > 2 or (n == 1 and _own_hp(f) < 40): return _cast(ai, f, "_ring_of_fire", "Ring of Fire", 40)
	return false

## 0x501350 (the Harpy, the Black Mage).
func _harpy(ai, f, label: String = "Harpy drain") -> bool:
	if not _spells(ai).has_unit_mana(f, 20): return false
	if count(ai, _cell(ai, f), _radius, ENEMIES, UNITS, ALIVE, 1, 1) <= 0: return false
	return _cast(ai, f, "_harpy", label, 20)

## 0x5016c0. The weight-1 branch cannot be reached (a unit with hp < max - 40 has max >= 42, so it weighs 2): kept as read.
func _heal_group(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 40): return false
	var n := count(ai, _cell(ai, f), _radius, FRIENDS, UNITS, 2, 0, 2)
	if n > 1 or (n == 1 and _own_hp(f) < 40): return _cast_spell(ai, f, HEAL_GROUP, "Heal Group", 40)
	return false

## 0x5026f0: the radius 9 is fixed, not DAT_0060f308.
func _resist_fire(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 30): return false
	var c := _cell(ai, f)
	if count(ai, c, 9, ENEMIES, UNITS, ALIVE, 4, 1) > 0: return _cast_spell(ai, f, RESIST_FIRE, "Resist Fire", 30)
	if ai.roll(1, 10000) == 1 and count(ai, c, 9, FRIENDS, UNITS, ALIVE, 0, 8) > 7:
		return _cast_spell(ai, f, RESIST_FIRE, "Resist Fire", 30)
	return false

## 0x501e90.
func _hand_of_ice(ai, f) -> bool:
	if ai.roll(1, 3) != 1 or not _spells(ai).has_unit_mana(f, 20): return false
	var n := count(ai, _cell(ai, f), _radius, ENEMIES, UNITS, ALIVE, 0, 3)
	if n > 2 or (n > 0 and _own_hp(f) < 40): return _cast_spell(ai, f, HAND_OF_ICE, "Hand of Ice", 20)
	return false

## 0x501df0: the radius 2 is fixed; the spell itself reaches 3.
func _pillar_of_fire(ai, f) -> bool:
	if not _spells(ai).has_unit_mana(f, 35): return false
	var n := count(ai, _cell(ai, f), 2, ENEMIES, BOTH, ALIVE, 0, 2)
	if n > 1 or (n > 0 and _own_hp(f) < 50): return _cast_spell(ai, f, PILLAR_OF_FIRE, "Pillar of Fire", 35)
	return false

## 0x501050: the friendly count holds the caster, so a lone Shaman's own weight 4 passes it.
func _berserker(ai, f) -> bool:
	if ai.roll(1, 12) != 1 or not _spells(ai).has_unit_mana(f, 25): return false
	var c := _cell(ai, f)
	if count(ai, c, _radius, ENEMIES, BOTH, ALIVE, 0, 4) > 3 and count(ai, c, _radius, FRIENDS, UNITS, ALIVE, 0, 4) > 3:
		return _cast_spell(ai, f, BERSERKER, "Berserker", 25)
	return false

## 0x501210.
func _archon(ai, f) -> bool:
	if ai.roll(1, 8) != 1 or not _spells(ai).has_unit_mana(f, 30): return false
	if count(ai, _cell(ai, f), _radius, FRIENDS, UNITS, ALIVE, 2, 1) <= 0: return false
	return _cast(ai, f, "_cure", "Cure", 30)

## 0x501130.
func _naga(ai, f) -> bool:
	if ai.roll(1, 8) != 1 or not _spells(ai).has_unit_mana(f, 40): return false
	var c := _cell(ai, f)
	if count(ai, c, 4, ENEMIES, BOTH, ALIVE, 0, 4) > 2 and count(ai, c, 4, FRIENDS, UNITS, ALIVE, 0, 4) > 2:
		return _cast(ai, f, "_naga", "Naga armour", 40)
	return false

## 0x5019d0 (Dunekeep) and 0x501820 / 0x502800 (Cathedral); the other halls' helpers are other races' (not ported).
func _building(ai, b) -> bool:
	var code := String(b.original_type_id)
	var world = ai.world
	if code.begins_with("BKR"):
		if ai.roll(1, 150) != 1: return false
		var level: int = world.production.research_level(ai.me, "PFAX")
		if level == 0 or int(world.economy.resources(ai.me)[2]) < FAMINE_CRYSTAL: return false
		var result: Dictionary = _spells(ai).cast_record("_famine", {"kind": "building", "id": int(b.entity_id)}, level)
		_note(ai, "Famine", null, bool(result.get("cast", false)))
		return true
	if code == "BPHE": return _healer(ai, b)                 # B4-3 (E23)
	if code.begins_with("BKG"): return _plague_hall(ai, b)     # B5-3 (E18): no Rites of Dawn after it
	if code.begins_with("BKL"): return _sun_temple(ai, b)      # B5-3 (E18): Couatl's Wrath, then 0x502800
	if code == "BPCA" or code == "BPMT":
		# B4-3 (E23): 0x501820 Holy Word first, then 0x502800.
		if _holy_word(ai, b): return true
		if ai.roll(1, 100) != 1 or world.production.research_level(ai.me, RacePowers.RITES_RESEARCH) == 0: return false
		var dn = world.get("day_night")
		if dn == null or not dn.enabled or dn.is_day(): return false
		dn.apply_record(0)                                    # 0x502800: a kind-4 record, amount 0 (dawn); no crystal
		_note(ai, "Rites of Dawn", null)
		return true
	return false

# ------------------------------------------------------------------------------------------------ 0x5002e0
## The weighted count of objects in the square of `radius` cells around `cell` (rows and columns clamped to the map).
## relation: FRIENDS (own and allied), ENEMIES, ANYONE; kinds: UNITS, 2 buildings, BOTH, EFFECTS (effect objects only);
## hp: 0 any, DEAD (hit points <= 0), 2 alive and below maximum - 40, 3 at maximum, ALIVE; extra: 0, 1 (a unit with 20
## mana or a hero whose pool holds 8), 2 (a poisoned unit), 5 (corpse effects EDTH / EDT1 / EDT2 and units without a body;
## the rebuild's corpses are fighters in state "corpse"); B1-7: 2 also a diseased unit (+0x19e), 4 a unit of damage type
## 3 (+0xa0, fire). A unit or building adds 1 + (maximum hit points >> 5), an effect
## 1; the walk stops once the total reaches `stop` (an effect one match later, as the original compares the previous total).
func count(ai, cell: Vector2i, radius: int, relation: int, kinds: int, hp: int, extra: int, stop: int) -> int:
	var world = ai.world
	var combat = world.combat
	var total := 0
	for id in _walk_order(combat, cell, radius):
		var f = combat.fighters[id]
		var c: Vector2i = combat.unit_cell(int(id))
		if f.state == "corpse":
			if extra != 5: continue
			var before := total
			total += 1
			if before >= stop: return total
			continue
		if kinds == EFFECTS or kinds == 2: continue
		var u = world.unit_by_id(int(id))
		# B1-7: a garrisoned unit is off the map grid; +0x1f1 is the invisible flag (B1-6d: "invisible_until"), skipped too
		if u == null or u.removed or u.inside_building or f.has("invisible_until"): continue
		if not _relation_ok(ai, int(f.owner), relation): continue
		if not _hp_ok(int(f.hp), int(f.max_hp), hp): continue
		if not _extra_ok(ai, f, extra): continue
		total += 1 + (int(f.max_hp) >> 5)
		if total >= stop: return total
	if kinds == BOTH or kinds == 2:
		for bid in world.production.buildings:
			var b = world.production.buildings[bid]
			var code := String(b.original_type_id)
			if code.length() > 1 and code[1] == "R": continue
			if int(b.owner) == 6 or not _relation_ok(ai, int(b.owner), relation): continue
			var o: Dictionary = combat.spells.object_of("building", int(bid))
			if o.is_empty(): continue
			var c: Vector2i = o.cell
			if absi(c.x - cell.x) > radius or absi(c.y - cell.y) > radius: continue
			if not _hp_ok(int(b.hit_points), int(b.max_hit_points), hp): continue
			# B5-3 (decompile 169982): filter 8 tests a unit's fear word +0xba only; a building passes it (Scare counts buildings).
			if extra in [1, 2, 3, 4, 9]: continue                           # unit-only filters (vtable +0x28 == 0)
			total += 1 + (int(b.max_hit_points) >> 5)
			if total >= stop: return total
	return total

## B5-3 (Emulated "ai_abilities" 'cloud three AMIX, three AHIX'; decompile 169899-169907): 0x5002e0 walks the spatial index row by row
## from the top (y - r first) and each row's list from its head, the sprite placed last first (0x547b80 / +0x60). With a stop value the
## order decides the total. The rebuild keeps no row lists: rows ascending, then the newest fighter first (Provisional for units that
## walked into a row after others).
func _walk_order(combat, cell: Vector2i, radius: int) -> Array:
	var rows := {}
	for id in combat.fighters:
		var f = combat.fighters[id]
		if f.removed: continue
		var c: Vector2i = combat.unit_cell(int(id))
		if absi(c.x - cell.x) > radius or absi(c.y - cell.y) > radius: continue
		if not rows.has(c.y): rows[c.y] = []
		rows[c.y].append(int(id))
	var ys: Array = rows.keys()
	ys.sort()
	var out: Array = []
	for y in ys:
		var row: Array = rows[y]
		row.sort()
		row.reverse()
		out.append_array(row)
	return out

func _relation_ok(ai, owner: int, relation: int) -> bool:
	if relation != FRIENDS and relation != ENEMIES: return true
	var friend: bool = owner == ai.me or ai.world.skirmish.is_allied(ai.me, owner)
	return friend if relation == FRIENDS else not friend

static func _hp_ok(hp: int, max_hp: int, rule: int) -> bool:
	match rule:
		1: return hp <= 0
		2: return hp >= 1 and hp < max_hp - 40
		3: return hp >= max_hp
		4: return hp >= 1
	return true

func _extra_ok(ai, f, extra: int) -> bool:
	match extra:
		1:
			if f.hero: return _spells(ai).hero_pool(int(f.owner)) >= 8
			return _spells(ai).has_unit_mana(f, 20)
		2: return bool(f.get("poisoned", false)) or bool(f.get("diseased", false))   # B1-7: +0x1a4 or +0x19e (B1-6e disease)
		4: return int(f.stats.get("dtype", -1)) == AiSpells.FIRE_TYPE              # B1-7: +0xa0 == 3 (fire), units only
		9: return int(f.stats.get("flags", 0)) & SUMMONED_STATUS != 0             # B3-3: Banish's kind 9 (STATUS 0x2000)
		3: return int(f.stats.get("flags", 0)) & RacePowers.EVIL != 0            # B4-3 (E23): Holy Word's evil units (STATUS 0x8000000)
		8: return _spells(ai).fear_bits(f) == 0                                    # B5-3 (decompile 169982): not already afraid (+0xba)
	return true

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the next ability pass and the casts made.
func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self, ["_ai"])

func load_state(state: Dictionary, _refs = null) -> void:
	preload("res://simulation/save_game.gd").restore(self, state, ["_ai"])

# ------------------------------------------------------------------------------------------------ B1-7: the hero
## 0x502ed0 (Emulated, tests/ai_spell_fixtures.json "fill"): the first ability pass of any computer player fills the tables
## of every player in use, not eliminated, with a hero object; only a computer player's can be enabled (the local
## branch never sets the enabled byte, so the rebuild leaves it out). The tables live in the shared AI manager (0x748700
## is one array for all players); without one (test stubs) each player keeps its own.
func _holder(ai):
	var holder = ai.world.get("ai_manager") if ai.world is Object else null
	if holder == null or not (holder is Object) or not ("hero_spell_tables" in holder): holder = self
	return holder

func _fill_hero_spells(ai):
	var holder = _holder(ai)
	if holder.hero_spells_filled: return
	holder.hero_spells_filled = true
	var world = ai.world
	var combat = world.combat
	for p in range(6):
		if not bool(world.skirmish.slots[p].active) or bool(world.skirmish.eliminated[p]): continue
		if not combat.heroes.has(p) or combat.heroes[p].match == null or combat.heroes[p].match.profile == null: continue
		var hf = combat.fighters.get(combat.heroes[p].unit)
		if hf == null or hf.removed: continue
		if not world.production.ai_players.has(p): continue
		holder.hero_spell_tables[p] = AiSpells.fill(combat.heroes[p].match.block().skills, ai.now())

func hero_table(ai):
	return _holder(ai).hero_spell_tables.get(ai.me)

## 0x503c60 for this player's hero.
func _hero(ai, f) -> bool:
	var t = hero_table(ai)
	if t == null: return false
	var env = AiSpells.LiveEnv.new(ai, f, self)
	var done: bool = AiSpells.decide(t, env)
	for d in env.drinks: hero_drinks[d] = int(hero_drinks.get(d, 0)) + 1
	for c in env.casts:
		hero_casts[int(c.spell)] = int(hero_casts.get(int(c.spell), 0)) + 1
		if log.size() < 200: log.append({"t": ai.now(), "cast": "hero spell %d" % int(c.spell), "type": String(f.type_id), "applied": bool(c.result.get("cast", false))})
	return done
