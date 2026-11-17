"""RL sheet decoder (EFFECTS_RESEARCH.md section 1), read from the executable's loader and renderer.

Loader 0x487600 -> 0x4879f0 (Read): 'RL' and 'RS' share one file layout; the magic only sets the sheet's format byte
(+0x13 = 1 for RL, 2 for RS). After the 2-byte magic a 0x1014-byte header is read: u32 data size, u16 width, u16 height,
eight 256-entry RGB565 palettes (0x1000 bytes; converted to 555 on 15-bit displays), then 12 bytes (u32, u32, u16 chunk
count, u16) that the loader does not keep. The data (size bytes) follows at file offset 0x1016: a table of
chunk_count * height u32 row offsets (relative to the data start; chunk c, row y at index c * height + y; chunks are
128 pixels wide, 0x487f20 uses x >> 7 and x & 0x7f), then the rows.

Row codes for format 1 (RL; renderer 0x487f20, the cVar7 == 1 branches, Read):
* 0xff n: skip n transparent pixels; 0xff 0xff ends the row.
* any other byte b: one pixel of palette entry b. What the pixel does depends on the sheet's ANI blend bytes
  (+2 pixel mode m, +3 shadow mode s; 0x487f20 reads them when the caller passes -1):
  - m == s == 0: every b is an opaque palette pixel (fast path 0x4884xx).
  - b < 0xef: opaque palette pixel (unless m is >= 0x11 or 8..10, which no slice sheet uses).
  - 0xef <= b <= 0xf6: shadow-mode pixel: s in 1..7 -> table 0xa38b74[s] darkens the screen by level b - 0xee;
    s in 0xb..0xf -> table 0xa38af8[s]; otherwise opaque.
  - 0xf7 <= b <= 0xfe: pixel-mode pixel: m in 1..7 -> 0xa38b74[m] darkens by level b - 0xf6; m in 0xb..0xf ->
    0xa38af8[m]; otherwise opaque.
  Mode 0xd (0xa38b2c = 0x48ccd0 on 565 displays, Read; BATCH1_RESEARCH.md section 4): palette[b] averaged 50/50
  with the screen (floor per 565 channel), written as alpha 128; the Shadow AUXX (13, 13) and the Liche AUMX (1, 13).
  Mode 0xf (0xa38b34 = 0x48ce30 on 565 displays, Read): blends palette[b] over the screen with screen weight
  k = b - 0xef (+ the global level 0xa38b9c, 0 outside fades): result = (src * (16 - k) + dst * k) / 16 per channel,
  i.e. alpha (16 - k) / 16; k >= 16 draws nothing. Mode 0xb (0xa38b24 = 0x485f30) draws nothing. Mode 1
  (0xa38b78 = 0x48b010): screen * L / 8 for L = 1..7, screen * 15/16 for L = 8 (a shadow; black with alpha 1 - L/8).
  Modes 1 and 2-7 are replaced by 0xb unless the "Shadows" (0x70d6b7) / "Lighting Effects" (0x70d6b6) options are on.
G-2 (ART_RESEARCH.md "G-2"): every routine of the 565 table now executed under Unicorn (tools/emulate_blend.py); the
whole-sprite modes 8..10, the additive mode 0x10, modes 0xc / 0xe and lighting 2 / 3 are modelled below (comment block
above pixel_rule), with their error bounds checked against tests/blend_fixtures.json.
The palette index used is the sprite's palette (-1 -> the sheet's default 0); icons (slot 8) always use palette 0.
"""
import struct
from pathlib import Path

from PIL import Image

HEADER = 0x1014
DATA = 2 + HEADER
CHUNK = 128
ALPHA_FIRST = 0xef      # first index of the per-index translucency band
PIXEL_BAND = 0xf7       # first index of the pixel-mode band (0xf7..0xfe)


def c565(v):
    return (((v >> 11) & 31) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31)


def header(data):
    if data[:2] not in (b'RL', b'RS'):
        raise ValueError(f'not an RL/RS sheet: {data[:2]!r}')
    size, w, h = struct.unpack_from('<IHH', data, 2)
    tail = struct.unpack_from('<IIHH', data, 2 + 8 + 0x1000)
    return dict(format=data[:2].decode(), size=size, width=w, height=h, chunks=tail[2], tail=list(tail))


# Blend routines of the 565 table (0x487f20 setup after LAB_004893d9), as RGBA rules. Fits against the routines executed
# under Unicorn (tools/emulate_blend.py -> tests/blend_fixtures.json; test_effects.BlendFixtures checks the error bounds):
# * palette table 0xa38af8[m], m = 0xb..0xf: 0xb (0x485f30) draws nothing; 0xc (0x48cbe0) ~ palette * 11/16 + screen * 5/16
#   (alpha 176, within 2 steps per channel); 0xd (0x48ccd0) 50/50 (alpha 128, within 1 step); 0xe (0x48cd50) ~ palette
#   * 5/16 + screen * 11/16 (alpha 80); 0xf (0x48ce30) palette * (16 - k) / 16 + screen * k / 16, k = b - 0xef.
# * whole-sprite modes 8..10 (pixel mode, else shadow mode): table 0xa38b08[m] = 0xa38af8[m + 4], i.e. 0xc / 0xd / 0xe for
#   every drawn pixel (also the band pixels whose own mode is not 1..7 or 0xb..0xf).
# * mode 0x10 (pixel mode): 0xa38b74[0] (0x48f130) adds the palette colour to the screen, saturating per 565 channel
#   (Emulated: exact), for every pixel; no RGBA alpha rule can express it, so such a sheet is written opaque and drawn
#   with additive blending (art.json "godot_blend": "add").
# * lighting table 0xa38b74[s], s = 1..7, level L = b - 0xee (shadow band) or b - 0xf6 (pixel band), 1..8:
#   1 (0x48b010) screen * L / 8 (15/16 for L = 8): black, alpha 1 - keep; 2 (0x48a120) screen + (-screen) * L / 32:
#   white at alpha L / 32 (within 2 steps for screens without a zero channel: the 16-bit negation borrows across
#   channels, so a black screen stays black); 3 (0x48a330) the same toward red. 4 / 7 (0x48a630 / 0x48ad70) are
#   near-white tints outside that bound and 5 / 6 (0x48a930 / 0x48aaf0) move the channels separately (5: red down,
#   blue up, green kept): no alpha blend, they raise. Of these only 5 is used, by EZ39 (ART_RESEARCH.md G-2 skip list).
# * modes 0x11 and above (0xa38af8[m] = 0xa38b3c..): not traced, unused by every shipped sheet; they raise.
WHOLE_MODES = {8: 0xc, 9: 0xd, 10: 0xe}
PALETTE_ALPHA = {0xc: 176, 0xd: 128, 0xe: 80}
LIGHT_TINT = {2: (255, 255, 255), 3: (255, 0, 0)}
ADD_MODE = 0x10


def _table(mode, b):
    """Palette table 0xa38af8[mode] (0xb..0xf) for index b."""
    if mode == 0xb:
        return None, 0
    if mode == 0xf:
        k = b - ALPHA_FIRST
        return ('pal', round((16 - k) * 255 / 16)) if 0 <= k < 16 else (None, 0)
    return 'pal', PALETTE_ALPHA[mode]


def _light(mode, level):
    """Lighting table 0xa38b74[mode] (1..7) at level 1..8."""
    if mode == 1:
        keep = 15 / 16 if level == 8 else level / 8          # 0x48b010 cases 1..8
        return 'shadow', round((1 - keep) * 255)
    if mode in LIGHT_TINT:
        return 'tint', round(level * 255 / 32), LIGHT_TINT[mode]
    return 'light', None                                      # 5 / 6: per-channel, not an alpha blend


def _whole(pixel_mode, shadow_mode):
    """The whole-sprite routine 0x487f20 selects before drawing (param_13 with bVar4 set), or None."""
    for mode in (pixel_mode, shadow_mode):
        if 8 <= mode <= 10:
            return WHOLE_MODES[mode]
    for mode in (pixel_mode, shadow_mode):
        if mode >= 0x11:
            return mode
    return None


def pixel_rule(b, pixel_mode, shadow_mode):
    """How index b draws: ('pal', alpha), ('shadow', alpha), ('tint', alpha, rgb), ('add', 255), (None, 0), or a kind
    with alpha None for a routine that has no RGBA form."""
    whole = _whole(pixel_mode, shadow_mode)
    if whole is not None and whole >= 0x11:
        return 'pal', None
    add = pixel_mode == ADD_MODE

    def other():                                              # the band's own mode is neither lighting nor a table
        if whole is not None:
            return _table(whole, b)
        return ('add', 255) if add else ('pal', 255)
    if b < ALPHA_FIRST:
        return other()
    mode, level = (shadow_mode, b - 0xee) if b < PIXEL_BAND else (pixel_mode, b - 0xf6)
    if 1 <= mode <= 7:
        return _light(mode, level)
    if 0xb <= mode <= 0xf:
        return _table(mode, b)
    return other()


def rows(data):
    """Yield (y, x, index) for every drawn pixel of an RL sheet."""
    hd = header(data)
    if hd['format'] != 'RL':
        raise ValueError('rows() decodes RL sheets; RS sheets use rle.decode()')
    w, h, n = hd['width'], hd['height'], hd['chunks']
    if n != (w + CHUNK - 1) // CHUNK:
        raise ValueError(f'chunk count {n} does not cover width {w}')
    table = struct.unpack_from(f'<{n * h}I', data, DATA)
    for y in range(h):
        for c in range(n):
            i = DATA + table[c * h + y]
            x = c * CHUNK
            end = min(w, x + CHUNK)
            while x < end:
                b = data[i]
                if b == 0xff:
                    run = data[i + 1]
                    i += 2
                    if run == 0xff:
                        break
                    x += run
                else:
                    yield y, x, b
                    x += 1
                    i += 1


def decode_rl(source, pixel_mode=0, shadow_mode=0, palette=0, shadows=True):
    """RGBA image of an RL sheet. Translucent bands become alpha; shadow-band pixels become black with the darkening
    expressed as alpha (dropped when shadows=False, as with the Shadows option off); lighting tints become their colour
    at the level's alpha. With mode 0x10 every pixel is opaque and hd['additive'] is True (draw with additive blend)."""
    data = Path(source).read_bytes() if not isinstance(source, (bytes, bytearray)) else bytes(source)
    hd = header(data)
    pal = [c565(v) for v in struct.unpack_from('<256H', data, 2 + 8 + 512 * palette)]
    img = Image.new('RGBA', (hd['width'], hd['height']), (0, 0, 0, 0))
    px = img.load()
    rules = [pixel_rule(b, pixel_mode, shadow_mode) for b in range(256)]
    if not shadows:
        rules = [(None, 0) if r[0] == 'shadow' else r for r in rules]
    kinds = set()
    for y, x, b in rows(data):
        rule = rules[b]
        kind, alpha = rule[0], rule[1]
        if kind is None:
            continue
        if alpha is None:
            raise ValueError(f'index {b:#x} uses an unrecovered blend table (modes {pixel_mode}, {shadow_mode})')
        kinds.add(kind)
        if kind == 'pal' or kind == 'add':
            px[x, y] = pal[b] + (alpha,)
        elif kind == 'tint':
            px[x, y] = rule[2] + (alpha,)
        else:
            px[x, y] = (0, 0, 0, alpha)
    if 'add' in kinds and kinds != {'add'}:
        raise ValueError(f'additive and alpha pixels in one sheet (modes {pixel_mode}, {shadow_mode})')
    hd['additive'] = kinds == {'add'}
    return img, hd


def team_mask(source):
    """8-bit mask like rle.team_mask() for an RL sheet: value k + 1 where the pixel uses palette index 224 + k. In RL
    those indices are ordinary pixels (below the 0xef band), so the renderer's ramp copy applies to them as to RS."""
    from rle import TEAM_FIRST, TEAM_COUNT
    data = Path(source).read_bytes() if not isinstance(source, (bytes, bytearray)) else bytes(source)
    hd = header(data)
    mask = bytearray(hd['width'] * hd['height'])
    for y, x, b in rows(data):
        if TEAM_FIRST <= b < TEAM_FIRST + TEAM_COUNT:
            mask[y * hd['width'] + x] = b - TEAM_FIRST + 1
    return Image.frombytes('L', (hd['width'], hd['height']), bytes(mask))


def histogram(data):
    counts = [0] * 256
    for _, _, b in rows(data):
        counts[b] += 1
    return counts
