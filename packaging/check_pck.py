"""PACKAGING.md step 3: lists the Godot .pck embedded in an exported .exe and fails when it holds anything that must
not ship (the imported game data, tests, tools, local files) or lacks the rule tables the game reads.

  python packaging/check_pck.py .local/packaging/game/WBC3Redux.exe
"""
import collections
import struct
import sys

FORBIDDEN = ('assets/', 'tests/', 'tools/', 'packaging/', '.local/', '.claude/')
REQUIRED = ('simulation/hero_races.json', 'simulation/unit_ai_scripts.json', 'menus/front_end.gdc', 'battle/main.tscn.remap')


def read_pck(path):
    data = open(path, 'rb').read()
    if data[-4:] != b'GDPC':
        raise SystemExit(f'{path}: no embedded .pck (expected the GDPC trailer)')
    pck_size = struct.unpack_from('<Q', data, len(data) - 12)[0]
    start = len(data) - 12 - pck_size
    if data[start:start + 4] != b'GDPC':
        raise SystemExit(f'{path}: .pck header not found')
    version, major, minor, patch, flags, base = struct.unpack_from('<5IQ', data, start + 4)
    pos = start + 4 + 20 + 8
    if version >= 3:
        pos = start + struct.unpack_from('<Q', data, pos)[0]   # directory offset
    else:
        pos += 16 * 4
    count = struct.unpack_from('<I', data, pos)[0]
    pos += 4
    files = []
    for _ in range(count):
        n = struct.unpack_from('<I', data, pos)[0]
        pos += 4
        name = data[pos:pos + n].rstrip(b'\0').decode('utf-8').replace('res://', '')
        pos += n
        offset, size = struct.unpack_from('<QQ', data, pos)
        pos += 16 + 16 + 4   # offset, size, md5, flags
        files.append((name, size))
    return f'{major}.{minor}.{patch}', version, files


def main():
    engine, version, files = read_pck(sys.argv[1])
    names = [n for n, _ in files]
    folders = collections.Counter(n.split('/')[0] if '/' in n else '(root)' for n in names)
    print(f'PCK v{version}, Godot {engine}: {len(files)} files, {sum(s for _, s in files) / 1048576:.1f} MB; '
          + ', '.join(f'{k} {v}' for k, v in folders.most_common()))
    bad = [n for n in names if n.startswith(FORBIDDEN)]
    missing = [r for r in REQUIRED if not any(n == r or n.endswith('/' + r) for n in names)]
    if bad or missing:
        if bad: print('Must not ship:', bad[:20], f'({len(bad)})')
        if missing: print('Missing:', missing)
        raise SystemExit(1)
    print('PCK check passed: nothing from ' + ', '.join(FORBIDDEN) + '; rule tables and scenes present')


if __name__ == '__main__':
    main()
