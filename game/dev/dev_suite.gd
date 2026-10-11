class_name DevSuite
extends Node3D
## Base of the developer tools in game/dev: short names for the parts of the game they drive and the helpers several of
## them share. DevHarness and every suite under game/dev/suites extend it; `expect` records into the harness.

var game: Node3D
var harness: DevHarness

func expect(label: String, condition: bool) -> void:
	harness.record(label, condition)

# Short names for the parts of the game the checks drive.
var player: Player:
	get: return game.player

var hud: Hud:
	get: return game.hud

var rig: CameraRig:
	get: return game.rig

var arena: Arena:
	get: return game.arena

var pause_menu: PauseMenu:
	get: return game.pause_menu

var wave: int:
	get: return game.director.wave
	set(value): game.director.wave = value

var kills: int:
	get: return game.director.kills

func _spawn_enemy(pos: Vector3, variant: String = "zombie", level: float = 1.0) -> Enemy:
	return game.director.spawn_enemy(pos, variant, level)

func _next_wave() -> void:
	game.director.start_wave()

## A spot with nothing (props, walls) in a corridor of `length` along +X, so spawned test enemies are not pushed around.
func _free_lane_start(length: float, width: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 2.0, width)
	for candidate in [Vector3(-25, 0, 25), Vector3(25, 0, -25), Vector3(-25, 0, -25), Vector3(25, 0, 25), Vector3(0, 0, 30),
			Vector3(0, 0, -30), Vector3(-30, 0, 0), Vector3(-12, 0, 18), Vector3(-12, 0, -18), Vector3(12, 0, 18)]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), candidate + Vector3(length * 0.5, 1.6, 0.0))
		query.collision_mask = Actor.LAYER_WORLD
		if space.intersect_shape(query, 1).is_empty():
			return candidate
	return Vector3.ZERO

## A spot with a clear lane of `length` x `width` running along +x from it, found by scanning the arena (the harness arena is full of props).
func _clear_lane(length: float, width: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 2.2, width)
	for x in range(-36, 12, 3):
		for z in range(-34, 35, 3):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(Basis(), Vector3(x + length * 0.5, 1.4, z))
			query.collision_mask = Actor.LAYER_WORLD
			if space.intersect_shape(query, 1).is_empty():
				return Vector3(x, 0, z)
	return Vector3.ZERO

## The sword sound plays when the blade connects with an enemy, and only then: not on a miss or a block, not for a fireball or a
## boot or a shockwave.
func _logged(prefix: String) -> int:
	var count: int = 0
	for name in Sfx.played_log:
		if name.begins_with(prefix):
			count += 1
	return count

func _count_buttons(root: Node) -> int:
	var count: int = 0
	for node in root.find_children("*", "Button", true, false):
		if not (node as Button).disabled:
			count += 1
	return count

func _find_button(root: Node, text_start: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with(text_start):
			return node as Button
	return null

func _label_text(root: Node) -> String:
	var out: PackedStringArray = []
	for node in root.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return " ".join(out)

## Weapon Throw: hold to wind up (the range grows with the hold), let go and the real weapon leaves his hand and tears through a line,
## buries itself; the same key recalls it back along its own line (whatever the cooldown says) and he catches it.
func _throw_dummy(pos: Vector3, variant: String = "zombie") -> Enemy:
	var e: Enemy = _spawn_enemy(pos, variant)
	e.aggro_range = 0.0
	e.max_health = 4000.0
	e.health = 4000.0
	e.block_chance = 0.0
	return e

func _wait_state(wanted: int, seconds: float) -> bool:
	var waited: float = 0.0
	while int(player.weapon_throw.state) != wanted and waited < seconds:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	return int(player.weapon_throw.state) == wanted
