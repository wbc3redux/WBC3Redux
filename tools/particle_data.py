"""Particle definitions (map wave 5, MAPS_RESEARCH.md "Wave 5"): the original's Assets/Particles/*.xml as read by 0x486010.

0x486010 (Read) fills one 0x104-byte entry of the table at 0xa28720 per file: the <Particle> attributes, then one element
per child. Integer attributes go through 0x5aa4e0 (atoi; a missing attribute is 0); both alpha values are stored as
translucency levels 15 - alpha * 15 / 100. The EFFH map records name an entry by its `id` (0x486980 compares +0x20).
`OFFSETS` is the entry layout; tools/emulate_particles.py writes `entry_bytes` into the emulated table.
"""
import json
import struct
import xml.etree.ElementTree as ET

# field -> (offset, struct format) in the 0x104-byte entry (0x486010).
OFFSETS = {
    'name': (0x00, '32s'), 'id': (0x20, '20s'), 'graphic': (0x34, '4s'), 'size': (0x3a, 'h'), 'temporary': (0x3c, 'B'),
    'lifetime': (0x40, 'i'),
    'total': (0x44, 'h'), 'max': (0x46, 'h'), 'release': (0x48, 'h'), 'interval': (0x4c, 'i'), 'life': (0x50, 'i'),
    'frame': (0x54, 'i'), 'red': (0x58, 'h'), 'green': (0x5a, 'h'), 'blue': (0x5c, 'h'), 'alpha': (0x60, 'i'),
    'anim_start': (0x64, 'i'), 'anim_end': (0x68, 'i'), 'anim_frame': (0x6c, 'i'), 'anim_red': (0x70, 'i'),
    'anim_green': (0x74, 'i'), 'anim_blue': (0x78, 'i'), 'anim_alpha': (0x7c, 'i'),
    'perimeter': (0x80, 'B'), 'circle': (0x81, 'B'),
    'emitter_x': (0x84, 'i'), 'emitter_y': (0x88, 'i'), 'emitter_varx': (0x8c, 'i'), 'emitter_vary': (0x90, 'i'),
    'anim_emitter_start': (0x94, 'i'), 'anim_emitter_end': (0x98, 'i'), 'anim_emitter_x': (0x9c, 'i'),
    'anim_emitter_y': (0xa0, 'i'), 'anim_emitter_varx': (0xa4, 'i'), 'anim_emitter_vary': (0xa8, 'i'),
    'velocity_x': (0xac, 'i'), 'velocity_y': (0xb0, 'i'), 'velocity_varx': (0xb4, 'i'), 'velocity_vary': (0xb8, 'i'),
    'anim_velocity_start': (0xbc, 'i'), 'anim_velocity_end': (0xc0, 'i'), 'anim_velocity_x': (0xc4, 'i'),
    'anim_velocity_y': (0xc8, 'i'), 'anim_velocity_varx': (0xcc, 'i'), 'anim_velocity_vary': (0xd0, 'i'),
    'force_x': (0xd4, 'i'), 'force_y': (0xd8, 'i'),
    'anim_force_start': (0xdc, 'i'), 'anim_force_end': (0xe0, 'i'), 'anim_force_x': (0xe4, 'i'), 'anim_force_y': (0xe8, 'i'),
    'pforce_x': (0xec, 'i'), 'pforce_y': (0xf0, 'i'),
    'anim_pforce_start': (0xf4, 'i'), 'anim_pforce_end': (0xf8, 'i'), 'anim_pforce_x': (0xfc, 'i'), 'anim_pforce_y': (0x100, 'i'),
}
ENTRY = 0x104
# element -> {attribute: field} (0x486010's element chain).
ELEMENTS = {
    'Number': dict(total='total', max='max', release='release', interval='interval', life='life'),
    'Graphics': dict(frame='frame', red='red', green='green', blue='blue', alpha='alpha'),
    'AnimGraphics': dict(frame='anim_frame', red='anim_red', green='anim_green', blue='anim_blue', alpha='anim_alpha',
                         start='anim_start', end='anim_end'),
    'Emitter': dict(x='emitter_x', y='emitter_y', varx='emitter_varx', vary='emitter_vary'),
    'AnimEmitter': dict(x='anim_emitter_x', y='anim_emitter_y', varx='anim_emitter_varx', vary='anim_emitter_vary',
                        start='anim_emitter_start', end='anim_emitter_end'),
    'Velocity': dict(x='velocity_x', y='velocity_y', varx='velocity_varx', vary='velocity_vary'),
    'AnimVelocity': dict(x='anim_velocity_x', y='anim_velocity_y', varx='anim_velocity_varx', vary='anim_velocity_vary',
                         start='anim_velocity_start', end='anim_velocity_end'),
    'Force': dict(x='force_x', y='force_y'),
    'AnimForce': dict(x='anim_force_x', y='anim_force_y', start='anim_force_start', end='anim_force_end'),
    'PForce': dict(x='pforce_x', y='pforce_y'),
    'AnimPForce': dict(x='anim_pforce_x', y='anim_pforce_y', start='anim_pforce_start', end='anim_pforce_end'),
}


def atoi(text):
    """The CRT atoi 0x5dab55: optional sign, leading digits; anything else is 0."""
    text = (text or '').strip()
    sign, digits = 1, ''
    if text[:1] in '+-' and text:
        sign, text = (-1 if text[0] == '-' else 1), text[1:]
    for ch in text:
        if not ch.isdigit():
            break
        digits += ch
    return sign * int(digits) if digits else 0


def translucency(alpha):
    return 15 - int(alpha * 15 / 100)      # C division truncates toward zero


def parse(body):
    """One particle file -> field dict (0x486010)."""
    root = ET.fromstring(body)
    assert root.tag == 'Particle', root.tag
    d = {k: 0 for k in OFFSETS}
    d['name'], d['id'] = root.get('name'), root.get('id')
    d['graphic'] = root.get('graphic')[:4]
    d['temporary'] = int(root.get('temporary') == 'yes')
    d['lifetime'], d['size'] = atoi(root.get('lifetime')), atoi(root.get('size'))
    for child in root:
        fields = ELEMENTS.get(child.tag)
        if fields is None:
            continue
        for attribute, field in fields.items():
            d[field] = atoi(child.get(attribute))
        if child.tag == 'Emitter':
            d['perimeter'] = int(child.get('perimeter') == 'yes')
            d['circle'] = int(child.get('circle') == 'yes')
    d['alpha'], d['anim_alpha'] = translucency(d['alpha']), translucency(d['anim_alpha'])
    return d


def entry_bytes(d):
    out = bytearray(ENTRY)
    for field, (offset, fmt) in OFFSETS.items():
        value = d[field]
        if fmt.endswith('s'):
            value = value.encode('latin1')
        struct.pack_into('<' + fmt, out, offset, value)
    return bytes(out)


def read_all(game):
    """id -> definition for every Assets/Particles/*.xml (sorted by file name, as the loader's directory scan)."""
    result = {}
    for path in sorted((game / 'Assets' / 'Particles').glob('*.xml')):
        d = parse(path.read_bytes())
        d['source'] = 'Assets/Particles/' + path.name
        result[d['id']] = d
    return result


OUTPUT = 'particles.json'


def sources(game):
    return set((game / 'Assets' / 'Particles').glob('*.xml'))


def build(game, out):
    """assets/particles.json: every definition by id (map wave 5: the EFFH map effects name them)."""
    data = dict(schema=1, loader='0x486010 (Read): Assets/Particles/*.xml; alpha values as translucency 15 - alpha * 15 / 100',
                definitions=read_all(game))
    (out / OUTPUT).write_text(json.dumps(data, indent=1, sort_keys=True) + '\n', encoding='utf-8')
    return data
