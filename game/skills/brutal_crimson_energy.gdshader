shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 blood_color : source_color = vec4(0.9, 0.015, 0.06, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float surge : hint_range(0.0, 3.0) = 1.0;
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	// Dark obsidian core with readable, hot crimson bevels and hairline fissures.
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float fissure = pow(max(0.0, sin(local_position.y * 29.0 + local_position.x * 17.0)), 22.0);
	vec3 core = vec3(0.045, 0.001, 0.008);
	ALBEDO = mix(core, blood_color.rgb * 0.38, edge);
	EMISSION = blood_color.rgb * (0.14 + edge * 1.4 + fissure * 0.28) * surge;
	ALPHA = fade;
}
