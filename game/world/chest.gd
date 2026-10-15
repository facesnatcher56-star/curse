class_name Chest
extends Node3D
## A treasure chest: click it (the hero walks up) or press the use key beside it, the lid swings open, and it gives up its loot once.
## Opened chests stay open and are empty. Shown as the dungeon chest model (a placeholder box if the model is missing).

const REACH := 3.2   # from its middle: the baked walkable area leaves a gap round the box, so the hero stops 2.3 to 2.8 m out
const BODY_SIZE := Vector3(1.1, 0.6, 0.7)
const LID_TIME := 0.45
## The dungeon's chest model (one mesh, no separate lid), shown at CHEST_HEIGHT metres tall, base on the ground. The box below is only
## the fallback if the model is missing, and the collision box stays BODY_SIZE either way.
const MODEL := "res://assets/models/dungeon/chest/model.glb"
const CHEST_HEIGHT := 0.8

var opened: bool = false
var _lid: Node3D
var _collision: StaticBody3D

func _ready() -> void:
	add_to_group("chests")
	if _lid == null:
		_build()

func _build() -> void:
	if ResourceLoader.exists(MODEL):
		_build_model(load(MODEL) as PackedScene)
		return
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.22, 0.1)
	wood.roughness = 0.9
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.55, 0.45, 0.2)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = BODY_SIZE
	base.mesh = base_mesh
	base.material_override = wood
	base.position.y = BODY_SIZE.y * 0.5
	add_child(base)
	# The lid hinges at the back top edge.
	_lid = Node3D.new()
	_lid.position = Vector3(0.0, BODY_SIZE.y, -BODY_SIZE.z * 0.5)
	add_child(_lid)
	var lid_mesh_node := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(BODY_SIZE.x + 0.04, 0.2, BODY_SIZE.z + 0.04)
	lid_mesh_node.mesh = lid_mesh
	lid_mesh_node.material_override = wood
	lid_mesh_node.position = Vector3(0.0, 0.1, BODY_SIZE.z * 0.5)
	_lid.add_child(lid_mesh_node)
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.14, 0.24, BODY_SIZE.z + 0.08)
	band.mesh = band_mesh
	band.material_override = iron
	band.position = Vector3(0.0, 0.1, BODY_SIZE.z * 0.5)
	_lid.add_child(band)
	_collision = StaticBody3D.new()
	_collision.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	shape.shape = box
	shape.position.y = BODY_SIZE.y * 0.5
	_collision.add_child(shape)
	add_child(_collision)

## The model as the chest: scaled to CHEST_HEIGHT, centred on the origin and standing on the ground. No lid node in the model, so the
## open tween has nothing to turn (`_lid` stays null); opening still empties it and drops the loot.
func _build_model(scene: PackedScene) -> void:
	var visual: Node3D = scene.instantiate()
	var bounds: AABB = CharacterModel._bounds_of(visual)
	var factor: float = CHEST_HEIGHT / maxf(bounds.size.y, 0.001)
	visual.scale = Vector3.ONE * factor
	visual.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * factor
	var holder := Node3D.new()
	holder.add_child(visual)
	add_child(holder)
	_collision = StaticBody3D.new()
	_collision.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	shape.shape = box
	shape.position.y = BODY_SIZE.y * 0.5
	_collision.add_child(shape)
	add_child(_collision)

## The nearest closed chest to a ground point, within `margin` metres of its edge (the click target).
static func near(tree: SceneTree, point: Vector3, margin: float) -> Chest:
	var best: Chest = null
	var best_gap: float = margin
	for node in tree.get_nodes_in_group("chests"):
		var chest := node as Chest
		if chest == null or chest.opened:
			continue
		var offset: Vector3 = chest.global_position - point
		offset.y = 0.0
		var gap: float = offset.length() - BODY_SIZE.x * 0.5
		if gap < best_gap:
			best_gap = gap
			best = chest
	return best

func in_reach(hero: Node3D) -> bool:
	var offset: Vector3 = hero.global_position - global_position
	offset.y = 0.0
	return not opened and offset.length() <= REACH

## Opens it and drops the loot. Returns false if it was already open.
func open() -> bool:
	if opened:
		return false
	opened = true
	remove_from_group("chests")
	if _lid != null:
		var tween := create_tween()
		tween.tween_property(_lid, "rotation:x", -1.9, LID_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_drop_loot()
	return true

func _drop_loot() -> void:
	var at: Vector3 = global_position + Vector3(0.0, 0.1, 0.9)
	var director: Node = get_tree().get_first_node_in_group("director")
	var level: int = 1
	if director != null and director.has_method("drop_level_at"):
		level = director.drop_level_at(at)
	if director != null and director.has_method("drop_item"):
		for i in randi_range(1, 3):
			var spot: Vector3 = at + Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.2, 0.5))
			director.drop_item(spot, Items.item_of_kind(Items.container_item_kind(randf()), level, Items.DROPS["normal"]["window"]))
	var gold := HealthOrb.new()
	gold.gold_amount = randi_range(4, 10) * maxi(level, 1)
	get_tree().current_scene.add_child(gold)
	gold.global_position = at
