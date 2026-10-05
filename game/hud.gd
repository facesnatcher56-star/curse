class_name Hud
extends Control
## Single-pass HUD: bars, hotbar, target bar, wave info, messages. Drawn in code.

var player: Player
var arena: Arena
var wave: int = 0
## What the job asks, with its progress ("Destroy nests: 1 / 3"), shown in place of the wave number when not "" (see RunDirector.objective_line).
var objective: String = ""
var kills: int = 0
var alive: int = 0
# Gear panel.
var show_gear: bool = false
var banner_text: String = ""
var _gear_hits: Array[Dictionary] = []
var _hint_age: float = 0.0
var banner_time: float = 0.0

func show_banner(text: String, seconds: float = 2.5) -> void:
	banner_text = text
	banner_time = seconds

func _ready() -> void:
	add_to_group("hud")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	show_gear = Input.is_action_pressed("gear")
	banner_time = maxf(banner_time - delta, 0.0)
	queue_redraw()

func _draw() -> void:
	if player == null:
		return
	var size_px: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font

	if player.hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size_px), Color(0.8, 0.0, 0.0, 0.25 * player.hurt_flash))

	# Resource bars, bottom left.
	var base: Vector2 = Vector2(24, size_px.y - 92)
	UiTheme.draw_panel(self, Rect2(base - Vector2(12, 12), Vector2(284, 90)), 0.62, false)
	_bar(base, Vector2(260, 24), player.health / player.max_health, UiTheme.BLOOD,
		"%d / %d" % [int(player.health), int(player.max_health)], font)
	_bar(base + Vector2(0, 30), Vector2(260, 18), player.stats.mana / player.stats.max_mana, UiTheme.MANA,
		"%d / %d" % [int(player.stats.mana), int(player.stats.max_mana)], font)
	_bar(base + Vector2(0, 54), Vector2(260, 8), player.stats.stamina / player.stats.max_stamina, UiTheme.STAMINA, "", font)

	_slot_hits.clear()
	# Hotbar, bottom centre.
	var slot: float = 64.0
	var slot_count: int = player.skills.hotbar.size() + 2
	var total: float = slot * slot_count + 8 * (slot_count - 1)
	var x0: float = (size_px.x - total) * 0.5
	var y0: float = size_px.y - slot - 24
	UiTheme.draw_panel(self, Rect2(x0 - 12.0, y0 - 10.0, total + 24.0, slot + 20.0), 0.6)
	for i in player.skills.hotbar.size():
		var id: String = player.skills.hotbar[i]
		_slot(Vector2(x0 + i * (slot + 8), y0), slot, "skill_%d" % (i + 1), id, font)
	var extra: int = player.skills.hotbar.size()
	_slot(Vector2(x0 + extra * (slot + 8), y0), slot, "alt_skill", player.skills.right_click_skill, font)
	_slot(Vector2(x0 + (extra + 1) * (slot + 8), y0), slot, "dodge", "dodge", font)
	_draw_tooltip(font, size_px)
	if player.skills.aiming_id != "":
		draw_string(font, Vector2(0, y0 - 14.0), "Release %s to cast %s" % [GameSettings.short_binding_text(player.skills.aiming_action),
			SkillDb.all()[player.skills.aiming_id]["name"]], HORIZONTAL_ALIGNMENT_CENTER, size_px.x, 20, Color(1.0, 0.75, 0.4))

	# Target bar, top centre: whatever the mouse is over, else what we are attacking.
	var target: Actor = player.hover_target
	if target == null:
		target = player.attack_target
	if target == null and player.skills.queued_target != null:
		target = player.skills.queued_target
	if target != null and not target.dead:
		var w: float = 340.0
		var color: Color = Color(0.55, 0.1, 0.1) if target.max_health < 150.0 else Color(0.62, 0.3, 0.08)
		_bar(Vector2((size_px.x - w) * 0.5, 24), Vector2(w, 18), target.health / target.max_health, color,
			"%s   %d / %d" % [target.display_name, ceili(target.health), int(target.max_health)], font)

	# Small bars over enemies that were hurt recently or are hovered.
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Actor
			if enemy == null or enemy.dead or (enemy.bar_timer <= 0.0 and enemy != player.hover_target):
				continue
			var head: Vector3 = enemy.get_global_transform_interpolated().origin + Vector3(0, enemy.body_height + 0.25, 0)
			if camera.is_position_behind(head):
				continue
			var screen: Vector2 = camera.unproject_position(head)
			var bar_w: float = 44.0 + enemy.body_radius * 30.0
			var alpha: float = 1.0 if enemy == player.hover_target else clampf(enemy.bar_timer, 0.0, 1.0)
			var pos := Vector2(screen.x - bar_w * 0.5, screen.y - 8.0)
			draw_rect(Rect2(pos, Vector2(bar_w, 6)), Color(0, 0, 0, 0.7 * alpha))
			draw_rect(Rect2(pos, Vector2(bar_w * clampf(enemy.health / enemy.max_health, 0.0, 1.0), 6)), Color(0.8, 0.15, 0.12, alpha))
			draw_rect(Rect2(pos, Vector2(bar_w, 6)), Color(1, 1, 1, 0.4 * alpha), false, 1.0)

	if banner_time > 0.0:
		var fade: float = clampf(minf(banner_time, 0.8) / 0.8, 0.0, 1.0)
		var lines: PackedStringArray = banner_text.split("\n")
		var top: float = size_px.y * 0.28 - 56.0
		var band_h: float = 78.0 + 28.0 * (lines.size() - 1)
		draw_rect(Rect2(0, top, size_px.x, band_h), Color(0, 0, 0, 0.42 * fade))
		draw_rect(Rect2(size_px.x * 0.3, top + band_h - 2.0, size_px.x * 0.4, 2.0), Color(UiTheme.EMBER.r, UiTheme.EMBER.g, UiTheme.EMBER.b, 0.7 * fade))
		UiTheme.text(self, font, Vector2(0, size_px.y * 0.28), lines[0], 50, Color(1.0, 0.9, 0.7, fade), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
		for i in range(1, lines.size()):
			UiTheme.text(self, font, Vector2(0, size_px.y * 0.28 + 30.0 * i), lines[i], 22, Color(0.85, 0.78, 0.65, fade), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
	_hint_age += get_process_delta_time()
	UiTheme.draw_panel(self, Rect2(14, 14, 250, 62), 0.7)
	if objective != "":
		UiTheme.text(self, font, Vector2(28, 42), objective, 20, UiTheme.BRONZE_LIGHT.lightened(0.25))
	else:
		UiTheme.text(self, font, Vector2(28, 42), "WAVE %d" % wave, 24, UiTheme.BRONZE_LIGHT.lightened(0.25))
	var kills_text: String = str(kills)
	var used: float = UiTheme.draw_stat(self, font, Vector2(28, 50), "kills", kills_text, 24.0, 18)
	UiTheme.draw_stat(self, font, Vector2(28 + used + 22.0, 50), "enemies", str(alive), 24.0, 18)
	# The control hints fade to a whisper after the first half minute.
	var hint_alpha: float = clampf(1.0 - (_hint_age - 25.0) / 10.0, 0.3, 1.0)
	UiTheme.text(self, font, Vector2(24, 100), Gamepad.help_text() if Gamepad.active else "LMB move/attack   1-2, 4-6 skills   3 potion   RMB attack   Ctrl stand still   Space dodge   Tab gear",
		14, Color(1, 1, 1, 0.5 * hint_alpha))

	_draw_minimap(size_px, font)

	if show_gear:
		_draw_gear(size_px, font)
	_draw_item_card(size_px, font)

	if player.message_time > 0.0:
		UiTheme.text(self, font, Vector2(0, size_px.y - 150), player.message, 22, Color(1, 0.85, 0.5, minf(player.message_time, 1.0)),
			HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
	if player.dead:
		draw_rect(Rect2(Vector2.ZERO, size_px), Color(0, 0, 0, 0.55))
		UiTheme.text(self, font, Vector2(0, size_px.y * 0.45), "YOU DIED", 64, Color(0.72, 0.12, 0.1), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
		UiTheme.text(self, font, Vector2(0, size_px.y * 0.45 + 44), "Press R to restart" if TownState.job.is_empty() else "Returning to town...", 22,
			Color(0.9, 0.86, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)

## True when a screen point is over a HUD panel (minimap, hotbar, resource bars): the world behind it must not react to the mouse.
func covers(point: Vector2) -> bool:
	var size_px: Vector2 = get_viewport_rect().size
	var side: float = 210.0
	if Rect2(Vector2(size_px.x - side - 24.0, size_px.y - side - 24.0), Vector2(side, side)).has_point(point):
		return true
	if Rect2(Vector2(24.0, size_px.y - 92.0), Vector2(260.0, 70.0)).has_point(point):   # health / mana / stamina bars
		return true
	var slot: float = 64.0
	var count: int = (player.skills.hotbar.size() + 2) if player != null else 9
	var total: float = slot * count + 8.0 * (count - 1)
	return Rect2(Vector2((size_px.x - total) * 0.5, size_px.y - slot - 24.0), Vector2(total, slot)).has_point(point)

## Whole-arena minimap, bottom right. It turns with the camera, so whatever is up the screen is up on the map.
func _draw_minimap(size_px: Vector2, font: Font) -> void:
	var side: float = 210.0
	var rect := Rect2(Vector2(size_px.x - side - 24.0, size_px.y - side - 24.0), Vector2(side, side))
	# A long, narrow arena (the Crypt Road) would be a thin strip, so its map shows a window round the hero instead of the whole place.
	var bounds: Vector2 = Arena.bounds_of(get_tree())
	var windowed: bool = bounds.y > bounds.x * 1.6
	var half: float = 45.0 if windowed else Arena.HALF
	var origin: Vector3 = player.global_position if windowed and player != null else Vector3.ZERO
	var scale_px: float = side / (half * 2.0)
	var centre: Vector2 = rect.get_center()
	UiTheme.draw_panel(self, rect.grow(7.0), 0.5)
	draw_rect(rect, Color(0.035, 0.035, 0.045, 0.82))
	if arena != null:
		for obstacle in arena.obstacles:
			var op: Vector3 = obstacle["position"] - origin
			if windowed and (absf(op.x) > half or absf(op.z) > half):
				continue
			var r: float = maxf(float(obstacle["radius"]) * scale_px, 1.5)
			draw_circle(centre + Vector2(op.x, op.z).rotated(Gamepad.view_yaw) * scale_px, r, Color(0.3, 0.3, 0.34, 0.5))
	# Corrupted nests (the job's targets): a sickly green ring, always shown, pinned to the edge of the map when out of the window.
	for node in get_tree().get_nodes_in_group("nests"):
		var nest := node as Destructible
		if nest == null or nest.broken:
			continue
		var nrel: Vector3 = nest.global_position - origin
		var nat: Vector2 = centre + Vector2(clampf(nrel.x, -half, half), clampf(nrel.z, -half, half)).rotated(Gamepad.view_yaw) * scale_px
		draw_circle(nat, 6.0, Color(0, 0, 0, 0.8))
		draw_arc(nat, 4.2, 0.0, TAU, 16, Color(0.55, 0.8, 0.2), 2.0)
	# Enemies: red dots, larger orange for bosses; the nearest few are not special, the count is in the header.
	var count: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Actor
		if enemy == null or enemy.dead:
			continue
		count += 1
		var p: Vector3 = enemy.global_position - origin
		if windowed and (absf(p.x) > half or absf(p.z) > half):
			continue
		var rel: Vector2 = Vector2(p.x, p.z).rotated(Gamepad.view_yaw)
		var at: Vector2 = centre + Vector2(clampf(rel.x, -half, half), clampf(rel.y, -half, half)) * scale_px
		if enemy.is_boss or enemy.max_health >= 150.0:
			draw_circle(at, 5.0, Color(0, 0, 0, 0.8))
			draw_circle(at, 3.8, Color(1.0, 0.55, 0.12))
		else:
			draw_circle(at, 3.0, Color(0, 0, 0, 0.7))
			draw_circle(at, 2.2, Color(0.95, 0.15, 0.12))
	# Items on the ground: a diamond in the rarity colour (bigger for rares and uniques), so they can be found from the map too.
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null:
			continue
		var lp: Vector3 = drop.global_position - origin
		if windowed and (absf(lp.x) > half or absf(lp.z) > half):
			continue
		var lrel: Vector2 = Vector2(lp.x, lp.z).rotated(Gamepad.view_yaw)
		var lat: Vector2 = centre + Vector2(clampf(lrel.x, -half, half), clampf(lrel.y, -half, half)) * scale_px
		var rarity: int = int(drop.item["rarity"])
		var r: float = 3.0 + 1.5 * rarity
		var tint: Color = Items.RARITY_COLORS[rarity] if rarity > 0 else Color(0.78, 0.76, 0.7)
		draw_colored_polygon(PackedVector2Array([lat + Vector2(0, -r - 1), lat + Vector2(r + 1, 0), lat + Vector2(0, r + 1), lat + Vector2(-r - 1, 0)]), Color(0, 0, 0, 0.85))
		draw_colored_polygon(PackedVector2Array([lat + Vector2(0, -r), lat + Vector2(r, 0), lat + Vector2(0, r), lat + Vector2(-r, 0)]), tint)
	# The hero: a white arrow pointing the way they face.
	var pp: Vector3 = player.global_position - origin
	var me: Vector2 = centre + Vector2(pp.x, pp.z).rotated(Gamepad.view_yaw) * scale_px
	var yaw: float = player.visual.rotation.y if player.visual != null else 0.0
	var fwd: Vector2 = Vector2(sin(yaw), cos(yaw)).rotated(Gamepad.view_yaw)
	var side_v := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([me + fwd * 7.0, me - fwd * 4.0 + side_v * 4.5, me - fwd * 2.0, me - fwd * 4.0 - side_v * 4.5]),
		Color(1, 1, 1))
	UiTheme.text(self, font, rect.position + Vector2(8, 18), "%d left" % count, 14, Color(1, 1, 1, 0.8))

## The item under the mouse (or, with a controller, the nearest one within reach): what it is, what it does, and how it compares with
## what is worn in that slot, with a note on whether walking over it will put it on or send it to the bag.
func _draw_item_card(size_px: Vector2, font: Font) -> void:
	var drop: LootDrop = _drop_in_focus()
	LootDrop.focused = drop
	if drop == null:
		return
	var pointer: Vector2 = get_viewport().get_mouse_position() if mouse_override.x < 0.0 else mouse_override
	var anchor: Vector2 = pointer + Vector2(24, 18) if not Gamepad.active else Vector2(size_px.x * 0.5 + 40.0, size_px.y * 0.5 - 150.0)
	_draw_card(drop.item, player.stats.equipment.get(int(drop.item["slot"])), anchor, size_px, font, true, true)

## An item's details card at `anchor`: name, kind, stats and effect, then (optionally) how it compares with `worn`, and (for a drop on the
## ground) whether walking over it will put it on or send it to the bag.
func _draw_card(item: Dictionary, worn: Variant, anchor: Vector2, size_px: Vector2, font: Font, with_compare: bool, for_drop: bool) -> void:
	var color: Color = Items.RARITY_COLORS[int(item["rarity"])]
	var width: float = 340.0
	var pad: float = 14.0
	var inner: float = width - pad * 2.0
	var lines: Array[String] = Items.lines(item)
	var compare: Array[Dictionary] = []
	if with_compare:
		compare = Items.compare(item, worn)
	var height: float = pad * 2.0 + 54.0
	for line in lines:
		height += font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, inner, 14).y + 4.0
	if with_compare:
		height += 30.0 + 18.0 * compare.size()
	if for_drop:
		height += 30.0
	var pos := Vector2(clampf(anchor.x, 8.0, size_px.x - width - 8.0), clampf(anchor.y, 8.0, size_px.y - height - 110.0))
	UiTheme.draw_panel(self, Rect2(pos, Vector2(width, height)), 0.97)
	draw_rect(Rect2(pos + Vector2(3, 3), Vector2(4, height - 6)), color)   # a rarity-coloured spine
	var y: float = pos.y + pad + 18.0
	UiTheme.text(self, font, Vector2(pos.x + pad + 6.0, y), String(item["name"]), 21, color, HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0)
	y += 20.0
	UiTheme.text(self, font, Vector2(pos.x + pad + 6.0, y), "%s %s" % [Items.RARITY_NAMES[int(item["rarity"])], Items.SLOT_NAMES[int(item["slot"])]], 13,
		Color(1, 1, 1, 0.55))
	y += 10.0
	for line in lines:
		var h: float = font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, inner, 14).y
		draw_multiline_string(font, Vector2(pos.x + pad + 6.0, y + 14.0), line, HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0, 14, -1, Color(0.9, 0.88, 0.82))
		y += h + 4.0
	if with_compare:
		y += 8.0
		draw_line(Vector2(pos.x + pad, y), Vector2(pos.x + width - pad, y), Color(1, 1, 1, 0.12), 1.0)
		y += 18.0
		UiTheme.text(self, font, Vector2(pos.x + pad + 6.0, y), "Compared with %s" % (String((worn as Dictionary)["name"]) if worn != null else "your gear"), 13,
			Color(0.7, 0.68, 0.62), HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0)
		for entry in compare:
			y += 18.0
			var sign_color: Color = Color(0.5, 0.85, 0.5) if int(entry["sign"]) > 0 else (Color(0.9, 0.45, 0.4) if int(entry["sign"]) < 0 else Color(0.75, 0.75, 0.75))
			var mark: String = "+ " if int(entry["sign"]) > 0 else ("- " if int(entry["sign"]) < 0 else "= ")
			UiTheme.text(self, font, Vector2(pos.x + pad + 6.0, y), mark + String(entry["text"]), 14, sign_color)
	if for_drop:
		y += 26.0
		var upgrade: bool = player.stats.takes_empty_slot(item)
		UiTheme.text(self, font, Vector2(pos.x + pad + 6.0, y), "Walk over it: you will wear it (empty slot)" if upgrade else "Walk over it: it goes in the bag", 14,
			Color(0.95, 0.8, 0.5) if upgrade else Color(0.7, 0.68, 0.62))

## The dropped item the player is pointing at: under the mouse (by where it is on screen), or with a controller the nearest within reach.
func _drop_in_focus() -> LootDrop:
	var best: LootDrop = null
	var best_d: float = 1.0e9
	if Gamepad.active:
		for node in get_tree().get_nodes_in_group("loot"):
			var drop := node as LootDrop
			if drop == null or not drop.landed:
				continue
			var d: float = player.global_position.distance_to(drop.global_position)
			if d < 4.0 and d < best_d:
				best_d = d
				best = drop
		return best
	var mouse: Vector2 = get_viewport().get_mouse_position() if mouse_override.x < 0.0 else mouse_override
	if mouse_over_hud(mouse):
		return null
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null or not drop.landed or camera.is_position_behind(drop.global_position):
			continue
		var d: float = camera.unproject_position(drop.global_position + Vector3(0, 0.5, 0)).distance_to(mouse)
		if d < 56.0 and d < best_d:
			best_d = d
			best = drop
	return best

func mouse_over_hud(point: Vector2) -> bool:
	return covers(point)

## What you wear and what is in the bag, as pictures, top right. Shown while holding Tab; point at one for its details.
func _draw_gear(size_px: Vector2, font: Font) -> void:
	var tile: float = 64.0
	var gap: float = 10.0
	var columns: int = 6
	var w: float = columns * tile + (columns - 1) * gap
	var x: float = size_px.x - w - 30.0
	var y: float = 70.0
	var rows: int = maxi(1, ceili(float(player.stats.bag.size()) / columns))
	var height: float = 36.0 + 20.0 + tile + 30.0 + 20.0 + rows * (tile + gap) + 20.0
	UiTheme.draw_panel(self, Rect2(x - 16, y - 40, w + 32, height), 0.92)
	UiTheme.text(self, font, Vector2(x, y - 12), "Worn", 18, UiTheme.BRONZE_LIGHT.lightened(0.2))
	_gear_hits.clear()
	var pointer: Vector2 = get_viewport().get_mouse_position() if mouse_override.x < 0.0 else mouse_override
	y += 4.0
	for slot in 3:
		var rect := Rect2(Vector2(x + slot * (tile + gap), y), Vector2(tile, tile))
		var worn: Variant = player.stats.equipment.get(slot)
		if worn == null:
			draw_rect(rect, Color(0.04, 0.04, 0.05, 0.9))
			draw_rect(rect, Color(0.3, 0.28, 0.25), false, 2.0)
			UiTheme.text(self, font, rect.position + Vector2(0, tile * 0.55), Items.SLOT_NAMES[slot], 12, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER, tile)
		else:
			draw_texture_rect(ItemIcons.badge(worn), rect, false)
			_gear_hits.append({"rect": rect, "item": worn, "worn": true})
	y += tile + 34.0
	UiTheme.text(self, font, Vector2(x, y - 12), "Bag (%d)   kept for the town stash" % player.stats.bag.size(), 15, UiTheme.BRONZE_LIGHT.lightened(0.2))
	if player.stats.bag.is_empty():
		UiTheme.text(self, font, Vector2(x, y + 22), "Nothing yet. Items that are not upgrades go here.", 13, Color(1, 1, 1, 0.45))
	for i in player.stats.bag.size():
		var rect := Rect2(Vector2(x + (i % columns) * (tile + gap), y + (i / columns) * (tile + gap)), Vector2(tile, tile))
		draw_texture_rect(ItemIcons.badge(player.stats.bag[i]), rect, false)
		_gear_hits.append({"rect": rect, "item": player.stats.bag[i], "worn": false})
	for hit in _gear_hits:
		if (hit["rect"] as Rect2).has_point(pointer):
			draw_rect((hit["rect"] as Rect2).grow(2.0), Color(1.0, 0.85, 0.5, 0.9), false, 2.0)
			var item: Dictionary = hit["item"]
			_draw_card(item, null if bool(hit["worn"]) else player.stats.equipment.get(int(item["slot"])), Vector2(x - 372.0, 70.0), size_px, font,
				not bool(hit["worn"]), false)
			break

func _bar(pos: Vector2, size_px: Vector2, fraction: float, color: Color, label: String, font: Font) -> void:
	UiTheme.draw_bar(self, Rect2(pos, size_px), fraction, color, label, font)

## One hotbar slot: icon, radial cooldown sweep with seconds left, mana-cost tint, ready flash, bound key.
func _slot(pos: Vector2, size_px: float, action: String, id: String, font: Font) -> void:
	var rect := Rect2(pos, Vector2(size_px, size_px))
	var skill: Dictionary = SkillDb.all()[id]
	draw_rect(rect, UiTheme.INK)
	var icon: Texture2D = _icon(id)
	if icon != null:
		draw_texture_rect(icon, rect.grow(-3.0), false)
	else:
		draw_string(font, pos + Vector2(2, size_px * 0.5 + 4), skill["name"], HORIZONTAL_ALIGNMENT_CENTER, size_px - 4, 11, Color(1, 1, 1))

	if player.stats.skill_has_modifier(id):
		# A small gold diamond: gear you wear is changing this skill (hover it for the details).
		var c: Vector2 = pos + Vector2(size_px - 11.0, 11.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)]), Color(0.1, 0.07, 0.02, 0.9))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), Color(1.0, 0.82, 0.3))
	var remaining: float = float(player.stats.cooldowns.get(id, 0.0))
	var fraction: float = player.stats.cooldown_fraction(id)
	_slot_hits.append({"rect": rect, "id": id, "action": action})
	var affordable: bool = player.stats.mana >= float(skill["mana"])
	if not affordable:
		draw_rect(rect, Color(0.12, 0.2, 0.42, 0.5))

	# An ultimate has no cooldown: it fills from the bottom as damage is dealt and glows when it is ready to use.
	var ult_cost: float = player.stats.ult_cost(id)
	var ult_filling: bool = ult_cost > 0.0 and player.stats.ult_charge < ult_cost
	# Ready flash: the moment a cooldown ends (or the ultimate is full) the slot pulses white.
	var was_on_cooldown: bool = _was_cooling.get(id, false)
	if was_on_cooldown and remaining <= 0.0 and not ult_filling:
		_ready_flash[id] = 0.35
	_was_cooling[id] = remaining > 0.0 or ult_filling
	var flash: float = float(_ready_flash.get(id, 0.0))
	if flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, 0.55 * flash / 0.35))
		_ready_flash[id] = maxf(flash - get_process_delta_time(), 0.0)

	if remaining > 0.0:
		draw_rect(rect, Color(0, 0, 0, 0.18))
		draw_colored_polygon(_sweep_polygon(rect, fraction), Color(0, 0, 0, 0.5))
		var text: String = "%.1f" % remaining if remaining < 10.0 else str(int(ceil(remaining)))
		draw_string(font, Vector2(pos.x, pos.y + size_px * 0.62), text, HORIZONTAL_ALIGNMENT_CENTER, size_px, 26, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(pos.x, pos.y + size_px * 0.6), text, HORIZONTAL_ALIGNMENT_CENTER, size_px, 26, Color(1, 0.95, 0.85))

	var border: Color = Color(0.85, 0.72, 0.45, 0.9) if remaining <= 0.0 and affordable else Color(0.4, 0.4, 0.45, 0.9)
	if ult_cost > 0.0:
		var filled: float = player.stats.ult_fraction(id)
		if ult_filling:
			draw_rect(Rect2(pos, Vector2(size_px, size_px * (1.0 - filled))), Color(0, 0, 0, 0.62))   # the unfilled part stays dark
			draw_rect(Rect2(pos + Vector2(0, size_px * (1.0 - filled)), Vector2(size_px, size_px * filled)), Color(1.0, 0.55, 0.15, 0.22))
			draw_string(font, Vector2(pos.x, pos.y + size_px * 0.62), "%d%%" % int(filled * 100.0), HORIZONTAL_ALIGNMENT_CENTER, size_px, 22, Color(1, 0.95, 0.85))
			border = Color(0.55, 0.4, 0.25, 0.9)
		else:
			var beat: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
			draw_rect(rect.grow(2.0 + 2.0 * beat), Color(1.0, 0.6, 0.2, 0.35 + 0.35 * beat), false, 3.0)
			border = Color(1.0, 0.8, 0.4, 1.0)
	draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.9), false, 2.0)
	draw_rect(rect, border, false, 2.0)
	# Key hint (follows rebinding), potion count and mana cost.
	var key_text: String = GameSettings.short_binding_text(action)
	draw_string(font, pos + Vector2(5, 15), key_text, HORIZONTAL_ALIGNMENT_LEFT, size_px - 8, 12, Color(0, 0, 0, 0.9))
	draw_string(font, pos + Vector2(4, 14), key_text, HORIZONTAL_ALIGNMENT_LEFT, size_px - 8, 12, Color(1, 0.92, 0.55))
	if id == "potion":
		draw_string(font, pos + Vector2(0, size_px - 5), "x%d" % player.stats.potions, HORIZONTAL_ALIGNMENT_RIGHT, size_px - 5, 15, Color(1, 1, 1))
	elif float(skill["mana"]) > 0.0:
		draw_string(font, pos + Vector2(5, size_px - 5), str(int(skill["mana"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.75, 1.0))

## Hover tooltip for hotbar skills: name, key, cost/cooldown, what it does, and gear that modifies it.
func _draw_tooltip(font: Font, size_px: Vector2) -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position() if mouse_override.x < 0.0 else mouse_override
	for hit in _slot_hits:
		var rect: Rect2 = hit["rect"]
		if not rect.has_point(mouse):
			continue
		var id: String = hit["id"]
		var skill: Dictionary = SkillDb.all()[id]
		var width: float = 340.0
		var pad: float = 14.0
		var inner: float = width - pad * 2.0
		var stats: Array[String] = []
		if float(skill["mana"]) > 0.0:
			stats.append("Mana %d" % int(skill["mana"]))
		if float(skill["cd"]) > 0.0:
			stats.append("Cooldown %.1f s" % float(skill["cd"]))
		if float(skill["range"]) > 0.0:
			stats.append("Range %d m" % int(round(float(skill["range"]))))
		if id == "dodge":
			stats.append("Stamina %d" % int(round(PlayerMovement.ROLL_STAMINA * player.stats.armor_stat("roll_cost", 1.0))))
		var stat_line: String = "    ".join(stats)
		var damage_line: String = player.stats.skill_damage_text(id)
		var desc: String = SkillDb.description(id)
		var mods: Array[String] = []
		for affix_id in SkillDb.modifier_affixes(id):
			if player.stats.has_affix(affix_id):
				mods.append(AffixDb.all()[affix_id]["desc"])
		# Measure, then draw the panel.
		var height: float = pad + 26.0
		if stat_line != "":
			height += 20.0
		if damage_line != "":
			height += 20.0
		height += font.get_multiline_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, inner, 15).y + 10.0
		for m in mods:
			height += font.get_multiline_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, inner, 14).y + 6.0
		if not mods.is_empty():
			height += 18.0
		height += pad
		var pos := Vector2(clampf(rect.get_center().x - width * 0.5, 8.0, size_px.x - width - 8.0), rect.position.y - height - 10.0)
		UiTheme.draw_panel(self, Rect2(pos, Vector2(width, height)), 0.97)
		var y: float = pos.y + pad + 16.0
		draw_string(font, Vector2(pos.x + pad, y), skill["name"], HORIZONTAL_ALIGNMENT_LEFT, inner - 70.0, 21, Color(1.0, 0.88, 0.6))
		draw_string(font, Vector2(pos.x + width - pad - 66.0, y), "[%s]" % GameSettings.short_binding_text(hit["action"]),
			HORIZONTAL_ALIGNMENT_RIGHT, 66.0, 14, Color(1, 0.92, 0.55))
		y += 10.0
		if stat_line != "":
			y += 18.0
			draw_string(font, Vector2(pos.x + pad, y), stat_line, HORIZONTAL_ALIGNMENT_LEFT, inner, 14, Color(0.6, 0.78, 1.0))
		if damage_line != "":
			y += 20.0
			draw_string(font, Vector2(pos.x + pad, y), damage_line, HORIZONTAL_ALIGNMENT_LEFT, inner, 14, Color(1.0, 0.65, 0.4))
		y += 22.0
		draw_multiline_string(font, Vector2(pos.x + pad, y), desc, HORIZONTAL_ALIGNMENT_LEFT, inner, 15, -1, Color(0.92, 0.9, 0.85))
		y += font.get_multiline_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, inner, 15).y - 8.0
		if not mods.is_empty():
			y += 20.0
			draw_string(font, Vector2(pos.x + pad, y), "From your gear", HORIZONTAL_ALIGNMENT_LEFT, inner, 13, Color(0.45, 0.72, 1.0))
			for m in mods:
				y += 16.0
				draw_multiline_string(font, Vector2(pos.x + pad, y), m, HORIZONTAL_ALIGNMENT_LEFT, inner, 14, -1, Color(0.8, 0.85, 0.95))
				y += font.get_multiline_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, inner, 14).y - 12.0
		return

static var _icons: Dictionary = {}
## Test hook: when set (x >= 0) it replaces the real mouse position for tooltips.
var mouse_override: Vector2 = Vector2(-1.0, -1.0)
var _slot_hits: Array = []  # [{rect, id, action}] for the slots drawn this frame (tooltip hit-testing)
var _was_cooling: Dictionary = {}
var _ready_flash: Dictionary = {}

func _icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path: String = "res://assets/icons/%s.png" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]

## Pie polygon covering the part of the square still on cooldown, sweeping clockwise from the top.
## `fraction` is the share of the cooldown remaining; the elapsed part stays clear.
func _sweep_polygon(rect: Rect2, fraction: float) -> PackedVector2Array:
	var centre: Vector2 = rect.get_center()
	var half: float = rect.size.x * 0.5
	var points := PackedVector2Array([centre])
	var start: float = -PI * 0.5 + (1.0 - fraction) * TAU
	var steps: int = maxi(int(ceil(fraction * 48.0)), 2)
	for i in steps + 1:
		var a: float = start + (TAU - (1.0 - fraction) * TAU) * float(i) / float(steps)
		var dir := Vector2(cos(a), sin(a))
		var t: float = half / maxf(maxf(absf(dir.x), absf(dir.y)), 0.0001)
		points.append(centre + dir * t)
	return points
