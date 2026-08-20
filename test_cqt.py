import json
import time
from pathlib import Path

import pytest

import unicodedata2 as unicodedata

from cqt import (
    SPACELESS_SCRIPTS,
    TERMINAL_PUNCTUATION,
    CqtError,
    DASH_PUNCTUATION,
    algorithm_2_17,
)


GOLDENS_PATH = Path(__file__).parent / "goldens" / "cqt2.17.json"


def load_goldens():
    return json.loads(GOLDENS_PATH.read_text(encoding="utf-8"))


def test_golden_manifest():
    manifest = load_goldens()
    assert manifest["algorithm"] == "cqt2.17"
    assert manifest["unicode_version"] == "17.0.0"
    ids = [case["id"] for case in manifest["cases"]]
    assert len(ids) == len(set(ids))
    assert all(("output" in case) ^ ("error" in case) for case in manifest["cases"])


@pytest.mark.parametrize("case", load_goldens()["cases"], ids=lambda case: case["id"])
def test_normative_golden(case):
    if "output" in case:
        assert algorithm_2_17(case["input"]) == case["output"].encode("utf-8")
    else:
        with pytest.raises(CqtError) as exc:
            algorithm_2_17(case["input"])
        assert exc.value.code == case["error"]


@pytest.mark.parametrize(
    "control",
    [
        "\u061c",
        "\u200e",
        "\u200f",
        "\u202a",
        "\u202b",
        "\u202c",
        "\u202d",
        "\u202e",
        "\u2066",
        "\u2067",
        "\u2068",
        "\u2069",
    ],
)
def test_every_unicode_17_bidi_control_is_rejected(control):
    with pytest.raises(CqtError) as exc:
        algorithm_2_17(f"left{control}right")
    assert exc.value.code == "disallowed-bidi-control"


def test_non_scalar_input_is_rejected():
    with pytest.raises(CqtError) as exc:
        algorithm_2_17("left\ud800right")
    assert exc.value.code == "invalid-unicode-scalar"


def test_non_string_input_is_rejected():
    with pytest.raises(TypeError):
        algorithm_2_17(b"not text")


def test_explicit_dash_set_is_complete_for_unicode_17():
    actual = {chr(codepoint) for codepoint in range(0x110000) if unicodedata.category(chr(codepoint)) == "Pd"}
    assert DASH_PUNCTUATION == actual


def test_unmatched_backtick_run_scanning_is_not_quadratic():
    # An unmatched run used to be re-entered one character at a time, so each of
    # its n positions rescanned the tail for a shorter closer. 12,800 backticks
    # took about 7 seconds. The bound here is loose enough not to be flaky on a
    # loaded machine and still far below the old cost, which would be minutes at
    # this size.
    plaintext = "a" + "`" * 50_000
    start = time.perf_counter()
    algorithm_2_17(plaintext)
    assert time.perf_counter() - start < 5.0


def test_unmatched_backtick_run_is_wholly_prose():
    # No proper suffix of an unmatched run may pair with a later run and protect
    # the whitespace between them.
    assert algorithm_2_17("a  ```  ``") == b"a ``` ``"


def test_recognition_must_agree_between_passes():
    # Removing an invisible makes the second pass see a URL the first pass did
    # not protect, while the bytes themselves have already settled.
    for invisible in ("\u200b", "\u00ad", "\u2060", "\ufeff"):
        with pytest.raises(CqtError) as exc:
            algorithm_2_17(f"http{invisible}://example.test/a--b")
        assert exc.value.code == "unstable-protected-syntax"


@pytest.mark.parametrize(
    "plaintext",
    [
        "see https://example.test/a , then",   # ordinary English
        "see https://example.test/a .",
        "voir https://example.test/a !",       # French requires the space
        "voir https://example.test/a ?",
        "voir https://example.test/a : suite",
        "voir https://example.test/a !",  # ... often a NO-BREAK SPACE
        "राम https://example.test/a ।",  # Devanagari danda
        "https://example.test/a ، b",     # Arabic comma
        "https://example.test/a 。",       # CJK full stop
    ],
)
def test_span_may_grow_during_punctuation_rules(plaintext):
    # Removing a space next to punctuation legitimately extends a URL span on the
    # second pass. Nothing inside the link is altered, so this must keep working:
    # the stability test looks only at what steps 1 and 2 create.
    algorithm_2_17(plaintext)


@pytest.mark.parametrize(
    "plaintext",
    [
        "x ｀a  b｀ y",                  # NFKC turns U+FF40 into a backtick
        "｀｀｀\ntext\n｀｀｀",
        "https：／／example.test/a--b",  # ... and fullwidth colon/solidus
        "\U0001d489ttps://example.test/a--b",    # ... and a mathematical letter
    ],
)
def test_normalization_may_not_create_protected_content(plaintext):
    with pytest.raises(CqtError) as exc:
        algorithm_2_17(plaintext)
    assert exc.value.code == "unstable-protected-syntax"


def test_url_scheme_case_insensitivity_is_ascii_only():
    # U+017F folds to "s" only under Unicode case folding; RFC 3986 schemes are
    # ASCII. NFKC then creates the scheme the first pass did not see.
    with pytest.raises(CqtError) as exc:
        algorithm_2_17("http\u017f://example.test/a--b")
    assert exc.value.code == "unstable-protected-syntax"
    assert algorithm_2_17("HtTpS://example.test/a--b") == b"HtTpS://example.test/a--b"


def test_many_protected_spans_restore_in_order():
    urls = [f"https://example.test/{i}--value?a=1&b=2" for i in range(1000)]
    plaintext = " ".join(urls)
    assert algorithm_2_17(plaintext) == plaintext.encode("utf-8")


@pytest.mark.parametrize("case", load_goldens()["cases"], ids=lambda case: case["id"])
def test_successful_goldens_are_idempotent(case):
    if "output" not in case:
        pytest.skip("error vector")
    once = algorithm_2_17(case["input"])
    twice = algorithm_2_17(once.decode("utf-8"))
    assert twice == once


def test_terminal_punctuation_set_matches_unicode_17():
    # ASCII members are the whole reason this property was chosen over Po: it
    # excludes the solidus and the apostrophe.
    assert {c for c in TERMINAL_PUNCTUATION if ord(c) < 128} == set("!,.:;?")
    assert "/" not in TERMINAL_PUNCTUATION
    assert "'" not in TERMINAL_PUNCTUATION
    assert len(TERMINAL_PUNCTUATION) == 291


def test_spaceless_scripts_set_matches_unicode_17():
    assert len(SPACELESS_SCRIPTS) == 757
    for char in "กກကក":  # Thai, Lao, Myanmar, Khmer
        assert char in SPACELESS_SCRIPTS
    for char in "A一कا":       # Latin, CJK, Devanagari, Arabic
        assert char not in SPACELESS_SCRIPTS


def test_emoticon_convergence_is_why_the_spacing_rule_exists():
    # Every spelling must land on the same bytes, with and without the space.
    forms = ["hello \U0001f60a", "hello :)", "hello :-)", "hello\U0001f60a"]
    assert len({algorithm_2_17(f) for f in forms}) == 1
