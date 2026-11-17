shader_type canvas_item;
// The main-menu hover float's blend level (0x58f5b0 -> glyph blitter 0x592b70, Read from the disassembly). The original's
// glyph pixel holds its coverage n (0..15) in the high nibble; at blend level L the blitter skips n <= L and draws the
// rest through jump table 0x59327c at index n - L - 1, whose colour weight is (index + 3) / 16, solid from index 13. So
// the faint rim goes first and the core dims: at level 9 only n >= 10 shows, at most 8/16; at 15 nothing shows.
// The level comes in the vertex colour's alpha (L / 15).
void fragment() {
	float coverage = texture(TEXTURE, UV).a;
	float n = clamp(floor(coverage * 15.0 + 0.5), 0.0, 15.0);
	float level = floor(COLOR.a * 15.0 + 0.5);
	float shown = step(level + 0.5, n);
	COLOR = vec4(COLOR.rgb, shown * min(16.0, n - level + 2.0) / 16.0);
}
