extends DevSuite
## Event timing and lifecycle for the owner's recorded power-sound composites.

func _test_power_audio() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var was_enabled: bool = Sfx.enabled
	Sfx.enabled = true
	player.set_physics_process(false)
	player.global_position = _free_lane_start(12.0, 3.0)
	player.reset_physics_interpolation()
	var archer: ArcherCompanion = game.companion
	archer.set_physics_process(false)
	archer.testing_disabled = true
	archer.target = null
	archer._clear_take_aim_visual()
	archer.take_aim_armed = false
	archer.global_position = player.global_position + Vector3(1, 0, 0)
	archer.reset_physics_interpolation()
	Sfx.played_log.clear()
	Sfx._last_played.clear()
	archer.arm_take_aim()
	expect("arming Take Aim without a target does not loop or start its draw sound", _logged("take_aim") == 0)
	var victim: Enemy = _spawn_enemy(player.global_position + Vector3(11, 0, 0))
	victim.set_physics_process(false)
	victim.max_health = 5000.0
	victim.health = 5000.0
	victim.target = player
	victim.wake()
	archer.target = victim
	archer.testing_disabled = false
	archer._scan_left = 100.0
	archer._cooldown = 0.0
	archer._draw = 0.0
	await get_tree().physics_frame
	archer._physics_process(0.01)
	expect("powered draw starts one charge sound, without a release or impact", _logged("take_aim_charge") == 1 and _logged("take_aim_fire") == 0 and _logged("take_aim_hit") == 0)
	archer._physics_process(0.01)
	expect("continuing the draw does not restart the charge sample", _logged("take_aim_charge") == 1)
	archer._cancel_draw(true)
	expect("aborting before release does not play the shot sound", _logged("take_aim_fire") == 0 and archer.take_aim_armed)
	archer._loose()
	expect("the release sound plays exactly when the empowered arrow is created", _logged("take_aim_fire") == 1 and not archer.take_aim_armed)
	# Drive the actual projectile contact path deterministically; no incidental ray hits.
	for node in game.get_children():
		if node is CompanionArrow:
			node.queue_free()
	var arrow := CompanionArrow.fire(game, archer, archer.global_position + Vector3.UP, victim.global_position + Vector3.UP, 1.0, true)
	arrow.set_physics_process(false)
	arrow._hit_enemy(victim, archer.global_position)
	expect("Take Aim impact plays once on the resolved hit, without an extra sword hit", _logged("take_aim_hit") == 1 and _logged("sword_hit") == 0)
	var hit := {"outcome": Combat.Outcome.HIT, "damage": 1.0, "source": player, "skill_id": "brutal_attack", "weight": 1.0}
	victim.receive(hit, player.global_position)
	expect("Brutal contact replaces ordinary sword audio with one layered power impact", _logged("brutal_hit") == 1 and _logged("sword_hit") == 0)
	var count: int = Sfx.played_log.size()
	for skill in ["brutal_attack", "take_aim"]:
		for outcome in [Combat.Outcome.MISS, Combat.Outcome.BLOCK]:
			victim.receive({"outcome": outcome, "damage": 0.0, "source": archer, "skill_id": skill, "weight": 1.0}, archer.global_position)
	expect("misses and blocks never play the power impact", Sfx.played_log.size() == count)
	Sfx.enabled = false
	Sfx._last_played.clear()
	Sfx.power(player, "brutal_hit")
	expect("power cues obey the Sound Effects switch", Sfx.played_log.size() == count)
	Sfx.enabled = true
	for i in 4:
		Sfx._last_played.clear()
		Sfx.power(player, "brutal_hit")
	await get_tree().physics_frame
	var playing: int = 0
	for node in get_tree().get_nodes_in_group("power_audio_brutal_hit"):
		var voice := node as AudioStreamPlayer3D
		if voice.playing:
			playing += 1
			expect("power voice is spatial, distance-limited and conservatively pitched", voice.max_distance == 30.0 and voice.unit_size == 7.0 and voice.pitch_scale >= 0.9 and voice.pitch_scale <= 1.1 and voice.bus == &"PowerFx")
	expect("new contacts retire old tails instead of stacking unlimited power voices", playing == 2)
	var bus: int = AudioServer.get_bus_index("PowerFx")
	expect("power overlap has its own limiter, without changing the Master bus", bus > 0 and AudioServer.get_bus_effect(bus, 0) is AudioEffectLimiter)
	for event in Sfx.POWER_AUDIO.EVENTS:
		var stream: AudioStream = load("res://assets/audio/powers/%s.wav" % event)
		expect("layered cue is imported and has the intended bounded duration: " + event, stream != null and stream.get_length() > 1.0 and stream.get_length() < 2.5)
	# Audible sequential demonstration only for an explicitly visible developer run.
	if DisplayServer.get_name() != "headless":
		for node in get_tree().get_nodes_in_group("sfx_voice"):
			node.queue_free()
		await get_tree().process_frame
		for event in Sfx.POWER_AUDIO.EVENTS:
			Sfx._last_played.clear()
			Sfx.power(player, event)
			print("POWER_AUDIO_DEMO ", event)
			await get_tree().create_timer(2.8).timeout
	for node in get_tree().get_nodes_in_group("sfx_voice"):
		node.queue_free()
	if is_instance_valid(arrow):
		arrow.queue_free()
	victim.queue_free()
	archer._clear_take_aim_visual()
	archer._cancel_draw(true)
	archer.target = null
	archer.testing_disabled = true
	archer.set_physics_process(true)
	player.set_physics_process(true)
	Sfx.enabled = was_enabled
