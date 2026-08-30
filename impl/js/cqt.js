/* Canonical Quoted Text 3.17 -- JavaScript port of the reference implementation.
 *
 * Loads as a classic browser script (defining a global `algorithm_3_17`) and as
 * a CommonJS module under Node. Run `node conformance.mjs` to check it against
 * the normative vectors in goldens/cqt3.17.json.
 *
 * Every invisible character is written as a \u{...} escape rather than a
 * literal, so that a tool which reflows or re-encodes this source cannot alter
 * the algorithm's behaviour without the change being visible in a diff.
 *
 * UTF-16 note. JavaScript strings are sequences of UTF-16 code units, but CQT is
 * defined on Unicode scalar values. Offsets below are code-unit offsets, which is
 * safe because every boundary this file computes falls between scalars: fences
 * split on ASCII line endings, backtick runs and URL schemes are ASCII, and the
 * URL terminator set is ASCII plus BMP whitespace. Wherever a *character* is
 * examined rather than an offset -- the neighbours of U+200B, the characters on
 * either side of a space run -- the code reads a whole code point, because
 * Terminal_Punctuation and Line_Break=SA both have astral members.
 */

/* The whole file is one IIFE so that form.html can load it with a plain
 * <script src="cqt.js"> without the helpers below landing on `window`, where
 * names like `protect` and `canonicalize` would collide with other scripts on
 * the page. Only the public surface is published, at the bottom. The body is
 * left at file indentation, as UMD wrappers conventionally are. */
(function () {
'use strict';

var UNICODE_VERSION = '17.0.0';

/** Expand "0E01-0E3A"-style ranges into a Set of scalars. */
function codepoints(ranges) {
  var out = new Set();
  for (var i = 0; i < ranges.length; i += 1) {
    var item = ranges[i];
    var dash = item.indexOf('-');
    var first = dash === -1 ? item : item.slice(0, dash);
    var last = dash === -1 ? item : item.slice(dash + 1);
    for (var cp = parseInt(first, 16); cp <= parseInt(last, 16); cp += 1) {
      out.add(String.fromCodePoint(cp));
    }
  }
  return out;
}

var SOFT_HYPHEN = '\u{AD}';
var ZERO_WIDTH_SPACE = '\u{200B}';
var WORD_JOINER = '\u{2060}';
var ZERO_WIDTH_NO_BREAK_SPACE = '\u{FEFF}';

// Step 5.1: the three invisibles that are layout artifacts and carry no meaning.
// U+FEFF is NOT among them: it is a serialization artifact rather than a layout
// one, so step 2.4 removes it before anything is recognized, which is why it
// also comes out of a protected span.
var REMOVED_INVISIBLES = new Set([SOFT_HYPHEN, ZERO_WIDTH_SPACE, WORD_JOINER]);
var REMOVED_ARTIFACTS = new Set([ZERO_WIDTH_NO_BREAK_SPACE]);

// The Unicode 17 White_Space set, enumerated by the spec so no runtime property
// lookup is needed.
var WHITE_SPACE = codepoints([
  '0009-000D', '0020', '0085', '00A0', '1680', '2000-200A',
  '2028', '2029', '202F', '205F', '3000',
]);
// Step 2.5 folds all of these onto LF, so from step 3 onward LF is the only
// line terminator and "horizontal whitespace" is the rest of White_Space.
var LINE_TERMINATORS = codepoints(['000A-000D', '0085', '2028', '2029']);
var HWS_CLASS =
  '[\u{9}\u{B}-\u{D}\u{20}\u{85}\u{A0}\u{1680}\u{2000}-\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}]';
var LEAD_HWS_RE = new RegExp('^' + HWS_CLASS + '+');
var TRAILING_HWS_RE = new RegExp(HWS_CLASS + '+$');
var QUOTE_PREFIX_RE = new RegExp('^' + HWS_CLASS + '*>(?:' + HWS_CLASS + '|>)*');
var FOLD_NEWLINES_RE = new RegExp('\\n+' + HWS_CLASS + '*', 'g');
var MEDIA_TOKEN = "[A-Za-z0-9!#$%&'*+.^_`|~-]+";
var URL_AUTHORITY_RE = /^([A-Za-z][A-Za-z0-9+.-]*)(:\/\/)([^\/?#]*)([\s\S]*)$/i;
var URL_SCHEME_RE = /^([A-Za-z][A-Za-z0-9+.-]*)(:)([\s\S]*)$/i;
var DATA_URI_RE = new RegExp(
  '^(data):((?:' + MEDIA_TOKEN + '/' + MEDIA_TOKEN + ')?'
  + '(?:;' + MEDIA_TOKEN + '=' + MEDIA_TOKEN + ')*(?:;base64)?)(,[\\s\\S]*)$',
  'i');

var WHITESPACE_RUN_RE =
  /[\u{9}-\u{D}\u{20}\u{85}\u{A0}\u{1680}\u{2000}-\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}]+/gu;

// U+202D LEFT-TO-RIGHT OVERRIDE and U+202E RIGHT-TO-LEFT OVERRIDE. Every other
// bidi control describes the text rather than overriding it, and stays.
var DIRECTIONAL_OVERRIDES = new Set(['\u{202D}', '\u{202E}']);

// Unicode 17.0.0 Terminal_Punctuation, from PropList.txt. Punctuation that ends
// a sentence, clause or word, and so attaches to the text on its LEFT. The ASCII
// members are exactly ! , . : ; ? -- deliberately NOT the whole Po category,
// which would drag in the solidus and turn "A & B / C" into "A & B/ C", nor the
// apostrophe, which step 7.6 has already made ambiguous by folding every quote
// character onto it.
var TERMINAL_PUNCTUATION = codepoints([
  '0021', '002C', '002E', '003A-003B', '003F', '037E', '0387', '0589', '05C3',
  '060C', '061B', '061D-061F', '06D4', '0700-070A', '070C', '07F8-07F9',
  '0830-0835', '0837-083E', '085E', '0964-0965', '0E5A-0E5B', '0F08',
  '0F0D-0F12', '104A-104B', '1361-1368', '166E', '16EB-16ED', '1735-1736',
  '17D4-17D6', '17DA', '1802-1805', '1808-1809', '1944-1945', '1AA8-1AAB',
  '1B4E-1B4F', '1B5A-1B5B', '1B5D-1B5F', '1B7D-1B7F', '1C3B-1C3F', '1C7E-1C7F',
  '2024', '203C-203D', '2047-2049', '2CF9-2CFB', '2E2E', '2E3C', '2E41', '2E4C',
  '2E4E-2E4F', '2E53-2E54', '3001-3002', 'A4FE-A4FF', 'A60D-A60F', 'A6F3-A6F7',
  'A876-A877', 'A8CE-A8CF', 'A92F', 'A9C7-A9C9', 'AA5D-AA5F', 'AADF',
  'AAF0-AAF1', 'ABEB', 'FE12', 'FE15-FE16', 'FE50-FE52', 'FE54-FE57', 'FF01',
  'FF0C', 'FF0E', 'FF1A-FF1B', 'FF1F', 'FF61', 'FF64', '1039F', '103D0', '10857',
  '1091F', '10A56-10A57', '10AF0-10AF5', '10B3A-10B3F', '10B99-10B9C',
  '10F55-10F59', '10F86-10F89', '11047-1104D', '110BE-110C1', '11141-11143',
  '111C5-111C6', '111CD', '111DE-111DF', '11238-1123C', '112A9', '113D4-113D5',
  '1144B-1144D', '1145A-1145B', '115C2-115C5', '115C9-115D7', '11641-11642',
  '1173C-1173E', '11944', '11946', '11A42-11A43', '11A9B-11A9C', '11AA1-11AA2',
  '11C41-11C43', '11C71', '11EF7-11EF8', '11F43-11F44', '12470-12474',
  '16A6E-16A6F', '16AF5', '16B37-16B39', '16B44', '16D6E-16D6F', '16E97-16E98',
  '1BC9F', '1DA87-1DA8A',
]);

// Unicode 17.0.0 Line_Break=SA, from LineBreak.txt: the scripts that do not
// separate words with spaces and therefore need explicit break opportunities --
// Thai, Lao, Khmer, Myanmar, Tai Tham, New Tai Lue, Ahom. In these scripts
// U+200B is a real word separator rather than a layout artifact.
var SPACELESS_SCRIPTS = codepoints([
  '0E01-0E3A', '0E40-0E4E', '0E81-0E82', '0E84', '0E86-0E8A', '0E8C-0EA3',
  '0EA5', '0EA7-0EBD', '0EC0-0EC4', '0EC6', '0EC8-0ECE', '0EDC-0EDF',
  '1000-103F', '1050-108F', '109A-109F', '1780-17D3', '17D7', '17DC-17DD',
  '1950-196D', '1970-1974', '1980-19AB', '19B0-19C9', '19DE-19DF', '1A20-1A5E',
  '1A60-1A7C', '1AA0-1AAD', 'A9E0-A9EF', 'A9FA-A9FE', 'AA60-AAC2', 'AADB-AADF',
  '11700-1171A', '1171D-1172B', '1173A-1173B', '1173F-11746',
]);

// Unicode 17.0.0 Dash_Punctuation (Pd), enumerated by the spec. Two members are
// astral, hence the `u` flag.
var DASH_PUNCTUATION_RE =
  /[\u{2D}\u{58A}\u{5BE}\u{1400}\u{1806}\u{2010}-\u{2015}\u{2E17}\u{2E1A}\u{2E3A}\u{2E3B}\u{2E40}\u{2E5D}\u{301C}\u{3030}\u{30A0}\u{FE31}\u{FE32}\u{FE58}\u{FE63}\u{FF0D}\u{10D6E}\u{10EAD}]/gu;

// Step 7.6: the quote characters that all fold onto the ASCII apostrophe.
var QUOTE_CHARACTERS_RE =
  /[\u{22}\u{AB}\u{BB}\u{2018}\u{2019}\u{201C}\u{201D}\u{2039}\u{203A}\u{3008}-\u{300D}]/gu;

var IDEOGRAPHIC_COMMA = '\u{3001}';
var IDEOGRAPHIC_FULL_STOP = '\u{3002}';
var HORIZONTAL_ELLIPSIS = '\u{2026}';
var FRACTION_SLASH = '\u{2044}';
// U+FE0F asks for the emoji rendering, U+FE0E for the text rendering.
var EMOJI_PRESENTATION_SELECTOR = '\u{FE0F}';
var TEXT_PRESENTATION_SELECTOR = '\u{FE0E}';

// Step 7.7.
var AUTOCORRECT_BASE = [
  ['\u{1F60A}', ':-)'],
  ['\u{1F610}', ':-|'],
  ['\u{2639}', ':-('],
  ['\u{1F603}', ':-D'],
  ['\u{1F61D}', ':-p'],
  ['\u{1F632}', ':-o'],
  ['\u{1F609}', ';-)'],
  ['\u{2764}', '<3'],
  ['\u{1F494}', '</3'],
  ['\u{A9}', '(c)'],
  ['\u{AE}', '(R)'],
  ['\u{2022}', '*'],
];

// A trailing variation selector belongs to the character it follows, for every
// entry rather than the two that happened to be spelled out. U+FE0F asks for the
// emoji rendering and U+FE0E for the text rendering; neither changes what the
// character is, and pickers and keyboards add them without the user knowing. So
// all three spellings of one character have to converge, which is the whole
// point of this step. Longest source first, so a selector form is always tried
// before the bare one.
var AUTOCORRECT_PAIRS = [];
for (var autocorrectIndex = 0; autocorrectIndex < AUTOCORRECT_BASE.length; autocorrectIndex += 1) {
  var basePair = AUTOCORRECT_BASE[autocorrectIndex];
  AUTOCORRECT_PAIRS.push([basePair[0] + EMOJI_PRESENTATION_SELECTOR, basePair[1]]);
  AUTOCORRECT_PAIRS.push([basePair[0] + TEXT_PRESENTATION_SELECTOR, basePair[1]]);
  AUTOCORRECT_PAIRS.push([basePair[0], basePair[1]]);
}

// Step 7.8.
var ASCII_AUTOCORRECT_PAIRS = [
  [':)', ':-)'],
  [':|', ':-|'],
  [':(', ':-('],
  [';)', ';-)'],
];

// The three whose second character is a letter carry a trailing guard: they
// convert only when what follows is not an ASCII letter, digit, "-" or "_".
// Without it the table rewrites URI schemes -- "did:peer" became "did:-peer",
// "urn:oid" became "urn:-oid", and "did:keri:DKxy..." became "did:keri:-DKxy..."
// because a D-coded CESR key follows the colon. Trailing only; a leading guard
// would also stop converting "lol:p", which people type.
var GUARDED_EMOTICONS = [
  [/:D(?![A-Za-z0-9_-])/g, ':-D'],
  [/:p(?![A-Za-z0-9_-])/g, ':-p'],
  [/:o(?![A-Za-z0-9_-])/g, ':-o'],
];

// Any leading horizontal whitespace, not just 0-3 spaces. CommonMark needs
// that limit to separate a fence from an indented code block; CQT has no
// indented code blocks, so it only ever cost a fence transport had indented.
var FENCE_OPEN_RE = new RegExp('^' + HWS_CLASS + '*(`{3,})([^`\\n]*)$');

// The `i` flag WITHOUT `u` is load-bearing. RFC 3986 section 3.1 restricts a
// scheme to ASCII ALPHA, and JavaScript's non-unicode case-insensitive
// canonicalization refuses to fold a non-ASCII scalar onto an ASCII one -- so
// U+017F LATIN SMALL LETTER LONG S does not match the "s" of "https". Adding `u`
// would switch to simple case folding, U+017F would match, and "http<U+017F>://"
// would be protected as a URL when it is nothing of the kind. `y` (sticky) gives
// the anchored-at-a-position match this scan needs.
// Three forms of URI span. Any scheme followed by "://" is safe to recognize
// because "://" does not occur in prose; a BARE scheme is not, because "note:"
// and "here is the data:" are ordinary English. The two bare schemes here earn
// their place by carrying structure that tells them from a sentence: mailto:
// must reach an "@" before any whitespace, and data: must present a well-formed
// RFC 2397 header, ending in the mandatory comma. "data:abc,x" is prose.
var URL_START_RE = new RegExp(
  '[A-Za-z][A-Za-z0-9+.-]*://'
  + '|mailto:(?=[^\\s]*@)'
  + '|data:(?:' + MEDIA_TOKEN + '/' + MEDIA_TOKEN + ')?'
  + '(?:;' + MEDIA_TOKEN + '=' + MEDIA_TOKEN + ')*(?:;base64)?,',
  'iy');

var MULTI_HYPHEN_RE = /-{2,}/g;
var LONG_DOTS_RE = /\.{4,}/g;
var SPACE_RUN_RE = / +/g;
var TRIM_EDGES_RE = /^[ \n]+|[ \n]+$/g;

// The marker is built from NUL deliberately. Step 2 strips every Cc scalar from
// the input BEFORE protection runs, so the text cannot contain one, and a marker
// therefore cannot be forged. A marker made of noncharacters could be: an input
// holding U+FDD0 CQT0 U+FDEF used to have span 0's content substituted into it.
//
// NUL also survives steps 4 through 7 untouched, which is what makes it a legal
// placeholder: NFKC leaves it alone, it is not in the White_Space set that step
// 6.1 collapses, and it is neither Terminal_Punctuation nor Ps/Pi/Pe/Pf, so step
// 7.9 treats it as the non-punctuation the spec requires.
var MARKER_OPEN = '\u{0}';
var MARKER_CLOSE = '\u{0}';
var PROTECTED_MARKER_RE = /\u{0}CQT[0-9]+\u{0}/gu;

var CONTROL_RE = /^\p{Cc}$/u;
var CLOSING_OR_FINAL_RE = /^[\p{Pe}\p{Pf}]$/u;
var OPENING_OR_INITIAL_RE = /^[\p{Ps}\p{Pi}]$/u;

/* ------------------------------------------------------------------ *
 * Code-point-aware neighbour access.                                  *
 * ------------------------------------------------------------------ */

/** The whole code point that ends at code-unit `index`, or null. */
function codePointBefore(text, index) {
  if (index <= 0) return null;
  var unit = text.charCodeAt(index - 1);
  if (unit >= 0xdc00 && unit <= 0xdfff && index >= 2) {
    var lead = text.charCodeAt(index - 2);
    if (lead >= 0xd800 && lead <= 0xdbff) return text.slice(index - 2, index);
  }
  return text.charAt(index - 1);
}

/** The whole code point that starts at code-unit `index`, or null. */
function codePointAt(text, index) {
  if (index < 0 || index >= text.length) return null;
  return String.fromCodePoint(text.codePointAt(index));
}

/* ------------------------------------------------------------------ *
 * Step 2: finish making the text plain.                               *
 * ------------------------------------------------------------------ */

/* Remove what cannot belong to plain text.
 *
 * Three groups, all of them artifacts rather than writing. Control characters
 * outside the White_Space set -- NUL and its neighbours -- are not plain text.
 * Unpaired surrogates are not Unicode scalar values at all and have no UTF-8
 * encoding; a well-formed pair is a character and is left alone. And the two
 * directional overrides, LRO and RLO, force every character in their scope to
 * render in a given direction regardless of what the character is, so Latin
 * letters display reversed. That is an instruction to a rendering engine, not a
 * statement about the text, and it is the primitive behind bidi spoofing.
 *
 * The other bidi controls stay. Marks (ALM, LRM, RLM) only affect how
 * neighbouring neutral characters resolve, and isolates (LRI, RLI, FSI, PDI)
 * scope a direction without overriding anything, so both are ordinary parts of
 * correct Arabic and Hebrew text.
 */
function stripDisallowed(text) {
  var out = [];
  var index = 0;
  while (index < text.length) {
    var unit = text.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      var trail = index + 1 < text.length ? text.charCodeAt(index + 1) : 0;
      if (trail >= 0xdc00 && trail <= 0xdfff) {
        // A well-formed pair is one astral character, not two errors.
        out.push(text.slice(index, index + 2));
        index += 2;
        continue;
      }
      index += 1;
      continue;
    }
    if (unit >= 0xdc00 && unit <= 0xdfff) {
      index += 1;
      continue;
    }
    var char = text.charAt(index);
    index += 1;
    if (CONTROL_RE.test(char) && !WHITE_SPACE.has(char)) continue;
    if (DIRECTIONAL_OVERRIDES.has(char)) continue;
    out.push(char);
  }
  return out.join('');
}

/* ------------------------------------------------------------------ *
 * Step 3: recognize protected content.                                *
 * ------------------------------------------------------------------ */

function lineBody(line) {
  return line.endsWith('\n') ? line.slice(0, -1) : line;
}

/* Split on LF, which step 2.5 has made the only line terminator. */
function linesWithEndings(text) {
  var lines = [];
  var start = 0;
  for (var i = 0; i < text.length; i += 1) {
    if (text.charAt(i) === '\n') {
      lines.push(text.slice(start, i + 1));
      start = i + 1;
    }
  }
  if (start < text.length) lines.push(text.slice(start));
  return lines;
}

function fencedSpans(text) {
  var lines = linesWithEndings(text);
  var spans = [];
  var offsets = [];
  var offset = 0;
  for (var k = 0; k < lines.length; k += 1) {
    offsets.push(offset);
    offset += lines[k].length;
  }

  var i = 0;
  while (i < lines.length) {
    var opening = FENCE_OPEN_RE.exec(lineBody(lines[i]));
    if (!opening) {
      i += 1;
      continue;
    }

    var fenceLength = opening[1].length;
    var closing = new RegExp('^' + HWS_CLASS + '*`{' + fenceLength + ',}' + HWS_CLASS + '*$');
    var j = i + 1;
    while (j < lines.length && !closing.test(lineBody(lines[j]))) j += 1;

    var start = offsets[i];
    // Take the line ending that precedes the opening line, so the fence still
    // starts a line after the surrounding prose is flattened into spaces.
    if (start > 0 && text.charAt(start - 1) === '\n') start -= 1;
    if (spans.length) start = Math.max(start, spans[spans.length - 1].end);
    if (j === lines.length) {
      // An opener with no closer runs to the end of the input rather than
      // decaying into prose. Truncation is ordinary, and under the old rule
      // losing one line reinterpreted a whole block; this makes it a slope.
      spans.push({ start: start, end: text.length, kind: 'fence' });
      break;
    }
    var end = offsets[j] + lines[j].length;
    spans.push({ start: start, end: end, kind: 'fence' });
    i = j + 1;
  }
  return spans;
}

/* Find a backtick run of exactly `length` in [start, limit) that is not part of
 * a longer run. The `candidate > start` test rather than `candidate >= 0` is
 * deliberate: the character just before `start` is the tail of the opening run
 * itself, and must not disqualify a closing run that begins immediately. */
function matchingBacktickRun(text, start, limit, length) {
  var needle = '`'.repeat(length);
  var candidate = text.indexOf(needle, start);
  while (candidate !== -1 && candidate + length <= limit) {
    var beforeIsTick = candidate > start && text.charAt(candidate - 1) === '`';
    var after = candidate + length;
    var afterIsTick = after < limit && text.charAt(after) === '`';
    if (!beforeIsTick && !afterIsTick) return candidate;
    candidate = text.indexOf(needle, candidate + length);
  }
  return null;
}

/* The span runs until the first Unicode 17 whitespace, the first < > " or
 * backtick, or the first unmatched closing parenthesis. */
function urlEnd(text, start, limit) {
  var i = start;
  var parenDepth = 0;
  while (i < limit) {
    var char = codePointAt(text, i);
    // The Cc test is unreachable defence in depth: validation has already
    // removed every Cc scalar that is not White_Space, and the White_Space ones
    // terminate on the first test. Kept so a reordering of the passes cannot
    // silently swallow a control character into a URL.
    if (
      WHITE_SPACE.has(char) ||
      char === '<' ||
      char === '>' ||
      char === '"' ||
      char === '`' ||
      CONTROL_RE.test(char)
    ) {
      break;
    }
    if (char === '(') {
      parenDepth += 1;
    } else if (char === ')') {
      if (parenDepth === 0) break;
      parenDepth -= 1;
    }
    i += char.length;
  }
  return i;
}

function inlineAndUrlSpans(text, start, end) {
  var spans = [];
  var i = start;
  while (i < end) {
    if (text.charAt(i) === '`') {
      var runEnd = i + 1;
      while (runEnd < end && text.charAt(runEnd) === '`') runEnd += 1;
      var runLength = runEnd - i;
      var closing = matchingBacktickRun(text, runEnd, end, runLength);
      if (closing !== null) {
        var spanEnd = closing + runLength;
        spans.push({ start: i, end: spanEnd, kind: 'inline' });
        i = spanEnd;
        continue;
      }
      // An unmatched run is ordinary prose in its entirety, so resume AFTER it.
      // Advancing one character would re-examine a proper suffix of the run as a
      // shorter run, which can pair with a later run and protect text the prose
      // rules should have normalized. It also made scanning quadratic, since
      // every position in a long run rescanned the tail.
      i = runEnd;
      continue;
    }

    URL_START_RE.lastIndex = i;
    var url = URL_START_RE.exec(text);
    if (url !== null && URL_START_RE.lastIndex <= end) {
      var urlSpanEnd = urlEnd(text, URL_START_RE.lastIndex, end);
      spans.push({ start: i, end: urlSpanEnd, kind: 'url' });
      i = urlSpanEnd;
      continue;
    }
    i += 1;
  }
  return spans;
}

/* Recognition precedence: fenced code blocks first, then inline code spans and
 * HTTP(S) URLs in whatever prose remains. */
function opaqueSpans(text) {
  var fences = fencedSpans(text);
  var spans = [];
  var cursor = 0;
  for (var i = 0; i < fences.length; i += 1) {
    var fence = fences[i];
    spans = spans.concat(inlineAndUrlSpans(text, cursor, fence.start));
    spans.push(fence);
    cursor = fence.end;
  }
  return spans.concat(inlineAndUrlSpans(text, cursor, text.length));
}

/* ------------------------------------------------------------------ *
 * Step 2 continued, and the span normalizations.                      *
 * ------------------------------------------------------------------ */

/* Step 2.4: drop the byte order mark. U+FEFF is a serialization signature
 * rather than writing, so it is not text and does not belong to the author.
 * Removing it here, before recognition, is why it also comes out of a fence. */
function removeArtifacts(text) {
  var out = [];
  for (var i = 0; i < text.length; i += 1) {
    var char = text.charAt(i);
    if (!REMOVED_ARTIFACTS.has(char)) out.push(char);
  }
  return out.join('');
}

/* Step 2.5: every line terminator becomes LF. Prose is unaffected, because
 * step 6.2 collapses any of them to one space either way. What changes is the
 * interior of a protected span, where CRLF and LF used to give different bytes
 * for the same block; MIME text/plain is CRLF-canonical, so email converts as
 * a matter of course. */
function normalizeLineTerminators(text) {
  text = text.split('\r\n').join('\n');
  var out = [];
  for (var i = 0; i < text.length; i += 1) {
    var char = text.charAt(i);
    out.push(LINE_TERMINATORS.has(char) ? '\n' : char);
  }
  return out.join('');
}

/* Step 2.6: remove horizontal whitespace before a line ending or end of input.
 * Editors trim on save, mailers pad, chat clients strip, and nobody can see
 * any of it. */
function rightTrimLines(text) {
  var lines = text.split('\n');
  for (var i = 0; i < lines.length; i += 1) lines[i] = lines[i].replace(TRAILING_HWS_RE, '');
  return lines.join('\n');
}

/* Step 6.1: normalize quotation.
 *
 * The marker first: a leading run of horizontal whitespace, a ">", and every
 * following character that is horizontal whitespace or another ">" all become
 * a single ">". A line that is nothing but the prefix is dropped, as is a
 * blank line, because mailers disagree about whether a blank quoted line keeps
 * its marker and nothing downstream would have preserved it.
 *
 * Then the structure. Consecutive lines of the same kind are joined, so the
 * number of markers stops tracking how a client wrapped the text; and the line
 * ending is kept wherever the kind changes, so a quoted question cannot absorb
 * the reply beneath it. Marking only where a quotation starts would be worse
 * than useless -- it would look as though quotation were tracked while
 * "> Did you murder that man?" followed by "No!" still reached the same bytes
 * as "> Did you murder that man? No!", as every version before 3.17 did.
 */
function normalizeQuotation(text) {
  var lines = text.split('\n');
  var parts = [];
  var current = [];
  var currentQuoted = null;
  for (var i = 0; i < lines.length; i += 1) {
    var line = lines[i];
    var match = QUOTE_PREFIX_RE.exec(line);
    var quoted = match !== null;
    var body = quoted ? line.slice(match[0].length) : line;
    if (body.trim() === '') continue;
    if (currentQuoted !== null && quoted !== currentQuoted) {
      parts.push((currentQuoted ? '>' : '') + current.join(' '));
      current = [];
    }
    currentQuoted = quoted;
    current.push(body);
  }
  if (currentQuoted !== null) parts.push((currentQuoted ? '>' : '') + current.join(' '));
  return parts.join('\n');
}

/* Strip leading horizontal whitespace from a fence's delimiter lines. Only the
 * two lines that are pure syntax; indentation inside the block is content --
 * it is what Python means -- and is never touched. */
function normalizeFenceIndent(body) {
  var lines = linesWithEndings(body);
  var fenceLength = null;
  var out = [];
  for (var i = 0; i < lines.length; i += 1) {
    var line = lines[i];
    var core = lineBody(line);
    if (fenceLength === null) {
      var opening = FENCE_OPEN_RE.exec(core);
      if (opening) {
        fenceLength = opening[1].length;
        line = line.replace(LEAD_HWS_RE, '');
      }
      out.push(line);
      continue;
    }
    if (i === lines.length - 1) {
      var closing = new RegExp('^' + HWS_CLASS + '*`{' + fenceLength + ',}' + HWS_CLASS + '*$');
      if (closing.test(core)) line = line.replace(LEAD_HWS_RE, '');
    }
    out.push(line);
  }
  return out.join('');
}

/* RFC 3986 case-insensitivity is ASCII-only. A Unicode lowering would fold
 * characters a scheme or host cannot legally contain, and is locale-sensitive
 * for the dotted capital I. */
function asciiLower(text) {
  return text.replace(/[A-Z]/g, function (c) { return c.toLowerCase(); });
}

/* Lowercase what RFC 2045 defines as case-insensitive in a data: header, and
 * nothing else. Section 5.1: the type, the subtype and each parameter's
 * attribute NAME are case-insensitive. A value is not, in general -- charset
 * happens to be, but that is RFC 2046 speaking about one parameter rather than
 * a rule about values -- so a value is reproduced exactly. ";base64" is an
 * attribute name with no value and folds with them. */
function lowerDataHeader(header) {
  var parts = header.split(';');
  var out = [asciiLower(parts[0])];
  for (var i = 1; i < parts.length; i += 1) {
    var eq = parts[i].indexOf('=');
    out.push(eq < 0 ? asciiLower(parts[i])
                    : asciiLower(parts[i].slice(0, eq)) + parts[i].slice(eq));
  }
  return out.join(';');
}

/* A protected span is not untouched bytes. It is text canonicalized under a
 * reduced rule set: line structure belongs to the channel, everything else
 * belongs to the author. */
function normalizeSpan(kind, body) {
  if (kind === 'fence') return normalizeFenceIndent(body);
  if (kind === 'inline') {
    // A line ending inside an inline span folds to one space, along with any
    // indentation after it. That is what makes an inline span rewrap-safe, and
    // it is the difference between the two kinds: an inline span carries no
    // line structure, a fence does.
    return body.replace(FOLD_NEWLINES_RE, ' ');
  }
  if (kind === 'url') {
    var m = URL_AUTHORITY_RE.exec(body);
    if (m) {
      var authority = m[3];
      var at = authority.lastIndexOf('@');
      var userinfo = at >= 0 ? authority.slice(0, at + 1) : '';
      var host = at >= 0 ? authority.slice(at + 1) : authority;
      return asciiLower(m[1]) + m[2] + userinfo + asciiLower(host) + m[4];
    }
    // A data: URI carries its own case-insensitive fields, defined by RFC 2045
    // rather than by RFC 3986: the type, the subtype and each parameter's
    // attribute name. Those fold; parameter values and the payload do not.
    var dm = DATA_URI_RE.exec(body);
    if (dm) return asciiLower(dm[1]) + ':' + lowerDataHeader(dm[2]) + dm[3];
    // Any other URI with no authority -- mailto: -- has a case-insensitive
    // scheme and nothing else this algorithm is entitled to fold.
    var n = URL_SCHEME_RE.exec(body);
    if (n) return asciiLower(n[1]) + n[2] + n[3];
    return body;
  }
  return body;
}

function protect(text) {
  var spans = opaqueSpans(text);
  if (spans.length === 0) return { text: text, spans: new Map() };

  var parts = [];
  var stash = new Map();
  var cursor = 0;
  for (var i = 0; i < spans.length; i += 1) {
    var span = spans[i];
    var marker = MARKER_OPEN + 'CQT' + i + MARKER_CLOSE;
    parts.push(text.slice(cursor, span.start));
    parts.push(marker);
    stash.set(marker, normalizeSpan(span.kind, text.slice(span.start, span.end)));
    cursor = span.end;
  }
  parts.push(text.slice(cursor));
  return { text: parts.join(''), spans: stash };
}

/* ------------------------------------------------------------------ *
 * Steps 5 through 7.                                                  *
 * ------------------------------------------------------------------ */

/* Step 5: drop the four layout-only characters.
 *
 * U+200B survives between two scalars from a script that does not separate words
 * with spaces, where it is the word separator rather than an artifact. Both
 * neighbours must qualify, so a stray U+200B injected at a script boundary by a
 * mailer or sanitizer is still removed. Iteration is by code point because Ahom,
 * one of those scripts, lives in the astral planes.
 */
function removeInvisibles(text) {
  var chars = Array.from(text);
  var out = [];
  for (var i = 0; i < chars.length; i += 1) {
    var char = chars[i];
    if (!REMOVED_INVISIBLES.has(char)) {
      out.push(char);
      continue;
    }
    if (char === ZERO_WIDTH_SPACE) {
      var before = i > 0 ? chars[i - 1] : null;
      var after = i + 1 < chars.length ? chars[i + 1] : null;
      if (before !== null && after !== null && SPACELESS_SCRIPTS.has(before) && SPACELESS_SCRIPTS.has(after)) {
        out.push(char);
      }
    }
  }
  return out.join('');
}

/* Step 6.2: a run of whitespace becomes one space, or one LF if the run
 * contains one. Step 6.1 has already joined every line within a passage, so
 * the only line endings left are the boundaries it chose to keep, and those
 * carry meaning a space would destroy. Step 6.3 then trims both. */
function collapseWhitespace(text) {
  return text
    .replace(WHITESPACE_RUN_RE, function (run) { return run.indexOf('\n') >= 0 ? '\n' : ' '; })
    .replace(TRIM_EDGES_RE, '');
}

/** Replace every occurrence literally, with no `$` substitution in the target. */
function replaceAllLiteral(text, source, target) {
  return text.split(source).join(target);
}

/* Step 7.9: attach punctuation to the side it belongs to.
 *
 * Punctuation is not symmetric. Opening punctuation binds to what follows it and
 * closing, final and terminal punctuation bind to what precedes, so a space is
 * removed on the side the punctuation attaches to and left alone on the other.
 * That keeps "ignorance, up" and "name: value" intact while still converging
 * "hello :)" and "hello <U+1F60A>" on "hello:-)", which is what this rule exists
 * to do.
 */
function removeSpacesAdjacentToPunctuation(text) {
  var out = [];
  var cursor = 0;
  var match;
  SPACE_RUN_RE.lastIndex = 0;
  while ((match = SPACE_RUN_RE.exec(text)) !== null) {
    var runStart = match.index;
    var runEnd = match.index + match[0].length;
    out.push(text.slice(cursor, runStart));
    var before = codePointBefore(text, runStart);
    var after = codePointAt(text, runEnd);
    var attachesLeft = after !== null && (TERMINAL_PUNCTUATION.has(after) || CLOSING_OR_FINAL_RE.test(after));
    var attachesRight = before !== null && OPENING_OR_INITIAL_RE.test(before);
    if (!attachesLeft && !attachesRight) out.push(' ');
    cursor = runEnd;
  }
  out.push(text.slice(cursor));
  return out.join('');
}

/* One pass, in order. Nothing here runs twice.
 *
 * The autocorrect tables run before space removal. A client that swaps an emoji
 * for its emoticon spelling, or the reverse, is exactly the kind of tooling
 * transformation CQT exists to survive, so "hello <emoji>", "hello :)" and
 * "hello :-)" must all reach the same bytes. Mapping to the canonical spelling
 * first puts a colon where the space rule can see it.
 *
 * The cost of a single pass is that ": )" ends at ":)" rather than ":-)", since
 * nothing revisits the tables after the space closes the gap. That is an oddity
 * somebody typed, not something a tool did to their text.
 */
function canonicalizeProse(text) {
  var i;
  text = text.normalize('NFKC');
  text = removeInvisibles(text);
  text = normalizeQuotation(text);
  text = collapseWhitespace(text);
  text = text.replace(DASH_PUNCTUATION_RE, '-');
  text = text.replace(MULTI_HYPHEN_RE, '-');
  text = replaceAllLiteral(text, IDEOGRAPHIC_COMMA, ',');
  text = replaceAllLiteral(text, IDEOGRAPHIC_FULL_STOP, '.');
  text = replaceAllLiteral(text, HORIZONTAL_ELLIPSIS, '...');
  text = text.replace(LONG_DOTS_RE, '...');
  text = replaceAllLiteral(text, FRACTION_SLASH, '/');
  text = text.replace(QUOTE_CHARACTERS_RE, "'");
  for (i = 0; i < AUTOCORRECT_PAIRS.length; i += 1) {
    text = replaceAllLiteral(text, AUTOCORRECT_PAIRS[i][0], AUTOCORRECT_PAIRS[i][1]);
  }
  for (i = 0; i < ASCII_AUTOCORRECT_PAIRS.length; i += 1) {
    text = replaceAllLiteral(text, ASCII_AUTOCORRECT_PAIRS[i][0], ASCII_AUTOCORRECT_PAIRS[i][1]);
  }
  for (i = 0; i < GUARDED_EMOTICONS.length; i += 1) {
    text = text.replace(GUARDED_EMOTICONS[i][0], GUARDED_EMOTICONS[i][1]);
  }
  text = removeSpacesAdjacentToPunctuation(text);
  text = replaceAllLiteral(text, '&', ' & ');
  return collapseWhitespace(text);
}

/* ------------------------------------------------------------------ *
 * The algorithm.                                                      *
 * ------------------------------------------------------------------ */

/**
 * Return the CQT 3.17 canonical UTF-8 byte stream for `plaintext`.
 *
 * @param {string} plaintext
 * @returns {Uint8Array}
 */
function algorithm_3_17(plaintext) {
  if (typeof plaintext !== 'string') throw new TypeError('plaintext must be a string');
  // Strip what cannot be plain text BEFORE recognizing anything. Otherwise an
  // override hidden inside a fence or a URL is copied through untouched, and the
  // span becomes a channel for exactly the spoof this removal prevents.
  var stripped = stripDisallowed(plaintext);
  stripped = removeArtifacts(stripped);
  stripped = normalizeLineTerminators(stripped);
  stripped = rightTrimLines(stripped);
  var protectedResult = protect(stripped);
  var stash = protectedResult.spans;
  var text = canonicalizeProse(protectedResult.text);
  // A marker-shaped run that came from the input rather than from `protect` has
  // no entry, and stays the text it always was; CQT never rejects input.
  text = text.replace(PROTECTED_MARKER_RE, function (marker) {
    return stash.has(marker) ? stash.get(marker) : marker;
  });
  return new TextEncoder().encode(text);
}

/**
 * Return the CQT 3.17 canonical form of `plaintext` as a JavaScript string.
 * Convenience for callers that are not about to hash the bytes.
 *
 * @param {string} plaintext
 * @returns {string}
 */
function canonicalize(plaintext) {
  return new TextDecoder().decode(algorithm_3_17(plaintext));
}

var api = {
  algorithm_3_17: algorithm_3_17,
  canonicalize: canonicalize,
  UNICODE_VERSION: UNICODE_VERSION,
};

// Node (CommonJS): the three names come off require('./cqt.js').
if (typeof module !== 'undefined' && module.exports) module.exports = api;

// Browser: `algorithm_3_17` is the global entry point, which is how form.html
// reaches the algorithm from a plain <script src="cqt.js">.
if (typeof window !== 'undefined') {
  window.algorithm_3_17 = algorithm_3_17;
  window.canonicalize = canonicalize;
  window.CQT = api;
}

})();
