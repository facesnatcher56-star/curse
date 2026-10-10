class_name BodyRecoil
extends RefCounted
## How a standing monster's body takes a blow: the torso snaps away from it, overshoots, and settles; the head follows a beat later; a blow from the side
## also twists the shoulders. Two damped springs (a lean vector and a twist), so no physics body: the cost is a few bone rotations, and only while it moves.
##
## The state lives here; CharacterModel applies it to the spine after the animation each frame (`CharacterModel._apply_hit_reaction`).
## A hit adds an impulse sized by how hard it was (`peak_for`), so a light blow is a jolt of the shoulders, a heavy one throws the chest back and a
## crushing one nearly doubles it over. The spring's overshoot is the "momentum recovery": it rocks back past upright before it steadies.

const OMEGA := 12.0         # spring stiffness (rad/s): about a 0.5 s recovery
const DAMPING := 0.36       # < 1: it overshoots and rocks once
const HEAD_FOLLOW := 9.0    # the head chases the torso's lean with this rate, so it arrives late
const TWIST_OMEGA := 17.0
const MAX_LEAN := 0.75      # rad: no blow bends a body further than this
const STEP_PEAK := 0.2      # blows that tip the chest further than this (rad) also cost a step to catch the balance
const STEP_TIME := 0.38
const REST := 0.004         # below this (and still) the reaction is over and costs nothing

var lean: Vector2 = Vector2.ZERO        # horizontal world-space direction the torso tips toward, magnitude = angle (rad)
var lean_vel: Vector2 = Vector2.ZERO
var head: Vector2 = Vector2.ZERO        # the head's own lagging copy of the lean
var twist: float = 0.0                  # rad about the vertical axis
var twist_vel: float = 0.0
var step_t: float = 0.0                 # > 0 while a recovery step is under way (counts down from STEP_TIME)
var step_dir: Vector2 = Vector2.ZERO    # the way the foot steps (away from the blow)
var step_leg: int = 0                   # which leg steps; alternates, so a staggering body shuffles

func active() -> bool:
	return step_t > 0.0 or lean.length() > REST or lean_vel.length() > REST * 4.0 or absf(twist) > REST or absf(twist_vel) > REST * 4.0 or head.length() > REST

## The peak lean (rad) a blow should cause. `weight` is the blow's own weight (light about 0.7, heavy 1.5+), `outcome_scale` 1 for a plain hit, 1.5 for a
## critical, 2.2 for a crushing blow; `resist` is the monster's knock-back resistance (0..1): big monsters shrug blows off.
static func peak_for(weight: float, outcome_scale: float, resist: float) -> float:
	return clampf(0.22 * weight * outcome_scale * (1.0 - resist * 0.6), 0.11, MAX_LEAN)   # even a light blow is plainly visible

## `away` is the horizontal world direction the blow pushes the body (zero length is ignored); `facing` the actor's horizontal facing, to tell a hit from the
## front from one from the side. `jitter` (0..1) varies each blow a little so a crowd hit by one swing does not all rock identically.
func hit(away: Vector3, facing: Vector3, peak: float, jitter: float = 0.2) -> void:
	var dir := Vector2(away.x, away.z)
	if dir.length() < 0.01 or peak <= 0.0:
		return
	dir = dir.normalized()
	var vary: float = 1.0 + (randf() * 2.0 - 1.0) * jitter
	var rotated: Vector2 = dir.rotated((randf() * 2.0 - 1.0) * 0.25 * jitter)
	lean_vel += rotated * peak * OMEGA * 1.35 * vary
	if peak >= STEP_PEAK and step_t <= 0.0:
		step_t = STEP_TIME * (0.8 + minf(peak, 0.6))
		step_dir = rotated
		step_leg = 1 - step_leg
	# A blow from the side turns the shoulders: how far the blow's direction is across the facing.
	var f := Vector2(facing.x, facing.z)
	if f.length() > 0.01:
		var across: float = f.normalized().cross(dir)
		twist_vel += -across * peak * 1.6 * TWIST_OMEGA * vary

func step(delta: float) -> void:
	delta = minf(delta, 0.05)
	# damped spring: x'' = -w^2 x - 2 z w x'
	lean_vel += (-OMEGA * OMEGA * lean - 2.0 * DAMPING * OMEGA * lean_vel) * delta
	lean += lean_vel * delta
	if lean.length() > MAX_LEAN:
		lean = lean.normalized() * MAX_LEAN
	twist_vel += (-TWIST_OMEGA * TWIST_OMEGA * twist - 2.0 * DAMPING * TWIST_OMEGA * twist_vel) * delta
	twist += twist_vel * delta
	step_t = maxf(step_t - delta, 0.0)
	head += (lean - head) * minf(HEAD_FOLLOW * delta, 1.0)
	if not active():
		lean = Vector2.ZERO
		lean_vel = Vector2.ZERO
		head = Vector2.ZERO
		twist = 0.0
		twist_vel = 0.0

## 0..1..0 over the step: the foot leaves the ground, swings out and plants.
func step_swing() -> float:
	if step_t <= 0.0:
		return 0.0
	var total: float = STEP_TIME * 1.4
	return sin(PI * clampf(1.0 - step_t / total, 0.0, 1.0))
