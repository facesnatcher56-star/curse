shader_type spatial;
// The Crypt's stone: the kit's own texture (not repainted), darkened, with grime and moss laid on by world position so the
// tiles stop reading as clean plastic. Used by CryptLook on the floor, walls and stone set pieces only.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float darken = 0.7;
uniform float grime = 0.6;
uniform float moss = 0.4;
uniform float rough_lo = 0.72;
uniform float rough_hi = 0.98;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.1 + 7.0) + 0.2 * vnoise(p * 4.3 + 19.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 col = tex.rgb * base_color.rgb * darken;
	vec2 plane = wpos.xz + vec2(wpos.y * 0.7, wpos.y * 0.4);
	float dirt = smoothstep(0.3, 0.75, fbm(plane * 0.33));
	float fine = fbm(plane * 1.9 + 11.0);
	col *= mix(1.0, 0.42, dirt * grime);
	col *= mix(0.85, 1.1, fine);
	float up = clamp(wnrm.y, 0.0, 1.0);
	float low = 1.0 - smoothstep(0.2, 2.2, wpos.y);
	float patch = smoothstep(0.58, 0.82, fbm(plane * 0.55 + 3.0));
	col = mix(col, vec3(0.055, 0.09, 0.04) * (0.8 + fine * 0.6), patch * moss * mix(0.5, 1.0, up) * low);
	ALBEDO = col * 0.92 + vec3(0.03, 0.032, 0.04);   // no texel goes pitch black
	ROUGHNESS = mix(rough_lo, rough_hi, fine);
	SPECULAR = 0.25;
}
