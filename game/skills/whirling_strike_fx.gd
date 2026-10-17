class_name WhirlingStrikeFx
extends Node3D
## Whirling Strike's presentation: a pale arc swept along the ground by the blade at exactly the power's radius, air streaks that follow
## the turn, a faint ring marking the reach for the whole cast, a flat shock ring and radial streaks plus dust at the strike frame, and a
## small grit burst on every enemy hit. Presentation only: it reads the hero's cast and never feeds anything back into combat.
## It lives while the cast does; a cast cut short (dodge, move, stun, knockdown, death) frees it at once (SkillController.cancel_action,
## reset), and it frees itself if the hero stops casting without either being called.

## Where the body turns in the clip (tools/author_attack_anims.gd SPIN_FROM / SPIN_TO, clip seconds): the blade ribbon and the air
## streaks run only inside that window.
const SPIN_FROM := 0.4
const SPIN_TO := 1.15
const GROUND_Y := 0.07
const ARC_AGE := 0.2            # seconds a swept piece of the ground arc lasts
const ARC_PEAK := 0.22
const STREAK_AGE := 0.2
const BLADE_AGE := 0.16
const BLADE_PEAK := 0.42
const FADE := 0.25              # once the spin is over (or the cast ends): the light goes out in the first ~0.1 s, the metal dissolves by 0.25 s
const DUST := WarriorPalette.DUST
const STEEL := WarriorPalette.HOT_STEEL
const RADIAL_STREAKS := 10
## Meshy textures (tools/meshy_whirling_fx.py): the war sigil, whose outer ring touches SIGIL_FILL of the image, and the dust-and-wind
## vortex, whose swirl fills VORTEX_FILL (x, y) of its 16:9 image (stretched so that it is round on the ground).
## The sigil's albedo is graded dark with a dark core; its emission holds only the bright leading edges and the ember runes
## (tools/process_whirling_textures.py); the vortex has its middle faded out so the hero and the weapon stay readable.
const SIGIL: Texture2D = preload("res://assets/fx/whirling/ground_sigil_albedo.png")
const SIGIL_GLOW: Texture2D = preload("res://assets/fx/whirling/ground_sigil_emission.png")           # crimson runes and hot-steel leading edges
const SIGIL_MOLTEN: Texture2D = preload("res://assets/fx/whirling/ground_sigil_molten.png")        # the same runes, molten orange: faded in as the rage builds
const VORTEX: Texture2D = preload("res://assets/fx/whirling/crescent_wind_hollow.png")
const SIGIL_FILL := 0.94
const VORTEX_FILL := Vector2(0.78, 0.73)

var player: Player
var radius: float = 3.0
var spinning: bool = false
var struck: bool = false
var finished: bool = false
var _samples: Array = []         # [direction (flat, unit), age, blade tip, blade root, jag] (tip and root relative to the hero)
var _arc: MeshInstance3D
var _blade: MeshInstance3D
var _radial: MeshInstance3D
var _radial_t: float = -1.0
var _dust_t: float = 0.0
var _fade: float = 1.0
var _sigil: Decal
var _ghost: Decal                   # a short afterimage of the blades' lit edges, lagging the turn a little
var _shattered: bool = false
var _frag_t: float = 0.0
var _molten: Decal                  # the runes in molten orange over the crimson ones
var rage: float = 0.0               # 0 dull crimson .. 1 molten: builds with the wind-up and the speed of the spin, never falls back in the cast
var _omega: float = 0.0
var _art_last: float = 0.0
var _overlay: StandardMaterial3D    # blood-red glow over the real weapon's own metal
var _overlaid: Array[MeshInstance3D] = []
var _vortex: Array[MeshInstance3D] = []
var _vortex_alpha: float = 0.0
var body_yaw: float = 0.0           # how far the hero's hips have turned since the cast began, radians, unwrapped (+ is toward his left)
var art_yaw: float = 0.0            # the turn the ground art shows: the hips' turn counted only from the bottom of the wind-up coil, so the
									# blades hold still while the body coils the other way and start with the counter-clockwise spin
var _yaw_floor: float = 0.0
var _art_frozen: bool = false      # set when the spin is over: the blades stop with the turn and never keep rotating while the body settles
var _hips_bone: int = -1
var _skeleton: Skeleton3D
var _yaw_last: float = 0.0
var _yaw_history: Array = []        # [time, body_yaw], to give the second vortex layer a short lag
var last_contact: Dictionary = {}   # the latest spark: its direction, the blade tip's own motion then, where it was struck
var _swept: Dictionary = {}         # enemy instance id -> true once the blade has swept past it (a contact spark, once)
var _tip_dir_last: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _since_strike: float = 0.0
var _ember_t: float = 0.0
var _ember_shed_t: float = 0.0
var _edge: MeshInstance3D           # the real weapon's sharpened edge (a bright line along the blade)
var weapon_power: float = 0.0

## Starts the effect for a hero's Whirling Strike cast. `reach` is the damage radius (PowerController reads it from the power's data).
static func start(from: Player, reach: float) -> WhirlingStrikeFx:
	var fx := WhirlingStrikeFx.new()
	fx.name = "WhirlingStrikeFx"
	from.add_child(fx)
	fx.setup(from, reach)
	return fx

func setup(from: Player, reach: float) -> void:
	player = from
	radius = reach
	top_level = true
	global_transform = Transform3D(Basis.IDENTITY, Vector3(from.global_position.x, 0.0, from.global_position.z))
	_arc = _flat_mesh(0.0)
	_blade = _flat_mesh(0.0)
	_blade.position = Vector3.ZERO
	(_blade.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_build_sigil()
	_build_vortex()
	_build_weapon_glow()
	_radial = _flat_mesh(0.0)
	_radial.mesh = _radial_mesh()
	_radial.visible = false

## The Meshy war sigil projected onto the ground (a Decal, so it lies on uneven floor and steps), its outer ring exactly on the damage
## radius. It opens as the power gathers.
func _build_sigil() -> void:
	_sigil = Decal.new()
	var size: float = 2.0 * radius / SIGIL_FILL
	_sigil.size = Vector3(size, 0.3, size)
	_sigil.texture_albedo = SIGIL
	_sigil.texture_emission = SIGIL_GLOW
	_sigil.emission_energy = 0.0
	_sigil.modulate = Color(1, 1, 1, 0)
	_sigil.upper_fade = 0.2
	_sigil.lower_fade = 0.2
	add_child(_sigil)
	_sigil.position = Vector3(0, 0.1, 0)
	_molten = Decal.new()
	_molten.size = _sigil.size
	_molten.texture_emission = SIGIL_MOLTEN
	_molten.emission_energy = 0.0
	_molten.modulate = Color(1, 1, 1, 0)
	_molten.upper_fade = 0.2
	_molten.lower_fade = 0.2
	add_child(_molten)
	_molten.position = _sigil.position
	_ghost = Decal.new()
	_ghost.size = _sigil.size
	_ghost.texture_emission = SIGIL_GLOW
	_ghost.emission_energy = 0.0
	_ghost.modulate = Color(1, 1, 1, 0)
	_ghost.upper_fade = 0.2
	_ghost.lower_fade = 0.2
	add_child(_ghost)
	_ghost.position = _sigil.position

## The held weapon, empowered: a thin silver-white edge along its blade with a restrained orange glow toward the hilt, and narrow
## directional glints at the tip (no soft blobs), so the real weapon stays readable through the whole spin. All of it follows the weapon's
## own nodes.
func _build_weapon_glow() -> void:
	_edge = MeshInstance3D.new()
	_edge.mesh = ImmediateMesh.new()
	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.vertex_color_use_as_albedo = true
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge_mat.no_depth_test = true
	_edge.material_override = edge_mat
	_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_edge)

## One camera-facing sliver from `a` to `b`, `width` across at `a` and `width_end` at `b`, colours at each end.
func _sliver(im: ImmediateMesh, a: Vector3, b: Vector3, side: Vector3, width: float, width_end: float, color_a: Color, color_b: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	im.surface_set_color(color_a)
	im.surface_add_vertex(a + side * width)
	im.surface_set_color(color_a)
	im.surface_add_vertex(a - side * width)
	im.surface_set_color(color_b)
	im.surface_add_vertex(b + side * width_end)
	im.surface_set_color(color_b)
	im.surface_add_vertex(b - side * width_end)
	im.surface_end()

## How empowered the weapon looks: it kindles through the wind-up, burns at full through the spin and the strike, and goes out first when
## the cast ends (`glow_k`).
func _update_weapon(gather: float, flare: float, glow_k: float) -> void:
	var power: float = 0.3 + 0.5 * gather * gather
	if spinning or (struck and not finished):
		power = 1.0
	power = maxf(power, flare) * glow_k
	weapon_power = power
	var tip: Node3D = player.model.weapon_tip if player.model != null else null
	var base: Node3D = player.model.weapon if player.model != null else null   # the pommel: the whole sword
	var im := _edge.mesh as ImmediateMesh
	im.clear_surfaces()
	if tip == null or base == null or not tip.is_inside_tree() or not tip.is_visible_in_tree() or power <= 0.01:
		return
	var a: Vector3 = base.global_position - global_position   # the mesh is drawn in this node's own space
	var b: Vector3 = tip.global_position - global_position
	var axis: Vector3 = (b - a).normalized()
	var camera: Camera3D = get_viewport().get_camera_3d()
	var view: Vector3 = (camera.global_position - global_position - (a + b) * 0.5).normalized() if camera != null else Vector3.UP
	var side: Vector3 = axis.cross(view)
	side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
	var heat: Color = WarriorPalette.rage(rage)           # crimson to molten as the rage builds
	var blood := Color(WarriorPalette.CRIMSON.r, WarriorPalette.CRIMSON.g, WarriorPalette.CRIMSON.b, 0.5 * power)
	var edge := Color(1.0, 0.9, 0.72, 1.0 * power)        # orange-white along the cutting edge
	var mid: Vector3 = a.lerp(b, 0.4)
	_sliver(im, a, b, side, 0.045, 0.03, blood, blood)   # a blood-red glow along the whole blade
	_sliver(im, a, mid, side, 0.03, 0.02, Color(heat.r, heat.g, heat.b, 0.6 * power), Color(1.0, 0.7, 0.4, 0.7 * power))
	_sliver(im, mid, b, side, 0.02, 0.012, Color(1.0, 0.7, 0.4, 0.7 * power), edge)
	_sliver(im, a.lerp(b, 0.25), b, side, 0.011, 0.006, Color(1.0, 0.95, 0.85, 0.7 * power), Color(1.0, 0.95, 0.85, 1.0 * power))   # the sharpened edge itself
	for k in 4:   # short heat marks down the blade, as the engravings on the ground blades
		var at: Vector3 = a.lerp(b, 0.3 + 0.17 * k)
		_sliver(im, at - axis * 0.03, at + axis * 0.03, side, 0.016, 0.016, Color(heat.r, heat.g, heat.b, 0.0), Color(heat.r, heat.g, heat.b, 0.85 * power))
	# Narrow glints at the tip: a streak along the blade and a short cross-streak, flickering, never a soft blob.
	var flick: float = 0.55 + 0.45 * sin(_elapsed * 47.0)
	var glint := Color(1.0, 0.9, 0.72, 0.9 * power * flick)
	_sliver(im, b - axis * 0.05, b + axis * (0.22 + 0.2 * power), side, 0.012, 0.0, glint, Color(glint.r, glint.g, glint.b, 0.0))
	var cross: Vector3 = side.cross(view).normalized()
	_sliver(im, b - cross * 0.12, b + cross * 0.12, side, 0.004, 0.004, Color(glint.r, glint.g, glint.b, 0.0), glint)
	_weapon_overlay(power)

## The sword's own dark metal glows blood-red: an additive overlay on its meshes, strongest through the spin. Removed when the effect goes.
func _weapon_overlay(power: float) -> void:
	if _overlaid.is_empty() and player.model.weapon != null:
		_overlay = StandardMaterial3D.new()
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		for node in player.model.weapon.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			mesh.material_overlay = _overlay
			_overlaid.append(mesh)
	if _overlay != null:
		_overlay.albedo_color = Color(0.85, 0.05, 0.04, 0.38 * power)

func _clear_overlay() -> void:
	for mesh in _overlaid:
		if is_instance_valid(mesh) and mesh.material_overlay == _overlay:
			mesh.material_overlay = null
	_overlaid.clear()

func _exit_tree() -> void:
	_clear_overlay()

## Incandescent fragments breaking away from the blades' leading edges through the fastest part of the turn.
func _break_off_fragments() -> void:
	for i in 2:
		var a: float = randf() * TAU
		var r: float = radius * randf_range(0.5, 0.97)
		var at: Vector3 = player.global_position + Vector3(sin(a), 0.12, cos(a)) * r
		var tangent: Vector3 = Vector3(cos(a), 0.0, -sin(a))   # along the turn
		Fx.burst(player, at, tangent + Vector3.UP * 0.4, WarriorPalette.rage(0.6 + 0.4 * rage), 3, 3.0, 0.018, true)

## The spin is over: the ring breaks up into glowing pieces that cool as they fall.
func _shatter() -> void:
	_shattered = true
	for i in 14:
		var a: float = TAU * (float(i) + randf()) / 14.0
		var r: float = radius * randf_range(0.45, 0.97)
		var at: Vector3 = player.global_position + Vector3(sin(a), 0.1, cos(a)) * r
		var tangent: Vector3 = Vector3(cos(a), 0.0, -sin(a))
		Fx.burst(player, at, tangent * 0.6 + Vector3(sin(a), 0.5, cos(a)) * 0.6, WarriorPalette.EMBER if i % 2 == 0 else WarriorPalette.CRIMSON, 4, 3.8, 0.02, true)
		if i % 3 == 0:
			Fx.burst(player, at, Vector3(sin(a), 0.3, cos(a)), WarriorPalette.IRON, 4, 2.6, 0.03)   # dark metal shards

## Embers tear off the weapon as it spins: thrown along the blade's own motion and falling.
func _shed_embers() -> void:
	var tip: Node3D = player.model.weapon_tip if player.model != null else null
	if tip == null or _samples.size() < 2:
		return
	var motion: Vector3 = (_samples[0][0] as Vector3) - (_samples[1][0] as Vector3)
	motion = motion.normalized() if motion.length() > 0.001 else Vector3.UP
	Fx.burst(player, tip.global_position, motion + Vector3.UP * 0.35, WarriorPalette.rage(0.5 + 0.5 * rage), 4, 3.4, 0.016, true)

## Two layers of the Meshy dust vortex round the hero (low and at hip height), turning with the body.
func _build_vortex() -> void:
	for i in 2:
		var node := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0 * radius / VORTEX_FILL.x, 2.0 * radius / VORTEX_FILL.y)   # the swirl's ellipse becomes a circle of the reach
		node.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = VORTEX
		mat.albedo_color = Color(1, 1, 1, 0)
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.position = Vector3(0, 0.22 + 0.5 * i, 0)
		node.rotation.x = -PI * 0.5
		_vortex.append(node)

func _flat_mesh(alpha: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1, 1, 1, 1.0 if alpha <= 0.0 else alpha)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.position = Vector3(0, GROUND_Y, 0)
	return node

## Radial streaks from the hero out to the edge of the reach: thin slivers, brighter outward.
func _radial_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RADIAL_STREAKS:
		var a: float = TAU * (float(i) + 0.35 * sin(float(i) * 2.7)) / RADIAL_STREAKS
		var dir := Vector3(sin(a), 0.0, cos(a))
		var side := Vector3(dir.z, 0.0, -dir.x)
		var length: float = 0.75 + 0.25 * fposmod(float(i) * 0.618, 1.0)   # of the radius: some reach it, some fall short
		var from: Vector3 = dir * 0.35
		var to: Vector3 = dir * length
		st.set_color(Color(STEEL.r, STEEL.g, STEEL.b, 0.0))
		st.add_vertex(from + side * 0.02)
		st.set_color(Color(STEEL.r, STEEL.g, STEEL.b, 0.0))
		st.add_vertex(from - side * 0.02)
		st.set_color(Color(STEEL.r, STEEL.g, STEEL.b, 0.7))
		st.add_vertex(to)
	return st.commit()

## Where the cast is in its clip, seconds (the same remap SkillController scrubs the pose by).
func clip_time() -> float:
	var skills: SkillController = player.skills
	var cast: Dictionary = skills.busy_def
	if cast.is_empty() or skills.busy_time <= 0.0:
		return 0.0
	return CharacterModel.remap(clampf(skills.busy_t / skills.busy_time, 0.0, 1.0), SkillController.hit_fraction(cast),
		float(cast["start"]), float(cast["strike"]), float(cast["end"]))

func casting() -> bool:
	return is_instance_valid(player) and not player.dead and player.skills.busy and player.skills.busy_skill == "whirling_strike"

func _process(delta: float) -> void:
	_elapsed += delta
	_track_body(delta)
	if not finished and is_instance_valid(player):
		global_position = Vector3(player.global_position.x, 0.0, player.global_position.z)   # anchored to the hero: it never slides or drifts
	_update_art(delta)
	if finished:
		_fade -= delta / FADE
		_age_samples(delta)
		_draw_arc()
		if _fade <= 0.0:
			queue_free()
		return
	if not casting():
		finish(not struck or not is_instance_valid(player) or player.dead)   # a cast that never struck, or a dead hero's, leaves nothing; a spin that landed fades
		return
	var t: float = clip_time()
	spinning = t >= SPIN_FROM and t <= SPIN_TO
	if t > SPIN_TO:
		_art_frozen = true
	_age_samples(delta)
	if _art_frozen:
		_fade -= delta / FADE   # the spin is over: the light goes out and the blades dissolve, whatever is left of the recovery
	if spinning:
		Fx.shake(player, 0.02)   # the ground trembles under the turn
		_sample_blade(delta)
		_blade_contacts()
		_ember_shed_t -= delta
		if _ember_shed_t <= 0.0:
			_ember_shed_t = 0.035
			_shed_embers()
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.07
			_kick_dust()
	if not struck and player.skills.busy_hit_done:
		_strike()
	_draw_arc()
	_animate_strike(delta)

## Stops the effect. `immediate` frees it now (a cast cut short); otherwise the arcs fade out over FADE seconds.
func finish(immediate: bool) -> void:
	if finished:
		if immediate:
			queue_free()
		return
	finished = true
	spinning = false
	if immediate:
		queue_free()
		return
	if _radial != null:
		_radial.visible = false

## Hot steel at the leading edge, cooling through ember orange and blood crimson to blackened iron.
func _heat(life: float) -> Color:
	if life > 0.6:
		return WarriorPalette.EMBER.lerp(WarriorPalette.HOT_STEEL, (life - 0.6) / 0.4)
	if life > 0.25:
		return WarriorPalette.CRIMSON.lerp(WarriorPalette.EMBER, (life - 0.25) / 0.35)
	return WarriorPalette.BLOOD.lerp(WarriorPalette.CRIMSON, life / 0.25)

func _sample_blade(delta: float) -> void:
	var tip: Node3D = player.model.weapon_tip if player.model != null else null
	var base: Node3D = player.model.weapon_base if player.model != null else null
	if tip == null or base == null or not tip.is_inside_tree():
		return
	var tip_rel: Vector3 = tip.global_position - player.global_position
	var base_rel: Vector3 = base.global_position - player.global_position
	var flat: Vector3 = Vector3(tip_rel.x, 0.0, tip_rel.z)
	if flat.length() < 0.2:
		return
	var dir: Vector3 = flat.normalized()
	# The blade turns up to ~40 degrees a frame at its fastest: fill in the turn since the last sample (oldest piece first) so the arc
	# and the ribbon are round rather than a few long chords.
	if not _samples.is_empty():
		var last: Array = _samples[0]
		var steps: int = clampi(ceili(acos(clampf((last[0] as Vector3).dot(dir), -1.0, 1.0)) / 0.2), 1, 12)
		for k in range(1, steps):
			var u: float = float(k) / steps
			_samples.push_front([(last[0] as Vector3).slerp(dir, u), delta * float(steps - k) / steps,
				(last[2] as Vector3).slerp(tip_rel, u), (last[3] as Vector3).slerp(base_rel, u), randf()])
	_samples.push_front([dir, 0.0, tip_rel, base_rel, randf()])   # the last: a fixed random per sample, so the afterimage is jagged but steady
	if _samples.size() > 60:
		_samples.resize(60)

func _age_samples(delta: float) -> void:
	for s in _samples:
		s[1] += delta
	while not _samples.is_empty() and float(_samples[_samples.size() - 1][1]) > ARC_AGE:
		_samples.pop_back()

## The hips' real turn is the source of truth for everything on the ground: no tween, no independent spin. Read from the skeleton the
## animation is driving, as the yaw of the hips' forward axis, unwrapped so a full turn keeps counting.
func _track_body(delta: float) -> void:
	if not is_instance_valid(player) or player.model == null:
		return
	if _skeleton == null:
		var found: Array[Node] = player.model.find_children("*", "Skeleton3D", true, false)
		if found.is_empty():
			return
		_skeleton = found[0]
		_hips_bone = _skeleton.find_bone("Hips")
		_yaw_last = _hips_yaw()
	var now: float = _hips_yaw()
	body_yaw += wrapf(now - _yaw_last, -PI, PI)
	_yaw_last = now
	_yaw_floor = minf(_yaw_floor, body_yaw)
	if not _art_frozen:
		art_yaw = body_yaw - _yaw_floor
	_yaw_history.push_front([_elapsed, art_yaw])
	while _yaw_history.size() > 2 and _elapsed - float(_yaw_history[_yaw_history.size() - 1][0]) > 0.3:
		_yaw_history.pop_back()

func _hips_yaw() -> float:
	var forward: Vector3 = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_hips_bone)).basis * Vector3.BACK
	return atan2(forward.x, forward.z)

## The ground art's turn `lag` seconds ago.
func _yaw_ago(lag: float) -> float:
	for entry in _yaw_history:
		if _elapsed - float(entry[0]) >= lag:
			return float(entry[1])
	return float(_yaw_history[_yaw_history.size() - 1][1]) if not _yaw_history.is_empty() else 0.0

## The Meshy art follows the cast: the sigil opens outward as the power gathers, flares at the strike and burns off through the recovery;
## the vortex fills in while the body turns and thins out after.
func _update_art(delta: float) -> void:
	var shutting: bool = finished or _art_frozen
	var fade: float = 1.0 if not shutting else clampf(_fade / 0.55, 0.0, 1.0)        # the silhouettes dissolve in the last part of the shutdown
	var glow_k: float = 1.0 if not shutting else clampf((_fade - 0.55) / 0.45, 0.0, 1.0)   # the light goes out first
	var gather: float = 1.0
	var flare: float = 0.0
	if not finished and is_instance_valid(player):
		var cast: Dictionary = player.skills.busy_def
		if not cast.is_empty():
			gather = clampf(clip_time() / maxf(float(cast["strike"]), 0.01), 0.0, 1.0)
		flare = clampf(1.0 - _since_strike / 0.22, 0.0, 1.0) if struck else 0.0
		_since_strike = _since_strike + delta if struck else 0.0
	var hold: float = 1.0 if not struck else clampf(1.0 - maxf(_since_strike - 0.4, 0.0) / 0.5, 0.0, 1.0)
	_sigil.modulate = Color(1, 1, 1, 1.0 * clampf(gather * 2.5, 0.0, 1.0) * hold * fade)
	# While the body winds up the blades power up in place: the runes heat from dull to white-orange and pulse faster as the coil tightens,
	# and embers lift off them. They do not turn until the spin begins (art_yaw).
	var charge: float = gather * gather if not spinning and not struck else 1.0
	var pulse: float = 0.5 + 0.5 * sin(_elapsed * (8.0 + 14.0 * gather))
	_omega = lerpf(_omega, absf(art_yaw - _art_last) / maxf(delta, 0.0001), 0.35)
	_art_last = art_yaw
	if not shutting:
		rage = maxf(rage, 0.55 * pow(gather, 1.5) + 0.45 * clampf(_omega / 22.0, 0.0, 1.0))   # both are the animation: its clip progress and the turn's own speed
		if struck:
			rage = maxf(rage, 0.9)
	var speed: float = clampf(_omega / 22.0, 0.0, 1.0)   # 1 through the fastest part of the turn: the leading edges flare
	var shut_t: float = (1.0 - clampf(_fade, 0.0, 1.0)) * FADE if shutting else 0.0
	# The ending: the engravings flare once as the spin stops, then cool to dark metal within ~0.1 s while the blades fragment and go.
	var end_flare: float = clampf(1.0 - absf(shut_t - 0.035) / 0.035, 0.0, 1.0) if shutting else 0.0
	var cool: float = 1.0 if not shutting else clampf(1.0 - shut_t / 0.1, 0.0, 1.0)
	_sigil.emission_energy = (0.3 + 1.7 * charge + 0.5 * charge * pulse + 2.5 * flare + 2.2 * speed) * glow_k * (1.0 + 2.2 * end_flare)
	_molten.modulate = Color(1, 1, 1, pow(rage, 1.5) * hold * fade * cool)
	_molten.emission_energy = (0.5 + 2.2 * rage + 2.5 * flare) * glow_k * (1.0 + 2.2 * end_flare)
	_ghost.modulate = Color(1, 1, 1, 0.4 * speed * hold * fade)
	_ghost.emission_energy = 1.6 * glow_k
	_ghost.rotation = Vector3(0.0, _yaw_ago(0.05), 0.0)
	_ghost.scale = Vector3.ONE
	if shutting and not _shattered:
		_shatter()
	if spinning and speed > 0.4:
		_frag_t -= delta
		if _frag_t <= 0.0:
			_frag_t = 0.05
			_break_off_fragments()
	_molten.rotation = Vector3(0.0, art_yaw, 0.0)
	_molten.scale = Vector3.ONE * lerpf(0.82, 1.0, clampf(gather * 1.6, 0.0, 1.0))
	if not finished and not spinning and not struck and gather > 0.25:
		_ember_t -= delta
		if _ember_t <= 0.0:
			_ember_t = lerpf(0.16, 0.05, gather)
			var a: float = randf() * TAU
			var at: Vector3 = player.global_position + Vector3(sin(a), 0.1, cos(a)) * radius * randf_range(0.4, 0.95)
			Fx.burst(player, at, Vector3.UP, WarriorPalette.rage(0.4 + gather * 0.6), 4, 1.6, 0.02, true)
	_sigil.rotation = Vector3(0.0, art_yaw, 0.0)
	_sigil.scale = Vector3.ONE * lerpf(0.82, 1.0, clampf(gather * 1.6, 0.0, 1.0))
	if is_instance_valid(player):
		_update_weapon(gather, flare, glow_k)
	_vortex_alpha = move_toward(_vortex_alpha, 0.2 if spinning else 0.0, delta * 8.0)
	for i in _vortex.size():
		_vortex[i].rotation = Vector3(-PI * 0.5, art_yaw if i == 0 else _yaw_ago(0.07), 0.0)   # the second layer trails the body a little
		var tint: Color = Color(0.95, 0.62, 0.5).lerp(Color(1.0, 0.5, 0.28), rage)   # ash and smoke lit from below by the heat
		(_vortex[i].material_override as StandardMaterial3D).albedo_color = Color(tint.r, tint.g, tint.b, _vortex_alpha * fade * (0.9 if i == 0 else 0.55))

## The swept arc: a band at the very edge of the reach (so the sweep is exactly as long as the blow), and two thinner streaks inside it
## that cool faster, all following the blade's direction around the hero.
func _draw_arc() -> void:
	_draw_blade()
	var im := _arc.mesh as ImmediateMesh
	im.clear_surfaces()
	if _samples.size() < 2:
		return
	var bands := [[0.94, 1.0, ARC_AGE, ARC_PEAK], [0.5, 0.54, STREAK_AGE, ARC_PEAK * 0.55], [0.66, 0.7, STREAK_AGE * 1.2, ARC_PEAK * 0.6]]
	for band in bands:
		var inner: float = band[0]
		var outer: float = band[1]
		var limit: float = band[2]
		var live: int = 0
		for s in _samples:
			if float(s[1]) > limit:
				break
			live += 1
		if live < 2:
			continue   # a strip of fewer than two samples has too few vertices to draw
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for s in _samples:
			if float(s[1]) > limit:
				break
			var life: float = clampf(1.0 - float(s[1]) / limit, 0.0, 1.0)
			var jag: float = float(s[4])
			var a: float = pow(life, 1.4) * float(band[3]) * clampf(_fade, 0.0, 1.0) * (1.0 + 0.9 * clampf((life - 0.85) * 6.0, 0.0, 1.0))
			a *= 0.6 + 0.8 * fposmod(jag * 7.3, 1.0)   # ragged: some pieces of the afterimage burn brighter than their neighbours
			var dir: Vector3 = s[0]
			var col: Color = _heat(life * 0.6)   # ember orange at the head, cooling to crimson and iron behind (hot steel stays on the weapon, not on the ground)
			var reach: float = 1.0 + (jag - 0.5) * 0.12
			im.surface_set_color(Color(col.r, col.g, col.b, a))
			im.surface_add_vertex(dir * radius * outer * reach)
			im.surface_set_color(Color(col.r, col.g, col.b, a * 0.1))
			im.surface_add_vertex(dir * radius * inner)
		im.surface_end()

## The blade's own ribbon: the swept strip from the tip toward the root, steel at the edge and cooling to dust, additive so it reads as a
## streak of light on metal rather than a solid sheet.
func _draw_blade() -> void:
	var im := _blade.mesh as ImmediateMesh
	im.clear_surfaces()
	if _samples.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in _samples:
		var life: float = clampf(1.0 - float(s[1]) / BLADE_AGE, 0.0, 1.0)
		var a: float = pow(life, 1.3) * BLADE_PEAK * clampf(_fade, 0.0, 1.0)
		var col: Color = _heat(life)   # a short, jagged afterimage of the real sword: hot steel at the edge, crimson as it cools
		a *= 0.55 + 0.9 * fposmod(float(s[4]) * 5.1, 1.0)
		var tip: Vector3 = s[2]
		var root: Vector3 = (s[3] as Vector3).lerp(tip, 0.72)
		var kick: Vector3 = Vector3(float(s[4]) - 0.5, (fposmod(float(s[4]) * 3.7, 1.0) - 0.5) * 0.5, fposmod(float(s[4]) * 9.1, 1.0) - 0.5) * 0.16
		tip += kick
		im.surface_set_color(Color(col.r, col.g, col.b, a))
		im.surface_add_vertex(tip)
		im.surface_set_color(Color(col.r, col.g, col.b, 0.0))
		im.surface_add_vertex(root)
	im.surface_end()
	# A jagged ember trail on the real sword's tip: a few bright zig-zag segments through its latest positions.
	var live: Array = []
	for s in _samples:
		if float(s[1]) > BLADE_AGE * 0.7:
			break
		live.append(s)
	if live.size() >= 3:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for k in live.size():
			var s: Array = live[k]
			var life2: float = clampf(1.0 - float(s[1]) / (BLADE_AGE * 0.7), 0.0, 1.0)
			var zig: Vector3 = Vector3(fposmod(float(s[4]) * 13.7, 1.0) - 0.5, fposmod(float(s[4]) * 6.3, 1.0) - 0.5, fposmod(float(s[4]) * 2.9, 1.0) - 0.5) * 0.28
			var at: Vector3 = (s[2] as Vector3) + zig
			var col2: Color = WarriorPalette.EMBER.lerp(WarriorPalette.HOT_STEEL, life2 * life2)
			im.surface_set_color(Color(col2.r, col2.g, col2.b, life2 * 0.85 * clampf(_fade, 0.0, 1.0)))
			im.surface_add_vertex(at)
			im.surface_set_color(Color(col2.r, col2.g, col2.b, 0.0))
			im.surface_add_vertex(at + Vector3(0.0, 0.05 + 0.04 * float(k % 2), 0.0))
		im.surface_end()

## Visual only: a small spark where the blade passes an enemy inside the reach, once each as it sweeps by. Damage still lands at the strike
## frame, as PowerController decides; this changes nothing about it.
func _blade_contacts() -> void:
	if _samples.is_empty():
		return
	var now: Vector3 = _samples[0][0]
	var prev: Vector3 = _tip_dir_last if _tip_dir_last != Vector3.ZERO else now
	_tip_dir_last = now
	var swept: float = wrapf(atan2(now.x, now.z) - atan2(prev.x, prev.z), -PI, PI)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead or _swept.has(e.get_instance_id()):
			continue
		var offset: Vector3 = e.global_position - player.global_position
		offset.y = 0.0
		if offset.length() > radius:
			continue
		var from_prev: float = wrapf(atan2(offset.x, offset.z) - atan2(prev.x, prev.z), -PI, PI)
		if (swept >= 0.0 and from_prev >= 0.0 and from_prev <= swept) or (swept < 0.0 and from_prev <= 0.0 and from_prev >= swept):
			_swept[e.get_instance_id()] = true
			var away: Vector3 = offset.normalized() if offset.length() > 0.05 else now
			# The blade travels along the tangent, so the strike throws sparks along it, and the body rocks the way it was cut.
			var tangent: Vector3 = Vector3(away.z, 0.0, -away.x) * signf(swept)   # a point at this bearing travels along (z, -x) when the turn is +yaw
			var cut: Vector3 = (tangent + away * 0.35).normalized()
			var contact: Vector3 = player.global_position + offset.normalized() * minf(offset.length(), radius * 0.9) + Vector3(0, e.body_height * 0.55, 0)
			Fx.burst(player, contact, cut + Vector3.UP * 0.15, WarriorPalette.HOT_STEEL, 4, 5.0, 0.012, true)   # a small mark as the blade passes; the registered hit (hit()) is the strong one
			
			last_contact = {"cut": cut, "motion": Vector3(now.x - prev.x, 0.0, now.z - prev.z), "at": contact}
			if e.model != null:
				e.model.react(cut, BodyRecoil.peak_for(2.1, 1.0, e.knock_resist))   # a visual rock only; the real knock-back is still PowerController's

## A puff of dust kicked out from the planted feet while the body turns.
func _kick_dust() -> void:
	var a: float = randf() * TAU
	var dir := Vector3(sin(a), 0.0, cos(a))
	Fx.burst(player, player.global_position + dir * 0.5 + Vector3(0, 0.08, 0), dir + Vector3.UP * 0.25, DUST, 5, 1.8, 0.05)

## The strike frame: the sigil flares, radial streaks open outward, dust is thrown, the camera nudges.
func _strike() -> void:
	struck = true
	_radial.visible = true
	_radial_t = 0.0
	for i in 6:
		var a: float = TAU * (float(i) + 0.5) / 6.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		Fx.burst(player, player.global_position + dir * 0.9 + Vector3(0, 0.08, 0), dir + Vector3.UP * 0.35, DUST, 14, 4.6, 0.06)
	Fx.burst(player, player.global_position + Vector3(0, 0.5, 0), Vector3.UP, WarriorPalette.EMBER, 28, 6.5, 0.025, true)   # embers, the one warm accent
	Fx.burst(player, player.global_position + Vector3(0, 0.15, 0), Vector3.UP, DUST, 40, 3.2, 0.09)   # the landing throws a column of dust
	Fx.slowmo(player, 0.35, 0.06, 0.25)   # a beat of weight on the landing (only when the owner's slow-motion setting is on)
	Fx.punch(player, 2.6)
	Fx.shake(player, 0.28)

func _animate_strike(delta: float) -> void:
	if _radial_t >= 0.0:
		_radial_t += delta
		var u: float = clampf(_radial_t / 0.28, 0.0, 1.0)
		var s: float = radius * lerpf(0.6, 1.0, 1.0 - pow(1.0 - u, 2.0))
		_radial.scale = Vector3(s, 1.0, s)
		(_radial.material_override as StandardMaterial3D).albedo_color.a = 1.0 - u
		if u >= 1.0:
			_radial.visible = false
			_radial_t = -1.0

## What every enemy the spin hits gets: a short burst of grit thrown outward from its chest and a faint flash.
static func hit(from: Node, enemy: Actor, origin: Vector3) -> void:
	if not is_instance_valid(enemy):
		return
	var away: Vector3 = enemy.global_position - origin
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
	var chest: Vector3 = enemy.global_position + Vector3(0, enemy.body_height * 0.6, 0)
	var cut: Vector3 = (Vector3(away.z, 0.0, -away.x) + away * 0.35).normalized()   # along the blade's path (the spin turns +yaw), thrown a little outward
	Fx.burst(from, chest, cut + Vector3.UP * 0.15, WarriorPalette.HOT_STEEL, 10, 7.0, 0.014, true)   # the strongest sparks: the registered hit, at the enemy
	Fx.burst(from, chest, cut + Vector3.UP * 0.3, WarriorPalette.EMBER, 8, 4.0, 0.018, true)
	Fx.burst(from, chest, cut + Vector3.UP * 0.1, WarriorPalette.BLOOD, 9, 5.0, 0.03)   # dark red, thrown with the cut
	Fx.burst(from, enemy.global_position + Vector3(0, 0.1, 0), away + Vector3.UP * 0.2, DUST, 7, 2.6, 0.05)
	Fx.light_flash(from, chest, Color(1.0, 0.45, 0.2), 0.8, 0.08)
