shader_type canvas_item;
// The fluid and glass are Blender renders; only level, frame blending and the
// meniscus respond to live gameplay here. One neutral atlas serves both vessels.
uniform sampler2D liquid_atlas : source_color, filter_linear, repeat_disable;
uniform sampler2D glass_dome : source_color, filter_linear, repeat_disable;
uniform vec4 liquid_color : source_color = vec4(0.60, 0.12, 0.10, 1.0);
uniform float fill_level : hint_range(0.0, 1.0) = 1.0;
uniform float clock = 0.0;
uniform float slosh : hint_range(0.0, 1.0) = 0.0;
uniform float lean : hint_range(-1.0, 1.0) = 0.0;
const float RADIUS = 0.31296;
vec3 frame_sample(float frame, vec2 uv) {
 vec2 cell = vec2(mod(frame, 8.0), floor(frame / 8.0));
 return texture(liquid_atlas, (cell + clamp(uv, vec2(0.002), vec2(0.998))) / vec2(8.0, 4.0)).rgb;
}
void fragment() {
 vec2 p = UV - vec2(0.5);
 float radius = length(p);
 float circle = 1.0 - smoothstep(RADIUS - 0.003, RADIUS, radius);
 float frame = mod(clock * 5.0, 32.0);
 vec3 fluid = mix(frame_sample(floor(frame), UV), frame_sample(mod(floor(frame) + 1.0, 32.0), UV), fract(frame));
 float stream = dot(fluid, vec3(0.333));
 float wave = sin(p.x * 27.0 + clock * 2.2) * 0.006 + sin(p.x * 43.0 - clock * 1.7) * 0.003;
 wave *= 1.0 + slosh * 2.5;
 float surface = mix(RADIUS + 0.015, -RADIUS - 0.015, fill_level) + wave + lean * p.x * 0.10;
 float wet = smoothstep(surface - 0.003, surface + 0.003, p.y);
 wet *= step(0.001, fill_level);
 vec3 glass = texture(glass_dome, UV).rgb;
 vec3 empty = vec3(0.016, 0.020, 0.026) + glass * 0.16;
 vec3 volume = liquid_color.rgb * (0.40 + stream * 1.5);
 float meniscus = exp(-abs(p.y - surface) * 300.0) * step(0.01, fill_level) * step(fill_level, 0.98);
 vec3 rgb = mix(empty, volume, wet) + glass * 0.14 + liquid_color.rgb * meniscus * 0.3;
 COLOR = vec4(rgb, circle);
}
