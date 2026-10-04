class_name ItemEffects
extends RefCounted
## What equipped item affixes actually do. Player/Actor call these hooks at the matching moments;
## everything here is a behaviour change, not a stat. Hits made by an effect are flagged "secondary"
## so effects never trigger other effects endlessly.

const HASTE_TIME := 3.0
const HASTE_BONUS := 0.30

# --- damage dealt -----------------------------------------------------------

static func outgoing_multiplier(player: Player, target: Actor) -> float:
	var mult: float = 1.0
	if player.stats.has_affix("executioner") and target.health < target.max_health * 0.25 and not target.dead:
		mult *= 1.6
		SkillFx.execute_mark(player, target)
	return mult

## Every hit the player lands (melee, cleave, fireball, even kills) passes through here.
static func on_dealt_hit(player: Player, target: Actor, result: Dictionary) -> void:
	if result.get("secondary", false):
		return
	var outcome: int = result["outcome"]
	if outcome == Combat.Outcome.MISS or outcome == Combat.Outcome.BLOCK:
		return
	if not target.dead:
		if player.stats.has_affix("frostbite"):
			target.apply_slow(0.4, 2.0)
		if player.stats.has_affix("searing") and outcome == Combat.Outcome.CRITICAL:
			target.apply_burn(maxf(float(result["damage"]) * 0.3, 2.0), 3.0)
			SkillFx.ignite_mark(player, target)
	if player.stats.has_affix("chain") and randf() < 0.25:
		_chain_lightning(player, target, result)
	if player.stats.has_affix("cleaving") and result.get("finisher", false):
		_cleave_arc(player, target, result)

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

static func _cleave_arc(player: Player, target: Actor, result: Dictionary) -> void:
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
	if player.stats.has_affix("momentum"):
		player.stats.haste_time = HASTE_TIME
	_drop_loot(player, enemy)
	if player.stats.has_affix("quickening") and randf() < 0.12:
		player.stats.cooldowns.clear()
		Fx.text_at(player, player.global_position + Vector3(0, 2.6, 0), "Cooldowns reset", Color(0.7, 0.9, 1.0), 40)
	if player.stats.has_affix("ember"):
		_ember_blast(player, enemy)

## Healing is scarce but fair: orbs drop more often the more hurt you are, potions drop rarely, and a Brute always
## pays out. `windfall` adds to the orb chance.
static func _drop_loot(player: Player, enemy: Actor) -> void:
	var missing: float = 1.0 - clampf(player.health / player.max_health, 0.0, 1.0)
	var big: bool = enemy.is_boss or enemy.max_health >= 150.0
	var orbs: int = 0
	var potions: int = 0
	if big:
		orbs = 2
		potions = 1 if randf() < 0.6 else 0
	else:
		var chance: float = 0.09 + 0.22 * missing + (0.15 if player.stats.has_affix("windfall") else 0.0)
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
	if player.stats.has_affix("shock_roll"):
		Fx.ring(player, player.global_position, 3.0, Color(0.7, 0.85, 1.0))
		for node in player.get_tree().get_nodes_in_group("enemies"):
			var e := node as Actor
			if e == null or e.dead or e.flat_distance_to(player) > 3.0:
				continue
			var blast: Dictionary = Combat.resolve(player, e, player.stats.weapon_damage(0.7), Combat.DamageType.PHYSICAL, false, 2.2)
			blast["secondary"] = true
			e.receive(blast, player.global_position)

static func on_roll_end(player: Player) -> void:
	if player.stats.has_affix("riposte"):
		player.stats.riposte_time = 1.5
		Fx.text_at(player, player.global_position + Vector3(0, 2.6, 0), "Riposte ready", Color(1.0, 0.9, 0.4), 38)

# --- damage taken -----------------------------------------------------------------

## May change an incoming hit before it is applied (block it, reduce it).
static func filter_incoming(player: Player, result: Dictionary) -> Dictionary:
	var outcome: int = result["outcome"]
	if outcome == Combat.Outcome.MISS or outcome == Combat.Outcome.BLOCK:
		return result
	if player.stats.has_affix("warding") and player.stats.ward_timer <= 0.0:
		player.stats.ward_timer = 8.0
		result["outcome"] = Combat.Outcome.BLOCK
		Fx.ring(player, player.global_position, 1.6, Color(0.5, 0.8, 1.0))
		return result
	if player.stats.has_affix("aegis"):
		player.stats.aegis_hits += 1
		if player.stats.aegis_hits % 4 == 0:
			result["outcome"] = Combat.Outcome.BLOCK
			_aegis_wave(player)
			return result
	if player.stats.has_affix("last_stand") and player.health < player.max_health * 0.35:
		result["damage"] = float(result["damage"]) * 0.7
	return result

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

## Whirlpool: Cleave drags enemies in before it lands.
static func pull_for_cleave(player: Player) -> void:
	if not player.stats.has_affix("whirlpool"):
		return
	SkillFx.whirlpool(player, 5.0)
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.flat_distance_to(player) > 5.0:
			continue
		var toward: Vector3 = player.global_position - e.global_position
		toward.y = 0.0
		e.knock += toward.normalized() * 7.0 * (1.0 - e.knock_resist)
		SkillFx.whirlpool_tug(player, e)
