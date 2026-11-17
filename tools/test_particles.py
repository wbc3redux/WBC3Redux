"""Map wave 5 (MAPS_RESEARCH.md "Wave 5"): the particle definitions the EFFH map effects name (tools/particle_data.py,
0x486010's layout) and the emulated emitter runs in tests/particle_fixtures.json (tools/emulate_particles.py)."""
import json
import struct
import unittest
from pathlib import Path

import particle_data
from original_reader import game_root

PROJECT = Path(__file__).resolve().parents[1]
FIXTURES = json.loads((PROJECT / 'tests' / 'particle_fixtures.json').read_text())


class ParticleTests(unittest.TestCase):
    def test_definitions(self):
        defs = particle_data.read_all(game_root())
        self.assertEqual(sorted(defs), ['EvilBrew', 'RainbowSparkle', 'RedGlow', 'Volcano', 'Volcano2'])
        self.assertEqual(defs, FIXTURES['definitions'])
        imported = json.loads((PROJECT / 'assets' / particle_data.OUTPUT).read_text())['definitions']
        self.assertEqual(imported, defs)
        volcano = defs['Volcano']
        # alpha 60 -> translucency 15 - 9 = 6; AnimGraphics alpha 0 -> 15 (fully clear at the end of the life).
        self.assertEqual((volcano['alpha'], volcano['anim_alpha']), (6, 15))
        self.assertEqual((volcano['max'], volcano['release'], volcano['interval'], volcano['life']), (20, 1, 100, 1000))
        self.assertEqual((volcano['velocity_y'], volcano['force_y'], volcano['temporary']), (-6, 1, 0))
        self.assertEqual(defs['RainbowSparkle']['temporary'], 1)

    def test_entry_layout(self):
        # The 0x104-byte entry: id at +0x20 (0x486980 compares the EFFH name there), graphic fourcc at +0x34.
        body = particle_data.entry_bytes(particle_data.read_all(game_root())['Volcano2'])
        self.assertEqual(len(body), 0x104)
        self.assertEqual(body[0x20:0x28], b'Volcano2')
        self.assertEqual(body[0x34:0x38], b'EPF0')
        self.assertEqual(struct.unpack_from('<hh', body, 0x44), (0, 20))
        self.assertEqual(particle_data.atoi('-6'), -6)
        self.assertEqual(particle_data.atoi(None), 0)

    def test_emulated_runs(self):
        runs = {(r['id'], r['start']): r for r in FIXTURES['runs']}
        self.assertEqual(len(runs), 6)
        for (key, start), run in runs.items():
            self.assertEqual(run['placed']['cell'], [56, 36], key)     # 0x4939a0: (1802 / 32, 882 / 24)
            self.assertEqual(run['placed']['kind'], 11, key)           # object type 0xb
            counts = [s['counts'] for s in run['steps']]
            self.assertTrue(all(c[1] <= FIXTURES['definitions'][key]['max'] for c in counts), key)
        # The permanent emitters keep running; the temporary ones end after their lifetime.
        self.assertTrue(runs[('Volcano', 0)]['steps'][-1]['alive'])
        self.assertFalse(runs[('RedGlow', 0)]['steps'][-1]['alive'])
        self.assertFalse(runs[('RainbowSparkle', 0)]['steps'][-1]['alive'])
        # Off screen nothing is released and no particle moves; the timers still advance.
        steps = runs[('Volcano', 0)]['steps']
        a, b = FIXTURES['culled']
        self.assertEqual(steps[a + 1]['counts'][2], steps[b]['counts'][2])
        self.assertEqual(steps[a + 1]['particles'], steps[b]['particles'])
        self.assertLess(steps[a + 1]['timers'][0], steps[b]['timers'][0])


if __name__ == '__main__':
    unittest.main()
