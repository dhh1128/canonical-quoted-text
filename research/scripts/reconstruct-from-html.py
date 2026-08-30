"""Can markers be reconstructed from the HTML flavor for the apps that
stripped them from the plain flavor?"""
import sys, os, re, html as H
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'impl', 'python'))
from cqt import algorithm_3_17 as c

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'clipboard')
HERE = os.path.dirname(os.path.abspath(__file__))
doc = open(os.path.join(HERE, '..', 'clipboard', 'protocol.md'),
           encoding='utf-8').read()
SRC = c(doc.split('\n---\n')[1].strip('\n'))


def reconstruct(source):
    """Map the three structural elements back to CQT's markers, then flatten."""
    s = re.sub(r'(?is)<(script|style|head)\b.*?</\1\s*>', ' ', source)
    # CF_HTML carries a header before the fragment
    s = re.sub(r'(?is)^.*?<!--StartFragment-->', '', s)
    s = re.sub(r'(?is)<!--EndFragment-->.*$', '', s)
    # fenced block: <pre> possibly wrapping <code>
    def fence(m):
        inner = re.sub(r'(?is)</?code[^>]*>', '', m.group(1))
        inner = H.unescape(re.sub(r'(?s)<[^>]*>', '', inner))
        return '\n```\n' + inner.strip('\n') + '\n```\n'
    s = re.sub(r'(?is)<pre[^>]*>(.*?)</pre\s*>', fence, s)
    # blockquote: one '>' per line of its content
    def quote(m):
        inner = H.unescape(re.sub(r'(?s)<[^>]*>', '', m.group(1))).strip()
        return '\n' + '\n'.join('> ' + l for l in inner.split('\n')) + '\n'
    s = re.sub(r'(?is)<blockquote[^>]*>(.*?)</blockquote\s*>', quote, s)
    # inline code
    s = re.sub(r'(?is)<code[^>]*>(.*?)</code\s*>',
               lambda m: '`' + H.unescape(re.sub(r'(?s)<[^>]*>', '', m.group(1))) + '`', s)
    s = re.sub(r'(?i)<br\s*/?>|</(p|div|tr|li|h[1-6])\s*>', '\n', s)
    s = re.sub(r'(?s)<[^>]*>', '', s)
    return H.unescape(s)


for label in sorted(os.path.basename(p).split('.')[0]
                    for p in __import__('glob').glob(D + '/*.html.txt')):
    src = open(f'{D}/{label}.html.txt', encoding='utf-8', errors='replace').read()
    plain = open(f'{D}/{label}.plain.txt', encoding='utf-8').read()
    rebuilt = reconstruct(src)
    a, b = c(plain), c(rebuilt)
    print(f'{label:<26} plain {"VERIFIES" if a == SRC else "fails":<9} '
          f'reconstructed {"VERIFIES" if b == SRC else "fails"}')
    if b != SRC and a != SRC:
        print(f'    got: {b.decode()[:150]}')

print('\n=== full diff for the four that stripped markers')
import difflib
want = SRC.decode()
for label in ('facebook-msgr', 'github-issue-pretty', 'gmail-pretty', 'vscode-preview'):
    src = open(f'{D}/{label}.html.txt', encoding='utf-8', errors='replace').read()
    got = c(reconstruct(src)).decode()
    print(f'\n--- {label}')
    sm = difflib.SequenceMatcher(None, want, got)
    print(f'    similarity {sm.ratio():.3f}')
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag != 'equal':
            print(f'    {tag:<8} want={want[i1:i2]!r:<44} got={got[j1:j2]!r}')
