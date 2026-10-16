class_name PowerHotkeyVfx
extends Control
## One independent instance per hotkey. Shader inputs always come from the
## assigned ability's current normalized gameplay state.

const FRAME_SHADER := preload("res://game/ui/power_frame_forge.gdshader")
const ICON_SHADER := preload("res://game/ui/power_icon_awakening.gdshader")
const LEGACY_FRAME := preload("res://assets/ui/vessels/skill_bezel.png")
const READY_GLINT_SECONDS := 0.18
const RELEASE_SECONDS := 0.18

var _frame: NinePatchRect
var _legacy_frame: TextureRect
var _icon: TextureRect
var _frame_material: ShaderMaterial
var _icon_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_frame_material = ShaderMaterial.new()
	_frame_material.shader = FRAME_SHADER
	_icon_material = ShaderMaterial.new()
	_icon_material.shader = ICON_SHADER
	_frame = NinePatchRect.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw_center = false
	_frame.patch_margin_left = 32
	_frame.patch_margin_top = 32
	_frame.patch_margin_right = 32
	_frame.patch_margin_bottom = 32
	_frame.material = _frame_material
	add_child(_frame)
	_legacy_frame = TextureRect.new()
	_legacy_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_legacy_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legacy_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_legacy_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_legacy_frame.material = _frame_material
	add_child(_legacy_frame)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.material = _icon_material
	add_child(_icon)
	hide()

func present(icon: Texture2D, rect: Rect2, charge: float, available: bool, cooling: bool,
		ready_glint: float, release: float, ds2_style: bool) -> void:
	visible = icon != null
	if not visible:
		return
	position = rect.position - Vector2(3.0, 3.0)
	size = rect.size + Vector2(6.0, 6.0)
	_frame.texture = UiTheme.art("icon")
	_frame.patch_margin_left = 12
	_frame.patch_margin_top = 12
	_frame.patch_margin_right = 12
	_frame.patch_margin_bottom = 12
	_frame.visible = ds2_style
	_legacy_frame.texture = LEGACY_FRAME
	_legacy_frame.visible = not ds2_style
	_icon.texture = icon
	_icon.position = Vector2(9.0, 9.0) if ds2_style else Vector2(6.0, 6.0)
	_icon.size = size - _icon.position * 2.0
	var active_charge := clampf(charge, 0.0, 1.0) if available and not cooling else 0.0
	_frame_material.set_shader_parameter("charge", active_charge)
	_frame_material.set_shader_parameter("frame_size", size)
	_frame_material.set_shader_parameter("enabled", 1.0 if available and not cooling else 0.0)
	_frame_material.set_shader_parameter("ready_glint", clampf(ready_glint / READY_GLINT_SECONDS, 0.0, 1.0))
	_frame_material.set_shader_parameter("release", clampf(release / RELEASE_SECONDS, 0.0, 1.0))
	_icon_material.set_shader_parameter("charge", active_charge)
	_icon_material.set_shader_parameter("ready_glint", clampf(ready_glint / READY_GLINT_SECONDS, 0.0, 1.0))
	_icon_material.set_shader_parameter("release", clampf(release / RELEASE_SECONDS, 0.0, 1.0))
