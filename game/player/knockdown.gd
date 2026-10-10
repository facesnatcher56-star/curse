class_name Knockdown
extends RefCounted
## The hero flattened by a heavy blow: impact -> downed -> getting up -> control back. A heavy blow is the one Player.is_heavy_hit
## defines (the old heavy stagger's trigger point, unchanged). While any phase runs the hero cannot move, attack, dodge or cast; the
## existing stun lock is held for the whole fall so every "can he act?" check keeps working, and only the potion still works.
## Death and revival cancel it. Getting up is a plain sequence with a heavy man's weight in it: no roll, no spring.

var p: Player

func _init(player: Player) -> void:
	p = player

enum Phase { NONE, IMPACT, DOWNED, GETTING_UP }

const IMPACT_TIME := 0.3      # thrown back off his feet
const DOWNED_TIME := 0.45     # flat on the ground, winded
const GET_UP_TIME := 0.55     # one knee, a hand on the sword, then up
const TOTAL_TIME := IMPACT_TIME + DOWNED_TIME + GET_UP_TIME
const LYING_PITCH := -1.42    # on his back (negative pitch leans the model backwards)
const BRACE_PITCH := -0.85    # rolled up onto a hip, one arm planted
const HUNCH_PITCH := 0.32     # one knee down, shoulders over it, head low: the heaviest moment of the get-up
const LYING_LIFT := 0.22      # the body lies on the ground, not in it
const KNEEL_SINK := -0.3      # on one knee he stands a good deal shorter
const BRACE_ROLL := 0.42      # the sideways lean of the brace (radians about the facing axis)
const ENTRY_BLEND := 0.12     # blend from the pose the blow caught him in into the fall
const CLIP := "knockdown"    # the authored fall/downed/get-up clip (tools/author_knockdown_anims.gd), as long as TOTAL_TIME

var phase: Phase = Phase.NONE
var phase_time: float = 0.0
var knockdowns: int = 0       # how many times he has been put down (tests, diagnostics)
var get_ups: int = 0          # how many get-ups ran to the end

func active() -> bool:
	return phase != Phase.NONE

func is_downed() -> bool:
	return phase == Phase.DOWNED

func phase_name() -> String:
	return String(Phase.keys()[phase]).to_lower()

## Puts the hero down (a heavy blow). Already down, dead, or mid Skewer charge (nothing may stall that): does nothing.
func begin() -> bool:
	if p.dead or active() or p.is_charging():
		return false
	knockdowns += 1
	phase = Phase.IMPACT
	phase_time = 0.0
	# Whatever he was doing is broken off for good: no swing, roll, aim, queued skill or walk goal survives the fall.
	p.skills.cancel_action()
	p.skills.clear_aim()
	p.skills.queued_skill = ""
	p.movement.rolling = false
	p.movement.has_goal = false
	p.attack_target = null
	p.attack_prop = null
	p.pickup_target = null
	if _authored():
		# Scrubbed by the fall's own clock (so a hit-pause freezes it and the phases keep their exact lengths) once the first
		# moments have blended in from the pose the blow caught him in. A blend only advances while the clip runs, so it runs for
		# those moments and _pose then freezes it for scrubbing: a swing is never snapped to the clip's first frame.
		p.model.once(CLIP, 0.0, 1.0, ENTRY_BLEND)
	else:
		p.model.once("hit", 0.0, 1.6)
	p.stun_time = maxf(p.stun_time, TOTAL_TIME)
	return true

## The authored clip is there to play (the procedural pose below is the fallback if it ever fails to load).
func _authored() -> bool:
	return p.model != null and p.model.anim != null and p.model.anim.has_animation("game/" + CLIP)

## Where the fall is in the clip: the three phases run back to back and the clip is one continuous motion across them.
func clip_time() -> float:
	match phase:
		Phase.IMPACT: return phase_time
		Phase.DOWNED: return IMPACT_TIME + phase_time
		Phase.GETTING_UP: return IMPACT_TIME + DOWNED_TIME + phase_time
	return 0.0

## Advances the fall; called once a frame by the hero while he is alive and not frozen by a hit-pause.
func tick(delta: float) -> void:
	if not active():
		return
	phase_time += delta
	match phase:
		Phase.IMPACT:
			if phase_time >= IMPACT_TIME:
				_enter(Phase.DOWNED)
		Phase.DOWNED:
			if phase_time >= DOWNED_TIME:
				_enter(Phase.GETTING_UP)
		Phase.GETTING_UP:
			if phase_time >= GET_UP_TIME:
				_finish()
				return
	p.stun_time = maxf(p.stun_time, _remaining())   # the control lock lasts exactly as long as the fall
	_pose()

func _enter(next: Phase) -> void:
	phase = next
	phase_time = 0.0

func _remaining() -> float:
	match phase:
		Phase.IMPACT: return (IMPACT_TIME - phase_time) + DOWNED_TIME + GET_UP_TIME
		Phase.DOWNED: return (DOWNED_TIME - phase_time) + GET_UP_TIME
		Phase.GETTING_UP: return GET_UP_TIME - phase_time
	return 0.0

## He is on his feet: the lock ends, then the one thing that rides on a completed get-up.
func _finish() -> void:
	_stand()
	get_ups += 1
	p.stun_time = 0.0
	p.model.loop("idle_alert")
	if p.has_passive("iron_recovery"):
		p._iron_recovery()

## Death and revival: the fall is simply over, with no get-up and no Iron Recovery.
func cancel() -> void:
	if not active():
		return
	_stand()
	p.stun_time = 0.0

## The hero dies: the fall stops here (no get-up, no Iron Recovery) and the death clip carries on from the pose he is in, so a
## man already on his back goes limp where he lies instead of snapping upright to fall again. The clip's own fall is skipped in
## proportion to how far down he already was; the visual is put square again because the clip lies down by itself.
func die() -> void:
	var down: float = 0.0
	var blend: float = 0.12
	match phase:
		Phase.IMPACT: down = clampf(phase_time / IMPACT_TIME, 0.0, 1.0)
		Phase.DOWNED: down = 1.0
		Phase.GETTING_UP: down = 0.8 if phase_time / GET_UP_TIME < 0.35 else 0.4   # braced on a hip / up on one knee
	if _authored():
		# The knockdown clip is still held on the pose he is in: ease from it over a longer blend into the death clip's lower half, so
		# a man braced or kneeling folds to the ground from where he is instead of a standing frame showing for a moment.
		blend = 0.4 if phase == Phase.GETTING_UP else 0.25
		if phase == Phase.GETTING_UP:
			down = 0.9
	cancel()
	if down > 0.05 and p.model != null and p.model.anim.has_animation("game/death"):
		var length: float = p.model.anim.get_animation("game/death").length
		p.model.once("death", length * 0.75 * down, 1.0, blend)

func reset() -> void:
	cancel()
	knockdowns = 0
	get_ups = 0

func _stand() -> void:
	phase = Phase.NONE
	phase_time = 0.0
	if p.visual != null:
		p.visual.rotation.x = 0.0
		p.visual.rotation.z = 0.0
		p.visual.position.y = 0.0

## Procedural pose over the existing "hit" clip, pivoting at his feet. Impact: a short hop off the ground, then thrown flat and a
## rebound off the earth. Downed: heaving, head rolled to one side. Get-up: roll onto a hip and plant an arm, drag a knee under
## him and hunch over it, then drive up with the legs. Nothing springs: every step eases in slowly and ends heavily.
func _pose() -> void:
	if p.visual == null:
		return
	if _authored():
		if phase != Phase.IMPACT or phase_time > ENTRY_BLEND:
			p.model.anim.speed_scale = 0.0   # the entry blend is done: from here the clip stands exactly where the phases say
		p.model.scrub(minf(clip_time(), TOTAL_TIME))
		return
	var pitch: float = 0.0
	var roll: float = 0.0
	var lift: float = 0.0
	match phase:
		Phase.IMPACT:
			var u: float = clampf(phase_time / IMPACT_TIME, 0.0, 1.0)
			pitch = lerpf(0.0, LYING_PITCH, pow(u, 2.2))   # gravity: slow off the mark, hard at the end
			lift = sin(u * PI) * 0.18 * (1.0 - u) + LYING_LIFT * pow(u, 2.2)   # feet leave the ground, then he drops
			if u > 0.85:
				pitch += sin((u - 0.85) / 0.15 * PI) * 0.07   # the rebound as his back hits
		Phase.DOWNED:
			var breath: float = sin(phase_time * 9.0)
			pitch = LYING_PITCH + breath * 0.02
			roll = lerpf(0.0, 0.12, clampf(phase_time / 0.25, 0.0, 1.0)) * (1.0 + breath * 0.2)
			lift = LYING_LIFT
		Phase.GETTING_UP:
			var u: float = clampf(phase_time / GET_UP_TIME, 0.0, 1.0)
			if u < 0.35:   # roll up onto a hip, one arm planted
				var a: float = ease(u / 0.35, 0.7)
				pitch = lerpf(LYING_PITCH, BRACE_PITCH, a)
				roll = lerpf(0.12, BRACE_ROLL, a)
				lift = lerpf(LYING_LIFT, 0.12, a)
			elif u < 0.7:   # drag a knee under him and hunch over it
				var a: float = ease((u - 0.35) / 0.35, 0.8)
				pitch = lerpf(BRACE_PITCH, HUNCH_PITCH, a)
				roll = lerpf(BRACE_ROLL, 0.1, a)
				lift = lerpf(0.12, KNEEL_SINK, a)
			else:   # legs drive him upright
				var a: float = ease((u - 0.7) / 0.3, 1.8)
				pitch = lerpf(HUNCH_PITCH, 0.0, a)
				roll = lerpf(0.1, 0.0, a)
				lift = lerpf(KNEEL_SINK, 0.0, a)
	p.visual.rotation.x = pitch
	p.visual.rotation.z = roll
	p.visual.position.y = lift
