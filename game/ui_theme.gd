class_name UiTheme
extends RefCounted
## One dark, muted theme for every menu so they look like part of the game.

const BG := Color(0.07, 0.07, 0.09, 0.96)
const PANEL := Color(0.11, 0.11, 0.14, 0.98)
const BORDER := Color(0.32, 0.30, 0.26)
const ACCENT := Color(0.92, 0.72, 0.38)
const TEXT := Color(0.9, 0.88, 0.82)
const TEXT_DIM := Color(0.62, 0.6, 0.56)

## Resource bars and the wear-and-tear trim: muted, one warm accent (docs/ART_DIRECTION.md).
const BLOOD := Color(0.60, 0.12, 0.10)
const MANA := Color(0.20, 0.34, 0.52)
const STAMINA := Color(0.70, 0.56, 0.22)
const BRONZE := Color(0.46, 0.36, 0.22)
const BRONZE_LIGHT := Color(0.72, 0.58, 0.36)
const EMBER := Color(0.95, 0.56, 0.22)
const INK := Color(0.045, 0.042, 0.055)

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
	var style := box(fill, edge, 2, 2, 10)
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

static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18

	theme.set_stylebox("normal", "Button", _button_box(Color(0.13, 0.12, 0.14), BRONZE.darkened(0.15), false))
	theme.set_stylebox("hover", "Button", _button_box(Color(0.20, 0.16, 0.13), BRONZE_LIGHT, true))
	theme.set_stylebox("pressed", "Button", _button_box(Color(0.28, 0.20, 0.12), EMBER, false))
	theme.set_stylebox("focus", "Button", _focus_box())
	theme.set_stylebox("disabled", "Button", _button_box(Color(0.09, 0.09, 0.10), Color(0.2, 0.19, 0.18), false))
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
	theme.set_stylebox("tab_unselected", "TabContainer", box(Color(0.1, 0.1, 0.12), BORDER, 1, 3, 10))
	theme.set_stylebox("tab_hovered", "TabContainer", box(Color(0.16, 0.15, 0.18), ACCENT, 1, 3, 10))
	theme.set_stylebox("panel", "TabContainer", box(Color(0.09, 0.09, 0.11), BORDER, 1, 3, 14))
	theme.set_color("font_selected_color", "TabContainer", ACCENT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	theme.set_color("font_hovered_color", "TabContainer", TEXT)

	# Sliders
	var slider_track := box(Color(0.16, 0.16, 0.19), BORDER, 1, 3, 0)
	slider_track.content_margin_top = 4
	slider_track.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", slider_track)
	theme.set_stylebox("grabber_area", "HSlider", box(ACCENT.darkened(0.2), ACCENT, 0, 3, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, ACCENT, 0, 3, 0))

	# Dropdowns and checkboxes reuse button styling.
	theme.set_stylebox("normal", "OptionButton", box(Color(0.15, 0.14, 0.17), BORDER, 1, 3, 10))
	theme.set_stylebox("hover", "OptionButton", box(Color(0.22, 0.20, 0.22), ACCENT, 1, 3, 10))
	theme.set_stylebox("pressed", "OptionButton", box(Color(0.30, 0.25, 0.18), ACCENT, 1, 3, 10))
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_stylebox("panel", "PopupMenu", box(PANEL, ACCENT, 1, 3, 6))
	theme.set_stylebox("hover", "PopupMenu", box(Color(0.3, 0.25, 0.18), Color(0, 0, 0, 0), 0, 2, 4))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_color", "CheckBox", TEXT)
	return theme

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
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ACCENT)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return label
