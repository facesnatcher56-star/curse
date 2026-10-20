extends SceneTree
## 1080p shots of the map-mode legendaries on the real HUD (`-- --mapmode`): legendaries lying under their beam with a tooltip, and the character
## screen with them in the bag. Run:
##   godot --path . --screen 1 -s res://game/dev/mm_legend_shots.gd --resolution 1920x1080 -- --mapmode --shots=<abs dir>

var _main: Node
var _frames := 0
var _step := 0
var _wait := 0
var _dir := ""
var _drops: Array[LootDrop] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(_dir)
	TownState.persist = false
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main

func _save(shot: String) -> void:
	var image := get_root().get_texture().get_image()
	var path := _dir.path_join(shot + ".png")
	image.save_png(path)
	print("MMLEGEND_SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _frames < 300 or _main.player == null:
		return false
	if MapMode.current != null and MapMode.current.overlay != null and MapMode.current.overlay.is_open():
		MapMode.current.overlay.close()
	if _wait > 0:
		_wait -= 1
		return false
	var player: Player = _main.player
	var hud: Hud = _main.hud
	match _step:
		0:
			TownState.dev_set_hero_level(30)
			player.stats.refresh()
			var at: Vector3 = player.global_position
			var i := 0
			for id in ["gravecaller_maul", "splitbow", "heros_amulet", "headsmans_due"]:
				var spot: Vector3 = at + Vector3(-2.4 + i * 1.6, 0, 3.4)
				var drop: LootDrop = _main.director.drop_item(spot, MapModeLegendaries.item(id))
				drop._end = spot
				_drops.append(drop)
				i += 1
			var rare_spot: Vector3 = at + Vector3(4.0, 0, 3.4)   # an ordinary rare beside them: no beam
			var rare: LootDrop = _main.director.drop_item(rare_spot, Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 5, "Longsword"))
			rare._end = rare_spot
			_wait = 120
		1:
			_save("legendary_beams")
			var camera: Camera3D = get_root().get_camera_3d()
			hud.mouse_override = camera.unproject_position(_drops[0].global_position + Vector3(0, 0.4, 0))
			_wait = 30
		2:
			_save("legendary_drop_tooltip_maul")
			var camera: Camera3D = get_root().get_camera_3d()
			hud.mouse_override = camera.unproject_position(_drops[2].global_position + Vector3(0, 0.4, 0))
			_wait = 30
		3:
			_save("legendary_drop_tooltip_amulet")
			hud.mouse_override = Vector2(-1, -1)
			for d in _drops:
				player.stats.add_to_bag(d.item)
				d.queue_free()
			hud._open_character()
			_wait = 40
		4:
			_save("legendary_inventory_open")
			print("MMLEGEND_SHOTS DONE")
			quit(0)
			return true
	_step += 1
	return false
