extends RefCounted
## B1-3 (B1_3_RESEARCH.md, BATCH1_RESEARCH.md R1-R3, R8): Undead advancement. A selection of one Undead unit type gets up
## to three advancement buttons in the control panel's unit row (0x4d3200); a press prices the step (0x40b6b0(target,
## source, player)), and the order 0x4cef90 sends message 500 (one unit) or 0x1f6 (up to 16 units, twice for up to 32)
## whose handlers 0x4a8ff0 / 0x4a9400 morph each unit into the new type and then charge the message's cost.
##
## Evidence: the tree 0x4fd8c0, the flat prices 0x40b6b0, the discount 0x40c350, the buttons 0x4d3200 (154 rows) and the
## order's messages 0x4cef90 are Emulated (tests/batch1_review_fixtures.json "advancement", checked by
## tests/test_advancement.gd). The morph handlers and the starting experience 0x557d90 are Read (decompile 113534,
## 113759, 110379, 228773).
## Open 1 (settled, Read): the new unit is created fresh by 0x4a49e0 (full hit points of the new type); its experience is
## the old unit's +0x40 less the new type's starting experience s = 0x557d90(...), given only when positive, plus s again
## through 0x527100: max(old, s) for s >= 0. The old unit is removed without a death (0x51a130(1)).

const HeroEffects = preload("res://simulation/hero_effects.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")

## 0x4fd8c0 (Emulated): the types a source advances to, in the order the original lists them.
const TREE := {"AUIX": ["AUJX", "AUKX"], "AUJX": ["AULX", "AUMX"], "AUKX": ["AUXX"], "AULX": ["AUAX"]}
## 0x4cef90 (Read): the source type a target's order looks for in the selection (B4-1: the Elves' AEAX <- AEBX row went: the Wisp merge is its own cell, race_powers.gd).
const SOURCE := {"AUJX": "AUIX", "AUKX": "AUIX", "AULX": "AUJX", "AUMX": "AUJX", "AUXX": "AUKX", "AUAX": "AULX"}
## 0x4d3200 (Emulated): per source the buttons in order: target, icon (Panel_Icons), callback, the buildings 0x40b580 must
## find owned, and the one stockpile lane (0 gold, 1 metal, 2 crystal, 3 stone) compared with price x selection count.
const BUTTONS := {
	"AUIX": [{"target": "AUJX", "icon": 0x2e, "callback": "0x4cf4b0", "gates": ["BPDM"], "lane": 1},
		{"target": "AUKX", "icon": 0x2c, "callback": "0x4cf500", "gates": ["BPBA"], "lane": 2}],
	"AUKX": [{"target": "AUXX", "icon": 0x2d, "callback": "0x4cf550", "gates": ["BPAS"], "lane": 2}],
	"AUJX": [{"target": "AULX", "icon": 0x2f, "callback": "0x4cf5a0", "gates": ["BPCG"], "lane": 1},
		{"target": "AUMX", "icon": 0x30, "callback": "0x4cf640", "gates": ["BPBL"], "lane": 2}],
	"AULX": [{"target": "AUAX", "icon": 0x37, "callback": "0x4cf5f0", "gates": ["BPBL", "BPCG", "BPAS", "BPBA"], "lane": 1}],
}
const UNDEAD := 2                         # 0x708f96: the buttons need the local player's race 2
const GROUP_LIMIT := 16                   # 0x4cef90: units per 0x1f6 message; a second message takes the next 16
const EFFECT := "EZ41"                    # 0x4a8ff0 / 0x4a9400 / 0x4a9230: 0x44e8f0(unit, 'EZ41', ...)
const SOUND := "Morph.wav"                # played for the first unit of a message only

## 0x4d3200 for a selection of `count` units of `source` (all the same type, no hero): the advancement buttons. `owned`
## answers 0x40b580(player, building); `price` returns 0x40b6b0(target, source, player) as [gold, metal, crystal, stone];
## `stock` is the player's stockpile [gold, metal, crystal, stone].
static func buttons(source: String, count: int, owned: Callable, price: Callable, stock: Array) -> Array:
	var out: Array = []
	for b in BUTTONS.get(source, []):
		var cost: Array = price.call(String(b.target))
		var gates_ok := true
		for g in b.gates:
			if not owned.call(String(g)): gates_ok = false
		var lane: int = int(b.lane)
		var enabled: bool = gates_ok and int(stock[lane]) >= int(cost[lane]) * count
		out.append({"target": b.target, "icon": b.icon, "callback": b.callback, "enabled": enabled, "cost": cost})
	return out

## 0x4cef90(player, target, gold, metal, stone, crystal) over the selection (`units`: [{id, type, removed}] in selection
## order). Returns the messages: [{"message": 500 / 0x1f6, "units": [ids], "cost": [gold, metal, crystal, stone]}].
## One selected unit: message 500 when the stock covers one price (the unit's type is not checked). Several: the units of
## the source type that are not being removed, while the stock covers the running total in every lane, 16 per message.
static func order(units: Array, target: String, cost: Array, stock: Array) -> Array:
	if units.is_empty(): return []
	var source: String = SOURCE.get(target, "AUIX")
	if units.size() < 2:
		if bool(units[0].get("removed", false)): return []
		for lane in 4:
			if int(stock[lane]) < int(cost[lane]): return []
		return [{"message": 500, "units": [units[0].id], "cost": cost.duplicate()}]
	var batches: Array = [[], []]
	var taken := 0
	var batch := 0
	for u in units:
		if bool(u.get("removed", false)) or String(u.type) != source: continue
		if batches[batch].size() >= GROUP_LIMIT:
			if batch == 1 or units.size() <= GROUP_LIMIT: break
			batch = 1
		var n := taken + 1
		var ok := true
		for lane in 4:
			if int(stock[lane]) < int(cost[lane]) * n: ok = false
		if not ok: break
		batches[batch].append(u.id)
		taken += 1
	var out: Array = []
	for ids in batches:
		if ids.is_empty(): continue
		var total := [0, 0, 0, 0]
		for lane in 4: total[lane] = int(cost[lane]) * ids.size()
		out.append({"message": 0x1f6, "units": ids, "cost": total})
	return out

## 0x557d90(player, type, general, typed, 0) (R-1, Emulated: tests/rank_fixtures.json "starting"): the starting experience of a
## new unit while the owner's hero lives (`block`, the hero block of HeroEffects; {} without a living hero). `general`: derived
## statistic 10, "experience" item powers (type 3) and the hero's effect 3 (`aura`, Telepathy); `typed`: the hero skills tied
## to unit types (0x556b50 / 0x556ea0). `status` is the type's Army.cfg STATUS (0x585970). The fifth argument's PGAX level x 20
## needs no living hero: Combat.starting_xp.
const TYPE_SKILLS := [[0x62, ["AGSL"]], [100, ["AARI"]], [0x5a, ["ADOX"]], [0x5d, ["AUIX"]], [0x55, ["AUCX"]],
	[0x53, ["ABIX", "ABCX", "ABEX"]], [0x56, ["AKJX"]], [0x58, ["AHFX", "AHDX", "AHEX"]], [0x59, ["AWJX", "AWKX"]],
	[0x5b, ["AAEF", "AAEE", "AAEW", "AAEA"]], [0x5c, ["AHGR", "AHGW", "AHGB"]], [0x61, ["AGSP", "AGGZ", "AGFL", "AAEY"]],
	[99, ["AAIX", "AAJX", "AAGX"]]]
const STATUS_SKILLS := [[0x57, 0x2], [0x54, 0x800], [0x5e, 0x800000], [0x60, 0x1000]]

static func starting_xp(block: Dictionary, type_id: String, status: int, general: bool = true, typed: bool = true, aura: int = 0) -> int:
	if block.is_empty() or not bool(block.get("hero", false)) or HeroEffects.s16(int(block.get("hp", 0))) < 1: return 0
	var xp := 0
	if general: xp += HeroRules.derived(block.stats, 10, 1) + HeroEffects.item_stat(block, 3) + aura
	if typed:
		for entry in STATUS_SKILLS:
			if (status & int(entry[1])) != 0: xp += HeroEffects.skill_effect(block, int(entry[0]))
		for entry in TYPE_SKILLS:
			if type_id in entry[1]: xp += HeroEffects.skill_effect(block, int(entry[0]))
	return HeroEffects.s16(xp)

## 0x4a8ff0 -> 0x4a49e0: the experience of the morphed unit (Open 1, Read).
static func morphed_xp(old_xp: int, start_xp: int) -> int:
	var out := 0
	if old_xp - start_xp > 0: out += old_xp - start_xp
	if start_xp > 0: out += start_xp
	return out
