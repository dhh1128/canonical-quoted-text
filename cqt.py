import re
import unicodedata


def algorithm_1_14(plaintext):
    # We start with step 1 already complete, since Python 3 strings are already unicode.

    # step 2
    x = unicodedata.normalize('NFKC', plaintext)

    def step3(whitespace_anomalies):
        pat1 = re.compile(r'[\u200B\uFEFF\u00A0\u3000]+')
        output = pat1.sub(' ', whitespace_anomalies)
        pat2 = re.compile(r'[\r\u2028\u2029]+')
        output = pat2.sub('\n', output)
        pat3 = re.compile(r'(?!\n)(\s+)\n')
        output = pat3.sub('\n', output)
        output = output.strip()
        pat4 = re.compile(r'[\n]{2,}')
        output = pat4.sub('\n', output)
        pat5 = re.compile(r'[ ]{2,}')
        output = pat5.sub(' ', output)
        output = output.replace('\n ', '\n')
        return output

    x = step3(x)

    def step4(punct_anomalies):
        pat = re.compile(r'[\u2011\u2012\u2013\u2014\u2015\u207B\uFF0D]')
        new = pat.sub('-', punct_anomalies)
        pat2 = re.compile(r'-{2,}')
        new = pat2.sub('-', new)
        new = new.replace('\u2026', '...')
        new = new.replace('\u2044', '/')
        pat3 = re.compile(r'["\u2018\u2019\u201C\u201D\u00AB\u00BB\u2039\u203A]')
        new = pat3.sub("'", new)
        pat4 = re.compile(r'(\s+)')
        output = ''
        next = 0
        for match in pat4.finditer(new):
            keep_space = True
            i = match.start()
            if i > 0:
                output += new[next:i]
                if unicodedata.category(new[i - 1]).startswith('P'):
                    keep_space = False
            next = match.end()
            if next < len(new) - 1:
                if unicodedata.category(new[next]).startswith('P'):
                    keep_space = False
            if keep_space:
                output += match.group(1)
        output += new[next:]
        return output

    x = step4(x)
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
    assert algorithm_1_14("line1 \nline2") == b"line1\nline2"

def test_redundant_linebreaks():
    assert algorithm_1_14("line1\n\nline2") == b"line1\nline2"

def test_redundant_linebreaks_with_trailing_whitespace():
    assert algorithm_1_14("line1 \n \nline2") == b"line1\nline2"

def test_cr_to_lf():
    assert algorithm_1_14("line1\rline2") == b"line1\nline2"

def test_2028_to_lf():
    assert algorithm_1_14("line1\u2028line2") == b"line1\nline2"

def test_2029_to_lf():
    assert algorithm_1_14("line1\u2029line2") == b"line1\nline2"

def test_crlf_to_lf():
    assert algorithm_1_14("line1\r\nline2") == b"line1\nline2"

def test_other_spaces():
    for x in '\u200B\ufeff\u00a0\u3000':
        assert algorithm_1_14('a' + x + 'b') == b"a b"

def test_squeeze():
    assert algorithm_1_14(("this  is  a \n\t\r   test")) == b"this is a\ntest"