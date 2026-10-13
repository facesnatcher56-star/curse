class_name HudLootCards
extends RefCounted
## What the HUD shows for loot on the ground: a name plate over every item (laid out so they never overlap; they are also what you click or
## point at to pick an item up) and the details card of the one in focus, which on the return waystone fits itself round the town's
## prompt. It draws on the HUD's own canvas, from Hud._draw, so it keeps its place in the HUD's drawing order.

var hud: Hud
var names: Array[Dictionary] = []   # [{drop, rect, anchor}] this frame's name plates over the items on the ground
var ground_card_rect := Rect2()   # actual drawn ground card, for focused layout regression checks

## Every item on the ground shows its name over it, in its rarity's colour. The plates are laid out on the screen so that they never
## overlap: they are placed from the bottom of the screen (nearest the camera) up, and any plate that would land on another is lifted
## above it, with a thin line back to its item.
const NAME_HEIGHT := 21.0
const NAME_FONT := 15

## The item under the mouse (or, with a controller, the nearest one within reach): what it is, what it does, and how it compares with
## what is worn in that slot, with a note on whether walking over it will put it on or send it to the bag.
func draw(size_px: Vector2, font: Font) -> void:
	ground_card_rect = Rect2()
	if hud.player != null and hud.player.dead:   # the death plate owns the screen: no loot name plates or item card showing through it
		names = []
		LootDrop.focused = null
		return
	names = _layout_loot_names(font)
	_draw_loot_names(font)
	var drop: LootDrop = drop_in_focus()
	LootDrop.focused = drop
	if drop == null:
		return
	var pointer: Vector2 = hud.get_viewport().get_mouse_position() if hud.mouse_override.x < 0.0 else hud.mouse_override
	var anchor: Vector2 = pointer + Vector2(24, 18) if not Gamepad.active else Vector2(size_px.x * 0.5 + 40.0, size_px.y * 0.5 - 150.0)
	_draw_card(drop.item, hud.player.stats.equipment.get(int(drop.item["slot"])), anchor, size_px, font, true, true)

## An item's details card at `anchor`: name, kind, stats and effect, then (optionally) how it compares with `worn`, and (for a drop on the
## ground) whether walking over it will put it on or send it to the bag.
func _draw_card(item: Dictionary, worn: Variant, anchor: Vector2, size_px: Vector2, font: Font, with_compare: bool, for_drop: bool) -> void:
	var color: Color = Items.RARITY_COLORS[int(item["rarity"])]
	var width: float = 340.0
	var pad: float = 14.0
	var inner: float = width - pad * 2.0
	var lines: Array[String] = Items.lines(item, PartyManager.current().active_id)
	var compare: Array[Dictionary] = []
	if with_compare:
		compare = Items.compare(item, worn, PartyManager.current().active_id)
	var height: float = pad * 2.0 + 54.0
	for line in lines:
		height += font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, inner, 14).y + 4.0
	if with_compare:
		height += 30.0 + 18.0 * compare.size()
	if for_drop:
		height += 30.0
	var pos := Vector2(clampf(anchor.x, 8.0, size_px.x - width - 8.0), clampf(anchor.y, 8.0, size_px.y - height - 110.0))
	var return_prompt := _return_prompt_rect() if for_drop else Rect2()
	if return_prompt.has_area():
		var layout := _return_card_layout(item, lines, compare, anchor, size_px, return_prompt, font, with_compare)
		if layout.is_empty():
			push_warning("No clear return-card space in viewport")
			return
		ground_card_rect = layout.rect
		hud.draw_set_transform(layout.rect.position, 0.0, Vector2.ONE * float(layout.scale))
		_draw_return_card_body(item, worn, lines, compare, layout.metrics, color, font, with_compare)
		hud.draw_set_transform(Vector2.ZERO)
		return
	if for_drop:
		ground_card_rect = Rect2(pos, Vector2(width, height))
	UiTheme.draw_panel(hud, Rect2(pos, Vector2(width, height)), 0.97)
	hud.draw_rect(Rect2(pos + Vector2(3, 3), Vector2(4, height - 6)), color)   # a rarity-coloured spine
	var y: float = pos.y + pad + 18.0
	UiTheme.text(hud, font, Vector2(pos.x + pad + 6.0, y), String(item["name"]), 21, color, HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0)
	y += 20.0
	UiTheme.text(hud, font, Vector2(pos.x + pad + 6.0, y), "%s %s" % [Items.RARITY_NAMES[int(item["rarity"])], Items.SLOT_NAMES[int(item["slot"])]], 13,
		Color(1, 1, 1, 0.55))
	y += 10.0
	for line in lines:
		var h: float = font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, inner, 14).y
		hud.draw_multiline_string(font, Vector2(pos.x + pad + 6.0, y + 14.0), line, HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0, 14, -1, ItemTile.stat_line_color(item, line))
		y += h + 4.0
	if with_compare:
		y += 8.0
		hud.draw_line(Vector2(pos.x + pad, y), Vector2(pos.x + width - pad, y), Color(1, 1, 1, 0.12), 1.0)
		y += 18.0
		UiTheme.text(hud, font, Vector2(pos.x + pad + 6.0, y), "Compared with %s" % (String((worn as Dictionary)["name"]) if worn != null else "your gear"), 13,
			Color(0.7, 0.68, 0.62), HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0)
		for entry in compare:
			y += 18.0
			var sign_color: Color = Color(0.5, 0.85, 0.5) if int(entry["sign"]) > 0 else (Color(0.9, 0.45, 0.4) if int(entry["sign"]) < 0 else Color(0.75, 0.75, 0.75))
			var mark: String = "+ " if int(entry["sign"]) > 0 else ("- " if int(entry["sign"]) < 0 else "= ")
			UiTheme.text(hud, font, Vector2(pos.x + pad + 6.0, y), mark + String(entry["text"]), 14, sign_color)
	if for_drop:
		y += 26.0
		var upgrade: bool = hud.player.stats.takes_empty_slot(item)
		UiTheme.text(hud, font, Vector2(pos.x + pad + 6.0, y), "Walk over it: you will wear it (empty slot)" if upgrade else "Walk over it: it goes in the bag", 14,
			Color(0.95, 0.8, 0.5) if upgrade else Color(0.7, 0.68, 0.62))

## Restrict clearance to the active return-waystone decision; other cards retain their layout.
func _return_prompt_rect() -> Rect2:
	var node := hud.get_parent()
	while node != null:
		if node is TownScene:
			var town := node as TownScene
			if String(town.near.get("kind", "")) == "waystone" and town.hud != null:
				return town.hud.interaction_prompt_rect()
			break
		node = node.get_parent()
	return Rect2()

## Measure all content before fitting: wrapping is part of the card, not a later addition. The return card keeps its text at full size and
## spends the slack on rhythm instead: a tighter line gap and, when every row fits half the card, the comparison in two columns.
## Positions are relative to the card's top-left; measuring and drawing both read them, so they cannot drift apart.
var _return_card_measure_key: Array = []
var _return_card_measures: Array[Dictionary] = []

func _return_card_metrics(item: Dictionary, lines: Array[String], compare: Array[Dictionary], width: float, font: Font, with_compare: bool) -> Dictionary:
	var pad := 12.0
	var inner := width - pad * 2.0
	var name_h := maxf(20.0, font.get_multiline_string_size(String(item["name"]), HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0, 21).y)
	var y := pad + 18.0 + name_h   # baseline of the kind line
	var kind_y := y
	y += 4.0
	var line_ys: Array[float] = []
	for line in lines:
		line_ys.append(y + 14.0)
		y += font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0, 14).y + 3.0
	var m := {"width": width, "inner": inner, "name_h": name_h, "kind_y": kind_y, "line_ys": line_ys, "cols": 1}
	if with_compare:
		y += 4.0
		m["rule_y"] = y
		y += 15.0
		m["header_y"] = y
		var cols := 2 if compare.size() >= 3 else 1
		for entry in compare:
			if font.get_string_size("+ " + String(entry["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > inner * 0.5 - 12.0:
				cols = 1
		m["cols"] = cols
		m["rows_y"] = y + 18.0
		y += 18.0 * ceilf(float(compare.size()) / float(cols))
	y += 21.0   # the walk-over line
	m["drop_y"] = y
	m["height"] = y + 12.0
	return m

func _draw_return_card_body(item: Dictionary, worn: Variant, lines: Array[String], compare: Array[Dictionary], m: Dictionary, color: Color, font: Font, with_compare: bool) -> void:
	var width: float = m.width
	var height: float = m.height
	var pad := 12.0
	var inner: float = m.inner
	UiTheme.draw_panel(hud, Rect2(Vector2.ZERO, Vector2(width, height)), 0.97)
	hud.draw_rect(Rect2(Vector2(3, 3), Vector2(4, height - 6)), color)   # a rarity-coloured spine
	hud.draw_multiline_string(font, Vector2(pad + 6.0, pad + 18.0), String(item["name"]), HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0, 21, -1, color)
	UiTheme.text(hud, font, Vector2(pad + 6.0, m.kind_y), "%s %s" % [Items.RARITY_NAMES[int(item["rarity"])], Items.SLOT_NAMES[int(item["slot"])]], 13, Color(1, 1, 1, 0.55))
	for i in lines.size():
		hud.draw_multiline_string(font, Vector2(pad + 6.0, m.line_ys[i]), lines[i], HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0, 14, -1, ItemTile.stat_line_color(item, lines[i]))
	if with_compare:
		hud.draw_line(Vector2(pad, m.rule_y), Vector2(width - pad, m.rule_y), Color(1, 1, 1, 0.12), 1.0)
		UiTheme.text(hud, font, Vector2(pad + 6.0, m.header_y), "Compared with %s" % (String((worn as Dictionary)["name"]) if worn != null else "your gear"), 13,
			Color(0.7, 0.68, 0.62), HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0)
		var per_col: int = ceili(float(compare.size()) / float(m.cols))
		for i in compare.size():
			var entry: Dictionary = compare[i]
			var sign_color: Color = Color(0.5, 0.85, 0.5) if int(entry["sign"]) > 0 else (Color(0.9, 0.45, 0.4) if int(entry["sign"]) < 0 else Color(0.75, 0.75, 0.75))
			var mark: String = "+ " if int(entry["sign"]) > 0 else ("- " if int(entry["sign"]) < 0 else "= ")
			UiTheme.text(hud, font, Vector2(pad + 6.0 + float(i / per_col) * inner * 0.5, float(m.rows_y) + 18.0 * float(i % per_col)), mark + String(entry["text"]), 14, sign_color)
	var upgrade: bool = hud.player.stats.takes_empty_slot(item)
	UiTheme.text(hud, font, Vector2(pad + 6.0, m.drop_y), "Walk over it: you will wear it (empty slot)" if upgrade else "Walk over it: it goes in the bag", 14,
		Color(0.95, 0.8, 0.5) if upgrade else Color(0.7, 0.68, 0.62))

## Find empty rectangles from actual obstacle edges, then fit the complete card into them.
## Prefer full-size typography, widening wrapped content before uniformly scaling it.
## No unsafe original-anchor fallback: every result is bounded and unobstructed.
func _return_card_layout(item: Dictionary, lines: Array[String], compare: Array[Dictionary], anchor: Vector2, screen: Vector2, prompt: Rect2, font: Font, with_compare: bool) -> Dictionary:
	var obstacles: Array[Rect2] = [prompt.grow(6.0), Hud.minimap_rect(screen, hud.use_ds2_ui).grow(7.0), Hud.orb_rect(screen, false).grow(7.0), Hud.orb_rect(screen, true).grow(7.0)]
	obstacles.append(Rect2(14, 14 + hud.top_offset, 250, 62 if hud.objective != "" or hud.wave > 0 else 38).grow(6.0))
	var node := hud.get_parent()
	while node != null:
		if node is TownScene:
			for overlay in (node as TownScene).hud.overlay_rects:
				obstacles.append(overlay.grow(6.0))
			break
		node = node.get_parent()
	for entry in names:
		obstacles.append((entry["rect"] as Rect2).grow(6.0))
	obstacles.append(hud.hotbar_rect(screen).grow(6.0))
	if hud.progression_hud != null:
		obstacles.append(hud.progression_hud.strip_rect(screen).grow(6.0))
	var bounds := Rect2(Vector2(8, 8), Vector2(screen.x - 16, screen.y - 118))
	var xs: Array[float] = [bounds.position.x, bounds.end.x]
	for obstacle in obstacles:
		for edge in [obstacle.position.x, obstacle.end.x]:
			var x := clampf(edge, bounds.position.x, bounds.end.x)
			if not xs.has(x):
				xs.append(x)
	xs.sort()
	var spaces: Array[Rect2] = []
	for left in xs:
		for right in xs:
			if right <= left:
				continue
			var spans: Array[Vector2] = []
			for obstacle in obstacles:
				if obstacle.position.x < right and obstacle.end.x > left and obstacle.position.y < bounds.end.y and obstacle.end.y > bounds.position.y:
					spans.append(Vector2(maxf(bounds.position.y, obstacle.position.y), minf(bounds.end.y, obstacle.end.y)))
			spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
			var top := bounds.position.y
			for span in spans:
				if span.x > top:
					spaces.append(Rect2(left, top, right - left, span.x - top))
				top = maxf(top, span.y)
			if top < bounds.end.y:
				spaces.append(Rect2(left, top, right - left, bounds.end.y - top))
	var measure_key: Array = [String(item["name"]), lines, compare, font, with_compare]
	if measure_key != _return_card_measure_key:
		_return_card_measure_key = measure_key.duplicate(true)
		_return_card_measures.clear()
		for width in range(340, 641, 20):
			_return_card_measures.append(_return_card_metrics(item, lines, compare, float(width), font, with_compare))
	var best: Dictionary = {}
	var best_score := INF
	for metrics in _return_card_measures:
		var content := Vector2(metrics.width, metrics.height)
		var width := content.x
		for space in spaces:
			# The drawn panel includes a four-pixel shadow; reserve it too.
			var room := space.grow(-4.0)
			var scale := minf(1.0, minf(room.size.x / content.x, room.size.y / content.y))
			if scale <= 0.0:
				continue
			var extent := content * scale
			var pos := Vector2(clampf(anchor.x, room.position.x, room.end.x - extent.x), clampf(anchor.y, room.position.y, room.end.y - extent.y))
			var score := (1.0 - scale) * 10000000.0 + (width - 340) * 100.0 + pos.distance_squared_to(anchor)
			if score < best_score:
				best_score = score
				best = {"rect": Rect2(pos, extent), "content": content, "scale": scale, "metrics": metrics}
	return best

## The dropped item the player is pointing at: under the mouse (by where it is on screen), or with a controller the nearest within reach.
func drop_in_focus() -> LootDrop:
	var best: LootDrop = null
	var best_d: float = 1.0e9
	if Gamepad.active:
		for node in hud.get_tree().get_nodes_in_group("loot"):
			var drop := node as LootDrop
			if drop == null or not drop.landed:
				continue
			var d: float = hud.player.global_position.distance_to(drop.global_position)
			if d < 4.0 and d < best_d:
				best_d = d
				best = drop
		return best
	var mouse: Vector2 = hud.get_viewport().get_mouse_position() if hud.mouse_override.x < 0.0 else hud.mouse_override
	if hud.mouse_over_hud(mouse):
		return null
	var camera: Camera3D = hud.get_viewport().get_camera_3d()
	if camera == null:
		return null
	for entry in names:   # a name plate under the pointer is the item
		if (entry["rect"] as Rect2).has_point(mouse):
			return entry["drop"]
	for node in hud.get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null or not drop.landed or camera.is_position_behind(drop.global_position):
			continue
		var d: float = minf(camera.unproject_position(drop.global_position + Vector3(0, 1.5, 0)).distance_to(mouse), camera.unproject_position(drop.global_position + Vector3(0, 0.5, 0)).distance_to(mouse))
		if d < 56.0 and d < best_d:
			best_d = d
			best = drop
	return best

func _layout_loot_names(font: Font) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera: Camera3D = hud.get_viewport().get_camera_3d()
	if camera == null or hud.show_gear or hud.player == null:
		return out
	var entries: Array[Dictionary] = []
	for node in hud.get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null or not drop.landed or camera.is_position_behind(drop.global_position):
			continue
		var anchor: Vector2 = camera.unproject_position(drop.global_position + Vector3(0, 0.4, 0))
		var width: float = font.get_string_size(String(drop.item["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT).x + 14.0
		entries.append({"drop": drop, "anchor": anchor, "width": width})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["anchor"].y > b["anchor"].y)
	var placed: Array[Rect2] = []
	for entry in entries:
		var anchor: Vector2 = entry["anchor"]
		var rect := Rect2(anchor.x - float(entry["width"]) * 0.5, anchor.y - NAME_HEIGHT - 10.0, float(entry["width"]), NAME_HEIGHT)
		var guard: int = 0
		while guard < 60:
			var clash: bool = false
			for other in placed:
				if rect.grow(2.0).intersects(other):
					clash = true
					rect.position.y = other.position.y - NAME_HEIGHT - 3.0   # lifted just above the plate it landed on
					break
			if not clash:
				break
			guard += 1
		if hud.covers(rect.get_center()) or hud.covers(rect.position) or hud.covers(rect.end):
			continue   # it would sit under the hotbar, the minimap or an open panel: left out, not drawn over them
		placed.append(rect)
		out.append({"drop": entry["drop"], "rect": rect, "anchor": anchor})
	return out

func _draw_loot_names(font: Font) -> void:
	var mouse: Vector2 = hud.get_viewport().get_mouse_position() if hud.mouse_override.x < 0.0 else hud.mouse_override
	for entry in names:
		var drop: LootDrop = entry["drop"]
		var rect: Rect2 = entry["rect"]
		var anchor: Vector2 = entry["anchor"]
		var colour: Color = Items.RARITY_COLORS[int(drop.item["rarity"])]
		var focus: bool = LootDrop.focused == drop or rect.has_point(mouse)
		if rect.end.y < anchor.y - 12.0:   # lifted off its item: a line shows whose name it is
			hud.draw_line(Vector2(rect.get_center().x, rect.end.y), anchor, Color(colour.r, colour.g, colour.b, 0.55), 1.0)
		hud.draw_rect(rect, Color(0.03, 0.03, 0.04, 0.82 if focus else 0.62))
		hud.draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.95 if focus else 0.45), false, 1.5 if focus else 1.0)
		UiTheme.text(hud, font, rect.position + Vector2(0, 15.5), String(drop.item["name"]), NAME_FONT, colour.lightened(0.2 if focus else 0.0),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
