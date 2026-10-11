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
static var _art: Dictionary = {}
const ART_LOGICAL_SIZE := {
	"metal": Vector2i(256, 256), "parchment": Vector2i(256, 192),
	"button": Vector2i(144, 48), "icon": Vector2i(64, 64),
}

## Artwork is reusable nine-slice material, never baked labels or game state.
static func art(id: String) -> Texture2D:
	if not _art.has(id):
		var imported := load("res://assets/ui/ornate/%s.png" % id) as Texture2D
		if ART_LOGICAL_SIZE.has(id):
			# Preserve nine-slice geometry without throwing away high-DPI pixels.
			var texture := ImageTexture.create_from_image(imported.get_image())
			texture.set_size_override(ART_LOGICAL_SIZE[id])
			_art[id] = texture
		else:
			_art[id] = imported
	return _art[id]

static func framed(id: String = "metal", padding: float = 20.0, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = art(id)
	style.set_texture_margin_all(32 if id != "button" else 16)
	if id in ["button", "metal"]:
		# Recessed material repeats instead of smearing into long stripes on
		# tall tooltips or wide HUD plates. Corners remain separate nine-slices.
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.set_content_margin_all(padding)
	style.modulate_color = tint
	return style

const PAPER_INK := Color(0.16, 0.105, 0.055)
const PAPER_DIM := Color(0.30, 0.22, 0.13)

static func parchment_box() -> StyleBoxTexture:
	return framed("parchment", 30)

## Preserve the designed layout at small resolutions / large interface settings.
## Scale only when needed; leave a clear strip for the live hotbar underneath.
static func responsive_window(window: Control, design_size: Vector2 = Vector2.ZERO) -> void:
	var fit := func() -> void: _fit_window.call_deferred(window, design_size)
	window.resized.connect(fit)
	window.minimum_size_changed.connect(fit)
	window.visibility_changed.connect(fit) # Containers reset child scale when a hidden page is shown.
	var viewport := window.get_viewport()
	viewport.size_changed.connect(fit)
	var container := window.get_parent() as Container
	if container != null: container.sort_children.connect(fit)
	window.tree_exiting.connect(func() -> void:
		if viewport.size_changed.is_connected(fit): viewport.size_changed.disconnect(fit)
		if is_instance_valid(container) and container.sort_children.is_connected(fit): container.sort_children.disconnect(fit), CONNECT_ONE_SHOT)
	fit.call()

static func _fit_window(window, design_size: Vector2) -> void:
	if not is_instance_valid(window) or not window.is_inside_tree(): return
	var viewport: Vector2 = window.get_viewport_rect().size
	# Wrapped labels can temporarily request a huge height before the first
	# container pass. Recompute from the settled minimum, not that stale height.
	window.size = design_size.max(window.get_combined_minimum_size())
	var factor := minf(1, minf((viewport.x - 32) / maxf(window.size.x, 1), (viewport.y - 114) / maxf(window.size.y, 1)))
	window.scale = Vector2.ONE * factor
	if window.get_parent() is CenterContainer:
		window.pivot_offset = Vector2.ZERO
		window.position = Vector2((viewport.x - window.size.x * factor) * 0.5,
			maxf(24, (viewport.y - 90 - window.size.y * factor) * 0.5))
	else:
		window.position.x = clampf(window.position.x, 16, maxf(16, viewport.x - window.size.x * factor - 16))
		window.position.y = clampf(window.position.y, 24, maxf(24, viewport.y - window.size.y * factor - 90))

static func paper_detail(parent: Control) -> void:
	var surface := Control.new()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.draw.connect(func() -> void:
		surface.draw_texture_rect(art("paper_detail"), Rect2(Vector2.ZERO, surface.size), false))
	parent.add_child(surface)

## Buttons retain identical margins in every state, including tiny icon controls.
static func style_button(button: Button, accent: Color = Color.WHITE, icon: bool = false) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var tint := accent
		if state == "hover": tint = accent * Color(1.10, 1.08, 1.04, 1)
		if state == "pressed": tint = accent.darkened(0.20)
		if state == "disabled": tint = Color(0.42, 0.40, 0.36)
		var style := framed("icon" if icon else "button", 4 if icon else 10, tint)
		if icon: style.set_texture_margin_all(12)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", _focus_box())

static func crest(parent: Control) -> void:
	# Containers resize their direct children: keep the ornament inside a passive
	# wrapper so a PanelContainer cannot stretch it across the entire window.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(overlay)
	var ornament := TextureRect.new()
	ornament.name = "FrameCrest"
	ornament.texture = art("crest")
	ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ornament.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ornament.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ornament.position = Vector2(-64, -45)
	ornament.size = Vector2(128, 42)
	overlay.add_child(ornament)

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

## One worn-gold material for menus and tooltip cards.
static func panel_box() -> StyleBoxTexture:
	return framed("metal", 24)

## Compact, recessed worn-metal popup; enough inset to clear its carved trim.
static func tooltip_box() -> StyleBoxTexture:
	var style := framed("button", 18, Color(0.92, 0.92, 0.92))
	style.set_texture_margin_all(16)
	return style

## Same restrained warm edge for item tiles and hand-drawn hotbar controls.
static func draw_hover(ci: CanvasItem, rect: Rect2, focused: bool = false) -> void:
	ci.draw_rect(rect.grow(-1), Color(ACCENT, 0.055))
	ci.draw_rect(rect.grow(-1), Color(BRONZE_LIGHT, 0.8 if focused else 0.55), false, 2 if focused else 1)

static func _button_box(fill: Color, edge: Color, glow: bool) -> StyleBoxTexture:
	var value: float = clampf(fill.r / 0.149, 0.5, 1.35)
	if edge.is_equal_approx(EMBER): value = 0.80
	elif glow: value = 1.10
	var style := framed("button", 10, Color(value, value, value))
	style.content_margin_left = 16
	style.content_margin_right = 16
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
	var style := framed("metal" if rivets else "button", 0, Color(1, 1, 1, alpha))
	style.set_texture_margin_all(minf(24, rect.size.y * 0.3))
	ci.draw_style_box(style, rect)

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
	theme.set_stylebox("tab_selected", "TabContainer", framed("button", 12, Color(1, 0.42, 0.32)))
	theme.set_stylebox("tab_unselected", "TabContainer", framed("button", 12))
	theme.set_stylebox("tab_hovered", "TabContainer", framed("button", 12, Color(1.2, 1.1, 0.9)))
	theme.set_stylebox("panel", "TabContainer", framed("metal", 18))
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
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "OptionButton", theme.get_stylebox(state, "Button"))
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_stylebox("panel", "PopupMenu", framed("metal", 12))
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
	theme.set_stylebox("panel", "TooltipPanel", tooltip_box())
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)
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
