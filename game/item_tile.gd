class_name ItemTile
extends Control
## An item as a picture in a menu. Hovering it shows the item's details and, when `compare_to` is set, how it compares with the piece
## worn in that slot. Used by the town's trader and stash.

const UNMET_COLOR := Color(0.93, 0.30, 0.24)   # the same red as an unmet requirement (see stat_line_color)

var item: Dictionary = {}
var compare_to: Variant = null    # the item worn in this item's slot (or null)
var show_compare: bool = true
var equip_hint: bool = false      # a bag item: its card ends with how to equip it ("(R-click to equip)")
var action_hint: String = ""      # optional action shown inside the item's details card
var tile_size: float = 52.0
var hovered: bool = false

static func create(for_item: Dictionary, worn: Variant, size: float = 52.0) -> ItemTile:
	var tile := ItemTile.new()
	tile.item = for_item
	tile.compare_to = worn
	tile.tile_size = size
	tile.custom_minimum_size = Vector2(size, size)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	return tile

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func() -> void: hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: hovered = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	focus_card(self, item, compare_to, show_compare, true, equip_hint, action_hint)

func _draw() -> void:
	draw_texture_rect(ItemIcons.badge(item), Rect2(Vector2.ZERO, size), false)
	if hovered or has_focus(): UiTheme.draw_hover(self, Rect2(Vector2.ZERO, size), has_focus())

## The details card for an item: name in its rarity colour, kind, stats and effect, then the comparison.
static func card(it: Dictionary, worn: Variant, with_compare: bool = true, with_equip_hint: bool = false, with_action_hint: String = "") -> Control:
	var panel := PanelContainer.new()
	panel.theme = UiTheme.get_theme() # Native tooltip windows do not always inherit the opener's theme.
	panel.add_theme_stylebox_override("panel", UiTheme.tooltip_box())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	panel.add_child(box)
	var member: String = PartyManager.current().active_id
	var rarity: int = int(it["rarity"])
	box.add_child(_label(String(it["name"]), 20, Items.RARITY_COLORS[rarity]))
	box.add_child(_label("%s %s" % [Items.RARITY_NAMES[rarity], Items.SLOT_NAMES[int(it["slot"])]], 13, Color(1, 1, 1, 0.55)))
	var comparison: Array[Dictionary] = Items.compare(it, worn, member) if with_compare else Items.wear_warning(it, member)
	for row in display_rows(it, comparison, member):
		box.add_child(_wrapping_label(String(row["text"]), 14, row["color"]))
	if with_equip_hint:
		box.add_child(_label("(Confirm to equip)" if Gamepad.active else "(R-click to equip)", 13, Color(0.7, 0.68, 0.62)))
	if not with_action_hint.is_empty():
		box.add_child(_wrapping_label(with_action_hint, 13, Color(0.7, 0.68, 0.62)))
	return panel

## Width of every item card (the trader, stash, inventory and hover cards). Wider than the old 300 so long descriptions wrap in fewer lines.
const CARD_WIDTH := 400.0
## The lines of an item card, in order, as {text, color}. Shared by every item card (hover, trader, stash, inventory and the ground). The one
## "cannot wear it yet" warning comes first. Each stat then carries its change beside it, coloured by that change ("Armor 8 (-1)" in red); a
## change to a stat the item does not have still appears, as its own line. An empty slot's note comes last.
static func display_rows(it: Dictionary, comparison: Array[Dictionary], member_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var deltas: Dictionary = {}
	for entry in comparison:
		var key: String = String(entry["key"])
		if key == Items.WARNING_KEY:
			out.append({"text": String(entry["text"]), "color": UNMET_COLOR})
		elif key != "":
			deltas[key] = entry
	var shown: Dictionary = {}
	for row in Items.rows(it, member_id):
		var key: String = String(row["key"])
		var line: String = String(row["text"])
		if deltas.has(key):
			var entry: Dictionary = deltas[key]
			shown[key] = true
			out.append({"text": "%s %s" % [line, String(entry["delta"])], "color": _delta_color(int(entry["sign"]))})
		else:
			out.append({"text": line, "color": stat_line_color(it, line)})
	for key in deltas:
		if not shown.has(key):
			var entry: Dictionary = deltas[key]
			out.append({"text": String(entry["text"]), "color": _delta_color(int(entry["sign"]))})
	for entry in comparison:
		if String(entry["key"]) == "":
			out.append({"text": String(entry["text"]), "color": _delta_color(int(entry["sign"]))})
	return out

## The colour of a comparison: green for a beneficial change, red for a detrimental one (the sign stays in the text), grey when neutral.
static func _delta_color(sign_value: int) -> Color:
	if sign_value > 0:
		return Color(0.5, 0.85, 0.5)
	if sign_value < 0:
		return UNMET_COLOR
	return Color(0.75, 0.75, 0.75)

static func _wrapping_label(text: String, size: int, color: Color) -> Label:
	var label := _label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CARD_WIDTH
	return label

## Shared by inventory/shop cards and ground-loot cards.
static func stat_line_color(it: Dictionary, line: String) -> Color:
	return Color(0.93, 0.30, 0.24) if line.contains("Requires ") and not Items.hero_can_wear(it, PartyManager.current().active_id) else Color(0.9, 0.88, 0.82)

static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

static func name_label(it: Dictionary, worn: Variant, compare: bool = true, with_equip_hint: bool = false) -> Label:
	var label: Label = preload("res://game/item_name.gd").new()
	label.item = it
	label.worn = worn
	label.show_compare = compare
	label.equip_hint = with_equip_hint
	label.text = String(it["name"])
	label.tooltip_text = label.text
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 84
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Items.RARITY_COLORS[int(it["rarity"])])
	return label

## The details card shown beside `control`: with a controller while it has focus, and with `on_hover` the moment the mouse is over it (an
## item's picture shows its card at once, like the item on the ground does; its buttons do not).
static func focus_card(control: Control, it: Dictionary, worn: Variant, compare: bool = true, on_hover: bool = false, with_equip_hint: bool = false, with_action_hint: String = "") -> void:
	var holder := Control.new()
	holder.name = "ItemDetails"
	holder.top_level = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 100
	holder.visible = false
	control.add_child(holder)
	var reposition: Callable = func() -> void:
		if not is_instance_valid(holder) or not holder.visible or holder.get_child_count() == 0:
			return
		var scroll := holder.get_child(0) as ScrollContainer
		var detail := scroll.get_child(0) as Control
		var screen: Vector2 = control.get_viewport_rect().size
		var safe_rect := Rect2(Vector2(8, 8), Vector2(maxf(1, screen.x - 16), maxf(1, screen.y - 118)))
		# Full size always: the card grows with its text, and only a card taller than the safe area scrolls (never scaled down).
		var extent: Vector2 = detail.get_combined_minimum_size()
		var shown := Vector2(minf(extent.x, safe_rect.size.x), minf(extent.y, safe_rect.size.y))
		scroll.size = shown
		var anchor: Vector2 = control.global_position + Vector2(control.size.x + 12, 0)
		if anchor.x + shown.x > safe_rect.end.x:
			anchor.x = control.global_position.x - shown.x - 12
		var position := Vector2(anchor.x, anchor.y)
		position.x = clampf(position.x, safe_rect.position.x, maxf(safe_rect.position.x, safe_rect.end.x - shown.x))
		position.y = clampf(position.y, safe_rect.position.y, maxf(safe_rect.position.y, safe_rect.end.y - shown.y))
		holder.global_position = position
	var open: Callable = func() -> void:
		for child in holder.get_children():
			child.free()
		var detail := card(it, worn, compare, with_equip_hint, with_action_hint)
		var scroll := ScrollContainer.new()   # a card taller than the screen scrolls instead of clipping or shrinking
		scroll.name = "DetailScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE # the card can overlap a merchant button: it must never take clicks
		scroll.add_child(detail)
		holder.add_child(scroll)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in detail.find_children("*", "Control", true, false):
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE # tooltip contents must not intercept a drag destination
		holder.visible = true
		reposition.call()
	holder.tree_entered.connect(func() -> void:
		var viewport: Viewport = control.get_viewport()
		if viewport != null and not viewport.size_changed.is_connected(reposition):
			viewport.size_changed.connect(reposition))
	control.tree_exiting.connect(func() -> void:
		var viewport: Viewport = control.get_viewport()
		if viewport != null and viewport.size_changed.is_connected(reposition):
			viewport.size_changed.disconnect(reposition))
	control.resized.connect(reposition)
	control.item_rect_changed.connect(reposition)
	control.focus_entered.connect(func() -> void:
		if Gamepad.active:
			open.call())
	control.focus_exited.connect(func() -> void: holder.visible = false)
	if on_hover:
		control.mouse_entered.connect(open)
		control.mouse_exited.connect(func() -> void: holder.visible = false)

static func decorate_button(button: Button, it: Dictionary, worn: Variant) -> void:
	button.set_script(preload("res://game/item_button.gd"))
	button.item = it
	button.worn = worn
	focus_card(button, it, worn)
