class_name PowerHotkeyVfx
extends Control
## One instance per hotkey, drawn over the slot's icon art. The icon is blacked out while the power recharges and fills with its own
## colour from the bottom up as it charges; when it is full a burst in that colour goes off, then it pulses until the power is spent.
## All of it follows the assigned power's real charge (the same value the portrait ring reads).

const ICON_SHADER := preload("res://game/ui/power_icon_charge.gdshader")
const BURST_SECONDS := 0.8
const PULSE_SECONDS := 1.6
static var _themes: Dictionary = {}

var _icon: TextureRect
var _icon_material: ShaderMaterial
var _theme := Color(1.0, 0.7, 0.3)
var _ready_now := false
var _burst_left := 0.0
var _clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_material = ShaderMaterial.new()
	_icon_material.shader = ICON_SHADER
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.material = _icon_material
	add_child(_icon)
	hide()

## The colour of an icon's art: the average of its most saturated pixels, lifted so it reads as light.
static func theme_of(texture: Texture2D) -> Color:
	if _themes.has(texture):
		return _themes[texture]
	var result := Color(1.0, 0.7, 0.3)
	var image: Image = texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var sum := Vector3.ZERO
		var weight := 0.0
		var step: int = maxi(image.get_width() / 24, 1)
		for y in range(0, image.get_height(), step):
			for x in range(0, image.get_width(), step):
				var c: Color = image.get_pixel(x, y)
				if c.a < 0.5 or c.v < 0.25:
					continue
				var w: float = c.s * c.s * c.v
				sum += Vector3(c.r, c.g, c.b) * w
				weight += w
		if weight > 0.001:
			var avg := Color(sum.x / weight, sum.y / weight, sum.z / weight)
			result = Color.from_hsv(avg.h, clampf(avg.s * 1.15, 0.45, 1.0), 1.0)
	_themes[texture] = result
	return result

func present(icon: Texture2D, rect: Rect2, charge: float, available: bool, cooling: bool, ds2_style: bool) -> void:
	visible = icon != null
	if not visible:
		return
	position = rect.position - Vector2(3.0, 3.0)
	size = rect.size + Vector2(6.0, 6.0)
	_icon.position = Vector2(9.0, 9.0) if ds2_style else Vector2(6.0, 6.0)
	_icon.size = size - _icon.position * 2.0
	var changed: bool = _icon.texture != icon
	if changed:
		_icon.texture = icon
		_theme = theme_of(icon)
		_icon_material.set_shader_parameter("theme", _theme)
	var usable: bool = available and not cooling
	var fill: float = clampf(charge, 0.0, 1.0) if usable else 0.0
	var is_ready: bool = usable and charge >= 0.999
	if is_ready and not _ready_now and not changed:
		_burst_left = BURST_SECONDS   # it just filled: no burst for a power that was already full when it was put here
	if not is_ready:
		_burst_left = 0.0
	_ready_now = is_ready
	_icon_material.set_shader_parameter("fill", fill)

func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	_burst_left = maxf(_burst_left - delta, 0.0)
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU / PULSE_SECONDS) if _ready_now else 0.0
	var burst: float = pow(_burst_left / BURST_SECONDS, 2.0)
	_icon_material.set_shader_parameter("pulse", pulse * smoothstep(0.55, 0.3, _burst_left / BURST_SECONDS) if _burst_left > 0.0 else pulse)
	_icon_material.set_shader_parameter("burst", burst)
	queue_redraw()

func _draw() -> void:
	if not _ready_now:
		return
	var centre: Vector2 = size * 0.5
	var radius: float = size.x * 0.5
	if _burst_left > 0.0:
		var p: float = 1.0 - _burst_left / BURST_SECONDS
		var fade: float = 1.0 - p
		for ring in 2:
			var grow: float = clampf(p * (1.0 + 0.35 * ring), 0.0, 1.0)
			draw_arc(centre, radius * (0.55 + 0.95 * grow), 0.0, TAU, 48, Color(_theme, 0.85 * fade), 3.0 * fade + 1.0, true)
		for ray in 14:
			var angle: float = TAU * float(ray) / 14.0 + 0.2
			var dir := Vector2(cos(angle), sin(angle))
			draw_line(centre + dir * radius * (0.7 + 0.8 * p), centre + dir * radius * (0.9 + 1.1 * p), Color(_theme, 0.9 * fade), 2.0, true)
		draw_circle(centre, radius * (0.4 + 0.5 * p), Color(_theme, 0.30 * fade))
	else:
		var pulse: float = 0.5 + 0.5 * sin(_clock * TAU / PULSE_SECONDS)
		draw_rect(Rect2(Vector2.ONE * 3.0, size - Vector2.ONE * 6.0), Color(_theme, 0.25 + 0.55 * pulse), false, 2.0)
