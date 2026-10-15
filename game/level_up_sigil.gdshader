shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D sigil_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
uniform float reveal_progress : hint_range(0.0, 1.0) = 0.0;
uniform float brightness : hint_range(0.0, 2.5) = 0.55;

void fragment() {
	vec4 sigil = texture(sigil_texture, UV);
	float radial = length((UV - vec2(0.5)) * 2.0) * 0.7071;
	float reveal = 1.0 - smoothstep(reveal_progress - 0.035, reveal_progress + 0.015, radial);
	float reveal_edge = exp(-pow((radial - reveal_progress) * 48.0, 2.0));
	vec3 edge_color = mix(vec3(1.0, 0.47, 0.16), vec3(1.0, 0.93, 0.66), reveal_edge);
	ALBEDO = sigil.rgb * vec3(1.05, 1.02, 0.98) * brightness;
	EMISSION = sigil.rgb * vec3(2.2, 1.95, 1.6) * brightness + edge_color * reveal_edge * 1.25;
	ALPHA = sigil.a * opacity * reveal;
}
