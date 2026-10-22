class_name CryptDungeon
extends TestDungeon
## The Crypt (`-- --crypt01`): a hand-designed dungeon built from the KayKit GridMap kit, dressed with ProtonScatter, in the scene
## `game/world/dungeons/crypt_01.tscn`. Menu -> Play still goes to the test dungeon; this is opt-in until the owner says to switch.
##
## Like TestDungeon this class only loads the scene and wires it up: the packs are DungeonEnemyGroup markers, props become breakable or
## solid, chests stand outside the navigation region, and the GridMaps are made solid here: the kit's MeshLibrary hulls would close
## every doorway, so each wall cell gets its own collision boxes (a doorway gets two jambs) in one StaticBody, and the one navigation bake
## sees them. How to edit the dungeon: docs/CRYPT_DUNGEON.md. The plan it was written from: CryptLayout.

const CRYPT_SCENE := "res://game/world/dungeons/crypt_01.tscn"
const SITE_NAME := "crypt_01"
## Wall pieces are one cell (4 m) wide, this thick, and this tall; a low barrier is LOW_HEIGHT; a doorway opening is DOOR_WIDTH wide.
const WALL_THICK := 1.0
const WALL_HEIGHT := 4.0
const LOW_HEIGHT := 1.1
const DOOR_WIDTH := 2.2


## The arena for this location: the plan's rectangle, no random scatter, and no navigation mesh yet.
static func make_arena() -> Arena:
	var a := Arena.new()
	a.half_x = CryptLayout.half_x()
	a.half_z = CryptLayout.half_z()
	a.scatter = false
	return a


## The Crypt names itself and never shows the Road's job text ("The Road / Free run").
func banner_text(_job: Dictionary) -> String:
	return "The Crypt\nDeep Beyond"


## Hooks for a dungeon built on this loader (MapModeDungeon): the scene to load, the HUD's zone name, and a look at the scene once the groups are
## read (the markers are still in it, the chests already stand under this node).
func scene_path() -> String:
	return CRYPT_SCENE


func zone_title() -> String:
	return "The Crypt"


func _scene_read() -> void:
	pass


func start_position() -> Vector3:
	if level != null and level.has_node("PlayerStart"):
		return (level.get_node("PlayerStart") as Node3D).global_position
	var start: Vector2 = CryptLayout.world(CryptLayout.START_CELL.x, CryptLayout.START_CELL.y)
	return Vector3(start.x, 0.0, start.y)


## Every walkable cell of the plan (rooms and corridors) as a world rectangle (x, z), for the minimap (MinimapMap paints them as the floor).
func floor_rects() -> Array[Rect2]:
	return plan_floor_rects(CryptLayout.W, CryptLayout.H, CryptLayout.CELL, CryptLayout.space_at, CryptLayout.world)


static func plan_floor_rects(w: int, h: int, cell: float, space_at: Callable, world: Callable) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in h:
		for c in w:
			if String(space_at.call(c, r)) != "":
				var centre: Vector2 = world.call(float(c), float(r))
				out.append(Rect2(centre - Vector2.ONE * cell * 0.5, Vector2.ONE * cell))
	return out


func build(for_arena: Arena) -> void:
	arena = for_arena
	in_world = false
	add_to_group("test_dungeon")   # the tests and tools that look for "the dungeon" find it
	add_to_group("crypt_dungeon")   # the HUD names the zone from it
	_rng.seed = 2525
	_black_out_ground()
	level = (load(scene_path()) as PackedScene).instantiate() as Node3D
	var nav: NavigationRegion3D = arena.get("_nav_region")
	nav.add_child(level)
	CryptLook.apply_materials(level)
	make_solid(level, nav)
	for group in level.get_children():
		match String(group.name):
			"Props", "SetPieces", "Pillars", "Torches":
				for holder in group.get_children():
					_adopt(holder)
			"Chests":
				for chest in group.get_children():   # chests stand outside the navigation region, as they always did
					group.remove_child(chest)
					add_child(chest)
	groups = read_groups(level)
	_scene_read()
	level.get_node("EnemyGroups").queue_free()   # only read: the groups are spawned by spawn_encounters
	arena.bake_navigation()


## The Crypt's own mood instead of the test dungeon's bright rooms (only under the atmosphere profile, which is the default).
func tune_look(environment: Environment) -> void:
	var suns: Array = arena.get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	CryptLook.tune_environment(environment, suns[0] as DirectionalLight3D if not suns.is_empty() else null)
	CryptLook.style_lights(arena)


# --- Solid walls from the GridMaps --------------------------------------------------------------------------------------------------------

## Turns every GridMap wall cell of `level_root` into collision boxes in one StaticBody3D added to `body_parent`, and switches the GridMaps'
## own collision off. Returns the number of boxes.
static func make_solid(level_root: Node3D, body_parent: Node) -> int:
	var body := StaticBody3D.new()
	body.name = "WallBody"
	body.collision_layer = Actor.LAYER_WORLD
	var count: int = 0
	for node in level_root.find_children("*", "GridMap", true, false):
		var grid := node as GridMap
		grid.collision_layer = 0
		grid.collision_mask = 0
		if not String(grid.name).begins_with("Walls") or grid.mesh_library == null:
			continue
		var cell_xz: Vector3 = grid.cell_size
		for cell in grid.get_used_cells():
			var item: int = grid.get_cell_item(cell)
			var piece: String = grid.mesh_library.get_item_name(item)
			var basis: Basis = grid.get_cell_item_basis(cell)
			var origin: Vector3 = grid.map_to_local(cell)
			for box in wall_boxes(piece, cell_xz.x):
				var shape := CollisionShape3D.new()
				var box_shape := BoxShape3D.new()
				box_shape.size = box["size"]
				shape.shape = box_shape
				var local := Transform3D(basis, origin) * Transform3D(Basis(), box["centre"])
				shape.transform = grid.transform * local
				body.add_child(shape)
				count += 1
	body_parent.add_child(body)
	return count


## The boxes that make a wall piece solid, in the piece's own frame (it lies along x on the cell's -z edge): [{size, centre}].
static func wall_boxes(piece: String, cell: float) -> Array:
	var edge := Vector3(0.0, 0.0, -cell * 0.5)
	if piece.begins_with("wall_doorway"):
		var jamb: float = (cell - DOOR_WIDTH) * 0.5
		var offset: float = DOOR_WIDTH * 0.5 + jamb * 0.5
		var out: Array = []
		for side in [-1.0, 1.0]:
			out.append({"size": Vector3(jamb, WALL_HEIGHT, WALL_THICK), "centre": edge + Vector3(side * offset, WALL_HEIGHT * 0.5, 0.0)})
		return out
	if piece.begins_with("barrier"):
		return [{"size": Vector3(cell, LOW_HEIGHT, WALL_THICK * 0.6), "centre": edge + Vector3(0.0, LOW_HEIGHT * 0.5, 0.0)}]
	return [{"size": Vector3(cell, WALL_HEIGHT, WALL_THICK), "centre": edge + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)}]


# --- The way in and the pacing -----------------------------------------------------------------------------------------------------------

## The way in as world points (x, z).
static func main_route() -> Array[Vector2]:
	return CryptLayout.route_world(CryptLayout.MAIN_PATH)


## The longest stretch (m) of the main route walked with no pack within PACK_VIEW_RANGE, for packs at `homes`, sampled every metre.
static func longest_pack_gap(homes: Array) -> float:
	var route: Array[Vector2] = main_route()
	var worst: float = 0.0
	var run: float = 0.0
	for i in route.size() - 1:
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		var length: float = a.distance_to(b)
		var s: float = 0.0
		while s <= length:
			var here: Vector2 = a.lerp(b, s / maxf(length, 0.001))
			var seen: bool = false
			for home in homes:
				if here.distance_to(home) <= PACK_VIEW_RANGE:
					seen = true
					break
			run = 0.0 if seen else run + 1.0
			worst = maxf(worst, run)
			s += 1.0
	return worst
