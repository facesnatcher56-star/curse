class_name Ds2TargetBanner
extends Control
## Dungeon Siege II-style ornate target banner at top-center.
## Shows target name, enemy tier, and health bar inside an ornate metal plaque.

var _banner_rect: Panel
var _damage_trail: ColorRect
var _hp_fill: ColorRect
var _name_label: Label
var _health_label: Label
var _level_label: Label
var _fade: float = 0.0
var _tracked_target_id: int = 0
var _displayed_hp_ratio: float = -1.0
var _trail_hp_ratio: float = -1.0
var _trail_hold: float = 0.0
var _hit_flash: float = 0.0

const WIDTH := 480.0
const HEIGHT := 68.0
const BAR_WIDTH := 400.0
const TRAIL_HOLD_SECONDS := 0.32
const TRAIL_CATCHUP_PER_SECOND := 1.8
const HIT_FLASH_SECONDS := 0.12

## Presentation only: no HP/level threshold may turn an ordinary enemy elite.
static func status_of(target: Actor) -> String:
	if target.is_boss: return "BOSS"
	if target.has_meta("monster_uid") or target.has_meta("quest_uid"): return "UNIQUE"
	if target is Enemy and target.def != null:
		if target.def.tier == "miniboss": return "MINIBOSS"
		if target.def.tier == "strong": return "STRONG"
	return ""

static func status_color(target: Actor) -> Color:
	match status_of(target):
		"BOSS": return Color(1.0, 0.48, 0.32)
		"UNIQUE", "MINIBOSS": return Color(1.0, 0.8, 0.35)
		"STRONG": return Color(0.45, 0.75, 1.0)
	return Color(1.0, 0.92, 0.78)

static func health_text(current: float, maximum: float) -> String:
	return "%d / %d" % [ceili(clampf(current, 0.0, maximum)), ceili(maximum)]

func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	# Center at top
	var screen: Vector2 = get_viewport_rect().size
	position = Vector2((screen.x - WIDTH) * 0.5, 4.0)
	modulate = Color(1, 1, 1, 0)

	var root := Control.new()
	root.custom_minimum_size = size
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Ornate plaque frame
	_banner_rect = Panel.new()
	_banner_rect.add_theme_stylebox_override("panel", UiTheme.framed("button", 0))
	_banner_rect.custom_minimum_size = size
	_banner_rect.size = size
	_banner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner_rect)

	# Delayed damage trail sits behind the immediate health fill.
	_damage_trail = ColorRect.new()
	_damage_trail.color = Color(1.0, 0.42, 0.24, 0.82)
	_damage_trail.position = Vector2(40, 36)
	_damage_trail.size = Vector2(BAR_WIDTH, 24)
	_damage_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_damage_trail)

	# Health fill bar inside plaque
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.85, 0.15, 0.12, 0.95)
	_hp_fill.position = Vector2(40, 36)
	_hp_fill.size = Vector2(BAR_WIDTH, 24)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_fill)

	# Monster Name Label
	_name_label = Label.new()
	_name_label.position = Vector2(24, 5)
	_name_label.size = Vector2(432, 28)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", UiTheme.heading_font())
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.78))
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_name_label)

	# Health Numbers Label
	_health_label = Label.new()
	_health_label.position = Vector2(128, 35)
	_health_label.size = Vector2(224, 26)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 18)
	_health_label.add_theme_font_override("font", ThemeDB.fallback_font) # Clear numerals at small physical sizes.
	_health_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_health_label.add_theme_constant_override("outline_size", 2)
	_health_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_health_label)

	# The monster's level, inside the health bar at its left end.
	_level_label = Label.new()
	_level_label.position = Vector2(46, 35)
	_level_label.size = Vector2(80, 26)
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 17)
	_level_label.add_theme_font_override("font", ThemeDB.fallback_font)
	_level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_level_label.add_theme_constant_override("outline_size", 2)
	_level_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.62))
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_level_label)

func update_target(target: Actor, delta: float) -> void:
	var screen: Vector2 = get_viewport_rect().size
	# Keep text readable even at the smallest interface scale.
	var physical_scale := maxf(float(get_window().size.x) / screen.x, 0.01)
	var readable_scale := maxf(1.0, 1.0 / physical_scale) # At least 18 physical pixels for HP.
	# Reserve the actual 240-wide party cards and the opposite objective panel.
	var available_scale := maxf(0.65, (screen.x - 500.0) / WIDTH)
	scale = Vector2.ONE * minf(readable_scale, available_scale)
	position.x = (screen.x - WIDTH * scale.x) * 0.5
	position.y = 4.0 if position.x >= 250.0 else 202.0
	var has_target := is_instance_valid(target) and not target.is_queued_for_deletion() and not target.dead
	if has_target:
		_fade = minf(_fade + delta * 6.0, 1.0)
		var target_id := target.get_instance_id()
		var target_changed := target_id != _tracked_target_id
		if target_changed:
			_tracked_target_id = target_id
			_displayed_hp_ratio = -1.0
			_trail_hp_ratio = -1.0
			_trail_hold = 0.0
			_hit_flash = 0.0
		var status := status_of(target)
		_name_label.text = target.display_name.to_upper() + ("  ·  " + status if not status.is_empty() else "")
		var name_font := _name_label.get_theme_font("font")
		var name_size := 20
		while name_size > 16 and name_font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > _name_label.size.x:
			name_size -= 1
		_name_label.add_theme_font_size_override("font_size", name_size)
		var cur_hp: float = maxf(target.health, 0.0)
		var max_hp: float = maxf(target.max_health, 1.0)
		var pct: float = clampf(cur_hp / max_hp, 0.0, 1.0)
		if _displayed_hp_ratio < 0.0:
			_displayed_hp_ratio = pct
			_trail_hp_ratio = pct
		elif pct < _displayed_hp_ratio - 0.0001:
			# Damage snaps the real bar down and holds the previous value briefly.
			_trail_hp_ratio = maxf(_trail_hp_ratio, _displayed_hp_ratio)
			_trail_hold = TRAIL_HOLD_SECONDS
			_hit_flash = HIT_FLASH_SECONDS
		elif pct > _displayed_hp_ratio + 0.0001:
			# Healing/regeneration is immediate and never leaves a misleading damage trail.
			_trail_hp_ratio = pct
			_trail_hold = 0.0
		_displayed_hp_ratio = pct
		if _trail_hold > 0.0:
			_trail_hold = maxf(_trail_hold - delta, 0.0)
		elif _trail_hp_ratio > pct:
			_trail_hp_ratio = maxf(pct, _trail_hp_ratio - TRAIL_CATCHUP_PER_SECOND * delta)
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		_damage_trail.size.x = _trail_hp_ratio * BAR_WIDTH
		_hp_fill.size.x = pct * BAR_WIDTH
		_health_label.text = health_text(cur_hp, max_hp)
		_level_label.text = "LV %d" % target.level
		
		_name_label.add_theme_color_override("font_color", status_color(target))
		var base_fill := Color(0.65, 0.12, 0.1, 0.95) if status.is_empty() else Color(status_color(target).darkened(0.55), 0.95)
		_hp_fill.color = base_fill.lerp(Color(1.0, 0.9, 0.72, 1.0), _hit_flash / HIT_FLASH_SECONDS)
		_damage_trail.color = Color(0.95, 0.43, 0.26, 0.82) if status.is_empty() else Color(status_color(target).lightened(0.12), 0.8)
		# Both decorative layers ignore mouse input, so world clicks pass through the banner.
	else:
		if target != null and is_instance_valid(target) and target.dead:
			_hp_fill.size.x = 0.0
			_damage_trail.size.x = 0.0
			_health_label.text = health_text(0.0, maxf(target.max_health, 1.0))
		else:
			_hp_fill.size.x = 0.0
			_damage_trail.size.x = 0.0
			_name_label.text = ""
			_health_label.text = ""
			_level_label.text = ""
		_tracked_target_id = 0
		_displayed_hp_ratio = -1.0
		_trail_hp_ratio = -1.0
		_trail_hold = 0.0
		_hit_flash = 0.0
		_fade = maxf(_fade - delta * 4.0, 0.0)

	modulate = Color(1, 1, 1, _fade)
	visible = _fade > 0.01
