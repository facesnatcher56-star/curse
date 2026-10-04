shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

// Blood confined to the blade of the sword: nothing below `blade_start` (grip, guard, pommel) is touched.
// `amount` (0..1) is how bloody it is; coverage is streaky and heavier toward the guard where blood pools.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float blade_start = 0.0;
uniform float blade_end = 1.0;
uniform vec4 blood_color : source_color = vec4(0.38, 0.02, 0.02, 1.0);

varying vec3 v_local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float t = (v_local.y - blade_start) / max(blade_end - blade_start, 0.001);
	float on_blade = smoothstep(-0.015, 0.03, t) * (1.0 - smoothstep(1.0, 1.03, t));
	float n = value_noise(vec3(v_local.x * 70.0, v_local.y * 16.0, v_local.z * 70.0));
	float coverage = amount * 1.5 + (n - 0.5) * 0.7 + (1.0 - clamp(t, 0.0, 1.0)) * 0.2 * amount;
	float a = on_blade * smoothstep(0.35, 0.65, coverage) * 0.92;
	ALBEDO = blood_color.rgb;
	ALPHA = a;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}