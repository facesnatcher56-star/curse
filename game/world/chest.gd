class_name Chest
extends Node3D
## A treasure chest: click it (the hero walks up) or press the use key beside it, the lid swings open, and it gives up its loot once.
## Opened chests stay open and are empty. Uses the functional dungeon model with a separately hinged lid (a box fallback is built if it is missing).

const REACH := 3.2   # from its middle: the baked walkable area leaves a gap round the box, so the hero stops 2.3 to 2.8 m out
const BODY_SIZE := Vector3(1.1, 0.6, 0.7)
const LID_TIME := 0.45
## The functional dungeon chest model. Its separate ChestLid node is pivoted at the rear hinge; the box below is only the fallback
## if the model is missing, and the collision box stays BODY_SIZE either way.
const MODEL := "res://assets/models/dungeon/chest/model.glb"
const CHEST_HEIGHT := 0.8

var opened: bool = false
## Map mode: which kind of chest this is (a key of MapDrops.T.guards: wooden, iron, gilded, cursed, hoard) and the item level of what it holds.
## An empty guard is the ordinary chest of the default game.
var guard: String = ""
var drop_level: int = 0
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

## A map-mode chest of `kind` (see MapDrops) holding items of `level`. It looks the part: tinted, bigger for a hoard, a cursed one glows.
static func create(kind: String, level: int) -> Chest:
	var chest := Chest.new()
	chest.guard = kind
	chest.drop_level = level
	return chest

## Gives an existing chest (one the scene already holds) its map-mode kind.
func set_guard(kind: String, level: int) -> void:
	guard = kind
	drop_level = level
	if _lid != null:
		_apply_guard_look()

func _apply_guard_look() -> void:
	var def: Dictionary = (MapDrops.T.guards as Dictionary).get(guard, {})
	scale = Vector3.ONE * float(def.get("scale", 1.0))
	ChestLook.apply(self, guard)   # tier styling on the real model: wood, iron bands, gilded trim, a cursed glow, a hoard's gold and size

## Scale the model to CHEST_HEIGHT, centre it, and find its real lid pivot before adding the unchanged collision box.
func _build_model(scene: PackedScene) -> void:
	var visual: Node3D = scene.instantiate()
	_lid = visual.find_child("ChestLid", true, false) as Node3D
	if _lid == null:
		push_error("Functional dungeon chest model has no ChestLid hinge node: " + MODEL)
		visual.queue_free()
		return
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
	if guard != "":
		_apply_guard_look()

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
	if guard != "":
		_drop_guarded()
		return
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

## Map mode: the chest's contents by its kind (MapDrops.chest_items), sprayed round the front with a burst in the chest's colour, and its gold.
func _drop_guarded() -> void:
	var at: Vector3 = global_position + Vector3(0.0, 0.1, 0.0) + global_transform.basis.z * 0.9
	var director: Node = get_tree().get_first_node_in_group("director")
	var level: int = drop_level
	if level <= 0:
		level = director.drop_level_at(at) if director != null and director.has_method("drop_level_at") else 1
	var tint: Color = MapDrops.guard_color(guard)
	Fx.burst(self, global_position + Vector3(0.0, 0.9, 0.0), Vector3.UP, tint, 36, 6.0, 0.03, true)
	if director != null and director.has_method("drop_item"):
		var thrown: Array = []
		for item in MapDrops.chest_items(guard, level, float(PartyManager.current().loot_bonuses().magic_find)):
			thrown.append(director.drop_item(at + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.2, 0.6)), item))
		ChestFx.play(self, thrown)   # rarity beams, a sound per rarity, a legendary's slow-motion beat
	var gold := HealthOrb.new()
	gold.gold_amount = MapDrops.gold_for(level, (MapDrops.T.chests[guard] as Dictionary).gold, float(PartyManager.current().loot_bonuses().gold_find))
	get_tree().current_scene.add_child(gold)
	gold.global_position = at
	if MapMode.active:
		MapMode.current.note_pickup("gold", gold.gold_amount)
