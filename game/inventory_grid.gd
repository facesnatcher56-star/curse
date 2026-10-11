extends RefCounted
## DS2 heroes_ds2.gas: five columns, thirteen rows. Pure packing rules, no UI or item deletion.
const WIDTH := 5
const HEIGHT := 13
const NONE := Vector2i(-1, -1)

static func footprint(item: Dictionary) -> Vector2i:
	var extent := base_footprint(item)
	return Vector2i(extent.y, extent.x) if item.get("bag_rotated", false) else extent

static func base_footprint(item: Dictionary) -> Vector2i:
	var def: ItemDef = ItemDb.get_def(String(item.get("def", "")))
	if def == null: return Vector2i.ONE
	if def.inventory_size != Vector2i.ZERO: return def.inventory_size
	# amr_bases.gas and wpn_bases.gas; jewellery inherits one cell.
	match def.item_type:
		"body", "helm", "shield": return Vector2i(2, 2)
		"boots", "gloves", "thrown": return Vector2i(1, 2)
		"1h": return Vector2i(1, 3)
		"2h": return Vector2i(1, 4) # current 2H base is a greatsword
		"bow": return Vector2i(1, 4)
	return Vector2i.ONE

static func fits(cell: Vector2i, extent: Vector2i, occupied: Array[Rect2i]) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x + extent.x > WIDTH or cell.y + extent.y > HEIGHT: return false
	var rect := Rect2i(cell, extent)
	for other in occupied:
		if rect.intersects(other): return false
	return true

static func layout(items: Array, keep_positions: bool = true) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var occupied: Array[Rect2i] = []
	cells.resize(items.size())
	cells.fill(NONE)
	# Reserve valid user placements before filling gaps (a newly collected item must not move older ones).
	if keep_positions:
		for i in items.size():
			var saved: Variant = items[i].get("bag_cell", NONE)
			if saved is Vector2i and fits(saved, footprint(items[i]), occupied):
				cells[i] = saved
				occupied.append(Rect2i(saved, footprint(items[i])))
	for i in items.size():
		if cells[i] != NONE: continue
		var extent := footprint(items[i])
		for y in HEIGHT:
			for x in WIDTH:
				if fits(Vector2i(x, y), extent, occupied):
					cells[i] = Vector2i(x, y)
					occupied.append(Rect2i(cells[i], extent))
					break
			if cells[i] != NONE: break
	return cells

static func can_hold(items: Array) -> bool:
	return not NONE in layout(items)

static func arrange(items: Array, keep_positions: bool = true) -> void:
	var cells := layout(items, keep_positions)
	for i in items.size(): items[i]["bag_cell"] = cells[i]

static func can_place(items: Array, index: int, cell: Vector2i, rotated: Variant = null) -> bool:
	if index < 0 or index >= items.size(): return false
	var cells := layout(items)
	var occupied: Array[Rect2i] = []
	for i in items.size():
		if i != index and cells[i] != NONE: occupied.append(Rect2i(cells[i], footprint(items[i])))
	var item: Dictionary = items[index]
	if rotated != null:
		item = item.duplicate()
		item["bag_rotated"] = rotated
	return fits(cell, footprint(item), occupied)
