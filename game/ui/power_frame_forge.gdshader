shader_type canvas_item;

// Reuses the shared ornate frame texture as its own engraving mask. Warm
// pixels are the bronze/gold metalwork; the recessed charcoal stays dark.
uniform vec2 frame_size = vec2(62.0);
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float ready_glint : hint_range(0.0, 1.0) = 0.0;
uniform float release : hint_range(0.0, 1.0) = 0.0;
uniform float enabled = 1.0;
varying vec2 frame_uv;

void vertex() {
	frame_uv = VERTEX / frame_size;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float metal = smoothstep(0.055, 0.30, base.r - base.b + (base.r + base.g + base.b) * 0.08);
	// Destination coordinates keep the reveal continuous across all nine slices.
	float side = abs(frame_uv.x - 0.5) * 2.0;
	// Lower scrollwork -> side engravings -> upper corners -> central crown.
	float path = 0.20 + (1.0 - frame_uv.y) * 0.60;
	if (frame_uv.y > 0.80) {
		path = side * 0.20;
	} else if (frame_uv.y < 0.20) {
		path = 0.80 + (1.0 - side) * 0.20;
	}
	float forged = smoothstep(path - 0.018, path + 0.018, charge) * smoothstep(0.0, 0.04, charge) * enabled;
	float ready = smoothstep(0.96, 1.0, charge) * enabled;
	vec3 bronze = base.rgb * vec3(0.40, 0.31, 0.22);
	vec3 gold = base.rgb * vec3(0.95, 0.80, 0.48) + vec3(0.46, 0.27, 0.055);
	vec3 lit = mix(bronze, gold, forged);
	// Steady ready illumination remains after the brief arrival glint.
	lit += vec3(0.22, 0.14, 0.035) * ready;
	lit += vec3(0.16, 0.10, 0.025) * ready_glint * enabled;
	// The engraving brightens first, then drains as the icon contracts inward.
	float discharge = smoothstep(0.25, 0.95, release) * enabled;
	lit = mix(lit, gold + vec3(0.28, 0.17, 0.04), discharge);
	COLOR = vec4(lit, base.a * metal);
}
