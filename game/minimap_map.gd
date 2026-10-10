class_name MinimapMap
extends RefCounted
## The minimap's map and its fog of war.
##
## The map is the ground of every arena in the world (the plaza and the Crypt Road lie end to end), the road itself, and every solid prop,
## rasterised ONCE into a small image (one pixel per CELL metres). The fog is a second image on top of it: every cell starts unknown, and the
## cells within REVEAL metres of the hero are uncovered as he walks and stay uncovered. The HUD draws the two as textures (a rotation and a
## scale, so the GPU does the work), so the map costs two draw calls however big the world is. Held in memory for the session: it is not saved.
##
## Live things on the map obey the same rule: a monster is shown only while it is within SIGHT of the hero (nobody sees what is behind the dark),
## loot and signs only where the hero has been. Job targets (the nests) and named monsters stay pinned, as they always were.

const CELL := 1.0
const REVEAL := 28.0          # how far the hero sees (m): the ground within it is uncovered
## The owner asked for no fog of war on the minimap (it showed as a black undiscovered ring). The machinery stays behind this switch.
static var fog_on: bool = false   # tests switch it on to exercise the machinery
const SIGHT := 30.0           # live monsters are shown only this close
const GROUND := Color(0.20, 0.17, 0.14, 1.0)
const ROAD := Color(0.36, 0.27, 0.17, 1.0)
const SOLID := Color(0.42, 0.36, 0.30, 1.0)
const UNKNOWN := Color(0.06, 0.06, 0.07, 1.0)
const VOID := Color(0, 0, 0, 0)

# What a cell is (`kinds`).
const K_VOID := 0
const K_GROUND := 1
const K_ROAD := 2
const K_SOLID := 3

var origin: Vector2 = Vector2.ZERO    # world (x, z) of the corner of cell (0, 0)
var cols: int = 0
var rows: int = 0
var kinds: PackedByteArray = PackedByteArray()
var terrain: Image
var fog: Image
var terrain_tex: ImageTexture
var fog_tex: ImageTexture
var explored: PackedByteArray = PackedByteArray()
var revealed_cells: int = 0
var ground_cells: int = 0

var _signature: int = -1
var _built_obstacles: int = 0
var _last_reveal: Vector2 = Vector2(INF, INF)

## Builds (or rebuilds, if the world's arenas changed or more solid props were added) the map from the arenas in the scene. Cheap when nothing
## changed. Props that are BROKEN later do not trigger a rebuild: a heap of rubble that is gone stays drawn until the next real rebuild.
func ensure_built(tree: SceneTree) -> void:
	var obstacle_count: int = 0
	var sig: int = 17
	for node in tree.get_nodes_in_group("arena"):
		var a := node as Arena
		if a == null:
			continue
		obstacle_count += a.obstacles.size()
		sig = sig * 31 + int(a.half_x * 10.0) + int(a.half_z * 10.0) * 7 + int(a.origin_offset.z * 10.0) * 13 + int(a.origin_offset.x * 10.0)
	if terrain != null and sig == _signature and obstacle_count <= _built_obstacles:
		return
	_signature = sig
	_built_obstacles = obstacle_count
	_build(tree)

func _build(tree: SceneTree) -> void:
	var rect := Rect2()
	var first: bool = true
	var arenas: Array[Arena] = []
	for node in tree.get_nodes_in_group("arena"):
		var a := node as Arena
		if a == null:
			continue
		arenas.append(a)
		var r := Rect2(a.origin_offset.x - a.half_x, a.origin_offset.z - a.half_z, a.half_x * 2.0, a.half_z * 2.0)
		rect = r if first else rect.merge(r)
		first = false
	if first:
		terrain = null
		return
	var new_cols: int = ceili(rect.size.x / CELL)
	var new_rows: int = ceili(rect.size.y / CELL)
	var same_grid: bool = terrain != null and origin == rect.position and cols == new_cols and rows == new_rows
	origin = rect.position
	cols = new_cols
	rows = new_rows
	kinds = PackedByteArray()
	kinds.resize(cols * rows)
	for a in arenas:
		var x0: int = maxi(floori((a.origin_offset.x - a.half_x - origin.x) / CELL), 0)
		var x1: int = mini(x0 + ceili(a.half_x * 2.0 / CELL), cols)
		var y0: int = maxi(floori((a.origin_offset.z - a.half_z - origin.y) / CELL), 0)
		var y1: int = mini(y0 + ceili(a.half_z * 2.0 / CELL), rows)
		for y in range(y0, y1):
			for x in range(x0, x1):
				kinds[y * cols + x] = K_GROUND
	for node in tree.get_nodes_in_group("crypt_road"):
		_paint_road(node as CryptRoad)
	for a in arenas:
		for obstacle in a.obstacles:
			var p: Vector3 = obstacle["position"]
			_paint_disc(Vector2(p.x, p.z), maxf(float(obstacle["radius"]), 0.8))
	ground_cells = 0
	var pixels := PackedByteArray()
	pixels.resize(cols * rows * 4)
	var palette: Array[Color] = [VOID, GROUND, ROAD, SOLID]
	for i in cols * rows:
		var kind: int = kinds[i]
		if kind != K_VOID:
			ground_cells += 1
		var c: Color = palette[kind]
		pixels[i * 4] = roundi(c.r * 255.0)
		pixels[i * 4 + 1] = roundi(c.g * 255.0)
		pixels[i * 4 + 2] = roundi(c.b * 255.0)
		pixels[i * 4 + 3] = roundi(c.a * 255.0)
	terrain = Image.create_from_data(cols, rows, false, Image.FORMAT_RGBA8, pixels)
	terrain_tex = ImageTexture.create_from_image(terrain)
	if not same_grid or explored.size() != cols * rows:
		explored = PackedByteArray()
		explored.resize(cols * rows)
		revealed_cells = 0
		_last_reveal = Vector2(INF, INF)
	_rebuild_fog()

## The fog image from `explored`: unknown wherever there is ground (the void outside the world needs none), clear where the hero has been.
func _rebuild_fog() -> void:
	var pixels := PackedByteArray()
	pixels.resize(cols * rows * 4)
	var unknown: PackedByteArray = PackedByteArray([roundi(UNKNOWN.r * 255.0), roundi(UNKNOWN.g * 255.0), roundi(UNKNOWN.b * 255.0), 255])
	for i in cols * rows:
		if kinds[i] != K_VOID and explored[i] == 0:
			pixels[i * 4] = unknown[0]
			pixels[i * 4 + 1] = unknown[1]
			pixels[i * 4 + 2] = unknown[2]
			pixels[i * 4 + 3] = 255
	fog = Image.create_from_data(cols, rows, false, Image.FORMAT_RGBA8, pixels)
	if fog_tex == null or fog_tex.get_width() != cols or fog_tex.get_height() != rows:
		fog_tex = ImageTexture.create_from_image(fog)
	else:
		fog_tex.update(fog)

func _paint_road(road: CryptRoad) -> void:
	if road == null or road.arena == null:
		return
	var pts: Array[Vector2] = []
	for point in CryptRoad.ROAD:
		pts.append(Vector2(road.arena.origin_offset.x + point.x, road.arena.origin_offset.z + point.y))
	var width: float = CryptRoad.ROAD_HALF_WIDTH + 0.6
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var lo := Vector2(minf(a.x, b.x) - width, minf(a.y, b.y) - width)
		var hi := Vector2(maxf(a.x, b.x) + width, maxf(a.y, b.y) + width)
		for cy in range(maxi(floori((lo.y - origin.y) / CELL), 0), mini(ceili((hi.y - origin.y) / CELL), rows)):
			for cx in range(maxi(floori((lo.x - origin.x) / CELL), 0), mini(ceili((hi.x - origin.x) / CELL), cols)):
				var centre := Vector2(origin.x + (cx + 0.5) * CELL, origin.y + (cy + 0.5) * CELL)
				if kinds[cy * cols + cx] != K_VOID and centre.distance_to(Geometry2D.get_closest_point_to_segment(centre, a, b)) <= width:
					kinds[cy * cols + cx] = K_ROAD

func _paint_disc(at: Vector2, radius: float) -> void:
	for cy in range(maxi(floori((at.y - radius - origin.y) / CELL), 0), mini(ceili((at.y + radius - origin.y) / CELL), rows)):
		for cx in range(maxi(floori((at.x - radius - origin.x) / CELL), 0), mini(ceili((at.x + radius - origin.x) / CELL), cols)):
			var centre := Vector2(origin.x + (cx + 0.5) * CELL, origin.y + (cy + 0.5) * CELL)
			if kinds[cy * cols + cx] != K_VOID and centre.distance_to(at) <= radius:
				kinds[cy * cols + cx] = K_SOLID

## Uncovers the ground within REVEAL of `world` (a position in the world). Only does the work after the hero has moved a little.
func reveal(world: Vector3, force: bool = false) -> void:
	if terrain == null:
		return
	var here := Vector2(world.x, world.z)
	if not force and here.distance_to(_last_reveal) < 1.5:
		return
	_last_reveal = here
	var reach: int = ceili(REVEAL / CELL)
	var cx0: int = floori((here.x - origin.x) / CELL)
	var cy0: int = floori((here.y - origin.y) / CELL)
	var changed: bool = false
	for dy in range(-reach, reach + 1):
		var cy: int = cy0 + dy
		if cy < 0 or cy >= rows:
			continue
		for dx in range(-reach, reach + 1):
			var cx: int = cx0 + dx
			if cx < 0 or cx >= cols or dx * dx + dy * dy > reach * reach:
				continue
			var index: int = cy * cols + cx
			if explored[index] == 0:
				explored[index] = 1
				if kinds[index] != K_VOID:
					revealed_cells += 1
					fog.set_pixel(cx, cy, VOID)
					changed = true
	if changed:
		fog_tex.update(fog)

## Has the hero's sight ever covered this world point?
func is_explored(world: Vector3) -> bool:
	if terrain == null:
		return false
	if not fog_on:
		return true
	var cx: int = floori((world.x - origin.x) / CELL)
	var cy: int = floori((world.z - origin.y) / CELL)
	if cx < 0 or cx >= cols or cy < 0 or cy >= rows:
		return false
	return explored[cy * cols + cx] == 1

## What kind of ground is at this world point (K_VOID outside the world).
func kind_at(world: Vector3) -> int:
	var cx: int = floori((world.x - origin.x) / CELL)
	var cy: int = floori((world.z - origin.y) / CELL)
	if terrain == null or cx < 0 or cx >= cols or cy < 0 or cy >= rows:
		return K_VOID
	return kinds[cy * cols + cx]

## Forgets everything (a new character; the road does not need it, it keeps its layout).
func forget() -> void:
	explored = PackedByteArray()
	explored.resize(cols * rows)
	revealed_cells = 0
	_last_reveal = Vector2(INF, INF)
	if terrain != null:
		_rebuild_fog()

## Draws the terrain, then the fog over it, into `canvas`, whose world-to-screen mapping is `xf` (world x,z in metres -> pixels).
func draw(canvas: CanvasItem, xf: Transform2D) -> void:
	if terrain_tex == null:
		return
	var world := Rect2(origin, Vector2(cols, rows) * CELL)
	canvas.draw_set_transform_matrix(xf)
	canvas.draw_texture_rect(terrain_tex, world, false)
	if fog_on:
		canvas.draw_texture_rect(fog_tex, world, false)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

## World (x, z) -> position in the minimap view for a hero at `hero`, a view turned by `yaw`, `scale` pixels per metre, `centre` the view's middle.
static func transform_for(hero: Vector3, yaw: float, scale: float, centre: Vector2) -> Transform2D:
	var xf := Transform2D(yaw, centre)
	xf = xf.scaled_local(Vector2(scale, scale))
	return xf.translated_local(-Vector2(hero.x, hero.z))
