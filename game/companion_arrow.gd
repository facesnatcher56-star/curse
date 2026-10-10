class_name CompanionArrow
extends Node3D
## Cutter's arrow is a swept physical projectile: it can be seen in flight, collides with the first body or wall in its path,
## and remains lodged for a moment. Geometry decides the hit; Combat supplies armour, damage and the body's normal impact response.

const MODEL := "res://assets/models/archer/arrow/model.glb"
const SPEED := 23.0
const GRAVITY := 2.8
const LIFE := 3.0
const STICK_TIME := 4.0

var shooter: ArcherCompanion
var velocity: Vector3
var damage: float = 16.0
var take_aim: bool = false
var age: float = 0.0
var struck: Actor

static func fire(parent: Node, archer: ArcherCompanion, from: Vector3, toward: Vector3, hit_damage: float,
		empowered: bool = false) -> CompanionArrow:
	var arrow := CompanionArrow.new()
	arrow.shooter = archer
	arrow.damage = hit_damage
	arrow.take_aim = empowered
	parent.add_child(arrow)
	arrow.global_position = from
	arrow.velocity = (toward - from).normalized() * SPEED
	return arrow

func _ready() -> void:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	LootDrop._use_vertex_colours(model)
	add_child(model)
	if take_aim:
		SkillFx.take_aim_trail(self)
	_orient()

func _physics_process(delta: float) -> void:
	if struck != null:
		return
	age += delta
	var from: Vector3 = global_position
	velocity.y -= GRAVITY * delta
	var to: Vector3 = from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD | Actor.LAYER_ENEMY)
	query.collide_with_areas = false
	if shooter != null:
		query.exclude = [shooter.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		if hit.collider is Enemy:
			_hit_enemy(hit.collider as Enemy, from)
		else:
			_stick(null)
		return
	global_position = to
	_orient()
	if age >= LIFE or global_position.y < -1.0:
		_stick(null)

func _orient() -> void:
	if velocity.length_squared() > 0.01:
		basis = Basis(Quaternion(Vector3.UP, velocity.normalized()))

func _hit_enemy(enemy: Enemy, from: Vector3) -> void:
	if enemy.dead:
		_stick(null)
		return
	# Cutter serves the hero: his kills count as the hero's for XP and physical-kill bookkeeping.
	enemy.credit_hero()
	var result: Dictionary = Combat.resolve(shooter, enemy, damage, Combat.DamageType.PHYSICAL, false,
		1.6 if take_aim else 0.9, false, not take_aim)
	result["skill_id"] = "take_aim" if take_aim else "companion_arrow"
	if take_aim and result["outcome"] not in [Combat.Outcome.MISS, Combat.Outcome.BLOCK]:
		SkillFx.take_aim_hit(self, enemy.global_position, velocity.normalized())
	enemy.receive(result, from)
	if shooter != null:
		shooter.last_hit_target = enemy
	if result["outcome"] not in [Combat.Outcome.MISS, Combat.Outcome.BLOCK] and shooter != null and shooter.player != null:
		if take_aim:
			shooter.spend_take_aim()
		shooter.player.stats.gain_brutal_charge(float(result.get("damage", 0.0)))
		if not take_aim:
			shooter.gain_take_aim_charge(float(result.get("damage", 0.0)))
	struck = enemy
	_stick(enemy)

func _stick(body: Actor) -> void:
	set_physics_process(false)
	if body != null and is_instance_valid(body) and not body.dead:
		reparent(body, true)
	var timer := get_tree().create_timer(STICK_TIME)
	timer.timeout.connect(queue_free)
