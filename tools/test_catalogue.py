"""All-races catalogue decoding checks (RACES_RESEARCH.md); local data only, no Godot or Unicorn required."""
import json
import unittest

import catalogue_data as catalogue
import import_assets as importer

FIXTURES = importer.PROJECT / 'tests/races_fixtures.json'


class CatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cat = catalogue.build_catalogue(importer.GAME)
        cls.fixtures = json.loads(FIXTURES.read_text())

    def test_counts_and_races(self):
        counts = self.cat['counts']
        self.assertEqual((counts['units'], counts['buildings'], counts['features']), (199, 264, 121))
        self.assertEqual((counts['army_rows'], counts['hero_rows']), (183, 17))
        self.assertEqual(len(self.cat['races']), 16)
        self.assertEqual(self.cat['races']['Knight']['construction'], ['H0', 'H1'])
        self.assertEqual(self.cat['races']['Knight']['hero_unit'], 'AHHX')
        self.assertEqual(len(self.cat['heroes']['classes']), 28)
        self.assertEqual(self.cat['heroes']['classes'][0], 'Warrior')
        # Every ARM has an Army.cfg row; PatchData.xcr ARM/BUI entries are byte-identical to the base ones.
        self.assertTrue(all(u['army_cfg'] for u in self.cat['units'].values()))
        patched = [e for t in ('units', 'buildings') for e in self.cat[t].values() if e['patch_status']]
        self.assertEqual(len(patched), 12)
        self.assertTrue(all(e['patch_status'] == 'identical' for e in patched))

    def test_knights_agree_with_production_json(self):
        production = json.loads((importer.PROJECT / 'assets/production.json').read_text())
        for code, d in production['definitions'].items():
            entry = self.cat['units' if d['kind'] == 'unit' else 'buildings'][code]
            cost = [entry['decoded']['cost'][lane] for lane in catalogue.LANES]
            self.assertEqual(cost, d['cost'], code)
            self.assertEqual(entry['decoded']['build_time_seconds'], d['build_time_seconds'], code)
            if d['kind'] == 'unit':
                self.assertEqual(entry['decoded']['movement_type'], d['movement_type'])
                self.assertEqual(entry['decoded']['extent'], d['footprint'])
            else:
                self.assertEqual(entry['footprint']['size'], d['footprint'])
                self.assertEqual(entry['footprint']['masks'], d['mask_rows'])
        rows = {r['building']: r for r in self.cat['building_cfg']['production'] if r['race'] == 'H'}
        for code, row in production['production'].items():
            self.assertEqual([s['id'] for s in rows[code]['slots']], [s['id'] for s in row['slots']], code)
            self.assertEqual(rows[code]['requires'], row['requires'], code)

    def test_movement_types_and_extents(self):
        index = self.cat['movement_extent_index']
        self.assertEqual(sorted(index), ['0/1x1', '0/2x2', '1/1x1', '3/1x1'])
        self.assertEqual(sum(map(len, index.values())), 199)
        self.assertIn('AAPE', index['1/1x1'])      # Pegasus flies
        self.assertIn('AHLX', index['3/1x1'])
        self.assertEqual(self.cat['units']['AHKX']['army_cfg']['status_fields']['locomotion'], 'L')

    def test_status_and_letters_match_emulation(self):
        rows = self.cat['army_cfg']['armies'] + self.cat['army_cfg']['heroes']
        self.assertEqual(len(rows), len(self.fixtures['status_bits']))
        for row, case in zip(rows, self.fixtures['status_bits']):
            self.assertEqual(catalogue.status_bits(case['status']), case['bits'], case['code'])
            self.assertEqual((row['code'], row['status_fields']['bits']), (case['code'], case['bits']))
        self.assertEqual(list(self.cat['army_cfg']['duplicate_codes']), ['AOKX'])
        self.assertEqual(self.cat['units']['AOKX']['army_cfg']['name'], 'Goblin Chief')
        for letter, index in self.fixtures['race_letters']:
            self.assertEqual(catalogue.race_index(letter), index, letter)

    def test_rules_and_costs_match_emulation(self):
        rules = {(r['id'], r['race_index']): r for r in self.cat['building_cfg']['rules']}
        self.assertEqual(rules[('AADE', 11)]['cost']['gold'], 200)
        self.assertEqual(self.fixtures['cost_data_model_mismatches'], [])
        cases = {(c['race'], c['item']): c for c in self.fixtures['cost_0x40b6b0']}
        self.assertEqual(cases[(11, 'AADE')]['cost'], [200, 200, 0, 0])
        self.assertEqual(cases[(0, 'AADE')]['cost'], [550, 550, 0, 0])
        for (race, item), case in cases.items():
            table = self.cat['units'] if item[0] == 'A' else self.cat['buildings'] if item[0] == 'B' else None
            if table is None or (item, race) in rules:
                continue
            self.assertEqual(case['cost'], [table[item]['decoded']['cost'][l] for l in catalogue.LANES], (race, item))

    def test_route_fixture_shape(self):
        passable = self.fixtures['passable_cells']
        self.assertEqual((passable['0/1'], passable['0/2'], passable['0/3']), (14723, 13690, 12599))
        self.assertEqual(passable['1/1'], 128 * 128)
        self.assertEqual(passable['2/1'], 0)
        for route in self.fixtures['routes']:
            if route['ok'] and route['cells']:
                self.assertEqual(route['cells'][-1], route['goal'], route['name'])
                steps = [route['start']] + route['cells']
                for a, b in zip(steps, steps[1:]):
                    self.assertLessEqual(max(abs(a[0] - b[0]), abs(a[1] - b[1])), 1)


if __name__ == '__main__':
    unittest.main()
