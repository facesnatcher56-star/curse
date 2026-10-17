extends Node3D
## Dev-only sample room built from the third-party art kits (not part of the game flow). Run:
##   godot --path . --screen 1 res://game/dev/third_party_sample.tscn -- --shot=PATH.png
## With --shot it saves a screenshot after the scatter has built and quits.

func _ready() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
	if shot.is_empty():
		return
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
