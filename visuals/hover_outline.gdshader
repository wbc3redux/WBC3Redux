// Enhanced visuals hover outline (ENHANCED_VISUALS.md, row 11 of the plan): a thin soft line just outside the body of the
// unit or building under the cursor. Drawn by its own sprite with the same sheet frame; the body and the shadow band
// (black pixels whose alpha is the darkening, tools/rl.py) stay untouched, the outline follows only the body.
shader_type canvas_item;

uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);   // the frame in UV
uniform vec4 line_colour : source_color = vec4(1.0, 0.95, 0.75, 0.7);
uniform float width = 1.5;                          // sheet pixels

bool inside(vec2 uv) {
	return uv.x >= region.x && uv.y >= region.y && uv.x <= region.x + region.z && uv.y <= region.y + region.w;
}

bool solid(vec4 s) {
	return s.a > 0.5 && max(s.r, max(s.g, s.b)) > 0.02;
}

void fragment() {
	if (inside(UV) && solid(texture(TEXTURE, UV))) {
		COLOR = vec4(0.0);
	} else {
		float hit = 0.0;
		for (int k = 0; k < 12; k++) {
			float a = 6.2831853 * float(k) / 12.0;
			vec2 o = vec2(cos(a), sin(a)) * TEXTURE_PIXEL_SIZE;
			vec2 far = UV + o * width;
			vec2 near = UV + o * width * 0.5;
			if (inside(far) && solid(texture(TEXTURE, far))) hit = 1.0;
			if (inside(near) && solid(texture(TEXTURE, near))) hit = 1.0;
		}
		COLOR = vec4(line_colour.rgb, line_colour.a * hit);
	}
}
