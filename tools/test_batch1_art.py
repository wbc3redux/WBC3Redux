"""Race batch 1 art (BATCH1_RESEARCH.md milestone B1-1): which units and buildings the import adds. The decoding itself
is covered by test_effects (rl.py) and the art checks of animation_viewer.gd. Run from tools/ with the research
interpreter."""
import unittest

import art_data
from catalogue_data import build_catalogue
from content_inventory import race_rosters
from original_reader import game_root


class Batch1ArtLists(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalogue = build_catalogue(game_root())
        cls.units, cls.buildings = art_data.art_lists(cls.catalogue)

    def test_existing_lists_keep_their_order(self):
        self.assertEqual(self.units[:len(art_data.UNITS)], art_data.UNITS)
        self.assertEqual(self.buildings[:len(art_data.BUILDINGS)], art_data.BUILDINGS)
        self.assertEqual(len(self.units), len(set(self.units)))
        self.assertEqual(len(self.buildings), len(set(self.buildings)))

    def test_every_roster_code_is_imported(self):
        # G-2: catalogue-driven, every ARM / BUI code (all 16 rosters, neutral, map and quest codes).
        rosters = race_rosters(self.catalogue)
        gaps = art_data.roster_gaps(self.catalogue)
        for race, roster in rosters.items():
            self.assertLessEqual(set(roster['units']) - set(gaps), set(self.units), race)
            self.assertLessEqual(set(roster['buildings']) - set(gaps), set(self.buildings), race)
        self.assertEqual(set(self.units), set(self.catalogue['units']))
        self.assertEqual(set(self.buildings), set(self.catalogue['buildings']))
        self.assertEqual((len(self.units), len(self.buildings)), (199, 264))
        self.assertEqual(gaps, {'AAAG': ['Barbarian']})         # a Building.cfg dependency row only
        # CONTENT_EXPANSION_PLAN.md section 6: the 12 map building and 12 map army codes without art before G-2.
        self.assertTrue({'BLBM', 'BLHN', 'BMSH', 'BWGI', 'AABX', 'AAGX', 'AAIX', 'AAJX', 'AASX', 'APDX', 'ATPX'}
                        <= set(self.units + self.buildings))
        self.assertTrue({'AUKX', 'AUXX', 'AUMX', 'AAEA', 'AAEF', 'AAEW', 'BKU0', 'BPBL', 'BPWT'} <= set(self.units + self.buildings))

    def test_map_buildings_stay_with_the_map_import(self):
        _, buildings = art_data.art_lists(self.catalogue, ['BKU0'])
        self.assertNotIn('BKU0', buildings)

    def test_skips_have_reasons(self):
        self.assertEqual(set(art_data.SKIPPED_SHEETS), {'atrxd.rle', 'ez39.rle', 'eosr.rle'})
        self.assertTrue(all(art_data.SKIPPED_SHEETS.values()))

    def test_effect_intervals(self):
        self.assertEqual([art_data.effect_interval_ms(c) for c in ('EF01', 'EX01', 'EX04', 'EDB0', 'EDTH', 'EZ08')],
                         [50, 120, 120, 10000, 10000, 50])

if __name__ == '__main__':
    unittest.main()
