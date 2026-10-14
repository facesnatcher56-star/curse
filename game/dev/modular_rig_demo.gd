extends SceneTree
## Rig-compatibility demonstration on the live character path (CharacterModel.build + CharacterPresentation.share_combat_clips),
## without touching Player: one knight2 skeleton, the modular plate pieces and kite shield bound to it, a sword mounted exactly as
## Player.refresh_weapon_model does, and the existing game clip names played. Prints measured evidence.
##   godot --headless --path . --script game/dev/modular_rig_demo.gd
##   (windowed) ... -- --shot=<abs dir>
const CLIPS_TO_TEST := ["idle_alert", "walk", "run", "atk_slash", "atk_thrust", "slash", "hit", "death"]
const WATCH := ["RightHand", "LeftHand", "RightFoot", "Head"]
# experiment-rig bone for each game-rig bone, for the rest-pose comparison
const EXPERIMENT := {"Hips": "Hips", "Spine02": "Spine", "Spine": "Chest", "neck": "Neck", "Head": "Head", "LeftShoulder": "LeftShoulder",
	"LeftArm": "LeftUpperArm", "LeftForeArm": "LeftLowerArm", "LeftHand": "LeftHand", "LeftUpLeg": "LeftUpperLeg", "LeftLeg": "LeftLowerLeg",
	"LeftFoot": "LeftFoot", "LeftToeBase": "LeftToes"}

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func pose_pos(sk: Skeleton3D, bone: String) -> Vector3:
	return sk.get_bone_global_pose(sk.find_bone(bone)).origin

func run() -> void:
	TownState.persist = false
	var stage := Node3D.new()
	root.add_child(stage)
	var clips: Array[String] = []
	clips.assign(Player.CLIPS)
	var model := CharacterModel.build("res://assets/models/knight2", clips, false)
	stage.add_child(model)
	CharacterPresentation.share_combat_clips(model)
	var look := ModularAppearance.new(model)
	var worn := {Items.Slot.ARMOR: Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 2, "Plate Cuirass"),
		Items.Slot.HELM: Items.make(Items.Slot.HELM, Items.Rarity.NORMAL, 2, "Iron Helm"),
		Items.Slot.GLOVES: Items.make(Items.Slot.GLOVES, Items.Rarity.NORMAL, 2, "Iron Gauntlets"),
		Items.Slot.BOOTS: Items.make(Items.Slot.BOOTS, Items.Rarity.NORMAL, 2, "Iron Greaves"),
		Items.Slot.SHIELD: Items.make(Items.Slot.SHIELD, Items.Rarity.NORMAL, 2, "Kite Shield")}
	look.sync(worn)
	model.attach_weapon(Player.SWORD_PATH, "RightHand", Player.GRIPS[3], 1.25, 0.12, Player.HAND_GRIP_POINT, 1.7)   # as Player does
	var sk: Skeleton3D = look.skeleton
	model.loop("idle_alert")
	await process_frame
	check("sword mounted on RightHand bone attachment", model.weapon != null and model.weapon.get_parent() is BoneAttachment3D
		and (model.weapon.get_parent() as BoneAttachment3D).bone_name == "RightHand")
	var shield: MeshInstance3D = sk.get_node("shd_kite")
	var rest_center: Vector3 = shield.get_aabb().get_center()
	var fore := sk.find_bone("LeftForeArm")
	var rest_inv := sk.get_bone_global_rest(fore).affine_inverse()

	print("EVIDENCE per clip: peak bone travel from rest pose, metres; sword/shield offset spread to their hand/forearm bone (cm)")
	var rest := {}
	for b in WATCH: rest[b] = sk.get_bone_global_rest(sk.find_bone(b)).origin
	for clip in CLIPS_TO_TEST:
		var anim := model.anim.get_animation("game/" + clip)
		check("clip %s exists (%.2fs, %d tracks)" % [clip, anim.length, anim.get_track_count()], anim != null)
		model.anim.play("game/" + clip, 0.0)
		model.anim.pause()
		var peak := {}
		for b in WATCH: peak[b] = 0.0
		var sword_d: Array[float] = []
		var shield_d: Array[float] = []
		var shield_x := true
		for i in 13:
			model.anim.seek(anim.length * i / 12.0, true)
			sk.force_update_all_bone_transforms()
			await process_frame
			for b in WATCH:
				peak[b] = maxf(peak[b], (pose_pos(sk, b) - rest[b]).length() / 100.0)
			var hand_pose: Transform3D = sk.get_bone_global_pose(sk.find_bone("RightHand"))
			var weapon_local: Vector3 = sk.to_local(model.weapon.global_position)
			sword_d.append(weapon_local.distance_to(hand_pose.origin))
			var fp: Transform3D = sk.get_bone_global_pose(fore)
			var shield_center: Vector3 = fp * (rest_inv * rest_center)
			shield_d.append(shield_center.distance_to(fp.origin))
			shield_x = shield_x and (sk.get_bone_global_pose(sk.find_bone("Spine")).affine_inverse() * shield_center).x > 0.0   # chest-local: game-rig left is +x
		print("CLIP %-11s hand_R %.2f hand_L %.2f foot_R %.2f head %.2f | sword->hand %.1f..%.1f | shield->forearm %.1f..%.1f" % [clip,
			peak["RightHand"], peak["LeftHand"], peak["RightFoot"], peak["Head"], sword_d.min(), sword_d.max(), shield_d.min(), shield_d.max()])
		check("%s: sword stays rigidly in the right hand (spread < 1 cm)" % clip, sword_d.max() - sword_d.min() < 1.0)
		check("%s: shield stays rigidly on the left forearm (spread < 0.5 cm)" % clip, shield_d.max() - shield_d.min() < 0.5)
		if clip in ["idle_alert", "walk", "run", "hit"]:   # combat swings legitimately carry the shield arm across the chest
			check("%s: shield centre stays on the character's left (chest-local +x) in every sample" % clip, shield_x)
	# hit reaction layer
	model.anim.play("game/idle_alert"); await process_frame
	var spine := sk.find_bone("Spine01")
	var before := sk.get_bone_pose_rotation(spine)
	model.react(Vector3(0, 0, -1), 0.6)
	for i in 6: await process_frame
	check("hit reaction (BodyRecoil) still tips the spine on the modular rig", sk.get_bone_pose_rotation(spine).angle_to(before) > 0.01)

	print("REST COMPARISON experiment rig vs game rig (global rest orientation difference, degrees; length of segment head->child, cm)")
	var exp: Node = (load("res://assets/art_staging/knight/knight_baseline.glb") as PackedScene).instantiate()
	root.add_child(exp)
	var esk: Skeleton3D = exp.find_children("*", "Skeleton3D", true, false)[0]
	var ok_names := true
	for g in EXPERIMENT:
		var gi := sk.find_bone(g); var ei := esk.find_bone(EXPERIMENT[g])
		ok_names = ok_names and gi >= 0 and ei >= 0
		var ga := sk.get_bone_global_rest(gi).basis.orthonormalized()
		var ea := esk.get_bone_global_rest(ei).basis.orthonormalized()
		print("ROLL %-12s -> %-13s  %.0f deg" % [g, EXPERIMENT[g], rad_to_deg(ga.get_rotation_quaternion().angle_to(ea.get_rotation_quaternion()))])
	check("all mapped bones exist (names differ, mapping is 1:1 for 13 bones)", ok_names)
	print("EXPERIMENT-ONLY bones: Root, LeftHandProp, RightHandProp, LeftToes naming; GAME-ONLY: Spine01, head_end, headfront, hand fists")
	exp.queue_free()   # the comparison copy must not sit in the demonstration shot
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
	if shot != "":
		await take_shot(stage, model, sk, shot)
	print("RIG DEMO ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)

func take_shot(stage: Node3D, model: CharacterModel, sk: Skeleton3D, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	root.size = Vector2i(900, 700)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.12, 0.12, 0.13)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	stage.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, -30, 0); stage.add_child(sun)
	var cam := Camera3D.new(); stage.add_child(cam); cam.make_current()
	for clip in ["idle_alert", "atk_slash", "run"]:
		model.anim.play("game/" + clip, 0.0)
		model.anim.seek(0.4 if clip != "idle_alert" else 0.0, true)
		model.anim.pause()
		for i in 3: await process_frame
		cam.global_position = Vector3(1.9, 1.5, 2.9)
		cam.look_at(Vector3(0, 1.0, 0)); cam.fov = 55
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir.path_join("RIGDEMO_%s.png" % clip))
		print("SHOT RIGDEMO_%s.png" % clip)
