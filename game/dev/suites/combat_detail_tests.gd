extends DevSuite
## Focused power presentation checks and observations for the DS2 detail audit.

func _test_armed_power_fx() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	player.set_physics_process(false)
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.attack_target = null
	player.hover_target = null
	player.skills.reset()
	TownState.passive_ranks["critical_strike"] = 1
	player.stats.brutal_reload_remaining = 0.0
	player.skills.activate_brutal_attack()
	var hero_aura: Node3D = player.skills._brutal_aura
	player.skills.activate_brutal_attack()
	expect("arming Brutal Attack out of combat immediately creates one body aura without starting an attack",
		player.skills.brutal_armed and hero_aura != null and hero_aura == player.skills._brutal_aura and not player.skills.busy)
	var archer: ArcherCompanion = game.companion
	archer.testing_disabled = true
	archer.target = null
	archer.global_position = Vector3(2.0, 0.0, 0.0)
	archer.reset_physics_interpolation()
	archer.take_aim_armed = false
	archer._clear_take_aim_visual()
	archer.activate_take_aim_now()
	var bow_aura: BrutalAttackFx = archer._take_aim_aura
	archer.activate_take_aim_now()
	expect("Take Aim uses DS2's shared orange body pre-launch aura, including without an enemy",
		archer.take_aim_armed and bow_aura != null and bow_aura.emitters.size() >= 12 and bow_aura == archer._take_aim_aura)
	await get_tree().create_timer(0.8).timeout
	expect("both stored powers retain their glow after a brief activation flash would have expired",
		is_instance_valid(hero_aura) and is_instance_valid(bow_aura) and player.skills.brutal_armed and archer.take_aim_armed)
	await _power_fx_capture("armed")
	SkillFx.take_aim_charge(archer._bow_holder)
	var gather := archer._bow_holder.get_node_or_null("TakeAimCharge") as CPUParticles3D
	expect("Take Aim's shot gathers 30 pale motes at the bow hand over 0.4 seconds",
		gather != null and gather.amount == 30 and is_equal_approx(gather.lifetime, 0.4) and gather.local_coords)
	await get_tree().create_timer(0.2).timeout
	await _power_fx_capture("bow_charge")
	archer._cancel_draw(true)
	expect("aborting a draw preserves the stored Take Aim and its aura", archer.take_aim_armed and archer._take_aim_aura == bow_aura)
	archer.spend_take_aim()
	expect("release/spend clears the Take Aim aura immediately", archer._take_aim_aura == null and not archer.take_aim_armed)
	archer.arm_take_aim()
	archer.dead = true
	archer._physics_process(0.01)
	expect("Cutter's death clears the armed aura", archer._take_aim_aura == null)
	archer.dead = false
	archer.take_aim_armed = false
	player.skills.reset()
	expect("hero reset/death clears the armed aura", player.skills._brutal_aura == null and not player.skills.brutal_armed)
	player.set_physics_process(true)

func _power_fx_capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	rig.set_process(false)
	rig.camera.global_position = Vector3(3.6, 3.2, 5.5)
	rig.camera.look_at(Vector3(1.0, 1.0, 0.0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_power_%s.png" % label)

## These lock observed Curse behaviour, not claims about DS2's closed engine.
func _test_hit_interruption_audit() -> void:
	player.set_physics_process(false)
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.invulnerable_time = 0.0
	player.knockdown.cancel()
	player.skills.reset()
	var enemy: Enemy = _spawn_enemy(Vector3(0, 0, 1.7))
	enemy.set_physics_process(false)
	enemy.target = player
	enemy.max_health = 5000.0
	enemy.health = 5000.0
	enemy.stun_resist = 0.0
	var melee := enemy.behavior as MeleeBehavior
	melee._active = true
	enemy._attacking = true
	enemy.receive({"outcome": Combat.Outcome.HIT, "damage": 1.0, "weight": 1.0, "source": player, "skill_id": "basic"}, player.global_position)
	enemy.hitpause = 0.0
	enemy._physics_process(0.01)
	expect("Curse: an ordinary hit cancels a small enemy's committed attack", not melee._active and not enemy._attacking and enemy.stun_time > 0.0)
	player.skills.start_skill("basic", enemy)
	player.receive({"outcome": Combat.Outcome.HIT, "damage": 1.0, "weight": 1.0, "source": enemy, "skill_id": "enemy_melee"}, enemy.global_position)
	expect("Curse: an ordinary enemy hit does not cancel the hero's committed attack", player.skills.busy and not player.knockdown.active())
	player.receive({"outcome": Combat.Outcome.HIT, "damage": 1.0, "weight": 2.5, "source": enemy, "skill_id": "enemy_melee"}, enemy.global_position)
	expect("Curse: a heavy enemy hit knocks down the hero and cancels the attack", player.knockdown.active() and not player.skills.busy)
	player.knockdown.cancel()
	var archer: ArcherCompanion = game.companion
	archer.testing_disabled = false
	archer._draw = 0.5
	archer.hitpause = 0.0
	archer.stun_time = 1.0
	archer._physics_process(0.01)
	expect("Curse: stun pauses Cutter's draw progress rather than restarting it", is_equal_approx(archer._draw, 0.5))
	archer.stun_time = 0.0
	archer._cancel_draw(true)
	archer.testing_disabled = true
	enemy.queue_free()
	player.stun_time = 0.0
	player.hitpause = 0.0
	player.set_physics_process(true)
