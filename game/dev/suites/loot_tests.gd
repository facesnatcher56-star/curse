extends DevSuite
## Self-test: items, loot drops and their UI, names, icons, destructibles and affixes.

## Equips every affix in turn and drives each hook (hit, kill, roll, incoming damage, skills) against dummies.
func _test_items() -> void:
	var failures: int = 0
	var dummies: Array[Enemy] = []
	for i in 4:
		var z: Enemy = _spawn_enemy(Vector3(2.0 + i * 0.8, 0, 1.0 + (i % 2) * 0.6))
		z.aggro_range = 0.0
		z.max_health = 400.0
		z.health = 400.0
		dummies.append(z)
	await get_tree().process_frame
	var saved: Dictionary = player.stats.equipment.duplicate()
	for id in AffixDb.all():
		var slot: int = AffixDb.all()[id]["slot"]
		var item: Dictionary = Items.make(slot, Items.Rarity.RARE, 1, id)
		player.stats.equip(item, false)
		if not player.stats.has_affix(id):
			failures += 1
			print("  AFFIX NOT ACTIVE: ", id)
		var target: Enemy = dummies[0]
		var result: Dictionary = Combat.resolve(player, target, 20.0, Combat.DamageType.PHYSICAL, false, 1.0, true)
		result["finisher"] = true
		target.receive(result, player.global_position)
		ItemEffects.on_kill(player, target)
		ItemEffects.on_roll_start(player)
		ItemEffects.power_shockwave(player, Vector3(1, 0, 0))
		var incoming: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": 10.0, "weight": 1.0}
		ItemEffects.filter_incoming(player, incoming)
		for d in dummies:
			d.health = d.max_health
			d.bleed_time = 0.0
			d.slow_time = 0.0
		player.stats.cooldowns.clear()
		player.stats.haste_time = 0.0
		player.stats.vault_time = 0.0
		player.stats.chain_time = 0.0
		await get_tree().process_frame
	var choices: Array[Dictionary] = Items.roll_choices(5, true, [])
	expect("every affix is driven by its hook", failures == 0)
	expect("reward offers 3 choices", choices.size() == 3)
	print("  items: ", AffixDb.all().size(), " affixes driven; reward choices=", choices.size(), " (brute offer: ",
		", ".join(choices.map(func(c): return c["name"])), "), failures=", failures)
	for d in dummies:
		d.queue_free()
	player.stats.equipment = saved
	player.armor = player.stats.base_armor + player.stats.armor_stat("armor", 0.0)
	player.health = player.max_health
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
	# The odds: ordinary monsters mostly drop commons, a Brute never drops a common.
	var common_brute: int = 0
	var rare_or_better: int = 0
	for i in 200:
		if int(Items.roll_drop(5, 1.0, [])["rarity"]) == Items.Rarity.COMMON:
			common_brute += 1
		if int(Items.roll_drop(2, 0.0, [])["rarity"]) >= Items.Rarity.RARE:
			rare_or_better += 1
	expect("a Brute's drop is always rare or better", common_brute == 0)
	# About 73% of 200 are rare or better (a rare roll, plus every common trinket made rare): a spread of six sigma either side.
	expect("an ordinary monster's drop is often common but sometimes rare", rare_or_better > 90 and rare_or_better < 188)
	expect("only monsters that should drop do", EnemyDb.get_def("brute").drop_chance > EnemyDb.get_def("zombie").drop_chance
		and EnemyDb.get_def("zombie").drop_chance > 0.0)
	# The old reward screen is gone.
	expect("the director no longer offers a reward", not game.director.has_method("offer_reward") and not game.director.has_method("choose"))
	# A kill can drop an item that lands near the body.
	var def: EnemyDef = EnemyDb.get_def("zombie")
	var saved_chance: float = def.drop_chance
	def.drop_chance = 1.0
	player.global_position = Vector3(30, 0, 30)
	var zombie: Enemy = _spawn_enemy(Vector3(24, 0, 24))
	zombie.aggro_range = 0.0
	await get_tree().process_frame
	zombie.receive({"outcome": Combat.Outcome.HIT, "damage": 9999.0, "source": player, "skill_id": "basic", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, player.global_position)
	await get_tree().create_timer(0.3).timeout
	def.drop_chance = saved_chance
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
	var plain: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Longsword")
	stats.pickup(plain)
	expect("an empty slot takes whatever is picked up", stats.equipment.get(Items.Slot.WEAPON, {}).get("name") == "Longsword" and stats.bag.is_empty())
	stats.pickup(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Falchion"))
	expect("a second weapon goes to the bag", stats.equipment[Items.Slot.WEAPON]["name"] == "Longsword" and stats.bag.size() == 1)
	var fancy: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword")
	for id in AffixDb.all():
		if AffixDb.all()[id]["slot"] == Items.Slot.WEAPON and AffixDb.all()[id]["title"] != "":
			fancy = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, id)
			break
	stats.pickup(fancy)
	expect("a rarer weapon is never swapped in on its own: it goes to the bag", stats.equipment[Items.Slot.WEAPON]["name"] == "Longsword" and stats.bag.size() == 2)
	for i in 20:
		stats.add_to_bag(Items.make(Items.Slot.TRINKET, Items.Rarity.COMMON, 1))
	expect("the bag holds a dozen items", stats.bag.size() == PlayerStats.MAX_BAG)
	# Walking over a drop does NOT pick it up: you click it (or its name), or press the use key.
	stats.bag = []
	player.global_position = Vector3(-30, 0, -30)   # well away, so the drop is not picked up as it lands
	player.reset_physics_interpolation()
	var walk: LootDrop = game.director.drop_item(Vector3(30, 0, 33), Items.make(Items.Slot.ARMOR, Items.Rarity.COMMON, 1, "", "Mail Hauberk"))
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
		stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", base_name), false)
		await get_tree().process_frame
		var tip_y: float = player.model.weapon_tip.position.y
		held_length[base_name] = tip_y
		expect("equipping the %s puts its model in the hand" % base_name, player._held_path == Items.model_path(stats.equipment[Items.Slot.WEAPON])
			and player.model.weapon != null and player._trail.tip_node == player.model.weapon_tip)
	expect("a greatsword is longer in the hand than a falchion", held_length["Greatsword"] > held_length["Falchion"])
	stats.equipment = saved_equipment
	stats.bag = saved_bag
	player.armor = stats.base_armor + stats.armor_stat("armor", 0.0)
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
	var longsword: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Longsword")
	var great: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword")
	var lines: Array[Dictionary] = Items.compare(great, longsword)
	var damage_better: bool = false
	var speed_worse: bool = false
	for entry in lines:
		if String(entry["text"]).begins_with("Damage") and int(entry["sign"]) > 0:
			damage_better = true
		if String(entry["text"]).begins_with("Speed") and int(entry["sign"]) < 0:
			speed_worse = true
	expect("a greatsword hits harder and swings slower than a longsword", damage_better and speed_worse)
	expect("an empty slot says so", Items.compare(great, null)[0]["text"] == "Nothing worn in this slot")
	expect("the same item compares as the same", Items.compare(longsword, longsword)[0]["sign"] == 0)
	var leather: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.COMMON, 1, "", "Leather Jerkin")
	var plate: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.COMMON, 1, "", "Plate Cuirass")
	var armour_lines: Array[Dictionary] = Items.compare(plate, leather)
	var cost_worse: bool = false
	for entry in armour_lines:
		if String(entry["text"]).begins_with("Roll cost") and int(entry["sign"]) < 0:
			cost_worse = true
	expect("heavier armour costs more to roll in", cost_worse)
	# Scale with distance, marker, focus.
	player.global_position = Vector3(0, 0, 0)
	var drop: LootDrop = game.director.drop_item(Vector3(0, 0, -4), Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "", "Falchion"))
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
	var item: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.UNIQUE, 1, "", "Greatsword")
	var badge: Texture2D = ItemIcons.badge(item)
	expect("an item's badge is its picture in a frame", badge != null and badge.get_width() == 96 and ItemIcons.badge(item) == badge)
	var common_badge: Texture2D = ItemIcons.badge(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword"))
	expect("rarity changes the frame", common_badge.get_image().get_pixel(3, 40) != badge.get_image().get_pixel(3, 40))
	var tile: ItemTile = ItemTile.create(item, Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Longsword"))
	add_child(tile)
	tile.mouse_entered.emit()   # pointing at the picture shows the card at once (the buttons beside it show nothing)
	var card: Control = null
	for child in tile.get_children():
		if child is Control and (child as Control).visible and (child as Control).get_child_count() > 0:
			card = (child as Control).get_child(0) as Control
	expect("pointing at a tile shows a card that describes the item and compares it", card != null and _label_text(card).contains("Greatsword") and _label_text(card).contains("Damage"))
	tile.mouse_exited.emit()
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

## Breakable props: barrels, carts, gravestones and braziers can be smashed; a charge or a leap through them throws the pieces along its
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
	# Charging through a barrel throws the pieces the way the hero was going.
	player.global_position = Vector3(26, 0, 30)
	player.reset_physics_interpolation()
	player.visual.rotation.y = PI * 0.5
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns["skewer"] = 0.0
	arena.place_prop("barrel", Vector3(30, 0, 30), 0.0, 1.0)
	arena.place_prop("wrecked_cart", Vector3(33, 0, 30.4), 0.0, 1.9)
	await get_tree().process_frame
	player.skills.try_directional("skewer", Vector3(40, 0, 30))
	var charge_t: float = 0.0
	while charge_t < 3.0 and (player.skills.busy or charge_t < 0.3):
		await get_tree().physics_frame
		charge_t += 1.0 / 60.0
	expect("a Skewer charge smashes what is in its path", Destructible.near(get_tree(), Vector3(30, 0, 30), 0.3) == null
		and Destructible.near(get_tree(), Vector3(33, 0, 30.4), 0.3) == null)
	var ahead: float = 0.0
	var count: int = 0
	for node in get_tree().get_nodes_in_group("debris"):
		ahead += (node as DebrisChunk).velocity.x + ((node as DebrisChunk).global_position.x - 30.0)
		count += 1
	expect("the pieces are thrown ahead of the charge (%d pieces)" % count, count > 10 and ahead > 0.0)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().create_timer(1.0).timeout
	# Leaping over a barrel breaks it too.
	player.global_position = Vector3(26, 0, 33)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns["leap"] = 0.0
	arena.place_prop("barrel", Vector3(30, 0, 33), 0.0, 1.0)
	await get_tree().process_frame
	player.skills.try_directional("leap", Vector3(34, 0, 33))
	var leap_t: float = 0.0
	while leap_t < 4.0 and (player.skills.busy or leap_t < 0.3):
		await get_tree().physics_frame
		leap_t += 1.0 / 60.0
	expect("a Leap through a barrel breaks it", Destructible.near(get_tree(), Vector3(30, 0, 33), 0.3) == null)
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

## The new gear affixes (the six dull ones are gone): each does what it says, using the same moves and states the skills create.
func _test_new_affixes() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	# The catalogue.
	var removed: Array = ["frostbite", "momentum", "last_stand", "riposte", "warding", "windfall"]
	var gone: bool = true
	for id in removed:
		gone = gone and not AffixDb.all().has(id)
	expect("the six dull affixes are gone", gone)
	var counts: Dictionary = {0: 0, 1: 0, 2: 0}
	var described: bool = true
	for id in AffixDb.all():
		var entry: Dictionary = AffixDb.all()[id]
		described = described and String(entry["desc"]) != ""
		if String(entry["title"]) != "":
			counts[int(entry["slot"])] += 1
	expect("9 weapon, 5 armor and 6 trinket affixes can roll on rares", counts[0] == 9 and counts[1] == 5 and counts[2] == 6)
	expect("every affix is described", described)
	var pips_ok: bool = true
	for skill_id in SkillDb.all():
		for affix_id in SkillDb.modifier_affixes(skill_id):
			pips_ok = pips_ok and AffixDb.all().has(affix_id)
	expect("every skill's list of affixes that change it names real ones", pips_ok)
	expect("Cleave and Whirling are absent from playable definitions and loot", not SkillDb.all().has("cleave") and not AffixDb.all().has("whirlpool")
		and not player.skills.hotbar.has("cleave") and player.skills.hotbar.size() == 6)

	var saved: Dictionary = player.stats.equipment.duplicate()
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	var a: Enemy = _spawn_enemy(Vector3(6, 0, 0))
	var b: Enemy = _spawn_enemy(Vector3(7.2, 0, 0))
	var far: Enemy = _spawn_enemy(Vector3(-20, 0, 0))
	for e in [a, b, far]:
		e.aggro_range = 0.0
		e.max_health = 3000.0
		e.health = 3000.0
	await get_tree().process_frame

	# Kindling: burning enemies take 50% more, and the fire jumps to the neighbour.
	_wear("kindling", 0)
	expect("a hit on a cold enemy is plain", is_equal_approx(ItemEffects.outgoing_multiplier(player, a), 1.0))
	a.apply_burn(5.0, 4.0)
	expect("a hit on a burning enemy does 50% more", is_equal_approx(ItemEffects.outgoing_multiplier(player, a), 1.5))
	var hit: Dictionary = Combat.resolve(player, a, 10.0, Combat.DamageType.PHYSICAL, false, 1.0, true)
	a.receive(hit, player.global_position)
	ItemEffects.on_dealt_hit(player, a, hit)
	expect("the fire jumps to the enemy next to it", b.is_burning() and not far.is_burning())
	a.stop_burning()
	b.stop_burning()

	# Juggler's: an enemy thrown into the air takes 80% more and is knocked back up.
	_wear("juggler", 0)
	a.ragdoll_launch(Vector3(0, 0, 4), 6.0, Vector3(3, 0, 0))
	await get_tree().process_frame
	expect("a thrown enemy is airborne", ItemEffects.is_airborne(a))
	expect("hits on it do 80% more", is_equal_approx(ItemEffects.outgoing_multiplier(player, a), 1.8))
	expect("hits on a grounded enemy do not", is_equal_approx(ItemEffects.outgoing_multiplier(player, far), 1.0))
	await get_tree().create_timer(0.4).timeout   # now on its way down
	expect("it is falling", ItemEffects.is_airborne(a) and a.ragdoll._vy < 0.0)
	ItemEffects.on_dealt_hit(player, a, hit)
	expect("the hit knocks it back up", ItemEffects.is_airborne(a) and a.ragdoll._vy > 3.0)
	await get_tree().create_timer(2.5).timeout

	# Breaker's: stunned or downed enemies are always crit.
	_wear("breaker", 0)
	far.stun_time = 0.0
	expect("a healthy enemy is not a guaranteed crit", not ItemEffects.guaranteed_crit(player, far))
	far.stun_time = 1.0
	expect("a stunned one is", ItemEffects.guaranteed_crit(player, far))
	far.stun_time = 0.0
	far.ragdoll_launch(Vector3(0, 0, 3), 5.0, Vector3(2, 0, 0))
	await get_tree().process_frame
	expect("a knocked-down one is", ItemEffects.guaranteed_crit(player, far))
	await get_tree().create_timer(3.0).timeout

	# Maelstrom: the Greatsword finisher stuns its target and another enemy caught by the slam.
	player.stats.equipment = {}
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "maelstrom", "Greatsword"), false)
	for e in [a, b]:
		e.global_position = player.global_position + (Vector3(0, 0, 1.4) if e == a else Vector3(0.6, 0, 2.0))
		e.stun_time = 0.0
	await get_tree().process_frame
	player.skills.combo_step = 2
	player.skills.start_skill("basic", a, a.global_position)
	var longest: float = 0.0
	var t: float = 0.0
	while t < 1.8:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		longest = maxf(longest, minf(a.stun_time, b.stun_time))
	expect("Maelstrom stuns the Greatsword finisher target and its slam victim for about a second (%.2f)" % longest, longest >= 0.8)
	await get_tree().create_timer(1.5).timeout
	for e in [a, b]:
		e.global_position = Vector3(6, 0, 0) if e == a else Vector3(7.2, 0, 0)
		e.stun_time = 0.0

	# Impaler's and Ramming: the Skewer kick.
	_wear("impaler", 0)
	var before: float = b.health
	ItemEffects.impaler_burst(player, a, Vector3(6, 0, 0))
	expect("an enemy kicked off the blade bursts and hurts the one beside it", b.health < before)

	# Ember-Treaded: the trail sets an enemy standing on it alight.
	_wear("cinder_roll", 1)
	far.global_position = player.global_position + Vector3(0.6, 0, 0)
	far.stop_burning()
	ItemEffects.on_roll_start(player)
	await get_tree().create_timer(0.5).timeout
	expect("an enemy on the embers catches fire", far.is_burning())
	far.global_position = Vector3(-20, 0, 0)
	far.stop_burning()

	# Vaultborn: a Leap landing makes the next Power Strike free.
	_wear("vaultborn", 1)
	player.stats.mana = 0.0
	player.stats.cooldowns["power"] = 5.0
	expect("without a Leap, Power Strike is not available", not player.stats.can_use("power"))
	ItemEffects.on_leap_land(player)
	expect("after a Leap landing it is, with no mana and no cooldown", player.stats.can_use("power") and player.stats.vault_time > 0.0)
	a.global_position = player.global_position + Vector3(1.4, 0, 0)
	player.skills.start_skill("power", a, null)
	expect("using it spends nothing", player.stats.mana == 0.0 and float(player.stats.cooldowns["power"]) == 5.0 and player.stats.vault_time == 0.0)
	await get_tree().create_timer(2.0).timeout
	player.skills.cancel_action()
	player.stats.mana = player.stats.max_mana

	# Smouldering: being hit sets the enemies close to you alight.
	_wear("smouldering", 1)
	a.global_position = player.global_position + Vector3(2.0, 0, 0)
	far.global_position = Vector3(-20, 0, 0)
	a.stop_burning()
	ItemEffects.on_player_hurt(player)
	expect("a close enemy catches fire when you are hit, a far one does not", a.is_burning() and not far.is_burning())
	a.stop_burning()

	# Wildfire: a Fireball that catches three or more.
	_wear("wildfire", 2)
	player.stats.cooldowns["fireball"] = 5.5
	ItemEffects.on_fireball_blast(player, 2)
	expect("two enemies in the blast earn nothing", float(player.stats.cooldowns["fireball"]) == 5.5)
	ItemEffects.on_fireball_blast(player, 3)
	expect("three earn 3 seconds off the cooldown", is_equal_approx(float(player.stats.cooldowns["fireball"]), 2.5))

	# Virtuoso: different skills in a row stack; repeating drops them.
	_wear("virtuoso", 2)
	player.stats.chain_stacks = 0
	player.stats.chain_time = 0.0
	player.stats.chain_last = ""
	ItemEffects.on_skill_start(player, "power")
	expect("the first skill starts the streak with no bonus", player.stats.chain_stacks == 0 and is_equal_approx(ItemEffects.virtuoso_multiplier(player), 1.0))
	ItemEffects.on_skill_start(player, "basic")
	expect("a different second skill gives +20%", player.stats.chain_stacks == 1 and is_equal_approx(ItemEffects.virtuoso_multiplier(player), 1.2))
	ItemEffects.on_skill_start(player, "fireball")
	ItemEffects.on_skill_start(player, "skewer")
	ItemEffects.on_skill_start(player, "leap")
	expect("it stops at three stacks (+60%)", player.stats.chain_stacks == 3 and is_equal_approx(ItemEffects.virtuoso_multiplier(player), 1.6))
	ItemEffects.on_skill_start(player, "leap")
	expect("repeating a skill drops them", player.stats.chain_stacks == 0)
	ItemEffects.on_skill_start(player, "power")
	ItemEffects.on_skill_start(player, "basic")
	player.stats.chain_time = 0.0
	player._physics_process(0.016)
	expect("the streak ends when its time runs out", player.stats.chain_stacks == 0)

	# Quakebound: kills charge the ultimate.
	_wear("quaker", 2)
	player.stats.ult_charge = 0.0
	ItemEffects.on_kill(player, far)
	expect("a kill charges 4% of Earthshatter", is_equal_approx(player.stats.ult_charge, PlayerStats.MAX_ULT_CHARGE * 0.04))

	# Pyrebound: a burning enemy that dies explodes.
	_wear("pyre", 2)
	a.global_position = Vector3(6, 0, 3)
	b.global_position = Vector3(7.0, 0, 3)
	a.stop_burning()
	b.stop_burning()
	a.health = 3000.0
	b.health = 3000.0
	var b_before: float = b.health
	ItemEffects.on_kill(player, a)
	expect("a cold kill explodes nothing", b.health == b_before and not b.is_burning())
	a.apply_burn(5.0, 4.0)
	ItemEffects.on_kill(player, a)
	expect("a burning kill goes up: the neighbour is hurt and set alight", b.health < b_before and b.is_burning())

	player.stats.equipment = saved
	player.armor = player.stats.base_armor + player.stats.armor_stat("armor", 0.0)
	player.stats.cooldowns.clear()
	player.stats.ult_charge = PlayerStats.MAX_ULT_CHARGE
	for node in get_tree().get_nodes_in_group("enemies"):
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
		var drop: LootDrop = game.director.drop_item(Vector3(0, 0, -6), Items.make(Items.Slot.WEAPON if i % 2 == 0 else Items.Slot.ARMOR, [Items.Rarity.COMMON, Items.Rarity.RARE][i % 2], 1, ""))
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
