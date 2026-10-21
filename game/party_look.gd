class_name PartyLook
extends RefCounted
## How the party reads in a crowd (issue #99): one colour per member, shared by the ground ring, the outline that shows through
## occluders and the overhead bars. Enemies get none of it. Change a colour here and everything follows.

const GOLD := Color(1.0, 0.78, 0.25)    # the warrior (the hero)
const TEAL := Color(0.2, 0.85, 0.8)     # the Cutter
const HEALTH_GREEN := Color(0.30, 0.78, 0.32)   # party overhead health (enemies stay red)
const DAMAGE_TAKEN := Color(1.0, 0.55, 0.12)    # orange numbers for damage a party member takes
const RING_SHADER := preload("res://game/party_ring.gdshader")
const XRAY_SHADER := preload("res://game/party_xray.gdshader")
const RIM_SHADER := preload("res://game/party_rim.gdshader")
const RING_SIZE := 2.4   # metres across the quad that carries the ring

static var _xray: Dictionary = {}

static func color_of(member_id: String) -> Color:
	return GOLD if member_id == "hero" else TEAL

## "sword" for the warrior, "bow" for the Cutter: the small class icon on the party's bars.
static func class_icon(member_id: String) -> String:
	return "sword" if member_id == "hero" else "bow"

## The soft ring decal that lies on the ground at a member's feet.
static func make_ring(member_id: String) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(RING_SIZE, RING_SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	var material := ShaderMaterial.new()
	material.shader = RING_SHADER
	material.set_shader_parameter("tint", color_of(member_id))
	var ring := MeshInstance3D.new()
	ring.name = "PartyRing"
	ring.mesh = quad
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, 0.12, 0.0)   # clear of the raised floor tiles and their bevels
	return ring

## The outline pass that stays on the model: a faint rim in the open, the whole silhouette where something stands in front.
static func xray_material(member_id: String) -> ShaderMaterial:
	if not _xray.has(member_id):
		var material := ShaderMaterial.new()
		material.shader = XRAY_SHADER
		material.set_shader_parameter("tint", color_of(member_id))
		var rim := ShaderMaterial.new()
		rim.shader = RIM_SHADER
		rim.set_shader_parameter("tint", color_of(member_id))
		material.next_pass = rim
		_xray[member_id] = material
	return _xray[member_id]
