# Reference code written from scratch by Daniel Hardman, and released
# under the Apache 2.0 license.

import re
import unicodedata


AMPERS_PAT = re.compile(r'[&\uFE60\uFF06]')
SPECIALIZED_WHITESPACE_PAT = re.compile(r'[\u2028\u2029\u200B\uFEFF\u00A0\u3000\r\n\t]+')
MULTI_WHITESPACE_PAT = re.compile(r'\s{2,}')
DASHCHARS_PAT = re.compile(r'[\u058A\u05BE\u1400\u1806\u2010\u2011\u2012\u2013\u2014\u2015\u2e17\u2e1a\u2e3a\u2e3b\u2e40\u2e5d\u301c\u3030\u30a0\ufe31\ufe32\ufe58\ufe63\uff0d]+')
MULTI_HYPHENS_PAT = re.compile(r'-{2,}')
CJK_PUNCT_PAIRS = [
    ("\u3001", ","),
    ("\u3002", ".")
]
LONG_DOTS_PAT = re.compile(r'[.]{4,}')
QUOTERS_PAT = re.compile(r'["\u2018\u2019\u201C\u201D\u00AB\u00BB\u2039\u203A\u3008\u3009\u300A\u300B\u300C\u300D]')
ANY_WHITESPACE_PAT = re.compile(r'(\s+)')
AUTOCORRECT_PAIRS = [
    ("\u1f60A", ":-)"),
    ("\u1f610", ":-|"),
    ("\u2639", ":-("),
    ("\u1f603", ":-D"),
    ("\u1f61D", ":-p"),
    ("\u1f632", ":-o"),
    ("\u1f609", ";-)"),
    ("\u2764", "<3"),
    ("\u1f494", "</3"),
    ("\u00a9", "(c)"),
    ("\u00ae", "(R)"),
    ("\u2022", "*")
]
ASCII_EMOJI_PAIRS = [
    (":)", ":-)"),
    (":|", ":-|"),
    (":(", ":-("),
    (":D", ":-D"),
    (":p", ":-p"),
    (":o", ":-o"),
    (";)", ";-)")
]

def algorithm_1_14(plaintext):
    # We start with step 1 already complete, since Python 3 strings are already unicode.

    # step 2
    x = unicodedata.normalize('NFKC', plaintext)

    def step3(ampersands):
        return AMPERS_PAT.sub(' and ', ampersands)

    x = step3(x)

    def step4(whitespace_anomalies):
        out = SPECIALIZED_WHITESPACE_PAT.sub(' ', whitespace_anomalies)
        out = out.strip()
        out = MULTI_WHITESPACE_PAT.sub(' ', out)
        return out

    x = step4(x)

    def step5(punct_anomalies):
        # 5.i
        out = DASHCHARS_PAT.sub('-', punct_anomalies)
        # 5.ii
        out = MULTI_HYPHENS_PAT.sub('-', out)
        # 5.iii
        for cjk, ascii in CJK_PUNCT_PAIRS:
            out = out.replace(cjk, ascii)
        txt = ''
        for c in out:
            n = ord(c)
            if 0xFF01 <= n <= 0xFF5E:
                c = n - 0xFEE0
            txt += c
        # 5.iv
        out = txt.replace('\u2026', '...')
        # 5.v
        out = LONG_DOTS_PAT.sub('...', out)
        # 5.vi
        out = out.replace('\u2044', '/')
        # 5.vii
        out = QUOTERS_PAT.sub("'", out)
        txt = ''
        next = 0
        # 5.viii
        for match in ANY_WHITESPACE_PAT.finditer(out):
            keep_space = True
            i = match.start()
            if i > 0:
                txt += out[next:i]
                if unicodedata.category(out[i - 1]).startswith('P'):
                    keep_space = False
            next = match.end()
            if next < len(out):
                if unicodedata.category(out[next]).startswith('P'):
                    keep_space = False
            if keep_space:
                txt += match.group(1)
        txt += out[next:]
        out = txt
        # 5.ix
        for autocorrect, ascii in AUTOCORRECT_PAIRS:
            out = out.replace(autocorrect, ascii)
        # 5.x
        for noncanonical, canonical in ASCII_EMOJI_PAIRS:
            out = out.replace(noncanonical, canonical)
        return txt

    x = step5(x)

    # step 6
    return x.encode("UTF-8")


if __name__ == '__main__':
    from blake3 import blake3
    import base64

    print("Enter some text (two blank lines to end): ")
    lines = []
    blank_count = 0
    while True:
        line = input().strip()
        if not line:
            blank_count += 1
            if blank_count > 1:
                break
        else:
            blank_count = 0
        lines.append(line)
    cqt = algorithm_1_14("\n".join(lines))
    cqt_txt = cqt.decode("UTF-8")
    print(f"Canonical quoted text = {cqt_txt}")
    hash = base64.urlsafe_b64encode(blake3(cqt).digest()).decode("ASCII")
    print(f"hash = {hash}")
