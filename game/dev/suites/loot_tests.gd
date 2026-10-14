extends DevSuite
## Self-test: items, loot drops and their UI, names, icons and destructibles.

## Items: every base builds at each of its item levels, a plain one named for its base and a magic one for its modifiers, and the trader
## offers three different pieces. (DS2's numbers are locked by --only=ds2items.)
func _test_items() -> void:
	var plain: bool = true
	for def in ItemDb.all().values():
		for level in def.levels:
			var item: Dictionary = Items.build(def, level, Items.Rarity.NORMAL)
			plain = plain and item["name"] == def.display_name and int(item["level"]) == level and (item["mods"] as Array).is_empty()
	expect("every base builds at each of its item levels, named for its base", plain)
	var legacy_clean: bool = true
	for def in ItemDb.all().values():
		legacy_clean = legacy_clean and not def.stats.has("roll_cost") and not def.stats.has("roll_speed") \
			and not def.profile.has("arc") and not def.profile.has("arc_damage") and not def.profile.has("finisher")
	expect("repurposed Curse bases contain no old roll modifiers or automatic cleave", legacy_clean)
	var old_armor: Dictionary = Items.from_save({"base": "Leather Jerkin", "tier": 2,
		"stats": {"armor": 9999.0, "roll_speed": 5.0}, "affixes": ["legacy_bleed"]})
	expect("pre-DS2 saved gear rebuilds with DS2 armour and discards legacy stats/affixes",
		is_equal_approx(float(old_armor["stats"]["armor"]), 9.6) and not old_armor["stats"].has("roll_speed") and old_armor["mods"].is_empty())
	var saved_armor: Dictionary = Items.to_save(Items.build(ItemDb.get_def("plate_cuirass"), 22, Items.Rarity.NORMAL))
	saved_armor["stats"] = {"roll_speed": 5.0}
	saved_armor["mods"] = ["legacy_bleed"]
	var rebuilt: Dictionary = Items.from_save(saved_armor)
	expect("definition-era saves cannot reintroduce removed affixes or armour movement stats",
		rebuilt["mods"].is_empty() and not rebuilt["stats"].has("roll_speed"))
	var magic: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.MAGIC, 20, "Longsword")
	expect("a magic item is named for its modifiers (%s)" % magic["name"], not (magic["mods"] as Array).is_empty() and String(magic["name"]) != "Longsword")
	var choices: Array[Dictionary] = Items.roll_choices(5)
	expect("the trader offers 3 choices", choices.size() == 3)
	print("  items: offer: ", ", ".join(choices.map(func(c): return c["name"])))
	await get_tree().process_frame

## Monsters drop items instead of the old between-wave reward: the odds, the models, walking over a drop, upgrades being put on and
## the rest going to the bag.
func _test_loot() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame
	# Every base item has its Blender model.
	var missing: PackedStringArray = []
	for def in ItemDb.all().values():
		if not ResourceLoader.exists(def.model_path):
			missing.append(def.display_name)
	expect("every base item has a dropped model (%s missing)" % ", ".join(missing), missing.is_empty())
	# The odds (DS2): a miniboss always drops, an ordinary monster rarely.
	var weak_drops: int = 0
	var miniboss_ok: bool = true
	for i in 400:
		if not Items.roll_drop(5, "weak").is_empty():
			weak_drops += 1
		miniboss_ok = miniboss_ok and not Items.roll_drop(5, "miniboss").is_empty()
	expect("a miniboss always drops", miniboss_ok)
	# DS2's weak monster drops an item 5.75% of the time: 23 of 400 (sigma about 4.7).
	expect("an ordinary monster mostly drops nothing (%d of 400)" % weak_drops, weak_drops > 5 and weak_drops < 45)
	# The old reward screen is gone.
	expect("the director no longer offers a reward", not game.director.has_method("offer_reward") and not game.director.has_method("choose"))
	# A kill can drop an item that lands near the body.
	var def: EnemyDef = EnemyDb.get_def("zombie")
	player.global_position = Vector3(30, 0, 30)
	var zombie: Enemy = _spawn_enemy(Vector3(24, 0, 24))
	zombie.aggro_range = 0.0
	await get_tree().process_frame
	def.tier = "miniboss"   # (a miniboss always drops)
	zombie.receive({"outcome": Combat.Outcome.HIT, "damage": 9999.0, "source": player, "skill_id": "basic", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, player.global_position)
	await get_tree().create_timer(0.3).timeout
	def.tier = "normal"
	var drops: Array = get_tree().get_nodes_in_group("loot")
	expect("a killed monster drops an item", drops.size() == 1)
	if drops.size() == 1:
		var drop: LootDrop = drops[0]
		await get_tree().create_timer(LootDrop.LAND_TIME + 0.2).timeout
		expect("the drop lands on the ground near the body", drop.landed and absf(drop.global_position.y) < 0.05
			and drop.global_position.distance_to(Vector3(24, 0, 24)) < 3.0)
		expect("the drop can be seen: it has a model", drop.get_node_or_null("Model") != null)
		drop.queue_free()
	# Pickup: an empty slot is filled, anything else goes to the bag (rarity never swaps gear by itself).
	var stats: PlayerStats = player.stats
	var saved_equipment: Dictionary = stats.equipment.duplicate(true)
	var saved_bag: Array[Dictionary] = stats.bag.duplicate(true)
	stats.equipment = {}
	stats.bag = []
	var plain: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Longsword")
	stats.pickup(plain)
	expect("an empty slot takes whatever is picked up", stats.equipment.get(Items.Slot.WEAPON, {}).get("name") == "Longsword" and stats.bag.is_empty())
	stats.pickup(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Falchion"))
	expect("a second weapon goes to the bag", stats.equipment[Items.Slot.WEAPON]["name"] == "Longsword" and stats.bag.size() == 1)
	var fancy: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "Greatsword")
	stats.pickup(fancy)
	expect("a rarer weapon is never swapped in on its own: it goes to the bag", stats.equipment[Items.Slot.WEAPON]["name"] == "Longsword" and stats.bag.size() == 2)
	for i in 20:
		stats.add_to_bag(Items.make(Items.Slot.RING, Items.Rarity.NORMAL, 1))
	expect("the sized backpack retains twenty rings plus both carried weapons", stats.bag.size() == 22)
	# Walking over a drop does NOT pick it up: you click it (or its name), or press the use key.
	stats.bag = []
	player.global_position = Vector3(-30, 0, -30)   # well away, so the drop is not picked up as it lands
	player.reset_physics_interpolation()
	var walk: LootDrop = game.director.drop_item(Vector3(30, 0, 33), Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 1, "Mail Hauberk"))
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.3).timeout
	player.global_position = walk.global_position + Vector3(0.5, 0, 0)
	await get_tree().create_timer(0.5).timeout
	expect("standing on a drop does not pick it up", is_instance_valid(walk) and not walk.is_queued_for_deletion() and stats.bag.is_empty())
	walk.pick_up(player)
	await get_tree().process_frame
	expect("taking it puts the armour on (or in the bag)", stats.equipment.get(Items.Slot.ARMOR, {}).get("name") == "Mail Hauberk" or stats.bag.size() >= 1)
	# The hero holds what is equipped: each weapon shows its own model, and longer weapons are longer in the hand.
	var held_length: Dictionary = {}
	for base_name in ["Falchion", "Longsword", "Greatsword"]:
		TownState.passive_ranks["overbear"] = 1   # (a two-handed weapon needs Overbear)
		stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, base_name), false)
		await get_tree().process_frame
		var tip_y: float = player.model.weapon_tip.position.y
		held_length[base_name] = tip_y
		expect("equipping the %s puts its model in the hand" % base_name, player._held_path == Items.model_path(stats.equipment[Items.Slot.WEAPON])
			and player.model.weapon != null and player._trail.tip_node == player.model.weapon_tip)
	expect("a greatsword is longer in the hand than a falchion", held_length["Greatsword"] > held_length["Falchion"])
	stats.equipment = saved_equipment
	stats.bag = saved_bag
	stats.refresh()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame

## Drop readability and the item card: a drop grows with camera distance and carries a constant-size marker; pointing at it shows
## what it is and how it compares with what is worn; enemies notice the hero from a shorter distance than they used to.
func _test_loot_ui() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame
	expect("enemies notice the hero from a shorter range", EnemyDef.new().aggro_range <= 12.5 and EnemyDb.get_def("zombie").aggro_range <= 12.5)
	# Comparison.
	var longsword: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Longsword")
	var great: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Greatsword")
	var lines: Array[Dictionary] = Items.compare(great, longsword)
	var damage_better: bool = false
	var speed_worse: bool = false
	for entry in lines:
		if String(entry["text"]).begins_with("Damage") and int(entry["sign"]) > 0:
			damage_better = true
		if String(entry["text"]).begins_with("Speed") and int(entry["sign"]) < 0:
			speed_worse = true
	expect("a greatsword hits harder and swings slower than a longsword", damage_better and speed_worse)
	expect("an empty slot says so", Items.compare(great, null).any(func(e: Dictionary) -> bool: return e["text"] == "Nothing worn in this slot"))
	expect("the same item compares as the same", Items.compare(longsword, longsword)[0]["sign"] == 0)
	var leather: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 1, "Leather Jerkin")
	var plate: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 1, "Plate Cuirass")
	var armour_lines: Array[Dictionary] = Items.compare(plate, leather)
	var armour_better: bool = false
	for entry in armour_lines:
		if String(entry["text"]).begins_with("Armor") and int(entry["sign"]) > 0:
			armour_better = true
	expect("fighter plate protects more than ranger leather", armour_better)
	# Scale with distance, marker, focus.
	player.global_position = Vector3(0, 0, 0)
	var drop: LootDrop = game.director.drop_item(Vector3(0, 0, -4), Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "Falchion"))
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.4).timeout
	expect("a drop is the item itself, with no icon or 3D text on it", drop.get_node("Model") != null and drop.find_children("*", "Sprite3D", true, false).is_empty()
		and drop.find_children("*", "Label3D", true, false).is_empty())
	var near_scale: float = drop.get_node("Model").scale.x
	game.rig.set_zoom_now(CameraRig.ZOOM_MAX)
	await get_tree().create_timer(0.6).timeout
	var far_scale: float = drop.get_node("Model").scale.x
	game.rig.set_zoom_now(1.0)
	expect("a drop grows when the camera is far away (%.2f vs %.2f)" % [near_scale, far_scale], far_scale > near_scale * 1.15)
	# The item under the mouse is the one in focus.
	await get_tree().create_timer(0.6).timeout
	var camera: Camera3D = get_viewport().get_camera_3d()
	hud.mouse_override = camera.unproject_position(drop.global_position + Vector3(0, 0.5, 0))
	expect("pointing at a drop focuses it", hud.loot_cards.drop_in_focus() == drop)
	hud.mouse_override = camera.unproject_position(drop.global_position + Vector3(0, 1.5, 0))
	expect("pointing just over an item focuses it", hud.loot_cards.drop_in_focus() == drop)
	await get_tree().process_frame
	var name_plate: Rect2 = Rect2()
	for entry in hud.loot_cards.names:
		if entry["drop"] == drop:
			name_plate = entry["rect"]
	hud.mouse_override = name_plate.get_center()
	expect("the item's name plate focuses its stats", name_plate.size.x > 0.0 and hud.loot_cards.drop_in_focus() == drop)
	hud.mouse_override = camera.unproject_position(drop.global_position + Vector3(400, 0, 0))
	expect("pointing elsewhere focuses nothing", hud.loot_cards.drop_in_focus() == null)
	hud.mouse_override = Vector2(-1.0, -1.0)
	drop.queue_free()
	await get_tree().process_frame

## Item pictures: every base item has an icon and a framed badge, a tile shows a tooltip card, and the Tab panel lists what is worn.
func _test_item_icons() -> void:
	var missing: PackedStringArray = []
	for def in ItemDb.all().values():
		if ItemIcons.icon_for(Items.build(def, 1, Items.Rarity.RARE)) == null:
			missing.append(def.display_name)
	expect("every base item has an icon (%s missing)" % ", ".join(missing), missing.is_empty())
	var item: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "Greatsword")
	var badge: Texture2D = ItemIcons.badge(item)
	expect("an item's badge is its picture in a frame", badge != null and badge.get_width() == 96 and ItemIcons.badge(item) == badge)
	var common_badge: Texture2D = ItemIcons.badge(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Greatsword"))
	expect("rarity changes the frame", common_badge.get_image().get_pixel(3, 40) != badge.get_image().get_pixel(3, 40))
	var tile: ItemTile = ItemTile.create(item, Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Longsword"))
	add_child(tile)
	tile.mouse_entered.emit()   # pointing at the picture shows the card at once (the buttons beside it show nothing)
	var card: Control = null
	for child in tile.get_children():
		if child is Control and (child as Control).visible and (child as Control).get_child_count() > 0:
			card = (child as Control).get_child(0) as Control
	expect("pointing at a tile shows a card that describes the item and compares it", card != null and _label_text(card).contains("Greatsword") and _label_text(card).contains("Damage"))
	tile.mouse_exited.emit()
	# The close is a deferred call: wait for its decision, but for at most 10 frames, so a missing decision is a [FAIL], not a hang.
	var decided: Array = [false]
	Signal(tile.get_node("ItemDetails"), "hover_resolved").connect(func() -> void: decided[0] = true)
	var waited := 0
	while not decided[0] and waited < 10:
		await get_tree().process_frame
		waited += 1
	expect("the close decision arrives within 10 frames", decided[0])
	expect("and it goes when the pointer leaves", not tile.get_children().any(func(c: Node) -> bool: return c is Control and (c as Control).visible))
	tile.queue_free()
	# On the ground an item is the item itself with its name over it in its rarity's colour, not a picture of it.
	var drop: LootDrop = game.director.drop_item(Vector3(40, 0, 40), item)
	await get_tree().create_timer(0.2).timeout
	expect("a dropped item is the item itself (its name is a plate drawn by the HUD), with no icon", drop.find_children("*", "Sprite3D", true, false).is_empty()
		and drop.get_node("Model") != null)
	drop.queue_free()
	# The character view contains focusable item pictures with the same details cards.
	hud.show_gear = true
	hud._open_character()
	await get_tree().create_timer(0.3).timeout
	expect("the Tab view has pictures for worn gear", not hud.character_panel.find_children("*", "Control", true, false).filter(func(control: Node) -> bool: return control is ItemTile).is_empty())
	hud.close_character()
	await get_tree().process_frame

## Breakable props: barrels, carts, gravestones and braziers can be smashed; a power's blast breaks them along its
## path; clicking one makes the hero swing at it; what breaks stops blocking the way and may leave something behind.
func _test_destructibles() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().process_frame
	var props: Array = get_tree().get_nodes_in_group("destructibles")
	var kinds: Dictionary = {}
	for node in props:
		kinds[(node as Destructible).prop_name] = true
	expect("the arena has breakable barrels, carts, gravestones and braziers", kinds.has("barrel") and kinds.has("wrecked_cart")
		and kinds.has("gravestone") and kinds.has("brazier"))
	# Hits: a barrel survives a scratch and goes with a proper blow; the pieces and what is left behind.
	arena.place_prop("barrel", Vector3(34, 0, 34), 0.0, 1.0)
	var barrel: Destructible = Destructible.near(get_tree(), Vector3(34, 0, 34), 0.5)
	expect("a placed barrel is breakable", barrel != null and barrel.prop_name == "barrel")
	var obstacles_before: int = arena.obstacles.size()
	expect("a scratch does not break it", not barrel.hit(3.0, Vector3.RIGHT) and not barrel.broken and barrel.hp < barrel.max_hp)
	expect("a proper blow does", barrel.hit(30.0, Vector3.RIGHT))
	await get_tree().create_timer(0.3).timeout
	expect("it throws pieces", get_tree().get_nodes_in_group("debris").size() >= 10)
	expect("what is broken stops being an obstacle", arena.obstacles.size() == obstacles_before - 1 and Destructible.near(get_tree(), Vector3(34, 0, 34), 0.5) == null)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	# Gravestones take several hits.
	arena.place_prop("gravestone", Vector3(30, 0, 36), 0.0, 1.3)
	var grave: Destructible = Destructible.near(get_tree(), Vector3(30, 0, 36), 0.5)
	expect("a gravestone takes more than one swing", not grave.hit(15.0, Vector3.RIGHT) and not grave.hit(15.0, Vector3.RIGHT) and grave.hit(15.0, Vector3.RIGHT))
	# A Whirling Strike breaks what stands around the hero.
	player.global_position = Vector3(26, 0, 30)
	player.reset_physics_interpolation()
	TownState.passive_ranks["critical_strike"] = 8
	TownState.passive_ranks["fortitude"] = 8
	player.powers.reset()
	arena.place_prop("barrel", Vector3(27.6, 0, 30), 0.0, 1.0)
	await get_tree().process_frame
	expect("a Whirling Strike smashes a barrel beside the hero", player.powers.activate("whirling_strike", player.global_position)
		and Destructible.near(get_tree(), Vector3(27.6, 0, 30), 0.3) == null)
	TownState.passive_ranks.clear()
	player.powers.reset()
	# Clicking a prop sends the hero to swing at it.
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	player.global_position = Vector3(20, 0, 20)
	player.reset_physics_interpolation()
	player.stats.stamina = player.stats.max_stamina
	arena.place_prop("barrel", Vector3(24, 0, 20), 0.0, 1.0)
	await get_tree().process_frame
	var target: Destructible = Destructible.near(get_tree(), Vector3(24, 0, 20), 0.3)
	player.attack_prop = target
	var smash_t: float = 0.0
	while smash_t < 6.0 and not target.broken:
		await get_tree().physics_frame
		smash_t += 1.0 / 60.0
	expect("the hero walks up and smashes a barrel they were sent at (%.1f s)" % smash_t, target.broken)
	# Fire and explosions.
	arena.place_prop("barrel", Vector3(14, 0, 14), 0.0, 1.0)
	await get_tree().process_frame
	expect("a blast breaks what is inside it", Destructible.blast(get_tree(), Vector3(14, 0, 14.5), 2.0, 80.0) == 1)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().process_frame

## Loot on the ground: nothing is picked up by walking over it; clicking an item (or its name) sends the hero to take it, the use key takes the
## nearest one in reach; and the names over a pile of drops never overlap, however many fall in one place.
func _test_loot_names() -> void:
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.stats.bag.clear()
	# A pile: twelve items landing within a metre of each other.
	var pile: Array[LootDrop] = []
	for i in 12:
		var drop: LootDrop = game.director.drop_item(Vector3(0, 0, -6), Items.make(Items.Slot.WEAPON if i % 2 == 0 else Items.Slot.ARMOR, [Items.Rarity.NORMAL, Items.Rarity.RARE][i % 2], 1, ""))
		drop._end = Vector3(randf_range(-0.5, 0.5), 0.0, -6.0 + randf_range(-0.5, 0.5))
		pile.append(drop)
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.6).timeout
	hud.show_gear = false
	await get_tree().process_frame
	await get_tree().process_frame
	var plates: Array[Dictionary] = hud.loot_cards.names
	var clashes: int = 0
	for i in plates.size():
		for j in range(i + 1, plates.size()):
			if (plates[i]["rect"] as Rect2).intersects(plates[j]["rect"]):
				clashes += 1
	expect("a pile of twelve drops has twelve name plates and none overlaps another (%d plates, %d clashes)" % [plates.size(), clashes], plates.size() == 12 and clashes == 0)
	# Nothing is taken by standing on it.
	player.global_position = pile[0].global_position
	await get_tree().create_timer(0.6).timeout
	var still: int = 0
	for drop in pile:
		still += 1 if is_instance_valid(drop) and not drop.is_queued_for_deletion() else 0
	expect("standing in the pile takes nothing", still == 12 and player.stats.bag.is_empty())
	# Sent for one, the hero walks to it and takes it, and only it.
	player.global_position = Vector3(0, 0, 4)
	player.reset_physics_interpolation()
	var target: LootDrop = pile[3]
	var taken_name: String = String(target.item["name"])
	player.pickup_target = target
	var seconds: float = 0.0
	while is_instance_valid(target) and not target.is_queued_for_deletion() and seconds < 6.0:
		await get_tree().physics_frame
		seconds += 1.0 / 60.0
	await get_tree().process_frame
	var left: int = 0
	for drop in pile:
		left += 1 if is_instance_valid(drop) and not drop.is_queued_for_deletion() else 0
	expect("sent for an item, the hero walks to it and takes that one (%.1f s)" % seconds, left == 11 and player.pickup_target == null
		and (player.stats.equipment.values().any(func(it: Dictionary) -> bool: return it["name"] == taken_name) or player.stats.bag.any(func(it: Dictionary) -> bool: return it["name"] == taken_name)))
	# The use key takes the nearest one in reach, and nothing out of reach.
	player.global_position = Vector3(0, 0, 4)
	player.reset_physics_interpolation()
	Input.action_press("interact")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("interact")
	var after_far: int = 0
	for drop in pile:
		after_far += 1 if is_instance_valid(drop) and not drop.is_queued_for_deletion() else 0
	expect("the use key takes nothing that is out of reach", after_far == 11)
	player.global_position = pile[0].global_position + Vector3(0.4, 0, 0)
	Input.action_press("interact")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("interact")
	await get_tree().process_frame
	var after_near: int = 0
	for drop in pile:
		after_near += 1 if is_instance_valid(drop) and not drop.is_queued_for_deletion() else 0
	expect("next to the pile the use key takes one", after_near == 10)
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()

## Item cards (trader, stash, inventory, hover and the ground all draw ItemTile.display_rows): each stat's change sits beside the stat,
## green when it helps and red when it hurts with the sign kept, "Compared with" is gone, and the cannot-wear warning shows exactly once.
func _test_item_card() -> void:
	var member: String = PartyManager.current().active_id
	var leather: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 1, "Leather Jerkin")
	var plate: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 1, "Plate Cuirass")
	var downgrade := ItemTile.display_rows(leather, Items.compare(leather, plate, member), member)
	var armor_row: Dictionary = {}
	for row in downgrade:
		if String(row["text"]).begins_with("Armor ") and String(row["text"]).contains("("):
			armor_row = row
	expect("a worse armour shows its change beside the stat: %s" % armor_row.get("text", ""),
		String(armor_row.get("text", "")).ends_with("(-%d)" % int(float(plate["stats"]["armor"]) - float(leather["stats"]["armor"]))))
	expect("a detrimental change is drawn red", armor_row.has("color") and (armor_row["color"] as Color).is_equal_approx(ItemTile._delta_color(-1)))
	var upgrade := ItemTile.display_rows(plate, Items.compare(plate, leather, member), member)
	var better: Dictionary = {}
	for row in upgrade:
		if String(row["text"]).begins_with("Armor "):
			better = row
	expect("a better armour shows a plus beside the stat: %s" % better.get("text", ""), String(better.get("text", "")).contains("(+"))
	expect("a beneficial change is drawn green", better.has("color") and (better["color"] as Color).is_equal_approx(ItemTile._delta_color(1)))
	var card := ItemTile.card(plate, leather, true)
	var card_texts: Array[String] = []
	for label in card.find_children("*", "Label", true, false):
		card_texts.append((label as Label).text)
	card.free()
	expect("no footer comparison heading remains", not card_texts.any(func(t: String) -> bool: return t.contains("Compared with")))
	var heavy: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 60, "Plate Cuirass")
	if not Items.hero_can_wear(heavy, member):
		expect("an unwearable item has one warning", Items.wear_warning(heavy, member).size() == 1)
		var heavy_card := ItemTile.card(heavy, null, true)
		var warning_labels := 0
		for label in heavy_card.find_children("*", "Label", true, false):
			if (label as Label).text.contains("cannot wear"):
				warning_labels += 1
		heavy_card.free()
		expect("the cannot-wear warning appears once on the card", warning_labels == 1)
	else:
		print("  item card: hero can wear the level-60 plate, so the warning check is skipped")
	# An elemental damage item compares as one "Fire damage" row. Its "_added_max" maximum is part of that row, not a separate line.
	var fire_sword: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 15, "Longsword")
	fire_sword["mods"] = ["fire_added_1"]
	var plain_sword: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 15, "Longsword")
	var fire_compare := Items.compare(fire_sword, plain_sword, member)
	var raw_key := fire_compare.any(func(e: Dictionary) -> bool: return String(e["text"]).contains("_max") or String(e["text"]).contains("_added"))
	expect("an elemental item compares with no raw stat key in any row: %s" % [fire_compare], not raw_key)
	expect("an elemental item's fire change is one row", fire_compare.any(func(e: Dictionary) -> bool: return String(e["key"]) == Items.mod_key("fire_added")))
	# Equal minimum, different maximum: both pieces hit for 2 at the minimum, but the worn one's maximum is 6 and this one's is 4. That is a real
	# change, shown on its own row in red, and the two are not reported as the same.
	var lower_max: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 15, "Longsword")
	lower_max["mods"] = ["fire_added_1"]
	var higher_max: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 15, "Longsword")
	higher_max["mods"] = ["fire_added_2"]
	higher_max["mod_values"] = {"fire_added_2": 2.0}
	var max_compare := Items.compare(lower_max, higher_max, member)
	expect("equal minimum with a different maximum is not reported as the same: %s" % [max_compare],
		not max_compare.any(func(e: Dictionary) -> bool: return String(e["text"]) == "Same as what you wear"))
	var max_rows := max_compare.filter(func(e: Dictionary) -> bool: return String(e["text"]).begins_with("Maximum fire damage"))
	expect("the lower maximum is its own row, named and red: %s" % [max_compare],
		max_rows.size() == 1 and String(max_rows[0]["text"]) == "Maximum fire damage 4 (-2)" and int(max_rows[0]["sign"]) < 0)
	# A card taller than its safe area scrolls with the mouse wheel: the wheel over the card moves its scroll position.
	var tile := ItemTile.create(plate, null, 56.0)
	tile.position = Vector2(120, 120)
	add_child(tile)
	await get_tree().process_frame
	tile.mouse_entered.emit()
	await get_tree().process_frame
	var holder := tile.get_node("ItemDetails") as Control
	var scroll: ScrollContainer = null
	if holder.get_child_count() > 0:
		scroll = holder.get_child(0) as ScrollContainer
	expect("an opened item card has a scroll area", scroll != null and holder.visible)
	# An item in the middle of the screen gets a card beside it, not pinned to the top of the screen.
	await _check_card_beside_item(get_viewport().get_visible_rect().size * 0.5 - Vector2(28, 28))
	if scroll != null:
		scroll.size = Vector2(300, 120)   # shorter than the card: it overflows
		await get_tree().process_frame
		expect("the card overlaps its item's edge, so the pointer crosses from item to card without a gap", scroll.get_global_rect().intersects(tile.get_global_rect()))
		await get_tree().process_frame
		expect("a tall item card overflows its scroll area so the wheel has something to move", scroll.get_v_scroll_bar().max_value > scroll.size.y)
		expect("the scroll area takes the mouse so the wheel reaches it", scroll.mouse_filter == Control.MOUSE_FILTER_PASS)
	# At the left and right screen edges the clamp must keep the card overlapping its item, so there is still no gap to cross.
	var view_size := get_viewport().get_visible_rect().size
	for edge_x in [view_size.x - 60.0, 2.0]:
		var edge_tile := ItemTile.create(plate, null, 56.0)
		edge_tile.position = Vector2(edge_x, 120.0)
		add_child(edge_tile)
		await get_tree().process_frame
		edge_tile.mouse_entered.emit()
		await get_tree().process_frame
		var edge_holder := edge_tile.get_node("ItemDetails") as Control
		var edge_scroll: ScrollContainer = null
		if edge_holder.get_child_count() > 0:
			edge_scroll = edge_holder.get_child(0) as ScrollContainer
		expect("at the screen edge x=%d the card still overlaps its item across the hover edge" % int(edge_x),
			edge_scroll != null and ItemTile._keeps_hover_edge(edge_scroll.get_global_rect(), edge_tile.get_global_rect()))
		edge_tile.queue_free()
		await get_tree().process_frame
	tile.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## A hover card opens beside its item, at the item's position on screen. Opened with the item at `at`, the card must sit on one side of it,
## overlapping across that edge by HOVER_OVERLAP. Beside a left or right side its top is the item's top; above or below, its left is the
## item's left. It is never above the top of the screen, and never above its item by more than its own height. A card pinned to the top of
## the screen (the wrong-height bug) fails the top-alignment check for an item in the middle of the screen.
func _check_card_beside_item(at: Vector2) -> void:
	var plate: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 1, "Plate Cuirass")
	var tile := ItemTile.create(plate, null, 56.0)
	tile.position = at
	add_child(tile)
	await get_tree().process_frame
	tile.mouse_entered.emit()
	await get_tree().process_frame
	var holder := tile.get_node("ItemDetails") as Control
	var scroll: ScrollContainer = null
	if holder.get_child_count() > 0:
		scroll = holder.get_child(0) as ScrollContainer
	expect("a middle-of-screen item opens a card", scroll != null and holder.visible)
	if scroll != null:
		var item := tile.get_global_rect()
		var card := scroll.get_global_rect()
		var tol := 1.5
		var right := absf(card.position.x - (item.end.x - ItemTile.HOVER_OVERLAP)) <= tol
		var left := absf(card.end.x - (item.position.x + ItemTile.HOVER_OVERLAP)) <= tol
		var below := absf(card.position.y - (item.end.y - ItemTile.HOVER_OVERLAP)) <= tol
		var above := absf(card.end.y - (item.position.y + ItemTile.HOVER_OVERLAP)) <= tol
		expect("the card sits on one side of its item (card %s, item %s)" % [card, item], right or left or below or above)
		expect("the card overlaps its item across that edge (card %s, item %s)" % [card, item], ItemTile._keeps_hover_edge(card, item))
		if right or left:
			expect("beside its item the card's top is the item's top, not the screen top (card y %d, item y %d)" % [int(card.position.y), int(item.position.y)],
				absf(card.position.y - item.position.y) <= tol)
		if below or above:
			expect("above or below its item the card's left is the item's left (card x %d, item x %d)" % [int(card.position.x), int(item.position.x)],
				absf(card.position.x - item.position.x) <= tol)
		expect("the card is not above the top of the screen (y %d)" % int(card.position.y), card.position.y >= 0.0)
		expect("the card is not above its item by more than its own height", card.position.y >= item.position.y - card.size.y)
	tile.queue_free()
	await get_tree().process_frame

## An item pickup's name: 3 s readable and a 0.5 s fade (4 s for a rare or better), and rapid pickups stack instead of overwriting each other.
func _test_pickup_notice() -> void:
	expect("an ordinary pickup stays 3 s, then fades in 0.5 s", Fx.pickup_timing(false).is_equal_approx(Vector2(3.0, 0.5)))
	expect("a rare or important pickup stays 4 s, then fades in 0.5 s", Fx.pickup_timing(true).is_equal_approx(Vector2(4.0, 0.5)))
	var base := player.global_position + Vector3(0, 2.6, 0)
	var first := Fx.pickup_text(player, base, "First", Color.WHITE)
	var second := Fx.pickup_text(player, base, "Second", Color.WHITE)
	var third := Fx.pickup_text(player, base, "Third", Color.WHITE, true)
	await get_tree().process_frame
	expect("three rapid pickups are all still on screen", is_instance_valid(first) and is_instance_valid(second) and is_instance_valid(third))
	expect("a second pickup starts above the first, not on it", second.global_position.y >= first.global_position.y + Fx.PICKUP_STEP - 0.001)
	expect("a third pickup stacks above the second", third.global_position.y >= second.global_position.y + Fx.PICKUP_STEP - 0.001)
	expect("the rapid pickups keep their own text", first.text == "First" and second.text == "Second" and third.text == "Third")
	var other := Fx.pickup_text(game.companion, base, "Archer", Color.WHITE)
	expect("another hero's pickup does not stack on this one", absf(other.global_position.y - base.y) < 0.001)
	# Lines already freed, and lines queued for deletion, must not break later pickups: the live ones still stack.
	var stale := Fx.pickup_text(player, base, "Stale", Color.WHITE)
	stale.queue_free()
	await get_tree().process_frame
	var fresh := Fx.pickup_text(player, base, "Fresh", Color.WHITE)
	var queued := Fx.pickup_text(player, base, "Queued", Color.WHITE)
	queued.queue_free()
	var after := Fx.pickup_text(player, base, "After", Color.WHITE)
	await get_tree().process_frame
	expect("pickups after freed and queued lines still show", is_instance_valid(fresh) and is_instance_valid(after))
	expect("a pickup after a freed line stacks above the live lines", fresh.global_position.y >= third.global_position.y + Fx.PICKUP_STEP - 0.001)
	expect("a pickup after a queued line stacks above the live lines", after.global_position.y >= fresh.global_position.y + Fx.PICKUP_STEP - 0.001)
	for label in [first, second, third, other, fresh, after]:
		label.queue_free()
	await get_tree().process_frame
