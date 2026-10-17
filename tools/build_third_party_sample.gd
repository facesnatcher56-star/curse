extends SceneTree
## Writes game/dev/third_party_sample.tscn: a small room made with GridMap from the KayKit dungeon MeshLibrary, props from the KayKit
## and Quaternius kits, dressed with ProtonScatter. Dev sample only.
##   godot --headless --path . -s res://tools/build_third_party_sample.gd

const M := "res://addons/proton_scatter/src/modifiers/%s.gd"
const OUT := "res://game/dev/third_party_sample.tscn"
const KK := "res://assets/third_party/kaykit_dungeon/models/%s.gltf.glb"
const Q1 := "res://assets/third_party/quaternius_modular_dungeon_1/%s.glb"
const Q2 := "res://assets/third_party/quaternius_modular_dungeon_2/%s.glb"

var _root: Node3D
var _lib: MeshLibrary

func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "ThirdPartySample"
	_root.set_script(load("res://game/dev/third_party_sample.gd"))
	_lib = load("res://assets/third_party/kaykit_dungeon/dungeon_meshlib.tres")
	_environment()
	_room()
	_props()
	_scatter()
	var ps := PackedScene.new()
	ps.pack(_root)
	print("save_err=", ResourceSaver.save(ps, OUT))
	quit()

func _add(parent: Node, n: Node) -> Node:
	parent.add_child(n)
	n.owner = _root
	return n

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.42)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.08, 0.1)
	env.fog_density = 0.012
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(_root, we)
	var sun := DirectionalLight3D.new()
	sun.name = "DimMoon"
	sun.light_color = Color(0.55, 0.62, 0.8)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, 30, 0)
	_add(_root, sun)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 45
	cam.position = Vector3(10, 26, 34)
	cam.rotation_degrees = Vector3(-42, 0, 0)
	cam.current = true
	_add(_root, cam)

func _grid(node_name: String) -> GridMap:
	var g := GridMap.new()
	g.name = node_name
	g.mesh_library = _lib
	g.cell_size = Vector3(4, 4, 4)
	g.cell_center_y = false
	_add(_root, g)
	return g

func _room() -> void:
	# One cell holds one item, so floors and walls are two GridMaps sharing the library (and cell grid).
	var gm := _grid("RoomFloor")
	var walls := _grid("RoomWalls")
	var floor_i := _lib.find_item_by_name("floor_tile_large")
	var wall_i := _lib.find_item_by_name("wall")
	var door_i := _lib.find_item_by_name("wall_doorway")
	var arch_i := _lib.find_item_by_name("wall_archedwindow_open")
	var barrier_i := _lib.find_item_by_name("barrier")
	var rot_n := gm.get_orthogonal_index_from_basis(Basis())
	var rot_w := gm.get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(90)))
	var rot_s := gm.get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(180)))
	var rot_e := gm.get_orthogonal_index_from_basis(Basis(Vector3.UP, deg_to_rad(270)))
	for x in 5:
		for z in 5:
			gm.set_cell_item(Vector3i(x, 0, z), floor_i)
	for x in 5:
		walls.set_cell_item(Vector3i(x, 0, 0), door_i if x == 2 else (arch_i if x == 0 or x == 4 else wall_i), rot_n)
		walls.set_cell_item(Vector3i(x, 0, 4), barrier_i, rot_s)
	for z in 5:
		var west: int = door_i if z == 2 else wall_i
		walls.set_cell_item(Vector3i(0, 0, z), west, rot_w)
		walls.set_cell_item(Vector3i(4, 0, z), arch_i if z == 1 or z == 3 else wall_i, rot_e)
	# Corners: the kit's pillar covers the wall ends.
	for c in [Vector3(0, 0, 0), Vector3(20, 0, 0), Vector3(0, 0, 20), Vector3(20, 0, 20)]:
		_prop(KK % "pillar_decorated" if c.z == 0 else KK % "pillar", c, 0.0)

func _prop(path: String, pos: Vector3, yaw_deg: float, scale := 1.0) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	n.scale = Vector3.ONE * scale
	n.name = path.get_file().get_basename().get_basename()
	_add(_root, n)
	return n

func _torch(pos: Vector3, yaw_deg: float) -> void:
	_prop(KK % "torch_mounted", pos, yaw_deg)
	var l := OmniLight3D.new()
	l.name = "TorchLight"
	l.position = pos + Vector3(0, 1.0, 0.6).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	l.light_color = Color(1.0, 0.55, 0.22)
	l.light_energy = 2.2
	l.omni_range = 11.0
	l.shadow_enabled = true
	_add(_root, l)

func _props() -> void:
	_torch(Vector3(6, 2.4, 0.6), 0)
	_torch(Vector3(14, 2.4, 0.6), 0)
	_torch(Vector3(0.6, 2.4, 6), 270)
	_torch(Vector3(0.6, 2.4, 14), 270)
	_torch(Vector3(19.4, 2.4, 10), 90)
	_prop(KK % "table_long_decorated_A", Vector3(10, 0, 8), 0)
	_prop(KK % "chair", Vector3(8.2, 0, 10), 200)
	_prop(KK % "stool", Vector3(12, 0, 10.4), 40)
	_prop(KK % "barrel_large", Vector3(2, 0, 2.2), 0)
	_prop(KK % "barrel_small_stack", Vector3(3.6, 0, 1.6), 20)
	_prop(KK % "crates_stacked", Vector3(17.5, 0, 2.5), -15)
	_prop(KK % "chest_gold", Vector3(17.6, 0, 8.5), 270)
	_prop(KK % "shelf_large", Vector3(1.4, 0, 9), 90)
	_prop(KK % "sword_shield_broken", Vector3(14.5, 1.6, 0.52), 0)
	_prop(KK % "banner_brown", Vector3(9, 3.4, 0.55), 0)
	# Quaternius kit props (separate pack, same CC0 licence), to prove the two kits mix.
	_prop(Q2 % "Candelabrum_tall", Vector3(15, 0, 14), 0)
	_prop(Q2 % "Bones", Vector3(6, 0, 15), 30)
	_prop(Q2 % "Column_Broken", Vector3(5, 0, 6), 0)

func _scatter() -> void:
	var sc := ProtonScatter.new()
	sc.name = "FloorDebris"
	sc.global_seed = 7
	_add(_root, sc)
	sc.position = Vector3(10, 0, 10)
	var picks: Array = [[KK % "rubble_half", 40, 0.35], [Q2 % "Rock3", 30, 0.8], [Q2 % "Bones2", 25, 0.9], [KK % "candle_melted", 20, 1.0], [Q2 % "Rock1", 20, 0.6]]
	for p in picks:
		var it := ProtonScatterItem.new()
		it.name = "Item_" + String(p[0]).get_file().get_basename().get_basename()
		it.proportion = p[1]
		it.source_scale_multiplier = p[2]
		_add(sc, it)
		it.path = p[0]
	var shape := ProtonScatterShape.new()
	shape.name = "ScatterShape"
	var box := ProtonScatterBoxShape.new()
	box.size = Vector3(14, 0.2, 12)
	shape.shape = box
	_add(sc, shape)
	var stack := ProtonScatterModifierStack.new()
	var cr = load(M % "create_inside_random").new()
	cr.amount = 26
	var rr = load(M % "randomize_rotation").new()
	rr.rotation = Vector3(0, 360, 0)
	rr.snap_angle = Vector3.ZERO
	var rs = load(M % "randomize_transforms").new()
	rs.scale = Vector3(0.6, 0.6, 0.6)
	stack.stack.append(cr)
	stack.stack.append(rr)
	stack.stack.append(rs)
	sc.modifier_stack = stack
