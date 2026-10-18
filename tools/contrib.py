"""Reads the exports players send in (/fp daten export) from contrib/*.txt.

One file per contributor (the newest export replaces the older one: the addon
exports everything it has recorded so far, so adding files up would count
everything twice). Names come from any client: English ones win, other languages fill the gaps (the beta is not fully translated yet).

    python3 -I tools/contrib.py            # summary of the files in contrib/
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.environ.get("FP_CONTRIB") or os.path.join(ROOT, "contrib")

# Limits against typos and abuse: one contributor can add this much to one entry.
MAX_WINDOWS = 5000
MAX_COUNT = 50
MAX_ITEMS = 120

STRING = r'"((?:[^"\\]|\\.)*)"'
NUMBER = r'(-?\d+(?:\.\d+)?)'


def unescape(text):
    """Lua string escapes as the addon writes them with %q."""
    text = re.sub(r'\\(\d{1,3})', lambda m: bytes([int(m.group(1))]).decode('latin-1'), text)
    return re.sub(r'\\(.)', lambda m: {'n': '\n'}.get(m.group(1), m.group(1)), text)


def cells(text):
    """'{ map, x, y, count }, ...' -> [(map, x, y, count)]"""
    result = []
    for m in re.finditer(r'\{\s*(\d+)\s*,\s*' + NUMBER + r'\s*,\s*' + NUMBER + r'(?:\s*,\s*(\d+))?\s*\}', text):
        x, y = float(m.group(2)), float(m.group(3))
        if 0 <= x <= 100 and 0 <= y <= 100 and int(m.group(1)) > 0:
            result.append((int(m.group(1)), x, y, min(int(m.group(4) or 1), MAX_COUNT)))
    return result


def ids(text):
    return [int(n) for n in re.findall(r'\d+', text)]


def parse(text):
    """One export -> {'meta': {build, locale}, 'loot': [...], 'inns': [...], ...}"""
    result = {'meta': {}, 'loot': [], 'inns': [], 'rides': [], 'books': [], 'npcs': [], 'objectives': [], 'creatures': [], 'flights': []}
    m = re.search(r'^-- @fp-export \d+(.*)$', text, re.M)
    if m:
        result['meta'] = dict(re.findall(r'(\w+)=(\S+)', m.group(1)))
    section = None
    for line in text.splitlines():
        line = line.strip()
        tag = re.match(r'^-- @fp (\w+)$', line)
        if tag:
            section = tag.group(1)
            continue
        if not line.startswith('{') or section not in result:
            continue
        try:
            row = parse_line(section, line)
        except (ValueError, IndexError):
            row = None
        if row:
            result[section].append(row)
    return result


def parse_line(section, line):
    if section == 'loot':
        m = re.match(r'^\{\s*' + STRING + r'\s*,\s*' + STRING + r'\s*,\s*(\d+)\s*,\s*\{(.*)\}\s*\}\s*,?$', line)
        if not m or not re.match(r'^(npc|object):\d+$', m.group(1)):
            return None
        items = {int(i): min(int(n), MAX_WINDOWS) for i, n in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', m.group(4))}
        windows = min(int(m.group(3)), MAX_WINDOWS)
        # an item cannot drop more often than there are windows
        items = {i: min(n, windows) for i, n in list(items.items())[:MAX_ITEMS] if n > 0}
        return (m.group(1), unescape(m.group(2)), windows, items) if windows > 0 and items else None
    if section == 'inns':
        m = re.match(r'^\{\s*(\d+)\s*,\s*(\d+)\s*,\s*' + NUMBER + r'\s*,\s*' + NUMBER + r'\s*,\s*' + STRING + r'\s*,\s*' + STRING + r'\s*\}', line)
        if not m or m.group(5) not in ('A', 'H', 'N'):
            return None
        return (int(m.group(1)), int(m.group(2)), float(m.group(3)), float(m.group(4)), m.group(5), unescape(m.group(6)))
    if section == 'rides':
        m = re.match(r'^\{\s*(\d+)\s*,\s*' + NUMBER + r'\s*,\s*' + NUMBER + r'\s*,\s*(\d+)\s*,\s*' + NUMBER + r'\s*,\s*' + NUMBER + r'\s*,\s*(\d+)\s*\}', line)
        if not m:
            return None
        values = [float(m.group(i)) for i in (2, 3, 5, 6)]
        if not all(0 <= v <= 1 for v in values) or not 5 <= int(m.group(7)) <= 1800:
            return None
        return (int(m.group(1)), values[0], values[1], int(m.group(4)), values[2], values[3], int(m.group(7)))
    if section == 'flights':
        m = re.match(r'^\{\s*' + STRING + r'\s*,\s*(\d+)\s*\}', line)
        if not m or ' -> ' not in m.group(1) or not 5 <= int(m.group(2)) <= 1800:
            return None
        return (unescape(m.group(1)), int(m.group(2)))
    if section == 'books':
        m = re.match(r'^\{\s*(\d+)\s*,\s*(\d+)\s*,\s*' + NUMBER + r'\s*,\s*' + NUMBER + r'\s*\}', line)
        return (int(m.group(1)), int(m.group(2)), float(m.group(3)), float(m.group(4))) if m else None
    if section == 'npcs':
        m = re.match(r'^\{\s*(\d+)\s*,\s*' + STRING + r'\s*,\s*\{([^}]*)\}\s*,\s*\{([^}]*)\}\s*,\s*\{(.*)\}\s*\}\s*,?$', line)
        if not m:
            return None
        return (int(m.group(1)), unescape(m.group(2)), ids(m.group(3)), ids(m.group(4)), cells(m.group(5)))
    if section == 'objectives':
        m = re.match(r'^\{\s*(\d+)\s*,\s*(\d+)\s*,\s*\{(.*)\}\s*\}\s*,?$', line)
        return (int(m.group(1)), int(m.group(2)), cells(m.group(3))) if m else None
    if section == 'creatures':
        m = re.match(r'^\{\s*(\d+)\s*,\s*\{(.*)\}\s*\}\s*,?$', line)
        return (int(m.group(1)), cells(m.group(2))) if m else None


def load(directory=DIR):
    """{contributor: parsed export} for every contrib/*.txt."""
    result = {}
    for path in sorted(glob.glob(os.path.join(directory, '*.txt'))):
        with open(path, encoding='utf-8', errors='replace') as f:
            result[os.path.splitext(os.path.basename(path))[0]] = parse(f.read())
    return result


def points(cell_list):
    """Cells -> position dicts as the Efficient Games data have them (fractions of the map)."""
    result = []
    for uimap, x, y, count in cell_list:
        result += [{'uiMap': uimap, 'mapX': x / 100, 'mapY': y / 100}] * count
    return result


if __name__ == '__main__':
    submissions = load()
    if not submissions:
        print('no files in %s' % DIR)
    for name, data in submissions.items():
        print('%s: %s' % (name, ', '.join('%d %s' % (len(v), k) for k, v in data.items() if k != 'meta' and v) or 'nothing'),
              data['meta'])
    sys.exit(0)
