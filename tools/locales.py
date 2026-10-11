# Sets or removes locale strings in Locales/deDE.lua and Locales/enUS.lua.
# Input: JSON file {"de": {KEY: text}, "en": {KEY: text}, "del": [KEY, ...]}.
# Existing keys are replaced in place, new keys are appended.
# Usage: python3 tools/locales.py strings.json
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def lua(v):
    return '"' + v.replace('\\','\\\\').replace('"','\\"') + '"'
def apply(path, sets, dels=()):
    lines = open(path).read().split('\n')
    out = []
    done = set()
    for line in lines:
        m = re.match(r'^L\.(\w+) = ', line)
        if m and m.group(1) in dels:
            continue
        if m and m.group(1) in sets:
            out.append('L.%s = %s' % (m.group(1), lua(sets[m.group(1)])))
            done.add(m.group(1))
            continue
        out.append(line)
    # append missing before trailing empty lines
    while out and out[-1] == '':
        out.pop()
    for k, v in sets.items():
        if k not in done:
            out.append('L.%s = %s' % (k, lua(v)))
    open(path, 'w').write('\n'.join(out) + '\n')
if __name__ == '__main__':
    data = json.load(open(sys.argv[1]))
    for f in ('de', 'en'):
        apply(os.path.join(ROOT, 'Locales', '%s.lua' % ('deDE' if f == 'de' else 'enUS')), data.get(f, {}), data.get('del', []))
