extends DevSuite
## One-hit barrels, crates and urns, breaking them by dodge-rolling through, and treasure chests (loot once, never twice).

func _test_barrels_chests() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	for kind in ["barrel", "crate", "urn"]:
		var stats: Dictionary = Destructible.STATS.get(kind, {})
		expect("%s: hp 1, one hit, breaks when rolled" % kind, not stats.is_empty() and float(stats["hp"]) <= 1.0 and bool(stats["one_hit"]) and bool(stats["roll_break"]))
	expect("carts, gravestones, braziers and nests are not one-hit or roll-broken", ["wrecked_cart", "gravestone", "brazier", "nest"].all(
		func(k: String) -> bool: return not bool(Destructible.STATS[k].get("one_hit", false)) and not bool(Destructible.STATS[k].get("roll_break", false))))

	var lane: Vector3 = await _own_lane(20.0, 8.0)
	# One minimal hit breaks a barrel; a gravestone still needs several.
	var origin: Vector3 = lane + Vector3(12, 0, -3)
	var barrel: Destructible = arena.place_prop("barrel", origin, 0.0, 1.0) as Destructible
	expect("a barrel breaks on one minimal hit", barrel != null and barrel.hit(0.1, Vector3.RIGHT) and barrel.broken)
	var grave: Destructible = arena.place_prop("gravestone", origin + Vector3(4, 0, 0), 0.0, 1.3) as Destructible
	expect("a gravestone still needs several hits", not grave.hit(0.1, Vector3.RIGHT) and not grave.hit(1.0, Vector3.RIGHT) and not grave.broken)
	grave.hit(999.0, Vector3.RIGHT)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()

	# Chests: opening drops loot once; a second open (or a second interact) gives nothing more.
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame
	var chest := Chest.new()
	get_tree().current_scene.add_child(chest)
	chest.global_position = lane + Vector3(15, 0, 0)
	expect("a closed chest is a click target", Chest.near(get_tree(), chest.global_position + Vector3(0, 0, 0.2), 0.35) == chest)
	player.global_position = chest.global_position + Vector3(-4, 0, 0)
	expect("it cannot be opened from afar", not chest.in_reach(player))
	player.chest_target = chest
	var seconds: float = 0.0
	while seconds < 8.0 and not chest.opened:
		await get_tree().physics_frame
		seconds += 1.0 / 60.0
	expect("the hero walks up and opens a chest sent for (%.1f s)" % seconds, chest.opened and player.chest_target == null)
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.3).timeout
	var drops: int = get_tree().get_nodes_in_group("loot").size()
	expect("it dropped one to three items (%d)" % drops, drops >= 1 and drops <= 3)
	expect("an opened chest is no longer a target", Chest.near(get_tree(), chest.global_position, 1.0) == null)
	expect("opening again does nothing", not chest.open())
	await get_tree().create_timer(0.3).timeout
	expect("no second helping (%d)" % get_tree().get_nodes_in_group("loot").size(), get_tree().get_nodes_in_group("loot").size() == drops)
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	chest.queue_free()
	await get_tree().process_frame

	# A roll through a barrel breaks it, throws pieces along the roll, and is not stopped by it. A gravestone beside the line stays.
	var start: Vector3 = lane
	var rolled_barrel: Destructible = arena.place_prop("barrel", start + Vector3(2.5, 0, 0), 0.0, 1.0) as Destructible
	var stone: Destructible = arena.place_prop("gravestone", start + Vector3(2.5, 0, 3.0), 0.0, 1.3) as Destructible
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.global_position = start
	player.reset_physics_interpolation()
	player.stats.stamina = player.stats.max_stamina
	player.stats.cooldowns["dodge"] = 0.0
	var rolled_broke: Array[bool] = [false]
	rolled_barrel.destroyed.connect(func(_prop: Destructible) -> void: rolled_broke[0] = true)
	player.movement.try_roll(start + Vector3(8, 0, 0))
	var frames: int = 0
	while player.movement.rolling and frames < 120:
		await get_tree().physics_frame
		frames += 1
	expect("a roll through a barrel breaks it", rolled_broke[0])
	expect("the roll is not stopped by the barrel (moved %.1f m)" % (player.global_position.x - start.x), player.global_position.x - start.x > 3.5)
	expect("a gravestone off the line is untouched", is_instance_valid(stone) and not stone.broken)
	var flew_along: int = 0
	for node in get_tree().get_nodes_in_group("debris"):
		var chunk := node as DebrisChunk
		if chunk != null and chunk.velocity.x > 1.0:
			flew_along += 1
	expect("pieces fly along the roll direction (%d)" % flew_along, flew_along >= 8)
	stone.hit(999.0, Vector3.RIGHT)
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
