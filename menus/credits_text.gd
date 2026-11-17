extends RefCounted
## The credits (R-1, Read: 0x4069e0 opens PNL_WBC3CREDITS at layer 50000, 0x406b10 reads English\Credits.xml, the panel's
## callback 0x406a50 ticks and 0x406e90 draws IM_WBC3CREDITS_TEXT). Lines appear one by one in two columns; a full page waits
## and the next page starts behind it; after the last line the list starts again.
##
## The rebuild reads Credits.xml from the installation folder above the project: the file is not part of the import (the text
## stays the game's own, unchanged). Provisional: the tick is the screens' 50 ms timer (the panel timer's period is not traced).

const COLUMN_X := [270, 535]       # 0x5fb73c, 0x5fb73e
const TOP := 150                   # 0x5fb740
const LINE_HEIGHT := 20            # 0x5fb742
const ROWS := 15                   # 0x406ee4: a heading on row 15, or any line past it, starts the next column
const HEADING_GAP := 5             # 0x406f3b: a heading right under a heading
const SUB_TICKS := 8               # 0x406a7e
const PAGE_WAIT := 0x18            # 0x406fb8
const HEADING_FONT := 0x15
const LINE_FONT := 0x1f
const TICK_MS := 50

## Credits.xml: [{text, heading, blank}].
static func read_lines(path: String) -> Array:
	var out: Array = []
	var parser := XMLParser.new()
	if parser.open(path) != OK: return out
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT or parser.get_node_name() != "Line": continue
		var kind: String = parser.get_named_attribute_value_safe("type")
		var text := ""
		if kind != "blank" and not parser.is_empty():
			if parser.read() == OK and parser.get_node_type() == XMLParser.NODE_TEXT: text = parser.get_node_data().strip_edges()
		out.append({"text": text, "heading": kind == "heading", "blank": kind == "blank"})
	return out

## The installation's Credits.xml: the nearest folder above the project (which may be a git worktree) that holds it.
static func installed_path() -> String:
	var dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	while dir.length() > 3:
		var candidate := dir.path_join("English").path_join("Credits.xml")
		if FileAccess.file_exists(candidate): return candidate
		dir = dir.get_base_dir()
	return ""

static func new_state() -> Dictionary:
	return {"first": 0, "shown": 0, "sub": 0, "wait": 0}

## 0x406a50 message 9.
static func tick(state: Dictionary):
	if int(state.wait) > 0:
		state.wait = int(state.wait) - 1
		return
	state.sub = int(state.sub) + 1
	if int(state.sub) == SUB_TICKS:
		state.shown = int(state.shown) + 1
		state.sub = 0

## 0x406e90: the lines to draw now, [{text, font, x, y}]; `state` moves to the next page or back to the start as it does.
static func lay_out(lines: Array, state: Dictionary) -> Array:
	var out: Array = []
	var i := int(state.first)
	var drawn := 0
	var row := 0
	var column := 0
	var previous = null
	while i < lines.size() and drawn <= int(state.shown):
		var line: Dictionary = lines[i]
		var new_column: bool = row > ROWS or (row == ROWS and bool(line.heading))
		if new_column:
			if column != 0:
				state.first = int(state.first) + drawn
				state.shown = 0
				state.wait = PAGE_WAIT
				break
			column = 1
			row = 0
		if row == 0 and bool(line.blank):
			i += 1
			if i >= lines.size(): break
			line = lines[i]
		var y: int = TOP + LINE_HEIGHT * row
		if bool(line.heading):
			if previous != null and bool(previous.heading): y += HEADING_GAP
			out.append({"text": String(line.text), "font": HEADING_FONT, "x": COLUMN_X[column], "y": y})
		else:
			out.append({"text": String(line.text), "font": LINE_FONT, "x": COLUMN_X[column], "y": y})
		row += 1
		previous = line
		drawn += 1
		i += 1
	if i >= lines.size():
		state.wait = PAGE_WAIT
		state.first = 0
		state.shown = 0
	return out
