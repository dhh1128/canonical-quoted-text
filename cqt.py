"""Reference implementation of Canonical Quoted Text 2.17."""

from __future__ import annotations

import re
from dataclasses import dataclass

import unicodedata2 as unicodedata


UNICODE_VERSION = "17.0.0"

if unicodedata.unidata_version != UNICODE_VERSION:
    raise RuntimeError(
        f"cqt2.17 requires Unicode {UNICODE_VERSION}, "
        f"but unicodedata2 provides {unicodedata.unidata_version}"
    )


class CqtError(ValueError):
    """A deterministic rejection required by the CQT 2.17 specification."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class _Span:
    start: int
    end: int


BIDI_CONTROLS = frozenset(
    "\u061c\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069"
)
REMOVED_INVISIBLES = frozenset("\u00ad\u200b\u2060\ufeff")
WHITE_SPACE = frozenset(
    "\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680"
    "\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a"
    "\u2028\u2029\u202f\u205f\u3000"
)
DASH_PUNCTUATION = frozenset(
    "\u002d\u058a\u05be\u1400\u1806\u2010\u2011\u2012\u2013\u2014\u2015"
    "\u2e17\u2e1a\u2e3a\u2e3b\u2e40\u2e5d\u301c\u3030\u30a0"
    "\ufe31\ufe32\ufe58\ufe63\uff0d\U00010d6e\U00010ead"
)
QUOTE_CHARACTERS = frozenset(
    "\u0022\u2018\u2019\u201c\u201d\u00ab\u00bb\u2039\u203a"
    "\u3008\u3009\u300a\u300b\u300c\u300d"
)

AUTOCORRECT_PAIRS = (
    ("\U0001f60a", ":-)"),
    ("\U0001f610", ":-|"),
    ("\u2639\ufe0f", ":-("),
    ("\u2639", ":-("),
    ("\U0001f603", ":-D"),
    ("\U0001f61d", ":-p"),
    ("\U0001f632", ":-o"),
    ("\U0001f609", ";-)"),
    ("\u2764\ufe0f", "<3"),
    ("\u2764", "<3"),
    ("\U0001f494", "</3"),
    ("\u00a9", "(c)"),
    ("\u00ae", "(R)"),
    ("\u2022", "*"),
)
ASCII_AUTOCORRECT_PAIRS = (
    (":)", ":-)"),
    (":|", ":-|"),
    (":(", ":-("),
    (":D", ":-D"),
    (":p", ":-p"),
    (":o", ":-o"),
    (";)", ";-)"),
)

_FENCE_OPEN = re.compile(r"^ {0,3}(`{3,})([^`\r\n]*)$")
_URL_START = re.compile(r"https?://", re.IGNORECASE)
_MULTI_HYPHEN = re.compile(r"-{2,}")
_LONG_DOTS = re.compile(r"\.{4,}")
_SPACES = re.compile(r" +")
_PROTECTED_MARKER = re.compile(r"\ufdd0CQT[0-9]+\ufdef")


def _line_body(line: str) -> str:
    if line.endswith("\r\n"):
        return line[:-2]
    if line.endswith(("\r", "\n")):
        return line[:-1]
    return line


def _lines_with_endings(text: str) -> list[str]:
    lines: list[str] = []
    start = 0
    i = 0
    while i < len(text):
        if text[i] == "\r":
            i += 2 if i + 1 < len(text) and text[i + 1] == "\n" else 1
            lines.append(text[start:i])
            start = i
        elif text[i] == "\n":
            i += 1
            lines.append(text[start:i])
            start = i
        else:
            i += 1
    if start < len(text):
        lines.append(text[start:])
    return lines


def _fenced_spans(text: str) -> list[_Span]:
    lines = _lines_with_endings(text)
    spans: list[_Span] = []
    offsets: list[int] = []
    offset = 0
    for line in lines:
        offsets.append(offset)
        offset += len(line)

    i = 0
    while i < len(lines):
        opening = _FENCE_OPEN.fullmatch(_line_body(lines[i]))
        if not opening:
            i += 1
            continue

        fence_length = len(opening.group(1))
        closing = re.compile(rf"^ {{0,3}}`{{{fence_length},}}[ \t]*$")
        j = i + 1
        while j < len(lines) and not closing.fullmatch(_line_body(lines[j])):
            j += 1
        if j == len(lines):
            raise CqtError("unclosed-fence", "opening backtick fence has no closing fence")

        start = offsets[i]
        if start >= 2 and text[start - 2 : start] == "\r\n":
            start -= 2
        elif start and text[start - 1] in "\r\n":
            start -= 1
        if spans:
            start = max(start, spans[-1].end)
        end = offsets[j] + len(lines[j])
        spans.append(_Span(start, end))
        i = j + 1
    return spans


def _matching_backtick_run(text: str, start: int, limit: int, length: int) -> int | None:
    needle = "`" * length
    candidate = text.find(needle, start, limit)
    while candidate != -1:
        before_is_tick = candidate > start and text[candidate - 1] == "`"
        after = candidate + length
        after_is_tick = after < limit and text[after] == "`"
        if not before_is_tick and not after_is_tick:
            return candidate
        candidate = text.find(needle, candidate + length, limit)
    return None


def _url_end(text: str, start: int, limit: int) -> int:
    i = start
    paren_depth = 0
    while i < limit:
        char = text[i]
        if char in WHITE_SPACE or char in '<>"`' or unicodedata.category(char) == "Cc":
            break
        if char == "(":
            paren_depth += 1
        elif char == ")":
            if paren_depth == 0:
                break
            paren_depth -= 1
        i += 1
    return i


def _inline_and_url_spans(text: str, start: int, end: int) -> list[_Span]:
    spans: list[_Span] = []
    i = start
    while i < end:
        if text[i] == "`":
            run_end = i + 1
            while run_end < end and text[run_end] == "`":
                run_end += 1
            run_length = run_end - i
            closing = _matching_backtick_run(text, run_end, end, run_length)
            if closing is not None:
                span_end = closing + run_length
                spans.append(_Span(i, span_end))
                i = span_end
                continue

        url = _URL_START.match(text, i, end)
        if url:
            span_end = _url_end(text, url.end(), end)
            spans.append(_Span(i, span_end))
            i = span_end
            continue
        i += 1
    return spans


def _opaque_spans(text: str) -> list[_Span]:
    fences = _fenced_spans(text)
    spans: list[_Span] = []
    cursor = 0
    for fence in fences:
        spans.extend(_inline_and_url_spans(text, cursor, fence.start))
        spans.append(fence)
        cursor = fence.end
    spans.extend(_inline_and_url_spans(text, cursor, len(text)))
    return spans


def _protect(text: str) -> tuple[str, dict[str, str]]:
    spans = _opaque_spans(text)
    if not spans:
        return text, {}

    parts: list[str] = []
    protected: dict[str, str] = {}
    cursor = 0
    for marker_number, span in enumerate(spans):
        marker = f"\ufdd0CQT{marker_number}\ufdef"
        parts.append(text[cursor : span.start])
        parts.append(marker)
        protected[marker] = text[span.start : span.end]
        cursor = span.end
    parts.append(text[cursor:])
    return "".join(parts), protected


def _collapse_unicode_whitespace(text: str) -> str:
    out: list[str] = []
    in_whitespace = False
    for char in text:
        if char in WHITE_SPACE:
            if not in_whitespace:
                out.append(" ")
            in_whitespace = True
        else:
            out.append(char)
            in_whitespace = False
    return "".join(out).strip(" ")


def _remove_spaces_adjacent_to_punctuation(text: str) -> str:
    out: list[str] = []
    cursor = 0
    for match in _SPACES.finditer(text):
        out.append(text[cursor : match.start()])
        before = text[match.start() - 1] if match.start() else None
        after = text[match.end()] if match.end() < len(text) else None
        adjacent = (
            (before is not None and unicodedata.category(before).startswith("P"))
            or (after is not None and unicodedata.category(after).startswith("P"))
        )
        if not adjacent:
            out.append(" ")
        cursor = match.end()
    out.append(text[cursor:])
    return "".join(out)


def _canonicalize_prose(text: str) -> str:
    text = unicodedata.normalize("NFKC", text)
    text = "".join(char for char in text if char not in REMOVED_INVISIBLES)
    text = _collapse_unicode_whitespace(text)
    while True:
        previous = text
        text = "".join("-" if char in DASH_PUNCTUATION else char for char in text)
        text = _MULTI_HYPHEN.sub("-", text)
        text = text.replace("\u3001", ",").replace("\u3002", ".")
        text = text.replace("\u2026", "...")
        text = _LONG_DOTS.sub("...", text)
        text = text.replace("\u2044", "/")
        text = "".join("'" if char in QUOTE_CHARACTERS else char for char in text)
        for source, target in AUTOCORRECT_PAIRS:
            text = text.replace(source, target)
        for source, target in ASCII_AUTOCORRECT_PAIRS:
            text = text.replace(source, target)
        text = _remove_spaces_adjacent_to_punctuation(text)
        if text == previous:
            break
    text = text.replace("&", " & ")
    return _collapse_unicode_whitespace(text)


def _validate(plaintext: str) -> None:
    for char in plaintext:
        codepoint = ord(char)
        if 0xD800 <= codepoint <= 0xDFFF:
            raise CqtError("invalid-unicode-scalar", "input contains an isolated surrogate")
        category = unicodedata.category(char)
        if category == "Cn":
            raise CqtError(
                "unassigned-code-point",
                f"U+{codepoint:04X} is unassigned in Unicode {UNICODE_VERSION}",
            )
        if char in BIDI_CONTROLS:
            raise CqtError(
                "disallowed-bidi-control",
                f"input contains bidi control U+{codepoint:04X}",
            )
        if category == "Cc" and char not in WHITE_SPACE:
            raise CqtError(
                "disallowed-control",
                f"input contains control character U+{codepoint:04X}",
            )


def _canonicalize_once(plaintext: str) -> str:
    text, protected = _protect(plaintext)
    text = _canonicalize_prose(text)
    return _PROTECTED_MARKER.sub(lambda match: protected[match.group()], text)


def algorithm_2_17(plaintext: str) -> bytes:
    """Return the CQT 2.17 canonical UTF-8 byte stream for ``plaintext``."""

    if not isinstance(plaintext, str):
        raise TypeError("plaintext must be str")
    _validate(plaintext)
    text = _canonicalize_once(plaintext)
    try:
        stable = _canonicalize_once(text)
    except CqtError as exc:
        raise CqtError(
            "unstable-protected-syntax",
            "normalization creates ambiguous protected-content syntax",
        ) from exc
    if stable != text:
        raise CqtError(
            "unstable-protected-syntax",
            "normalization changes protected-content parsing on a second pass",
        )
    return text.encode("utf-8")


__all__ = ["CqtError", "UNICODE_VERSION", "algorithm_2_17"]
