"""All-races data catalogue (RACES_RESEARCH.md) -> assets/catalogue.json (generated, ignored).

Decodes every ARM/BUI/FEA record (base archives and PatchData.xcr), Army.cfg and every race's rows of the
Building.cfg tables. Field names come from the code that reads them; anything else stays raw (raw_hex,
raw tokens). Parsers mirrored here: Army.cfg 0x584810 (STATUS via 0x5856e0), Building.cfg 0x585ca0,
race letters 0x5873a0, RULES lookups 0x587aa0/0x587b70, ARM loader 0x41b3d0, BUI 0x41af50 (200-byte branch; every shipped BUI is 200 bytes),
FEA 0x41b730. Data interpretation only: no rule is resolved here (see production_data.py for Knights).
"""
import hashlib
import re
import struct
from pathlib import Path

import original_reader as reader

# 0x5873a0: race letter -> index. Unknown letters return 0 (Knight); 'R' -> 14.
RACE_LETTERS = 'HDUBMOEWKFAVPLRG'
# Army.cfg/Building.cfg [HEADINGS] order for indices 0-11 agrees with 0x5873a0; 12-15 differ by file
# (Army.cfg 12 = SIEGE WEAPONS), so the index -> name below follows the letters, not the headings.
RACE_NAMES = ['Knight', 'Dwarf', 'Undead', 'Barbarian', 'Minotaur', 'Orc', 'High Elf', 'Wood Elf',
              'Dark Elf', 'Fey', 'Dark Dwarf', 'Daemon', 'Empire', 'Ssrathi', 'Swarm', 'Plaguelord']
SIDE_ARCHIVES = ['Knights', 'Dwarves', 'Undead', 'Barbarians', 'Minotaurs', 'Orcs', 'HighElves', 'WoodElves',
                 'DarkElves', 'Fey', 'DarkDwarves', 'Daemons', 'Empire', 'Ssrathi', 'Swarm', 'Plaguelords']
SHOOT_TYPES = dict(P=0, I=1, E=2, F=3, M=4, C=5, S=6)            # 0x584810 / 0x585ca0
RESOURCES = dict(G=1, M=2, S=3, C=4)                               # Building.cfg R column, 0x585ca0
SLOT_KINDS = dict(H=-1, T=-2, W=-3, L=-4)                          # [PRODUCTION]/[CONSTRUCTION] slot char
LANES = ('gold', 'metal', 'crystal', 'stone')


def race_index(letter):
    return RACE_LETTERS.index(letter) if letter in RACE_LETTERS else 0


def status_bits(text):
    """Python reading of 0x5856e0 (checked against emulation in emulate_races.py)."""
    bits = 0
    bits |= dict(S=0x20000000, M=0x10000000, L=0x80000000, H=0x40000000).get(text[0], 0)
    bits |= dict(G=0x2000000, N=0x4000000, E=0x8000000).get(text[1], 0)
    bits |= dict(H=1, D=2, U=4, B=0x40, M=0x80, O=0x100, E=8, W=0x10, K=0x20, V=0x800000, A=2,
                 F=0x80000, N=0x1000, X=0x800, C=0x4000, L=0x1000000, R=0x400).get(text[2], 0)
    bits |= dict(X=0x2000, T=0x200).get(text[3], 0)
    bits |= dict(L=0x400000, A=0x200000, F=0x100000).get(text[4], 0)
    bits |= dict(I=0x10000, C=0x20000).get(text[5], 0)
    bits |= 0x8000 if text[6] == 'A' else 0
    bits |= 0x40000 if text[7] == 'M' else 0
    return bits


def status_fields(text):
    """Header-comment names for the STATUS characters; the bit values are the parser's."""
    return dict(size=text[0], alignment=text[1], race_or_kind=text[2], planar=text[3], locomotion=text[4],
                infantry_cavalry=text[5], advanced=text[6] == 'A', missile=text[7] == 'M',
                bits=status_bits(text))


def system_file(source, name):
    for entry, _, body in reader.archive(source / 'Assets/Data/System.xcr'):
        if entry == name:
            return body.translate(reader.cipher_inverse()).decode('latin1')
    raise ValueError(f'{name} missing from System.xcr')


def _sections(text):
    result, current = {}, None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            current = stripped[1:-1]
            result[current] = []
        elif current and stripped and not stripped.startswith('//'):
            result[current].append(line.rstrip())
    return result


def _headings(lines):
    return {int(line.split()[0]): line.split(None, 1)[1] for line in lines}


def _lists(lines):
    lists, heading = {}, None
    for line in lines:
        tokens = line.split()
        if tokens[0] == 'HEADING':
            heading = int(tokens[1])
            lists.setdefault(heading, [])
        else:
            lists[heading].append(tokens[0])
    return {str(k): v for k, v in lists.items()}


def _side_flags(text):
    return [c != '-' for c in text]


def _army_row(line):
    tokens = line.split(None, 9)
    index, code, status, cache, shoot, latency, ai, mana, general = tokens[:9]
    row = dict(index=int(index), code=code, status=status, status_fields=status_fields(status),
               cache_sides=_side_flags(cache), shoot=None, latency=None, ai_flag=ai != '-',
               mana=None, general_flag=general != '-', name=tokens[9] if len(tokens) > 9 else '', raw=line)
    if shoot[0] != '-':
        row['shoot'] = dict(type=SHOOT_TYPES.get(shoot[0]), letter=shoot[0], effect_code=shoot[2:6])
    if latency[0] != '-':
        frame, time = latency.split(':')
        row['latency'] = dict(frame=int(frame), time=int(time))
    if mana[0] != '-':
        a, b = mana.split(':')
        row['mana'] = [int(a), int(b)]
    return row


def army_cfg(source):
    sections = _sections(system_file(source, 'Army.cfg'))
    return dict(headings={str(k): v for k, v in _headings(sections['HEADINGS']).items()},
                armies=[_army_row(line) for line in sections['ARMIES']],
                heroes=[_army_row(line) for line in sections['HEROES']],
                lists=_lists(sections['LIST']),
                field_notes='0x584810 stores: name +0, code +0x18/+0x20, STATUS bits +0x24 (0x5856e0), 16 '
                            'cache-side flags +0x28, shoot flag +0x38/type +0x3a/effect chars +0x3c, latency '
                            '+0x48/+0x4c, AI flag +0x50, general flag +0x51, mana +0x52/+0x54. Consumers of '
                            'cache/latency/AI/mana/general are not traced (Open).')


def _slot(token):
    kind, _, ident = token.partition(':')
    return dict(kind=kind, gate=SLOT_KINDS.get(kind, 0 if kind == '-' else int(kind) if kind.isdigit() else None),
                id=None if ident == '----' else ident)


def _ids(tokens):
    return [None if t == '----' else t for t in tokens]


def building_cfg(source):
    sections = _sections(system_file(source, 'Building.cfg'))
    buildings = []
    for line in sections['BUILDINGS']:
        t = line.split(None, 14)
        if len(t) < 14:
            continue
        shoot = None if t[5][0] == '-' else dict(type=SHOOT_TYPES.get(t[5][0]), letter=t[5][0],
                                                   effect_code=t[5][2:6])
        buildings.append(dict(index=int(t[0]), code=t[1], display_level=int(t[2][0]), data_level=int(t[2][1]),
                              resource=RESOURCES.get(t[3][0], 0), cache_sides=_side_flags(t[4]), shoot=shoot,
                              stop_defeat_sides=_side_flags(t[6]), armies_sides=_side_flags(t[7]),
                              build_sides=_side_flags(t[8]), army_limit=0 if t[9] == '-' else int(t[9]),
                              searchable=t[10] != '-', garrison=0 if t[11] == '-' else int(t[11]),
                              lair=t[12] != '-', shop=t[13] != '-', name=t[14] if len(t) > 14 else '', raw=line))
    production = []
    for line in sections['PRODUCTION']:
        head, _, tail = line.partition('|')
        tokens, tail = head.split(), tail.split()
        production.append(dict(building=tokens[0], race=tokens[1], race_index=race_index(tokens[1]),
                               slots=[_slot(x) for x in tokens[2:]], requires=_ids(tail[:4]),
                               last_field=tail[4], raw=line))
    construction = []
    for line in sections['CONSTRUCTION']:
        tokens = line.split()
        construction.append(dict(row=tokens[0], race=tokens[0][0], race_index=race_index(tokens[0][0]),
                                 slots=[_slot(x) for x in tokens[1:]], raw=line))
    dependencies = []
    for line in sections['DEPENDENCIES']:
        head, _, tail = line.partition(':')
        race, ident = head.split()
        parts = tail.split()
        dependencies.append(dict(race=race, race_index=race_index(race), id=ident, requires=_ids(parts[:4]),
                                 last_field=parts[4], raw=line))
    rules = []
    for line in sections['RULES']:
        t = line.split()
        value = lambda s: None if s.startswith('-') else int(s)
        rules.append(dict(id=t[0], race=t[1], race_index=race_index(t[1]),
                          cost=dict(gold=value(t[2]), metal=value(t[3]), stone=value(t[4]), crystal=value(t[5])),
                          time=value(t[6]), strength=value(t[7]), hits=value(t[8]), speed=value(t[9]),
                          resistance=value(t[10]), pscfm_raw=t[11], damage=value(t[12]), range=value(t[13]),
                          raw=line))
    return dict(headings={str(k): v for k, v in _headings(sections['HEADINGS']).items()},
                buildings=buildings, production=production, construction=construction,
                dependencies=dependencies, rules=rules, lists=_lists(sections['LIST']),
                field_notes='0x585ca0 [BUILDINGS]: levels +9/+0x26, resource +10 (G1 M2 S3 C4), cache +0x2a, '
                            'shoot +0x3a/+0x1e, stop-defeat/armies/build side flags +0x48/+0x58/+0x68, army limit '
                            '+0x3c (0x587800), searchable +0x7a, garrison digit +0x7c (0x5877a0), lair +0x7e, shop +0x7f. '
                            '[PRODUCTION]/[DEPENDENCIES] last field: only its first character is stored (+0x4c / '
                            '+0x18); meaning Open. [RULES] (0x587aa0) replaces cost lanes and time per (id, player '
                            'race); 0x587b70 replaces strength/hits/speed/resistance; PSCFM column is not parsed '
                            '(stored as -1); -1 / "-" means keep the record value.')


def _u16(d, o):
    return struct.unpack_from('<H', d, o)[0]


def _i16(d, o):
    return struct.unpack_from('<h', d, o)[0]


def decode_arm(d):
    """Offsets equal memory offsets in the 0x14c-stride table 0x6e3f18 (straight copy by 0x41b3d0)."""
    return dict(
        movement_type=d[5],                                   # 0x42cc10 / 0x42dd80
        name=d[6:26].split(b'\0')[0].decode('latin1'),        # copied as a string by 0x41b3d0
        build_time_seconds=_u16(d, 0x1c),                     # 0x40b6b0
        extent=[d[0x38], d[0x39]],                            # 0x51bb80, 0x42cc10 (extent), routing
        cost=dict(zip(LANES, [_u16(d, o) for o in (0x5e, 0x60, 0x62, 0x64)])),   # 0x40b6b0
        builder_ability=_u16(d, 0x68), builder_speed=_u16(d, 0x6c),            # 0x40b6b0 (== 50 -> builder)
        command_cost=_i16(d, 0xc8),                           # 0x5348b0 / 0x533dc0
        loader_minimum_one=[_u16(d, o) for o in (0xf8, 0xfa, 0xfc, 0xfe)],    # 0x41b3d0 forces 0 -> 1
        loader_flag_f6=_u16(d, 0xf6),                         # 0x41b3d0 forces nonzero -> 2
        existing_reader_unverified=dict(combat=_u16(d, 0x1e), speed=d[0x20], damage=_u16(d, 0x22),
                                        hit_points=_u16(d, 0x24), armour=_u16(d, 0x28), range=_u16(d, 0x36)))


def decode_bui(d):
    return dict(build_time_seconds=_u16(d, 26), cost=dict(zip(LANES, [_u16(d, o) for o in (28, 30, 32, 34)])),
                hit_points=_u16(d, 42), armour=_u16(d, 44))


def footprint(d, kind):
    """Same offsets as collision.decode_footprint (BUI +62, FEA +24; set mask bit = hole), without its id check."""
    start = 62 if kind == 'buildings' else 24
    w, h = d[start:start + 2]
    result = dict(size=[w, h], masks=list(struct.unpack_from('<16H', d, start + 2))[:min(h, 16)])
    if kind == 'features':
        result['occupancy_bypass'] = d[58] != 0
    return result


def names(source):
    result = {}
    for path in sorted((source / 'Assets').rglob('*.en')):
        text = path.read_text(encoding='latin1')
        for kind, code, name in re.findall(r'<(Army|Building|Feature)\s+id="(\w{4})"[^>]*?name="([^"]+)"', text):
            result.setdefault(code, dict(kind=kind, name=name, file=path.relative_to(source).as_posix()))
    return result


def hero_strings(source):
    text = (source / 'English/XCIStrings.txt').read_text(encoding='latin1')
    strings = dict(re.findall(r'^\[(\d{4}\.\d)\]\s*(.*?)\s*$', text, re.M))
    classes = [strings['%04d.%d' % (8 + i // 8, i % 8)] for i in range(28)]
    races = [strings['0015.%d' % i] for i in range(8)]
    return dict(classes=classes, races_first_eight=races, source='English/XCIStrings.txt [0008.0]-[0011.3], '
                '[0015.x]; class index order assumed equal to string order (Open until a class table is read)')


def records(source):
    """Every ARM/BUI/FEA entry with archive provenance; PatchData.xcr entries kept separately."""
    inverse = reader.cipher_inverse()
    found = {}
    archives = sorted((source / 'Assets').rglob('*.xcr')) + [source / 'PatchData.xcr']
    for path in archives:
        for name, offset, body in reader.archive(path):
            ext = Path(name).suffix.upper()
            if ext not in ('.ARM', '.BUI', '.FEA'):
                continue
            code = Path(name).stem.upper()
            entry = dict(archive=path.relative_to(source).as_posix(), entry=name, offset=offset,
                         sha256=hashlib.sha256(body).hexdigest(), bytes=len(body))
            item = found.setdefault((ext, code), dict(kind=ext[1:].lower(), code=code, sources=[]))
            item['sources'].append(entry)
            d = body.translate(inverse)
            entry['decoded_hex'] = d.hex()
            if path.name == 'PatchData.xcr':
                item['patch'] = d
            else:
                item.setdefault('base', d)
    return found


def help_text(source):
    """English/Help.cfg '[XXXX_Name]' / '[XXXX_Desc]' / '[XXXX_Requ]' rows (tab-separated) for 4-character ids: the names,
    descriptions and requirement lines the production dialog shows for research items (milestone 13)."""
    out = {}
    path = Path(source) / 'English' / 'Help.cfg'
    if not path.exists():
        return out
    for line in path.read_text(encoding='latin1').splitlines():
        if not line.startswith('[') or ']' not in line:
            continue
        key, _, value = line[1:].partition(']')
        ident, _, field = key.partition('_')
        if len(ident) == 4 and field in ('Name', 'Desc', 'Requ'):
            out.setdefault(ident, {})[field.lower()] = value.strip()
    return out


def build_catalogue(source):
    army, building = army_cfg(source), building_cfg(source)
    display = names(source)
    # 0x585970 (STATUS lookup by id) returns the first [ARMIES] row; AOKX appears twice (Goblin Chief, Ice Maiden).
    army_rows, duplicates = {}, {}
    for section in ('armies', 'heroes'):
        for r in army[section]:
            if r['code'] in army_rows:
                duplicates.setdefault(r['code'], [army_rows[r['code']]['raw']]).append(r['raw'])
            army_rows.setdefault(r['code'], dict(r, section=section.upper()))
    army['duplicate_codes'] = duplicates
    building_rows = {r['code']: r for r in building['buildings']}
    units, buildings, features = {}, {}, {}
    for (ext, code), item in sorted(records(source).items()):
        base = item['base']
        patch = item.get('patch')
        differs = None if patch is None else [i for i in range(len(base)) if base[i] != patch[i]]
        effective = patch if patch is not None else base
        record_id = effective[:4].decode('latin1')
        entry = dict(code=code, record_id=record_id, record_id_matches=record_id == code,
                     raw_hex=effective.hex(), display=display.get(code), sources=item['sources'],
                     patch_differs_at=differs,
                     patch_status=None if patch is None else ('identical' if not differs else
                                                              'PatchData.xcr differs; effective record assumed patched (precedence Open)'))
        if ext == '.ARM':
            entry.update(decoded=decode_arm(effective), army_cfg=army_rows.get(code))
            units[code] = entry
        elif ext == '.BUI':
            entry.update(decoded=decode_bui(effective), footprint=footprint(effective, 'buildings'),
                         building_cfg=building_rows.get(code))
            buildings[code] = entry
        else:
            entry.update(footprint=footprint(effective, 'features'))
            features[code] = entry
    for table in (units, buildings, features):
        for entry in table.values():
            for s in entry['sources']:
                s.pop('decoded_hex', None)
    for code, entry in units.items():
        entry['race_index'] = None
        row = entry['army_cfg']
        if row:
            sides = [i for i, flag in enumerate(row['cache_sides']) if flag]
            entry['cache_side_indices'] = sides
    by_race = {}
    for index, letter in enumerate(RACE_LETTERS):
        by_race[RACE_NAMES[index]] = dict(
            index=index, letter=letter, side_archive=SIDE_ARCHIVES[index] + '.xcr',
            construction=[r['row'] for r in building['construction'] if r['race'] == letter],
            production_buildings=[r['building'] for r in building['production'] if r['race'] == letter],
            dependency_ids=[r['id'] for r in building['dependencies'] if r['race'] == letter],
            rules=[r['id'] for r in building['rules'] if r['race'] == letter],
            hero_unit=next((r['code'] for r in army['heroes'] if r['status'][2] == letter), None),
            units_in_archive=sorted(c for c, u in units.items()
                                    if any(Path(s['archive']).stem == SIDE_ARCHIVES[index] for s in u['sources'])),
            buildings_in_archive=sorted(c for c, b in buildings.items()
                                        if any(Path(s['archive']).stem == SIDE_ARCHIVES[index] for s in b['sources'])))
    movement = {}
    for code, entry in units.items():
        key = '%d/%dx%d' % (entry['decoded']['movement_type'], *entry['decoded']['extent'])
        movement.setdefault(key, []).append(code)
    return dict(schema=1, evidence='RACES_RESEARCH.md; parsers and loaders named in field_notes',
                races=by_race, race_letter_rule='0x5873a0: HDUBMOEWKFAVPLRG -> 0..15; unknown letter -> 0',
                heroes=hero_strings(source), army_cfg=army, building_cfg=building, help=help_text(source),
                units=units, buildings=buildings, features=features,
                movement_extent_index=dict(sorted(movement.items())),
                counts=dict(units=len(units), buildings=len(buildings), features=len(features),
                            army_rows=len(army['armies']), hero_rows=len(army['heroes']),
                            production_rows=len(building['production']), construction_rows=len(building['construction']),
                            dependency_rows=len(building['dependencies']), rule_rows=len(building['rules'])))

