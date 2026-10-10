class_name HitReaction
extends RefCounted
## The directional part of an ordinary stagger. The "hit" clip is one pose for every blow; this leans and twists the hero's model
## (feet planted: it is a rotation about his own origin, never a displacement) away from where the blow came from, so a hit from the
## front rocks him back, one from behind pitches him forward and one from the side bends him along it with the shoulders turning
## into it. It lasts exactly as long as the stagger it decorates (no extra stun, no invulnerability), is dropped the moment a fall,
## death, roll or revival takes over, and leaves the model upright.

var p: Player

func _init(player: Player) -> void:
	p = player

const MAX_PITCH := 0.17    # radians: rocked back (front blow) / pitched forward (rear blow)
const MAX_ROLL := 0.15     # bent along a side blow
const MAX_TWIST := 0.2     # the shoulders turn into a side blow
const ATTACK := 0.07       # seconds to reach the full lean (the blow lands hard)

var lean: Vector3 = Vector3.ZERO   # the full lean of the current blow (pitch, yaw, roll)
var duration: float = 0.0
var elapsed: float = 0.0
var reactions: int = 0             # blows reacted to (tests, diagnostics)
var _on: bool = false

func active() -> bool:
	return _on

## The blow came from `from` (world position); `duration` is the stagger it causes.
func begin(from: Vector3, stagger: float) -> void:
	var away: Vector3 = p.global_position - from
	away.y = 0.0
	if away.length() < 0.05 or p.visual == null or stagger < 0.08:
		return
	# The push in the hero's own frame: z = in front of him (he is thrown backward when negative), x = to his left.
	var local: Vector3 = away.normalized().rotated(Vector3.UP, -p.visual.rotation.y)
	lean = Vector3(local.z * MAX_PITCH, -local.x * MAX_TWIST, -local.x * MAX_ROLL)
	duration = stagger
	elapsed = 0.0
	reactions += 1
	_on = true

func tick(delta: float) -> void:
	if not _on:
		return
	if p.dead or p.knockdown.active() or p.movement.rolling or elapsed >= duration:
		clear()
		return
	elapsed += delta
	var rise: float = clampf(elapsed / ATTACK, 0.0, 1.0)
	var fall: float = clampf((duration - elapsed) / maxf(duration - ATTACK, 0.01), 0.0, 1.0)
	var k: float = rise * smoothstep(0.0, 1.0, fall)
	p.model.rotation = lean * k

func clear() -> void:
	if _on or p.model.rotation != Vector3.ZERO:
		p.model.rotation = Vector3.ZERO
	_on = false
