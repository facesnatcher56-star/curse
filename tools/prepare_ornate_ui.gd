extends SceneTree
## Import preparation only: normalize generated source art to nine-slice pixel sizes.
## Run headless --script res://tools/prepare_ornate_ui.gd -- SOURCE_DIRECTORY.
func _initialize() -> void:
	var source := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("res://assets/ui/ornate")
	for id in ["parchment", "metal", "button", "compass", "crest"]:
		var image := Image.load_from_file(source.path_join(id + ".png"))
		if image == null:
			push_error("Missing generated UI source: " + id)
			quit(1)
			return
		if id == "parchment":
			var inset := Vector2i(image.get_width() / 10, image.get_height() / 10)
			var detail := image.get_region(Rect2i(inset, image.get_size() - inset * 2))
			detail.save_png("res://assets/ui/ornate/paper_detail.png")
		# Keep four physical pixels per logical nine-slice pixel. The theme retains
		# the original logical sizes so trim does not become four times thicker.
		var width: int = 1024 if id in ["parchment", "metal"] else (576 if id == "button" else 768)
		var height: int = roundi(image.get_height() * float(width) / image.get_width())
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)
		image.save_png("res://assets/ui/ornate/" + id + ".png")
		if id == "metal":
			var icon := image.duplicate() as Image
			icon.resize(256, 256, Image.INTERPOLATE_LANCZOS)
			icon.save_png("res://assets/ui/ornate/icon.png")
		print(id, " ", image.get_size(), " alpha=", image.detect_alpha())
	quit()
