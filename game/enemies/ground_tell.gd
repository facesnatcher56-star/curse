class_name GroundTell
extends Node3D
## A ground marker for an attack that has already chosen where it will land: a worn ember ring at exactly the hit radius, with a
## dull fill that warms as the strike gets closer. It sits in world space (not on the enemy), and frees itself if the enemy that
## owns it dies or leaves the tree, so a missed cleanup can never leave one behind.

const GROUP := "ground_tells"
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec4 ember : source_color = vec4(0.56, 0.27, 0.12, 1.0);
uniform float progress = 0.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;   // 1.0 is exactly the hit radius
	float edge = smoothstep(0.86, 0.93, d) * (1.0 - smoothstep(0.985, 1.0, d));
	float fill = (1.0 - smoothstep(0.0, 0.93, d)) * 0.14 + step(d, 0.93) * (0.04 + 0.14 * progress);
	float a = clamp(edge * (0.6 + 0.25 * progress) + fill * step(d, 0.93), 0.0, 1.0);
	ALBEDO = ember.rgb * (0.75 + 0.45 * progress);
	ALPHA = a;
}
"""

static var _shader: Shader

var radius: float = 1.0
var lifetime: float = 1.5
var owner_enemy: Node3D

var _age: float = 0.0
var _mat: ShaderMaterial

## Creates a marker under `parent`, centred on `point`, at `hit_radius`, owned by `enemy`.
static func spawn(parent: Node, enemy: Node3D, point: Vector3, hit_radius: float, seconds: float) -> GroundTell:
	var tell := GroundTell.new()
	tell.radius = hit_radius
	tell.lifetime = seconds + 0.35   # a safety margin: normally the owner frees it on landing
	tell.owner_enemy = enemy
	parent.add_child(tell)
	tell.global_position = Vector3(point.x, 0.04, point.z)
	return tell

func _ready() -> void:
	add_to_group(GROUP)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	mesh.mesh = plane
	mesh.material_override = _mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime or not is_instance_valid(owner_enemy) or not owner_enemy.is_inside_tree() or ("dead" in owner_enemy and owner_enemy.dead):
		queue_free()
		return
	_mat.set_shader_parameter("progress", clampf(_age / maxf(lifetime - 0.35, 0.01), 0.0, 1.0))

func clear() -> void:
	remove_from_group(GROUP)
	queue_free()
