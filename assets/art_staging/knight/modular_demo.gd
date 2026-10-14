extends Node3D
## Modular character demo (staging, not wired into the live game).
## One skinned character (curse_modular.glb); equipment is swapped by toggling mesh visibility.
## Keys: 1 leather fighter, 2 plate knight, 3 robed mage, 4 leather archer
##       H helmet  B body armor  G gloves  F boots  W weapon  S shield
##       A cycle animation  T turntable  Esc quit
## Capture: godot --path . res://assets/art_staging/knight/modular_demo.tscn -- --capture=<abs dir>

const GLB := "res://assets/art_staging/knight/curse_modular.glb"
const ANIMS := ["Idle_Combat", "Walk_Forward", "Run_Forward", "Attack_Sword_Light", "Hit_Reaction_Front", "Death"]
const LOOPING := ["Idle_Combat", "Walk_Forward", "Run_Forward"]

const HEADS := ["", "HLM_Great", "HLM_Kettle", "HLM_Hood"]
const BODIES := ["", "plate", "leather", "robe"]
const GLOVES := ["", "GLV_Plate", "GLV_Leather"]
const BOOTS := ["", "BTS_Plate", "BTS_Leather"]
const WEAPONS := ["", "WPN_Sword", "WPN_Bow"]
const BODY_SETS := {
	"": [], "plate": ["TOR_Plate", "ARM_Plate", "LEG_Plate"], "leather": ["TOR_Leather"], "robe": ["ROBE_Mage"],
}
const PRESETS := {
	"Leather fighter": {"head": "HLM_Kettle", "body": "leather", "gloves": "GLV_Leather", "boots": "BTS_Leather", "weapon": "WPN_Sword", "shield": false},
	"Plate knight": {"head": "HLM_Great", "body": "plate", "gloves": "GLV_Plate", "boots": "BTS_Plate", "weapon": "WPN_Sword", "shield": true},
	"Robed mage": {"head": "HLM_Hood", "body": "robe", "gloves": "", "boots": "BTS_Leather", "weapon": "", "shield": false},
	"Leather archer": {"head": "HLM_Hood", "body": "leather", "gloves": "GLV_Leather", "boots": "BTS_Leather", "weapon": "WPN_Bow", "shield": false},
}

var char_root: Node3D
var meshes := {}
var anim: AnimationPlayer
var state := {}
var preset_name := ""
var anim_idx := 0
var turntable := false
var label: Label
var capturing := false

func _ready() -> void:
	_build_stage()
	var packed: PackedScene = load(GLB)
	char_root = Node3D.new()
	add_child(char_root)
	var inst := packed.instantiate()
	char_root.add_child(inst)
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		meshes[n.name] = n
	anim = inst.find_children("*", "AnimationPlayer", true, false)[0]
	anim.animation_finished.connect(_on_anim_finished)
	for a in LOOPING:
		anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	print("MESHES ", meshes.keys())
	print("ANIMS ", anim.get_animation_list())
	apply_preset("Plate knight")
	play(0)
	var cap := _arg("--capture")
	if cap != "":
		_run_capture(cap)

func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return ""

func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.09, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.47, 0.55)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.35
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.6; disc.bottom_radius = 1.6; disc.height = 0.05
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.025
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.17, 0.16, 0.15); fm.roughness = 1.0
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.fov = 35
	add_child(cam)
	cam.position = Vector3(0, 2.7, 4.2)
	cam.look_at(Vector3(0, 0.95, 0))
	var layer := CanvasLayer.new(); add_child(layer)
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	layer.add_child(label)

func apply_preset(n: String) -> void:
	preset_name = n
	state = PRESETS[n].duplicate()
	refresh()

func refresh() -> void:
	var on := ["BODY_Skin"]
	if state.body != "robe":
		on.append("CLT_Gambeson")
	on.append_array(BODY_SETS[state.body])
	for k in ["head", "gloves", "boots", "weapon"]:
		if state[k] != "":
			on.append(state[k])
	if state.shield:
		on.append("SHD_Kite")
	for n in meshes:
		meshes[n].visible = n in on
	label.text = "%s | head:%s body:%s gloves:%s boots:%s weapon:%s shield:%s | anim:%s\n1-4 presets  H B G F W S swap slots  A anim  T turntable" % [
		preset_name, state.head, state.body, state.gloves, state.boots, state.weapon, state.shield, ANIMS[anim_idx]]

func cycle(key: String, options: Array) -> void:
	state[key] = options[(options.find(state[key]) + 1) % options.size()]
	preset_name = "custom"
	refresh()

func play(i: int) -> void:
	anim_idx = i
	anim.play(ANIMS[i])
	refresh()

func _process(delta: float) -> void:
	if turntable:
		char_root.rotation.y += delta * 0.6

func _on_anim_finished(n: StringName) -> void:
	if n != &"Death" and not capturing:
		play(0)

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_1: apply_preset("Leather fighter")
		KEY_2: apply_preset("Plate knight")
		KEY_3: apply_preset("Robed mage")
		KEY_4: apply_preset("Leather archer")
		KEY_H: cycle("head", HEADS)
		KEY_B: cycle("body", BODIES)
		KEY_G: cycle("gloves", GLOVES)
		KEY_F: cycle("boots", BOOTS)
		KEY_W: cycle("weapon", WEAPONS)
		KEY_S:
			state.shield = not state.shield
			preset_name = "custom"
			refresh()
		KEY_A: play((anim_idx + 1) % ANIMS.size())
		KEY_T: turntable = not turntable
		KEY_ESCAPE: get_tree().quit()

# --- deterministic capture: pose is sought and frozen, then the viewport is saved
func _shot(dir: String, fname: String, a: String, t: float, yaw: float) -> void:
	char_root.rotation.y = deg_to_rad(yaw)
	anim.play(a)
	anim.seek(t, true)
	anim.pause()
	anim_idx = ANIMS.find(a)
	refresh()
	for i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(fname))
	print("SHOT ", fname)

func _run_capture(dir: String) -> void:
	capturing = true
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.5).timeout
	var names := PRESETS.keys()
	for i in names.size():
		apply_preset(names[i])
		var tag := "%d_%s" % [i + 1, String(names[i]).to_lower().replace(" ", "_")]
		await _shot(dir, "godot_%s_idle_front.png" % tag, "Idle_Combat", 0.5, 0)
		await _shot(dir, "godot_%s_idle_back.png" % tag, "Idle_Combat", 0.5, 150)
		await _shot(dir, "godot_%s_run.png" % tag, "Run_Forward", 0.3, 35)
		await _shot(dir, "godot_%s_attack.png" % tag, "Attack_Sword_Light", 0.45, 35)
	apply_preset("Plate knight")
	await _shot(dir, "godot_anim_hit.png", "Hit_Reaction_Front", 0.35, 20)
	await _shot(dir, "godot_anim_death.png", "Death", 2.0, 20)
	await _shot(dir, "godot_anim_walk.png", "Walk_Forward", 0.4, 20)
	apply_preset("Robed mage")
	await _shot(dir, "godot_mage_walk.png", "Walk_Forward", 0.4, 20)
	await _shot(dir, "godot_mage_death.png", "Death", 2.0, 20)
	get_tree().quit()
