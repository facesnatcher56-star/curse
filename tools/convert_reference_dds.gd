extends SceneTree
## Converts explicitly supplied DDS reference images to adjacent PNG previews.
## Usage: godot --headless --script res://tools/convert_reference_dds.gd -- <absolute.dds> [...]

func _init() -> void:
	var failed: bool = false
	for source in OS.get_cmdline_user_args():
		if source.get_extension().to_lower() != "dds":
			continue
		var image := Image.load_from_file(source)
		if image == null or image.is_empty():
			push_error("Could not decode DDS: " + source)
			failed = true
			continue
		var destination: String = source.get_basename() + ".png"
		var error: Error = image.save_png(destination)
		if error != OK:
			push_error("Could not save PNG (%s): %s" % [error_string(error), destination])
			failed = true
		else:
			print("Converted: ", destination)
	quit(1 if failed else 0)
