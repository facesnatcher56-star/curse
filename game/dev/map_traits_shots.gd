extends SceneTree
## Map-mode trait tooltips in the real HUD (issue #82): the full HUD with the inventory open, a bag item with a trait hovered (mouse) and focused
## (controller), at 1080p on screen 1. Run windowed, not headless:
##   godot --path . --script res://game/dev/map_traits_shots.gd -- <output dir>
## Images need a person's eyes; nothing is asserted here.

var _out: String = "res://docs/screenshots/mapmode_loot"

func _init() -> void:
	call_deferred("run")

func settle() -> void:
	await create_timer(0.35, true).timeout
	await RenderingServer.frame_post_draw

func shot(tag: String) -> void:
	await settle()
	var path: String = ProjectSettings.globalize_path(_out).path_join(tag + ".png")
	root.get_texture().get_image().save_png(path)
	print("MM_SHOT ", path)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			_out = arg
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	TownState.persist = false
	TownState.reset()
	var game := load("res://game/main.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await create_timer(1.0).timeout
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	for body in PartyManager.current().bodies.values():
		body.set_physics_process(false)
	var screen: int = mini(1, DisplayServer.get_screen_count() - 1)
	root.current_screen = screen
	root.borderless = true
	root.size = Vector2i(1920, 1080)
	root.position = DisplayServer.screen_get_position(screen) + (DisplayServer.screen_get_size(screen) - Vector2i(1920, 1080)).max(Vector2i.ZERO) / 2
	GameSettings.ui_size = 1.0
	GameSettings.apply_ui_scale()
	var mm := MapMode.new()   # the flag: traits and their tooltip lines are on
	game.add_child(mm)
	var hero: Player = game.player
	hero.stats.bag.clear()
	# What the hero wears, and what lies in the bag: a trait on a plain base, a magic base with a new modifier, a rare, a gap base.
	hero.stats.equipment.clear()
	hero.stats.wear(Items.Slot.WEAPON, Items.build(ItemDb.get_def("longsword"), 3, Items.Rarity.NORMAL))   # worn without the requirement check
	hero.stats.wear(Items.Slot.ARMOR, Items.build(ItemDb.get_def("leather_jerkin"), 3, Items.Rarity.NORMAL))
	hero.stats.wear(Items.Slot.BOOTS, Items.build(ItemDb.get_def("leather_boots"), 2, Items.Rarity.NORMAL))
	var bag_items: Array[Dictionary] = [
		Items.build(ItemDb.get_def("axe_1h"), 3, Items.Rarity.NORMAL),
		Items.build(ItemDb.get_def("falchion"), 3, Items.Rarity.MAGIC, ["mm_auto_1"], "", {"mm_auto_1": 6.0}),
		Items.build(ItemDb.get_def("leather_boots"), 3, Items.Rarity.MAGIC, ["mm_heal_1"], "", {"mm_heal_1": 12.0}),
		Items.build(ItemDb.get_def("axe_2h"), 3, Items.Rarity.NORMAL),
		Items.build(ItemDb.get_def("buckler"), 3, Items.Rarity.NORMAL),
		Items.build(ItemDb.get_def("charm"), 3, Items.Rarity.MAGIC, ["mm_charge_kill_1"], "", {"mm_charge_kill_1": 3.0}),
		Items.build(ItemDb.get_def("iron_helm"), 5, Items.Rarity.NORMAL),
		Items.build(ItemDb.get_def("signet"), 3, Items.Rarity.MAGIC, ["mm_marked_1"], "", {"mm_marked_1": 8.0}),
	]
	for item in bag_items:
		hero.stats.add_to_bag(item)
	PartyManager.current().select("hero")
	game.hud._open_character()
	await shot("01_inventory_open")
	var tiles: Array = game.hud.character_panel.find_children("*", "ItemTile", true, false)
	print("MM_TILES ", tiles.size())
	for i in [0, 1, 2, 3, 5]:
		if i < tiles.size():
			var tile: ItemTile = tiles[i]
			tile.mouse_entered.emit()
			await shot("02_hover_%d_%s" % [i, String(tile.item["base"]).replace(" ", "_").to_lower()])
			tile.mouse_exited.emit()
			await settle()
	Gamepad.active = true
	for i in [1, 3, 6]:
		if i < tiles.size():
			var tile2: ItemTile = tiles[i]
			tile2.grab_focus()
			await shot("03_focus_%d_%s" % [i, String(tile2.item["base"]).replace(" ", "_").to_lower()])
	Gamepad.active = false
	print("MM SHOTS COMPLETE (review required)")
	quit()
