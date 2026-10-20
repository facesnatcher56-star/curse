extends SceneTree
## 1080p shots of map mode's loot rewards in The Sunken Way, on the real HUD (`-- --mapmode`): every chest tier closed and open, and the reward
## screen after a clear (1 item, 6 items, a hoard with a legendary, every verdict, inventory full, controller focus). Run (second monitor):
##   godot --path . --screen 1 -s res://game/dev/mm_rewards_shots.gd --resolution 1920x1080 -- --mapmode --shots=<abs dir> [--only=a,b]
## The scenes use only what exists before and after the redesign (chest open, tally, show_summary), so the same script makes both sets.

var _main: Node
var _frames := 0
var _dir := ""
var _only: PackedStringArray = []
var _started := false
var _hero_pos := Vector3.ZERO
var _spawned: Array[Chest] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(_dir)
	TownState.persist = false
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main

func _save(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var path := _dir.path_join(shot + ".png")
	image.save_png(path)
	print("MMREWARDS_SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _started or _frames < 240 or _main.player == null or MapMode.current == null or MapMode.current.state != MapMode.State.MAP:
		return false
	_started = true
	_run()
	return false

func _m() -> MapMode:
	return MapMode.current

func _hero() -> Player:
	return _main.player

func _pos(dx: float, dz: float) -> Vector3:
	return Nav.snap(_hero(), _hero_pos + Vector3(dx, 0.0, dz))

func _clear_ground() -> void:
	for node in get_nodes_in_group("loot"):
		node.queue_free()
	for node in get_nodes_in_group("orbs"):
		node.queue_free()
	for node in get_nodes_in_group("chests"):
		node.queue_free()
	for chest in _spawned:
		if is_instance_valid(chest):
			chest.queue_free()
	_spawned.clear()

func _chest(kind: String, at: Vector3) -> Chest:
	var chest := Chest.create(kind, 12)
	_main.add_child(chest)
	chest.global_position = at
	_spawned.append(chest)
	return chest

func _gear(level: int) -> void:
	TownState.dev_set_hero_level(level)
	_hero().stats.refresh()

## A clear of a `kind` chest: it opens (its own spray); with `items` the random loot is swapped for exactly those. Then the real COLLECT sequence
## runs and the reward screen shows over the reopened map.
func _clear(kind: String, items: Array, node_id: int, shot: String) -> void:
	var m := _m()
	m.overlay.close()
	_clear_ground()
	m._reset_tally()
	m._visit_pos = _hero_pos
	m._visit_kind = "group"
	m._visit_node = node_id
	var chest := _chest(kind, _pos(0.0, -3.4))
	chest.open()
	await _wait(0.5)
	if not items.is_empty():
		for node in get_nodes_in_group("loot"):
			node.queue_free()
		m._reset_tally()
		m.note_pickup("gold", 120)
		var i := 0
		for item in items:
			var spot := _pos(-2.0 + float(i) * 0.9, -2.2)
			_main.director.drop_item(spot, item)
			i += 1
	await _wait(1.8)
	var rows: Array[Dictionary] = HudLootCards.summary_rows(m.loot_tally, [_hero(), m.companion])
	m._collect_rewards()
	if m.hud.loot_cards.has_method("hide_summary"):
		m.hud.loot_cards.hide_summary()
	m.hud.loot_cards.show_summary(String(m.graph.row(node_id).get("name", "Cleared")), m.loot_tally, rows, 120.0, kind)
	m._open_map()
	await _wait(1.6)
	await _save(shot)

func hud_panel() -> MapRewardPanel:
	return _main.hud.loot_cards.reward_panel

func _club(scale_by: float, label: String) -> Dictionary:
	var it: Dictionary = Items.build(ItemDb.get_def("club"), 1, Items.Rarity.NORMAL)
	it["stats"] = (it["stats"] as Dictionary).duplicate(true)
	it["stats"]["min"] = float(it["stats"]["min"]) * scale_by
	it["stats"]["max"] = float(it["stats"]["max"]) * scale_by
	it["name"] = label
	return it

## The warrior wears a weak club and an unbeatable helm, the Cutter has no helm: the verdicts of a clear are then known.
func _arrange_gear() -> void:
	var hero := _hero()
	var cutter: Player = _m().companion
	hero.stats.bag.clear()
	hero.stats.equipment[Items.Slot.WEAPON] = _club(1.0, "Weak club")
	var helm: Dictionary = Items.build(ItemDb.get_def("iron_helm"), 1, Items.Rarity.NORMAL)
	helm["stats"] = {"armor": 9999}
	helm["name"] = "Unbeatable helm"
	hero.stats.equipment[Items.Slot.HELM] = helm
	cutter.stats.equipment.erase(Items.Slot.HELM)
	hero.stats.refresh()
	cutter.stats.refresh()

func _legendary(id: String) -> Dictionary:
	return MapModeLegendaries.item(id)

func _run() -> void:
	var m := _m()
	var hero := _hero()
	m.overlay.close()
	_gear(20)
	_hero_pos = Nav.snap(hero, hero.global_position)
	# Chest tiers closed and open.
	for kind in ["wooden", "iron", "gilded", "cursed", "hoard"]:
		if _want("chest_" + kind):
			_clear_ground()
			var chest := _chest(kind, _pos(0.0, -3.0))
			await _wait(0.6)
			await _save("chest_%s_closed" % kind)
			chest.open()
			await _wait(0.5)
			await _save("chest_%s_open" % kind)
			await _wait(1.0)
	var rare: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 12, "Longsword")
	var magic: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.MAGIC, 12)
	if _want("one_item"):
		await _clear("wooden", [rare], 5, "reward_1_item")
	if _want("six_items"):
		var six: Array = [rare, magic, Items.make(Items.Slot.HELM, Items.Rarity.MAGIC, 12), Items.make(Items.Slot.BOOTS, Items.Rarity.RARE, 12),
			Items.make(Items.Slot.RING, Items.Rarity.MAGIC, 12), Items.make(Items.Slot.AMULET, Items.Rarity.NORMAL, 12)]
		await _clear("iron", six, 5, "reward_6_items")
	if _want("hoard"):
		await _clear("hoard", [_legendary("gravecaller_maul"), rare, magic, Items.make(Items.Slot.HELM, Items.Rarity.RARE, 12)], 5, "reward_hoard_legendary")
	if _want("verdicts") or _want("controller") or _want("hover"):
		_arrange_gear()
		var club: Dictionary = _club(1.0, "Weak club")
		var verdict_items: Array = [_club(3.0, "Heavy Club of the Pit"), _club(1.0, "Plain club, other maker"), _club(0.5, "Splintered Club"),
			_legendary("gravecaller_maul"), Items.build(ItemDb.get_def("leather_cap"), 1, Items.Rarity.MAGIC)]
		await _clear("gilded", verdict_items, 12, "reward_verdicts")
		if _want("hover") and hud_panel() != null:
			var icon: Control = hud_panel().tiles[0]["icon"]
			icon.mouse_entered.emit()
			await _wait(0.5)
			await _save("reward_hover_card")
			icon.mouse_exited.emit()
		if _want("controller") and hud_panel() != null:
			Gamepad.active = true
			hud_panel()._focus(1)
			await _wait(0.6)
			await _save("reward_controller_focus")
			Gamepad.active = false
	if _want("full"):
		_arrange_gear()
		var filler: Array = []
		var n := 0
		for slot in [Items.Slot.ARMOR, Items.Slot.WEAPON, Items.Slot.HELM, Items.Slot.RING, Items.Slot.AMULET, Items.Slot.RING]:   # big pieces first, then 1x1 ones into the gaps
			while _hero().stats.add_to_bag(Items.make(slot, Items.Rarity.NORMAL, 3)) and n < 400:
				n += 1
		await _clear("iron", [_club(3.0, "Heavy Club of the Pit"), Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 12, "Longsword")], 5, "reward_inventory_full")
	print("MMREWARDS_SHOTS DONE")
	quit(0)
