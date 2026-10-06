class_name QuestMarker
extends RefCounted
## A marker for a monster a quest is after: an ember-coloured diamond over its head that stays one size on screen however far the camera
## is, so the target can be found on the long road.

static var _tex: ImageTexture

static func attach(target: Node3D) -> Sprite3D:
	var marker := Sprite3D.new()
	marker.texture = _diamond()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.fixed_size = true
	marker.no_depth_test = true
	marker.shaded = false
	marker.modulate = Color(1.0, 0.45, 0.15)
	marker.pixel_size = 0.0007
	marker.position = Vector3(0, 3.1, 0)
	marker.render_priority = 5
	target.add_child(marker)
	return marker

static func _diamond() -> ImageTexture:
	if _tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d: float = (absf(x - 15.5) + absf(y - 15.5)) / 15.5
				if d <= 1.0:
					var core: float = 1.0 if d > 0.6 else 0.45
					img.set_pixel(x, y, Color(core, core, core, clampf((1.0 - d) * 6.0, 0.0, 1.0)))
		_tex = ImageTexture.create_from_image(img)
	return _tex
