"""Deterministic decoder for the original interface data (UI_RESEARCH.md).

War4Int.xci  read by FUN_0045aa10: 0x134 header, then element (0x11c), panel (0x1734),
             screen (0xec) and string-section (0x2c) tables, counts at header 0x24..0x30.
War4Gfx.xcg  read by FUN_00466970: 0x54 header, then bitmap records of 0x84 (count at 0x1c) and cursor records
             of 0x11c (count at 0x20; parity pass 1, UI_RESEARCH.md "Cursors").
XCIStrings.txt supplies the text: section N of the XCI string table is [NNNN.i].
Unknown bytes are preserved as hex so nothing is silently dropped.
"""
import io
import re
import struct

ELEMENT_SIZE, PANEL_SIZE, CONTROL_SIZE, SCREEN_SIZE, SECTION_SIZE = 0x11c, 0x1734, 0x5c, 0xec, 0x2c
BITMAP_SIZE, XCG_HEADER, CURSOR_SIZE = 0x84, 0x54, 0x11c
MAX_CONTROLS = (PANEL_SIZE - 0x34) // CONTROL_SIZE
# Type (+0x24) and subtype (+0x28) numbering; names follow the element-name prefixes.
TYPES = {0: 'button', 1: 'edit', 2: 'scrollbar', 3: 'listbox', 4: 'label', 5: 'progress', 6: 'primitive', 7: 'image'}
SUBTYPES = {0: 'radio', 1: 'toggle', 2: 'bitmap_states', 3: 'bitmap_text', 4: 'text', 5: 'hotspot',
            6: 'single_line', 7: 'multi_line', 8: 'vertical', 9: 'horizontal', 10: 'list', 12: 'text',
            14: 'bar', 18: 'line', 19: 'box', 20: 'shadow', 21: 'fill', 22: 'static', 23: 'animated', 25: 'overlay'}
RESOLUTIONS = ['640x480', '800x600', '1024x768', '1280x1024']  # FUN_00463b20 index (800->1, 1024->2, 1280/1600->3)


def cstr(data):
    return data.split(b'\0')[0].decode('latin1')


def i32(data, offset):
    return struct.unpack_from('<i', data, offset)[0]


def rgb(value):
    return [(value >> 16) & 255, (value >> 8) & 255, value & 255]


def element_fields(kind, e):
    """Per-type fields. Offsets copied by FUN_0045c1b0 are 'read'; the rest are labelled by usage."""
    if kind == 0:
        # FUN_0045c9a0: font numbers per state (+0x58 normal, +0x5c hover/pressed, +0x60 disabled).
        # FUN_0045c880: subtype 2 source x = column (+0x118) * width. Post-load: label = string(section +0xc4, index +0xe8); second string = (+0xec, +0x110).
        return dict(fonts=[i32(e, 0x58), i32(e, 0x5c), i32(e, 0x60)],
                    font_names=[cstr(e[0x64:0x84]), cstr(e[0x84:0xa4]), cstr(e[0xa4:0xc4])],
                    label=dict(section=i32(e, 0xc4), section_name=cstr(e[0xc8:0xe8]), index=i32(e, 0xe8)),
                    alt_label=dict(section=i32(e, 0xec), section_name=cstr(e[0xf0:0x110]), index=i32(e, 0x110)),
                    unknown_0x114=e[0x114], column=i32(e, 0x118))
    if kind == 1:
        return dict(colours=[rgb(i32(e, o)) for o in (0x34, 0x38, 0x3c)], text=dict(index=i32(e, 0x64), section=cstr(e[0x44:0x64])),
                    font=cstr(e[0x6c:0x8c]), max_length=i32(e, 0x68), id_base=i32(e, 0x90), scrollbar=cstr(e[0x94:0xb4]))
    if kind == 2:
        return dict(range_max=i32(e, 0x5c), step=i32(e, 0x60))
    if kind == 3:
        return dict(rows=i32(e, 0x34), columns=i32(e, 0x38), fonts=[cstr(e[0x3c:0x5c]), cstr(e[0x5c:0x7c])],
                    colours=[rgb(i32(e, o)) for o in (0xa0, 0xa4, 0xa8)], id_base=i32(e, 0xb0),
                    scrollbar=cstr(e[0xb4:0xd4]), item_metrics=[i32(e, 0xd4), i32(e, 0xd8), i32(e, 0xdc)])
    if kind == 4:
        # FUN_0045c1b0 case 4 copies +0x34 (section), +0x58 (index), +0x5c (font number).
        return dict(text=dict(section=i32(e, 0x34), section_name=cstr(e[0x38:0x58]), index=i32(e, 0x58)),
                    font=i32(e, 0x5c), font_name=cstr(e[0x60:0x80]))
    if kind == 5:
        return dict(font=cstr(e[0x6c:0x8c]), range=[i32(e, 0x90), i32(e, 0x94)])
    if kind == 6:
        return dict(colours=[rgb(i32(e, 0x34)), rgb(i32(e, 0x38))])
    if kind == 7:
        return dict(frame_size=[i32(e, 0x60), i32(e, 0x64)])
    return {}


def decode_xci(data):
    assert data.startswith(b'xci File 1.00'), 'not an xci file'
    total_controls, n_elements, n_panels, n_screens, n_sections = struct.unpack_from('<5I', data, 0x20)
    out = dict(header=dict(unknown_0x20=total_controls, graphics_file=cstr(data[0x34:0x134])),
               elements=[], panels=[], screens=[], sections=[])
    offset = 0x134
    for _ in range(n_elements):
        e = data[offset:offset + ELEMENT_SIZE]
        kind, sub = i32(e, 0x24), i32(e, 0x28)
        out['elements'].append(dict(id=i32(e, 0), name=cstr(e[4:0x24]), type=kind, type_name=TYPES.get(kind, 'unknown'),
            subtype=sub, subtype_name=SUBTYPES.get(sub, 'unknown'), size=[i32(e, 0x2c), i32(e, 0x30)],
            bitmap_id=i32(e, 0x34) if kind in (0, 2, 5, 7) else None,
            bitmap=cstr(e[0x38:0x58]) if kind in (0, 2, 5, 7) else '', **element_fields(kind, e), raw=e.hex()))
        offset += ELEMENT_SIZE
    for _ in range(n_panels):
        p = data[offset:offset + PANEL_SIZE]
        count = i32(p, 0x30)
        assert 0 <= count <= MAX_CONTROLS, ('control count', count)
        controls = []
        for j in range(count):
            c = p[0x34 + j * CONTROL_SIZE:0x34 + (j + 1) * CONTROL_SIZE]
            controls.append(dict(element_id=i32(c, 0), name=cstr(c[4:0x24]), instance=i32(c, 0x24),
                position=[i32(c, 0x28), i32(c, 0x2c)], layer=i32(c, 0x30), initial=i32(c, 0x34),
                editor_text=cstr(c[0x38:0x58]), tab=i32(c, 0x58)))
        out['panels'].append(dict(id=i32(p, 0), name=cstr(p[4:0x24]), position=[i32(p, 0x24), i32(p, 0x28)],
            flags=list(p[0x2c:0x30]), controls=controls))
        offset += PANEL_SIZE
    for _ in range(n_screens):
        s = data[offset:offset + SCREEN_SIZE]
        out['screens'].append(dict(id=i32(s, 0), name=cstr(s[4:0x24]), background_type=i32(s, 0x24),
            backgrounds={RESOLUTIONS[k]: dict(value=i32(s, 0x28 + 4 * k), bitmap=cstr(s[0x38 + 0x20 * k:0x58 + 0x20 * k]))
                         for k in range(4)},
            flags=list(s[0xc4:0xcc]), pad=cstr(s[0xcc:0xec])))
        offset += SCREEN_SIZE
    for _ in range(n_sections):
        t = data[offset:offset + SECTION_SIZE]
        count, pool = struct.unpack_from('<hxxI', t, 0x24)
        # +0x28 is a file offset into the trailing pool of 0x50-byte strings (compiled copy of XCIStrings.txt).
        embedded = [cstr(data[pool + 0x50 * k:pool + 0x50 * (k + 1)]) for k in range(count)] if count > 0 else []
        out['sections'].append(dict(index=i32(t, 0), name=cstr(t[4:0x24]), count=count, pool_offset=pool, embedded=embedded))
        offset += SECTION_SIZE
    out['header']['table_end'] = offset
    out['header']['trailing_bytes'] = len(data) - offset
    return out


def decode_cursor(r):
    """One 0x11c cursor record as FUN_00466970 copies it into the graphics object (+0x43a40, slot = record order + 1):
    +0 id, +4 name, +0x24 bitmap id, +0x28 bitmap name, +0x48/+0x4c frame size, +0x50 frame count, +0x54/+0x58 hotspot
    (FUN_0046c9b0 subtracts it from the mouse position), +0x5c 16 frames of (x, y, delay ms; 0 = hold)."""
    count = i32(r, 0x50)
    return dict(id=i32(r, 0), name=cstr(r[4:0x24]), bitmap_id=i32(r, 0x24), bitmap=cstr(r[0x28:0x48]),
                size=[i32(r, 0x48), i32(r, 0x4c)], hotspot=[i32(r, 0x54), i32(r, 0x58)],
                frames=[[i32(r, 0x5c + 12 * k), i32(r, 0x60 + 12 * k), i32(r, 0x64 + 12 * k)] for k in range(min(count, 16))])


def decode_xcg(data):
    assert data.startswith(b'xcg File 1.00'), 'not an xcg file'
    total, size, n_bitmaps = struct.unpack_from('<3I', data, 0x14)
    assert size == len(data), 'xcg size field mismatch'
    n_cursors = struct.unpack_from('<I', data, 0x20)[0]
    bitmaps = []
    # FUN_00466970 reads exactly `count` bitmap records into slots 1..count (the loop runs from 1 while < count + 1).
    for k in range(n_bitmaps):
        r = data[XCG_HEADER + k * BITMAP_SIZE:XCG_HEADER + (k + 1) * BITMAP_SIZE]
        if not cstr(r[4:0x24]):
            continue
        bitmaps.append(dict(id=i32(r, 0), name=cstr(r[4:0x24]), archive=cstr(r[0x24:0x4c]), file=cstr(r[0x4c:0x74]),
                            values=[i32(r, 0x74), i32(r, 0x78), i32(r, 0x7c)], flags=list(r[0x80:0x84])))
    base = XCG_HEADER + n_bitmaps * BITMAP_SIZE
    cursors = [decode_cursor(data[base + k * CURSOR_SIZE:base + (k + 1) * CURSOR_SIZE]) for k in range(n_cursors)]
    return dict(header=dict(total_records=total, bitmap_count=n_bitmaps, other_counts=list(struct.unpack_from('<3I', data, 0x20))),
                bitmaps=bitmaps, cursors=cursors)


def parse_strings(text, sections):
    """FUN_0045aa10 reads one line per string in section order and drops the 9-character
    '[NNNN.i] ' prefix; the bracketed numbers are not used (they agree with the order anyway)."""
    lines = [line for line in text.splitlines() if line.strip()]
    assert len(lines) == sum(max(s['count'], 0) for s in sections), 'XCIStrings line count differs from the XCI table'
    strings, cursor = {}, 0
    for section in sections:
        strings[section['index']] = [line[9:] for line in lines[cursor:cursor + max(section['count'], 0)]]
        cursor += max(section['count'], 0)
    return strings


def parse_screen_help(text):
    return dict(re.findall(r'^\[([A-Z0-9_]+)\]\t(.*?)\r?$', text, re.M))


def parse_font_ini(text):
    fonts, current = {}, None
    for line in text.splitlines():
        line = line.split('//')[0].strip()
        header = re.match(r'\[FONT\.(\d+)\]', line)
        if header:
            current = {}
            fonts[int(header.group(1))] = current
        elif current is not None and '=' in line:
            key, value = line.split('=', 1)
            current[key.strip()] = int(value) if value.strip().lstrip('-').isdigit() else value.strip()
    # XCI elements refer to fonts by their [FONT.N] number.
    return {str(n): dict(name=f.get('Name'), file=f.get('File'), size=f.get('PointSize'), baseline=f.get('Baseline'),
            colour=[f.get('ColorRed', 255), f.get('ColorGreen', 255), f.get('ColorBlue', 255)],
            style=f.get('Style', 'Normal')) for n, f in sorted(fonts.items()) if 'Name' in f}


def key_bitmap(body):
    """BMP -> RGBA with magenta (255,0,255) transparent (colour key observed in the art; see UI_RESEARCH.md)."""
    from PIL import Image, ImageChops
    with Image.open(io.BytesIO(body)) as image:
        rgb_image = image.convert('RGB')
    r, g, b = rgb_image.split()
    magenta = ImageChops.multiply(ImageChops.multiply(r.point(lambda v: 255 if v == 255 else 0),
                                                      g.point(lambda v: 255 if v == 0 else 0)),
                                  b.point(lambda v: 255 if v == 255 else 0))
    keyed = Image.composite(Image.new('RGB', rgb_image.size), rgb_image, magenta)
    keyed.putalpha(ImageChops.invert(magenta))
    return keyed


def build_ui(source, out, archives):
    """Write ui_layout.json, keyed ui_bm_*.png and ui_font_*.ttf into out. archives: lower-case entry -> (name, body, provenance)."""
    xci = decode_xci((source / 'War4Int.xci').read_bytes())
    xcg = decode_xcg((source / 'War4Gfx.xcg').read_bytes())
    strings = parse_strings((source / 'English/XCIStrings.txt').read_text(encoding='latin1'), xci['sections'])
    help_text = parse_screen_help((source / 'English/ScreenHelp.txt').read_text(encoding='latin1'))
    fonts = parse_font_ini((source / 'English/Font.ini').read_text(encoding='latin1'))
    by_name = {b['name']: b for b in xcg['bitmaps']}
    used = {e['bitmap'] for e in xci['elements'] if e['bitmap']}
    used |= {v['bitmap'] for s in xci['screens'] for v in s['backgrounds'].values() if v['bitmap']}
    exported = {}
    for name in sorted(used):
        record = by_name.get(name)
        if not record or record['file'].lower() not in archives:
            continue
        entry, body, provenance = archives[record['file'].lower()]
        image = key_bitmap(body)
        filename = f'ui_bm_{name}.png'
        image.save(out / filename, optimize=False)
        exported[name] = dict(file=filename, size=list(image.size), source=provenance)
    for font in sorted({f['file'] for f in fonts.values() if f['file']}):
        (out / f'ui_font_{font.rsplit(".", 1)[0]}.ttf').write_bytes((source / 'Fonts' / font).read_bytes())
    missing = sorted(n for n in used if n not in exported)
    layout = dict(schema=1, resolutions=RESOLUTIONS, xci=xci, xcg=xcg, fonts=fonts, exported_bitmaps=exported,
                  missing_bitmaps={n: by_name[n] if n in by_name else None for n in missing},
                  strings={str(k): v for k, v in sorted(strings.items())},
                  screen_help=help_text)
    return layout
