class_name Hud
extends Control
## Single-pass HUD: bars, hotbar, target bar, wave info, messages. Drawn in code.

var player: Player
var arena: Arena
var wave: int = 0
## What the job asks, with its progress ("Destroy nests: 1 / 3"), shown in place of the wave number when not "" (see RunDirector.objective_line).
var objective: String = ""
## How far down the top-left panel sits (the town draws its resource bar above it) and whether the minimap always shows a window round
## the hero rather than the whole arena (the world is a plaza and a long road).
var top_offset: float = 0.0
var force_window: bool = false
## True in the town/road world, where a fallen hero is dragged home rather than restarting the run (the arena sets nothing: it restarts).
var world_mode: bool = false
var kills: int = 0
var alive: int = 0
# Gear panel.
var show_gear: bool = false
var character_panel: Control
var banner_text: String = ""
var banner_time: float = 0.0
## The baked iron of the tray and the slot bezels is neutral grey; this warms it toward tarnished bronze-brown so the HUD is not one tone.
const METAL_WARMTH := Color(1.32, 1.04, 0.80, 1.0)
var health_orb: Control
var _busts: Array[TextureRect] = []
var _plinths: Array[TextureRect] = []
var mana_orb: Control
var tray: Texture2D
var bezel: Texture2D
const Ds2PartyFrameClass := preload("res://game/ui/ds2_party_frame.gd")
const Ds2TargetBannerClass := preload("res://game/ui/ds2_target_banner.gd")
const Ds2PotionDockClass := preload("res://game/ui/ds2_potion_dock.gd")

var use_ds2_ui: bool = true
var ds2_party_frame: Control
var ds2_target_banner: Control
var ds2_potion_dock: Control
var ds2_action_bezel: Texture2D
var ds2_power_bezel: Texture2D
var ds2_compass_ring: Texture2D

func show_banner(text: String, seconds: float = 2.5) -> void:
	banner_text = text
	banner_time = seconds

var progression_hud: ProgressionHud
## The level-up plate lives in ProgressionHud; these read through so anything that asks the HUD (tests, the town) still can.
var level_toast_text: String:
	get: return progression_hud.toast_text if progression_hud != null else ""
var level_toast_points: String:
	get: return progression_hud.toast_points if progression_hud != null else ""
var level_toast_time: float:
	get: return progression_hud.toast_time if progression_hud != null else 0.0

func _ready() -> void:
	progression_hud = ProgressionHud.new()   # the level and XP strip, the level-up plate and the points-available mark
	add_child(progression_hud)
	add_to_group("hud")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in 2:   # the carved slab each bust sits on, running from the screen's edge in to its vessel
		var slab := TextureRect.new()
		slab.texture = preload("res://assets/ui/vessels/bust_plinth.png")
		slab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slab.stretch_mode = TextureRect.STRETCH_SCALE
		slab.flip_h = side == 1
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slab)
		_plinths.append(slab)
	for side in 2:   # the two busts sit behind the vessels, at the screen's edges: the hero's helmed head on the health side, a hooded shape on the mana side
		var bust := TextureRect.new()
		bust.texture = load("res://assets/ui/busts/%s.png" % ("knight" if side == 0 else "priest")) as Texture2D
		bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bust)
		_busts.append(bust)
	health_orb = preload("res://game/resource_orb.gd").new()
	health_orb.title = "Health"
	health_orb.color = UiTheme.BLOOD
	add_child(health_orb)
	mana_orb = preload("res://game/resource_orb.gd").new()
	mana_orb.title = "Mana"
	mana_orb.color = UiTheme.MANA
	add_child(mana_orb)
	tray = preload("res://assets/ui/vessels/hotbar_tray.png")
	bezel = preload("res://assets/ui/vessels/skill_bezel.png")
	ds2_action_bezel = preload("res://assets/ui/ds2/action_slot_bezel.png")
	ds2_power_bezel = preload("res://assets/ui/ds2/power_bezel.png")
	ds2_compass_ring = preload("res://assets/ui/ds2/compass_ring.png")

	ds2_party_frame = Ds2PartyFrameClass.new()
	add_child(ds2_party_frame)

	ds2_target_banner = Ds2TargetBannerClass.new()
	add_child(ds2_target_banner)

	ds2_potion_dock = Ds2PotionDockClass.new()
	add_child(ds2_potion_dock)

## The minimap is its own canvas item, redrawn 20 times a second instead of every frame: it walks every obstacle and monster in the world
## (hundreds), and doing that at the full frame rate was about 8 ms of every frame, the biggest cost in the plaza.
const MAP_REDRAW := 0.05
## How far the hotbar sits above the bottom edge: the XP bar and the level badge run along the very bottom, under it.
const HOTBAR_LIFT := 30.0
var _map: Control
var _map_clock: float = 0.0
## The map under the dots, and its fog of war (see MinimapMap). Two children drawn BEHIND the map item (frame, then the clipped terrain+fog view), so
## the dots, the nests and the hero's arrow, which the map item itself draws, sit on top of them.
var map_data: MinimapMap = MinimapMap.new()
var _map_frame: Control
var _map_view: Control
var _map_content: Control

func _paint_map() -> void:
	if player != null:
		_draw_minimap(_map, get_viewport_rect().size, ThemeDB.fallback_font)

## The round map's frame: a dark worn-iron ring with a bronze line, studs at the four quarters, the compass N (it turns with the camera, so it
## always points to world north) and the name of the place under it.
func _paint_map_frame() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var rect: Rect2 = minimap_rect(screen, use_ds2_ui)
	var c: Vector2 = rect.get_center()
	var radius: float = rect.size.x * 0.5
	var f: Control = _map_frame
	if use_ds2_ui and ds2_compass_ring != null:
		var inner_radius: float = radius * 0.69
		# 1. Solid circular backing disc behind the map view
		f.draw_circle(c, inner_radius + 2.0, Color(0.10, 0.09, 0.08, 0.98))
		# 2. Draw compass ring matching the aperture exactly
		var ring_span: float = (inner_radius / 0.6914) * 2.0
		var ring_rect := Rect2(c - Vector2.ONE * (ring_span * 0.5), Vector2.ONE * ring_span)
		f.draw_texture_rect(ds2_compass_ring, ring_rect, false)
		# 3. Zone name neatly positioned above the compass ring
		UiTheme.text(f, UiTheme.heading_font(), Vector2(c.x - 120.0, rect.position.y - 18.0), zone_name().to_upper(), 13, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
		return
	f.draw_circle(c + Vector2(0, 5), radius + 12.0, Color(0, 0, 0, 0.45))        # the shadow it casts
	f.draw_circle(c, radius, Color(0.105, 0.09, 0.08, 0.96))                       # what the map sits on: worn earth, not a black hole beyond the world
	f.draw_arc(c, radius + 5.0, 0.0, TAU, 96, Color(0.055, 0.05, 0.06), 11.0)      # the iron
	f.draw_arc(c, radius + 9.5, 0.0, TAU, 96, Color(0, 0, 0, 0.9), 2.0)
	f.draw_arc(c, radius + 6.0, -2.4, -0.7, 32, UiTheme.BRONZE_LIGHT.darkened(0.35), 1.5)   # a glint, upper right
	f.draw_arc(c, radius + 0.5, 0.0, TAU, 96, UiTheme.BRONZE.darkened(0.1), 1.5)   # the bronze inner line
	for quarter in 4:
		var stud: Vector2 = c + Vector2.from_angle(quarter * PI * 0.5) * (radius + 5.0)
		f.draw_circle(stud, 3.2, Color(0, 0, 0, 0.85))
		f.draw_circle(stud, 2.0, UiTheme.BRONZE_LIGHT.darkened(0.3))
	var north: Vector2 = c + Vector2(0, -1).rotated(Gamepad.view_yaw) * (radius + 17.0)
	UiTheme.text(f, UiTheme.heading_font(), north + Vector2(-5.0, 5.5), "N", 15, UiTheme.BRONZE_LIGHT.lightened(0.15))
	UiTheme.text(f, UiTheme.heading_font(), Vector2(rect.position.x, rect.end.y + 30.0), zone_name().to_upper(), 15, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x)

## Where the hero is, for the map's caption and the title at the top left.
func zone_name() -> String:
	if player == null:
		return ""
	for node in get_tree().get_nodes_in_group("crypt_road"):
		var road := node as CryptRoad
		if road != null and road.arena != null:
			var local: Vector3 = player.global_position - road.arena.origin_offset
			if absf(local.x) <= road.arena.half_x and absf(local.z) <= road.arena.half_z:
				return "The Crypt Road" if local.z > CryptRoad.FORECOURT_Z else "The Crypt Forecourt"
	return "The Last Hearth"

func zone_subtitle() -> String:
	var zone: String = zone_name()
	return "Safe Haven" if zone == "The Last Hearth" else ("Hostile Ground" if zone == "The Crypt Road" else "Deep Beyond")

func _paint_map_view() -> void:
	if player == null:
		return
	var radius: float = (_map_view.size.x * 0.5 * 0.69) if use_ds2_ui else (_map_view.size.x * 0.5)
	_map_view.draw_circle(_map_view.size * 0.5, radius, Color.WHITE)   # this item only clips the one under it to a circle (it is not shown)

func _paint_map_content() -> void:
	if player == null:
		return
	var params: Dictionary = map_view_params(get_viewport_rect().size)
	map_data.draw(_map_content, MinimapMap.transform_for(params["origin"], Gamepad.view_yaw, float(params["scale"]), _map_content.size * 0.5))

## How the map is framed: a window round the hero in the connected world (and on any long arena), the whole arena otherwise.
func map_view_params(size_px: Vector2) -> Dictionary:
	var bounds: Vector2 = Arena.bounds_of(get_tree())
	var windowed: bool = force_window or bounds.y > bounds.x * 1.6
	var half: float = 45.0 if windowed else Arena.HALF
	var origin: Vector3 = player.global_position if windowed and player != null else Vector3.ZERO
	return {"windowed": windowed, "half": half, "origin": origin, "scale": minimap_rect(size_px, use_ds2_ui).size.x / (half * 2.0)}

func _make_map_layers() -> void:
	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.draw.connect(_paint_map)
	add_child(_map)
	_map_frame = Control.new()
	_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_frame.show_behind_parent = true
	_map_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_frame.draw.connect(_paint_map_frame)
	_map.add_child(_map_frame)
	_map_view = Control.new()   # a disc that clips what is drawn in it (the map content) to a circle; it is not shown itself
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.show_behind_parent = true
	_map_view.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_map_view.draw.connect(_paint_map_view)
	_map.add_child(_map_view)
	_map_content = Control.new()
	_map_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_content.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_map_content.draw.connect(_paint_map_content)
	_map_view.add_child(_map_content)

func _process(delta: float) -> void:
	if _map == null:
		_make_map_layers()
	_map_clock += delta
	if _map_clock >= MAP_REDRAW:
		_map_clock = 0.0
		if player != null:
			map_data.ensure_built(get_tree())
			map_data.reveal(player.global_position)
			var view: Rect2 = minimap_rect(get_viewport_rect().size, use_ds2_ui)
			_map_view.position = view.position
			_map_view.size = view.size
		_map.queue_redraw()
		_map_frame.queue_redraw()
		_map_view.queue_redraw()
		_map_content.queue_redraw()
	if player != null:
		var screen: Vector2 = get_viewport_rect().size
		var hp_rect: Rect2 = orb_rect(screen, false)
		var mp_rect: Rect2 = orb_rect(screen, true)
		for side in _plinths.size():
			var reach: float = hp_rect.position.x + hp_rect.size.x * 0.55
			var slab_h: float = maxf(reach / 8.0, 12.0)
			_plinths[side].size = Vector2(reach, slab_h)
			_plinths[side].position = Vector2(0.0 if side == 0 else screen.x - reach, screen.y - slab_h - 4.0)
			_plinths[side].visible = not use_ds2_ui
		for side in _busts.size():
			var span: float = hp_rect.size.x * 0.92
			_busts[side].size = Vector2(span, span)
			_busts[side].position = Vector2(0.0 if side == 0 else screen.x - span, screen.y - span + 6.0)
			_busts[side].visible = not use_ds2_ui
		health_orb.position = hp_rect.position
		health_orb.size = hp_rect.size
		mana_orb.position = mp_rect.position
		mana_orb.size = mp_rect.size
		health_orb.visible = not use_ds2_ui
		mana_orb.visible = not use_ds2_ui
		health_orb.update_value(player.health, player.max_health, delta, player.velocity)
		mana_orb.update_value(player.stats.mana, player.stats.max_mana, delta, player.velocity)

		if use_ds2_ui:
			ds2_party_frame.visible = true
			ds2_party_frame.update_frame(player)
			var target: Actor = player.hover_target
			if target == null:
				target = player.attack_target
			if target == null and player.skills != null:
				target = player.skills.queued_target
			ds2_target_banner.update_target(target, delta)
			ds2_potion_dock.visible = true
			ds2_potion_dock.update_dock(player)
		else:
			ds2_party_frame.visible = false
			ds2_target_banner.visible = false
			ds2_potion_dock.visible = false
	banner_time = maxf(banner_time - delta, 0.0)
	queue_redraw()

func _draw() -> void:
	if player == null:
		return
	var size_px: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font

	if player.hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size_px), Color(0.8, 0.0, 0.0, 0.25 * player.hurt_flash))

	_slot_hits.clear()
	# Hotbar, bottom centre.
	var slot: float = hotbar_slot_size(size_px)
	var slot_count: int = player.skills.hotbar.size() + 2
	var total: float = slot * slot_count + 8 * (slot_count - 1)
	var x0: float = (size_px.x - total) * 0.5
	var bar_height: float = slot + 28.0
	var y0: float = (size_px.y - bar_height + 6.0) if use_ds2_ui else (size_px.y - slot - 18.0 - HOTBAR_LIFT)
	if use_ds2_ui:
		_draw_ds2_runner_bar(size_px, x0, y0, total, slot, bar_height)
	else:
		draw_texture_rect(tray, Rect2(x0 - 24.0, y0 - 22.0, total + 48.0, slot + 44.0), false, METAL_WARMTH)
	# (A narrow stamina bar used to sit here, just above the skill tray; stamina is off, see PlayerStats.STAMINA_ON.)
	if PlayerStats.STAMINA_ON:
		_bar(Vector2(x0, y0 - 13.0), Vector2(total, 5), player.stats.stamina / player.stats.max_stamina, UiTheme.STAMINA, "", font)
	for i in player.skills.hotbar.size():
		var id: String = player.skills.hotbar[i]
		_slot(Vector2(x0 + i * (slot + 8), y0), slot, "skill_%d" % (i + 1), id, font)
	var extra: int = player.skills.hotbar.size()
	_slot(Vector2(x0 + extra * (slot + 8), y0), slot, "alt_skill", player.skills.right_click_skill, font)
	_slot(Vector2(x0 + (extra + 1) * (slot + 8), y0), slot, "dodge", "dodge", font)
	if picker_open():
		_draw_picker(font, size_px)
	else:
		_draw_tooltip(font, size_px)
	_draw_ability_toast(size_px, font)

	# Target bar, top centre: whatever the mouse is over, else what we are attacking.
	if not use_ds2_ui:
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

	# Small bars over every enemy that has been hurt (and stays hurt), and over the one the pointer is on.
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Actor
			if enemy == null or enemy.dead or (enemy.health >= enemy.max_health - 0.01 and enemy.bar_timer <= 0.0 and enemy != player.hover_target):
				continue
			var head: Vector3 = enemy.get_global_transform_interpolated().origin + Vector3(0, enemy.body_height + 0.25, 0)
			if camera.is_position_behind(head):
				continue
			var screen: Vector2 = camera.unproject_position(head)
			var bar_w: float = 44.0 + enemy.body_radius * 30.0
			var alpha: float = 1.0 if (enemy == player.hover_target or enemy.health < enemy.max_health - 0.01) else clampf(enemy.bar_timer, 0.0, 1.0)
			var pos := Vector2(screen.x - bar_w * 0.5, screen.y - 8.0)
			draw_rect(Rect2(pos, Vector2(bar_w, 6)), Color(0, 0, 0, 0.7 * alpha))
			draw_rect(Rect2(pos, Vector2(bar_w * clampf(enemy.health / enemy.max_health, 0.0, 1.0), 6)), Color(0.8, 0.15, 0.12, alpha))
			draw_rect(Rect2(pos, Vector2(bar_w, 6)), Color(1, 1, 1, 0.4 * alpha), false, 1.0)

		# Objectives that must be destroyed (the nests) always carry a bar, even before the first hit.
		for node in get_tree().get_nodes_in_group("nests"):
			var nest := node as Destructible
			if nest == null or nest.broken:
				continue
			var nest_head: Vector3 = nest.global_position + Vector3(0, nest.height + 0.3, 0)
			if camera.is_position_behind(nest_head):
				continue
			var nest_screen: Vector2 = camera.unproject_position(nest_head)
			var nest_w: float = 90.0
			var nest_pos := Vector2(nest_screen.x - nest_w * 0.5, nest_screen.y - 8.0)
			draw_rect(Rect2(nest_pos, Vector2(nest_w, 8)), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(nest_pos, Vector2(nest_w * clampf(nest.hp / nest.max_hp, 0.0, 1.0), 8)), Color(0.55, 0.8, 0.2))
			draw_rect(Rect2(nest_pos, Vector2(nest_w, 8)), Color(1, 1, 1, 0.45), false, 1.0)

	if banner_time > 0.0 and not banner_text.begins_with(CryptForecourtClimax.CLEAR_BANNER_TEXT):
		var fade: float = clampf(minf(banner_time, 0.8) / 0.8, 0.0, 1.0)
		var lines: PackedStringArray = banner_text.split("\n")
		var top: float = size_px.y * 0.28 - 56.0
		var band_h: float = 78.0 + 28.0 * (lines.size() - 1)
		draw_rect(Rect2(0, top, size_px.x, band_h), Color(0, 0, 0, 0.42 * fade))
		draw_rect(Rect2(size_px.x * 0.3, top + band_h - 2.0, size_px.x * 0.4, 2.0), Color(UiTheme.EMBER.r, UiTheme.EMBER.g, UiTheme.EMBER.b, 0.7 * fade))
		UiTheme.text(self, font, Vector2(0, size_px.y * 0.28), lines[0], 50, Color(1.0, 0.9, 0.7, fade), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
		for i in range(1, lines.size()):
			UiTheme.text(self, font, Vector2(0, size_px.y * 0.28 + 30.0 * i), lines[i], 22, Color(0.85, 0.78, 0.65, fade), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
	var has_title: bool = objective != "" or wave > 0
	if not use_ds2_ui or has_title:
		var panel_top: float = (212.0 if use_ds2_ui else 14.0) + top_offset
		var row_y: float = panel_top + (36.0 if has_title else 12.0)
		UiTheme.draw_panel(self, Rect2(14, panel_top, 250, 62 if has_title else 38), 0.7)
		if objective != "":
			UiTheme.text(self, font, Vector2(28, panel_top + 28.0), objective, 20, UiTheme.BRONZE_LIGHT.lightened(0.25))
		elif wave > 0:
			UiTheme.text(self, font, Vector2(28, panel_top + 28.0), "WAVE %d" % wave, 24, UiTheme.BRONZE_LIGHT.lightened(0.25))
		var kills_text: String = str(kills)
		var used: float = UiTheme.draw_stat(self, font, Vector2(28, row_y), "kills", kills_text, 24.0, 18)
		UiTheme.draw_stat(self, font, Vector2(28 + used + 22.0, row_y), "enemies", str(alive), 24.0, 18)
	_draw_item_card(size_px, font)
	if banner_time > 0.0 and banner_text.begins_with(CryptForecourtClimax.CLEAR_BANNER_TEXT):
		_draw_forecourt_banner(size_px, font)

	_draw_ranged_warnings(camera, size_px)

	if player.message_time > 0.0:
		if camera != null and not camera.is_position_behind(player.global_position):
			var anchor: Vector2 = camera.unproject_position(player.global_position + Vector3(0, player.body_height + 0.6, 0))
			var width: float = font.get_string_size(player.message, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			UiTheme.text(self, font, anchor - Vector2(width * 0.5, 0), player.message, 18, Color(1, 0.85, 0.5, minf(player.message_time, 1.0)))
	if player.dead:
		draw_rect(Rect2(Vector2.ZERO, size_px), Color(0, 0, 0, 0.4 if world_mode else 0.55))   # the world's drag-back banner sits over this: keep it readable
		UiTheme.text(self, font, Vector2(0, size_px.y * 0.45), "YOU DIED", 64, Color(0.72, 0.12, 0.1), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
		UiTheme.text(self, font, Vector2(0, size_px.y * 0.45 + 44), death_subline(), 22, Color(0.9, 0.86, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
		var detail: String = death_detail()
		if detail != "":
			UiTheme.text(self, font, Vector2(0, size_px.y * 0.45 + 76), detail, 17, Color(0.72, 0.68, 0.6), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)

## Offscreen ranged warning: while a spitter is in its wind-up and out of the camera view, a sickly-green chevron on the screen edge points
## toward it, pulsing like the on-model "spit" telegraph. Display only; it never touches timing or damage.
const RANGED_WARN_MARGIN := 34.0

## [{pos: Vector2 (edge point), dir: Vector2 (toward the enemy), enemy}] for every winding-up spitter that is off the screen.
func ranged_warnings(camera: Camera3D, size_px: Vector2) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if camera == null:
		return found
	var centre: Vector2 = size_px * 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.dead or not (enemy.behavior is SpitterBehavior) or not (enemy.behavior as SpitterBehavior).is_winding_up():
			continue
		var at: Vector3 = enemy.global_position + Vector3(0, enemy.body_height * 0.5, 0)
		var behind: bool = camera.is_position_behind(at)
		var screen: Vector2 = camera.unproject_position(at)
		if not behind and Rect2(Vector2.ZERO, size_px).has_point(screen):
			continue   # on screen: its own telegraph is visible
		var dir: Vector2 = screen - centre
		if behind:
			dir = -dir
		if dir.length() < 0.001:
			dir = Vector2.DOWN
		dir = dir.normalized()
		var half: Vector2 = centre - Vector2.ONE * RANGED_WARN_MARGIN
		var k: float = minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
		found.append({"pos": _clear_of_hud(centre + dir * k, size_px), "dir": dir, "enemy": enemy})
	return found

## Permanent HUD controls the offscreen chevron must not sit on: hotbar tray, both vessels, minimap.
func ranged_warn_keepouts(size_px: Vector2) -> Array[Rect2]:
	var pad: float = 22.0   # chevron half-size plus a breath
	return [hotbar_rect(size_px).grow(pad), orb_rect(size_px, false).grow(pad), orb_rect(size_px, true).grow(pad), minimap_rect(size_px, use_ds2_ui).grow(7.0 + pad)]

## Slides an edge point the shortest way out of any keep-out rect (staying on screen and out of the others), so a spitter straight behind the
## camera warns just above the hotbar instead of over slot 5. Only the marker's position moves; its direction still points at the enemy.
func _clear_of_hud(point: Vector2, size_px: Vector2) -> Vector2:
	var rects: Array[Rect2] = ranged_warn_keepouts(size_px)
	var screen_rect: Rect2 = Rect2(Vector2.ZERO, size_px).grow(-RANGED_WARN_MARGIN)
	for _pass in 4:
		var hit: int = -1
		for i in rects.size():
			if rects[i].has_point(point):
				hit = i
				break
		if hit < 0:
			return point
		var r: Rect2 = rects[hit]
		var best: Vector2 = point
		var best_d: float = INF
		for cand in [Vector2(point.x, r.position.y - 1.0), Vector2(point.x, r.end.y + 1.0), Vector2(r.position.x - 1.0, point.y), Vector2(r.end.x + 1.0, point.y)]:
			if not screen_rect.grow(1.0).has_point(cand):
				continue
			var blocked: bool = false
			for other in rects:
				if other != r and other.has_point(cand):
					blocked = true
					break
			if not blocked and cand.distance_to(point) < best_d:
				best = cand
				best_d = cand.distance_to(point)
		if best_d == INF:
			return point
		point = best
	return point

func _draw_ranged_warnings(camera: Camera3D, size_px: Vector2) -> void:
	if player.dead:
		return
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * 14.0)
	var tint: Color = Enemy.TELEGRAPH_LOOKS["spit"][0]
	for w in ranged_warnings(camera, size_px):
		var pos: Vector2 = w["pos"]
		var dir: Vector2 = w["dir"]
		var side := Vector2(-dir.y, dir.x)
		var tip: Vector2 = pos + dir * 16.0
		var tri := PackedVector2Array([tip, pos - dir * 8.0 + side * 15.0, pos - dir * 8.0 - side * 15.0])
		draw_colored_polygon(tri, Color(0.04, 0.05, 0.02, 0.55))
		draw_colored_polygon(tri, Color(tint.r, tint.g, tint.b, 0.45 + 0.4 * pulse))

## What the death plate says under "YOU DIED": the world drags the hero home (nothing to press), a job returns to town, the arena asks for the
## restart control as it is bound right now (the pad's button while a controller is the active device).
func death_subline() -> String:
	if world_mode:
		return "Dragged back to town..."
	if not TownState.job.is_empty():
		return "Returning to town..."
	var key: String = Gamepad.label_for("restart") if Gamepad.active else GameSettings.binding_text("restart")
	if key == "" or key == "Unbound" or key == "-":
		key = GameSettings.binding_text("restart") if Gamepad.active else Gamepad.label_for("restart")
	if key == "" or key == "Unbound" or key == "-":
		return "Restart from the pause menu"
	return "Press %s to restart" % key

## What the hero keeps, under the death plate (world only; nothing is lost on a death there): gear, items and XP stay with him, he is
## revived whole at the Last Hearth, and the road and whatever killed him are still out there (a killer may be remembered as a nemesis).
func death_detail() -> String:
	if world_mode:
		return "Gear, items and XP are kept. The road stays as you left it, and what killed you remembers."
	return ""

## True when a screen point is over a HUD panel (minimap, hotbar, resource vessels): the world behind it must not react to the mouse.
func covers(point: Vector2) -> bool:
	var size_px: Vector2 = get_viewport_rect().size
	if picker_open() and picker_panel(size_px).grow(6.0).has_point(point):
		return true
	if show_gear and character_panel != null and character_panel.get_global_rect().has_point(point):
		return true
	if minimap_rect(size_px, use_ds2_ui).grow(7).has_point(point) or minimap_rect(size_px, false).grow(7).has_point(point):
		return true
	if progression_hud != null and progression_hud.chip_rect(size_px).grow(4.0).has_point(point):
		return true   # the points chip is a button: a click on it must not also walk the hero
	if progression_hud != null and progression_hud.strip_rect(size_px).grow(22.0).has_point(point):
		return true   # the XP bar and its badge along the bottom
	if orb_rect(size_px, false).has_point(point) or orb_rect(size_px, true).has_point(point):
		return true
	if use_ds2_ui and point.y >= size_px.y - (hotbar_slot_size(size_px) + 28.0):
		return true
	return hotbar_rect(size_px).has_point(point)

## The hotbar tray's screen rectangle.
func hotbar_rect(size_px: Vector2) -> Rect2:
	var slot: float = hotbar_slot_size(size_px)
	var count: int = (player.skills.hotbar.size() + 2) if player != null else 8
	var total: float = slot * count + 8.0 * (count - 1)
	if use_ds2_ui:
		var bar_height: float = slot + 28.0
		return Rect2(Vector2((size_px.x - total) * 0.5 - 16.0, size_px.y - bar_height), Vector2(total + 32.0, bar_height))
	return Rect2(Vector2((size_px.x - total) * 0.5 - 24, size_px.y - slot - 46 - HOTBAR_LIFT), Vector2(total + 48, slot + 44))

static func orb_rect(screen: Vector2, right: bool) -> Rect2:
	var diameter: float = clampf(screen.x * 0.17, 160.0, 220.0)
	var inset: float = diameter * 0.50   # the bust stands outside the vessel, at the screen edge
	return Rect2(Vector2(screen.x - diameter - inset if right else inset, screen.y - diameter - 6), Vector2.ONE * diameter)

static func minimap_rect(screen: Vector2, ds2: bool = false) -> Rect2:
	if ds2:
		var size_map: float = 160.0
		return Rect2(Vector2(screen.x - size_map - 18.0, screen.y - size_map - 12.0), Vector2(size_map, size_map))
	return Rect2(Vector2(screen.x - 246, 30), Vector2(214, 214))

func hotbar_slot_size(screen: Vector2) -> float:
	var count: int = (player.skills.hotbar.size() + 2) if player != null else 8
	var available: float = screen.x - orb_rect(screen, false).end.x * 2.0 - 52.0
	return clampf((available - 8.0 * (count - 1)) / count, 36.0, 64.0)

## "New ability learned": a plate low on the left, above the health vessel, with the skill's icon, its name and what it does. Call this when the
## hero gains a skill (nothing in the game unlocks skills yet; `--abilitytoast=ID` shows one for a look).
const ABILITY_TOAST_SECONDS := 6.0
var ability_toast_id: String = ""
var ability_toast_time: float = 0.0

func show_ability_toast(skill_id: String) -> void:
	if not SkillDb.all().has(skill_id):
		return
	ability_toast_id = skill_id
	ability_toast_time = ABILITY_TOAST_SECONDS

func _draw_ability_toast(size_px: Vector2, font: Font) -> void:
	if ability_toast_time <= 0.0 or ability_toast_id == "" or player.dead:
		return
	ability_toast_time = maxf(ability_toast_time - get_process_delta_time(), 0.0)
	var age: float = ABILITY_TOAST_SECONDS - ability_toast_time
	var fade: float = clampf(minf(age / 0.25, ability_toast_time / 0.8), 0.0, 1.0)
	var skill: Dictionary = SkillDb.all()[ability_toast_id]
	var orb: Rect2 = orb_rect(size_px, false)
	var panel := Rect2(Vector2(24.0, orb.position.y - 138.0), Vector2(430.0, 122.0))
	UiTheme.draw_panel(self, panel, 0.9 * fade, false)
	var icon_rect := Rect2(panel.position + Vector2(16.0, 18.0), Vector2(86.0, 86.0))
	draw_rect(icon_rect, Color(UiTheme.INK, fade))
	var icon: Texture2D = _icon(ability_toast_id)
	if icon != null:
		draw_texture_rect(icon, icon_rect.grow(-3.0), false, Color(1, 1, 1, fade))
	draw_texture_rect(bezel, icon_rect.grow(4.0), false, Color(METAL_WARMTH.r, METAL_WARMTH.g, METAL_WARMTH.b, fade))
	var heading: Font = UiTheme.heading_font()
	var tx: float = icon_rect.end.x + 20.0
	UiTheme.text(self, heading, Vector2(tx, panel.position.y + 30.0), "NEW ABILITY LEARNED", 13, Color(UiTheme.BRONZE_LIGHT, fade))
	UiTheme.text(self, heading, Vector2(tx, panel.position.y + 62.0), String(skill["name"]).to_upper(), 26, Color(UiTheme.TEXT, fade))
	var description: String = SkillDb.description(ability_toast_id).split(". ")[0].split(" (")[0]   # the first clause: a plate, not the whole tooltip
	if not description.ends_with("."):
		description += "."
	draw_multiline_string(font, Vector2(tx, panel.position.y + 84.0), description, HORIZONTAL_ALIGNMENT_LEFT, panel.end.x - tx - 14.0, 15, 2, Color(0.82, 0.8, 0.74, fade))

## Fog of war: is this monster close enough to the hero to be seen (and so shown on the map)?
func enemy_in_sight(enemy: Actor) -> bool:
	if player == null:
		return false
	var gap := Vector2(enemy.global_position.x - player.global_position.x, enemy.global_position.z - player.global_position.z)
	return gap.length() <= MinimapMap.SIGHT

## Whole-arena minimap, upper right. It turns with the camera, so whatever is up the screen is up on the map.
func _draw_minimap(t: CanvasItem, size_px: Vector2, font: Font) -> void:
	var rect: Rect2 = minimap_rect(size_px, use_ds2_ui)
	# A long, narrow arena (the Crypt Road) would be a thin strip, so its map shows a window round the hero instead of the whole place.
	var params: Dictionary = map_view_params(size_px)
	var windowed: bool = bool(params["windowed"])
	var half: float = float(params["half"])
	var origin: Vector3 = params["origin"]
	var scale_px: float = float(params["scale"])
	var centre: Vector2 = rect.get_center()
	# (The panel, the backdrop, the ground, the road, the solid props and the fog are the two layers drawn behind this item: see MinimapMap.)
	# Corrupted nests (the job's targets): a sickly green ring, always shown, pinned to the edge of the map when out of the window.
	for node in get_tree().get_nodes_in_group("nests"):
		var nest := node as Destructible
		if nest == null or nest.broken:
			continue
		var nrel: Vector3 = nest.global_position - origin
		var nat: Vector2 = centre + Vector2(nrel.x, nrel.z).limit_length(half).rotated(Gamepad.view_yaw) * scale_px
		t.draw_circle(nat, 6.0, Color(0, 0, 0, 0.8))
		t.draw_arc(nat, 4.2, 0.0, TAU, 16, Color(0.55, 0.8, 0.2), 2.0)
	# Enemies: red dots, larger orange for bosses. (No count: how many are left is not the player's business.)
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Actor
		if enemy == null or enemy.dead:
			continue
		var p: Vector3 = enemy.global_position - origin
		if windowed and (Vector2(p.x, p.z).length() > half) and not (enemy.has_meta("monster_uid") or enemy.has_meta("quest_uid")):
			continue   # (a named monster is pinned to the edge of the map instead, so it can be found)
		if not (enemy.has_meta("monster_uid") or enemy.has_meta("quest_uid")) and not enemy_in_sight(enemy):
			continue   # fog of war: a monster is shown only while it is near enough to be seen
		var rel: Vector2 = Vector2(p.x, p.z).rotated(Gamepad.view_yaw)
		var at: Vector2 = centre + Vector2(rel.x, rel.y).limit_length(half) * scale_px
		if enemy.has_meta("monster_uid") or enemy.has_meta("quest_uid"):   # a named monster: a diamond (red for a nemesis), not a dot
			var named: Color = Color(1.0, 0.75, 0.3) if enemy.has_meta("quest_uid") else Color(1.0, 0.5, 0.18)
			if enemy.has_meta("monster_uid") and bool(Monsters.find(int(enemy.get_meta("monster_uid"))).get("nemesis", false)):
				named = Color(0.95, 0.2, 0.14)
			t.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0)]), Color(0, 0, 0, 0.9))
			t.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 0), at + Vector2(0, 6), at + Vector2(-6, 0)]), named)
		elif enemy.is_boss or enemy.max_health >= 150.0:
			t.draw_circle(at, 5.0, Color(0, 0, 0, 0.8))
			t.draw_circle(at, 3.8, Color(1.0, 0.55, 0.12))
		else:
			t.draw_circle(at, 3.0, Color(0, 0, 0, 0.7))
			t.draw_circle(at, 2.2, Color(0.95, 0.15, 0.12))
	# Items on the ground: a diamond in the rarity colour (bigger for rares and uniques), so they can be found from the map too.
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null:
			continue
		var lp: Vector3 = drop.global_position - origin
		if windowed and (Vector2(lp.x, lp.z).length() > half):
			continue
		if not map_data.is_explored(drop.global_position):
			continue   # fog of war: only where the hero has been
		var lrel: Vector2 = Vector2(lp.x, lp.z).rotated(Gamepad.view_yaw)
		var lat: Vector2 = centre + Vector2(lrel.x, lrel.y).limit_length(half) * scale_px
		var rarity: int = int(drop.item["rarity"])
		var r: float = 3.0 + 1.5 * rarity
		var tint: Color = Items.RARITY_COLORS[rarity] if rarity > 0 else Color(0.78, 0.76, 0.7)
		t.draw_colored_polygon(PackedVector2Array([lat + Vector2(0, -r - 1), lat + Vector2(r + 1, 0), lat + Vector2(0, r + 1), lat + Vector2(-r - 1, 0)]), Color(0, 0, 0, 0.85))
		t.draw_colored_polygon(PackedVector2Array([lat + Vector2(0, -r), lat + Vector2(r, 0), lat + Vector2(0, r), lat + Vector2(-r, 0)]), tint)
	# What a monster's plot has put up (altar, war banner, bones), a violet triangle; a quest item lying on the road, a small gold ring.
	for node in get_tree().get_nodes_in_group("plot_signs"):
		if not map_data.is_explored((node as Node3D).global_position):
			continue
		var sp: Vector3 = (node as Node3D).global_position - origin
		var srel: Vector2 = Vector2(sp.x, sp.z).rotated(Gamepad.view_yaw)
		var sat: Vector2 = centre + Vector2(srel.x, srel.y).limit_length(half) * scale_px
		t.draw_colored_polygon(PackedVector2Array([sat + Vector2(0, -9), sat + Vector2(8, 6), sat + Vector2(-8, 6)]), Color(0, 0, 0, 0.9))
		t.draw_colored_polygon(PackedVector2Array([sat + Vector2(0, -6.5), sat + Vector2(5.5, 4.5), sat + Vector2(-5.5, 4.5)]), Color(0.75, 0.4, 0.9))
	for node in get_tree().get_nodes_in_group("quest_pickups"):
		if not map_data.is_explored((node as Node3D).global_position):
			continue
		var qp: Vector3 = (node as Node3D).global_position - origin
		var qrel: Vector2 = Vector2(qp.x, qp.z).rotated(Gamepad.view_yaw)
		var qat: Vector2 = centre + Vector2(qrel.x, qrel.y).limit_length(half) * scale_px
		t.draw_circle(qat, 5.5, Color(0, 0, 0, 0.85))
		t.draw_arc(qat, 4.0, 0.0, TAU, 14, Color(1.0, 0.8, 0.3), 2.0)
	# The hero: a white arrow pointing the way they face.
	var pp: Vector3 = player.global_position - origin
	var me: Vector2 = centre + Vector2(pp.x, pp.z).rotated(Gamepad.view_yaw) * scale_px
	var yaw: float = player.visual.rotation.y if player.visual != null else 0.0
	var fwd: Vector2 = Vector2(sin(yaw), cos(yaw)).rotated(Gamepad.view_yaw)
	var side_v := Vector2(-fwd.y, fwd.x)
	t.draw_colored_polygon(PackedVector2Array([me + fwd * 7.0, me - fwd * 4.0 + side_v * 4.5, me - fwd * 2.0, me - fwd * 4.0 - side_v * 4.5]),
		Color(1, 1, 1))

## The item under the mouse (or, with a controller, the nearest one within reach): what it is, what it does, and how it compares with
## what is worn in that slot, with a note on whether walking over it will put it on or send it to the bag.
func _draw_item_card(size_px: Vector2, font: Font) -> void:
	_ground_card_rect = Rect2()
	if player != null and player.dead:   # the death plate owns the screen: no loot name plates or item card showing through it
		_loot_names = []
		LootDrop.focused = null
		return
	_loot_names = _layout_loot_names(font)
	_draw_loot_names(font)
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
	var return_prompt := _return_prompt_rect() if for_drop else Rect2()
	if return_prompt.has_area():
		var layout := _return_card_layout(item, lines, compare, anchor, size_px, return_prompt, font, with_compare)
		if layout.is_empty():
			push_warning("No clear return-card space in viewport")
			return
		_ground_card_rect = layout.rect
		draw_set_transform(layout.rect.position, 0.0, Vector2.ONE * float(layout.scale))
		_draw_return_card_body(item, worn, lines, compare, layout.metrics, color, font, with_compare)
		draw_set_transform(Vector2.ZERO)
		return
	if for_drop:
		_ground_card_rect = Rect2(pos, Vector2(width, height))
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

## Restrict clearance to the active return-waystone decision; other cards retain their layout.
func _return_prompt_rect() -> Rect2:
	var node := get_parent()
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
	UiTheme.draw_panel(self, Rect2(Vector2.ZERO, Vector2(width, height)), 0.97)
	draw_rect(Rect2(Vector2(3, 3), Vector2(4, height - 6)), color)   # a rarity-coloured spine
	draw_multiline_string(font, Vector2(pad + 6.0, pad + 18.0), String(item["name"]), HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0, 21, -1, color)
	UiTheme.text(self, font, Vector2(pad + 6.0, m.kind_y), "%s %s" % [Items.RARITY_NAMES[int(item["rarity"])], Items.SLOT_NAMES[int(item["slot"])]], 13, Color(1, 1, 1, 0.55))
	for i in lines.size():
		draw_multiline_string(font, Vector2(pad + 6.0, m.line_ys[i]), lines[i], HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0, 14, -1, Color(0.9, 0.88, 0.82))
	if with_compare:
		draw_line(Vector2(pad, m.rule_y), Vector2(width - pad, m.rule_y), Color(1, 1, 1, 0.12), 1.0)
		UiTheme.text(self, font, Vector2(pad + 6.0, m.header_y), "Compared with %s" % (String((worn as Dictionary)["name"]) if worn != null else "your gear"), 13,
			Color(0.7, 0.68, 0.62), HORIZONTAL_ALIGNMENT_LEFT, inner - 6.0)
		var per_col: int = ceili(float(compare.size()) / float(m.cols))
		for i in compare.size():
			var entry: Dictionary = compare[i]
			var sign_color: Color = Color(0.5, 0.85, 0.5) if int(entry["sign"]) > 0 else (Color(0.9, 0.45, 0.4) if int(entry["sign"]) < 0 else Color(0.75, 0.75, 0.75))
			var mark: String = "+ " if int(entry["sign"]) > 0 else ("- " if int(entry["sign"]) < 0 else "= ")
			UiTheme.text(self, font, Vector2(pad + 6.0 + float(i / per_col) * inner * 0.5, float(m.rows_y) + 18.0 * float(i % per_col)), mark + String(entry["text"]), 14, sign_color)
	var upgrade: bool = player.stats.takes_empty_slot(item)
	UiTheme.text(self, font, Vector2(pad + 6.0, m.drop_y), "Walk over it: you will wear it (empty slot)" if upgrade else "Walk over it: it goes in the bag", 14,
		Color(0.95, 0.8, 0.5) if upgrade else Color(0.7, 0.68, 0.62))

## Find empty rectangles from actual obstacle edges, then fit the complete card into them.
## Prefer full-size typography, widening wrapped content before uniformly scaling it.
## No unsafe original-anchor fallback: every result is bounded and unobstructed.
func _return_card_layout(item: Dictionary, lines: Array[String], compare: Array[Dictionary], anchor: Vector2, screen: Vector2, prompt: Rect2, font: Font, with_compare: bool) -> Dictionary:
	var obstacles: Array[Rect2] = [prompt.grow(6.0), minimap_rect(screen, use_ds2_ui).grow(7.0), orb_rect(screen, false).grow(7.0), orb_rect(screen, true).grow(7.0)]
	obstacles.append(Rect2(14, 14 + top_offset, 250, 62 if objective != "" or wave > 0 else 38).grow(6.0))
	var node := get_parent()
	while node != null:
		if node is TownScene:
			for overlay in (node as TownScene).hud.overlay_rects:
				obstacles.append(overlay.grow(6.0))
			break
		node = node.get_parent()
	for entry in _loot_names:
		obstacles.append((entry["rect"] as Rect2).grow(6.0))
	obstacles.append(hotbar_rect(screen).grow(6.0))
	if progression_hud != null:
		obstacles.append(progression_hud.strip_rect(screen).grow(6.0))
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
	for entry in _loot_names:   # a name plate under the pointer is the item
		if (entry["rect"] as Rect2).has_point(mouse):
			return entry["drop"]
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null or not drop.landed or camera.is_position_behind(drop.global_position):
			continue
		var d: float = minf(camera.unproject_position(drop.global_position + Vector3(0, 1.5, 0)).distance_to(mouse), camera.unproject_position(drop.global_position + Vector3(0, 0.5, 0)).distance_to(mouse))
		if d < 56.0 and d < best_d:
			best_d = d
			best = drop
	return best

func mouse_over_hud(point: Vector2) -> bool:
	return covers(point)

func _draw_ds2_runner_bar(size_px: Vector2, x0: float, _y0: float, total: float, _slot: float, bar_height: float) -> void:
	var bar_y: float = size_px.y - bar_height

	# 1. Full-width dark stone runner bar across the ENTIRE bottom of the screen
	var bar_rect := Rect2(0, bar_y, size_px.x, bar_height)
	draw_rect(bar_rect, Color(0.11, 0.10, 0.09, 0.98))

	# Top beveled edge highlight
	draw_line(Vector2(0, bar_y), Vector2(size_px.x, bar_y), Color(0.44, 0.40, 0.32, 0.95), 2.0)
	# Subtle inner shadow groove
	draw_line(Vector2(0, bar_y + 2.0), Vector2(size_px.x, bar_y + 2.0), Color(0.06, 0.05, 0.04, 0.9), 1.0)

	# 2. Recessed action slot bay inside the stone console
	var bay_rect := Rect2(x0 - 12.0, bar_y + 3.0, total + 24.0, bar_height - 5.0)
	draw_rect(bay_rect, Color(0.07, 0.06, 0.05, 0.95))
	draw_rect(bay_rect, Color(0.28, 0.25, 0.20, 0.8), false, 1.0)

	# Bronze corner studs on the bay
	for corner in [bay_rect.position + Vector2(3, 3), Vector2(bay_rect.end.x - 3, bay_rect.position.y + 3), Vector2(bay_rect.position.x + 3, bay_rect.end.y - 3), bay_rect.end - Vector2(3, 3)]:
		draw_circle(corner, 2.5, Color(0.05, 0.04, 0.03, 0.9))
		draw_circle(corner, 1.8, Color(0.72, 0.58, 0.34, 0.9))

	# 3. Decorative central medallion at the top lip of the runner bar
	var mid_x: float = x0 + total * 0.5
	var medal_pos := Vector2(mid_x, bar_y + 1.0)
	draw_circle(medal_pos + Vector2(0, 1), 12.0, Color(0.05, 0.04, 0.03, 0.85))
	draw_circle(medal_pos, 11.0, Color(0.14, 0.12, 0.10))
	draw_arc(medal_pos, 10.5, 0.0, TAU, 28, Color(0.80, 0.64, 0.38, 0.95), 1.5)
	draw_arc(medal_pos, 7.0, 0.0, TAU, 20, Color(0.55, 0.42, 0.24, 0.8), 1.0)
	draw_circle(medal_pos, 3.5, Color(0.88, 0.70, 0.40, 0.95))

func _bar(pos: Vector2, size_px: Vector2, fraction: float, color: Color, label: String, font: Font) -> void:
	UiTheme.draw_bar(self, Rect2(pos, size_px), fraction, color, label, font)

## One hotbar slot: icon, radial cooldown sweep with seconds left, mana-cost tint, ready flash, bound key.
func _slot(pos: Vector2, size_px: float, action: String, id: String, font: Font) -> void:
	var rect := Rect2(pos, Vector2(size_px, size_px))
	draw_rect(rect, UiTheme.INK)
	_slot_hits.append({"rect": rect, "id": id, "action": action})
	if id == "":
		draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.9), false, 2.0)
		draw_rect(rect, Color(0.3, 0.28, 0.28, 0.8), false, 2.0)
		draw_texture_rect(bezel, rect.grow(3.0), false, Color(0.42, 0.38, 0.36))
		UiTheme.text(self, UiTheme.heading_font(), pos + Vector2(0, (size_px + 13.0) if use_ds2_ui else (size_px + 17.0)), GameSettings.short_binding_text(action), 12 if use_ds2_ui else 13,
			Color(0.78, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER, size_px)
		return
	var skill: Dictionary = SkillDb.all()[id]
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
	# Weapon Throw with the weapon out is the recall key: available whatever the throw cooldown says, so it is not dimmed or swept.
	var recall: bool = id == WeaponThrowSkill.SKILL_ID and player.weapon_throw.is_away()
	if recall:
		remaining = 0.0
		fraction = 0.0
	var affordable: bool = player.stats.mana >= float(skill["mana"])
	if not affordable:
		draw_rect(rect, Color(0.12, 0.2, 0.42, 0.5))

	# An ultimate has no cooldown: it fills from the bottom as damage is dealt and glows when it is ready to use.
	var ult_cost: float = player.stats.ult_cost(id)
	var ult_filling: bool = ult_cost > 0.0 and player.stats.ult_fraction(id) < 1.0
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
	var active_bezel: Texture2D = bezel
	if use_ds2_ui:
		active_bezel = ds2_power_bezel if ult_cost > 0.0 else ds2_action_bezel
	draw_texture_rect(active_bezel, rect.grow(3.0), false, METAL_WARMTH if remaining <= 0.0 and affordable else Color(0.60, 0.52, 0.46))
	if recall:   # a pulsing ember edge and a small curved arrow: it comes back
		var beat: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		draw_rect(rect.grow(2.0 + 1.5 * beat), Color(0.95, 0.6, 0.25, 0.3 + 0.3 * beat), false, 2.5)
		var arrow: Vector2 = pos + Vector2(size_px - 16.0, size_px - 16.0)
		draw_arc(arrow, 7.0, PI * 0.15, PI * 1.65, 14, Color(0, 0, 0, 0.8), 4.5)
		draw_arc(arrow, 7.0, PI * 0.15, PI * 1.65, 14, Color(1.0, 0.86, 0.5), 2.5)
		var head: Vector2 = arrow + Vector2(cos(PI * 0.15), sin(PI * 0.15)) * 7.0
		draw_colored_polygon(PackedVector2Array([head + Vector2(-5, -3), head + Vector2(4, -3), head + Vector2(0, 5)]), Color(1.0, 0.86, 0.5))
	# Key hint (follows rebinding), potion count and mana cost.
	var key_text: String = GameSettings.short_binding_text(action)
	# (The key sits UNDER the slot, engraved, as on the reference; the old top-left corner hint is gone.)
	UiTheme.text(self, UiTheme.heading_font(), pos + Vector2(0, (size_px + 13.0) if use_ds2_ui else (size_px + 17.0)), key_text, 12 if use_ds2_ui else 13, Color(0.78, 0.72, 0.6), HORIZONTAL_ALIGNMENT_CENTER, size_px)
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
		if id == "":
			continue
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
		if id == "dodge" and PlayerStats.STAMINA_ON:
			stats.append("Stamina %d" % int(round(PlayerMovement.ROLL_STAMINA * player.stats.armor_stat("roll_cost", 1.0))))
		var stat_line: String = "    ".join(stats)
		var damage_line: String = player.stats.skill_damage_text(id)
		var desc: String = SkillDb.description(id)
		if slot_of_action(String(hit["action"])) != HotbarLayout.NONE:
			desc += "\n\nClick to change what is on this key."
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
var _loot_names: Array[Dictionary] = []   # [{drop, rect, anchor}] this frame's name plates over the items on the ground
var _ground_card_rect := Rect2()   # actual drawn ground card, for focused layout regression checks

# --- Names over loot ------------------------------------------------------------------------------------------------------------
## Every item on the ground shows its name over it, in its rarity's colour. The plates are laid out on the screen so that they never
## overlap: they are placed from the bottom of the screen (nearest the camera) up, and any plate that would land on another is lifted
## above it, with a thin line back to its item. They are also what you click or point at to pick an item up.

const NAME_HEIGHT := 21.0
const NAME_FONT := 15

func _layout_loot_names(font: Font) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or show_gear or player == null:
		return out
	var entries: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("loot"):
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
		if covers(rect.get_center()) or covers(rect.position) or covers(rect.end):
			continue   # it would sit under the hotbar, the minimap or an open panel: left out, not drawn over them
		placed.append(rect)
		out.append({"drop": entry["drop"], "rect": rect, "anchor": anchor})
	return out

func _draw_loot_names(font: Font) -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position() if mouse_override.x < 0.0 else mouse_override
	for entry in _loot_names:
		var drop: LootDrop = entry["drop"]
		var rect: Rect2 = entry["rect"]
		var anchor: Vector2 = entry["anchor"]
		var colour: Color = Items.RARITY_COLORS[int(drop.item["rarity"])]
		var focus: bool = LootDrop.focused == drop or rect.has_point(mouse)
		if rect.end.y < anchor.y - 12.0:   # lifted off its item: a line shows whose name it is
			draw_line(Vector2(rect.get_center().x, rect.end.y), anchor, Color(colour.r, colour.g, colour.b, 0.55), 1.0)
		draw_rect(rect, Color(0.03, 0.03, 0.04, 0.82 if focus else 0.62))
		draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.95 if focus else 0.45), false, 1.5 if focus else 1.0)
		UiTheme.text(self, font, rect.position + Vector2(0, 15.5), String(drop.item["name"]), NAME_FONT, colour.lightened(0.2 if focus else 0.0),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


# --- The skill picker --------------------------------------------------------------------------------------------------------
# Click a hotbar slot (the numbered ones or the right mouse button) and every skill appears above it as an icon; click one and it goes
# on that key. A skill that was on another key trades places with what was here, so nothing is ever lost. See HotbarLayout.

var picker_slot: int = HotbarLayout.NONE   # the slot it is open for (HotbarLayout.NONE: closed)
var _picker_anchor: Rect2 = Rect2()
const PICKER_CELL := 62.0
const PICKER_GAP := 8.0
const PICKER_PAD := 12.0

func picker_open() -> bool:
	return picker_slot != HotbarLayout.NONE

func open_picker(slot: int, anchor: Rect2) -> void:
	picker_slot = slot
	_picker_anchor = anchor

func close_picker() -> void:
	picker_slot = HotbarLayout.NONE

## The slot number a hotbar slot's action stands for: 0.. for skill_1.., HotbarLayout.ALT for the mouse button, NONE for the dodge.
static func slot_of_action(action: String) -> int:
	if action == "alt_skill":
		return HotbarLayout.ALT
	if action.begins_with("skill_"):
		return int(action.substr(6)) - 1
	return HotbarLayout.NONE

## The change-able hotbar slot under a point, as {slot, rect}; {} when there is none.
func slot_at(point: Vector2) -> Dictionary:
	for hit in _slot_hits:
		var rect: Rect2 = hit["rect"]
		var slot: int = slot_of_action(String(hit["action"]))
		if slot != HotbarLayout.NONE and rect.has_point(point):
			return {"slot": slot, "rect": rect}
	return {}

func picker_panel(size_px: Vector2) -> Rect2:
	var count: int = HotbarLayout.ASSIGNABLE.size()
	var width: float = PICKER_PAD * 2.0 + PICKER_CELL * count + PICKER_GAP * (count - 1)
	var height: float = PICKER_PAD * 2.0 + PICKER_CELL + 30.0
	var x: float = clampf(_picker_anchor.get_center().x - width * 0.5, 8.0, maxf(size_px.x - width - 8.0, 8.0))
	return Rect2(x, _picker_anchor.position.y - height - 16.0, width, height)

## Every skill's icon cell in the open picker: [{rect, id}].
func picker_cells(size_px: Vector2) -> Array[Dictionary]:
	var panel: Rect2 = picker_panel(size_px)
	var cells: Array[Dictionary] = []
	for i in HotbarLayout.ASSIGNABLE.size():
		cells.append({"rect": Rect2(panel.position + Vector2(PICKER_PAD + i * (PICKER_CELL + PICKER_GAP), PICKER_PAD + 26.0), Vector2.ONE * PICKER_CELL),
			"id": HotbarLayout.ASSIGNABLE[i]})
	return cells

## A left click on a hotbar slot opens the picker; with it open, a click on a skill chooses it, on another slot moves the picker there,
## anywhere else (or the right button) closes it. Returns true when the click was used.
func _picker_click(click: InputEventMouseButton) -> bool:
	var size_px: Vector2 = get_viewport_rect().size
	if picker_open():
		if click.button_index != MOUSE_BUTTON_LEFT:
			close_picker()
			return true
		for cell in picker_cells(size_px):
			if (cell["rect"] as Rect2).has_point(click.position):
				player.skills.assign_slot(picker_slot, String(cell["id"]))
				close_picker()
				return true
		var other: Dictionary = slot_at(click.position)
		if not other.is_empty() and int(other["slot"]) != picker_slot:
			open_picker(int(other["slot"]), other["rect"])
		else:
			close_picker()
		return true
	if click.button_index == MOUSE_BUTTON_LEFT:
		var hit: Dictionary = slot_at(click.position)
		if not hit.is_empty():
			open_picker(int(hit["slot"]), hit["rect"])
			return true
	return false

func _draw_picker(font: Font, size_px: Vector2) -> void:
	var panel: Rect2 = picker_panel(size_px)
	var mouse: Vector2 = get_viewport().get_mouse_position() if mouse_override.x < 0.0 else mouse_override
	UiTheme.draw_panel(self, panel, 0.95)
	var here: String = HotbarLayout.skill_at(player.skills.hotbar, player.skills.right_click_skill, picker_slot)
	var title: String = "Put on %s" % (GameSettings.short_binding_text("alt_skill") if picker_slot == HotbarLayout.ALT else GameSettings.short_binding_text("skill_%d" % (picker_slot + 1)))
	var hovered_id: String = ""
	for cell in picker_cells(size_px):
		if (cell["rect"] as Rect2).has_point(mouse):
			hovered_id = String(cell["id"])
	UiTheme.text(self, font, panel.position + Vector2(PICKER_PAD, 24.0), title, 16, UiTheme.BRONZE_LIGHT.lightened(0.25))
	if hovered_id != "":
		UiTheme.text(self, font, panel.position + Vector2(panel.size.x - PICKER_PAD, 24.0), String(SkillDb.all()[hovered_id]["name"]), 16, UiTheme.TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x * 0.6)
	for cell in picker_cells(size_px):
		var rect: Rect2 = cell["rect"]
		var id: String = cell["id"]
		draw_rect(rect, UiTheme.INK)
		var icon: Texture2D = _icon(id)
		if icon != null:
			draw_texture_rect(icon, rect.grow(-3.0), false)
		else:
			draw_string(font, rect.position + Vector2(2, PICKER_CELL * 0.5 + 4), String(SkillDb.all()[id]["name"]), HORIZONTAL_ALIGNMENT_CENTER, PICKER_CELL - 4, 11, Color(1, 1, 1))
		var border: Color = Color(0.32, 0.30, 0.26)
		if id == here:
			border = UiTheme.ACCENT
		elif id == hovered_id:
			border = Color(1.0, 0.95, 0.8)
		draw_rect(rect, border, false, 3.0 if id == hovered_id or id == here else 1.5)
		# Which key it is on now, so a swap is no surprise.
		var where: int = HotbarLayout.where(player.skills.hotbar, player.skills.right_click_skill, id)
		var tag: String = ""
		if where == HotbarLayout.ALT:
			tag = GameSettings.short_binding_text("alt_skill")
		elif where != HotbarLayout.NONE:
			tag = GameSettings.short_binding_text("skill_%d" % (where + 1))
		if tag != "":
			UiTheme.text(self, font, rect.position + Vector2(5, 15), tag, 13, Color(1, 0.95, 0.7))


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

func _open_character() -> void:
	if character_panel != null:
		character_panel.queue_free()
	character_panel = preload("res://game/character_view.gd").new()
	character_panel.hero = player
	add_child(character_panel)
	get_tree().paused = true

## The Progression screen (passives and evolutions), opened from the character screen: it sits over it and leaves it as it was.
var progression_panel: ProgressionPanel

func open_progression() -> void:
	if progression_panel != null:
		return
	if character_panel != null:
		character_panel.visible = false
	progression_panel = ProgressionPanel.new()
	progression_panel.closed.connect(close_progression)
	add_child(progression_panel)

## From play (the "points available" chip): the character screen opens behind the Progression screen, so closing it lands back there and
## the game stays paused exactly as it does when you go in through the PROGRESSION button.
func open_progression_from_play() -> void:
	if progression_panel != null or player == null or player.dead or show_gear:
		return
	show_gear = true
	_open_character()
	open_progression()

func close_progression() -> void:
	if progression_panel != null:
		progression_panel.queue_free()
		progression_panel = null
	if character_panel != null:
		character_panel.visible = true
		if character_panel.has_method("focus_progression_button"):
			character_panel.call_deferred("focus_progression_button")

func close_character() -> void:
	show_gear = false
	if progression_panel != null:
		progression_panel.queue_free()
		progression_panel = null
	if character_panel != null:
		character_panel.queue_free()
		character_panel = null
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if player != null and not get_tree().paused:
		if picker_open() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
			close_picker()
			get_viewport().set_input_as_handled()
			return
		var click := event as InputEventMouseButton
		if click != null and click.pressed and _picker_click(click):
			get_viewport().set_input_as_handled()
			return
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and progression_hud != null and progression_hud.click_chip(click.position):
			get_viewport().set_input_as_handled()   # the "points available" chip: straight to where they are spent
			return
	if progression_panel != null and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		progression_panel.back()   # a question first, then the screen
		get_viewport().set_input_as_handled()
	elif show_gear and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("gear")):
		close_character()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("gear") and not get_tree().paused:
		show_gear = true
		_open_character()
		get_viewport().set_input_as_handled()

## Forecourt announcements own a measured free block, rather than the full-width combat band.
## Keep the existing card/prompt placement and the other banner types unchanged.
func _forecourt_keepouts(screen: Vector2, _font: Font) -> Array[Rect2]:
	var blocks: Array[Rect2] = [minimap_rect(screen, use_ds2_ui).grow(15), orb_rect(screen, false).grow(7), orb_rect(screen, true).grow(7)]
	if progression_hud != null:
		blocks.append(progression_hud.strip_rect(screen).grow(6.0))
	if _ground_card_rect.has_area():
		blocks.append(_ground_card_rect.grow(8))
	for entry in _loot_names:
		blocks.append((entry["rect"] as Rect2).grow(6))
	for sibling in get_parent().get_children():
		if sibling is TownHud:
			var prompt: Rect2 = sibling.interaction_prompt_rect()
			if prompt.has_area():
				blocks.append(prompt.grow(8))
			for overlay in sibling.overlay_rects:
				blocks.append(overlay.grow(6))
	return blocks

func _forecourt_banner_layout(screen: Vector2, font: Font) -> Dictionary:
	var regions: Array[Rect2] = [Rect2(280, 84, screen.x - 288, screen.y * 0.48 - 84)]
	for block in _forecourt_keepouts(screen, font):
		var next: Array[Rect2] = []
		for region in regions:
			if not region.intersects(block):
				next.append(region)
				continue
			var cut := region.intersection(block)
			for part in [Rect2(region.position, Vector2(region.size.x, cut.position.y - region.position.y)), Rect2(Vector2(region.position.x, cut.end.y), Vector2(region.size.x, region.end.y - cut.end.y)), Rect2(region.position, Vector2(cut.position.x - region.position.x, region.size.y)), Rect2(Vector2(cut.end.x, region.position.y), Vector2(region.end.x - cut.end.x, region.size.y))]:
				if part.size.x > 32 and part.size.y > 32:
					next.append(part)
		regions = next
	var lines := banner_text.split("\n", false, 1)
	var reward: String = lines[1] if lines.size() > 1 else ""
	var best: Dictionary = {}
	var best_score := -INF
	for region in regions:
		for heading_size in range(36, 23, -1):
			if font.get_string_size(lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, heading_size).x > region.size.x - 24:
				continue
			for reward_size in range(22, 17, -1):
				var reward_height := font.get_multiline_string_size(reward, HORIZONTAL_ALIGNMENT_LEFT, region.size.x - 24, reward_size).y
				var height := 24 + font.get_height(heading_size) + 4 + reward_height
				if height > region.size.y:
					continue
				var score := heading_size * 10 + reward_size * 20 - region.position.y * 0.1
				if score > best_score:
					best_score = score
					best = {"rect": Rect2(region.position, Vector2(region.size.x, height)), "heading_size": heading_size, "reward_size": reward_size, "heading": lines[0], "reward": reward}
	return best

func _draw_forecourt_banner(screen: Vector2, font: Font) -> void:
	var layout := _forecourt_banner_layout(screen, font)
	if layout.is_empty():
		return
	var fade := clampf(minf(banner_time, 0.8) / 0.8, 0, 1)
	var rect: Rect2 = layout.rect
	draw_rect(rect, Color(0, 0, 0, 0.42 * fade))
	draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.3, rect.size.y - 2), Vector2(rect.size.x * 0.4, 2)), Color(UiTheme.EMBER, 0.7 * fade))
	var baseline := rect.position.y + 12 + font.get_ascent(layout.heading_size)
	UiTheme.text(self, font, Vector2(rect.position.x + 12, baseline), layout.heading, layout.heading_size, Color(1, 0.9, 0.7, fade), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 24)
	baseline += font.get_height(layout.heading_size) + 4 - font.get_ascent(layout.heading_size) + font.get_ascent(layout.reward_size)
	draw_multiline_string(font, Vector2(rect.position.x + 13.5, baseline + 1.5), layout.reward, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 24, layout.reward_size, -1, Color(0, 0, 0, 0.85 * fade))
	draw_multiline_string(font, Vector2(rect.position.x + 12, baseline), layout.reward, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 24, layout.reward_size, -1, Color(0.85, 0.78, 0.65, fade))
