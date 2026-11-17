"""Desert Sands encounter data (ENCOUNTERS_RESEARCH.md) -> assets/encounters.json (generated, ignored).

* Mausoleum quests: Quest.xcr entry "Bzma.dat" (enciphered with the archive cipher; 0x52edb0 loads "<building id>.dat"
  from Quest.xcr into a 0x5080-byte buffer): header id +0, count +6, enabled bytes from +8, records of 0x66 bytes from
  +0xd0. Field names are the ones read by 0x52edb0 (offer), 0x43dde0 (eligibility), 0x43d3a0 (completion), 0x43d560
  (rewards) and 0x527660 (accept); everything else stays in raw_hex. English/Quest.cfg "[BZMA_###_*]" lines carry the text.
* ANI records (nine 26-byte slots, ani.decode_ani) of the units the encounters use: AMJX (Gnoll), ACCA (Camel), ACTU
  (Turtle), AHHX (Knight hero). Slot 2 word +0x18 is the hit entry (COMBAT_RESEARCH.md). Sheets are not imported.
"""
import re
import struct
from pathlib import Path

import original_reader as reader
from ani import decode_ani

QUEST_BUILDINGS = ['Bzma', 'Bmsh']   # S-2: the Shrine, the other searchable building (Building.cfg)
UNIT_ANI = ['AMJX', 'ACCA', 'ACTU', 'AHHX']
RECORD, FIRST = 0x66, 0xd0
TYPES = {0: 'deliver_resource', 1: 'kill_units', 2: 'raze_buildings', 3: 'convert_buildings', 4: 'never', 5: 'kill_heroes',
         6: 'kill_unit_type', 7: 'destroy_building_type', 8: 'capture_building_type', 9: 'own_building_type'}


def _i16(d, o):
    return struct.unpack_from('<h', d, o)[0]


def _fourcc(d, o):
    raw = d[o:o + 4]
    return raw.split(b'\0')[0].decode('latin1')


def quest_record(index, enabled, r):
    return dict(index=index, enabled=enabled, time_limit_s=_i16(r, 0), word_02=_i16(r, 2), portrait=_fourcc(r, 4), name_index=r[9],
        type=_i16(r, 0xa), type_name=TYPES.get(_i16(r, 0xa), 'unknown'), count=_i16(r, 0xc), target=_fourcc(r, 0xe),
        reward_resources=bool(r[0x1e]), reward_unit=bool(r[0x1f]), reward_group=bool(r[0x20]), reward_research=bool(r[0x21]),
        reward_item=bool(r[0x22]),
        resources=[_i16(r, 0x24), _i16(r, 0x26), _i16(r, 0x28), _i16(r, 0x2a)],          # gold, metal, crystal, stone (0x1fd message)
        unit=_fourcc(r, 0x2c), unit_xp=_i16(r, 0x32), group_count=_i16(r, 0x34), group_unit=_fourcc(r, 0x36), group_xp=_i16(r, 0x3c),
        group_named=r[0x3e], group_name_index=r[0x3f], research=_fourcc(r, 0x40), item=_i16(r, 0x4e), raw_hex=r.hex())


def quests(source):
    out = {}
    text = (source / 'English' / 'Quest.cfg').read_bytes().decode('latin1')
    for building in QUEST_BUILDINGS:
        body = None
        for name, offset, data in reader.archive(source / 'Quest.xcr'):
            if name.lower() == building.lower() + '.dat':
                body = data.translate(reader.cipher_inverse())
        if body is None:
            raise ValueError(f'{building}.dat missing from Quest.xcr')
        count = _i16(body, 6)
        records = []
        for i in range(count):
            r = body[FIRST + i * RECORD:FIRST + (i + 1) * RECORD]
            entry = quest_record(i, body[8 + i], r)
            for key in ('NAME', 'NEWQ', 'CONT', 'CMPL', 'REPT', 'INST'):
                m = re.search(r'\[%s_%03d_%s\]\t([^\r\n]*)' % (building.upper(), i, key), text)
                if m: entry[key.lower()] = m.group(1)
            records.append(entry)
        out[building.upper()] = dict(source='Quest.xcr/%s.dat' % building, header_id=_fourcc(body, 0), count=count, records=records)
    return out


def unit_ani(source):
    wanted = {code.lower() + '.ani': code for code in UNIT_ANI}
    found = {}
    for path in sorted((source / 'Assets').rglob('*.xcr')):
        for name, offset, body in reader.archive(path):
            code = wanted.get(name.lower())
            if code is None or code in found: continue
            ani = decode_ani(body)
            slots = [dict(slot=s['slot'], suffix=s['suffix'], enabled=s['enabled'], frames=s['frame_count'], frame_size=s['frame_size'],
                          pivot=s['pivot'], word_18=s['unknown_words']['0x18']) for s in ani['slots']]
            found[code] = dict(archive=path.relative_to(source).as_posix(), entry=name, slots=slots, decoded_hex=ani['decoded_hex'])
    missing = [c for c in UNIT_ANI if c not in found]
    if missing:
        raise ValueError(f'ANI records missing: {missing}')
    return found


# 0x434e90's table 0x6085d8 (strings read from the image, Read): the naming set files, indexed by Quest record +0x3f.
NAMING_SETS = ['Standard', 'GenericEvil', 'KnightlyMale', 'KnightlyFemale', 'HumanMale', 'HumanFemale', 'ElvenMale',
               'ElvenFemale', 'DwarvenMale', 'DwarvenFemale', 'WizardMale', 'WizardFemale', 'BarbarianMale',
               'BarbarianFemale', 'Draconic', 'Fey']


def naming_sources(source):
    return {source / 'NamingSets' / (name + '.nam') for name in NAMING_SETS}


def naming_sets(source):
    """Each set's lines as 0x435060 reads them in text mode (fgets, CR LF -> LF, the LF removed)."""
    out = []
    for name in NAMING_SETS:
        text = (source / 'NamingSets' / (name + '.nam')).read_bytes().decode('latin1').replace(chr(13) + chr(10), chr(10))
        out.append(dict(file='NamingSets/' + name + '.nam', lines=text.split(chr(10))))
    return out


def build_encounters(source):
    return dict(schema=1, quests=quests(source), ani=unit_ani(source), naming_sets=naming_sets(source),
        evidence='ENCOUNTERS_RESEARCH.md: quest record fields from 0x52edb0/0x43dde0/0x43d3a0/0x43d560; ANI slots via ani.decode_ani')


if __name__ == '__main__':
    import json, sys
    root = Path(sys.argv[1] if len(sys.argv) > 1 else r'G:\Games\Warlords Battlecry 3')
    data = build_encounters(root)
    print(json.dumps({k: (len(v) if isinstance(v, dict) else v) for k, v in data.items()}))
    print({c: [(s['suffix'], s['frames'], s['word_18']) for s in a['slots'] if s['enabled']] for c, a in data['ani'].items()})
