"""Knights construction/production data (milestone 7). Static evidence: PRODUCTION_RESEARCH.md.

Reads ARM/BUI base records and the Building.cfg tables exactly as the executable's loaders do
(ARM loader 0x41b3d0, Building.cfg parser around 0x586...; accessors 0x587830-0x587b70). Nothing is
interpreted beyond the recovered offsets; unknown words are preserved in raw_hex.
"""
import re
import struct

import original_reader as reader

UNITS = ('AHBX', 'AHKX', 'AHMX', 'AHHX')
BUILDINGS = ('BKK0', 'BKK1', 'BAGA', 'BPFL')
RACE = 'H'  # Building.cfg race letter for Knights; CONSTRUCTION rows are H0 (ordinary) / H1 (towers, walls)


def _u16(data, offset):
    return struct.unpack_from('<H', data, offset)[0]


def _i16(data, offset):
    return struct.unpack_from('<h', data, offset)[0]


def building_cfg(source):
    for name, _, body in reader.archive(source / 'Assets/Data/System.xcr'):
        if name == 'Building.cfg':
            return body.translate(reader.cipher_inverse()).decode('latin1')
    raise ValueError('Building.cfg missing from System.xcr')


def _section(text, name):
    start = text.index('[%s]' % name)
    end = text.index('\n[', start + 1)
    return [line for line in text[start:end].splitlines()[1:] if line.strip() and not line.startswith('//')]


def parse_cfg(text):
    """Keep every Knights ('H') row of the four tables used by milestone 7."""
    production = {}
    for line in _section(text, 'PRODUCTION'):
        head, _, tail = line.partition('|')
        tokens = head.split()
        if len(tokens) != 11 or tokens[1] != RACE:
            continue
        tail = tail.split()
        slots = []
        for token in tokens[2:]:
            kind, _, ident = token.partition(':')
            slots.append(dict(kind=kind, id=None if ident == '----' else ident))
        production[tokens[0]] = dict(slots=slots, requires=[None if t == '----' else t for t in tail[:4]],
                                     last_field=tail[4], raw=line)
    construction = {}
    for line in _section(text, 'CONSTRUCTION'):
        tokens = line.split()
        if tokens[0] in ('H0', 'H1'):
            slots = []
            for token in tokens[1:]:
                kind, _, ident = token.partition(':')
                slots.append(dict(kind=kind, id=None if ident == '----' else ident))
            construction[tokens[0]] = slots
    dependencies = {}
    for line in _section(text, 'DEPENDENCIES'):
        head, _, tail = line.partition(':')
        race, _, ident = head.split()[0], None, head.split()[1]
        if race != RACE:
            continue
        parts = tail.split()
        dependencies[ident] = dict(requires=[None if t == '----' else t for t in parts[:4]], last_field=parts[4])
    listing = {}
    for line in _section(text, 'BUILDINGS'):
        tokens = line.split()
        if len(tokens) >= 15 and tokens[1] in BUILDINGS:
            listing[tokens[1]] = dict(index=int(tokens[0]), level_field=tokens[2], army_limit=int(tokens[9]),
                                      name=' '.join(tokens[14:]), raw=line)
    return production, construction, dependencies, listing


def names(source, ids):
    result = {}
    for path in sorted((source / 'Assets').rglob('*.en')):
        text = path.read_text(encoding='latin1')
        for code, name in re.findall(r'<(?:Army|Building)\s+id="(\w{4})"[^>]*?name="([^"]+)"', text):
            if code in ids:
                result.setdefault(code, name)
    return result


def build_production(source, out, entries):
    """entries: importer archive lookup {lowercase entry name: (name, body, provenance)}."""
    inverse = reader.cipher_inverse()
    text = building_cfg(source)
    production, construction, dependencies, listing = parse_cfg(text)
    display = names(source, set(UNITS) | set(BUILDINGS))
    definitions = {}
    for ident in UNITS:
        name, body, provenance = entries[ident.lower() + '.arm']
        d = body.translate(inverse)
        definitions[ident] = dict(
            kind='unit', display_name=display.get(ident, ident), source=provenance, raw_hex=d.hex(),
            movement_type=d[5], footprint=[d[0x38], d[0x39]],
            build_time_seconds=_u16(d, 28),
            cost=[_u16(d, o) for o in (94, 96, 98, 100)],
            population=_i16(d, 200),
            builder_ability=_u16(d, 104), builder_speed=_u16(d, 108),
            base_speed=d[32], hit_points=_u16(d, 36))
    for ident in BUILDINGS:
        name, body, provenance = entries[ident.lower() + '.bui']
        d = body.translate(inverse)
        width, height = d[62], d[63]
        definitions[ident] = dict(
            kind='building', display_name=listing[ident]['name'], source=provenance, raw_hex=d.hex(),
            build_time_seconds=_u16(d, 26),
            cost=[_u16(d, o) for o in (28, 30, 32, 34)],
            footprint=[width, height],
            mask_rows=[_u16(d, 64 + 2 * row) for row in range(height)],
            hit_points=_u16(d, 42), armour=_u16(d, 44),
            army_limit=listing[ident]['army_limit'], level_field=listing[ident]['level_field'])
    keys = set(production) | set(construction) | set(dependencies)
    return dict(
        schema=1, race=RACE, evidence='ARM/BUI base records and Building.cfg; see PRODUCTION_RESEARCH.md',
        definitions=definitions,
        production={k: production[k] for k in sorted(production) if k.startswith(('BKK', 'BAGA', 'BPFL', 'BPSM',
                                                                                  'BPSB', 'BPMA', 'BAV', 'BPSS', 'BPCA'))},
        construction=construction,
        unit_dependencies={k: dependencies[k] for k in sorted(dependencies) if k in UNITS},
        building_list={k: {kk: vv for kk, vv in v.items() if kk != 'raw'} for k, v in listing.items()},
        keep_capacity_table=[2, 5, 10, 15, 20, 30],
        status='Read: Building.cfg and base ARM/BUI records. Research (P/R) rows are retained, not simulated.')
