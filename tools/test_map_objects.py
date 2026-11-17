"""Placement conservation and independently decoded presentation regression checks."""
import json
import struct
import unittest
from pathlib import Path
from PIL import Image
from original_reader import archive, cipher_inverse, game_root

PROJECT = Path(__file__).resolve().parents[1]


class Presentations(unittest.TestCase):
    def test_all_source_placements_and_geometry(self):
        data = json.loads((PROJECT/'assets/map_objects.json').read_text())
        scenario = json.loads((PROJECT/'assets/map.json').read_text())
        expected = [dict(kind=k, code=r['code'], source_offset=r['source_offset'],
                         world_position=r['world_position'], raw_hex=r['raw_hex'])
                    for k in ('buildings', 'features') for r in scenario[k]]
        self.assertEqual(data['placements'], expected)
        self.assertEqual(len(expected), 66)
        self.assertEqual(len(data['definitions']), 33)
        sources = {}
        for path in (game_root()/'Assets').rglob('*.xcr'):
            for name, _, body in archive(path):
                if name[:4] in data['definitions']:
                    sources[name.lower()] = body
        for code, definition in data['definitions'].items():
            raw = sources[code.lower()+'.ani'].translate(cipher_inverse())
            px, py, w, h = struct.unpack_from('<4h', raw, 4)
            self.assertEqual(definition['pivot'], [px, py])
            self.assertEqual(definition['frame_size'], [w, h])
            self.assertEqual(definition['frames'], raw[1])
            with Image.open(PROJECT/'assets'/definition['texture']) as image:
                self.assertEqual(image.size, (w*raw[1], h))
            kind = next(p['kind'] for p in expected if p['code']==code)
            source = sources[code.lower()+('.bui' if kind=='buildings' else '.fea')].translate(cipher_inverse())
            height = source[63 if kind=='buildings' else 25]
            offset = (height-1)*12
            if kind=='features' and source[58] and source[59]: offset -= 48
            self.assertEqual(definition['depth_offset'], offset or 1)
        tower = data['definitions']['BZMA']
        self.assertEqual((tower['frames'], tower['interval_ms']), (8,150))
        self.assertTrue(all(data['definitions'][r['code']]['frames']==1 for r in expected if r['kind']=='features'))


if __name__ == '__main__': unittest.main()
