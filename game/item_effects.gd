class_name ItemEffects
extends RefCounted
## What equipped item affixes actually do. Player/Actor call these hooks at the matching moments;
## everything here is a behaviour change, not a stat. Hits made by an effect are flagged "secondary"
## so effects never trigger other effects endlessly.

const HASTE_BONUS := 0.30                 # attack speed bonus while PlayerStats.haste_time runs
const KINDLING_BONUS := 1.5               # Kindling: hits on burning enemies
const JUGGLER_BONUS := 1.8                # Juggler's: hits on airborne enemies
const VIRTUOSO_STEP := 0.2                # Virtuoso: damage per stack
const VIRTUOSO_MAX := 3
const VIRTUOSO_WINDOW := 4.0
const VAULT_WINDOW := 4.0                 # Vaultborn: seconds after a Leap lands in which Power Strike is free
const QUAKER_CHARGE := 0.04               # Quakebound: share of the ultimate each kill charges

# --- damage dealt -----------------------------------------------------------

static func outgoing_multiplier(player: Player, target: Actor) -> float:
	var mult: float = 1.0
	if player.stats.has_affix("executioner") and target.health < target.max_health * 0.25 and not target.dead:
		mult *= 1.6
		SkillFx.execute_mark(player, target)
	if player.stats.has_affix("kindling") and target.is_burning() and not target.dead:
		mult *= KINDLING_BONUS
	if player.stats.has_affix("juggler") and is_airborne(target):
		mult *= JUGGLER_BONUS
	if player.stats.has_affix("virtuoso"):
		mult *= virtuoso_multiplier(player)
	return mult

## Enemies that are thrown through the air (by Earthshatter, a Fireball blast, a Skewer kick...).
static func is_airborne(target: Actor) -> bool:
	return target != null and not target.dead and target.is_ragdolled() and target.ragdoll.state == Ragdoll.State.FLIGHT

## Breaker's: a hit on an enemy that is stunned or knocked down is always a critical hit.
static func guaranteed_crit(player: Player, target: Actor) -> bool:
	if target == null or target.dead or not player.stats.has_affix("breaker"):
		return false
	return target.stun_time > 0.0 or LeapSkill.is_downed(target)

## Virtuoso: using a different skill than the last one stacks +20% damage (3 stacks, for 4 seconds); repeating a skill drops the stacks.
static func virtuoso_multiplier(player: Player) -> float:
	if not player.stats.has_affix("virtuoso") or player.stats.chain_time <= 0.0:
		return 1.0
	return 1.0 + VIRTUOSO_STEP * float(player.stats.chain_stacks)

static func on_skill_start(player: Player, id: String) -> void:
	if not player.stats.has_affix("virtuoso"):
		return
	var stats: PlayerStats = player.stats
	if stats.chain_time > 0.0 and id != stats.chain_last:
		stats.chain_stacks = mini(stats.chain_stacks + 1, VIRTUOSO_MAX)
	else:
		stats.chain_stacks = 0
	stats.chain_last = id
	stats.chain_time = VIRTUOSO_WINDOW
	if stats.chain_stacks > 0:
		Fx.text_at(player, player.global_position + Vector3(0, 2.7, 0), "Virtuoso x%d" % stats.chain_stacks, Color(1.0, 0.85, 0.4), 40)

## Every hit the player lands (melee, fireball, even kills) passes through here.
static func on_dealt_hit(player: Player, target: Actor, result: Dictionary) -> void:
	if result.get("secondary", false):
		return
	var outcome: int = result["outcome"]
	if outcome == Combat.Outcome.MISS or outcome == Combat.Outcome.BLOCK:
		return
	if not target.dead:
		if player.stats.has_affix("searing") and outcome == Combat.Outcome.CRITICAL:
			target.apply_burn(maxf(float(result["damage"]) * 0.3, 2.0), 3.0)
			SkillFx.ignite_mark(player, target)
		if player.stats.has_affix("kindling") and target.is_burning():
			_spread_burn(player, target)
		if player.stats.has_affix("juggler") and is_airborne(target):
			_juggle(player, target)
	if player.stats.has_affix("chain") and randf() < 0.25:
		_chain_lightning(player, target, result)
	if player.stats.has_affix("cleaving") and result.get("finisher", false):
		_finisher_arc(player, target, result)

## Kindling: the fire on a burning enemy you hit jumps to the ones standing next to it.
static func _spread_burn(player: Player, target: Actor) -> void:
	var caught: int = 0
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e == target or e.dead or e.is_burning() or e.flat_distance_to(target) > 2.5:
			continue
		e.apply_burn(target.burn_dps, 3.0)
		SkillFx.ignite_mark(player, e)
		caught += 1
	if caught > 0:
		Fx.ring(player, target.global_position + Vector3(0, 0.1, 0), 2.5, Color(1.0, 0.5, 0.15))

## Juggler's: a hit on an enemy in mid-air knocks it back up, so the next hit finds it airborne too.
static func _juggle(player: Player, target: Actor) -> void:
	var away: Vector3 = target.global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
	var spin: Vector3 = away.cross(Vector3.UP) * 6.0 + Vector3.UP * randf_range(-2.0, 2.0)
	target.ragdoll_launch(away * 3.5, 5.5, spin)
	Fx.burst(player, target.global_position + Vector3(0, 1.0, 0), Vector3.UP, Color(1.0, 0.95, 0.8), 10, 6.0, 0.03, true)
	Fx.text_at(player, target.global_position + Vector3(0, 2.4, 0), "Juggled", Color(1.0, 0.9, 0.5), 36)

static func _nearest_other(player: Player, from_actor: Actor, max_dist: float) -> Actor:
	var best: Actor = null
	var best_d: float = max_dist
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e == from_actor or e.dead:
			continue
		var d: float = e.flat_distance_to(from_actor)
		if d < best_d:
			best_d = d
			best = e
	return best

static func _chain_lightning(player: Player, target: Actor, result: Dictionary) -> void:
	var other: Actor = _nearest_other(player, target, 4.5)
	if other == null:
		return
	var from: Vector3 = target.global_position + Vector3(0, target.body_height * 0.6, 0)
	var to: Vector3 = other.global_position + Vector3(0, other.body_height * 0.6, 0)
	Fx.beam(player, from, to, Color(0.6, 0.8, 1.0))
	SkillFx.chain_spark(player, from)
	SkillFx.chain_spark(player, to)
	var arc: Dictionary = Combat.resolve(player, other, float(result["damage"]) * 0.6, Combat.DamageType.FIRE, false, 0.8)
	arc["secondary"] = true
	other.receive(arc, target.global_position)

static func _finisher_arc(player: Player, target: Actor, result: Dictionary) -> void:
	var facing: Vector3 = target.global_position - player.global_position
	facing.y = 0.0
	facing = facing.normalized()
	var hit_any: bool = false
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e == target or e.dead:
			continue
		var to_e: Vector3 = e.global_position - player.global_position
		to_e.y = 0.0
		if to_e.length() <= 3.2 and to_e.normalized().dot(facing) > 0.25:
			var swing: Dictionary = Combat.resolve(player, e, float(result["damage"]) * 0.8, Combat.DamageType.PHYSICAL, false, 1.2)
			swing["secondary"] = true
			e.receive(swing, player.global_position)
			hit_any = true
	if hit_any:
		SkillFx.cleaving_arc(player, facing, 3.4)

# --- kills --------------------------------------------------------------------

static func on_kill(player: Player, enemy: Actor) -> void:
	_drop_loot(player, enemy)
	if player.stats.has_affix("quickening") and randf() < 0.12:
		player.stats.cooldowns.clear()
		Fx.text_at(player, player.global_position + Vector3(0, 2.6, 0), "Cooldowns reset", Color(0.7, 0.9, 1.0), 40)
	if player.stats.has_affix("ember"):
		_ember_blast(player, enemy)
	if player.stats.has_affix("quaker"):
		player.stats.gain_ult_charge(PlayerStats.MAX_ULT_CHARGE * QUAKER_CHARGE)
	if player.stats.has_affix("pyre") and enemy.burn_time > 0.0:
		_pyre_blast(player, enemy)

## Pyrebound: an enemy that dies while burning goes up, hurting and igniting everything around it (which can set off the next one).
static func _pyre_blast(player: Player, enemy: Actor) -> void:
	var centre: Vector3 = enemy.global_position
	Fx.ring(player, centre, 3.2, Color(1.0, 0.45, 0.12))
	Fx.burst(player, centre + Vector3(0, 0.8, 0), Vector3.UP, Color(1.0, 0.5, 0.1), 28, 7.5, 0.04, true)
	Fx.light_flash(player, centre + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.15), 4.0, 0.25)
	var dps: float = maxf(enemy.burn_dps, 4.0)
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e == enemy or e.dead or e.flat_distance_to(enemy) > 3.2:
			continue
		var blast: Dictionary = Combat.resolve(player, e, player.stats.weapon_damage(0.6), Combat.DamageType.FIRE, false, 1.4)
		blast["secondary"] = true
		e.receive(blast, centre)
		if is_instance_valid(e) and not e.dead:
			e.apply_burn(dps, 3.5)

## Healing is scarce but fair: orbs drop more often the more hurt you are, potions drop rarely, and a Brute always
## pays out.
static func _drop_loot(player: Player, enemy: Actor) -> void:
	var missing: float = 1.0 - clampf(player.health / player.max_health, 0.0, 1.0)
	var big: bool = enemy.is_boss or enemy.max_health >= 150.0
	var orbs: int = 0
	var potions: int = 0
	if big:
		orbs = 2
		potions = 1 if randf() < 0.6 else 0
	else:
		var chance: float = 0.09 + 0.22 * missing
		orbs = 1 if randf() < chance else 0
		potions = 1 if randf() < 0.025 + 0.04 * missing else 0
	for i in orbs + potions:
		var orb := HealthOrb.new()
		orb.is_potion = i >= orbs
		player.get_tree().current_scene.add_child(orb)
		orb.global_position = enemy.global_position + Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7))

static func _ember_blast(player: Player, enemy: Actor) -> void:
	var centre: Vector3 = enemy.global_position
	Fx.ring(player, centre, 3.0, Color(1.0, 0.5, 0.15))
	Fx.burst(player, centre + Vector3(0, 0.8, 0), Vector3.UP, Color(1.0, 0.55, 0.12), 24, 7.0, 0.04, true)
	Fx.light_flash(player, centre + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 3.5, 0.2)
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e == enemy or e.dead or e.flat_distance_to(enemy) > 3.0:
			continue
		var blast: Dictionary = Combat.resolve(player, e, player.stats.weapon_damage(0.7), Combat.DamageType.FIRE, false, 1.3)
		blast["secondary"] = true
		e.receive(blast, centre)

# --- rolling --------------------------------------------------------------------

static func on_roll_start(player: Player) -> void:
	if player.stats.has_affix("cinder_roll"):
		EmberTrail.follow(player)
	if player.stats.has_affix("shock_roll"):
		Fx.ring(player, player.global_position, 3.0, Color(0.7, 0.85, 1.0))
		for node in player.get_tree().get_nodes_in_group("enemies"):
			var e := node as Actor
			if e == null or e.dead or e.flat_distance_to(player) > 3.0:
				continue
			var blast: Dictionary = Combat.resolve(player, e, player.stats.weapon_damage(0.7), Combat.DamageType.PHYSICAL, false, 2.2)
			blast["secondary"] = true
			e.receive(blast, player.global_position)


# --- damage taken -----------------------------------------------------------------

## May change an incoming hit before it is applied (block it, reduce it).
static func filter_incoming(player: Player, result: Dictionary) -> Dictionary:
	var outcome: int = result["outcome"]
	if outcome == Combat.Outcome.MISS or outcome == Combat.Outcome.BLOCK:
		return result
	if player.stats.has_affix("aegis"):
		player.stats.aegis_hits += 1
		if player.stats.aegis_hits % 4 == 0:
			result["outcome"] = Combat.Outcome.BLOCK
			_aegis_wave(player)
			return result
	return result

## Smouldering: being hit sets the enemies around you alight.
static func on_player_hurt(player: Player) -> void:
	if not player.stats.has_affix("smouldering"):
		return
	var lit: int = 0
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.flat_distance_to(player) > 3.6:
			continue
		e.apply_burn(5.0, 3.0)
		SkillFx.ignite_mark(player, e)
		lit += 1
	if lit > 0:
		Fx.ring(player, player.global_position + Vector3(0, 0.1, 0), 3.6, Color(1.0, 0.45, 0.12))

static func _aegis_wave(player: Player) -> void:
	Fx.ring(player, player.global_position, 3.6, Color(1.0, 0.8, 0.4))
	Fx.shake(player, 0.15)
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.flat_distance_to(player) > 3.6:
			continue
		var wave: Dictionary = Combat.resolve(player, e, player.stats.weapon_damage(0.9), Combat.DamageType.PHYSICAL, false, 2.4)
		wave["secondary"] = true
		e.receive(wave, player.global_position)

# --- skills -----------------------------------------------------------------------

## Gravewarden: Power Strike sends a shockwave through everything in a line.
static func power_shockwave(player: Player, direction: Vector3) -> void:
	if not player.stats.has_affix("gravewarden"):
		return
	var dir: Vector3 = direction
	dir.y = 0.0
	dir = dir.normalized()
	SkillFx.gravewarden_wave(player, dir)
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead:
			continue
		var to_e: Vector3 = e.global_position - player.global_position
		to_e.y = 0.0
		var along: float = to_e.dot(dir)
		var across: float = absf(to_e.cross(dir).y)
		if along > 0.5 and along < 8.5 and across < 1.2:
			var wave: Dictionary = Combat.resolve(player, e, player.stats.weapon_damage(1.0), Combat.DamageType.PHYSICAL, false, 1.8)
			wave["secondary"] = true
			e.receive(wave, player.global_position)

## Wildfire: a Fireball that catches three or more enemies in its blast gets three seconds off its cooldown.
static func on_fireball_blast(player: Player, caught: int) -> void:
	if caught >= 3 and player.stats.has_affix("wildfire"):
		player.stats.cooldowns["fireball"] = maxf(float(player.stats.cooldowns.get("fireball", 0.0)) - 3.0, 0.0)
		Fx.text_at(player, player.global_position + Vector3(0, 2.6, 0), "Wildfire", Color(1.0, 0.6, 0.2), 40)

## Vaultborn: landing a Leap makes your next Power Strike (within a few seconds) free, with no cooldown.
static func on_leap_land(player: Player) -> void:
	if player.stats.has_affix("vaultborn"):
		player.stats.vault_time = VAULT_WINDOW
		Fx.text_at(player, player.global_position + Vector3(0, 2.6, 0), "Power Strike ready", Color(1.0, 0.8, 0.4), 38)

## Ramming: a Skewer that carried three enemies is ready again as soon as the kick lands.
static func on_skewer_kick(player: Player, carried: int) -> void:
	if carried >= 3 and player.stats.has_affix("charger"):
		player.stats.cooldowns["skewer"] = 0.0
		Fx.text_at(player, player.global_position + Vector3(0, 2.6, 0), "Skewer ready", Color(1.0, 0.8, 0.4), 38)

## Impaler's: an enemy kicked off the Skewer bursts where it lands, hurting everything around it.
static func impaler_burst(player: Player, victim: Actor, fallback: Vector3) -> void:
	if not player.stats.has_affix("impaler"):
		return
	var centre: Vector3 = victim.global_position if is_instance_valid(victim) else fallback
	centre.y = 0.0
	Fx.ring(player, centre + Vector3(0, 0.1, 0), 3.2, Color(0.8, 0.15, 0.1))
	Fx.burst(player, centre + Vector3(0, 0.6, 0), Vector3.UP, Color(0.55, 0.05, 0.04), 30, 8.0)
	Fx.shake(player, 0.12)
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e == victim or e.dead or e.flat_distance_to_point(centre) > 3.2:
			continue
		var blast: Dictionary = Combat.resolve(player, e, player.stats.weapon_damage(1.0), Combat.DamageType.PHYSICAL, false, 2.0)
		blast["secondary"] = true
		e.receive(blast, centre)
