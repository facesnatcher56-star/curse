class_name ThrownWeapon
extends Node3D
## The hero's real weapon while it is out of his hand: a copy of the model he was holding (the one in his hand is hidden for as long
## as this exists), standing in the world. It only knows how to be drawn: where its middle is, which way the blade points and how it
## is rolled. Everything it does (flying, hitting, embedding, coming back) is decided by WeaponThrowSkill, which owns the one weapon.

## Where, along the blade from the grip to the point, the weapon balances (what it spins about).
const BALANCE := 0.3

var length_m: float = 1.0        # from the grip to the point, in metres
var _holder: Node3D
var _scale: Vector3 = Vector3.ONE

## `hand_holder` is the weapon node in the hero's hand (CharacterModel.weapon); its grip point is its origin and the blade runs along +Y.
static func from_hand(hand_holder: Node3D, tip: Node3D) -> ThrownWeapon:
	var thrown := ThrownWeapon.new()
	thrown.top_level = true
	thrown.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	thrown._holder = hand_holder.duplicate() as Node3D
	thrown._holder.visible = true
	thrown.add_child(thrown._holder)
	thrown.length_m = maxf((tip.global_position - hand_holder.global_position).length(), 0.3)
	thrown._scale = hand_holder.global_transform.basis.get_scale()
	return thrown

## Places the weapon: its balance point at `center`, its blade pointing along `axis`, rolled about that axis by `roll`.
func set_pose(center: Vector3, axis: Vector3, roll: float = 0.0) -> void:
	var y: Vector3 = axis.normalized()
	var reference: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = y.cross(reference).normalized().rotated(y, roll)
	var z: Vector3 = x.cross(y)
	var basis := Basis(x * _scale.x, y * _scale.y, z * _scale.z)
	_holder.transform = Transform3D(basis, center - y * length_m * BALANCE)

## The balance point as last placed (tests and the embed check read it).
func center() -> Vector3:
	return _holder.transform.origin + _holder.transform.basis.y.normalized() * length_m * BALANCE

func axis() -> Vector3:
	return _holder.transform.basis.y.normalized()

## The point of the blade.
func tip() -> Vector3:
	return _holder.transform.origin + axis() * length_m

func model_count() -> int:
	return _holder.find_children("*", "MeshInstance3D", true, false).size()
