class_name ChestLook
extends RefCounted
## What each tier of map-mode chest looks like (issue #87). It is the real chest model (assets/models/dungeon/chest) in every tier; what differs
## is its material (the model's own wood texture is kept, only nudged toward the tier's colour) and the trim added to it: wooden is bare wood,
## iron has steel bands and rivets, gilded has gold bands, a rim and a clasp, cursed has purple glowing runes, a ground sigil and rising wisps,
## and the hoard is bigger, banded in gold, with a heap of coin inside. Trim on the lid rides with the lid when it opens.

## tier -> the model's textured materials: tint (and how far), emission and metal.
const BODY := {
	"wooden": {"tint": Color(0.70, 0.48, 0.26), "amount": 0.12, "emission": Color(0.70, 0.48, 0.26), "energy": 0.3, "metal": 0.0},
	"iron": {"tint": Color(0.42, 0.46, 0.52), "amount": 0.2, "emission": Color(0.5, 0.55, 0.62), "energy": 0.3, "metal": 0.1},
	"gilded": {"tint": Color(0.7, 0.6, 0.4), "amount": 0.1, "emission": Color(0.8, 0.7, 0.55), "energy": 0.25, "metal": 0.15},
	"cursed": {"tint": Color(0.52, 0.3, 0.72), "amount": 0.3, "emission": Color(0.62, 0.28, 0.95), "energy": 0.3, "metal": 0.05},
	"hoard": {"tint": Color(0.8, 0.6, 0.35), "amount": 0.1, "emission": Color(0.8, 0.7, 0.55), "energy": 0.25, "metal": 0.15},
}

static func apply(chest: Chest, guard: String) -> void:
	if not BODY.has(guard):
		return
	var def: Dictionary = BODY[guard]
	for node in chest.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as BaseMaterial3D
			if mat.albedo_texture != null:   # the carved wood and metal; the plain interior keeps its own colour
				copy.metallic = float(def["metal"])
				copy.roughness = 0.78
				copy.albedo_color = Color.WHITE.lerp(def["tint"], float(def["amount"]) * 2.2)
				copy.emission_enabled = true   # the carving lights itself a little, so the dark wood reads at the camera's distance
				copy.emission = def["emission"]
				copy.emission_texture = mat.albedo_texture
				copy.emission_energy_multiplier = float(def["energy"])
			(node as MeshInstance3D).set_surface_override_material(i, copy)
	var body: Node3D = chest.find_child("ChestBody", true, false) as Node3D
	var lid_mesh: Node3D = chest.find_child("ChestLidMesh", true, false) as Node3D
	if body == null or lid_mesh == null:
		return
	var b: AABB = _local_aabb(chest, body)
	var l: AABB = _local_aabb(chest, lid_mesh)
	match guard:
		"iron": _iron(chest, b, l)
		"gilded": _gilded(chest, b, l)
		"cursed": _cursed(chest, b, l)
		"hoard": _hoard(chest, b, l)
	if guard in ["cursed", "hoard"]:
		var light := OmniLight3D.new()
		light.light_color = MapDrops.guard_color(guard)
		light.light_energy = 0.4 if guard == "hoard" else 0.9
		light.position = Vector3(0.0, 1.8, 0.0)
		light.omni_range = 3.5
		chest.add_child(light)

## The node's bounds in the chest's own (unscaled) space.
static func _local_aabb(chest: Node3D, node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for child in [node] + node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var to_chest: Transform3D = chest.global_transform.affine_inverse() * mi.global_transform
		var box: AABB = to_chest * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out

static func _metal(colour: Color, metal: float, rough: float, glow: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = metal
	mat.roughness = rough
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = colour
		mat.emission_energy_multiplier = glow
	return mat

## A box `size` (chest space) centred at `centre` (chest space), riding with `on` (the chest or its lid).
static func _box(chest: Node3D, on: Node3D, centre: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	on.add_child(mi)
	mi.global_transform = Transform3D(chest.global_transform.basis, chest.to_global(centre))
	return mi

static func _lid(chest: Chest) -> Node3D:
	return chest._lid if chest._lid != null else chest

## Straps round the chest at fractions of its width (x). They ride with the body: the model's lid is left as modelled.
static func _bands(chest: Chest, b: AABB, l: AABB, fractions: Array, width: float, mat: Material) -> void:
	for f in fractions:
		var x: float = b.position.x + b.size.x * float(f)
		_box(chest, chest, Vector3(x, b.get_center().y, b.get_center().z), Vector3(width, b.size.y + 0.015, b.size.z + 0.03), mat)

static func _rivets(chest: Chest, b: AABB, fractions: Array, mat: Material) -> void:
	for f in fractions:
		var x: float = b.position.x + b.size.x * float(f)
		var front: float = b.end.z + 0.012
		_box(chest, chest, Vector3(x, b.position.y + b.size.y * 0.22, front), Vector3(0.05, 0.05, 0.03), mat)
		_box(chest, chest, Vector3(x, b.position.y + b.size.y * 0.78, front), Vector3(0.05, 0.05, 0.03), mat)

static func _iron(chest: Chest, b: AABB, l: AABB) -> void:
	var steel: StandardMaterial3D = _metal(Color(0.34, 0.37, 0.42), 0.8, 0.38)
	_bands(chest, b, l, [0.16, 0.84], 0.06, steel)
	_rivets(chest, b, [0.16, 0.84], _metal(Color(0.6, 0.62, 0.66), 0.9, 0.3))
	_box(chest, chest, Vector3(b.get_center().x, b.position.y + b.size.y * 0.78, b.end.z + 0.012), Vector3(0.14, 0.17, 0.03), steel)   # the lock plate

static func _gilded(chest: Chest, b: AABB, l: AABB) -> void:
	var gold: StandardMaterial3D = _metal(Color(0.85, 0.62, 0.18), 0.5, 0.35, 0.7)
	_bands(chest, b, l, [0.14, 0.86], 0.045, gold)
	_box(chest, chest, Vector3(b.get_center().x, b.position.y + 0.02, b.get_center().z), Vector3(b.size.x + 0.04, 0.045, b.size.z + 0.04), gold)   # the base rim
	_box(chest, chest, Vector3(b.get_center().x, b.position.y + b.size.y * 0.78, b.end.z + 0.015), Vector3(0.17, 0.2, 0.035), gold)   # the clasp

static func _cursed(chest: Chest, b: AABB, l: AABB) -> void:
	var rune: StandardMaterial3D = _metal(Color(0.72, 0.32, 1.0), 0.0, 0.5, 2.6)
	_bands(chest, b, l, [0.2, 0.8], 0.03, rune)
	_box(chest, chest, Vector3(b.get_center().x, b.position.y + b.size.y * 0.5, b.end.z + 0.012), Vector3(b.size.x * 0.7, 0.03, 0.02), rune)
	# The sigil on the ground under it, pulsing, and wisps rising from it.
	var sigil := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.05
	disc.bottom_radius = 1.05
	disc.height = 0.01
	sigil.mesh = disc
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(0.55, 0.2, 0.9, 0.38)
	sigil.material_override = glow
	sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sigil.position = Vector3(b.get_center().x, 0.02, b.get_center().z)
	chest.add_child(sigil)
	var pulse := sigil.create_tween().set_loops()
	pulse.tween_property(glow, "albedo_color:a", 0.14, 1.1).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "albedo_color:a", 0.4, 1.1).set_trans(Tween.TRANS_SINE)
	var wisps := CPUParticles3D.new()
	wisps.amount = 14
	wisps.lifetime = 1.8
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	wisps.emission_box_extents = Vector3(b.size.x * 0.45, 0.03, b.size.z * 0.45)
	wisps.direction = Vector3.UP
	wisps.spread = 12.0
	wisps.initial_velocity_min = 0.35
	wisps.initial_velocity_max = 0.7
	wisps.gravity = Vector3.ZERO
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	wisps.mesh = dot
	var wisp_mat := StandardMaterial3D.new()
	wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wisp_mat.albedo_color = Color(0.78, 0.45, 1.0)
	wisps.material_override = wisp_mat
	wisps.position = Vector3(b.get_center().x, b.end.y, b.get_center().z)
	chest.add_child(wisps)

static func _hoard(chest: Chest, b: AABB, l: AABB) -> void:
	var gold: StandardMaterial3D = _metal(Color(0.85, 0.62, 0.18), 0.5, 0.35, 0.7)
	_bands(chest, b, l, [0.1, 0.5, 0.9], 0.055, gold)
	_box(chest, chest, Vector3(b.get_center().x, b.position.y + 0.02, b.get_center().z), Vector3(b.size.x + 0.05, 0.05, b.size.z + 0.05), gold)
	_box(chest, chest, Vector3(b.get_center().x, b.position.y + b.size.y * 0.78, b.end.z + 0.018), Vector3(0.2, 0.24, 0.04), gold)
	for corner in [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0)]:   # a gold cap on each foot
		_box(chest, chest, Vector3(b.position.x + b.size.x * corner.x, b.position.y + 0.06, b.position.z + b.size.z * corner.y), Vector3(0.1, 0.12, 0.1), gold)
	# A heap of coin inside, under the lid's edge when closed and shining when it opens.
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	var coin_mat: StandardMaterial3D = _metal(Color(1.0, 0.82, 0.3), 0.9, 0.25, 1.2)
	for i in 26:
		var coin := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.06
		disc.bottom_radius = 0.06
		disc.height = 0.015
		coin.mesh = disc
		coin.material_override = coin_mat
		coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chest.add_child(coin)
		var spread := Vector2(rng.randf_range(-0.5, 0.5) * b.size.x * 0.8, rng.randf_range(-0.5, 0.5) * b.size.z * 0.7)
		coin.position = Vector3(b.get_center().x + spread.x, b.end.y - 0.07 + 0.03 * (1.0 - spread.length() / maxf(b.size.x, 0.1)), b.get_center().z + spread.y)
		coin.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
