"""Integration regression checks; local assets only, no source writes or Godot required."""
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image
import import_assets as importer


class ImporterTests(unittest.TestCase):
    def test_rebuild_and_failure_detection(self):
        source = importer.GAME
        baseline = json.loads((importer.PROJECT / 'assets/import_manifest.json').read_text())
        with tempfile.TemporaryDirectory(dir=importer.PROJECT, prefix='wbc-import-test-') as temp:
            root = Path(temp)
            # Keep a concurrent Godot editor/import from importing test fixtures.
            (root / '.gdignore').write_text('', encoding='utf-8')
            first, second = root / 'first', root / 'second'
            first.mkdir()
            second.mkdir()
            importer.generate(source, first)
            importer.generate(source, second)
            importer.check(source, first)
            self.assertEqual({p.name:importer.sha(p) for p in first.iterdir() if p.is_file()},
                             {p.name:importer.sha(p) for p in second.iterdir() if p.is_file()})
            # Existing imported image bytes must be reproduced, including palette and alpha.
            for name in ['terrain.png','AHKX.RLE.png','AHKXw.RLE.png','AHKXf.RLE.png','AHKXd.RLE.png','AHKXa.RLE.png','collision_walk.png','collision_build.png','collision_height.png','collision_material.png','collision_objects.png']:
                self.assertEqual(importer.sha(first / name), baseline['outputs'][name])
            manifest = json.loads((first / 'map.json').read_text())
            self.assertEqual([r['cell'] for r in manifest['starts']], [[12,64],[113,64]])
            mines = [r for r in manifest['buildings'] if 'resource' in r]
            self.assertEqual(len(mines), 20)
            self.assertEqual(sorted(r['level'] for r in mines), [2]*8+[3]*12)
            production = json.loads((first / 'production.json').read_text())
            costs = {k: v['cost'] for k, v in production['definitions'].items()}
            self.assertEqual(costs['AHBX'], [20, 0, 0, 0])
            self.assertEqual(costs['AHKX'], [0, 20, 0, 0])
            self.assertEqual(costs['AHMX'], [60, 0, 0, 0])
            self.assertEqual((costs['BAGA'], costs['BPFL'], costs['BKK1']), ([100, 0, 0, 100], [80, 0, 0, 100], [300, 0, 0, 100]))
            self.assertEqual(production['production']['BAGA']['requires'][0], 'BKK0')
            self.assertEqual(production['production']['BPFL']['requires'][0], 'BKK1')
            self.assertEqual(production['unit_dependencies']['AHMX']['requires'][0], 'BPFL')
            self.assertEqual([s['id'] for s in production['production']['BAGA']['slots'][:2]], ['AHKX', 'AHMX'])
            self.assertEqual(production['definitions']['BAGA']['footprint'], [9, 8])
            with Image.open(first / 'terrain.png') as image:
                self.assertEqual(image.size, (4096,3072))
            (first / 'terrain.png').write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError, 'Output missing or modified'):
                importer.check(source, first)
            (second / 'map.json').unlink()
            with self.assertRaises(FileNotFoundError):
                importer.check(source, second)
            fake_source = root / 'source'
            (fake_source / 'Scenario').mkdir(parents=True)
            (fake_source / 'Scenario/Desert Sands.SCN').write_bytes(b'wrong baseline')
            with self.assertRaisesRegex(ValueError, 'source hash differs'):
                importer.generate(fake_source, first)
        importer.check(source, importer.PROJECT / 'assets')


if __name__ == '__main__':
    unittest.main()
