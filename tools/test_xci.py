"""Decoder checks for War4Int.xci / War4Gfx.xcg / XCIStrings.txt; reads the local installation only."""
from pathlib import Path
import unittest
import xci
from original_reader import game_root

SOURCE = game_root()


class XciTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ui = xci.decode_xci((SOURCE / 'War4Int.xci').read_bytes())
        cls.gfx = xci.decode_xcg((SOURCE / 'War4Gfx.xcg').read_bytes())
        cls.strings = xci.parse_strings((SOURCE / 'English/XCIStrings.txt').read_text(encoding='latin1'), cls.ui['sections'])
        cls.fonts = xci.parse_font_ini((SOURCE / 'English/Font.ini').read_text(encoding='latin1'))
        cls.elements = {e['id']: e for e in cls.ui['elements']}
        cls.panels = {p['name']: p for p in cls.ui['panels']}

    def test_table_counts_and_layout(self):
        self.assertEqual([len(self.ui[k]) for k in ('elements', 'panels', 'screens', 'sections')], [1194, 386, 12, 347])
        # Tables end where the 0x50-byte string pool starts; the pool fills the rest of the file exactly.
        self.assertEqual(self.ui['header']['trailing_bytes'], 0x50 * sum(s['count'] for s in self.ui['sections']))
        self.assertEqual(self.ui['sections'][0]['pool_offset'], self.ui['header']['table_end'])
        self.assertEqual(len(self.elements), 1194, 'element ids are unique')
        self.assertEqual(sum(len(p['controls']) for p in self.ui['panels']), 4179)
        for panel in self.ui['panels']:
            for control in panel['controls']:
                self.assertIn(control['element_id'], self.elements)

    def test_types_follow_name_prefixes(self):
        prefixes = {0: ('BUTT_', 'PAD_'), 1: ('EDIT',), 2: ('SBAR_',), 3: ('LB_', 'DROPDOWNLIST'), 4: ('STR_',), 5: ('PB_',), 6: ('PRIM_',), 7: ('IM',)}
        for element in self.ui['elements']:
            self.assertTrue(element['name'].startswith(prefixes[element['type']]), element['name'])

    def test_main_menu_labels_and_fonts(self):
        panel = self.panels['PNL_MAINMENU']
        labels = {}
        for control in panel['controls']:
            element = self.elements[control['element_id']]
            if element['type'] == 0:
                ref = element['label']
                labels[control['name']] = self.strings[ref['section']][ref['index']]
                self.assertEqual([self.fonts[str(n)]['name'] for n in element['fonts']], element['font_names'])
        self.assertEqual(labels, {'BUTT_MM_CAMPAIGN': 'Campaign', 'BUTT_MM_SINGLEPLAYER': 'Skirmish',
            'BUTT_MM_MULTIPLAYER': 'Multiplayer', 'BUTT_MM_TUTORIAL': 'Tutorial', 'BUTT_MM_OPTIONS': 'Options',
            'BUTT_MM_EDITOR': 'Editor', 'BUTT_MM_QUIT': 'Quit'})

    def test_strings_are_read_in_line_order(self):
        # The loader ignores the [NNNN.i] numbers; section 170 has no strings, so the file has no [0170] lines.
        self.assertEqual((self.ui['sections'][170]['count'], self.strings[170]), (0, []))
        self.assertEqual(self.ui['sections'][171]['name'], 'TXT_SS_GLOBAL')
        self.assertEqual(self.strings[171][:2], ['800 x 600', '1024 x 768'])
        same = sum(1 for s in self.ui['sections'] if self.strings[s['index']] == s['embedded'])
        self.assertGreater(same, 290, 'text file mostly matches the compiled pool')

    def test_xcg_bitmaps(self):
        self.assertEqual(self.gfx['header']['bitmap_count'], 739)
        names = {b['name']: b for b in self.gfx['bitmaps']}
        self.assertEqual(names['BM_MAINMENU']['file'], 'MainMenu.bmp')
        self.assertEqual(names['BM_BUTTON200']['archive'], 'Graphics.xcr')
        for element in self.ui['elements']:
            if element['bitmap'] and element['bitmap'] in names:
                self.assertEqual(names[element['bitmap']]['id'], element['bitmap_id'], element['name'])

    def test_xcg_cursors(self):
        """Parity pass 1: the 16 cursor records follow the bitmap records (FUN_00466970); slot n = record id n, the
        index 0x46c190 stores and 0x420390 returns. Hotspots and frames as FUN_0046c9b0 draws them."""
        self.assertFalse(any(b['name'].startswith('CURS_') for b in self.gfx['bitmaps']), 'no cursor record read as a bitmap')
        cursors = self.gfx['cursors']
        self.assertEqual([c['id'] for c in cursors], list(range(1, 17)))
        by_id = {c['id']: c for c in cursors}
        self.assertEqual([by_id[i]['name'] for i in (1, 2, 6, 7, 8, 9, 12, 13, 14)],
                         ['CURS_ARROW', 'CURS_POINTER', 'CURS_SELECT', 'CURS_FIGHT', 'CURS_WALK', 'CURS_PATROL', 'CURS_RUIN',
                          'CURS_RESUMEBUILDING', 'CURS_GUARD'])
        self.assertEqual(by_id[1]['hotspot'], [0, 0])
        self.assertEqual(by_id[8]['hotspot'], [14, 18])
        self.assertEqual(by_id[7]['frames'][0], [128, 0, 1000])
        self.assertEqual(len(by_id[7]['frames']), 12)
        self.assertTrue(all(c['bitmap'] == 'BM_CURSORS' for c in cursors if c['id'] != 11))

    def test_screen_backgrounds_per_resolution(self):
        startup = self.ui['screens'][0]
        self.assertEqual(startup['name'], 'SCR_STARTUP')
        self.assertEqual(startup['backgrounds']['800x600']['bitmap'], 'BM_MAINMENU')


if __name__ == '__main__':
    unittest.main()
