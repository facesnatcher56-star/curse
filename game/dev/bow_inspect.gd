extends Node
## Bow inspection: the real game with Cutter shooting a stationary zombie, his own AI driving every shot. Each shot is
## photographed from one view (relative to where he faces) at five moments: carrying the bow, early draw, full draw,
## release, and the arrow in flight. Every frame, the bow, the string, the drawn arrow and the quiver are measured against
## his body (capsules round his bones, sized from his skin) and the closest approach per part and moment is printed;
## negative clearance means the part is inside him. Images go to user://bow_inspect/. Run res://game/dev/bow_inspect.tscn.

const OUT := "user://bow_inspect"
const CELL := Vector2i(640, 640)
# view name -> [camera offset in his frame (x right, y up, z forward), look-at height]
const VIEWS := [["front", Vector3(0.7, 1.55, 2.2), 1.3], ["bowside", Vector3(-2.2, 1.5, 0.4), 1.3],
	["right", Vector3(2.2, 1.5, 0.2), 1.3], ["back", Vector3(-0.5, 1.7, -2.2), 1.35], ["top", Vector3(0.3, 3.4, 0.6), 1.1],
	["face", Vector3(-0.55, 1.78, 0.55), 1.66], ["shoulder", Vector3(-0.6, 1.85, -0.75), 1.45],
	["rwrist", Vector3(-0.3, 0.12, 0.12), "RightHand"], ["lwrist", Vector3(-0.3, 0.1, -0.2), "LeftHand"],
	["relbow", Vector3(-0.35, 0.15, -0.2), "RightForeArm"], ["grip", Vector3(-0.25, 0.05, 0.1), "LeftHand"]]
# a view whose third entry is a bone name follows that bone: the camera sits at the offset from it (his frame), looking at it
const BONES := [["Hips", "Spine02"], ["Spine02", "Spine01"], ["Spine01", "Spine"], ["Spine", "neck"], ["neck", "Head"],
	["Head", "head_end"], ["LeftShoulder", "LeftArm"], ["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"],
	["RightShoulder", "RightArm"], ["RightArm", "RightForeArm"], ["RightForeArm", "RightHand"],
	["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"]]
# which bones a part may touch by design: the bow sits in the left hand, the arrow between both hands, the string in the
# right fingers; the forearm next to a hand counts within FOREARM_GRACE of the wrist
const ALLOW := {"bow": ["LeftHand"], "arrow": ["LeftHand", "RightHand"], "string": ["RightHand"], "quiver": [],
	"rhand": ["RightHand", "RightForeArm"], "lhand": ["LeftHand", "LeftForeArm"]}   # the hands against the rest of him   # by name prefix: fingers count as the hand

var game: Node
var archer: ArcherCompanion
var cam: Camera3D
var sk: Skeleton3D
var radius := {}            # bone pair "a>b" -> capsule radius (m) (kept for reference; the measure uses the skin)
var skin_v: PackedVector3Array   # sampled body vertices (bind space)
var skin_n: PackedVector3Array
var skin_b: Array = []           # per vertex: [[skeleton bone, bind index, weight] x up to 4]
var skin_dom: PackedStringArray  # per vertex: its dominant bone's name
var skin_mesh: MeshInstance3D
var frame_n := 0
var worst := {}             # "part|moment" -> [clearance, bone, view]
var view_i := -1
var shots_seen := 0
var caught := {}            # moments photographed for the current shot
var release_t := -1.0
var last_draw := 0.0
var final_pose: Array[Transform3D] = []   # the pose as drawn: after the joint helpers (read when they finish, JointHelpers)

func _capture_final_pose() -> void:
	final_pose.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		final_pose[i] = sk.get_bone_global_pose(i)

func _ready() -> void:
	TownState.persist = false
	DirAccess.make_dir_recursive_absolute(OUT)
	game = load("res://game/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(1.6).timeout
	get_tree().current_scene = game
	for layer in game.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	archer = game.companion
	var hero: Player = game.player
	hero.set_physics_process(false)   # the hero stays put; only Cutter acts
	sk = archer.model.find_children("*", "Skeleton3D", true, false)[0]
	for jh in sk.find_children("*", "JointHelpers", false, false):
		(jh as SkeletonModifier3D).modification_processed.connect(_capture_final_pose)
	_measure_radii()
	_sample_skin()
	var target := _place_target()
	print("BOW INSPECT target at ", target.global_position, " archer at ", archer.global_position)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.make_current()
	get_window().size = CELL
	_next_view()

func _place_target() -> Enemy:
	for nd in get_tree().get_nodes_in_group("enemies"):
		nd.queue_free()
	var best := Vector3.ZERO
	for k in 16:
		var dir := Vector3(sin(TAU * k / 16.0), 0, cos(TAU * k / 16.0))
		var at: Vector3 = archer.global_position + dir * 7.0
		if Nav.sight_clear(archer, archer.global_position, at + Vector3.UP * 1.1, null):
			best = at
			break
	var e: Enemy = game.director.spawn_enemy(best, "zombie", 1.0)
	e.set_physics_process(false)
	e.max_health = 99999.0
	e.health = e.max_health
	e.target = game.player
	e.wake()
	return e

func _measure_radii() -> void:
	var pts := {}
	for mi in sk.find_children("*", "MeshInstance3D", false, false):
		var m := mi as MeshInstance3D
		if not String(m.name).begins_with("body_skin") or m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty(): continue
			var per := bones.size() / verts.size()
			for v in range(0, verts.size(), 2):
				var best := 0
				for j in per:
					if weights[v * per + j] > weights[v * per + best]: best = j
				var bind := bones[v * per + best]
				var bname := m.skin.get_bind_name(bind)
				var p: Vector3 = sk.get_bone_global_rest(sk.find_bone(bname)) * (m.skin.get_bind_pose(bind) * verts[v])
				if not pts.has(bname): pts[bname] = []
				pts[bname].append(p)
	for pair in BONES:
		var a: Vector3 = sk.get_bone_global_rest(sk.find_bone(pair[0])).origin
		var b: Vector3 = sk.get_bone_global_rest(sk.find_bone(pair[1])).origin
		var d: Array[float] = []
		for p in pts.get(pair[0], []):
			d.append((Geometry3D.get_closest_point_to_segment(p, a, b) - p).length())
		d.sort()
		var r: float = (d[int(d.size() * 0.6)] if d.size() > 10 else 6.0)
		radius[pair[0] + ">" + pair[1]] = r * sk.global_transform.basis.get_scale().x   # skeleton units -> metres
	print("BOW INSPECT radii (cm): ", radius.keys().map(func(k): return "%s %.1f" % [k, radius[k] * 100.0]))

## Every 3rd vertex of his body mesh, with its skin binds, so it can be skinned on the CPU like the GPU does.
func _sample_skin() -> void:
	for mi in sk.find_children("*", "MeshInstance3D", false, false):
		if String(mi.name).begins_with("body_skin"):
			skin_mesh = mi
	var m := skin_mesh
	for s in m.mesh.get_surface_count():
		var arr := m.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for v in range(0, verts.size(), 3):
			var binds := []
			var best := 0
			for j in per:
				var w: float = weights[v * per + j]
				if w <= 0.001: continue
				var bind: int = bones[v * per + j]
				binds.append([sk.find_bone(m.skin.get_bind_name(bind)), bind, w])
				if w > weights[v * per + best]: best = j
			skin_v.append(verts[v]); skin_n.append(norms[v]); skin_b.append(binds)
			skin_dom.append(m.skin.get_bind_name(bones[v * per + best]))
	print("BOW INSPECT skin samples ", skin_v.size())

## The body's surface now, as a 3 cm hash grid of [position, normal, dominant bone].
func _skinned_grid() -> Dictionary:
	var grid := {}
	var to_world: Transform3D = sk.global_transform
	var mats := {}
	for i in skin_v.size():
		var pos := Vector3.ZERO; var nrm := Vector3.ZERO
		for b in skin_b[i]:
			var key: int = b[1]
			if not mats.has(key):
				var pose: Transform3D = final_pose[b[0]] if final_pose.size() > b[0] else sk.get_bone_global_pose(b[0])
				mats[key] = pose * skin_mesh.skin.get_bind_pose(b[1])
			var t: Transform3D = mats[key]
			pos += (t * skin_v[i]) * float(b[2]); nrm += (t.basis * skin_n[i]) * float(b[2])
		var wp: Vector3 = to_world * pos
		var cell := Vector3i((wp / 0.03).floor())
		if not grid.has(cell): grid[cell] = []
		grid[cell].append([wp, (to_world.basis * nrm).normalized(), skin_dom[i]])
	return grid

## Signed clearance of `points` from the skin: the nearest body point within 6 cm, its normal giving the side (negative =
## inside him). Body points whose bone the part may touch by design are skipped. [clearance m, bone].
func _skin_clearance(grid: Dictionary, points: Array, part: String) -> Array:
	var best := [99.0, ""]
	var hand_part: bool = part.ends_with("hand")
	for item in points:
		var p: Vector3 = item[0] if item is Array else item   # a hand point carries its own bone: [position, normal, bone]
		var own: String = String(item[2]) + ">" if item is Array else ""
		var c0 := Vector3i((p / 0.03).floor())
		var near: Array = []; var near_d := 99.0
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for dz in range(-2, 3):
					for e in grid.get(c0 + Vector3i(dx, dy, dz), []):
						var d: float = ((e[0] as Vector3) - p).length()
						# a hand is measured against the rest of him (its own skin is skipped); a prop point nearest to a part it may
						# touch is contact by design and is not measured
						if d < near_d and not (hand_part and _allowed(part, String(e[2]))):
							near_d = d; near = e
		if near.is_empty() or (not hand_part and _allowed(part, String(near[2]))):
			continue
		if hand_part and near_d > 0.05:
			continue   # beyond 5 cm the nearest normal no longer tells inside from outside
		var signed: float = ((p as Vector3) - (near[0] as Vector3)).dot(near[1])
		var c: float = near_d if signed >= 0.0 else -near_d
		if c < best[0]:
			var b := archer.visual.global_basis.orthonormalized()
			var d := p - archer.global_position
			best = [c, own + String(near[2]) + " at %s" % Vector3(snappedf(d.dot(b.x), 0.01), snappedf(d.y, 0.01), snappedf(d.dot(b.z), 0.01))]
	return best

func _allowed(part: String, bone: String) -> bool:
	for a in ALLOW[part]:
		if bone.begins_with(a):
			return true
	return false

func _bone_pos(name: String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(name)).origin

## The closest any of `points` comes to his body, outside the bones the part may touch: [clearance m, bone].
func _clearance(points: Array, part: String) -> Array:
	var best := [99.0, ""]
	for pair in BONES:
		if pair[0] in ALLOW[part] or pair[1] in ALLOW[part] and part != "bow":
			continue
		var a := _bone_pos(pair[0]); var b := _bone_pos(pair[1])
		var r: float = radius[pair[0] + ">" + pair[1]]
		for p in points:
			var c: float = ((Geometry3D.get_closest_point_to_segment(p, a, b)) - p).length() - r
			if c < best[0]:
				best = [c, pair[0] + ">" + pair[1]]
	return best

func _mesh_points(holder: Node3D, step: int) -> Array:
	var out := []
	if holder == null or not is_instance_valid(holder) or not holder.is_visible_in_tree():
		return out
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var verts: PackedVector3Array = m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for s in range(1, m.mesh.get_surface_count()):
			verts.append_array(m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
		for i in range(0, verts.size(), step):
			out.append(m.global_transform * verts[i])
	return out

func _cord_points(cord: MeshInstance3D) -> Array:
	if cord == null or not cord.visible:
		return []
	var out := []
	for i in 9:
		out.append(cord.global_transform * Vector3(0, -0.5 + i / 8.0, 0))
	return out

func _moment() -> String:
	var bow := archer.bow
	if bow == null:
		return ""
	if bow._release > 0.0:
		return "release"
	if bow._draw > 0.01:
		return "draw"
	return "hold"

func _physics_process(_delta: float) -> void:
	if archer == null or archer.bow == null or sk == null:
		return
	var bow := archer.bow
	frame_n += 1
	if frame_n % 4 != 0:
		return
	var moment := _moment()
	var parts := {"bow": _mesh_points(bow._bow_holder, 7), "arrow": _mesh_points(bow._draw_arrow, 4),
		"string": _cord_points(bow._string_upper) + _cord_points(bow._string_lower), "quiver": _mesh_points(bow._quiver, 10)}
	var grid := _skinned_grid()
	var hands := {"rhand": [], "lhand": []}
	for cell in grid:
		for e in grid[cell]:
			var bone := String(e[2])
			if bone.begins_with("RightHand"): hands["rhand"].append(e)
			elif bone.begins_with("LeftHand"): hands["lhand"].append(e)
	parts.merge(hands)
	for part in parts:
		if (parts[part] as Array).is_empty():
			continue
		var c := _skin_clearance(grid, parts[part], part)
		var key: String = part + "|" + moment
		if not worst.has(key) or c[0] < worst[key][0]:
			worst[key] = [c[0], c[1], VIEWS[maxi(view_i, 0)][0], snappedf(bow._draw, 0.01), snappedf(bow._release, 0.01)]

func _process(_delta: float) -> void:
	if archer == null or cam == null or archer.bow == null:
		return
	var bow := archer.bow
	_aim_camera()
	var draw: float = bow._draw
	if not caught.has("raise") and draw > 0.08:
		_snap("raise")
	if not caught.has("draw_early") and draw > 0.3:
		_snap("draw_early")
	if not caught.has("draw_full") and draw > 0.8:
		_snap("draw_full")
	if not caught.has("release") and bow._release > 0.0:
		_snap("release"); release_t = Time.get_ticks_msec() / 1000.0
	if caught.has("flight") and not caught.has("lower") and bow._release > 0.0 and bow._release < 0.18:
		_snap("lower")
	if release_t > 0.0 and not caught.has("flight") and Time.get_ticks_msec() / 1000.0 - release_t > 0.1:
		_snap("flight")
	# the carry, once the shot has settled (the recovery), then the next view
	if caught.has("flight") and not caught.has("hold") and draw <= 0.01 and bow._release <= 0.0:
		_snap("hold")
	elif caught.has("hold"):
		_next_view()
	last_draw = draw

func _aim_camera() -> void:
	var v: Array = VIEWS[maxi(view_i, 0)]
	var basis: Basis = archer.visual.global_basis.orthonormalized()
	var at: Vector3
	var pos: Vector3
	if v[2] is String:
		at = _bone_pos(String(v[2]))
		pos = at + basis.x * (v[1] as Vector3).x + Vector3.UP * (v[1] as Vector3).y + basis.z * (v[1] as Vector3).z
	else:
		at = archer.global_position + Vector3.UP * float(v[2])
		pos = archer.global_position + basis.x * (v[1] as Vector3).x + Vector3.UP * (v[1] as Vector3).y + basis.z * (v[1] as Vector3).z
	cam.look_at_from_position(pos, at)
	if caught.has("release") and not caught.has("flight"):
		cam.fov = 55.0   # wider for the arrow leaving
	else:
		cam.fov = 40.0

func _snap(moment: String) -> void:
	caught[moment] = true
	if moment == "draw_full":
		_probe()
	if moment == "draw_full":
		var sk3: Skeleton3D = archer.bow._skeleton
		var jh: Node = sk3.find_children("*", "JointHelpers", false, false)[0] if not sk3.find_children("*", "JointHelpers", false, false).is_empty() else null
		if jh:
			await (jh as SkeletonModifier3D).modification_processed
		var angs := []
		for n in ["LeftForeArmTwist", "RightForeArmTwist", "LeftArmTwist", "RightArmTwist", "LeftShoulderHelp", "RightShoulderHelp", "LeftElbowHelp", "RightElbowHelp", "NeckHelp"]:
			var i := sk3.find_bone(n)
			if i >= 0:
				var d: Quaternion = sk3.get_bone_rest(i).basis.get_rotation_quaternion().inverse() * sk3.get_bone_pose_rotation(i)
				angs.append("%s %.0f" % [n, rad_to_deg(d.get_angle())])
		print("HELPERS ", ", ".join(angs))
	if moment in ["draw_early", "draw_full"] and archer.bow.clip_mode:
		var bow := archer.bow
		var sk2: Skeleton3D = bow._skeleton
		var nock: Vector3 = sk2.to_global((sk2.get_bone_global_pose(sk2.find_bone("RightHandIndex3")).origin + sk2.get_bone_global_pose(sk2.find_bone("RightHandMiddle3")).origin) * 0.5)
		print("CLIPPROBE %s draw %.2f holder %s scale %.3f rest %s nock %s arrow_vis %s arrow_pos %s fistL %s" % [moment, bow._draw,
			bow._bow_holder.global_position, bow._bow_holder.global_basis.get_scale().x, bow._bow_holder.to_global(BowAttack.CLIP_REST),
			nock, bow._draw_arrow.visible, bow._draw_arrow.global_position, bow._fist_world("Left")])
	var path := "%s/%s_%s.png" % [OUT, VIEWS[view_i][0], moment]   # named now: the view may change before the frame is drawn
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _next_view() -> void:
	view_i += 1
	caught = {}
	release_t = -1.0
	if view_i >= VIEWS.size():
		_report()
		get_tree().quit()

func _report() -> void:
	print("BOW INSPECT clearances (cm; negative = inside him), worst per part and moment:")
	var keys := worst.keys()
	keys.sort()
	for k in keys:
		var w: Array = worst[k]
		print("  %-16s %6.1f cm  near %-44s view %s draw %.2f release left %.2f" % [k, w[0] * 100.0, w[1], w[2], w[3], w[4]])
	print("BOW INSPECT DONE -> ", ProjectSettings.globalize_path(OUT))

## The draw's geometry at full draw, in his frame: where the target, the fists, the anchor and the face point (degrees off the target line).
func _probe() -> void:
	var bow := archer.bow
	var face: Vector3 = archer.visual.global_basis.z
	var to_target: Vector3 = bow._aim_point - archer.global_position
	var head: Vector3 = bow._bone_world("Head")
	var front: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("headfront")).origin) - head
	var lf: Vector3 = bow._fist_world("Left")
	var rf: Vector3 = bow._fist_world("Right")
	var ang := func(v: Vector3) -> float: return rad_to_deg(Vector2(face.x, face.z).angle_to(Vector2(v.x, v.z)))
	var local := func(v: Vector3) -> Vector3:
		var b := archer.visual.global_basis.orthonormalized()
		var d := v - archer.global_position
		return Vector3(snappedf(d.dot(b.x), 0.01), snappedf(d.y, 0.01), snappedf(d.dot(b.z), 0.01))
	print("PROBE face->target %.0f  head front %.0f  left fist %s  right fist %s  head %s  shoulderL %s  shoulderR %s  arrow dir %.0f" % [
		ang.call(to_target), ang.call(front), local.call(lf), local.call(rf), local.call(head), local.call(bow._bone_world("LeftArm")),
		local.call(bow._bone_world("RightArm")), ang.call(lf - rf)])
