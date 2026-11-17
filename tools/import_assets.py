"""Local, deterministic reference importer. Never writes to the source installation."""
import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
import shutil
import struct
import sys
import tempfile

from PIL import Image, __version__ as pillow_version
import original_reader as reader
from rle import decode
from ani import decode_ani, validate_sheet, DIRECTIONS
from collision import build_collision, validate_minimap
from map_objects import build_feature_presentations, FEATURE_OUTPUT
from audio_data import terrain_ambient
from map_objects import build_presentations
from production_data import build_production, UNITS as PRODUCTION_UNITS, BUILDINGS as PRODUCTION_BUILDINGS
from xci import build_ui
from ui_extra import build_extra, parse_game_text, parse_history, parse_spells, parse_tips, xml_number
from catalogue_data import build_catalogue
from encounters_data import build_encounters, naming_sources
from items_data import build_items, hero_sources
import art_data
import random_map_data  # RM-1 (RANDOM_MAP_RESEARCH.md): RandomData.xcr piece sets
import particle_data    # map wave 5 (MAPS_RESEARCH.md "Wave 5"): Assets/Particles, the EFFH map effects

PROJECT = Path(__file__).resolve().parents[1]
GAME = reader.game_root(PROJECT)  # installation folder, also when the project is a worktree copy
from audio_data import build_audio, check_audio, audio_sources, MANIFEST as AUDIO_MANIFEST
DEFAULT_SOURCE = GAME  # name used by the audio importer
MAP_HASH = 'ac858846725ab96ee84a85669253123adeef938bf84a6245f3e8914b8e70ef82'
# W1 (CONTENT_EXPANSION_PLAN.md): every shipped scenario's SHA-256 and counts (starts, buildings, armies, features, MAPH
# records) as parsed by original_reader.parse_scenario. A differing file stops the import, like Desert Sands' pin.
MAP_PINS = {
    'Bridges': ('696c331b7f3f5821856b78f561f8842786cb979384a381bd35dac3c719701c97', [5, 43, 21, 268, 169]),
    'Cavemen': ('4a2171d50398b7d87fd8e674893626617fa51aecc9fa15aa5d003997059caa30', [6, 76, 11, 17, 676]),
    'Cavern Wars': ('3e5d4da4eb6554fa0a2c8ed8061882e58cf5c793360217125273634b67ef43a4', [4, 30, 0, 0, 169]),
    'Celestial Oasis': ('3611efe571e52e93de6656ae101238652286586ac7a67b1ccea02538d994302a', [4, 36, 16, 31, 169]),
    'Circles': ('72f28b76d932c55c95fe94cfd0a93da03c87808faf953c9e3b92cf08091924d1', [4, 48, 0, 238, 676]),
    'Desert Crossing': ('c2e2fe7f0c2e96d98d9eb5df17d74a5adc424b2778d0506346b7367718fba84a', [5, 45, 67, 188, 676]),
    'Desert Sands': ('ac858846725ab96ee84a85669253123adeef938bf84a6245f3e8914b8e70ef82', [2, 26, 10, 40, 169]),
    "Dragon's Pyramid": ('72594e8d36431a7d55c41d2adb3ca75dbaad139fc5653b0e9d4f61e4713b8ded', [6, 42, 0, 42, 676]),
    'Dwarven Tunnels': ('68b4aaa734347ec6f546a96f0cadfdca25719b14794110d10eef65b728ebb006', [3, 28, 59, 118, 400]),
    'Forest Lakes': ('f612baed1ab320a1e62fd97354ece0087a3d9400d014bdeee067637cc87905a9', [6, 61, 22, 923, 676]),
    'Four Bridges': ('f09ff8dfd1c1892fd12598138f14d5d130227b0431ca7d779f6dfb5c904481e0', [4, 32, 16, 41, 169]),
    'Four Rivers': ('08bb8a94456af33229a14b0114458fd8693cb81249f3919483831e96a6cd69f8', [4, 49, 17, 509, 400]),
    'Hills to Climb': ('207d37d887396608e3b5851c0a9550b6c409619ba8bb797570dd136e002fb8cd', [4, 63, 14, 541, 676]),
    'Land of the Lost': ('5f8db35985df216b4053803bd63c4ab9abba7dc468439c2ee70e225840085ecb', [6, 74, 60, 180, 400]),
    'Lands Divided': ('96082f11cd5f1339789474d2e1d6ad9759c517719f143d9720f65406e817a872', [4, 54, 10, 324, 169]),
    'Next Door': ('a063a9cb7db0d5a569c7b4182892aa138ea3011b91eaa9324b3aa795d5d4b27d', [4, 43, 14, 175, 169]),
    'Rumble in the Jungle': ('326977ac8aeb7b69dc22765ab9f75e9ddf08a9be7f95c4213282e697c3f89a28', [3, 37, 9, 64, 169]),
    'The Hill': ('2e20ae6a2d37675c88d5b667e32e3cfa3bf1adf26803baee4b6ce4e6e8c329ae', [4, 38, 10, 71, 169]),
    "The Lion's Den": ('09312ae4ea54853d2db2a3f5526460f3a164574820fe5b669124cf078b38a5be', [3, 24, 5, 24, 169]),
    'Valley of the Dead': ('7ba8caf79c504c8e71ac85467f4ee6f6bc515df3e78b00eff99e8477de19c600', [4, 47, 12, 204, 400]),
    'Volcanic Pit': ('233977729f59a2798bebbf6b7097e27ac4f0f714f1f2802fd17299d2584d7688', [5, 39, 0, 16, 169]),
    'Winter Wonderland': ('32f9a22ac1142fe86ed371f5d0dd28a2e1625ade28a778a8510f4819fca8cea1', [6, 64, 139, 445, 676]),
}
# Scenarios imported into assets/maps/<slug>/ (map waves add entries; Desert Sands first, it also keeps the legacy
# top-level outputs). Wave 1: The Hill. Wave 2 (M-2): The Lion's Den, Hills to Climb (the first 256 map).
MAPS = ['Desert Sands', 'The Hill', "The Lion's Den", 'Hills to Climb',
        # Map wave 3 (water, milestone M-3): MAPS_RESEARCH.md "Wave 3".
        'Celestial Oasis', 'Next Door', 'Four Bridges', 'Bridges', 'Four Rivers', 'Valley of the Dead',
        # Wave 3 part 2: six sides each.
        'Forest Lakes', 'Winter Wonderland', 'Land of the Lost',
        # Map wave 4 (the remaining land maps): MAPS_RESEARCH.md "Wave 4".
        'Circles', "Dragon's Pyramid", 'Desert Crossing', 'Rumble in the Jungle', 'Lands Divided',
        # Map wave 5 (caverns and lava, the EFFH map effects): MAPS_RESEARCH.md "Wave 5".
        'Cavern Wars', 'Dwarven Tunnels', 'Cavemen', 'Volcanic Pit']
MAP_FILES = ['map.json', 'map_info.json', 'terrain.json', 'collision.json', 'map_objects.json', 'scenario_minimap.png',
             'terrain_validation.json', 'collision_walk.png', 'collision_build.png', 'collision_height.png',
             'collision_material.png', 'collision_objects.png']


class UnsupportedSource(ValueError):
    """The installation differs from the verified GOG build (PACKAGING.md step 2): exit code 3."""


PROGRESS_FILE = None   # --progress-file: the installer polls it (PACKAGING.md step 2)


def progress(percent, label):
    """One progress line on stdout ('PROGRESS <percent> <label>') and, with --progress-file, the same line in that file."""
    line = f'PROGRESS {int(percent)} {label}'
    print(line, flush=True)
    if PROGRESS_FILE is not None:
        temp = PROGRESS_FILE.with_suffix(PROGRESS_FILE.suffix + '.tmp')
        temp.write_text(line + '\n', encoding='utf-8')
        temp.replace(PROGRESS_FILE)


def preflight(source):
    """Every pinned source file is checked before anything is written, so a different version of the game is reported
    once, with all differing files and their hashes, instead of failing midway. The importer reads tables from
    Battlecry III.exe at fixed addresses, so only the verified build can be imported (other versions need samples)."""
    from collision import EXE_HASH
    require((source / 'Battlecry III.exe').is_file(), f'No Battlecry III.exe in {source}; choose the Warlords Battlecry III folder.')
    pins = {'Battlecry III.exe': EXE_HASH, random_map_data.SOURCE: random_map_data.SOURCE_HASH}
    pins.update({f'Scenario/{name}.SCN': MAP_PINS[name][0] for name in MAPS})
    differing = []
    for name, digest in sorted(pins.items()):
        path = source / name
        actual = sha(path) if path.is_file() else 'missing'
        if actual != digest:
            differing.append(f'{name}: {actual}')
    if differing:
        raise UnsupportedSource('This copy of Warlords Battlecry III differs from the version this importer was verified on (the GOG release). '
                                'Please report these files and hashes: ' + '; '.join(differing))


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def source_files(source):
    return sorted(set(source.joinpath('Assets').rglob('*.en')) |
                  set(source.joinpath('Assets').rglob('*.xcr')) |
                  set(source.joinpath('Scenario').glob('*.SCN')) |
                  set(source.joinpath('Fonts').glob('*.fnt')) |
                  {source / 'Battlecry III.exe', source / 'PatchData.xcr', source / 'Quest.xcr', source / 'English' / 'Quest.cfg'} |
                  ui_sources(source) | audio_sources(source) | hero_sources(source) | naming_sources(source) |
                  random_map_data.sources(source) | particle_data.sources(source))


def ui_sources(source):
    return {source / name for name in ('War4Int.xci', 'War4Gfx.xcg', 'English/XCIStrings.txt',
            'English/ScreenHelp.txt', 'English/Font.ini', 'English/GText.xcr', 'English/TipOfTheDay.xml',
            'English/History.xml')}


def ui_archives(source):
    """Bitmap entries the XCG may reference: Assets archives plus GText.xcr (lower-case name -> first entry)."""
    found = {}
    for path in sorted((source / 'Assets').rglob('*.xcr')) + [source / 'English/GText.xcr']:
        for name, offset, body in reader.archive(path):
            if name.lower().endswith('.bmp'):
                found.setdefault(name.lower(), (name, body, dict(archive=path.relative_to(source).as_posix(),
                    entry=name, offset=offset, sha256=hashlib.sha256(body).hexdigest())))
    return found


def scenario_manifests(source, desert_sands):
    """slug -> (scenario name, manifest) for MAPS; each file must match its MAP_PINS hash and counts."""
    names = reader.scenario_names(source)
    result = {}
    for name in MAPS:
        path = source / 'Scenario' / (name + '.SCN')
        manifest = desert_sands if name == 'Desert Sands' else reader.parse_scenario(path, names)
        manifest['source'] = 'Scenario/' + path.name
        digest, counts = MAP_PINS[name]
        require(manifest['sha256'] == digest, f'{name} source hash differs from the reference; investigate before importing.')
        require([len(manifest[k]) for k in ('starts','buildings','armies','features','terrain_records')] == counts,
                f'Unexpected scenario counts: {name}')
        width, height = manifest['size_cells']
        require(all(0 <= r['cell_position'][0] < width and 0 <= r['cell_position'][1] < height
                    for group in ['buildings','armies','features'] for r in manifest[group]), f'Object outside the map: {name}')
        result[reader.map_slug(name)] = (name, manifest)
    return result


def terrain_layout(manifest, bitmap_sizes):
    """One draw per MAPH record (CONTENT_EXPANSION_PLAN.md 4.2): record i at ((i % cols) * 320, (i // cols) * 240), cols =
    ceil(width / 10) (serializer 0x4937d0), crop ((q & 1) * 320, (q >> 1) * 240) of its tile bitmap (renderer 0x494862),
    clipped to the map's world size (32 x 24 per cell), which is how terrain.png has always been cut."""
    width, height = manifest['size_cells']
    world = [width * 32, height * 24]
    cols = (width + 9) // 10
    draws = []
    for record in manifest['terrain_records']:
        q = record['unknown_u32'][0] >> 16
        require(q in range(4), f'Unsupported quadrant {q}')
        x, y = q % 2 * 320, q // 2 * 240
        tw, th = bitmap_sizes[record['code']]
        require(x + 320 <= tw and y + 240 <= th, f"Invalid crop: {record['code']}")
        index = record['index']
        dest = [index % cols * 320, index // cols * 240]
        size = [min(320, world[0] - dest[0]), min(240, world[1] - dest[1])]
        require(size[0] > 0 and size[1] > 0, f'MAPH record {index} outside the map')
        draws.append(dict(index=index, code=record['code'], texture='terrain/' + record['code'] + '.png',
                          source_rect=[x, y, size[0], size[1]], destination=dest))
    return dict(schema=1, world_size=world, draws=draws,
                evidence='MAPH order 0x4937d0, quadrant crop 0x494862 (COLLISION_RESEARCH.md); one textured quad per record')


def compose_terrain(layout, tiles):
    """The whole map as one image from the per-record draws (validation only: the game draws the records itself)."""
    image = Image.new('RGB', tuple(layout['world_size']))
    for draw in layout['draws']:
        x, y, w, h = draw['source_rect']
        image.paste(tiles[draw['code']].crop((x, y, x + w, y + h)), tuple(draw['destination']))
    return image


def output_hashes(out):
    """Top-level files by name, plus the shared terrain tiles and every map folder by relative path (W1)."""
    files = [p for p in sorted(out.iterdir()) if p.is_file()]
    files += [p for folder in ('terrain', 'maps') if (out / folder).is_dir()
              for p in sorted((out / folder).rglob('*')) if p.is_file() and p.suffix != '.import']
    return {p.relative_to(out).as_posix(): sha(p) for p in files}


def generate(source, out):
    progress(2, 'Reading the scenarios')
    require(sha(source / 'Scenario/Desert Sands.SCN') == MAP_HASH,
            'Desert Sands source hash differs from the reference; investigate before importing.')
    reader.ROOT, reader.OUT = source, out
    with contextlib.redirect_stdout(io.StringIO()):
        reader.main()
    manifest = json.loads((out / 'desert_sands_manifest.json').read_text())
    manifest['source'] = 'Scenario/Desert Sands.SCN'
    require([len(manifest[k]) for k in ('starts','buildings','armies','features','terrain_records')]
            == [2,26,10,40,169], 'Unexpected scenario counts')
    require(manifest['size_cells'] == [128,128], 'Unexpected map dimensions')
    save(out / 'map.json', manifest)
    save(out / 'desert_sands_manifest.json', manifest)
    maps = scenario_manifests(source, manifest)
    manifests = [m for _, m in maps.values()]
    map_codes = sorted({r['code'] for m in manifests for r in m['buildings']})
    codes = {r['code'] for m in manifests for r in m['terrain_records']}
    wanted = ({c.lower()+ext for c in codes for ext in ['.bmp','.ter']} |
             {r['code'].lower()+ext for m in manifests for group,ext in [('buildings','.bui'),('features','.fea')] for r in m[group]} | {'ahkx.rle','ahkxw.rle','ahkxf.rle','ahkxd.rle','ahkxa.rle','ahkx.ani'})
    wanted |= {r['code'].lower()+ext for m in manifests for kind in ('buildings','features') for r in m[kind] for ext in ('.ani','.rle')}
    wanted |= {c.lower()+'.arm' for c in PRODUCTION_UNITS} | {c.lower()+'.bui' for c in PRODUCTION_BUILDINGS}
    piece_features = random_map_data.piece_feature_codes(source)   # RM-3: footprints are in random_map.json, this is their art
    wanted |= {c.lower()+ext for c in piece_features for ext in ('.ani', '.rle', '.fea')}
    catalogue = build_catalogue(source)  # all races, research only (RACES_RESEARCH.md); also picks batch 1's art
    art_units, art_buildings = art_data.art_lists(catalogue, map_codes)
    wanted |= art_data.wanted_entries(manifest, map_codes, art_units, art_buildings)
    # Sheets of the art codes are optional per ANI slot (ART_RESEARCH.md); they get the same ambiguity/patch checks.
    art_codes = {c.lower() for c in art_units + art_buildings + list(art_data.EFFECTS) + [art_data.ITEM_SHEET, art_data.TREASURE_SHEET] + map_codes}
    entries = {}
    ani_names = set()
    sheets = {}
    inputs = source_files(source)
    progress(10, 'Reading the archives')
    for path in sorted((source / 'Assets').rglob('*.xcr')):
        for name, offset, body in reader.archive(path):
            key = name.lower()
            if key.endswith('.ani'):
                ani_names.add(key)
            if key in wanted:
                require(key not in entries, f'Ambiguous archive entry: {name}')
                entries[key] = (name, body, dict(archive=path.relative_to(source).as_posix(),
                    entry=name, offset=offset, sha256=hashlib.sha256(body).hexdigest()))
            # G-2: every effect ANI and sheet (E???) is optional art too; the effect list comes from the archives.
            if (key.endswith('.rle') and key[:4] in art_codes or key[0] == 'e' and key.endswith(('.ani', '.rle'))) \
                    and key not in wanted:
                require(key not in sheets, f'Ambiguous archive entry: {name}')
                sheets[key] = (name, body, dict(archive=path.relative_to(source).as_posix(),
                    entry=name, offset=offset, sha256=hashlib.sha256(body).hexdigest()))
    require(set(entries) == wanted, f'Missing assets: {wanted-set(entries)}')
    terrain = Image.new('RGB', (4096,3072))
    placements = []
    for record in manifest['terrain_records']:
        name, body, provenance = entries[record['code'].lower()+'.bmp']
        with Image.open(io.BytesIO(body)) as bitmap:
            tile = bitmap.convert('RGB')
        q = record['unknown_u32'][0] >> 16
        require(q in range(4), f'Unsupported quadrant {q}')
        x,y = q%2*320,q//2*240
        require(x+320 <= tile.width and y+240 <= tile.height, f'Invalid crop: {name}')
        index = record['index']
        dest = [index%13*320,index//13*240]
        terrain.paste(tile.crop((x,y,x+320,y+240)), dest)
        placements.append(dict(index=index, code=record['code'], source=provenance,
            source_rect=[x,y,320,240], destination=dest))
    terrain.save(out / 'terrain.png')
    # Do not silently ignore an effective patch override.
    for patch_name, patch_offset, patch_body in reader.archive(source / 'PatchData.xcr'):
        key=patch_name.lower()
        if key not in wanted and key not in sheets:
            continue
        name, body, provenance=entries[key] if key in wanted else sheets[key]
        require(patch_body == body, f'Required entry differs in PatchData.xcr: {patch_name}; resolve precedence first')
        provenance.setdefault('identical_patch_entries', []).append(dict(archive='PatchData.xcr',
            entry=patch_name, offset=patch_offset, sha256=hashlib.sha256(patch_body).hexdigest()))
    # Terrain sets (decided 2026-11-01): every tile bitmap a map uses is written once to terrain/<CODE>.png, shared by all
    # maps, unscaled RGB like terrain.png; each map draws its MAPH records from them (maps/<slug>/terrain.json).
    progress(18, 'Terrain tiles')
    (out / 'terrain').mkdir(exist_ok=True)
    tiles, tile_sources = {}, {}
    for code in sorted(codes):
        name, body, provenance = entries[code.lower()+'.bmp']
        with Image.open(io.BytesIO(body)) as bitmap:
            bitmap.convert('RGB').save(out / 'terrain' / (code + '.png'))
        with Image.open(out / 'terrain' / (code + '.png')) as saved:
            tiles[code] = saved.convert('RGB')     # read back: the gate below checks the written files, not the decode
        tile_sources[code] = dict(source=provenance, size=list(tiles[code].size))
    save(out / 'terrain' / 'tiles.json', dict(schema=1, tiles=tile_sources))
    for index, (slug, (name, map_manifest)) in enumerate(maps.items()):
        progress(22 + 38 * index // len(maps), f'Map {index + 1} of {len(maps)}: {name}')
        folder = out / 'maps' / slug
        folder.mkdir(parents=True, exist_ok=True)
        layout = terrain_layout(map_manifest, {c: t['size'] for c, t in tile_sources.items()})
        composed = compose_terrain(layout, tiles)
        if name == 'Desert Sands':
            # Gate (W1): the per-record drawing reproduces the baked terrain.png pixel for pixel.
            require(composed.tobytes() == terrain.tobytes(), 'Desert Sands tile drawing differs from terrain.png')
        save(folder / 'map.json', map_manifest)
        save(folder / 'terrain.json', layout)
        validate_minimap(source / map_manifest['source'], folder, composed, map_manifest['source'])
        cells = build_collision(source, folder, map_manifest, entries)['cells']
        build_presentations(out, map_manifest, entries, folder)
        save(folder / 'map_info.json', dict(schema=1, name=name, slug=slug, source=map_manifest['source'],
            sha256=map_manifest['sha256'], players=map_manifest['players'], size_cells=map_manifest['size_cells'],
            terrain_ambient=terrain_ambient(map_manifest), materials=sorted({c['raw'][1] for c in cells})))
    # The skirmish menu's list (LB_SS_MAPS): every imported map, by name.
    save(out / 'maps' / 'index.json', dict(schema=1, maps=[dict(slug=slug, name=name, players=m['players'],
        size_cells=m['size_cells']) for slug, (name, m) in sorted(maps.items(), key=lambda item: item[1][0])]))
    progress(60, 'Random map pieces and effects')
    random_map_data.build(source, out)  # RM-1: random_map.json + the piece sets' tiles in terrain/ (after the maps' tiles)
    particle_data.build(source, out)    # wave 5: particles.json, the definitions the EFFH records name
    build_feature_presentations(out, piece_features, entries)   # RM-3: feature_presentations.json + the sheets
    # The legacy top-level copies of Desert Sands (tests and tools that predate assets/maps/ read these).
    for file in ['collision.json', 'map_objects.json', 'scenario_minimap.png', 'terrain_validation.json', 'collision_walk.png',
                 'collision_build.png', 'collision_height.png', 'collision_material.png', 'collision_objects.png']:
        shutil.copyfile(out / 'maps/desert-sands' / file, out / file)
    progress(64, 'Units and buildings')
    save(out / 'production.json', build_production(source, out, entries))
    progress(68, 'Interface')
    ui_bitmaps = ui_archives(source)
    layout = build_ui(source, out, ui_bitmaps)
    layout['extra_bitmaps'] = build_extra(source, out, reader.archive)  # milestone 11-menus (UI_RESEARCH.md)
    layout['game_text'] = parse_game_text((source / 'English/Game.txt').read_bytes().decode('latin1'))
    layout['spells'] = parse_spells((source / 'English/Spells.txt').read_bytes().decode('latin1'))   # HUD pass: the spellbook
    # Parity pass 2: the tip of the day (0x453e30 / 0x454110) and the loading screen's history page (0x43c970).
    layout['tips'] = parse_tips((source / 'English/TipOfTheDay.xml').read_bytes().decode('latin1'))
    layout['history'] = parse_history((source / 'English/History.xml').read_bytes().decode('latin1'))
    # The root's number attribute bounds the roll (0x454110 / 0x43c970 read "number"): History.xml holds 63 entries but
    # says 52, so entries 52..62 are never shown.
    layout['tips_number'] = xml_number((source / 'English/TipOfTheDay.xml').read_bytes().decode('latin1'))
    layout['history_number'] = xml_number((source / 'English/History.xml').read_bytes().decode('latin1'))
    save(out / 'ui_layout.json', layout)
    save(out / 'catalogue.json', catalogue)  # all races, research only (RACES_RESEARCH.md)
    progress(72, 'Quests, items and sound')
    save(out / 'encounters.json', build_encounters(source))  # Mausoleum quests, encounter unit ANI (ENCOUNTERS_RESEARCH.md)
    save(out / 'items.json', build_items(source))  # Items.xcr items/sets and skill names (HERO_RESEARCH.md, milestone 11)
    save(out / AUDIO_MANIFEST, build_audio(source, out, manifest))  # original sounds and music, unchanged bytes (AUDIO_RESEARCH.md)
    save(out / 'terrain_metadata.json', dict(status='verified static engine prefab order and TL/TR/BL/BR crops; runtime visual comparison pending',
        world_size=[4096,3072], records=placements, collision='collision.json: evidence-labelled TER/occupancy grid'))
    name, body, provenance = entries['ahkx.ani']
    ani = decode_ani(body)
    ani['source'] = provenance
    ani['raw_hex'] = body.hex()
    (out / name).write_bytes(body)
    save(out / 'AHKX.ani.json', ani)
    sprites = {}
    for slot in ani['slots'][:5]:
        key = 'ahkx'+slot['suffix']+'.rle'
        name, body, provenance = entries[key]
        (out / name).write_bytes(body)
        image, info = decode(out / name)
        columns, rows = validate_sheet(slot, image.size)
        image.save(out / (name+'.png'))
        sprites[name] = dict(source=provenance, verified_sheet_size=list(image.size),
            ani_slot=slot['slot'], ani_byte_offset=slot['byte_offset'],
            ani_raw_word_02=slot['raw_word_02'], ani_unknown_words=slot['unknown_words'],
            frame_size=slot['frame_size'], frame_count=slot['frame_count'], pivot=slot['pivot'],
            offset=[-v for v in slot['pivot']], sheet_columns=columns, directions=rows,
            direction_labels=DIRECTIONS, direction_status='artwork-facing inspection; original runtime comparison pending',
            palette_index=0, palette_status='temporary choice; eight source palettes',
            timing=dict(status='unverified: ANI does not establish a uniform FPS', preview_fps=10),
            playback_policy='viewer preview only; original loop/end/event behavior unverified')
    save(out / 'sprite_metadata.json', dict(schema=2, sprites=sprites,
        animation_record=dict(source=ani['source'], raw_hex=ani['raw_hex'], decoded_file='AHKX.ani.json',
            status='frame counts, dimensions, pivots and suffix slots decoded; remaining words preserved')))
    progress(78, 'Unit, building and effect art')
    art = art_data.build_art(out, manifest, entries, {**sheets, **entries}, source, ui_bitmaps, map_codes, art_units,
                             art_buildings, catalogue)  # ART_RESEARCH.md, EFFECTS_RESEARCH.md
    # G-2 gate: every ARM / BUI code of the catalogue has an art record; every enabled sheet is imported or skip-listed.
    require(set(catalogue['units']) <= set(art['units']) and set(catalogue['buildings']) <= set(art['buildings']),
            'Catalogue codes without art records')
    require(not any(c.lower() + '.ani' in ani_names for c in art['roster_gaps']),
            'A roster id without a catalogue record has an ANI')
    save(out / 'art.json', art)
    print(f"Art: {len(art['units'])} units, {len(art['buildings'])} buildings, {len(art['effects'])} effects, "
          f"{len(art['icons'])} icons; {len(art['skip_list'])} sheets on the reasoned skip list (art.json skip_list)")
    progress(92, 'Recording the import')
    save(out / 'import_manifest.json', dict(schema=1, map_sha256=MAP_HASH,
        inputs={p.relative_to(source).as_posix():sha(p) for p in inputs},
        tools={p.name:sha(p) for p in sorted(Path(__file__).parent.glob('*.py')) if not p.name.startswith(RESEARCH_TOOLS)},
        pillow_version=pillow_version,
        outputs=output_hashes(out),
        source_policy='Base Assets archives; byte-identical patch equivalents retained; differing required overrides rejected'))


# Research tools write fixtures, never assets: a change to one must not ask for a re-import.
RESEARCH_TOOLS = ('test_', 'emulate_', 'inspect_', 'observe_')


def check(source, assets):
    manifest = json.loads((assets / 'import_manifest.json').read_text())
    require(manifest['schema'] == 1 and manifest['map_sha256'] == MAP_HASH, 'Unknown import baseline')
    require(manifest['pillow_version'] == pillow_version, 'Pillow version changed; regenerate assets')
    require(set(manifest['inputs']) == {p.relative_to(source).as_posix() for p in source_files(source)},
            'Source inventory changed; regenerate assets')
    for name, digest in manifest['tools'].items():
        require(sha(Path(__file__).parent / name) == digest, 'Importer changed; regenerate assets')
    for name, digest in manifest['inputs'].items():
        require(sha(source / name) == digest, f'Source changed: {name}')
    for name, digest in manifest['outputs'].items():
        require(sha(assets / name) == digest, f'Output missing or modified: {name}; rerun importer')
    require({'map.json','terrain.png','sprite_metadata.json','terrain_metadata.json',
        'map_objects.json','production.json','catalogue.json','encounters.json','items.json','art.json','BKK0.RLE.png','BKK0z.RLE.png','AHBXw.RLE.png','AHKX.RLE.png','AHKXw.RLE.png','AHKXf.RLE.png','AHKXd.RLE.png',
        'AHKXa.RLE.png','AHKX.ani.json','collision.json','terrain_validation.json','scenario_minimap.png',
        'collision_walk.png','collision_build.png','collision_height.png','collision_material.png','collision_objects.png',
        'ui_layout.json','EMA0.RLE.png','EMM0.RLE.png','EF01.RLE.png','EX02.RLE.png','EZ08.RLE.png','AHMXi.RLE.png','BKK0i.RLE.png','icons_skills.png','icons_items.png','ui_bm_BM_MAINMENU.png','ui_bm_BM_BUTTON200.png','ui_font_BigFont.ttf','ui_font_MainFont.ttf','ui_x_Panel_800.png','ui_x_EMDG.png','ui_x_icon_AHKX.png',
        AUDIO_MANIFEST} <= set(manifest['outputs']), 'Incomplete import')
    require({f'maps/{reader.map_slug(name)}/{file}' for name in MAPS for file in MAP_FILES} | {'terrain/tiles.json', 'maps/index.json'}
            <= set(manifest['outputs']), 'Incomplete map import')
    require(random_map_data.OUTPUT in manifest['outputs'], 'Incomplete random map import')  # RM-1
    require(particle_data.OUTPUT in manifest['outputs'], 'Incomplete particle import')     # wave 5
    require(FEATURE_OUTPUT in manifest['outputs'], 'Incomplete feature presentation import')   # RM-3
    audio = check_audio(assets)
    print(f"Import checks passed: {len(manifest['inputs'])} source files, {len(manifest['outputs'])} outputs, {len(audio['entries'])} audio files")


def main():
    global PROGRESS_FILE
    # importer.exe (packaging/build_importer.ps1): the defaults would point inside the bundle, so both are required there.
    frozen = getattr(sys, 'frozen', False)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=None if frozen else GAME)
    parser.add_argument('--dest', type=Path, default=None if frozen else PROJECT / 'assets',
                        help="Output folder (default: this project's assets/; the installer passes the game's assets folder)")
    parser.add_argument('--progress-file', type=Path, help="Keep 'PROGRESS <percent> <label>' in this file while importing")
    parser.add_argument('--check', action='store_true', help='Validate existing output and source hashes without writing')
    args = parser.parse_args()
    require(args.source is not None and args.dest is not None,
            'importer.exe needs --source <Warlords Battlecry III folder> and --dest <output folder>')
    require(pillow_version == '12.2.0', 'Install dependencies: python -m pip install -r requirements.txt')
    source = args.source.resolve()
    assets = args.dest.resolve()
    PROGRESS_FILE = args.progress_file.resolve() if args.progress_file else None
    if args.check:
        check(source, assets)
        return
    preflight(source)
    assets.parent.mkdir(parents=True, exist_ok=True)
    # Staging beside the output (same drive): the output is replaced only after the staged import passes its checks.
    with tempfile.TemporaryDirectory(prefix='wbc-import-', dir=assets.parent) as temp:
        staging = Path(temp)
        generate(source, staging)
        progress(94, 'Checking the import')
        check(source, staging)
        progress(97, 'Copying into place')
        assets.mkdir(exist_ok=True)
        for path in sorted(staging.iterdir()):
            if path.is_dir():
                shutil.copytree(path, assets / path.name, dirs_exist_ok=True)   # assets/audio (hashes in audio_manifest.json)
            else:
                shutil.copyfile(path, assets / path.name)
    check(source, assets)
    progress(100, 'Done')

if __name__ == '__main__':
    # Exit codes for the installer: 0 done, 1 failed, 3 a different version of the game (preflight).
    try:
        main()
    except UnsupportedSource as error:
        print(f'Unsupported game version: {error}', file=sys.stderr)
        sys.exit(3)
    except (OSError, ValueError, AssertionError, struct.error) as error:
        raise SystemExit(f'Import failed: {error}')
