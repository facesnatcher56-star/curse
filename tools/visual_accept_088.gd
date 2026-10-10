extends SceneTree
## Scratch visual acceptance (task visual-acceptance-combat-088): death plate, offscreen spitter chevron, rare/unique ground glow on the
## Crypt Road at default zoom. Real window: GODOT_HEADLESS= tools/run_godot.sh LOG 150 -- --script res://tools/visual_accept_088.gd -- --out=DIR --w=1280 --h=720

var out_dir := ""
var res := Vector2i(1280, 720)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		if a.begins_with("--w="): res.x = int(a.substr(4))
		if a.begins_with("--h="): res.y = int(a.substr(4))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func _shot(n: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s_%dx%d.png" % [out_dir, n, res.x, res.y])
	print("saved ", n, " ", root.get_viewport().get_texture().get_image().get_size())

func _run() -> void:
	DisplayServer.window_set_size(res)
	root.size = res
	for i in 5: await process_frame
	print("window=", DisplayServer.window_get_size(), " viewport=", root.get_viewport().get_visible_rect().size)
	TownState.reset()
	var town := TownScene.new()
	root.add_child(town)
	current_scene = town
	for i in 10: await process_frame
	var z: float = CryptRoad.EXIT_Z - 40.0
	town.player.global_position = town.crypt.at(town.crypt.road_centre_x(z), z)
	for i in 30: await process_frame
	var hud: Hud = town.combat_hud
	var player: Player = town.player
	var pp: Vector3 = player.global_position
	# Loot: common, rare, unique beside each other, ahead of the hero.
	var director = town.director if "director" in town else null
	print("director=", director)
	var rar := [Items.Rarity.COMMON, Items.Rarity.RARE, Items.Rarity.UNIQUE]
	var drops: Array = []
	for i in 3:
		var item := Items.make(Items.Slot.WEAPON, rar[i], 1)
		var d: LootDrop = director.drop_item(pp + Vector3(-2.2 + i * 2.2, 0, -3.0), item)
		drops.append(d)
	for i in 60: await process_frame
	await _shot("loot_three")
	# Spitters.
	for n in get_nodes_in_group("enemies"): (n as Node).queue_free()
	await process_frame
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var sp: Enemy = director.spawn_enemy(pp + Vector3(0, 0, -50), "spitter", 1.0)
	await process_frame
	var sb: SpitterBehavior = sp.behavior as SpitterBehavior
	var dirs := {"east": Vector3(40, 0, 0), "north_far": Vector3(0, 0, -50), "behind": Vector3(0, 0, 40), "nearedge_w": Vector3(-16, 0, 2)}
	for k in dirs:
		sp.global_position = pp + dirs[k]
		sb._begin_windup()
		await process_frame
		print(k, " warnings=", hud.ranged_warnings(cam, Vector2(root.size)).size())
		await _shot("chevron_" + k)
	sb.on_interrupted()
	await _shot("chevron_cancelled")
	for n in get_nodes_in_group("enemies"): (n as Node).queue_free()
	# Death plate.
	player.dead = true
	town.hud.show_banner("You were dragged back\nTaunt goes here", 4.0)
	await _shot("death_plate")
	quit(0)
