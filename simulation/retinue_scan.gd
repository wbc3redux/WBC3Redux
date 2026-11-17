extends RefCounted
## The end-of-battle retinue scan 0x43f3e0 (Read from the decompile; called once per match for the local player before the
## results, 0x43f3e0(0x709100, 0xa23ca8)). Pure: the scene hands in its units, the hero's retinue and graveyard; the result
## is the new retinue and graveyard plus up to eight recruit candidates for the retinue screen (0x440b40 / 0x4427d0 /
## 0x443890, hero_advance.gd).
##
## * Units (the player's unit list; the rebuild walks the fighters by id: the list order is Open):
##   - a living retinue member (+0x1c8 = 1, slot +0x1ca >= 0, the slot's death byte +1 clear) writes its rank and
##     experience back to its slot (0x40a850 restores the type's base stats, 0x40daa0 re-applies one step per rank);
##   - any other living unit that may join (+0xb4 hero clear, not a retinue member, +0xc2 set) is a candidate when it is
##     not AAEY, its rank (+0x3c) is above 1, its Combat (+0x92) above 7, STATUS bit 14 (+0x1c0 & 0x4000) clear, and the
##     type's ARM byte +4 is set (1 for all 199 types, Data). Such a candidate that is a general (+0x1cc) blocks the
##     random offer below. Up to eight are kept; with eight, a type held twice or more (the most common, first found)
##     loses its weakest (rank x 5 + Combat) to the newcomer, else the weakest of all is replaced only when the newcomer's
##     rank x 3 + Combat is higher.
## * Unless a general qualified (and not in the campaign): a general for hire, table 0x609330 at race x 10 + 1d10 (the
##   race's first entry is never drawn and a 10 draws the next race's first; the Plaguelords' 10 reads past the table, so
##   it offers nothing here: Deliberate guard), rank 0 with 1 experience, into a free place or over the candidate with
##   the lowest Combat.
## * Each candidate without a name gets one from the naming set of its kind (0x434e90; codes, then STATUS bits).
## * Slots: a dead member goes to the graveyard (a free grave, else over the oldest), battles + 1, the battle text, age 0,
##   and the slot is cleared; a living member counts one more battle. After each slot the strongest grave
##   ((Combat + rank x 2) x 5 + experience) moves to the front; at the end every grave ages by one.
## Open: +0x1cd (clears +0xc2 at creation), STATUS bit 14's meaning; a retinue member removed without dying (advanced,
## converted, in a mine) keeps its record unchanged.

const NamingSets = preload("res://simulation/naming_sets.gd")

const SLOTS := 8
const GRAVES := 10
## 0x519ae0: these types never join (+0xc2 cleared at creation).
const NEVER_JOIN := ["AADR", "AADG", "AADB", "AADC", "AADW", "AADU"]
## 0x609330 (Data): the generals for hire, ten per race.
const OFFERS := [
	"AHGX", "AHGX", "AHGW", "AHGW", "AHGX", "AAAR", "ADGX", "AEGX", "ABGX", "AWGX",
	"ADGX", "ADGX", "ADGX", "AAGX", "AAEE", "ABGX", "ABGX", "AHGR", "AHGW", "AOGX",
	"AUGX", "AUGX", "AUGX", "AUGX", "AKGX", "AADE", "AKGX", "AHGB", "ABGX", "AOGX",
	"ABGX", "ABGX", "ABGX", "AMGX", "AMGX", "AOGX", "AAEF", "ADGX", "AAEA", "AHGW",
	"AMGX", "AMGX", "AMGX", "AOGX", "AOGX", "AADE", "AAEF", "ABGX", "ABGX", "ADGX",
	"AOGX", "AOGX", "AOGX", "AOGX", "ABGX", "AAEE", "AMGX", "AKGX", "AUGX", "AADE",
	"AEGX", "AEGX", "AEGX", "AAEA", "AAAR", "AWGX", "AHGW", "AHGW", "AHGR", "ABGX",
	"AWGX", "AWGX", "AWGX", "AFGX", "AEGX", "AEGX", "AAEA", "AHGW", "ABGX", "AHGR",
	"AKGX", "AKGX", "AKGX", "AKGX", "AADE", "AUGX", "AUGX", "AOGX", "ABGX", "AHGB",
	"AFGX", "AFGX", "AFGX", "AWGX", "AWGX", "AAEA", "AAEF", "AEGX", "AWKX", "AHGW",
	"AAGX", "AAGX", "AAGX", "ABGX", "AAEE", "AAEE", "AMGX", "AOGX", "AADE", "AHGB",
	"AVGX", "AVGX", "AADE", "AADE", "AADE", "AADE", "AHGB", "AAEF", "AKGX", "AUGX",
	"AHGR", "AHGW", "AHGB", "AHGR", "AHGW", "AHGB", "ADGX", "AEGX", "ABGX", "AHGW",
	"ALGX", "ALGX", "ALGX", "ALGX", "AGGX", "AAEA", "AAEF", "AAEE", "ABGX", "AHGR",
	"ARGX", "ARGX", "ARGX", "ARGX", "AGGX", "AAEF", "AAEF", "AADE", "AHGB", "AUGX",
	"AGGX", "AGGX", "AGGX", "AGGX", "AUGX", "AKGX", "AAEF", "AVGX", "ALGX", "AHGB"]

## 0x43f3e0's candidate test for one unit (u: {"type", "rank", "combat", "flags"}).
static func qualifies(u: Dictionary) -> bool:
	return String(u.type) != "AAEY" and int(u.rank) > 1 and int(u.combat) > 7 and (int(u.flags) & 0x4000) == 0

## The naming set 0x43f3e0 picks for a candidate of `type` with STATUS `flags`; -1 = the type's own name (0x58a230).
static func naming_set(type: String, flags: int) -> int:
	if type in ["AWGX", "AEXX", "AASP", "AFJX"]: return 0xf
	if type in ["AAHA", "AVIX", "AFGX"]: return 0xb
	if type in ["AAIM", "AADE"]: return 1
	if type in ["AHFX", "AHEX", "AHDX"]: return 2
	if flags & 0x100: return 1
	if flags & 0x38: return 6
	if flags & 4: return 1
	if flags & 2: return 8
	if flags & 0xc0: return 0xc
	if flags & 1: return 4
	if flags & 0x4000: return -1
	return 0

static func _block(u: Dictionary) -> Dictionary:
	return {"original_type_id": String(u.type), "medal_level": clampi(int(u.rank), 0, 19), "xp": clampi(int(u.xp), 0, 20000),
		"name": String(u.get("name", "")), "permanent_state": {"combat": int(u.combat)}}

static func _combat(block: Dictionary) -> int:
	return int(block.get("permanent_state", {}).get("combat", 0))

## Adds a qualifying unit to the candidates as 0x43f3e0 does (`types` parallels `out`).
static func _offer(out: Array, u: Dictionary):
	var block := _block(u)
	if out.size() < SLOTS:
		out.append(block)
		return
	var counts: Array = []
	for i in out.size():
		var n := 0
		for j in out.size():
			if String(out[j].original_type_id) == String(out[i].original_type_id): n += 1
		counts.append(n)
	var common := -1
	var best := -1
	for i in counts.size():
		if int(counts[i]) > best and int(counts[i]) > 1:
			best = int(counts[i])
			common = i
	var weakest := -1
	var low := 1000
	for j in out.size():
		if common >= 0 and String(out[j].original_type_id) != String(out[common].original_type_id): continue
		var score: int = int(out[j].medal_level) * 5 + _combat(out[j])
		if score < low:
			low = score
			weakest = j
	if weakest < 0: return
	if common < 0 and int(u.rank) * 3 + int(u.combat) <= low: return
	out[weakest] = block

## scan(units, retinue, graveyard, context) -> {"retinue", "graveyard", "candidates"}.
## units: the player's units in list order, {"id", "type", "alive", "hero", "retinue_id" ("" = none), "may_join", "rank",
## "xp", "combat", "flags", "general", "name"}. retinue / graveyard: the hero's records (not changed). context: {"race",
## "campaign", "dead" (retinue ids that died), "text" (the battle text), "rng" (roll(count, sides)), "type_stats"
## (Callable code -> {"combat", "flags"}), "display_name" (Callable code -> String)}.
static func scan(units: Array, retinue: Array, graveyard: Array, context: Dictionary) -> Dictionary:
	var slots: Array = retinue.duplicate(true)
	var graves: Array = graveyard.duplicate(true)
	var dead: Array = context.get("dead", [])
	var candidates: Array = []
	var general_seen := false
	for u in units:
		if not bool(u.alive): continue
		var member := String(u.get("retinue_id", ""))
		if member != "" and not dead.has(member):
			for i in slots.size():
				if String(slots[i].id) != member: continue
				var block := _block(u)
				slots[i]["medal_level"] = block.medal_level
				slots[i]["xp"] = block.xp
				var state: Dictionary = slots[i].get("permanent_state", {}).duplicate()
				state["combat"] = int(u.combat)
				slots[i]["permanent_state"] = state
		if bool(u.hero) or member != "" or not bool(u.may_join): continue
		if not qualifies(u): continue
		if bool(u.get("general", false)): general_seen = true
		_offer(candidates, u)
	var rng = context.get("rng")
	if not bool(context.get("campaign", false)) and not general_seen and rng != null:
		var roll: int = rng.roll(1, 10)
		var at: int = int(context.get("race", 0)) * 10 + roll
		if at < OFFERS.size():
			var code: String = OFFERS[at]
			var stats: Dictionary = context.type_stats.call(code) if context.has("type_stats") else {"combat": 0}
			var block := {"original_type_id": code, "medal_level": 0, "xp": 1, "name": "", "permanent_state": {"combat": int(stats.get("combat", 0))}}
			var place := candidates.size()
			if candidates.size() >= SLOTS:
				var low := 1000
				place = -1
				for j in candidates.size():
					if _combat(candidates[j]) < low:
						low = _combat(candidates[j])
						place = j
			if place == candidates.size(): candidates.append(block)
			elif place >= 0: candidates[place] = block
	for c in candidates:
		if String(c.name) != "": continue
		var code := String(c.original_type_id)
		var flags: int = int(context.type_stats.call(code).get("flags", 0)) if context.has("type_stats") else 0
		var which := naming_set(code, flags)
		if which < 0:
			c["name"] = String(context.display_name.call(code)) if context.has("display_name") else code
		elif rng != null:
			c["name"] = NamingSets.name_for(which, rng)
	var kept: Array = []
	for slot in slots:
		if dead.has(String(slot.id)):
			var grave := {"original_type_id": String(slot.original_type_id), "xp": int(slot.xp), "medal_level": int(slot.medal_level),
				"battles": int(slot.get("battles", 0)) + 1, "text": String(context.get("text", "")), "age": 0,
				"name": String(slot.get("name", "")), "permanent_state": slot.get("permanent_state", {}).duplicate(true)}
			if graves.size() < GRAVES:
				graves.append(grave)
			else:
				var oldest := -1
				var age := -1
				for g in graves.size():
					if int(graves[g].get("age", 0)) > age:
						age = int(graves[g].get("age", 0))
						oldest = g
				graves[oldest] = grave
		else:
			slot["battles"] = int(slot.get("battles", 0)) + 1
			kept.append(slot)
		_strongest_first(graves)
	for g in graves: g["age"] = int(g.get("age", 0)) + 1
	return {"retinue": kept, "graveyard": graves, "candidates": candidates}

static func _strongest_first(graves: Array):
	var best := -1
	var score := -1
	for g in graves.size():
		var s: int = (_combat(graves[g]) + int(graves[g].medal_level) * 2) * 5 + int(graves[g].xp)
		if s > score:
			score = s
			best = g
	if best > 0:
		var first = graves[0]
		graves[0] = graves[best]
		graves[best] = first
