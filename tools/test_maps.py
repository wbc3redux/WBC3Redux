"""W1 multi-map import (CONTENT_EXPANSION_PLAN.md): scenario pins, per-map outputs, terrain drawn from tile records."""
import json
from pathlib import Path
import unittest
from PIL import Image
import import_assets as importer
import original_reader as reader

ASSETS = importer.PROJECT / 'assets'


class MapImportTests(unittest.TestCase):
    def test_every_scenario_matches_its_pin(self):
        names = reader.scenario_names(importer.GAME)
        files = sorted((importer.GAME / 'Scenario').glob('*.SCN'))
        self.assertEqual(len(files), 22)
        self.assertEqual({p.stem for p in files}, set(importer.MAP_PINS))
        for path in files:
            manifest = reader.parse_scenario(path, names)
            digest, counts = importer.MAP_PINS[path.stem]
            self.assertEqual(manifest['sha256'], digest, path.name)
            self.assertEqual([len(manifest[k]) for k in ('starts', 'buildings', 'armies', 'features', 'terrain_records')],
                             counts, path.name)
            width, height = manifest['size_cells']
            self.assertEqual(len(manifest['terrain_records']), ((width + 9) // 10) * ((height + 9) // 10), path.name)

    def test_slugs(self):
        self.assertEqual(reader.map_slug("The Lion's Den.SCN"), 'the-lions-den')
        self.assertEqual(reader.map_slug('Rumble in the Jungle'), 'rumble-in-the-jungle')
        self.assertEqual(reader.map_slug('Desert Sands.SCN'), 'desert-sands')

    def test_index_and_desert_sands_copies(self):
        index = json.loads((ASSETS / 'maps/index.json').read_text())
        self.assertEqual([m['slug'] for m in index['maps']], ['bridges', 'cavemen', 'cavern-wars', 'celestial-oasis', 'circles', 'desert-crossing', 'desert-sands', 'dragons-pyramid', 'dwarven-tunnels', 'forest-lakes', 'four-bridges', 'four-rivers', 'hills-to-climb', 'land-of-the-lost', 'lands-divided', 'next-door', 'rumble-in-the-jungle', 'the-hill', 'the-lions-den', 'valley-of-the-dead', 'volcanic-pit', 'winter-wonderland'])

    def test_wave3_effects_and_broken_pairs(self):
        # Valley of the Dead's EFFH record (a particle emitter since wave 5, test_particles.py); Four Rivers' three painted-over big-tile partners
        # are pinned in collision.KNOWN_BROKEN_PAIRS and import as their own quarters.
        valley = json.loads((ASSETS / 'maps/valley-of-the-dead/map.json').read_text())
        self.assertEqual([(e['name'], e['world_position']) for e in valley['effects']], [('EvilBrew', [5778, 2876])])
        rivers = json.loads((ASSETS / 'maps/four-rivers/map.json').read_text())
        self.assertNotIn('effects', rivers)
        self.assertEqual([rivers['terrain_records'][i]['code'] for i in (84, 85, 104, 105)], ['TGF1', 'TGX0', 'TGF1', 'TGF1'])
        for file in ['map.json', 'collision.json', 'map_objects.json', 'scenario_minimap.png', 'terrain_validation.json',
                     'collision_walk.png', 'collision_build.png', 'collision_height.png', 'collision_material.png',
                     'collision_objects.png']:
            self.assertEqual((ASSETS / 'maps/desert-sands' / file).read_bytes(), (ASSETS / file).read_bytes(), file)

    def compose(self, slug):
        layout = json.loads((ASSETS / 'maps' / slug / 'terrain.json').read_text())
        image = Image.new('RGB', tuple(layout['world_size']))
        tiles = {}
        for draw in layout['draws']:
            if draw['code'] not in tiles:
                with Image.open(ASSETS / draw['texture']) as tile:
                    tiles[draw['code']] = tile.convert('RGB')
            x, y, w, h = draw['source_rect']
            image.paste(tiles[draw['code']].crop((x, y, x + w, y + h)), tuple(draw['destination']))
        return layout, image

    def test_desert_sands_terrain_from_records_is_pixel_identical(self):
        layout, image = self.compose('desert-sands')
        self.assertEqual(len(layout['draws']), 169)
        with Image.open(ASSETS / 'terrain.png') as baked:
            self.assertEqual(image.tobytes(), baked.convert('RGB').tobytes())

    def test_the_hill(self):
        manifest = json.loads((ASSETS / 'maps/the-hill/map.json').read_text())
        self.assertEqual(manifest['source'], 'Scenario/The Hill.SCN')
        self.assertEqual([s['cell'] for s in manifest['starts']], [[7, 8], [116, 9], [113, 112], [19, 117]])
        self.assertEqual(len([b for b in manifest['buildings'] if 'resource' in b]), 28)
        info = json.loads((ASSETS / 'maps/the-hill/map_info.json').read_text())
        self.assertEqual((info['players'], info['size_cells'], info['materials']), (4, [128, 128], [0, 1, 2, 8]))
        collision = json.loads((ASSETS / 'maps/the-hill/collision.json').read_text())
        self.assertEqual(len(collision['cells']), 128 * 128)
        self.assertEqual(collision['summary']['quadrant_records_validated'], 169)
        self.assertEqual((collision['summary']['building_count'], collision['summary']['feature_count']), (38, 71))
        objects = json.loads((ASSETS / 'maps/the-hill/map_objects.json').read_text())
        self.assertEqual(len(objects['placements']), 109)
        self.assertTrue(all((ASSETS / d['texture']).exists() for d in objects['definitions'].values()))
        validation = json.loads((ASSETS / 'maps/the-hill/terrain_validation.json').read_text())
        self.assertEqual(validation['best_tested_orientation'], 'identity')
        layout, image = self.compose('the-hill')
        self.assertEqual((len(layout['draws']), image.size), (169, (4096, 3072)))
        tiles = json.loads((ASSETS / 'terrain/tiles.json').read_text())['tiles']
        self.assertTrue({d['code'] for d in layout['draws']} <= set(tiles))


if __name__ == '__main__':
    unittest.main()
