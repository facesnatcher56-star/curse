extends Node3D
## Visual inspection of the hero rig (CharacterPresentation's "hero" model) on the live character path: the modular
## appearance, the sword as Player mounts it, and the game clips. Renders front, back, both sides, top and the game's
## camera angle for several outfits, a face close-up and a few clips, into user://hero_inspect/*.png (paths printed).
## Open res://game/dev/hero_inspect.tscn and run it (F6); it quits when done. Saving and the town file are untouched.

const OUT := "user://hero_inspect"
const VIEWS := {   # name -> [camera position, look-at point, fov]
	"front": [Vector3(0, 1.1, 3.4), Vector3(0, 1.0, 0), 45.0],   # the rig faces +Z
	"back": [Vector3(0, 1.1, -3.4), Vector3(0, 1.0, 0), 45.0],
	"left": [Vector3(3.4, 1.1, 0), Vector3(0, 1.0, 0), 45.0],
	"right": [Vector3(-3.4, 1.1, 0), Vector3(0, 1.0, 0), 45.0],
	"top": [Vector3(0.01, 4.2, 0.6), Vector3(0, 0.9, 0), 45.0],
	"game": [Vector3(0, 8.5, 6.2), Vector3(0, 0.9, 0), 22.0],
}

var _model: CharacterModel
var _look: ModularAppearance
var _cam: Camera3D

func _ready() -> void:
	TownState.persist = false
	DirAccess.make_dir_recursive_absolute(OUT)
	get_window().size = Vector2i(900, 900)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.16, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG   # metals reflect the room, not black
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 200, 0)
	fill.light_energy = 0.45
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	(floor_mesh.mesh as PlaneMesh).size = Vector2(6, 6)
	add_child(floor_mesh)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()

	var clips: Array[String] = []
	clips.assign(Player.CLIPS)
	_model = CharacterModel.build(CharacterPresentation.folder("hero"), clips, false)
	add_child(_model)
	CharacterPresentation.share_combat_clips(_model)
	_look = ModularAppearance.new(_model)
	var built: Dictionary = ModularAppearance.rig(_model.folder)["item_models"].get("longsword", {})   # his starting sword, as Player mounts it
	var grip: Array = _model.finger_grip("Right")
	if not built.is_empty() and not grip.is_empty():
		var measured: Node3D = (load(String(built["model"])) as PackedScene).instantiate()
		var length: float = CharacterModel._bounds_of(measured).size.y
		measured.free()
		_model.attach_weapon(String(built["model"]), "RightHand", grip[0], length, float(built["grip_at"]), grip[1])
		_model.show_weapon(true)
	else:
		_model.attach_weapon(Player.SWORD_PATH, "RightHand", Player.GRIPS[3], 1.25, 0.12, Player.HAND_GRIP_POINT, 1.7)
	print("HERO INSPECT rig ", _model.folder, " -> ", ProjectSettings.globalize_path(OUT))

	var outfits := {
		"bare": {},
		"start": _starting(),
		"plate": {Items.Slot.ARMOR: _item(Items.Slot.ARMOR, "Plate Cuirass"), Items.Slot.HELM: _item(Items.Slot.HELM, "Iron Helm"),
			Items.Slot.GLOVES: _item(Items.Slot.GLOVES, "Iron Gauntlets"), Items.Slot.BOOTS: _item(Items.Slot.BOOTS, "Iron Greaves"),
			Items.Slot.SHIELD: _item(Items.Slot.SHIELD, "Kite Shield")},
		"mage": {Items.Slot.ARMOR: _item(Items.Slot.ARMOR, "Apprentice Robe"), Items.Slot.HELM: _item(Items.Slot.HELM, "Woven Hood"),
			Items.Slot.BOOTS: _item(Items.Slot.BOOTS, "Sorcerer Boots")},
	}
	await _shot("_warmup", VIEWS["front"])   # the first capture after the window resize comes out blank
	for outfit in outfits:
		_look.sync(outfits[outfit])
		await _pose("idle_alert", 0.0)
		for view in VIEWS:
			await _shot("%s_%s" % [outfit, view], VIEWS[view])
	_look.sync({})
	await _pose("idle_alert", 0.0)
	var head: Vector3 = _bone("Head") + Vector3(0, 0.12, 0)
	await _shot("bare_face", [head + Vector3(0.2, 0.0, 0.75), head, 35.0])
	var hand: Vector3 = _bone("RightHand")
	await _shot("bare_hand", [hand + Vector3(-0.45, 0.1, 0.45), hand, 35.0])
	_look.sync(outfits["start"])
	for clip in ["walk", "run", "atk_slash", "atk_thrust", "hit"]:
		await _pose(clip, 0.4)
		await _shot("start_%s" % clip, [Vector3(2.4, 1.6, 2.6), Vector3(0, 1.0, 0), 45.0])
	print("HERO INSPECT DONE")
	get_tree().quit()

func _bone(bone: String) -> Vector3:
	return _look.skeleton.global_transform * _look.skeleton.get_bone_global_pose(_look.skeleton.find_bone(bone)).origin

func _item(slot: int, base: String) -> Dictionary:
	return Items.make(slot, Items.Rarity.NORMAL, 2, base)

func _starting() -> Dictionary:
	var worn := {}
	for item in Items.starting_gear():
		worn[int(item.get("slot", -1))] = item
	return worn

func _pose(clip: String, at: float) -> void:
	_model.anim.play("game/" + clip, 0.0)
	_model.anim.seek(at, true)
	_model.anim.pause()
	for i in 3:
		await get_tree().process_frame

func _shot(name: String, view: Array) -> void:
	_cam.fov = view[2]
	_cam.look_at_from_position(view[0], view[1])
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
