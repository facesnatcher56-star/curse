class_name PlayerMovement
extends RefCounted
## Click-to-move steering, locomotion animation and the dodge roll.

var p: Player

func _init(player: Player) -> void:
	p = player

const ROLL_TIME := 0.55
const ROLL_SPEED := 10.0
const ROLL_STAMINA := 20.0
# The roll clip crouches for ~0.9 s before it tumbles (see tools/roll_profile.gd). Play only the dive and
# tumble so the visible roll starts the instant the body starts moving.
const ROLL_CLIP_START := 0.78
const ROLL_CLIP_END := 1.68
var goal: Vector3 = Vector3.ZERO
var has_goal: bool = false
var _nav_state: Dictionary = {}  # cached path for click-to-move (see Nav)
var shoved: Dictionary = {}  # enemies already staggered by the current roll
var rolling: bool = false
var roll_t: float = 0.0
var roll_dir: Vector3 = Vector3.FORWARD
func update_locomotion_anim() -> void:
	var moving_speed: float = (p.velocity - p.knock).length()
	# Only walk or run on purpose: being shoved by the crowd or a hit must not start the legs moving.
	if moving_speed > 0.5 and (has_goal or Gamepad.move_vector().length() > 0.0) and not p.skills.busy:
		if moving_speed > p.stats.run_speed * 0.8:
			p.model.loop("run", 1.0)
		else:
			p.model.loop("walk", 1.0)
	elif not p.skills.busy:
		p.model.loop("idle_alert")

## Walking speed this frame, paying stamina (or slowing down once exhausted) while in combat.
func _travel_speed(delta: float) -> float:
	var speed: float = p.stats.run_speed
	if p.combat_timer > 0.0:
		if p.stats.stamina <= 0.0:
			speed = p.stats.run_speed * 0.6
		else:
			p.stats.stamina = maxf(p.stats.stamina - 16.0 * delta, 0.0)
	return speed

## Left-stick movement: direct and analog (a light push walks, a full push runs). The hero faces the right-stick aim if it
## is in use, otherwise where it is going.
func stick_move(stick: Vector2, delta: float) -> void:
	has_goal = false
	var strength: float = clampf(stick.length(), 0.0, 1.0)
	var direction: Vector3 = Gamepad.to_world(stick).normalized()
	var speed: float = _travel_speed(delta) * lerpf(0.45, 1.0, clampf((strength - 0.1) / 0.8, 0.0, 1.0))
	if Gamepad.aim_vector().length() == 0.0:
		p.face(p.global_position + direction, 0.35)
	p.move_with(direction * speed)

func move(delta: float) -> void:
	var stick: Vector2 = Gamepad.move_vector()
	if stick.length() > 0.0:
		stick_move(stick, delta)
		return
	if not has_goal:
		p.move_with(Vector3.ZERO)
		return
	var to_goal: Vector3 = goal - p.global_position
	to_goal.y = 0.0
	if to_goal.length() < 0.2:
		has_goal = false
		p.move_with(Vector3.ZERO)
		return
	var speed: float = _travel_speed(delta)
	# Steer along the navmesh path so we walk around pillars, walls and ruins instead of grinding against them.
	var steer: Vector3 = Nav.next_point(p, goal, _nav_state, delta)
	var to_steer: Vector3 = steer - p.global_position
	to_steer.y = 0.0
	if to_steer.length() < 0.05:
		to_steer = to_goal
	p.face(p.global_position + to_steer, 0.35)
	p.move_with(to_steer.normalized() * speed)

## While rolling, every non-boss enemy close to the hero is shoved sideways out of the way and has its current
## action interrupted. Bosses ignore it (Actor.is_boss).
func shove_enemies(delta: float) -> void:
	var side: Vector3 = roll_dir.cross(Vector3.UP).normalized()
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.is_boss or e.impaled or e.is_ragdolled():
			continue
		# During a Skewer charge, do not shove enemies the blade can still catch; they are the target.
		if p.skewer.skewer_phase == 2 and e.can_be_impaled() and p.skewer.skewer_impaled.size() < 3 and not p.skewer.big_hit.has(e.get_instance_id()):
			continue
		var rel: Vector3 = e.global_position - p.global_position
		rel.y = 0.0
		if rel.length() > p.body_radius + e.body_radius + 0.7:
			continue
		var direction: float = 1.0 if rel.dot(side) >= 0.0 else -1.0
		# Direct displacement (not knockback), so heavy enemies that resist knockback still get moved.
		var shove: Vector3 = side * direction * 6.0 + roll_dir * 1.5
		e.move_and_collide(shove * delta)
		if not shoved.has(e.get_instance_id()):
			shoved[e.get_instance_id()] = true
			e.interrupt(0.55)
			Fx.burst(p, e.global_position + Vector3(0, 0.3, 0), side * direction + Vector3.UP * 0.4, Color(0.5, 0.45, 0.38), 10, 3.5, 0.04)

func try_roll(cursor: Vector3) -> void:
	if float(p.stats.cooldowns.get("dodge", 0.0)) > 0.0:
		return
	if p.skills.busy and not p.skills.busy_hit_done:
		return  # committed to the wind-up; once the blow lands the recovery can be cancelled
	var roll_cost: float = ROLL_STAMINA * p.stats.armor_stat("roll_cost", 1.0)
	if p.stats.stamina < roll_cost:
		p._say("Too tired to dodge")
		return
	var dir: Vector3 = Vector3.ZERO
	var stick: Vector2 = Gamepad.move_vector()
	if stick.length() > 0.0:
		dir = Gamepad.to_world(stick)   # roll the way the stick is pushed
	elif has_goal and (goal - p.global_position).length() > 0.4:
		dir = goal - p.global_position
	else:
		dir = cursor - p.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3(sin(p.visual.rotation.y), 0.0, cos(p.visual.rotation.y))
	roll_dir = dir.normalized()
	p.stats.stamina -= roll_cost
	p.stats.cooldowns["dodge"] = float(SkillDb.all()["dodge"]["cd"])
	rolling = true
	roll_t = 0.0
	p.skills.busy = false
	p.skills.queued_skill = ""
	p.attack_target = null
	p.click_mode = 0
	has_goal = false
	if p._trail != null:
		p._trail.active = false
	p.invulnerable_time = ROLL_TIME + 0.12  # immune for the whole roll plus a short grace
	shoved.clear()
	p.collision_mask = Actor.LAYER_WORLD  # slip through enemies while rolling
	p.visual.rotation.y = atan2(roll_dir.x, roll_dir.z)
	p.model.manual("roll")
	p.model.scrub(ROLL_CLIP_START)
	Sfx.play(p, "swing", -6.0, 0.7)
	ItemEffects.on_roll_start(p)

func tick_roll(delta: float) -> void:
	shove_enemies(delta)
	roll_t += delta
	var u: float = clampf(roll_t / ROLL_TIME, 0.0, 1.0)
	p.model.scrub(lerpf(ROLL_CLIP_START, ROLL_CLIP_END, u))
	p.move_with(roll_dir * ROLL_SPEED * p.stats.armor_stat("roll_speed", 1.0) * (1.0 - 0.6 * u))
	if roll_t >= ROLL_TIME:
		rolling = false
		p.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ENEMY
		p.model.loop("idle_alert")
		ItemEffects.on_roll_end(p)
