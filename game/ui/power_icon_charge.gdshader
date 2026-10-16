shader_type canvas_item;

// A power's hotbar icon: blacked out while it recharges, filling with its own colour from the bottom up, then pulsing once it is ready.
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;   // 0 until the power is ready, then a slow 0..1 wave
uniform float burst : hint_range(0.0, 1.0) = 0.0;   // 1 at the instant it fills, fading to 0
uniform vec3 theme : source_color = vec3(1.0, 0.7, 0.3);

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float up = 1.0 - UV.y;
	float lit = (1.0 - smoothstep(fill - 0.025, fill + 0.025, up)) * step(0.001, fill);
	vec3 col = mix(base.rgb * 0.05, base.rgb, lit);
	// A thin bright line rides the top of the colour as it rises.
	float edge = (1.0 - smoothstep(0.0, 0.045, abs(up - fill))) * step(0.001, fill) * (1.0 - step(0.999, fill));
	col += theme * edge * 0.7;
	float lum = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
	col *= 1.0 + pulse * 0.28;
	col += theme * pulse * 0.16 * (0.4 + lum);
	col += (theme * 1.1 + vec3(0.35)) * burst * (0.35 + lum);
	COLOR = vec4(col, base.a);
}
