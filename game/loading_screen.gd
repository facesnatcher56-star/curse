class_name LoadingScreen
extends Control
## Loading screen with a real progress bar and a rotating message.
##
## It requests every heavy asset (models, animation libraries, icons, data resources) and the game scene itself on
## background threads, advances the bar by how much of the work (weighted by file size) is done, and when everything is
## in memory switches to the game. The first frame of play then has nothing left to load.
##
## Go there with `LoadingScreen.go(tree, scene_path)`.

signal finished

const SCENE := "res://game/loading.tscn"
const ROOTS: Array[String] = ["res://assets/models", "res://assets/icons", "res://data"]
const WANTED_EXTENSIONS: Array[String] = ["glb", "res", "png", "tres"]

## Messages shown while loading: some about the game, some about nothing at all.
const MESSAGES: Array[String] = [
	"Polishing the sword. Again.",
	"Convincing the zombies to form an orderly queue",
	"Teaching the Bloater about personal space",
	"Reticulating splines",
	"Downloading more RAM",
	"Untangling the controller cables",
	"Counting to infinity (twice)",
	"Asking the cat for permission",
	"Warming up the fireballs (careful, they're hot)",
	"Sharpening the pixels",
	"Looking for the 'any' key",
	"Feeding the gremlins that make the models",
	"Sweeping gibs under the rug",
	"Applying anti-gravity to the ragdolls",
	"Reading the terms and conditions (all 9,000 pages)",
	"Hiding the potions in plain sight",
	"Rolling for initiative",
	"Calibrating the dodge roll to 'just in time'",
	"Rehearsing dramatic death animations",
	"Alphabetizing the affixes",
	"Bribing the navmesh",
	"Asking the Plague Priest to stop warding things",
	"Telling the Ghoul to blink less",
	"Defrosting the frostbite",
	"Teaching the knight to say 'ow' in twelve languages",
	"Buffering the buffer",
	"Dusting off the gravestones",
	"Wondering why the Spitter has such good aim",
	"Checking under the bed for Brutes",
	"Locating the missing sock",
	"Taking a short break to think about pizza",
	"Inflating the Bloater (safely)",
	"Charging the lightning (it was at 3%)",
	"Memorising 'LB is the potion button'",
	"Rendering the fog, one particle at a time",
	"Spawning enough zombies to be rude",
	"Tuning the crunch of a critical hit",
	"Hiring a guard for the loot goblin (there is no loot goblin)",
	"Persuading the camera to stay at a 3/4 angle",
	"Sanding the corners off the arena",
	"Updating the update that updates updates",
	"Please hold. Your hero is very important to us",
	"Watering the dead trees",
	"Reversing the polarity of the navmesh",
	"Loading... loading... still loading... done soon",
]

const MESSAGE_SECONDS := 1.7

## The scene to load and start. Set by go().
static var next_scene: String = "res://game/main.tscn"

## Tests turn this off to inspect the screen without leaving the scene.
var auto_switch: bool = true
var progress: float = 0.0          # what the bar shows (eased)
var real_progress: float = 0.0     # what has actually loaded
var assets_total: int = 0
var assets_done: int = 0
var message: String = ""

var _paths: Array[String] = []
var _weights: Dictionary = {}
var _done: Dictionary = {}
var _bar: ProgressBar
var _percent: Label
var _message_label: Label
var _count_label: Label
var _message_timer: float = 0.0
var _last_message: int = -1
var _finished: bool = false
var _switch_in: float = -1.0

## Opens the loading screen, which loads `scene_path` and then switches to it.
static func go(tree: SceneTree, scene_path: String) -> void:
	next_scene = scene_path
	tree.change_scene_to_file(SCENE)

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_collect_assets()
	for path in _paths:
		ResourceLoader.load_threaded_request(path, "", true)
	next_message()

func _build_ui() -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.04, 0.05)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.custom_minimum_size = Vector2(760, 0)
	center.add_child(column)
	column.add_child(UiTheme.title_label("Loading", 56))
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(760, 26)
	_bar.add_theme_stylebox_override("background", UiTheme.box(Color(0.1, 0.1, 0.13), UiTheme.BORDER, 1, 3, 0))
	_bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.ACCENT, UiTheme.ACCENT, 0, 3, 0))
	column.add_child(_bar)
	var row := HBoxContainer.new()
	column.add_child(row)
	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_count_label)
	_percent = Label.new()
	_percent.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(_percent)
	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 22)
	_message_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(760, 64)
	column.add_child(_message_label)

## Every heavy file the game will want, plus the scene to start.
func _collect_assets() -> void:
	var seen: Dictionary = {}
	for root in ROOTS:
		_scan(root, seen)
	if ResourceLoader.exists(next_scene) and not seen.has(next_scene):
		seen[next_scene] = true
		_paths.append(next_scene)
		_weights[next_scene] = 400000.0   # the scene builds the arena when it starts: weight it like a big model
	assets_total = _paths.size()
	_count_label.text = "0 / %d" % assets_total

func _scan(dir_path: String, seen: Dictionary) -> void:
	for sub in DirAccess.get_directories_at(dir_path):
		_scan("%s/%s" % [dir_path, sub], seen)
	for file in DirAccess.get_files_at(dir_path):
		var name: String = file.trim_suffix(".remap")
		if name.get_extension() not in WANTED_EXTENSIONS or name.ends_with(".import"):
			continue
		var path: String = "%s/%s" % [dir_path, name]
		if seen.has(path) or not ResourceLoader.exists(path):
			continue
		seen[path] = true
		_paths.append(path)
		var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
		_weights[path] = float(handle.get_length()) if handle != null else 50000.0
		if _weights[path] < 20000.0:
			_weights[path] = 20000.0

## A new message, never the one just shown.
func next_message() -> String:
	var index: int = randi() % MESSAGES.size()
	if index == _last_message:
		index = (index + 1 + randi() % (MESSAGES.size() - 1)) % MESSAGES.size()
	_last_message = index
	message = MESSAGES[index]
	if _message_label != null:
		_message_label.text = message
	_message_timer = MESSAGE_SECONDS
	return message

func _process(delta: float) -> void:
	_poll()
	# The bar eases toward the real progress so it moves smoothly rather than jumping with each file.
	progress = move_toward(progress, real_progress, delta * (0.35 + real_progress))
	_bar.value = progress
	_percent.text = "%d%%" % int(round(progress * 100.0))
	_count_label.text = "%d / %d" % [assets_done, assets_total]
	_message_timer -= delta
	if _message_timer <= 0.0:
		next_message()
	if _finished and not auto_switch:
		return
	if _finished and progress >= 0.999:
		if _switch_in < 0.0:
			_switch_in = 0.15   # a beat at 100% so the bar is seen to finish
			_message_label.text = "Building the arena..."
		_switch_in -= delta
		if _switch_in <= 0.0:
			set_process(false)
			var packed: PackedScene = ResourceLoader.load_threaded_get(next_scene) as PackedScene
			get_tree().change_scene_to_packed(packed)

func _poll() -> void:
	if _finished:
		return
	var total: float = 0.0
	var got: float = 0.0
	var done: int = 0
	var failed: bool = false
	for path in _paths:
		var weight: float = float(_weights[path])
		total += weight
		if _done.has(path):
			got += weight
			done += 1
			continue
		var progress_array: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(path, progress_array)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				_done[path] = true
				got += weight
				done += 1
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				got += weight * (float(progress_array[0]) if not progress_array.is_empty() else 0.0)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_done[path] = true   # a missing optional asset must not hang the screen
				got += weight
				done += 1
				failed = true
	assets_done = done
	real_progress = got / maxf(total, 1.0) if total > 0.0 else 1.0
	if failed:
		push_warning("LoadingScreen: some assets failed to preload (they will load on demand)")
	if done >= assets_total:
		_finished = true
		real_progress = 1.0
		finished.emit()
