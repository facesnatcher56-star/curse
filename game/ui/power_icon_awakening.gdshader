shader_type canvas_item;
render_mode blend_add;

// Generic alpha-respecting sheen over the currently assigned icon texture.
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float ready_glint : hint_range(0.0, 1.0) = 0.0;
uniform float release : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float luminance = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Follow the painted highlights, with enough response for dark metal too.
	float highlights = mix(0.18, 1.0, smoothstep(0.025, 0.70, luminance));
	float diagonal = UV.x + UV.y;
	float warm_sheen = 1.0 - smoothstep(0.0, 0.22, abs(diagonal - (0.20 + charge * 1.50)));
	float glint = 1.0 - smoothstep(0.008, 0.045, abs(diagonal - (2.10 - ready_glint * 2.20)));
	float ready_envelope = smoothstep(0.0, 0.16, ready_glint);
	// Paired reflections start at opposite corners and contract into the icon.
	// They are clipped to the assigned texture, never drawn as a progress ring.
	float inward = 1.0 - smoothstep(0.012, 0.065, abs(abs(diagonal - 1.0) - release * 0.95));
	float release_envelope = smoothstep(0.0, 0.22, release);
	float initial_flash = smoothstep(0.70, 1.0, release) * 0.10;
	vec3 reflection = vec3(1.0, 0.74, 0.40) * charge * (0.30 + warm_sheen * 0.38) * highlights;
	reflection += vec3(1.0, 0.69, 0.25) * glint * ready_envelope * 0.55 * mix(0.55, 1.0, highlights);
	reflection += vec3(1.0, 0.65, 0.20) * (initial_flash + inward * release_envelope * 0.50) * mix(0.55, 1.0, highlights);
	// Apply intensity once. Multiplying RGB and alpha by it squared the old sheen.
	COLOR = vec4(reflection, base.a);
}
