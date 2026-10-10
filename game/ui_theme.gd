class_name UiTheme
extends RefCounted
## One dark, muted theme for every menu so they look like part of the game.

const BG := Color(0.082, 0.060, 0.050, 0.96)
const PANEL := Color(0.125, 0.092, 0.074, 0.98)
const BORDER := Color(0.45, 0.34, 0.20)
const ACCENT := Color(0.92, 0.72, 0.38)
const TEXT := Color(0.94, 0.86, 0.70)
const TEXT_DIM := Color(0.68, 0.58, 0.44)

## Resource bars and the wear-and-tear trim: muted, one warm accent (docs/ART_DIRECTION.md).
const BLOOD := Color(0.66, 0.11, 0.08)
const MANA := Color(0.16, 0.34, 0.62)
const STAMINA := Color(0.70, 0.56, 0.22)
const BRONZE := Color(0.54, 0.38, 0.16)
const BRONZE_LIGHT := Color(0.84, 0.64, 0.30)
const EMBER := Color(0.95, 0.56, 0.22)
const INK := Color(0.060, 0.042, 0.036)

static var _cached: Theme

static func get_theme() -> Theme:
	if _cached == null:
		_cached = _build()
	return _cached

static func box(color: Color, border: Color = BORDER, border_width: int = 1, radius: int = 3, pad: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(pad)
	return style

## A worn-metal panel for menus: dark fill, a dark outer edge and a bronze inner one, a soft shadow.
static func panel_box() -> StyleBoxFlat:
	var style := box(Color(0.085, 0.08, 0.095, 0.97), BRONZE.darkened(0.2), 2, 3, 20)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	return style

static func _button_box(fill: Color, edge: Color, glow: bool) -> StyleBoxFlat:
	var style := box(fill, edge, 1, 1, 10)   # a thin engraved edge, like the reference
	style.border_blend = false
	style.content_margin_left = 16
	style.content_margin_right = 16
	if glow:
		style.shadow_color = Color(EMBER.r, EMBER.g, EMBER.b, 0.18)
		style.shadow_size = 6
	return style

static func _focus_box() -> StyleBoxFlat:
	var style := box(Color(0, 0, 0, 0), EMBER, 2, 2, 10)
	style.shadow_color = Color(EMBER.r, EMBER.g, EMBER.b, 0.35)
	style.shadow_size = 8
	style.draw_center = false
	return style

# --- Drawing helpers for the HUD (any CanvasItem) ------------------------------------------------------------------------

## Text with a drop shadow, so it reads over bright ground and dark alike.
static func text(ci: CanvasItem, font: Font, pos: Vector2, label: String, size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string(font, pos + Vector2(1.5, 1.5), label, align, width, size, Color(0, 0, 0, 0.85 * color.a))
	ci.draw_string(font, pos, label, align, width, size, color)

## A worn-metal plate: shadow, dark fill with a faint sheen, a dark edge, a bronze inner line and small rivets in the corners.
## The small status icons the HUDs draw instead of labels (rendered in Blender by tools/blender/make_ui_icons.py; "potion" is the
## hotbar's own icon). Cached; null when the file is missing so a HUD still draws its numbers.
static var _status_icons: Dictionary = {}

static func status_icon(id: String) -> Texture2D:
	if not _status_icons.has(id):
		var path: String = "res://assets/icons/potion.png" if id == "potion" else "res://assets/icons/ui/%s.png" % id
		_status_icons[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _status_icons[id]

## How wide one status (an icon and its number) is.
static func stat_width(font: Font, value: String, icon_px: float, font_size: int) -> float:
	return icon_px + 6.0 + font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

## An icon with its number beside it, the icon's top left at `at`, the number centred on it. `tint` colours both a warning
## (the food icon goes red when there is not enough). Returns the width used.
static func draw_stat(ci: CanvasItem, font: Font, at: Vector2, icon_id: String, value: String, icon_px: float = 30.0, font_size: int = 22,
		tint: Color = Color.WHITE, text_color: Color = Color(0.95, 0.9, 0.78)) -> float:
	var icon: Texture2D = status_icon(icon_id)
	if icon != null:
		ci.draw_texture_rect(icon, Rect2(at, Vector2(icon_px, icon_px)), false, tint)
	text(ci, font, Vector2(at.x + icon_px + 6.0, at.y + icon_px * 0.5 + font_size * 0.36), value, font_size, text_color)
	return stat_width(font, value, icon_px, font_size)

static func draw_panel(ci: CanvasItem, rect: Rect2, alpha: float = 0.9, rivets: bool = true) -> void:
	ci.draw_rect(rect.grow(4.0), Color(0, 0, 0, 0.28))
	ci.draw_rect(rect, Color(0.07, 0.066, 0.08, alpha))
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.45)), Color(1, 0.95, 0.85, 0.028))
	ci.draw_rect(rect, Color(0, 0, 0, 0.95), false, 2.0)
	ci.draw_rect(rect.grow(-2.0), BRONZE.darkened(0.1), false, 1.0)
	ci.draw_rect(rect.grow(-4.0), Color(1, 1, 1, 0.04), false, 1.0)
	if rivets and rect.size.x > 40.0 and rect.size.y > 30.0:
		for corner in [rect.position + Vector2(7, 7), Vector2(rect.end.x - 7, rect.position.y + 7), Vector2(rect.position.x + 7, rect.end.y - 7), rect.end - Vector2(7, 7)]:
			ci.draw_circle(corner, 2.6, Color(0, 0, 0, 0.8))
			ci.draw_circle(corner, 1.7, BRONZE_LIGHT.darkened(0.25))

## A resource bar: a recessed dark trough, a fill with a lit upper half, tick marks every tenth, a bronze frame and a shadowed label.
static func draw_bar(ci: CanvasItem, rect: Rect2, fraction: float, color: Color, label: String, font: Font, size: int = 13) -> void:
	var f: float = clampf(fraction, 0.0, 1.0)
	ci.draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.55))
	ci.draw_rect(rect, Color(0.02, 0.02, 0.03, 0.95))
	if f > 0.0:
		var fill := Rect2(rect.position, Vector2(rect.size.x * f, rect.size.y))
		ci.draw_rect(fill, color.darkened(0.25))
		ci.draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.5)), color.lightened(0.12))
		ci.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1.0)), color.lightened(0.45))
	for i in range(1, 10):
		var x: float = rect.position.x + rect.size.x * i / 10.0
		ci.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0, 0, 0, 0.28), 1.0)
	ci.draw_rect(rect, Color(0, 0, 0, 0.9), false, 2.0)
	ci.draw_rect(rect.grow(-1.0), BRONZE.darkened(0.2), false, 1.0)
	if label != "":
		text(ci, font, rect.position + Vector2(0, rect.size.y - maxf((rect.size.y - size) * 0.5 + 2.0, 3.0)), label, size,
			Color(0.96, 0.93, 0.86), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

## The engraved heading face (Cinzel, a little heavier than regular): plate titles, menu buttons, names. Body text is the project's default
## font (Crimson Pro, gui/theme/custom_font). Both are OFL, see assets/fonts/CREDITS.md.
static var _heading: Font

static func heading_font() -> Font:
	if _heading == null:
		var base: Font = load("res://assets/fonts/Cinzel.ttf") as Font
		if base == null:
			return ThemeDB.fallback_font
		var variation := FontVariation.new()
		variation.base_font = base
		variation.variation_opentype = {"wght": 600}
		variation.spacing_glyph = 1
		_heading = variation
	return _heading

## The big title face (the game's name): the same engraved capitals, lighter and widely spaced.
static var _title: Font

static func title_font() -> Font:
	if _title == null:
		var base: Font = load("res://assets/fonts/Cinzel.ttf") as Font
		if base == null:
			return ThemeDB.fallback_font
		var variation := FontVariation.new()
		variation.base_font = base
		variation.variation_opentype = {"wght": 500}
		variation.spacing_glyph = 10
		_title = variation
	return _title

static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_font("font", "Button", heading_font())
	theme.set_font_size("font_size", "Button", 17)

	theme.set_stylebox("normal", "Button", _button_box(Color(0.149, 0.116, 0.095), BRONZE.darkened(0.15), false))
	theme.set_stylebox("hover", "Button", _button_box(Color(0.20, 0.16, 0.13), BRONZE_LIGHT, true))
	theme.set_stylebox("pressed", "Button", _button_box(Color(0.28, 0.20, 0.12), EMBER, false))
	theme.set_stylebox("focus", "Button", _focus_box())
	theme.set_stylebox("disabled", "Button", _button_box(Color(0.103, 0.087, 0.068), Color(0.2, 0.19, 0.18), false))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color(1, 0.95, 0.8))
	theme.set_color("font_pressed_color", "Button", Color(1, 0.92, 0.7))
	theme.set_color("font_focus_color", "Button", Color(1, 0.95, 0.8))
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)

	theme.set_stylebox("panel", "PanelContainer", panel_box())
	theme.set_stylebox("background", "ProgressBar", box(INK, BRONZE.darkened(0.15), 2, 2, 0))
	theme.set_stylebox("fill", "ProgressBar", box(EMBER.darkened(0.2), EMBER.darkened(0.45), 1, 2, 0))
	theme.set_color("font_color", "ProgressBar", TEXT)
	theme.set_color("font_color", "Label", TEXT)

	# Tabs
	theme.set_stylebox("tab_selected", "TabContainer", box(PANEL, ACCENT, 1, 3, 10))
	theme.set_stylebox("tab_unselected", "TabContainer", box(Color(0.115, 0.097, 0.082), BORDER, 1, 3, 10))
	theme.set_stylebox("tab_hovered", "TabContainer", box(Color(0.184, 0.145, 0.122), ACCENT, 1, 3, 10))
	theme.set_stylebox("panel", "TabContainer", box(Color(0.103, 0.087, 0.075), BORDER, 1, 3, 14))
	theme.set_color("font_selected_color", "TabContainer", ACCENT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	theme.set_color("font_hovered_color", "TabContainer", TEXT)

	# Sliders
	var slider_track := box(Color(0.184, 0.155, 0.129), BORDER, 1, 3, 0)
	slider_track.content_margin_top = 4
	slider_track.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", slider_track)
	theme.set_stylebox("grabber_area", "HSlider", box(ACCENT.darkened(0.2), ACCENT, 0, 3, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, ACCENT, 0, 3, 0))

	# Dropdowns and checkboxes reuse button styling.
	theme.set_stylebox("normal", "OptionButton", box(Color(0.172, 0.136, 0.116), BORDER, 1, 3, 10))
	theme.set_stylebox("hover", "OptionButton", box(Color(0.22, 0.20, 0.22), ACCENT, 1, 3, 10))
	theme.set_stylebox("pressed", "OptionButton", box(Color(0.30, 0.25, 0.18), ACCENT, 1, 3, 10))
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_stylebox("panel", "PopupMenu", box(PANEL, ACCENT, 1, 3, 6))
	theme.set_stylebox("hover", "PopupMenu", box(Color(0.3, 0.25, 0.18), Color(0, 0, 0, 0), 0, 2, 4))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_color", "CheckBox", TEXT)
	# A checkbox's every state shares ONE padding. (Only some states came from this theme; the rest fell back to the engine's own, with other
	# margins, so the label jumped onto the tick the moment the mouse was over it.)
	theme.set_stylebox("normal", "CheckBox", _check_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", "CheckBox", _check_box(Color(0.20, 0.16, 0.13, 0.55), BRONZE.darkened(0.1)))
	theme.set_stylebox("pressed", "CheckBox", _check_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	theme.set_stylebox("hover_pressed", "CheckBox", _check_box(Color(0.20, 0.16, 0.13, 0.55), BRONZE.darkened(0.1)))
	theme.set_stylebox("disabled", "CheckBox", _check_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	theme.set_stylebox("focus", "CheckBox", _focus_box())
	theme.set_color("font_hover_color", "CheckBox", Color(1, 0.95, 0.8))
	theme.set_color("font_pressed_color", "CheckBox", TEXT)
	theme.set_color("font_hover_pressed_color", "CheckBox", Color(1, 0.95, 0.8))
	theme.set_color("font_focus_color", "CheckBox", Color(1, 0.95, 0.8))
	theme.set_color("font_disabled_color", "CheckBox", TEXT_DIM)
	theme.set_constant("h_separation", "CheckBox", 10)
	return theme

## The checkbox row's look in one state: same margins always, only the fill and edge change.
static func _check_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := box(fill, edge, 1, 2, 6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

## A standard menu button.
## Gives keyboard/pad focus to the first control under `root` that can take it (a button, slider, checkbox...). So a menu opened
## with a controller always has something selected, and the D-pad / left stick move from there.
static func focus_first(root: Node) -> bool:
	if root == null:
		return false
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		var control := node as Control
		if control != null and control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			if not (control is BaseButton and (control as BaseButton).disabled):
				control.grab_focus()
				return true
		queue.append_array(node.get_children())
	return false

static func button(text: String, min_width: float = 260.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 46)
	return b

static func title_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", title_font() if size >= 64 else heading_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ACCENT)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return label
