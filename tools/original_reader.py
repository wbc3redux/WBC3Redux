"""Vendored from MVP_RESEARCH/inspect_original.py (2026-10-30).
Importer sets ROOT and OUT; unknown source bytes remain intact.
Base-record interpretation only, not a patch or runtime rules resolver.
"""
from pathlib import Path
import collections
import csv
import hashlib
import json
import re
import struct

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(__file__).resolve().parent

def chunks(data):
    offset = 0
    while offset < len(data):
        assert offset + 8 <= len(data), ('truncated header', offset)
        tag = data[offset:offset+4].decode('ascii')
        size = struct.unpack_from('<I', data, offset+4)[0]
        assert size >= 8 and offset + size <= len(data), (tag, offset, size)
        yield tag, offset, size, data[offset+8:offset+size]
        offset += size
    assert offset == len(data)

def archive(path):
    data = path.read_bytes()
    assert data.startswith(b'xcr File')
    count = struct.unpack_from('<I', data, 0x14)[0]
    for i in range(count):
        offset = 28 + 532*i
        entry = data[offset:offset+532]
        assert len(entry) == 532
        name = entry[:256].split(b'\0')[0].decode('latin1')
        pos, size = struct.unpack_from('<II', entry, 512)
        assert pos + size <= len(data)
        yield name, pos, data[pos:pos+size]

def cipher_inverse():
    seed, values = 0x2d8, []
    while len(values) < 256:
        seed = (seed * 0x6255 + 0x3619) & 0xffff
        v = min(255, (((seed << 8) * 0x80008001) >> 32) >> 15)
        if v not in values:
            values.append(v)
    inverse = [0]*256
    for i, v in enumerate(values):
        inverse[v] = i
    return bytes(inverse)

def save(name, value):
    (OUT/name).write_text(json.dumps(value, indent=2), encoding='utf-8')

def scenario_names(root):
    """Display names of every army/building/feature/tile id in the installation's .en files (first definition wins)."""
    names = {}
    for path in sorted((root/'Assets').rglob('*.en')):
        for code, name in re.findall(r'<(?:Army|Building|Feature|Tile)\s+id="(\w{4})"[^>]*?name="([^"]+)"', path.read_text(encoding='latin1')):
            names.setdefault(code, name)
    return names


def map_slug(name):
    """Folder name of a scenario under assets/maps/: lower case, apostrophes dropped, other runs of non-alphanumerics -> '-'
    ('The Lion's Den' -> 'the-lions-den')."""
    stem = Path(name).stem.lower().replace("'", '')
    return re.sub(r'[^a-z0-9]+', '-', stem).strip('-')


def parse_scenario(path, names):
    """Placement manifest of one SCN (any shipped scenario; W1 of CONTENT_EXPANSION_PLAN.md). Players and size come from the
    header words at 0x48 (Desert Sands: 2, 128 x 128, as the pinned milestone-1 manifest)."""
    data = path.read_bytes()
    parsed = list(chunks(data))
    players, width, height = struct.unpack_from('<III', data, 0x48)
    result = dict(source=str(path), sha256=hashlib.sha256(data).hexdigest(),
                  players=players, size_cells=[width,height], coordinate_conversion={'x':32,'y':24,
                  'status':'existing-reader convention; verify against editor'},
                  starts=[], buildings=[], armies=[], features=[], terrain_records=[], chunks=[],
                  unknowns=['Side ownership/team/race flags', 'Terrain record words and placement order',
                            'Terrain collision masks', 'AI and event-script semantics',
                            'Entity anchor meaning', 'Starting army/Keep from match settings'])
    for tag, offset, size, body in parsed:
        result['chunks'].append(dict(tag=tag, offset=offset, size=size, sha256=hashlib.sha256(body).hexdigest()))
        if tag == 'SIDH':
            assert len(body) % 44 == 0
            for index in range(len(body)//44):
                record = body[index*44:(index+1)*44]
                x,y = struct.unpack_from('<i',record,20)[0],struct.unpack_from('<i',record,24)[0]
                if record[0] == 1 and x >= 0:
                    result['starts'].append(dict(side_index=index, cell=[x,y],raw_hex=record.hex()))
        elif tag in ('BLDH','ARMH','FTRH'):
            code = body[:4].decode('ascii')
            position_offset = 8 if tag == 'ARMH' else 16
            x,y = struct.unpack_from('<ii',body,position_offset)
            record = dict(code=code, name=names.get(code,code), world_position=[x,y],
                          cell_position=[x/32,y/24], source_offset=offset, raw_hex=body.hex())
            # Owner word: BLDH +0x64 and ARMH +0x94, read by the scenario loader 0x4910e0 (ENCOUNTERS_RESEARCH.md, 9-fix).
            # Each ARMH record is one unit; its +4 word (6 in every shipped record) is not a count (meaning Open).
            if tag == 'BLDH':
                record['owner'] = struct.unpack_from('<h',body,0x64)[0]
            if tag == 'ARMH':
                record['owner'] = struct.unpack_from('<h',body,0x94)[0]
                record['word_04'] = struct.unpack_from('<I',body,4)[0]
            if tag == 'BLDH' and code[:3] in ['BRG','BRM','BRC','BRS']:
                record['resource'] = dict(BRG='Gold',BRM='Metal',BRC='Crystal',BRS='Stone')[code[:3]]
                record['level'] = int(code[3])+1
            result[dict(BLDH='buildings',ARMH='armies',FTRH='features')[tag]].append(record)
        elif tag == 'EFFH':
            # Map effect records: a 20-byte particle id and the world position as two words at +20 / +24 (0x4910e0 reads 0x1c
            # bytes; the writer is 0x546350). Each creates a particle emitter (simulation/map_effects.gd, map wave 5,
            # MAPS_RESEARCH.md "Wave 5") from Assets/Particles/<id>.xml (assets/particles.json).
            x, y = struct.unpack_from('<ii', body, 20)
            result.setdefault('effects', []).append(dict(name=body[:20].split(b'\0')[0].decode('latin1'), world_position=[x, y],
                cell_position=[x/32, y/24], source_offset=offset, raw_hex=body.hex(), status='particle emitter (simulation/map_effects.gd)'))
        elif tag == 'MAPH':
            assert len(body)%16 == 0
            for index in range(len(body)//16):
                record = body[index*16:(index+1)*16]
                code = record[:4].decode('ascii')
                result['terrain_records'].append(dict(index=index, code=code,
                    name=names.get(code,code), unknown_u32=list(struct.unpack_from('<III',record,4)),raw_hex=record.hex()))
    return result


def main():
    names = scenario_names(ROOT)
    inventory = []
    for path in sorted((ROOT/'Scenario').glob('*.SCN')):
        data = path.read_bytes()
        parsed = list(chunks(data))
        players, width, height = struct.unpack_from('<III', data, 0x48)
        inventory.append(dict(file=path.name, players=players, size=[width, height],
                              bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                              chunk_counts=dict(collections.Counter(t for t, _, _, _ in parsed))))
    save('original_scenario_inventory.json', inventory)
    result = parse_scenario(ROOT/'Scenario'/'Desert Sands.SCN', names)
    assert result['players'] == 2 and result['size_cells'] == [128,128]
    assert len(result['starts']) == 2
    assert len(result['buildings']) == 26
    assert len(result['terrain_records']) == 169
    assert all(0 <= r['cell_position'][0] < 128 and 0 <= r['cell_position'][1] < 128
               for group in ['buildings','armies','features'] for r in result[group])
    save('desert_sands_manifest.json', result)
    with (OUT/'desert_sands_placements.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.writer(f)
        writer.writerow(['kind','code','name','world_x','world_y','cell_x','cell_y','level','owner','source_offset'])
        for group in ['buildings','armies','features']:
            for r in result[group]:
                writer.writerow([group,r['code'],r['name'],*r['world_position'],*r['cell_position'],r.get('level',''),r.get('owner',''),r['source_offset']])
    codes = {r['code'] for group in ['buildings','armies','features','terrain_records'] for r in result[group]}
    codes.update(['AHHX','AHBX','AHKX','AHMX','BKK0','BKK1','BAGA','BPFL'])
    inverse = cipher_inverse()
    assets, stats = [], []
    for path in sorted((ROOT/'Assets').rglob('*.xcr')):
        for name,offset,body in archive(path):
            code = name[:4]
            if code not in codes:
                continue
            info = dict(code=code, entry=name, archive=str(path.relative_to(ROOT)), offset=offset, bytes=len(body))
            ext = Path(name).suffix.upper()
            if ext == '.RLE' and body[:2] == b'RS':
                info['sheet_size'] = list(struct.unpack_from('<HH',body,6))
            elif ext == '.BMP' and body[:2] == b'BM':
                info['bitmap_size'] = list(struct.unpack_from('<ii',body,18))
            elif ext in ['.ARM','.BUI']:
                d=body.translate(inverse)
                u=lambda n:struct.unpack_from('<H',d,n)[0]
                stats.append(dict(code=code,name=names.get(code,code),archive=info['archive'],entry=name,
                    costs=dict(zip(['Gold','Metal','Crystal','Stone'],[u(n) for n in ([94,96,98,100] if ext=='.ARM' else [28,30,32,34])])),
                    base_fields=({ 'build_time_raw':u(28),'combat':u(30),'speed_raw':u(32),'damage':u(34),'hp':u(36),'armour':u(40),'range_raw':u(54)} if ext=='.ARM' else {'build_time_raw':u(40),'hp':u(42),'armour':u(44)}),
                    caveat='Existing-reader field interpretation; hero modifiers and runtime units not verified. Base archive records only, not a general patch resolver.'))
            assets.append(info)
    save('desert_sands_asset_inventory.json', assets)
    save('selected_base_stats.json', stats)
    print('Two-player maps:',[r['file'] for r in inventory if r['players']==2])
    print('Starts:',result['starts'])
    print('Buildings:',dict(collections.Counter(r['name'] for r in result['buildings'])))
    print('Armies:',dict(collections.Counter(r['name'] for r in result['armies'])))
    print('Features:',len(result['features']),'Terrain records:',len(result['terrain_records']))
    print('Terrain codes:',dict(collections.Counter(r['code'] for r in result['terrain_records'])))
    print('Matched assets:',len(assets),'Stat records:',len(stats))
    print('Unresolved catalogue IDs:',sorted(c for c in codes if c not in names))


def game_root(start=None):
    """Installation folder: the nearest ancestor holding 'Battlecry III.exe' (the project may be a worktree copy below
    GodotRebuild); falls back to the project's parent, the original layout."""
    here = Path(start).resolve() if start else Path(__file__).resolve().parent
    for parent in [here] + list(here.parents):
        if (parent / 'Battlecry III.exe').exists():
            return parent
    return Path(__file__).resolve().parents[2]
