shader_type spatial;
// Energy stays readable as the raised weapon passes behind the shoulders.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform vec4 blood_color : source_color = vec4(0.95, 0.02, 0.12, 1.0);
uniform float fade = 1.0;
uniform float surge = 1.0;
uniform float flow_phase = 0.0;

void fragment() {
	float packet = pow(0.5 + 0.5 * cos((UV.x - flow_phase) * 6.283185), 14.0);
	float rim = smoothstep(0.0, 0.25, UV.y) * smoothstep(0.0, 0.25, 1.0 - UV.y);
	ALBEDO = blood_color.rgb * 0.4;
	EMISSION = blood_color.rgb * (0.65 + packet * 1.6) * surge;
	ALPHA = fade * rim * (0.65 + packet * 0.35);
}
