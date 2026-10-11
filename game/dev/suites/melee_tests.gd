extends DevSuite
## Self-test: melee feel (auto-attack, impacts, sword sounds, roll and dodge, fists, weapon styles, recoil, brutal attacks).

## Skewer: a Brute in the lane is staggered (not impaled); three zombies are impaled, ragdoll, get kicked off and
## thrown trailing blood, lie limp, then get back up. A fourth zombie is only shoved aside.
## A click attacks once; nothing keeps attacking afterwards, and skills drop the attack order.
func _test_auto_attack() -> void:
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	var dummy: Enemy = _spawn_enemy(Vector3(3.5, 0, 0))
	dummy.aggro_range = 0.0
	dummy.max_health = 5000.0
	dummy.health = 5000.0
	await get_tree().physics_frame
	# 1. Order an attack with the mouse NOT held: it should walk up and swing exactly once.
	player.attack_target = dummy
	player.click_mode = 1
	var swings: int = 0
	var was_busy: bool = false
	var facing_turns: float = 0.0
	var elapsed: float = 0.0
	while elapsed < 4.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if player.skills.busy and not was_busy and player.skills.busy_skill == "basic":
			swings += 1
		was_busy = player.skills.busy
	var idle_after: bool = not player.skills.busy and player.attack_target == null
	# 2. Standing idle with an enemy nearby must not turn the hero or start anything.
	var yaw_before: float = player.visual.rotation.y
	var busy_during_idle: bool = false
	for i in 90:
		await get_tree().physics_frame
		busy_during_idle = busy_during_idle or player.skills.busy
	var yaw_drift: float = absf(angle_difference(yaw_before, player.visual.rotation.y))
	# 3. A skill clears the attack order so the hero does not resume swinging when it ends.
	player.attack_target = dummy
	player.skills.start_skill("fireball", null, Vector3(0, 0, -6))
	var cleared_by_skill: bool = player.attack_target == null
	await get_tree().create_timer(2.0).timeout
	var swings_after_skill: bool = player.skills.busy and player.skills.busy_skill == "basic"
	expect("click attacks exactly once", swings == 1)
	expect("hero idles after a single click", idle_after)
	expect("hero does not swing or turn with no input", not busy_during_idle and absf(yaw_drift) < 0.02)
	expect("a skill clears the attack order", cleared_by_skill)
	expect("no swinging resumes after a skill", not swings_after_skill)
	print("  auto-attack: one click -> swings=", swings, " (expected 1), idle afterwards=", idle_after, ", idle with enemy near: busy=", busy_during_idle,
		" turned ", snappedf(rad_to_deg(yaw_drift), 0.1), " deg, skill clears attack order=", cleared_by_skill, ", resumed swinging after skill=", swings_after_skill)
	dummy.queue_free()
	await get_tree().process_frame

## Skewer catches knocked-down enemies; thrown bodies spread burn to enemies they hit and slam into props.
func _test_impact() -> void:
	player.global_position = Vector3(-25, 0, -25)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	var lying: Enemy = _spawn_enemy(Vector3(-25, 0, -29))
	lying.aggro_range = 0.0
	lying.max_health = 800.0
	lying.health = 800.0
	await get_tree().process_frame
	lying.ragdoll_launch(Vector3.ZERO, 0.0, Vector3.ZERO)
	var t: float = 0.0
	while t < 3.0 and not (lying.ragdoll != null and lying.ragdoll.state == Ragdoll.State.LYING):
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var was_lying: bool = lying.ragdoll != null and lying.ragdoll.state == Ragdoll.State.LYING
	player.skewer.start_skewer(Vector3(-25, 0, -40))
	var caught: bool = false
	t = 0.0
	while player.skills.busy and t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		caught = caught or player.skewer.skewer_impaled.has(lying)
	expect("skewer catches a downed enemy", was_lying and caught)
	print("  skewer vs downed enemy: was lying=", was_lying, " impaled it=", caught)
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(lying):
		lying.queue_free()

	# Burning body bowled into a bystander.
	var bystander: Enemy = _spawn_enemy(Vector3(32, 0, -13))
	var burner: Enemy = _spawn_enemy(Vector3(32, 0, -19))
	for e in [bystander, burner]:
		e.aggro_range = 0.0
		e.max_health = 500.0
		e.health = 500.0
	await get_tree().process_frame
	burner.apply_burn(5.0, 6.0)
	burner.apply_slow(0.4, 5.0)
	burner.ragdoll_launch(Vector3(0, 0, 12), 6.5, Vector3(4, 0, 0))   # same throw as the Skewer kick
	await get_tree().create_timer(1.0).timeout
	expect("a thrown burning body passes burn and slow on", bystander.is_burning() and bystander.slow_time > 0.0 and bystander.health < 500.0)
	print("  bowled: bystander burning=", bystander.is_burning(), " slowed=", bystander.slow_time > 0.0, " health=", snappedf(bystander.health, 0.1), "/500")
	bystander.queue_free()
	burner.queue_free()
	await get_tree().process_frame

	# Thrown into a wall.
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 3, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = Vector3(32, 1.5, -10)
	var flier: Enemy = _spawn_enemy(Vector3(32, 0, -16))
	flier.aggro_range = 0.0
	flier.max_health = 500.0
	flier.health = 500.0
	await get_tree().process_frame
	flier.ragdoll_launch(Vector3(0, 0, 13), 2.0, Vector3(5, 0, 0))
	await get_tree().create_timer(1.0).timeout
	expect("slamming into a wall hurts and stuns", flier.health < 500.0 and flier.stun_time > 2.0)
	print("  wall slam: health=", snappedf(flier.health, 0.1), "/500 stun left=", snappedf(flier.stun_time, 0.1))
	for e in [bystander, burner, flier]:
		if is_instance_valid(e):
			e.queue_free()
	wall.queue_free()
	await get_tree().process_frame

## Roll: immune for the whole roll, shoves non-boss enemies sideways and interrupts them; bosses stay put.
func _test_roll_shove() -> void:
	player.global_position = Vector3(20, 0, 20)
	player.reset_physics_interpolation()
	await get_tree().process_frame
	var near: Enemy = _spawn_enemy(player.global_position + Vector3(1.4, 0, 0.1))
	var attacker: Enemy = _spawn_enemy(player.global_position + Vector3(2.4, 0, -0.1))
	# The boss stands off to the side of the other two so zombies being shoved cannot bump it.
	var boss: Enemy = _spawn_enemy(player.global_position + Vector3(2.0, 0, 6.0), "brute")
	boss.is_boss = true
	for e in [near, attacker, boss]:
		e.aggro_range = 0.0
	await get_tree().process_frame
	# Put one zombie mid-attack so we can see it get interrupted.
	attacker._attacking = true
	attacker.model.manual("attack")
	var start: Vector3 = player.global_position
	var near_start: Vector3 = near.global_position
	var attacker_start: Vector3 = attacker.global_position
	var boss_start: Vector3 = boss.global_position
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(player.global_position + Vector3(8, 0, 0))
	var immune_late: bool = false
	boss.global_position = player.global_position + Vector3(2.4, 0, 0.9)  # inside the roll corridor
	boss_start = boss.global_position
	for i in 40:
		await get_tree().physics_frame
		if player.movement.rolling and player.movement.roll_t > ROLL_CHECK_TIME and player.invulnerable_time > 0.0:
			immune_late = true
	await get_tree().create_timer(0.3).timeout
	var lateral_near: float = absf(near.global_position.z - near_start.z)
	var lateral_attacker: float = absf(attacker.global_position.z - attacker_start.z)
	var boss_moved: float = boss.global_position.distance_to(boss_start)
	expect("roll shoves non-bosses aside", lateral_near > 0.3 and lateral_attacker > 0.3)
	expect("roll interrupts an attacker", not attacker._attacking)
	expect("roll is immune late in the roll", immune_late)
	print("  roll shove: near moved sideways ", snappedf(lateral_near, 0.1), " m, attacker ", snappedf(lateral_attacker, 0.1),
		" m (interrupted=", not attacker._attacking, "), boss displaced ", snappedf(boss_moved, 0.1), " m, immune late in roll=", immune_late)
	for e in [near, attacker, boss]:
		e.queue_free()
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	await get_tree().process_frame

const ROLL_CHECK_TIME := 0.4

func _test_sword_sound() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in game.get_children():
		if node is Projectile:   # a fireball left flying by an earlier check would land mid-test and play its impact sound
			node.queue_free()
	await get_tree().process_frame
	var was_enabled: bool = Sfx.enabled
	Sfx.enabled = true
	expect("both sword sound files are in the project", ResourceLoader.exists("res://assets/audio/sword_hit.ogg") and ResourceLoader.exists("res://assets/audio/sword_hit_2.wav"))
	# The sounds are randomised, never the same recording twice in a row, and both get used.
	var used: Dictionary = {}
	var repeated: bool = false
	var previous: String = ""
	for i in 40:
		Sfx._last_played.clear()
		Sfx.sample(self, "sword_hit")
		used[Sfx.last_name] = true
		repeated = repeated or Sfx.last_name == previous
		previous = Sfx.last_name
	expect("the sword hit sound is randomised between both recordings", used.size() == 2 and not repeated)
	Sfx._last_played.clear()
	var enemy: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -3))
	enemy.aggro_range = 0.0
	enemy.max_health = 5000.0
	enemy.health = 5000.0
	await get_tree().process_frame
	Sfx.played_log.clear()
	var hit: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
	hit["skill_id"] = "basic"
	enemy.receive(hit, player.global_position)
	expect("a sword hit plays the sound", _logged("sword_hit") == 1 and _logged("sword_miss") == 0)
	await get_tree().create_timer(0.1).timeout
	var miss: Dictionary = {"outcome": Combat.Outcome.MISS, "damage": 0.0, "source": player, "skill_id": "basic"}
	enemy.receive(miss, player.global_position)
	expect("a missed swing plays a swing sound, not the hit sound", _logged("sword_hit") == 1 and _logged("sword_miss") == 1)
	await get_tree().create_timer(0.1).timeout
	var block: Dictionary = {"outcome": Combat.Outcome.BLOCK, "damage": 0.0, "source": player, "skill_id": "basic", "weight": 1.0}
	enemy.receive(block, player.global_position)
	expect("a block plays neither", Sfx.played_log.size() == 2)
	await get_tree().create_timer(0.1).timeout
	for other in ["skewer_kick", "earthshatter", "fireball"]:
		var odd: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
		odd["skill_id"] = other
		enemy.receive(odd, player.global_position)
		await get_tree().create_timer(0.1).timeout
	expect("a boot, a shockwave or a fireball is not the sword", Sfx.played_log.size() == 2)
	var secondary: Dictionary = Combat.resolve(player, enemy, 20.0, Combat.DamageType.PHYSICAL, false, 1.0)
	secondary["skill_id"] = "power"
	secondary["secondary"] = true
	enemy.receive(secondary, player.global_position)
	expect("splash damage is not a sword hit either", Sfx.played_log.size() == 2)
	await get_tree().create_timer(0.1).timeout
	# The four swing recordings are all used, never the same twice running.
	Sfx.played_log.clear()
	var repeats: bool = false
	for i in 60:
		Sfx._last_played.clear()
		Sfx.sample(self, "sword_miss")
		if Sfx.played_log.size() >= 2 and Sfx.played_log[-1] == Sfx.played_log[-2]:
			repeats = true
	var distinct: Dictionary = {}
	for name in Sfx.played_log:
		distinct[name] = true
	expect("all four swing sounds are used and none repeats back to back", distinct.size() == 4 and not repeats)
	Sfx.enabled = was_enabled
	enemy.queue_free()
	await get_tree().process_frame

## Any time the sword swings and finds nothing, a swing sound plays: a swing at a target that is out of reach, a Power Strike with nobody
## around, a Leap chop on open ground.
func _test_sword_miss_in_air() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var was_enabled: bool = Sfx.enabled
	Sfx.enabled = true
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	# A swing at an enemy that is out of reach by the time the blow lands.
	var far: Enemy = _spawn_enemy(Vector3(0, 0, -9))
	far.aggro_range = 0.0
	await get_tree().process_frame
	Sfx._last_played.clear()
	Sfx.played_log.clear()
	player.skills.start_skill("basic", far, far.global_position)
	var t: float = 0.0
	while player.skills.busy and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a swing that cannot reach its target makes the swing sound", _logged("sword_miss") == 1 and _logged("sword_hit") == 0)
	far.queue_free()
	await get_tree().process_frame
	# A Power Strike with nobody in range.
	await get_tree().create_timer(0.2).timeout
	Sfx._last_played.clear()
	Sfx.played_log.clear()
	player.skills.start_skill("power", null, player.global_position + Vector3(0, 0, -3))
	t = 0.0
	while player.skills.busy and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a Power Strike through empty air makes the swing sound", _logged("sword_miss") == 1)
	# A Leap chop onto open ground.
	player.stats.cooldowns.clear()
	Sfx._last_played.clear()
	Sfx.played_log.clear()
	player.skills.try_directional("leap", player.global_position + Vector3(0, 0, -6))
	t = 0.0
	while player.skills.busy and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	expect("a Leap chop on bare ground makes the swing sound", _logged("sword_miss") == 1)
	expect("the Leap landing plays its impact sound once", _logged("leap_land") == 1)
	# And when it does connect there is no swing sound.
	var near: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -1.6))
	near.aggro_range = 0.0
	near.max_health = 3000.0
	near.health = 3000.0
	await get_tree().process_frame
	for attempt in 8:   # a swing can also be dodged (that is a miss): swing until one connects
		player.stats.cooldowns.clear()
		Sfx._last_played.clear()
		Sfx.played_log.clear()
		player.skills.start_skill("power", near, near.global_position)
		t = 0.0
		while player.skills.busy and t < 3.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		if _logged("sword_hit") >= 1 and _logged("sword_miss") == 0:   # (a swing that also whiffed on someone else is not the case under test)
			break
		await get_tree().create_timer(0.1).timeout
	expect("a Power Strike that connects makes the hit sound, not the swing sound", _logged("sword_hit") >= 1 and _logged("sword_miss") == 0)
	near.queue_free()
	Sfx.enabled = was_enabled
	await get_tree().process_frame

## A dodge always wins over an auto attack: it is dropped mid-swing, and a still-held attack button does not start another one afterwards.
func _test_dodge_cancels_attack() -> void:
	player.global_position = _free_lane_start(8.0, 6.0)
	player.reset_physics_interpolation()
	player.stats.cooldowns.clear()
	player.stats.stamina = player.stats.max_stamina
	var foe: Enemy = _spawn_enemy(player.global_position + Vector3(1.4, 0, 0))
	foe.aggro_range = 0.0
	foe.max_health = 900.0
	foe.health = 900.0
	await get_tree().process_frame
	player.attack_target = foe
	player.skills.start_skill("basic", foe)
	await get_tree().create_timer(0.1).timeout   # still gathering the swing: the blade has not come down
	expect("the swing is under way and has not landed", player.skills.busy and not player.skills.busy_hit_done)
	Input.action_press("alt_skill")   # the attack button is still held
	player.movement.try_roll(player.global_position + Vector3(-5, 0, 0))
	expect("a dodge pressed in the middle of an auto attack goes through", player.movement.rolling)
	expect("and the attack is dropped", not player.skills.busy and player.attack_target == null and player.skills.queued_skill == "")
	await get_tree().create_timer(1.0).timeout
	var swung: bool = player.skills.busy
	Input.action_release("alt_skill")
	expect("the held attack button does not start another swing after the roll", not swung)
	foe.queue_free()

func _test_brutal_attack() -> void:
	GameSettings.reset_hotbar()
	expect("the default loadout contains the two party powers and the basic attack",
		GameSettings.hotbar_slots == ["brutal_attack", "take_aim", "", "", "", ""] and GameSettings.hotbar_alt == "basic")
	var skills: SkillController = player.skills
	skills.cancel_action()
	player.stats.brutal_reload_remaining = 0.0
	var priority_target: Enemy = _spawn_enemy(player.global_position + Vector3(0.0, 0.0, -1.7))
	priority_target.aggro_range = 0.0
	player.attack_target = priority_target
	skills.start_skill("basic", priority_target)
	await get_tree().create_timer(0.08).timeout
	skills.activate_brutal_attack()
	expect("Brutal Attack interrupts the ordinary swing and begins its powered blow immediately",
		skills.brutal_armed and skills._brutal_aura != null and skills.busy and skills.busy_skill == "basic"
		and bool(skills.busy_def.get("brutal_animation", false)) and skills.busy_t < 0.08)
	skills.cancel_action()
	priority_target.queue_free()
	player.attack_target = null
	skills.combo_step = 2
	var brutal_animation: Dictionary = skills._next_basic()
	expect("an armed Brutal Attack replaces the basic combo with its own short heavy windup",
		bool(brutal_animation.get("brutal_animation", false)) and brutal_animation["clip"] == "power"
		and float(brutal_animation["time"]) > 1.0 and float(brutal_animation["weight"]) > 2.0 and skills.combo_step == 0)
	# A complete basic swing into empty space must leave the stored power untouched.
	skills.busy_skill = "basic"
	skills.busy_target = null
	skills.busy_aim = player.global_position + Vector3(0.0, 0.0, -2.0)
	skills._apply_skill(SkillDb.all()["basic"])
	expect("a missed Brutal Attack is not consumed", skills.brutal_armed and player.stats.brutal_reload_remaining == 0.0)
	var victim: Enemy = _spawn_enemy(player.global_position + Vector3(0.0, 0.0, -1.7))
	victim.max_health = 10000.0
	victim.health = victim.max_health
	victim.armor = 0.0
	var before: float = victim.health
	skills.busy_target = victim
	skills._apply_skill(SkillDb.all()["basic"])
	# Use the production helper so the test observes the same minimum level guard as a fresh new-game save.
	var expected_reload: float = player.stats.brutal_recharge_damage()
	expect("the next successful basic hit spends Brutal Attack and deals its amplified weapon damage",
		not skills.brutal_armed and is_equal_approx(player.stats.brutal_reload_remaining, expected_reload)
		and is_equal_approx(player.stats.brutal_reload_required, expected_reload) and before - victim.health > player.stats.weapon_range(1.0).y * 5.0)
	player.on_dealt_hit(victim, {"outcome": Combat.Outcome.HIT, "damage": 90.0, "skill_id": "basic"})
	expect("ordinary combat damage subtracts from DS2's reload-damage budget",
		is_equal_approx(player.stats.brutal_reload_remaining, expected_reload - 90.0))
	player.on_dealt_hit(victim, {"outcome": Combat.Outcome.HIT, "damage": 999.0, "skill_id": "brutal_attack"})
	expect("Brutal Attack does not recharge itself", is_equal_approx(player.stats.brutal_reload_remaining, expected_reload - 90.0))
	var gibs_before: int = get_tree().get_nodes_in_group("gibs").size()
	victim.health = 1.0
	var brutal_kill: Dictionary = Combat.resolve(player, victim, 10.0, Combat.DamageType.PHYSICAL, false, 1.0, false)
	brutal_kill["outcome"] = Combat.Outcome.HIT   # prove the skill, not a crit/crushing roll, causes the gib
	brutal_kill["damage"] = 10.0
	brutal_kill["skill_id"] = "brutal_attack"
	victim.receive(brutal_kill, player.global_position)
	expect("a lethal Brutal Attack gibs the enemy",
		victim.dead and not victim.visual.visible and get_tree().get_nodes_in_group("gibs").size() > gibs_before)
	victim.queue_free()
	for node in get_tree().get_nodes_in_group("gibs"):
		node.queue_free()
	skills.cancel_action()

## Weapons have a moveset of their own: the falchion recovers fast, staggers lightly and finishes its combo quickly; the longsword is the
## baseline; the greatsword hits a wide arc, staggers and knocks back harder, recovers slowly and finishes with a slam.
## Both hands are closed gauntlets round the grip (the open Meshy hands are shrunk away), and standing about long enough rests the sword on his shoulder.
func _test_fists() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var model: CharacterModel = player.model
	await get_tree().create_timer(0.3).timeout
	expect("each hand has its own closed fist", model._mounts.size() == 2 and model._mounts["RightHand"].get_child_count() >= 1
		and model._mounts["LeftHand"].get_child_count() == 1)
	expect("the sword is held by the right fist's mount", model.weapon != null and model.weapon.get_parent() == model._mounts["RightHand"])
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	expect("the open hand meshes are shrunk away inside the wrists", skeleton.get_bone_pose_scale(skeleton.find_bone("RightHand")).x < 0.1
		and skeleton.get_bone_pose_scale(skeleton.find_bone("LeftHand")).x < 0.1)
	expect("the fist is not shrunk with them", (model._mounts["RightHand"] as Node3D).transform.basis.get_scale().x > 0.5)
	player.combat_timer = 0.0
	player.movement.idle_time = 0.0
	player.movement.update_locomotion_anim()
	expect("standing about he is alert at first", model.current == "idle_alert")
	player.movement.idle_time = PlayerMovement.REST_AFTER + 1.0
	player.movement.update_locomotion_anim()
	expect("after a while he rests the sword on his shoulder", model.current == "idle_rest")
	player.combat_timer = 3.0
	player.movement.update_locomotion_anim()
	expect("in a fight he is alert again", model.current == "idle_alert")
	player.movement.idle_time = 0.0

## A two-hander swings its own clips (both hands on the grip); the one-handers swing theirs, and no basic swing leaves a blade ribbon.
func _test_two_hand() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	var skills: SkillController = player.skills
	var seen: Dictionary = {}
	for base in ["Falchion", "Greatsword"]:
		player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, base), false)
		var clips: Array[String] = []
		for step in 3:
			var far: Enemy = _spawn_enemy(Vector3(0, 0, 14))
			far.alert_delay = 999.0
			skills.combo_step = step
			skills.start_skill("basic", far)
			clips.append(player.model.current)
			expect("%s swing %d has a blade ribbon only when it is not a basic swing" % [base, step], not player._trail.active)
			skills.cancel_action()
			far.queue_free()
		seen[base] = clips
	var one: Array = seen["Falchion"]
	var two: Array = seen["Greatsword"]
	expect("a falchion swings the one-handed clips", one.all(func(c: String) -> bool: return c.begins_with("atk_")))
	expect("a greatsword swings the two-handed clips", two.all(func(c: String) -> bool: return c.begins_with("atk2_")))
	expect("a greatsword recovers slower than it did", float(player.stats.weapon_profile("recovery", 1.0)) <= 0.6)

func _test_weapon_styles() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	var skills: SkillController = player.skills
	var swing_time: Dictionary = {}
	var finisher_time: Dictionary = {}
	var actual_finisher: Dictionary = {}   # how long the finisher really takes, swing speed and recovery included
	var weights: Dictionary = {}
	var swept: Dictionary = {}
	var slammed: Dictionary = {}
	var base_time: float = float(SkillDb.basic_combo()[2][0]["time"])
	for base in ["Falchion", "Longsword", "Greatsword"]:
		player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, base), false)
		# How long a first swing takes from start to recovered (stepped by hand so engine time cannot blur it).
		var far: Enemy = _spawn_enemy(Vector3(0, 0, 14))
		far.alert_delay = 999.0
		skills.combo_step = 0
		skills.start_skill("basic", far)
		var steps: int = 0
		while skills.busy and steps < 900:
			skills.tick_busy(1.0 / 60.0)
			steps += 1
		swing_time[base] = steps / 60.0
		far.queue_free()
		skills.combo_step = 2
		finisher_time[base] = float(skills._next_basic()["time"])
		skills.combo_step = 2
		skills.start_skill("basic", _spawn_enemy(Vector3(0, 0, 14)))
		var fsteps: int = 0
		while skills.busy and fsteps < 900:
			skills.tick_busy(1.0 / 60.0)
			fsteps += 1
		actual_finisher[base] = fsteps / 60.0
		# What one swing does to enemies around the target (the timed swing above lunged the hero forward: back to the origin).
		player.global_position = Vector3.ZERO
		player.reset_physics_interpolation()
		var target: Enemy = _spawn_enemy(Vector3(0, 0, 1.6))
		var left: Enemy = _spawn_enemy(Vector3(1.4, 0, 1.2))
		var right: Enemy = _spawn_enemy(Vector3(-1.3, 0, 1.3))
		var behind: Enemy = _spawn_enemy(Vector3(0, 0, -1.5))
		var group: Array[Enemy] = [target, left, right, behind]
		for e in group:
			e.alert_delay = 999.0
			e.max_health = 5000.0
			e.health = 5000.0
			e.dodge_chance = 0.0   # (DS2: a blow lands unless dodged or blocked)
			e.block_chance = 0.0
		skills.busy_skill = "basic"
		skills.busy_target = target
		skills.busy_aim = target.global_position
		var plain: Dictionary = SkillDb.all()["basic"].duplicate()
		plain.merge(SkillDb.basic_combo()[0][0], true)
		weights[base] = 0.0
		for attempt in 8:
			skills._apply_skill(plain)
			if not target.last_result.is_empty():
				weights[base] = float(target.last_result.get("weight", 0.0))
		swept[base] = int(left.health < 5000.0) + int(right.health < 5000.0) + int(behind.health < 5000.0)
		for e in group:
			e.health = 5000.0
			e.stun_time = 0.0
		var finisher: Dictionary = SkillDb.all()["basic"].duplicate()
		finisher.merge(SkillDb.basic_combo()[2][0], true)
		skills._apply_skill(finisher)
		slammed[base] = int(left.stun_time > 0.0) + int(right.stun_time > 0.0) + int(behind.stun_time > 0.0)
		for e in group:
			e.queue_free()
		await get_tree().process_frame
	expect("a falchion recovers faster than a longsword, a greatsword slower", swing_time["Falchion"] < swing_time["Longsword"] - 0.1
		and swing_time["Greatsword"] > swing_time["Longsword"] + 0.1)
	expect("a falchion's finisher is short and a greatsword's is not", absf(finisher_time["Falchion"] - base_time * 0.9) < 0.001 and absf(finisher_time["Longsword"] - base_time) < 0.001
		and absf(finisher_time["Greatsword"] - base_time) < 0.001)
	expect("a falchion's finisher really takes about 0.8 s (longsword 1.3 s), readable from wind-up to finish", actual_finisher["Falchion"] > 0.7
		and actual_finisher["Falchion"] < 0.9 and absf(actual_finisher["Longsword"] - base_time) < 0.05 and actual_finisher["Greatsword"] > actual_finisher["Longsword"])
	expect("stagger weight rises falchion < longsword < greatsword", weights["Falchion"] < weights["Longsword"] - 0.15 and weights["Greatsword"] > weights["Longsword"] + 0.3)
	expect("only the greatsword's swing reaches the others in an arc in front (not behind)", swept["Falchion"] == 0 and swept["Longsword"] == 0 and swept["Greatsword"] == 2)
	expect("only the greatsword's finisher slams the ground in front", slammed["Falchion"] == 0 and slammed["Longsword"] == 0 and slammed["Greatsword"] >= 2)
	expect("the tooltip says how the weapon fights", Items.lines(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "Greatsword")).any(
		func(line: String) -> bool: return line.contains("slam")))
	player.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "Longsword"), false)

## Standing monsters take a blow in the body: the chest tips away from it, overshoots and settles (BodyRecoil + CharacterModel._apply_hit_reaction).
func _test_body_recoil() -> void:
	await get_tree().process_frame
	# The spring on its own: heavier blows lean further, big monsters lean less, it overshoots once, and comes to rest.
	var light: float = BodyRecoil.peak_for(0.7, 1.0, 0.0)
	var crushing: float = BodyRecoil.peak_for(1.5, 2.2, 0.0)
	var heavy_big: float = BodyRecoil.peak_for(1.5, 2.2, 0.8)
	expect("a crushing blow tips the body further than a light one", crushing > light * 3.0 and crushing <= BodyRecoil.MAX_LEAN)
	expect("a monster that resists knock-back leans less", heavy_big < crushing * 0.7)
	var spring := BodyRecoil.new()
	spring.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.3, 0.0)
	var peak: float = 0.0
	var crossed: bool = false
	for i in 120:
		spring.step(1.0 / 60.0)
		peak = maxf(peak, spring.lean.length())
		if spring.lean.y > 0.01:
			crossed = true   # it rocked back past upright (the blow pushed toward -z)
	expect("the lean reaches about the asked-for peak, in the direction of the blow", peak > 0.2 and peak < 0.45)
	expect("it overshoots upright once (momentum recovery)", crossed)
	for i in 120:
		spring.step(1.0 / 60.0)
	expect("and it comes to rest", not spring.active())
	var stepper := BodyRecoil.new()
	stepper.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.32, 0.0)
	var first_leg: int = stepper.step_leg
	var mild := BodyRecoil.new()
	mild.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.1, 0.0)
	expect("a heavy blow costs a recovery step, a light one does not", stepper.step_t > 0.0 and mild.step_t <= 0.0 and stepper.step_swing() >= 0.0)
	for i in 90:
		stepper.step(1.0 / 60.0)
	stepper.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.32, 0.0)
	expect("the next step uses the other leg", stepper.step_leg != first_leg)
	var sideways := BodyRecoil.new()
	sideways.hit(Vector3(1, 0, 0), Vector3(0, 0, 1), 0.3, 0.0)
	var straight := BodyRecoil.new()
	straight.hit(Vector3(0, 0, -1), Vector3(0, 0, 1), 0.3, 0.0)
	expect("a blow from the side turns the shoulders, one from the front does not", absf(sideways.twist_vel) > 0.5 and absf(straight.twist_vel) < 0.01)
	# On real monsters: every body has a spine to bend, and a landed blow moves it and then settles.
	for variant in ["zombie", "ghoul", "spitter", "bloater", "brute", "priest"]:
		var body: Enemy = _spawn_enemy(Vector3(-30, 0, -30), variant)
		body.aggro_range = 0.0
		body.max_health = 5000.0
		body.health = 5000.0
		await get_tree().process_frame
		body.model._find_reaction_bones()
		expect("%s has a spine to bend" % variant, body.model._spine.size() >= 1)
		body.queue_free()
	var target: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -6.0), "zombie")
	target.aggro_range = 0.0
	target.max_health = 5000.0
	target.health = 5000.0
	await get_tree().create_timer(0.4).timeout
	var blow: Dictionary = {"outcome": Combat.Outcome.CRITICAL, "damage": 5.0, "weight": 2.2, "source": player,
		"type": Combat.DamageType.PHYSICAL, "skill_id": "basic"}
	target.receive(blow, target.global_position + Vector3(0, 0, 3.0))
	var seen: float = 0.0
	for i in 40:
		await get_tree().physics_frame
		seen = maxf(seen, target.model.reaction.lean.length())
	expect("a heavy critical blow on a standing zombie tips its spine (peak %.2f rad)" % seen, seen > 0.15)
	expect("and the zombie has thighs to step with", target.model._thighs.size() == 2 and target.model._thighs[0] > 0 and target.model._thighs[1] > 0)
	await get_tree().create_timer(1.8).timeout
	expect("and it recovers", not target.model.reaction.active())
	# Every blow interrupts a small monster, even a light one, and a blow while it is still reeling restarts the reaction.
	target.stun_time = 0.0
	var light_blow: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": 1.0, "weight": 0.5, "source": player,
		"type": Combat.DamageType.PHYSICAL, "skill_id": "basic"}
	var every_time: bool = true
	for i in 4:
		target.stun_time = 0.0
		target.receive(light_blow, target.global_position + Vector3(0, 0, 3.0))
		every_time = every_time and target.stun_time >= 0.1
	expect("a light blow interrupts a small monster every time", every_time)
	var serial: int = target.flinch_serial
	target.receive(light_blow, target.global_position + Vector3(0, 0, 3.0))
	expect("each blow counts, so the hit pose can restart", target.flinch_serial == serial + 1)
	target.queue_free()
