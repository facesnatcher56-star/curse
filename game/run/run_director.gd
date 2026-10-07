class_name RunDirector
extends Node3D
## The run itself: wave composition and spawning, kill tracking, and what the dead drop (see LootDrop).
## Main builds the world and the hero; this decides what comes at them and what they get for surviving.

var player: Player
var hud: Hud
var wave: int = 0
var kills: int = 0
var selftest: bool = false   # the self-test drives waves by hand, so waves do not follow each other on their own
var _clear_pending: bool = false

## Seconds between a wave being cleared and the next one, for walking over what dropped.
const LOOT_BREATHER := 6.0
## A job taken from the town board: its objective (see JobObjective) and which rules apply (see RunModifierDef). Empty for a free run.
var job: Dictionary = {}
var modifiers: Array[RunModifierDef] = []
var _ending: bool = false
## True when the director serves the one connected world (TownScene) instead of a run: no waves, gold for every kill paid as it happens,
## and a fallen hero is dragged home (`hero_fell`) instead of the run ending.
var world_mode: bool = false
var gold_per_kill: int = 0
var _fell: bool = false
signal hero_fell
## The quests heard something on the road (see Quests): a line to show, and where a quest item dropped.
signal quest_news(line: String)
signal quest_item_dropped(inst: Dictionary, at: Vector3)
## Set for a job played in an authored location (see CryptRoad) instead of the wave loop: the monsters are already out there.
var location: CryptRoad
const SLEEP_BEYOND := 85.0   # an unaware monster this far from the hero is switched off...
const WAKE_WITHIN := 70.0    # ...and back on when he comes this close (the gap stops it flickering)
var _sleep_clock: float = 0.0

## Starts the run as the given job: its modifiers shape every wave, and completing its objective ends the run.
func set_job(offer: Dictionary) -> void:
	job = offer
	modifiers.clear()
	for id in offer.get("modifiers", []):
		var def: RunModifierDef = TownDb.modifier(String(id))
		if def != null:
			modifiers.append(def)

## The modifiers in force at this wave (some only start later).
func active_modifiers(at_wave: int = -1) -> Array[RunModifierDef]:
	var w: int = wave if at_wave < 0 else at_wave
	var out: Array[RunModifierDef] = []
	for m in modifiers:
		if connected() or m.min_stage <= w:   # a stage that starts later is a wave idea; the world's conditions are in force from the start
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

## How much more (or less) likely a group made of these kinds is, once the modifiers have had their say: the average of what each kind's
## weight is multiplied by (a Spitters' Nest makes groups with spitters in them more likely, and leaves the rest alone).
func group_weight(kinds: Array) -> float:
	if kinds.is_empty():
		return 1.0
	var total: float = 0.0
	for kind in kinds:
		var mult: float = 1.0
		for m in active_modifiers():
			mult *= float(m.spawn_weights.get(String(kind), 1.0))
		total += mult
	return total / float(kinds.size())

## How much bigger (or smaller) a group is made, by the modifiers and by world events (Raging Hordes).
func group_count_mult() -> float:
	var mult: float = modifier_product("count_mult")
	return mult * (Quests.world_mult("count_mult") if world_mode else 1.0)

## Names of the active modifiers, for the wave banner.
func modifier_names() -> String:
	var names: PackedStringArray = []
	for m in active_modifiers():
		names.append(m.display_name)
	return ", ".join(names)

## Far, unaware monsters sleep: with the road holding two hundred of them, only those near the hero need thinking about.
func _sleep_far_monsters(delta: float) -> void:
	if (location == null and not world_mode) or player == null:
		return
	_sleep_clock -= delta
	if _sleep_clock > 0.0:
		return
	_sleep_clock = 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.dead or enemy.is_ragdolled() or enemy.impaled:
			continue
		var distance: float = enemy.global_position.distance_to(player.global_position)
		var asleep: bool = enemy.process_mode == Node.PROCESS_MODE_DISABLED
		if asleep and (distance < WAKE_WITHIN or enemy.is_aggro()):
			enemy.process_mode = Node.PROCESS_MODE_INHERIT
		elif not asleep and distance > SLEEP_BEYOND and not enemy.is_aggro():
			enemy.process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	add_to_group("director")   # lets enemies that summon reinforcements find it

func is_ending() -> bool:
	return _ending

## Where the job stands, in the objective's own terms (see JobObjective): the wave number for waves, nests destroyed for nests.
func progress() -> Dictionary:
	return {"stage": location.nests_destroyed if location != null else wave}

## The line for the HUD while a job in a location is on: "Destroy nests: 1 / 3" ("" for the wave loop, which shows its wave).
func objective_line() -> String:
	if location == null or job.is_empty():
		return ""
	return JobObjective.progress_text(job, progress())

## True for the connected world and for a job in an authored location, false for the wave arena. `wave` belongs to the arena alone:
## nothing in the connected world reads it (see WorldThreat for what the world uses).
func connected() -> bool:
	return location != null or world_mode

## The arena's own monster level for a wave (a development mode; the connected world uses WorldThreat).
static func arena_level(at_wave: int) -> float:
	return 1.0 + 0.12 * (at_wave - 1)

## The item tier a drop from a source of this threat has: the arena goes by its wave, the connected world by the source.
func drop_tier(source_threat: float) -> int:
	return Items.tier_for_source(source_threat) if connected() else Items.tier_for_wave(wave)

## The item tier for something with no monster behind it (a smashed prop) at a place: the stretch of road it stands in.
func drop_tier_at(point: Vector3) -> int:
	if not connected():
		return Items.tier_for_wave(wave)
	return Items.tier_for_source(location.threat_at(point) if location != null else WorldThreat.for_distance(0.0))

## Starts the job in an authored location: every group is already there, doing its own thing, so there is no wave and no timer.
func start_location(place: CryptRoad) -> void:
	location = place
	Enemy.max_tokens = 3
	place.nest_destroyed.connect(_on_nest_destroyed)
	hud.show_banner("%s\n%s" % [String(job.get("location", "The road")).capitalize(), JobObjective.describe(job)], 4.0)
	place.spawn_encounters(self)

func _on_nest_destroyed(count: int, total: int) -> void:
	if count >= total:
		hud.show_banner("The last nest is destroyed\nGo back to the gate to hand it in, or keep exploring", 5.0)
	else:
		hud.show_banner("Nest destroyed\n%s" % JobObjective.progress_text(job, progress()), 3.0)

## The hero walked out through the gate: the job is handed in if its objective is done, abandoned if not.
func request_exit() -> void:
	_end_run(JobObjective.is_complete(job, progress()), true)

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
	var level: float = arena_level(wave)
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
		banner += "\n%s: %s" % [job.get("name", "Job"), JobObjective.progress_text(job, {"stage": wave})]
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
	var clamped: Vector3 = Arena.clamp_point(get_tree(), pos, 2.0)
	clamped.y = 0.0
	return clamped

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
	if world_mode:
		enemy.max_health *= Quests.world_mult("health_mult")
		enemy.health = enemy.max_health
		enemy.move_speed *= Quests.world_mult("speed_mult")
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

## Starts watching the road as part of the world: its monsters are placed where the layout says and wait there. No banner, no timer.
func attach_world(place: CryptRoad) -> void:
	location = place
	Enemy.max_tokens = 3
	place.spawn_encounters(self)

## The hero is back on his feet in town: a fall can be reported again.
func hero_returned() -> void:
	_fell = false

func _process(delta: float) -> void:
	_sleep_far_monsters(delta)
	if world_mode:
		TownState.flush_progression()   # ordinary kills' XP reaches the disk within a few seconds
		if player != null and player.dead and not _fell:
			_fell = true
			hero_fell.emit()
		return
	# A job run ends in the town: the hero fell, or the last wave is done (see _on_enemy_died).
	if not job.is_empty() and not _ending and not selftest and player != null and player.dead:
		_end_run(false)

## What a kill means to the quests: a named monster done (and a good item from it), or one of a kind being counted (and maybe a quest item).
func _report_to_quests(actor: Actor) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return 0
	if enemy.has_meta("monster_uid"):   # a named monster (see Monsters): the bounty is paid and it leaves its best behind
		var named_level: float = float(Monsters.find(int(enemy.get_meta("monster_uid"))).get("level", enemy.level_scale))   # its own, not the road's
		var paid: Dictionary = Monsters.killed(int(enemy.get_meta("monster_uid")))
		for i in int(paid.get("items", 0)):
			drop_item(enemy.global_position + Vector3(0.6 * i, 0, 0), Items.roll_drop(drop_tier(named_level), 1.0, owned_uniques()))
		for line in Quests.pop_news():
			quest_news.emit(line)
		return int(paid.get("xp", 0)) if enemy.hero_credited() else 0   # the bounty is paid regardless; the XP is for the hero's own kill
	if enemy.has_meta("quest_uid"):
		if Quests.report_unique_killed(int(enemy.get_meta("quest_uid"))):
			drop_item(enemy.global_position, Items.roll_drop(drop_tier(enemy.level_scale), 1.0, owned_uniques()))   # a named monster always leaves something good
		for line in Quests.pop_news():
			quest_news.emit(line)
		return 0
	var result: Dictionary = Quests.report_kill(enemy.variant)
	for inst in result["drops"]:
		quest_item_dropped.emit(inst, enemy.global_position)
	for line in Quests.pop_news():
		quest_news.emit(line)
	return 0

## What a death pays the hero in XP, as ONE award (so several levels at once make one level-up): the enemy's own kill value at the threat it
## was killed at, plus a named monster's bounty XP. Only a death the hero is credited with (Actor.hero_credited), of an enemy that is
## worth XP (`xp_eligible`: no renewable summons), pays anything. The hero's level is never an input. Ordinary kills are saved lazily
## (TownState.add_hero_xp); a named monster's bounty is saved at once.
func _pay_kill_xp(actor: Actor, bounty_xp: int) -> void:
	var enemy := actor as Enemy
	if enemy == null or enemy.def == null or not enemy.xp_eligible or not enemy.hero_credited():
		return
	var kill_xp: int = HeroProgression.kill_xp(enemy.def.xp_reward, enemy.level_scale)
	var total: int = kill_xp + bounty_xp
	if total <= 0:
		return
	HeroProgression.log_xp("kill: %s base=%d threat=%.2f kill=%d%s final=%d" % [enemy.display_name, enemy.def.xp_reward, enemy.level_scale, kill_xp,
		(" named bounty=%d" % bounty_xp) if bounty_xp > 0 else "", total])
	TownState.add_hero_xp(total, bounty_xp > 0)

## What the road as it stands now could pay in XP if all of it were cleared (developer diagnostic, `--xpreport`; changes nothing):
## {kills (ordinary, per kind too), kill_xp, nests, nest_xp, quest_xp (the standing quest), named (count), named_xp (their bounties and
## kill values, kept apart), total (kills + nests + quest, without the named extras)}.
func xp_report() -> Dictionary:
	var by_kind: Dictionary = {}
	var kills_n: int = 0
	var kill_total: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead or e.def == null or not e.xp_eligible or e.has_meta("monster_uid"):
			continue
		var xp: int = HeroProgression.kill_xp(e.def.xp_reward, e.level_scale)
		kills_n += 1
		kill_total += xp
		by_kind[e.variant] = int(by_kind.get(e.variant, 0)) + 1
	var nests: int = 0
	if location != null:
		nests = maxi(location.total_nests - location.nests_destroyed, 0)
	var quest_xp: int = 0
	for offer in TownState.board:
		quest_xp += int((offer as Dictionary).get("xp", 0))
	var named_n: int = 0
	var named_total: int = 0
	for mon in Monsters.alive():
		named_n += 1
		named_total += HeroProgression.named_xp(float(mon["level"]), int(mon.get("kills", 0)), not (mon["plot"] as Dictionary).is_empty())
	return {"kills": kills_n, "by_kind": by_kind, "kill_xp": kill_total, "nests": nests, "nest_xp": nests * HeroProgression.NEST_XP, "quest_xp": quest_xp,
		"named": named_n, "named_xp": named_total, "total": kill_total + nests * HeroProgression.NEST_XP + quest_xp}

## A dead monster may drop an item (see EnemyDef.drop_chance): it lands near the body and waits to be walked over.
func _drop_loot(actor: Actor) -> void:
	var enemy := actor as Enemy
	if enemy == null or enemy.def == null or randf() >= enemy.def.drop_chance * (Quests.world_mult("drop_mult") if world_mode else 1.0):
		return
	drop_item(enemy.global_position, Items.roll_drop(drop_tier(enemy.level_scale), enemy.def.drop_luck, owned_uniques()))

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
func _end_run(completed: bool, walked_out: bool = false) -> void:
	if _ending:
		return
	_ending = true
	var banner: String = "Job complete" if completed else ("Job abandoned" if walked_out else "You have fallen")
	hud.show_banner(banner, 3.0)
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
	if gold_per_kill > 0:
		TownState.gold += int(round(gold_per_kill * Quests.world_mult("gold_mult")))
	if world_mode:
		var named_xp: int = _report_to_quests(actor)
		_pay_kill_xp(actor, named_xp)
	player.on_enemy_killed(actor)
	_drop_loot(actor)
	await get_tree().process_frame
	if location != null:
		return   # an authored location has no waves: the job ends when the hero walks out through the gate
	if get_tree().get_nodes_in_group("enemies").size() == 0 and not selftest and not player.dead:
		if not job.is_empty() and JobObjective.is_complete(job, {"stage": wave}):
			_end_run(true)
		else:
			_wave_cleared()
