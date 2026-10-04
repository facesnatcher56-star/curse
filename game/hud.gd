class_name Hud
extends Control
## Single-pass HUD: bars, hotbar, target bar, wave info, messages. Drawn in code.

var player: Player
var arena: Arena
var wave: int = 0
var kills: int = 0
var alive: int = 0
# Reward choice (see main.gd) and gear panel.
var choosing: bool = false
var choices: Array[Dictionary] = []
var card_rects: Array[Rect2] = []
var show_gear: bool = false
var banner_text: String = ""
var banner_time: float = 0.0

func show_banner(text: String, seconds: float = 2.5) -> void:
	banner_text = text
	banner_time = seconds

func _ready() -> void:
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
	_bar(base, Vector2(260, 24), player.health / player.max_health, Color(0.75, 0.12, 0.12),
		"%d / %d" % [int(player.health), int(player.max_health)], font)
	_bar(base + Vector2(0, 30), Vector2(260, 18), player.mana / player.max_mana, Color(0.15, 0.35, 0.85),
		"%d / %d" % [int(player.mana), int(player.max_mana)], font)
	_bar(base + Vector2(0, 54), Vector2(260, 8), player.stamina / player.max_stamina, Color(0.85, 0.75, 0.2), "", font)

	_slot_hits.clear()
	# Hotbar, bottom centre.
	var slot: float = 64.0
	var slot_count: int = player.hotbar.size() + 2
	var total: float = slot * slot_count + 8 * (slot_count - 1)
	var x0: float = (size_px.x - total) * 0.5
	var y0: float = size_px.y - slot - 24
	for i in player.hotbar.size():
		var id: String = player.hotbar[i]
		_slot(Vector2(x0 + i * (slot + 8), y0), slot, "skill_%d" % (i + 1), id, font)
	var extra: int = player.hotbar.size()
	_slot(Vector2(x0 + extra * (slot + 8), y0), slot, "alt_skill", player.right_click_skill, font)
	_slot(Vector2(x0 + (extra + 1) * (slot + 8), y0), slot, "dodge", "dodge", font)
	_draw_tooltip(font, size_px)
	if player.aiming_id != "":
		draw_string(font, Vector2(0, y0 - 14.0), "Release %s to cast %s" % [GameSettings.short_binding_text(player.aiming_action),
			SkillDb.all()[player.aiming_id]["name"]], HORIZONTAL_ALIGNMENT_CENTER, size_px.x, 20, Color(1.0, 0.75, 0.4))

	# Target bar, top centre: whatever the mouse is over, else what we are attacking.
	var target: Actor = player.hover_target
	if target == null:
		target = player.attack_target
	if target == null and player.queued_target != null:
		target = player.queued_target
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
		draw_string(font, Vector2(0, size_px.y * 0.28), banner_text, HORIZONTAL_ALIGNMENT_CENTER, size_px.x, 52,
			Color(1.0, 0.9, 0.7, fade))
	draw_string(font, Vector2(24, 34), "Wave %d   Kills %d   Zombies %d" % [wave, kills, alive],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(24, 58), "LMB move/attack   1-3 skills   4 potion   RMB attack   Ctrl stand still   Space dodge   Tab gear",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.55))

	_draw_minimap(size_px, font)

	if choosing:
		_draw_reward(size_px, font)
	elif show_gear:
		_draw_gear(size_px, font)

	if player.message_time > 0.0:
		draw_string(font, Vector2(0, size_px.y - 150), player.message, HORIZONTAL_ALIGNMENT_CENTER,
			size_px.x, 22, Color(1, 0.85, 0.4, minf(player.message_time, 1.0)))
	if player.dead:
		draw_rect(Rect2(Vector2.ZERO, size_px), Color(0, 0, 0, 0.55))
		draw_string(font, Vector2(0, size_px.y * 0.45), "YOU DIED", HORIZONTAL_ALIGNMENT_CENTER, size_px.x, 64, Color(0.8, 0.1, 0.1))
		draw_string(font, Vector2(0, size_px.y * 0.45 + 40), "Press R to restart", HORIZONTAL_ALIGNMENT_CENTER, size_px.x, 24, Color(1, 1, 1))

## Whole-arena minimap, bottom right. The camera never rotates, so world -Z is up on the map.
func _draw_minimap(size_px: Vector2, font: Font) -> void:
	var side: float = 210.0
	var rect := Rect2(Vector2(size_px.x - side - 24.0, size_px.y - side - 24.0), Vector2(side, side))
	var half: float = Arena.HALF
	var scale_px: float = side / (half * 2.0)
	var centre: Vector2 = rect.get_center()
	draw_rect(rect, Color(0.04, 0.04, 0.05, 0.72))
	if arena != null:
		for obstacle in arena.obstacles:
			var op: Vector3 = obstacle["position"]
			var r: float = maxf(float(obstacle["radius"]) * scale_px, 1.5)
			draw_circle(centre + Vector2(op.x, op.z) * scale_px, r, Color(0.3, 0.3, 0.34, 0.5))
	# Enemies: red dots, larger orange for bosses; the nearest few are not special, the count is in the header.
	var count: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Actor
		if enemy == null or enemy.dead:
			continue
		count += 1
		var p: Vector3 = enemy.global_position
		var at: Vector2 = centre + Vector2(clampf(p.x, -half, half), clampf(p.z, -half, half)) * scale_px
		if enemy.is_boss or enemy.max_health >= 150.0:
			draw_circle(at, 5.0, Color(0, 0, 0, 0.8))
			draw_circle(at, 3.8, Color(1.0, 0.55, 0.12))
		else:
			draw_circle(at, 3.0, Color(0, 0, 0, 0.7))
			draw_circle(at, 2.2, Color(0.95, 0.15, 0.12))
	# The hero: a white arrow pointing the way they face.
	var pp: Vector3 = player.global_position
	var me: Vector2 = centre + Vector2(pp.x, pp.z) * scale_px
	var yaw: float = player.visual.rotation.y if player.visual != null else 0.0
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side_v := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([me + fwd * 7.0, me - fwd * 4.0 + side_v * 4.5, me - fwd * 2.0, me - fwd * 4.0 - side_v * 4.5]),
		Color(1, 1, 1))
	draw_rect(rect, Color(0.8, 0.7, 0.5, 0.6), false, 2.0)
	draw_string(font, rect.position + Vector2(8, 18), "%d left" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))

## Equipped items, top right. Shown while holding Tab.
func _draw_gear(size_px: Vector2, font: Font) -> void:
	var w: float = 330.0
	var x: float = size_px.x - w - 16.0
	var y: float = 70.0
	draw_rect(Rect2(x - 8, y - 22, w + 16, 330), Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(x, y), "Equipped", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	y += 24.0
	for slot in 3:
		var item: Variant = player.equipment.get(slot)
		draw_string(font, Vector2(x, y), Items.SLOT_NAMES[slot], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
		y += 17.0
		if item == null:
			draw_string(font, Vector2(x, y), "Empty", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.4))
			y += 30.0
			continue
		var it: Dictionary = item
		draw_string(font, Vector2(x, y), it["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Items.RARITY_COLORS[it["rarity"]])
		y += 18.0
		for line in Items.lines(it):
			draw_multiline_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, w, 12, -1, Color(1, 1, 1, 0.75))
			y += maxf(font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, w, 12).y, 14.0) + 2.0
		y += 8.0

## One-of-three reward cards between waves.
func _draw_reward(size_px: Vector2, font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size_px), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(0, size_px.y * 0.12), "Choose a reward", HORIZONTAL_ALIGNMENT_CENTER, size_px.x, 36, Color(1, 0.92, 0.75))
	var card_w: float = 300.0
	var card_h: float = 330.0
	var gap: float = 28.0
	var count: int = choices.size()
	var x0: float = (size_px.x - (card_w * count + gap * (count - 1))) * 0.5
	var y0: float = size_px.y * 0.2
	card_rects.clear()
	for i in count:
		var item: Dictionary = choices[i]
		var rect := Rect2(Vector2(x0 + i * (card_w + gap), y0), Vector2(card_w, card_h))
		card_rects.append(rect)
		var hovered: bool = rect.has_point(get_viewport().get_mouse_position())
		var color: Color = Items.RARITY_COLORS[item["rarity"]]
		draw_rect(rect, Color(0.08, 0.08, 0.1, 0.96) if not hovered else Color(0.14, 0.14, 0.18, 0.98))
		draw_rect(rect, color, false, 3.0 if hovered else 2.0)
		var pad: float = 16.0
		var y: float = rect.position.y + 30.0
		draw_string(font, Vector2(rect.position.x + pad, y), "[%d]" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.5))
		y += 28.0
		draw_multiline_string(font, Vector2(rect.position.x + pad, y), item["name"],
			HORIZONTAL_ALIGNMENT_LEFT, card_w - pad * 2.0, 24, -1, color)
		y += maxf(font.get_multiline_string_size(item["name"], HORIZONTAL_ALIGNMENT_LEFT, card_w - pad * 2.0, 24).y, 28.0)
		draw_string(font, Vector2(rect.position.x + pad, y), "%s  -  %s" % [Items.RARITY_NAMES[item["rarity"]], Items.SLOT_NAMES[item["slot"]]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
		y += 26.0
		for line in Items.lines(item):
			draw_multiline_string(font, Vector2(rect.position.x + pad, y), line,
				HORIZONTAL_ALIGNMENT_LEFT, card_w - pad * 2.0, 15, -1, Color(1, 1, 1, 0.9))
			y += maxf(font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, card_w - pad * 2.0, 15).y, 16.0) + 8.0
		var current: Variant = player.equipment.get(int(item["slot"]))
		var replaces: String = "Replaces: %s" % (current["name"] if current != null else "nothing")
		draw_string(font, Vector2(rect.position.x + pad, rect.end.y - 14.0), replaces, HORIZONTAL_ALIGNMENT_LEFT, card_w - pad * 2.0, 12, Color(1, 1, 1, 0.45))
	draw_string(font, Vector2(0, y0 + card_h + 44.0), "Press 1-3 or click to take one.   [4] Skip for a potion",
		HORIZONTAL_ALIGNMENT_CENTER, size_px.x, 16, Color(1, 1, 1, 0.65))

func _bar(pos: Vector2, size_px: Vector2, fraction: float, color: Color, label: String, font: Font) -> void:
	draw_rect(Rect2(pos, size_px), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(pos, Vector2(size_px.x * clampf(fraction, 0.0, 1.0), size_px.y)), color)
	draw_rect(Rect2(pos, size_px), Color(1, 1, 1, 0.35), false, 1.0)
	if label != "":
		draw_string(font, pos + Vector2(0, size_px.y - 5), label, HORIZONTAL_ALIGNMENT_CENTER, size_px.x, 13, Color(1, 1, 1))

## One hotbar slot: icon, radial cooldown sweep with seconds left, mana-cost tint, ready flash, bound key.
func _slot(pos: Vector2, size_px: float, action: String, id: String, font: Font) -> void:
	var rect := Rect2(pos, Vector2(size_px, size_px))
	var skill: Dictionary = SkillDb.all()[id]
	draw_rect(rect, Color(0.17, 0.16, 0.2, 0.95))
	var icon: Texture2D = _icon(id)
	if icon != null:
		draw_texture_rect(icon, rect.grow(-3.0), false)
	else:
		draw_string(font, pos + Vector2(2, size_px * 0.5 + 4), skill["name"], HORIZONTAL_ALIGNMENT_CENTER, size_px - 4, 11, Color(1, 1, 1))

	if player.skill_has_modifier(id):
		# A small gold diamond: gear you wear is changing this skill (hover it for the details).
		var c: Vector2 = pos + Vector2(size_px - 11.0, 11.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)]), Color(0.1, 0.07, 0.02, 0.9))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), Color(1.0, 0.82, 0.3))
	var remaining: float = float(player.cooldowns.get(id, 0.0))
	var fraction: float = player.cooldown_fraction(id)
	_slot_hits.append({"rect": rect, "id": id, "action": action})
	var affordable: bool = player.mana >= float(skill["mana"])
	if not affordable:
		draw_rect(rect, Color(0.1, 0.2, 0.6, 0.45))

	# Ready flash: the moment a cooldown ends the slot pulses white.
	var was_on_cooldown: bool = _was_cooling.get(id, false)
	if was_on_cooldown and remaining <= 0.0:
		_ready_flash[id] = 0.35
	_was_cooling[id] = remaining > 0.0
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
	draw_rect(rect, border, false, 2.0)
	# Key hint (follows rebinding), potion count and mana cost.
	var key_text: String = GameSettings.short_binding_text(action)
	draw_string(font, pos + Vector2(5, 15), key_text, HORIZONTAL_ALIGNMENT_LEFT, size_px - 8, 12, Color(0, 0, 0, 0.9))
	draw_string(font, pos + Vector2(4, 14), key_text, HORIZONTAL_ALIGNMENT_LEFT, size_px - 8, 12, Color(1, 0.92, 0.55))
	if id == "potion":
		draw_string(font, pos + Vector2(0, size_px - 5), "x%d" % player.potions, HORIZONTAL_ALIGNMENT_RIGHT, size_px - 5, 15, Color(1, 1, 1))
	elif float(skill["mana"]) > 0.0:
		draw_string(font, pos + Vector2(5, size_px - 5), str(int(skill["mana"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.75, 1.0))

## Hover tooltip for hotbar skills: name, key, cost/cooldown, what it does, and gear that modifies it.
func _draw_tooltip(font: Font, size_px: Vector2) -> void:
	if choosing:
		return
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
			stats.append("Stamina %d" % int(round(Player.ROLL_STAMINA * player.armor_stat("roll_cost", 1.0))))
		var stat_line: String = "    ".join(stats)
		var damage_line: String = player.skill_damage_text(id)
		var desc: String = SkillDb.description(id)
		var mods: Array[String] = []
		for affix_id in SkillDb.modifier_affixes(id):
			if player.has_affix(affix_id):
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
		draw_rect(Rect2(pos, Vector2(width, height)), Color(0.06, 0.06, 0.08, 0.97))
		draw_rect(Rect2(pos, Vector2(width, height)), Color(0.85, 0.72, 0.45, 0.9), false, 2.0)
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