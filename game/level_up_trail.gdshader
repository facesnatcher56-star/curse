shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 trail_color : source_color = vec4(1.0, 0.74, 0.38, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
uniform float rise_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float ribbon_edge = pow(max(sin(PI * UV.x), 0.0), 1.2);
	float rising_front = smoothstep(UV.y - 0.04, UV.y + 0.04, rise_progress);
	float tip_glow = 0.75 + 0.25 * sin(UV.y * 10.0 - TIME * 4.0);
	ALBEDO = trail_color.rgb;
	EMISSION = trail_color.rgb * 1.0;
	ALPHA = opacity * ribbon_edge * rising_front * tip_glow;
}
