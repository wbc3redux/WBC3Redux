// Enhanced visuals effect boost (ENHANCED_VISUALS.md, rows 4 and 5 of the plan): an additive copy of a fire, explosion or
// magic frame over the original one, plus a small halo (a bloom limited to the effect itself, never the whole scene).
// The halo samples only inside the frame's own region of the sheet, so neighbouring frames never bleed in.
shader_type canvas_item;
render_mode blend_add;

uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);   // the frame in UV: x, y, width, height
uniform float sharp = 0.2;                         // the frame added once more (brighter core)
uniform float halo = 0.35;                         // the soft spread around the bright parts
uniform float radius = 5.0;                        // halo radius in sheet pixels

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 lo = region.xy + TEXTURE_PIXEL_SIZE * 0.5;
	vec2 hi = region.xy + region.zw - TEXTURE_PIXEL_SIZE * 0.5;
	vec3 spread = vec3(0.0);
	float total = 0.0;
	for (int ring = 1; ring <= 2; ring++) {
		float r = radius * float(ring) / 2.0;
		for (int k = 0; k < 8; k++) {
			float a = 6.2831853 * float(k) / 8.0 + float(ring) * 0.39;
			vec4 s = texture(TEXTURE, clamp(UV + vec2(cos(a), sin(a)) * r * TEXTURE_PIXEL_SIZE, lo, hi));
			float w = 1.0 / float(ring);
			spread += s.rgb * s.a * w;
			total += w;
		}
	}
	spread /= total;
	// Only bright, coloured parts bloom (fire cores, sparks, magic); grey smoke and dust stay as they are.
	float lum = dot(spread, vec3(0.299, 0.587, 0.114));
	float sat = max(spread.r, max(spread.g, spread.b)) - min(spread.r, min(spread.g, spread.b));
	float bright = smoothstep(0.45, 0.9, lum) * smoothstep(0.12, 0.35, sat);
	float own_sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	vec3 add = c.rgb * c.a * sharp * smoothstep(0.12, 0.35, own_sat) + spread * halo * bright;
	COLOR = vec4(add, 1.0) * COLOR;
}
