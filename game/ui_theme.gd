class_name UiTheme
extends RefCounted
## One dark, muted theme for every menu so they look like part of the game.

const BG := Color(0.07, 0.07, 0.09, 0.96)
const PANEL := Color(0.11, 0.11, 0.14, 0.98)
const BORDER := Color(0.32, 0.30, 0.26)
const ACCENT := Color(0.92, 0.72, 0.38)
const TEXT := Color(0.9, 0.88, 0.82)
const TEXT_DIM := Color(0.62, 0.6, 0.56)

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

static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18

	theme.set_stylebox("normal", "Button", box(Color(0.15, 0.14, 0.17), BORDER, 1, 3, 10))
	theme.set_stylebox("hover", "Button", box(Color(0.22, 0.20, 0.22), ACCENT, 1, 3, 10))
	theme.set_stylebox("pressed", "Button", box(Color(0.30, 0.25, 0.18), ACCENT, 2, 3, 10))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT, 2, 3, 10))
	theme.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.12), Color(0.2, 0.2, 0.2), 1, 3, 10))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color(1, 0.95, 0.8))
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)

	theme.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 2, 4, 18))
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
