// B1-3 day / night (simulation/day_night.gd, B1_3_RESEARCH.md): the palette lighting level the original's renderer
// draws the battlefield with (*DAT_00a38b98, 0x495c30). Every palette entry has eight levels built by the palette
// builder's 565 branch (Emulated, tests/day_night_fixtures.json "palette"); a dusk steps 0 -> 4 -> 5 -> 3 (night), a dawn
// back. Here the same integer operations run on the finished world view: each pixel is taken to 565 as the palette
// builder does (red and blue >> 3, green >> 2), lit, and widened again. Only drawn while the level is not 0, on a canvas
// layer above the world and below the HUD. Presentation (labelled): the original lights palette entries before blending;
// on blended pixels (shadows, translucent sheets) the order differs by at most a 565 step.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int level = 0;

int scale_down(int x, int n) {      // 0x48b010 cases 5..7
	if (n == 5) return (x - ((((x & 0xf800) * 3) >> 3) & 0xf800) - ((((x & 0x7e0) * 3) >> 3) & 0x7e0) - (((x & 0x1f) * 3) >> 3)) & 0xffff;
	if (n == 6) { int u = x >> 2; return (x - (u & 0x3800) - (u & 0x1e0) - (u & 7)) & 0xffff; }
	if (n == 7) { int u = x >> 3; return (x - (u & 0x1800) - (u & 0xe0) - (u & 3)) & 0xffff; }
	return x;
}

int blue_shift(int x, int n) {      // 0x48a930 cases 2 / 3
	if (n == 2) return (x + (((-x) >> 3) & 3) - ((x >> 4) & 0x800)) & 0xffff;
	if (n == 3) return (((((-x) & 0x1f) * 3) >> 4) - ((((x & 0xf800) * 3) >> 5) & 0xf800) + x) & 0xffff;
	return x;
}

int red_shift(int x, int n) {       // 0x48a330 cases 2 / 3
	if (n == 2) return ((((-x) >> 4) & 0x800) - ((x >> 4) & 0x60) - ((x >> 4) & 1) + x) & 0xffff;
	if (n == 3) {
		int r = ((((-x) & 0xf800) * 3) >> 5) & 0xf800;
		int g = (((x & 0x7e0) * 3) >> 5) & 0x7e0;
		int b = ((x & 0x1f) * 3) >> 5;
		return (r - g - b + x) & 0xffff;
	}
	return x;
}

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	int r8 = int(clamp(c.r * 255.0 + 0.5, 0.0, 255.0));
	int g8 = int(clamp(c.g * 255.0 + 0.5, 0.0, 255.0));
	int b8 = int(clamp(c.b * 255.0 + 0.5, 0.0, 255.0));
	int x = ((r8 >> 3) << 11) | ((g8 >> 2) << 5) | (b8 >> 3);
	if (level == 3) x = blue_shift(scale_down(x, 5), 3);
	else if (level == 4) x = red_shift(scale_down(x, 7), 3);
	else if (level == 5) x = blue_shift(red_shift(scale_down(x, 6), 2), 2);
	COLOR = vec4(float((x >> 11) & 31) / 31.0, float((x >> 5) & 63) / 63.0, float(x & 31) / 31.0, 1.0);
}
