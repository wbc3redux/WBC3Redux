// Team colour of original RS sheets (ART_RESEARCH.md): the sprite renderer 0x487f20 copies the owner's 15-entry ramp
// over palette entries 224..238. The importer stores those pixels in an 8-bit mask (value k + 1 for entry 224 + k).
shader_type canvas_item;

uniform sampler2D team_mask : filter_nearest;
uniform bool team_enabled = false;
uniform vec4 ramp[15];
// Enhanced visuals (deliberate modern change, ENHANCED_VISUALS.md, off by default): the sheets' shadow band (black with
// the darkening as alpha, tools/rl.py) is feathered over its neighbours and tinted, so units and buildings sit softer on
// the ground. Body pixels are never changed.
uniform bool soft_shadows = false;
uniform vec3 shadow_tint = vec3(0.07, 0.05, 0.09);
uniform float shadow_strength = 1.0;

// P-2 (EFFECTS_RESEARCH.md "P-2" item 1): a building whose sprite cell the local player cannot see is drawn with palette 6
// of its sheet (0x53b2b7..0x53b2d9). Every one of the 2,269 sheets in the archives has palette 6 = the grey of palette 0
// in 565 terms: g6' = (2 r5 + g6 + 2 b5) / 3 (integer), r5' = b5' = g6' >> 1 (checked on all 580,864 entries). The
// imported sheets are palette 0 expanded 565 -> 8 bit (rle.c565), so the 565 values are recovered exactly and the grey is
// expanded the same way. The team ramp is copied over entries 224..238 of the palette in use (0x48833d.. writes the
// active palette), so team pixels keep the owner's colour.
uniform bool fog_palette = false;

varying vec4 modulate;

vec3 palette6(vec3 c) {
	float r5 = round(c.r * 31.0);
	float g6 = round(c.g * 63.0);
	float b5 = round(c.b * 31.0);
	float grey = floor((2.0 * r5 + g6 + 2.0 * b5) / 3.0 + 0.0001);
	float half = floor(grey / 2.0 + 0.0001);
	// rle.c565: x * 255 // 31 (or // 63), back to 0..1.
	return vec3(floor(half * 255.0 / 31.0 + 0.0001), floor(grey * 255.0 / 63.0 + 0.0001), floor(half * 255.0 / 31.0 + 0.0001)) / 255.0;
}

void vertex() {
	modulate = COLOR;
}

bool is_shadow(vec4 s) {
	return s.a < 0.995 && max(s.r, max(s.g, s.b)) < 0.02;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (soft_shadows && is_shadow(c)) {
		// Weighted mean of the shadow alpha over a 5 x 5 tent, skipping body pixels (so no halo around them).
		float sum = 0.0;
		float weight = 0.0;
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				vec4 s = texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE);
				float w = (3.0 - abs(float(x))) * (3.0 - abs(float(y)));
				if (is_shadow(s)) { sum += s.a * w; weight += w; }
				else if (s.a >= 0.995) { sum += c.a * w; weight += w; }   // under a body pixel the shadow continues
			}
		}
		float a = weight > 0.0 ? sum / weight : c.a;
		c = vec4(shadow_tint, clamp(a * shadow_strength, 0.0, 0.92));
	}
	if (fog_palette && c.a > 0.0) {
		c.rgb = palette6(c.rgb);
	}
	if (team_enabled) {
		int k = int(round(texture(team_mask, UV).r * 255.0)) - 1;
		if (k >= 0 && k < 15) {
			c = vec4(ramp[k].rgb, c.a);
		}
	}
	COLOR = c * modulate;
}
