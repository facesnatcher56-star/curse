class_name Sfx
extends RefCounted
## Procedural sound effects (no audio assets needed). Each sound is synthesised once and cached.

const RATE := 22050

static var _cache: Dictionary = {}

## Master switch. Sound is off for now; set to true to bring the synthesized effects back.
static var enabled: bool = false

static func play(from: Node, sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled:
		return
	var player := AudioStreamPlayer.new()
	player.stream = _stream_for(sound)
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.92, 1.08)
	from.get_tree().current_scene.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

## Recorded sounds (res://assets/audio/NAME.ogg). They follow the same "Sound effects" switch as the synthesised ones.
static var _files: Dictionary = {}
static var _last_played: Dictionary = {}
## How many recorded sounds have been started (tests read this).
static var samples_played: int = 0
const SAMPLE_GAP_MS := 45   # a sweep that hits six enemies is one crunch, not six stacked on top of each other

## Sound families: several recordings of the same event; one is picked at random (never the same twice running).
const FAMILIES := {
	"sword_hit": ["sword_hit", "sword_hit_2"],
	"sword_miss": ["sword_miss_1", "sword_miss_2", "sword_miss_3", "sword_miss_4"],
	"fireball_cast": ["fireball_cast_1", "fireball_cast_2"],
	"fireball_impact": ["fireball_impact"],
}
static var _last_pick: Dictionary = {}

static func _pick(family: String) -> String:
	var options: Array = FAMILIES.get(family, [family])
	if options.size() == 1:
		return options[0]
	var choice: int = randi() % options.size()
	if choice == int(_last_pick.get(family, -1)):
		choice = (choice + 1 + randi() % (options.size() - 1)) % options.size()
	_last_pick[family] = choice
	return options[choice]

static func _load_file(name: String) -> AudioStream:
	for extension in ["ogg", "wav"]:
		var path: String = "res://assets/audio/%s.%s" % [name, extension]
		if ResourceLoader.exists(path):
			return load(path)
	return null

## Plays a recorded sound, or a random member of its family. `last_name` (tests) is the file that was used.
static var last_name: String = ""
## Every recording played, in order (tests read this).
static var played_log: Array[String] = []

static func sample(from: Node, family: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled:
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_last_played.get(family, -1000)) < SAMPLE_GAP_MS:
		return
	var name: String = _pick(family)
	if not _files.has(name):
		_files[name] = _load_file(name)
	var stream: AudioStream = _files[name]
	if stream == null:
		return
	last_name = name
	played_log.append(name)
	_last_played[family] = now
	samples_played += 1
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch * randf_range(0.95, 1.05)
	from.get_tree().current_scene.add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

## The blade cutting empty air: one of the four swing recordings.
static func sword_miss(from: Node) -> void:
	sample(from, "sword_miss", -2.0, randf_range(0.95, 1.1))

## The sword connecting with a body: a heavier hit sounds lower and louder. Never called for misses or blocks.
static func sword_hit(from: Node, outcome: int, weight: float) -> void:
	match outcome:
		Combat.Outcome.CRUSHING:
			sample(from, "sword_hit", 3.0, 0.8)
		Combat.Outcome.CRITICAL:
			sample(from, "sword_hit", 1.5, 0.9)
		_:
			sample(from, "sword_hit", -1.0, 1.0 / maxf(weight, 0.8) ** 0.3)

static func _stream_for(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _to_stream(Callable(Sfx, "_make_" + sound).call())
	return _cache[sound]

# --- synthesis helpers -----------------------------------------------------------

static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav

static func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out

static func _noise_burst(seconds: float, lowpass: float, decay: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(seconds)
	var y: float = 0.0
	for i in out.size():
		var t: float = float(i) / RATE
		y += lowpass * (randf_range(-1.0, 1.0) - y)
		out[i] = y * exp(-t * decay) * gain
	return out

static func _sine_sweep(seconds: float, f0: float, f1: float, decay: float, gain: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(seconds)
	var phase: float = 0.0
	for i in out.size():
		var t: float = float(i) / RATE
		var f: float = f1 + (f0 - f1) * exp(-t * 18.0)
		phase += TAU * f / RATE
		out[i] = sin(phase) * exp(-t * decay) * gain
	return out

static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = a.duplicate()
	if b.size() > out.size():
		out.resize(b.size())
	for i in b.size():
		out[i] += b[i]
	return out

# --- sounds ---------------------------------------------------------------------

static func _make_swing() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(0.32)
	var low: float = 0.0
	var high: float = 0.0
	for i in out.size():
		var t: float = float(i) / RATE
		var u: float = t / 0.32
		var cutoff: float = 0.04 + 0.5 * sin(u * PI)
		var n: float = randf_range(-1.0, 1.0)
		low += cutoff * (n - low)
		high += 0.02 * (low - high)
		out[i] = (low - high) * sin(u * PI) * sin(u * PI) * 1.4
	return out

static func _make_swing_heavy() -> PackedFloat32Array:
	var out: PackedFloat32Array = _make_swing()
	var low: PackedFloat32Array = _sine_sweep(0.35, 180.0, 70.0, 6.0, 0.35)
	return _mix(out, low)

static func _make_hit() -> PackedFloat32Array:
	return _mix(_sine_sweep(0.22, 170.0, 55.0, 16.0, 0.9), _noise_burst(0.12, 0.35, 40.0, 0.8))

static func _make_crit() -> PackedFloat32Array:
	var body: PackedFloat32Array = _mix(_sine_sweep(0.3, 200.0, 50.0, 12.0, 1.0), _noise_burst(0.2, 0.5, 28.0, 0.9))
	var crack: PackedFloat32Array = _noise_burst(0.1, 0.95, 50.0, 0.7)
	return _mix(body, crack)

static func _make_crush() -> PackedFloat32Array:
	var body: PackedFloat32Array = _mix(_sine_sweep(0.5, 120.0, 32.0, 7.0, 1.0), _noise_burst(0.35, 0.3, 14.0, 0.9))
	return _mix(body, _noise_burst(0.14, 0.9, 35.0, 0.8))

static func _make_clang() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(0.45)
	var partials: Array[float] = [520.0, 1210.0, 2090.0, 3150.0]
	for i in out.size():
		var t: float = float(i) / RATE
		var s: float = 0.0
		for k in partials.size():
			s += sin(TAU * partials[k] * t) * exp(-t * (9.0 + k * 6.0)) / (k + 1.0)
		out[i] = s * 0.8
	return _mix(out, _noise_burst(0.03, 0.9, 120.0, 0.6))

static func _make_miss() -> PackedFloat32Array:
	var out: PackedFloat32Array = _make_swing()
	for i in out.size():
		out[i] *= 0.45
	return out

static func _make_explosion() -> PackedFloat32Array:
	return _mix(_noise_burst(0.8, 0.12, 5.0, 1.4), _sine_sweep(0.7, 90.0, 38.0, 5.0, 0.9))

static func _make_fire_whoosh() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(0.5)
	var low: float = 0.0
	for i in out.size():
		var t: float = float(i) / RATE
		var u: float = t / 0.5
		low += (0.05 + 0.25 * u) * (randf_range(-1.0, 1.0) - low)
		out[i] = low * sin(u * PI) * 1.6
	return out

static func _make_groan() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(0.75)
	var phase: float = 0.0
	var low: float = 0.0
	for i in out.size():
		var t: float = float(i) / RATE
		var u: float = t / 0.75
		var f: float = 78.0 + 22.0 * sin(u * PI) + sin(t * 31.0) * 5.0
		phase += f / RATE
		var saw: float = fmod(phase, 1.0) * 2.0 - 1.0
		low += 0.07 * (saw - low)
		out[i] = low * sin(u * PI) * 2.2 + randf_range(-0.04, 0.04) * sin(u * PI)
	return out

static func _make_death_groan() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(1.1)
	var phase: float = 0.0
	var low: float = 0.0
	for i in out.size():
		var t: float = float(i) / RATE
		var u: float = t / 1.1
		var f: float = 95.0 - 45.0 * u
		phase += f / RATE
		var saw: float = fmod(phase, 1.0) * 2.0 - 1.0
		low += 0.06 * (saw - low)
		out[i] = low * pow(sin(u * PI), 0.7) * 2.4
	return out

static func _make_hurt() -> PackedFloat32Array:
	return _mix(_sine_sweep(0.25, 210.0, 120.0, 10.0, 0.7), _noise_burst(0.15, 0.25, 22.0, 0.5))

static func _make_potion() -> PackedFloat32Array:
	var out: PackedFloat32Array = _buffer(0.5)
	for i in out.size():
		var t: float = float(i) / RATE
		var f: float = 520.0 if t < 0.12 else (660.0 if t < 0.24 else 880.0)
		out[i] = sin(TAU * f * t) * exp(-fmod(t, 0.12) * 14.0) * 0.5 * exp(-t * 3.0)
	return out
