"""Static terrain/occupancy decoding. See COLLISION_RESEARCH.md for evidence and limits."""
import collections
import hashlib
import json
import struct
from pathlib import Path
from original_reader import cipher_inverse, chunks
from PIL import Image, ImageChops, ImageStat

EXE_HASH = '77d47d0eff727bdec9845b0cc47e63147f470b6059d379c3f0121dbd5b5689ce'
# Big-tile records whose partner quadrant was painted over in the shipped scenario (map wave 3, MAPS_RESEARCH.md "Wave 3"):
# (scenario, MAPH index, missing partner quadrant). The renderer (0x494862) and the TER lookup take each record's own
# quadrant, so such a record still draws and collides as its own quarter; any other broken pairing stays an error.
KNOWN_BROKEN_PAIRS = {('Scenario/Four Rivers.SCN', 84, 1), ('Scenario/Four Rivers.SCN', 104, 1),
                      ('Scenario/Four Rivers.SCN', 105, 1), ('Scenario/Forest Lakes.SCN', 97, 1),
                      ('Scenario/Forest Lakes.SCN', 123, 1), ('Scenario/Forest Lakes.SCN', 124, 1)}


def decode_ter(body, code):
    if len(body) != 1652:
        raise ValueError(f'{code}: expected 1652-byte TER')
    data = body.translate(cipher_inverse())
    if data[:4].decode('ascii') != code:
        raise ValueError(f'{code}: TER identifier mismatch')
    return dict(code=code, storage='column-major x*20+y', grid_size=[20,20],
        # Values remain raw where no consumer semantics have been established.
        cells=[list(data[i:i+4]) for i in range(4,1604,4)],
        big_shape=data[1607], tail_hex=data[1604:].hex(), decoded_hex=data.hex())


def sample_ter(terrain, local_x, local_y, quadrant):
    if quadrant not in range(4) or not (0 <= local_x < 10 and 0 <= local_y < 10):
        raise ValueError('Invalid terrain quadrant/local coordinate')
    sx=local_x+(quadrant&1)*10
    sy=local_y+(quadrant>>1)*10
    return terrain['cells'][sx*20+sy], [sx,sy], 4+(sx*20+sy)*4


def decode_footprint(body, code, kind):
    expected, start = (200,62) if kind=='buildings' else (68,24)
    if len(body)!=expected:
        raise ValueError(f'{code}: unsupported {kind} record size')
    data=body.translate(cipher_inverse())
    if data[:4].decode('ascii')!=code:
        raise ValueError(f'{code}: definition identifier mismatch')
    w,h=data[start:start+2]
    if not (1 <= w <= 16 and 1 <= h <= 16):
        raise ValueError(f'{code}: footprint exceeds 16x16 mask')
    masks=list(struct.unpack_from('<16H',data,start+2))
    # The original occupancy routines skip SET bits. Bit 0 is the leftmost cell.
    shape=[[x,y] for y in range(h) for x in range(w) if not masks[y] & (1<<x)]
    bypass=kind=='features' and data[58]!=0
    return dict(code=code, size=[w,h], mask_offset=start+2, masks=masks,
        occupancy_bypass=bypass, bypass_raw=data[58] if kind=='features' else None,
        solid_local_cells=[] if bypass else shape, unbypassed_local_cells=shape,
        decoded_hex=data.hex(), anchor_rule='cell_x-floor((width-1)/2), cell_y; Y extends down',
        status='static executable occupancy routine; runtime match initialization unverified')


def border_nav_material(nav_material, material, interior):
    """G1 (RANDOM_MAP_RESEARCH.md "RM-4", Emulated): 0x42bf80 writes the raw TER material into the cell's +9 byte for every
    cell, the border too, and 0x42cc10 fails a cell whose +9 byte is 9. On the border the nav array (hence the cost
    profile) stays 0, so `nav_material` carries the 9 there (navigation.gd blocks material 9 at the anchor) while
    `profile_passable` stays material 0's. Interior material-9 cells already block through cost row [9]."""
    return 9 if not interior and material == 9 else nav_material


def build_collision(source, out, manifest, entries):
    binary=(source/'Battlecry III.exe').read_bytes()
    if hashlib.sha256(binary).hexdigest()!=EXE_HASH:
        raise ValueError('Collision executable differs from inspected baseline; re-establish table/consumer addresses')
    # File offset = VA - 0x400000 in this pinned PE data section.
    costs=[list(struct.unpack_from('<13h',binary,0x203e68+row*26)) for row in range(4)]
    tiles={}
    for code in sorted({r['code'] for r in manifest['terrain_records']}):
        name,body,provenance=entries[code.lower()+'.ter']
        tiles[code]=decode_ter(body,code)
        tiles[code]['source']=provenance
    records=manifest['terrain_records']
    cols=(manifest['size_cells'][0]+9)//10
    rows=(manifest['size_cells'][1]+9)//10
    if len(records)!=cols*rows:
        raise ValueError('MAPH record count disagrees with engine ceil(dim/10) layout')
    checks=[]
    for record in records:
        i=record['index'];q=record['unknown_u32'][0]>>16
        shape=tiles[record['code']]['big_shape']
        if shape not in (0,1,2,3):
            raise ValueError(f'Unsupported TER big shape {shape}')
        allowed={0:[0],1:[0,1,2,3],2:[0,1],3:[0,2]}[shape]
        if q not in allowed:
            raise ValueError('MAPH quadrant contradicts TER shape')
        # For every used quadrant, require its origin/partners within the map prefab extent.
        ox=i%cols-(q&1);oy=i//cols-(q>>1)
        for partner in allowed:
            px=ox+(partner&1);py=oy+(partner>>1)
            if not (0<=px<cols and 0<=py<rows):
                continue
            candidate=records[py*cols+px]
            if candidate['code']!=record['code'] or candidate['unknown_u32'][0]>>16!=partner:
                if (manifest.get('source'),i,partner) in KNOWN_BROKEN_PAIRS:
                    continue
                raise ValueError(f'Broken quadrant pairing at MAPH index {i}')
        checks.append(dict(index=i, code=record['code'], quadrant=q, shape=shape, origin_prefab=[ox,oy]))
    width,height=manifest['size_cells']
    cells=[]
    for y in range(height):
        for x in range(width):
            record=records[(y//10)*cols+x//10]
            q=record['unknown_u32'][0]>>16
            raw,local,offset=sample_ter(tiles[record['code']],x%10,y%10,q)
            elevation,material,permission,reserved=raw
            if material>=13:
                raise ValueError(f'Unknown terrain material {material}')
            # 0x42de40 fills the nav array for interior cells only; border cells keep the zeroed
            # BSS value 0 that 0x42bf80 then reads (emulated: tools/emulate_collision_grid.py).
            interior=0<x<width-1 and 0<y<height-1
            nav_material=(material if permission else 12) if interior else 0
            profile=[row[nav_material]<=100 for row in costs]
            nav_material=border_nav_material(nav_material, material, interior)
            cells.append(dict(raw=raw, terrain_record=record['index'], source_cell=local,
                source_byte_offset=offset, nav_material=nav_material,
                profile_passable=profile,
                terrain_build_gate=permission!=0 and material not in [3,5,6,7,9],
                object_indices=[]))
    objects=[]
    definitions={}
    for kind,ext in [('buildings','.bui'),('features','.fea')]:
        for record in manifest[kind]:
            code=record['code'];key=code.lower()+ext
            if key not in definitions:
                name,body,provenance=entries[key]
                definitions[key]=decode_footprint(body,code,kind)
                definitions[key]['source']=provenance
            definition=definitions[key]
            w,h=definition['size']
            wx,wy=record['world_position']
            cx,cy=wx//32,wy//24
            origin=[cx-(w-1)//2,cy]
            occupied=[[origin[0]+x,origin[1]+y] for x,y in definition['solid_local_cells']]
            index=len(objects)
            outside=[]
            for x,y in occupied:
                if 0<=x<width and 0<=y<height:
                    cells[y*width+x]['object_indices'].append(index)
                else:
                    outside.append([x,y])
            objects.append(dict(index=index,kind=kind,code=code,name=record['name'],
                world_position=record['world_position'], anchor_cell=[cx,cy], origin_cell=origin,
                size=[w,h], definition=key, bypass=definition['occupancy_bypass'],
                occupied_cells=occupied, clipped_cells=outside, source_offset=record['source_offset']))
    result=dict(schema=1,size_cells=[width,height],cell_pixels=[32,24],storage='row-major y*width+x',
        cells=cells,objects=objects,definitions=definitions,tiles=tiles,quadrant_checks=checks,
        movement_cost_rows=costs, movement_profile_status='raw table rows 0..3; Swordsman/profile-0 association not established',
        evidence=dict(geometry='verified static engine accessors, MAPH serializer and quadrant placement',
            traversal='emulated 0x42de40/0x42bf80: interior permission-zero -> nav material 12, border cells nav material 0 (9 for TER material 9, G1); table threshold >100 blocks',
            buildability='necessary terrain gates only; full original construction check is not reconstructed',
            occupancy='verified static BUI/FEA masks and feature bypass, floor world-to-cell and anchor formula',
            preview='point-based straight-line probe; no original pathfinding, collision radius, dynamic armies or match replacement rules',
            runtime='original-game visual/route comparison still pending'),
        summary=dict(terrain_permission_zero=sum(c['raw'][2]==0 for c in cells),
            terrain_profile0_blocked=sum(not c['profile_passable'][0] for c in cells),
            object_occupied_cells=sum(bool(c['object_indices']) for c in cells),
            building_count=len(manifest['buildings']),feature_count=len(manifest['features']),
            bypassed_features=sum(o['kind']=='features' and o['bypass'] for o in objects),
            quadrant_records_validated=len(checks)))
    (out/'collision.json').write_text(json.dumps(result,sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8')
    write_overlays(out, result)
    return result


def write_overlays(out, result):
    width,height=result['size_cells']
    for mode in ['walk','build','height','material','objects']:
        image=Image.new('RGBA',(width,height),(0,0,0,0))
        pixels=[]
        for cell in result['cells']:
            occupied=bool(cell['object_indices'])
            if mode=='walk':
                color=(235,65,65,155) if not cell['profile_passable'][0] else ((250,170,40,170) if occupied else (50,205,160,45))
            elif mode=='build':
                color=(50,180,235,110) if cell['terrain_build_gate'] and not occupied else (235,80,110,155)
            elif mode=='height':
                v=cell['raw'][0];color=(min(255,30+v*32),max(0,200-v*20),max(0,245-v*28),145)
            elif mode=='material':
                v=cell['raw'][1];color=((v*83+50)%256,(v*47+110)%256,(v*131+180)%256,150)
            else:
                color=(250,170,40,190) if occupied else (0,0,0,0)
                if occupied and any(result['objects'][i]['kind']=='features' for i in cell['object_indices']):
                    color=(210,90,240,190)
            pixels.append(color)
        image.putdata(pixels)
        image.save(out/('collision_'+mode+'.png'))


def validate_minimap(scenario, out, composed, label):
    """scenario: the SCN path; label: its name in the output ('Scenario/Desert Sands.SCN'). SM24 is 128 x 128 in every
    shipped scenario, also on 192 and 256 maps (one pixel per 1.5 / 2 cells)."""
    body=next(b for tag,_,_,b in chunks(scenario.read_bytes()) if tag=='SM24')
    if len(body)!=128*128*3:
        raise ValueError('Unexpected SM24 preview size')
    raw=Image.frombytes('RGB',(128,128),body)
    b,g,r=raw.split()
    reference=Image.merge('RGB',(r,g,b))
    reference.save(out/'scenario_minimap.png')
    image=composed.resize((128,128),Image.Resampling.BOX)
    variants={'identity':image, 'flip_x':image.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
              'flip_y':image.transpose(Image.Transpose.FLIP_TOP_BOTTOM),
              'rotate_180':image.transpose(Image.Transpose.ROTATE_180),
              'transpose':image.transpose(Image.Transpose.TRANSPOSE)}
    errors={key:sum(ImageStat.Stat(ImageChops.difference(reference,value)).sum2)/(128*128*3)
            for key,value in variants.items()}
    rgb_error=sum(ImageStat.Stat(ImageChops.difference(raw,image)).sum2)/(128*128*3)
    result=dict(source=label+':SM24',size=[128,128],
        display_channel_order='BGR hypothesis: lower comparison error than raw RGB; not yet traced to original preview writer',
        terrain_only_mse=errors, raw_rgb_identity_mse=rgb_error,
        best_tested_orientation=min(errors,key=errors.get),
        caveat='Stored preview includes source features; current terrain excludes their artwork. Downsampling/color/objects differ, so this is corroboration, not pixel fidelity.')
    (out/'terrain_validation.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    return result
