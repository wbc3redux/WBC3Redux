// Ground scatter wind sway (ground_scatter.gd, ENHANCED_VISUALS.md). The atlas has two rows: row 0 (tufts, scrub) bends
// at the top and stays rooted at the bottom; row 1 (pebbles, contact shadows) never moves.
shader_type canvas_item;

uniform float amount = 1.4;    // world pixels at the tip

void vertex() {
	float top = 1.0 - clamp(UV.y * 2.0, 0.0, 1.0);
	vec2 wp = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + wp.x * 0.004 - wp.y * 0.002);
	float s = sin(TIME * 1.7 + wp.x * 0.035 + wp.y * 0.021) + 0.45 * sin(TIME * 3.1 + wp.x * 0.071);
	VERTEX.x += (s * 0.6 + 0.5) * amount * gust * top;
}
