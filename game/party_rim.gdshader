shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
// A party member's outline, part two: a thin, subtle rim in the member's colour on the visible body edge.
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.25, 1.0);
uniform float rim_alpha = 0.55;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb;
	ALPHA = rim * rim_alpha;
}
