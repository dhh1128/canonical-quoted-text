import sys, os, re, glob
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'impl', 'python'))
from cqt import algorithm_3_17 as c

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'clipboard')
SKIP = {'p4p-build-evidence', 'p4p-build-evidence-v2'}

labels = sorted({os.path.basename(p).split('.')[0]
                 for p in glob.glob(D + '/*.plain.txt')} - SKIP)

CHECKS = [
    ('backtick', lambda t: '`' in t),
    ('fence ```', lambda t: '```' in t),
    ('> marker', lambda t: re.search(r'(?m)^\s*>', t) is not None),
    ('span 2sp', lambda t: '--dry-run  &' in t or '-dry-run  &' in t),
    ('fence 2sp', lambda t: 'x  *  2' in t),
    ('indent', lambda t: re.search(r'(?m)^ {2,}return', t) is not None),
    ('URL --', lambda t: 'a--b' in t),
    ('URL &', lambda t: re.search(r'q=1&r=2', t) is not None),
    ('&amp;', lambda t: '&amp;' in t),
    ('prose --', lambda t: re.search(r'dashes --', t) is not None),
    ('straight "', lambda t: '"quoted"' in t),
    ('em dash', lambda t: '\u2014' in t),
    ('CRLF', lambda t: '\r\n' in t),
    ('NBSP', lambda t: ' ' in t),
]

print(f'{"label":<26}' + ''.join(f'{n:>11}' for n, _ in CHECKS))
rows = {}
for label in labels:
    t = open(f'{D}/{label}.plain.txt', encoding='utf-8').read()
    rows[label] = t
    cells = ''.join(f'{("yes" if f(t) else "-"):>11}' for _, f in CHECKS)
    print(f'{label:<26}{cells}')

print('\n=== flavors offered')
for label in labels:
    p = f'{D}/{label}.formats'
    if os.path.exists(p):
        fmts = [x for x in open(p).read().split('\n') if x.strip()]
        print(f'  {label:<26} {len(fmts):>2}  {", ".join(fmts[:6])}')

print('\n=== plain flavor, verbatim')
for label in labels:
    print(f'\n--- {label}  ({len(rows[label])} chars)')
    print(repr(rows[label]))
