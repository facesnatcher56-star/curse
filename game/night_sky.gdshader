shader_type sky;
// A night sky for Curse (docs/ART_DIRECTION.md: dark, muted, one warm accent): a deep blue-black gradient, a scatter of stars that
// twinkle a little, thin drifting cloud streaks, and a pale cratered moon with a cold halo. It is painted on every direction, below the
// horizon too: the fixed 3/4 camera looks down, so what shows beyond the edge of the map is this.

uniform vec3 moon_direction = vec3(-0.5, -0.6, -0.62);
uniform float moon_radius = 0.052;
uniform vec3 zenith_color : source_color = vec3(0.004, 0.007, 0.02);
uniform vec3 horizon_color : source_color = vec3(0.02, 0.026, 0.045);
uniform float star_amount = 1.3;
uniform vec3 moon_tint = vec3(0.72, 0.73, 0.74);   // a blood moon is a deep red
uniform vec3 halo_color = vec3(0.16, 0.2, 0.3);
uniform vec3 halo_wide_color = vec3(0.1, 0.13, 0.2);
uniform vec3 cloud_light = vec3(0.1, 0.11, 0.14);
uniform float eclipse = 0.0;   // 1: a total-eclipse blood moon: a dim copper-red disc, darker toward one side, with a thin bright crescent on its limb

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise2(p);
		p = p * 2.03 + vec2(7.1, 3.7);
		a *= 0.5;
	}
	return v;
}

vec3 stars(vec3 d) {
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 70.0 : 150.0;
		vec3 p = d * scale;
		vec3 cell = floor(p);
		float h = hash13(cell + float(layer) * 17.0);
		float threshold = layer == 0 ? 0.972 : 0.986;
		if (h > threshold) {
			vec3 jitter = (hash33(cell) - 0.5) * 0.6;
			float dist = length(fract(p) - 0.5 - jitter);
			float size = layer == 0 ? 120.0 : 260.0;
			float twinkle = 0.75 + 0.25 * sin(TIME * (1.5 + h * 9.0) + h * 80.0);
			float bright = (h - threshold) / (1.0 - threshold);
			vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.68), hash13(cell + 3.0));
			col += tint * exp(-dist * dist * size) * (0.8 + 1.6 * bright) * twinkle;
		}
	}
	return col * star_amount;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = abs(d.y);
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), 0.55));

	// A faint cold glow around the moon.
	vec3 m = normalize(moon_direction);
	float md = dot(d, m);
	col += halo_color * pow(clamp(md, 0.0, 1.0), 40.0) * 0.55;
	col += halo_wide_color * pow(clamp(md, 0.0, 1.0), 8.0) * 0.07;

	// Stars, dimmed near the moon and by the haze at the horizon.
	float star_fade = (1.0 - smoothstep(0.80, 0.97, md)) * smoothstep(0.0, 0.25, up);
	col += stars(d) * star_fade;

	// The moon: a lit disc with dark maria, a terminator that leaves a thin crescent of earthshine, soft edges.
	vec3 u = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
	vec3 v = cross(u, m);
	float x = dot(d, u) / moon_radius;
	float y = dot(d, v) / moon_radius;
	float r2 = x * x + y * y;
	if (md > 0.0 && r2 < 1.0) {
		float z = sqrt(1.0 - r2);
		vec3 n = vec3(x, y, z);
		float maria = fbm(vec2(x, y) * 2.6 + 3.0);
		float craters = fbm(vec2(x, y) * 9.0);
		vec3 surface = moon_tint * (0.62 + 0.5 * smoothstep(0.35, 0.65, maria)) * (0.88 + 0.22 * craters);
		float lit = smoothstep(-0.12, 0.35, dot(n, normalize(vec3(0.62, 0.25, 0.74))));
		if (eclipse > 0.5) {
			// In the umbra: dim and copper, darker toward the lower left, with a thin bright sliver where the sun still reaches the limb.
			surface *= mix(0.45, 1.0, smoothstep(-0.7, 0.55, dot(n, normalize(vec3(0.55, 0.4, 0.5)))));
			float sliver = smoothstep(0.9, 0.975, dot(n, normalize(vec3(0.82, 0.5, 0.28))));
			surface = mix(surface, vec3(0.9, 0.82, 0.72) * (0.8 + 0.3 * maria), sliver);
		} else {
			surface *= mix(0.07, 1.0, lit);
		}
		float edge = smoothstep(1.0, 0.94, sqrt(r2));
		col = mix(col, surface, edge);
	}

	// Thin cloud streaks drifting across, catching a little moonlight; they cover stars and the lower moon a little.
	vec2 cuv = d.xz / (up + 0.35) * 1.4 + vec2(TIME * 0.006, 0.0);
	float cloud = smoothstep(0.52, 0.8, fbm(cuv * vec2(1.0, 2.6)));
	vec3 cloud_col = vec3(0.045, 0.05, 0.075) + cloud_light * pow(clamp(md, 0.0, 1.0), 12.0);
	col = mix(col, cloud_col, cloud * 0.7);

	COLOR = col;
}
