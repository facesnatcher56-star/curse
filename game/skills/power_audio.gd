extends RefCounted
## Four recorded composites, baked offline; no mixing/DSP overhead in combat.
## DS2-inspired pitch and per-event concurrency, with conservative mix headroom.

## Brutal Attack and Take Aim (the first pass), then the cast and impact cues of Whirling Strike, Staggering Blow and War Cry
## (tools/build_power_cues.py, sources in assets/audio/CREDITS.md).
const EVENTS := ["brutal_hit", "take_aim_charge", "take_aim_fire", "take_aim_hit",
	"whirling_strike_cast", "whirling_strike_hit", "staggering_cast", "staggering_hit", "war_cry_cast", "war_cry_hit"]
static var _streams: Dictionary = {}

static func play(from: Node3D, event: String) -> bool:
	if event not in EVENTS:
		return false
	if not _streams.has(event):
		_streams[event] = load("res://assets/audio/powers/%s.wav" % event)
	if _streams[event] == null:
		return false
	var voices: Array[Node] = from.get_tree().get_nodes_in_group("power_audio_" + event).filter(func(node: Node) -> bool: return not node.is_queued_for_deletion())
	# Retire the oldest tail rather than drop a new contact. Two voices per cue.
	if voices.size() >= 2:
		(voices[0] as AudioStreamPlayer3D).stop()
		voices[0].queue_free()
	var voice := AudioStreamPlayer3D.new()
	voice.stream = _streams[event]
	voice.volume_db = -4.0 if event == "take_aim_charge" else -1.0
	voice.bus = _bus()
	voice.pitch_scale = randf_range(0.9, 1.1)
	voice.unit_size = 7.0 if event == "brutal_hit" else 6.0
	voice.max_distance = 30.0
	voice.max_db = voice.volume_db  # Never amplify near-camera audio above the authored gain.
	voice.add_to_group("sfx_voice")
	voice.add_to_group("power_audio_" + event)
	from.get_tree().current_scene.add_child(voice)
	voice.global_position = from.global_position
	voice.finished.connect(voice.queue_free)
	voice.play()
	return true

static func _bus() -> StringName:
	if AudioServer.get_bus_index("PowerFx") < 0:
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "PowerFx")
		AudioServer.set_bus_send(index, "Master")
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -4.0
		limiter.threshold_db = 0.0
		AudioServer.add_bus_effect(index, limiter)
	return &"PowerFx"
