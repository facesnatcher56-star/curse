class_name RunDirector
extends Node3D
## The run itself: wave composition and spawning, kill tracking, and what the dead drop (see LootDrop).
## Main builds the world and the hero; this decides what comes at them and what they get for surviving.

const ARENA_HALF := Arena.HALF

var player: Player
var hud: Hud
var wave: int = 0
var kills: int = 0
var selftest: bool = false   # the self-test drives waves by hand, so waves do not follow each other on their own
var _clear_pending: bool = false

## Seconds between a wave being cleared and the next one, for walking over what dropped.
const LOOT_BREATHER := 6.0
## A job taken from the town board: how many waves to survive and which rules apply (see WaveModifierDef). Empty for a free run.
var job: Dictionary = {}
var modifiers: Array[WaveModifierDef] = []
var _ending: bool = false

## Starts the run as the given job: its modifiers shape every wave, and clearing its last wave ends the run.
func set_job(offer: Dictionary) -> void:
	job = offer
	modifiers.clear()
	for id in offer.get("modifiers", []):
		var def: WaveModifierDef = TownDb.modifier(String(id))
		if def != null:
			modifiers.append(def)

## The modifiers in force at this wave (some only start later).
func active_modifiers(at_wave: int = -1) -> Array[WaveModifierDef]:
	var w: int = wave if at_wave < 0 else at_wave
	var out: Array[WaveModifierDef] = []
	for m in modifiers:
		if m.min_wave <= w:
			out.append(m)
	return out

## How many of an enemy this wave brings once the modifiers have had their say.
func modified_count(def: EnemyDef, at_wave: int) -> int:
	var base: int = EnemyDb.count_for(def, at_wave)
	if base <= 0:
		return 0
	var mult: float = 1.0
	for m in active_modifiers(at_wave):
		mult *= float(m.spawn_weights.get(def.id, 1.0)) * m.count_mult
	return maxi(int(round(base * mult)), 1 if mult > 0.0 else 0)

## Product of one numeric field ("health_mult", "speed_mult", "size_mult") over the active modifiers.
func modifier_product(field: String) -> float:
	var product: float = 1.0
	for m in active_modifiers():
		product *= float(m.get(field))
	return product

## Names of the active modifiers, for the wave banner.
func modifier_names() -> String:
	var names: PackedStringArray = []
	for m in active_modifiers():
		names.append(m.display_name)
	return ", ".join(names)

func _ready() -> void:
	add_to_group("director")   # lets enemies that summon reinforcements find it

## Wave over: a short breather to pick up what dropped, then the next wave.
func _wave_cleared() -> void:
	if _clear_pending:
		return
	_clear_pending = true
	hud.show_banner("Wave cleared", 1.8)
	await get_tree().create_timer(LOOT_BREATHER).timeout
	_clear_pending = false
	if not player.dead and not _ending:
		start_wave()

func start_wave() -> void:
	wave += 1
	var level: float = 1.0 + 0.12 * (wave - 1)
	var defs: Array[EnemyDef] = EnemyDb.spawnable(wave)
	var banner: String = "Wave %d" % wave
	# Wave 1 starts farther out and every enemy holds still for a few seconds, so the hero can take in the arena first.
	var lead: float = 6.0 if wave == 1 else 0.0
	var arrivals: PackedStringArray = []
	for def in defs:
		if def.min_wave == wave and def.id != "zombie":
			arrivals.append(def.display_name + ("s" if def.id != "priest" else ""))
	if not arrivals.is_empty():
		banner += "  -  new: " + ", ".join(arrivals)
	if not modifiers.is_empty():
		banner += "\n[%s]" % modifier_names()
	if not job.is_empty():
		banner += "\n%s: wave %d of %d" % [job.get("name", "Job"), wave, int(job.get("waves", 0))]
	hud.show_banner(banner)
	Enemy.max_tokens = 2 + wave / 5   # how many enemies may swing at the hero at once
	# Packs and loners first, then the support enemies that hang back behind the packs.
	var centres: Array[Vector3] = []
	for def in defs:
		var count: int = modified_count(def, wave)
		if def.spawn_mode == "pack":
			_spawn_packs(def, count, level, centres, lead)
		elif def.spawn_mode == "solo":
			for i in count:
				var spot: Vector3 = _spawn_point(18.0 + lead, 34.0, centres, 11.0)   # clear of pack members, which spread up to ~4.5 m
				centres.append(spot)
				spawn_enemy(spot, def.id, level)
	for def in defs:
		if def.spawn_mode == "support":
			for i in modified_count(def, wave):
				spawn_enemy(_support_point(centres), def.id, level)
	if wave >= 2:
		for i in randi_range(1, 2):
			spawn_enemy(_spawn_point(16.0, 34.0, centres, 6.0), "zombie", level)  # stragglers
	# Nobody notices the hero for the first moments of a wave (longer on wave 1).
	var grace: float = 4.0 if wave == 1 else 2.0
	for node in get_tree().get_nodes_in_group("enemies"):
		(node as Enemy).alert_delay = grace + randf() * 1.5

## Spawns `count` of an enemy in tight little groups (zombies 2-5 strong, the smaller kinds 2-3) with room between groups.
func _spawn_packs(def: EnemyDef, count: int, level: float, centres: Array[Vector3], lead: float = 0.0) -> void:
	var biggest: int = 5 if def.id == "zombie" else 3
	var remaining: int = count
	while remaining > 0:
		var pack: int = mini(remaining, randi_range(2, biggest))
		if remaining - pack < 2:
			pack = remaining
		remaining -= pack
		var centre: Vector3 = _spawn_point(14.0 + lead, 28.0 + lead, centres, 9.0)
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
	# Never closer than 80% of min_dist to the hero (the arena clamp could otherwise pull a spawn onto them) and at least
	# `spacing` from every spot already used. If a crowded arena allows no such spot, take the roomiest one tried.
	var roomiest: Vector3 = player.global_position
	var roomiest_gap: float = -1.0
	var farthest: Vector3 = player.global_position
	var farthest_d: float = -1.0
	for attempt in 40:
		var angle: float = randf() * TAU
		var pos: Vector3 = _clamp_to_arena(player.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(min_dist, max_dist))
		if Nav.ready(self):
			# Snap to the navmesh, but never trust a snap that moves the spot far: right after a scene change the map can still
			# be empty and answers with the origin, which is exactly where the hero stands.
			var snapped: Vector3 = Nav.snap(self, pos)
			if snapped.distance_to(pos) <= 4.0:
				pos = snapped
		var d: float = pos.distance_to(player.global_position)
		if d > farthest_d:
			farthest_d = d
			farthest = pos
		if d < min_dist * 0.8:
			continue
		var gap: float = 9999.0
		for other in used:
			gap = minf(gap, other.distance_to(pos))
		if gap >= spacing:
			return pos
		if gap > roomiest_gap:
			roomiest_gap = gap
			roomiest = pos
	return roomiest if roomiest_gap >= 0.0 else farthest

func spawn_enemy(pos: Vector3, variant: String = "zombie", level: float = 1.0) -> Enemy:
	var enemy := Enemy.new()
	enemy.variant = variant
	enemy.level_scale = level
	enemy.target = player
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.global_position = pos
	if not modifiers.is_empty():
		_apply_modifiers(enemy)
	# Teleported bodies would otherwise be drawn sliding in from their previous position.
	enemy.reset_physics_interpolation()
	return enemy

## Tougher, quicker or bigger enemies, as the job's modifiers ask.
func _apply_modifiers(enemy: Enemy) -> void:
	var health: float = modifier_product("health_mult")
	enemy.max_health *= health
	enemy.health = enemy.max_health
	enemy.move_speed *= modifier_product("speed_mult")
	var size: float = modifier_product("size_mult")
	if size != 1.0 and enemy.visual != null:
		enemy.visual.scale *= size

func _process(_delta: float) -> void:
	# A job run ends in the town: the hero fell, or the last wave is done (see _on_enemy_died).
	if not job.is_empty() and not _ending and not selftest and player != null and player.dead:
		_end_run(false)

## A dead monster may drop an item (see EnemyDef.drop_chance): it lands near the body and waits to be walked over.
func _drop_loot(actor: Actor) -> void:
	var enemy := actor as Enemy
	if enemy == null or enemy.def == null or randf() >= enemy.def.drop_chance:
		return
	drop_item(enemy.global_position, Items.roll_drop(wave, enemy.def.drop_luck, owned_uniques()))

func owned_uniques() -> Array[String]:
	var owned: Array[String] = []
	for item in player.stats.equipment.values():
		if int(item["rarity"]) == Items.Rarity.UNIQUE:
			owned.append(String(item["name"]))
	for item in player.stats.bag:
		if int(item["rarity"]) == Items.Rarity.UNIQUE:
			owned.append(String(item["name"]))
	return owned

func drop_item(at: Vector3, item: Dictionary) -> LootDrop:
	var drop: LootDrop = LootDrop.create(item)
	add_child(drop)
	drop.toss_from(at)
	return drop

## Back to town: the run's gold, gear and potions are handed over and the town takes it from there.
func _end_run(completed: bool) -> void:
	if _ending:
		return
	_ending = true
	hud.show_banner("Job complete" if completed else "You have fallen", 3.0)
	await get_tree().create_timer(3.2).timeout
	TownState.take_gear(player.stats.equipment)
	for item in player.stats.bag:
		TownState.stash_item(item)
	TownState.potions = maxi(player.stats.potions, 0)
	TownState.finish_run({"kills": kills, "wave": wave, "completed": completed, "died": player.dead})
	get_tree().paused = false
	LoadingScreen.go(get_tree(), "res://game/town.tscn")

func _on_enemy_died(actor: Actor) -> void:
	kills += 1
	player.on_enemy_killed(actor)
	_drop_loot(actor)
	await get_tree().process_frame
	if get_tree().get_nodes_in_group("enemies").size() == 0 and not selftest and not player.dead:
		if not job.is_empty() and wave >= int(job.get("waves", 0)):
			_end_run(true)
		else:
			_wave_cleared()
