extends Node3D
## Clip review: every clip of the knight2 library played on the hero rig (right) beside the knight it was made for
## (left), sampled at SAMPLES points across the clip, from the front three-quarter view and from the side. Writes one strip
## per clip to user://clip_review/<clip>.png (paths printed). Run res://game/dev/clip_review.tscn (F6); quits when done.

const OUT := "user://clip_review"
const SAMPLES := 6
const CELL := Vector2i(360, 360)
const KNIGHT := "res://assets/models/knight2"
const VIEWS := [[Vector3(2.6, 1.7, 4.6), Vector3(0, 1.0, 0)], [Vector3(6.0, 1.4, 0.4), Vector3(0, 1.0, 0)]]
## Non-empty: only these clips, hero alone and close (front, side, top three-quarter) instead of the side-by-side.
const FOCUS: Array[String] = []
const FOCUS_VIEWS := [[Vector3(1.1, 1.5, 2.2), Vector3(1.1, 1.2, 0)], [Vector3(3.3, 1.4, 0.2), Vector3(1.1, 1.2, 0)],
	[Vector3(2.0, 2.6, 1.6), Vector3(1.1, 1.1, 0)]]

var _hero: CharacterModel
var _knight: CharacterModel
var _cam: Camera3D

func _ready() -> void:
	TownState.persist = false
	DirAccess.make_dir_recursive_absolute(OUT)
	get_window().size = CELL
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.16, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	(floor_mesh.mesh as PlaneMesh).size = Vector2(12, 12)
	add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.make_current()

	var clips: Array[String] = []
	clips.assign(Player.CLIPS)
	_knight = CharacterModel.build(KNIGHT, clips)
	_knight.position = Vector3(-1.1, 0, 0)
	add_child(_knight)
	_hero = CharacterModel.build(CharacterPresentation.folder("hero"), clips, false)
	_hero.position = Vector3(1.1, 0, 0)
	add_child(_hero)
	CharacterPresentation.share_combat_clips(_hero)
	ModularAppearance.new(_hero).sync({})
	print("CLIP REVIEW -> ", ProjectSettings.globalize_path(OUT))

	var lib := _knight.anim.get_animation_library("game")
	await _frames(4)   # the first captures after the window resize come out blank
	var views: Array = VIEWS if FOCUS.is_empty() else FOCUS_VIEWS
	_knight.visible = FOCUS.is_empty()
	for clip in (lib.get_animation_list() if FOCUS.is_empty() else PackedStringArray(FOCUS)):
		var length: float = lib.get_animation(clip).length
		var strip := Image.create(CELL.x * SAMPLES, CELL.y * views.size(), false, Image.FORMAT_RGB8)
		for i in SAMPLES:
			var t := length * float(i) / float(SAMPLES - 1)
			for model in [_knight, _hero]:
				model.anim.play("game/" + clip, 0.0)
				model.anim.seek(t, true)
				model.anim.pause()
			for v in views.size():
				_cam.look_at_from_position(views[v][0], views[v][1])
				await _frames(2)
				await RenderingServer.frame_post_draw
				var shot := get_viewport().get_texture().get_image()
				shot.convert(Image.FORMAT_RGB8)
				strip.blit_rect(shot, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, v * CELL.y))
		strip.save_png("%s/%s.png" % [OUT, clip])
	print("CLIP REVIEW DONE")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
