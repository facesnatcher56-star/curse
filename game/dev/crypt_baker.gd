class_name CryptBaker
extends RefCounted
## Writes the Crypt scene (`game/world/dungeons/crypt_01.tscn`) from the plan in CryptLayout. Developer tool: the game never runs this.
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
const C := CryptLayout.CELL

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # north, east, south, west
const DIR_NAMES := ["N", "E", "S", "W"]
const DIR_YAW := [0.0, 270.0, 180.0, 90.0]    # the GridMap rotation that puts a wall on that edge (the piece sits on the -z edge at 0 degrees)

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


func build() -> int:
	rng.seed = 7301
	lib = load(LIB)
	_stone = StandardMaterial3D.new()
	_stone.albedo_color = Color(0.5, 0.52, 0.6)
	_stone.roughness = 0.9
	root = Node3D.new()
	root.name = "Crypt01"
	for group_name in ["Floor", "Walls", "Pillars", "Props", "SetPieces", "Decor", "Torches", "Scatter", "Chests", "EnemyGroups"]:
		var group := Node3D.new()
		group.name = group_name
		root.add_child(group)
		group.owner = root
		_groups[group_name] = group
	_floor()
	_walls()
	_corner_posts()
	for chest in CryptLayout.CHESTS:
		var spot: Vector2 = CryptLayout.world(float(chest["cell"].x), float(chest["cell"].y))
		_chests.append(spot)
	_set_pieces()
	_props()
	_torches()
	_scatter()
	_chest_nodes()
	_packs()
	var start := Marker3D.new()
	start.name = "PlayerStart"
	var s: Vector2 = CryptLayout.world(CryptLayout.START_CELL.x, CryptLayout.START_CELL.y)
	start.position = Vector3(s.x, 0.0, s.y)
	root.add_child(start)
	start.owner = root
	var packed := PackedScene.new()
	var error: int = packed.pack(root)
	if error != OK:
		return error
	error = ResourceSaver.save(packed, OUT)
	print("CRYPT_BAKE %s: %s (error %d)" % [OUT, str(_counts), error])
	return error


# --- helpers ---------------------------------------------------------------------------------------------------------------------------

func _grid(parent: String, node_name: String) -> GridMap:
	var g := GridMap.new()
	g.name = node_name
	g.mesh_library = lib
	g.cell_size = Vector3(C, C, C)
	g.cell_center_y = false
	g.position = Vector3(-float(CryptLayout.W) * C * 0.5, 0.0, -float(CryptLayout.H) * C * 0.5)
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


func _flame(parent: Node3D, at: Vector3, energy: float, range_m: float, shadow: bool = false) -> void:
	var light := OmniLight3D.new()
	light.name = "FlameLight"
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
	for r in CryptLayout.H:
		for c in CryptLayout.W:
			var space: String = CryptLayout.space_at(c, r)
			if space == "":
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
	var half: int = lib.find_item_by_name("barrier")
	var door: int = lib.find_item_by_name("wall_doorway")
	var n_wall := 0
	var n_door := 0
	for r in CryptLayout.H:
		for c in CryptLayout.W:
			var space: String = CryptLayout.space_at(c, r)
			if space == "":
				continue
			for d in 4:
				var nc: int = c + (DIRS[d] as Vector2i).x
				var nr: int = r + (DIRS[d] as Vector2i).y
				var other: String = CryptLayout.space_at(nc, nr)
				if other == space:
					continue
				var centre: Vector2 = CryptLayout.world(c, r)
				var edge: Vector2 = centre + Vector2(DIRS[d]) * C * 0.5
				if other != "":
					if space > other:
						continue   # the other side places the doorway
					grids[d].set_cell_item(Vector3i(c, 0, r), door, rot[d])
					_doors.append(edge)
					n_door += 1
					continue
				var item: int = wall
				var roll: float = rng.randf()
				if d == 2:
					item = half   # the camera looks north: the wall on a room's south edge is a low barrier, so the room stays in view
				elif roll < 0.14:
					item = cracked
				elif roll < 0.2 and CryptLayout.SPACES[space]["kind"] in ["side", "hall"]:
					item = shelves
				grids[d].set_cell_item(Vector3i(c, 0, r), item, rot[d])
				n_wall += 1
				_wall_cells.append({"space": space, "dir": d, "edge": edge, "inward": -Vector2(DIRS[d]), "item": item == half})
	_counts["walls"] = n_wall
	_counts["doorways"] = n_door


## A pillar post on every wall corner, T and end (a straight run needs none), so wall ends and door jambs read as built, not cut.
func _corner_posts() -> void:
	var post: PackedScene = load(KK % "pillar")
	var n := 0
	for vr in range(0, CryptLayout.H + 1):
		for vc in range(0, CryptLayout.W + 1):
			var around: Array[String] = [CryptLayout.space_at(vc - 1, vr - 1), CryptLayout.space_at(vc, vr - 1),
				CryptLayout.space_at(vc, vr), CryptLayout.space_at(vc - 1, vr)]   # NW, NE, SE, SW
			var north: bool = around[0] != around[1]
			var east: bool = around[1] != around[2]
			var south: bool = around[2] != around[3]
			var west: bool = around[3] != around[0]
			var count: int = int(north) + int(east) + int(south) + int(west)
			if count == 0 or (count == 2 and ((north and south) or (east and west))):
				continue
			var holder := Node3D.new()
			holder.position = Vector3((float(vc) - float(CryptLayout.W) * 0.5) * C, 0.0, (float(vr) - float(CryptLayout.H) * 0.5) * C)
			holder.add_child(post.instantiate())
			_add("Pillars", holder, "Post")
			n += 1
	_counts["wall posts"] = n


# --- set pieces and props -----------------------------------------------------------------------------------------------------------------

func _space_rect_world(space: String) -> Rect2:
	var rect: Array = CryptLayout.SPACES[space]["rects"][0]
	var a: Vector2 = CryptLayout.world(int(rect[0]), int(rect[1])) - Vector2(C, C) * 0.5
	var b: Vector2 = CryptLayout.world(int(rect[2]), int(rect[3])) + Vector2(C, C) * 0.5
	return Rect2(a, b - a)


func _sarcophagus(p: Vector2, yaw: float, name_suffix: String) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(p.x, 0.0, p.y)
	holder.rotation.y = yaw
	holder.set_meta("obstacle_radius", 1.3)
	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(2.5, 0.75, 1.15)
	base.mesh = base_mesh
	base.material_override = _stone
	base.position.y = 0.375
	holder.add_child(base)
	var lid := MeshInstance3D.new()
	lid.name = "Lid"
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(2.3, 0.3, 0.95)
	lid.mesh = lid_mesh
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.58, 0.6, 0.68)
	lid_mat.roughness = 0.85
	lid.material_override = lid_mat
	lid.position = Vector3(0.0, 0.9, 0.0)
	lid.rotation.y = deg_to_rad(rng.randf_range(-4.0, 4.0))
	holder.add_child(lid)
	var ridge := MeshInstance3D.new()
	ridge.name = "Ridge"
	var ridge_mesh := BoxMesh.new()
	ridge_mesh.size = Vector3(1.7, 0.14, 0.34)
	ridge.mesh = ridge_mesh
	ridge.material_override = lid_mat
	ridge.position = Vector3(0.0, 1.1, 0.0)
	holder.add_child(ridge)
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
	_flame(holder, Vector3(0, height + 0.9, 0), 1.6, 7.0)
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
			var p := Vector2((float(vc) - float(CryptLayout.W) * 0.5) * C, (float(vr) - float(CryptLayout.H) * 0.5) * C)
			var broken: bool = (vr == 38 and vc == 10)
			_solid("SetPieces", Q2 % "Column_Broken" if broken else KK % "pillar_decorated", p, 0.0, 2.6 if broken else 4.0, 0.75, "CryptPillar")
	_sarcophagus(CryptLayout.world(5.2, 34.2) + Vector2(0, 0), 0.0, "A")
	_sarcophagus(CryptLayout.world(5.2, 39.0), PI, "B")
	# Long hall: a broken pillar every few cells along the north wall, banners above, a sarcophagus at the west end.
	for c in [26, 22, 18, 14, 11]:
		var p := CryptLayout.world(c, 45) + Vector2(rng.randf_range(-0.4, 0.4), 0.9)
		_solid("SetPieces", Q2 % ("Column_Broken" if c % 2 == 0 else "Column_Broken2"), p, rng.randf() * TAU, 2.4, 0.6, "BrokenPillar")
	_sarcophagus(CryptLayout.world(10, 47) + Vector2(0, 0.6), PI * 0.5, "C")
	# Ossuary: two rows of sarcophagi with bones between them.
	for i in 3:
		_sarcophagus(CryptLayout.world(20.2 + float(i) * 2.3, 34.7), 0.0, "O%d" % i)
		_sarcophagus(CryptLayout.world(20.2 + float(i) * 2.3, 37.9), PI, "P%d" % i)
	# Rotunda: the altar in the middle, eight pillars round it.
	var centre: Vector2 = CryptLayout.world(16, 24)
	_altar(centre, "RotundaAltar", 1.4)
	_ring(centre, 8.5, 8, 22.5, KK % "pillar_decorated", 4.0, "RotundaPillar")
	# Vault (side): a long table with candles and shelves; shrine (side): an altar and a statue; bone closet: a sarcophagus.
	_solid("SetPieces", KK % "table_long_decorated_A", CryptLayout.world(7, 24) + Vector2(0, 0), PI * 0.5, 1.1, 1.0, "VaultTable", Vector3(2.4, 1.1, 1.0))
	_solid("SetPieces", KK % "shelf_large", CryptLayout.world(4.4, 22.6) + Vector2(-0.4, 0.0), PI * 0.5, 2.6, 0.9, "VaultShelf", Vector3(1.0, 2.0, 2.4))
	_altar(CryptLayout.world(27, 16), "ShrineAltar", 1.2)
	_solid("SetPieces", Q1 % "Statue_Horse", CryptLayout.world(27, 14.4), PI, 2.8, 1.0, "ShrineStatue")
	_sarcophagus(CryptLayout.world(1, 34.7), 0.0, "D")
	# Guard hall: two pairs of pillars and a statue at each end.
	for vc in [14, 18]:
		for vr in [16, 18]:
			var p := Vector2((float(vc) - float(CryptLayout.W) * 0.5) * C, (float(vr) - float(CryptLayout.H) * 0.5) * C)
			_solid("SetPieces", KK % "pillar", p, 0.0, 4.0, 0.7, "GuardPillar")
	_solid("SetPieces", Q1 % "Statue_Horse", CryptLayout.world(12, 15.6), PI * 0.5, 2.6, 1.0, "GuardStatue")
	_solid("SetPieces", Q1 % "Statue_Horse", CryptLayout.world(20, 15.6), -PI * 0.5, 2.6, 1.0, "GuardStatue")
	# Antechamber: sarcophagi against the side walls, an altar between them.
	_sarcophagus(CryptLayout.world(13.0, 11.0), PI * 0.5, "E")
	_sarcophagus(CryptLayout.world(19.0, 11.0), PI * 0.5, "F")
	# The arena: six great pillars in two rows and a broken altar in the middle.
	for vc in [11, 14, 18, 21]:
		for vr in [2, 6]:
			var p := Vector2((float(vc) - float(CryptLayout.W) * 0.5) * C, (float(vr) - float(CryptLayout.H) * 0.5) * C)
			_solid("SetPieces", KK % "pillar_decorated", p, 0.0, 4.0, 0.75, "ArenaPillar")
	_altar(CryptLayout.world(16, 3.5) + Vector2(0, 0), "WardenAltar", 1.0)


func _props() -> void:
	var models: Array = [
		["barrel", KK % "barrel_large", 1.2, 0.55],
		["barrel", KK % "barrel_small_stack", 0.9, 0.55],
		["crate", KK % "crates_stacked", 1.3, 0.75],
		["crate", KK % "box_large", 0.9, 0.55],
		["barrel", KK % "keg", 0.9, 0.5],
		["urn", URN, 0.9, 0.45],
	]
	var targets := {"vestibule": 7, "long_hall": 9, "pillared_crypt": 6, "ossuary": 5, "rotunda": 3, "guard_hall": 6, "antechamber": 4, "arena": 5,
		"vault": 4, "shrine": 3, "bone_closet": 3}   # corridors stay clear: a barrel in a 4 m passage closes the navigation mesh
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
			if _near_door(p, 3.6) or not _spot_free(p, float(pick[3])) or _near_pack(p) or _near_chest(p):
				continue
			_breakable(String(pick[0]), String(pick[1]), p, rng.randf() * TAU, float(pick[2]), float(pick[3]))
			made += 1
	_counts["breakables"] = _counts.get("Props", 0)


func _near_pack(p: Vector2) -> bool:
	for pack in CryptLayout.PACKS:
		if p.distance_to(CryptLayout.world((pack["cell"] as Vector2).x, (pack["cell"] as Vector2).y)) < 3.6:
			return true
	return false


func _near_chest(p: Vector2) -> bool:
	for c in _chests:
		if p.distance_to(c) < 3.2:
			return true
	return false


func _torches() -> void:
	var counters: Dictionary = {}
	for w in _wall_cells:
		if int(w["dir"]) == 2:
			continue   # a low wall carries no torch
		var key: String = "%s/%d" % [w["space"], int(w["dir"])]
		var n: int = int(counters.get(key, 0))
		counters[key] = n + 1
		var kind: String = String(CryptLayout.SPACES[w["space"]]["kind"])
		var step: int = 2 if kind == "corridor" else 3
		if n % step != 1:
			continue
		var edge: Vector2 = w["edge"]
		var inward: Vector2 = w["inward"]
		if _near_door(edge, 2.6):
			continue
		var holder := Node3D.new()
		var pos: Vector2 = edge + inward * 0.5
		holder.position = Vector3(pos.x, 2.1, pos.y)
		holder.rotation.y = atan2(inward.x, inward.y)   # local +z points into the room
		holder.add_child(_model(KK % "torch_mounted"))
		_flame(holder, Vector3(0, 0.9, 0.5), 2.4, 9.0, false)
		_add("Torches", holder, "Torch")


func _scatter() -> void:
	var picks: Array = [[Q2 % "Bones2", 30, 1.0], [KK % "candle_melted", 12, 1.0],
		[Q1 % "Skull", 16, 1.0], [Q2 % "Bones", 22, 1.0], [Q1 % "Brick", 12, 1.0]]
	for space in CryptLayout.SPACES:
		var kind: String = String(CryptLayout.SPACES[space]["kind"])
		var area: float = 0.0
		var sc := ProtonScatter.new()
		sc.global_seed = 100 + absi(int(hash(space) % 1000))
		sc.show_output_in_tree = false
		for rect in CryptLayout.SPACES[space]["rects"]:
			var a: Vector2 = CryptLayout.world(int(rect[0]), int(rect[1])) - Vector2(C, C) * 0.5
			var b: Vector2 = CryptLayout.world(int(rect[2]), int(rect[3])) + Vector2(C, C) * 0.5
			var size: Vector2 = b - a - Vector2(2.2, 2.2)
			if size.x < 0.5 or size.y < 0.5:
				size = (b - a) * 0.6
			area += size.x * size.y
			var shape := ProtonScatterShape.new()
			shape.name = "Area%d" % int(shape.get_instance_id() % 100000)
			var box := ProtonScatterBoxShape.new()
			box.size = Vector3(size.x, 0.2, size.y)
			shape.shape = box
			shape.position = Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
			sc.add_child(shape)
		var density: float = 1.0 / (22.0 if kind in ["corridor"] else 13.0)
		var stack := ProtonScatterModifierStack.new()
		var create = load(SCATTER_MOD % "create_inside_random").new()
		create.amount = clampi(int(area * density * 1.4), 3, 80)
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
			sc.add_child(item)
			item.owner = root
			item.path = p[0]
		_counts["scatter areas"] = int(_counts.get("scatter areas", 0)) + 1


func _chest_nodes() -> void:
	var i := 0
	for chest in CryptLayout.CHESTS:
		var node := Chest.new()
		node.position = Vector3(_chests[i].x, 0.0, _chests[i].y)
		var space: String = String(chest["space"])
		var toward: Vector2 = _space_rect_world(space).get_center() - _chests[i]
		node.rotation.y = atan2(toward.x, toward.y)
		node.name = "Chest_%s" % space
		(_groups["Chests"] as Node3D).add_child(node)
		node.owner = root
		i += 1


func _packs() -> void:
	var made := 0
	for pack in CryptLayout.PACKS:
		var marker := DungeonEnemyGroup.new()
		var p: Vector2 = CryptLayout.world((pack["cell"] as Vector2).x, (pack["cell"] as Vector2).y)
		marker.position = Vector3(p.x, 0.0, p.y)
		marker.area = int(pack["stage"])
		marker.behaviour = DungeonEnemyGroup.Behaviour.WANDER if String(pack["mode"]) == "wander" else DungeonEnemyGroup.Behaviour.STAND_GUARD
		marker.kinds = (pack["kinds"] as Array).duplicate(true)
		var members := 0
		for pair in marker.kinds:
			members += int(pair[1])
		marker.spread = clampf(0.9 + 0.3 * float(members), 1.6, 3.0)
		made += 1
		marker.name = "Pack%02d_stage%d_%s" % [made, marker.area, CryptLayout.space_at(CryptLayout.cell_of(p).x, CryptLayout.cell_of(p).y)]
		(_groups["EnemyGroups"] as Node3D).add_child(marker)
		marker.owner = root
	_counts["packs"] = made
