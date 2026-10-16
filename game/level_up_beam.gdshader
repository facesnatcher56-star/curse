shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(1.0, 0.74, 0.38, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float radial_fade = pow(max(sin(PI * UV.x), 0.0), 0.65);
	float vertical_fade = smoothstep(0.0, 0.10, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	float filament = 0.78 + 0.22 * sin(UV.y * 24.0 - TIME * 3.5);
	ALBEDO = beam_color.rgb;
	EMISSION = beam_color.rgb * 1.8;
	ALPHA = opacity * radial_fade * vertical_fade * filament;
}
