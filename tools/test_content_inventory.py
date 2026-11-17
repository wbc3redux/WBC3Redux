"""W0 content inventory: regenerates byte-identically and agrees with what earlier milestones established."""
import json
import unittest

import content_inventory as inventory

READY = (inventory.DEFAULT_DECOMPILE.exists() and (inventory.PROJECT / 'assets' / 'catalogue.json').exists()
         and (inventory.PROJECT / 'assets' / 'art.json').exists())


@unittest.skipUnless(READY, 'needs the decompile and an imported assets/ folder')
class ContentInventory(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = inventory.build()

    def test_regenerates_identically(self):
        again = inventory.build()
        self.assertEqual(json.dumps(self.data, sort_keys=True), json.dumps(again, sort_keys=True))

    def test_every_race_and_map(self):
        self.assertEqual(len(self.data['races']), 16)
        self.assertEqual(len(self.data['maps']), 22)
        self.assertEqual(sorted(r['index'] for r in self.data['races'].values()), list(range(16)))

    def test_desert_sands_matches_the_importer(self):
        sands = next(m for m in self.data['maps'] if m['file'] == 'Desert Sands.SCN')
        self.assertEqual(sands['size_cells'], [128, 128])
        self.assertEqual([s['cell'] for s in sands['sides']], [[12, 64], [113, 64]])
        self.assertEqual([s['race_name'] for s in sands['sides']], ['Dwarf', 'Swarm'])     # RACES_RESEARCH.md 11a
        self.assertEqual(sum(sands['objects']['buildings'].values()), 26)
        self.assertEqual(sorted(sands['materials']), ['0', '1', '2', '8'])                # COLLISION_RESEARCH.md row 0
        self.assertEqual((sands['buildings_without_art'], sands['armies_without_art']), ([], []))

    def test_known_hubs(self):
        self.assertEqual(self.data['totals']['hardcoded_ids'], 585)                       # the 11a scratch scan
        hubs = {h['address']: h for h in self.data['hubs']}
        self.assertEqual(hubs['0x4391c0']['research'], 257)                               # RACES_RESEARCH.md 2.3
        self.assertEqual((hubs['0x436500']['units'], hubs['0x436500']['research']), (90, 124))

    def test_knights_rows(self):
        knights = self.data['races']['Knight']
        self.assertEqual(knights['letter'], 'H')
        units = {r['code']: r for r in knights['units']}
        for code in ('AHBX', 'AHKX', 'AHMX', 'AHHX'):
            self.assertTrue(units[code]['in_catalogue'])
            self.assertIn(0, units[code]['art']['decoded_slots'])


if __name__ == '__main__':
    unittest.main()
