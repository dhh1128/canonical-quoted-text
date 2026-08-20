import json
from pathlib import Path

import pytest

import unicodedata2 as unicodedata

from cqt import CqtError, DASH_PUNCTUATION, algorithm_2_17


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
