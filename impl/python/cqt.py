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


def _codepoints(*ranges: str) -> frozenset[str]:
    """Expand "0E01-0E3A"-style ranges into a set of scalars."""
    out: set[str] = set()
    for item in ranges:
        first, _, last = item.partition("-")
        for codepoint in range(int(first, 16), int(last or first, 16) + 1):
            out.add(chr(codepoint))
    return frozenset(out)


# Unicode 17.0.0 Terminal_Punctuation, from PropList.txt. Punctuation that ends
# a sentence, clause or word, and so attaches to the text on its LEFT. The ASCII
# members are exactly ! , . : ; ? -- deliberately NOT the whole Po category,
# which would drag in the solidus and turn "A & B / C" into "A & B/ C", nor the
# apostrophe, which step 4 has already made ambiguous by folding every quote
# character onto it.
TERMINAL_PUNCTUATION = _codepoints(
    "0021", "002C", "002E", "003A-003B", "003F", "037E", "0387", "0589", "05C3",
    "060C", "061B", "061D-061F", "06D4", "0700-070A", "070C", "07F8-07F9",
    "0830-0835", "0837-083E", "085E", "0964-0965", "0E5A-0E5B", "0F08",
    "0F0D-0F12", "104A-104B", "1361-1368", "166E", "16EB-16ED", "1735-1736",
    "17D4-17D6", "17DA", "1802-1805", "1808-1809", "1944-1945", "1AA8-1AAB",
    "1B4E-1B4F", "1B5A-1B5B", "1B5D-1B5F", "1B7D-1B7F", "1C3B-1C3F", "1C7E-1C7F",
    "2024", "203C-203D", "2047-2049", "2CF9-2CFB", "2E2E", "2E3C", "2E41", "2E4C",
    "2E4E-2E4F", "2E53-2E54", "3001-3002", "A4FE-A4FF", "A60D-A60F", "A6F3-A6F7",
    "A876-A877", "A8CE-A8CF", "A92F", "A9C7-A9C9", "AA5D-AA5F", "AADF",
    "AAF0-AAF1", "ABEB", "FE12", "FE15-FE16", "FE50-FE52", "FE54-FE57", "FF01",
    "FF0C", "FF0E", "FF1A-FF1B", "FF1F", "FF61", "FF64", "1039F", "103D0", "10857",
    "1091F", "10A56-10A57", "10AF0-10AF5", "10B3A-10B3F", "10B99-10B9C",
    "10F55-10F59", "10F86-10F89", "11047-1104D", "110BE-110C1", "11141-11143",
    "111C5-111C6", "111CD", "111DE-111DF", "11238-1123C", "112A9", "113D4-113D5",
    "1144B-1144D", "1145A-1145B", "115C2-115C5", "115C9-115D7", "11641-11642",
    "1173C-1173E", "11944", "11946", "11A42-11A43", "11A9B-11A9C", "11AA1-11AA2",
    "11C41-11C43", "11C71", "11EF7-11EF8", "11F43-11F44", "12470-12474",
    "16A6E-16A6F", "16AF5", "16B37-16B39", "16B44", "16D6E-16D6F", "16E97-16E98",
    "1BC9F", "1DA87-1DA8A",
)

# Unicode 17.0.0 Line_Break=SA, from LineBreak.txt: the scripts that do not
# separate words with spaces and therefore need explicit break opportunities --
# Thai, Lao, Khmer, Myanmar, Tai Tham, New Tai Lue, Ahom. In these scripts
# U+200B is a real word separator rather than a layout artifact.
SPACELESS_SCRIPTS = _codepoints(
    "0E01-0E3A", "0E40-0E4E", "0E81-0E82", "0E84", "0E86-0E8A", "0E8C-0EA3",
    "0EA5", "0EA7-0EBD", "0EC0-0EC4", "0EC6", "0EC8-0ECE", "0EDC-0EDF",
    "1000-103F", "1050-108F", "109A-109F", "1780-17D3", "17D7", "17DC-17DD",
    "1950-196D", "1970-1974", "1980-19AB", "19B0-19C9", "19DE-19DF", "1A20-1A5E",
    "1A60-1A7C", "1AA0-1AAD", "A9E0-A9EF", "A9FA-A9FE", "AA60-AAC2", "AADB-AADF",
    "11700-1171A", "1171D-1172B", "1173A-1173B", "1173F-11746",
)

QUOTE_CHARACTERS = frozenset(
    "\u0022\u2018\u2019\u201c\u201d\u00ab\u00bb\u2039\u203a"
    "\u3008\u3009\u300a\u300b\u300c\u300d"
)

_AUTOCORRECT_BASE = (
    ("\U0001f60a", ":-)"),
    ("\U0001f610", ":-|"),
    ("\u2639", ":-("),
    ("\U0001f603", ":-D"),
    ("\U0001f61d", ":-p"),
    ("\U0001f632", ":-o"),
    ("\U0001f609", ";-)"),
    ("\u2764", "<3"),
    ("\U0001f494", "</3"),
    ("\u00a9", "(c)"),
    ("\u00ae", "(R)"),
    ("\u2022", "*"),
)

# A trailing variation selector belongs to the character it follows, for every
# entry rather than the two that happened to be spelled out. U+FE0F asks for the
# emoji rendering and U+FE0E for the text rendering; neither changes what the
# character is, and pickers and keyboards add them without the user knowing. So
# all three spellings of one character have to converge, which is the whole
# point of this step. Longest source first, so a selector form is always tried
# before the bare one.
AUTOCORRECT_PAIRS = tuple(
    pair
    for source, target in _AUTOCORRECT_BASE
    for pair in (
        (source + "\ufe0f", target),
        (source + "\ufe0e", target),
        (source, target),
    )
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
# re.ASCII is load-bearing. Without it, IGNORECASE on a str pattern applies full
# Unicode case folding, so U+017F LATIN SMALL LETTER LONG S matches the "s" of
# "https" and "httpſ://..." is protected as a URL. RFC 3986 section 3.1 restricts
# a scheme to ASCII ALPHA, so that match is simply wrong.
_URL_START = re.compile(r"https?://", re.IGNORECASE | re.ASCII)
_MULTI_HYPHEN = re.compile(r"-{2,}")
_LONG_DOTS = re.compile(r"\.{4,}")
_SPACES = re.compile(r" +")
# The marker is built from NUL deliberately. Step 2 strips every Cc scalar from
# the input BEFORE protection runs, so the text cannot contain one, and a marker
# therefore cannot be forged. A marker made of noncharacters could be: an input
# holding U+FDD0 CQT0 U+FDEF used to have span 0's content substituted into it.
_MARKER_OPEN = "\x00"
_MARKER_CLOSE = "\x00"
_PROTECTED_MARKER = re.compile(r"\x00CQT[0-9]+\x00")


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
            # No closing line, so the pattern is not present. A run of backticks
            # in prose is prose. Failing to match is not an error; human text
            # has no syntax to get wrong.
            i += 1
            continue

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
        # The Cc test is unreachable defence in depth: validation has already
        # rejected every Cc scalar that is not White_Space, and the White_Space
        # ones terminate on the first test. Kept so a reordering of the passes
        # cannot silently swallow a control character into a URL.
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
            # An unmatched run is ordinary prose in its entirety, so resume AFTER
            # it. Advancing one character would re-examine a proper suffix of the
            # run as a shorter run, which can pair with a later run and protect
            # text the prose rules should have normalized. It also made scanning
            # quadratic, since every position in a long run rescanned the tail.
            i = run_end
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
        marker = f"{_MARKER_OPEN}CQT{marker_number}{_MARKER_CLOSE}"
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


def _strip_disallowed(text: str) -> str:
    """Remove what cannot belong to plain text.

    Three groups, all of them artifacts rather than writing. Control characters
    outside the White_Space set -- NUL and its neighbours -- are not plain text.
    Unpaired surrogates are not Unicode scalar values at all and have no UTF-8
    encoding; a well-formed pair is a character and is left alone. And the two
    directional overrides, LRO and RLO, force every character in their scope to
    render in a given direction regardless of what the character is, so Latin
    letters display reversed. That is an instruction to a rendering engine, not
    a statement about the text, and it is the primitive behind bidi spoofing.

    The other bidi controls stay. Marks (ALM, LRM, RLM) only affect how
    neighbouring neutral characters resolve, and isolates (LRI, RLI, FSI, PDI)
    scope a direction without overriding anything, so both are ordinary parts
    of correct Arabic and Hebrew text.
    """
    out: list[str] = []
    index = 0
    while index < len(text):
        char = text[index]
        codepoint = ord(char)
        if 0xD800 <= codepoint <= 0xDBFF:
            following = text[index + 1] if index + 1 < len(text) else ""
            if following and 0xDC00 <= ord(following) <= 0xDFFF:
                # A well-formed pair is one astral character, not two errors.
                out.append(chr(0x10000 + ((codepoint - 0xD800) << 10) + (ord(following) - 0xDC00)))
                index += 2
                continue
            index += 1
            continue
        if 0xDC00 <= codepoint <= 0xDFFF:
            index += 1
            continue
        if unicodedata.category(char) == "Cc" and char not in WHITE_SPACE:
            index += 1
            continue
        if unicodedata.bidirectional(char) in ("LRO", "RLO"):
            index += 1
            continue
        out.append(char)
        index += 1
    return "".join(out)


def _remove_invisibles(text: str) -> str:
    """Step 5: drop the four layout-only characters.

    U+200B survives between two scalars from a script that does not separate
    words with spaces, where it is the word separator rather than an artifact.
    Both neighbours must qualify, so a stray U+200B injected at a script
    boundary by a mailer or sanitizer is still removed.
    """
    out: list[str] = []
    for index, char in enumerate(text):
        if char not in REMOVED_INVISIBLES:
            out.append(char)
            continue
        if char == "​":
            before = text[index - 1] if index else None
            after = text[index + 1] if index + 1 < len(text) else None
            if before in SPACELESS_SCRIPTS and after in SPACELESS_SCRIPTS:
                out.append(char)
    return "".join(out)


def _remove_spaces_adjacent_to_punctuation(text: str) -> str:
    """Step 7.9: attach punctuation to the side it belongs to.

    Punctuation is not symmetric. Opening punctuation binds to what follows it
    and closing, final and terminal punctuation bind to what precedes, so a
    space is removed on the side the punctuation attaches to and left alone on
    the other. That keeps "ignorance, up" and "name: value" intact while still
    converging "hello :)" and "hello \U0001f60a" on "hello:-)", which is what
    this rule exists to do.
    """
    out: list[str] = []
    cursor = 0
    for match in _SPACES.finditer(text):
        out.append(text[cursor : match.start()])
        before = text[match.start() - 1] if match.start() else None
        after = text[match.end()] if match.end() < len(text) else None
        attaches_left = after is not None and (
            after in TERMINAL_PUNCTUATION
            or unicodedata.category(after) in ("Pe", "Pf")
        )
        attaches_right = before is not None and unicodedata.category(before) in (
            "Ps",
            "Pi",
        )
        if not (attaches_left or attaches_right):
            out.append(" ")
        cursor = match.end()
    out.append(text[cursor:])
    return "".join(out)


def _canonicalize_prose(text: str) -> str:
    """One pass, in order. Nothing here runs twice.

    The autocorrect tables run before space removal. A client that swaps an
    emoji for its emoticon spelling, or the reverse, is exactly the kind of
    tooling transformation CQT exists to survive, so "hello <emoji>",
    "hello :)" and "hello :-)" must all reach the same bytes. Mapping to the
    canonical spelling first puts a colon where the space rule can see it.

    The cost of a single pass is that ": )" ends at ":)" rather than ":-)",
    since nothing revisits the tables after the space closes the gap. That is
    an oddity somebody typed, not something a tool did to their text.
    """
    text = unicodedata.normalize("NFKC", text)
    text = _remove_invisibles(text)
    text = _collapse_unicode_whitespace(text)
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
    text = text.replace("&", " & ")
    return _collapse_unicode_whitespace(text)


def algorithm_2_17(plaintext: str) -> bytes:
    """Return the CQT 2.17 canonical UTF-8 byte stream for ``plaintext``."""

    if not isinstance(plaintext, str):
        raise TypeError("plaintext must be str")
    # Strip what cannot be plain text BEFORE recognizing anything. Otherwise an
    # override hidden inside a fence or a URL is copied through untouched, and
    # the span becomes a channel for exactly the spoof this removal prevents.
    plaintext = _strip_disallowed(plaintext)
    text, protected = _protect(plaintext)
    text = _canonicalize_prose(text)
    text = _PROTECTED_MARKER.sub(lambda match: protected.get(match.group(), match.group()), text)
    return text.encode("utf-8")


__all__ = ["UNICODE_VERSION", "algorithm_2_17"]
