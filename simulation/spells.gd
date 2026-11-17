extends RefCounted
## Spell framework (B1-4, SPELLS_RESEARCH.md). Labels: Emulated = tests/spell_fixtures.json (tools/emulate_spells.py) or
## tests/batch1_review_fixtures.json; Read = decompile read only.
##
## * Records: there is no spell table in the original. Each spell id has one function (0x574f20..0x582000) that fills a
##   0x141-byte record and sends it as message 0x1f7; here each has one builder (BUILDERS, `_<name>`) returning the
##   record as a Dictionary with the fixture's field names, and SpellEffects.apply runs it. B1-6 adds a builder per
##   spell and a handler per new kind; nothing else changes.
## * Casting: a hero's cast is unit order 9 (`order_cast`, 0x51d3b0) -> state 6 (ANI slot 6) -> event 7 at the slot's
##   +0x18 entry (0x523150) -> the dispatcher `dispatch` (0x5777a0: cost, payment from the owner's hero pool, hero
##   cooldown, the builder). The casters' abilities (`hot_key`, 0x427f70 -> 0x426350) pay the unit's own mana and call
##   the builders directly, without the dispatcher.
## * Mana: heroes use the player's pool (combat.gd's hero fighter "mana"); every other unit has its own (+0x208 / +0x20a,
##   from the Army.cfg MANA pair, `setup_unit` = 0x528cd0, regeneration `_regenerate_unit` = 0x51b6b0), kept in the
##   fighter's "mana" / "max_mana" like the hero's, so the HUD bar reads both.
const Assets = preload("res://core/asset_store.gd")

const SpellEffects = preload("res://simulation/spell_effects.gd")
const HeroSpells = preload("res://simulation/hero_spells.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const Rules = preload("res://simulation/combat_rules.gd")
const ArtData = preload("res://core/art_data.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
const UnitRanks = preload("res://simulation/unit_ranks.gd")

const TABLE_PATH := "res://simulation/spell_table.json"
static var CATALOGUE_PATH: String = Assets.path("catalogue.json")
const CAST_ENTRY_MS := 100            # state 6 entries 100 ms apart (0x536cc0, the conversion's builder; Read)
const FAMINE_PRICE := 500             # crystal (LAB_004d1c60, Read)
const FAMINE_THROTTLE_MS := 1000      # the Dunekeep button at most once per second, stamped before the price test
const MYSTICISM_MANA := 15            # 0x436500 -> 0x4386d0 (PLI0, PLI1)
const COMPUTER_START_MANA := 10       # 0x528cd0: a computer unit starts with 10 more mana when that fits under the maximum
const STATUS_ARMOUR := 0x18           # 0x5260a0 adds the strongest active effect 0x18 to armour word 0 (Read)
const STATUS_MANA_COST := 0x24        # 0x529fa0
const STATUS_MANA_RATE := 0x21        # 0x51b580

## Spell ids of the dispatcher 0x5777a0 that batch 1 builds (all 130 in B1-6) and the extra abilities.
const CURE := 1
const SUMMON_IMP := 14
const CALL_THE_DEAD := 47
const RING_OF_FIRE := 54
const FIRE_ELEMENTAL := 58
const DOOMSTONES := 75
const STONECALL := 79
const HARPY := 0x96                   # dispatcher case 150: 0x578b60
const NAGA := -1                      # dispatcher case -1: 0x578930
const BUILDERS := {CURE: "_cure", SUMMON_IMP: "_summon_imp", CALL_THE_DEAD: "_call_the_dead", RING_OF_FIRE: "_ring_of_fire",
	FIRE_ELEMENTAL: "_fire_elemental", DOOMSTONES: "_doomstones", STONECALL: "_stonecall", HARPY: "_harpy", NAGA: "_naga"}
## 0x426350 cases -> builder (the table's "cases" hold casters, mana, key and the case's own command check).
const CASE_BUILDERS := {2: "_ring_of_fire", 4: "_harpy", 11: "_cure", 21: "_summon_imp", 27: "_doomstones", 28: "_stonecall",
	29: "_bats", 38: "_naga", 41: "_fire_elemental", 47: "_call_the_dead",
	0x1a: "_salvage", 0x23: "_firebomb", 0x2b: "_goblins",     # B3-2 (BATCH3_RESEARCH.md E16)
	0x11: "_multi_target", 0x28: "_queen_spider",             # B4-2 (BATCH4_RESEARCH.md E14)
	0x21: "_plague_cloud", 0x24: "_couatls_wrath"}            # B5-2 (BATCH5_RESEARCH.md E13)
## B2-2 (BATCH2_RESEARCH.md E4): the cases whose record builders are the hero spells' (hero_spells.gd; the same functions, called
## directly at level (rank + 1) / 5 + 1). B3-2 (E16): Call Lightning, Light/Darkness, Daemongate, Banish, Earthpower.
const HERO_CASE_BUILDERS := {0: "_heal_group", 5: "_pillar_of_fire", 10: "_hand_of_ice", 14: "_berserker", 18: "_resist_fire",
	1: "_call_lightning", 9: "_light_darkness", 0x16: "_daemongate", 0x17: "_banish", 0x18: "_earthpower",
	3: "_ring_of_ice", 6: "_raise_zombie", 7: "_darkstorm", 8: "_white_ward", 0xc: "_entangle", 0xd: "_invisibility", 0x2c: "_freeze",   # B4-2 (E14)
	0x1e: "_scare", 0x20: "_eye_of_oros", 0x22: "_chaos_plague", 0x25: "_poison_cloud", 0x27: "_cauterize"}   # B5-2 (BATCH5_RESEARCH.md E13)
## 0x4d3200's ability chain (Read, decompile 138118-138345, stubs 0x4cf9d0..0x4cfc20 `push case; call 0x426350`): the order of the
## unit-row cells when every selected unit has one type: [case, icon, mana, the types that show it and enable it with
## 0x4d4840(type, mana), the 0x414ef0 tooltip line]. A case without a builder (its race comes in a later batch) shows disabled.
## Not listed: the race-gated Scavenge (game_hud.race_unit_cells). B3-2: AABX's Earthpower (0x4b) and AAGX's Salvage (0x4c) are.
const UNIT_ROW := [[0xb, 0x31, 30, ["AHGW", "AEDX", "AAAR"], 0x9f], [0, 0x39, 40, ["AHGW", "AEDX"], 0xa1], [0x12, 0x3a, 30, ["AHGR"], 0xa3],
	[2, 0x3b, 40, ["AHGR", "AMMX", "ARGX"], 0xa5], [0x29, 0x5e, 100, ["ARGX"], 0x37c], [0xa, 0x3c, 20, ["AHGB", "AEOX"], 0xa7],
	[0x2f, 0x36, 45, ["AUMX"], 0x86], [0x2c, 0x56, 45, ["AEOX"], 0x38a], [0x25, 0x58, 25, ["ALMX"], 0x374], [0x26, 0x5d, 40, ["ALGX"], 0x376],
	[0x27, 0x5c, 30, ["ALMX"], 0x378], [4, 0x35, 20, ["AAHA", "AHGB"], 0xdc], [8, 0x34, 25, ["AENX"], 0xda], [3, 0x3d, 50, ["AENX"], 0xa9],
	[1, 0x3e, 40, ["AWNX", "AONX"], 0xab], [0xe, 0x3f, 25, ["AONX", "AMMX"], 0xad], [9, 0x40, 50, ["AWNX", "AONX"], 0xaf],
	[0x11, 0x19, 25, ["AEGX", "ASSC"], 0xde], [0xc, 0xc, 20, ["AWJX", "AWKX"], 0xe0], [5, 0x41, 35, ["AKNX", "AMMX"], 0xe4], [6, 0x42, 45, ["AKNX"], 0xe6],
	[0x15, 0x45, 40, ["AADE"], 0x199], [0x16, 0x46, 100, ["AVGX"], 0x19c], [0x1d, 0x4f, 40, ["AUGX"], 0x2d0], [0x28, 0x59, 45, ["AKOX"], 0x37a],
	[0x1e, 0x50, 40, ["AFGX"], 0x2d6], [0x17, 0x48, 30, ["AVGX"], 0x19f], [7, 0x43, 40, ["AKNX"], 0xe8], [0xd, 0x1e, 35, ["AKGX", "ALBX"], 0x8b],
	[0x1b, 0x4d, 40, ["ADOX"], 0x2a3], [0x1c, 0x4e, 100, ["ADOX"], 0x2a5], [0x1f, 0x51, 50, ["AHGX"], 0x363], [0x20, 0x53, 30, ["AGGX"], 0x36a],
	[0x21, 0x52, 55, ["AGGX"], 0x368], [0x23, 0x55, 35, ["AAJX"], 0x36f], [0x2b, 0x5a, 75, ["AOKX"], 0x386], [0x2d, 0x61, 45, ["AHGX"], 0x450],
	[0x18, 0x4b, 40, ["AABX"], 0x1ad], [0x1a, 0x4c, 0, ["AAGX"], 0x20e]]   # B3-2 (E15): Earthpower (race 10, PEPO), Salvage (always on)
## B3-2 (E15, Emulated "unit_cells"): Earthpower's cell only for a local Dark Dwarf player, enabled with PEPO and the mana; Salvage's
## always enabled (no mana). The key (0x426350 case 0x18) tests neither race nor PEPO (Read, decompile of 0x426350).
const EARTHPOWER_CASE := 0x18
const EARTHPOWER_RACE := 10
const EARTHPOWER_RESEARCH := "PEPO"
const SALVAGE_CASE := 0x1a
const SALVAGE_MS := 1000                # 0x4cfce0: at most once per second (timeGetTime + 1000; game clock here)
const FAMINE_CASE := 42
const SUMMON_CASES := [21, 28, 29, 41, 0x16, 0x23, 0x2b, 6, 0x28, 0x20]   # B4-2: Raise Zombie, Queen Spider; B5-2: Eye of Oros  # 0x426350 passes the caster's cell as the summon target

signal cast_done(info: Dictionary)    # a record was applied: {"caster", "spell", "level", "record", "result"}
signal notice(text: String)
signal dropped(info: Dictionary)      # B1-6a Rune Item: {"item", "cell", "owner"}
signal floated(info: Dictionary)      # P-2: presentation only, a floating text 0x53a010: {"id", "line", "value", "colour", "ms"}

## The Combat world, held weakly: Combat owns this object (`combat.spells`), so a strong reference back would be a
## RefCounted cycle and leak every world (as UnitAI, REVIEW_ENCOUNTERS.md D7).
var _world: WeakRef
var combat:
	get: return _world.get_ref() if _world != null else null
	set(value): _world = weakref(value) if value != null else null
var production
var host                              # the scene (main.gd): add_unit, mines, economy, selected_units, view_rect
var mines                             # simulation/mines.gd (Famine)
var economy
var navigator
var table: Dictionary = {}
var famine_stamp: Dictionary = {}     # building id -> ms of the last Dunekeep click
var salvage_ms := -100000             # B3-2: 0x4cfce0's stamp (the next Salvage allowed at this game time)
var cheat := false                    # 0xa27d6c: spells cost nothing
var mana_gate := 100                  # B1-6b: 0x7494c4 (100 at match setup, 0x41b860; Freeze Magic sets its amount)
var mana_gate_until := 0              # B1-6b: 0x7494c8
var hero_spells                       # B1-6a: simulation/hero_spells.gd (the human cast path, the schools' builders)

static var _army_mana: Dictionary = {}
static var _table_cache: Dictionary = {}

static func load_table() -> Dictionary:
	if _table_cache.is_empty():
		var text := FileAccess.get_file_as_string(TABLE_PATH)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary: _table_cache = parsed
	return _table_cache

## Army.cfg MANA pair by type (catalogue.json army rows, first row of a code as 0x585970 finds it).
static func army_mana(type_id: String) -> Array:
	if _army_mana.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE_PATH))
		if parsed is Dictionary:
			for row in parsed.get("army_cfg", {}).get("armies", []):
				if not _army_mana.has(row.code): _army_mana[row.code] = row.get("mana", null)
		_army_mana["__loaded"] = true
	var pair = _army_mana.get(type_id, null)
	return pair if pair is Array else []

func _init(combat_world, scene = null):
	combat = combat_world
	production = combat.production
	navigator = combat.navigator
	host = scene
	table = load_table()
	hero_spells = HeroSpells.new(self)
	combat.spells = self
	if production != null and production.has_signal("research_completed"):
		production.research_completed.connect(_on_research_completed)   # B1-6e: PSPR / PARR -> 0x438180
	for f in combat.fighters.values(): setup_unit(f)
	if host is Node:
		var old = host.get_node_or_null("SpellKeys")
		if old != null: old.free()
		var keys := KeyHook.new()
		keys.name = "SpellKeys"
		keys.spells = self
		host.add_child(keys)

## The ability keys come before every other hot key (0x427f70 is the key handler's first test, after the chat-entry
## state): the scene's last child gets `_input` before the HUD layer (game_hud.gd handles its keys in `_input` too). An
## open HUD dialog or the options screen keeps its keys.
class KeyHook extends Node:
	var spells
	func _input(event: InputEvent):
		var host = spells.host
		# B1-6a: the placement cursor of a pending Black Portal / Summon Guardian (0x425150 mode 9) takes the next click.
		if event is InputEventMouseButton and event.pressed and String(spells.hero_spells.pending.get("mode", "")) == "place":
			if spells.placement_click(event): get_viewport().set_input_as_handled()
			return
		if not event is InputEventKey or not event.pressed or event.echo: return
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
		var hud = host.get("hud") if host != null else null
		if hud != null and (String(hud.get("dialog")) != "" or (hud.has_method("options_open") and hud.options_open())): return
		var owner_id: int = int(host.get("local_player")) if host != null else 0
		# B1-6a: F1..F8 (0x10a..0x111, 0x459c60) cast the hero's hot key slots (0x427fb0 -> 0x5717e0).
		if event.keycode >= KEY_F1 and event.keycode <= KEY_F8 and host != null and int(host.get("hero_unit_id")) >= 0:
			var slot := int(event.keycode - KEY_F1)
			var spell: int = int(spells.hero_spells.hotkey_slots(owner_id)[slot])
			var result: Dictionary = spells.hero_spells.hotkey(owner_id, slot, int(host.get("hero_unit_id")), owner_id)
			if hud != null and hud.has_method("spell_request_shown"): hud.spell_request_shown(spell, result)   # REVIEW D1
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and not spells.hero_spells.pending.is_empty():
			spells.hero_spells.cancel_pending()
			get_viewport().set_input_as_handled()
			return
		if spells.hot_key(int(event.keycode), owner_id): get_viewport().set_input_as_handled()

func now() -> int:
	return int(combat.now_ms)

## The scene's mines and economy are read when needed (the skirmish sets them up after the combat world).
func _mines():
	return host.get("mines") if host != null and host.get("mines") != null else mines

func _economy():
	return host.get("economy") if host != null and host.get("economy") != null else economy

# ------------------------------------------------------------------------------------------------ unit mana
## 0x528cd0 (Emulated, unit_mana in the fixtures): maximum = MANA first + 15 x level of PLIX (else PSOX), current =
## MANA second + the same; a computer player's unit starts 10 higher when that stays within the maximum. No MANA pair:
## no mana (+0x20a = 0, the abilities never fire). Heroes keep the pool (combat.gd _regenerate_mana).
func setup_unit(f):
	if not f.hero and not f.has("poison_gate_checked"):
		f["poison_gate_checked"] = true
		_poison_gate(f)
	if f.hero or f.has("max_mana"): return
	var pair := army_mana(String(f.type_id))
	if pair.is_empty(): return
	var bonus := 0
	if production != null:
		bonus = production.research_level(f.owner, "PLIX")
		if bonus == 0: bonus = production.research_level(f.owner, "PSOX")
	f["max_mana"] = bonus * 15 + int(pair[0])
	f["mana"] = bonus * 15 + int(pair[1])
	if combat.ai_players.has(f.owner) and int(pair[1]) + COMPUTER_START_MANA <= int(pair[0]):
		f.mana = int(f.mana) + COMPUTER_START_MANA
	f["mana_ms"] = 0

## 0x51b580 for a unit (Emulated): (3000 - rank x 100) x 100 / (0x611220[Summon Mana level] + effect 0x21) ms, with
## 6000 / 200 for STATUS bit 23 (the Daemon).
func unit_mana_interval(f) -> int:
	if int(f.get("max_mana", 0)) < 1: return 0
	var base := 3000
	var per_rank := 100
	if int(f.base.get("flags", 0)) >> 23 & 1:
		base = 6000
		per_rank = 200
	var level: int = production.research_level(f.owner, "PMRX") if production != null else 0
	var rates: Array = table.get("mana_rate", [100, 150, 200, 300])
	var divisor: int = int(rates[clampi(level, 0, rates.size() - 1)]) + status_value(f, STATUS_MANA_RATE)
	if divisor == 0: return 0
	return ((base - int(f.get("rank", 0)) * per_rank) * 100) / divisor

## 0x51b6b0, unit branch (Read; the interval is Emulated): nothing at full mana; a computer player's interval is
## shortened by 0x611234[AI value]; the first tick arms the timer (+0x18c), later due ticks add 1 and re-arm.
func _regenerate_unit(f):
	# Performance (P-2): no pool or a full pool returns first; unit_mana_interval has no side effects.
	if int(f.get("max_mana", 0)) < 1 or int(f.max_mana) <= int(f.mana): return
	var interval := unit_mana_interval(f)
	if interval < 1: return
	if not mana_flowing(): return                     # B1-6b: 0x51b6b0 returns while 0x7494c4 < 1 (Freeze Magic)
	if int(f.max_mana) <= int(f.mana): return
	if combat.ai_players.has(f.owner) and production != null:
		var terms: Array = table.get("mana_computer", [0, 0, 0, 0, 0, 0, 0, 0])
		interval -= int(terms[clampi(int(production.ai_players.get(f.owner, 0)), 0, terms.size() - 1)])
	if int(f.mana_ms) == 0: f.mana_ms = interval + now()
	if int(f.mana_ms) <= now():
		f.mana_ms = interval + now()
		f.mana = int(f.mana) + 1

## 0x51b340 / 0x51b370: enough unit mana (and a mana pool at all), and paying it (clamped at 0).
static func has_unit_mana(f, amount: int) -> bool:
	return int(f.get("mana", 0)) >= amount and int(f.get("max_mana", 0)) >= 1

static func pay_unit_mana(f, amount: int):
	f.mana = maxi(0, int(f.mana) - amount)

# ------------------------------------------------------------------------------------------------ the match tick
## Called by combat.gd once per 25 ms update after the units: unit mana, hero cooldowns (0x51c6a0 clears +0x268 when
## due), the cast sequences (state 6) and expired status effects.
## 0x532a20 (every 40th world frame) keeps unit +0x190 set while the unit is near its owner's living hero (the source list
## is the living heroes of the side and its allies, each with its conversion radius: combat.near_hero); 0x51c460 adds 2 to the speed,
## 1 for STATUS bit 2 (Read, decompile of 0x51c460; playtest 2026-11-11: the walking speed lacked it).
const AURA_TICK_MS := 1000
var aura_next_ms := 0

func aura_speed(f) -> int:
	if not bool(f.get("hero_aura", false)): return 0
	return 1 if (int(f.stats.get("flags", 0)) & 4) != 0 else 2

func _step_aura(t: int):
	aura_next_ms = t + AURA_TICK_MS
	for f in combat.fighters.values():
		if f.removed or f.hero or not combat.alive(f): continue
		var near: bool = combat.near_hero(f)
		if bool(f.get("hero_aura", false)) == near: continue
		f["hero_aura"] = near
		sync_speed(f)

func step():
	var t := now()
	if t >= aura_next_ms: _step_aura(t)
	for id in combat.fighters.keys():
		var f = combat.fighters[id]
		# B1-6d (Emulated, REVIEW_HERO_SPELLS_D.md U2 / D1): 0x51c7d0 removes a dying unit quietly (0x51a130(1)) once its
		# lifetime +0x1ec has passed (+0x1ec is never cleared): timed summons leave no body.
		var living: bool = combat.alive(f)                # P-3: asked once (nothing changes between the two tests)
		if not f.removed and not living and int(f.get("lifetime_until", 0)) != 0 and t > int(f.lifetime_until):
			_remove_quietly(int(id))
			continue
		if f.removed or not living: continue
		# Performance (P-3): the calls below are made only when their own first test would not return at once (same tests).
		if not f.hero and int(f.get("max_mana", 0)) >= 1 and int(f.max_mana) > int(f.mana): _regenerate_unit(f)
		if int(f.get("cooldown_until", 0)) != 0 and t >= int(f.cooldown_until):
			f.cooldown_until = 0
			f.cooldown_start = 0
		if f.has("statuses"):
			# Performance (P-2): the list is rebuilt only when an entry has run out (the filter keeps the same entries).
			var expired := false
			for s in f.statuses:
				if int(s.until) <= t:
					expired = true
					break
			if expired:
				var before: int = f.statuses.size()
				f.statuses = f.statuses.filter(func(s): return int(s.until) > t)
				if f.statuses.size() != before: sync_speed(f)
		if f.has("shadow") or f.has("invisible_until") or f.has("lifetime_until") or f.has("fear"):
			_step_illusion_states(f, t)                   # B1-6d: Shadowform, invisibility, lifetimes, fear
		if bool(f.get("diseased", false)): _step_disease(f, t)   # B1-6e: the disease's count and end
		if f.get("berserk") != null: _step_berserk(f, t)   # B2-1: the drain and the end of the berserk state (may kill the unit)
		if f.get("cast") != null and combat.alive(f): _update_cast(f)   # the steps above may have killed the unit
	# B1-6b: 0x532330 (Read) restores the unit-mana gate 0x7494c4 to 100 once Freeze Magic's 0x7494c8 has passed.
	if mana_gate_until != 0 and mana_gate_until < t:
		mana_gate_until = 0
		mana_gate = 100
	hero_spells.step(t)
	_scavenge_records()
	_sync_sight()                                     # B1-6c: See Invisible -> visibility.gd
	_sync_invisible()                                 # B1-6d: +0x1f1 -> visibility.gd

# ------------------------------------------------------------------------------------------------ cost and dispatch
## 0x529fa0 (Emulated by the review): table cost x max(25, 100 - effect 0x24 - item power 0x24 (heroes only)) / 100.
func cost(f, spell: int) -> int:
	var base := table_cost(spell)
	var off := status_value(f, STATUS_MANA_COST)
	if f.hero: off += HeroEffects.item_stat(combat.hero_block(f.owner), 0x24)
	return (maxi(25, 100 - off) * base) / 100

func table_cost(spell: int) -> int:
	var costs: Array = table.get("cost", [])
	return int(costs[spell]) if spell >= 0 and spell < costs.size() else 0

## The owner's hero mana pool 0x70931c (the hero fighter's "mana"); -1 when the owner has no hero object.
func hero_pool(owner: int) -> int:
	var h = _hero_fighter(owner)
	return int(h.get("mana", 0)) if h != null else -1

func _hero_fighter(owner: int):
	if not combat.heroes.has(owner): return null
	var h = combat.fighters.get(combat.heroes[owner].unit)
	return h if h != null and not h.removed else null

## 0x5777a0 (Emulated by the review for the payer and cooldown): caster = {"kind": "unit" | "building", "id"}.
## A unit caster (vtable +0x28 = 0, hero or not) costs max(1, cost()); a building the raw table entry; nothing with pay
## false or the cheat flag. A hero with a running cooldown casts nothing; otherwise the cooldown becomes
## now + (max(5, table) x (id % 10 + 1) + (level x 5 + 50) x 2) x 10 ms, even when nothing is paid. The cost always comes
## from the owner's hero pool (clamped at 0). Level < 1 is a failed cast (message 0x456; nothing is built).
func dispatch(caster: Dictionary, spell: int, level: int, target: Dictionary = {}, pay: bool = true) -> Dictionary:
	var f = combat.fighters.get(int(caster.id)) if caster.kind == "unit" else null
	var owner: int = int(f.owner) if f != null else int(production.building(int(caster.id)).owner)
	var price: int
	var hero: bool = f != null and bool(f.hero)
	if f != null: price = maxi(1, cost(f, spell))
	else: price = table_cost(spell)
	if cheat or not pay: price = 0
	if hero:
		if int(f.get("cooldown_until", 0)) != 0:
			# P-3 (0x5777a0, decompile 245713-245721, Read): the local player's hero floats Game.txt [0x47e], colour 1, 1000 ms.
			floated.emit({"id": int(f.id), "line": 0x47e, "value": 0, "colour": 1, "ms": 1000, "owner": owner, "local_only": true})
			return {"cast": false, "reason": "cooldown"}
		f["cooldown_start"] = now()
		f["cooldown_until"] = now() + (maxi(5, table_cost(spell)) * (spell % 10 + 1) + (level * 5 + 50) * 2) * 10
	if price > 0:
		var h = _hero_fighter(owner)
		if h != null: h.mana = maxi(0, int(h.mana) - price)
	if pay and hero: hero_spells.gem[owner] = 0      # B1-6a: 0x70d54c[owner] = 0 after a paid hero cast (Read, 245749)
	if level < 1:
		if hero: notice.emit("The spell failed")         # B1-6a: Game.txt 0x456 and the fizzle 0x58c0d0 (Read)
		return {"cast": false, "reason": "failed", "paid": price}
	var result: Dictionary
	if BUILDERS.has(spell): result = cast_record(String(BUILDERS[spell]), caster, level, target)
	elif hero_spells.has_builder(spell): result = cast_built(hero_spells.build(spell, caster, level, target), caster, level, spell)
	else: return {"cast": false, "reason": "not built yet", "paid": price}
	if hero and bool(result.get("cast", false)): hero_spells.casts[owner] = int(hero_spells.casts.get(owner, 0)) + 1
	result["paid"] = price
	return result

## Builds one record with `builder` and applies it.
func cast_record(builder: String, caster: Dictionary, level: int, target: Dictionary = {}) -> Dictionary:
	return cast_built(call(builder, caster, level, target), caster, level)

## Applies a built record (B1-6a: the schools' builders live in hero_spells.gd). An empty record is a refusal, except for
## the spell that acts without one (Rune Item 78).
func cast_built(record: Dictionary, caster: Dictionary, level: int, spell: int = -1) -> Dictionary:
	if record.is_empty():
		if spell in HeroSpells.NO_RECORD:
			var done := {"cast": true, "caster": caster, "level": level, "record": {}, "result": {}, "spell": spell}
			cast_done.emit(done)                         # B1-6e: the drop / the trade dialog happened
			return done
		return {"cast": false, "reason": "refused"}
	# B1-6b: a function that sends two records (Purify, Call of Kargoth) returns {"records": [...]}, applied in order;
	# the summons of one cast share the command counts as they stood (0x4aa840 reads them, the units arrive later).
	if record.has("records"):
		var shared := {}
		var infos: Array = []
		for r in record.records:
			r["free_cache"] = shared
			infos.append(cast_built(r, caster, level, spell))
		var last: Dictionary = infos[-1].duplicate()
		last["results"] = infos.map(func(i): return i.get("result", {}))
		return last
	var result := SpellEffects.apply(record, self)
	var info := {"cast": true, "caster": caster, "level": level, "record": record, "result": result, "spell": spell}
	_present(record, result)
	cast_done.emit(info)
	return info

## 0x529d20 (Read; called by the strike method 0x51ab00 for a hero before the blow, playtest 2026-11-11): the player's
## living hero object (0x70adb4[owner]), No Hero Items clear and no running cooldown (+0x268): for each of the seven
## equipped items, each of its first three powers of type 0x62 ("cast spell") rolls 1d100 on the match generator and below
## its chance casts the power's spell (data) at its level through the dispatcher without payment (0x5777a0(.., 0)), so the
## cast sets the hero's cooldown like any cast and later rolls of the same strike cast nothing. The target is the unit's
## +0x17c, the order-9 target of its last cast, which the rebuild does not keep: the struck object is passed instead
## (Provisional). Returns whether a roll succeeded.
func item_casts(f, kind: String, id: int) -> bool:
	if f == null or not bool(f.hero) or not combat.heroes.has(int(f.owner)) or int(combat.heroes[int(f.owner)].unit) != int(f.id): return false
	var block: Dictionary = combat.hero_block(int(f.owner))
	if bool(block.get("no_items", false)) or int(f.get("cooldown_until", 0)) != 0: return false
	var cell: Vector2i = combat.unit_cell(id) if kind == "unit" else combat.nearest_target_cell(f, {"target_kind": kind, "target_id": id})
	var target := {"x": cell.x, "y": cell.y, "id": id if kind == "unit" else -1, "extra": 0}
	var hit := false
	var equipment: Array = block.get("equipment", [])
	for slot in mini(7, equipment.size()):
		var item_id := int(equipment[slot])
		if item_id <= 0: continue
		var powers: Array = HeroEffects.item(item_id).get("powers", [])
		for k in mini(3, powers.size()):
			if int(powers[k].get("type", 0)) != 0x62: continue
			if combat.rng.roll(1, 100, 0) < int(powers[k].get("chance", 0)):
				dispatch({"kind": "unit", "id": int(f.id)}, int(powers[k].get("data", 0)), int(powers[k].get("level", 1)), target, false)
				hit = true
	return hit

# ------------------------------------------------------------------------------------------------ the cast order
## 0x51d3b0 (Read): order 9 with +0x174 pending, +0x176 spell, +0x178 level, +0x17c target; a repeated identical order
## keeps the running one. The unit stops and plays state 6 (ANI slot 6, CAST_ENTRY_MS per entry); at the slot's +0x18
## entry 0x5394a0 calls 0x523150 with event 7, which clears the pending flag and dispatches (pay 1). A negative spell id
## is handled as event 2 (the attack hit) there, so it never casts this way.
func order_cast(unit_id: int, spell: int, level: int, target: Dictionary = {}) -> bool:
	var f = combat.fighters.get(unit_id)
	if f == null or not combat.alive(f) or spell < 0: return false
	var cur = f.get("cast")
	if cur != null and int(cur.spell) == spell: return true
	var sheet := _slot6(String(f.type_id))
	reveal(f)                                         # B1-6d: 0x536cc0 (the cast state 6) ends invisibility (0x5285b0(0, 0))
	f["cast"] = {"spell": spell, "level": level, "target": target, "start_ms": now(), "pending": true,
		"frames": int(sheet.get("frame_count", 0)), "event_entry": int(sheet.get("ani_unknown_words", {}).get("0x18", 0))}
	combat.order_stop(unit_id)
	return true

func _slot6(type_id: String) -> Dictionary:
	return ArtData.unit_sheet(type_id, 6)

func _update_cast(f):
	var c: Dictionary = f.cast
	var entry := (now() - int(c.start_ms)) / CAST_ENTRY_MS
	if c.pending and entry >= int(c.event_entry):
		c.pending = false
		c["result"] = dispatch({"kind": "unit", "id": f.id}, int(c.spell), int(c.level), c.target, true)
	var frames := int(c.frames)
	var unit = combat.units[f.id]
	if entry > frames:
		f.cast = null
		unit.anim = {}
		return
	# 0x536cc0's state 6 sequence: entries 0..F show slot 6 frame i, the last two the idle frame (slot 0, row 4).
	if frames > 1 and entry < frames - 1: unit.anim = {"slot": 6, "row": unit.direction, "index": entry, "frames": frames}
	else: unit.anim = {"slot": 0, "row": 4, "index": 0, "frames": 1}

# ------------------------------------------------------------------------------------------------ the abilities
## 0x427f70 + 0x426350 (keys Emulated from 0x425bf0, cases Read): every case whose key matches is tried in index order
## until one casts; the original checks these before any other hot key. Returns whether a case cast.
func hot_key(keycode: int, owner: int) -> bool:
	var keys: Array = table.get("keys", [])
	for i in keys.size():
		if int(keys[i]) != keycode: continue
		if i == FAMINE_CASE:
			if famine_key(owner): return true
			continue
		if i == SWORD_CASE:                   # G-2: the Shrine's Sword of Sirian key (case 0x2e)
			sword_key(owner)
			continue
		if i == HOLY_CASE:                    # B4-1 (R8): Holy Word's O and Elcor's Balm's Q return 0
			holy_key(owner)
			continue
		if i == ELCOR_CASE:
			elcor_key(owner)
			continue
		if i == CHAOS_CASE:                   # B5-1 (E6 / V1): Chaos Plague's C and Couatl's Wrath's W are free and return 0
			chaos_key(owner)
			continue
		if i == WRATH_CASE:
			wrath_key(owner)
			continue
		if not table.get("cases", {}).has(str(i)): continue
		if ability(i, owner): return true
	return false

## One 0x426350 case. 0x427cf0: the first selected unit of the case's types (in their order) with the mana, else a unit of
## the local player of that type in the view rectangle; then the case's own command check (0x5776c0), the unit's mana is
## paid (0x51b370) and the builder runs at level (rank + 1) / 5 + 1.
func ability(case_index: int, owner: int) -> bool:
	var row: Dictionary = table.cases.get(str(case_index), {})
	if row.is_empty() or not has_case(case_index): return false
	var mana: int = int(row.mana)
	var f = null
	if case_index == INVISIBILITY_CASE and _invisibility_selection(mana): return false   # B4-2 (R5): the case returns 0
	# B4-2 (R5, Emulated review "keys"): case 0xc asks a selected Treant (selection only), then AWKX, then AWJX (selection, then view).
	var order: Array = ["AWJX", "AWKX", "AWJX"] if case_index == ENTANGLE_CASE else row.casters
	for i in order.size():
		f = find_caster(String(order[i]), mana, owner, case_index == ENTANGLE_CASE and i == 0)
		if f != null: break
	if case_index == SALVAGE_CASE:
		# B3-2 (E16, Read 0x426350 case 0x1a -> 0x4cfce0): no mana; at most once per second (stamped when it runs).
		if f == null or (salvage_ms > -100000 and now() < salvage_ms): return false
		salvage_ms = now() + SALVAGE_MS
		cast_case(case_index, {"kind": "unit", "id": f.id}, (int(f.get("rank", 0)) + 1) / 5 + 1)
		return true
	if f == null or not has_unit_mana(f, mana): return false
	if row.command_check != null and not command_free(int(f.owner), String(row.command_check)): return false
	pay_unit_mana(f, mana)
	var level := (int(f.get("rank", 0)) + 1) / 5 + 1
	var target := {}
	if case_index in SUMMON_CASES:
		var cell: Vector2i = combat.unit_cell(f.id)
		target = {"x": cell.x, "y": cell.y, "id": -1}
	cast_case(case_index, {"kind": "unit", "id": f.id}, level, target)
	return true

## B4-2 (R5, Emulated review "keys"; decompile of 0x426350 case 0xd): every selected AKGX / ASWM (ALBX with PBLE) with the mana pays
## and casts Invisibility; when one did, the case returns 0. Returns whether one did.
const ENTANGLE_CASE := 0xc
const INVISIBILITY_CASE := 0xd
func _invisibility_selection(mana: int) -> bool:
	var selected: Array = host.selected_units() if host != null and host.has_method("selected_units") else []
	var any := false
	for unit in selected:
		var f = combat.fighters.get(unit.unit_id)
		if f == null or not combat.alive(f): continue
		var t := String(f.type_id)
		if not (t == "ASWM" or t == "AKGX" or (t == "ALBX" and production.research_level(int(f.owner), "PBLE") != 0)): continue
		if not has_unit_mana(f, mana): continue
		pay_unit_mana(f, mana)
		cast_case(INVISIBILITY_CASE, {"kind": "unit", "id": f.id}, (int(f.get("rank", 0)) + 1) / 5 + 1)
		any = true
	return any

## B4-2 (E14, Emulated "abilities"): 0x578c90 Multi-Target (case 0x11, AEGX and ASSC): kind 0x10, a missile per enemy object (units
## and buildings, alive) within max(10, the type's attack range), EMA1 (ASSC EMA4), amount 0x40dd50(owner, 50 + 2 x rank), x 3 / 4
## for ASSC; the ability level is not used.
func _multi_target(caster: Dictionary, _level: int, _target := {}) -> Dictionary:
	var f = _caster_fighter(caster)
	var owner: int = object_of(String(caster.kind), int(caster.id)).get("owner", 0)
	var assc: bool = f != null and String(f.type_id) == "ASSC"
	var amount := spell_power(owner, 50 + 2 * int(f.get("rank", 0) if f != null else 0))
	if assc: amount = amount * 3 / 4
	var radius := maxi(10, int(f.stats.get("range", 0)) if f != null else 0)
	return _record(caster, {"b6": 0xff, "sound": 5, "radius": radius, "b9": 2, "b12": 4, "kind": SpellEffects.MISSILES, "amount": amount,
		"w9d": radius, "summon": "EMA4" if assc else "EMA1"})

## 0x579b90 Queen Spider (case 0x28, AKOX): one AKLX at the caster's cell, EZ08, +6 = 0x35, experience 0x557d90 + 20 x (level - 1);
## its own command check (the case checks AKLX before paying too).
func _queen_spider(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon_record(caster, level, target, "AKLX", 1, 20, {"b6": 0x35, "sound": 5, "effect2": "EZ08", "w9d": 1})

func has_case(case_index: int) -> bool:
	return CASE_BUILDERS.has(case_index) or HERO_CASE_BUILDERS.has(case_index)

## The case's record, built as 0x426350 calls the function.
func build_case(case_index: int, caster: Dictionary, level: int, target: Dictionary = {}) -> Dictionary:
	if HERO_CASE_BUILDERS.has(case_index): return hero_spells.call(String(HERO_CASE_BUILDERS[case_index]), caster, level, target)
	return call(String(CASE_BUILDERS[case_index]), caster, level, target)

func cast_case(case_index: int, caster: Dictionary, level: int, target: Dictionary = {}) -> Dictionary:
	return cast_built(build_case(case_index, caster, level, target), caster, level)

## The rows of UNIT_ROW a selection of `type_id` shows, in the chain's order.
static func unit_row(type_id: String) -> Array:
	return UNIT_ROW.filter(func(row): return Array(row[3]).has(type_id))

## B3-2 (E15): the rows a selection of `type_id` shows for the local player `owner` (Earthpower only for race 10).
func unit_row_for(type_id: String, owner: int) -> Array:
	return unit_row(type_id).filter(func(row): return int(row[0]) != EARTHPOWER_CASE or (production != null and production.race_of(owner) == EARTHPOWER_RACE))

## 0x4d4840 for each of the row's types: a selected unit of the type has the mana (`units`: the selected unit nodes).
func unit_row_enabled(row: Array, units: Array) -> bool:
	if not has_case(int(row[0])): return false
	if int(row[0]) == SALVAGE_CASE: return units.any(func(u): return combat.fighters.has(u.unit_id) and combat.alive(combat.fighters[u.unit_id]))
	if int(row[0]) == EARTHPOWER_CASE and not units.is_empty() and production.research_level(int(units[0].owner_id), EARTHPOWER_RESEARCH) == 0: return false
	for unit in units:
		var f = combat.fighters.get(unit.unit_id)
		if f != null and combat.alive(f) and Array(row[3]).has(String(f.type_id)) and has_unit_mana(f, int(row[2])): return true
	return false

## 0x427cf0(type, mana, selection_only) (B4-2, R5: `selection_only` skips the view scan, case 0xc's first pass).
func find_caster(type_id: String, mana: int, owner: int, selection_only := false):
	var selected: Array = host.selected_units() if host != null and host.has_method("selected_units") else []
	for unit in selected:
		var f = combat.fighters.get(unit.unit_id)
		if f != null and not f.hero and combat.alive(f) and String(f.type_id) == type_id and (mana == 0 or has_unit_mana(f, mana)):
			return f
	if selection_only: return null
	var rect := Rect2i()
	if host != null and host.has_method("view_rect") and host.get("collision") != null:
		var r: Rect2 = host.view_rect()
		var a: Vector2i = host.collision.world_cell(r.position)
		rect = Rect2i(a, host.collision.world_cell(r.end) - a + Vector2i.ONE)
	for f in combat.fighters.values():
		if f.removed or f.hero or not combat.alive(f) or f.owner != owner or String(f.type_id) != type_id: continue
		if rect.size != Vector2i.ZERO and not rect.has_point(combat.unit_cell(f.id)): continue
		if mana == 0 or has_unit_mana(f, mana): return f
	return null

## 0x426350 case 0x2a (Read; REVIEW_SPELLS.md D4): with Famine researched (PFAX), for each of BKR4..BKR0 in turn
## 0x427e30(type, 1) takes the selected building of that type, else any of the local player's on the map; 500 crystal
## (else the "not enough" cue 0x50f1b0(0x14)); no throttle on the key. The case returns 0 even after casting, so the key
## handler goes on to later cases with the same key.
## B4-1 (decision 8): the building through key_building (0x427e30), unfinished Dunekeeps included as in the original.
func famine_key(owner: int) -> bool:
	if production.research_level(owner, "PFAX") == 0: return false
	for code in ["BKR4", "BKR3", "BKR2", "BKR1", "BKR0"]:
		var pick = key_building(owner, code)
		if pick != null:
			famine(int(pick.entity_id), false)
			return false
	return false

func _building_selected(b) -> bool:
	return host != null and host.get("selected_building_id") != null and int(host.get("selected_building_id")) == int(b.entity_id)

## B4-1 (BATCH4_RESEARCH.md R8, Emulated review "keys"; decompile 26176-26229): 0x427e30(type, 1), the building of a key case: a
## selected building of the type (the selection list, no owner test), else the local player's first of the type on the whole map,
## rows from the top, then x (the row lists 0x547b80 of the sprite cells), in any state (no construction test).
func key_building(owner: int, type_id: String):
	for b in production.buildings.values():
		if String(b.original_type_id) == type_id and _building_selected(b): return b
	var best = null
	var best_cell := Vector2i.ZERO
	for b in production.buildings.values():
		if int(b.owner) != owner or String(b.original_type_id) != type_id or int(b.hit_points) <= 0: continue
		var c: Vector2i = combat._building_sprite(b).cell
		if best == null or c.y < best_cell.y or (c.y == best_cell.y and c.x < best_cell.x):
			best = b
			best_cell = c
	return best

# ------------------------------------------------------------------------------------------------ B4-1: Holy Word, Elcor's Balm
## BATCH4_RESEARCH.md E10 / E11 / R8 (rules in race_powers.gd). The buttons are throttled (stamp first) and Holy Word's tests for an
## evil enemy unit within 14 (0x5002a0); the keys (cases 0x13 / 0x14) take key_building, pay and cast without either, and return 0.
const HOLY_CASE := 0x13
const ELCOR_CASE := 0x14
var holy_stamp := -1                  # 0xa4786c: ms until which the Holy Word buttons do nothing
var elcor_stamp := -1                 # 0xa47880 (Elcor's Balm)

## The cell's press (LAB at 0x4d1a00 -> 0x5002a0 -> 0x4d1ef0). Returns whether the record went out.
func holy_word(building_id: int) -> bool:
	var b = production.building(building_id)
	if b == null or b.constructing or production.research_level(b.owner, RacePowers.HOLY_RESEARCH) == 0: return false
	if holy_stamp >= 0 and holy_stamp > now(): return false
	holy_stamp = now() + RacePowers.HOLY_MS
	var eco = _economy()
	if eco == null or int(eco.stockpiles[int(b.owner)][2]) < RacePowers.HOLY_CRYSTAL:
		notice.emit("Not enough crystal")
		return false
	if not evil_enemy_near(int(b.owner), combat._building_sprite(b).cell, RacePowers.HOLY_REACH):
		notice.emit("No evil units near")             # the refused cue (0x4ca050); nothing paid
		return false
	return _holy_cast(b)

## 0x4d1ef0: 200 crystal (message 0x1fe), then the record.
func _holy_cast(b) -> bool:
	var eco = _economy()
	if eco == null or not eco.try_spend(int(b.owner), [0, 0, RacePowers.HOLY_CRYSTAL, 0]): return false
	cast_record("_holy_word", {"kind": "building", "id": int(b.entity_id)}, 1)
	return true

## 0x426350 case 0x13 (O): PHOL, the key building BPCA, 200 crystal or the cue; no throttle, no evil test; returns 0.
func holy_key(owner: int) -> bool:
	if production.research_level(owner, RacePowers.HOLY_RESEARCH) == 0: return false
	var b = key_building(owner, "BPCA")
	if b == null: return false
	var eco = _economy()
	if eco == null or int(eco.stockpiles[owner][2]) < RacePowers.HOLY_CRYSTAL:
		notice.emit("Not enough crystal")
		return false
	_holy_cast(b)
	return false

## 0x5002a0 -> 0x5002e0(sprite cell, 14, owner, enemies, units, alive, evil, stop 1): an enemy (not own, not allied) living unit
## on the map grid with STATUS 0x8000000 in the square of `reach` cells.
## B5-1 (E4): `status` 0 is Chaos Plague's 0x5007f0 -> 0x5002e0(14, enemies, units, alive), any enemy living unit.
func evil_enemy_near(owner: int, cell: Vector2i, reach: int, status: int = RacePowers.EVIL) -> bool:
	for f in combat.fighters.values():
		if f.removed or not combat.alive(f) or int(f.hp) < 1: continue
		if int(f.owner) == owner or allied(owner, int(f.owner)) or f.has("invisible_until"): continue
		if status != 0 and int(f.base.get("flags", 0)) & status == 0: continue
		var u = combat.units.get(int(f.id))
		if u == null or u.inside_building: continue
		var c: Vector2i = combat.unit_cell(int(f.id))
		if absi(c.x - cell.x) <= reach and absi(c.y - cell.y) <= reach: return true
	return false

## The cell's press (0x4d1e10 -> 0x4d2030). Returns whether the record went out.
func elcor_balm(building_id: int) -> bool:
	var b = production.building(building_id)
	if b == null or b.constructing or production.research_level(b.owner, RacePowers.ELCOR_RESEARCH) == 0: return false
	if elcor_stamp >= 0 and elcor_stamp > now(): return false
	elcor_stamp = now() + RacePowers.ELCOR_MS
	var eco = _economy()
	if eco == null or int(eco.stockpiles[int(b.owner)][2]) < RacePowers.ELCOR_CRYSTAL:
		notice.emit("Not enough crystal")
		return false
	return elcor_cast(b)

## 0x4d2030: message 0x1fe (400 crystal, 300 for a computer: 0x70d6a4[owner]), then 0x57b9d0(building, 1).
func elcor_cast(b) -> bool:
	var eco = _economy()
	if eco == null: return false
	var price: int = RacePowers.ELCOR_COMPUTER_CRYSTAL if combat.ai_players.has(int(b.owner)) else RacePowers.ELCOR_CRYSTAL
	eco.debit_clamped(int(b.owner), [0, 0, price, 0])
	cast_record("_elcor_balm", {"kind": "building", "id": int(b.entity_id)}, 1)
	return true

## 0x426350 case 0x14 (Q): PELC, key_building BPHE, else BPHO; 400 crystal or the cue; no throttle; returns 0.
func elcor_key(owner: int) -> bool:
	if production.research_level(owner, RacePowers.ELCOR_RESEARCH) == 0: return false
	var b = key_building(owner, "BPHE")
	if b == null: b = key_building(owner, "BPHO")
	if b == null: return false
	var eco = _economy()
	if eco == null or int(eco.stockpiles[owner][2]) < RacePowers.ELCOR_CRYSTAL:
		notice.emit("Not enough crystal")
		return false
	elcor_cast(b)
	return false

## 0x4d1ef0's record (Emulated "powers.holy"): kind 0x10, a missile EMM2 per evil enemy unit within 15, amount 50, damage type 4.
func _holy_word(caster: Dictionary, _level: int, _target := {}) -> Dictionary:
	return _record(caster, {"b6": 0xff, "sound": 9, "radius": 15, "b9": 2, "b10": 1, "b12": 4, "kind": SpellEffects.MISSILES,
		"amount": 50, "w9b": 4, "w9d": 15, "summon": "EMM2", "d135": RacePowers.EVIL})

## 0x57b9d0(building, 1) (Emulated "powers.elcor"): kind 0x14 (heal and cure), amount 0x40dd50(owner, 100), radius 0xff, friendly
## hurt units (b12 2), EZ11.
func _elcor_balm(caster: Dictionary, _level: int, _target := {}) -> Dictionary:
	var owner: int = object_of(String(caster.kind), int(caster.id)).get("owner", 0)
	return _record(caster, {"b6": 7, "sound": 11, "radius": 0xff, "b9": 1, "b10": 1, "b11": 1, "b12": 2, "effect": "EZ11", "effect2": "EZ11",
		"kind": SpellEffects.HEAL_CURE, "amount": spell_power(owner, 100)})

## B4-1 (E7, Emulated "powers.sacrifice"): the record of 0x4ced00: kind 0x1b, the targets and their cells, AADE, EZ08, +0x9b = 1 when
## the roll <= 4 x n. No caster object (the record's caster is -1).
func sacrifice_record(owner: int, ids: Array, roll_value: int) -> Dictionary:
	var cells: Array = ids.map(func(id): return combat.unit_cell(int(id)))
	return {"caster_kind": "none", "caster": -1, "owner": owner, "area": 1, "b4": 0, "b6": 0xff, "sound": 0, "radius": 0, "b9": 0, "b10": 0,
		"b11": 0, "b12": 0, "d85": 0, "d89": 0, "effect": "", "effect2": RacePowers.SACRIFICE_EFFECT, "kind": RacePowers.SACRIFICE_KIND,
		"w97": -1, "amount": ids.size(), "w9b": 1 if RacePowers.sacrifice_daemon(roll_value, ids.size()) else 0, "w9d": 0, "w9f": 0,
		"cells": cells, "summon": RacePowers.SACRIFICE_DAEMON, "d131": 0, "d135": 0, "descriptors": [], "target_ids": ids.duplicate()}

## 0x4aa840 case 0x1b (Emulated "sacrifice_applied"): every target dies (0x4a9890, message 0x138), then with +0x9b = 1 one AADE on a
## free cell by the first target (0x43b4c0), EZ08 (message 0xfa without +0x3b: start experience).
func apply_sacrifice(record: Dictionary) -> Dictionary:
	var out := {"killed": [], "daemon": {}}
	var ids: Array = record.target_ids
	var first: Vector2i = record.cells[0] if not record.cells.is_empty() else Vector2i(-1, -1)
	for id in ids:
		var f = combat.fighters.get(int(id))
		if f == null or not combat.alive(f): continue
		combat.apply_damage("unit", int(id), maxi(1, int(f.hp)), -1, "none")
		out.killed.append(int(id))
	if int(record.w9b) == 1 and first.x >= 0:
		out.daemon = spawn(String(record.summon), first, int(record.owner), 0, 1, {"start": true})
	cast_done.emit({"caster": {"kind": "none", "id": -1}, "spell": RacePowers.SACRIFICE_KIND, "level": 1, "record": record, "result": out})
	return out

# ------------------------------------------------------------------------------------------------ B5-1: Chaos Plague, Couatl's Wrath
## BATCH5_RESEARCH.md E3-E6 (rules in race_powers.gd). The buttons are throttled (stamp first); Chaos Plague's tests for an enemy
## unit within 14; the keys (cases 0x22 / 0x24) take key_building, test the stock and cast without paying (decision 1), return 0.
const CHAOS_CASE := 0x22
const WRATH_CASE := 0x24
var chaos_stamp := -1                 # 0xa47870: ms until which the Chaos Plague buttons do nothing
var wrath_stamp := -1                 # 0xa4787c (Couatl's Wrath)

func _has_research(owner: int) -> Callable:
	return func(code): return production.research_level(owner, code) != 0

## The cell's press (LAB_004d1ae0 -> 0x5007f0 -> 0x4d20b0). Returns whether the record went out.
func chaos_plague(building_id: int) -> bool:
	var b = production.building(building_id)
	if b == null or b.constructing or production.research_level(b.owner, RacePowers.CHAOS_RESEARCH) == 0: return false
	if chaos_stamp >= 0 and chaos_stamp > now(): return false
	chaos_stamp = now() + RacePowers.CHAOS_MS
	var eco = _economy()
	if eco == null or int(eco.stockpiles[int(b.owner)][2]) < RacePowers.CHAOS_CRYSTAL:
		notice.emit("Not enough crystal")              # advisor 0x14
		return false
	if not evil_enemy_near(int(b.owner), combat._building_sprite(b).cell, RacePowers.CHAOS_REACH, 0):
		notice.emit("No enemy units near")             # the refused cue (0x4ca050); nothing paid
		return false
	return chaos_cast(b)

## 0x4d20b0 (the button's and the computer's payer): message 0x1fe (1000 crystal, no stock test), then 0x5771f0(hall, PCN level).
func chaos_cast(b, pay := true) -> bool:
	var eco = _economy()
	if eco == null: return false
	if pay: eco.debit_clamped(int(b.owner), [0, 0, RacePowers.CHAOS_CRYSTAL, 0])
	var caster := {"kind": "building", "id": int(b.entity_id)}
	var level := RacePowers.chaos_level(_has_research(int(b.owner)))
	cast_built(hero_spells._chaos_plague(caster, level), caster, level)
	return true

## 0x426350 case 0x22 (C): PCN0, crystal >= 1000 (advisor 0x14), key_building BKG4 .. BKG0, the cast without payment; returns 0.
func chaos_key(owner: int) -> bool:
	if production.research_level(owner, RacePowers.CHAOS_RESEARCH) == 0: return false
	var eco = _economy()
	if eco == null or int(eco.stockpiles[owner][2]) < RacePowers.CHAOS_CRYSTAL:
		notice.emit("Not enough crystal")
		return false
	for code in RacePowers.CHAOS_HALLS:
		var b = key_building(owner, code)
		if b != null:
			chaos_cast(b, false)
			return false
	return false

## The cell's press (LAB_004d1d70 -> 0x4d2190): no enemy test.
func couatls_wrath(building_id: int) -> bool:
	var b = production.building(building_id)
	if b == null or b.constructing or production.research_level(b.owner, RacePowers.WRATH_RESEARCH) == 0: return false
	if wrath_stamp >= 0 and wrath_stamp > now(): return false
	wrath_stamp = now() + RacePowers.WRATH_MS
	var eco = _economy()
	if eco == null or int(eco.stockpiles[int(b.owner)][0]) < RacePowers.WRATH_GOLD:
		notice.emit("Not enough gold")                 # advisor 0x11
		return false
	return wrath_cast(b)

## 0x4d2190: message 0x1fe (750 gold, no stock test), then 0x57a1e0(temple, PCWR level: one level, 1).
func wrath_cast(b, pay := true) -> bool:
	var eco = _economy()
	if eco == null: return false
	if pay: eco.debit_clamped(int(b.owner), [RacePowers.WRATH_GOLD, 0, 0, 0])
	cast_record("_couatls_wrath", {"kind": "building", "id": int(b.entity_id)}, 1)
	return true

## 0x426350 case 0x24 (W): PCWR, gold >= 750 (advisor 0x11), key_building BKL4 .. BKL0, free; returns 0.
func wrath_key(owner: int) -> bool:
	if production.research_level(owner, RacePowers.WRATH_RESEARCH) == 0: return false
	var eco = _economy()
	if eco == null or int(eco.stockpiles[owner][0]) < RacePowers.WRATH_GOLD:
		notice.emit("Not enough gold")
		return false
	for code in RacePowers.WRATH_TEMPLES:
		var b = key_building(owner, code)
		if b != null:
			wrath_cast(b, false)
			return false
	return false

## 0x57a1e0 (Emulated "powers.wrath", "abilities"): kind 0x23, amount 5 + level meteors, radius 11 + level, enemy units and
## buildings listed (b9 2, b12 4; the applier does not use the list), art 15, sound 18.
func _couatls_wrath(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _record(caster, {"b6": 15, "sound": 18, "radius": 11 + level, "b9": 2, "b12": 4, "kind": RacePowers.WRATH_KIND,
		"amount": 5 + level})

## B5-2 (BATCH5_RESEARCH.md E13, Emulated "abilities"): 0x579f80 Plague Cloud (case 0x21, AGGX): kind 0xd amount 5 (disease) on enemy
## units with a STATUS bit of 0x1001cfb within 4 + 4 x level, art 15, sound 18, effects ECHC / EZ29.
func _plague_cloud(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _record(caster, {"radius": 4 + 4 * level, "b6": 15, "sound": 18, "b9": 2, "b10": 1, "b12": 4, "effect": "ECHC", "effect2": "EZ29",
		"kind": SpellEffects.AFFLICT, "amount": 5, "d135": 0x1001cfb})

## 0x4ac0e0 case 0x23 (Emulated "abilities" meteor calls, tests/batch5_meteor_fixtures.json): STEZ47 / STEZ27 at the caster, then
## `amount` meteors (combat.launch_meteor) to the caster's cell + METEOR_OFFSETS, skipping a cell past 0 .. width / height.
func apply_meteors(record: Dictionary) -> Dictionary:
	var out := {"meteors": []}
	var caster: Dictionary = object_of(String(record.caster_kind), int(record.caster))
	if caster.is_empty(): return out
	var size: Vector2i = combat._map_size()
	var c: Vector2i = caster.cell
	for i in mini(int(record.amount), RacePowers.METEOR_OFFSETS.size()):
		var o: Array = RacePowers.METEOR_OFFSETS[i]
		var to := c + Vector2i(int(o[0]), int(o[1]))
		if to.x < 0 or to.x > size.x or to.y < 0 or to.y > size.y: continue
		out.meteors.append(combat.launch_meteor(c, to))
	return out

## The Dunekeep's Famine cell (LAB_004d1c60, Read) and the key: 500 crystal; the button is throttled to once per second
## (stamped before the price test, so a refused click also waits). Level = highest PFAn owned + 1 (0x437f70).
func famine(building_id: int, button: bool = true) -> bool:
	var b = production.building(building_id)
	if b == null: return false
	if button:
		if famine_stamp.has(building_id) and now() <= int(famine_stamp[building_id]) + FAMINE_THROTTLE_MS: return false
		famine_stamp[building_id] = now()
	var eco = _economy()
	if eco == null or not eco.try_spend(b.owner, [0, 0, FAMINE_PRICE, 0]):
		notice.emit("Not enough crystal")
		return false
	cast_record("_famine", {"kind": "building", "id": building_id}, production.research_level(b.owner, "PFAX"))
	return true

# ------------------------------------------------------------------------------------------------ G-2: Sword of Sirian
## PSWS at the Shrine of the Sword (BPSS; COMBAT_RESEARCH.md "G-2", Read). The cell (0x4d0430: an own finished BPSS, shown
## for race 0 or with PSWS, enabled with PSWS; icon 0x60) runs LAB_004d1bc0: at most once per second (one stamp 0xa47874,
## set before the price test), crystal >= 200 or the advisor cue 0x14, then 0x4d2130: message 0x1fe pays 200 crystal and
## 0x57a3b0(building) builds the record. The key (0x426350 case 0x2e, key 'W'): PSWS, 0x427e30('BPSS', 1) (the selected
## Shrine, else any own one), crystal >= 200 or the cue, then 0x57a3b0 **without** the payment and without the stamp.
const SWORD_CASE := 46
const SWORD_PRICE := 200
const SWORD_THROTTLE_MS := 1000
const SWORD_RESEARCH := "PSWS"
const SWORD_SHRINE := "BPSS"
var sword_stamp := -1                 # 0xa47874: ms until which the Shrine button does nothing

## The cell's press (LAB_004d1bc0). Returns whether the record went out.
func sword_of_sirian(building_id: int) -> bool:
	var b = production.building(building_id)
	if b == null or b.constructing or production.research_level(b.owner, SWORD_RESEARCH) == 0: return false
	if sword_stamp >= 0 and sword_stamp > now(): return false
	sword_stamp = now() + SWORD_THROTTLE_MS
	var eco = _economy()
	if eco == null or not eco.try_spend(b.owner, [0, 0, SWORD_PRICE, 0]):
		notice.emit("Not enough crystal")
		return false
	cast_record("_sword_of_sirian", {"kind": "building", "id": building_id}, 1)
	return true

## 0x426350 case 0x2e: no payment (0x57a3b0 is called directly); the case returns 0, so later cases of the key still run.
func sword_key(owner: int) -> bool:
	if production.research_level(owner, SWORD_RESEARCH) == 0: return false
	var pick = key_building(owner, SWORD_SHRINE)          # B4-1: 0x427e30 (decision 8)
	if pick == null: return false
	var eco = _economy()
	if eco == null or int(eco.stockpiles[owner][2]) < SWORD_PRICE:
		notice.emit("Not enough crystal")
		return false
	cast_record("_sword_of_sirian", {"kind": "building", "id": int(pick.entity_id)}, 1)
	return false

## 0x57a3b0: rows max(0, y - 0x15) .. min(y + 0x15, height - 1) - 1 around the Shrine's sprite cell, up to 24 death remains
## with dx^2 + dy^2 < 0x191; a record of kind 0x27 (art 0xff, sound 0x16, EZ02 / EZ08, +0x99 the count, +0x9b
## 0x557d90(owner, AHLX, 0, 1, 1), +0x9d 1, +0x9f 0x15, the cells, AHLX). No command check here (0x4aa840's loop has one).
func _sword_of_sirian(caster: Dictionary, _level: int, _target := {}) -> Dictionary:
	var o := object_of(String(caster.kind), int(caster.id))
	if o.is_empty(): return {}
	var owner: int = int(o.owner)
	var cells: Array = sword_remains(o.cell)
	return _record(caster, {"b6": 0xff, "sound": 0x16, "effect": "EZ02", "effect2": "EZ08", "kind": SpellEffects.SWORDS,
		"amount": cells.size(), "w9b": summon_start(owner, "AHLX"), "w9d": 1, "w9f": 0x15, "summon": "AHLX", "cells": cells})

## The remains 0x57a3b0 gathers (the rebuild's corpses; the destroyed buildings it also takes are Open, as for the Zombie).
func sword_remains(cell: Vector2i) -> Array:
	var found: Array = []
	for f in combat.fighters.values():
		if f.removed or f.state != "corpse": continue
		var c: Vector2i = combat.unit_cell(f.id)
		if c.y < maxi(0, cell.y - 0x15) or c.y >= mini(cell.y + 0x15, map_size().y - 1): continue
		var d := c - cell
		if d.x * d.x + d.y * d.y >= 0x191: continue
		found.append(c)
	found.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x > b.x)   # the row order as corpses_near
	return found.slice(0, SpellEffects.MAX_TARGETS)

## 0x4ada90 around a cell (the Shrine's): rows max(0, y - r) .. min(y + r, height - 1) - 1, dx^2 + dy^2 <= r^2.
func remove_corpses_at(cell: Vector2i, radius: int) -> Array:
	var gone: Array = []
	if cell.x < 0: return gone
	for f in combat.fighters.values():
		if f.removed or f.state != "corpse": continue
		var c: Vector2i = combat.unit_cell(f.id)
		if c.y < maxi(0, cell.y - radius) or c.y >= mini(cell.y + radius, map_size().y - 1): continue
		var d: Vector2i = c - cell
		if d.x * d.x + d.y * d.y > radius * radius: continue
		f.death_ms = now() - combat.corpse_ms(String(f.type_id))
		gone.append(f.id)
	return gone

# ------------------------------------------------------------------------------------------------ record builders
## Every builder returns the record of its spell function as tests/spell_fixtures.json names the fields, or {} when the
## function sends nothing. Shared fields (0x57xxxx locals): +0 caster id, +2 owner, +3 area (1 = through 0x4aa840),
## +4 status count, +6 art, +7 sound, +8 radius, +9 alliance, +0xa kinds, +0xb caster too, +0xc hit points filter,
## +0x85 / +0x8d / +0x91 effects, +0x89 duration, +0x95 kind, +0x97, +0x99 amount, +0x9b, +0x9d, +0x9f, +0xc9 / +0xf9
## cells, +0x129 summon type, +0x131 / +0x135 STATUS masks.
func _record(caster: Dictionary, fields: Dictionary) -> Dictionary:
	var owner: int = object_of(String(caster.kind), int(caster.id)).get("owner", 0)
	var r := {"caster_kind": caster.kind, "caster": int(caster.id), "owner": owner, "area": 1, "b4": 0, "b6": 0, "sound": 0,
		"radius": 0, "b9": 0, "b10": 0, "b11": 0, "b12": 0, "d85": 0, "d89": 0, "effect": "", "effect2": "", "kind": 0,
		"w97": -1, "amount": 0, "w9b": 0, "w9d": 0, "w9f": 0, "cells": [], "summon": "", "d131": 0, "d135": 0, "descriptors": []}
	r.merge(fields, true)
	return r

## 0x40dd50(owner, value): value x (100 + the hero's effect 0x2a + item power 0x2a) / 100 while the owner's hero lives.
func spell_power(owner: int, value: int) -> int:
	var h = _hero_fighter(owner)
	if h == null or int(h.hp) < 1: return value
	return ((HeroEffects.item_stat(combat.hero_block(owner), 0x2a) + 100 + status_value(h, 0x2a)) * value) / 100

## vtable +0x64 (0x529ea0, Read): r = min(19, 0x5267b0) (a unit: 8, 9 for a computer player; a hero: Charisma + 5 and
## "command" item powers, HeroEffects.conversion_radius; +8 with Dark Lord PDKL) plus r x (param x 50 + effect 0x20 +
## item power 0x20 (heroes)) / 100.
func spell_radius(f, param: int) -> int:
	var base: int
	if f.hero:
		base = HeroEffects.conversion_radius(combat.hero_block(f.owner)) + status_value(f, 10)   # + effect 10 (REVIEW D7)
		if production.research_level(f.owner, "PDKL") != 0: base += 8
	else: base = 9 if combat.ai_players.has(f.owner) else 8
	base = mini(19, base)
	var add := param * 50 + status_value(f, 0x20)
	if f.hero: add += HeroEffects.item_stat(combat.hero_block(f.owner), 0x20)
	return (add * base) / 100 + base

## vtable +0x68 (0x529f30 / 0x5199e0 case 6, Read): duration (param + 1) x 30000 ms, plus effect / item power 0x23 %.
func spell_duration(f, param: int) -> int:
	return duration(f, 6, param)

## B1-6a: vtable +0x68 (0x529f30, disassembly read; values Emulated in tests/hero_spell_fixtures.json): 0x5199e0(kind,
## param) plus (effect 0x23 + a hero's item power 0x23) % of it. 0x5199e0: 0 (p + 1) x 60 s, 1 (p + 1) x 5 s, 2 / 5
## (p + 2) x 60 s, 3 (p + 5) x 120 s, 4 (p + 1) x 600 s, 6 (p + 1) x 30 s, 7 (p + 1) x 120 s, else 0 (REVIEW_SPELLS.md D8).
static func base_duration(kind: int, param: int) -> int:
	match kind:
		0: return (param + 1) * 60000
		1: return (param + 1) * 5000
		2, 5: return (param + 2) * 60000
		3: return (param + 5) * 120000
		4: return (param + 1) * 600000
		6: return (param + 1) * 30000
		7: return (param + 1) * 120000
	return 0

func duration(f, kind: int, param: int) -> int:
	var d := base_duration(kind, param)
	if f == null: return d
	var add := status_value(f, 0x23)
	if f.hero: add += HeroEffects.item_stat(combat.hero_block(f.owner), 0x23)
	return (add * d) / 100 + d

## B1-6a: 0x5267b0 (Read): the radius base before vtable +0x64's scaling (a unit 8, 9 for a computer; a hero Charisma + 5
## + effect 10 + item power 10, + 8 with Dark Lord), as spell_radius uses it.
func radius_base(f) -> int:
	if not f.hero: return 9 if combat.ai_players.has(f.owner) else 8
	var base := HeroEffects.conversion_radius(combat.hero_block(f.owner)) + status_value(f, 10)
	if production != null and production.research_level(f.owner, "PDKL") != 0: base += 8
	return base

func _caster_fighter(caster: Dictionary):
	return combat.fighters.get(int(caster.id)) if caster.kind == "unit" else null

## 0x57fd60 Ring of Fire (spell 54, Emulated): enemies of every kind within 6, 25 x level + 25 fire (mode 2, type 3).
func _ring_of_fire(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var owner: int = object_of(String(caster.kind), int(caster.id)).owner
	return _record(caster, {"b6": 0x1b, "sound": 0x2f, "radius": 6, "b9": 2, "b12": 4, "effect": "EZ06", "kind": SpellEffects.DAMAGE,
		"amount": spell_power(owner, (level * 5 + 5) * 5), "w9b": 2, "w9d": 3})

## 0x578b60 the Harpy's ability (case 150, Emulated): enemy units within 10 (a hero: vtable +0x64(level - 1)) lose up to
## 25 x level + 25 mana.
func _harpy(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = _caster_fighter(caster)
	var owner: int = object_of(String(caster.kind), int(caster.id)).owner
	var radius := spell_radius(f, level - 1) if f != null and f.hero else 10
	return _record(caster, {"b6": 0xff, "sound": 4, "radius": radius, "b9": 2, "b10": 1, "b12": 4, "effect": "EZ15", "effect2": "EZ15",
		"kind": SpellEffects.DRAIN_MANA, "amount": spell_power(owner, (level * 5 + 5) * 5)})

## 0x57b1a0 Cure (spell 1, Emulated): allied units within vtable +0x64(0) (8), the caster too, heal 10 x level and cure.
func _cure(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = _caster_fighter(caster)
	var owner: int = object_of(String(caster.kind), int(caster.id)).owner
	return _record(caster, {"b6": 1, "sound": 15, "radius": spell_radius(f, 0) if f != null else 8, "b9": 1, "b10": 1, "b11": 1, "b12": 4,
		"effect": "EZ20", "effect2": "EZ20", "kind": SpellEffects.HEAL_CURE, "amount": spell_power(owner, level * 10)})

## 0x5809c0 Doomstones (spell 75, Emulated): one EMC0 missile at every enemy within vtable +0x64(0), damage 20 x level + 10.
func _doomstones(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = _caster_fighter(caster)
	var owner: int = object_of(String(caster.kind), int(caster.id)).owner
	var radius := spell_radius(f, 0) if f != null else 8
	# +0x9d is the radius too (B1-6a: a hero's record carries 9 with radius 9, the Runelord's 8; Emulated).
	return _record(caster, {"b6": 0x4e, "sound": 0x1b, "radius": radius, "b9": 2, "b12": 4,
		"effect": "ERUC", "kind": SpellEffects.MISSILES, "amount": spell_power(owner, level * 20 + 10), "w9b": 5, "w9d": radius, "summon": "EMC0"})

## 0x578930 the Naga's ability (case -1, Emulated): allied units within vtable +0x64(0), the caster too, get armour +10
## (status 0x18) for vtable +0x68(6, level - 1) = 30000 x level ms.
func _naga(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = _caster_fighter(caster)
	return _record(caster, {"b4": 1, "b6": 0xff, "sound": 2, "radius": spell_radius(f, 0) if f != null else 8, "b9": 1, "b10": 1, "b11": 1,
		"b12": 4, "d85": 0x34355a45, "d89": spell_duration(f, level - 1) if f != null else level * 30000, "effect": "EZ00",
		"kind": SpellEffects.STATUS_ONLY, "descriptors": [[STATUS_ARMOUR, 10]]})

## Summons (Emulated): the function's own command check 0x5776c0 for the summoned type, count, experience
## 0x557d90(owner, type, 0, 1, 1) + (level - 1) x step (summon_start), the target cell.
func _summon_record(caster: Dictionary, level: int, target: Dictionary, type_id: String, count: int, step: int, fields: Dictionary) -> Dictionary:
	var owner: int = object_of(String(caster.kind), int(caster.id)).owner
	if not command_free(owner, type_id): return {}
	var cell := Vector2i(int(target.get("x", 0)), int(target.get("y", 0)))
	var cells: Array = []
	for i in count: cells.append(cell)
	var r := {"kind": SpellEffects.SUMMON, "amount": count, "w9b": summon_start(owner, type_id) + (level - 1) * step, "summon": type_id, "cells": cells}
	r.merge(fields, true)
	return _record(caster, r)

## 0x580260 Fire Elemental (spell 58).
func _fire_elemental(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon_record(caster, level, target, "AAEF", 1, 50, {"b6": 0x1f, "sound": 0x20, "effect2": "EZ14", "w9d": 1})

## 0x5818f0 Summon Imp (spell 14).
func _summon_imp(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon_record(caster, level, target, "AAIM", 1, 20, {"b6": 0x39, "sound": 0x26, "effect2": "EZ34", "w9d": 1})

## 0x581250 Stonecall (spell 79).
func _stonecall(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon_record(caster, level, target, "AAEE", 1, 50, {"b6": 0x52, "sound": 0x20, "effect": "ERUC", "effect2": "EZ34", "w9d": 2})

## B3-2 (BATCH3_RESEARCH.md E16, Emulated "abilities"): 0x57a080 the Iron Golem's Firebomb (case 0x23): `level` AASX at the caster's
## cell, effect EZ08, +6 = 0xd, sound 5, experience 0x557d90 only. Its own command check runs after the case paid the mana.
func _firebomb(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon_record(caster, level, target, "AASX", level, 0, {"b6": 0xd, "sound": 5, "effect2": "EZ08", "w9d": 1})

## 0x579ce0 the Goblin Chief's Goblins (case 0x2b): level + 4 AOSX, EZ18, +6 = 0x35, sound 5; the check after the payment too.
func _goblins(caster: Dictionary, level: int, target := {}) -> Dictionary:
	return _summon_record(caster, level, target, "AOSX", level + 4, 0, {"b6": 0x35, "sound": 5, "effect2": "EZ18", "w9d": 1})

## 0x579410 the Bronze Golem's Salvage (case 0x1a through 0x4cfce0; E16a: record Emulated, the dice Read, decompile 247096-247156):
## one 1..8 per debris node (kind 6, EDB0-2) within distance^2 < 37 of the Golem; A = (L + 1)d20 + 20, B = (L + 1)d40 + 20, a fresh
## roll per use: 1-2 metal A and stone A; 3-4 metal B; 5-6 stone B; 7 gold A and metal A; 8 gold, metal, stone and crystal A. The
## totals go out as record kind 0x21, EZ44, sound 6, +0x99 = 7, +0x9b / +0x9d / +0x9f / +0xa1 (the scavenging applier's lanes,
## SpellEffects SCAVENGE: see BATCH3_RESEARCH.md B3-2 on the lane names). The debris stays; no corpses, no burning ruins.
const SALVAGE_KIND := 0x21
const SALVAGE_RADIUS2 := 37
func _salvage(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = _caster_fighter(caster)
	var here: Vector2i = combat.unit_cell(f.id) if f != null else Vector2i.ZERO
	var lanes := {"gold": 0, "metal": 0, "stone": 0, "crystal": 0}
	var a := func() -> int: return roll(level + 1, 20, 20)
	var b := func() -> int: return roll(level + 1, 40, 20)
	for cell in combat.debris_cells():
		var d: Vector2i = cell - here
		if d.x * d.x + d.y * d.y >= SALVAGE_RADIUS2: continue
		match roll(1, 8, 0):
			1, 2:
				lanes.metal += a.call()
				lanes.stone += a.call()
			3, 4: lanes.metal += b.call()
			5, 6: lanes.stone += b.call()
			7:
				lanes.gold += a.call()
				lanes.metal += a.call()
			8:
				lanes.gold += a.call()
				lanes.metal += a.call()
				lanes.stone += a.call()
				lanes.crystal += a.call()
	return _record(caster, {"sound": 6, "effect": "EZ44", "kind": SALVAGE_KIND, "amount": 7, "w9b": lanes.gold, "w9d": lanes.metal,
		"w9f": lanes.stone, "wa1": lanes.crystal})

## 0x579a10 the Vampire's bats (0x426350 case 0x1d only): 4 bats, 2 when exactly one command point is free.
func _bats(caster: Dictionary, level: int, target := {}) -> Dictionary:
	var owner: int = object_of(String(caster.kind), int(caster.id)).owner
	var pop: Dictionary = production.population(owner)
	var count := 2 if int(pop.current) == int(pop.maximum) - 1 else 4
	return _summon_record(caster, level, target, "AABA", count, 20, {"b6": 0xd, "sound": 5, "effect2": "EZ08", "w9d": 1})

## 0x57e670 Call the Dead (spell 47, Emulated): up to 24 corpses within vtable +0x64(0) of the caster (rows y - r - 4 ..
## y + r + 3 scanned, dx^2 + dy^2 <= r^2); with at least one, the command check for one point; a Skeleton (AUIX) at each
## corpse cell, experience (level - 1) x 20; +0x9f = the radius (the per-kind stage removes the corpses within it).
func _call_the_dead(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	var f = _caster_fighter(caster)
	var owner: int = object_of(String(caster.kind), int(caster.id)).owner
	var radius := spell_radius(f, 0) if f != null else 8
	var cells: Array = corpses_near(object_of(String(caster.kind), int(caster.id)).cell, radius)
	if not cells.is_empty() and not command_free(owner, ""): return {}
	return _record(caster, {"b6": 0x14, "sound": 9, "effect": "EZ78", "effect2": "EZ08",
		"kind": SpellEffects.RAISE, "amount": cells.size(), "w9b": summon_start(owner, "AUIX") + (level - 1) * 20, "w9d": 1, "w9f": radius, "summon": "AUIX", "cells": cells})

## 0x57a2e0 Famine (Emulated): amount 2000 x level, from the Dunekeep.
func _famine(caster: Dictionary, level: int, _target := {}) -> Dictionary:
	return _record(caster, {"sound": 0x1b, "effect": "EZ30", "kind": SpellEffects.FAMINE, "amount": level * 2000})

# ------------------------------------------------------------------------------------------------ the world (SpellEffects)
## {kind, id, owner, cell, hp, max_hp, status, hero} of a unit or building, {} when gone.
func object_of(kind: String, id: int) -> Dictionary:
	if kind == "unit":
		var f = combat.fighters.get(id)
		if f == null or f.removed or f.state == "dying" or f.state == "corpse": return {}
		var u = combat.units[id]
		if u.inside_building: return {}
		return {"kind": "unit", "id": id, "owner": int(f.owner), "cell": combat.unit_cell(id), "hp": int(f.hp), "max_hp": int(f.max_hp),
			"status": int(f.base.get("flags", 0)), "hero": bool(f.hero)}
	var b = production.building(id)
	if b == null or b.hit_points <= 0: return {}
	var cell: Vector2i = combat._building_sprite(b).cell
	return {"kind": "building", "id": id, "owner": int(b.owner), "cell": cell, "hp": int(b.hit_points), "max_hp": int(b.max_hit_points),
		"status": 0, "hero": false, "code": String(b.original_type_id)}

func map_size() -> Vector2i:
	return combat._map_size()

## The objects whose map node is in row y, in x order (the original row lists' own order is not recovered; it matters
## only past 24 targets).
func row_objects(y: int, dead := false) -> Array:
	var out: Array = []
	for id in combat.fighters:
		var o := object_of("unit", int(id))
		if o.is_empty() and dead: o = corpse_of(int(id))
		if not o.is_empty() and o.cell.y == y: out.append(o)
	for id in production.buildings:
		var o := object_of("building", int(id))
		if not o.is_empty() and o.cell.y == y: out.append(o)
	out.sort_custom(func(a, b): return a.cell.x < b.cell.x if a.cell.x != b.cell.x else (a.kind < b.kind if a.kind != b.kind else a.id < b.id))
	return out

func allied(a: int, b: int) -> bool:
	return a == b or combat.allied(a, b)

func armour_block(o: Dictionary) -> Dictionary:
	if o.kind == "unit": return combat.combat_block(combat.fighters[int(o.id)])
	return combat.building_block(production.building(int(o.id)))

func damage(o: Dictionary, amount: int, record: Dictionary):
	combat.apply_damage(String(o.kind), int(o.id), amount, int(record.caster) if record.caster_kind == "unit" else -1, String(record.caster_kind))

func set_hp(o: Dictionary, hp: int):
	if o.kind == "unit":
		var f = combat.fighters[int(o.id)]
		f.hp = hp
		combat.units[int(o.id)].hp = hp
	else:
		production.building(int(o.id)).hit_points = hp

## Poison +0x1a4 cleared through G-1's combat.set_poisoned(id, false) (0x51bfb0(0)); B1-6b: the disease +0x19e too;
## B1-6e: 0x51c060(0) (Emulated, fixtures "disease"): +0x19e and the level +0x19d go, the count +0x19c stays.
func cure(o: Dictionary) -> bool:
	var f = combat.fighters[int(o.id)]
	var had: bool = bool(f.get("poisoned", false)) or bool(f.get("diseased", false))
	if bool(f.get("poisoned", false)): combat.set_poisoned(int(o.id), false)
	_end_disease(f)
	return had

## B1-6e: vtable +0x38 (0x522af0, the hit-point setter) with a lower value: the unit is hurt (0x522af0 also ends
## invisibility, B1-6d's reveal), a building's hit points are set.
func set_hit_points(o: Dictionary, hp: int):
	set_hp(o, hp)
	if o.kind == "unit": reveal(combat.fighters[int(o.id)])

# ------------------------------------------------------------------------------------------------ B1-6e: the Morphs
## 0x4ac0e0 case 0x1f (Emulated, fixtures 90-94): stat 0 combat, 1 speed, 2 maximum and current hit points, 3 damage of
## a unit (+0x92 / +0x94 / +0x98 + 0x9c / +0x9e) or a building (+0x68 / +0x6a / +0x6e + +0x82 / +0x7c); combat and speed
## (+0x6a) clamp to 1..99, the others to 1..999. A unit's walking speed follows its speed; a tower's +0x6a is its shot
## period index (0x52b150) and +0x7c its damage (0x52e9e0); a building's combat goes through combat.building_block.
func morph(o: Dictionary, stat: int, change: int):
	var hi := 99 if stat < 2 else 999
	if o.kind == "unit":
		# The words are the block's own (f.base), clamped there; the live stats move by the same difference, so research
		# terms stay on top and a later promotion (0x40daa0) reads and clamps the morphed word (REVIEW_R1.md D2).
		var f = combat.fighters[int(o.id)]
		match stat:
			0: _morph_word(f, "combat", change, hi)
			1:
				var moved := _morph_word(f, "speed", change, hi)
				var u = _unit_node(int(f.id))
				if u != null:
					u.base_speed = maxi(1, int(u.base_speed) + moved)
					if f.has("speed_raw"): f.speed_raw = int(f.speed_raw) + moved
			2:
				f.max_hp = clampi(int(f.max_hp) + change, 1, hi)
				f.stats.max_hp = int(f.max_hp)
				f.base.max_hp = int(f.max_hp)
				f.hp = clampi(int(f.hp) + change, 1, hi)
				combat.units[int(f.id)].hp = f.hp
			3: _morph_word(f, "dmg", change, hi)
		return
	var b = production.building(int(o.id))
	if b == null: return
	if stat == 2:
		b.max_hit_points = clampi(int(b.max_hit_points) + change, 1, hi)
		b.hit_points = clampi(int(b.hit_points) + change, 1, hi)
		return
	var old := building_stat(b, stat)
	var value := clampi(old + change, 1, hi)
	var words: Dictionary = b.get_meta("morph", {})
	words[stat] = value
	b.set_meta("morph", words)
	var tower = combat.towers.get(b.entity_id)
	if tower == null: return
	if stat == 1: tower.period = combat.TOWER_PERIOD_MS[mini(16, maxi(0, value))]
	if stat == 3: tower.damage = int(tower.damage) + value - old

## A unit's Morph on one block word: the word clamped to 1..hi, the live stat moved by the same amount. Returns the move.
func _morph_word(f, key: String, change: int, hi: int) -> int:
	var old := int(f.base.get(key, f.stats[key]))
	var moved := clampi(old + change, 1, hi) - old
	f.base[key] = old + moved
	f.stats[key] = int(f.stats[key]) + moved
	return moved

## The gather's Morph filter (4aa840): a building needs BUI damage (+0x38 of its type's record) of 1 or more, a unit for
## Morph Damage (stat 3) its damage +0x9e.
func morph_target(o: Dictionary, stat: int) -> bool:
	if o.kind == "building":
		var b = production.building(int(o.id))
		return b != null and Rules.i16(b.definition.raw_hex.hex_decode(), 0x38) >= 1
	return stat != 3 or int(combat.fighters[int(o.id)].stats.dmg) >= 1

## A building's word the Morphs change (0 combat +0x68 = BUI +0x24, 1 +0x6a = BUI +0x26, 3 damage +0x7c = BUI +0x38).
func building_stat(b, stat: int) -> int:
	var words: Dictionary = b.get_meta("morph", {}) if b.has_meta("morph") else {}
	if words.has(stat): return int(words[stat])
	var raw: PackedByteArray = b.definition.raw_hex.hex_decode()
	return Rules.i16(raw, [0x24, 0x26, 0x2a, 0x38][stat])

## B1-6e: 0x4ac0e0 case 0x20 (Emulated, fixtures 97): for the local player's own caster only, 0x436500(owner, PSPR, ...):
## PSPR is never listed, so it completes again on every cast (Production.complete_research -> the research signal ->
## HeroSpells.raise_school(owner, 1)). Returns the school raised, -1 otherwise.
func increase_casting(owner: int) -> int:
	if production == null or owner != int(production.local_player): return -1
	_last_school = -1
	production.complete_research(owner, "PSPR")
	return _last_school
var _last_school := -1

## 0x436500's PSPR / PARR (Read): 0x438180(p, 1) / 0x438180(p, 3).
func _on_research_completed(owner: int, item: String):
	if item == "PSPR": _last_school = hero_spells.raise_school(owner, 1)
	elif item == "PARR": _last_school = hero_spells.raise_school(owner, 3)
	elif item == "PLI0" or item == "PLI1": mysticism(owner)
	elif item == RacePowers.RABIES_RESEARCH:
		# B3-1 (E14, Read 0x438ca0 decompile 37111): the owner's existing AOCX get the word 0x605 (rabies 5).
		for f in combat.fighters.values():
			if int(f.owner) == owner and String(f.type_id) == RacePowers.RABID and not f.removed: f["rabies"] = RacePowers.RABIES_EXISTING

## B2-1 (E6, Emulated: fixtures "mysticism"): 0x436500 -> 0x4386d0(player, 15, 0): each own non-hero unit with a mana
## maximum gains 15 current and maximum mana (0x52a020(15, 1)); new units get 15 x level from setup_unit.
func mysticism(owner: int):
	for f in combat.fighters.values():
		if int(f.owner) != owner or f.hero or f.removed or int(f.get("max_mana", 0)) < 1: continue
		f.max_mana = int(f.max_mana) + MYSTICISM_MANA
		f.mana = int(f.mana) + MYSTICISM_MANA

# ------------------------------------------------------------------------------------------------ B1-6e: disease
const DISEASE_TICK_MS := 1000          # 0x532a20 runs on every 40th world frame (as the fear count, FEAR_TICK_MS)
const PLAGUE_PIT := "BPSP"             # 0x70d630 counts them (0x4a47b0 / 0x4a7200 +1, 0x52b3e0 -1)

## 0x70d630 (Read): the BPSP buildings standing (any owner).
func plague_pits() -> int:
	if production == null: return 0
	var n := 0
	for b in production.buildings.values():
		if String(b.original_type_id) == PLAGUE_PIT and int(b.hit_points) > 0: n += 1
	return n

## 0x40d9b0 (Read; Emulated through 0x51c060 / 0x532a20): 0x70d630 plus every player's living hero's skill 0x65 term.
func plague_power() -> int:
	var power := plague_pits()
	for owner in combat.heroes:
		if int(owner) > 5: continue
		var h = _hero_fighter(int(owner))
		if h == null or int(h.hp) < 1: continue
		power += HeroEffects.skill_effect(combat.hero_block(int(owner)), 0x65)
	return power

## 0x51c060(1) (Emulated, fixtures "disease"): nothing for a diseased unit; else +0x19e = 1, the count +0x19c = 0, the end
## +0x1a0 = now + (0x40d9b0 x 3 + 120) x 5000 (or `until`), the regeneration timer +0x164 = now + 500 + magic armour x 128
## (a hero's regen_ms); the art EZ52 and Disease.wav (presentation, not ported).
func set_disease(f, until: int = -1):
	if f == null or bool(f.get("diseased", false)): return
	f["diseased"] = true
	f["disease_count"] = 0
	f["disease_level"] = int(f.get("disease_level", 0))
	f["disease_until"] = until if until >= 0 else now() + (plague_power() * 3 + 120) * 5000
	f["disease_next"] = now() + DISEASE_TICK_MS
	f["regen_ms"] = now() + 500 + _magic_armour(f) * 128   # 0x51c060 arms +0x164 for every unit (REVIEW_R1.md D3)
	sync_speed(f)

func _end_disease(f):
	if not bool(f.get("diseased", false)) and int(f.get("disease_level", 0)) == 0: return
	f["diseased"] = false
	f["disease_level"] = 0
	sync_speed(f)

func _magic_armour(f) -> int:
	return int(combat.combat_block(f).get("mres", 0))

## 0x532a20's disease part (Emulated, fixtures "disease_count"): +0x19c + 1; at (magic armour - 0x40d9b0) x 2 + 5 the
## level +0x19d rises by one, at most min(0x40d9b0 + 10, 100) (unsigned byte compare), and the count restarts.
func disease_tick(f):
	if not bool(f.get("diseased", false)): return
	f.disease_count = (int(f.get("disease_count", 0)) + 1) & 0xff
	var power := plague_power()
	if (_magic_armour(f) - power) * 2 + 5 <= int(f.disease_count):
		var cap := 100
		if power + 10 < 0x65 and power + 10 >= 0: cap = (power + 10) & 0xff
		f.disease_level = mini(int(f.get("disease_level", 0)) + 1, cap)
		f.disease_count = 0
		sync_speed(f)

## Spells.step: the disease's end (0x51b820, Read: cured once now passes +0x1a0; Emulated rows "regeneration") and its
## count (0x532a20, every DISEASE_TICK_MS from the infection: Provisional, the original's counter is shared).
func _step_disease(f, t: int):
	if not bool(f.get("diseased", false)): return
	if t > int(f.get("disease_until", 0)):
		_end_disease(f)
		return
	if t >= int(f.get("disease_next", 0)):
		f["disease_next"] = int(f.get("disease_next", t)) + DISEASE_TICK_MS
		disease_tick(f)

## combat.gd's hero regeneration hook (0x51b820, Emulated rows "regeneration"): a diseased, not poisoned hero does not
## regenerate (+0x164 = now + 1000) and is cured once now passes +0x1a0. Returns true when the tick is used up.
func disease_blocks_regeneration(f) -> bool:
	if not bool(f.get("diseased", false)) or bool(f.get("poisoned", false)): return false
	if now() > int(f.get("disease_until", 0)): _end_disease(f)
	else: f["regen_ms"] = now() + 1000
	return true

## Rot's term (Emulated, fixtures "rot"; 4aa840 case 0x26): +0x19d = the larger of 0x51c460(1) and 0x51bd10(1) as they
## stand (a byte), then 0x529970.
func rot_disease(f):
	var u = _unit_node(int(f.id))
	var speed: int = int(u.base_speed) if u != null else int(f.stats.speed)
	var value: int = Rules.effective_combat(combat.combat_block(f))
	f["disease_level"] = maxi(speed, value) & 0xff
	sync_speed(f)

func disease_level(f) -> int:
	return int(f.get("disease_level", 0)) if f != null else 0

## 0x4ac0e0 kind 1 (Emulated): a unit loses min(amount, its mana), nothing at 0 current mana; a hero's pool loses
## min(amount, pool). Returns the amount taken, -1 for a unit skipped.
func drain_mana(o: Dictionary, amount: int) -> int:
	var f = combat.fighters[int(o.id)]
	if f.hero:
		var h = _hero_fighter(int(f.owner))
		if h == null: return 0
		var taken := mini(amount, int(h.get("mana", 0)))
		h.mana = int(h.mana) - taken
		return taken
	if int(f.get("mana", 0)) < 1: return -1                # 0x4acf54: current mana +0x208 <= 0 skips the unit (Emulated, REVIEW D3)
	var taken := mini(amount, int(f.mana))
	pay_unit_mana(f, taken)
	return taken

## 0x4ac0e0 kind 0x10 (Read; the missile creation 0x58bdd0 / 0x541d20 arguments are Emulated): a missile of the record's
## type (+0x129, else the caster's shoot id) from the caster at the target, damage +0x99, type +0x9b.
func launch_spell_missile(record: Dictionary, o: Dictionary) -> Dictionary:
	var shooter_cell: Vector2i = object_of(String(record.caster_kind), int(record.caster)).get("cell", o.cell)
	# Temporary: the shooter's combat / roll are chosen so the accuracy test never misses (0x58bdd0 builds spell
	# missiles outside the attack path; its accuracy is not traced).
	var shooter := {"kind": "unit", "owner": int(record.owner), "cell": shooter_cell, "rect": [shooter_cell.x * 32, shooter_cell.y * 24, 32, 24],
		"launch_offset": Vector2i.ZERO, "combat": 100, "roll": 1, "flags_ba": 0, "high": false, "elevation": 0}
	var missile_id := String(SpellEffects.SPELL_MISSILE_IDS.get(String(record.summon), String(record.summon)))   # B1-6b: 0x40f620
	var m: Dictionary = combat.Missiles.create(missile_id, shooter, combat._missile_target(String(o.kind), int(o.id)), combat.rng, now(), map_size())
	m.merge({"attacker": int(record.caster), "attacker_kind": String(record.caster_kind), "damage": int(record.amount), "dtype": int(record.w9b),
		"target_kind": String(o.kind), "target_id": int(o.id), "launch_ms": now(), "from": shooter_cell, "to": m.aim, "spell": true,
		"art": String(record.summon), "owner": int(record.owner)})
	combat.missiles.append(m)
	combat.missile_launched.emit(m)
	return {"target": o.id, "type": record.summon, "damage": record.amount, "dtype": record.w9b}

## Corpses in the rebuild: fighters past their death animation, before removal (state "corpse"). The original looks for
## the EDTH / EDT1 / EDT2 effect objects a death leaves (0x57e670); their lifetime against the d-slot hold is Open.
func corpses_near(cell: Vector2i, radius: int) -> Array:
	var out: Array = []
	var found: Array = []
	for f in combat.fighters.values():
		if f.removed or f.state != "corpse": continue
		var c: Vector2i = combat.unit_cell(f.id)
		# rows max(0, y - r - 4) .. min(y + r + 4, height - 1) - 1 (Emulated, REVIEW D2)
		if c.y < maxi(0, cell.y - radius - 4) or c.y >= mini(cell.y + radius + 4, map_size().y - 1): continue
		var d := c - cell
		if d.x * d.x + d.y * d.y > radius * radius: continue
		found.append(f)
	found.sort_custom(func(a, b): return combat.unit_cell(a.id).y < combat.unit_cell(b.id).y if combat.unit_cell(a.id).y != combat.unit_cell(b.id).y else combat.unit_cell(a.id).x > combat.unit_cell(b.id).x)
	for f in found:
		if out.size() >= SpellEffects.MAX_TARGETS: break
		out.append(combat.unit_cell(f.id))
	return out

## 0x4ada90 for kind 0x15 (Emulated by REVIEW_SPELLS.md): the corpses within +0x9f of the caster disappear (removed at the next update).
func remove_corpses_near(caster_id: int, radius: int) -> Array:
	var o := object_of("unit", caster_id)
	if o.is_empty(): return []
	var gone: Array = []
	for f in combat.fighters.values():
		if f.removed or f.state != "corpse": continue
		var c: Vector2i = combat.unit_cell(f.id)
		# rows max(0, y - r) .. min(y + r, height - 1) - 1: a corpse at dy = +r is raised but stays (Emulated, REVIEW D2)
		if c.y < maxi(0, o.cell.y - radius) or c.y >= mini(o.cell.y + radius, map_size().y - 1): continue
		var d: Vector2i = c - Vector2i(o.cell)
		if d.x * d.x + d.y * d.y > radius * radius: continue
		f.death_ms = now() - combat.corpse_ms(String(f.type_id))
		gone.append(f.id)
	return gone

## 0x5776c0 (Read): used + the type's command cost (ARM +0xc8; type "" = 1) must fit under the limit.
func command_free(owner: int, type_id: String = "") -> bool:
	var pop: Dictionary = production.population(owner)
	var points := 1
	if type_id != "": points = int(production.rules.definition(type_id).get("population", 1))
	return int(pop.current) + points <= int(pop.maximum)

func summon_thief_eligible(p: int) -> bool:
	if not production.players_in_match.has(p): return false
	var h = _hero_fighter(p)
	if h == null or int(h.hp) < 1: return false
	var pop: Dictionary = production.population(p)
	return int(pop.current) < int(pop.maximum)

func summon_steal_chance(p: int) -> int:
	var h = _hero_fighter(p)
	return status_value(h, 0x28) + HeroEffects.item_stat(combat.hero_block(p), 0x28) if h != null else 0

func roll(count: int, sides: int, bonus: int) -> int:
	return combat.rng.roll(count, sides, bonus)

## Creates a summoned unit at the free cell nearest `cell` (0x43b4c0 -> navigator.free_cell_near) through the scene's
## add_unit, as message 0xfa's handler does; xp = +0x9b. R-1: 0x4a49e0's tail (Combat.creation_experience): extra "start" for
## the records sent with +0x3b = 0 (Strip Flesh's Skeleton, Mutate's animal); summons and Resurrection send 1.
func spawn(type_id: String, cell: Vector2i, owner: int, xp: int, _radius: int, extra := {}) -> Dictionary:
	if host == null or not host.has_method("add_unit"): return {}
	var free: Vector2i = navigator.free_cell_near(cell)
	var unit = host.add_unit(type_id, free, owner)
	production.register_unit(unit.unit_id, type_id, owner)
	var f = combat.fighters.get(unit.unit_id)
	if f != null:
		combat.creation_experience(f, xp, bool(extra.get("start", false)))
		setup_unit(f)
		# B1-6d: the 0xfa lifetime (+0x33 -> +0x1ec) and kind 0x18's illusion data (0x43c450, +0x1f0).
		if int(extra.get("lifetime", 0)) > 0:
			f["lifetime_until"] = now() + int(extra.lifetime)
			f["timed"] = true                             # +0x1ec stays set after the unit dies (Resurrection skips the body)
		if bool(extra.get("illusion", false)): make_illusion(f)
	return {"id": unit.unit_id, "type": type_id, "cell": free, "owner": owner, "xp": xp, "illusion": bool(extra.get("illusion", false)),
		"lifetime": int(extra.get("lifetime", 0))}

## 0x4aa840 case 0x24 candidates (Emulated): the resource buildings (second letter R) of every active, non-allied
## other player, players in order, each in its own object order (the rebuild: mine ids).
func famine_candidates(owner: int) -> Array:
	var out: Array = []
	var mines = _mines()
	if mines == null: return out
	var skirmish = host.get("skirmish") if host != null else null
	for p in 7:
		if p == owner or allied(owner, p): continue
		# 0x708f94 active slot, 0x748668 not eliminated (REVIEW D9)
		if not production.players_in_match.is_empty() and not production.players_in_match.has(p): continue
		if skirmish != null and p < skirmish.eliminated.size() and skirmish.eliminated[p]: continue
		var ids: Array = mines.mines.keys()
		ids.sort()
		for id in ids:
			if mines.owner_of(id) != p: continue
			var cell: Vector2i = mines.mines[id].anchor
			out.append({"kind": "building", "id": id, "owner": p, "cell": cell, "hp": 1, "max_hp": 1, "code": String(mines.mines[id].code)})
	return out

func mine_reserve(id: int) -> int:
	var eco = _economy()
	return int(eco.mines[id].reserve) if eco != null and eco.mines.has(id) else 0

func set_mine_reserve(id: int, value: int):
	var eco = _economy()
	if eco != null and eco.mines.has(id): eco.mines[id].reserve = value

## Timed status effects (the unit +0xfc list, 0x577320): the strongest value of a kind counts (0x577520).
func add_status(o: Dictionary, status: Dictionary) -> bool:
	if o.kind != "unit" or not combat.fighters.has(int(o.id)): return false
	var f = combat.fighters[int(o.id)]
	if not f.has("statuses"): f["statuses"] = []
	# 0x5773b0 (Read, REVIEW D6): an entry of the same kind and art byte (+0x30, the record's +6) is replaced, not stacked.
	f.statuses = f.statuses.filter(func(s): return not (int(s.kind) == int(status.kind) and int(s.get("art", -1)) == int(status.get("art", -1))))
	f.statuses.append(status)
	sync_speed(f)
	return true

func status_value(f, kind: int) -> int:
	if f == null or not f.has("statuses"): return 0
	var best = null
	for s in f.statuses:
		if int(s.kind) == kind and int(s.until) > now() and (best == null or int(s.value) > int(best)): best = int(s.value)
	return int(best) if best != null else 0

# ------------------------------------------------------------------------------------------------ B1-6a: the world for the new kinds
## R-1 (Emulated: 0x557d90 in tests/rank_fixtures.json "starting"; the builders' sum Read, decompile 243841..253293): the summon
## builders put 0x557d90(player, type, 0, 1, 1) in +0x9b: the hero's skills tied to the type and PGAX level x 20.
func summon_start(owner: int, type_id: String) -> int:
	return combat.starting_xp(owner, type_id, false, true, true)

## 0x526d80 (R-1, Emulated): a hero's player level (block +0x28), else the unit's rank (+0x3c).
func unit_level(o: Dictionary) -> int:
	var f = combat.fighters.get(int(o.id))
	if f == null: return 0
	if f.hero:
		var block: Dictionary = combat.hero_block(int(f.owner))
		return int(block.get("level", 1)) if not block.is_empty() else 1
	return int(f.get("rank", 0))

## 0x4aa840 case 0x25 (Emulated, fixtures 'strip'): the unit vanishes without remains (0x4a9890 with the no-corpse flag ->
## message 0x1fb) and a Skeleton of the unit's owner stands at the free cell nearest its cell (message 0xfa, effect +0x91).
func strip_flesh(o: Dictionary, record: Dictionary) -> Dictionary:
	var f = combat.fighters.get(int(o.id))
	if f == null: return {}
	var cell: Vector2i = o.cell
	_remove_quietly(int(o.id))
	var made := spawn("AUIX", cell, int(o.owner), 0, 0, {"start": true})   # R-1: case 0x25 sends +0x3b = 0
	if not made.is_empty(): made["from"] = int(o.id)
	return made

## 0x51a130(1) (Read): off the map without remains or experience (the scene's remove_unit_quietly; a bare world marks it).
func _remove_quietly(id: int):
	var unit = combat.units[id]
	if host != null and host.has_method("remove_unit_quietly"):
		host.remove_unit_quietly(unit)
		return
	var f = combat.fighters[id]
	f.removed = true
	f.order = null
	f.swing = null
	unit.removed = true
	unit.visible = false
	navigator.release(unit, unit.cell)
	if production != null: production.unregister_unit(id)

## Message 0x1f9 -> 0x4a7200 (Read; the message Emulated): a finished building of the record's type at the record's cell
## for the duration (+0x120 = now + +0x89; 0x52cd77 removes it once now passes); nothing when a building already stands
## there. Provisional: the cell is the placement anchor and must fit (Placement.check), the original only tests for a
## building node at the cell.
func create_spell_building(type_id: String, cell: Vector2i, owner: int, duration_ms: int) -> Dictionary:
	if production == null: return {}
	var definition: Dictionary = production.rules.definition(type_id)
	if definition.is_empty(): return {}
	# The node cell is the anchor: the centre column and the top row (as add_completed's sprite cell).
	var check: Dictionary = HeroSpells.Placement.check_top(navigator, definition, cell.x, cell.y)
	if not check.ok: return {}
	var b = production.add_completed(owner, type_id, int(check.left), int(check.top))
	if host != null and host.has_method("add_marker"): host.add_marker(b)
	if int(definition.get("attack", 0)) > 0:
		var w: int = int(definition.footprint[0])
		var h: int = int(definition.footprint[1])
		combat.register_tower(b, Vector2i(b.left + ((w - 1) >> 1), b.top + ((h - 1) >> 1)))
	if duration_ms > 0: hero_spells.timed_buildings[int(b.entity_id)] = now() + duration_ms
	return {"id": int(b.entity_id), "type": type_id, "cell": cell, "owner": owner, "until": now() + duration_ms}

## Kind 4 (0x4ac0e0 case 4, B1-3's DayNight.apply_record): amount 3 = dusk and rain (the rain part is B1-3's Open).
func day_night_record(amount: int) -> bool:
	var dn = host.get("day_night") if host != null else null
	if dn == null: return false
	dn.apply_record(amount)
	return true

## 0x43e9b0 (Emulated through the scavenging record, fixtures "scavenge"): the four amounts credited (capped as the
## economy caps a credit).
func credit(owner: int, amounts: Array):
	var eco = _economy()
	if eco != null: eco.credit(owner, amounts)

## 0x4ada90 for kind 0x1c (Emulated, fixtures "scavenge"): the death remains within the record's +0x99 (7) of the unit go,
## rows y - r .. y + r - 1 as for Call the Dead (a remain at distance^2 37..49 goes without having paid).
func remove_corpses_around(unit_id: int, radius: int) -> Array:
	return remove_corpses_near(unit_id, radius)

## The record's +0x97 >= 0 (Read, 0x4ac0e0 tail): the target's map node shows look +0x97 until now + +0x89 (+0x132 /
## +0x134; Stoneskin 6, Resist Magic 7). Presentation: the node's look itself is Open.
func set_look(o: Dictionary, look: int, until: int):
	var f = combat.fighters.get(int(o.id)) if o.kind == "unit" else null
	if f != null: f["look"] = {"state": look, "until": until}

## B1-3's queued Zombie scavenging records (main.gd scavenge -> scavenge_records) through the applier as 0x578e10's
## record (Emulated): kind 0x1c, effect EZ44, sound 6, +0x99 = 7, +0x9b gold, +0x9d metal, +0x9f crystal, +0xa1 stone.
func _scavenge_records():
	if host == null: return
	var queue = host.get("scavenge_records")
	if not queue is Array or queue.is_empty(): return
	var records: Array = queue.duplicate()
	queue.clear()
	for q in records:
		if not combat.fighters.has(int(q.unit)): continue
		var a: Array = q.get("amounts", [0, 0, 0, 0])
		var record := _record({"kind": "unit", "id": int(q.unit)}, {"sound": 6, "effect": String(q.get("effect", "EZ44")),
			"kind": SpellEffects.SCAVENGE, "amount": 7, "w9b": int(a[0]), "w9d": int(a[1]), "w9f": int(a[2]), "wa1": int(a[3])})
		cast_built(record, {"kind": "unit", "id": int(q.unit)}, 1)

## The placement click (B1-6a, hero_spells.place): a left press over the map places, a right press cancels.
func placement_click(event: InputEventMouseButton) -> bool:
	var hud = host.get("hud") if host != null else null
	if hud != null and hud.has_method("over_panel") and hud.over_panel(hud.to_virtual(event.position)): return false
	if event.button_index == MOUSE_BUTTON_RIGHT:
		hero_spells.cancel_pending()
		notice.emit("Cancelled.")
		return true
	if event.button_index != MOUSE_BUTTON_LEFT or host == null or host.get("collision") == null: return false
	var world: Vector2 = host.get_canvas_transform().affine_inverse() * event.position
	var result: Dictionary = hero_spells.place(host.collision.world_cell(world))
	if not bool(result.get("cast", false)): notice.emit("You cannot place that there.")
	return true

## C1 (DELIBERATE MODERN CHANGE, COMPLAINTS_AND_FIXES.md F7, modern_rules.gd "Casting", off by default): with the original
## rules a pause drops the pending placement / dialog and the cast orders whose event has not fired (the behaviour the
## complaint reports; its mechanism in the original is not traced, Open); with Casting on a pause keeps both and the
## placement and dialogs still work while paused.
func pause_changed(_paused: bool, keep_casts: bool):
	if keep_casts: return
	hero_spells.cancel_pending()
	for f in combat.fighters.values():
		var c = f.get("cast")
		if c != null and bool(c.pending):
			f.cast = null
			if combat.units.has(f.id): combat.units[f.id].anim = {}

## The record's effects and sound (presentation; 0x4ac0e0 tail, Read): +0x8d on the caster (0x44e8f0), +0x91 on each
## affected target, +0x85 on each affected target while its status lasts (linked to the status entry by 0x577320), the
## summons' +0x91 at their cells (message 0xfa), STEZ<+7>.wav at the caster.
func _present(record: Dictionary, result: Dictionary):
	if host == null: return
	var fx = host.get("effects")
	var caster := object_of(String(record.caster_kind), int(record.caster))
	if fx != null and fx.has_method("spawn_effect"):
		if String(record.effect) != "" and not caster.is_empty(): _effect_on(fx, String(record.effect), caster, 0)
		for t in result.get("affected", []):
			var o := object_of(String(t.kind), int(t.id))
			if o.is_empty(): continue
			if String(record.effect2) != "" and not (o.kind == caster.get("kind", "") and int(o.id) == int(caster.get("id", -1)) and record.effect2 == record.effect):
				_effect_on(fx, String(record.effect2), o, 0)
			if int(record.d85) != 0: _effect_on(fx, _fourcc_text(int(record.d85)), o, now() + int(record.d89))
		for s in result.get("summoned", []) + result.get("stripped", []) + result.get("mutated", []):
			if String(record.effect2) != "": fx.spawn_effect(String(record.effect2), _cell_pixel(s.cell), int(s.cell.y), true)
		for b in result.get("buildings", []):
			if String(record.effect2) != "": fx.spawn_effect(String(record.effect2), _cell_pixel(b.cell), int(b.cell.y), true)
	if int(record.sound) != 0 and not caster.is_empty() and host.has_method("play_at"):
		host.play_at("STEZ%02d.wav" % int(record.sound), caster.cell)

func _effect_on(fx, code: String, o: Dictionary, until: int):
	var follow = combat.units.get(int(o.id)) if o.kind == "unit" else null
	var pixel := _cell_pixel(o.cell)
	if follow != null: pixel = Vector2i(int(follow.position.x), int(follow.position.y))
	fx.spawn_effect(code, pixel, int(o.cell.y), until == 0, 0, follow, until)

static func _cell_pixel(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * 32 + 16, cell.y * 24 + 12)

static func _fourcc_text(v: int) -> String:
	return PackedByteArray([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]).get_string_from_ascii()

# ------------------------------------------------------------------------------------------------ B1-6a: status consumers
## 0x525c80 (disassembly 0x525dfc..0x525e4c, Read): every unit's armour table gains its strongest effects 0x51 (word 4,
## magic: Resist Magic), 0x50 (word 3, fire), 0x58 (word 1, ice) and 0x59 (word 2, electricity) before the hero terms.
func add_resist_statuses(f, block: Dictionary):
	var fire := BERSERK_FIRE_ARMOUR if berserk_level(f) == 2 else 0    # B2-1: 0x525c80, the berserk state of level 2
	if fire == 0 and (not f.has("statuses") or f.statuses.is_empty()): return
	var adds := {4: status_value(f, 0x51), 3: status_value(f, 0x50) + fire, 1: status_value(f, 0x58), 2: status_value(f, 0x59)}
	if adds.values().all(func(v): return v == 0): return
	var t: Array = Rules.armour_table(block).duplicate()
	for i in adds: t[i] = int(t[i]) + int(adds[i])
	block["armour_table"] = t

## 0x526f40 (Read): the life drain of an attacker: a hero's skill 0x35 term and item power 0x3c, every unit's effect 0x3c
## (Vampirism); combat.gd adds the non-hero type terms (ResearchEffects.drain).
func drain_terms(f) -> int:
	var v := status_value(f, HeroSpells.STATUS_VAMPIRISM)
	if f.hero:
		var block: Dictionary = combat.hero_block(int(f.owner))
		if not block.is_empty(): v += HeroEffects.skill_effect(block, 0x35) + HeroEffects.item_stat(block, 0x3c)
	return v

## 0x5427e0 with 0x527040 (B1-6b: Emulated, tests/hero_spell_b_fixtures.json "arrows"; the rule is Rules.arrow_damage):
## a missile of class 0 or 0xb (the record's damage type, m.dtype) against an arrow-resistant unit (Rules.arrow_resistant:
## the six types, AOIX with its owner's PNOP, ALBX with its owner's PDEF, a hero with effect 0x52) does damage >> 4, at
## least 1 (class 0xb: 2), unless the shooter's owner has PHUN (0x70d5c3).
func missile_resisted(m: Dictionary, target, amount: int) -> int:
	var owner := int(target.owner)
	var pnop: bool = production != null and production.research_level(owner, "PNOP") != 0
	var pdef: bool = production != null and production.research_level(owner, "PDEF") != 0
	var resisting: bool = Rules.arrow_resistant(String(target.type_id), bool(target.hero) and status_value(target, HeroSpells.STATUS_RESIST_MISSILE) > 0, pnop, pdef)
	return Rules.arrow_damage(amount, int(m.get("dtype", 0)), resisting, shooter_phun(m))

## B1-6c: the shooter's owner 0x5427e0 reads (missile +0x670 -> +0x70 -> +0xc; -1 without a shooter): a spell missile's
## record owner, else the shooting unit's or tower's owner (B1-6b read only the spell missiles' "owner", so a unit's shot
## never saw its player's PHUN).
func shooter_owner(m: Dictionary) -> int:
	if m.has("owner"): return int(m.owner)
	var id := int(m.get("attacker", -1))
	if String(m.get("attacker_kind", "unit")) == "unit":
		var f = combat.fighters.get(id)
		return int(f.owner) if f != null else -1
	var b = production.building(id) if production != null else null
	return int(b.owner) if b != null else -1

## 0x70d5c3[shooter owner] (PHUN): the arrow rule spares the shot (units and buildings alike).
func shooter_phun(m: Dictionary) -> bool:
	var shooter := shooter_owner(m)
	return shooter >= 0 and production != null and production.research_level(shooter, "PHUN") != 0

# ------------------------------------------------------------------------------------------------ B1-6b: the world for the new kinds
const STATUS_COMBAT := 1              # 0x51bd10 (Berserker)
const STATUS_SPEED := 5               # 0x51c460 (Berserker)
const STATUS_MAGIC_ARMOUR := 6        # 0x526b70 (White Ward)
const STATUS_MORALE := 7              # 0x5269a0 (Blessing; a hero's derived 12)
const STATUS_ATTACK := 0x17           # 0x526310 (Firebreath, Ice Floe): the attack triple
const STATUS_HASTE := 0x2e            # 0x51c460 and 0x51c6a0 (Invigorate)
const STATUS_FAST_ATTACK := 0x2f      # 0x51c6a0
const STATUS_SLOW_ATTACK := 0x37      # 0x51c6a0
const STATUS_SLOW := 0x38             # 0x51c460
const STATUS_FREEZE := 0x30           # 0x51c460 and 0x51c6a0 (Freeze)
const STATUS_LIFE_WARD := 0x3e        # 0x522860 (death), 0x5427e0 / 0x53f180 (poison and disease by missiles)
const STATUS_IMMUNITY := 0x7c         # 0x51c130 / 0x51c1b0 (Immunity)
const STATUS_VENOM := 0x7d            # 0x51aae0 (Venom Touch)
const STATUS_POISON_GATE := 0x7e      # 0x4a49e0 (Poison Gate)
const BERSERK_STATES := {0: [2, 15000], 1: [5, 60000], 2: [1, 180000]}   # 0x527720: level -> hit points per period, length
const BERSERK_PERIOD_MS := 1000       # +0x1d8
const BERSERK_SCRIPT := 4             # Rampant (0x506f10 at 0x527720)
const BERSERK_FIRE_ARMOUR := 15       # 0x525c80: armour word 3 (fire) at level 2 (Emulated, "armour")

## A dead unit (the rebuild's dying / corpse fighter, hit points 0) as the gather sees it (0x4aa840 with +0xc = 1).
func corpse_of(id: int) -> Dictionary:
	var f = combat.fighters.get(id)
	if f == null or f.removed or (f.state != "dying" and f.state != "corpse") or _unit_node(id) == null: return {}
	return {"kind": "unit", "id": id, "owner": int(f.owner), "cell": combat.unit_cell(id), "hp": 0, "max_hp": int(f.max_hp),
		"status": int(f.base.get("flags", 0)), "hero": bool(f.hero)}

## 0x4aa840 case 5 (Emulated): the body's type for the record's owner at the free cell nearest the body (message 0xfa,
## effect +0x91); the body itself stays.
func resurrect(o: Dictionary, record: Dictionary) -> Dictionary:
	var f = combat.fighters.get(int(o.id))
	if f == null: return {}
	var made := spawn(String(f.type_id), o.cell, int(record.owner), int(f.xp), 0)   # R-1: case 5, +0x10 = 0x526db0 of the body
	if not made.is_empty(): made["from"] = int(o.id)
	return made

## 0x51c130 (Read; Emulated through Poison Cloud): no effect 0x7c, no hero item power 0x3a, not diseased (+0x19e), not
## already poisoned (+0x1a4). B4-1 (BATCH4_RESEARCH.md E9 / REVIEW_BATCH4.md D1, Emulated "poison"; decompile 192500..): a target
## whose own type class word +0xae has high byte 5, a titan (+0x1cd) and +0x1a5, which the constructor sets from 0x5286c0(5) bit 0
## (decompile 191397-191402: STATUS 0x4, 0x100, animals; the Brew term is not the constructor's), refuse too.
func poisonable(f) -> bool:
	if f == null or status_value(f, STATUS_IMMUNITY) != 0: return false
	if f.hero and HeroEffects.item_stat(combat.hero_block(int(f.owner)), 0x3a) > 0: return false
	if RacePowers.class_byte(int(f.base.get("word_ae", 0)) & 0xffff) == RacePowers.POISON_CLASS or UnitRanks.is_titan(String(f.type_id)): return false
	if fear_class({"base": f.base, "type_id": f.type_id}, 5) & 1: return false
	return not bool(f.get("diseased", false)) and not bool(f.get("poisoned", false))

## 0x51c1b0 (Read): as 0x51c130 with item power 0x39 and the hero class 0xf excluded (the class is not tested: Open).
func diseasable(f) -> bool:
	if f == null or status_value(f, STATUS_IMMUNITY) != 0: return false
	if f.hero and HeroEffects.item_stat(combat.hero_block(int(f.owner)), 0x39) > 0: return false
	# B3-1 (E14, Emulated review "immunity"): the type class 6 (a rabid unit), the titans (+0x1cd) and +0x19f, which the constructor
	# sets from 0x5286c0(6) bit 0 (STATUS 0x4, 0x100, 0x4000, animals, the AG* list). The hero class 15 stays Open.
	# B5-1 (E9): the class 6 of the target's own word (its type's, every race), not only the rabid one.
	if class_word(f) >> 8 == RacePowers.DISEASE_CLASS or UnitRanks.is_titan(String(f.type_id)): return false
	if fear_class({"base": f.base, "type_id": f.type_id}, 6) & 1: return false   # the constructor's reading: no Brew term
	return not bool(f.get("diseased", false)) and not bool(f.get("poisoned", false))

func poison(o: Dictionary) -> bool:
	var f = combat.fighters.get(int(o.id))
	if not poisonable(f): return false
	combat.set_poisoned(int(o.id), true)
	return true

## 0x51c1b0 then 0x51c060(1) (B1-6e: set_disease, the deadlines, the count and the combat / speed terms).
func disease(o: Dictionary) -> bool:
	var f = combat.fighters.get(int(o.id))
	if not diseasable(f): return false
	set_disease(f)
	return true

## 0x527100 (Emulated through Soul Flame, R-1): a non-hero's experience (+0x40, the fighter's xp) gains min(amount, cap - xp)
## while below the cap, with the promotions 0x40da20 makes; returns the gain.
func add_experience(o: Dictionary, amount: int, cap: int) -> int:
	var f = combat.fighters.get(int(o.id))
	if f == null or f.hero: return 0
	var xp := int(f.get("xp", 0))
	if xp >= cap: return 0
	var gain := mini(amount, cap - xp)
	combat.gain_experience(f, gain)
	return gain

## 0x527720 (B2-1, Emulated: tests/batch2_review_fixtures.json "state", "tick"; BATCH2_RESEARCH.md E7): a living unit enters
## the berserk (level 2) or burning (level 0) state: +0x1ce = 1, +0x1cf = level; it loses +0x1d0 hit points every +0x1d8 =
## 1000 ms until +0x1dc: level 0 2 hp for 15 s, level 1 5 hp for 60 s, level 2 1 hp for 180 s. The attitude script +0x130
## is saved at +0x1d2 and the unit goes on script 4 (Rampant, 0x506f10). An existing level <= the new one stays; a higher
## one is replaced, the timers restart and the saved script is then Rampant, so that unit stays Rampant afterwards.
func berserk(o: Dictionary, amount: int):
	var f = combat.fighters.get(int(o.id))
	if f == null or not combat.alive(f): return           # 0x527720 returns at hit points < 1
	var cur = f.get("berserk")
	if cur != null and int(cur.level) <= amount: return
	var row: Array = BERSERK_STATES.get(amount, [])
	if row.is_empty(): return
	f["berserk"] = {"level": amount, "drain": int(row[0]), "period": BERSERK_PERIOD_MS, "next_ms": now() + BERSERK_PERIOD_MS,
		"until": now() + int(row[1]), "saved_script": int(f.script)}
	combat.ai.assign_script(f, BERSERK_SCRIPT)
	sync_speed(f)
	combat.berserk_changed.emit(int(f.id), amount, cur == null)   # the art EF04 / EZ50 of a first entry (main.gd)

## The tick 0x51c7d0 (disassembly 0x51ca7e..0x51cb26, Emulated "tick"): the end comes first (flag cleared, script restored
## through 0x506f10; no drain at the end time), else on each due period (next = now + period) the setter vtable +0x38 =
## 0x522af0 stores hit points - drain with no attacker, on the host only (the rebuild is always the host): a unit that
## reaches 0 dies the ordinary way without a killer.
func _step_berserk(f, t: int):
	var b = f.get("berserk")
	if b == null: return
	if t >= int(b.until):
		f.erase("berserk")
		combat.ai.assign_script(f, int(b.saved_script))
		sync_speed(f)
		combat.berserk_changed.emit(int(f.id), -1, false)
	elif t >= int(b.next_ms):
		b.next_ms = t + int(b.period)
		combat.apply_damage("unit", int(f.id), int(b.drain), -1)

## 0x4ac0e0 case 0x1d (disassembly 0x4ad018..0x4ad031): +0xba cleared and every status effect removed (0x577480).
func calm(o: Dictionary):
	var f = combat.fighters.get(int(o.id))
	if f == null: return
	f["statuses"] = []                                # +0xba and the list only; the berserk block stays (REVIEW F4, Read)
	sync_speed(f)

## The gather's Calm test (+0xba != 0 or a status entry at +0xfc): the rebuild's statuses and berserk state.
func has_effects(o: Dictionary) -> bool:
	var f = combat.fighters.get(int(o.id))
	return f != null and not f.get("statuses", []).is_empty()     # +0xba is not modelled (REVIEW F4 / F5)

func set_mana_gate(value: int, until: int):
	mana_gate = value
	mana_gate_until = until

## 0x51b6b0 (Read): no unit or hero regenerates mana while 0x7494c4 < 1.
func mana_flowing() -> bool:
	return mana_gate >= 1

## The strongest active entry of a kind (0x577520: the largest value; ties keep the first).
func status_entry(f, kind: int) -> Dictionary:
	if f == null or not f.has("statuses"): return {}
	var best := {}
	for s in f.statuses:
		if int(s.kind) == kind and int(s.until) > now() and (best.is_empty() or int(s.value) > int(best.value)): best = s
	return best

## Combat block terms (Read): effect 1 adds to combat (0x51bd10), effect 6 to magic armour (0x526b70), effect 0x17
## (0x526310, disassembly 0x52634a..0x5263a3): value 0 replaces (damage, type) with its words when its damage is not
## below the unit's or it has a range and the unit none; another value adds its damage. The range word is kept as
## "status_range" only (Provisional: the shot a melee unit would fire is Open).
func apply_status_terms(f, block: Dictionary):
	# B1-6e (Emulated, fixtures "getters"): 0x51bd10 subtracts the disease level +0x19d (the caller keeps it at least 1).
	block.combat = int(block.combat) - disease_level(f)
	# REVIEW_HERO_SPELLS_B.md F2 (Emulated): the berserk flag (+0x1ce, level +0x1cf == 2) adds 6 to combat in 0x51bd10.
	if berserk_level(f) == 2: block.combat = int(block.combat) + 6
	# B1-6d (Emulated, fixtures "shadow"): while +0x1e4 is set, 0x5260a0 adds +0x1e6 to armour word 0 and 0x526b70 adds
	# +0x1e7 to the magic armour (Shadowform, Phantom Steed).
	var sh = shadow_block(f)
	if sh != null:
		block.armour = int(block.armour) + int(sh.armour)
		block["mres"] = int(block.get("mres", 0)) + int(sh.magic)
	if not f.has("statuses") or f.statuses.is_empty(): return
	block.combat = int(block.combat) + status_value(f, STATUS_COMBAT)
	# B1-6c (Emulated, REVIEW_HERO_SPELLS_C.md R1 / D1): an active 0x46 (Psychic Blast) makes 0x51bd10 return exactly 1,
	# after every other term (the near-hero bonus, encumbrance and hero terms included: Rules.effective_combat reads "stunned").
	if _has_status(f, SpellEffects.STATUS_STUNNED):
		block.combat = 1
		block["stunned"] = true
	block["mres"] = int(block.get("mres", 0)) + status_value(f, STATUS_MAGIC_ARMOUR)
	var e := status_entry(f, STATUS_ATTACK)
	if e.is_empty() or not e.has("data"): return
	var d: Array = e.data
	var base_dmg := int(f.base.get("dmg", block.dmg))
	var bonus := int(block.dmg) - base_dmg                  # the research terms 0x526310 adds after the status
	if int(e.value) == 0:
		if int(d[0]) >= base_dmg or (int(d[2]) != 0 and int(f.base.get("range", 0)) == 0):
			block.dmg = int(d[0]) + bonus
			block.dtype = int(d[1])
			block["status_range"] = int(d[2])
	else:
		block.dmg = int(block.dmg) + int(d[0])

## 0x51c460 (Read): speed + max(effects 5, 0x2e) - max(effects 0x38, 0x30).
func speed_term(f) -> int:
	var sh = shadow_block(f)                          # B1-6d (Emulated, fixtures "shadow"): + +0x1e5 while +0x1e4 is set
	# B1-6e (Emulated, fixtures "getters"): - the disease level +0x19d.
	return aura_speed(f) + (int(sh.speed) if sh != null else 0) + (4 if berserk_level(f) == 2 else 0) + maxi(status_value(f, STATUS_SPEED), status_value(f, STATUS_HASTE)) - maxi(status_value(f, STATUS_SLOW), status_value(f, STATUS_FREEZE)) - disease_level(f)

## 0x51c6a0 (Read): the attack rate + max(effects 0x2f, 0x2e) - max(effects 0x37, 0x30) (the caller keeps it at least 1).
func rate_term(f) -> int:
	return maxi(status_value(f, STATUS_FAST_ATTACK), status_value(f, STATUS_HASTE)) - maxi(status_value(f, STATUS_SLOW_ATTACK), status_value(f, STATUS_FREEZE))

## 0x51c6a0 (disassembly 0x51c6a0..0x51c7bd, Read; Emulated by REVIEW_HERO_SPELLS_B.md's consumer rows,
## tests/hero_spells_b_review_fixtures.json): v = 10 + rate_term; B1-6d: with a fear bit 1 / 2 / 4 of +0xba (Scare, the
## flight, Awe) v - trunc(v / 2); then the hero's item terms or the type terms (`rate` is 10 + those, as combat.gd passes
## it: HeroEffects / ResearchEffects.attack_rate); at least 1.
func attack_rate(f, rate: int) -> int:
	var v := Rules.BASE_ATTACK_RATE + rate_term(f)
	if fear_bits(f) & 7: v -= Rules.tdiv(v, 2)
	return maxi(1, v + rate - Rules.BASE_ATTACK_RATE)

## The unit's walking speed follows speed_term (Provisional: the rebuild's walking speed is the unit's base_speed, which
## a running move keeps until its next order).
func sync_speed(f):
	var term := speed_term(f)
	var old := int(f.get("status_speed", 0))
	var u = _unit_node(int(f.id))
	if term == old or u == null: return
	f["status_speed"] = term
	# REVIEW F3: keep the unclamped value so a clamp at 1 does not drift (unless research has rebuilt base_speed since).
	var raw: int = int(f.speed_raw) if f.has("speed_raw") and int(u.base_speed) == maxi(1, int(f.speed_raw)) else int(u.base_speed)
	raw += term - old
	f["speed_raw"] = raw
	u.base_speed = maxi(1, raw)

func berserk_level(f) -> int:
	var b = f.get("berserk") if f != null else null
	return int(b.level) if b != null else -1

## 0x522860 (disassembly 0x522b6a..0x522bd7): a unit whose hit points fall to 0 with an active effect 0x3e of value > 0
## stands again at its maximum and message 0x1f8 goes out; its handler 0x4a96f0 clears every status entry (0x577480 on
## +0xfc; Emulated by REVIEW_HERO_SPELLS_B.md F1). Returns whether the death was prevented.
func life_ward(f) -> bool:
	if status_value(f, STATUS_LIFE_WARD) < 1: return false
	f.hp = int(f.max_hp)
	combat.units[f.id].hp = f.hp
	f.statuses = []
	sync_speed(f)
	return true

## 0x51aae0 (disassembly 0x51ac22..0x51acdb): a melee hit by an attacker with effect 0x7d (Venom Touch) poisons a target
## that 0x51c130 allows when a 1..100 roll is at most max(1, (10 - magic armour + 10) x 5). The 0x5286c0(5) terrain
## terms (+5 / -5 / 0) are not ported (Provisional: 0); the type-class poisoners (+0xaf = 5): B4-1 below.
func venom_hit(attacker, target):
	if attacker == null or target == null: return
	# B1-6e (REVIEW_HERO_SPELLS_E.md D1 / D3, Emulated U1): the hit function is 0x51abe0; both tests run before the hit's
	# damage lands (0x520e10 only stores it), so a killing blow still rolls; 0x5286c0(5 / 6) adjust the magic armour.
	# B4-1 (E9, Emulated "poison"; disassembly 0x51ac22..0x51acdb, decision 2: every race): an attacker whose class word +0xae has
	# high byte 5, or with effect 0x7d, poisons; strength the word's low byte (10 with effect 0x7d).
	var word := int(attacker.base.get("word_ae", 0)) & 0xffff
	var venom := _has_status(attacker, STATUS_VENOM)       # value 0: presence counts
	if (venom or RacePowers.class_byte(word) == RacePowers.POISON_CLASS) and poisonable(target):
		var chance := RacePowers.poison_chance(10 if venom else word & 0xff, _hit_armour(target, 5))
		if roll(1, 100, 0) <= chance: combat.set_poisoned(int(target.id), true)
	# B1-6e (disassembly 0x51ace0..0x51adf8; Emulated by REVIEW U1): then a diseased attacker diseases a target 0x51c1b0
	# allows when a 1..100 roll is at most max(1, (0x70d630 + 5 - magic armour' + 10) x 5). Attackers of type class 6
	# (+0xae high byte 6) spread it while healthy with strength 0x70d630 + +0xae's low byte: no rebuild state (Open).
	if bool(attacker.get("diseased", false)) and diseasable(target):
		var chance := maxi(1, (plague_pits() + 5 - _hit_armour(target, 6) + 10) * 5)
		if roll(1, 100, 0) <= chance: set_disease(target)
	# B3-1 (E14, Emulated "rabies"): a healthy attacker of type class 6 (a rabid Wolfrider, +0xae = 0x606 / 0x605) spreads it with
	# its strength: max(1, (strength + 0x70d630 - magic armour' + 10) x 5).
	# B5-1 (BATCH5_RESEARCH.md E9, decision 3, Emulated "class_hits"): every attacker whose class word has high byte 6 (the Ghoul
	# 0x608, the Slime 0x607, the Zombie 0x605 of every race), the rabid Wolfrider's word standing in for its type's.
	elif class_word(attacker) >> 8 == RacePowers.DISEASE_CLASS and diseasable(target):
		var chance := RacePowers.rabies_chance(class_word(attacker) & 0xff, plague_pits(), _hit_armour(target, 6))
		if roll(1, 100, 0) <= chance: set_disease(target)

## B5-1: the unit's type class word +0xae (ARM +0x5a, 0x43bfb0), or the rabid word 0x600 + strength PRAB wrote over it (B3-1).
func class_word(f) -> int:
	if int(f.get("rabies", 0)) > 0: return (RacePowers.DISEASE_CLASS << 8) | int(f.rabies)
	return int(f.base.get("word_ae", 0)) & 0xffff

## 0x4a49e0 (Read): a unit created while heroes carry effect 0x7e (Poison Gate) is poisoned when more than one hero has
## it, or one hero of another player does.
func _poison_gate(f):
	var count := 0
	var holder := -1
	for owner in combat.heroes:
		var h = _hero_fighter(int(owner))
		if h != null and _has_status(h, STATUS_POISON_GATE):        # value 0: 0x577520 finds the entry
			count += 1
			holder = int(owner)
	if count > 1 or (count == 1 and holder != int(f.owner)):
		f["poisoned_on_creation"] = true
		if _unit_node(int(f.id)) != null: combat.set_poisoned(int(f.id), true)

func _unit_node(id: int):
	return combat.units[id] if id >= 0 and id < combat.units.size() else null

func _has_status(f, kind: int) -> bool:
	return not status_entry(f, kind).is_empty()

## Kind 4 by the weather (Storm 81, Read 0x57be40): night 3 / 5, day 1 / 4 (level 1 / more); no weather object = day.
func is_night() -> bool:
	var dn = host.get("day_night") if host != null else null
	return dn != null and dn.has_method("is_night") and dn.is_night()

## 0x49bb10 (B1-6d, Light/Darkness; Read): it rains (B1-3's DayNight.raining, never set in the rebuild: Open).
func is_raining() -> bool:
	var dn = host.get("day_night") if host != null else null
	return dn != null and dn.get("raining") == true

# ------------------------------------------------------------------------------------------------ B1-6c: Nature, Divination, Arcane
const STATUS_SEE_INVISIBLE := 0x43    # 0x529e50 -> 0x40dd10 (See Invisible)
const STATUS_MIND_LEECH := 0x19       # 0x526fe0 (Mind Leech): a killer takes the victim's experience
const STATUS_MANA_LEECH := 0x29       # 0x526de0 (Mana Leech): mana per kill
const STATUS_RESEARCH := 0x25         # 0x40b6b0 (Comprehension): research price - n % (with item power 0x25, at most 75)
const STATUS_TRAINING := 3            # 0x557d90 (Telepathy): new units' starting experience (Combat.starting_xp)

## 0x437f70 (Read): the player has the research (any level).
func has_research(owner: int, id: String) -> bool:
	return production != null and production.research_level(owner, id) != 0

## Every entry of the kind goes (a helper; no B1-6c spell needs it: REVIEW_HERO_SPELLS_C.md D3 shows 0x577560 is only a
## lookup of the strongest entry).
func remove_status(o: Dictionary, kind: int):
	var f = combat.fighters.get(int(o.id)) if o.kind == "unit" else null
	if f == null or not f.has("statuses"): return
	f.statuses = f.statuses.filter(func(s): return int(s.kind) != kind)
	sync_speed(f)

## 0x40dd10 / 0x529e50 (Read): the player's living hero carries effect 0x43 or item power 0x43 (See Invisible): units
## with +0x1f1 (invisible) can then be seen and picked (0x548xxx, 0x51e6xx). Synchronised into visibility.gd each step.
func sees_invisible(owner: int) -> bool:
	var h = _hero_fighter(owner)
	if h == null or int(h.hp) < 1: return false
	return _has_status(h, STATUS_SEE_INVISIBLE) or HeroEffects.item_stat(combat.hero_block(owner), STATUS_SEE_INVISIBLE) != 0

## 0x57ae50 True Sight (Emulated, fixtures 118 'globals'): the owner's sight bonus 0x70d488 grows by the level for the rest
## of the match (no timer: nothing takes it back); the fog sweep reads it (visibility.gd sight_bonus, radius 10 + bonus).
## REVIEW_HERO_SPELLS_C.md D2 (Read): research completion (0x436500) adds to the same counter, so combat.gd's
## refresh_research adds sight_spells to the research sight counter instead of overwriting the spell's share.
var sight_spells: Dictionary = {}     # owner -> True Sight levels cast (part of 0x70d488)
func add_sight(owner: int, amount: int):
	sight_spells[owner] = int(sight_spells.get(owner, 0)) + amount
	var vis = host.get("visibility") if host != null else null
	if vis == null: return
	vis.sight_bonus[owner] = int(vis.sight_bonus.get(owner, 0)) + amount
	vis.dirty = true

## 0x526fe0 (Read): a non-hero AUKX / AUXX, or any unit with effect 0x19 (Mind Leech), takes its victims' experience.
func mind_leech(killer) -> int:
	if killer == null: return 0
	if not killer.hero and (String(killer.type_id) == "AUKX" or String(killer.type_id) == "AUXX"): return 1
	return status_value(killer, STATUS_MIND_LEECH)

## 0x526de0 (Read): the mana a kill gives: a non-hero 5 for the AHGB type, else 0; a hero skill 0x34 + item power 0x29 +
## effect 0x29 (Mana Leech).
func mana_leech_amount(killer) -> int:
	if not killer.hero: return 5 if String(killer.type_id) == "AHGB" else 0
	var block: Dictionary = combat.hero_block(int(killer.owner))
	var v := 0
	if not block.is_empty(): v = HeroEffects.skill_effect(block, 0x34) + HeroEffects.item_stat(block, 0x29)
	return v + status_value(killer, STATUS_MANA_LEECH)

## 0x5210b0 (Read, decompile 196242..196275): after an enemy kill (not an animal) the killer gains min(amount, maximum -
## current) mana, at most once per second (the killer's +0x194 stamp); a hero fills the player's pool.
func mana_leech(killer):
	var amount := mana_leech_amount(killer)
	if amount == 0: return
	if killer.has("leech_ms") and int(killer.leech_ms) + 1000 >= now(): return
	killer["leech_ms"] = now()
	var target = _hero_fighter(int(killer.owner)) if killer.hero else killer
	if target == null: return
	var gain := mini(amount, int(target.get("max_mana", 0)) - int(target.get("mana", 0)))
	if gain > 0: target.mana = int(target.mana) + gain

## 0x51b580, hero branch (Read): 20000 / derived 9 x 100 / (0x611220[PMRX] + skill 6 + effect 0x21 + item power 0x21);
## HeroEffects.mana_rate without the effect, which Enervate (0x21) adds.
func hero_mana_rate(f, block: Dictionary, research: Array) -> int:
	var add := status_value(f, STATUS_MANA_RATE)
	if add == 0: return HeroEffects.mana_rate(block, research)
	var interval: int = 20000 / maxi(1, HeroEffects.Rules.derived(block.stats, 9, 1))
	var percent: int = HeroEffects.MANA_RESEARCH[mini(HeroEffects.ProductionRules.research_level(research, "PMRX"), 9)] + HeroEffects.skill_effect(block, 6) + HeroEffects.item_stat(block, 0x21) + add
	if percent == 0: return 0
	return Rules.tdiv(interval * 100, percent)

## 0x40b6b0 (Read): Comprehension's effect 0x25 on the owner's living hero, added to the research discount.
func research_status(owner: int) -> int:
	var h = _hero_fighter(owner)
	return status_value(h, STATUS_RESEARCH) if h != null and int(h.hp) > 0 else 0

## Each step: the See Invisible state of every player for the fog / pick consumers (visibility.gd).
func _sync_sight():
	var vis = host.get("visibility") if host != null else null
	if vis == null or not "sees_invisible" in vis: return
	for owner in combat.heroes: vis.sees_invisible[int(owner)] = sees_invisible(int(owner))

# ------------------------------------------------------------------------------------------------ B1-6d: Summoning, Illusion
## B1-6d's world for kinds 0xc / 0xd (0..3) / 0xe / 0x12 / 0x18 / 0x19 / 0x1a and their consumers (SPELLS_RESEARCH.md
## "B1-6d"; tests/hero_spell_d_fixtures.json, tools/emulate_hero_spells_d.py). Fighter keys: "shadow" (+0x1e4..+0x1e8),
## "invisible_until" (+0x1f1 / +0x1f4), "illusion" (+0x1f0), "lifetime_until" (+0x1ec), "fear" (+0xba / +0x128).
const FEAR_TICK_MS := 1000            # 0x532a20 counts +0x128 down on every 40th world frame (0x5468e0; 25 ms frames: Read)

## 0x528570 (Emulated): the Shadowform block, while +0x1e4 is set; null otherwise.
func shadow_block(f):
	if f == null: return null
	var sh = f.get("shadow")
	return sh if sh != null and int(sh.until) >= now() else null

func shadow(o: Dictionary, speed: int, armour: int, magic: int, until: int):
	var f = combat.fighters.get(int(o.id))
	if f == null: return
	f["shadow"] = {"speed": speed, "armour": armour, "magic": magic, "until": until}
	sync_speed(f)

## 0x5285b0(1, until) (Emulated): +0x1f1 / +0x1f4.
func set_invisible(o: Dictionary, until: int):
	var f = combat.fighters.get(int(o.id))
	if f != null: f["invisible_until"] = until

## 0x5285b0(0, 0) (Read): the attack states 0x537060 / 0x5373a0 / 0x5374a0, the cast state 0x536cc0 and the damage path
## 0x522af0 (the hit-point setter, disassembly 0x522b2c) make an invisible unit visible again.
func reveal(f):
	if f != null and f.has("invisible_until"): f.erase("invisible_until")

func is_invisible(id: int) -> bool:
	var f = combat.fighters.get(id)
	return f != null and f.has("invisible_until")

## 0x51e670 (Read, decompile 194183): an order against a unit with +0x1f1 is dropped unless the LOCAL player's hero sees
## invisible (0x40dd10(0x709100)), for every unit's order, as in the original.
func hidden_target(order: Dictionary) -> bool:
	if String(order.get("target_kind", "")) != "unit" or not is_invisible(int(order.get("target_id", -1))): return false
	var local: int = int(host.get("local_player")) if host != null and host.get("local_player") != null else 0
	return not sees_invisible(local)

## 0x5334f0 (Read, decompile 207697): a search never takes a unit with +0x1f1 (See Invisible does not matter there).
func unsearchable(id: int) -> bool:
	return is_invisible(id)

func _sync_invisible():
	var vis = host.get("visibility") if host != null else null
	var local: int = int(host.get("local_player")) if host != null and host.get("local_player") != null else 0
	var now_hidden := {}
	for id in combat.fighters:
		var f = combat.fighters[id]
		if f.has("invisible_until"): now_hidden[int(id)] = true
		# 0x5377a0 (disassembly 0x538f1e..0x538f49, Read): the sprite takes look 9 under Shadowform (+0x1e4), as an illusion
		# of the local player (+0x1f0), or while invisible (+0x1f1). DELIBERATE presentation (labelled): look 9's own drawing
		# is not traced, the rebuild draws the sprite at half opacity.
		var ghost: bool = f.has("shadow") or f.has("invisible_until") or (bool(f.get("illusion", false)) and int(f.owner) == local)
		if ghost != bool(f.get("ghost", false)):
			f["ghost"] = ghost
			var u = _unit_node(int(id))
			var sprite = u.get("sprite") if u != null else null
			if sprite != null: sprite.self_modulate.a = 0.5 if ghost else 1.0
	if vis == null or not "invisible" in vis: return
	vis.invisible = now_hidden

## 0x51c7d0 (unit vtable +0x2c; disassembly 0x51c94c..0x51c9ac, Emulated by REVIEW_HERO_SPELLS_D.md U2): +0x1e4 clears once now passes +0x1e8, +0x1f1 once now passes +0x1f4;
## 0x51c835..0x51c876: a living unit with a lifetime +0x1ec dies once now passes it (vtable +0x38(0): hit points 0). B1-6d also
## counts the fear countdown here (0x532a20, FEAR_TICK_MS).
func _step_illusion_states(f, t: int):
	var sh = f.get("shadow")
	if sh != null and t > int(sh.until):
		f.erase("shadow")
		sync_speed(f)
	if f.has("invisible_until") and t > int(f.invisible_until): f.erase("invisible_until")
	if int(f.get("lifetime_until", 0)) != 0 and t > int(f.lifetime_until):
		combat.apply_damage("unit", int(f.id), int(f.hp), -1, "unit")   # 0x522af0(0, 0, 1); +0x1ec stays (REVIEW D1)
		return
	var fear = f.get("fear")
	if fear != null and t >= int(fear.next_ms):
		fear.next_ms = int(fear.next_ms) + FEAR_TICK_MS
		fear.seconds = int(fear.seconds) - 1
		if int(fear.seconds) <= 0:
			# 0x532a20 (Read, decompile 207135..207150): a unit whose word is exactly 2 (fleeing) stops; the word clears.
			if int(fear.bits) == 2: _stop_unit(int(f.id))
			f.erase("fear")

func fear_bits(f) -> int:
	var fear = f.get("fear") if f != null else null
	return int(fear.bits) if fear != null else 0

## 0x5286c0(case) (Read, decompile 200517..200669; its use Emulated): 1 = immune (the Brew's +0x1f8, STATUS bit 14, +0x1cd,
## an animal), else per case the STATUS classes 0x10 / 0x20 (a longer fear) or 2 / 4 / 8 (0x532a20's chance terms).
func fear_class(f, case_index: int) -> int:
	if int(f.get("drunk_until", 0)) > 0: return 1
	var s := int(f.base.get("flags", 0))
	if s >> 14 & 1 or String(f.type_id) in SpellEffects.CRITTERS: return 1
	# B5-1 (Emulated tests/batch5_fixtures.json "immunity": ATFX, ATGX, ATLX 1 / 1; decompile 200531): the titan flag +0x1cd.
	if UnitRanks.is_titan(String(f.type_id)): return 1
	var bit := func(n: int) -> bool: return s >> n & 1 == 1
	match case_index:
		1:
			if bit.call(8): return 0x10
			if bit.call(3): return 1
			if bit.call(4): return 2
			if bit.call(5) or bit.call(2): return 1
			if bit.call(23): return 2
		2:
			if bit.call(8): return 0x10
			if bit.call(3): return 1
			if bit.call(4): return 2
			if bit.call(2): return 1
		3:
			if bit.call(8): return 0x10
			if bit.call(2): return 1
			if bit.call(5): return 0x20
			if bit.call(23): return 1
		4:
			if bit.call(8): return 0x10
			if bit.call(2): return 1
			if bit.call(7): return 0x22
			if bit.call(23): return 1
			if bit.call(10): return 2
		5, 6:
			# B1-6e (REVIEW_HERO_SPELLS_E.md D1, Emulated U1; decompile 200608..200662): Venom's (5) and the contagion's (6)
			# magic-armour class: 2 -> +5, 4 -> -5, 8 -> 0 (Dwarves AD* bit 1, AE* bit 3, AW* bit 4).
			if bit.call(8) or bit.call(2): return 1
			if bit.call(1): return 2
			if bit.call(3): return 8
			if bit.call(4): return 4
			if case_index == 5 and (bit.call(24) or bit.call(10)): return 2
			if case_index == 6 and String(f.type_id) in ["AGGX", "AGPC", "AGGZ", "AGFL", "AGSP", "AGSL"]: return 1
	return 0

## 0x51abe0's magic armour of a Venom (case 5) / contagion (case 6) target: +5 / -5 / 0 by 0x5286c0's class.
func _hit_armour(target, case_index: int) -> int:
	var mres := _magic_armour(target)
	var c := fear_class(target, case_index)
	if c & 2: return mres + 5
	if c & 4: return mres - 5
	if c & 8: return 0
	return mres

## 0x528a40(n) (Read; the words and counts Emulated, fixtures 31 / 33 'fear'): n = 1 / 2 / 4 / 8 asks 0x5286c0(1 / 2 / 3 /
## 4); immune (bit 1) -> false; else +0xba |= n and +0x128 = the seconds of n (45 / 15 / 30 / 30), or with class 0x10, 0x20,
## 0x40 the longer ones; n = 2 (flight) also stops the unit's action.
const FEAR_SECONDS := {1: [45, 135, 90, 211], 2: [15, 45, 30, 241], 4: [30, 90, 60, 226], 8: [30, 90, 60, 226]}
func frighten(o: Dictionary, n: int) -> bool:
	var f = combat.fighters.get(int(o.id))
	if f == null or f.hero: return false
	var r := fear_class(f, {1: 1, 2: 2, 4: 3, 8: 4}.get(n, 1))
	if r & 1: return false
	var times: Array = FEAR_SECONDS.get(n, [30, 90, 60, 226])
	var seconds: int = int(times[0])
	if r & 0x10: seconds = int(times[1])
	elif r & 0x20: seconds = int(times[2])
	elif r & 0x40: seconds = int(times[3])
	var fear = f.get("fear")
	var bits: int = (int(fear.bits) if fear != null else 0) | n
	f["fear"] = {"bits": bits, "seconds": seconds, "next_ms": now() + FEAR_TICK_MS}
	if n == 2: _stop_unit(int(f.id))
	return true

func _stop_unit(id: int):
	combat.order_stop(id)
	var u = _unit_node(id)
	if u != null: u.stop()

## 0x530a90 with its seventh argument 1 (Read; its use Emulated with the cell recorded): the free cell nearest `cell` that
## the unit can reach from its own cell (0x509320's flood of the unit's movement type over the sector regions); a flyer
## uses the air layer without the reachability test (movement 1). The spiral and score are navigation.free_cell_near's
## (0x530a90, Emulated in M-x); extent 2 units are tested on the extent-1 regions (Provisional).
func reachable_cell(o: Dictionary, cell: Vector2i) -> Vector2i:
	var u = _unit_node(int(o.id))
	if u == null: return cell
	if bool(u.flying): return navigator.free_air_cell_near(_clamp_cell(cell), u)
	var mtype := int(u.movement_type)
	var start_region: int = navigator.region(u.cell)
	if start_region < 0 or navigator.regions.is_empty(): return navigator.free_cell_near(cell, u, int(u.extent), mtype)
	var reached := {start_region: true}
	var queue: Array = [start_region]
	while not queue.is_empty():
		var r: int = queue.pop_back()
		for other in navigator.regions[r].links:
			if reached.has(int(other)) or not navigator._admitted(navigator.regions[int(other)], mtype): continue
			reached[int(other)] = true
			queue.append(int(other))
	var ok := func(c: Vector2i) -> bool:
		if not navigator.collision.inside(c) or not reached.has(navigator.region(c)): return false
		if int(u.extent) > 1 or mtype != 0: return navigator.enterable_extent(c, int(u.extent), mtype) and navigator.occupant_extent(c, int(u.extent), u) == null
		var data: Dictionary = navigator.collision.cell_data(c)
		var taken: bool = navigator.building_cells.has(c) or not data.object_indices.is_empty()
		return not taken and data.profile_passable[0] and navigator.occupant(c, u) == null and navigator.enterable_static(c)
	if ok.call(cell): return cell
	var origin_height: int = navigator.nav_cell_height(cell) if navigator.collision.inside(cell) else 0
	var c := cell
	var direction := 0
	var arm := 1
	var walked := 0
	var total := 0
	var after := 0
	var found := false
	var best := 5000
	var chosen := Vector2i(-1, -1)
	while true:
		if after > 10: break
		if found: after += 1
		else: total += 1
		match direction:
			0: c.x += 1
			1: c.y += 1
			2: c.x -= 1
			3: c.y -= 1
		walked += 1
		if walked == arm:
			walked = 0
			direction = (direction + 1) % 4
			if direction == 0 or direction == 2: arm += 1
		total += 1
		if ok.call(c):
			var dx := absi(c.x - cell.x)
			var dy := absi(c.y - cell.y)
			var score := mini(dx, dy) + (maxi(dx, dy) + absi(navigator.nav_cell_height(c) - origin_height) * 4) * 2
			if not found or score < best:
				found = true
				best = score
				chosen = c
		if total >= 300: break
	return chosen

func _clamp_cell(cell: Vector2i) -> Vector2i:
	var size := map_size()
	return Vector2i(clampi(cell.x, 0, size.x - 1), clampi(cell.y, 0, size.y - 1))

## Kind 0x12's per-kind stage (Read: 0x493940, 0x51bb80(0), 0x5351d0, unit vtable +0x30(0) = 0x51b9f0, which only
## re-occupies the footprint; REVIEW_HERO_SPELLS_D.md D2): the unit stands at the cell and keeps its orders; its walk is
## reset so a running order plans again from the new cell.
func teleport(o: Dictionary, cell: Vector2i):
	var u = _unit_node(int(o.id))
	if u == null: return
	u.clear_route()
	u.in_step = false
	navigator.release(u, u.cell)
	u.position = navigator.center(cell)
	u.cell = cell
	navigator.occupy(u, cell)

## 0x581700 Blink's cell (Emulated, fixtures 13 'seed n' / 'edge'; disassembly 0x581724..0x5817da): r = vtable +0x64(0);
## x in max(1, x - r) .. min(x + r, width - 2), then y in max(1, y - r) .. min(y + r, height - 2), each one 1..n roll.
func blink_cell(f) -> Vector2i:
	var here: Vector2i = combat.unit_cell(int(f.id))
	var r := spell_radius(f, 0)
	var size := map_size()
	var x0 := maxi(1, here.x - r)
	var x1 := mini(here.x + r, size.x - 2)
	var y0 := maxi(1, here.y - r)
	var y1 := mini(here.y + r, size.y - 2)
	var x: int = roll(1, x1 - x0 + 1, x0 - 1)
	var y: int = roll(1, y1 - y0 + 1, y0 - 1)
	return Vector2i(x, y)

## 0x581bc0 Home Portal's cell (Emulated, fixtures 16 'start'): the owner's start location 0x708fa8 / 0x708fac (the
## scenario's side record: the skirmish slot's start); (0, 0) without one (the per-kind stage then moves nothing).
func start_cell(owner: int) -> Vector2i:
	var sk = host.get("skirmish") if host != null else null
	if sk != null and owner < sk.slots.size() and sk.slots[owner] is Dictionary and sk.slots[owner].has("start"):
		var s: Vector2i = sk.slots[owner].start
		if s.x >= 0: return s
	var fixed = host.get("start_cells") if host != null else null
	if fixed is Dictionary and fixed.has(owner): return Vector2i(fixed[owner])
	return Vector2i.ZERO

## 0x43c450 (Emulated, fixtures "illusion_data", against 0x43bfb0 for the same types): an illusion's block is its type's
## with combat 1, magic armour 0, hit points / 4 (truncated), damage 1, range / 2, armour 0, resistances -1 / -1, and a
## command cost of 1 unless a dragon; the unit carries +0x1f0 = 1 (0x4a49e0). The command cost is not modelled per unit
## (production.gd counts by type: Open), nor the block's +0x54 / +0x86 bytes (Open).
func make_illusion(f):
	f["illusion"] = true
	var base: Dictionary = f.base
	base.combat = 1
	base.mres = 0
	base.max_hp = Rules.tdiv(int(base.max_hp), 4)
	base.dmg = 1
	base.range = Rules.tdiv(int(base.get("range", 0)), 2)
	base.armour = 0
	base.res1 = -1
	base.res2 = -1
	f.max_hp = int(base.max_hp)
	f.hp = int(base.max_hp)
	combat._apply_research(f)
	var u = _unit_node(int(f.id))
	if u != null:
		u.hp = f.hp
		u.max_hp = f.max_hp

## 0x4aa840 case 0x19 (Emulated): the unit goes without remains (0x4a9890, message 0x1fb), the animal of player 6 stands
## at the free cell nearest it (0x43b4c0 radius 1; message 0xfa without experience).
func mutate(o: Dictionary, animal: String) -> Dictionary:
	var f = combat.fighters.get(int(o.id))
	if f == null: return {}
	var cell: Vector2i = o.cell
	_remove_quietly(int(o.id))
	var made := spawn(animal, cell, SpellEffects.NEUTRAL, 0, 1)
	if not made.is_empty(): made["from"] = int(o.id)
	return made

## 0x4a91d0 -> message 0x1f4 -> 0x4a8ff0 (Read; the message Emulated): the unit morphs into `type_id` at its cell, as an
## advancement does (main.gd morph_unit: EZ41, Morph.wav, the old unit removed without a death); the message's costs are
## zero.
func transform(o: Dictionary, type_id: String) -> Dictionary:
	var u = _unit_node(int(o.id))
	if u == null or production == null or production.rules.definition(type_id).is_empty(): return {}
	if host != null and host.has_method("morph_unit"):
		var made = host.morph_unit(u, type_id, true)
		return {} if made == null else {"id": int(made.unit_id), "type": type_id, "from": int(o.id), "cell": o.cell}
	var cell: Vector2i = o.cell
	var owner := int(o.owner)
	_remove_quietly(int(o.id))
	var out := spawn(type_id, cell, owner, 0, 0)
	if not out.is_empty(): out["from"] = int(o.id)
	return out

## 0x5325d0 (Read, decompile 206816; Emulated through 'transform keep seed n'): the owner's highest keep (a building whose
## code's second letter is K) level + 1: its fourth character - '/' (BKx0 -> 1 .. BKx4 -> 5); 0 without one.
## B1-6e: Acquire's 0x532640(owner, cell, reach, 1) (Read; the scan 0x5489e0 Emulated in milestone 12,
## tests/conversion_fixtures.json): milestone 12's eligibility and scan order with the resource-building test 0x52b050
## (Provisional: the rebuild's mines; BUI words +0x94..+0x9a are not modelled), at most eight, then the transfer (0x104).
## Returns the converted ids.
func acquire_mines(owner: int, cell: Vector2i, reach: int) -> Array:
	var conv = host.get("conversions") if host != null else null
	if conv == null or conv.mines == null: return []
	var MatchConversion = load("res://simulation/match_conversion.gd")
	var targets: Array = MatchConversion.Targets.select_from(conv.records(), owner, cell, reach,
		func(o, e): return conv.mines.mines.has(e.entity_id) and conv.eligible(o, e))
	conv.transfer(targets, owner)
	return targets.map(func(e): return int(e.entity_id))

func keep_level(owner: int) -> int:
	if production == null: return 0
	var best := 0
	for b in production.buildings.values():
		if int(b.owner) != owner: continue
		var code := String(b.original_type_id)
		if code.length() >= 4 and code[1] == "K": best = maxi(best, code.unicode_at(3) - 0x2f)
	return best

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). The spell table is data (spell_table.json).
const _SAVE_SKIP := ["_world", "combat", "production", "host", "mines", "economy", "navigator", "table", "hero_spells"]

func save_state(refs) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, _SAVE_SKIP)
	s["hero_spells"] = hero_spells.save_state(refs)
	return s

func load_state(state: Dictionary, refs):
	preload("res://simulation/save_game.gd").restore(self, state, _SAVE_SKIP)
	hero_spells.load_state(state.hero_spells, refs)
