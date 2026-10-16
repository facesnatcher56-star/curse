class_name DamageNumber
extends Node3D
## Shared combat-number presentation. Receives resolved display values only;
## never changes combat outcomes, health, or damage rounding.

const GROUP := "damage_number_fx"
static var _font: Font

static func number_font() -> Font:
	if _font == null:
		var face := FontVariation.new()
		face.base_font = preload("res://assets/fonts/Cinzel.ttf")
		face.variation_opentype = {"wght": 800}
		face.variation_embolden = 0.8
		_font = face
	return _font

static func spawn(from: Node3D, pos: Vector3, text: String, color: Color, size: int, critical: bool) -> DamageNumber:
	var number := DamageNumber.new()
	from.get_tree().current_scene.add_child(number)
	number.add_to_group(GROUP)
	# Per-recipient lanes keep rapid blows from starting on the same glyphs.
	var lane := int(from.get_meta("damage_number_lane", 0)) % 3
	from.set_meta("damage_number_lane", lane + 1)
	var camera := from.get_viewport().get_camera_3d()
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	var start := pos + right * float(lane - 1) * 0.18 + Vector3.UP * float(lane) * 0.10
	number.global_position = start
	var shadow := number._label(text, Color("211209"), size, 10)
	shadow.position = right * 0.018 - Vector3.UP * 0.022
	shadow.render_priority = 0
	var face := number._label(text, color, size, 7)
	face.render_priority = 1
	if critical:
		var caption := number._label("CRITICAL", Color("d6a654"), 23, 5)
		var up := camera.global_basis.y if camera != null else Vector3.UP
		caption.position = up * float(size) * 0.0055 * 0.76
		caption.render_priority = 1
	var duration := 1.05 if critical else 0.85
	number.scale = Vector3.ONE * (0.62 if critical else 0.78)
	var pop := number.create_tween()
	pop.tween_property(number, "scale", Vector3.ONE * (1.12 if critical else 1.06), 0.085).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pop.tween_property(number, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var motion := number.create_tween().set_parallel(true)
	motion.tween_property(number, "global_position", start + Vector3.UP * 0.85 + right * (0.22 if lane % 2 == 0 else -0.22), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Hold the value through the impact pop, then let the whole embossed face fade.
	for child in number.get_children():
		motion.tween_property(child, "modulate:a", 0.0, duration * 0.30).set_delay(duration * 0.70)
	motion.chain().tween_callback(number.queue_free)
	return number

func _label(text: String, color: Color, size: int, outline: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = number_font()
	label.font_size = size
	label.modulate = color
	label.outline_modulate = Color("100d0b")
	label.outline_size = outline
	label.pixel_size = 0.0055
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	return label
