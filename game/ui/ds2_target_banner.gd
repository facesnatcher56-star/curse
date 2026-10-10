class_name Ds2TargetBanner
extends Control
## Dungeon Siege II-style ornate target banner at top-center.
## Shows target name, enemy tier, and health bar inside an ornate metal plaque.

const BANNER_TEX := preload("res://assets/ui/ds2/target_banner.png")

var _banner_rect: TextureRect
var _hp_fill: ColorRect
var _name_label: Label
var _health_label: Label
var _fade: float = 0.0

func _init() -> void:
	custom_minimum_size = Vector2(400, 44)
	size = Vector2(400, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	# Center at top
	var screen: Vector2 = get_viewport_rect().size
	position = Vector2((screen.x - 400.0) * 0.5, 4.0)
	modulate = Color(1, 1, 1, 0)

	var root := Control.new()
	root.custom_minimum_size = Vector2(400, 44)
	root.size = Vector2(400, 44)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Ornate plaque frame
	_banner_rect = TextureRect.new()
	_banner_rect.texture = BANNER_TEX
	_banner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_banner_rect.custom_minimum_size = Vector2(400, 44)
	_banner_rect.size = Vector2(400, 44)
	_banner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner_rect)

	# Health fill bar inside plaque
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.85, 0.15, 0.12, 0.95)
	_hp_fill.position = Vector2(48, 26)
	_hp_fill.size = Vector2(304, 8)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_fill)

	# Monster Name Label
	_name_label = Label.new()
	_name_label.position = Vector2(40, 4)
	_name_label.size = Vector2(320, 20)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", UiTheme.heading_font())
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.78))
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_name_label)

	# Health Numbers Label
	_health_label = Label.new()
	_health_label.position = Vector2(48, 22)
	_health_label.size = Vector2(304, 16)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 10)
	_health_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_health_label)

func update_target(target: Actor, delta: float) -> void:
	var screen: Vector2 = get_viewport_rect().size
	position.x = (screen.x - 400.0) * 0.5
	position.y = 4.0
	if target != null and not target.dead:
		_fade = minf(_fade + delta * 6.0, 1.0)
		_name_label.text = target.display_name.to_upper()
		var cur_hp: float = maxf(target.health, 0.0)
		var max_hp: float = maxf(target.max_health, 1.0)
		var pct: float = clampf(cur_hp / max_hp, 0.0, 1.0)
		_hp_fill.size.x = pct * 304.0
		_health_label.text = "%d / %d" % [ceili(cur_hp), int(max_hp)]
		
		# Boss / Elite color
		if target.is_boss or max_hp >= 150.0:
			_name_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
			_hp_fill.color = Color(0.92, 0.35, 0.10, 0.95)
		else:
			_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.78))
			_hp_fill.color = Color(0.85, 0.15, 0.12, 0.95)
	else:
		_fade = maxf(_fade - delta * 4.0, 0.0)

	modulate = Color(1, 1, 1, _fade)
	visible = _fade > 0.01
