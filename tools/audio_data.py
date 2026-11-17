"""Original audio export (AUDIO_RESEARCH.md). Never writes to the source installation.

Sources, as the executable opens them (0x4ca890 archive kinds):
  kind 0  Assets/SoundFX.xcr                 effects, UI sounds, attack/death/missile sets, building sounds
  kind 1  English/GameSpeech.xcr             advisor speech System<n> / SystemF<n>
  kind 4  Assets/Sides/<Side>VoicesEn.xcr     unit and hero voices <CODE>Select<n> / Order<n> / Ready / ...
  kind 3  loose files                        SoundFX/Terrain/*.wav (terrain ambience streams), SoundFX/Weather/*.wav
  music   Music/*.mp3 named by Music/Battlecry3.ini [SOUNDTRACK] (0x510710)
Every entry is a plain RIFF/WAVE PCM file (format tag 1, 8- or 16-bit, mono or stereo) or an MP3; the bytes are
copied unchanged so Godot plays the original data (AudioStreamWAV / AudioStreamMP3 load_from_buffer).
Lookup inside an archive is the first case-insensitive name match (0x4cd1f0); later duplicates are recorded as shadowed.
The folder gets a .gdignore so the Godot editor does not re-import ~1,900 files; the game loads them at runtime.
"""
import hashlib
import json
import re
import struct
from pathlib import Path

import original_reader as reader

AUDIO_DIR = 'audio'
MANIFEST = 'audio_manifest.json'
# Classification of 0x4180xx (Read): sample every 10th cell; the second code letter counts when the third is X/F/B.
TERRAIN_LETTERS = {'G': 0, 'H': 6, 'D': 1, 'E': 7, 'I': 3, 'W': 5, 'Y': 5, 'S': 2, 'M': 4}
TERRAIN_AMBIENT = {1: 'Prairie', 2: 'Desert', 3: 'Arctic', 8: 'Coast'}   # anything else: Plains


def audio_sources(source):
    sides = sorted((source / 'Assets/Sides').glob('*VoicesEn.xcr'))
    loose = sorted((source / 'SoundFX').rglob('*.wav'))
    music = sorted((source / 'Music').glob('*.mp3')) + [source / 'Music/Battlecry3.ini']
    return {source / 'Assets/SoundFX.xcr', source / 'English/GameSpeech.xcr', *sides, *loose, *music}


def wav_info(body):
    """RIFF chunk walk; returns the PCM format and frame count or raises ValueError."""
    if body[:4] != b'RIFF' or body[8:12] != b'WAVE':
        raise ValueError('not a RIFF/WAVE file')
    offset, fmt, frames = 12, None, None
    while offset + 8 <= len(body):
        tag, size = body[offset:offset + 4], struct.unpack_from('<I', body, offset + 4)[0]
        data = body[offset + 8:offset + 8 + size]
        if tag == b'fmt ':
            tag_id, channels, rate, byte_rate, align, bits = struct.unpack_from('<HHIIHH', data)
            fmt = dict(format_tag=tag_id, channels=channels, rate=rate, bits=bits, block_align=align)
        elif tag == b'data':
            if fmt is None:
                raise ValueError('data before fmt')
            frames = len(data) // fmt['block_align']
        offset += 8 + size + (size & 1)
    if fmt is None or frames is None:
        raise ValueError('missing fmt or data chunk')
    if fmt['format_tag'] != 1 or fmt['bits'] not in (8, 16) or fmt['channels'] not in (1, 2):
        raise ValueError(f'unsupported WAV format {fmt}')
    return dict(fmt, frames=frames, duration_ms=round(frames * 1000 / fmt['rate']))


def mp3_first_frame(body):
    """Offset of the first MPEG audio frame header (the shipped tracks start with zero padding), or -1."""
    start = 0
    if body[:3] == b'ID3':
        start = 10 + ((body[6] << 21) | (body[7] << 14) | (body[8] << 7) | body[9])
    for i in range(start, min(len(body) - 4, start + 0x40000)):
        if body[i] == 0xff and (body[i + 1] & 0xe0) == 0xe0 and (body[i + 1] >> 1) & 3 and (body[i + 2] >> 4) not in (0, 15):
            return i
    return -1


def soundtrack(text):
    """Music/Battlecry3.ini [SOUNDTRACK]; read by 0x510710 (Tracks capped at 20, Ambient0.., Intro, Victory, Defeat)."""
    values = {}
    section = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith('['):
            section = line.strip('[]').upper()
        elif section == 'SOUNDTRACK' and '=' in line and not line.startswith('//'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    tracks = min(20, int(values.get('Tracks', '0')))
    stem = lambda v: Path(v.replace('\\', '/').lstrip('/')).stem
    return dict(title=values.get('Title', ''), tracks=tracks,
                ambient=[stem(values[f'Ambient{i}']) for i in range(tracks) if f'Ambient{i}' in values],
                intro=stem(values.get('Intro', 'WBC3_Theme.mp3')), victory=stem(values.get('Victory', 'WBC3_Theme.mp3')),
                defeat=stem(values.get('Defeat', 'WBC3_Theme.mp3')))


def terrain_ambient(manifest):
    """Desert Sands' terrain ambience: one sample per 10 x 10-cell prefab tile (the original samples every 10th cell)."""
    counts = [0] * 8
    for record in manifest['terrain_records']:
        code = record['code']
        if len(code) >= 3 and code[2].upper() in 'XFB' and code[1].upper() in TERRAIN_LETTERS:
            counts[TERRAIN_LETTERS[code[1].upper()]] += 1
    merged = [counts[0] + counts[6], counts[1] + counts[7]] + counts[2:6]
    best = 0
    for i in range(6):
        if merged[best] < merged[i]:
            best = i
    kind = best
    if best == 5:                       # water dominates: the largest of the first five, 0 -> coast (8)
        kind, best_value = 0, merged[0]
        for i in range(5):
            if best_value < merged[i]:
                kind, best_value = i, merged[i]
        kind = kind or 8
    return dict(counts=counts, kind=kind, name=TERRAIN_AMBIENT.get(kind, 'Plains'))


def arm_sound_fields(source):
    """ARM sound fields (the 0x14c-byte record at 0x6e3f18 + type * 0x14c, file offset = memory offset)."""
    inverse = reader.cipher_inverse()
    out = {}
    for path in sorted((source / 'Assets/Sides').glob('*.xcr')):
        if path.name.endswith('VoicesEn.xcr'):
            continue
        for name, offset, body in reader.archive(path):
            if not name.upper().endswith('.ARM') or len(body) < 0x10c:
                continue
            d = body.translate(inverse)
            h = lambda o: struct.unpack_from('<h', d, o)[0]
            out.setdefault(name[:4].upper(), dict(side=path.stem, movement_sound=h(0xce), attack_sound=h(0xd0),
                voice_variants=h(0x106), struck_sound=h(0x108), death_sound=h(0x10a)))
    return out


def build_audio(source, out, map_manifest):
    folder = out / AUDIO_DIR
    folder.mkdir(exist_ok=True)
    (folder / '.gdignore').write_text('', encoding='utf-8')
    entries, shadowed, voices = [], [], {}

    def add(group, name, body, provenance):
        key = f'{group}/{Path(name).stem}'
        if any(e['id'].lower() == key.lower() for e in entries_by_group.get(group, [])):
            shadowed.append(dict(id=key, **provenance))
            return
        suffix = Path(name).suffix.lower()
        target = folder / group / (Path(name).stem + suffix)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
        entry = dict(id=key, group=group, file=f'{AUDIO_DIR}/{group}/{target.name}', bytes=len(body),
                     sha256=hashlib.sha256(body).hexdigest(), source=provenance)
        if suffix == '.wav':
            entry['format'] = wav_info(body)
        elif suffix == '.mp3':
            first = mp3_first_frame(body)
            if first < 0:
                raise ValueError(f'not an MP3 stream: {name}')
            entry['format'] = dict(kind='mp3', first_frame=first)
        entries.append(entry)
        entries_by_group.setdefault(group, []).append(entry)

    entries_by_group = {}
    for archive, group in [('Assets/SoundFX.xcr', 'sfx'), ('English/GameSpeech.xcr', 'speech')] + \
            [(p.relative_to(source).as_posix(), 'voices/' + p.name[:-len('VoicesEn.xcr')])
             for p in sorted((source / 'Assets/Sides').glob('*VoicesEn.xcr'))]:
        for name, offset, body in reader.archive(source / archive):
            add(group, name, body, dict(archive=archive, entry=name, offset=offset))
            if group.startswith('voices/'):
                voices.setdefault(re.match(r'(\w{4})', name).group(1).upper(), group)
    for path in sorted((source / 'SoundFX').rglob('*.wav')):
        add(path.parent.name.lower(), path.name, path.read_bytes(), dict(file=path.relative_to(source).as_posix()))
    for path in sorted((source / 'Music').glob('*.mp3')):
        add('music', path.name, path.read_bytes(), dict(file=path.relative_to(source).as_posix()))
    track = soundtrack((source / 'Music/Battlecry3.ini').read_text(encoding='latin1'))
    known = {e['id'] for e in entries}
    for name in track['ambient'] + [track['intro'], track['victory'], track['defeat']]:
        if f'music/{name}' not in known:
            raise ValueError(f'Battlecry3.ini names a missing track: {name}')
    entries.sort(key=lambda e: e['id'].lower())
    groups = {}
    for e in entries:
        groups[e['group']] = groups.get(e['group'], 0) + 1
    return dict(schema=1, status='original bytes, unchanged; ids are <group>/<entry stem> (lookup case-insensitive)',
                counts=dict(entries=len(entries), shadowed=len(shadowed), groups=groups),
                entries=entries, shadowed=shadowed, voice_archives=voices, soundtrack=track,
                terrain_ambient=terrain_ambient(map_manifest), arm_sounds=arm_sound_fields(source))


def check_audio(assets):
    """Every exported file is present and unchanged (the manifest itself is hashed by import_manifest.json)."""
    manifest = json.loads((assets / MANIFEST).read_text(encoding='utf-8'))
    for entry in manifest['entries']:
        path = assets / entry['file']
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError(f'Audio output missing or modified: {entry["file"]}; rerun importer')
    if not (assets / AUDIO_DIR / '.gdignore').is_file():
        raise ValueError('assets/audio/.gdignore missing; rerun importer')
    return manifest
