class_name TrainingDummy
extends Actor
## Stationary training dummy using genuine Actor/Combat damage intake and reactions.
## Strictly developer-only, used by ItemTestLab.

signal hit_received(result: Dictionary, dummy: TrainingDummy)
signal health_changed(current: float, max_val: float)

var initial_max_health: float = 10000.0

func _init() -> void:
	max_health = initial_max_health
	health = max_health
	level = 1
	armor = 0.0
	toughness = 0.0
	fire_resist = 0.0
	dodge_chance = 0.0
	block_chance = 0.0
	ranged_block_chance = 0.0
	body_radius = 0.5
	body_height = 1.8
	display_name = "Training Dummy"

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = LAYER_ENEMY
	collision_mask = LAYER_WORLD | LAYER_PLAYER
	_build_model("res://assets/models/zombie", ["idle", "hit"], 1.8, 0.5)
	if model != null:
		model.loop("idle")

func _build_dummy_visual() -> void:
	visual = Node3D.new()
	add_child(visual)

	# Try loading zombie or knight rigged model, or fallback to distinctive post mesh
	var post := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.35
	cylinder.bottom_radius = 0.4
	cylinder.height = 1.6
	post.mesh = cylinder
	post.position = Vector3(0, 0.8, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.45, 0.25) # Weathered wood
	mat.roughness = 0.9
	post.material_override = mat
	visual.add_child(post)

	# Crossbar / arms
	var crossbar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.2, 0.2)
	crossbar.mesh = box
	crossbar.position = Vector3(0, 1.25, 0)
	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(0.5, 0.35, 0.2)
	crossbar.material_override = cross_mat
	visual.add_child(crossbar)

	# Head / top knot
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	head.mesh = sphere
	head.position = Vector3(0, 1.7, 0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.8, 0.7, 0.5) # Burlap sack
	head.material_override = head_mat
	visual.add_child(head)

	# Base plate
	var base_plate := MeshInstance3D.new()
	var cyl_base := CylinderMesh.new()
	cyl_base.top_radius = 0.6
	cyl_base.bottom_radius = 0.65
	cyl_base.height = 0.1
	base_plate.mesh = cyl_base
	base_plate.position = Vector3(0, 0.05, 0)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.3, 0.3, 0.35) # Iron stand
	base_plate.material_override = base_mat
	visual.add_child(base_plate)

	# Collision shape
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

func _physics_process(delta: float) -> void:
	if _actor_tick(delta):
		return
	# Stationary: absorb knock velocity in place
	knock = knock.move_toward(Vector3.ZERO, 30.0 * delta)

func receive(result: Dictionary, source_pos: Vector3) -> void:
	# Keep alive: never die completely so tester can hit continuously without scene reload
	var incoming_damage: float = float(result.get("damage", 0.0))
	super.receive(result, source_pos)

	# Clamp health above zero if it would be lethal
	if health <= 0.0 or dead:
		dead = false
		health = 1.0

	hit_received.emit(result, self)
	health_changed.emit(health, max_health)

func set_dummy_level(new_level: int) -> void:
	level = clampi(new_level, 1, 100)
	health_changed.emit(health, max_health)

func set_dummy_armor(new_armor: float) -> void:
	armor = maxf(new_armor, 0.0)

func reset_health() -> void:
	dead = false
	health = max_health
	stun_time = 0.0
	hitpause = 0.0
	burn_time = 0.0
	bleed_time = 0.0
	armor_shred = 0.0
	armor_shred_time = 0.0
	health_changed.emit(health, max_health)
