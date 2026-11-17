"""Map object presentation data (any imported map). Static evidence: OBJECT_RESEARCH.md."""
import json
from ani import decode_ani
from original_reader import cipher_inverse
from rle import decode


KINDS = [('buildings', '.bui', 63), ('features', '.fea', 25)]
FEATURE_OUTPUT = 'feature_presentations.json'


def object_definition(out, code, kind, ext, height_offset, entries):
    """One object's presentation; writes its sheet to `out` (shared by every map, named by object id)."""
    _, body, source = entries[code.lower()+'.ani']
    ani = decode_ani(body)
    slot = ani['slots'][0]
    if not slot['enabled']:
        raise ValueError(f'{code}: disabled standing presentation')
    _, raw, sheet_source = entries[code.lower()+'.rle']
    filename = code+'.object.rle'
    (out/filename).write_bytes(raw)
    image, _ = decode(out/filename)
    w, h = slot['frame_size']
    if image.width != w*slot['frame_count'] or image.height != h:
        raise ValueError(f'{code}: unexpected object sheet layout {image.size}')
    image.save(out/(filename+'.png'))
    _, body, definition_source = entries[code.lower()+ext]
    data = body.translate(cipher_inverse())
    depth = (data[height_offset]*24-24)//2
    if kind == 'features' and data[58] and data[59]:
        depth -= 48
    depth = depth or 1
    return dict(ani=ani, ani_source=source, sheet_source=sheet_source,
        definition_source=definition_source, texture=filename+'.png',
        frame_size=slot['frame_size'], pivot=slot['pivot'], frames=slot['frame_count'],
        first_interval_ms=(slot['unknown_words']['0x18'] or 100) if kind=='buildings' else 100,
        interval_ms=(slot['unknown_words']['0x18'] or 100) if kind=='buildings' else 100,
        depth_offset=depth, palette=0,
        status='Static ANI geometry/depth/timing; palette and shadow composition hypothesis')


def build_feature_presentations(out, codes, entries):
    """RM-3: the sheets and presentations of the Random Map pieces' feature codes (a generated map has no map_objects.json)."""
    kind, ext, height_offset = KINDS[1]
    definitions = {code: object_definition(out, code, kind, ext, height_offset, entries) for code in sorted(codes)}
    for definition in definitions.values():
        del definition['ani']                  # the geometry is in the fields above; keeps the file small
    (out/FEATURE_OUTPUT).write_text(json.dumps(dict(schema=1, definitions=definitions),
        indent=1, sort_keys=True)+'\n', encoding='utf-8')


def build_presentations(out, manifest, entries, data_dir=None):
    """Sheets go to `out` (shared by every map, named by object id); map_objects.json to `data_dir` (the map's folder)."""
    definitions = {}
    placements = []
    for kind, ext, height_offset in KINDS:
        for record in manifest[kind]:
            code = record['code']
            if code not in definitions:
                definitions[code] = object_definition(out, code, kind, ext, height_offset, entries)
            placements.append(dict(kind=kind, code=code, source_offset=record['source_offset'],
                world_position=record['world_position'], raw_hex=record['raw_hex']))
    ((data_dir or out)/'map_objects.json').write_text(json.dumps(dict(schema=1, definitions=definitions,
        placements=placements, presentation='standing slot 0; match-state changes not implemented'),
        indent=2, sort_keys=True)+'\n', encoding='utf-8')
