"""Milestone 11-menus: the RL sheet rows, the interface art loaded by name and the in-game dialog sheets.
Reads the local installation only."""
import struct
import unittest
from pathlib import Path

import original_reader as reader
import ui_extra
from original_reader import game_root

SOURCE = game_root()


def rl_row_widths(body):
    """Pixels each RL row covers (literal bytes plus 0xff skips); a well-formed row covers exactly the sheet width."""
    width, height = struct.unpack_from('<HH', body, 6)
    _, _, chunks, _ = struct.unpack_from('<IIHH', body, 0x100a)
    table = struct.unpack_from('<%dI' % (chunks * height), body, 0x1016)
    widths = []
    for y in range(height):
        total = 0
        for chunk in range(chunks):
            i, x, end = 0x1016 + table[chunk * height + y], 0, min(128, width - chunk * 128)
            while x < end:
                if body[i] == 0xff:
                    if body[i + 1] == 0xff:
                        x = end
                        break
                    x += body[i + 1]
                    i += 2
                else:
                    x += 1
                    i += 1
            total += x
        widths.append(total)
    return width, widths


class UiExtraTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.effects = {n.upper(): b for n, _, b in reader.archive(SOURCE / 'Assets/Effects/Effects1.xcr')}
        cls.knights = {n.upper(): b for n, _, b in reader.archive(SOURCE / 'Assets/Sides/Knights.xcr')}
        cls.graphics = {n.lower(): b for n, _, b in reader.archive(SOURCE / 'Assets/Graphics.xcr')}

    def test_rl_rows_cover_the_width_exactly(self):
        """RL = RS header and row table; only 0xff escapes; every row ends exactly at the sheet width."""
        bodies = [self.effects[c + '.RLE'] for c in ('EMDC', 'EMDE', 'ERIX', 'ERNX')]
        bodies += [self.knights[c] for c in ('AHKXI.RLE', 'AHBXI.RLE', 'BKK0I.RLE', 'BAGAI.RLE')]
        for body in bodies:
            self.assertEqual(body[:2], b'RL')
            width, widths = rl_row_widths(body)
            self.assertEqual(set(widths), {width})

    def test_sheet_sizes(self):
        sizes = {code: ui_extra.decode_sheet(self.effects[code + '.RLE']).size for code in ui_extra.DIALOG_SHEETS}
        self.assertEqual(sizes, {'EMDG': (400, 431), 'EMDC': (30, 120), 'EMDO': (450, 431), 'EMDM': (600, 300),
                                 'EMDE': (180, 144), 'ERIX': (60, 320), 'ERNX': (84, 10),
                                 'EMDP': (610, 450), 'EMDX': (450, 431),    # milestone 13: 0x568290 / 0x5723a0 sizes
                                 'EZDV': (360, 450), 'EZDD': (360, 360),    # parity pass 2: 0x574b00 end-of-battle boxes
                                 'EMDA': (450, 431), 'ESHD': (175, 20),     # HUD pass: 0x558810 diplomacy (450 x 431)
                                 'EMDS': (613, 445), 'EMDI': (308, 44),     # 0x56f910 spellbook (0x265 x 0x1bd)
                                 'EMDQ': (430, 417),                        # 0x56a150 quest (0x1ae x 0x1a1)
                                 'EMDL': (400, 431)})                       # S-1: 0x564c20 load sheet (400 x 0x1af)
        icon = ui_extra.decode_sheet(self.knights['AHKXI.RLE'])
        self.assertEqual(icon.size, (144, 374))
        self.assertGreater(sum(1 for p in icon.getdata() if p[3]), 5000, 'the icon sheet has visible pixels')

    def test_resource_box_shading(self):
        # Parity pass 3: ERIX's purple shades darken the ground like the original at 1024x768 (fill keeps 47 %, rim 27 %).
        self.assertEqual([ui_extra.purple_alpha(v) for v in (148, 115, 98, 70, 236)], [135, 186, 212, 255, 0])

    def test_named_bitmaps_exist(self):
        for name in ui_extra.NAMED_BITMAPS:
            self.assertIn(name.lower(), self.graphics, name)
        portraits = [n for n, _, _ in reader.archive(SOURCE / 'Assets/Heroes/Portraits.xcr') if n.lower().startswith('portrait')]
        self.assertGreaterEqual(len(portraits), 80)

    def test_quest_portraits(self):
        # Q-2: 0x56a150 loads "<record +4>.bmp" from Quest.xcr into a 0x80 x 0xa0 frame; every record of both tables has one.
        bodies = {n.upper(): b for n, _, b in reader.archive(SOURCE / 'Quest.xcr')}
        portraits = {n[:-4] for n in bodies if n.endswith('.BMP')}
        self.assertEqual(len(portraits), 30)
        for code in portraits:
            self.assertEqual(ui_extra.key_magenta(bodies[code + '.BMP']).size, (128, 160), code)
        import encounters_data
        used = {r['portrait'].upper() for t in encounters_data.quests(SOURCE).values() for r in t['records'] if r['enabled']}
        self.assertTrue(used <= portraits, sorted(used - portraits))

if __name__ == '__main__':
    unittest.main()
