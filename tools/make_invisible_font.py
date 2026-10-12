#!/usr/bin/env python3
# Builds Media/Fonts/Invisible.ttf: a TrueType font whose letters, digits and punctuation (U+0020..U+00FF) are
# empty glyphs with a width. Used as DAMAGE_TEXT_FONT, it makes the game's floating world text invisible.
# Usage: python3 tools/make_invisible_font.py
import os, struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLYPHS = 0xE0 + 1  # .notdef and U+0020..U+00FF
UNITS, ADVANCE = 1000, 500


def pad(data):
    return data + b'\0' * (-len(data) % 4)


def checksum(data):
    data = pad(data)
    return sum(struct.unpack('>%dI' % (len(data) // 4), data)) & 0xFFFFFFFF


def build():
    tables = {}
    tables['head'] = struct.pack('>IIIIHHqqhhhhHHhhh', 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, UNITS,
                                 0, 0, 0, 0, 0, 0, 0, 8, 2, 0, 0)
    tables['hhea'] = struct.pack('>IhhhHhhhhhhhhhhhH', 0x00010000, 800, -200, 0, ADVANCE, 0, 0, 0, 1, 0, 0,
                                 0, 0, 0, 0, 0, GLYPHS)
    tables['maxp'] = struct.pack('>IHHHHHHHHHHHHHH', 0x00010000, GLYPHS, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)
    tables['hmtx'] = struct.pack('>Hh', ADVANCE, 0) * GLYPHS
    tables['loca'] = struct.pack('>H', 0) * (GLYPHS + 1)
    tables['glyf'] = b'\0' * 4
    seg_end, seg_start, seg_delta = [0x00FF, 0xFFFF], [0x0020, 0xFFFF], [(1 - 0x20) & 0xFFFF, 1]
    sub = struct.pack('>HHHHHHH', 4, 0, 0, 4, 4, 1, 0)
    sub += struct.pack('>HH', *seg_end) + struct.pack('>H', 0) + struct.pack('>HH', *seg_start)
    sub += struct.pack('>HH', *seg_delta) + struct.pack('>HH', 0, 0)
    sub = sub[:2] + struct.pack('>H', len(sub)) + sub[4:]
    tables['cmap'] = struct.pack('>HHHHI', 0, 1, 3, 1, 12) + sub
    names = {1: 'ForeverPlus Invisible', 2: 'Regular', 4: 'ForeverPlus Invisible', 6: 'ForeverPlusInvisible'}
    records, strings = b'', b''
    for name_id, text in sorted(names.items()):
        encoded = text.encode('utf-16-be')
        records += struct.pack('>HHHHHH', 3, 1, 0x409, name_id, len(encoded), len(strings))
        strings += encoded
    tables['name'] = struct.pack('>HHH', 0, len(names), 6 + 12 * len(names)) + records + strings
    tables['post'] = struct.pack('>IIhhIIIII', 0x00030000, 0, -100, 50, 0, 0, 0, 0, 0)

    order = sorted(tables)
    count = len(order)
    search = 16 * (1 << (count.bit_length() - 1))
    header = struct.pack('>IHHHH', 0x00010000, count, search, count.bit_length() - 1, count * 16 - search)
    offset = 12 + 16 * count
    directory, body = b'', b''
    for tag in order:
        data = tables[tag]
        directory += struct.pack('>4sIII', tag.encode(), checksum(data), offset + len(body), len(data))
        body += pad(data)
    font = bytearray(header + directory + body)
    # checkSumAdjustment of "head"
    head_at = offset + len(b''.join(pad(tables[t]) for t in order[:order.index('head')]))
    struct.pack_into('>I', font, head_at + 8, (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF)
    return bytes(font)


if __name__ == '__main__':
    path = os.path.join(ROOT, 'Media', 'Fonts', 'Invisible.ttf')
    with open(path, 'wb') as f:
        f.write(build())
    print(path, os.path.getsize(path), 'bytes')
