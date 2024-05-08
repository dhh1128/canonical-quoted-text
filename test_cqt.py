from cqt import *

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

def test_hyphens():
    assert algorithm_1_14("\u2010\u2011\u2012\u2013\u2014\u2015") == b"-"

def test_space_before_trailing_qmark():
    assert algorithm_1_14("hello ?") == b"hello?"

