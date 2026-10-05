class_name ItemTile
extends Control
## An item as a picture in a menu. Hovering it shows the item's details and, when `compare_to` is set, how it compares with the piece
## worn in that slot. Used by the town's trader and stash.

var item: Dictionary = {}
var compare_to: Variant = null    # the item worn in this item's slot (or null)
var show_compare: bool = true
var tile_size: float = 76.0

static func create(for_item: Dictionary, worn: Variant, size: float = 76.0) -> ItemTile:
	var tile := ItemTile.new()
	tile.item = for_item
	tile.compare_to = worn
	tile.tile_size = size
	tile.custom_minimum_size = Vector2(size, size)
	tile.tooltip_text = String(for_item["name"])   # any text switches the custom tooltip on
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	return tile

func _draw() -> void:
	draw_texture_rect(ItemIcons.badge(item), Rect2(Vector2.ZERO, size), false)

func _make_custom_tooltip(_for_text: String) -> Object:
	return ItemTile.card(item, compare_to if show_compare else null, show_compare)

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
