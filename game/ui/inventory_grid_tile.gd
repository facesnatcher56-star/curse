extends ItemTile
## Rectangle frame with the existing square artwork fitted inside, never stretched into a sword-shaped badge.
var grid: Control
var index: int

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.075, 0.065, 0.96))
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Items.RARITY_COLORS[int(item.rarity)].darkened(0.3), false)
	var side: float = minf(size.x, size.y) - 4.0
	draw_set_transform(size * 0.5, PI * 0.5 if item.get("bag_rotated", false) else 0.0)
	draw_texture_rect(ItemIcons.badge(item), Rect2(-Vector2.ONE * side * 0.5, Vector2.ONE * side), false)
	draw_set_transform(Vector2.ZERO)
	if hovered or has_focus(): UiTheme.draw_hover(self, Rect2(Vector2.ZERO, size), has_focus())

func _ready() -> void:
	if grid == null: return # native drag preview, not an interactive inventory tile
	super._ready()

func _gui_input(event: InputEvent) -> void:
	if grid.handle_input(event, index): accept_event()

func _get_drag_data(_at: Vector2) -> Variant:
	var preview := get_script().new() as Control
	preview.item = item.duplicate()
	preview.size = size
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.drag_preview = preview
	set_drag_preview(preview)
	return {"stats": grid.stats, "index": index, "rotated": bool(item.get("bag_rotated", false))}

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return grid._can_drop_data(position + at, data)

func _drop_data(at: Vector2, data: Variant) -> void:
	grid._drop_data(position + at, data)
