class_name CryptBaker
extends RefCounted
## Writes the Crypt scene (`game/world/dungeons/crypt_01.tscn`) from the plan in L. Developer tool: the game never runs this.
##   godot --headless --path . -s res://tools/build_crypt_01.gd
## The scene it writes is the SOURCE of the dungeon from then on (docs/CRYPT_DUNGEON.md): open it in the editor, move, add and delete things,
## save. Run this again only to throw hand edits away and start over from the plan.

const OUT := "res://game/world/dungeons/crypt_01.tscn"
const LIB := "res://assets/third_party/kaykit_dungeon/dungeon_meshlib.tres"
const KK := "res://assets/third_party/kaykit_dungeon/models/%s.gltf.glb"
const Q1 := "res://assets/third_party/quaternius_modular_dungeon_1/%s.glb"
const Q2 := "res://assets/third_party/quaternius_modular_dungeon_2/%s.glb"
const URN := "res://assets/models/dungeon/urn/model.glb"
const SCATTER_MOD := "res://addons/proton_scatter/src/modifiers/%s.gd"
const C := 4.0   # the cell size of every plan (CryptLayout.CELL)

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # north, east, south, west
const DIR_NAMES := ["N", "E", "S", "W"]
const DIR_YAW := [0.0, 270.0, 180.0, 90.0]    # the GridMap rotation that puts a wall on that edge (the piece sits on the -z edge at 0 degrees)

## The plan to bake: CryptLayout, or a layout with the same constants and helpers (MapModeBaker hands in MapModeLayout).
var L: Variant = CryptLayout
var out_path: String = OUT
var root_name: String = "Crypt01"
var root: Node3D
var lib: MeshLibrary
var rng := RandomNumberGenerator.new()
var _groups: Dictionary = {}
var _doors: Array[Vector2] = []        # the middle of every doorway, world (x, z)
var _taken: Array[Vector3] = []        # props placed so far: x, z, clearance radius
var _wall_cells: Array = []            # {space, dir, cell, centre (world x, z), normal (inward, world x, z)}
var _chests: Array[Vector2] = []
var _counts: Dictionary = {}
var _stone: StandardMaterial3D
var _cut_zones: Array[Vector3] = []     # corner cuts: corner x, z, size


func build() -> int:
	rng.seed = 7301
	lib = load(LIB)
	_stone = StandardMaterial3D.new()
	_stone.albedo_color = Color(0.3, 0.31, 0.35)
	_stone.roughness = 0.95
	root = Node3D.new()
	root.name = root_name
	for group_name in _group_names():
		var group := Node3D.new()
		group.name = group_name
		root.add_child(group)
		group.owner = root
		_groups[group_name] = group
	_floor()
	_walls()
	_corner_posts()
	_rounds()
	_cuts()
	for chest in L.CHESTS:
		var spot: Vector2 = L.world(float(chest["cell"].x), float(chest["cell"].y))
		_chests.append(spot)
	_set_pieces()
	_props()
	_dress()
	_torches()
	_scatter()
	_chest_nodes()
	_packs()
	_floor_detail()
	var start := Marker3D.new()
	start.name = "PlayerStart"
	var s: Vector2 = L.world(L.START_CELL.x, L.START_CELL.y)
	start.position = Vector3(s.x, 0.0, s.y)
	root.add_child(start)
	start.owner = root
	var packed := PackedScene.new()
	var error: int = packed.pack(root)
	if error != OK:
		return error
	error = ResourceSaver.save(packed, out_path)
	print("CRYPT_BAKE %s: %s (error %d)" % [out_path, str(_counts), error])
	return error


## The scene's top-level groups (MapModeBaker adds "Shrines").
func _group_names() -> Array:
	return ["Floor", "Walls", "Pillars", "Props", "SetPieces", "Decor", "Torches", "Liners", "Scatter", "Chests", "EnemyGroups"]


# --- helpers ---------------------------------------------------------------------------------------------------------------------------

func _grid(parent: String, node_name: String) -> GridMap:
	var g := GridMap.new()
	g.name = node_name
	g.mesh_library = lib
	g.cell_size = Vector3(C, C, C)
	g.cell_center_y = false
	g.position = Vector3(-float(L.W) * C * 0.5, 0.0, -float(L.H) * C * 0.5)
	g.collision_layer = 0
	g.collision_mask = 0
	(_groups[parent] as Node3D).add_child(g)
	g.owner = root
	return g


func _own(node: Node) -> void:
	node.owner = root
	if node.scene_file_path != "":
		return
	for child in node.get_children():
		_own(child)


func _add(group: String, node: Node3D, node_name: String) -> Node3D:
	var n: int = int(_counts.get(group, 0))
	_counts[group] = n + 1
	node.name = "%s_%02d" % [node_name, n]
	(_groups[group] as Node3D).add_child(node)
	_own(node)
	return node


func _model(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate() as Node3D


func _bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var walker: Node = m
		while walker != null and walker != node:
			xf = (walker as Node3D).transform * xf
			walker = walker.get_parent()
		var box: AABB = xf * m.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## The model scaled to `height` tall (0 keeps its own size), standing on the ground and centred over its holder's origin.
func _fitted(path: String, height: float) -> Node3D:
	var model := _model(path)
	model.name = "model"
	var box: AABB = _bounds(model)
	var factor: float = height / maxf(box.size.y, 0.001) if height > 0.0 else 1.0
	model.scale = Vector3.ONE * factor
	model.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * factor
	return model


## The model stretched to exactly `size`, standing on the ground and centred over its holder's origin.
func _fitted_scaled(path: String, size: Vector3) -> Node3D:
	var model := _model(path)
	model.name = "model"
	var box: AABB = _bounds(model)
	var f := Vector3(size.x / maxf(box.size.x, 0.001), size.y / maxf(box.size.y, 0.001), size.z / maxf(box.size.z, 0.001))
	model.scale = f
	model.position = Vector3(-box.get_center().x * f.x, -box.position.y * f.y, -box.get_center().z * f.z)
	return model


func _body(shape: Shape3D, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = centre
	body.add_child(cs)
	return body


func _cylinder(radius: float, height: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


func _spot_free(p: Vector2, radius: float) -> bool:
	for t in _taken:
		if p.distance_to(Vector2(t.x, t.y)) < radius + t.z:
			return false
	return true


func _near_door(p: Vector2, margin: float) -> bool:
	for d in _doors:
		if p.distance_to(d) < margin:
			return true
	return false


func _remember(p: Vector2, radius: float) -> void:
	_taken.append(Vector3(p.x, p.y, radius))


## A breakable prop (Destructible: barrel, crate or urn) with its visual and a cylinder body; the game wires it up when the scene loads.
func _breakable(kind: String, model: String, p: Vector2, yaw: float, height: float, radius: float) -> void:
	var holder := Destructible.new()
	holder.position = Vector3(p.x, 0.0, p.y)
	holder.rotation.y = yaw
	holder.set_meta("category", "Props")
	holder.set_meta("obstacle_radius", radius)
	holder.set_meta("prop_kind", kind)
	holder.set_meta("prop_height", height)
	holder.add_child(_fitted(model, height))
	holder.add_child(_body(_cylinder(radius, height), Vector3(0, height * 0.5, 0)))
	_add("Props", holder, kind.capitalize())
	_remember(p, radius + 0.4)


## A solid prop or set piece: a visual and a body; the game registers it as an obstacle (metadata obstacle_radius).
func _solid(group: String, model: String, p: Vector2, yaw: float, height: float, radius: float, node_name: String, box: Vector3 = Vector3.ZERO) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(p.x, 0.0, p.y)
	holder.rotation.y = yaw
	holder.set_meta("obstacle_radius", radius)
	holder.add_child(_fitted(model, height))
	var shape: Shape3D = _cylinder(radius, maxf(height, 1.0))
	var hh: float = maxf(height, 1.0)
	if box != Vector3.ZERO:
		var b := BoxShape3D.new()
		b.size = box
		shape = b
		hh = box.y
	holder.add_child(_body(shape, Vector3(0, hh * 0.5, 0)))
	_add(group, holder, node_name)
	_remember(p, radius + 0.3)
	return holder


func _decor(model: String, p: Vector3, yaw: float, height: float, node_name: String) -> Node3D:
	var holder := Node3D.new()
	holder.position = p
	holder.rotation.y = yaw
	holder.add_child(_fitted(model, height))
	_add("Decor", holder, node_name)
	return holder


func _flame(parent: Node3D, at: Vector3, energy: float, range_m: float, shadow: bool = false, role: String = "torch") -> void:
	var light := OmniLight3D.new()
	light.name = "FlameLight"
	light.set_meta("crypt_role", role)
	light.position = at
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = shadow
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 10.0
	parent.add_child(light)
	var flicker := FlickerLight.new()
	flicker.name = "Flicker"
	light.add_child(flicker)


# --- floor, walls, posts -----------------------------------------------------------------------------------------------------------------

func _floor() -> void:
	var grid := _grid("Floor", "Floor")
	var plain: int = lib.find_item_by_name("floor_tile_large")
	var rocks: int = lib.find_item_by_name("floor_tile_large_rocks")
	var rotations: Array[int] = []
	for deg in [0, 90, 180, 270]:
		rotations.append(grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(float(deg)))))
	var n: int = 0
	for r in L.H:
		for c in L.W:
			var space: String = L.space_at(c, r)
			if space == "":
				continue
			if L.ROUNDS.has(space) and not _round_keeps(space, c, r):
				continue
			var item: int = plain
			if rng.randf() < 0.0:   # floor_tile_large_rocks carries a boulder bigger than the hero: left out
				item = rocks
			grid.set_cell_item(Vector3i(c, 0, r), item, rotations[rng.randi() % 4])
			n += 1
	_counts["floor cells"] = n


func _walls() -> void:
	var grids: Array[GridMap] = []
	for d in 4:
		grids.append(_grid("Walls", "Walls" + String(DIR_NAMES[d])))
	var rot: Array[int] = []
	for d in 4:
		rot.append(grids[0].get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(float(DIR_YAW[d])))))
	var wall: int = lib.find_item_by_name("wall")
	var cracked: int = lib.find_item_by_name("wall_cracked")
	var shelves: int = lib.find_item_by_name("wall_shelves")
	var broken: int = lib.find_item_by_name("wall_broken")
	var arched: int = lib.find_item_by_name("wall_arched")
	var half: int = lib.find_item_by_name("barrier")
	var door: int = lib.find_item_by_name("wall_doorway")
	var n_wall := 0
	var n_door := 0
	for r in L.H:
		for c in L.W:
			var space: String = L.space_at(c, r)
			if space == "":
				continue
			for d in 4:
				var nc: int = c + (DIRS[d] as Vector2i).x
				var nr: int = r + (DIRS[d] as Vector2i).y
				var other: String = L.space_at(nc, nr)
				if other == space:
					continue
				var centre: Vector2 = L.world(c, r)
				var edge: Vector2 = centre + Vector2(DIRS[d]) * C * 0.5
				if other != "":
					if space > other:
						continue   # the other side places the doorway
					grids[d].set_cell_item(Vector3i(c, 0, r), door, rot[d])
					_doors.append(edge)
					n_door += 1
					continue
				if L.ROUNDS.has(space):
					continue   # the curve walls this space (see _rounds)
				var item: int = wall
				var roll: float = rng.randf()
				if d == 2:
					item = half   # the camera looks north: the wall on a room's south edge is a low barrier, so the room stays in view
				elif roll < 0.12:
					item = cracked
				elif roll < 0.2:
					item = broken
				elif roll < 0.25 and L.SPACES[space]["kind"] in ["side", "hall"]:
					item = shelves
				elif roll < 0.29 and L.SPACES[space]["kind"] in ["side", "hall"]:
					item = arched
				grids[d].set_cell_item(Vector3i(c, 0, r), item, rot[d])
				n_wall += 1
				_wall_cells.append({"space": space, "dir": d, "edge": edge, "inward": -Vector2(DIRS[d]), "item": item == half})
	_counts["walls"] = n_wall
	_counts["doorways"] = n_door


## A pillar post on every wall corner, T and end (a straight run needs none), so wall ends and door jambs read as built, not cut.
func _corner_posts() -> void:
	var post: PackedScene = load(KK % "pillar")
	var n := 0
	for vr in range(0, L.H + 1):
		for vc in range(0, L.W + 1):
			var around: Array[String] = [L.space_at(vc - 1, vr - 1), L.space_at(vc, vr - 1),
				L.space_at(vc, vr), L.space_at(vc - 1, vr)]   # NW, NE, SE, SW
			var north: bool = around[0] != around[1]
			var east: bool = around[1] != around[2]
			var south: bool = around[2] != around[3]
			var west: bool = around[3] != around[0]
			var count: int = int(north) + int(east) + int(south) + int(west)
			if count == 0 or (count == 2 and ((north and south) or (east and west))):
				continue
			var round_here: bool = false
			var door_here: bool = false
			for i in 4:
				var a: String = around[i]
				var b: String = around[(i + 1) % 4]
				round_here = round_here or L.ROUNDS.has(a) or L.ROUNDS.has(b)
				door_here = door_here or (a != b and a != "" and b != "")
			if round_here and not door_here:
				continue   # the curve has no square corners to post
			var holder := Node3D.new()
			holder.position = Vector3((float(vc) - float(L.W) * 0.5) * C, 0.0, (float(vr) - float(L.H) * 0.5) * C)
			holder.add_child(post.instantiate())
			_add("Pillars", holder, "Post")
			n += 1
	_counts["wall posts"] = n


# --- set pieces and props -----------------------------------------------------------------------------------------------------------------

func _space_rect_world(space: String) -> Rect2:
	var rect: Array = L.SPACES[space]["rects"][0]
	var a: Vector2 = L.world(int(rect[0]), int(rect[1])) - Vector2(C, C) * 0.5
	var b: Vector2 = L.world(int(rect[2]), int(rect[3])) + Vector2(C, C) * 0.5
	return Rect2(a, b - a)


func _sarcophagus(p: Vector2, yaw: float, name_suffix: String) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(p.x, 0.0, p.y)
	holder.rotation.y = yaw
	holder.set_meta("obstacle_radius", 1.3)
	var base := _fitted_scaled(Q1 % "Pedestal2", Vector3(2.5, 0.85, 1.1))
	base.name = "Base"
	holder.add_child(base)
	var lid := _fitted_scaled(Q1 % "Pedestal2", Vector3(2.3, 0.28, 0.95))
	lid.name = "Lid"
	lid.position.y += 0.85
	lid.rotation.y = deg_to_rad(rng.randf_range(-5.0, 5.0))
	holder.add_child(lid)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.5, 1.2, 1.15)
	holder.add_child(_body(shape, Vector3(0, 0.6, 0)))
	_add("SetPieces", holder, "Sarcophagus" + name_suffix)
	_remember(p, 1.6)


func _altar(p: Vector2, node_name: String, height: float = 1.3) -> void:
	var holder := _solid("SetPieces", Q1 % "Pedestal2", p, 0.0, height, 0.9, node_name)
	var candle := _model(KK % "candle_triple")
	candle.position = Vector3(0, height, 0)
	candle.scale = Vector3.ONE * 1.4
	holder.add_child(candle)
	_own(candle)
	_flame(holder, Vector3(0, height + 0.9, 0), 1.6, 7.0, false, "candle")
	holder.get_node("FlameLight").owner = root
	holder.get_node("FlameLight/Flicker").owner = root


func _ring(centre: Vector2, radius: float, count: int, offset_deg: float, model: String, height: float, node_name: String) -> void:
	for i in count:
		var a: float = deg_to_rad(offset_deg + 360.0 * float(i) / float(count))
		var p: Vector2 = centre + Vector2(cos(a), sin(a)) * radius
		_solid("SetPieces", model, p, rng.randf() * TAU, height, 0.7, node_name)


func _set_pieces() -> void:
	# Pillared crypt: two lines of pillars down the nave, a broken one now and then.
	for vr in [35, 38]:
		for vc in [7, 10, 13]:
			var p := Vector2((float(vc) - float(L.W) * 0.5) * C, (float(vr) - float(L.H) * 0.5) * C)
			var broken: bool = (vr == 38 and vc == 10)
			_solid("SetPieces", Q2 % "Column_Broken" if broken else KK % "pillar_decorated", p, 0.0, 2.6 if broken else 4.0, 0.75, "CryptPillar")
	_sarcophagus(L.world(5.2, 34.2) + Vector2(0, 0), 0.0, "A")
	_sarcophagus(L.world(5.2, 39.0), PI, "B")
	# Long hall: a broken pillar every few cells along the north wall, banners above, a sarcophagus at the west end.
	for c in [26, 22, 18, 14, 11]:
		var p: Vector2 = L.world(c, 45) + Vector2(rng.randf_range(-0.4, 0.4), 0.9)
		_solid("SetPieces", Q2 % ("Column_Broken" if c % 2 == 0 else "Column_Broken2"), p, rng.randf() * TAU, 2.4, 0.6, "BrokenPillar")
	_sarcophagus(L.world(10, 47) + Vector2(0, 0.6), PI * 0.5, "C")
	# Ossuary: two rows of sarcophagi with bones between them.
	for i in 3:
		_sarcophagus(L.world(20.2 + float(i) * 2.3, 34.7), 0.0, "O%d" % i)
		_sarcophagus(L.world(20.2 + float(i) * 2.3, 37.9), PI, "P%d" % i)
	# Rotunda: the altar in the middle, eight pillars round it.
	var centre: Vector2 = L.world(16, 24)
	_altar(centre, "RotundaAltar", 1.4)
	_ring(centre, 8.5, 8, 22.5, KK % "pillar_decorated", 4.0, "RotundaPillar")
	# Vault (side): a long table with candles and shelves; shrine (side): an altar and a statue; bone closet: a sarcophagus.
	_solid("SetPieces", KK % "table_long_decorated_A", L.world(7, 24) + Vector2(0, 0), PI * 0.5, 1.1, 1.0, "VaultTable", Vector3(2.4, 1.1, 1.0))
	_solid("SetPieces", KK % "shelf_large", L.world(4.4, 22.6) + Vector2(-0.4, 0.0), PI * 0.5, 2.6, 0.9, "VaultShelf", Vector3(1.0, 2.0, 2.4))
	_altar(L.world(27, 16), "ShrineAltar", 1.2)
	_solid("SetPieces", Q1 % "Statue_Horse", L.world(27, 14.4), PI, 2.8, 1.0, "ShrineStatue")
	_sarcophagus(L.world(1, 34.7), 0.0, "D")
	# Guard hall: two pairs of pillars and a statue at each end.
	for vc in [14, 18]:
		for vr in [16, 18]:
			var p := Vector2((float(vc) - float(L.W) * 0.5) * C, (float(vr) - float(L.H) * 0.5) * C)
			_solid("SetPieces", KK % "pillar", p, 0.0, 4.0, 0.7, "GuardPillar")
	_solid("SetPieces", Q1 % "Statue_Horse", L.world(12, 15.6), PI * 0.5, 2.6, 1.0, "GuardStatue")
	_solid("SetPieces", Q1 % "Statue_Horse", L.world(20, 15.6), -PI * 0.5, 2.6, 1.0, "GuardStatue")
	# Antechamber: sarcophagi against the side walls, an altar between them.
	_sarcophagus(L.world(13.0, 11.0), PI * 0.5, "E")
	_sarcophagus(L.world(19.0, 11.0), PI * 0.5, "F")
	# The arena: six great pillars in two rows and a broken altar in the middle.
	for vc in [11, 14, 18, 21]:
		for vr in [2, 6]:
			var p := Vector2((float(vc) - float(L.W) * 0.5) * C, (float(vr) - float(L.H) * 0.5) * C)
			_solid("SetPieces", KK % "pillar_decorated", p, 0.0, 4.0, 0.75, "ArenaPillar")
	_altar(L.world(16, 3.5) + Vector2(0, 0), "WardenAltar", 1.0)


## How many breakables each space gets. Corridors stay clear: a barrel in a 4 m passage closes the navigation mesh.
func _prop_targets() -> Dictionary:
	return {"vestibule": 7, "long_hall": 9, "pillared_crypt": 6, "ossuary": 5, "rotunda": 3, "guard_hall": 6, "antechamber": 4, "arena": 5,
		"vault": 4, "shrine": 3, "bone_closet": 3}


func _props() -> void:
	var models: Array = [
		["barrel", KK % "barrel_large", 1.2, 0.55],
		["barrel", KK % "barrel_small_stack", 0.9, 0.55],
		["crate", KK % "crates_stacked", 1.3, 0.75],
		["crate", KK % "box_large", 0.9, 0.55],
		["barrel", KK % "keg", 0.9, 0.5],
		["urn", URN, 0.9, 0.45],
	]
	var targets: Dictionary = _prop_targets()
	for space in targets:
		var wanted: int = int(targets[space])
		var cells: Array = _wall_cells.filter(func(w: Dictionary) -> bool: return w["space"] == space and not bool(w["item"]))
		if cells.is_empty():
			continue
		var made := 0
		var tries := 0
		while made < wanted and tries < wanted * 60:
			tries += 1
			var w: Dictionary = cells[rng.randi() % cells.size()]
			var along: Vector2 = Vector2((w["inward"] as Vector2).y, -(w["inward"] as Vector2).x)
			var p: Vector2 = (w["edge"] as Vector2) + (w["inward"] as Vector2) * rng.randf_range(1.0, 1.5) + along * rng.randf_range(-1.4, 1.4)
			var pick: Array = models[rng.randi() % models.size()]
			if _in_cut(p) or _near_door(p, 3.6) or not _spot_free(p, float(pick[3])) or _near_pack(p) or _near_chest(p):
				continue
			_breakable(String(pick[0]), String(pick[1]), p, rng.randf() * TAU, float(pick[2]), float(pick[3]))
			made += 1
	_counts["breakables"] = _counts.get("Props", 0)


func _near_pack(p: Vector2) -> bool:
	for pack in L.PACKS:
		if p.distance_to(L.world((pack["cell"] as Vector2).x, (pack["cell"] as Vector2).y)) < 3.6:
			return true
	return false


func _near_chest(p: Vector2) -> bool:
	for c in _chests:
		if p.distance_to(c) < 3.2:
			return true
	return false


func _torches() -> void:
	var counters: Dictionary = {}
	var banners: Array = ["banner_red", "banner_brown", "banner_thin_red", "banner_thin_brown", "banner_shield_red", "banner_shield_brown"]
	for w in _wall_cells:
		if int(w["dir"]) == 2 or bool(w["item"]):
			continue   # a low wall carries no torch
		var key: String = "%s/%d" % [w["space"], int(w["dir"])]
		var n: int = int(counters.get(key, 0))
		counters[key] = n + 1
		var kind: String = String(L.SPACES[w["space"]]["kind"])
		var step: int = 3 if kind == "corridor" else 5
		var edge: Vector2 = w["edge"]
		var inward: Vector2 = w["inward"]
		if _near_door(edge, 2.6) or _in_cut(edge + inward * 0.5):
			continue
		if n % step == 1:
			_torch_at(edge + inward * 0.5, inward)
		elif kind != "corridor" and n % step == 3 and rng.randf() < 0.7:
			var banner := _fitted(KK % String(banners[rng.randi() % banners.size()]), 3.0)
			var holder := Node3D.new()
			var pos: Vector2 = edge + inward * 0.35
			holder.position = Vector3(pos.x, 0.9, pos.y)
			holder.rotation.y = atan2(inward.x, inward.y)
			holder.add_child(banner)
			_add("Decor", holder, "Banner")
		elif kind in ["hall", "side"] and n % step == 2 and rng.randf() < 0.35:
			_chain(edge + inward * 0.2, inward)


func _torch_at(pos: Vector2, inward: Vector2) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(pos.x, 2.1, pos.y)
	holder.rotation.y = atan2(inward.x, inward.y)   # local +z points into the room
	holder.add_child(_model(KK % "torch_mounted"))
	_flame(holder, Vector3(0, 0.9, 0.5), 2.4, 9.0, false, "torch")
	_add("Torches", holder, "Torch")


## A chain hanging down a wall: links of a ring, alternately turned, in one MultiMesh.
func _chain(pos: Vector2, inward: Vector2) -> void:
	var mm := MultiMesh.new()
	var link := TorusMesh.new()
	link.inner_radius = 0.045
	link.outer_radius = 0.1
	link.rings = 8
	link.ring_segments = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.1)
	mat.metallic = 0.8
	mat.roughness = 0.45
	link.material = mat
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link
	var links: int = 14 + rng.randi() % 5
	mm.instance_count = links
	for i in links:
		var turn := Basis(Vector3.UP, deg_to_rad(90.0 if i % 2 == 1 else 0.0))
		mm.set_instance_transform(i, Transform3D(turn * Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(0, -float(i) * 0.19, 0)))
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = mm
	holder.position = Vector3(pos.x, 3.7, pos.y)
	holder.rotation.y = atan2(inward.x, inward.y)
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add("Decor", holder, "Chain")


func _scatter() -> void:
	var picks: Array = [[Q2 % "Bones2", 20, 0.5], [Q2 % "Bones", 14, 0.5], [Q1 % "Skull", 14, 0.9], [KK % "candle_melted", 6, 0.55],
		[Q1 % "Brick", 24, 1.4], [Q1 % "Vase", 6, 1.6],
		[Q1 % "Bucket", 2, 1.2]]
	for space in L.SPACES:
		var kind: String = String(L.SPACES[space]["kind"])
		var area: float = 0.0
		var sc := ProtonScatter.new()
		sc.global_seed = 100 + absi(int(hash(space) % 1000))
		sc.show_output_in_tree = false
		for strip in _scatter_strips(space):   # {centre Vector2, size Vector2, yaw}
			area += (strip["size"] as Vector2).x * (strip["size"] as Vector2).y
			var shape := ProtonScatterShape.new()
			shape.name = "Area%d" % int(shape.get_instance_id() % 100000)
			var box := ProtonScatterBoxShape.new()
			box.size = Vector3((strip["size"] as Vector2).x, 0.2, (strip["size"] as Vector2).y)
			shape.shape = box
			shape.position = Vector3((strip["centre"] as Vector2).x, 0.0, (strip["centre"] as Vector2).y)
			shape.rotation.y = float(strip["yaw"])
			sc.add_child(shape)
		for door in _doors:   # keep every doorway clear
			if _door_in_space(door, space):
				var gap := ProtonScatterShape.new()
				gap.name = "Door%d" % int(gap.get_instance_id() % 100000)
				gap.negative = true
				var gap_box := ProtonScatterBoxShape.new()
				gap_box.size = Vector3(4.4, 0.6, 4.4)
				gap.shape = gap_box
				gap.position = Vector3(door.x, 0.0, door.y)
				sc.add_child(gap)
		var density: float = 0.5 if kind == "corridor" else 1.2
		var stack := ProtonScatterModifierStack.new()
		var create = load(SCATTER_MOD % "create_inside_random").new()
		create.amount = clampi(int(area * density), 6, 700)
		_counts["scatter items"] = int(_counts.get("scatter items", 0)) + create.amount
		var rotate = load(SCATTER_MOD % "randomize_rotation").new()
		rotate.rotation = Vector3(0, 360, 0)
		rotate.snap_angle = Vector3.ZERO
		var jitter = load(SCATTER_MOD % "randomize_transforms").new()
		jitter.scale = Vector3(0.6, 0.6, 0.6)
		stack.stack.append(create)
		stack.stack.append(rotate)
		stack.stack.append(jitter)
		sc.modifier_stack = stack
		sc.name = "Scatter_" + space
		(_groups["Scatter"] as Node3D).add_child(sc)
		sc.owner = root
		for shape in sc.get_children():
			shape.owner = root
		for p in picks:
			var item := ProtonScatterItem.new()
			item.name = "Item_" + String(p[0]).get_file().get_basename().get_basename()
			item.proportion = p[1]
			item.source_scale_multiplier = p[2]
			item.override_cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sc.add_child(item)
			item.owner = root
			item.path = p[0]
		_counts["scatter areas"] = int(_counts.get("scatter areas", 0)) + 1


## Where clutter piles up in a space: a band along every wall of each rect (corners get two bands, so they gather the most), or a ring of
## bands inside a curved wall. The middle of the floor stays free, which is where the fighting is.
func _scatter_strips(space: String) -> Array:
	var out: Array = []
	if L.ROUNDS.has(space):
		var cfg: Dictionary = L.ROUNDS[space]
		var ce: Vector2 = L.world(float((cfg["centre"] as Vector2).x), float((cfg["centre"] as Vector2).y))
		var n: int = int(cfg["segments"]) / 2
		for i in n:
			var ang: float = TAU * (float(i) + 0.5) / float(n)
			var inset: float = 1.9
			var at: Vector2 = ce + Vector2(cos(ang) * (float(cfg["rx"]) - inset), sin(ang) * (float(cfg["ry"]) - inset))
			var tangent: Vector2 = Vector2(-sin(ang) * float(cfg["rx"]), cos(ang) * float(cfg["ry"])).normalized()
			out.append({"centre": at, "size": Vector2(maxf(TAU * minf(float(cfg["rx"]), float(cfg["ry"])) / float(n), 3.0), 2.6),
				"yaw": atan2(-tangent.y, tangent.x)})
		return out
	for rect in L.SPACES[space]["rects"]:
		var a: Vector2 = L.world(int(rect[0]), int(rect[1])) - Vector2(C, C) * 0.5
		var b: Vector2 = L.world(int(rect[2]), int(rect[3])) + Vector2(C, C) * 0.5
		var w: float = b.x - a.x
		var h: float = b.y - a.y
		var band: float = 2.6
		var edge: float = 0.8   # inside the wall's inner face
		if w - 1.6 > 0.5:
			out.append({"centre": Vector2((a.x + b.x) * 0.5, a.y + edge + band * 0.5), "size": Vector2(w - 1.6, band), "yaw": 0.0})
			out.append({"centre": Vector2((a.x + b.x) * 0.5, b.y - edge - band * 0.5), "size": Vector2(w - 1.6, band), "yaw": 0.0})
		if h - 1.6 > 0.5:
			out.append({"centre": Vector2(a.x + edge + band * 0.5, (a.y + b.y) * 0.5), "size": Vector2(band, h - 1.6), "yaw": 0.0})
			out.append({"centre": Vector2(b.x - edge - band * 0.5, (a.y + b.y) * 0.5), "size": Vector2(band, h - 1.6), "yaw": 0.0})
	return out


func _door_in_space(door: Vector2, space: String) -> bool:
	for off in [Vector2(2.1, 0), Vector2(-2.1, 0), Vector2(0, 2.1), Vector2(0, -2.1)]:
		var cell: Vector2i = L.cell_of(door + off)
		if L.space_at(cell.x, cell.y) == space:
			return true
	return false


func _chest_nodes() -> void:
	var i := 0
	for chest in L.CHESTS:
		var node := Chest.new()
		node.position = Vector3(_chests[i].x, 0.0, _chests[i].y)
		var space: String = String(chest["space"])
		var toward: Vector2 = _space_rect_world(space).get_center() - _chests[i]
		node.rotation.y = atan2(toward.x, toward.y)
		node.name = "Node%d" % int(chest["node"]) if chest.has("node") else "Chest_%s" % space
		(_groups["Chests"] as Node3D).add_child(node)
		node.owner = root
		i += 1


func _packs() -> void:
	var made := 0
	for pack in L.PACKS:
		var marker := DungeonEnemyGroup.new()
		var p: Vector2 = L.world((pack["cell"] as Vector2).x, (pack["cell"] as Vector2).y)
		marker.position = Vector3(p.x, 0.0, p.y)
		marker.area = int(pack["stage"])
		marker.behaviour = DungeonEnemyGroup.Behaviour.WANDER if String(pack["mode"]) == "wander" else DungeonEnemyGroup.Behaviour.STAND_GUARD
		marker.kinds = (pack["kinds"] as Array).duplicate(true)
		var members := 0
		for pair in marker.kinds:
			members += int(pair[1])
		marker.spread = clampf(0.9 + 0.3 * float(members), 1.6, 3.0)
		made += 1
		marker.name = "Pack%02d_stage%d_%s" % [made, marker.area, L.space_at(L.cell_of(p).x, L.cell_of(p).y)]
		if pack.has("node"):   # map mode: one marker per node, named for it; a champion pack carries its champion as metadata
			marker.name = "Node%d" % int(pack["node"])
			if not (pack["champion"] as Dictionary).is_empty():
				marker.set_meta(L.CHAMPION_META, pack["champion"])
			if members >= 20:
				marker.spread = 6.0   # a swarm
		(_groups["EnemyGroups"] as Node3D).add_child(marker)
		marker.owner = root
	_counts["packs"] = made


# --- chamfers, curved rooms, gates -----------------------------------------------------------------------------------------------------

const LOW_H := 1.2


## A wall segment between two plan points (world x, z): the kit's wall stretched to fit, with a box to match. A low one (a barrier's height)
## faces the camera, as the square rooms' south walls do.
func _wall_seg(a: Vector2, b: Vector2, height: float, node_name: String = "Seg") -> void:
	var length: float = a.distance_to(b)
	var mid: Vector2 = (a + b) * 0.5
	var holder := StaticBody3D.new()
	holder.collision_layer = Actor.LAYER_WORLD
	holder.position = Vector3(mid.x, 0.0, mid.y)
	holder.rotation.y = atan2(-(b.y - a.y), b.x - a.x)
	holder.add_child(_fitted_scaled(KK % "wall", Vector3(length + 0.15, height, 1.0)))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length + 0.15, height, 1.0)
	cs.shape = box
	cs.position = Vector3(0, height * 0.5, 0)
	holder.add_child(cs)
	_add("Liners", holder, node_name)


func _in_cut(p: Vector2) -> bool:
	for z in _cut_zones:
		if absf(p.x - z.x) + absf(p.y - z.y) < z.z + 1.2:
			return true
	return false


func _cuts() -> void:
	for cut in L.CUTS:
		var rect: Array = L.SPACES[cut[0]]["rects"][0]
		var a: Vector2 = L.world(int(rect[0]), int(rect[1])) - Vector2(C, C) * 0.5
		var b: Vector2 = L.world(int(rect[2]), int(rect[3])) + Vector2(C, C) * 0.5
		var size: float = float(cut[2])
		var corner: String = String(cut[1])
		var v: Vector2 = Vector2(a.x if corner.ends_with("W") else b.x, a.y if corner.begins_with("N") else b.y)
		var u: Vector2 = Vector2(1.0 if corner.ends_with("W") else -1.0, 0.0)
		var w: Vector2 = Vector2(0.0, 1.0 if corner.begins_with("N") else -1.0)
		_cut_zones.append(Vector3(v.x, v.y, size))
		_wall_seg(v + u * size, v + w * size, LOW_H if corner.begins_with("S") else 4.0, "Chamfer")
	_counts["chamfers"] = L.CUTS.size()


func _round_keeps(space: String, c: int, r: int) -> bool:
	var cfg: Dictionary = L.ROUNDS[space]
	var m: Vector2 = L.world(c, r)
	var ce: Vector2 = L.world(float((cfg["centre"] as Vector2).x), float((cfg["centre"] as Vector2).y))
	var dx: float = maxf(absf(m.x - ce.x) - C * 0.5, 0.0)
	var dz: float = maxf(absf(m.y - ce.y) - C * 0.5, 0.0)
	var rx: float = float(cfg["rx"])
	var ry: float = float(cfg["ry"])
	return (dx / rx) * (dx / rx) + (dz / ry) * (dz / ry) < 1.0


## The doorways of a space: [{edge (world x, z), out (unit, pointing out of the space)}].
func _round_doors(space: String) -> Array:
	var out: Array = []
	for r in L.H:
		for c in L.W:
			if L.space_at(c, r) != space:
				continue
			for d in 4:
				var other: String = L.space_at(c + (DIRS[d] as Vector2i).x, r + (DIRS[d] as Vector2i).y)
				if other != "" and other != space:
					out.append({"edge": L.world(c, r) + Vector2(DIRS[d]) * C * 0.5, "out": Vector2(DIRS[d])})
	return out


func _rounds() -> void:
	for space in L.ROUNDS:
		var cfg: Dictionary = L.ROUNDS[space]
		var ce: Vector2 = L.world(float((cfg["centre"] as Vector2).x), float((cfg["centre"] as Vector2).y))
		var rx: float = float(cfg["rx"])
		var ry: float = float(cfg["ry"])
		var n: int = int(cfg["segments"])
		var doors: Array = _round_doors(space)
		var torch_n: int = 0
		var slots: Array = []   # angle ranges [from, to] of the curve that each doorway's stub passage takes out
		for door in doors:
			var out: Vector2 = door["out"]
			var lateral: Vector2 = Vector2(-out.y, out.x)
			var angles: Array = []
			for side in [-1.0, 1.0]:
				var start: Vector2 = (door["edge"] as Vector2) + lateral * side * 2.0
				var t: float = 0.0
				while t < 14.0:
					var q: Vector2 = start - out * t
					if pow((q.x - ce.x) / rx, 2.0) + pow((q.y - ce.y) / ry, 2.0) < 1.0:
						break
					t += 0.1
				var hit: Vector2 = start - out * t
				angles.append(fposmod(atan2((hit.y - ce.y) / ry, (hit.x - ce.x) / rx), TAU))
			var lo: float = minf(angles[0], angles[1])
			var hi: float = maxf(angles[0], angles[1])
			if hi - lo > PI:   # the slot wraps past zero
				slots.append([hi, lo + TAU])
			else:
				slots.append([lo, hi])
		for i in n:
			var pieces: Array = [[TAU * float(i) / n, TAU * float(i + 1) / n]]
			for slot in slots:
				for shift in [-TAU, 0.0, TAU]:
					var cut_lo: float = float(slot[0]) + shift
					var cut_hi: float = float(slot[1]) + shift
					var next: Array = []
					for piece in pieces:
						if cut_hi <= piece[0] or cut_lo >= piece[1]:
							next.append(piece)
							continue
						if cut_lo > piece[0]:
							next.append([piece[0], cut_lo])
						if cut_hi < piece[1]:
							next.append([cut_hi, piece[1]])
					pieces = next
			for piece in pieces:
				if float(piece[1]) - float(piece[0]) < 0.03:
					continue
				var p0: Vector2 = ce + Vector2(cos(float(piece[0])) * rx, sin(float(piece[0])) * ry)
				var p1: Vector2 = ce + Vector2(cos(float(piece[1])) * rx, sin(float(piece[1])) * ry)
				var mid: Vector2 = (p0 + p1) * 0.5
				var normal: Vector2 = Vector2((mid.x - ce.x) / (rx * rx), (mid.y - ce.y) / (ry * ry)).normalized()
				var low: bool = normal.y > 0.35
				_wall_seg(p0, p1, LOW_H if low else 4.0, "Curve")
				if not low and float(piece[1]) - float(piece[0]) > TAU / float(n) * 0.9:
					torch_n += 1
					if torch_n % (4 if space == "rotunda" else 6) == 2:
						_torch_at(mid - normal * 0.55, -normal)
		for door in doors:
			var out: Vector2 = door["out"]
			var lateral: Vector2 = Vector2(-out.y, out.x)
			var edge: Vector2 = door["edge"]
			var hits: Array[Vector2] = []
			for side in [-1.0, 0.0, 1.0]:
				var start: Vector2 = edge + lateral * side * 2.0
				var t: float = 0.0
				while t < 14.0:
					var q: Vector2 = start - out * t
					if pow((q.x - ce.x) / rx, 2.0) + pow((q.y - ce.y) / ry, 2.0) < 1.0:
						break
					t += 0.1
				hits.append(start - out * t)
				if side != 0.0 and t > 0.3:
					_wall_seg(start, start - out * t, LOW_H if out.y > 0.5 else 4.0, "Stub")
			_arch(hits[1], PI * 0.5 if absf(out.x) > 0.5 else 0.0, space == "arena" and out.y > 0.5)
		_counts["curve walls %s" % space] = n


## A stone arch in a curved room's doorway, with jamb boxes; the gate has an iron grille raised in its head.
func _arch(p: Vector2, yaw: float, gate: bool) -> void:
	var holder := StaticBody3D.new()
	holder.collision_layer = Actor.LAYER_WORLD
	holder.position = Vector3(p.x, 0.0, p.y)
	holder.rotation.y = yaw
	holder.add_child(_fitted_scaled(Q1 % "Arch", Vector3(4.1, 4.0, 1.0)))
	for side in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.9, 4.0, 1.0)
		cs.shape = box
		cs.position = Vector3(side * 1.62, 2.0, 0.0)
		holder.add_child(cs)
	if gate:
		var bars := _fitted_scaled(Q1 % "Arch_bars", Vector3(2.5, 2.2, 0.06))
		bars.position.y += 2.0
		holder.add_child(bars)
	_add("Liners", holder, "Arch")


# --- the rooms' character ---------------------------------------------------------------------------------------------------------------

func _brazier(p: Vector2, node_name: String = "Brazier") -> void:
	var holder := _solid("SetPieces", KK % "column", p, 0.0, 1.15, 0.6, node_name)
	var fire := _fitted(Q1 % "Woodfire", 0.75)
	fire.position.y += 1.15
	holder.add_child(fire)
	_own(fire)
	_flame(holder, Vector3(0, 2.1, 0), 4.2, 11.0, true, "brazier")
	holder.get_node("FlameLight").owner = root
	holder.get_node("FlameLight/Flicker").owner = root


func _bone_pile(p: Vector2, node_name: String = "BonePile") -> void:
	var holder := Node3D.new()
	holder.position = Vector3(p.x, 0.0, p.y)
	var models: Array = [Q2 % "Bones", Q2 % "Bones2", Q1 % "Skull", Q2 % "Bones2", Q1 % "Skull", Q2 % "Bones"]
	for i in models.size():
		var piece := _fitted(String(models[i]), 0.0)
		piece.scale = Vector3.ONE * rng.randf_range(0.5, 0.8)
		piece.position = Vector3(rng.randf_range(-0.7, 0.7), 0.1 * float(i % 3), rng.randf_range(-0.7, 0.7))
		piece.rotation.y = rng.randf() * TAU
		holder.add_child(piece)
	_add("Decor", holder, node_name)


func _rubble(p: Vector2, yaw: float, height: float = 1.4) -> void:
	_solid("SetPieces", KK % "rubble_half", p, yaw, height, height * 0.65, "RubblePile")


func _fallen_pillar(p: Vector2, yaw: float) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(p.x, 0.0, p.y)
	holder.rotation.y = yaw
	holder.set_meta("obstacle_radius", 1.3)
	var inner := Node3D.new()
	inner.rotation.z = PI * 0.5
	inner.position = Vector3(2.0, 0.75, 0.0)
	inner.add_child(_fitted(KK % "pillar", 4.0))
	holder.add_child(inner)
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.5, 1.5)
	holder.add_child(_body(box, Vector3(0, 0.75, 0)))
	_add("SetPieces", holder, "FallenPillar")
	_remember(p, 2.2)


func _pit(p: Vector2, well: bool = false) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(p.x, 0.0, p.y)
	holder.set_meta("obstacle_radius", 1.6)
	var hole := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.25
	disc.bottom_radius = 1.25
	disc.height = 0.02
	hole.mesh = disc
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.05, 0.07) if well else Color(0.0, 0.0, 0.0)
	dark.roughness = 0.03 if well else 1.0
	hole.material_override = dark
	hole.position.y = 0.45 if well else 0.03
	holder.add_child(hole)
	var rim := MeshInstance3D.new()
	if well:
		var tube := CylinderMesh.new()
		tube.top_radius = 1.5
		tube.bottom_radius = 1.6
		tube.height = 0.7
		rim.mesh = tube
		rim.position.y = 0.3
		# a tube is solid, so open it: sink the water above the curb's top is not wanted; the water sits on top of the curb instead
		hole.position.y = 0.66
	else:
		var ring := TorusMesh.new()
		ring.inner_radius = 1.15
		ring.outer_radius = 1.65
		rim.mesh = ring
		rim.scale = Vector3(1, 0.5, 1)
		rim.position.y = 0.1
	rim.material_override = _stone
	holder.add_child(rim)
	holder.add_child(_body(_cylinder(1.5, 1.0), Vector3(0, 0.5, 0)))
	_add("SetPieces", holder, "Well" if well else "Pit")
	_remember(p, 1.9)


func _urns(p: Vector2, count: int) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(p.x, 0.0, p.y)
	for i in count:
		var urn := _fitted(URN if i % 2 == 0 else Q1 % "Vase", rng.randf_range(0.6, 0.95) if i % 2 == 0 else 0.55)
		urn.position += Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		holder.add_child(urn)
	_add("Decor", holder, "Pottery")


func _candles(p: Vector2, height: float, node_name: String = "Candles") -> void:
	var holder := Node3D.new()
	holder.position = Vector3(p.x, height, p.y)
	var candle := _model(KK % "candle_triple")
	candle.scale = Vector3.ONE * 1.3
	holder.add_child(candle)
	_flame(holder, Vector3(0, 0.9, 0), 0.9, 4.5, false, "candle")
	_add("Decor", holder, node_name)


## Cobwebs in the floor corners of every room and alcove, turned into the corner.
func _cobwebs() -> void:
	var webs: Array = [Q1 % "Cobweb", Q1 % "Cobweb2"]
	for space in L.SPACES:
		if String(L.SPACES[space]["kind"]) == "corridor" or L.ROUNDS.has(space):
			continue
		for rect in L.SPACES[space]["rects"]:
			var a: Vector2 = L.world(int(rect[0]), int(rect[1])) - Vector2(C, C) * 0.5
			var b: Vector2 = L.world(int(rect[2]), int(rect[3])) + Vector2(C, C) * 0.5
			for corner in [Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(a.x, b.y), Vector2(b.x, b.y)]:
				var into: Vector2 = Vector2(1.0 if corner.x == a.x else -1.0, 1.0 if corner.y == a.y else -1.0)
				var at: Vector2 = corner + into * 1.0
				var cell: Vector2i = L.cell_of(corner + into * 0.5)
				if L.space_at(cell.x, cell.y) != space or _in_cut(at) or rng.randf() < 0.25:
					continue
				var web := _fitted(String(webs[rng.randi() % 2]), 0.0)
				web.scale = Vector3.ONE * 1.5
				var holder := Node3D.new()
				holder.position = Vector3(at.x, 0.05, at.y)
				holder.rotation.y = atan2(-into.x, -into.y)
				holder.add_child(web)
				_add("Decor", holder, "Cobweb")


## Puddles and moss: flat discs laid along the walls (the scatter takes only a mesh, and these came out black), kept off doorways.
func _puddles() -> void:
	var wet := StandardMaterial3D.new()
	wet.albedo_color = Color(0.05, 0.08, 0.12)
	wet.roughness = 0.12
	var moss := StandardMaterial3D.new()
	moss.albedo_color = Color(0.1, 0.16, 0.06)
	moss.roughness = 1.0
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.01
	disc.radial_segments = 14
	disc.rings = 1
	for space in L.SPACES:
		var strips: Array = _scatter_strips(space)
		var corridor: bool = String(L.SPACES[space]["kind"]) == "corridor"
		var wanted: int = 3 if corridor else 4 + strips.size()
		var made: int = 0
		var tries: int = 0
		while made < wanted and tries < wanted * 20 and not strips.is_empty():
			tries += 1
			var strip: Dictionary = strips[rng.randi() % strips.size()]
			var size: Vector2 = strip["size"]
			var local := Vector2(rng.randf_range(-0.5, 0.5) * size.x, rng.randf_range(-0.5, 0.5) * size.y).rotated(-float(strip["yaw"]))
			var p: Vector2 = (strip["centre"] as Vector2) + local
			if _near_door(p, 3.0) or _in_cut(p):
				continue
			var water: bool = made % 3 == 0
			var mi := MeshInstance3D.new()
			mi.mesh = disc
			mi.material_override = wet if water else moss
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.scale = Vector3(rng.randf_range(0.8, 1.6), 1.0, rng.randf_range(0.7, 1.3)) * (1.0 if water else 1.5)
			mi.position = Vector3(p.x, 0.03 if water else 0.02, p.y)
			mi.rotation.y = rng.randf() * TAU
			_add("Decor", mi, "Puddle" if water else "Moss")
			made += 1


func _dress() -> void:
	# Braziers: the pools of light in the middle of the rooms, between the torches' pools.
	for cell in [Vector2(25.2, 54.3), Vector2(12, 47.6), Vector2(24.5, 45.4), Vector2(29.5, 47.5), Vector2(5.4, 34.4), Vector2(13.6, 39.6),
			Vector2(25.6, 34.1), Vector2(25.5, 38.8), Vector2(26, 17.4), Vector2(28.7, 17.4), Vector2(14.5, 11.9), Vector2(17.5, 11.9),
			Vector2(12, 14), Vector2(20, 14), Vector2(5.2, 25.4), Vector2(8.7, 22.6), Vector2(13.4, 6.9), Vector2(18.6, 6.9)]:
		_brazier(L.world(cell.x, cell.y))
	var rc: Vector2 = L.world(16, 24)
	for deg in [83.0, 155.0, 225.0, 320.0]:   # the four doors are at about 38, 128, 180 and 270 degrees: keep clear of them
		var a: float = deg_to_rad(deg)
		_brazier(rc + Vector2(cos(a), sin(a)) * 10.4, "RotundaBrazier")
	var ac: Vector2 = L.world(16, 3.5)
	for deg in [12.0, 35.0, 145.0, 168.0, 192.0, 215.0, 325.0, 348.0]:
		var a: float = deg_to_rad(deg)
		_brazier(ac + Vector2(cos(a) * 26.0, sin(a) * 9.6), "ArenaBrazier")
	# Alcoves: each holds one thing.
	var alcoves: Array = [
		[14, 44, "sarc", 0.0], [20, 44, "rubble"], [24, 44, "bones"], [12, 49, "urns"], [17, 49, "bones"], [22, 49, "rubble"],
		[6, 32, "sarc", 0.0], [10, 32, "candles"], [6, 41, "bones"], [13, 41, "rubble"],
		[24, 32, "bones"], [19, 40, "pit"], [23, 40, "bones"], [27, 35, "sarc", PI * 0.5], [27, 37, "urns"],
		[20, 19, "urns"], [12, 19, "rubble"], [13, 9, "sarc", 0.0], [19, 9, "sarc", 0.0],
	]
	for al in alcoves:
		var p: Vector2 = L.world(al[0], al[1])
		match String(al[2]):
			"sarc":
				_sarcophagus(p, float(al[3]), "Alcove")
			"rubble":
				_rubble(p, rng.randf() * TAU)
			"bones":
				_bone_pile(p)
			"urns":
				_urns(p, 4)
			"candles":
				_candles(p, 0.0)
			"pit":
				_pit(p)
	# Room pieces.
	_pit(L.world(29.2, 54.3), true)
	_fallen_pillar(L.world(19.5, 48.2) + Vector2(-2.0, 0.0), 0.0)
	_fallen_pillar(L.world(8.3, 39.4) + Vector2(0.5, 0.0), 0.0)
	_rubble(L.world(9.4, 33.6), 0.7, 1.3)
	_rubble(L.world(25.8, 39.4), 2.1, 1.3)
	_rubble(L.world(3.6, 44.7), 0.4, 1.2)
	_rubble(L.world(18.6, 33.7), 1.0, 1.2)
	_bone_pile(L.world(21.5, 35.9))
	_bone_pile(L.world(23.8, 35.9))
	_bone_pile(L.world(19.4, 38.7))
	_bone_pile(L.world(1.4, 34.4))
	_bone_pile(L.world(1.5, 38.2))
	_candles(L.world(5.4, 22.7), 0.0)
	_candles(L.world(29.0, 14.5), 0.0)
	_candles(L.world(7.0, 24.0), 1.1, "TableCandles")
	_urns(L.world(0.7, 38.0), 3)
	_urns(L.world(9.2, 26.2), 3)
	_urns(L.world(29.0, 18.2), 3)
	_fallen_pillar(L.world(12.2, 7.6), 0.3)
	_fallen_pillar(L.world(19.0, 0.9), -0.2)
	_bone_pile(L.world(9.6, 0.9))
	_bone_pile(L.world(22.6, 6.4))
	_bone_pile(L.world(10.4, 6.6))
	_rubble(L.world(23.0, 1.0), 0.5, 1.5)
	_rubble(L.world(9.0, 4.0), 1.1, 1.5)
	_cobwebs()
	_puddles()


# --- Flat floor detail (Lane S3) ---------------------------------------------------------------------------------------------------------

## Low, flat marks across the middle of the rooms (cracks, grime, blood, scattered bones, floor grates, faint rune circles). Plain meshes with
## no collider, at most 7 cm high, so nothing blocks the hero or the navigation; a separate generator keeps the rest of the scene as it was.
const DETAIL_KINDS := ["crack", "crack", "crack", "grime", "grime", "grime", "blood", "bones", "bones", "grate"]


func _floor_detail() -> void:
	var detail_rng := RandomNumberGenerator.new()
	detail_rng.seed = 4411
	var dark := _flat_material(Color(0.04, 0.035, 0.035), 0.55)
	var grime_mat := _flat_material(Color(0.07, 0.055, 0.045), 0.5)
	var blood_mat := _flat_material(Color(0.2, 0.025, 0.02), 0.75)
	var bone_mat := _flat_material(Color(0.62, 0.58, 0.48), 1.0)
	var iron := _flat_material(Color(0.06, 0.06, 0.07), 1.0)
	var rune_mat := _flat_material(Color(0.05, 0.03, 0.02), 1.0)
	rune_mat.emission_enabled = true
	rune_mat.emission = Color(0.9, 0.5, 0.2)
	rune_mat.emission_energy_multiplier = 0.45
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.01
	disc.radial_segments = 16
	disc.rings = 1
	var slab := BoxMesh.new()
	slab.size = Vector3(1.0, 0.012, 1.0)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.93
	ring.outer_radius = 1.0
	ring.rings = 28
	ring.ring_segments = 4
	var bone := CylinderMesh.new()
	bone.top_radius = 0.035
	bone.bottom_radius = 0.035
	bone.height = 0.55
	bone.radial_segments = 5
	bone.rings = 1
	for space in L.SPACES:
		var kind: String = String(L.SPACES[space]["kind"])
		if kind == "corridor":
			continue
		var region: Dictionary = _detail_region(space, kind)
		var wanted: int = clampi(int(float(region["area"]) / 26.0), 3, 14)
		var made: int = 0
		var tries: int = 0
		var runes: int = 0
		while made < wanted and tries < wanted * 30:
			tries += 1
			var p: Vector2 = _detail_point(region, detail_rng)
			if _near_door(p, 3.5) or _in_cut(p) or not _spot_free(p, 0.5):
				continue
			var what: String = String(DETAIL_KINDS[detail_rng.randi() % DETAIL_KINDS.size()])
			if made == 0 and (kind == "round" or kind == "room") and runes == 0:
				what = "rune"
			var node := Node3D.new()
			node.position = Vector3(p.x, 0.0, p.y)
			node.rotation.y = detail_rng.randf() * TAU
			node.set_meta("floor_detail", what)
			match what:
				"crack":   # three thin dark strips in a zigzag
					var at := Vector3.ZERO
					for i in 3:
						var seg_len: float = detail_rng.randf_range(0.5, 0.9)
						var heading: float = detail_rng.randf_range(-0.7, 0.7)
						var seg := _flat_mesh(slab, dark, Vector3(seg_len, 1.0, 0.05), at + Vector3(cos(heading), 0.0, sin(heading)) * seg_len * 0.5 + Vector3(0, 0.022, 0), -heading)
						node.add_child(seg)
						at += Vector3(cos(heading), 0.0, sin(heading)) * seg_len
				"grime":
					node.add_child(_flat_mesh(disc, grime_mat, Vector3(detail_rng.randf_range(1.3, 2.4), 1.0, detail_rng.randf_range(1.0, 1.9)), Vector3(0, 0.018, 0), 0.0))
				"blood":
					node.add_child(_flat_mesh(disc, blood_mat, Vector3(1.0, 1.0, 0.8), Vector3(0, 0.024, 0), 0.0))
					for i in 3:
						node.add_child(_flat_mesh(disc, blood_mat, Vector3.ONE * detail_rng.randf_range(0.15, 0.35), Vector3(detail_rng.randf_range(-0.9, 0.9), 0.026, detail_rng.randf_range(-0.9, 0.9)), 0.0))
				"bones":
					for i in 4:
						var b := MeshInstance3D.new()
						b.mesh = bone
						b.material_override = bone_mat
						b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						b.rotation = Vector3(0.0, detail_rng.randf() * TAU, PI * 0.5)
						b.position = Vector3(detail_rng.randf_range(-0.5, 0.5), 0.04, detail_rng.randf_range(-0.5, 0.5))
						node.add_child(b)
				"grate":
					node.add_child(_flat_mesh(slab, dark, Vector3(1.1, 1.0, 1.1), Vector3(0, 0.02, 0), 0.0))
					for i in 5:
						node.add_child(_flat_mesh(slab, iron, Vector3(1.0, 2.5, 0.07), Vector3(0, 0.03, -0.42 + 0.21 * i), 0.0))
				"rune":
					runes += 1
					node.add_child(_flat_mesh(ring, rune_mat, Vector3(1.4, 0.02, 1.4), Vector3(0, 0.03, 0), 0.0))
					node.add_child(_flat_mesh(ring, rune_mat, Vector3(0.9, 0.02, 0.9), Vector3(0, 0.03, 0), 0.0))
					for i in 4:
						node.add_child(_flat_mesh(slab, rune_mat, Vector3(1.9, 1.5, 0.05), Vector3(0, 0.03, 0), PI * 0.25 * i))
			_add("Decor", node, "FloorDetail")
			made += 1


func _flat_material(colour: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	return m


func _flat_mesh(mesh: Mesh, mat: Material, scale: Vector3, at: Vector3, yaw: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 45.0
	mi.scale = scale
	mi.position = at
	mi.rotation.y = yaw
	return mi


## The middle of a room: its first rectangle pulled in by a cell (an ellipse scaled down for the round rooms). {rect | ellipse, area}.
func _detail_region(space: String, kind: String) -> Dictionary:
	if L.ROUNDS.has(space):
		var cfg: Dictionary = L.ROUNDS[space]
		var ce: Vector2 = L.world(float((cfg["centre"] as Vector2).x), float((cfg["centre"] as Vector2).y))
		var radii := Vector2(float(cfg["rx"]), float(cfg["ry"])) * 0.62
		return {"ellipse": ce, "radii": radii, "area": PI * radii.x * radii.y}
	var rect: Rect2 = _space_rect_world(space)
	var inset: float = C * (0.5 if kind == "side" else 1.0)
	rect = rect.grow_individual(-inset, -inset, -inset, -inset)
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		rect = _space_rect_world(space).grow(-C * 0.5)
	return {"rect": rect, "area": rect.get_area()}


func _detail_point(region: Dictionary, detail_rng: RandomNumberGenerator) -> Vector2:
	if region.has("ellipse"):
		var radii: Vector2 = region["radii"]
		var ang: float = detail_rng.randf() * TAU
		var r: float = sqrt(detail_rng.randf())
		return (region["ellipse"] as Vector2) + Vector2(cos(ang) * radii.x, sin(ang) * radii.y) * r
	var rect: Rect2 = region["rect"]
	return rect.position + Vector2(detail_rng.randf() * rect.size.x, detail_rng.randf() * rect.size.y)
