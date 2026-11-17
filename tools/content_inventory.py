"""W0 content inventory (CONTENT_EXPANSION_PLAN.md): what every race, unit, building, research item and skirmish map
still lacks in the rebuild -> assets/content_inventory.json (generated, ignored).

Research only: reads the importer's generated assets (catalogue.json, art.json), the rebuild's data and GDScript, the
installation's archives and scenarios, and the decompile; it writes nothing else. Labels follow RACES_RESEARCH.md:
values copied from files are Read; nothing here is executed under emulation.

* Race rosters: a race's buildings are its Building.cfg [PRODUCTION] buildings plus every id of its [CONSTRUCTION] rows;
  its units and research are every A / P / R id in those buildings' slots plus its dependency ids (catalogue
  races[*].dependency_ids). Shared ids (temples, siege, dragons) belong to every race that can make them.
* Hard-coded ids: a 32-bit hex constant in the decompile whose little-endian bytes spell a catalogue unit, building or
  feature id or a research id of simulation/research_prices.json (the 0x4391c0 table) - the scan of RACES_RESEARCH.md
  2.3, now regenerated. Functions are split at the decompile's "//==== <address> <name>" headers.
* Art: the slots art.json decoded per code, against the slots each code's ANI enables and the RLE sheets the archives
  hold for it ('RL'-format sheets flagged). G-2: slots on art.json's reasoned skip list count as accounted for
  ("skipped"), so "art complete" = every enabled slot decoded or skip-listed.
* Rebuild references: quoted 4-character ids in the game's GDScript (project root and simulation/, not tests or tools),
  a proxy for "has id-specific code in the rebuild".
* Maps: every Scenario/*.SCN chunk count, size, sides (SIDH: record[0] == 1 and x >= 0, race s16 +2 as
  skirmish_setup.gd reads it), terrain codes and the Assets/Terrain archive each comes from, raw TER materials per cell
  (sampled as collision.py does), and object codes without a catalogue record or decoded art.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import struct

import original_reader as reader
from ani import decode_ani, SUFFIXES
from collision import decode_ter, sample_ter

PROJECT = Path(__file__).resolve().parents[1]
DEFAULT_DECOMPILE = Path(r'G:\Tools\ghidra_work\wbc3_decomp.c')
SCHEMA = 1
ID = re.compile(r'[A-Z][A-Z0-9]{3}')
HEX = re.compile(r'\b0x([0-9a-fA-F]{8})\b')
HEADER = re.compile(r'^//==== ([0-9a-fA-F]{8}) (\S+)', re.M)
GD_ID = re.compile(r'"([A-Z][A-Z0-9]{3})"')
# Hubs already named in RACES_RESEARCH.md 2.3 / PRODUCTION_RESEARCH.md 4 (Read there); others are listed unnamed.
HUB_NOTES = {'0x4391c0': 'research price table', '0x436500': 'research completion effects',
             '0x444980': 'per-race unit roster (switch on player race)', '0x4382d0': 'unit predicates',
             '0x426350': 'unit predicates / hot-keyed abilities', '0x4d3200': 'control panel (UI)',
             '0x500830': 'unit predicates', '0x42ace0': 'swing damage multipliers, animals', '0x557d90': 'unit predicates',
             '0x570f80': 'unit predicates', '0x40b6b0': 'cost function', '0x42a0d0': 'hero type by race',
             '0x533dc0': 'command limit', '0x4a50f0': 'scenario towers by owner race'}
# Hero unit type by race index, 0x42a0d0's switch (Read, RACES_RESEARCH.md 11a; the Barbarian/Minotaur pair as the code
# has it). Heroes are not in any Building.cfg row, so the roster adds them.
HERO_TYPES = ['AHHX', 'ADHX', 'AUHX', 'AMHX', 'ABHX', 'AOHX', 'AEHX', 'AWHX', 'AKHX', 'AFHX', 'AAHX', 'AVHX', 'APHX',
              'ALHX', 'ARHX', 'AHH1']


def sha_file(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def code_of(value):
    raw = struct.pack('<I', value)
    if not all(0x30 <= b <= 0x5a for b in raw):
        return None
    text = raw.decode('ascii')
    return text if ID.fullmatch(text) else None


def hardcoded_ids(decompile, known):
    """id -> {function address: occurrences}, for every known id written as a hex constant."""
    text = decompile.read_text(encoding='latin1')
    heads = [(m.start(), '0x' + m.group(1).lstrip('0').lower()) for m in HEADER.finditer(text)]
    found = collections.defaultdict(collections.Counter)
    for index, (start, address) in enumerate(heads):
        end = heads[index + 1][0] if index + 1 < len(heads) else len(text)
        for match in HEX.finditer(text, start, end):
            code = code_of(int(match.group(1), 16))
            if code in known:
                found[code][address] += 1
    return {code: dict(sorted(by.items())) for code, by in sorted(found.items())}


def rebuild_references():
    refs = collections.defaultdict(set)
    for path in sorted(PROJECT.glob('*.gd')) + sorted((PROJECT / 'simulation').glob('*.gd')):
        for code in GD_ID.findall(path.read_text(encoding='utf-8')):
            refs[code].add(path.relative_to(PROJECT).as_posix())
    return {code: sorted(files) for code, files in refs.items()}


def archive_art(game):
    """code -> enabled ANI slots and the RLE sheets present per suffix (format RLE or RL), first archive wins."""
    art = collections.defaultdict(lambda: dict(ani_slots=None, sheets={}, archives=set()))
    for path in sorted((game / 'Assets').rglob('*.xcr')):
        rel = path.relative_to(game).as_posix()
        for name, _, body in reader.archive(path):
            stem, _, ext = name.rpartition('.')
            ext = ext.lower()
            if len(stem) < 4 or not ID.fullmatch(stem[:4].upper()):
                continue
            code, suffix = stem[:4].upper(), stem[4:].lower()
            if ext == 'ani' and suffix == '' and len(body) == 234:
                entry = art[code]
                entry['archives'].add(rel)
                if entry['ani_slots'] is None:
                    try:
                        entry['ani_slots'] = [s['slot'] for s in decode_ani(body)['slots'] if s['enabled']]
                    except ValueError as error:
                        # ani.decode_ani rejects slots it cannot validate; keep the enabled flags and list the code.
                        plain = body.translate(reader.cipher_inverse())
                        entry['ani_slots'] = [s for s in range(9) if plain[s * 26] == 1]
                        entry['ani_error'] = str(error)
            elif ext == 'rle' and suffix in SUFFIXES:
                entry = art[code]
                entry['archives'].add(rel)
                slot = SUFFIXES.index(suffix)
                entry['sheets'].setdefault(str(slot), 'RL' if body[:2] == b'RL' else 'RLE')
    return {code: dict(ani_slots=v['ani_slots'] or [], sheets=dict(sorted(v['sheets'].items())),
                       archives=sorted(v['archives']), ani_error=v.get('ani_error'))
            for code, v in sorted(art.items())}


def art_status(code, decoded, available):
    """Decoded slots (art.json sheets / icons) against the slots the ANI enables."""
    entry = decoded['units'].get(code) or decoded['buildings'].get(code) or {}
    done = sorted(int(s) for s in entry.get('sheets', {}))
    if code in decoded.get('icons', {}):
        done = sorted(set(done) | {8})
    skipped = sorted({int(r['slot']) for r in decoded.get('skip_list', []) if r['code'] == code} - set(done))
    have = available.get(code, dict(ani_slots=[], sheets={}))
    wanted = have['ani_slots']
    return dict(ani_slots=wanted, ani_error=have.get('ani_error'), decoded_slots=done, skipped_slots=skipped,
                missing_slots=[s for s in wanted if s not in done and s not in skipped],
                rl_sheets=sorted(int(s) for s, f in have['sheets'].items() if f == 'RL'),
                undecoded_rl_sheets=entry.get('undecoded_rl_sheets', []))


def race_rosters(catalogue):
    cfg = catalogue['building_cfg']
    rosters = {}
    for name, race in sorted(catalogue['races'].items(), key=lambda kv: kv[1]['index']):
        letter = race['letter']
        buildings = set(race['production_buildings'])
        for row in cfg['construction']:
            if row['race'] == letter:
                buildings |= {s['id'] for s in row['slots'] if s['id']}
        ids = set(race['dependency_ids']) | {HERO_TYPES[race['index']]}
        for row in cfg['production']:
            if row['race'] == letter:
                ids |= {s['id'] for s in row['slots'] if s['id']}
        buildings |= {i for i in ids if i[0] == 'B'}
        rosters[name] = dict(index=race['index'], letter=letter, hero_unit=HERO_TYPES[race['index']],
                             side_archive=race['side_archive'], buildings=sorted(buildings),
                             units=sorted(i for i in ids if i[0] == 'A'),
                             research=sorted(i for i in ids if i[0] in 'PR'),
                             other_ids=sorted(i for i in ids if i[0] not in 'ABPR'))
    return rosters


def unit_row(code, catalogue, decoded, available, hard, refs):
    record = catalogue['units'].get(code)
    if record is None:
        return dict(code=code, in_catalogue=False)
    d, army = record.get('decoded', {}), record.get('army_cfg') or {}
    return dict(code=code, in_catalogue=True, name=d.get('name'), movement_type=d.get('movement_type'),
                extent=d.get('extent'), shoot=army.get('shoot'), mana=army.get('mana'),
                stats_status='existing_reader_unverified' if 'existing_reader_unverified' in d else 'named',
                art=art_status(code, decoded, available), hardcoded_in=sorted(hard.get(code, {})),
                rebuild_refs=refs.get(code, []))


def building_row(code, catalogue, decoded, available, hard, refs):
    record = catalogue['buildings'].get(code)
    if record is None:
        return dict(code=code, in_catalogue=False)
    cfg = record.get('building_cfg') or {}
    return dict(code=code, in_catalogue=True, name=(record.get('display') or {}).get('name') or cfg.get('name'),
                shoot=cfg.get('shoot'), footprint=(record.get('footprint') or {}).get('size'),
                art=art_status(code, decoded, available), hardcoded_in=sorted(hard.get(code, {})),
                rebuild_refs=refs.get(code, []))


def research_row(code, prices, effects, hard, refs):
    return dict(code=code, price_table=code in prices, effect_ported=code in effects,
                hardcoded_in=sorted(hard.get(code, {})), rebuild_refs=refs.get(code, []))


def terrain_sets(game):
    sets = {}
    for path in sorted((game / 'Assets' / 'Terrain').glob('*.xcr')):
        for name, _, body in reader.archive(path):
            if name.lower().endswith('.ter'):
                sets.setdefault(name[:4].upper(), (path.stem, body))
    return sets


def scenario(path, catalogue, decoded, races_by_index, ter):
    data = path.read_bytes()
    players, width, height = struct.unpack_from('<III', data, 0x48)
    parsed = list(reader.chunks(data))
    counts = collections.Counter(tag for tag, _, _, _ in parsed)
    sides, terrain, objects = [], [], dict(buildings=collections.Counter(), features=collections.Counter(),
                                           armies=collections.Counter())
    for tag, _, _, body in parsed:
        if tag == 'SIDH':
            for index in range(len(body) // 44):
                record = body[index * 44:(index + 1) * 44]
                x, y = struct.unpack_from('<ii', record, 20)
                if record[0] == 1 and x >= 0:
                    race = struct.unpack_from('<h', record, 2)[0]
                    sides.append(dict(side_index=index, cell=[x, y], race=race, race_name=races_by_index.get(race)))
        elif tag in ('BLDH', 'ARMH', 'FTRH'):
            objects[dict(BLDH='buildings', ARMH='armies', FTRH='features')[tag]][body[:4].decode('ascii')] += 1
        elif tag == 'MAPH':
            for index in range(len(body) // 16):
                record = body[index * 16:(index + 1) * 16]
                terrain.append((record[:4].decode('ascii').upper(), struct.unpack_from('<I', record, 4)[0] >> 16))
    cols = (width + 9) // 10
    tiles, missing_ter = {}, set()
    for code in {c for c, _ in terrain}:
        if code in ter:
            tiles[code] = decode_ter(ter[code][1], code)
        else:
            missing_ter.add(code)
    materials = collections.Counter()
    for y in range(height):
        for x in range(width):
            code, quadrant = terrain[(y // 10) * cols + x // 10]
            if code in tiles:
                materials[sample_ter(tiles[code], x % 10, y % 10, quadrant)[0][1]] += 1
    known_buildings, known_units = set(catalogue['buildings']), set(catalogue['units'])
    known_features = set(catalogue['features'])
    art_buildings, art_units = set(decoded['buildings']), set(decoded['units'])
    return dict(file=path.name, sha256=hashlib.sha256(data).hexdigest(), players=players, size_cells=[width, height],
                chunk_counts=dict(sorted(counts.items())), sides=sides,
                terrain_sets=sorted({ter[c][0] for c, _ in terrain if c in ter}),
                terrain_codes=len({c for c, _ in terrain}), missing_ter=sorted(missing_ter),
                materials={str(k): v for k, v in sorted(materials.items())},
                objects={k: dict(sorted(v.items())) for k, v in objects.items()},
                buildings_without_record=sorted(set(objects['buildings']) - known_buildings),
                armies_without_record=sorted(set(objects['armies']) - known_units),
                features_without_record=sorted(set(objects['features']) - known_features),
                buildings_without_art=sorted(set(objects['buildings']) - art_buildings),
                armies_without_art=sorted(set(objects['armies']) - art_units))


def build(game=None, decompile=DEFAULT_DECOMPILE, assets=None):
    game = game or reader.game_root(PROJECT)
    assets = assets or PROJECT / 'assets'
    catalogue = load(assets / 'catalogue.json')
    decoded = load(assets / 'art.json')
    prices = load(PROJECT / 'simulation' / 'research_prices.json')['prices']
    effects = load(PROJECT / 'simulation' / 'research_effects.json')['effects']
    known = set(catalogue['units']) | set(catalogue['buildings']) | set(catalogue['features']) | set(prices)
    hard = hardcoded_ids(decompile, known)
    refs = rebuild_references()
    available = archive_art(game)
    rosters = race_rosters(catalogue)

    races = {}
    for name, roster in rosters.items():
        units = [unit_row(c, catalogue, decoded, available, hard, refs) for c in roster['units']]
        buildings = [building_row(c, catalogue, decoded, available, hard, refs) for c in roster['buildings']]
        research = [research_row(c, prices, effects, hard, refs) for c in roster['research']]
        rows = units + buildings
        summary = dict(units=len(units), buildings=len(buildings), research=len(research),
                       art_complete=sum(1 for r in rows if r.get('in_catalogue') and r['art']['ani_slots']
                                        and not r['art']['missing_slots']),
                       art_none=sum(1 for r in rows if r.get('in_catalogue') and not r['art']['decoded_slots']),
                       art_skipped_slots=sum(len(r['art']['skipped_slots']) for r in rows if r.get('in_catalogue')),
                       # Icons (slot 8) are always RL and rl.py decodes them; count the other RL sheets only.
                       rl_sheets=sum(sum(1 for s in r['art']['rl_sheets'] if s != 8)
                                     for r in rows if r.get('in_catalogue')),
                       hardcoded_ids=sum(1 for r in rows + research if r.get('hardcoded_in')),
                       hardcoded_without_rebuild_ref=sum(1 for r in rows + research
                                                         if r.get('hardcoded_in') and not r.get('rebuild_refs')),
                       research_effects_ported=sum(1 for r in research if r['effect_ported']),
                       flyers=sum(1 for r in units if r.get('movement_type') == 1),
                       water_types=sum(1 for r in units if r.get('movement_type') in (2, 3)),
                       large=sum(1 for r in units if (r.get('extent') or [1])[0] > 1),
                       ranged=sum(1 for r in units if r.get('shoot')),
                       casters=sum(1 for r in units if r.get('mana')))
        races[name] = dict({k: v for k, v in roster.items() if k not in ('units', 'buildings', 'research')},
                           summary=summary, units=units, buildings=buildings, research=research)

    hubs = collections.defaultdict(set)
    for code, by in hard.items():
        for address in by:
            hubs[address].add(code)
    hub_rows = [dict(address=a, ids=len(c), units=sum(1 for i in c if i[0] == 'A'),
                     buildings=sum(1 for i in c if i[0] == 'B'), research=sum(1 for i in c if i[0] in 'PR'),
                     features=sum(1 for i in c if i[0] == 'F'), note=HUB_NOTES.get(a))
                for a, c in hubs.items()]
    hub_rows.sort(key=lambda r: (-r['ids'], r['address']))

    races_by_index = {r['index']: n for n, r in rosters.items()}
    ter = terrain_sets(game)
    maps = [scenario(p, catalogue, decoded, races_by_index, ter) for p in sorted((game / 'Scenario').glob('*.SCN'))]
    return dict(schema=SCHEMA,
                sources=dict(catalogue=sha_file(assets / 'catalogue.json'), art=sha_file(assets / 'art.json'),
                             decompile=sha_file(decompile), decompile_name=decompile.name),
                evidence='Read: files only (tools/content_inventory.py docstring); CONTENT_EXPANSION_PLAN.md W0',
                totals=dict(hardcoded_ids=len(hard), hardcoded_functions=len(hubs), maps=len(maps), races=len(races)),
                hubs=hub_rows, races=races, maps=maps)


def markdown(inventory):
    out = ['| Race | Units | Buildings | Research | Art complete / none (skip-listed slots) | RL sheets (not icons) '
           '| Hard-coded ids (no rebuild ref) | Research in research_effects.json | Fly / water / large / ranged / casters |',
           '|' + '---|' * 9]
    for name, race in sorted(inventory['races'].items(), key=lambda kv: kv[1]['index']):
        s = race['summary']
        out.append(f"| {name} | {s['units']} | {s['buildings']} | {s['research']} | {s['art_complete']} / {s['art_none']} ({s['art_skipped_slots']}) "
                   f"| {s['rl_sheets']} | {s['hardcoded_ids']} ({s['hardcoded_without_rebuild_ref']}) "
                   f"| {s['research_effects_ported']} | {s['flyers']} / {s['water_types']} / {s['large']} / "
                   f"{s['ranged']} / {s['casters']} |")
    out += ['', '| Map | Size | Sides (races) | Terrain sets | Materials | Missing records (bld/army/feat) '
            '| Map buildings / armies without art | Extra chunks |', '|' + '---|' * 8]
    base = {'SCNH', 'SIDH', 'SAIH', 'SM24', 'MAPH', 'FTRH', 'BLDH', 'ARMH', 'EVSH', 'ENDX'}
    for m in inventory['maps']:
        sides = ', '.join(s['race_name'] or str(s['race']) for s in m['sides'])
        extra = ', '.join(f'{t} {n}' for t, n in m['chunk_counts'].items() if t not in base) or '-'
        out.append(f"| {m['file'][:-4]} | {m['size_cells'][0]} | {len(m['sides'])} ({sides}) | {', '.join(m['terrain_sets'])} "
                   f"| {', '.join(m['materials'])} | {len(m['buildings_without_record'])} / {len(m['armies_without_record'])} / "
                   f"{len(m['features_without_record'])} | {len(m['buildings_without_art'])} / {len(m['armies_without_art'])} "
                   f"| {extra} |")
    out += ['', '| Function | Ids | Units | Buildings | Research | Note |', '|' + '---|' * 6]
    for h in inventory['hubs'][:20]:
        out.append(f"| `{h['address']}` | {h['ids']} | {h['units']} | {h['buildings']} | {h['research']} | {h['note'] or ''} |")
    return '\n'.join(out) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--decompile', type=Path, default=DEFAULT_DECOMPILE)
    parser.add_argument('--out', type=Path, default=PROJECT / 'assets' / 'content_inventory.json')
    parser.add_argument('--markdown', action='store_true', help='print the summary tables')
    args = parser.parse_args()
    inventory = build(decompile=args.decompile)
    args.out.write_text(json.dumps(inventory, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    if args.markdown:
        print(markdown(inventory))


if __name__ == '__main__':
    main()
