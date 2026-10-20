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
var _tag_label: Label
var _elite_frame: Panel
var _chips: AffixChips
var _shield_track: ColorRect
var _shield_fill: ColorRect
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
## Thin, so the shield strip sits above the health numbers and below the tag line, never behind either one.
const SHIELD_H := 4.0

## Presentation only: no HP/level threshold may turn an ordinary enemy elite.
static func status_of(target: Actor) -> String:
	if target.is_boss: return "BOSS"
	if target.has_meta("monster_uid") or target.has_meta("quest_uid"): return "UNIQUE"
	if target is Enemy and target.def != null:
		if target.def.tier == "miniboss": return "MINIBOSS"
		if target.def.tier == "strong": return "STRONG"
	return ""

## The tag line under a champion's, boss's or named monster's name ("SUMMONING CHAMPION", "BOSS"); empty for a regular monster. The DS2 tier names
## ("MINIBOSS", "STRONG") are internal and not shown: they only colour the bar (status_color).
static func tag_of(target: Actor) -> String:
	var enemy := target as Enemy
	if enemy != null and enemy.champion != null:
		return "%s CHAMPION" % String(enemy.champion.affix.title).to_upper()
	var status: String = status_of(target)
	return "" if status in ["MINIBOSS", "STRONG"] else status

## The affix ids a banner shows chips for (empty for anything but a champion).
static func affixes_of(target: Actor) -> Array:
	var enemy := target as Enemy
	if enemy != null and enemy.champion != null:
		return enemy.champion.affix_ids()
	return []

## Champions and bosses get the heavy frame; other tinted targets (elites) the thin one.
static func strong_frame(target: Actor) -> bool:
	return target.is_boss or (target is Enemy and (target as Enemy).champion != null)

## The name as the banner shows it: a champion's affix title moves to the tag, so the name is its plain one.
static func name_of(target: Actor) -> String:
	var enemy := target as Enemy
	if enemy != null and enemy.champion != null and not enemy.champion.base_name.is_empty():
		return enemy.champion.base_name
	return target.display_name

static func status_color(target: Actor) -> Color:
	var enemy := target as Enemy
	if enemy != null and enemy.champion != null:
		return enemy.champion.affix.color
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

	# Champions and elites get a thin frame in their colour over the plaque (hidden for regular monsters).
	_elite_frame = Panel.new()
	var rim := StyleBoxFlat.new()
	rim.bg_color = Color(0, 0, 0, 0)
	rim.set_border_width_all(2)
	rim.set_corner_radius_all(3)
	rim.border_color = Color.WHITE
	_elite_frame.add_theme_stylebox_override("panel", rim)
	_elite_frame.size = size
	_elite_frame.visible = false
	_elite_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_elite_frame)

	# The affix chips sit under the plaque, one row per affix.
	_chips = AffixChips.new()
	_chips.position = Vector2(0, HEIGHT + 4.0)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chips)

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

	# A Warded champion's shield: its own bright segment along the top of the health bar (the dark track shows once it is broken).
	_shield_track = ColorRect.new()
	_shield_track.color = Color(0.02, 0.05, 0.12, 0.85)
	_shield_track.position = Vector2(40, 36)
	_shield_track.size = Vector2(BAR_WIDTH, SHIELD_H)
	_shield_track.visible = false
	_shield_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_shield_track)
	_shield_fill = ColorRect.new()
	_shield_fill.color = Color(0.55, 0.85, 1.0, 1.0)
	_shield_fill.position = Vector2(40, 36)
	_shield_fill.size = Vector2(0, SHIELD_H)
	_shield_fill.visible = false
	_shield_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_shield_fill)

	# Monster Name Label
	_name_label = Label.new()
	_name_label.position = Vector2(24, 5)
	_name_label.size = Vector2(432, 28)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", UiTheme.heading_font())
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.78))
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 5)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_name_label)

	# The affix / tier tag, a small line under the name (champions and elites only).
	_tag_label = Label.new()
	_tag_label.position = Vector2(24, 22)
	_tag_label.size = Vector2(432, 14)
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_label.add_theme_font_size_override("font_size", 12)
	_tag_label.add_theme_font_override("font", UiTheme.heading_font())
	_tag_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_tag_label.add_theme_constant_override("outline_size", 4)
	_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tag_label)

	# Health Numbers Label
	_health_label = Label.new()
	_health_label.position = Vector2(128, 35)
	_health_label.size = Vector2(224, 26)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 18)
	_health_label.add_theme_font_override("font", ThemeDB.fallback_font) # Clear numerals at small physical sizes.
	_health_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_health_label.add_theme_constant_override("outline_size", 4)
	_health_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
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
		var tag := tag_of(target)
		var tinted := not tag.is_empty()
		_name_label.text = name_of(target).to_upper()
		_tag_label.text = tag
		_tag_label.add_theme_color_override("font_color", status_color(target).lightened(0.45))
		_elite_frame.visible = tinted
		if tinted:
			var rim := _elite_frame.get_theme_stylebox("panel") as StyleBoxFlat
			rim.set_border_width_all(5 if strong_frame(target) else 2)
			rim.border_color = Color(status_color(target), 1.0 if strong_frame(target) else 0.85)
		_name_label.position.y = 1.0 if tinted else 5.0
		_name_label.size.y = 22.0 if tinted else 28.0
		var name_font := _name_label.get_theme_font("font")
		var name_size := 18 if tinted else 20
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
		_chips.set_ids(affixes_of(target))
		var ward: Champion = (target as Enemy).champion if target is Enemy else null
		var warded: bool = ward != null and ward.shield_max > 0.0
		_shield_track.visible = warded
		_shield_fill.visible = warded and ward.shield > 0.0
		if warded:
			_shield_fill.size.x = clampf(ward.shield / ward.shield_max, 0.0, 1.0) * BAR_WIDTH
		_health_label.text = health_text(cur_hp, max_hp)
		_level_label.text = "LV %d" % target.level
		
		_name_label.add_theme_color_override("font_color", status_color(target))   # exactly the affix/status colour (a test holds it); the 5 px black outline gives the contrast
		var base_fill := Color(0.65, 0.12, 0.1, 0.95) if not tinted else Color(status_color(target).darkened(0.55), 0.95)
		_hp_fill.color = base_fill.lerp(Color(1.0, 0.9, 0.72, 1.0), _hit_flash / HIT_FLASH_SECONDS)
		_damage_trail.color = Color(0.95, 0.43, 0.26, 0.82) if not tinted else Color(status_color(target).lightened(0.12), 0.8)
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
			_tag_label.text = ""
			_elite_frame.visible = false
			_chips.set_ids([])
			_shield_track.visible = false
			_shield_fill.visible = false
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
