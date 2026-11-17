"""RM-1 (RANDOM_MAP_RESEARCH.md "RM-1"): the Random Map piece sets of RandomData.xcr as one compact data file.

Reads every `<set><n>.GOM` of the archive (647 pieces in 11 sets) into assets/random_map.json:
* the 0x44-byte header (A5): word 0x7b marker, word +2, the 9 TER codes (row-major 3 x 3), the 9 skip words (+0x28,
  0 = write the tile), the edge ids +0x3a top, +0x3c right, +0x3e bottom, +0x40 left, word +0x42;
* the 0x134-byte block +0x44..0x178 that 0x583800 copies per slot and nothing reads (A5, Open), kept as base64 in a
  table of distinct blocks (each piece names its block by index);
* the FTRH feature records (tag, size 0x20, code, 3 words, x, y in pixels inside the piece) up to the ENDX record.
The reader rebuilds every GOM byte for byte from the decoded fields (`piece_bytes`), so nothing is lost.

Next to the pieces: the terrain-type table of 0x582e10 (A4: set name and piece count per terrain 0..9; the `desert` set
is never used), the decrypted TER record of every code the pieces name (first record in sorted Assets\\Terrain archive
order, the order of the tile table 0x497c10 searches; byte 0x647 is the big-tile shape 0x48f8c0 reads, the 400 cells
are the collision data RM-3 needs), the codes no TER defines (0x497c10 returns -1: the piece's read index stops), the
feature registry (every FEA code of Assets\\Features, the set 0x5888e0 searches) and the fill tile TGX0 (0x48f210).
RM-4 adds what the generated map's collision grid needs (simulation/random_map_grid.gd): every registry code's FEA
footprint (`feature_definitions`: size, 16 mask words, bypass byte 58, as collision.decode_footprint reads it) and the
movement cost table 0x603e68 (`movement_cost_rows`, from the pinned executable).

Terrain bitmaps: every code the ten used sets name (plus TGX0) is written to terrain/<CODE>.png, unscaled RGB like the
map importer's tiles, unless the map import already wrote it (same bytes either way). Called from import_assets.generate
with one line; RandomData.xcr joins the importer's source inventory through `sources`.
"""
import base64
import hashlib
import io
import json
import re
import struct
from pathlib import Path

from PIL import Image

import original_reader as reader

OUTPUT = 'random_map.json'
SOURCE = 'RandomData.xcr'
SOURCE_HASH = '7f6953fbf1de1140c01298f9f86610444d00aa8716f27fe658bbd179f29baf12'
PIECES, SETS_IN_ARCHIVE, FEATURE_RECORDS = 647, 11, 5588
HEADER, BLOCK_END, RECORD = 0x44, 0x178, 0x20
MARKER = 0x7b
FILL_TILE = 'TGX0'
TER_SIZE = 0x674
# 0x582e10: terrain type -> set name (as the code asks for it) and piece count (A4).
TERRAIN_SETS = [('clear', 61), ('grass', 81), ('HighGrass', 81), ('oasis', 61), ('lava', 41), ('sand', 68),
                ('cavern', 34), ('snow', 61), ('water', 55), ('jungle', 73)]
TERRAIN_NAMES = ['Grasslands', 'Plains', 'Highlands', 'Desert', 'Lava', 'Outlands', 'Caverns', 'Snow', 'Wetlands',
                 'Jungle']


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sources(source):
    return {source / SOURCE}


def parse_piece(body):
    """One GOM: header fields, the 0x134 block, FTRH records, the ENDX record's size word."""
    require(len(body) >= BLOCK_END + 8, 'GOM too short')
    marker, word2 = struct.unpack_from('<hh', body, 0)
    codes = [body[4 + 4 * i:8 + 4 * i].decode('latin-1') for i in range(9)]
    skip = list(struct.unpack_from('<9h', body, 0x28))
    top, right, bottom, left, word42 = struct.unpack_from('<5h', body, 0x3a)
    features, offset = [], BLOCK_END
    while body[offset:offset + 4] == b'FTRH':
        size, = struct.unpack_from('<I', body, offset + 4)
        require(size == RECORD, 'FTRH record size')
        code, w1, w2, w3, x, y = struct.unpack_from('<4sIIIii', body, offset + 8)
        features.append([code.decode('latin-1'), w1, w2, w3, x, y])
        offset += RECORD
    require(body[offset:offset + 4] == b'ENDX' and len(body) == offset + 8, 'GOM does not end in ENDX')
    end, = struct.unpack_from('<I', body, offset + 4)
    return dict(marker=marker, word2=word2, tiles=codes, skip=skip, edges=[top, right, bottom, left], word42=word42,
                features=features, endx=end), body[HEADER:BLOCK_END]


def piece_bytes(piece, block):
    """The GOM rebuilt from the decoded fields (round-trip check)."""
    out = struct.pack('<hh', piece['marker'], piece['word2']) + b''.join(c.encode('latin-1') for c in piece['tiles'])
    out += struct.pack('<9h', *piece['skip']) + struct.pack('<5h', *piece['edges'], piece['word42']) + block
    for code, w1, w2, w3, x, y in piece['features']:
        out += b'FTRH' + struct.pack('<I4sIIIii', RECORD, code.encode('latin-1'), w1, w2, w3, x, y)
    return out + b'ENDX' + struct.pack('<I', piece['endx'])


def read_sets(source):
    """{set name (archive spelling): {index: (piece, block, entry name)}} and the raw bodies by entry name."""
    path = source / SOURCE
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    require(digest == SOURCE_HASH, f'{SOURCE} differs from the reference ({digest}); investigate before importing.')
    sets, raw = {}, {}
    for name, _, body in reader.archive(path):
        match = re.fullmatch(r'(.*?)(\d+)\.GOM', name, re.IGNORECASE)
        require(match is not None, f'Unexpected entry {name}')
        piece, block = parse_piece(body)
        require(piece_bytes(piece, block) == body, f'{name} does not round-trip')
        group = sets.setdefault(match.group(1), {})
        require(int(match.group(2)) not in group, f'Duplicate piece {name}')
        group[int(match.group(2))] = (piece, block, name)
        raw[name] = body
    require(len(raw) == PIECES and len(sets) == SETS_IN_ARCHIVE, 'Unexpected piece count')
    return sets, raw


def terrain_records(source):
    """code -> (decrypted TER record, archive, entry): first record per code in sorted Assets\\Terrain order."""
    inverse = reader.cipher_inverse()
    found = {}
    for path in sorted((source / 'Assets' / 'Terrain').glob('*.xcr')):
        for name, _, body in reader.archive(path):
            if name.upper().endswith('.TER') and len(body) == TER_SIZE:
                record = body.translate(inverse)
                found.setdefault(record[:4].decode('latin-1'), (record, path.relative_to(source).as_posix(), name))
    return found


def feature_registry(source):
    inverse = reader.cipher_inverse()
    return sorted({body.translate(inverse)[:4].decode('latin-1') for path in (source / 'Assets' / 'Features').glob('*.xcr')
                   for name, _, body in reader.archive(path) if name.upper().endswith('.FEA')})


def piece_feature_codes(source):
    """RM-3: the feature codes the pieces place that are in the registry (the only ones 0x5888e0 lets through, A10)."""
    registry = set(feature_registry(source))
    sets, _ = read_sets(source)
    return sorted({f[0] for pieces in sets.values() for piece, _, _ in pieces.values() for f in piece['features']} & registry)


def feature_definitions(source):
    """RM-4: code -> the FEA footprint collision.decode_footprint reads (size, the 16 mask words, the occupancy bypass
    byte 58) for every registry code; each code has exactly one FEA record in Assets\\Features (none in PatchData)."""
    import collision
    found = {}
    for path in sorted((source / 'Assets' / 'Features').glob('*.xcr')):
        for name, _, body in reader.archive(path):
            if name.upper().endswith('.FEA'):
                code = body.translate(reader.cipher_inverse())[:4].decode('latin-1')
                require(code not in found or found[code][0] == body, f'Two FEA records for {code}')
                found[code] = (body, path.relative_to(source).as_posix(), name)
    out = {}
    for code, (body, archive, entry) in sorted(found.items()):
        d = collision.decode_footprint(body, code, 'features')
        out[code] = dict(size=d['size'], masks=d['masks'], bypass=d['occupancy_bypass'], source=dict(archive=archive, entry=entry))
    return out


def movement_cost_rows(source):
    """RM-4: the movement cost table 0x603e68 (4 rows of 13 shorts, as collision.build_collision reads it)."""
    import collision
    binary = (source / 'Battlecry III.exe').read_bytes()
    require(hashlib.sha256(binary).hexdigest() == collision.EXE_HASH, 'Executable differs from the inspected baseline')
    return [list(struct.unpack_from('<13h', binary, 0x203e68 + row * 26)) for row in range(4)]


def tile_bitmaps(source, codes):
    """code -> (bitmap bytes, provenance) from Assets\\**\\*.xcr; a name must be unique, a PatchData twin identical."""
    wanted = {code.lower() + '.bmp': code for code in codes}
    found = {}
    for path in sorted((source / 'Assets').rglob('*.xcr')):
        for name, offset, body in reader.archive(path):
            key = name.lower()
            if key in wanted:
                require(key not in found, f'Ambiguous archive entry: {name}')
                found[key] = (body, dict(archive=path.relative_to(source).as_posix(), entry=name, offset=offset,
                                         sha256=hashlib.sha256(body).hexdigest()))
    for name, _, body in reader.archive(source / 'PatchData.xcr'):
        if name.lower() in found:
            require(found[name.lower()][0] == body, f'Required entry differs in PatchData.xcr: {name}')
    require(set(found) == set(wanted), f'Missing tile bitmaps: {sorted(set(wanted) - set(found))}')
    return {wanted[key]: value for key, value in found.items()}


def build_data(source):
    """The data file's content (no bitmaps) and the codes whose bitmaps the used sets need."""
    sets, _ = read_sets(source)
    by_lower = {name.lower(): name for name in sets}
    ter = terrain_records(source)
    registry = feature_registry(source)
    blocks, block_index = [], {}
    out_sets = {}
    for name in sorted(sets, key=str.lower):
        pieces = sets[name]
        require(sorted(pieces) == list(range(len(pieces))), f'{name}: piece numbers are not 0..n-1')
        rows = []
        for n in range(len(pieces)):
            piece, block, entry = pieces[n]
            require(piece['marker'] == MARKER, f'{entry}: marker')
            if block not in block_index:
                block_index[block] = len(blocks)
                blocks.append(base64.b64encode(block).decode('ascii'))
            rows.append(dict(piece, entry=entry, block=block_index[block]))
        out_sets[name.lower()] = dict(name=name, pieces=rows)
    terrains = []
    used_codes = {FILL_TILE}
    for terrain, (name, count) in enumerate(TERRAIN_SETS):
        key = name.lower()
        require(key in by_lower and len(out_sets[key]['pieces']) == count, f'Set {name}: count')
        terrains.append(dict(terrain=terrain, name=TERRAIN_NAMES[terrain], set=key, count=count))
        used_codes |= {c for p in out_sets[key]['pieces'] for c in p['tiles']}
    all_codes = {c for s in out_sets.values() for p in s['pieces'] for c in p['tiles']} | {FILL_TILE}
    require(sum(len(p['features']) for s in out_sets.values() for p in s['pieces']) == FEATURE_RECORDS, 'FTRH count')
    require(FILL_TILE in ter, 'No TER record for the fill tile')
    tiles = {}
    for code in sorted(all_codes & set(ter)):
        record, archive, entry = ter[code]
        tiles[code] = dict(shape=record[0x647], ter=base64.b64encode(record).decode('ascii'),
                           ter_source=dict(archive=archive, entry=entry), used=code in used_codes)
    missing = sorted(all_codes - set(ter))
    return dict(schema=1, source=dict(archive=SOURCE, sha256=SOURCE_HASH),
                evidence='RANDOM_MAP_RESEARCH.md A4 (0x582e10 sets), A5 (GOM layout), A8 (0x497c10 / 0x48f8c0), '
                         'A9 (fill TGX0), A10 (0x5888e0 registry); decoded by tools/random_map_data.py',
                terrain_types=terrains, sets=out_sets, blocks=blocks, tiles=tiles, missing_tiles=missing,
                missing_tiles_used=sorted(set(missing) & used_codes), feature_registry=registry,
                feature_definitions=feature_definitions(source), movement_cost_rows=movement_cost_rows(source),
                fill_tile=FILL_TILE), sorted(used_codes & set(ter))


def build(source, out):
    """Writes out/random_map.json and out/terrain/<CODE>.png for every tile code of the used sets (RM-1)."""
    data, bitmap_codes = build_data(source)
    terrain = out / 'terrain'
    terrain.mkdir(exist_ok=True)
    for code, (body, provenance) in sorted(tile_bitmaps(source, bitmap_codes).items()):
        target = terrain / (code + '.png')
        with Image.open(io.BytesIO(body)) as bitmap:
            image = bitmap.convert('RGB')
            if not target.exists():
                image.save(target)
            data['tiles'][code].update(bitmap='terrain/' + code + '.png', size=list(image.size), bitmap_source=provenance)
    (out / OUTPUT).write_text(json.dumps(data, sort_keys=True, separators=(',', ':')) + '\n', encoding='utf-8')
    return data


if __name__ == '__main__':
    import tempfile
    with tempfile.TemporaryDirectory() as temp:
        result = build(reader.game_root(), Path(temp))
        print(len(result['sets']), 'sets', sum(len(s['pieces']) for s in result['sets'].values()), 'pieces',
              len(result['blocks']), 'distinct blocks', len(result['tiles']), 'tiles', 'missing', result['missing_tiles'],
              'missing and used', result['missing_tiles_used'])
        print('bytes', (Path(temp) / OUTPUT).stat().st_size,
              'bitmaps', sum(p.stat().st_size for p in (Path(temp) / 'terrain').glob('*.png')))
