extends DevSuite
const Grid := preload("res://game/inventory_grid.gd")

func _action(id: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = id
	event.pressed = true
	return event

func _drag(from: Control, destination: Vector2, rotate: bool = false, cancel: bool = false) -> void:
	var origin: Vector2 = from.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = origin
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = origin + Vector2(12, 0)
	motion.relative = Vector2(12, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	if rotate:
		get_viewport().push_input(_action("inventory_rotate"), true)
		await get_tree().process_frame
	if cancel:
		get_viewport().push_input(_action("ui_cancel"), true)
		await get_tree().process_frame
	motion = motion.duplicate()
	motion.position = destination
	motion.relative = destination - origin
	get_viewport().warp_mouse(destination)
	get_viewport().push_input(motion, true)
	press = press.duplicate()
	press.position = destination
	press.pressed = false
	get_viewport().push_input(press, true)
	await get_tree().process_frame

func _test_inventory_grid() -> void:
	TownState.persist = false
	TownState.reset()
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	await get_tree().process_frame
	var stats: PlayerStats = player.stats
	var saved_bag: Array[Dictionary] = stats.bag.duplicate(true)
	var saved_equipment: Dictionary = stats.equipment.duplicate(true)
	var ring: Dictionary = Items.make(Items.Slot.RING, Items.Rarity.MAGIC, 1)
	var sword: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Longsword")
	var great: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Greatsword")
	var armor: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 2, "Leather Jerkin")
	expect("DS2 grid is 5 wide by 13 high with source-backed item footprints", Grid.WIDTH == 5 and Grid.HEIGHT == 13
		and Grid.footprint(sword) == Vector2i(1, 3) and Grid.footprint(great) == Vector2i(1, 4)
		and Grid.footprint(armor) == Vector2i(2, 2) and Grid.footprint(ring) == Vector2i.ONE)
	stats.bag.clear()
	var all_added: bool = true
	for i in 65: all_added = stats.add_to_bag(ring) and all_added
	expect("all 65 cells can hold one-cell jewellery", all_added and stats.bag.size() == 65)
	var before: Array = stats.bag.duplicate(true)
	expect("full bag refuses new loot without discarding any existing item", not stats.add_to_bag(sword) and stats.bag == before)
	# A free weapon slot equips a pickup directly; occupy it so this case actually tests full-bag rejection.
	stats.wear(Items.Slot.WEAPON, great)
	var drop: LootDrop = game.director.drop_item(player.global_position + Vector3(1, 0, 0), sword)
	drop.pick_up(player)
	expect("failed pickup leaves the drop on the ground", not drop.is_queued_for_deletion() and stats.bag == before)
	drop.queue_free()
	stats.wear(Items.Slot.ARMOR, armor)
	expect("taking off gear with no room fails without changing equipment", not stats.unequip_to_bag(Items.Slot.ARMOR) and stats.equipment.has(Items.Slot.ARMOR))
	stats.bag.clear()
	stats.add_to_bag(sword)
	for i in 62: stats.add_to_bag(ring)
	stats.wear(Items.Slot.WEAPON, great)
	expect("swap that displaces a larger item is atomic when full", not stats.equip_from_bag(0)
		and stats.equipment[Items.Slot.WEAPON]["def"] == great["def"] and stats.bag.size() == 63)
	for i in stats.bag.size():
		if stats.bag[i]["bag_cell"] == Vector2i(0, 3):
			stats.bag.remove_at(i)
			break
	expect("same swap succeeds once the displaced weapon fits", stats.equip_from_bag(0)
		and stats.equipment[Items.Slot.WEAPON]["def"] == sword["def"] and Grid.can_hold(stats.bag))
	stats.bag.clear()
	for item in [sword, great, armor, ring]: stats.add_to_bag(item)
	hud._open_character()
	await get_tree().process_frame
	var view: Control = hud.character_panel
	var grid: Control = view.find_child("BackpackGrid", true, false)
	expect("character inventory renders sized icons instead of text cards", grid != null and grid.tiles.size() == 4
		and grid.tiles[0].size.y > grid.tiles[0].size.x * 2)
	expect("drag placement rejects overlaps and out-of-bounds positions", not grid.move_item(0, Vector2i(4, 12))
		and not grid.move_item(0, stats.bag[1]["bag_cell"]) and grid.move_item(0, Vector2i(4, 6)))
	expect("controller select picks up a focused item", grid.handle_input(_action("ui_select"), 0) and grid.moving == 0)
	grid.handle_input(_action("ui_down"), 0)
	grid.handle_input(_action("ui_accept"), 0)
	expect("controller can move and place without a mouse", grid.moving == -1 and stats.bag[0]["bag_cell"] == Vector2i(4, 7))
	grid.handle_input(_action("ui_select"), 0)
	grid.handle_input(_action("ui_up"), 0)
	grid.handle_input(_action("ui_cancel"), 0)
	expect("cancelled move preserves placement", stats.bag[0]["bag_cell"] == Vector2i(4, 7))
	view._sort_bag()
	await get_tree().process_frame
	expect("sort retains every item and fits them in the grid", stats.bag.size() == 4 and Grid.can_hold(stats.bag))
	view = hud.character_panel
	grid = view.find_child("BackpackGrid", true, false)
	if DisplayServer.get_name() == "headless":
		# Headless native drag callbacks use cursor (0,0); validate coordinates directly here.
		var data := {"stats": stats, "index": 0}
		var at: Vector2 = Vector2(4.5, 8.5) * grid.cell_size
		expect("free cell accepts a backpack drop", grid._can_drop_data(at, data))
		grid._drop_data(at, data)
	else:
		await _drag(grid.tiles[0], grid.global_position + Vector2(4.5, 8.5) * grid.cell_size)
	expect("drop places a sized item in the selected cell (real mouse in rendered test)", stats.bag[0]["bag_cell"] == Vector2i(4, 8))
	var ring_index: int = -1
	for i in stats.bag.size():
		if int(stats.bag[i]["slot"]) == Items.Slot.RING: ring_index = i
	var ring_slot: Control = view._doll_tiles[view.DOLL.find(Items.Slot.RING2)]
	await _drag(grid.tiles[ring_index], ring_slot.get_global_rect().get_center())
	expect("dragging to the second ring slot equips exactly that slot", stats.equipment.has(Items.Slot.RING2) and not stats.equipment.has(Items.Slot.RING))
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var path: String = OS.get_environment("TEMP").path_join("curse_ds2_inventory.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("INVENTORY_CAPTURE ", path)
	hud.close_character()
	TownState.stash.clear()
	for i in 70: TownState.stash_item(ring)
	expect("stash deposits never silently erase old items", TownState.stash.size() == 70)
	TownState.reset()
	stats.bag.assign(saved_bag)
	stats.equipment = saved_equipment
	stats.refresh()

func _test_inventory_rotation() -> void:
	TownState.persist = false
	TownState.reset()
	var stats := player.stats
	stats.bag.clear()
	stats.add_to_bag(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Greatsword"))
	hud._open_character()
	for i in 5: await get_tree().process_frame
	var grid: Control = hud.character_panel.find_child("BackpackGrid", true, false)
	expect("rotation has mouse and controller bindings", not InputMap.action_get_events("inventory_rotate").is_empty())
	expect("a vertical weapon can rotate into free horizontal cells", grid.move_item(0, Vector2i(0, 0), true)
		and Grid.footprint(stats.bag[0]) == Vector2i(4, 1) and grid.tiles[0].size.x > grid.tiles[0].size.y * 3)
	var original: Dictionary = stats.bag[0].duplicate(true)
	expect("rotation at the bottom edge fails atomically", grid.move_item(0, Vector2i(0, 12), true)
		and not grid.move_item(0, Vector2i(0, 12), false) and Grid.footprint(stats.bag[0]) == Vector2i(4, 1))
	grid.move_item(0, Vector2i.ZERO, false)
	grid.handle_input(_action("ui_select"), 0)
	grid.handle_input(_action("inventory_rotate"), 0)
	expect("controller rotation previews without mutating the item", grid.move_rotated and not stats.bag[0].get("bag_rotated", false))
	grid.handle_input(_action("ui_cancel"), 0)
	expect("cancel restores orientation as well as placement", not stats.bag[0].get("bag_rotated", false))
	grid.handle_input(_action("ui_select"), 0)
	grid.handle_input(_action("inventory_rotate"), 0)
	grid.handle_input(_action("ui_accept"), 0)
	expect("controller confirm commits the rotated footprint", grid.moving == -1 and stats.bag[0].bag_rotated)
	stats.add_to_bag(Items.make(Items.Slot.RING, Items.Rarity.NORMAL, 1))
	hud._open_character()
	for i in 5: await get_tree().process_frame
	grid = hud.character_panel.find_child("BackpackGrid", true, false)
	grid.move_item(1, Vector2i(0, 1))
	original = stats.bag[0].duplicate(true)
	expect("rotation cannot overlap another item", not grid.move_item(0, Vector2i.ZERO, false) and stats.bag[0] == original)
	grid.move_item(1, Vector2i(4, 12))
	if DisplayServer.get_name() != "headless":
		await _drag(grid.tiles[0], grid.global_position + Vector2(3.5, 5.5) * grid.cell_size, true)
		expect("R during real mouse drag rotates and drops vertically", Grid.footprint(stats.bag[0]) == Vector2i(1, 4)
			and stats.bag[0].bag_cell == Vector2i(3, 5))
		original = stats.bag[0].duplicate(true)
		await _drag(grid.tiles[0], grid.global_position + Vector2(0.5, 9.5) * grid.cell_size, true, true)
		expect("escape cancels a rotated mouse drag without closing inventory", hud.show_gear and stats.bag[0] == original)
	else:
		var data := {"stats": stats, "index": 0, "rotated": false}
		grid._drop_data(Vector2(3.5, 5.5) * grid.cell_size, data)
		expect("rotated drop payload uses requested footprint", Grid.footprint(stats.bag[0]) == Vector2i(1, 4))
	grid.move_item(0, Vector2i.ZERO, true)
	hud.character_panel._sort_bag()
	for i in 5: await get_tree().process_frame
	expect("sorting preserves rotation and all items", stats.bag.size() == 2 and stats.bag[0].bag_rotated and Grid.can_hold(stats.bag))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := OS.get_environment("TEMP").path_join("curse_inventory_rotated.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("ROTATION_CAPTURE ", path)
	TownState.stash_item(stats.bag[0])
	expect("stash does not confuse rotation with item identity", not TownState.stash.back().has("bag_rotated"))
	hud.close_character()
	stats.bag.clear()
	TownState.reset()
