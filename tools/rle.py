"""RS decoder vendored from Castles tools/analysis/wbc3/rle.py.
Palette/shadow interpretation retained as a reference hypothesis.
"""
import struct
from pathlib import Path
from PIL import Image
def c565(v): return (((v>>11)&31)*255//31, ((v>>5)&63)*255//63, (v&31)*255//31)
def decode(path, pal_idx=0):
    d=Path(path).read_bytes()
    assert d[:2]==b'RS', d[:2]
    size,w,h=struct.unpack_from('<IHH',d,2)
    pals=[[c565(x) for x in struct.unpack_from('<256H',d,0x0a+512*p)] for p in range(8)]
    tb,_,nchunk,_=struct.unpack_from('<IIHH',d,0x100a)
    B=0x1016
    t=struct.unpack_from('<%dI'%(nchunk*h),d,B)
    img=Image.new('RGBA',(w,h),(0,0,0,0)); px=img.load(); pal=pals[pal_idx]
    for y in range(h):
        x=0
        for c in range(nchunk):
            a=t[c*h+y]; i=B+a; cw=min(128,w-c*128); x=c*128; end=x+cw
            while x<end:
                b=d[i]
                if b==0xff:
                    n=d[i+1]; i+=2
                    if n==0xff: x=end; break
                    x+=n
                elif b==0xfa:
                    n=d[i+1]; i+=2
                    for _ in range(n): px[x,y]=(0,0,0,110); x+=1
                elif b>=0xfb:
                    px[x,y]=(0,0,0,{0xfb:60,0xfc:85,0xfd:110,0xfe:140}[b]); x+=1; i+=1
                else:
                    px[x,y]=pal[b]+(255,); x+=1; i+=1
    return img,(w,h,nchunk)


# Team colour slots (ART_RESEARCH.md): the sprite renderer 0x487f20 copies a 15-entry RGB565 ramp of the owner's colour
# (table 0xa38ba4, built by 0x494450) over palette entries 224..238 before drawing (0x4888d3..0x4888f0).
TEAM_FIRST, TEAM_COUNT = 224, 15


def team_mask(path):
    """8-bit mask of the RS sheet: value k+1 where the pixel uses palette index 224+k (k = 0..14), 0 elsewhere.
    Walks the same chunk/run layout as decode(); decode() itself is unchanged so existing outputs keep their bytes."""
    d=Path(path).read_bytes()
    assert d[:2]==b'RS', d[:2]
    size,w,h=struct.unpack_from('<IHH',d,2)
    tb,_,nchunk,_=struct.unpack_from('<IIHH',d,0x100a)
    B=0x1016
    t=struct.unpack_from('<%dI'%(nchunk*h),d,B)
    mask=bytearray(w*h)
    for y in range(h):
        for c in range(nchunk):
            i=B+t[c*h+y]; x=c*128; end=x+min(128,w-c*128)
            while x<end:
                b=d[i]
                if b==0xff:
                    n=d[i+1]; i+=2
                    if n==0xff: break
                    x+=n
                elif b==0xfa:
                    x+=d[i+1]; i+=2
                elif b>=0xfb:
                    x+=1; i+=1
                else:
                    if TEAM_FIRST <= b < TEAM_FIRST+TEAM_COUNT: mask[y*w+x]=b-TEAM_FIRST+1
                    x+=1; i+=1
    return Image.frombytes('L',(w,h),bytes(mask))
