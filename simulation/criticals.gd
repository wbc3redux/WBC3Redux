extends RefCounted
## G-4 (COMBAT_RESEARCH.md "G-4"): the critical-hit side effects.
##
## Where the effect byte comes from (Read; Emulated where marked):
## * a melee swing 0x42ace0 (combat_rules.gd swing: the x4 / x2 bands by damage type, effect 4 for the assassin's roll);
## * a unit's shot 0x523150: one 1..100 draw for every shot (petrifiers too), below 5 the swing's table by damage type
##   (missile_kind, Emulated by B3 "missile_kinds"); otherwise the kind the missile class gave its art (0x53f180, Emulated
##   here: tests/criticals_fixtures.json "art_kinds": EMF1 Burn, EMF2 Freeze, EMF3 Armor Reduced, EMF4 XP Drained, EMF5
##   Crystallize, EMF6 Mana Drain).
## What it does: the melee hit function 0x51abe0 (unit vtable +0x20, Emulated "hits") and the missile impact 0x5427e0
## (Read) send a message per effect; their handlers (Emulated "handlers" / "cleave" / "armour") change the target:
##   1 Burn 0x204 (spells.berserk, B2-1)      3 Petrify 0x20e (combat._petrify, B3-1)   4 Assassinate 0x20f: +100 gold
##   5 Crystallize 0x214: +100 crystal, no body  6 Freeze 0x21e -> 0x527b30            8 Stun 0x221 -> 0x527d10(level)
##   9 Mana Drain 0x21f -> 0x527a00(level)      10 Ignore Armor (no message: the armour is skipped, EZ06 and the text)
##  11 Cleave 0x220 -> 0x5278a0: a kind 0x13 record around the attacker   12 XP Drained 0x223   14 Armor Reduced 0x224
##   7 (damage type 4) has no case in either switch: nothing happens.
## Presentation (texts, art, sounds) goes out through spells.floated (P-3's way; effects_layer.gd draws it).
const SpellEffects = preload("res://simulation/spell_effects.gd")

const BURN := 1
const PETRIFY := 3
const ASSASSINATE := 4
const CRYSTALLIZE := 5
const FREEZE := 6
const NONE_7 := 7
const STUN := 8
const MANA_DRAIN := 9
const IGNORE_ARMOUR := 10
const CLEAVE := 11
const XP_DRAIN := 12
const ARMOUR_REDUCED := 14

## 0x53f180 (Emulated "art_kinds", 32 missile codes): the kind +0x67c and level +0x67d a missile's art gives it.
const ART_KINDS := {"EMF1": [BURN, 0], "EMF2": [FREEZE, 5], "EMF3": [ARMOUR_REDUCED, 2], "EMF4": [XP_DRAIN, 10],
	"EMF5": [CRYSTALLIZE, 10], "EMF6": [MANA_DRAIN, 40]}
## 0x51abe0's message per effect byte (Emulated "hits": a surviving and a killed target, effects 0..11). Effects 3 and 5
## (0x20e / 0x214 when the blow kills, 3 sends 0x21e otherwise) are missile kinds the swing never writes: not ported here.
const MELEE_MESSAGES := {BURN: 0x204, ASSASSINATE: 0x20f, FREEZE: 0x21e, STUN: 0x221, MANA_DRAIN: 0x21f, CLEAVE: 0x220}
const PETRIFIERS := ["ATOX", "AOXX"]            # 0x523150: kind 3 whatever the draw (B3-1 E11)
const KIND_CHANCE := 5                          # 0x523531: the draw below 5 (4 %)
const REWARD := 100                             # 0x51ae7b / 0x542d.. : Assassinate's gold, Crystallize's crystal
const NEUTRAL := 6                              # 0x4a9e90: no gold for player 6

const FREEZE_STATUS := 0x30                     # 0x527b30 (Emulated): 0x30 = 6 for 8 s, art 0
const FREEZE_VALUE := 6
const FREEZE_MS := 8000
const FREEZE_LOOK := 7                          # the map node's +0x132 until now + 8000 (when no longer 0x30 runs)
const STUN_VALUE := 10                          # 0x527d10 (Emulated): 0x46 = 10 for level x 1000 ms, art 0
const CLEAVE_RADIUS := 2                        # 0x5278a0 (Emulated "cleave"): the record's +8, +9 2, +0xa 1, +0xc 4
const CLEAVE_MODE := 2
const CLEAVE_DTYPE := 6

## Game.txt lines and colours (0x44f4a0 / 0x53a010 arguments, Read).
const LINES := {"ignore": 0x459, "cleave": 0x45a, "stun": 0x45b, "freeze": 0x45c, "mana": 0x45e, "xp": 0x360,
	"armour": 0x35f, "assassinate": 0x47a, "crystallize": 0x47c}
const CRYSTAL_BURST := [8, 8, 1, 1, 4, 1, 10, 1, 0, 1]   # 0x528190 -> 0x58c0d0 (decompile 200270)

## 0x523150 (Read, disassembly 0x52351e..0x52369b; kinds Emulated by B3 "missile_kinds"): the kind and level of a new
## unit shot. `hit`: the draw (and for type 0xb the second draw) came out below 5; `art`: the art's kind (art_kind).
static func missile_kind(type_id: String, dtype: int, damage: int, hit: bool, art: Array) -> Array:
	if type_id in PETRIFIERS: return [PETRIFY, 0]
	if not hit: return art
	match dtype:
		3, 0xb: return [BURN, 0]
		1: return [FREEZE, 5]
		2: return [MANA_DRAIN, 0x28]
		4: return [NONE_7, 0]
		5: return [STUN, 5]
		6: return [CLEAVE, 0x32 if damage > 0x32 else damage & 0xff]
		0: return [IGNORE_ARMOUR, 0]
	return art

static func art_kind(art: String) -> Array:
	return Array(ART_KINDS.get(art, [0, 0])).duplicate()

## The draws of 0x523150 on the combat generator: always one, a second for damage type 0xb when the first missed.
static func draw_kind(rng, dtype: int) -> bool:
	var hit: bool = int(rng.roll(1, 100, 0)) < KIND_CHANCE
	if not hit and dtype == 0xb: hit = int(rng.roll(1, 100, 0)) < KIND_CHANCE
	return hit

# ------------------------------------------------------------------------------------------------ the melee hit (0x51abe0)
## Before the damage: effect 4 (0x51adfd: message 0x20f goes before the hit's own message 0x520e20).
static func before_blow(c, f, kind: String, id: int, result: Dictionary):
	if kind != "unit" or int(result.get("effect", 0)) != ASSASSINATE: return
	assassinate(c, f, id)

## After the damage (0x51aea2..: the switch on the effect byte; every case needs a unit target).
static func after_blow(c, f, kind: String, id: int, result: Dictionary):
	if kind != "unit" or c.spells == null: return
	var t = c.fighters.get(id)
	if t == null or t.removed: return
	match int(result.get("effect", 0)):
		FREEZE: freeze(c, t)
		STUN: stun(c, t, int(result.param))
		MANA_DRAIN: mana_drain(c, t, int(result.param))
		IGNORE_ARMOUR: ignore_armour(c, t, 1)
		CLEAVE: cleave(c, f, t, int(result.param))

# ------------------------------------------------------------------------------------------------ the missile impact (0x5427e0)
## The impact's switch after the damage (decompile 214710-214814): the struck object must be a unit.
static func after_impact(c, m: Dictionary, hit: Dictionary):
	if hit.kind != "unit" or c.spells == null: return
	var t = c.fighters.get(int(hit.id))
	if t == null or t.removed: return
	var level := int(m.get("level", 0))
	match int(m.get("kind", 0)):
		FREEZE: freeze(c, t)
		STUN: stun(c, t, level)
		MANA_DRAIN: mana_drain(c, t, level)
		IGNORE_ARMOUR: ignore_armour(c, t, 1)
		CLEAVE:
			var shooter = c.fighters.get(int(m.get("attacker", -1))) if String(m.get("attacker_kind", "unit")) == "unit" else null
			if shooter != null: cleave(c, shooter, t, level)
		XP_DRAIN: xp_drain(c, t, level)
		ARMOUR_REDUCED: armour_reduced(c, t, level)

## Kind 10 against a unit (0x5428cb): the damage skips the armour tail.
static func skips_armour(m: Dictionary, hit_kind: String) -> bool:
	return hit_kind == "unit" and int(m.get("kind", 0)) == IGNORE_ARMOUR

# ------------------------------------------------------------------------------------------------ the handlers
## 0x527b30 (Emulated): a living unit gets 0x30 = 6 for 8 s (0x5773b0 replaces an entry of kind 0x30 and art 0, a longer
## one too); unless a 0x30 entry already ran past now + 8000, the map node shows look 7 until then when its look ends by
## then. EZ64 (once, depth + 2), "Critical: Freeze", IceCrit.wav in view; the light (0x44edb0) is not ported.
static func freeze(c, t):
	if int(t.hp) < 1: return
	var until: int = int(c.now_ms) + FREEZE_MS
	var longer := false
	for s in t.get("statuses", []):
		if int(s.kind) == FREEZE_STATUS and int(s.until) > until: longer = true
	c.spells.add_status({"kind": "unit", "id": int(t.id)}, {"kind": FREEZE_STATUS, "value": FREEZE_VALUE, "until": until, "art": 0})
	var look = t.get("look")
	if not longer and (look == null or int(look.get("until", 0)) <= until):
		c.spells.set_look({"kind": "unit", "id": int(t.id)}, FREEZE_LOOK, until)
	_float(c, t, "freeze", 0, 0, [{"code": "EZ64", "on": int(t.id), "once": true, "depth": 2}], "IceCrit.wav")

## 0x527d10 (Emulated, the same function as Psychic Blast's): 0x46 = 10 for level x 1000 ms, art 0; EZ10 on the unit while
## it lasts, "Critical: Stun", EZ63 once (depth + 2), CrushCrit.wav in view.
static func stun(c, t, level: int):
	if int(t.hp) < 1: return
	var until: int = int(c.now_ms) + level * 1000
	c.spells.add_status({"kind": "unit", "id": int(t.id)}, {"kind": SpellEffects.STATUS_STUNNED, "value": STUN_VALUE, "until": until, "art": 0})
	_float(c, t, "stun", 0, 0, [{"code": "EZ10", "on": int(t.id), "follow": true, "until": until},
		{"code": "EZ63", "on": int(t.id), "once": true, "depth": 2}], "CrushCrit.wav")

## 0x527a00 (Emulated): a unit loses min(level, mana) and nothing happens at 0 mana; a hero's player pool loses level,
## clamped at 0. No hit-point test. EZ61 (once, depth + 1), "Critical: Mana Drain", ElectricCrit.wav in view.
static func mana_drain(c, t, level: int):
	if c.spells.drain_mana({"kind": "unit", "id": int(t.id)}, level) < 0: return
	_float(c, t, "mana", 0, 0, [{"code": "EZ61", "on": int(t.id), "once": true, "depth": 1}], "ElectricCrit.wav")

## 0x51b119 / 0x5427e0 case 10 (Read): EZ06 at the unit; in view "Critical: Ignore Armor" and PiercingCrit.wav.
static func ignore_armour(c, t, depth: int):
	_float(c, t, "ignore", 0, 0, [{"code": "EZ06", "on": int(t.id), "once": true, "depth": depth}], "PiercingCrit.wav", true)

## 0x5278a0 (Emulated "cleave"): with the attacker found, "Critical: Cleave" over the target, then the host sends the
## record (0x1f7) of the attacker: kind 0x13, radius 2, enemies, units only, alive, not the caster, the level as the
## damage through 0x42bbf0 mode 2, damage type 6, effect EZ62 (+0x8d).
static func cleave(c, attacker, t, level: int):
	if attacker == null or attacker.removed: return
	_float(c, t, "cleave", 0, 0, [], "")
	var caster := {"kind": "unit", "id": int(attacker.id)}
	var record: Dictionary = c.spells._record(caster, {"radius": CLEAVE_RADIUS, "b9": 2, "b10": 1, "b11": 0, "b12": 4,
		"effect": "EZ62", "kind": SpellEffects.DAMAGE, "amount": level, "w9b": CLEAVE_MODE, "w9d": CLEAVE_DTYPE, "w9f": 1})
	c.spells.cast_built(record, caster, 0)

## 0x527ed0 (Emulated for units; the hero branch Read): a living unit loses level experience (+0x40, clamped at 0); a hero
## of the local player loses it from the profile's experience 0x709d04 (clamped); another player's hero keeps it.
## "%d XP Drained" (colour 2), EZ15 (once, depth + 2).
static func xp_drain(c, t, level: int):
	if int(t.hp) < 1: return
	_float(c, t, "xp", level, 2, [{"code": "EZ15", "on": int(t.id), "once": true, "depth": 2}], "")
	if not t.hero:
		t.xp = maxi(0, int(t.xp) - level)
		return
	var side = c.heroes.get(int(t.owner))
	var hm = side.match if side != null else null
	if hm != null and not bool(hm.computer) and hm.profile != null:
		hm.profile.data.xp = maxi(0, int(hm.profile.data.xp) - level)

## 0x527ff0 (Emulated): a living unit's +0x20c grows by level for good; 0x5260a0(1) takes it from armour word 0 last,
## clamped at 0 (combat.combat_block). "Armor Reduced" (colour 2), EZ15 (once, depth + 2).
static func armour_reduced(c, t, level: int):
	if int(t.hp) < 1: return
	t["armour_cut"] = int(t.get("armour_cut", 0)) + level
	_float(c, t, "armour", 0, 2, [{"code": "EZ15", "on": int(t.id), "once": true, "depth": 2}], "")

## 0x4a9e90 (Read; the message Emulated "hits"): the attacker's owner gets 100 gold (not player 6); EZ43 at the target
## (once, depth + 2) with Assassination.wav at most once a second; "Assassinate: +100 Gold" over a non-hero attacker.
static func assassinate(c, f, target_id: int):
	if int(f.owner) != NEUTRAL: c.spells.credit(int(f.owner), [REWARD, 0, 0, 0])
	var info := {"id": -1 if f.hero else int(f.id), "line": LINES.assassinate, "value": 0, "colour": 1, "ms": 1000,
		"effects": [{"code": "EZ43", "on": target_id, "once": true, "depth": 2}], "sound": "Assassination.wav",
		"sound_on": target_id, "sound_cooldown": "assassination"}
	c.spells.floated.emit(info)

## 0x5427e0 kind 5 -> 0x214 -> 0x4a9d90 / 0x528190 (Read; the melee message Emulated "hits"): as Petrify, a unit the shot
## brings to 0 (not under Life Ward) leaves no body and the shooter's owner gets 100 crystal; the burst at the body,
## Crystallize.wav at most once a second when the local player is either side, "Crystallize: +100 Crystal" over the shooter.
static func crystallize(c, t, shooter):
	if shooter == null: return
	t.removed = true
	var unit = c.units[t.id]
	unit.visible = false
	unit.removed = true
	c.spells.credit(int(shooter.owner), [0, 0, REWARD, 0])
	c.spells.floated.emit({"id": int(shooter.id), "line": LINES.crystallize, "value": 0, "colour": 1, "ms": 1000,
		"bursts": [{"burst": CRYSTAL_BURST, "pixel": Vector2i(int(unit.position.x), int(unit.position.y)), "row": int(unit.cell.y)}],
		"sound": "Crystallize.wav", "sound_cell": unit.cell, "sound_cooldown": "crystallize", "local_party": [int(t.owner), int(shooter.owner)]})

static func _float(c, t, key: String, value: int, colour: int, effects: Array, sound: String, view_only := false):
	var info := {"id": int(t.id), "line": int(LINES[key]), "value": value, "colour": colour, "ms": 1000, "effects": effects}
	if sound != "":
		info["sound"] = sound
		info["sound_on"] = int(t.id)
		info["sound_view"] = true
	if view_only: info["text_view"] = true
	c.spells.floated.emit(info)
