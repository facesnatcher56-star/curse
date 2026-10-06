class_name ItemTile
extends Control
## An item as a picture in a menu. Hovering it shows the item's details and, when `compare_to` is set, how it compares with the piece
## worn in that slot. Used by the town's trader and stash.

var item: Dictionary = {}
var compare_to: Variant = null    # the item worn in this item's slot (or null)
var show_compare: bool = true
var tile_size: float = 52.0

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
	focus_card(self, item, compare_to, show_compare, true)

func _draw() -> void:
	draw_texture_rect(ItemIcons.badge(item), Rect2(Vector2.ZERO, size), false)

## The details card for an item: name in its rarity colour, kind, stats and effect, then the comparison.
static func card(it: Dictionary, worn: Variant, with_compare: bool = true) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(300, 0)
	panel.add_child(box)
	var rarity: int = int(it["rarity"])
	box.add_child(_label(String(it["name"]), 20, Items.RARITY_COLORS[rarity]))
	box.add_child(_label("%s %s" % [Items.RARITY_NAMES[rarity], Items.SLOT_NAMES[int(it["slot"])]], 13, Color(1, 1, 1, 0.55)))
	for line in Items.lines(it):
		var l := _label(line, 14, Color(0.9, 0.88, 0.82))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		box.add_child(l)
	if with_compare:
		box.add_child(HSeparator.new())
		box.add_child(_label("Compared with %s" % (String((worn as Dictionary)["name"]) if worn != null else "your gear"), 13, Color(0.7, 0.68, 0.62)))
		for entry in Items.compare(it, worn):
			var sign_value: int = int(entry["sign"])
			var color: Color = Color(0.5, 0.85, 0.5) if sign_value > 0 else (Color(0.9, 0.45, 0.4) if sign_value < 0 else Color(0.75, 0.75, 0.75))
			box.add_child(_label(("+ " if sign_value > 0 else ("- " if sign_value < 0 else "= ")) + String(entry["text"]), 14, color))
	return panel

static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

static func name_label(it: Dictionary, worn: Variant, compare: bool = true) -> Label:
	var label: Label = preload("res://game/item_name.gd").new()
	label.item = it
	label.worn = worn
	label.show_compare = compare
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
static func focus_card(control: Control, it: Dictionary, worn: Variant, compare: bool = true, on_hover: bool = false) -> void:
	var holder := Control.new()
	holder.top_level = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 100
	holder.visible = false
	control.add_child(holder)
	var open: Callable = func() -> void:
		for child in holder.get_children():
			child.free()
		var detail := card(it, worn, compare)
		holder.add_child(detail)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.visible = true
		var screen: Vector2 = control.get_viewport_rect().size
		var anchor: Vector2 = control.global_position + Vector2(control.size.x + 12, 0)
		var extent: Vector2 = detail.get_combined_minimum_size()
		if anchor.x + extent.x > screen.x - 8:
			anchor.x = control.global_position.x - extent.x - 12
		holder.global_position = Vector2(maxf(8, anchor.x), clampf(anchor.y, 8, maxf(8, screen.y - extent.y - 8)))
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
