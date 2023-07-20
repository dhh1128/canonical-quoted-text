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
        out = DASHCHARS_PAT.sub('-', punct_anomalies)
        out = MULTI_HYPHENS_PAT.sub('-', out)
        for cjk, ascii in CJK_PUNCT_PAIRS:
            out = out.replace(cjk, ascii)
        txt = ''
        for c in out:
            n = ord(c)
            if 0xFF01 <= n <= 0xFF5E:
                c = n - 0xFEE0
            txt += c
        out = txt.replace('\u2026', '...')
        out = LONG_DOTS_PAT.sub('...', out)
        out = out.replace('\u2044', '/')
        out = QUOTERS_PAT.sub("'", out)
        txt = ''
        next = 0
        for match in ANY_WHITESPACE_PAT.finditer(out):
            keep_space = True
            i = match.start()
            if i > 0:
                txt += out[next:i]
                if unicodedata.category(out[i - 1]).startswith('P'):
                    keep_space = False
            next = match.end()
            if next < len(out) - 1:
                if unicodedata.category(out[next]).startswith('P'):
                    keep_space = False
            if keep_space:
                txt += match.group(1)
        txt += out[next:]
        out = txt
        for autocorrect, ascii in AUTOCORRECT_PAIRS:
            out = out.replace(autocorrect, ascii)
        for noncanonical, canonical in ASCII_EMOJI_PAIRS:
            out = out.replace(noncanonical, canonical)
        return txt

    x = step5(x)

    return x.encode("UTF-8")


def test_hello():
    assert algorithm_1_14("hello") == b"hello"

def test_empty():
    assert algorithm_1_14("") == b""

def test_nkfc():
    assert algorithm_1_14("\uFEC9\uFECA\uFECB\uFECC") == b'\xd8\xb9\xd8\xb9\xd8\xb9\xd8\xb9'
    x = algorithm_1_14("ℌℍ\u00a0①ｶ︷︸⁹₉㌀¼ǆ")
    print(x)
    y = "HH 1カ{}99アパート1/4dž".encode("UTF-8")
    assert x == y

def test_leading_and_trailing_whitespace():
    assert algorithm_1_14(" abc  ") == b"abc"
    assert algorithm_1_14("\n abc\n\t  ") == b"abc"
    assert algorithm_1_14("\r abc\n\t  \n") == b"abc"
    assert algorithm_1_14("\u3000\u00a0abc\ufeff\u200b") == b"abc"

def test_trailing_whitespace_on_lines():
    assert algorithm_1_14("line1 \nline2") == b"line1 line2"

def test_redundant_linebreaks():
    assert algorithm_1_14("line1\n\nline2") == b"line1 line2"

def test_redundant_linebreaks_with_trailing_whitespace():
    assert algorithm_1_14("line1 \n \nline2") == b"line1 line2"

def test_cr_to_space():
    assert algorithm_1_14("line1\rline2") == b"line1 line2"

def test_2028_to_space():
    assert algorithm_1_14("line1\u2028\tline2") == b"line1 line2"

def test_2029_to_space():
    assert algorithm_1_14("line1\t\u2029\rline2") == b"line1 line2"

def test_crlf_to_space():
    assert algorithm_1_14("line1\r\nline2") == b"line1 line2"

def test_other_spaces():
    for x in '\u200B\ufeff\u00a0\u3000':
        assert algorithm_1_14('a' + x + 'b') == b"a b"

def test_squeeze():
    assert algorithm_1_14(("this  is  a \n\t\r   test")) == b"this is a test"

def test_ideographic_punct():
    assert algorithm_1_14("\u3001\u3000\u3002\u3008") == b",.'"

def test_ideographic_ascii():
    assert algorithm_1_14("\uFF01\uFF02\uFF25\uFF37\uFF56") == b"!'EWv"


if __name__ == '__main__':
    from blake3 import blake3
    import base58

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
    print("Canonical quoted text = %s" % cqt_txt)
    said = "E" + base58.b58encode(blake3(cqt).digest()).decode("ASCII")
    print("SAID = %s" % said)
