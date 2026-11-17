"""Hero items and skill names (milestone 11-hero). Importer module; writes the ignored assets/items.json.

Source: `English/Items.xcr` entry `Items.xml` (archive cipher), the file 0x4030f0 copies to Tempfile.dat and
0x403220 parses into the item table at 0x62db80 (0x27c bytes per item, items numbered 1.. in file order, not by
their id attribute) and the set table at 0x62db80 + 0x27c08. Power elements go through 0x403a90, whose type-name
table is POWER_TYPES below (emulated in tools/emulate_hero_skills.py, compared by tools/test_hero_items.py).
Skill names: `English/Game.txt` [0759 + id] (Ferocity = skill 1 ... Contamination = skill 100). See HERO_RESEARCH.md.
"""
import re
import xml.etree.ElementTree as ET

import original_reader as reader

# 0x403a90: Power "type" attribute -> record type code (+0x260 + id * 2). Unknown names leave the slot unchanged (0).
POWER_TYPES = {
    'combat': 1, 'command': 10, 'speed': 5, 'speed attack': 0x2f, 'slow': 0x38, 'slow attack': 0x37,
    'slashing': 0x5b, 'crushing': 0x5c, 'piercing': 0x5a, 'fire': 0x5d, 'ice': 0x5e, 'electricity': 0x5f,
    'magic': 0x60, 'resistance': 6, 'fire resistance': 0x50, 'cold resistance': 0x58,
    'electricity resistance': 0x59, 'magic resistance': 0x51, 'armor': 0x18, 'spell failure': 0x61,
    'cast spell': 0x62, 'hero skill': 99, 'discount': 0xb, 'morale': 7, 'spell casting': 0x1c,
    'spell range': 0x20, 'mana discount': 0x24, 'assassin': 0x22, 'vampirism': 0x3c, 'critical hit': 0x1b,
    'mana regen': 0x21, 'life regen': 0x2c, 'vision': 0x2d, 'immunity disease': 0x39, 'immunity poison': 0x3a,
    'none': 0xd,
}
# 0x403220 Data "level" attribute -> +0x280 (0 cursed, 1 minor, 2 lesser, 3 greater, 4 artifact, 5 set); other text keeps 1.
LEVELS = {'minor': 1, 'lesser': 2, 'greater': 3, 'cursed': 0, 'artifact': 4, 'set': 5}
# 0x55ec20 / 0x42a0d0: Image iconrow -> equipment slot (rows 5 and 10 fit slot 4 or 5). Emulated.
ROW_SLOTS = {0: [2], 1: [2], 2: [1], 3: [1], 4: [3], 8: [3], 5: [4, 5], 10: [4, 5], 6: [0], 7: [0], 9: [6]}


def _int(element, name):
    """0x5aa4e0: the attribute as an integer (atoi of the text, 0 when absent)."""
    text = element.get(name)
    if text is None:
        return 0
    m = re.match(r'\s*([+-]?\d+)', text)
    return int(m.group(1)) if m else 0


def _power(element):
    kind = element.get('type', '')
    return dict(type=POWER_TYPES.get(kind.lower(), 0), type_name=kind, data=_int(element, 'data'), level=_int(element, 'level'),
                chance=_int(element, 'chance'), text=(element.text or '').strip())


def parse_items(xml_text):
    # The file holds two top-level elements (<Items> and <Sets>); the original parser reads both from the document.
    root = ET.fromstring('<Root>' + xml_text.split('?>', 1)[-1] + '</Root>')
    items = [None]
    for index, element in enumerate(root.find('Items').findall('Item'), start=1):
        record = dict(index=index, xml_id=_int(element, 'id'), name='unnamed', description='', iconrow=0, iconcol=0,
                      value=1, level=1, rarity=0, set=0, powers=[{}, {}, {}], power_count=0)
        for child in element:
            if child.tag == 'Name':
                record['name'] = (child.text or '')
            elif child.tag == 'Description':
                record['description'] = (child.text or '')
            elif child.tag == 'Image':
                record['iconrow'], record['iconcol'] = _int(child, 'iconrow'), _int(child, 'iconcol')
            elif child.tag == 'Data':
                record['value'], record['set'], record['rarity'] = _int(child, 'value'), _int(child, 'set'), _int(child, 'rarity')
                record['level'] = LEVELS.get(child.get('level', '').lower(), record['level'])
            elif child.tag == 'Power':
                slot = _int(child, 'id')
                record['powers'][slot] = _power(child)
                record['power_count'] += 1
        record['powers'] = [p if p else dict(type=0, type_name='', data=0, level=0, chance=0, text='') for p in record['powers']]
        items.append(record)
    sets = []
    for number, element in enumerate(root.find('Sets').findall('Set')):
        entry = dict(index=number, name='', power=dict(type=0, type_name='', data=0, level=0, chance=0, text=''), items=[])
        for child in element:
            if child.tag == 'Name':
                entry['name'] = child.text or ''
            elif child.tag == 'Power':
                entry['power'] = _power(child)
            elif child.tag == 'Item':
                entry['items'].append(_int(child, 'id'))
                if 0 < _int(child, 'id') < len(items):
                    items[_int(child, 'id')]['set'] = number + 1      # 0x403220: item +0x27a = set index + 1
        sets.append(entry)
    return items, sets


def skill_names(source):
    text = (source / 'English' / 'Game.txt').read_bytes().decode('latin1')
    names = {}
    for skill in range(1, 101):
        m = re.search(r'\[%04d\]\t([^\r\n]*)' % (759 + skill), text)
        if m:
            names[skill] = m.group(1).strip()
    return names


def items_xml(source):
    for name, _, body in reader.archive(source / 'English' / 'Items.xcr'):
        if name.lower() == 'items.xml':
            return body.translate(reader.cipher_inverse()).decode('latin1')
    raise ValueError('Items.xml missing from English/Items.xcr')


def build_items(source):
    items, sets = parse_items(items_xml(source))
    return dict(schema=1, source='English/Items.xcr/Items.xml (0x403220, 0x403a90); English/Game.txt [0760..0859]',
                count=len(items) - 1, items=items[1:], sets=sets, power_types=POWER_TYPES, row_slots={str(k): v for k, v in ROW_SLOTS.items()},
                skill_names={str(k): v for k, v in skill_names(source).items()},
                notes='Items are numbered by file order from 1 (0x403220 counts them; 226 = 225 items + 1 is its success test). '
                      'Power slot = the id attribute. Sets: item +0x27a = set index + 1.')


def hero_sources(source):
    return {source / 'English' / 'Items.xcr', source / 'English' / 'Game.txt'}
