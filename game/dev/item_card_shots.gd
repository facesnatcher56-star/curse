extends SceneTree
## 1080p shots of every item-card kind on the real HUD: ground loot cards, bag and worn hover cards, a controller-focused card, the trader and
## the map-mode loot summary. Run (a `before_`/`after_` prefix names the set):
##   godot --path . --screen 1 -s res://game/dev/item_card_shots.gd --resolution 1920x1080 -- --mapmode --prefix=after_ --shots=<abs dir>
##   godot --path . --screen 1 -s res://game/dev/item_card_shots.gd --resolution 1920x1080 -- --town --prefix=after_ --shots=<abs dir>

var _main: Node
var _town: TownScene
var _frames := 0
var _step := 0
var _wait := 0
var _dir := ""
var _prefix := ""
var _town_mode := false
var _drops: Array[LootDrop] = []
var _items: Dictionary = {}
var _last: ItemTile

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
		elif arg.begins_with("--prefix="):
			_prefix = arg.substr(9)
		elif arg == "--town":
			_town_mode = true
	DirAccess.make_dir_recursive_absolute(_dir)
	TownState.persist = false
	if not _town_mode:
		_main = (load("res://game/main.tscn") as PackedScene).instantiate()
		get_root().add_child(_main)
		current_scene = _main

func _save(shot: String) -> void:
	var image := get_root().get_texture().get_image()
	var path := _dir.path_join(_prefix + shot + ".png")
	image.save_png(path)
	print("CARD_SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])

func _make_items() -> void:
	_items = {
		"normal": Items.build(ItemDb.get_def("greatsword"), 3, Items.Rarity.NORMAL),
		"magic": Items.make(Items.Slot.HELM, Items.Rarity.MAGIC, 8),
		"rare": Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 6, "Longsword"),
		"unique": Items.make(Items.Slot.AMULET, Items.Rarity.UNIQUE, 10),
		"set": Items.make(Items.Slot.ARMOR, Items.Rarity.SET, 10),
		"unmet": Items.build(ItemDb.get_def("greatsword"), 60, Items.Rarity.RARE, Items.roll_mods(ItemDb.get_def("greatsword"), 60, Items.Rarity.RARE)),
		"long": Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 6, "Longsword"),
	}
	_items["long"]["name"] = "Gravecaller's Wretched Warhammer of the Eternal Sunless Deep Vigil"

func _bag_tile(hud: Hud, item: Dictionary) -> ItemTile:
	for node in hud.character_panel.find_children("*", "Control", true, false):
		if node is ItemTile and String((node as ItemTile).item.get("name", "")) == String(item["name"]) and (node as ItemTile).get("grid") != null:
			return node
	return null

func _hover(tile: ItemTile) -> void:
	for holder in get_root().find_children("ItemDetails", "Control", true, false):
		(holder as Control).visible = false
	if is_instance_valid(_last):
		_last.mouse_exited.emit()
	_last = tile
	if tile == null:
		print("CARD_SHOT_NO_TILE")
	if tile != null:
		var motion := InputEventMouseMotion.new()
		motion.position = tile.get_global_rect().get_center()
		motion.global_position = motion.position
		get_root().push_input(motion, true)
		tile.mouse_entered.emit()

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _town_mode:
		return _process_town()
	if _frames < 300 or _main.player == null:
		return false
	if MapMode.current != null and MapMode.current.overlay != null and MapMode.current.overlay.is_open():
		MapMode.current.overlay.close()
	if _wait > 0:
		_wait -= 1
		return false
	var player: Player = _main.player
	var hud: Hud = _main.hud
	var camera: Camera3D = get_root().get_camera_3d()
	if _step == 0:
		TownState.dev_set_hero_level(30)
		player.stats.refresh()
		_make_items()
		player.stats.equip(Items.build(ItemDb.get_def("longsword"), 3, Items.Rarity.NORMAL))
		var at: Vector3 = player.global_position
		var i := 0
		for key in ["normal", "rare", "unique", "unmet"]:
			var spot: Vector3 = at + Vector3(-3.0 + i * 2.0, 0, 3.6)
			var drop: LootDrop = _main.director.drop_item(spot, _items[key])
			drop._end = spot
			_drops.append(drop)
			i += 1
		_wait = 120
	elif _step >= 1 and _step <= 4:
		if _step > 1:
			_save("ground_" + ["normal", "rare", "unique", "unmet"][_step - 2])
		if _step <= 4 and _step - 1 < _drops.size():
			hud.mouse_override = camera.unproject_position(_drops[_step - 1].global_position + Vector3(0, 0.4, 0))
		_wait = 30
	elif _step == 5:
		_save("ground_unmet")
		hud.mouse_override = Vector2(-1, -1)
		for d in _drops:
			d.queue_free()
		for key in ["normal", "magic", "rare", "unique", "set", "unmet", "long"]:
			player.stats.add_to_bag(_items[key])
		hud._open_character()
		_wait = 40
	elif _step >= 6 and _step <= 12:
		var key: String = ["normal", "magic", "rare", "unique", "set", "unmet", "long"][_step - 6]
		if _step > 6:
			_save("bag_" + ["normal", "magic", "rare", "unique", "set", "unmet", "long"][_step - 7])
		var tile: ItemTile = _bag_tile(hud, _items[key])
		_hover(tile)
		_wait = 20
	elif _step == 13:
		_save("bag_long")
		Gamepad.active = true
		for holder in get_root().find_children("ItemDetails", "Control", true, false):
			(holder as Control).visible = false
		var tile: ItemTile = _bag_tile(hud, _items["rare"])
		if tile != null:
			tile.grab_focus()
			tile.focus_entered.emit()
		_wait = 30
	elif _step == 14:
		_save("controller_focus")
		Gamepad.active = false
		hud.close_character()
		var item: Dictionary = MapModeLegendaries.item("gravecaller_maul")
		var tally := {"gold": 120, "health": 1, "mana": 0, "items": [_items["rare"], _items["unique"], item, _items["normal"]]}
		hud.loot_cards.show_summary("Sunken Crypt", tally, HudLootCards.summary_rows(tally, [player]), 60.0)
		_wait = 30
	elif _step == 15:
		_save("summary")
		var legend: Dictionary = MapModeLegendaries.item("gravecaller_maul")
		if legend.is_empty():
			legend = _items["unique"]
		_items["legend"] = legend
		hud.loot_cards.hide_summary()
		player.stats.add_to_bag(legend)
		hud._open_character()
		_wait = 40
	elif _step == 16:
		var tile: ItemTile = _bag_tile(hud, _items["legend"])
		_hover(tile)
		_wait = 20
	elif _step == 17:
		_save("bag_legendary")
		print("CARD_SHOTS DONE")
		quit(0)
		return true
	_step += 1
	return false

func _process_town() -> bool:
	if _frames == 10:
		TownState.reset()
		_town = TownScene.new()
		_town.with_road = false
		get_root().add_child(_town)
		current_scene = _town
	if _town == null or _frames < 200:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step == 0:
		TownState.gold = 5000
		_town.panel.open_npc("marlow")
		_wait = 40
	elif _step == 1:
		_save("trader")
		var tiles: Array[Node] = _town.panel.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n is ItemTile)
		if not tiles.is_empty():
			(tiles[0] as ItemTile).mouse_entered.emit()
		_wait = 25
	elif _step == 2:
		_save("trader_hover")
		print("CARD_SHOTS DONE")
		quit(0)
		return true
	_step += 1
	return false
