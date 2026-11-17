"""AHKX ANI structural decoder; unknown fields are preserved, never guessed as FPS."""
import struct
from original_reader import cipher_inverse

# Executable suffix pointer table at VA 0x60e054, read by 0x48744c.
SUFFIXES = ['', 'w', 'f', 'd', 'a', 'z', 'c', 's', 'i']
DIRECTIONS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']


def decode_ani(body):
    if len(body) != 234:
        raise ValueError(f'Expected nine 26-byte ANI slots, got {len(body)} bytes')
    decoded = body.translate(cipher_inverse())
    slots = []
    for slot, suffix in enumerate(SUFFIXES):
        offset = slot * 26
        record = decoded[offset:offset+26]
        pivot_x, pivot_y, width, height = struct.unpack_from('<4h', record, 4)
        enabled, frames = record[:2]
        # Slot 5 ('z') may be enabled with frame count 0 (BPWT, EMDP): construction draws the fixed columns 0 / 1 / 2
        # (0x52c404..0x52c450), not the frame count, so the column count comes from the sheet (G-2).
        if enabled not in (0, 1) or (enabled and ((not frames and slot != 5) or width <= 0 or height <= 0)):
            raise ValueError(f'Invalid ANI slot {slot}')
        slots.append(dict(slot=slot, byte_offset=offset, suffix=suffix,
            enabled=bool(enabled), frame_count=frames,
            pivot=[pivot_x,pivot_y], frame_size=[width,height],
            raw_word_02=struct.unpack_from('<h',record,2)[0],
            unknown_words={f'0x{i:02x}':struct.unpack_from('<h',record,i)[0] for i in range(12,26,2)},
            decoded_hex=record.hex()))
    return dict(schema=1, bytes_per_slot=26, slots=slots, decoded_hex=decoded.hex(),
        evidence='ANIMATION_RESEARCH.md: executable loader/getters/renderer; source sheet geometry')


def validate_sheet(slot, size):
    w,h = slot['frame_size']
    if not slot['enabled'] or w <= 0 or h <= 0 or size[0] % w or size[1] % h:
        raise ValueError(f"ANI/sheet geometry mismatch: slot {slot['slot']}, {size}")
    columns, rows = size[0]//w,size[1]//h
    if columns < slot['frame_count'] or rows != 8:
        raise ValueError(f"ANI frame count/directions exceed sheet: slot {slot['slot']}")
    return columns, rows
