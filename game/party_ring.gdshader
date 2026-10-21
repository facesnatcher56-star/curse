shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// The party's ground ring: a soft band lying on the floor, so it sits under the feet of anything standing on it.
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.25, 1.0);
uniform float radius = 0.82;     // of the quad's half width (1.0 = the quad's edge)
uniform float width = 0.10;
uniform float softness = 0.07;

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float band = 1.0 - smoothstep(width * 0.5, width * 0.5 + softness, abs(d - radius));
	float glow = (1.0 - smoothstep(0.0, 0.35, abs(d - radius))) * 0.18;
	ALBEDO = tint.rgb;
	ALPHA = clamp(band * 0.85 + glow, 0.0, 1.0);
}
