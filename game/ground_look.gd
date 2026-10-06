class_name GroundLook
extends RefCounted
## The look of the ground: the plaza's earth and the Crypt Road's packed dirt. One flat noise texture stretched over eighty metres
## showed as big soft blotches with blocky bumps, so this lays four scales of noise over the world instead, all in world space (so
## the plaza and the road join without a seam): broad stains, clods and cracks (a cellular noise measuring the distance to the
## nearest crack), gravel and fine grit. The relief is worked out from the same heights, so the light catches every clod. Muted and
## dirty, never glossy (docs/ART_DIRECTION.md).

const SIZE := 512

static var _broad: ImageTexture
static var _cells: ImageTexture
static var _grain: ImageTexture
static var _shaders: Dictionary = {}

const CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D broad : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cells : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 dark : source_color;
uniform vec3 light : source_color;
uniform vec3 stain : source_color;
uniform float relief = 1.0;
uniform float crack_depth = 0.45;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 0 in the cracks between clods, up to 1 in the middle of one
float clods(vec2 p) {
	float big = texture(cells, p / 2.6).r;
	float small = texture(cells, p / 0.85 + vec2(0.37, 0.61)).r;
	return big * 0.6 + small * 0.4;
}

float ground_height(vec2 p) {
	float g = texture(grain, p / 0.32).r * 0.6 + texture(grain, p / 0.1 + vec2(0.5, 0.2)).r * 0.4;
	return clods(p) * 0.7 + g * 0.45;
}

void fragment() {
	vec2 p = world_pos.xz;
	float wide = texture(broad, p / 55.0).r * 0.55 + texture(broad, p / 14.0 + vec2(0.3, 0.7)).r * 0.45;
	float h = ground_height(p);
	float e = 0.02;
	float hx = ground_height(p + vec2(e, 0.0));
	float hz = ground_height(p + vec2(0.0, e));
	vec3 n = normalize(vec3((h - hx) / e * 0.045 * relief, 1.0, (h - hz) / e * 0.045 * relief));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float grit = texture(grain, p / 0.22 + vec2(0.13, 0.81)).r;
	float c = clods(p);
	vec3 col = mix(dark, light, clamp(wide * 0.8 + (h - 0.5) * 0.45, 0.0, 1.0));
	col = mix(col, stain, smoothstep(0.62, 0.9, texture(broad, p / 23.0 + vec2(0.8, 0.1)).r) * 0.55);   // damp, dark patches
	col *= mix(1.0 - crack_depth, 1.0, smoothstep(0.02, 0.28, c));                                       // cracks and the gaps between clods
	col *= 0.86 + 0.28 * grit;                                                                          // grit
	col = mix(col, col * 1.55, smoothstep(0.86, 0.97, grit) * 0.6);                                       // a few pale pebbles
	ALBEDO = col;
	ROUGHNESS = 0.9 + 0.1 * grit;
	SPECULAR = 0.15;
	//ALPHA_LINE
}
"""

## A material for ground in this palette. `edge_fade` makes it fade out where the mesh's vertex alpha does (the road's ribbon).
static func material(dark: Color, light: Color, stain: Color, edge_fade: bool = false, relief: float = 1.0) -> ShaderMaterial:
	_make_textures()
	var key: String = "fade" if edge_fade else "solid"
	if not _shaders.has(key):
		var shader := Shader.new()
		shader.code = CODE.replace("//ALPHA_LINE", "ALPHA = COLOR.a;" if edge_fade else "")
		_shaders[key] = shader
	var mat := ShaderMaterial.new()
	mat.shader = _shaders[key]
	mat.set_shader_parameter("broad", _broad)
	mat.set_shader_parameter("cells", _cells)
	mat.set_shader_parameter("grain", _grain)
	mat.set_shader_parameter("dark", dark)
	mat.set_shader_parameter("light", light)
	mat.set_shader_parameter("stain", stain)
	mat.set_shader_parameter("relief", relief)
	return mat

static func _make_textures() -> void:
	if _broad != null:
		return
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	noise.seed = 11
	_broad = _bake(noise)
	var cellular := FastNoiseLite.new()
	cellular.noise_type = FastNoiseLite.TYPE_CELLULAR
	cellular.frequency = 0.04
	cellular.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cellular.cellular_jitter = 1.0
	cellular.seed = 5
	_cells = _bake(cellular)
	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fine.frequency = 0.09
	fine.fractal_octaves = 3
	fine.seed = 23
	_grain = _bake(fine)

static func _bake(noise: FastNoiseLite) -> ImageTexture:
	var image: Image = noise.get_seamless_image(SIZE, SIZE)
	image.convert(Image.FORMAT_L8)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
