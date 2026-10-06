class_name Sfx
extends RefCounted
## Sound effects: recorded files in res://assets/audio (nothing is synthesised). Sounds are grouped in families; one recording
## of a family is picked at random each time.

## Master switch (the "Sound effects" setting).
static var enabled: bool = false

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
	"leap_land": ["leap_land"],
	# Reuse the owner's recorded steel and body impacts at distinct pitches.
	"body_wall": ["leap_land"],
	"body_enemy": ["sword_hit_2"],
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
