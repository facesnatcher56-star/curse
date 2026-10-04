class_name RunDirector
extends Node3D
## The run itself: wave composition and spawning, kill tracking, and the reward offered between waves.
## Main builds the world and the hero; this decides what comes at them and what they get for surviving.

const ARENA_HALF := Arena.HALF

var player: Player
var hud: Hud
var wave: int = 0
var kills: int = 0
var choosing: bool = false
var selftest: bool = false   # the self-test drives waves by hand, so no automatic reward offers
var _choices: Array[Dictionary] = []
var _brute_killed: bool = false
var _reward_pending: bool = false

func _ready() -> void:
	add_to_group("director")   # lets enemies that summon reinforcements find it

## Wave over: offer three items, one of which you keep. Brutes make better offers.
func offer_reward() -> void:
	if _reward_pending:
		return
	_reward_pending = true
	hud.show_banner("Wave cleared", 1.5)
	await get_tree().create_timer(1.3).timeout
	if player.dead:
		return
	var owned: Array[String] = []
	for item in player.stats.equipment.values():
		if item["rarity"] == Items.Rarity.UNIQUE:
			owned.append(item["name"])
	_choices = Items.roll_choices(wave, _brute_killed, owned)
	_brute_killed = false
	hud.choices = _choices
	hud.choosing = true
	choosing = true
	get_tree().paused = true

func choose(index: int) -> void:
	if index >= 0 and index < _choices.size():
		player.stats.equip(_choices[index])
	else:
		player.stats.potions += 1
		player._say("Skipped: +1 potion")
	choosing = false
	_reward_pending = false
	hud.choosing = false
	get_tree().paused = false
	await get_tree().create_timer(1.8).timeout
	if not player.dead:
		start_wave()

func start_wave() -> void:
	wave += 1
	var level: float = 1.0 + 0.12 * (wave - 1)
	var defs: Array[EnemyDef] = EnemyDb.spawnable(wave)
	var banner: String = "Wave %d" % wave
	var arrivals: PackedStringArray = []
	for def in defs:
		if def.min_wave == wave and def.id != "zombie":
			arrivals.append(def.display_name + ("s" if def.id != "priest" else ""))
	if not arrivals.is_empty():
		banner += "  -  new: " + ", ".join(arrivals)
	hud.show_banner(banner)
	Enemy.max_tokens = 2 + wave / 5   # how many enemies may swing at the hero at once
	# Packs and loners first, then the support enemies that hang back behind the packs.
	var centres: Array[Vector3] = []
	for def in defs:
		var count: int = EnemyDb.count_for(def, wave)
		if def.spawn_mode == "pack":
			_spawn_packs(def, count, level, centres)
		elif def.spawn_mode == "solo":
			for i in count:
				var spot: Vector3 = _spawn_point(18.0, 34.0, centres, 11.0)   # clear of pack members, which spread up to ~4.5 m
				centres.append(spot)
				spawn_enemy(spot, def.id, level)
	for def in defs:
		if def.spawn_mode == "support":
			for i in EnemyDb.count_for(def, wave):
				spawn_enemy(_support_point(centres), def.id, level)
	if wave >= 2:
		for i in randi_range(1, 2):
			spawn_enemy(_spawn_point(16.0, 34.0, centres, 6.0), "zombie", level)  # stragglers

## Spawns `count` of an enemy in tight little groups (zombies 2-5 strong, the smaller kinds 2-3) with room between groups.
func _spawn_packs(def: EnemyDef, count: int, level: float, centres: Array[Vector3]) -> void:
	var biggest: int = 5 if def.id == "zombie" else 3
	var remaining: int = count
	while remaining > 0:
		var pack: int = mini(remaining, randi_range(2, biggest))
		if remaining - pack < 2:
			pack = remaining
		remaining -= pack
		var centre: Vector3 = _spawn_point(14.0, 28.0, centres, 9.0)
		centres.append(centre)
		var placed: Array[Vector3] = []
		for k in pack:
			var pos: Vector3 = centre
			for attempt in 8:
				var offset: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.0, 1.8 + pack * 0.55)
				pos = centre + Vector3(offset.x, 0.0, offset.y)
				var clear: bool = true
				for other in placed:
					if other.distance_to(pos) < 1.5:
						clear = false
						break
				if clear:
					break
			placed.append(pos)
			spawn_enemy(_clamp_to_arena(pos), def.id, level)

## A spot just behind one of the packs (on the far side from the hero), for enemies that support from the back.
func _support_point(centres: Array[Vector3]) -> Vector3:
	if centres.is_empty():
		return _spawn_point(18.0, 30.0, centres, 6.0)
	var centre: Vector3 = centres[randi() % centres.size()]
	var behind: Vector3 = centre - player.global_position
	behind.y = 0.0
	behind = behind.normalized() if behind.length() > 0.1 else Vector3.FORWARD
	return _clamp_to_arena(centre + behind * 4.5)

func _clamp_to_arena(pos: Vector3) -> Vector3:
	return Vector3(clampf(pos.x, -ARENA_HALF + 2, ARENA_HALF - 2), 0.0, clampf(pos.z, -ARENA_HALF + 2, ARENA_HALF - 2))

## A random spot `min_dist`..`max_dist` from the hero, at least `spacing` from every spot already used.
func _spawn_point(min_dist: float, max_dist: float, used: Array[Vector3], spacing: float) -> Vector3:
	# Never closer than 80% of min_dist to the hero (the arena clamp could otherwise pull a spawn onto them);
	# if no spot qualifies, take the farthest one tried.
	var farthest: Vector3 = player.global_position
	var farthest_d: float = -1.0
	for attempt in 30:
		var angle: float = randf() * TAU
		var pos: Vector3 = _clamp_to_arena(player.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(min_dist, max_dist))
		if Nav.ready(self):
			pos = Nav.snap(self, pos)
		var d: float = pos.distance_to(player.global_position)
		if d > farthest_d:
			farthest_d = d
			farthest = pos
		if d < min_dist * 0.8:
			continue
		var ok: bool = true
		for other in used:
			if other.distance_to(pos) < spacing:
				ok = false
				break
		if ok:
			return pos
	return farthest

func spawn_enemy(pos: Vector3, variant: String = "zombie", level: float = 1.0) -> Enemy:
	var enemy := Enemy.new()
	enemy.variant = variant
	enemy.level_scale = level
	enemy.target = player
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.global_position = pos
	# Teleported bodies would otherwise be drawn sliding in from their previous position.
	enemy.reset_physics_interpolation()
	return enemy

func _on_enemy_died(actor: Actor) -> void:
	kills += 1
	player.on_enemy_killed(actor)
	if actor is Enemy and (actor as Enemy).variant == "brute":
		_brute_killed = true
	await get_tree().process_frame
	if get_tree().get_nodes_in_group("enemies").size() == 0 and not selftest and not player.dead and not choosing:
		offer_reward()
