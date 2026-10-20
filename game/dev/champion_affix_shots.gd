extends SceneTree
## 1080p shots of the champion affix chips on the real HUD. Run:
##   godot --path . --screen 1 -s res://game/dev/champion_affix_shots.gd --resolution 1920x1080 -- --shots=<abs dir> [--mapmode --tooltip]

var _main: Node
var _frames := 0
var _step := 0
var _wait := 0
var _dir := ""
var _tooltip := false
var _champs: Dictionary = {}
var _target: Enemy = null

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
		if arg == "--tooltip":
			_tooltip = true
	DirAccess.make_dir_recursive_absolute(_dir)
	TownState.persist = false
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main

func _save(shot: String) -> void:
	var image := get_root().get_texture().get_image()
	var path := _dir.path_join(shot + ".png")
	image.save_png(path)
	print("AFFIX_SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])

func _make(id: String, offset: Vector3, extra: Array = []) -> Enemy:
	var player: Player = _main.player
	var e: Enemy = _main.director.spawn_enemy(Nav.snap(player, player.global_position + offset), "zombie", WorldThreat.threat_for_level(4), "normal")
	e.alert_delay = 999.0
	e.aggro_range = 0.0
	var c: Champion = Champion.attach(e, id)
	c.extra_ids = extra
	return e

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _frames < 300 or _main.player == null:
		return false
	if _target != null and is_instance_valid(_target):
		_main.player.attack_target = _target
	if _wait > 0:
		_wait -= 1
		return false
	var player: Player = _main.player
	var hud: Hud = _main.hud
	if _tooltip:
		var overlay = MapMode.current.overlay
		if _step == 0:
			if not overlay.is_open():
				return false
			var markers: Array = []
			var mm = MapMode.current
			for id in mm.graph.ids():   # every node lit, the hidden champion nodes too, so their tooltips can be shot
				var row: Dictionary = mm.graph.row(int(id))
				var p: Vector2 = mm.graph.pos_of(int(id))
				markers.append({"id": int(id), "pos": Vector3(p.x, 0.0, p.y), "kind": String(row.get("kind", "pack")), "state": "reachable",
					"strength": MapMode._strength_of(row), "label": mm.node_label(int(id)), "guard": ""})
			overlay.open(markers, Vector3.ZERO, true)
			overlay._hover = 4
			_wait = 20
			_step = 1
		elif _step == 1:
			_save("maptooltip_swift_champion")
			overlay._hover = 8
			_wait = 20
			_step = 2
		else:
			_save("maptooltip_warded_champion")
			quit(0)
			return true
		return false
	if MapMode.current != null and MapMode.current.overlay != null and MapMode.current.overlay.is_open():
		MapMode.current.overlay.close()
	hud.mouse_override = Vector2(960, 900)
	var order := ["fast", "shielded", "summoner", "explodes"]
	match _step:
		0:
			var i := 0
			for id in order:
				_champs[id] = _make(id, Vector3(-4.5 + i * 3.0, 0, -4.0))
				i += 1
			_champs["two"] = _make("shielded", Vector3(-1.5, 0, 2.0), ["fast"])
			for k in 2:
				var z: Enemy = _main.director.spawn_enemy(Nav.snap(player, player.global_position + Vector3(2.0 + k * 2.0, 0, 2.0)), "zombie", WorldThreat.threat_for_level(4), "normal")
				z.alert_delay = 999.0
				z.aggro_range = 0.0
			_wait = 90
		1:
			_save("world_marker_pack")
			_target = _champs["fast"]
			_wait = 25
		2:
			_save("banner_swift")
			_target = _champs["shielded"]
			_wait = 25
		3:
			_save("banner_warded_full")
			var c: Champion = _target.champion
			c.shield = c.shield_max * 0.4
			c._update_bubble()
			_wait = 10
		4:
			_save("banner_warded_regenerating_40pct")
			var c: Champion = _target.champion
			c.shield = 0.0
			c._update_bubble()
			_wait = 10
		5:
			_save("banner_warded_broken")
			_target = _champs["summoner"]
			_wait = 25
		6:
			_save("banner_summoning")
			_target = _champs["explodes"]
			_wait = 25
		7:
			_save("banner_volatile")
			_target = _champs["two"]
			_wait = 25
		8:
			_save("banner_two_affixes_warded_swift")
			var b: Enemy = _main.director.spawn_enemy(Nav.snap(player, player.global_position + Vector3(4.0, 0, -4.0)), "brute", WorldThreat.threat_for_level(6), "miniboss")
			b.is_boss = true
			b.display_name = "Grimfang"
			b.alert_delay = 999.0
			b.aggro_range = 0.0
			_target = b
			_wait = 25
		9:
			_save("banner_boss")
			var plain: Enemy = _main.director.spawn_enemy(Nav.snap(player, player.global_position + Vector3(5.0, 0, 0)), "zombie", WorldThreat.threat_for_level(4), "normal")
			plain.alert_delay = 999.0
			plain.aggro_range = 0.0
			_target = plain
			_wait = 25
		10:
			_save("banner_plain_enemy")
			print("AFFIX_SHOTS DONE")
			quit(0)
			return true
	_step += 1
	return false
