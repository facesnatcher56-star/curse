extends SceneTree
## Developer check of the offscreen spitter warning (task spitter-ranged-warning-082): a winding-up spitter outside the camera view
## gets a screen-edge chevron; on screen it gets none; the warning ends with the wind-up and on death; timing/damage are untouched.
##   tools/run_godot.sh LOG 60 -- --script res://tools/spitter_warning_check.gd -- --check
## User arguments make it a developer session: the production save is never touched.

var failures: int = 0

func expect(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	TownState.reset()
	TownState.job = {}
	var main: Node = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await process_frame
	var hud: Hud = main.hud
	var player: Player = hud.player
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var size_px: Vector2 = root.get_viewport().get_visible_rect().size
	for n in root.get_tree().get_nodes_in_group("enemies"):
		(n as Node).queue_free()
	await process_frame

	# On screen, winding up: no warning.
	var near: Enemy = main.director.spawn_enemy(player.global_position + Vector3(0, 0, -4.0), "spitter", 1.0)
	await process_frame
	var sb: SpitterBehavior = near.behavior as SpitterBehavior
	expect("idle spitter: no warning", hud.ranged_warnings(cam, size_px).is_empty())
	sb._begin_windup()
	expect("spitter is winding up", sb.is_winding_up())
	var on_screen: bool = Rect2(Vector2.ZERO, size_px).has_point(cam.unproject_position(near.global_position)) and not cam.is_position_behind(near.global_position)
	expect("near spitter is on screen (precondition)", on_screen)
	expect("on-screen windup: no edge warning", hud.ranged_warnings(cam, size_px).is_empty())

	# Offscreen, winding up: one warning on the screen edge pointing toward it.
	near.global_position = player.global_position + Vector3(60, 0, 0)
	var w: Array[Dictionary] = hud.ranged_warnings(cam, size_px)
	expect("offscreen windup: exactly one warning", w.size() == 1)
	if w.size() == 1:
		var p: Vector2 = w[0]["pos"]
		var d: Vector2 = w[0]["dir"]
		expect("marker sits inside the screen, on its edge band", Rect2(Vector2.ZERO, size_px).grow(1.0).has_point(p) and (p.x <= 40.0 or p.y <= 40.0 or p.x >= size_px.x - 40.0 or p.y >= size_px.y - 40.0))
		var toward: Vector2 = cam.unproject_position(near.global_position) - size_px * 0.5
		expect("marker points toward the spitter", d.dot(toward.normalized()) > 0.99)
	hud.queue_redraw()
	await process_frame   # _draw runs the draw path without error

	# Wind-up ends (interrupt / fire): warning clears. Timing state untouched by the HUD.
	var before: float = sb._timer
	hud.ranged_warnings(cam, size_px)
	expect("computing the warning does not alter wind-up timing", sb._timer == before)
	sb.on_interrupted()
	expect("interrupted: warning cancelled", hud.ranged_warnings(cam, size_px).is_empty())

	# HUD clearance (task spitter-chevron-hotbar-clearance-089): behind, lateral and corner targets never sit on the hotbar, vessels or minimap.
	sb._begin_windup()
	var back: Vector3 = cam.global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var spots: Dictionary = {
		"behind": back * 60.0, "left": -right * 60.0, "right": right * 60.0, "ahead": -back * 60.0,
		"behind-left": (back - right).normalized() * 60.0, "behind-right": (back + right).normalized() * 60.0,
		"ahead-left": (-back - right).normalized() * 60.0, "ahead-right": (-back + right).normalized() * 60.0}
	for sz in [Vector2(1280, 720), Vector2(1920, 1080)]:
		var keep: Array[Rect2] = hud.ranged_warn_keepouts(sz)
		for label in spots:
			near.global_position = player.global_position + (spots[label] as Vector3)
			var ws: Array[Dictionary] = hud.ranged_warnings(cam, sz)
			if ws.size() != 1:
				expect("%s @%d: one warning" % [label, int(sz.x)], false)
				continue
			var wp: Vector2 = ws[0]["pos"]
			var clear: bool = Rect2(Vector2.ZERO, sz).has_point(wp)
			for r in keep:
				clear = clear and not r.has_point(wp)
			expect("%s @%dx%d: chevron on screen and clear of hotbar/vessels/minimap" % [label, int(sz.x), int(sz.y)], clear)
			if label == "behind":
				expect("behind @%d: sits above the hotbar tray" % int(sz.x), wp.y < hud.hotbar_rect(sz).position.y)
	near.global_position = player.global_position + Vector3(60, 0, 0)

	# Death cancels it.
	sb._begin_windup()
	expect("re-armed: warning back", hud.ranged_warnings(cam, size_px).size() == 1)
	near._apply_damage(near.max_health * 10.0)
	near.dead = true
	expect("dead spitter: warning cancelled", hud.ranged_warnings(cam, size_px).is_empty())

	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
