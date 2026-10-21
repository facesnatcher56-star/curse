shader_type spatial;
render_mode unshaded, blend_mix, depth_test_inverted, depth_draw_never, cull_back, shadows_disabled;
// A party member's outline, part one: where something stands in front of the body (an enemy, a prop, a wall) the depth test is
// inverted, so only the hidden parts draw, as a flat silhouette in the member's colour. The faint rim in the open is the next pass
// (party_rim.gdshader). One extra pass over the body meshes, no extra geometry.
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.25, 1.0);
uniform float hidden_alpha = 0.55;

uniform float toward_camera = 0.7;   // metres: the pass sits this far in front of the body, so the body's own depth never counts as hiding it

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.z += toward_camera;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = hidden_alpha;
}

