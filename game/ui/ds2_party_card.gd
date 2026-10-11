class_name Ds2PartyCard
extends Control
## Dungeon Siege II authentic party card component.
## Layout matches DS2 reference:
##   - Left: Portrait framed in stone, with horizontal Health & Mana bars underneath.
##   - Right: weapon slot and four circular power bezels; recharge is inside the icon.

const PORTRAIT_FRAME_TEX := preload("res://assets/ui/ds2/portrait_frame.png")
const ACTION_BEZEL_TEX := preload("res://assets/ui/ds2/action_slot_bezel.png")
const POWER_BEZEL_TEX := preload("res://assets/ui/ds2/power_bezel.png")
const PowerVisual := preload("res://game/ui/power_button_visual.gd")

var character_name: String = "Hero"
var is_companion: bool = false

var _portrait_rect: TextureRect
var _portrait_frame: TextureRect
var _hp_fill: ColorRect
var _mana_fill: ColorRect
var _weapon_slot: TextureRect
var _power_icons: Array[TextureRect] = []
var _power_sweeps: Array[Control] = []
var _power_charge: float = 1.0
var _power_armed: bool = false
var _power_available: bool = true

func _init(name: String = "Hero", companion: bool = false) -> void:
	character_name = name
	is_companion = companion
	custom_minimum_size = Vector2(240, 84)
	size = Vector2(240, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_setup_ui()

func _setup_ui() -> void:
	# Card background plate (weathered stone with dark beveled border)
	var bg := ColorRect.new()
	bg.size = Vector2(236, 82)
	bg.color = Color(0.14, 0.13, 0.12, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var bg_border := ReferenceRect.new()
	bg_border.size = Vector2(236, 82)
	bg_border.border_color = Color(0.38, 0.34, 0.28, 0.9)
	bg_border.border_width = 1.5
	bg_border.editor_only = false
	bg_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_border)

	# --- LEFT COLUMN: Portrait + Vitals Stack ---
	var left_col := Control.new()
	left_col.position = Vector2(5, 4)
	left_col.size = Vector2(58, 74)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_col)

	# Portrait (54x50)
	_portrait_rect = TextureRect.new()
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_rect.size = Vector2(46, 42)
	_portrait_rect.position = Vector2(4, 4)
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_portrait_rect)

	_portrait_frame = TextureRect.new()
	_portrait_frame.texture = PORTRAIT_FRAME_TEX
	_portrait_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait_frame.size = Vector2(54, 50)
	_portrait_frame.position = Vector2.ZERO
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_portrait_frame)

	# Vitals stacked directly under portrait (matching DS2 reference)
	# Health Bar (Red)
	var hp_bg := ColorRect.new()
	hp_bg.position = Vector2(2, 53)
	hp_bg.size = Vector2(50, 8)
	hp_bg.color = Color(0.08, 0.05, 0.05, 0.95)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(2, 53)
	_hp_fill.size = Vector2(50, 8)
	_hp_fill.color = Color(0.85, 0.12, 0.08, 0.95)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_hp_fill)

	# Mana Bar (Blue)
	var mana_bg := ColorRect.new()
	mana_bg.position = Vector2(2, 63)
	mana_bg.size = Vector2(50, 8)
	mana_bg.color = Color(0.05, 0.06, 0.10, 0.95)
	mana_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(mana_bg)

	_mana_fill = ColorRect.new()
	_mana_fill.position = Vector2(2, 63)
	_mana_fill.size = Vector2(50, 8)
	_mana_fill.color = Color(0.18, 0.42, 0.88, 0.95)
	_mana_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_mana_fill)

	# --- RIGHT COLUMN: Weapon Slot, Buffs, 4 Power Bezels, Charge Bar ---
	var right_col := Control.new()
	right_col.position = Vector2(66, 4)
	right_col.size = Vector2(165, 74)
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right_col)

	# Row 1: Weapon Attack Slot (Left) + Name / Stance (Right)
	var w_box := Control.new()
	w_box.position = Vector2(2, 2)
	w_box.size = Vector2(26, 26)
	w_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(w_box)

	var w_bezel := TextureRect.new()
	w_bezel.texture = ACTION_BEZEL_TEX
	w_bezel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	w_bezel.stretch_mode = TextureRect.STRETCH_SCALE
	w_bezel.size = Vector2(26, 26)
	w_bezel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w_box.add_child(w_bezel)

	# These generated bezels have a weathered inset rather than a transparent
	# hole. Keep that inset as the backing, then place the readable icon above it.
	_weapon_slot = TextureRect.new()
	_weapon_slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_slot.size = Vector2(18, 18)
	_weapon_slot.position = Vector2(4, 4)
	_weapon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w_box.add_child(_weapon_slot)

	# Character name / title engraved in top row
	var name_lbl := Label.new()
	name_lbl.text = character_name
	name_lbl.position = Vector2(34, 4)
	name_lbl.size = Vector2(125, 20)
	name_lbl.add_theme_font_override("font", UiTheme.heading_font())
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.85, 0.72))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(name_lbl)

	# Row 2: 4 Circular Power Bezels (matching DS2's 4 power slots)
	var powers_box := HBoxContainer.new()
	powers_box.position = Vector2(2, 34)
	powers_box.add_theme_constant_override("separation", 6)
	powers_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(powers_box)

	for i in 4:
		var p_cell := Control.new()
		p_cell.custom_minimum_size = Vector2(26, 26)
		p_cell.size = Vector2(26, 26)
		p_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		powers_box.add_child(p_cell)

		var p_frame := TextureRect.new()
		p_frame.texture = POWER_BEZEL_TEX
		p_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p_frame.stretch_mode = TextureRect.STRETCH_SCALE
		p_frame.size = Vector2(26, 26)
		p_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p_cell.add_child(p_frame)

		var p_icon := TextureRect.new()
		p_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p_icon.size = Vector2(16, 16)
		p_icon.position = Vector2(5, 5)
		p_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p_cell.add_child(p_icon)
		_power_icons.append(p_icon)

		var p_sweep := Control.new()
		p_sweep.size = Vector2(26, 26)
		p_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p_sweep.draw.connect(_draw_power_sweep.bind(p_sweep, i))
		p_cell.add_child(p_sweep)
		_power_sweeps.append(p_sweep)

	if _pending_portrait != null and _portrait_rect != null:
		_portrait_rect.texture = _pending_portrait
	if _pending_weapon != null and _weapon_slot != null:
		_weapon_slot.texture = _pending_weapon
	if _pending_power != null and _power_icons.size() > 0 and _power_icons[0] != null:
		_power_icons[0].texture = _pending_power

var _pending_portrait: Texture2D
var _pending_weapon: Texture2D
var _pending_power: Texture2D

func set_portrait(tex: Texture2D) -> void:
	_pending_portrait = tex
	if _portrait_rect != null:
		_portrait_rect.texture = tex

func set_icons(weapon: Texture2D, power: Texture2D) -> void:
	_pending_weapon = weapon
	_pending_power = power
	if _weapon_slot != null:
		_weapon_slot.texture = weapon
	if _power_icons.size() > 0 and _power_icons[0] != null:
		_power_icons[0].texture = power

func update_vitals(hp_pct: float, mana_pct: float, xp_pct: float, power_charge: float = 1.0, power_armed: bool = false, power_available: bool = true) -> void:
	if _hp_fill != null:
		_hp_fill.size.x = clampf(hp_pct, 0.0, 1.0) * 50.0
	if _mana_fill != null:
		_mana_fill.size.x = clampf(mana_pct, 0.0, 1.0) * 50.0
	_power_charge = clampf(power_charge, 0.0, 1.0)
	_power_armed = power_armed
	_power_available = power_available
	if _power_sweeps.size() > 0 and _power_sweeps[0] != null:
		_power_sweeps[0].queue_redraw()

func _draw_power_sweep(sweep: Control, index: int) -> void:
	if index == 0 and _pending_power != null:
		PowerVisual.draw_on(sweep, Rect2(Vector2.ZERO, sweep.size), _power_charge, _power_armed, _power_available, 0.2)
