import json
import re
import time
from pathlib import Path

import pytest

import unicodedata2 as unicodedata

from cqt import (
    SPACELESS_SCRIPTS,
    TERMINAL_PUNCTUATION,
    DASH_PUNCTUATION,
    algorithm_2_17,
)


GOLDENS_PATH = Path(__file__).resolve().parents[2] / "goldens" / "cqt2.17.json"
README_PATH = Path(__file__).resolve().parents[2] / "README.md"

# The three worked examples in README.md are also vectors, so the most visible
# outputs in the specification cannot drift from what the algorithm does. This
# test pins the prose to the vector; test_normative_golden pins the vector to
# the implementation. form.html is held in place the same way, by
# impl/js/demo-page-check.mjs.
WORKED_EXAMPLE_IDS = [
    "worked-example-typography",
    "worked-example-fences",
    "worked-example-invisibles",
]


def load_goldens():
    return json.loads(GOLDENS_PATH.read_text(encoding="utf-8"))


def test_golden_manifest():
    manifest = load_goldens()
    assert manifest["algorithm"] == "cqt2.17"
    assert manifest["unicode_version"] == "17.0.0"
    ids = [case["id"] for case in manifest["cases"]]
    assert len(ids) == len(set(ids))
    # Inputs must be unique too. Two ids for one input is a vector that looks
    # like coverage and is not.
    inputs = [case["input"] for case in manifest["cases"]]
    assert len(inputs) == len(set(inputs))
    # CQT is total: every vector has an output and none has an error.
    assert all("output" in case and "error" not in case for case in manifest["cases"])


def _as_written_in_the_readme(text):
    # A character that cannot be seen is written as its codepoint in angle
    # brackets, which is the notation the third worked example documents. Line
    # endings are excluded, since the second example shows them as themselves.
    return "".join(
        "<%04X>" % ord(char)
        if unicodedata.category(char) in ("Cc", "Cf") and not char.isspace()
        else char
        for char in text
    )


def _worked_example_blocks():
    section = README_PATH.read_text(encoding="utf-8")
    section = section.split("\n## Worked examples\n", 1)[1].split("\n## ", 1)[0]
    lines = section.split("\n")
    blocks, i = [], 0
    while i < len(lines):
        # Fences here vary in length: the example that contains a fenced block
        # is itself shown inside a longer one. A table row may open with an
        # inline code span, so an opener has to be a whole line of backticks
        # and an optional info string.
        run = re.fullmatch("(`{3,})[^`]*", lines[i])
        if run:
            close = lines.index(run.group(1), i + 1)
            blocks.append("\n".join(lines[i + 1 : close]))
            i = close + 1
        else:
            i += 1
    return blocks


def test_worked_examples_are_the_vectors_they_claim_to_be():
    cases = {case["id"]: case for case in load_goldens()["cases"]}
    blocks = _worked_example_blocks()
    assert len(blocks) == 2 * len(WORKED_EXAMPLE_IDS)
    for n, case_id in enumerate(WORKED_EXAMPLE_IDS):
        case = cases[case_id]
        assert blocks[2 * n] == _as_written_in_the_readme(case["input"]), case_id
        assert blocks[2 * n + 1] == _as_written_in_the_readme(case["output"]), case_id


@pytest.mark.parametrize("case", load_goldens()["cases"], ids=lambda case: case["id"])
def test_normative_golden(case):
    assert algorithm_2_17(case["input"]) == case["output"].encode("utf-8")


def test_many_protected_spans_restore_in_order():
    urls = [f"https://example.test/{i}--value?a=1&b=2" for i in range(1000)]
    plaintext = " ".join(urls)
    assert algorithm_2_17(plaintext) == plaintext.encode("utf-8")


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


def test_emoji_and_emoticon_spellings_converge():
    # A client swapping an emoji for its emoticon spelling is a tooling
    # transformation, so every spelling must reach the same bytes. This is why
    # the autocorrect tables run before the space rule rather than after.
    forms = ["hello \U0001f60a", "hello :)", "hello :-)", "hello:)", "hello\U0001f60a"]
    assert len({algorithm_2_17(f) for f in forms}) == 1


def test_cqt_is_total():
    # No input is refused. Unpaired surrogates are stripped as part of making
    # the input plain text; a well-formed pair is the character it encodes.
    assert algorithm_2_17("left\ud800right") == b"leftright"
    assert algorithm_2_17("left\udc00right") == b"leftright"
    assert algorithm_2_17("a\ud83d\ude0ab") == algorithm_2_17("a\U0001f60ab")


@pytest.mark.parametrize(
    "plaintext",
    ["```", "before\n```py\nprint('x')", "｀｀｀", "I typed ``` by accident", "a͸b", "a﷐b"],
)
def test_human_text_has_no_syntax_errors(plaintext):
    algorithm_2_17(plaintext)


def test_overrides_are_stripped_and_other_bidi_controls_are_kept():
    assert algorithm_2_17("file‮gnp.exe") == "filegnp.exe".encode("utf-8")
    assert algorithm_2_17("a‭b") == b"ab"
    for keep in ("؜", "‎", "‏", "⁦", "⁧", "⁨", "⁩"):
        assert keep in algorithm_2_17(f"ا{keep}b").decode("utf-8")


def test_control_characters_are_stripped_not_refused():
    assert algorithm_2_17("before\x00after") == b"beforeafter"


def test_unclosed_fence_is_prose_and_closed_fence_is_exact():
    assert algorithm_2_17("before\n```py\nx  y") == b"before ```py x y"
    exact = "a\n```\nx  y\n```\nb"
    assert algorithm_2_17(exact) == exact.encode("utf-8")


def test_prose_is_transformed_in_one_pass():
    # Space removal precedes the autocorrect tables, as in 1.14, so ": )"
    # reaches ":-)" without iterating.
    # One pass, so nothing revisits the tables after the space closes: ": )"
    # ends at ":)". That is an authored oddity, not a tooling artifact.
    assert algorithm_2_17(": )") == b":)"
    assert algorithm_2_17("hello :)") == b"hello:-)"
    assert algorithm_2_17("hello \U0001f60a") == b"hello:-)"
