extends Control
## Developer tool: shows the map-mode node-map overlay on a synthetic dungeon and saves PNGs, to judge the layout by eye.
## `godot --path . res://game/dev/map_overlay_preview.tscn --resolution 1920x1080 --screen 1 -- --ui=1.5 --out=<dir>`

func _ready() -> void:
	var ui: float = 1.0
	var out: String = OS.get_environment("TEMP")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui="):
			ui = float(arg.substr(5))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
	GameSettings.ui_size = ui
	GameSettings.apply_ui_scale()
	var spec: Array = [
		[0, "start", Vector2(0, 0), 0, ""], [1, "pack", Vector2(22, -16), 3, ""], [2, "swarm", Vector2(22, 16), 9, ""],
		[3, "champion", Vector2(44, -16), 4, "Grimfang"], [4, "chest", Vector2(44, 16), 0, ""], [5, "shrine", Vector2(66, 0), 0, ""],
		[6, "pack", Vector2(88, -16), 6, ""], [7, "pack", Vector2(88, 16), 5, ""], [8, "boss", Vector2(110, 0), 1, ""],
		[9, "pack", Vector2(66, -34), 3, ""], [10, "champion", Vector2(66, 34), 4, "Mordrek"], [11, "swarm", Vector2(88, -40), 12, ""]]
	var rows: Array = []
	for s in spec:
		rows.append({"id": s[0], "kind": s[1], "name": "%s %d" % [String(s[1]).capitalize(), s[0]], "pos": s[2], "groups": [["zombie", s[3]]] if s[3] > 0 else [], "champion": s[4]})
	var pairs: Array = [[0, 1], [0, 2], [1, 3], [2, 4], [3, 5], [4, 5], [5, 6], [5, 7], [6, 8], [7, 8], [3, 9], [4, 10], [9, 11]]
	var links: Array = []
	for pr in pairs:
		var a: Vector2 = rows[pr[0]]["pos"]
		var b: Vector2 = rows[pr[1]]["pos"]
		links.append({"a": pr[0], "b": pr[1], "waypoints": [a, (a + b) * 0.5 + Vector2(0, 3), b]})
	var g := MapGraph.from_rows(rows, links)
	g.mark_cleared(1)
	g.mark_cleared(3)
	var mm := MapMode.new()
	mm.use_graph(g, {})
	var overlay := MapModeOverlay.new()
	add_child(overlay)
	overlay.set_links(g.link_rows())
	overlay.set_frame(g.bounds())
	overlay.open(mm.markers(), Vector3(44, 0, -16), false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/overlay_ui%s_plain.png" % [out, str(ui)])
	for id in [5, 2]:
		var ev := InputEventMouseMotion.new()
		ev.position = overlay.marker_screen_pos(id)
		overlay._input(ev)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/overlay_ui%s_hover%d.png" % [out, str(ui), id])
	print("size ", overlay.size, " panel ", overlay.panel_rect())
	get_tree().quit()
