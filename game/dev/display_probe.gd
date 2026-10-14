extends SceneTree
## Read-only probe: prints what DisplayServer exposes on this machine (screens, sizes, usable rects, DPI, refresh).
## Run: godot --path . --script res://game/dev/display_probe.gd --quit-after 2

func _init() -> void:
	print("PROBE driver=", DisplayServer.get_name())
	var count: int = DisplayServer.get_screen_count()
	print("PROBE screen_count=", count, " primary=", DisplayServer.get_primary_screen())
	for i in count:
		print("PROBE screen=", i,
			" pos=", DisplayServer.screen_get_position(i),
			" size=", DisplayServer.screen_get_size(i),
			" usable=", DisplayServer.screen_get_usable_rect(i),
			" dpi=", DisplayServer.screen_get_dpi(i),
			" scale=", DisplayServer.screen_get_scale(i),
			" refresh=", DisplayServer.screen_get_refresh_rate(i))
	if DisplayServer.get_name() != "headless":
		print("PROBE window_current_screen=", DisplayServer.window_get_current_screen(),
			" window_size=", DisplayServer.window_get_size(),
			" window_mode=", DisplayServer.window_get_mode())
	for method in ["screen_get_name", "screen_get_orientation", "get_display_safe_area", "window_set_current_screen"]:
		print("PROBE has_method ", method, "=", DisplayServer.has_method(method))
	# Which screen-change events the engine exposes (decides how a disconnect can be noticed without polling).
	for cls in ["DisplayServer", "Window"]:
		for info in ClassDB.class_get_signal_list(cls, true):
			var sig: String = str(info["name"])
			if sig.contains("screen") or sig.contains("display") or sig.contains("focus"):
				print("PROBE signal ", cls, ".", sig)
	quit()
