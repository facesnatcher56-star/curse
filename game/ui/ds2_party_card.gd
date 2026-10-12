class_name Ds2PartyCard
extends Control
## Live party state in the shared worn-gold theme; recharge remains inside each power.
const PowerVisual := preload("res://game/ui/power_button_visual.gd")
var character_name: String = "Hero"
var is_companion: bool = false
var _portrait_rect: TextureRect
var _weapon_slot: TextureRect
var _hp_fill: ColorRect
var _mana_fill: ColorRect
var _xp_fill: ColorRect
var _level: Label
var _power_icons: Array[TextureRect] = []
var _power_sweeps: Array[Control] = []
var _power_charge: float = 1.0
var _power_armed: bool = false
var _power_available: bool = true
var _pending_portrait: Texture2D
var _pending_weapon: Texture2D
var _pending_power: Texture2D

func _init(title: String = "Hero", companion: bool = false) -> void:
	character_name = title
	is_companion = companion
	custom_minimum_size = Vector2(240, 96)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	gui_input.connect(_select_input)

func _select_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if (click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
		PartyManager.current().select("cutter" if is_companion else "hero")
		accept_event()

func _ready() -> void:
	theme = UiTheme.get_theme()
	draw.connect(func() -> void: UiTheme.draw_panel(self, Rect2(Vector2.ZERO, size), 1.0))
	draw.connect(func() -> void:
		if PartyManager.current().active_id == ("cutter" if is_companion else "hero"):
			draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), UiTheme.BRONZE_LIGHT, false, 1.5))
	var disc := Control.new()
	disc.position = Vector2(6, 5)
	disc.size = Vector2(72, 72)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	disc.draw.connect(func() -> void: disc.draw_circle(Vector2(36, 36), 25, Color.WHITE))
	add_child(disc)
	_portrait_rect = _texture(disc, _pending_portrait, Rect2(9, 8, 54, 58))
	_texture(self, UiTheme.art("compass"), Rect2(6, 5, 72, 72))
	var title := ItemTile._label(character_name, 12, UiTheme.TEXT)
	title.position = Vector2(82, 7)
	title.size = Vector2(148, 20)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	_hp_fill = _vital(Vector2(83, 30), UiTheme.BLOOD)
	_mana_fill = _vital(Vector2(83, 42), UiTheme.MANA)
	_xp_fill = _vital(Vector2(83, 83), UiTheme.BRONZE_LIGHT)
	_weapon_slot = _texture(self, _pending_weapon, Rect2(83, 56, 20, 20))
	for i in 4:
		var cell := Control.new()
		cell.position = Vector2(110 + i * 28, 54)
		cell.size = Vector2(24, 24)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cell)
		cell.draw.connect(func() -> void:
			var style := UiTheme.framed("icon", 0)
			style.set_texture_margin_all(7)
			cell.draw_style_box(style, Rect2(Vector2.ZERO, cell.size)))
		var icon := _texture(cell, _pending_power if i == 0 else null, Rect2(4, 4, 16, 16))
		_power_icons.append(icon)
		var sweep := Control.new()
		sweep.size = cell.size
		sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sweep.draw.connect(_draw_power_sweep.bind(sweep, i))
		cell.add_child(sweep)
		_power_sweeps.append(sweep)
	var medal := Control.new()
	medal.position = Vector2(7, 57)
	medal.size = Vector2(26, 26)
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal.draw.connect(func() -> void:
		medal.draw_circle(Vector2(13, 13), 12, UiTheme.INK)
		medal.draw_arc(Vector2(13, 13), 12, 0, TAU, 32, UiTheme.BRONZE_LIGHT, 2, true))
	add_child(medal)
	_level = ItemTile._label("1", 13, UiTheme.TEXT)
	_level.size = medal.size
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal.add_child(_level)

func _texture(parent: Control, tex: Texture2D, rect: Rect2) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.texture = tex
	image.position = rect.position
	image.size = rect.size
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func _vital(at: Vector2, color: Color) -> ColorRect:
	var back := Control.new()
	back.position = at - Vector2.ONE
	back.size = Vector2(145, 10)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.draw.connect(func() -> void:
		back.draw_rect(Rect2(Vector2.ZERO, back.size), UiTheme.INK)
		back.draw_rect(Rect2(Vector2.ZERO, back.size), UiTheme.BRONZE, false))
	add_child(back)
	var fill := ColorRect.new()
	fill.position = at
	fill.size = Vector2(143, 8)
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)
	return fill

func set_portrait(tex: Texture2D) -> void:
	_pending_portrait = tex
	if _portrait_rect != null: _portrait_rect.texture = tex

func set_icons(weapon: Texture2D, power: Texture2D) -> void:
	_pending_weapon = weapon
	_pending_power = power
	if _weapon_slot != null: _weapon_slot.texture = weapon
	if not _power_icons.is_empty(): _power_icons[0].texture = power

func update_vitals(hp_pct: float, mana_pct: float, xp_pct: float, power_charge: float = 1.0, power_armed: bool = false, power_available: bool = true) -> void:
	if _hp_fill != null: _hp_fill.size.x = clampf(hp_pct, 0, 1) * 143.0
	if _mana_fill != null: _mana_fill.size.x = clampf(mana_pct, 0, 1) * 143.0
	if _xp_fill != null: _xp_fill.size.x = clampf(xp_pct, 0, 1) * 143.0
	if _level != null:
		_level.text = str(HeroProgression.level_for_xp(TownState.cutter_xp if is_companion else TownState.hero_xp))
	_power_charge = clampf(power_charge, 0, 1)
	_power_armed = power_armed
	_power_available = power_available
	if not _power_sweeps.is_empty(): _power_sweeps[0].queue_redraw()

func _draw_power_sweep(sweep: Control, index: int) -> void:
	if index == 0 and _pending_power != null:
		PowerVisual.draw_on(sweep, Rect2(Vector2.ZERO, sweep.size), _power_charge, _power_armed, _power_available, 0.2)
