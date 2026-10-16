class_name ProgressionHud
extends Control
## The HUD's reward loop for the hero's level: a compact level + XP strip over the hotbar. The level-up celebration is in-world, attached to the earning character.

const CLASS_NOTICE_SECONDS := 5.0 # Previously 2 seconds; owner requested three extra.
const STRIP_HEIGHT := 18.0
## Where the strip sits above the hotbar's top edge (the stamina bar is the line just above the slots).
const STRIP_LIFT := 40.0
const MELEE_RANK_FX: Script = preload("res://game/fx/melee_rank_up_fx.gd")

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
	TownState.events.hero_xp_changed.connect(_on_xp_changed)
	TownState.events.member_class_skills_leveled.connect(_on_class_skills_leveled)
	_connected = true

func _exit_tree() -> void:
	if _connected:
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
			if id == "melee":
				var old_fx := body.get_node_or_null("MeleeRankUpFx")
				if old_fx != null:
					old_fx.queue_free()
				var rank_fx := MELEE_RANK_FX.new() as Node3D
				rank_fx.name = "MeleeRankUpFx"
				body.add_child(rank_fx)
				rank_fx.call("start", int(levels[id]))
				continue
			lines.append("%s increased to %d" % [HeroAttributes.CLASS_NAMES[id], int(levels[id])])
	if not lines.is_empty():
		Fx.text_at(body, body.global_position + Vector3(0, body.body_height + 0.6, 0), "\n".join(lines), UiTheme.BRONZE_LIGHT, 32, CLASS_NOTICE_SECONDS)

func _on_xp_changed(old_xp: int, new_xp: int) -> void:
	if new_xp > old_xp:
		_flash = 1.0
	else:   # the hero was set back (a developer command or a reload): no celebration, the strip just follows
		_shown_level = TownState.hero_level
		_shown_fraction = HeroProgression.level_fraction(new_xp)

func _process(delta: float) -> void:
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

## Legacy callers use this geometry to avoid the old screen-space toast. There is no HUD plate now.
func toast_rect(_size_px: Vector2) -> Rect2:
	return Rect2()

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

