class_name Shaders
extends RefCounted
## Canvas shaders built from code (kept here so every effect is in one place).

static var _cache := {}

const FLASH := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float alpha_mul = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.rgb = mix(c.rgb, flash_color.rgb, flash);
	c.a *= alpha_mul;
	COLOR = c;
}
"""

const GHOST := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.19, 0.88, 0.73, 1.0);
uniform float strength = 0.55;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float scan = step(0.5, fract(FRAGCOORD.y * 0.5 + TIME * 3.0));
	vec3 col = mix(tint.rgb * 0.55, tint.rgb * 1.25, l);
	COLOR = vec4(col, c.a * strength * (0.75 + 0.25 * scan));
}
"""

const VIGNETTE := """
shader_type canvas_item;
uniform float intensity = 0.0;
uniform vec4 tint : source_color = vec4(0.9, 0.05, 0.1, 1.0);
uniform float dark = 0.0;
// 4x4 ordered dither: a soft pixel-art gradient instead of hard bands
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}
float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}
void fragment() {
	vec2 p = UV - 0.5;
	p.x *= 1.35;
	float d = length(p);
	// only the outer rim tints; the play area around the hero stays clear
	float v = smoothstep(0.48, 0.92, d);
	float a = v * v * (intensity * 0.62 + dark);
	float q = floor(a * 8.0 + bayer4(FRAGCOORD.xy)) / 8.0;
	// ink-leaning red reads as "danger" without a neon frame
	vec3 rgb = mix(tint.rgb, vec3(0.18, 0.13, 0.18), 0.35 + 0.65 * dark);
	COLOR = vec4(rgb, clamp(q, 0.0, 0.7));
}
"""

const DARKNESS := """
shader_type canvas_item;
uniform int count = 0;
uniform vec4 lights[16];
uniform float darkness = 0.93;
uniform vec2 screen_size = vec2(640.0, 360.0);
uniform vec4 shade : source_color = vec4(0.05, 0.035, 0.08, 1.0);
void fragment() {
	// chunky 2px light grid, fully clear core, 4 posterized falloff bands
	vec2 px = floor(UV * screen_size / 2.0) * 2.0 + 1.0;
	float lit = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= count) break;
		vec4 L = lights[i];
		float d = distance(px, L.xy);
		float v = 1.0 - smoothstep(L.z * 0.5, L.z, d);
		lit = max(lit, v * L.w);
	}
	float band = floor(lit * 4.0 + 0.35) / 4.0;
	float a = darkness * (1.0 - clamp(band, 0.0, 1.0));
	COLOR = vec4(shade.rgb, a);
}
"""

const REWIND := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;
uniform float t = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float row = floor(uv.y * 90.0);
	float jitter = sin(row * 1.7 + t * 40.0) * 0.012 * amount;
	float band = step(0.93, fract(uv.y * 3.0 - t * 2.5)) * 0.04 * amount;
	uv.x += jitter + band;
	float sh = 0.006 * amount;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(sh, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(sh, 0.0)).b;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(g * 0.6, g * 1.0, g * 0.95), amount * 0.65);
	float lines = step(0.5, fract(FRAGCOORD.y * 0.5)) * 0.12 * amount;
	c -= lines;
	COLOR = vec4(c, 1.0);
}
"""

const WAVE := """
shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	vec2 uv = UV;
	uv.x += sin(uv.y * 24.0 + TIME * 6.0) * 0.01;
	COLOR = texture(TEXTURE, uv) * COLOR;
}
"""


static func get_shader(key: String) -> Shader:
	if _cache.has(key):
		return _cache[key]
	var s := Shader.new()
	match key:
		"flash": s.code = FLASH
		"ghost": s.code = GHOST
		"vignette": s.code = VIGNETTE
		"darkness": s.code = DARKNESS
		"rewind": s.code = REWIND
		"wave": s.code = WAVE
	_cache[key] = s
	return s


static func material(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = get_shader(key)
	return m
