shader_type canvas_item;
render_mode blend_add;

// Reuses the shared ornate frame texture as its own engraving mask. Warm
// pixels are the bronze/gold metalwork; the recessed charcoal stays dark.
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float ready_glint : hint_range(0.0, 1.0) = 0.0;
uniform float release : hint_range(0.0, 1.0) = 0.0;
uniform float enabled = 1.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float metal = smoothstep(0.055, 0.30, base.r - base.b + (base.r + base.g + base.b) * 0.08);
	// Traversal follows the frame's two side engravings from their lower ends
	// toward the crown. This gates the existing metal detail; it draws no rail.
	float path = clamp((1.0 - UV.y) * 0.80 + abs(UV.x - 0.5) * 0.20, 0.0, 1.0);
	float progress = smoothstep(path - 0.10, path + 0.045, charge);
	float lower = smoothstep(0.80, 1.0, UV.y) * ((1.0 - smoothstep(0.0, 0.48, UV.x))
		+ smoothstep(0.52, 1.0, UV.x));
	float ember = smoothstep(0.0, 0.20, charge) * lower;
	float glow = enabled * metal * max(progress, ember * 0.78);
	float top = 1.0 - smoothstep(0.04, 0.26, UV.y);
	float crown = enabled * metal * top * smoothstep(0.88, 1.0, charge);
	float sweep = 1.0 - smoothstep(0.0, 0.075, abs(UV.x + UV.y - (1.62 - ready_glint * 1.9)));
	float release_sweep = 1.0 - smoothstep(0.0, 0.11, abs(UV.x + UV.y - (1.8 - release * 2.4)));
	vec3 heated = mix(vec3(0.36, 0.12, 0.025), vec3(1.0, 0.62, 0.19), progress);
	vec3 result = base.rgb + heated * glow * (0.12 + 0.58 * progress);
	result += vec3(1.0, 0.76, 0.35) * glow * smoothstep(0.72, 1.0, charge) * 0.36;
	result += vec3(1.0, 0.79, 0.42) * crown * 0.48;
	result += vec3(1.0, 0.92, 0.68) * enabled * sweep * metal * ready_glint * 0.75;
	result += vec3(1.0, 0.95, 0.79) * enabled * release_sweep * metal * release * 0.9;
	float alpha = clamp((glow * (0.12 + 0.42 * progress) + crown * 0.38
		+ enabled * sweep * metal * ready_glint * 0.62
		+ enabled * release_sweep * metal * release * 0.72) * base.a, 0.0, 0.82);
	COLOR = vec4(max(result - base.rgb, vec3(0.0)), alpha);
}
