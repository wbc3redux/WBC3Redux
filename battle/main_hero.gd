extends RefCounted
## main.gd's hero side (R-1 split of main.gd, no behaviour change): the encounters fixture and quests, the hero's
## items and the inventory sheet, treasure sprites, quest sites and shops. The state stays on the scene (main.gd);
## `main` is the scene.

const MainScript = preload("res://battle/main.gd")
const Navigation = preload("res://battle/navigation.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const ArtData = preload("res://core/art_data.gd")
const SkirmishShops = preload("res://simulation/skirmish_shops.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

# ------------------------------------------------------------------ milestone 9: Desert Sands encounters

# Test harness (button "Encounters fixture"): the map's own neutral buildings (towers, Gnoll Lair, Mausoleum) and its
# ten animals as the neutral player 6, plus a hero and small Knights groups placed near each encounter. Fog is off so
# the encounters can be watched; this is not an original match start.
func spawn_encounters_fixture():
	main.reset_fixture()
	main.clear_units()
	for id in main.building_nodes.keys(): main.building_nodes[id].queue_free()
	main.building_nodes.clear()
	main.setup_combat()
	main.visibility.fog = false
	main.visibility.shroud = false
	for entry in main.encounters.adopt_map_buildings(main.game_ms()):
		if entry.code == "BZMA": main.mausoleum_id = entry.id
		if entry.code == "BLGL": main.lair_id = entry.id
	main.encounters.spawn_animals()
	var hero = main.add_unit("AHHX", main.navigator.free_cell_near(Vector2i(27, 105)), 0)
	for i in 2: main.add_unit("AHKX", main.navigator.free_cell_near(Vector2i(28, 107 + i)), 0)
	# Groups: beside player 0's own Dwarven Towers (west, not attacked), 15 rows south of the Gnoll Lair, and beside
	# player 1's Swarm Towers (east, inside their 12-cell reach, attacked). Tower owners come from BLDH +0x64 (9-fix).
	for spot in [Vector2i(30, 64), Vector2i(58, 52), Vector2i(94, 64)]:
		for i in 3: main.add_unit("AHKX", main.navigator.free_cell_near(spot + Vector2i(0, i * 2 - 2)), 0)
		main.add_unit("AHMX", main.navigator.free_cell_near(spot + Vector2i(2, 0)), 0)
	for unit in main.units: unit.selected = unit == hero
	main.apply_fog_to_nodes()
	main.refresh_fog_overlay()
	main.camera.position = hero.position
	main.camera.zoom = Vector2.ONE
	main.last_message = "Encounters fixture: hero by the Mausoleum (south-west); groups by your own Dwarven Towers (west), the Gnoll Lair, and the enemy's Swarm Towers (east); animals roam. Fog is off."

func hero_near_mausoleum() -> bool:
	if main.hero_unit_id < 0 or main.mausoleum_id < 0: return false
	var here: Vector2i = main.units[main.hero_unit_id].cell
	for cell in main.navigator.building_cells:
		if main.navigator.building_cells[cell] == main.mausoleum_id and Navigation.chebyshev(cell, here) <= 2: return true
	return false

## Harness for 0x43d180: the original runs it when the hero reaches the building; here the hero must stand within
## two cells of the Mausoleum and the button stands in for the arrival.
func quest_visit() -> Dictionary:
	if main.encounters == null or main.mausoleum_id < 0:
		main.last_message = "Start the Encounters fixture first."
		return {}
	if not hero_near_mausoleum():
		main.last_message = "Move the hero next to the Mausoleum first."
		return {}
	var v: Dictionary = main.encounters.visit(main.local_player, main.mausoleum_id)
	var r = v.get("record")
	match v.mode:
		"none": main.last_message = "The Mausoleum has nothing to offer now."
		"busy": main.last_message = "The hero already has another quest."
		"unsupported": main.last_message = "Quest %d '%s' (type %s) is not supported by this rebuild yet (Open)." % [int(r.index), r.get("name", ""), r.type_name]
		"offer": main.last_message = "%s: %s" % [r.get("name", ""), r.get("newq", "")]
		"instant": main.last_message = "%s: %s" % [r.get("name", ""), r.get("inst", r.get("newq", ""))]
		"continue": main.last_message = "%s: %s" % [r.get("name", ""), r.get("cont", "")]
		"complete": main.last_message = "%s: ready to complete." % r.get("name", "")
	return v

func quest_accept():
	var v := quest_visit()
	if v.is_empty() or not (v.mode in ["offer", "instant"]): return
	if main.encounters.accept(main.local_player, main.mausoleum_id): main.last_message = "Accepted: %s. %s" % [v.record.get("name", ""), v.record.get("rept", "")]

func quest_complete():
	var v := quest_visit()
	if v.is_empty(): return
	if v.mode == "instant": main.encounters.accept(main.local_player, main.mausoleum_id)
	elif v.mode != "complete": return
	var reward: Dictionary = main.encounters.complete(main.local_player, main.mausoleum_id, main.hero_match, main.units[main.hero_unit_id].cell)
	if reward.is_empty(): return
	if main.skirmish != null: main.skirmish.note_quest(main.local_player)
	main.last_message ="%s Reward: resources %s, %d units, item %d, hero +%d XP." % [v.record.get("cmpl", "Done."), reward.resources, reward.units.size(), int(reward.item), int(reward.xp)]

func lair_wave_test():
	if main.encounters == null or main.encounters.lairs.is_empty(): return
	var entry: Dictionary = main.encounters.lairs[0]
	if entry.active: main.encounters._wave(entry, main.game_ms(), true)
	main.last_message = "Lair wave forced (test): the Gnolls defend the lair (Defensive script)."

func destroy_lair_test():
	if main.encounters == null or main.lair_id < 0 or main.production.building(main.lair_id) == null: return
	var b = main.production.building(main.lair_id)
	main.combat.apply_damage("building", main.lair_id, b.hit_points + 1, main.hero_unit_id)
	main.last_message = "Gnoll Lair destroyed (test, credited to the hero): the boss appears."

func encounter_text() -> String:
	if main.encounters == null or (main.encounters.lairs.is_empty() and main.encounters.givers.is_empty()): return ""
	var text := ""
	for entry in main.encounters.lairs:
		if entry.active: text += " · lair wave in %ds (%d so far)" % [maxi(0, (int(entry.next_ms) - main.game_ms()) / 1000), int(entry.waves)]
		else: text += " · lair destroyed"
	var q = main.encounters.quests.get(main.local_player)
	if q != null: text += " · quest '%s' %d/%d" % [q.record.get("name", ""), int(q.progress), int(q.record.count)]
	for id in main.combat.towers:
		var b = main.production.building(id)
		if b != null and main.combat.towers[id].target_kind != "": text += " · %s %d hp shooting" % [b.original_type_id, b.hit_points]
	if main.hero_match != null and not main.hero_match.match_items.is_empty(): text += " · backpack %s" % [main.hero_match.match_items.map(func(i): return int(i.item))]
	return text

func toggle_hero_items():
	if main.inventory.is_empty(): open_inventory(-1)
	else: close_inventory()

## 0x55e0e0(pile): the ground row holds the pile's four items (none without a pile).
func open_inventory(pile_id: int) -> bool:
	if main.hero_match == null or main.hero_match.profile == null: return false
	if not main.inventory.is_empty(): close_inventory()
	var ground: Array = [{}, {}, {}, {}]
	var pile = main.treasures.piles.get(pile_id) if main.treasures != null and pile_id >= 0 else null
	if pile != null:
		for k in mini(4, pile.items.size()): ground[k] = {"item": int(pile.items[k]), "source": "ground"}
	main.inventory = {"pile": pile_id if pile != null else -1, "ground": ground, "selected": -1, "previous": -1, "tick": 100}
	main.inventory_quiet_tick = 0
	if main.hud != null: main.hud.open_dialog("inventory")
	return true

func close_inventory():
	if main.inventory.is_empty(): return
	_inventory_commit_ground()
	main.inventory = {}
	main.inventory_quiet_tick = 0
	if main.hud != null and main.hud.dialog == "inventory": main.hud.close_dialog()

## Slot k's item dictionary ({} when empty): 0..10 the hero's, 11..14 the ground row.
func inventory_slot(k: int) -> Dictionary:
	if k >= 11 and k < 15: return main.inventory.ground[k - 11] if not main.inventory.is_empty() else {}
	if k < 0 or k > 10 or main.hero_match == null or main.hero_match.profile == null: return {}
	return main.hero_match.profile.data.equipment[k] if k < 7 else main.hero_match.profile.data.backpack[k - 7]

func _inventory_put(k: int, value: Dictionary):
	if k >= 11: main.inventory.ground[k - 11] = value
	else: main.hero_match.set_slot(k, value)

## 0x55ec20 for a slot dictionary: an empty slot fits anywhere; the ground and the backpack take any item.
func _inventory_fits(value: Dictionary, k: int) -> bool:
	return value.is_empty() or k > 6 or HeroEffects.equip_allowed(int(value.item), k)

## 0x55ecc0 for a release on slot k (-1 outside every slot). Returns what happened: "drink", "moved", "swapped",
## "selected" or "".
func inventory_release(k: int) -> String:
	if main.inventory.is_empty() or main.hero_match == null: return ""
	main.inventory_quiet_tick = 0
	if k == 15 or k == 16:
		var hs = main.combat.spells.hero_spells if main.combat != null and main.combat.spells != null else null
		var drank: bool = hs != null and (hs.drink_potion(main.local_player) if k == 15 else hs.drink_mana_potion(main.local_player))
		if drank: close_inventory()
		return "drink" if drank else ""
	if k < 0 or k > 14: return ""
	var selected: int = int(main.inventory.selected)
	var result := ""
	if int(main.inventory.tick) < MainScript.INVENTORY_DOUBLE_TICKS and k == selected:
		var value := inventory_slot(k)
		for j in 11:
			if inventory_slot(j).is_empty() and _inventory_fits(value, j):
				_inventory_put(j, value)
				_inventory_put(k, {})
				result = "moved"
				break
		main.inventory.selected = -1
		main.inventory.previous = -1
		main.inventory.tick = 30
	else:
		main.inventory.tick = 0
		if selected >= 0 and selected != k:
			main.inventory.tick = 30
			var a := inventory_slot(selected)
			var b := inventory_slot(k)
			if _inventory_fits(a, k) and _inventory_fits(b, selected):
				_inventory_put(k, a)
				_inventory_put(selected, b)
				result = "swapped"
			main.inventory.selected = -1
			main.inventory.previous = -1
		elif not inventory_slot(k).is_empty():
			main.inventory.selected = k
			if k == int(main.inventory.previous): main.inventory.previous = -1
			result = "selected"
	if result in ["moved", "swapped"]:
		refresh_hero_unit(main.hero_match)
	return result

## One game update for the dialog's counters and the pile checks. While the dialog is open (its tick 0x55f350, Read)
## 0xbbf2c8 counts up and 0xb90fa0 +0x200 stays 0; every 1000 ms: no living hero closes it; a pile more than 2 cells
## from the hero is committed (0x560a00) and let go; without a pile the first pile of the hero's 3 x 3 cells (row by row)
## fills the ground row (Provisional: only while the row is empty). Closed, 0x53a1a0 opens it beside a pile.
func inventory_tick():
	if not main.inventory.is_empty():
		main.inventory.tick = int(main.inventory.tick) + 1
		main.inventory_quiet_tick = 0
		main.inventory.second = int(main.inventory.get("second", 0)) + 1
		if int(main.inventory.second) < 40: return
		main.inventory.second = 0
		if not alive_hero():
			close_inventory()
			return
		var at: Vector2i = main.units[main.hero_unit_id].cell
		var pile = main.treasures.piles.get(int(main.inventory.pile)) if main.treasures != null else null
		if pile != null:
			if maxi(absi(at.x - pile.cell.x), absi(at.y - pile.cell.y)) > 2:
				_inventory_commit_ground()
				main.inventory.pile = -1
				main.inventory.ground = [{}, {}, {}, {}]
		elif main.inventory.ground.all(func(slot): return slot.is_empty()):
			var found := _pile_beside(at)
			if found >= 0:
				main.inventory.pile = found
				var items: Array = main.treasures.piles[found].items
				for k in mini(4, items.size()): main.inventory.ground[k] = {"item": int(items[k]), "source": "ground"}
		return
	main.inventory_quiet_tick += 1
	if not alive_hero() or main.treasures == null or main.treasures.piles.is_empty():
		main.inventory_hero_cell = Vector2i(-1, -1)
		return
	var cell: Vector2i = main.units[main.hero_unit_id].cell
	if cell == main.inventory_hero_cell: return
	main.inventory_hero_cell = cell
	if main.inventory_quiet_tick <= MainScript.INVENTORY_REOPEN_TICKS: return
	if main.hud != null and main.hud.dialog != "": return
	var id := _pile_beside(cell)
	if id >= 0: open_inventory(id)

## The first pile with items in the 3 x 3 cells around `cell`, row by row (0x53a1a0, 0x55f350), or -1.
func _pile_beside(cell: Vector2i) -> int:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var id: int = int(main.treasures.by_cell.get(cell + Vector2i(dx, dy), -1))
			if id >= 0 and not main.treasures.piles[id].items.is_empty(): return id
	return -1

## 0x560a00: the ground row, compacted, becomes the pile's items; without a pile they are put down at the hero.
func _inventory_commit_ground():
	var items: Array = []
	for slot in main.inventory.ground:
		if not slot.is_empty(): items.append(int(slot.item))
	var pile = main.treasures.piles.get(int(main.inventory.pile)) if main.treasures != null else null
	if pile != null:
		main.treasures.set_items(pile.id, items)
	elif not items.is_empty() and main.hero_unit_id >= 0 and main.hero_unit_id < main.units.size():
		main.treasures.drop_all(items, main.units[main.hero_unit_id].cell, "dropped")   # also a hero that just died

func refresh_hero_items():
	pass

func sync_treasure_sprites():
	var piles: Dictionary = main.treasures.piles if main.treasures != null else {}
	for id in main.treasure_sprites.keys():
		if not piles.has(id) or not is_instance_valid(main.treasure_sprites[id]):
			if is_instance_valid(main.treasure_sprites[id]): main.treasure_sprites[id].queue_free()
			main.treasure_sprites.erase(id)
	if piles.is_empty(): return
	var record: Dictionary = ArtData.data().get("effects", {}).get("IMAP", {})
	if record.is_empty(): return
	for id in piles:
		var sprite: Sprite2D = main.treasure_sprites.get(id)
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.centered = false
			sprite.region_enabled = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.texture = ArtData.texture(String(record.texture))
			sprite.region_rect = ArtData.frame_rect(record, 4, 0)
			sprite.offset = ArtData.offset(record)
			main.add_child(sprite)
			main.treasure_sprites[id] = sprite
		var cell: Vector2i = piles[id].cell
		sprite.position = Vector2(cell.x * 32 + 16, cell.y * 24 + 12)
		sprite.z_index = preload("res://core/map_data.gd").depth(sprite.position.y)

func alive_hero() -> bool:
	return main.hero_unit_id >= 0 and main.combat.alive(main.combat.fighters.get(main.hero_unit_id))

## to = -1: the first empty backpack slot; -2: the first equipment slot that takes the item (an empty one first).
func hero_item_move(from: int, to: int) -> bool:
	if not alive_hero(): return false
	var item := int((main.hero_match.profile.data.equipment[from] if from < 7 else main.hero_match.profile.data.backpack[from - 7]).get("item", 0))
	var target := to
	if to == -1:
		target = -1
		for i in range(7, 11):
			if main.hero_match.profile.data.backpack[i - 7].is_empty():
				target = i
				break
	elif to == -2:
		target = -1
		for i in range(7):
			if HeroEffects.equip_allowed(item, i) and main.hero_match.profile.data.equipment[i].is_empty():
				target = i
				break
		if target < 0:
			for i in range(7):
				if HeroEffects.equip_allowed(item, i):
					target = i
					break
	var ok: bool = target >= 0 and main.hero_match.move_item(from, target)
	main.last_message = ("%s moved." % HeroEffects.item_name(item)) if ok else "That item does not fit there."
	if ok: refresh_hero_unit(main.hero_match)
	refresh_hero_items()
	return ok

func hero_item_drop(slot: int) -> bool:
	if not alive_hero(): return false
	var id: int = main.hero_match.drop_slot(slot)
	if id > 0: main.treasures.drop(id, main.units[main.hero_unit_id].cell, "dropped")
	refresh_hero_unit(main.hero_match)
	refresh_hero_items()
	return id > 0

func hero_item_take(pile_id: int, index: int) -> bool:
	if not alive_hero(): return false
	var pile = main.treasures.piles.get(pile_id)
	if pile == null or index >= pile.items.size(): return false
	if main.hero_match.take_item(int(pile.items[index]), "ground") < 0:
		main.last_message = "The backpack is full."
		return false
	main.treasures.take(pile_id, index)
	refresh_hero_items()
	return true

## 0x54fd50(0, p, 0) after an item change: the hero block and unit are rebuilt; the hit points keep the damage taken.
func refresh_hero_unit(bound):
	if bound == null or bound.entity == null or not main.combat.fighters.has(bound.entity.entity_id): return
	var f = main.combat.fighters[bound.entity.entity_id]
	var stats := HeroEffects.hero_unit(bound.record())
	stats["flags"] = f.stats.get("flags", 0)
	var taken: int = int(f.max_hp) - int(f.hp)
	main.combat.set_base_stats(f, stats)            # milestone 13: the research armour term is applied again
	f.max_hp = int(stats.max_hp)
	f.hp = maxi(1, f.max_hp - taken)
	main.units[f.id].max_hp = f.max_hp
	main.units[f.id].hp = f.hp
	main.units[f.id].base_speed = HeroEffects.movement_speed(int(stats.speed), bound.block(f.hp))
	main.refresh_hero_commands()

func site_kind(hovered: Dictionary) -> String:
	if hovered.get("kind", "") != "building" or main.encounters == null: return ""
	var id: int = hovered.object.entity_id
	if main.encounters.givers.has(id): return "quest" if main.encounters.quests_enabled else ""
	return "shop" if main.encounters.shops.has(id) else ""

func order_site_visit(head, hovered: Dictionary, point: Vector2, mods: Dictionary) -> bool:
	if not main.is_hero_unit(head) or int(head.owner_id) != main.local_player or main.combat == null: return false
	var kind := site_kind(hovered)
	if kind == "": return false
	var id: int = hovered.object.entity_id
	head.sync_cell()
	var goal: Vector2i = main.navigator.free_cell_near(main.collision.world_cell(point), head, head.extent, head.movement_type)
	if goal.x < 0: return false
	if not mods.shift:
		main.patrols.erase(head.unit_id)
		main.guards.erase(head.unit_id)
		main.cancel_conversion(head)
		main.forget_modern_orders([head.unit_id])
		main.combat.order_stop(head.unit_id)
	head.give_order({"kind": "move", "target": main.navigator.center(goal), "requested": point, "group": 0, "speed": head.base_speed,
		"individual": true, "site": id}, "append" if mods.shift else "replace")
	main.combat.note_move(head.unit_id, goal)
	main.site_orders[head.unit_id] = {"building": id, "kind": kind, "goal": goal}
	return true

## Issue 1 (v0.1.0): the dialog opened wherever the hero's walk ended (stopped, a failed route, a fight), at any later
## moment. The visit now counts only when the hero stands at the cell it was sent to or beside the building, within
## SITE_REACH cells (Provisional: the original's own arrival test is not read; a blocked goal ends a walk a cell or two
## short). An order from a save made before this fix has no goal and is tested against the building only.
const SITE_REACH := 2

func arrived_at_site(unit, order: Dictionary, b) -> bool:
	var cell: Vector2i = unit.cell
	if order.get("goal") is Vector2i:
		var goal: Vector2i = order.goal
		if maxi(absi(cell.x - goal.x), absi(cell.y - goal.y)) <= SITE_REACH: return true
	return b.cell_rect().grow(SITE_REACH).has_point(cell)

## Orders 0xb / 0x13 on arrival (the order switch at line 195608 of the decompile): another order drops the visit, and
## so does a walk that ends anywhere but at the site (issue 1).
func resolve_site_orders():
	for id in main.site_orders.keys():
		var unit = main.unit_by_id(int(id))
		var order: Dictionary = main.site_orders[id]
		if unit == null or unit.dying or unit.removed:
			main.site_orders.erase(id)
			continue
		if not unit.orders.is_empty():
			if not unit.orders.any(func(o): return int(o.get("site", -1)) == int(order.building)): main.site_orders.erase(id)
			continue
		if unit.in_step: continue
		main.site_orders.erase(id)
		var b = main.production.building(int(order.building))
		if b == null or b.hit_points <= 0: continue
		# The player's own attack order (not a script's) replaced the walk without leaving a move order behind.
		var f = main.combat.fighters.get(int(id)) if main.combat != null else null
		if f != null and f.get("order") != null and not bool(f.order.get("ai", false)): continue
		if not arrived_at_site(unit, order, b): continue
		if order.kind == "quest": arrive_at_quest_site(int(order.building))
		else: arrive_at_shop(int(order.building))

## 0x43d180: the offer, instant, continue or complete dialog 0x56a150; nothing to offer: line 187 ([00bb]).
func arrive_at_quest_site(building_id: int) -> Dictionary:
	var v: Dictionary = main.encounters.visit(main.local_player, building_id)
	main.site_visit = v.duplicate()
	main.site_visit["building"] = building_id
	if main.hud != null:
		if String(v.get("mode", "none")) in ["none", "busy"]: main.hud.show_message(main.hud.game_text(187))
		else: main.hud.open_quest_offer(main.site_visit)
	return main.site_visit

## The dialog's accept (0x43d350 -> 0x527660) or reward (0x43d560).
func quest_site_accept(building_id: int) -> Dictionary:
	var mode := String(main.site_visit.get("mode", ""))
	if mode == "offer":
		if main.encounters.accept(main.local_player, building_id): return {"accepted": true}
		return {}
	if mode == "instant": main.encounters.accept(main.local_player, building_id)
	elif mode != "complete": return {}
	if main.hero_unit_id < 0: return {}
	var reward: Dictionary = main.encounters.complete(main.local_player, building_id, main.hero_match, main.units[main.hero_unit_id].cell)
	if not reward.is_empty() and main.skirmish != null: main.skirmish.note_quest(main.local_player)
	return reward

## 0x408580: dialog 12.
func arrive_at_shop(building_id: int):
	main.site_visit = {"building": building_id, "mode": "shop"}
	if main.hud != null: main.hud.open_shop(building_id)

## The four goods of dialog 12 for the HUD: {"good", "name", "price"}; an empty place has good 0.
func shop_goods(building_id: int) -> Array:
	var shop = main.encounters.shops.get(building_id)
	if shop == null: return []
	var out: Array = []
	for good in SkirmishShops.goods(shop):
		var entry := {"good": good, "name": "", "price": 0}
		if good > 0:
			var it: Dictionary = HeroEffects.item(int(good))
			entry.name = String(it.get("name", ""))
			entry.price = SkirmishShops.price(shop, good, main.local_player, int(it.get("value", 0)))
		elif good < 0:
			entry.name = "Healing Potion" if good == SkirmishShops.HEALING_POTION else "Mana Potion"
			entry.price = SkirmishShops.price(shop, good, main.local_player, 0)
		out.append(entry)
	return out

## 0x56e420: the place under the click; true when bought.
func shop_buy(building_id: int, place: int) -> bool:
	var goods: Array = shop_goods(building_id)
	if place < 0 or place >= goods.size() or int(goods[place].good) == 0: return false
	if main.hero_match == null or main.hero_unit_id < 0 or not main.combat.alive(main.combat.fighters.get(main.hero_unit_id)): return false
	if place == 0 and int(main.hero_match.potions) > SkirmishShops.POTION_LIMIT: return false
	if place == 1 and main.hero_match.mana_potion_count() > SkirmishShops.POTION_LIMIT: return false
	var price: int = int(goods[place].price)
	if not main.economy.try_spend(main.local_player, [price, price, price, price]): return false
	match place:
		0: main.hero_match.potions += 1
		1: main.hero_match.mana_potions = main.hero_match.mana_potion_count() + 1
		_:
			var good: int = int(goods[place].good)
			if not main.hero_match.receive_item(good, "shop"): main.treasures.drop(good, main.units[main.hero_unit_id].cell, "shop")
			main.encounters.shops[building_id].items[place - 2] = 0
	if main.audio != null: main.audio.ui_sound("sfx/Bing")
	return true

