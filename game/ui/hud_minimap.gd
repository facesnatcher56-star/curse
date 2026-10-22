class_name HudMinimap
extends Control
## The HUD's round minimap (upper right): this item draws the nests, monsters, loot, plot signs and the hero's arrow; behind it sit the
## frame and a circle-clipped view holding the terrain and fog of war (MinimapMap). Hud creates it and calls tick() every frame.

var hud: Hud

## The minimap is its own canvas item, redrawn 20 times a second instead of every frame: it walks every obstacle and monster in the world
## (hundreds), and doing that at the full frame rate was about 8 ms of every frame, the biggest cost in the plaza.
const MAP_REDRAW := 0.05

var _map_clock: float = 0.0

## The map under the dots, and its fog of war (see MinimapMap). Two children drawn BEHIND the map item (frame, then the clipped terrain+fog view), so
## the dots, the nests and the hero's arrow, which the map item itself draws, sit on top of them.
var map_data: MinimapMap = MinimapMap.new()
var _map_frame: Control
var _map_view: Control
var _map_content: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_frame = Control.new()
	_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_frame.show_behind_parent = true
	_map_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_frame.draw.connect(_paint_map_frame)
	add_child(_map_frame)
	_map_view = Control.new()   # a disc that clips what is drawn in it (the map content) to a circle; it is not shown itself
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.show_behind_parent = true
	_map_view.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_map_view.draw.connect(_paint_map_view)
	add_child(_map_view)
	_map_content = Control.new()
	_map_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_content.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_map_content.draw.connect(_paint_map_content)
	_map_view.add_child(_map_content)

## Reveals the map round the hero and redraws every layer, MAP_REDRAW apart.
func tick(delta: float) -> void:
	_map_clock += delta
	if _map_clock < MAP_REDRAW:
		return
	_map_clock = 0.0
	if hud.player != null:
		map_data.ensure_built(get_tree())
		map_data.reveal(hud.player.global_position)
		var view: Rect2 = Hud.minimap_rect(get_viewport_rect().size, hud.use_ds2_ui)
		_map_view.position = view.position
		_map_view.size = view.size
	queue_redraw()
	_map_frame.queue_redraw()
	_map_view.queue_redraw()
	_map_content.queue_redraw()

func _draw() -> void:
	if hud.player != null:
		_draw_minimap(self, get_viewport_rect().size, ThemeDB.fallback_font)

## The round map's frame: a dark worn-iron ring with a bronze line, studs at the four quarters, the compass N (it turns with the camera, so it
## always points to world north) and the name of the place under it.
func _paint_map_frame() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var rect: Rect2 = Hud.minimap_rect(screen, hud.use_ds2_ui)
	var c: Vector2 = rect.get_center()
	var radius: float = rect.size.x * 0.5
	var f: Control = _map_frame
	if hud.use_ds2_ui and hud.ds2_compass_ring != null:
		var inner_radius: float = radius * 0.66
		# 1. Solid circular backing disc behind the map view
		f.draw_circle(c, inner_radius + 2.0, Color(0.10, 0.09, 0.08, 0.98))
		# 2. Draw compass ring matching the aperture exactly
		var ring_span: float = radius * 2.0
		var ring_rect := Rect2(c - Vector2.ONE * (ring_span * 0.5), Vector2.ONE * ring_span)
		f.draw_texture_rect(hud.ds2_compass_ring, ring_rect, false)
		# 3. Zone name neatly positioned above the compass ring
		UiTheme.text(f, UiTheme.heading_font(), Vector2(c.x - 120.0, rect.position.y - 18.0), hud.zone_name().to_upper(), 13, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
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
	UiTheme.text(f, UiTheme.heading_font(), Vector2(rect.position.x, rect.end.y + 30.0), hud.zone_name().to_upper(), 15, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x)

func _paint_map_view() -> void:
	if hud.player == null:
		return
	var radius: float = (_map_view.size.x * 0.5 * 0.66) if hud.use_ds2_ui else (_map_view.size.x * 0.5)
	_map_view.draw_circle(_map_view.size * 0.5, radius, Color.WHITE)   # this item only clips the one under it to a circle (it is not shown)

func _paint_map_content() -> void:
	if hud.player == null:
		return
	var params: Dictionary = map_view_params(get_viewport_rect().size)
	map_data.draw(_map_content, MinimapMap.transform_for(params["origin"], Gamepad.view_yaw, float(params["scale"]), _map_content.size * 0.5))

## How the map is framed: a window round the hero in the connected world, on any long arena and on anything bigger than the plain arena (a
## dungeon); the whole arena otherwise.
func map_view_params(size_px: Vector2) -> Dictionary:
	var bounds: Vector2 = Arena.bounds_of(get_tree())
	var windowed: bool = hud.force_window or bounds.y > bounds.x * 1.6 or maxf(bounds.x, bounds.y) > Arena.HALF + 1.0
	var half: float = 45.0 if windowed else Arena.HALF
	var origin: Vector3 = hud.player.global_position if windowed and hud.player != null else Vector3.ZERO
	return {"windowed": windowed, "half": half, "origin": origin, "scale": Hud.minimap_rect(size_px, hud.use_ds2_ui).size.x * (0.66 if hud.use_ds2_ui else 1.0) / (half * 2.0)}

## Whole-arena minimap, upper right. It turns with the camera, so whatever is up the screen is up on the map.
func _draw_minimap(t: CanvasItem, size_px: Vector2, font: Font) -> void:
	var rect: Rect2 = Hud.minimap_rect(size_px, hud.use_ds2_ui)
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
		if not (enemy.has_meta("monster_uid") or enemy.has_meta("quest_uid")) and not hud.enemy_in_sight(enemy):
			continue   # fog of war: a monster is shown only while it is near enough to be seen
		var rel: Vector2 = Vector2(p.x, p.z).rotated(Gamepad.view_yaw)
		var at: Vector2 = centre + Vector2(rel.x, rel.y).limit_length(half) * scale_px
		if enemy.has_meta("monster_uid") or enemy.has_meta("quest_uid"):   # a named monster: a diamond (red for a nemesis), not a dot
			var named: Color = Color(1.0, 0.75, 0.3) if enemy.has_meta("quest_uid") else Color(1.0, 0.5, 0.18)
			if enemy.has_meta("monster_uid") and bool(Monsters.find(int(enemy.get_meta("monster_uid"))).get("nemesis", false)):
				named = Color(0.95, 0.2, 0.14)
			t.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0)]), Color(0, 0, 0, 0.9))
			t.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 0), at + Vector2(0, 6), at + Vector2(-6, 0)]), named)
		elif enemy.is_big():
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
		var r: float = 3.0 + 1.5 * mini(rarity, 3)
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
	# The other party members: a dot in their ring colour (gold warrior, teal Cutter), pinned to the edge when out of the window.
	for member in PartyManager.current().living():
		if member == hud.player:
			continue
		var mp: Vector3 = member.global_position - origin
		var mat: Vector2 = centre + Vector2(mp.x, mp.z).limit_length(half).rotated(Gamepad.view_yaw) * scale_px
		t.draw_circle(mat, 4.6, Color(0, 0, 0, 0.85))
		t.draw_circle(mat, 3.4, PartyLook.color_of(member.member_id))
	# The hero: a white arrow pointing the way they face.
	var pp: Vector3 = hud.player.global_position - origin
	var me: Vector2 = centre + Vector2(pp.x, pp.z).rotated(Gamepad.view_yaw) * scale_px
	var yaw: float = hud.player.visual.rotation.y if hud.player.visual != null else 0.0
	var fwd: Vector2 = Vector2(sin(yaw), cos(yaw)).rotated(Gamepad.view_yaw)
	var side_v := Vector2(-fwd.y, fwd.x)
	t.draw_colored_polygon(PackedVector2Array([me + fwd * 7.0, me - fwd * 4.0 + side_v * 4.5, me - fwd * 2.0, me - fwd * 4.0 - side_v * 4.5]),
		Color(1, 1, 1))
