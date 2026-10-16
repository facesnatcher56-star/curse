class_name Ds2PartyCard
extends Control
## Live party state in the shared worn-gold theme; recharge remains inside each power.
## Unspent skill points show a pulsing plus over the portrait; clicking it asks for that member's skill tree (`skills_requested`).
const PowerVisual := preload("res://game/ui/power_button_visual.gd")
signal skills_requested(member_id: String)
const BADGE_CENTRE := Vector2(42, 41)   # centered over the portrait image
const BADGE_RADIUS := 21.0
var character_name: String = "Hero"
var member_id: String = "hero"
var is_companion: bool = false
var skill_points: int = 0
var _seen_points: int = -1   # the points the last update saw (-1: none yet); a rise from it is a level-up
var _earned: bool = false     # a point was earned while this game ran, so the plus is up
var _badge: Control
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
	member_id = "cutter" if companion else "hero"
	custom_minimum_size = Vector2(240, 96)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	gui_input.connect(_select_input)

func _select_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	# The badge is part of this card, so its press is consumed here: it never selects the member or reaches the world.
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and _badge_hit(click.position):
		if skill_points > 0:
			skills_requested.emit(member_id)
		accept_event()
		return
	if (click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
		PartyManager.current().select(member_id)
		accept_event()

func _badge_hit(at: Vector2) -> bool:
	return _badge != null and _badge.visible and at.distance_to(BADGE_CENTRE) <= BADGE_RADIUS + 4.0

## Shows the plus once this game has seen the member earn a skill point (a level-up), and keeps it up until the points are spent. Points
## already waiting when the game starts do not raise it (the caller counts them with TownState; the card does not recount).
func set_skill_points(points: int) -> void:
	points = maxi(points, 0)
	if _seen_points >= 0 and points > _seen_points:
		_earned = true
	if points == 0:
		_earned = false
	_seen_points = points
	skill_points = points
	if _badge != null:
		_badge.visible = skill_points > 0 and _earned
		_badge.queue_redraw()

func _draw_badge() -> void:
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0022)
	var halo_radius: float = BADGE_RADIUS + 2.0 + 2.5 * pulse
	_badge.draw_circle(BADGE_CENTRE, halo_radius, Color("ffd34e", 0.10 + 0.16 * pulse))
	_badge.draw_arc(BADGE_CENTRE, BADGE_RADIUS, 0.0, TAU, 48, Color("ffe16a", 0.68 + 0.32 * pulse), 2.0, true)
	var arm: float = 16.0 + 1.5 * pulse
	var weight: float = 8.0 + 1.0 * pulse
	# Oversized cross fills the portrait while a dark edge preserves its shape over the face art.
	_badge.draw_line(BADGE_CENTRE + Vector2(-arm, 0), BADGE_CENTRE + Vector2(arm, 0), Color("241707", 0.96), weight + 4.0, true)
	_badge.draw_line(BADGE_CENTRE + Vector2(0, -arm), BADGE_CENTRE + Vector2(0, arm), Color("241707", 0.96), weight + 4.0, true)
	_badge.draw_line(BADGE_CENTRE + Vector2(-arm, 0), BADGE_CENTRE + Vector2(arm, 0), Color("ffe16a"), weight, true)
	_badge.draw_line(BADGE_CENTRE + Vector2(0, -arm), BADGE_CENTRE + Vector2(0, arm), Color("ffe16a"), weight, true)
	if _badge.has_focus():   # keyboard / pad focus: a bright ring outside the plus
		_badge.draw_arc(BADGE_CENTRE, BADGE_RADIUS + 4.0, 0.0, TAU, 40, UiTheme.TEXT, 2.0, true)

func _process(_delta: float) -> void:
	if is_instance_valid(_badge) and _badge.visible:
		_badge.queue_redraw()

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
	# Added last so the plus sits over the portrait. The card takes the press (see _select_input), so the badge ignores the mouse itself.
	_badge = Control.new()
	_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the mouse is handled by the card (_select_input); the keyboard or pad reaches the plus by focus
	_badge.focus_mode = Control.FOCUS_ALL
	_badge.visible = false
	_badge.draw.connect(_draw_badge)
	_badge.focus_entered.connect(_badge.queue_redraw)
	_badge.focus_exited.connect(_badge.queue_redraw)
	_badge.gui_input.connect(_badge_input)
	add_child(_badge)

## The focused plus: accept opens this member's skill tree, as a click on it does.
func _badge_input(event: InputEvent) -> void:
	if skill_points > 0 and event.is_action_pressed("ui_accept"):
		skills_requested.emit(member_id)
		_badge.accept_event()

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
