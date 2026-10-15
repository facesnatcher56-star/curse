class_name DevSuite
extends Node3D
## Base of the developer tools in game/dev: short names for the parts of the game they drive and the helpers several of
## them share. DevHarness and every suite under game/dev/suites extend it; `expect` records into the harness.

var game: Node3D
var harness: DevHarness

func expect(label: String, condition: bool) -> void:
	harness.record(label, condition)

## Plays the hero's current wind-up (a power's cast, its impact included) to the end, in fixed steps, so a check reads what the impact did
## rather than the key press. Does nothing when no power wind-up is under way.
func _settle_cast(hero: Player) -> void:
	var steps: int = 0
	while hero.skills.busy and String(hero.skills.busy_def.get("kind", "")) == "power" and steps < 400:
		hero.skills.tick_busy(0.01)
		steps += 1

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

## A clear lane for an archer check that runs after other suites. When the arena is too crowded (earlier suites leave props), the
## breakable props and debris are removed and the lane is found again.
func _own_lane(length: float, width: float) -> Vector3:
	var lane := _clear_lane(length, width)
	if lane != Vector3.ZERO:
		return lane
	for node in get_tree().get_nodes_in_group("destructibles"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("debris"):
		node.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return _clear_lane(length, width)

## A known archer state for a check that runs after other suites: no cooldown or mana spent by earlier fights, no leftover orders or
## shot in progress. Earlier suites leave the shared basic cooldown spent, which would otherwise refuse every archer shot.
func _prepare_archer(archer: ArcherCompanion) -> void:
	# An earlier suite can leave him in the dagger stance (no target now ends it): the bow he starts with is then the one to use.
	archer.update_melee_stance(null)
	archer.bow.cancel()
	archer.stats.cooldowns.clear()
	archer.stats.mana = archer.stats.max_mana
	archer.attack_target = null
	archer.attack_prop = null
	archer.skills.busy = false
	if not archer.stats.is_ranged():
		# An earlier suite swapped the archer's weapon: restore the bow he starts with (see TownState's cutter setup).
		archer.stats.equipment[Items.Slot.WEAPON] = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow")
		archer.stats.refresh()

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

## The party's position and archer switches before a check that moves them, so the next check starts from what it had.
func _party_snapshot() -> Dictionary:
	return {"hero": player.global_position, "archer": game.companion.global_position, "archer_testing": game.companion.testing_disabled}

func _party_restore(saved: Dictionary) -> void:
	player.global_position = saved["hero"]
	player.reset_physics_interpolation()
	player.movement.has_goal = false
	player.attack_target = null
	player.attack_prop = null
	game.companion.global_position = saved["archer"]
	game.companion.reset_physics_interpolation()
	game.companion.testing_disabled = bool(saved["archer_testing"])
	game.companion.bow.cancel()
	game.companion.attack_target = null
	game.companion.attack_prop = null
