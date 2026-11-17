// Enhanced visuals weather (weather_fx.gd, ENHANCED_VISUALS.md): a deliberate modern change, off by default. One
// full-screen pass on a canvas layer above the colour grade and below the HUD. Everything is made here from noise and
// hashed cells (no textures, no particles on the CPU) and anchored to world coordinates, so it scrolls with the map and
// never reads or depends on the terrain renderer. Blended over the frame; it only adds haze, streaks and flakes.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 screen_px = vec2(1920.0, 1080.0);
uniform vec2 view_px = vec2(1920.0, 930.0);       // the world view above the control panel
uniform float view_left = 0.0;                    // window pixels of the side bar left of the world view
uniform vec2 view_origin = vec2(0.0);             // world pixel at the window's top-left
uniform float world_per_px = 1.0;
uniform float time_s = 0.0;
uniform int kind = 0;                             // 0 none, 1 rain, 2 snow, 3 fog, 4 sandstorm
uniform float strength = 1.0;                     // Weather Strength: 0.55 light, 1.0 heavy

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
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

// Premultiplied "over": a layer of colour c and alpha a on top of what is gathered so far.
void over(inout vec4 acc, vec3 c, float a) {
	acc.rgb = c * a + acc.rgb * (1.0 - a);
	acc.a = a + acc.a * (1.0 - a);
}

// Falling streaks in cells of `cell` world pixels along `dir` (unit, mostly down): one streak per occupied cell.
float streaks(vec2 w, vec2 dir, vec2 cell, float speed, float len, float width, float density, float seed) {
	vec2 side = vec2(dir.y, -dir.x);
	vec2 q = vec2(dot(w, side), dot(w, dir) - time_s * speed) / cell;
	vec2 id = floor(q);
	vec2 f = fract(q);
	float h = hash(id + seed);
	if (h > density) return 0.0;
	float x = abs(f.x - (0.15 + 0.7 * hash(id + seed + 3.1))) * cell.x;
	float y = (f.y - hash(id + seed + 7.7) * 0.5) * cell.y;
	float body = step(0.0, y) * step(y, len) * (y / len);       // brightest at the leading end
	return body * (1.0 - smoothstep(width * 0.5, width, x));
}

// Splash rings on the ground: a small squashed ring that grows and fades, at a random spot and time per cell.
float splashes(vec2 w, float density) {
	vec2 cell = vec2(42.0, 32.0);
	vec2 id = floor(w / cell);
	if (hash(id + 41.0) > density) return 0.0;
	vec2 at = (id + vec2(0.2, 0.2) + 0.6 * vec2(hash(id + 5.0), hash(id + 9.0))) * cell;
	float t = fract(time_s * 1.6 + hash(id + 13.0));
	vec2 d = (w - at) * vec2(1.0, 2.2);
	float r = 1.0 + 6.0 * t;
	return (1.0 - t) * (1.0 - smoothstep(0.0, 1.2, abs(length(d) - r)));
}

// Soft flakes drifting down with a sway; one per occupied cell.
float flakes(vec2 w, float cell, float speed, float radius, float density, float seed) {
	vec2 q = w / cell;
	q.y -= time_s * speed / cell;
	vec2 id = floor(q);
	if (hash(id + seed) > density) return 0.0;
	float sway = sin(time_s * (0.8 + hash(id + seed + 2.0)) + hash(id + seed + 4.0) * 6.28) * 0.18;
	vec2 at = vec2(0.2 + 0.6 * hash(id + seed + 6.0) + sway, 0.2 + 0.6 * hash(id + seed + 8.0));
	float d = length((fract(q) - at) * cell);
	return 1.0 - smoothstep(radius * 0.15, radius, d);
}

void fragment() {
	vec2 px = SCREEN_UV * screen_px;
	vec2 world = view_origin + px * world_per_px;
	vec4 acc = vec4(0.0);
	// Slow gusts: the weather swells and eases over about a minute.
	float gust = 0.8 + 0.2 * sin(time_s * 0.09) * sin(time_s * 0.031 + 1.3);
	float s = strength * gust;
	if (kind == 1) {
		// Rain: an overcast tint, three depths of streaks (the nearer ones move a little faster with the camera), splashes.
		over(acc, vec3(0.10, 0.13, 0.19), 0.30 * s);
		vec2 dir = normalize(vec2(0.22, 1.0));
		for (int i = 0; i < 3; i++) {
			float k = float(i);
			vec2 w = world + view_origin * (0.15 * k);
			float a = streaks(w, dir, vec2(9.0 + 3.0 * k, 90.0 + 30.0 * k), 620.0 + 180.0 * k, 22.0 + 10.0 * k,
				1.2 + 0.4 * k, 0.45 * s + 0.12, 11.0 * k);
			over(acc, vec3(0.86, 0.90, 0.97), a * (0.36 + 0.12 * k));
		}
		over(acc, vec3(0.86, 0.90, 0.97), splashes(world, 0.5 * s) * 0.5);
	} else if (kind == 2) {
		// Snow: a cold pale veil and three depths of flakes.
		over(acc, vec3(0.86, 0.90, 0.98), 0.18 * s);
		for (int i = 0; i < 3; i++) {
			float k = float(i);
			vec2 w = world + view_origin * (0.12 * k) + vec2(time_s * (6.0 + 5.0 * k), 0.0);
			float a = flakes(w, 20.0 + 12.0 * k, 26.0 + 16.0 * k, 2.0 + 1.2 * k, 0.60 * s + 0.15, 23.0 * k);
			over(acc, vec3(1.0), a * (0.70 + 0.10 * k));
		}
	} else if (kind == 3) {
		// Fog: a thin haze everywhere and drifting banks, anchored to the map.
		vec2 drift = vec2(time_s * 7.0, time_s * 2.0);
		float banks = fbm((world + drift) / 520.0);
		float wisps = fbm((world - drift * 1.7) / 190.0 + 3.0);
		float d = 0.12 + 0.48 * smoothstep(0.38, 0.78, banks) + 0.12 * smoothstep(0.5, 0.8, wisps);
		over(acc, vec3(0.80, 0.82, 0.84), clamp(d * s, 0.0, 0.7));
	} else if (kind == 4) {
		// Sandstorm: a warm haze in long moving bands, and fast grains blowing across.
		float bands = fbm(vec2((world.x - time_s * 260.0) / 900.0, world.y / 260.0));
		float puffs = fbm(vec2((world.x - time_s * 420.0) / 300.0, world.y / 140.0) + 5.0);
		// Darker and redder than the desert it blows over, so it reads on sand.
		float d = 0.22 + 0.34 * smoothstep(0.35, 0.75, bands) + 0.12 * smoothstep(0.45, 0.8, puffs);
		over(acc, mix(vec3(0.66, 0.46, 0.27), vec3(0.80, 0.62, 0.40), bands), clamp(d * s, 0.0, 0.62));
		vec2 dir = normalize(vec2(1.0, 0.12));
		for (int i = 0; i < 2; i++) {
			float k = float(i);
			vec2 w = world + view_origin * (0.15 * k);
			// streaks() falls along dir; with dir sideways the grains blow left to right.
			float a = streaks(w, dir, vec2(7.0 + 3.0 * k, 120.0 + 40.0 * k), 700.0 + 200.0 * k, 26.0 + 12.0 * k,
				1.1 + 0.4 * k, 0.40 * s + 0.08, 31.0 * k);
			over(acc, vec3(0.96, 0.86, 0.66), a * (0.40 + 0.12 * k));
		}
	}
	// Only over the world view (not the side bars; the control panel's layer is above anyway).
	vec2 v = px - vec2(view_left, 0.0);
	float inside = step(0.0, v.x) * step(v.x, view_px.x) * step(v.y, view_px.y);
	acc *= inside;
	COLOR = acc.a > 0.0001 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.0);
}
