extends Control
## A Blender-rendered iron vessel, glass dome and looping liquid, with a live level.
var color := UiTheme.BLOOD
var title: String = "Health"
var current: float = 0.0
var maximum: float = 1.0
var level: float = 1.0
var displayed: float = 1.0
var motion: float = 0.0
var clock: float = 0.0
var fluid: ShaderMaterial
var numbers: Label
var caption: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fluid = ShaderMaterial.new()
	fluid.shader = preload("res://game/resource_orb.gdshader")
	fluid.set_shader_parameter("liquid_atlas", preload("res://assets/ui/vessels/liquid_atlas.png"))
	fluid.set_shader_parameter("glass_dome", preload("res://assets/ui/vessels/glass_dome.png"))
	fluid.set_shader_parameter("liquid_color", color)
	var liquid := TextureRect.new()
	liquid.texture = preload("res://assets/ui/vessels/glass_dome.png")
	liquid.material = fluid
	_full(liquid)
	var rim := TextureRect.new()
	rim.texture = preload("res://assets/ui/vessels/orb_frame.png")
	_full(rim)
	numbers = _label(18)
	caption = _label(15)
	caption.text = title
	resized.connect(_layout)
	_layout()

func _full(rect: TextureRect) -> void:
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiTheme.TEXT)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.012, 0.012, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label

func _layout() -> void:
	numbers.position = Vector2(0, size.y * 0.48)
	numbers.size = Vector2(size.x, 28)
	caption.position = Vector2(0, size.y * 0.86)
	caption.size = Vector2(size.x, 25)

func update_value(value: float, capacity: float, delta: float, movement: Vector3) -> void:
	current = value
	maximum = capacity
	var next: float = clampf(value / maxf(capacity, 0.001), 0.0, 1.0)
	motion = maxf(motion, minf(absf(next - level) * 5.0, 1.0))
	level = next
	# Fast enough to remain honest during combat, eased enough to feel like liquid.
	displayed = move_toward(displayed, level, delta * 2.0)
	motion = move_toward(motion, 0.0, delta * 1.4)
	clock += delta
	fluid.set_shader_parameter("fill_level", displayed)
	fluid.set_shader_parameter("clock", clock)
	fluid.set_shader_parameter("slosh", maxf(motion, minf(movement.length() / 14.0, 0.6)))
	fluid.set_shader_parameter("lean", clampf(movement.x / 10.0, -0.8, 0.8))
	numbers.text = "%d / %d" % [ceili(value), ceili(capacity)]
