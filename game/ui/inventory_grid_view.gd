extends Control
## Sized backpack UI. Rules live in inventory_grid.gd; items stay in PlayerStats.bag.
const Rules := preload("res://game/inventory_grid.gd")
const Tile := preload("res://game/ui/inventory_grid_tile.gd")
signal item_activated(index: int)
signal equipment_dropped(place: int, cell: Vector2i)
var stats: PlayerStats
var cell_size: float = 30.0
var tiles: Array[ItemTile] = []
var moving: int = -1
var move_cell := Vector2i.ZERO
var move_rotated: bool = false
var drag_preview: Control

func _ready() -> void:
	Rules.arrange(stats.bag)
	custom_minimum_size = Vector2(Rules.WIDTH, Rules.HEIGHT) * cell_size
	for i in stats.bag.size():
		var tile := Tile.new()
		tile.item = stats.bag[i]
		tile.compare_to = stats.equipment.get(int(tile.item["slot"]))
		tile.equip_hint = true
		tile.grid = self
		tile.index = i
		tile.position = Vector2(tile.item["bag_cell"]) * cell_size + Vector2.ONE
		tile.size = Vector2(Rules.footprint(tile.item)) * cell_size - Vector2.ONE * 2
		add_child(tile)
		tiles.append(tile)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color(0.025, 0.025, 0.023, 0.96))
	for y in Rules.HEIGHT:
		for x in Rules.WIDTH:
			draw_rect(Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size), Color(UiTheme.BRONZE_LIGHT, 0.25), false)
	if moving >= 0:
		var valid: bool = Rules.can_place(stats.bag, moving, move_cell, move_rotated)
		var preview: Dictionary = stats.bag[moving].duplicate()
		preview["bag_rotated"] = move_rotated
		draw_rect(Rect2(Vector2(move_cell) * cell_size, Vector2(Rules.footprint(preview)) * cell_size),
			Color(0.8, 0.6, 0.3, 0.5) if valid else Color(0.8, 0.15, 0.12, 0.5), false, 3.0)

func move_item(index: int, cell: Vector2i, rotated: Variant = null) -> bool:
	if not Rules.can_place(stats.bag, index, cell, rotated): return false
	stats.bag[index]["bag_cell"] = cell
	if rotated != null: stats.bag[index]["bag_rotated"] = rotated
	tiles[index].position = Vector2(cell) * cell_size + Vector2.ONE
	tiles[index].size = Vector2(Rules.footprint(stats.bag[index])) * cell_size - Vector2.ONE * 2
	tiles[index].queue_redraw()
	queue_redraw()
	return true

## Scoped to this open backpack. Drag/ghost rotation is committed only on a valid drop/place.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("inventory_rotate") or event.is_echo(): return
	var data: Variant = get_viewport().gui_get_drag_data()
	if data is Dictionary and data.get("stats") == stats and data.has("index"):
		data["rotated"] = not bool(data.get("rotated", false))
		if is_instance_valid(drag_preview):
			drag_preview.item["bag_rotated"] = data["rotated"]
			drag_preview.size = Vector2(Rules.footprint(drag_preview.item)) * cell_size - Vector2.ONE * 2
			drag_preview.queue_redraw()
		get_viewport().set_input_as_handled()
		return
	var index := moving
	if index < 0:
		for i in tiles.size():
			if not Gamepad.active and tiles[i].get_global_rect().has_point(get_global_mouse_position()):
				index = i
				break
	if index < 0:
		for i in tiles.size():
			if tiles[i].has_focus():
				index = i
				break
	if index >= 0 and handle_input(event, index): get_viewport().set_input_as_handled()

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("stats") != stats: return false
	var cell := Vector2i((at / cell_size).floor())
	if data.has("index"): return Rules.can_place(stats.bag, int(data.index), cell, data.get("rotated"))
	if data.has("place") and stats.equipment.has(int(data.place)):
		var candidate: Array = stats.bag.duplicate()
		candidate.append(stats.equipment[int(data.place)])
		return Rules.can_place(candidate, candidate.size() - 1, cell)
	return false

func _drop_data(at: Vector2, data: Variant) -> void:
	var cell := Vector2i((at / cell_size).floor())
	if data.has("index"): move_item(int(data.index), cell, data.get("rotated"))
	else: equipment_dropped.emit(int(data.place), cell)

## Controller: select picks up the focused item, directions move the ghost, confirm places, cancel restores.
func handle_input(event: InputEvent, index: int) -> bool:
	if event.is_echo(): return false
	if event.is_action_pressed("inventory_rotate"):
		if moving >= 0:
			move_rotated = not move_rotated
			queue_redraw()
		elif not move_item(index, stats.bag[index]["bag_cell"], not bool(stats.bag[index].get("bag_rotated", false))):
			stats.p._say("Not enough room to rotate")
		return true
	if moving >= 0:
		if event.is_action_pressed("ui_cancel"):
			moving = -1
		elif event.is_action_pressed("ui_accept"):
			if move_item(moving, move_cell, move_rotated): moving = -1
		else:
			var direction := Vector2i.ZERO
			if event.is_action_pressed("ui_left"): direction.x = -1
			elif event.is_action_pressed("ui_right"): direction.x = 1
			elif event.is_action_pressed("ui_up"): direction.y = -1
			elif event.is_action_pressed("ui_down"): direction.y = 1
			else: return false
			move_cell = (move_cell + direction).clamp(Vector2i.ZERO, Vector2i(Rules.WIDTH - 1, Rules.HEIGHT - 1))
		queue_redraw()
		return true
	if event.is_action_pressed("ui_select"):
		moving = index
		move_cell = stats.bag[index]["bag_cell"]
		move_rotated = bool(stats.bag[index].get("bag_rotated", false))
		queue_redraw()
		return true
	var click := event as InputEventMouseButton
	if event.is_action_pressed("ui_accept") or (click != null and click.pressed and
		(click.button_index == MOUSE_BUTTON_RIGHT or (click.button_index == MOUSE_BUTTON_LEFT and click.double_click))):
		item_activated.emit(index)
		return true
	return false
