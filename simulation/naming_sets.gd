extends RefCounted
## The naming sets (NamingSets/*.nam, imported into encounters.json "naming_sets"; playtest 2026-11-11). Read from the
## decompile:
## * 0x434e90(index): the file of table 0x6085d8[index] (a remap 0x608618 applies while 0xa27d7a is set: Open, taken as
##   clear); no name from the file gives "Sirian".
## * 0x435060(file): from the line "[RULES]" on, up to ten rule lines "%d %s %s %s %s" (lines of 4 characters or fewer
##   skipped, a line starting with '[' ends the list; end of file before that gives no name). A 1d100 roll picks the first
##   rule whose number is above the roll, else rule 0. For each of the rule's (up to four) section names: the lines after
##   that section's header are counted up to the next '[' (empty lines not counted, 0x434f60); a 1d(count) roll r takes
##   the line at zero-based position r (0x434fb0), so the section's first line is never taken and r = count adds nothing;
##   the parts are joined as they are (strcat). Rolls through 0x458e70 (the match generator).
const Assets = preload("res://core/asset_store.gd")
const FALLBACK := "Sirian"

static var _sets: Array = []

static func sets() -> Array:
	if _sets.is_empty() and Assets.exists("encounters.json"):
		var data = Assets.json("encounters.json")
		if data is Dictionary: _sets = data.get("naming_sets", [])
	return _sets

## 0x434e90 for set `index` with the match generator `rng` (combat_rng.gd).
static func name_for(index: int, rng) -> String:
	var all := sets()
	if index < 0 or index >= all.size(): return FALLBACK
	var made = generate(all[index].lines, rng)
	return made if made != null else FALLBACK

## 0x435060 over a file's lines (no line ends). Returns null where the original returns no name.
static func generate(lines: Array, rng):
	var at := _section(lines, "[RULES]")
	if at < 0: return null
	var rules: Array = []
	var i := at
	while rules.size() < 10:
		if i >= lines.size(): return null                    # end of file inside the rules: no name
		var line := String(lines[i])
		i += 1
		if line.length() <= 4: continue
		if line.begins_with("["): break
		var parts := line.split(" ", false)
		if parts.size() < 2 or not parts[0].is_valid_int(): continue
		var names: Array = []
		for k in range(1, mini(parts.size(), 5)): names.append(parts[k])
		rules.append({"limit": int(parts[0]), "sections": names})
	if rules.is_empty(): return null
	var roll: int = rng.roll(1, 100)
	var chosen := 0
	for k in rules.size():
		if roll < int(rules[k].limit):
			chosen = k
			break
	var out := ""
	for section in rules[chosen].sections:
		var start := _section(lines, String(section))
		if start < 0: return null
		var entries: Array = []
		for k in range(start, lines.size()):
			var entry := String(lines[k])
			if entry.begins_with("["): break
			if entry != "": entries.append(entry)
		if entries.is_empty(): continue
		var pick: int = rng.roll(1, entries.size())
		if pick < entries.size(): out += String(entries[pick])
	return out

## 0x434ed0: the line after the first line equal to `header`, or -1.
static func _section(lines: Array, header: String) -> int:
	for k in lines.size():
		if String(lines[k]) == header: return k + 1
	return -1
