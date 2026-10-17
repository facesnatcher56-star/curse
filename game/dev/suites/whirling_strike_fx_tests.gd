extends DevSuite
## Whirling Strike's animation and effects: the spin clips exist for one hand and for two with the impact where PowerController.CASTS says,
## the body really makes one turn, the effect starts with the cast, marks the power's real radius, flashes at the strike frame, hits
## spawn grit, and a cast cut short (a cancel, a knockdown, death) or finished leaves no node behind.

func _count_fx() -> int:
	var n: int = 0
	for child in player.get_children():
		if child is WhirlingStrikeFx and not child.is_queued_for_deletion():
			n += 1
	return n

## Total turn of the hips between two clip times, degrees (consecutive keys, shortest way).
func _hips_turn(anim: Animation, t0: float, t1: float) -> float:
	var idx: int = anim.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
	var total: float = 0.0
	var prev: Quaternion = anim.rotation_track_interpolate(idx, t0)
	var steps: int = 40
	for i in range(1, steps + 1):
		var q: Quaternion = anim.rotation_track_interpolate(idx, lerpf(t0, t1, float(i) / steps))
		total += rad_to_deg(prev.angle_to(q))
		prev = q
	return total

func _hips_forward_yaw() -> float:
	var skeleton: Skeleton3D = player.model.find_children("*", "Skeleton3D", true, false)[0]
	var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hips"))
	var forward: Vector3 = pose.basis.z
	return atan2(forward.x, forward.z)

func _test_whirling_strike_fx() -> void:
	TownState.persist = false
	TownState.reset()
	await get_tree().process_frame
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	for item in Items.starting_gear(): player.stats.equip(item, false)
	TownState.passive_ranks = {"critical_strike": 8, "fortitude": 8, "overbear": 1}
	player.stats.refresh()
	player.set_physics_process(false)
	var powers: PowerController = player.powers
	var s: SkillController = player.skills
	powers.reset()
	s.reset()
	player.global_position = Vector3(46, 0, 46)
	player.reset_physics_interpolation()
	var cast: Dictionary = PowerController.CASTS["whirling_strike"]

	# --- The clips: one hand and two, one turn, impact where the cast expects it ---------------------------------------------------------
	var lib: AnimationLibrary = load("res://assets/models/knight2/anims.res") as AnimationLibrary
	for clip in ["atk_spin", "atk2_spin"]:
		expect("%s exists in the Knight's clips and in Player.CLIPS" % clip, lib.has_animation(clip) and Player.CLIPS.has(clip))
		if not lib.has_animation(clip):
			continue
		var anim: Animation = lib.get_animation(clip)
		expect("%s is long enough for the cast's strike and end (%.2f s)" % [clip, anim.length],
			absf(anim.length - float(cast["end"])) < 0.05 and float(cast["strike"]) < anim.length)
		expect("%s turns the hips a full revolution (and the overshoot) between SPIN_FROM and SPIN_TO" % clip,
			absf(_hips_turn(anim, WhirlingStrikeFx.SPIN_FROM, WhirlingStrikeFx.SPIN_TO) - 430.0) < 25.0)
		var hips_idx: int = anim.find_track(NodePath("Armature/Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
		expect("%s ends facing the way it started" % clip, anim.rotation_track_interpolate(hips_idx, 0.0).angle_to(
			anim.rotation_track_interpolate(hips_idx, anim.length)) < deg_to_rad(8.0))
	expect("the one-handed cast plays the spin clip", String(cast["clip"]) == "atk_spin")
	for id in ["greatsword", "axe_2h", "hammer_2h"]:
		var two: Dictionary = ItemDb.get_def(id).profile.get("two_hand_clips", {}).get("atk_spin", {})
		expect("%s turns with both hands (atk2_spin) on the cast's timings" % id, String(two.get("clip", "")) == "atk2_spin"
			and is_equal_approx(float(two.get("start", -1.0)), float(cast["start"])) and is_equal_approx(float(two.get("strike", -1.0)), float(cast["strike"]))
			and is_equal_approx(float(two.get("end", -1.0)), float(cast["end"])))

	# --- A cast: the effect starts with it and marks the real radius ---------------------------------------------------------------------
	var radius: float = powers.value("whirling_strike", "radius")
	var near: Enemy = _spawn_enemy(player.global_position + Vector3(1.4, 0, 0))
	near.set_physics_process(false)
	near.aggro_range = 0.0
	near.max_health = 50000.0
	near.health = near.max_health
	near.dodge_chance = 0.0
	near.block_chance = 0.0
	expect("the effect is absent before the cast", _count_fx() == 0)
	expect("Whirling Strike starts", powers.activate("whirling_strike", player.global_position) and s.busy)
	expect("the effect starts with the cast, exactly one", _count_fx() == 1 and is_instance_valid(s.whirl_fx))
	expect("its radius is the power's real radius (%.2f)" % radius, is_equal_approx(s.whirl_fx.radius, radius) and radius > 0.5)
	expect("the Meshy war sigil's outer ring sits on that radius", is_equal_approx(s.whirl_fx._sigil.size.x * WhirlingStrikeFx.SIGIL_FILL * 0.5, radius))
	expect("the dust vortex is on the cast too", s.whirl_fx._vortex.size() == 2)
	expect("the clip is the spin and its strike is the cast's", String(s.busy_def["clip"]) == "atk_spin" and float(s.busy_def["strike"]) == float(cast["strike"]))
	await get_tree().process_frame
	expect("it has not struck before the strike frame", not s.whirl_fx.struck)
	for i in 5:
		s.tick_busy(0.02)
		await get_tree().process_frame
	expect("the blades hold still while the body coils (no spin until the counter-clockwise turn begins)", s.whirl_fx.art_yaw < 0.05)

	# --- Through the spin to the strike frame ---------------------------------------------------------------------------------------------
	var blade_seen: bool = false
	var sync_last: float = NAN
	var sync_total: float = 0.0
	var sync_floor: float = 0.0
	var sync_error: float = 0.0
	var guard: int = 0
	while s.busy and not s.busy_hit_done and guard < 300:
		s.tick_busy(0.01)
		guard += 1
		if guard % 5 == 0:
			await get_tree().process_frame
			if s.whirl_fx != null and not s.whirl_fx._art_frozen:
				var turn: float = _hips_forward_yaw()
				if not is_nan(sync_last):
					sync_total += wrapf(turn - sync_last, -PI, PI)
					sync_floor = minf(sync_floor, sync_total)
					sync_error = maxf(sync_error, absf((sync_total - sync_floor) - s.whirl_fx.art_yaw))
				sync_last = turn
			blade_seen = blade_seen or (s.whirl_fx.spinning and s.whirl_fx._samples.size() > 6)
	await get_tree().process_frame
	expect("the blade ribbon and the ground arc are sampled while the body turns", blade_seen)
	expect("at the strike frame the effect flares the sigil and nudges the camera", s.whirl_fx.struck)
	expect("through the spin the blades' angle matched the hips' own turn, read separately here, to within %.3f rad" % sync_error, sync_error < 0.03 and not is_nan(sync_last))
	expect("the damage landed on the same frame", near.health < near.max_health)

	# --- It fades out when the cast is over ------------------------------------------------------------------------------------------------
	guard = 0
	while s.busy and guard < 300:
		s.tick_busy(0.01)
		guard += 1
		if guard % 3 == 0:
			await get_tree().process_frame   # frames as in play, so the turn is followed in small steps
	await get_tree().process_frame
	var fx: WhirlingStrikeFx = s.whirl_fx
	expect("the ground art turns with the body: the sigil's yaw is the hips' unwrapped turn, not a tween",
		fx._sigil.basis.z.is_equal_approx(Basis(Vector3.UP, fx.art_yaw).z) and fx.art_yaw > TAU * 0.9)
	expect("the blades stopped with the turn: frozen once the spin phase is over", fx._art_frozen)
	expect("sparks travel along the blade's own motion at the contact point", not fx.last_contact.is_empty()
		and (fx.last_contact["cut"] as Vector3).dot(fx.last_contact["motion"] as Vector3) > 0.0)
	expect("the vortex's first layer follows it exactly", fx._vortex[0].basis.z.is_equal_approx((Basis.from_euler(Vector3(-PI * 0.5, fx.art_yaw, 0.0))).z))
	expect("an enemy the blade passed got its (visual-only) contact mark once", fx._swept.has(near.get_instance_id()))
	expect("a finished cast lets the effect fade, no longer drawing the blade", s.whirl_fx == null or s.whirl_fx.finished)
	expect("the effect stops sampling the blade", not s.whirl_fx.spinning if s.whirl_fx != null else true)
	for i in 40:
		await get_tree().create_timer(0.02).timeout
	expect("and it is gone shortly after (nothing left on the hero)", _count_fx() == 0)

	# --- Cut short: cancel, knockdown, death, a second cast -------------------------------------------------------------------------------
	powers.reset()
	s.reset()
	powers.activate("whirling_strike", player.global_position)
	s.tick_busy(0.2)
	await get_tree().process_frame
	expect("a second cast shows one effect", _count_fx() == 1)
	s.cancel_action()
	await get_tree().process_frame
	expect("cancelling the cast frees the effect at once", _count_fx() == 0 and not is_instance_valid(s.whirl_fx))
	expect("the cancelled cast spent nothing", not powers.reload_remaining.has("whirling_strike"))

	powers.activate("whirling_strike", player.global_position)
	s.tick_busy(0.1)
	await get_tree().process_frame
	player.knockdown.begin()
	await get_tree().process_frame
	expect("a knockdown frees the effect", _count_fx() == 0)
	player.knockdown.phase = Knockdown.Phase.NONE
	player.stun_time = 0.0

	powers.reset()
	s.reset()
	powers.activate("whirling_strike", player.global_position)
	s.tick_busy(0.1)
	player.dead = true
	await get_tree().process_frame
	await get_tree().process_frame
	expect("death frees the effect", _count_fx() == 0)
	player.dead = false
	s.reset()

	powers.activate("whirling_strike", player.global_position)
	s.tick_busy(0.1)
	var first: WhirlingStrikeFx = s.whirl_fx
	s.cancel_action()
	powers.reset()
	powers.activate("whirling_strike", player.global_position)
	await get_tree().process_frame
	expect("recasting right after a cancel leaves a single effect, and not the old one", _count_fx() == 1 and s.whirl_fx != first)
	s.cancel_action()
	await get_tree().process_frame

	# --- A two-handed weapon turns with both hands, on the same timings -------------------------------------------------------------------
	var saved_weapon: Variant = player.stats.equipment.get(Items.Slot.WEAPON)
	player.stats.wear(Items.Slot.WEAPON, Items.build(ItemDb.get_def("greatsword"), 6, Items.Rarity.NORMAL))
	powers.reset()
	powers.activate("whirling_strike", player.global_position)
	expect("a greatsword uses the two-handed spin on the cast's timings", String(s.busy_def["clip"]) == "atk2_spin"
		and float(s.busy_def["strike"]) == float(cast["strike"]) and is_equal_approx(s.busy_time, float(cast["time"])))
	expect("and the effect marks the same radius", _count_fx() == 1 and is_equal_approx(s.whirl_fx.radius, radius))
	s.cancel_action()
	await get_tree().process_frame
	expect("cancelling the two-handed spin leaves nothing", _count_fx() == 0)
	if saved_weapon != null:
		player.stats.wear(Items.Slot.WEAPON, saved_weapon)

	# --- Hits spawn grit without errors; the effect never changes the power's numbers -----------------------------------------------------
	var lights_before: int = get_tree().get_nodes_in_group("flash_light").size()
	WhirlingStrikeFx.hit(player, near, player.global_position)
	WhirlingStrikeFx.hit(player, null, player.global_position)
	expect("a hit spawns its flash (bounded by the shared light cap)", get_tree().get_nodes_in_group("flash_light").size() >= lights_before)
	near.queue_free()
	player.dead = false
	s.reset()
	powers.reset()

## A short visible playtest: the hero spins into a pack, once with the one-handed sword and shield and once with a greatsword, then
## again with nobody in reach. Frames go to .dev_output/ws_frames (1080p on the second monitor):
##   Godot --path . --screen 1 res://game/main.tscn -- --whirlingcapture [--far] [--crypt --atmosphere]
func _whirling_capture() -> void:
	TownState.persist = false
	TownState.reset()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	for item in Items.starting_gear(): player.stats.equip(item, false)
	TownState.passive_ranks = {"critical_strike": 8, "fortitude": 8, "overbear": 1}
	player.stats.refresh()
	var lane: Vector3 = player.global_position if game.location != null else await _own_lane(14.0, 14.0)   # `--crypt`: on the real road, where it starts
	player.global_position = lane
	player.reset_physics_interpolation()
	rig.target = player
	rig.global_position = player.global_position
	rig.set_zoom_now(0.42 if not OS.get_cmdline_user_args().has("--far") else 0.8)
	var out := ProjectSettings.globalize_path("res://.dev_output/ws_frames")
	DirAccess.make_dir_recursive_absolute(out)
	var pack: Array[Enemy] = []
	var radius: float = player.powers.value("whirling_strike", "radius")
	for i in 9:
		var a: float = TAU * float(i) / 9.0 + 0.3
		var dist: float = radius * (0.55 if i % 3 != 2 else 1.35)   # most inside the reach, some outside it
		var foe := _spawn_enemy(player.global_position + Vector3(sin(a), 0.0, cos(a)) * dist)
		foe.set_physics_process(false)
		foe.aggro_range = 0.0
		foe.max_health = 100000.0
		foe.health = foe.max_health
		pack.append(foe)
	print("WS_CAPTURE radius=", radius, " pack=", pack.size())
	var greatsword: Variant = Items.build(ItemDb.get_def("greatsword"), 6, Items.Rarity.NORMAL)
	var one_hand: Variant = player.stats.equipment.get(Items.Slot.WEAPON)
	for frame in 520:
		match frame:
			30:
				player.powers.reset()
				print("WS_CAPTURE one-hand cast ", player.powers.activate("whirling_strike", player.global_position))
			230:
				for foe in pack:
					if is_instance_valid(foe):
						foe.stun_time = 0.0
				player.stats.wear(Items.Slot.WEAPON, greatsword)
				player.powers.reset()
				print("WS_CAPTURE two-hand cast ", player.powers.activate("whirling_strike", player.global_position))
			420:
				for foe in pack:
					if is_instance_valid(foe):
						foe.queue_free()
				player.stats.wear(Items.Slot.WEAPON, one_hand)
				player.powers.reset()
				print("WS_CAPTURE empty cast ", player.powers.activate("whirling_strike", player.global_position))
		rig.global_position = player.global_position
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0:
			get_viewport().get_texture().get_image().save_jpg(out.path_join("frame_%04d.jpg" % frame), 0.92)
	print("WS_CAPTURE done fx_left=", player.get_children().filter(func(c: Node) -> bool: return c is WhirlingStrikeFx).size())
	get_tree().quit()
