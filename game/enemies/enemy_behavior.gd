class_name EnemyBehavior
extends RefCounted
## What an enemy does in a fight. The Enemy node owns the body (stats, model, stun, aggro, movement helpers, attack
## slots); a behaviour owns the decisions. Subclasses override tick() and, when needed, the hooks below.

var e: Enemy

func setup(enemy: Enemy) -> void:
	e = enemy

## Called every physics frame while the enemy is awake, not stunned, not frozen and has a living target.
func tick(_delta: float, _dist: float) -> void:
	pass

## The enemy was stunned or knocked down: drop whatever was in progress and release anything held.
func on_interrupted() -> void:
	pass

## The enemy just died (before its corpse is handled).
func on_death(_killing_blow: Dictionary) -> void:
	pass

## True while a committed attack is in progress.
func is_attacking() -> bool:
	return false
