"""Milestone 11-menus: interface art the code loads by file name or by 4CC, outside the XCI/XCG element tables.

Evidence (UI_RESEARCH.md "Milestone 11"):
* 0x4d6e00 (control panel set-up, Read) swaps bitmap 0x55 to Panel_800/1024/1280/1600.bmp by resolution, 0xbc to
  Panel_Buttons.bmp and 0xbd to Panel_Icons.bmp (FUN_00466060), 0x1d1/0x1d2 to the race's Powerups*.bmp, and the hero
  portrait 0xe to "Portrait%02d.bmp" (hero record +0x58).
* The in-game dialogs look their sheets up by 4CC in the effect sheet table (0x487050): game menu 'EMDG' 400x431 with the
  close button 'EMDC' (0x565670), options 'EMDO' 450x431 (0x566c30), message box 'EMDM' 600x300 with the yes/no
  buttons 'EMDE' (0x55c8d0). They live in Assets/Effects/Effects1.xcr.
* Sheets are 'RS' (decoded by rle.py) or 'RL'. RL (Data, every row of the sheets used here): the same header, the same
  eight RGB565 palettes and the same row table as RS; in the rows only 0xff is an escape (0xff n skips n pixels,
  0xff 0xff ends the row) and every other byte, including 0xfa..0xfe, is a palette index. Rows end at the sheet width
  without a terminator. RS uses 0xfa..0xfe for shadow pixels instead.
* Unit and building icons are the ANI slot 8 'i' sheets (RL, 144x374 / 140x370) in the race archive.
"""
import io
import struct
from PIL import Image

from rle import c565

# Graphics.xcr bitmaps the control panel loads by name (0x4d6e00) plus the loading screen art (PNL_PROGRESSHT).
NAMED_BITMAPS = ['Panel_800.bmp', 'Panel_1600.bmp', 'Panel_Buttons.bmp', 'Panel_Icons.bmp', 'Panel_Menu.bmp',
                 'Panel_Bars.bmp', 'Panel_HeroDead.bmp', 'ProductionSlots.bmp', 'ProductionBar.bmp',
                 # 0x4d6e00 loads bitmaps 0x1d1 / 0x1d2 from the local player's race's Powerups sheets (playtest 2026-11-11:
                 # every race, not only the Knights).
                 'PowerupsKnight.bmp', 'PowerupsKnight_Small.bmp',
                 'PowerupsDwarf.bmp', 'PowerupsDwarf_Small.bmp',
                 'PowerupsUndead.bmp', 'PowerupsUndead_Small.bmp',
                 'PowerupsBarbarian.bmp', 'PowerupsBarbarian_Small.bmp',
                 'PowerupsMinotaur.bmp', 'PowerupsMinotaur_Small.bmp',
                 'PowerupsOrc.bmp', 'PowerupsOrc_Small.bmp',
                 'PowerupsHighElf.bmp', 'PowerupsHighElf_Small.bmp',
                 'PowerupsWoodElf.bmp', 'PowerupsWoodElf_Small.bmp',
                 'PowerupsDarkElf.bmp', 'PowerupsDarkElf_Small.bmp',
                 'PowerupsFey.bmp', 'PowerupsFey_Small.bmp',
                 'PowerupsDarkDwarf.bmp', 'PowerupsDarkDwarf_Small.bmp',
                 'PowerupsDaemon.bmp', 'PowerupsDaemon_Small.bmp',
                 'PowerupsEmpire.bmp', 'PowerupsEmpire_Small.bmp',
                 'PowerupsSsrathi.bmp', 'PowerupsSsrathi_Small.bmp',
                 'PowerupsSwarm.bmp', 'PowerupsSwarm_Small.bmp',
                 'PowerupsPlaguelords.bmp', 'PowerupsPlaguelords_Small.bmp',
                 # Parity pass 1: BM_CURSORS (XCG bitmap 3, the cursor records' sheet) and BM_SELECTIONRINGS (0x66: rings,
                 # the 0x4d7710 / 0x4ddd30 health strips and the 0x49c240 order markers).
                 'Cursors.bmp', 'SelectionRings.bmp',
                 # Parity pass 4: BM_DAMAGEICONS (0x189, the info rows' damage-type icon) and BM_OVERHERO (0x14, drawn over the
                 # portrait's left edge by 0x4d7710).
                 'DamageIcons.bmp', 'Panel_OverHero.bmp',
                 # P-1: BM_INFOBOX (XCG bitmap 0x6d, esibi.bmp), the strategic-map alert frames 0x4dc850 blits.
                 'esibi.bmp']
DIALOG_SHEETS = {'EMDG': 'game menu (0x565670)', 'EMDC': 'dialog close button (0x565670)',
                 'EMDO': 'options dialog (0x566c30)', 'EMDM': 'message box (0x55c8d0)',
                 'EMDE': 'message box yes/no buttons (0x55c8d0)',
                 'ERIX': 'resource icons, 50x20 boxes (0x497500)', 'ERNX': 'resource digits 7x10 (0x497500)',
                 # Milestone 13: the production dialog (0x568290) and the Market's trade dialog (0x5723a0).
                 'EMDP': 'production dialog (0x568290)', 'EMDX': 'market trade dialog (0x5723a0)',
                 # Parity pass 2: the end-of-battle boxes 0x574b00 opens after the stinger (0x513eb0 'EZDV' 360x450,
                 # 0x513d30 'EZDD' 360x360; texts drawn by 0x574c90).
                 'EZDV': 'victory box (0x513eb0 -> 0x574b00)', 'EZDD': 'defeat box (0x513d30 -> 0x574b00)',
                 # HUD pass: the dialogs of the control panel's round buttons and keys. Diplomacy 0x558810 ('EMDA' 450x431,
                 # 'ESHD' the player gems), the spellbook 0x56f910 ('EMDS' 613x445, 'EMDI' the school glyphs and tabs),
                 # the current quest 0x56a150 ('EMDQ' 430x417).
                 'EMDA': 'diplomacy dialog (0x558810)', 'ESHD': 'diplomacy player gems (0x558810)',
                 'EMDS': 'spellbook dialog (0x56f910)', 'EMDI': 'spellbook school glyphs and tabs (0x56f910)',
                 'EMDQ': 'quest dialog (0x56a150)',
                 # S-1: the load sheet 0x564c20 ('EMDL' 400x431; Alt+L and the game menu's Load Game).
                 'EMDL': 'load game sheet (0x564c20)'}
# 'i' icon sheets of the Knights roster (milestone 13: every unit and building the production pages show).
ICON_CODES = ['AHBX', 'AHKX', 'AHMX', 'AHHX', 'AHFX', 'AHDX', 'AHEX', 'AHLX', 'AHGX', 'ATHX', 'ASBA', 'ASCA', 'AAEG', 'AAPE',
              'AADR', 'AADC', 'AAAR', 'BKK0', 'BKK1', 'BKK2', 'BKK3', 'BKK4', 'BAGA', 'BPFL', 'BPSM', 'BPSB', 'BPMA', 'BAV0',
              'BAV1', 'BAV2', 'BPSS', 'BPCA', 'BWTC', 'BWG0', 'BWG1', 'BWG2', 'BWRA']


def decode_sheet(body, palette=0):
    """RS or RL sheet bytes -> RGBA image (palette 0, the rebuild's choice for every sheet)."""
    magic = body[:2]
    assert magic in (b'RS', b'RL'), magic
    width, height = struct.unpack_from('<HH', body, 6)
    colours = [c565(v) for v in struct.unpack_from('<256H', body, 0x0a + 512 * palette)]
    _, _, chunks, _ = struct.unpack_from('<IIHH', body, 0x100a)
    base = 0x1016
    table = struct.unpack_from('<%dI' % (chunks * height), body, base)
    image = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(height):
        for chunk in range(chunks):
            i = base + table[chunk * height + y]
            x = chunk * 128
            end = min(width, x + 128)
            while x < end:
                b = body[i]
                if b == 0xff:
                    n = body[i + 1]
                    i += 2
                    if n == 0xff:
                        break
                    x += n
                elif magic == b'RS' and b >= 0xfa:
                    # RS shadow codes (rle.py): a run of 110-alpha pixels or one translucent pixel.
                    if b == 0xfa:
                        n = body[i + 1]
                        i += 2
                        for _ in range(n):
                            pixels[x, y] = (0, 0, 0, 110)
                            x += 1
                        continue
                    pixels[x, y] = (0, 0, 0, {0xfb: 60, 0xfc: 85, 0xfd: 110, 0xfe: 140}[b])
                    x += 1
                    i += 1
                else:
                    pixels[x, y] = colours[b] + (255,)
                    x += 1
                    i += 1
            assert x <= end, ('row overrun', y, chunk, x, end)
    return image


def parse_game_text(text):
    """English/Game.txt -> {"N": text}: the lines 0x44f4a0(N) returns ("[NNNN]<tab>text", decimal numbers)."""
    import re
    return {str(int(n)): t.rstrip(chr(13)) for n, t in re.findall(r"^\[(\d{4})\]\t?(.*)$", text, re.M)}


def parse_spells(text):
    """English/Spells.txt (loaded by 0x56f490) -> {"schools": 13 names, "spells": 130 {name, desc}}; spell i belongs to
    school i / 10 (0x40c6b0)."""
    import re
    entries = dict(re.findall(r"^\[(SPELL_[A-Z_]+\d+)\]\t?(.*?)\r?$", text, re.M))
    schools = [entries.get('SPELL_NAME_PLURAL_%d' % i, '') for i in range(13)]
    spells = [dict(name=entries.get('SPELL_NAME_%02d' % i, entries.get('SPELL_NAME_%d' % i, '')),
                   desc=entries.get('SPELL_DESC_%02d' % i, entries.get('SPELL_DESC_%d' % i, ''))) for i in range(130)]
    return dict(schools=schools, spells=spells)


def parse_tips(text):
    """English/TipOfTheDay.xml -> the tip texts in id order (0x454110 picks entry 0x458e70(1, number) - 1)."""
    import html
    import re
    return [html.unescape(t).strip() for t in re.findall(r'<Tip id="\d+">(.*?)</Tip>', text, re.S)]


def xml_number(text):
    """The number="N" attribute of the XML root (the count the original rolls over)."""
    import re
    found = re.search(r'number="(\d+)"', text)
    return int(found.group(1)) if found else 0


def parse_history(text):
    """English/History.xml -> [{"title", "paragraphs"}] in id order (the loading screen 0x43c970 shows one entry)."""
    import html
    import re
    entries = []
    for body in re.findall(r'<Entry id="\d+">(.*?)</Entry>', text, re.S):
        title = re.search(r'<Title>(.*?)</Title>', body, re.S)
        entries.append(dict(title=html.unescape(title.group(1)).strip() if title else '',
                            paragraphs=[html.unescape(p).strip() for p in re.findall(r'<Paragraph>(.*?)</Paragraph>', body, re.S)]))
    return entries


def translucent_purple(image):
    """ERIX's box background is purple (palette shades with green 0 and red ~ blue: 148 fill, 115 rim, 98 corners). The
    blend mode 0x487f20 uses for it is not traced (Open). Parity pass 3 (Data, fitted to the original at 1024x768 over
    the desert): the fill keeps 47 % of the ground and the rim 27 %, i.e. kept = (shade - 70) / 166; drawn as black with
    alpha 1 - kept."""
    pixels = image.load()
    for y in range(image.size[1]):
        for x in range(image.size[0]):
            r, g, b, a = pixels[x, y]
            if a and g == 0 and r > 0 and abs(r - b) <= 8:   # the price boxes' strip (frames 4..7) has b = r + 8
                pixels[x, y] = (0, 0, 0, purple_alpha(r))
    return image


def purple_alpha(shade):
    kept = min(1.0, max(0.0, (shade - 70) / 166))
    return round(255 * (1 - kept))


def key_magenta(body):
    """BMP bytes -> RGBA with magenta transparent (same colour key as xci.key_bitmap)."""
    from xci import key_bitmap
    return key_bitmap(body)


def build_extra(source, out, archive_reader):
    """Write ui_x_*.png into out; returns the layout section {name: {file, size, source}}."""
    import hashlib
    exported = {}

    def provenance(path, name, offset, body):
        return dict(archive=path.relative_to(source).as_posix(), entry=name, offset=offset,
                    sha256=hashlib.sha256(body).hexdigest())

    graphics = source / 'Assets/Graphics.xcr'
    wanted = {n.lower(): n for n in NAMED_BITMAPS}
    for name, offset, body in archive_reader(graphics):
        if name.lower() in wanted and wanted[name.lower()] not in exported:
            image = key_magenta(body)
            filename = 'ui_x_' + wanted[name.lower()].rsplit('.', 1)[0] + '.png'
            image.save(out / filename, optimize=False)
            exported[wanted[name.lower()]] = dict(file=filename, size=list(image.size), source=provenance(graphics, name, offset, body))
    portraits = source / 'Assets/Heroes/Portraits.xcr'
    if portraits.exists():
        for name, offset, body in archive_reader(portraits):
            if name.lower().startswith('portrait') and name.lower().endswith('.bmp') and name not in exported:
                image = key_magenta(body)
                filename = 'ui_x_' + name.rsplit('.', 1)[0] + '.png'
                image.save(out / filename, optimize=False)
                exported[name] = dict(file=filename, size=list(image.size), source=provenance(portraits, name, offset, body))
    # Q-2: the quest portraits 0x56a150 loads as image 0x184 from "<record +4>.bmp" (Quest.xcr at the installation root,
    # 128 x 160, drawn at (0x4e, 0x4b) by 0x56aff0); layout key "quest_<ID>".
    quests = source / 'Quest.xcr'
    if quests.exists():
        for name, offset, body in archive_reader(quests):
            if name.lower().endswith('.bmp'):
                key = 'quest_' + name.rsplit('.', 1)[0].upper()
                image = key_magenta(body)
                filename = 'ui_x_%s.png' % key
                image.save(out / filename, optimize=False)
                exported[key] = dict(file=filename, size=list(image.size), role='quest portrait (0x56a150)',
                                     source=provenance(quests, name, offset, body))
    effects = source / 'Assets/Effects/Effects1.xcr'
    for name, offset, body in archive_reader(effects):
        code = name.upper()
        if code.endswith('.RLE') and code[:-4] in DIALOG_SHEETS and code[:-4] not in exported:
            image = decode_sheet(body)
            if code[:-4] == 'ERIX':
                image = translucent_purple(image)
            filename = 'ui_x_%s.png' % code[:-4]
            image.save(out / filename, optimize=False)
            exported[code[:-4]] = dict(file=filename, size=list(image.size), format=body[:2].decode(),
                                       role=DIALOG_SHEETS[code[:-4]], source=provenance(effects, name, offset, body))
    for side in ('Knights', 'Fliers', 'Dragons', 'Siege', 'TowersWalls'):   # milestone 13: the archives of the Knights roster
        archive = source / ('Assets/Sides/%s.xcr' % side)
        if not archive.exists():
            continue
        for name, offset, body in archive_reader(archive):
            code = name.upper()
            if code.endswith('I.RLE') and code[:4] in ICON_CODES and len(code) == 9:
                key = code[:4] + 'i'
                if key in exported:
                    continue
                image = decode_sheet(body)
                filename = 'ui_x_icon_%s.png' % code[:4]
                image.save(out / filename, optimize=False)
                exported[key] = dict(file=filename, size=list(image.size), format=body[:2].decode(),
                                     source=provenance(archive, name, offset, body))
    return exported
