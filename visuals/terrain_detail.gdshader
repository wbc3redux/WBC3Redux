// Enhanced visuals terrain detail (ENHANCED_VISUALS.md): a deliberate modern change, off by default. Fine detail over the
// painted 320 x 240 panels (terrain_layer.gd draws one quad per MAPH record), chosen per pixel from the painted colour itself (sand, grass, or left alone
// for rock, cliffs and road), so it follows the original art exactly. Kept at world-pixel scale and low contrast: the
// ground must stay quieter than the units on it.
shader_type canvas_item;

// W1: the world pixel comes from the vertex (terrain_layer.gd sits at the origin, so its local vertex is the world
// pixel), not from UV * map size: each record is its own quad with its own texture region.
varying vec2 world_px;
uniform float sand_grain = 0.07;
uniform float sand_ripple = 0.06;
uniform float grass_blades = 0.10;
uniform float macro = 0.06;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(31.0, 17.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_px = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 w = world_px;
	// The map is drawn at 32 x 24 per cell: patterns are squashed vertically by 3/4 so they lie on the ground.
	vec2 g = w * vec2(1.0, 4.0 / 3.0);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float grass = smoothstep(0.0, 0.07, c.g - c.r) * smoothstep(0.04, 0.12, c.g - c.b);
	float sand = smoothstep(0.06, 0.16, c.r - c.b) * smoothstep(0.30, 0.50, lum) * (1.0 - grass);

	// Large, slow variation across panels breaks up the repeated panel pattern (both materials).
	float m = fbm(g / 520.0) - 0.5;
	// Sand: per-pixel grain, wind ripples bent by noise, and a pale / warm drift.
	float grain = hash(floor(w)) - 0.5;
	float bend = fbm(g / 90.0) * 7.0;
	float ripple = sin(dot(g, vec2(0.16, 0.30)) + bend) * smoothstep(0.25, 0.75, noise(g / 160.0));
	vec3 s = c.rgb * (1.0 + sand_grain * grain + sand_ripple * ripple);
	s *= vec3(1.0) + vec3(1.0, 0.5, -0.7) * m * macro * 2.0;
	// Grass: short vertical blade streaks and drier / lusher patches.
	float blades = noise(w * vec2(0.85, 0.22)) * 0.6 + hash(floor(w * vec2(1.0, 0.5))) * 0.4 - 0.5;
	float patch = smoothstep(-0.12, 0.18, fbm(g / 210.0) - 0.5);
	vec3 gr = c.rgb * (1.0 + grass_blades * blades);
	gr = mix(gr, gr * vec3(1.16, 1.07, 0.78), patch * 0.45);
	gr *= 1.0 + m * macro;

	vec3 outc = mix(c.rgb, s, sand);
	outc = mix(outc, gr, grass);
	COLOR = vec4(outc, c.a);   // the terrain sprite has no modulate; COLOR already held the texture
}
