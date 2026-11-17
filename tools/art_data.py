"""Original art for every unit, building and effect the rebuild shows (ART_RESEARCH.md) -> assets/art.json + sheets.

Evidence (decompile/disassembly of the pinned executable, labels as in ART_RESEARCH.md):
* ANI: nine 26-byte slots (ani.decode_ani); suffix table 0x60e054 ('', w, f, d, a, z, c, s, i). Bytes +2/+3 of a slot are the
  pixel/shadow blend modes the sprite renderer 0x487f20 reads when its caller passes -1 (Read).
* Buildings (vtable 0x5eaee0: draw +0x14 = 0x53ae40, depth +0x34 = 0x53ab30): the sprite is drawn at the building's pixel
  position (+0x4c/+0x4e = anchor cell * (32, 24) + (16, 12), 0x5350a0) with ANI slot +0x38 and column +0x3c, in the owner's
  colour (word 0x708f9a + player * 0x2c). Construction uses slot 5 ('z'): column 0 when placed (0x4a6f80), 1 from 34 %,
  2 from 67 % (0x52c404..0x52c450), standing slot 0 on completion (0x52bfd0); each change starts a 16-step cross-fade
  (0x53c130). A destroyed building shows slot 5 column 0 as rubble (0x52b3e0) for 120 s. Damage fires EF01..EF03 are
  separate effect objects at BUI +0x6a + 4 i (x, y), lit below 3/4, 1/2 and 1/4 of the hit points (0x52b7xx, 0x53bba0).
* Team colour: 0x487f20 copies the owner's 15-entry ramp (table 0xa38ba4, built by 0x494450) over palette entries
  224..238; rle.team_mask() records those pixels so Godot can recolour them (team_colour.gdshader).
* Effects (EF0x, EX01, EX02, EZ08, EZ55, EMA0, EMM0), the item sheet IDLG and the icons (slot 8) use the 'RL' sheet
  format, decoded by rl.py from the loader 0x4879f0 and the renderer 0x487f20 (EFFECTS_RESEARCH.md section 1): each
  is written as a palette-0 RGBA PNG with its ANI blend bytes applied (translucency band 0xef..0xfe as alpha for mode
  0xf, the shadow band as black alpha for mode 1).
* Icons (EFFECTS_RESEARCH.md section 4): slot 8 of a unit/building ANI; 0x487f20 draws column 0 as the frame-sized
  portrait and, for columns 1..5, fixed regions below it (32x50 at (0, H) and (33, H); 90x90 at (0, H + 50) and
  (0, H + 140); a 50x47 or 22x19 face at (90, H + 50) by slot 8 word +0x16). Hero items come from BM_HERO_ITEMS
  (Items.bmp, 70x110 cells, 0x5a64e0) and the small UI icons from BM_SKILLICONS (SkillIcons.bmp).
"""
import struct

from ani import decode_ani, DIRECTIONS, SUFFIXES as ANI_SUFFIX
from original_reader import cipher_inverse
from rle import decode, team_mask, TEAM_FIRST, TEAM_COUNT
from rl import decode_rl, header, team_mask as rl_team_mask

# Every unit type the slice can put on the map (ENCOUNTERS_RESEARCH.md, PRODUCTION_RESEARCH.md). The lair boss is AMJX
# at level 18 (lair table 0x5fb338 row 2). Quest reward types (Quest.xcr Bzma.dat) are listed as Open in ART_RESEARCH.md.
UNITS = ['AHBX', 'AHKX', 'AHMX', 'AHHX', 'AMJX', 'ACCA', 'ACTU']
# Buildings the production slice creates; map buildings come from map.json.
BUILDINGS = ['BKK0', 'BKK1', 'BAGA', 'BPFL']
# Milestone 11a: the Dwarves (race 1) end to end. Every unit and building of their Building.cfg rows (D0 construction,
# the Citadel / Armory / Foundry / College menus, the siege engines and the lord) plus their hero ADHX (0x42a0d0's race
# switch, the computer player's hero).
UNITS += ['ADBX', 'ADSX', 'ADIX', 'ADMX', 'ADJX', 'ADLX', 'ADOX', 'ADNX', 'ADGX', 'ASBA', 'ASCA', 'ATDX', 'ADHX']
BUILDINGS += ['BKD0', 'BKD1', 'BKD2', 'BKD3', 'BKD4', 'BAAR', 'BPFO', 'BPWS', 'BPTP', 'BWMO', 'BPBR', 'BPCL']
# The Swarm (race 14), Desert Sands' second side race and the setup's default for slot 1: their R0 row, hall and hive
# upgrades and every ground unit those buildings train, plus their hero ARHX.
UNITS += ['ARBX', 'ARJX', 'ARMX', 'ARIX', 'ARCX', 'ARGX', 'ASBC', 'ATRX', 'ARHX']
# Milestone 11b: every race's hero unit (the art 0x54bee0 writes into a new hero record, record +0x5c), so a hero of any
# race created in the hero book appears as itself (HERO_RESEARCH.md "Milestone 11b").
UNITS += ['AUHX', 'AMHX', 'ABHX', 'AOHX', 'AEHX', 'AWHX', 'AKHX', 'AFHX', 'AAHX', 'AVHX', 'APHX', 'ALHX', 'AHH1']
BUILDINGS += ['BKR0', 'BKR1', 'BKR2', 'BKR3', 'BKR4', 'BAH0', 'BAH1', 'BAH2', 'BAH3', 'BAH4', 'BABC', 'BPEC', 'BPWA',
              'BPSQ', 'BPSK']
# Parity pass 3: the Knights roster of milestone 13 (every unit and building its pages train or build) had no world art,
# and the scenario towers take their owner's race (0x4a50f0 swaps BWT? by the race at 0x708f96): every race's tower.
UNITS += ['AHFX', 'AHDX', 'AHEX', 'AHLX', 'AHGX', 'ATHX', 'AAEG', 'AAPE', 'AADR', 'AADC', 'AAAR']
BUILDINGS += ['BKK2', 'BKK3', 'BKK4', 'BPSM', 'BPSB', 'BPMA', 'BAV0', 'BAV1', 'BAV2', 'BPSS', 'BPCA', 'BWG0', 'BWG1',
              'BWG2', 'BWRA'] + ['BWT' + c for c in 'CDUBROMWKFAVHLEG' if c not in 'DE']
# G-2 (ART_RESEARCH.md "G-2", CONTENT_EXPANSION_PLAN.md W3): every ARM and BUI code of catalogue.json joins the lists
# above at import time (art_lists()): the 16 race rosters (content_inventory.race_rosters), the neutral and map codes
# (animals, lair guards, lairs, shops, mines, temples) and the quest / scenario types. Every catalogue code has an ANI.
# Units whose idle sheet is one row draw every facing from it (the temple elementals AAEA / AAEF / AAEW, the Soul ACSO;
# BATCH1_RESEARCH.md section 4 item 4): their one-row sheets carry one_row_facings and unit_agent.gd clamps the facing
# row to the sheet's rows, so row 0 serves every facing.
ONE_ROW_UNITS = {'AAEA', 'AAEF', 'AAEW', 'ACSO'}
# Sheets present and enabled but not imported, with the reason (art.json skip_list; a unit keeps them in
# undecoded_rl_sheets / undecoded_reasons, an effect in effects_skipped).
SKIPPED_SHEETS = {'atrxd.rle': 'Open (BATCH1_RESEARCH.md Open 7): the sheet is a 197 x 184 grid of 12 frames, its ANI '
                               'slot says 194 x 130 and 11 frames',
                  'ez39.rle': 'Open: shadow mode 5 = lighting routine 0x48a930, which moves the 565 channels separately '
                              '(red down, blue up, green kept; Emulated, tests/blend_fixtures.json): no RGBA alpha form',
                  'eosr.rle': 'Open: the sheet is 109 x 109, its ANI slot says one 108 x 108 frame (not a grid)'}
# Enabled ANI slots without any sheet in the archives (Read: the archives hold no <code><suffix>.RLE): nothing to draw.
NO_SHEET_REASON = 'the ANI enables the slot but no archive holds its sheet (nothing to draw)'
# Missiles drawn without a sheet: 0x53f180 gives these ids colour bytes (+0x67c / +0x67d and +0x82b = 1 for the EMF
# fire family, +0x816.. colour rows with flags 0x2021 for EMM1 / EMM2 / EMM4), so their ANI has no sheet (Read).
PROCEDURAL_MISSILES = {'EMF1', 'EMF2', 'EMF3', 'EMF4', 'EMF5', 'EMF6', 'EMM1', 'EMM2', 'EMM4'}
EFFECTS = {'EF01': 'damage fire 1 (0x53bba0)', 'EF02': 'damage fire 2', 'EF03': 'damage fire 3',
           'EX01': 'building collapse explosion (0x53b960)', 'EX02': 'building explosion at the fire points (0x53baa0)', 'EZ08': 'lair spawn effect (lair table 0x5fb338)',
           'EZ55': 'lair boss item effect (0x4a49e0)', 'EMA0': 'arrow: Squire, Dwarven Tower (Army.cfg / Building.cfg P:EMA0)',
           'EMM0': 'Swarm Tower shot (Building.cfg M:EMM0)',
           'EZ01': 'conversion flash on each converted building in view (0x4a6cc0, played once)',
           'EZ56': 'conversion pose effect, started by each slot 6 cycle (0x536cc0)'}
# Spell record effects (SPELLS_RESEARCH.md, B1-4 / B1-6a; the records Emulated in tests/spell_fixtures.json and
# tests/hero_spell_fixtures.json): +0x8d on the caster, +0x91 on each affected target or at a created unit / building,
# +0x85 on each affected target while its status lasts. ERUC (the Runes casts' +0x8d) has no ANI in the archives.
SPELL_EFFECT_ROLES = {
    'EZ00': 'spell: Earthpower heal on each building (+0x91); the Naga cast (+0x8d)',
    'EZ05': 'spell: Black Portal, at the new portal (+0x91, message 0x1f9)',
    'EZ06': 'spell: Ring of Fire cast (+0x8d)', 'EZ07': 'spell: Ring of Ice cast (+0x8d)',
    'EZ14': 'spell: Fire Elemental summon (+0x91)', 'EZ15': 'spell: the Harpy drain (+0x8d / +0x91)',
    'EZ19': 'Dark Citadel / Rites of Dawn day-night record (kind 4, +0x8d)',
    'EZ20': 'spell: Cure (+0x8d / +0x91)', 'EZ26': 'spell: Vampirism status on each target (+0x85)',
    'EZ27': 'spell: Necromancy cast on the caster (Vampirism, Darkstorm, Strip Flesh, +0x8d)',
    'EZ30': 'spell: Famine (+0x8d)', 'EZ34': 'spell: Summon Imp / Stonecall summon (+0x91)',
    'EZ35': 'spell: Summon Guardian, at the new statue (+0x91, message 0x1f9)',
    'EZ40': 'spell: Resist Missile status on the caster (+0x85)',
    'EZ41': 'spell: Strip Flesh, at each new Skeleton (+0x91, message 0xfa)',
    'EZ44': 'Zombie scavenging record (kind 0x1c, +0x8d on the Zombie)',
    'EZ78': 'spell: Call the Dead cast (+0x8d)',
}
UNIT_SLOTS = range(8)          # slot 8 (icon) is an RL image, imported by icon_sheet()
ICON_SLOT = 8
ITEM_SHEET = 'IDLG'            # item portraits (ANI IDLG slot 0: 70 x 110 frames), loaded by 0x41a650 from Effects1.xcr
# Treasure piles (0x4a7870 -> 0x58bd20('IMAP', 0, 4, 1), Read): Effects1.xcr IMAP, 75 x 60 cells, 2 x 5; the resource carts
# and, in row 4, the closed / open chest.
TREASURE_SHEET = 'IMAP'
# Effect frame interval of the effect class (0x53c870): 50 ms, 120 ms for EX01..EX04, 10 s for EDB*/EDT*.
EFFECT_INTERVAL_MS = {'EX01': 120, 'EX02': 120}


def effect_interval_ms(code):
    if code in EFFECT_INTERVAL_MS or code[:3] == 'EX0' and code[3] in '1234':
        return EFFECT_INTERVAL_MS.get(code, 120)
    return 10000 if code[:3] in ('EDB', 'EDT') else 50


def effect_codes(all_entries):
    """EFFECTS first (their roles are traced), then every other E??? ANI in the archives, sorted (G-2)."""
    found = sorted({k[:4].upper() for k in all_entries if k[0] == 'e' and k.endswith('.ani') and len(k) == 8})
    return list(EFFECTS) + [c for c in found if c not in EFFECTS]
UI_ATLASES = {'skillicons.bmp': 'icons_skills.png', 'items.bmp': 'icons_items.png'}
# 0x494450, 16-bit 565 branch: colour c, step k: R8 = r0 + k*dr, G8 = g0 + k*dg, B8 = b0 + k*db (bytes), packed 565.
TEAM_RAMP_PARAMS = [(0x28, 7, 0, 3, 0, 3), (0, 3, 0x14, 4, 0x32, 7), (0, 2, 0x28, 7, 0, 3), (0x28, 6, 3, 3, 0x28, 6),
                    (0, 5, 0, 5, 0, 5), (0x32, 6, 0x28, 5, 0, 0), (0x28, 4, 0x28, 4, 0x28, 4), (0x3c, 11, 0x3c, 11, 0, 0)]
CONSTRUCTION_STAGE_PERCENT = [0, 34, 67]   # 0x52c404 (0x22) and 0x52c436 (0x43)


def team_ramps():
    """RGB triplets (8-bit, expanded from 565 exactly like rle.c565) for the eight colours x 15 steps."""
    out = []
    for r0, dr, g0, dg, b0, db in TEAM_RAMP_PARAMS:
        ramp = []
        for k in range(TEAM_COUNT):
            r5 = ((r0 + k * dr) & 0xff) >> 3
            g6 = ((g0 + k * dg) & 0xff) >> 2
            b5 = ((b0 + k * db) & 0xff) >> 3
            ramp.append([r5 * 255 // 31, g6 * 255 // 63, b5 * 255 // 31])
        out.append(ramp)
    return out


def map_building_codes(manifest, codes=None):
    """Building ids placed on the map; `codes` overrides with the union over every imported map (W1)."""
    return sorted(codes) if codes is not None else sorted({r['code'] for r in manifest['buildings']})


def art_lists(catalogue, map_codes=()):
    """(units, buildings) to import: UNITS / BUILDINGS, then every other ARM / BUI code of the catalogue in sorted order
    (existing entries keep their place; map buildings of the imported maps stay with map_objects' import). Every code
    of the 16 race rosters is then imported, except roster_gaps()."""
    units, buildings = list(UNITS), list(BUILDINGS)
    units += sorted(set(catalogue['units']) - set(units))
    buildings += sorted(set(catalogue['buildings']) - set(buildings) - set(map_codes))
    return units, buildings


def roster_gaps(catalogue):
    """Roster ids without a catalogue record -> the races naming them. Only Building.cfg dependency rows name such ids
    (AAAG, the Barbarians' row 151 'B AAAG : ---- ---- ---- ---- 050'); the import requires that no archive holds an
    ANI for them, so there is no art to import (art.json roster_gaps)."""
    from content_inventory import race_rosters
    known = set(catalogue['units']) | set(catalogue['buildings'])
    gaps = {}
    for race, roster in race_rosters(catalogue).items():
        for code in sorted(set(roster['units']) | set(roster['buildings'])):
            if code not in known:
                gaps.setdefault(code, []).append(race)
    return gaps


def wanted_entries(manifest, map_codes=None, units=None, buildings=None):
    """Archive entries (lower case) the art import reads; import_assets adds them to its required set."""
    wanted = set()
    for code in UNITS if units is None else units:
        wanted |= {code.lower() + '.ani', code.lower() + '.arm'}
    for code in (BUILDINGS if buildings is None else buildings) + map_building_codes(manifest, map_codes):
        wanted |= {code.lower() + '.ani', code.lower() + '.bui'}
    for code in EFFECTS:
        wanted.add(code.lower() + '.ani')
    wanted.add(ITEM_SHEET.lower() + '.ani')
    wanted.add(TREASURE_SHEET.lower() + '.ani')
    return wanted


def optional_sheets(entries, code, slots):
    """(slot, entry key) for every enabled slot whose sheet exists in the archives (ANI enables slots without art)."""
    return [(s, (code + s['suffix'] + '.rle').lower()) for s in slots if (code + s['suffix'] + '.rle').lower() in entries]


def _sheet(out, entries, all_entries, code, slot, texture, columns_from_sheet=False, rows_expected=None, reuse=False):
    key = (code + slot['suffix'] + '.rle').lower()
    name, raw, provenance = all_entries[key]
    temp = out / ('_art_' + key)
    temp.write_bytes(raw)
    try:
        if raw[:2] != b'RS':
            raise ValueError(f'{key}: not an RS sheet')
        if reuse and (out / texture).exists():
            from PIL import Image
            with Image.open(out / texture) as existing:
                size = existing.size
        else:
            image, _ = decode(temp)
            image.save(out / texture)
            size = image.size
        mask_name = texture[:-4] + '.team.png'
        mask = team_mask(temp)
        mask.save(out / mask_name)
        team_pixels = sum(mask.histogram()[1:])
    finally:
        temp.unlink()
    return _grid_record(key, size, slot, texture, mask_name, team_pixels, provenance, name, columns_from_sheet,
                        rows_expected)


def _rl_sheet_layers(out, all_entries, code, slot, texture, rows_expected=None, columns_from_sheet=False):
    """An RL unit sheet in the RS sheets' form: palette-0 RGBA with the slot's blend bytes (rl.decode_rl) and the team
    mask (rl.team_mask), with _sheet's grid checks and record (BATCH1_RESEARCH.md section 4 items 1-3)."""
    key = (code + slot['suffix'] + '.rle').lower()
    name, raw, provenance = all_entries[key]
    if raw[:2] != b'RL':
        raise ValueError(f'{key}: not an RL sheet')
    blend = struct.unpack_from('<BB', bytes.fromhex(slot['decoded_hex']), 2)
    image, _ = decode_rl(raw, blend[0], blend[1], palette=0)
    image.save(out / texture)
    mask_name = texture[:-4] + '.team.png'
    mask = rl_team_mask(raw)
    mask.save(out / mask_name)
    record = _grid_record(key, image.size, slot, texture, mask_name, sum(mask.histogram()[1:]), provenance, name,
                          columns_from_sheet, rows_expected)
    record['sheet_format'] = 'RL'
    return record


def _grid_record(key, size, slot, texture, mask_name, team_pixels, provenance, name, columns_from_sheet, rows_expected):
    w, h = slot['frame_size']
    if size[0] % w or size[1] % h:
        raise ValueError(f'{key}: sheet {size} is not a grid of {w}x{h}')
    columns, rows = size[0] // w, size[1] // h
    if rows_expected is not None and rows not in ((rows_expected,) if isinstance(rows_expected, int) else rows_expected):
        raise ValueError(f'{key}: {rows} rows, expected {rows_expected}')
    if not columns_from_sheet and columns < slot['frame_count']:
        raise ValueError(f'{key}: {columns} columns for {slot["frame_count"]} ANI frames')
    blend = struct.unpack_from('<BB', bytes.fromhex(slot['decoded_hex']), 2)
    return dict(texture=texture, team_mask=mask_name, team_pixels=team_pixels, source=provenance, entry=name,
                ani_slot=slot['slot'], ani_byte_offset=slot['byte_offset'], suffix=slot['suffix'],
                frame_size=slot['frame_size'], pivot=slot['pivot'], offset=[-v for v in slot['pivot']],
                frame_count=slot['frame_count'], sheet_columns=columns, rows=rows, verified_sheet_size=list(size),
                ani_raw_word_02=slot['raw_word_02'], blend_bytes=list(blend), ani_unknown_words=slot['unknown_words'],
                direction_labels=DIRECTIONS if rows == 8 else ['-'] * rows)


def _decode_rs(out, key, raw):
    """An RS sheet through rle.decode (palette 0), as the unit and building sheets are decoded."""
    temp = out / ('_art_' + key)
    temp.write_bytes(raw)
    try:
        image, _ = decode(temp)
    finally:
        temp.unlink()
    return image


def rl_sheet(out, all_entries, code, suffix, slot, role):
    """Decode an RL sheet with the blend bytes of its ANI slot (rl.decode_rl) -> <CODE><suffix>.RLE.png. RS-format
    effect and icon sheets (G-2: EDBA, EDBD, EMA1, the EMD* family, 16 building icons) go through rle.decode."""
    key = (code + suffix + '.rle').lower()
    name, raw, provenance = all_entries[key]
    blend = list(struct.unpack_from('<BB', bytes.fromhex(slot['decoded_hex']), 2))
    if raw[:2] == b'RS':
        image, info = _decode_rs(out, key, raw), dict(tail=header(raw)['tail'], additive=False)
    elif raw[:2] == b'RL':
        image, info = decode_rl(raw, blend[0], blend[1], palette=0)
    else:
        raise ValueError(f'{key}: not an RL or RS sheet')
    texture = code + suffix + '.RLE.png'
    w, h = slot['frame_size']
    if suffix != 'i' and (image.size[0] % w or image.size[1] % h):
        raise ValueError(f'{key}: sheet {image.size} is not a grid of {w}x{h}')
    image.save(out / texture)
    record = dict(role=role, texture=texture, source=provenance, entry=name, sheet_format=raw[:2].decode(),
                  frames=slot['frame_count'], frame_size=slot['frame_size'], pivot=slot['pivot'], blend_bytes=blend,
                  columns=image.size[0] // w, rows=image.size[1] // h, verified_sheet_size=list(image.size),
                  rl_header=info['tail'], status='decoded (rl.py, Read from 0x4879f0 / 0x487f20)')
    if info['additive']:
        record['godot_blend'] = 'add'      # mode 0x10: 0x48f130 adds the colour to the screen (rl.py, Emulated)
    return record


def icon_regions(slot):
    """Source rectangles of the icon columns (0x487f20 slot 8 branch): column -> [x, y, w, h]."""
    w, h = slot['frame_size']
    face_w = 0x32 if slot['unknown_words']['0x16'] > 1 else 0x16
    face_h = 0x2f if slot['unknown_words']['0x16'] > 0 else 0x13
    return {'0': [0, 0, w, h], '1': [0, h, 32, 50], '2': [33, h, 32, 50], '3': [0, h + 50, 90, 90],
            '4': [0, h + 140, 90, 90], '5': [90, h + 50, face_w, face_h]}


def icon_sheet(out, all_entries, code, slot):
    sheet = rl_sheet(out, all_entries, code, 'i', slot, 'icon (ANI slot 8)')
    regions = icon_regions(slot)
    width, height = sheet['verified_sheet_size']
    # G-2: BWBR (Wall of Thorns) has a 140 x 140 icon sheet, the portrait only: the regions below it are not in the sheet
    # (what 0x487f20 reads there is Open); they are left out, so ArtData.icon() returns null for those columns.
    inside = {k: r for k, r in regions.items() if r[0] + r[2] <= width and r[1] + r[3] <= height}
    sheet['regions'] = inside
    if len(inside) < len(regions):
        sheet['regions_outside_sheet'] = sorted(set(regions) - set(inside))
    sheet['uses'] = {'0': 'large portrait (0x4d7710 info view)', '1': 'production button (0x4d7710, 0x569xxx)',
                     '3': 'selection panel portrait (0x4d7710)', '4': 'selection portrait under fog (0x4d7710)',
                     '5': 'small face (0x4ddd30)'}
    return sheet


def _shooters(catalogue):
    """Effect code -> unit and building codes whose Army.cfg / Building.cfg shoot field names it."""
    found = {}
    for a in (catalogue or {}).get('army_cfg', {}).get('armies', []):
        if a.get('shoot'):
            found.setdefault(a['shoot']['effect_code'], []).append(a['code'])
    for code, record in sorted((catalogue or {}).get('buildings', {}).items()):
        shoot = (record.get('building_cfg') or {}).get('shoot')
        if shoot:
            found.setdefault(shoot['effect_code'], []).append(code)
    return {k: sorted(set(v)) for k, v in found.items()}


def build_art(out, manifest, entries, all_entries, source, ui_bitmaps=None, map_codes=None, unit_codes=None,
              building_codes=None, catalogue=None):
    """entries: required importer lookup; all_entries: every archive entry (sheets are optional per ANI);
    unit_codes / building_codes: art_lists() (default UNITS / BUILDINGS); catalogue: names the shooters of each
    effect code (roles of the effects outside EFFECTS)."""
    from production_data import names
    inverse = cipher_inverse()
    unit_codes = UNITS if unit_codes is None else unit_codes
    building_codes = BUILDINGS if building_codes is None else building_codes
    display = names(source, set(unit_codes) | set(building_codes) | set(map_building_codes(manifest, map_codes)))
    skip_list = []
    units = {}
    for code in unit_codes:
        _, body, ani_source = entries[code.lower() + '.ani']
        ani = decode_ani(body)
        _, arm_raw, arm_source = entries[code.lower() + '.arm']
        arm = arm_raw.translate(inverse)
        sheets = {}
        rl_sheets = []
        enabled = [s for s in ani['slots'] if s['slot'] in UNIT_SLOTS and s['enabled']]
        present = {s['slot'] for s, _ in optional_sheets(all_entries, code, enabled)}
        missing = {str(s['slot']): NO_SHEET_REASON for s in enabled if s['slot'] not in present}
        skip_list += [dict(code=code, slot=int(s), entry=(code + ANI_SUFFIX[int(s)] + '.rle').lower(), reason=r)
                      for s, r in missing.items()]
        for slot, key in optional_sheets(all_entries, code, enabled):
            if key in SKIPPED_SHEETS:
                rl_sheets.append(key)
                skip_list.append(dict(code=code, slot=slot['slot'], entry=key, reason=SKIPPED_SHEETS[key]))
                continue
            texture = code + slot['suffix'] + '.RLE.png'
            # Slot 6 ('c') draws one row; deaths of fliers, dragons and siege engines are one row, the rest eight;
            # one-row units (ONE_ROW_UNITS) draw every facing from one row.
            rows = 1 if slot['suffix'] == 'c' or code in ONE_ROW_UNITS else (1, 8) if slot['suffix'] == 'd' else 8
            if all_entries[key][1][:2] == b'RL':
                sheets[str(slot['slot'])] = _rl_sheet_layers(out, all_entries, code, slot, texture, rows_expected=rows)
            else:
                sheets[str(slot['slot'])] = _sheet(out, entries, all_entries, code, slot, texture, rows_expected=rows,
                                                   reuse=code == 'AHKX')
            if code in ONE_ROW_UNITS:
                sheets[str(slot['slot'])]['one_row_facings'] = True
        units[code] = dict(name=display.get(code, code), ani_source=ani_source, arm_source=arm_source, sheets=sheets,
            ani_enabled=[s['slot'] for s in ani['slots'] if s['enabled']],
            walk_weights_0xd3=list(arm[0xd3:0xd3 + 32]), step_factors_0xf8=list(struct.unpack_from('<4h', arm, 0xf8)),
            type_flags_0x104=struct.unpack_from('<H', arm, 0x104)[0], undecoded_rl_sheets=rl_sheets,
            undecoded_reasons={k: SKIPPED_SHEETS[k] for k in rl_sheets}, missing_sheets=missing,
            status='sheets and ANI geometry decoded; step timing still uses the Swordsman walk count (movement code unchanged)')
    buildings = {}
    map_codes = map_building_codes(manifest, map_codes)
    for code in building_codes + map_codes:
        _, body, ani_source = entries[code.lower() + '.ani']
        ani = decode_ani(body)
        _, bui_raw, bui_source = entries[code.lower() + '.bui']
        bui = bui_raw.translate(inverse)
        sheets = {}
        enabled = [s for s in ani['slots'] if s['slot'] < 8 and s['enabled']]
        present = {s['slot'] for s, _ in optional_sheets(all_entries, code, enabled)}
        missing = {str(s['slot']): NO_SHEET_REASON for s in enabled if s['slot'] not in present}
        skip_list += [dict(code=code, slot=int(s), entry=(code + ANI_SUFFIX[int(s)] + '.rle').lower(), reason=r)
                      for s, r in missing.items()]
        for slot, key in optional_sheets(all_entries, code, enabled):
            if all_entries[key][1][:2] == b'RL':
                # G-2: RL building sheets (BPRB's standing sheet, modes (1, 13)) in the RS sheets' form.
                texture = code + slot['suffix'] + '.RLE.png'
                sheets[str(slot['slot'])] = _rl_sheet_layers(out, all_entries, code, slot, texture, rows_expected=1,
                                                             columns_from_sheet=True)
                continue
            if slot['slot'] == 0 and code in map_codes:
                texture = code + '.object.rle.png'        # written by map_objects.py (milestone 5), identical decode
                sheets['0'] = _sheet(out, entries, all_entries, code, slot, texture, columns_from_sheet=True, reuse=True)
                continue
            texture = code + slot['suffix'] + '.RLE.png'
            sheets[str(slot['slot'])] = _sheet(out, entries, all_entries, code, slot, texture, columns_from_sheet=True,
                                               rows_expected=1)
        height = bui[63]
        depth = ((height * 24 - 24) >> 1) or 1
        buildings[code] = dict(name=display.get(code, code), ani_source=ani_source, bui_source=bui_source, sheets=sheets,
            footprint=[bui[62], height], depth_offset=depth,
            fire_offsets=[list(struct.unpack_from('<2h', bui, 0x6a + 4 * i)) for i in range(3)],
            construction_columns=sheets['5']['sheet_columns'] if '5' in sheets else 0,
            standing_interval_ms=ani['slots'][0]['unknown_words']['0x18'] or 100,
            map_building=code in map_codes, missing_sheets=missing,
            ani_enabled=[s['slot'] for s in ani['slots'] if s['enabled']])
    effects, effects_skipped = {}, {}
    shooters = _shooters(catalogue)
    roles = dict(SPELL_EFFECT_ROLES, **EFFECTS, **{ITEM_SHEET: 'hero item portraits (70 x 110 cells)',
                                                      TREASURE_SHEET: 'treasure pile on the ground (0x4a7870: column 0, row 4)'})
    for code in effect_codes(all_entries) + [ITEM_SHEET, TREASURE_SHEET]:
        _, body, ani_source = all_entries[code.lower() + '.ani']
        slot = decode_ani(body)['slots'][0]
        key = code.lower() + '.rle'
        reason = (SKIPPED_SHEETS.get(key) if key in all_entries else
                  'procedural missile: 0x53f180 draws it from colour bytes, no sheet (Read)' if code in PROCEDURAL_MISSILES
                  else NO_SHEET_REASON)
        if reason or not slot['enabled']:
            effects_skipped[code] = reason or 'ANI slot 0 is off'
            skip_list.append(dict(code=code, slot=0, entry=key, reason=effects_skipped[code]))
            continue
        role = roles.get(code) or ('missile of ' + ', '.join(shooters[code]) if code in shooters else
                                   'effect (role not traced; spell / ability effects: EFFECTS_RESEARCH.md, spell lane)')
        effects[code] = rl_sheet(out, all_entries, code, '', slot, role)
        effects[code].update(ani_source=ani_source, interval_ms=effect_interval_ms(code))
        if code in shooters:
            effects[code]['shot_by'] = shooters[code]
    icons = {}
    for code in unit_codes + building_codes + map_codes:
        _, body, _ = entries[code.lower() + '.ani']
        slot = decode_ani(body)['slots'][ICON_SLOT]
        if slot['enabled'] and (code + 'i.rle').lower() in all_entries:
            icons[code] = icon_sheet(out, all_entries, code, slot)
        elif slot['enabled']:
            skip_list.append(dict(code=code, slot=ICON_SLOT, entry=(code + 'i.rle').lower(), reason=NO_SHEET_REASON))
    atlases = {}
    for key, texture in UI_ATLASES.items():
        if ui_bitmaps is not None and key in ui_bitmaps:
            import io
            from PIL import Image
            name, raw, provenance = ui_bitmaps[key]
            with Image.open(io.BytesIO(raw)) as bitmap:
                image = bitmap.convert('RGBA')
            # Magenta (255, 0, 255) is the UI colour key (UI_RESEARCH.md hypothesis, as in xci.py's exports).
            image.putdata([(0, 0, 0, 0) if px[:3] == (255, 0, 255) else px for px in image.getdata()])
            image.save(out / texture)
            atlases[key[:-4]] = dict(texture=texture, size=list(image.size), source=provenance, entry=name)
    owners = {str(r['source_offset']): int(r.get('owner', 6)) for r in manifest['buildings']}
    shot_codes = sorted(shooters)
    return dict(schema=1, units=units, buildings=buildings, effects=effects, icons=icons, ui_atlases=atlases, map_building_owners=owners,
        roster_gaps={c: dict(races=r, reason='Building.cfg dependency row only: no ARM / BUI record and no ANI in any '
                                              'archive') for c, r in roster_gaps(catalogue).items()} if catalogue else {},
        effects_skipped=effects_skipped, skip_list=sorted(skip_list, key=lambda r: (r['code'], r['slot'])),
        shoot_codes={c: dict(shot_by=shooters[c], imported=c in effects,
                             reason=None if c in effects else effects_skipped.get(c, 'no ANI in the archives'))
                     for c in shot_codes},
        team=dict(first_index=TEAM_FIRST, count=TEAM_COUNT, ramps=team_ramps(),
                  player_colour='Decision: colour index = player index (the skirmish colour setup 0x708f9a is not traced)'),
        construction=dict(slot=5, stage_percent=CONSTRUCTION_STAGE_PERCENT, fade_steps=16, rubble_column=0,
                          rubble_ms=120000),
        evidence='ART_RESEARCH.md')
