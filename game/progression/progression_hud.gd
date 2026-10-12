class_name ProgressionHud
extends Control
## The HUD's reward loop for the hero's level (see HeroProgression, TownState): a compact level + XP strip over the hotbar, a brief plate
## when a level is reached. It owns no progression state: the strip reads TownState every frame, and the plate is built from `ProgressionEvents.hero_leveled` (an award that crosses several
## levels is one event; awards landing while the plate is still up are folded into it, not stacked). Drawn in code like the rest of the HUD.

const TOAST_SECONDS := 3.2
const CLASS_NOTICE_SECONDS := 5.0 # Previously 2 seconds; owner requested three extra.
const TOAST_IN := 0.22
const TOAST_OUT := 0.7
const STRIP_HEIGHT := 18.0
## Where the strip sits above the hotbar's top edge (the stamina bar is the line just above the slots).
const STRIP_LIFT := 40.0

var toast_text: String = ""
var toast_levels: int = 0          # levels the plate in view covers (more than one reads "+N levels")
var toast_time: float = 0.0
var toast_count: int = 0           # how many hero_leveled events were folded into the plate (tests read it)

var _hud: Hud
var _shown_level: int = 0
var _shown_fraction: float = 0.0   # what the bar draws: eases toward the real fraction, restarts at 0 on a new level
var _flash: float = 0.0            # a brief brightening when XP arrives
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
		TownState.events.member_class_skills_leveled.connect(_on_class_skills_leveled)
		_connected = true

func _exit_tree() -> void:
	if _connected:
		if TownState.events.hero_leveled.is_connected(_on_hero_leveled):
			TownState.events.hero_leveled.disconnect(_on_hero_leveled)
		if TownState.events.hero_xp_changed.is_connected(_on_xp_changed):
			TownState.events.hero_xp_changed.disconnect(_on_xp_changed)
		if TownState.events.member_class_skills_leveled.is_connected(_on_class_skills_leveled):
			TownState.events.member_class_skills_leveled.disconnect(_on_class_skills_leveled)
		_connected = false

## Discipline feedback follows the earner, never whichever member is selected.
func _on_class_skills_leveled(member_id: String, levels: Dictionary) -> void:
	var body := PartyManager.current().bodies.get(member_id) as Player
	if _hud == null or not is_instance_valid(body) or body.dead:
		return
	var lines: PackedStringArray = []
	for id in HeroAttributes.CLASSES:
		if levels.has(id):
			lines.append("%s increased to %d" % [HeroAttributes.CLASS_NAMES[id], int(levels[id])])
	if not lines.is_empty():
		Fx.text_at(body, body.global_position + Vector3(0, body.body_height + 0.6, 0), "\n".join(lines), UiTheme.BRONZE_LIGHT, 32, CLASS_NOTICE_SECONDS)

func _on_xp_changed(old_xp: int, new_xp: int) -> void:
	if new_xp > old_xp:
		_flash = 1.0
	else:   # the hero was set back (a developer command or a reload): no celebration, the strip just follows
		_shown_level = TownState.hero_level
		_shown_fraction = HeroProgression.level_fraction(new_xp)

## One level-up, or several at once. A plate still on screen takes the new award into its totals and shows the level now reached.
func _on_hero_leveled(old_level: int, new_level: int, _new_xp: int) -> void:
	if toast_time > 0.0:
		toast_levels += new_level - old_level
	else:
		toast_levels = new_level - old_level
	toast_count += 1
	toast_text = "LEVEL %d" % new_level
	toast_time = TOAST_SECONDS
	if is_inside_tree():
		Sfx.sample(self, "leap_land", -12.0, 0.75)

func _process(delta: float) -> void:
	toast_time = maxf(toast_time - delta, 0.0)
	_flash = maxf(_flash - delta * 2.2, 0.0)
	if TownState.hero_level != _shown_level:   # a new level: the bar starts over and fills to what is left
		_shown_level = TownState.hero_level
		_shown_fraction = 0.0
	_shown_fraction = move_toward(_shown_fraction, HeroProgression.level_fraction(TownState.hero_xp), delta * 1.6)
	queue_redraw()

## The strip's text: "LV 7" and "420 / 650" (or "MAX" at the cap).
static func level_text() -> String:
	return "LV %d" % TownState.hero_level

static func xp_text() -> String:
	return "MAX" if HeroProgression.is_max_level(TownState.hero_xp) else "%d / %d" % [HeroProgression.xp_into_level(TownState.hero_xp), HeroProgression.xp_span_of_level(TownState.hero_xp)]

## The XP strip's rectangle, in screen pixels, for the viewport size: a long thin bar along the very bottom, under the hotbar's tray, with the
## level badge at its left end (drawn in `_draw_strip`; the badge is outside this rectangle, to its left).
func strip_rect(size_px: Vector2) -> Rect2:
	if _hud != null and _hud.use_ds2_ui:
		return Rect2()
	var slot: float = _hud.hotbar_slot_size(size_px)
	var count: int = (_hud.player.skills.hotbar.size() + 2) if _hud.player != null else 8
	var total: float = slot * count + 8.0 * (count - 1)
	var left: float = (size_px.x - total) * 0.5 - 24.0
	var y_pos: float = size_px.y - 31.0
	return Rect2(Vector2(left + 38.0, y_pos), Vector2(total + 48.0 - 38.0, 16.0))

func _draw() -> void:
	if _hud == null or _hud.player == null:
		return
	var size_px: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	if not _hud.player.dead and not _hud.use_ds2_ui:
		_draw_strip(size_px, font)
	_draw_toast(size_px, font)

func _draw_strip(size_px: Vector2, font: Font) -> void:
	var rect: Rect2 = strip_rect(size_px)
	var maxed: bool = HeroProgression.is_max_level(TownState.hero_xp)
	var xp: String = xp_text()
	var xp_w: float = font.get_string_size(xp, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var bar := Rect2(rect.position + Vector2(0.0, 3.0), Vector2(rect.size.x - xp_w - 14.0, 9.0))
	draw_rect(bar.grow(3.0), Color(0, 0, 0, 0.7))
	draw_rect(bar, Color(0.02, 0.02, 0.03, 0.95))
	var fraction: float = 1.0 if maxed else _shown_fraction
	var fill: Color = UiTheme.BRONZE_LIGHT.darkened(0.15) if maxed else UiTheme.EMBER.darkened(0.2).lerp(UiTheme.EMBER.lightened(0.25), _flash)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), fill)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y * 0.4)), Color(1, 1, 1, 0.12))
	draw_rect(bar.grow(3.0), UiTheme.BRONZE.darkened(0.15), false, 1.0)
	UiTheme.text(self, font, Vector2(rect.end.x - xp_w, rect.position.y + 12.0), xp, 12, UiTheme.TEXT_DIM)
	# The level badge: a round iron boss with a bronze rim, the number in the engraved face.
	var badge: Vector2 = Vector2(rect.position.x - 21.0, rect.position.y + 7.5)
	draw_circle(badge + Vector2(0, 2), 19.0, Color(0, 0, 0, 0.55))
	draw_circle(badge, 17.0, Color(0.05, 0.047, 0.055))
	draw_arc(badge, 16.0, 0.0, TAU, 40, UiTheme.BRONZE_LIGHT.darkened(0.2), 2.0)
	draw_arc(badge, 12.5, 0.0, TAU, 32, UiTheme.BRONZE.darkened(0.3), 1.0)
	var level_number: String = str(TownState.hero_level)
	UiTheme.text(self, UiTheme.heading_font(), badge + Vector2(-20.0, 6.0), level_number, 17, UiTheme.BRONZE_LIGHT.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, 40.0)

func _draw_toast(size_px: Vector2, font: Font) -> void:
	if toast_time <= 0.0:
		return
	var age: float = TOAST_SECONDS - toast_time
	var fade: float = clampf(minf(age / TOAST_IN, toast_time / TOAST_OUT), 0.0, 1.0)
	var slide: float = (1.0 - clampf(age / TOAST_IN, 0.0, 1.0)) * -12.0
	var lines: int = 1 if toast_levels > 1 else 0
	var width: float = 240.0
	var target_bottom := 80.0
	if _hud.use_ds2_ui and is_instance_valid(_hud.ds2_target_banner) and _hud.ds2_target_banner.visible:
		target_bottom = _hud.ds2_target_banner.get_global_rect().end.y + 12.0
	var plate := Rect2(Vector2((size_px.x - width) * 0.5, target_bottom + slide), Vector2(width, 54.0 + 22.0 * lines))
	UiTheme.draw_panel(self, plate, 0.9 * fade, false)
	var spread: float = clampf(age / 0.35, 0.0, 1.0)   # the ember line draws out from the middle
	var line_w: float = (plate.size.x - 48.0) * spread
	draw_rect(Rect2(Vector2(plate.get_center().x - line_w * 0.5, plate.position.y + 41.0), Vector2(line_w, 2)), Color(UiTheme.EMBER.r, UiTheme.EMBER.g, UiTheme.EMBER.b, 0.8 * fade))
	UiTheme.text(self, font, plate.position + Vector2(0, 33), toast_text, 30, Color(UiTheme.BRONZE_LIGHT.lightened(0.35), fade), HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	var row: float = 62.0
	if toast_levels > 1:
		UiTheme.text(self, font, plate.position + Vector2(0, row), "+%d levels" % toast_levels, 15, Color(UiTheme.TEXT_DIM, fade), HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)

