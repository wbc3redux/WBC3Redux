extends RefCounted
## Treasure piles on the map (IMAP map objects with four item slots, record +0x3c; milestone 11-hero, Read).
## * 0x580d00 (a quest reward item, 0x43d560): the item goes to the pile under the hero when it has fewer than four items;
##   a missing pile is created there; a full pile passes the item to the neighbours in the order (x+1, y), (x-1, y),
##   (x, y+1), (x, y-1), (x+1, y+1), (x-1, y+1), (x+1, y-1), (x-1, y-1) (a free neighbour gets a new pile, a pile with
##   room takes it); after all eight a new pile replaces the one under the hero (messages 0x191 create / 0x193 add).
## * 0x528300 -> message 0x198 -> 0x4a87f0: a dying hero's four backpack items, or one random treasure item
##   (0x43e340(1, 1)) for a unit carrying status 0x1a (the lair boss, 0x404cf0 -> 0x4a49e0), are dropped at the death
##   cell. Provisional: the rebuild drops them one by one with the 0x580d00 rule; 0x4a87f0's own overflow placement is
##   longer and not ported.
## * Taking items (messages 0x192 / 0x193 from the hero panel's "Ground" list, string [0870]): Provisional, the hero
##   must stand on or next to the pile (the panel's reach is not traced).

const MAX_ITEMS := 4
const NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1),
	Vector2i(1, -1), Vector2i(-1, -1)]

signal changed(pile_id: int)

var piles: Dictionary = {}       # id -> {"id", "cell", "items": [item ids]}
var by_cell: Dictionary = {}     # cell -> pile id
var next_id := 1
var map_size := Vector2i(128, 128)
var log: Array = []

func _create(cell: Vector2i, item_id: int) -> int:
	if by_cell.has(cell): piles.erase(by_cell[cell])
	var pile := {"id": next_id, "cell": cell, "items": [item_id]}
	piles[next_id] = pile
	by_cell[cell] = next_id
	next_id += 1
	changed.emit(pile.id)
	return pile.id

func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y

## 0x580d00 for one item at `cell`; returns the pile id.
func drop(item_id: int, cell: Vector2i, source: String = "") -> int:
	if item_id <= 0: return -1
	log.append({"item": item_id, "cell": cell, "source": source})
	if not by_cell.has(cell): return _create(cell, item_id)
	var own: Dictionary = piles[by_cell[cell]]
	if own.items.size() < MAX_ITEMS:
		own.items.append(item_id)
		changed.emit(own.id)
		return own.id
	for step in NEIGHBOURS:
		var next: Vector2i = cell + step
		if not _inside(next): continue
		if not by_cell.has(next): return _create(next, item_id)
		var pile: Dictionary = piles[by_cell[next]]
		if pile.items.size() < MAX_ITEMS:
			pile.items.append(item_id)
			changed.emit(pile.id)
			return pile.id
	return _create(cell, item_id)

func drop_all(items: Array, cell: Vector2i, source: String = ""):
	for id in items:
		if int(id) > 0: drop(int(id), cell, source)

## Piles the hero at `cell` can reach (its own cell and the eight neighbours).
func reachable(cell: Vector2i) -> Array:
	var found: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if by_cell.has(c): found.append(piles[by_cell[c]])
	return found

## Removes item `index` of pile `pile_id`; returns the item id (0 when absent). An emptied pile disappears.
func take(pile_id: int, index: int) -> int:
	var pile = piles.get(pile_id)
	if pile == null or index < 0 or index >= pile.items.size(): return 0
	var id: int = pile.items[index]
	pile.items.remove_at(index)
	if pile.items.is_empty():
		piles.erase(pile_id)
		by_cell.erase(pile.cell)
	changed.emit(pile_id)
	return id

## 0x560a00 (the inventory dialog closing): the pile's items become `items` (compacted, at most four); an emptied pile
## disappears.
func set_items(pile_id: int, items: Array):
	var pile = piles.get(pile_id)
	if pile == null: return
	pile.items = items.slice(0, MAX_ITEMS)
	if pile.items.is_empty():
		piles.erase(pile_id)
		by_cell.erase(pile.cell)
	changed.emit(pile_id)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd).
func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self)

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state)
