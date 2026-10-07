class_name ProgressionHud
extends Control
## The HUD's reward loop for the hero's level (see HeroProgression, TownState): a compact level + XP strip over the hotbar, a brief plate
## when a level is reached, and a quiet "points available" mark while Passive or Evolution Points wait to be spent. It owns no progression
## state: the strip reads TownState every frame, and the plate is built from `ProgressionEvents.hero_leveled` (an award that crosses several
## levels is one event; awards landing while the plate is still up are folded into it, not stacked). Drawn in code like the rest of the HUD.

const TOAST_SECONDS := 3.2
const TOAST_IN := 0.22
const TOAST_OUT := 0.7
const STRIP_HEIGHT := 18.0
## Where the strip sits above the hotbar's top edge (the stamina bar is the line just above the slots).
const STRIP_LIFT := 40.0

var toast_text: String = ""
var toast_points: String = ""
var toast_levels: int = 0          # levels the plate in view covers (more than one reads "+N levels")
var toast_passive: int = 0
var toast_evolution: int = 0
var toast_time: float = 0.0
var toast_count: int = 0           # how many hero_leveled events were folded into the plate (tests read it)

var _hud: Hud
var _shown_level: int = 0
var _shown_fraction: float = 0.0   # what the bar draws: eases toward the real fraction, restarts at 0 on a new level
var _flash: float = 0.0            # a brief brightening when XP arrives
var _clock: float = 0.0
var _connected: bool = false

func _ready() -> void:
	_hud = get_parent() as Hud
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shown_level = TownState.hero_level
	_shown_fraction = HeroProgression.level_fraction(TownState.hero_xp)
	if not TownState.events.hero_leveled.is_connected(_on_hero_leveled):
		TownState.events.hero_leveled.connect(_on_hero_leveled)
		TownState.events.hero_xp_changed.connect(_on_xp_changed)
		_connected = true

func _exit_tree() -> void:
	if _connected:
		if TownState.events.hero_leveled.is_connected(_on_hero_leveled):
			TownState.events.hero_leveled.disconnect(_on_hero_leveled)
		if TownState.events.hero_xp_changed.is_connected(_on_xp_changed):
			TownState.events.hero_xp_changed.disconnect(_on_xp_changed)
		_connected = false

func _on_xp_changed(old_xp: int, new_xp: int) -> void:
	if new_xp > old_xp:
		_flash = 1.0
	else:   # the hero was set back (a developer command or a reload): no celebration, the strip just follows
		_shown_level = TownState.hero_level
		_shown_fraction = HeroProgression.level_fraction(new_xp)

## One level-up, or several at once. A plate still on screen takes the new award into its totals and shows the level now reached.
func _on_hero_leveled(old_level: int, new_level: int, _new_xp: int, passive_gained: int, evolution_gained: int) -> void:
	if toast_time > 0.0:
		toast_levels += new_level - old_level
		toast_passive += passive_gained
		toast_evolution += evolution_gained
	else:
		toast_levels = new_level - old_level
		toast_passive = passive_gained
		toast_evolution = evolution_gained
	toast_count += 1
	toast_text = "LEVEL %d" % new_level
	toast_points = HeroProgression.points_text(toast_passive, toast_evolution)
	toast_time = TOAST_SECONDS
	if is_inside_tree():
		Sfx.sample(self, "leap_land", -12.0, 0.75)

func _process(delta: float) -> void:
	_clock += delta
	toast_time = maxf(toast_time - delta, 0.0)
	_flash = maxf(_flash - delta * 2.2, 0.0)
	if TownState.hero_level != _shown_level:   # a new level: the bar starts over and fills to what is left
		_shown_level = TownState.hero_level
		_shown_fraction = 0.0
	_shown_fraction = move_toward(_shown_fraction, HeroProgression.level_fraction(TownState.hero_xp), delta * 1.6)
	queue_redraw()

## Passive and Evolution Points waiting to be spent, as {passive, evolution}. Only points something can still buy count: a skill takes one
## evolution and there are few passives, so points beyond that would otherwise nag forever.
static func points_waiting() -> Dictionary:
	var passive: int = 0
	for id in BuildDefs.PASSIVE_ORDER:
		if not TownState.has_passive(id):
			passive += 1
	var evolution: int = 0
	for skill in BuildDefs.EVOLUTION_SKILLS:
		if TownState.selected_evolution(skill) == "":
			evolution += 1
	return {"passive": mini(TownState.passive_points_available(), passive), "evolution": mini(TownState.evolution_points_available(), evolution)}

## "2 Passive  1 Evolution points available", or "" when everything has been spent.
static func points_available_text() -> String:
	var waiting: Dictionary = points_waiting()
	var parts: PackedStringArray = []
	if int(waiting["passive"]) > 0:
		parts.append("%d Passive" % int(waiting["passive"]))
	if int(waiting["evolution"]) > 0:
		parts.append("%d Evolution" % int(waiting["evolution"]))
	if parts.is_empty():
		return ""
	return "%s %s available" % [" + ".join(parts), "point" if (int(waiting["passive"]) + int(waiting["evolution"])) == 1 else "points"]

## The strip's text: "LV 7" and "420 / 650" (or "MAX" at the cap).
static func level_text() -> String:
	return "LV %d" % TownState.hero_level

static func xp_text() -> String:
	return "MAX" if HeroProgression.is_max_level(TownState.hero_xp) else "%d / %d" % [HeroProgression.xp_into_level(TownState.hero_xp), HeroProgression.xp_span_of_level(TownState.hero_xp)]

## The strip's rectangle, in screen pixels, for the viewport size (the hotbar's width, above its stamina line).
func strip_rect(size_px: Vector2) -> Rect2:
	var slot: float = _hud.hotbar_slot_size(size_px)
	var count: int = (_hud.player.skills.hotbar.size() + 2) if _hud.player != null else 8
	var total: float = slot * count + 8.0 * (count - 1)
	var y0: float = size_px.y - slot - 24.0
	return Rect2(Vector2((size_px.x - total) * 0.5, y0 - STRIP_LIFT), Vector2(total, STRIP_HEIGHT))

func _draw() -> void:
	if _hud == null or _hud.player == null:
		return
	var size_px: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	if not _hud.player.dead:
		_draw_strip(size_px, font)
	_draw_toast(size_px, font)

func _draw_strip(size_px: Vector2, font: Font) -> void:
	var rect: Rect2 = strip_rect(size_px)
	var maxed: bool = HeroProgression.is_max_level(TownState.hero_xp)
	var level: String = level_text()
	var level_w: float = font.get_string_size(level, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var xp: String = xp_text()
	var xp_w: float = font.get_string_size(xp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	UiTheme.text(self, font, rect.position + Vector2(0, 14), level, 15, UiTheme.BRONZE_LIGHT.lightened(0.3))
	UiTheme.text(self, font, rect.position + Vector2(rect.size.x - xp_w, 13), xp, 13, UiTheme.TEXT_DIM)
	var bar := Rect2(rect.position + Vector2(level_w + 10.0, 6.0), Vector2(rect.size.x - level_w - xp_w - 22.0, 6.0))
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.6))
	draw_rect(bar, Color(0.02, 0.02, 0.03, 0.95))
	var fraction: float = 1.0 if maxed else _shown_fraction
	var fill: Color = UiTheme.BRONZE_LIGHT.darkened(0.15) if maxed else UiTheme.EMBER.darkened(0.2).lerp(UiTheme.EMBER.lightened(0.25), _flash)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), fill)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y * 0.4)), Color(1, 1, 1, 0.12))
	draw_rect(bar.grow(2.0), UiTheme.BRONZE.darkened(0.1), false, 1.0)
	var waiting: String = points_available_text()
	if waiting != "":   # a slow ember breath, not a flash: it stays until the points are spent
		var pulse: float = 0.72 + 0.28 * sin(_clock * 2.4)
		var width: float = font.get_string_size(waiting, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var chip := Rect2(Vector2(rect.position.x + (rect.size.x - width) * 0.5 - 12.0, rect.position.y - 24.0), Vector2(width + 24.0, 20.0))
		UiTheme.draw_panel(self, chip, 0.7, false)
		draw_circle(chip.position + Vector2(10.0, 10.0), 2.6, Color(UiTheme.EMBER.r, UiTheme.EMBER.g, UiTheme.EMBER.b, pulse))
		UiTheme.text(self, font, chip.position + Vector2(18.0, 15.0), waiting, 14, Color(UiTheme.EMBER.lightened(0.3), pulse))

func _draw_toast(size_px: Vector2, font: Font) -> void:
	if toast_time <= 0.0:
		return
	var age: float = TOAST_SECONDS - toast_time
	var fade: float = clampf(minf(age / TOAST_IN, toast_time / TOAST_OUT), 0.0, 1.0)
	var slide: float = (1.0 - clampf(age / TOAST_IN, 0.0, 1.0)) * -12.0
	var lines: int = (1 if toast_levels > 1 else 0) + (1 if toast_points != "" else 0)
	var width: float = maxf(240.0, font.get_string_size(toast_points, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 56.0)
	var plate := Rect2(Vector2((size_px.x - width) * 0.5, 62.0 + slide), Vector2(width, 54.0 + 22.0 * lines))   # below the target bar
	UiTheme.draw_panel(self, plate, 0.9 * fade, false)
	var spread: float = clampf(age / 0.35, 0.0, 1.0)   # the ember line draws out from the middle
	var line_w: float = (plate.size.x - 48.0) * spread
	draw_rect(Rect2(Vector2(plate.get_center().x - line_w * 0.5, plate.position.y + 41.0), Vector2(line_w, 2)), Color(UiTheme.EMBER.r, UiTheme.EMBER.g, UiTheme.EMBER.b, 0.8 * fade))
	UiTheme.text(self, font, plate.position + Vector2(0, 33), toast_text, 30, Color(UiTheme.BRONZE_LIGHT.lightened(0.35), fade), HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	var row: float = 62.0
	if toast_levels > 1:
		UiTheme.text(self, font, plate.position + Vector2(0, row), "+%d levels" % toast_levels, 15, Color(UiTheme.TEXT_DIM, fade), HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
		row += 22.0
	if toast_points != "":
		UiTheme.text(self, font, plate.position + Vector2(0, row), toast_points, 15, Color(UiTheme.EMBER.lightened(0.35), fade), HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
