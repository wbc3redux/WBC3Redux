// Enhanced visuals colour grade (enhanced_visuals.gd, ENHANCED_VISUALS.md): a deliberate modern change, off by default.
// Runs on a canvas layer above the world and below the HUD, so only the battlefield is graded. Kept gentle: the sheets'
// own painted light stays the main light; team colours and fog must still read as before.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 screen_px = vec2(1920.0, 1080.0);
uniform vec2 view_px = vec2(1920.0, 930.0);       // the world view above the control panel
uniform float view_left = 0.0;                    // window pixels of the side bar left of the world view
uniform float amount = 1.0;                       // the Colour Grade setting: 0.6 subtle, 1.0 full
uniform vec2 view_origin = vec2(0.0);             // world pixel at the window's top-left
uniform float world_per_px = 1.0;
uniform float time_s = 0.0;
uniform vec3 warm = vec3(1.045, 1.0, 0.93);
uniform vec3 cool = vec3(0.93, 0.97, 1.06);
uniform float saturation = 1.08;
uniform float contrast = 1.05;
uniform float cloud_strength = 0.11;
uniform float vignette = 0.20;

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

void fragment() {
	vec3 original = texture(screen_tex, SCREEN_UV).rgb;
	vec3 c = original;
	vec2 px = SCREEN_UV * screen_px;
	vec2 world = view_origin + px * world_per_px;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// Split toning: warm light, cooler shade; then saturation and a soft contrast curve around mid grey.
	c *= mix(cool, warm, smoothstep(0.15, 0.75, l));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	// Slow cloud shadows, anchored to the map (they drift with the wind, not with the camera).
	float cloud = fbm(world / 700.0 + vec2(time_s * 0.012, time_s * 0.004));
	c *= 1.0 - cloud_strength * smoothstep(0.48, 0.72, cloud);
	// Vignette on the world view only.
	vec2 d = (px - vec2(view_left, 0.0) - view_px * 0.5) / (view_px * 0.5);
	c *= 1.0 - vignette * pow(clamp(length(d * vec2(0.85, 1.0)) - 0.35, 0.0, 1.0), 1.6);
	COLOR = vec4(mix(original, clamp(c, 0.0, 1.0), amount), 1.0);
}
