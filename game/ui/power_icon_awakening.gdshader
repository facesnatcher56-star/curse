shader_type canvas_item;
render_mode blend_add;

// Generic alpha-respecting sheen over the currently assigned icon texture.
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float ready_glint : hint_range(0.0, 1.0) = 0.0;
uniform float release : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float visible = base.a;
	float sheen_line = UV.x + UV.y;
	float warm_sheen = 1.0 - smoothstep(0.0, 0.16, abs(sheen_line - (0.26 + charge * 1.15)));
	float glint = 1.0 - smoothstep(0.0, 0.045, abs(sheen_line - (1.45 - ready_glint * 1.9)));
	float release_glint = 1.0 - smoothstep(0.0, 0.065, abs(sheen_line - (1.65 - release * 2.2)));
	float intensity = charge * warm_sheen * 0.18 + ready_glint * glint * 0.64 + release * release_glint * 0.78;
	vec3 metallic = mix(vec3(1.0, 0.40, 0.08), vec3(1.0, 0.94, 0.76), max(glint * ready_glint, release_glint * release));
	// A restrained additive reflection preserves icon hue and any painted background.
	COLOR = vec4(metallic * intensity, clamp(intensity * visible, 0.0, 0.78));
}
