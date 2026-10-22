extends DevSuite
## The walking game (issue #112 a): Play is the Sunken Way, and map mode's combat and loot rules hold with map mode off: powers start empty,
## each member charges only from his own damage, the first champion drops a legendary, nothing is auto-equipped, a shrine is used by walking
## onto it.

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _test_walk_game() -> void:
	expect("map mode is off", not MapMode.active)
	# --- Play starts in the Sunken Way ---------------------------------------------------------------------------------------------
	var main_script: GDScript = load("res://game/main.gd")
	expect("Menu -> Play (no flag) builds the Sunken Way", main_script.call("location_kind", PackedStringArray()) == "sunken")
	expect("`--mapmode` is the same dungeon on the node map", main_script.call("location_kind", PackedStringArray(["--mapmode"])) == "sunken")
	expect("`--crypt01` is still the Crypt, `--dungeon` the old test dungeon",
		main_script.call("location_kind", PackedStringArray(["--crypt01"])) == "crypt01" and main_script.call("location_kind", PackedStringArray(["--dungeon"])) == "testdungeon")
	var sunken := MapModeDungeon.new()
	expect("the Sunken Way is MapModeDungeon", sunken.zone_title() == "The Sunken Way")
	sunken.free()

	# --- Powers start empty at the start of a run ----------------------------------------------------------------------------------
	var cutter: Player = game.companion
	var learned: Array[String] = []
	for id in PowerController.LIVE:
		if PowerDb.hero_rank(id, player.member_id) > 0:
			learned.append(id)
	player.powers.gain(1.0e9)
	player.stats.gain_brutal_charge(1.0e9)
	MapMode.start_run([player, cutter])
	var all_empty: bool = player.stats.ult_fraction("brutal_attack") < 1.0 or player.stats.is_ranged()
	for id in learned:
		all_empty = all_empty and player.powers.fraction(id) < 1.0
	expect("a walking run starts with Brutal Attack and every learned power empty (%d powers)" % learned.size(), all_empty)

	# --- Each member charges from his own damage only ------------------------------------------------------------------------------
	var cutter_before: float = cutter.stats.ult_fraction("brutal_attack") if not cutter.stats.is_ranged() else (cutter.bow.reload_remaining if cutter.bow != null else 0.0)
	var hero_before: float = player.stats.ult_fraction("brutal_attack")
	player.on_party_damage(50.0, "basic")
	var cutter_after: float = cutter.stats.ult_fraction("brutal_attack") if not cutter.stats.is_ranged() else (cutter.bow.reload_remaining if cutter.bow != null else 0.0)
	expect("the warrior's damage charges his own powers (%.3f -> %.3f)" % [hero_before, player.stats.ult_fraction("brutal_attack")], player.stats.is_ranged() or player.stats.ult_fraction("brutal_attack") > hero_before)
	expect("and not the Cutter's", is_equal_approx(cutter_after, cutter_before))

	# --- Nothing is auto-equipped --------------------------------------------------------------------------------------------------
	var worn: Dictionary = player.stats.equipment.duplicate()
	player.stats.equipment.erase(Items.Slot.HELM)
	var helm: Dictionary = Items.build(ItemDb.get_def("leather_cap"), 1, Items.Rarity.NORMAL, [])
	expect("a pickup that fits an empty slot is not put on (it goes to the bag)", player.stats.fits_empty_slot(helm) and not player.stats.takes_empty_slot(helm))
	player.stats.equipment = worn
	player.stats.refresh()

	# --- The first champion drops a legendary, a later one does not ----------------------------------------------------------------
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await _frames(2)
	MapModeLegendaries.reset_run()
	var legend_n: Array[int] = []
	for i in 2:
		var z: Enemy = _spawn_enemy(Nav.snap(player, player.global_position + Vector3(14.0 + 2.0 * i, 0.0, 4.0)), "zombie", 2.0)
		z.aggro_range = 0.0
		z.alert_delay = 999.0
		Champion.attach(z, "fast")
		z.credit_hero()
		z._apply_damage(z.max_health + 10.0)
		await _frames(10)
		var n: int = 0
		for node in get_tree().get_nodes_in_group("loot"):
			var drop := node as LootDrop
			if drop != null and not drop.is_queued_for_deletion() and MapModeLegendaries.id_of(drop.item) != "":
				n += 1
		legend_n.append(n)
	expect("the first champion of a walking run drops a legendary (%d)" % legend_n[0], legend_n[0] == 1)
	expect("the second does not (still %d)" % legend_n[1], legend_n[1] == 1)
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("orbs"):
		node.queue_free()

	# --- A shrine is used by walking onto it ---------------------------------------------------------------------------------------
	var shrine := Shrine.new()
	game.add_child(shrine)
	shrine.global_position = player.global_position + Vector3(8.0, 0.0, 0.0)
	player.health = player.max_health * 0.5
	await _frames(3)
	expect("a shrine farther than its range is not used", not shrine.used and player.health < player.max_health)
	shrine.global_position = player.global_position + Vector3(Shrine.USE_RANGE * 0.5, 0.0, 0.0)
	await _frames(3)
	expect("a party member who steps onto it uses it: the party is restored", shrine.used and player.health >= player.max_health)
	shrine.queue_free()
	await _frames(2)

## Z (issue #112 c): every member goes to pick up the loot near him; a full bag leaves the item; a hit stops the order.
func _drop_at(pos: Vector3, level: int = 2) -> LootDrop:
	var drop: LootDrop = game.director.drop_item(pos, Items.build(ItemDb.get_def("leather_cap"), level, Items.Rarity.NORMAL))
	return drop

func _test_pickup_nearby() -> void:
	expect("the Pick up nearby loot action exists on Z and is in the key-binding list", InputMap.has_action("pickup_nearby")
		and InputMap.action_get_events("pickup_nearby").any(func(e: InputEvent) -> bool: return e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_Z)
		and GameSettings.ACTIONS.any(func(row: Array) -> bool: return row[0] == "pickup_nearby"))
	var cutter: Player = game.companion
	var cutter_was_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = false
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await _frames(2)
	var bag_before: Array = PartyManager.current().backpack.duplicate(true)
	PartyManager.current().backpack = []
	var base: Vector3 = player.global_position
	cutter.global_position = Nav.snap(cutter, base + Vector3(0.0, 0.0, 9.0))
	var near_hero: Array[LootDrop] = [_drop_at(Nav.snap(player, base + Vector3(3.0, 0.0, 0.0))), _drop_at(Nav.snap(player, base + Vector3(-4.0, 0.0, 1.0)))]
	var near_cutter: LootDrop = _drop_at(Nav.snap(cutter, cutter.global_position + Vector3(2.5, 0.0, 1.0)))
	var far: LootDrop = _drop_at(Nav.snap(player, base + Vector3(Player.PICKUP_NEARBY_RADIUS + 10.0, 0.0, -6.0)))
	await _frames(60)   # they land
	var ordered: int = Player.order_pickup_nearby(PartyManager.current().living())
	expect("Z orders the 3 items near the members and not the far one (%d)" % ordered, ordered == 3)
	expect("each member goes for the loot nearest him: the hero for his two, the Cutter for hers", near_hero.has(player.pickup_target) and player.pickup_queue.size() == 1
		and cutter.pickup_target == near_cutter and player.collecting and cutter.collecting)
	var frames: int = 0
	while frames < 900 and (is_instance_valid(near_hero[0]) or is_instance_valid(near_hero[1]) or is_instance_valid(near_cutter)):
		await get_tree().physics_frame
		frames += 1
	expect("every member walked to his items and took them (%d frames)" % frames, not is_instance_valid(near_hero[0]) and not is_instance_valid(near_hero[1]) and not is_instance_valid(near_cutter))
	expect("they are in the party's bag (%d items), the far one still lies there" % PartyManager.current().backpack.size(), PartyManager.current().backpack.size() == 3 and is_instance_valid(far) and not far.is_queued_for_deletion())
	expect("the order is over", not player.collecting and not cutter.collecting and player.pickup_target == null and cutter.pickup_target == null)
	# A full bag: the item stays on the ground and the order still ends.
	var filler: Array = []
	while true:
		var candidate: Array = filler.duplicate()
		candidate.append(Items.build(ItemDb.get_def("leather_cap"), 1, Items.Rarity.NORMAL))
		if not PlayerStats.BagGrid.can_hold(candidate):
			break
		filler = candidate
	PartyManager.current().backpack.assign(filler)
	PlayerStats.BagGrid.arrange(PartyManager.current().backpack)
	var kept: LootDrop = _drop_at(Nav.snap(player, player.global_position + Vector3(2.0, 0.0, 0.0)))
	await _frames(60)
	Player.order_pickup_nearby([player])
	frames = 0
	while frames < 600 and player.collecting:
		await get_tree().physics_frame
		frames += 1
	expect("with a full bag the item stays on the ground (order over after %d frames)" % frames, is_instance_valid(kept) and not kept.is_queued_for_deletion() and not player.collecting)
	PartyManager.current().backpack = []
	# A hit ends the order: he stops and fights.
	var other: LootDrop = _drop_at(Nav.snap(player, player.global_position + Vector3(-8.0, 0.0, 0.0)))
	await _frames(60)
	Player.order_pickup_nearby([player])
	expect("setup: he is on his way to the item", player.collecting and player.pickup_target != null)
	player._on_hurt({"damage": 1.0, "outcome": Combat.Outcome.HIT}, player.global_position)
	expect("a member who is hit stops picking up", not player.collecting and player.pickup_target == null and player.pickup_queue.is_empty())
	for node in [far, kept, other]:
		if is_instance_valid(node):
			node.queue_free()
	PartyManager.current().backpack.assign(bag_before)
	cutter.testing_disabled = cutter_was_disabled
	await _frames(2)
