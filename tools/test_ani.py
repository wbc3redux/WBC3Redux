"""Checks against the installation's encrypted ANI and independent decoded expectations."""
import struct
import unittest
from pathlib import Path
from ani import decode_ani, validate_sheet
from original_reader import archive, game_root

SOURCE = game_root()


class AniTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = next(b for n,_,b in archive(SOURCE/'Assets/Sides/Knights.xcr') if n=='AHKX.ANI')

    def test_original_values(self):
        result=decode_ani(self.raw)
        self.assertEqual(len(result['slots']),9)
        expected=[(1,[52,45],[88,66]), (16,[60,56],[96,77]),
                  (16,[66,55],[112,84]), (13,[63,55],[120,96]), (16,[56,55],[88,74])]
        for slot,(frames,pivot,size) in zip(result['slots'],expected):
            self.assertEqual((slot['frame_count'],slot['pivot'],slot['frame_size']),(frames,pivot,size))
        self.assertEqual(result['slots'][2]['unknown_words']['0x18'],6)
        self.assertEqual([s['enabled'] for s in result['slots']],[True]*5+[False]*3+[True])
        self.assertEqual(bytes.fromhex(result['decoded_hex']), b''.join(bytes.fromhex(s['decoded_hex']) for s in result['slots']))

    def test_reject_truncation_and_mismatched_geometry(self):
        with self.assertRaises(ValueError):
            decode_ani(self.raw[:-1])
        slot=decode_ani(self.raw)['slots'][1]
        self.assertEqual(validate_sheet(slot,(1536,616)),(16,8))
        for size in [(1535,616),(1536,615),(96,616),(1536,77)]:
            with self.assertRaises(ValueError):
                validate_sheet(slot,size)
        idle=decode_ani(self.raw)['slots'][0]
        self.assertEqual(validate_sheet(idle,(176,528)),(2,8))



class ArtTests(unittest.TestCase):
    """Art import (ART_RESEARCH.md): unit/building ANI geometry, team-colour slots and ramps."""
    @classmethod
    def setUpClass(cls):
        cls.entries = {}
        for path in sorted((SOURCE/'Assets').rglob('*.xcr')):
            for name, _, body in archive(path):
                cls.entries.setdefault(name.lower(), body)

    def test_unit_geometry(self):
        expected = {'amjx': [(1, [112, 83]), (13, [96, 87]), (18, [120, 102]), (12, [184, 140]), (16, [136, 105])],
                    'ahbx': [(1, [48, 50]), (16, [60, 54]), (19, [124, 97]), (13, [128, 101]), (19, [68, 60])]}
        for code, slots in expected.items():
            decoded = decode_ani(self.entries[code + '.ani'])['slots']
            self.assertEqual([(s['frame_count'], s['frame_size']) for s in decoded[:5]], slots)
        self.assertEqual(decode_ani(self.entries['amjx.ani'])['slots'][2]['unknown_words']['0x18'], 10)

    def test_building_construction_sheet(self):
        slot = decode_ani(self.entries['bkk0.ani'])['slots'][5]
        self.assertTrue(slot['enabled'])
        self.assertEqual((slot['frame_count'], slot['frame_size']), (1, [312, 243]))
        width, height = struct.unpack_from('<HH', self.entries['bkk0z.rle'], 6)
        self.assertEqual((width // 312, height), (3, 243))   # three construction columns (0x52c250)

    def test_team_slots_and_ramps(self):
        import tempfile
        from rle import decode, team_mask
        from art_data import team_ramps
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'AHKX.RLE'
            path.write_bytes(self.entries['ahkx.rle'])
            image, _ = decode(path)
            mask = team_mask(path)
        self.assertEqual(mask.size, image.size)
        self.assertEqual(sum(mask.histogram()[1:]), 1651)
        pixels, masks = image.tobytes(), mask.tobytes()
        for i, m in enumerate(masks):
            r, g, b, a = pixels[4 * i:4 * i + 4]
            if m:
                self.assertEqual((r, b, a), (0, 0, 255))            # palette 0 entries 224..238 are the green ramp
        ramps = team_ramps()
        self.assertEqual(len(ramps), 8)
        self.assertTrue(all(len(r) == 15 for r in ramps))
        self.assertEqual(ramps[0][0], [41, 0, 0])                    # 0x494450 colour 0: R 0x28 -> 565 -> 41
        self.assertEqual(ramps[1][14], [41, 76, 148])
        self.assertEqual(ramps[7][14], [213, 214, 0])


if __name__=='__main__':
    unittest.main()
