extends RefCounted
## S-2 (SKIRMISH_RESEARCH.md "S-2"; Read): shops, the map's buildings with the Building.cfg shop flag (+0x7f; BSFG, "Shop",
## is the only one; BMSH is the Shrine, a quest site like the Mausoleum, simulation/encounters.gd). The original's shop list
## is built once from the neutral player's object list (0x408300 -> 0x4083c0), newest first.
## * Stock 0x408450: two items of the rarity draw 0x402f90 and a price percentage per player, 100 + 1d21 - 11.
## * Attacking a shop (0x52bd10 -> 0x408360): +50 on the attacker's percentage (at most 300) in every list entry up to and
##   including the shop hit.
## * Dialog 12 (0x56dc00, EMDK): Healing Potion (id 0xffff), Mana Potion (id 0xfffe) and the two items.
## * Price 0x56e860: potions base 500, items value x 10 (item +0x27c), times the player's percentage / 100, at most 3000, the
##   same amount of each of the four resources.
## * Buying 0x56e420: every resource must cover it and a potion needs 8 or fewer of its kind; an item goes to the first free
##   backpack slot 7..10, else to the ground at the hero, and leaves the stock; message 0x1fe pays; Bing.wav.

const ComputerHero = preload("res://simulation/computer_hero.gd")
const HEALING_POTION := -1           # 0x56dc00: +0x144 = 0xffff
const MANA_POTION := -2              # +0x146 = 0xfffe
const POTION_PRICE := 500
const PRICE_CAP := 3000
const POTION_LIMIT := 8              # 0x56e420: refused when the count is above 8
const OFFENCE := 50                  # 0x408360
const OFFENCE_CAP := 300
const PLAYERS := 7

## 0x408450 for a shop after `existing` others: the rolls are the original's order (match generator, roll(1, 100, 0) etc.).
static func stock(rng, existing: int, cell: Vector2i) -> Dictionary:
	var minor: bool = rng.roll(1, 100, 0) < 0x50
	var lesser_roll: int = rng.roll(1, 100, 0)
	var greater_roll: int = rng.roll(1, 100, 0)
	var artifact := false
	if existing < 5: artifact = rng.roll(1, 100, 0) < 5
	var with_set := false
	if existing < 3: with_set = rng.roll(1, 100, 0) < 2
	if lesser_roll >= 0x50 and greater_roll >= 0x28 and not artifact and not with_set: minor = true
	var allowed := [minor, lesser_roll < 0x50, greater_roll < 0x28, artifact, with_set]
	var items := [ComputerHero.random_item(rng, allowed), ComputerHero.random_item(rng, allowed)]
	var percent: Array = []
	for i in PLAYERS: percent.append(100 + int(rng.roll(1, 21, -11)))
	return {"items": items, "percent": percent, "cell": cell}

## The four goods of dialog 12; 0 is an empty place.
static func goods(shop: Dictionary) -> Array:
	return [HEALING_POTION, MANA_POTION, int(shop.items[0]), int(shop.items[1])]

## 0x56e860: `value` is the item's value (ignored for potions).
static func price(shop: Dictionary, good: int, player: int, value: int) -> int:
	var base := POTION_PRICE if good < 0 else (0 if good == 0 else value * 10)
	return mini(int(shop.percent[player]) * base / 100, PRICE_CAP)

## 0x408360: the list runs newest first and stops at the shop hit.
static func offended(shops: Dictionary, id: int, player: int):
	if player < 0 or player >= PLAYERS or not shops.has(id): return
	var ids: Array = shops.keys()
	ids.reverse()
	for s in ids:
		shops[s].percent[player] = mini(int(shops[s].percent[player]) + OFFENCE, OFFENCE_CAP)
		if s == id: return
