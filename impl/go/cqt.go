// Package cqt is a port of the Canonical Quoted Text 3.17 reference
// implementation (cqt.py) to Go.
//
// CQT 3.17 pins every Unicode Character Database lookup to Unicode 17.0.0.
// Go's own tables move with the toolchain: go1.26 and earlier ship Unicode
// 15.0.0 both in the standard library and, through golang.org/x/text, in the
// normalizer. go1.27 ships 17.0.0 in both. This package therefore requires a
// go1.27 or later toolchain (go.mod asks for one) and refuses to load when the
// tables it can see are not 17.0.0, exactly as the reference implementation
// refuses to load when unicodedata2 reports another version. Substituting
// whichever version the runtime happens to have would silently produce
// non-conformant bytes; see "Official name and version" in README.md.
package cqt

import (
	"fmt"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

// UnicodeVersion is the Unicode edition every property lookup below must use.
const UnicodeVersion = "17.0.0"

func init() {
	if norm.Version != UnicodeVersion || unicode.Version != UnicodeVersion {
		panic(fmt.Sprintf(
			"cqt3.17 requires Unicode %s, but this build sees normalization tables %s "+
				"and standard-library tables %s; build with a go1.27 or later toolchain",
			UnicodeVersion, norm.Version, unicode.Version))
	}
}

// A span is a half-open range of scalar values -- not bytes, and not UTF-16
// code units -- in the working text.
type spanKind int

const (
	fenceSpan spanKind = iota
	inlineSpan
	urlSpan
)

type span struct {
	start, end int
	kind       spanKind
}

const (
	zeroWidthSpace = '\u200b'

	// The marker is built from NUL deliberately. Step 2 strips every Cc scalar
	// from the input BEFORE protection runs, so the working text provably
	// cannot contain one and a marker cannot be forged. A marker made of
	// noncharacters could be: an input holding U+FDD0 CQT0 U+FDEF used to have
	// span 0's content substituted into it, so two different inputs reached the
	// same bytes. NUL also survives NFKC and is neither whitespace nor
	// punctuation, which is what step 3 requires of a placeholder.
	markerOpen  = '\u0000'
	markerClose = '\u0000'
)

var (
	// U+00AD SOFT HYPHEN, U+200B ZERO WIDTH SPACE and U+2060 WORD JOINER.
	// U+FEFF is NOT here: it is a serialization artifact rather than a layout
	// one, so step 2.4 removes it before anything is recognized, which is why
	// it also comes out of a protected span.
	removedInvisibles = codepoints("00AD", "200B", "2060")
	removedArtifacts  = codepoints("FEFF")

	// Step 2.5 folds all of these onto LF, so from step 3 onward LF is the only
	// line terminator and horizontal whitespace is the rest of White_Space.
	lineTerminators = codepoints("000A-000D", "0085", "2028-2029")

	// The Unicode 17.0.0 White_Space set named in step 6.2.
	whiteSpace = codepoints(
		"0009-000D", "0020", "0085", "00A0", "1680", "2000-200A",
		"2028-2029", "202F", "205F", "3000")

	// White_Space without LF, which step 2.5 has made the only line terminator.
	horizontalWhiteSpace = codepoints(
		"0009", "000B-000D", "0020", "0085", "00A0", "1680", "2000-200A",
		"2028-2029", "202F", "205F", "3000")

	// DashPunctuation is the Unicode 17.0.0 Dash_Punctuation (Pd) category.
	DashPunctuation = codepoints(
		"002D", "058A", "05BE", "1400", "1806", "2010-2015", "2E17", "2E1A",
		"2E3A-2E3B", "2E40", "2E5D", "301C", "3030", "30A0", "FE31-FE32",
		"FE58", "FE63", "FF0D", "10D6E", "10EAD")

	// The quote characters step 7.6 folds onto the ASCII apostrophe.
	quoteCharacters = codepoints(
		"0022", "00AB", "00BB", "2018-2019", "201C-201D", "2039-203A",
		"3008-300D")

	// TerminalPunctuation is the Unicode 17.0.0 Terminal_Punctuation property,
	// from PropList.txt. Punctuation that ends a sentence, clause or word, and
	// so attaches to the text on its LEFT. The ASCII members are exactly
	// ! , . : ; ? -- deliberately NOT the whole Po category, which would drag
	// in the solidus and turn "A & B / C" into "A & B/ C", nor the apostrophe,
	// which step 7.6 has already made ambiguous by folding every quote
	// character onto it.
	TerminalPunctuation = codepoints(
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
		"1BC9F", "1DA87-1DA8A")

	// SpacelessScripts is Unicode 17.0.0 Line_Break=SA, from LineBreak.txt: the
	// scripts that do not separate words with spaces and therefore need
	// explicit break opportunities -- Thai, Lao, Khmer, Myanmar, Tai Tham,
	// New Tai Lue, Ahom. In these scripts U+200B is a real word separator
	// rather than a layout artifact.
	SpacelessScripts = codepoints(
		"0E01-0E3A", "0E40-0E4E", "0E81-0E82", "0E84", "0E86-0E8A", "0E8C-0EA3",
		"0EA5", "0EA7-0EBD", "0EC0-0EC4", "0EC6", "0EC8-0ECE", "0EDC-0EDF",
		"1000-103F", "1050-108F", "109A-109F", "1780-17D3", "17D7", "17DC-17DD",
		"1950-196D", "1970-1974", "1980-19AB", "19B0-19C9", "19DE-19DF", "1A20-1A5E",
		"1A60-1A7C", "1AA0-1AAD", "A9E0-A9EF", "A9FA-A9FE", "AA60-AAC2", "AADB-AADF",
		"11700-1171A", "1171D-1172B", "1173A-1173B", "1173F-11746")
)

// A replacement is one row of an autocorrect table.
type replacement struct{ from, to string }

// autocorrectBase is the twelve-row table in step 7.7.
var autocorrectBase = []replacement{
	{"\U0001f60a", ":-)"},
	{"\U0001f610", ":-|"},
	{"☹", ":-("},
	{"\U0001f603", ":-D"},
	{"\U0001f61d", ":-p"},
	{"\U0001f632", ":-o"},
	{"\U0001f609", ";-)"},
	{"❤", "<3"},
	{"\U0001f494", "</3"},
	{"©", "(c)"},
	{"®", "(R)"},
	{"•", "*"},
}

// autocorrectPairs expands every base row into its three spellings: with a
// trailing U+FE0F VARIATION SELECTOR-16, with a trailing U+FE0E VARIATION
// SELECTOR-15, and bare.
//
// A trailing variation selector belongs to the character it follows, whichever
// selector it is. VS16 asks for emoji presentation and VS15 for text
// presentation; neither changes what the character is, so all three spellings a
// keyboard might emit have to converge, which is the whole point of this step.
// Longest source first, so a selector is never left stranded by a match on the
// bare form.
var autocorrectPairs = expandVariationSelectors(autocorrectBase)

func expandVariationSelectors(base []replacement) []replacement {
	out := make([]replacement, 0, 3*len(base))
	for _, pair := range base {
		out = append(out,
			replacement{pair.from + "\ufe0f", pair.to},
			replacement{pair.from + "\ufe0e", pair.to},
			pair)
	}
	return out
}

var asciiAutocorrectPairs = []replacement{
	{":)", ":-)"},
	{":|", ":-|"},
	{":(", ":-("},
	{";)", ";-)"},
}

// The three whose second character is a letter carry a trailing guard: they
// convert only when what follows is not an ASCII letter, digit, "-" or "_".
// Without it the table rewrites URI schemes -- "did:peer" became "did:-peer"
// and "did:keri:DKxy..." became "did:keri:-DKxy...". Trailing only; a leading
// guard would also stop converting "lol:p", which people type.
var guardedEmoticons = []replacement{
	{":D", ":-D"},
	{":p", ":-p"},
	{":o", ":-o"},
}

func applyGuardedEmoticons(text string) string {
	runes := []rune(text)
	var b strings.Builder
	for i := 0; i < len(runes); {
		matched := false
		for _, pair := range guardedEmoticons {
			from := []rune(pair.from)
			if i+len(from) > len(runes) {
				continue
			}
			if runes[i] != from[0] || runes[i+1] != from[1] {
				continue
			}
			if next := i + len(from); next < len(runes) && isEmoticonGuard(runes[next]) {
				continue
			}
			b.WriteString(pair.to)
			i += len(from)
			matched = true
			break
		}
		if !matched {
			b.WriteRune(runes[i])
			i++
		}
	}
	return b.String()
}

func isEmoticonGuard(r rune) bool {
	return (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') ||
		(r >= '0' && r <= '9') || r == '-' || r == '_'
}

// codepoints expands "0E01-0E3A"-style ranges into a set of scalars.
func codepoints(ranges ...string) map[rune]bool {
	out := make(map[rune]bool)
	for _, item := range ranges {
		first, last, ok := strings.Cut(item, "-")
		if !ok {
			last = first
		}
		lo, err := strconv.ParseInt(first, 16, 32)
		if err != nil {
			panic(err)
		}
		hi, err := strconv.ParseInt(last, 16, 32)
		if err != nil {
			panic(err)
		}
		for cp := lo; cp <= hi; cp++ {
			out[rune(cp)] = true
		}
	}
	return out
}

// decode turns a Go string into the sequence of code points it spells.
//
// Go strings are UTF-8 byte sequences, so ranging over one yields BYTE offsets
// and cannot represent a lone surrogate; converting with []rune would fold each
// byte of an ill-formed sequence into its own U+FFFD. CQT records spans as
// scalar offsets, and step 2.1 has to be able to see an unpaired surrogate in
// order to remove it, so decode works in scalars throughout, keeps a surrogate
// that was encoded in WTF-8 (the three-byte form ED A0..BF 80..BF) as the
// surrogate code point it spells, and leaves any other ill-formed byte as the
// U+FFFD the standard decoder produces.
func decode(s string) []rune {
	runes := make([]rune, 0, len(s))
	for i := 0; i < len(s); {
		if i+2 < len(s) && s[i] == 0xED && s[i+1] >= 0xA0 && s[i+1] <= 0xBF &&
			s[i+2] >= 0x80 && s[i+2] <= 0xBF {
			runes = append(runes,
				rune(s[i]&0x0F)<<12|rune(s[i+1]&0x3F)<<6|rune(s[i+2]&0x3F))
			i += 3
			continue
		}
		r, size := utf8.DecodeRuneInString(s[i:])
		runes = append(runes, r)
		i += size
	}
	return runes
}

// stripDisallowed removes what cannot belong to plain text.
//
// Three groups, all of them artifacts rather than writing. Control characters
// outside the White_Space set -- NUL and its neighbours -- are not plain text.
// Unpaired surrogates are not Unicode scalar values at all and have no UTF-8
// encoding; a well-formed pair is a character and is left alone. And the two
// directional overrides, LRO and RLO, force every character in their scope to
// render in a given direction regardless of what the character is, so Latin
// letters display reversed. That is an instruction to a rendering engine, not
// a statement about the text, and it is the primitive behind bidi spoofing.
//
// The other bidi controls stay. Marks (ALM, LRM, RLM) only affect how
// neighbouring neutral characters resolve, and isolates (LRI, RLI, FSI, PDI)
// scope a direction without overriding anything, so both are ordinary parts of
// correct Arabic and Hebrew text.
func stripDisallowed(text []rune) []rune {
	out := make([]rune, 0, len(text))
	for i := 0; i < len(text); {
		r := text[i]
		if r >= 0xD800 && r <= 0xDBFF {
			if i+1 < len(text) && text[i+1] >= 0xDC00 && text[i+1] <= 0xDFFF {
				// A well-formed pair is one astral character, not two errors.
				out = append(out, 0x10000+((r-0xD800)<<10)+(text[i+1]-0xDC00))
				i += 2
				continue
			}
			i++
			continue
		}
		if r >= 0xDC00 && r <= 0xDFFF {
			i++
			continue
		}
		if unicode.Is(unicode.Cc, r) && !whiteSpace[r] {
			i++
			continue
		}
		// U+202D LEFT-TO-RIGHT OVERRIDE and U+202E RIGHT-TO-LEFT OVERRIDE are
		// the only two scalars whose Bidi_Class is LRO or RLO.
		if r == '\u202d' || r == '\u202e' {
			i++
			continue
		}
		out = append(out, r)
		i++
	}
	return out
}

// lineStarts and lineEnds split text into lines that carry their endings. For
// fence recognition a line ending is exactly LF, CR, or CRLF; no other Unicode
// separator ends a line.
func lineStartsAndEnds(text []rune) (starts, ends []int) {
	start := 0
	for i := 0; i < len(text); i++ {
		if text[i] != '\n' {
			continue
		}
		starts = append(starts, start)
		ends = append(ends, i+1)
		start = i + 1
	}
	if start < len(text) {
		starts = append(starts, start)
		ends = append(ends, len(text))
	}
	return starts, ends
}

// lineBody drops the line ending, if any, from a line.
func lineBody(line []rune) []rune {
	if n := len(line); n >= 1 && line[n-1] == '\n' {
		return line[:n-1]
	}
	return line
}

// fenceOpen matches a delimiter line: any leading horizontal whitespace, a run
// of three or more backticks, and an info string containing no backtick. It
// returns the length of the backtick run.
//
// There is no three-space limit. CommonMark needs one so a fence can be told
// from a four-space indented code block; CQT has no indented code blocks, so
// the limit protected nothing and cost a fence that transport had indented.
func fenceOpen(body []rune) (int, bool) {
	i := 0
	for i < len(body) && horizontalWhiteSpace[body[i]] {
		i++
	}
	ticks := 0
	for i+ticks < len(body) && body[i+ticks] == '`' {
		ticks++
	}
	if ticks < 3 {
		return 0, false
	}
	for _, r := range body[i+ticks:] {
		if r == '`' {
			return 0, false
		}
	}
	return ticks, true
}

// fenceClose matches a closing delimiter line: any leading horizontal
// whitespace and a backtick run at least as long as the opener. Step 2.6 has
// already removed anything that could follow it.
func fenceClose(body []rune, n int) bool {
	i := 0
	for i < len(body) && horizontalWhiteSpace[body[i]] {
		i++
	}
	ticks := 0
	for i+ticks < len(body) && body[i+ticks] == '`' {
		ticks++
	}
	if ticks < n {
		return false
	}
	for _, r := range body[i+ticks:] {
		if !horizontalWhiteSpace[r] {
			return false
		}
	}
	return true
}

func fencedSpans(text []rune) []span {
	starts, ends := lineStartsAndEnds(text)

	var spans []span
	i := 0
	for i < len(starts) {
		ticks, ok := fenceOpen(lineBody(text[starts[i]:ends[i]]))
		if !ok {
			i++
			continue
		}
		j := i + 1
		for j < len(starts) && !fenceClose(lineBody(text[starts[j]:ends[j]]), ticks) {
			j++
		}
		// Take the line ending that precedes the opening line, so the fence
		// still starts a line after the prose around it has been flattened.
		start := starts[i]
		if start >= 1 && text[start-1] == '\n' {
			start--
		}
		if n := len(spans); n > 0 && spans[n-1].end > start {
			start = spans[n-1].end
		}
		if j == len(starts) {
			// An opener with no closer runs to the end of the input rather
			// than decaying into prose. Truncation is ordinary, and under the
			// old rule losing one line reinterpreted a whole block.
			spans = append(spans, span{start, len(text), fenceSpan})
			break
		}
		spans = append(spans, span{start, ends[j], fenceSpan})
		i = j + 1
	}
	return spans
}

// matchingBacktickRun finds the first run of exactly length backticks that lies
// inside [start, limit) and is not part of a longer run.
func matchingBacktickRun(text []rune, start, limit, length int) (int, bool) {
	for candidate := start; candidate+length <= limit; candidate++ {
		if text[candidate] != '`' {
			continue
		}
		run := 0
		for candidate+run < limit && text[candidate+run] == '`' {
			run++
		}
		if run == length && !(candidate > start && text[candidate-1] == '`') {
			return candidate, true
		}
		candidate += run - 1
	}
	return 0, false
}

func urlEnd(text []rune, start, limit int) int {
	i := start
	parenDepth := 0
	for i < limit {
		r := text[i]
		// The Cc test is unreachable defence in depth: step 2 has already
		// removed every Cc scalar that is not White_Space, and the White_Space
		// ones terminate on the first test. Kept so a reordering of the passes
		// cannot silently swallow a control character into a URL.
		if whiteSpace[r] || r == '<' || r == '>' || r == '"' || r == '`' ||
			unicode.Is(unicode.Cc, r) {
			break
		}
		if r == '(' {
			parenDepth++
		} else if r == ')' {
			if parenDepth == 0 {
				break
			}
			parenDepth--
		}
		i++
	}
	return i
}

func isAlpha(r rune) bool {
	return (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z')
}

func isSchemeChar(r rune) bool {
	return isAlpha(r) || (r >= '0' && r <= '9') || r == '+' || r == '-' || r == '.'
}

// isTokenChar reports whether r may appear in an RFC 2045 token: printable
// ASCII other than space, control characters and the tspecials ()<>@,;:\"/[]?=
func isTokenChar(r rune) bool {
	if r <= ' ' || r >= 0x7F {
		return false
	}
	switch r {
	case '(', ')', '<', '>', '@', ',', ';', ':', '\\', '"', '/', '[', ']', '?', '=':
		return false
	}
	return true
}

// literal matches an ASCII literal case-insensitively, ASCII-only.
func literal(text []rune, i, limit int, want string) (int, bool) {
	if i+len(want) > limit {
		return 0, false
	}
	for k := 0; k < len(want); k++ {
		if asciiLower(text[i+k]) != rune(want[k]) {
			return 0, false
		}
	}
	return i + len(want), true
}

func runOfTokens(text []rune, i, limit int) (int, bool) {
	start := i
	for i < limit && isTokenChar(text[i]) {
		i++
	}
	return i, i > start
}

// dataHeader matches an RFC 2397 header: an optional type/subtype, zero or
// more ";attribute=value" parameters, an optional ";base64", and the mandatory
// comma. It returns the offset just past the comma.
func dataHeader(text []rune, i, limit int) (int, bool) {
	if j, ok := runOfTokens(text, i, limit); ok && j < limit && text[j] == '/' {
		if k, ok := runOfTokens(text, j+1, limit); ok {
			i = k
		}
	}
	for i < limit && text[i] == ';' {
		if j, ok := literal(text, i, limit, ";base64"); ok && j < limit && text[j] == ',' {
			return j + 1, true
		}
		j, ok := runOfTokens(text, i+1, limit)
		if !ok || j >= limit || text[j] != '=' {
			return 0, false
		}
		k, ok := runOfTokens(text, j+1, limit)
		if !ok {
			return 0, false
		}
		i = k
	}
	if i < limit && text[i] == ',' {
		return i + 1, true
	}
	return 0, false
}

// urlStart recognizes the three forms of URI span and returns the offset just
// past the recognized prefix. Any scheme followed by "://" is safe because
// "://" does not occur in prose; a bare scheme is not, because "note:" and
// "here is the data:" are ordinary English. The two bare schemes admitted here
// carry structure a sentence does not: mailto: must reach an "@" before any
// whitespace, and data: must present a well-formed RFC 2397 header.
//
// Comparison is ASCII-only throughout. A Unicode case fold would make U+017F
// LATIN SMALL LETTER LONG S match the "s" of "https", and RFC 3986 section 3.1
// allows only ASCII letters in a scheme, so that match is simply wrong.
func urlStart(text []rune, i, limit int) (int, bool) {
	if !isAlpha(text[i]) {
		return 0, false
	}
	j := i + 1
	for j < limit && isSchemeChar(text[j]) {
		j++
	}
	if k, ok := literal(text, j, limit, "://"); ok {
		return k, true
	}
	if k, ok := literal(text, i, limit, "mailto:"); ok {
		for n := k; n < limit && !whiteSpace[text[n]]; n++ {
			if text[n] == '@' {
				return k, true
			}
		}
		return 0, false
	}
	if k, ok := literal(text, i, limit, "data:"); ok {
		return dataHeader(text, k, limit)
	}
	return 0, false
}

func asciiLower(r rune) rune {
	if r >= 'A' && r <= 'Z' {
		return r + ('a' - 'A')
	}
	return r
}

func inlineAndURLSpans(text []rune, start, end int) []span {
	var spans []span
	i := start
	for i < end {
		if text[i] == '`' {
			runEnd := i + 1
			for runEnd < end && text[runEnd] == '`' {
				runEnd++
			}
			runLength := runEnd - i
			if closing, ok := matchingBacktickRun(text, runEnd, end, runLength); ok {
				spanEnd := closing + runLength
				spans = append(spans, span{i, spanEnd, inlineSpan})
				i = spanEnd
				continue
			}
			// An unmatched run is ordinary prose in its entirety, so resume
			// AFTER it. Advancing one character would re-examine a proper
			// suffix of the run as a shorter run, which can pair with a later
			// run and protect text the prose rules should have normalized. It
			// also made scanning quadratic, since every position in a long run
			// rescanned the tail.
			i = runEnd
			continue
		}

		if schemeEnd, ok := urlStart(text, i, end); ok {
			spanEnd := urlEnd(text, schemeEnd, end)
			spans = append(spans, span{i, spanEnd, urlSpan})
			i = spanEnd
			continue
		}
		i++
	}
	return spans
}

// opaqueSpans applies the precedence in README.md: fenced code blocks first,
// then inline code spans and HTTP(S) URLs in whatever prose remains.
func opaqueSpans(text []rune) []span {
	fences := fencedSpans(text)
	var spans []span
	cursor := 0
	for _, fence := range fences {
		spans = append(spans, inlineAndURLSpans(text, cursor, fence.start)...)
		spans = append(spans, fence)
		cursor = fence.end
	}
	spans = append(spans, inlineAndURLSpans(text, cursor, len(text))...)
	return spans
}

// protect replaces every opaque span with a placeholder that is neither
// whitespace nor punctuation, and that the input provably cannot spell.
// removeArtifacts is step 2.4: drop the byte order mark. U+FEFF is a
// serialization signature rather than writing, so it is not text and does not
// belong to the author. Removing it here, before recognition, is why it also
// comes out of a protected span.
func removeArtifacts(text []rune) []rune {
	out := text[:0:0]
	for _, r := range text {
		if !removedArtifacts[r] {
			out = append(out, r)
		}
	}
	return out
}

// normalizeLineTerminators is step 2.5: every line terminator becomes LF.
// Prose is unaffected, because step 6.2 collapses any of them to one space
// either way. What changes is the interior of a protected span, where CRLF and
// LF used to give different bytes for the same block; MIME text/plain is
// CRLF-canonical, so email converts as a matter of course.
func normalizeLineTerminators(text []rune) []rune {
	out := make([]rune, 0, len(text))
	for i := 0; i < len(text); i++ {
		if text[i] == '\r' && i+1 < len(text) && text[i+1] == '\n' {
			out = append(out, '\n')
			i++
			continue
		}
		if lineTerminators[text[i]] {
			out = append(out, '\n')
			continue
		}
		out = append(out, text[i])
	}
	return out
}

// rightTrimLines is step 2.6: remove the whole run of horizontal whitespace
// that precedes a line ending or the end of the input. Editors trim on save,
// mailers pad, chat clients strip, and nobody can see any of it.
func rightTrimLines(text []rune) []rune {
	out := make([]rune, 0, len(text))
	pending := make([]rune, 0, 8)
	for _, r := range text {
		if horizontalWhiteSpace[r] {
			pending = append(pending, r)
			continue
		}
		// A pending run is emitted verbatim unless a line ending follows it,
		// in which case it is what this step exists to remove. Emitting spaces
		// instead of the original runes would turn a tab inside an inline code
		// span into a space, which is not this step's business.
		if r != '\n' {
			out = append(out, pending...)
		}
		pending = pending[:0]
		out = append(out, r)
	}
	// A run at the end of the input precedes the end of the input, so it goes.
	return out
}

// normalizeQuotation is step 6.1.
//
// The marker first: a leading run of horizontal whitespace, a ">", and every
// following character that is horizontal whitespace or another ">" all become
// a single ">". A line that is nothing but the prefix is dropped, as is a
// blank line, because mailers disagree about whether a blank quoted line keeps
// its marker and nothing downstream would have preserved it.
//
// Then the structure. Consecutive lines of the same kind are joined, so the
// number of markers stops tracking how a client wrapped the text; and the line
// ending is kept wherever the kind changes, so a quoted question cannot absorb
// the reply beneath it. Marking only where a quotation starts would be worse
// than useless: it would look as though quotation were tracked while
// "> Did you murder that man?" followed by "No!" still reached the same bytes
// as "> Did you murder that man? No!", as every version before 3.17 did.
func normalizeQuotation(text string) string {
	var parts []string
	var current []string
	quoted, haveKind := false, false
	for _, line := range strings.Split(text, "\n") {
		runes := []rune(line)
		i := 0
		for i < len(runes) && horizontalWhiteSpace[runes[i]] {
			i++
		}
		isQuoted := i < len(runes) && runes[i] == '>'
		if isQuoted {
			i++
			for i < len(runes) && (runes[i] == '>' || horizontalWhiteSpace[runes[i]]) {
				i++
			}
		} else {
			i = 0
		}
		body := string(runes[i:])
		if strings.TrimSpace(body) == "" {
			continue
		}
		if haveKind && isQuoted != quoted {
			parts = append(parts, marker(quoted)+strings.Join(current, " "))
			current = nil
		}
		quoted, haveKind = isQuoted, true
		current = append(current, body)
	}
	if haveKind {
		parts = append(parts, marker(quoted)+strings.Join(current, " "))
	}
	return strings.Join(parts, "\n")
}

func marker(quoted bool) string {
	if quoted {
		return ">"
	}
	return ""
}

// normalizeFenceIndent strips leading horizontal whitespace from a fence's
// delimiter lines. Only the two lines that are pure syntax; indentation inside
// the block is content -- it is what Python means -- and is never touched.
func normalizeFenceIndent(body string) string {
	runes := []rune(body)
	starts, ends := lineStartsAndEnds(runes)
	fenceLength, haveFence := 0, false
	var b strings.Builder
	for i := range starts {
		line := runes[starts[i]:ends[i]]
		core := lineBody(line)
		if !haveFence {
			if ticks, ok := fenceOpen(core); ok {
				fenceLength, haveFence = ticks, true
				line = dropLeadingHorizontal(line)
			}
			b.WriteString(string(line))
			continue
		}
		if i == len(starts)-1 && fenceClose(core, fenceLength) {
			line = dropLeadingHorizontal(line)
		}
		b.WriteString(string(line))
	}
	return b.String()
}

func dropLeadingHorizontal(line []rune) []rune {
	i := 0
	for i < len(line) && horizontalWhiteSpace[line[i]] {
		i++
	}
	return line[i:]
}

// foldInlineNewlines turns each run of line endings inside an inline span,
// together with any horizontal whitespace after it, into one space. That is
// what makes an inline span rewrap-safe, and it is the difference between the
// two backtick-delimited kinds: an inline span carries no line structure, a
// fence does.
func foldInlineNewlines(body string) string {
	runes := []rune(body)
	var b strings.Builder
	for i := 0; i < len(runes); {
		if runes[i] != '\n' {
			b.WriteRune(runes[i])
			i++
			continue
		}
		for i < len(runes) && (runes[i] == '\n' || horizontalWhiteSpace[runes[i]]) {
			i++
		}
		b.WriteRune(' ')
	}
	return b.String()
}

func asciiLowerString(text string) string {
	var b strings.Builder
	for _, r := range text {
		b.WriteRune(asciiLower(r))
	}
	return b.String()
}

// lowerDataHeader lowercases what RFC 2045 section 5.1 defines as
// case-insensitive and nothing else: the type, the subtype and each
// parameter's attribute NAME. A value is not case-insensitive in general --
// charset happens to be, but that is RFC 2046 speaking about one parameter --
// so a value is reproduced exactly. ";base64" is an attribute name with no
// value and folds with them.
func lowerDataHeader(header string) string {
	parts := strings.Split(header, ";")
	for i, part := range parts {
		if i == 0 {
			parts[i] = asciiLowerString(part)
			continue
		}
		if eq := strings.Index(part, "="); eq >= 0 {
			parts[i] = asciiLowerString(part[:eq]) + part[eq:]
		} else {
			parts[i] = asciiLowerString(part)
		}
	}
	return strings.Join(parts, ";")
}

// normalizeURI lowercases the scheme, and the host of a URI that has an
// authority; RFC 3986 defines both as case-insensitive. A data: URI carries
// its own case-insensitive fields, defined by RFC 2045. Nothing else folds.
func normalizeURI(body string) string {
	if i := strings.Index(body, "://"); i > 0 {
		scheme := body[:i]
		rest := body[i+3:]
		end := strings.IndexAny(rest, "/?#")
		if end < 0 {
			end = len(rest)
		}
		authority, tail := rest[:end], rest[end:]
		userinfo := ""
		if at := strings.LastIndex(authority, "@"); at >= 0 {
			userinfo, authority = authority[:at+1], authority[at+1:]
		}
		return asciiLowerString(scheme) + "://" + userinfo + asciiLowerString(authority) + tail
	}
	colon := strings.Index(body, ":")
	if colon < 0 {
		return body
	}
	scheme := asciiLowerString(body[:colon])
	if scheme != "data" {
		return scheme + body[colon:]
	}
	comma := strings.Index(body[colon+1:], ",")
	if comma < 0 {
		return scheme + body[colon:]
	}
	comma += colon + 1
	return scheme + ":" + lowerDataHeader(body[colon+1:comma]) + body[comma:]
}

// normalizeSpan: a protected span is not untouched bytes. It is text
// canonicalized under a reduced rule set, and the line is that line structure
// belongs to the channel while everything else belongs to the author.
func normalizeSpan(kind spanKind, body string) string {
	switch kind {
	case fenceSpan:
		return normalizeFenceIndent(body)
	case inlineSpan:
		return foldInlineNewlines(body)
	case urlSpan:
		return normalizeURI(body)
	}
	return body
}

func protect(text []rune) (string, map[string]string) {
	spans := opaqueSpans(text)
	if len(spans) == 0 {
		return string(text), nil
	}
	var b strings.Builder
	protected := make(map[string]string, len(spans))
	cursor := 0
	for number, s := range spans {
		marker := string(markerOpen) + "CQT" + strconv.Itoa(number) + string(markerClose)
		b.WriteString(string(text[cursor:s.start]))
		b.WriteString(marker)
		protected[marker] = normalizeSpan(s.kind, string(text[s.start:s.end]))
		cursor = s.end
	}
	b.WriteString(string(text[cursor:]))
	return b.String(), protected
}

// restore puts every protected span back exactly where its placeholder is.
//
// A run that merely looks like a placeholder but names no span is left alone.
// Step 2 has already removed every Cc scalar, so no such run can survive from
// the input and this is defence in depth rather than a reachable case; CQT is
// total and has no error conditions, so it passes through unchanged.
func restore(text string, protected map[string]string) string {
	if len(protected) == 0 {
		return text
	}
	runes := []rune(text)
	var b strings.Builder
	for i := 0; i < len(runes); {
		if runes[i] == markerOpen && i+4 < len(runes) &&
			runes[i+1] == 'C' && runes[i+2] == 'Q' && runes[i+3] == 'T' {
			k := i + 4
			for k < len(runes) && runes[k] >= '0' && runes[k] <= '9' {
				k++
			}
			if k > i+4 && k < len(runes) && runes[k] == markerClose {
				if body, ok := protected[string(runes[i:k+1])]; ok {
					b.WriteString(body)
					i = k + 1
					continue
				}
			}
		}
		b.WriteRune(runes[i])
		i++
	}
	return b.String()
}

// collapseWhitespace is step 6: replace each run of White_Space with a single
// U+0020, then trim leading and trailing spaces.
// collapseWhitespace is step 6.2: a run of whitespace becomes one space, or
// one line ending if the run contains one. Step 6.1 has already joined every
// line within a passage, so the only line endings left at this point are the
// boundaries it chose to keep, and those carry meaning a space would destroy.
// Step 6.3 then trims both from the edges.
func collapseWhitespace(text string) string {
	var b strings.Builder
	runLength, runHasNewline := 0, false
	flush := func() {
		if runLength == 0 {
			return
		}
		if runHasNewline {
			b.WriteRune('\n')
		} else {
			b.WriteRune(' ')
		}
		runLength, runHasNewline = 0, false
	}
	for _, r := range text {
		if whiteSpace[r] {
			runLength++
			if r == '\n' {
				runHasNewline = true
			}
			continue
		}
		flush()
		b.WriteRune(r)
	}
	flush()
	return strings.Trim(b.String(), " \n")
}

// removeInvisibles is step 5: drop the four layout-only characters.
//
// U+200B survives between two scalars from a script that does not separate
// words with spaces, where it is the word separator rather than an artifact.
// Both neighbours must qualify, so a stray U+200B injected at a script boundary
// by a mailer or sanitizer is still removed.
func removeInvisibles(text string) string {
	runes := []rune(text)
	var b strings.Builder
	for i, r := range runes {
		if !removedInvisibles[r] {
			b.WriteRune(r)
			continue
		}
		if r == zeroWidthSpace && i > 0 && i+1 < len(runes) &&
			SpacelessScripts[runes[i-1]] && SpacelessScripts[runes[i+1]] {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// removeSpacesAdjacentToPunctuation is step 7.9: attach punctuation to the side
// it belongs to.
//
// Punctuation is not symmetric. Opening punctuation binds to what follows it
// and closing, final and terminal punctuation bind to what precedes, so a space
// is removed on the side the punctuation attaches to and left alone on the
// other. That keeps "ignorance, up" and "name: value" intact while still
// converging "hello :)" and "hello U+1F60A" on "hello:-)", which is what this
// rule exists to do.
func removeSpacesAdjacentToPunctuation(text string) string {
	runes := []rune(text)
	var b strings.Builder
	for i := 0; i < len(runes); {
		if runes[i] != ' ' {
			b.WriteRune(runes[i])
			i++
			continue
		}
		runEnd := i
		for runEnd < len(runes) && runes[runEnd] == ' ' {
			runEnd++
		}
		attachesLeft := runEnd < len(runes) && (TerminalPunctuation[runes[runEnd]] ||
			unicode.Is(unicode.Pe, runes[runEnd]) || unicode.Is(unicode.Pf, runes[runEnd]))
		attachesRight := i > 0 && (unicode.Is(unicode.Ps, runes[i-1]) ||
			unicode.Is(unicode.Pi, runes[i-1]))
		if !attachesLeft && !attachesRight {
			b.WriteRune(' ')
		}
		i = runEnd
	}
	return b.String()
}

// mapRunes applies a per-scalar substitution.
func mapRunes(text string, replacement func(rune) (rune, bool)) string {
	var b strings.Builder
	for _, r := range text {
		if to, ok := replacement(r); ok {
			b.WriteRune(to)
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}

// collapseRun replaces every run of least or more copies of r with with.
func collapseRun(text string, r rune, least int, with string) string {
	runes := []rune(text)
	var b strings.Builder
	for i := 0; i < len(runes); {
		if runes[i] != r {
			b.WriteRune(runes[i])
			i++
			continue
		}
		runEnd := i
		for runEnd < len(runes) && runes[runEnd] == r {
			runEnd++
		}
		if runEnd-i >= least {
			b.WriteString(with)
		} else {
			b.WriteString(string(runes[i:runEnd]))
		}
		i = runEnd
	}
	return b.String()
}

// compositionTableData is the Unicode 17.0.0 set of primary composites: every
// (starter, second) pair that canonical composition maps onto a single scalar,
// minus the Hangul syllables, which are arithmetic rather than data. Derived
// from UnicodeData.txt by keeping each scalar whose canonical decomposition is
// two scalars, whose first is a starter, and which is not a composition
// exclusion. Three comma-separated hex fields per entry: first, second,
// composite.
const compositionTableData = `
3C,338,226E 3D,338,2260 3E,338,226F 41,300,C0 41,301,C1 41,302,C2
41,303,C3 41,304,100 41,306,102 41,307,226 41,308,C4 41,309,1EA2 41,30A,C5
41,30C,1CD 41,30F,200 41,311,202 41,323,1EA0 41,325,1E00 41,328,104
42,307,1E02 42,323,1E04 42,331,1E06 43,301,106 43,302,108 43,307,10A
43,30C,10C 43,327,C7 44,307,1E0A 44,30C,10E 44,323,1E0C 44,327,1E10
44,32D,1E12 44,331,1E0E 45,300,C8 45,301,C9 45,302,CA 45,303,1EBC
45,304,112 45,306,114 45,307,116 45,308,CB 45,309,1EBA 45,30C,11A
45,30F,204 45,311,206 45,323,1EB8 45,327,228 45,328,118 45,32D,1E18
45,330,1E1A 46,307,1E1E 47,301,1F4 47,302,11C 47,304,1E20 47,306,11E
47,307,120 47,30C,1E6 47,327,122 48,302,124 48,307,1E22 48,308,1E26
48,30C,21E 48,323,1E24 48,327,1E28 48,32E,1E2A 49,300,CC 49,301,CD
49,302,CE 49,303,128 49,304,12A 49,306,12C 49,307,130 49,308,CF
49,309,1EC8 49,30C,1CF 49,30F,208 49,311,20A 49,323,1ECA 49,328,12E
49,330,1E2C 4A,302,134 4B,301,1E30 4B,30C,1E8 4B,323,1E32 4B,327,136
4B,331,1E34 4C,301,139 4C,30C,13D 4C,323,1E36 4C,327,13B 4C,32D,1E3C
4C,331,1E3A 4D,301,1E3E 4D,307,1E40 4D,323,1E42 4E,300,1F8 4E,301,143
4E,303,D1 4E,307,1E44 4E,30C,147 4E,323,1E46 4E,327,145 4E,32D,1E4A
4E,331,1E48 4F,300,D2 4F,301,D3 4F,302,D4 4F,303,D5 4F,304,14C 4F,306,14E
4F,307,22E 4F,308,D6 4F,309,1ECE 4F,30B,150 4F,30C,1D1 4F,30F,20C
4F,311,20E 4F,31B,1A0 4F,323,1ECC 4F,328,1EA 50,301,1E54 50,307,1E56
52,301,154 52,307,1E58 52,30C,158 52,30F,210 52,311,212 52,323,1E5A
52,327,156 52,331,1E5E 53,301,15A 53,302,15C 53,307,1E60 53,30C,160
53,323,1E62 53,326,218 53,327,15E 54,307,1E6A 54,30C,164 54,323,1E6C
54,326,21A 54,327,162 54,32D,1E70 54,331,1E6E 55,300,D9 55,301,DA
55,302,DB 55,303,168 55,304,16A 55,306,16C 55,308,DC 55,309,1EE6
55,30A,16E 55,30B,170 55,30C,1D3 55,30F,214 55,311,216 55,31B,1AF
55,323,1EE4 55,324,1E72 55,328,172 55,32D,1E76 55,330,1E74 56,303,1E7C
56,323,1E7E 57,300,1E80 57,301,1E82 57,302,174 57,307,1E86 57,308,1E84
57,323,1E88 58,307,1E8A 58,308,1E8C 59,300,1EF2 59,301,DD 59,302,176
59,303,1EF8 59,304,232 59,307,1E8E 59,308,178 59,309,1EF6 59,323,1EF4
5A,301,179 5A,302,1E90 5A,307,17B 5A,30C,17D 5A,323,1E92 5A,331,1E94
61,300,E0 61,301,E1 61,302,E2 61,303,E3 61,304,101 61,306,103 61,307,227
61,308,E4 61,309,1EA3 61,30A,E5 61,30C,1CE 61,30F,201 61,311,203
61,323,1EA1 61,325,1E01 61,328,105 62,307,1E03 62,323,1E05 62,331,1E07
63,301,107 63,302,109 63,307,10B 63,30C,10D 63,327,E7 64,307,1E0B
64,30C,10F 64,323,1E0D 64,327,1E11 64,32D,1E13 64,331,1E0F 65,300,E8
65,301,E9 65,302,EA 65,303,1EBD 65,304,113 65,306,115 65,307,117 65,308,EB
65,309,1EBB 65,30C,11B 65,30F,205 65,311,207 65,323,1EB9 65,327,229
65,328,119 65,32D,1E19 65,330,1E1B 66,307,1E1F 67,301,1F5 67,302,11D
67,304,1E21 67,306,11F 67,307,121 67,30C,1E7 67,327,123 68,302,125
68,307,1E23 68,308,1E27 68,30C,21F 68,323,1E25 68,327,1E29 68,32E,1E2B
68,331,1E96 69,300,EC 69,301,ED 69,302,EE 69,303,129 69,304,12B 69,306,12D
69,308,EF 69,309,1EC9 69,30C,1D0 69,30F,209 69,311,20B 69,323,1ECB
69,328,12F 69,330,1E2D 6A,302,135 6A,30C,1F0 6B,301,1E31 6B,30C,1E9
6B,323,1E33 6B,327,137 6B,331,1E35 6C,301,13A 6C,30C,13E 6C,323,1E37
6C,327,13C 6C,32D,1E3D 6C,331,1E3B 6D,301,1E3F 6D,307,1E41 6D,323,1E43
6E,300,1F9 6E,301,144 6E,303,F1 6E,307,1E45 6E,30C,148 6E,323,1E47
6E,327,146 6E,32D,1E4B 6E,331,1E49 6F,300,F2 6F,301,F3 6F,302,F4 6F,303,F5
6F,304,14D 6F,306,14F 6F,307,22F 6F,308,F6 6F,309,1ECF 6F,30B,151
6F,30C,1D2 6F,30F,20D 6F,311,20F 6F,31B,1A1 6F,323,1ECD 6F,328,1EB
70,301,1E55 70,307,1E57 72,301,155 72,307,1E59 72,30C,159 72,30F,211
72,311,213 72,323,1E5B 72,327,157 72,331,1E5F 73,301,15B 73,302,15D
73,307,1E61 73,30C,161 73,323,1E63 73,326,219 73,327,15F 74,307,1E6B
74,308,1E97 74,30C,165 74,323,1E6D 74,326,21B 74,327,163 74,32D,1E71
74,331,1E6F 75,300,F9 75,301,FA 75,302,FB 75,303,169 75,304,16B 75,306,16D
75,308,FC 75,309,1EE7 75,30A,16F 75,30B,171 75,30C,1D4 75,30F,215
75,311,217 75,31B,1B0 75,323,1EE5 75,324,1E73 75,328,173 75,32D,1E77
75,330,1E75 76,303,1E7D 76,323,1E7F 77,300,1E81 77,301,1E83 77,302,175
77,307,1E87 77,308,1E85 77,30A,1E98 77,323,1E89 78,307,1E8B 78,308,1E8D
79,300,1EF3 79,301,FD 79,302,177 79,303,1EF9 79,304,233 79,307,1E8F
79,308,FF 79,309,1EF7 79,30A,1E99 79,323,1EF5 7A,301,17A 7A,302,1E91
7A,307,17C 7A,30C,17E 7A,323,1E93 7A,331,1E95 A8,300,1FED A8,301,385
A8,342,1FC1 C2,300,1EA6 C2,301,1EA4 C2,303,1EAA C2,309,1EA8 C4,304,1DE
C5,301,1FA C6,301,1FC C6,304,1E2 C7,301,1E08 CA,300,1EC0 CA,301,1EBE
CA,303,1EC4 CA,309,1EC2 CF,301,1E2E D4,300,1ED2 D4,301,1ED0 D4,303,1ED6
D4,309,1ED4 D5,301,1E4C D5,304,22C D5,308,1E4E D6,304,22A D8,301,1FE
DC,300,1DB DC,301,1D7 DC,304,1D5 DC,30C,1D9 E2,300,1EA7 E2,301,1EA5
E2,303,1EAB E2,309,1EA9 E4,304,1DF E5,301,1FB E6,301,1FD E6,304,1E3
E7,301,1E09 EA,300,1EC1 EA,301,1EBF EA,303,1EC5 EA,309,1EC3 EF,301,1E2F
F4,300,1ED3 F4,301,1ED1 F4,303,1ED7 F4,309,1ED5 F5,301,1E4D F5,304,22D
F5,308,1E4F F6,304,22B F8,301,1FF FC,300,1DC FC,301,1D8 FC,304,1D6
FC,30C,1DA 102,300,1EB0 102,301,1EAE 102,303,1EB4 102,309,1EB2
103,300,1EB1 103,301,1EAF 103,303,1EB5 103,309,1EB3 112,300,1E14
112,301,1E16 113,300,1E15 113,301,1E17 14C,300,1E50 14C,301,1E52
14D,300,1E51 14D,301,1E53 15A,307,1E64 15B,307,1E65 160,307,1E66
161,307,1E67 168,301,1E78 169,301,1E79 16A,308,1E7A 16B,308,1E7B
17F,307,1E9B 1A0,300,1EDC 1A0,301,1EDA 1A0,303,1EE0 1A0,309,1EDE
1A0,323,1EE2 1A1,300,1EDD 1A1,301,1EDB 1A1,303,1EE1 1A1,309,1EDF
1A1,323,1EE3 1AF,300,1EEA 1AF,301,1EE8 1AF,303,1EEE 1AF,309,1EEC
1AF,323,1EF0 1B0,300,1EEB 1B0,301,1EE9 1B0,303,1EEF 1B0,309,1EED
1B0,323,1EF1 1B7,30C,1EE 1EA,304,1EC 1EB,304,1ED 226,304,1E0 227,304,1E1
228,306,1E1C 229,306,1E1D 22E,304,230 22F,304,231 292,30C,1EF 391,300,1FBA
391,301,386 391,304,1FB9 391,306,1FB8 391,313,1F08 391,314,1F09
391,345,1FBC 395,300,1FC8 395,301,388 395,313,1F18 395,314,1F19
397,300,1FCA 397,301,389 397,313,1F28 397,314,1F29 397,345,1FCC
399,300,1FDA 399,301,38A 399,304,1FD9 399,306,1FD8 399,308,3AA
399,313,1F38 399,314,1F39 39F,300,1FF8 39F,301,38C 39F,313,1F48
39F,314,1F49 3A1,314,1FEC 3A5,300,1FEA 3A5,301,38E 3A5,304,1FE9
3A5,306,1FE8 3A5,308,3AB 3A5,314,1F59 3A9,300,1FFA 3A9,301,38F
3A9,313,1F68 3A9,314,1F69 3A9,345,1FFC 3AC,345,1FB4 3AE,345,1FC4
3B1,300,1F70 3B1,301,3AC 3B1,304,1FB1 3B1,306,1FB0 3B1,313,1F00
3B1,314,1F01 3B1,342,1FB6 3B1,345,1FB3 3B5,300,1F72 3B5,301,3AD
3B5,313,1F10 3B5,314,1F11 3B7,300,1F74 3B7,301,3AE 3B7,313,1F20
3B7,314,1F21 3B7,342,1FC6 3B7,345,1FC3 3B9,300,1F76 3B9,301,3AF
3B9,304,1FD1 3B9,306,1FD0 3B9,308,3CA 3B9,313,1F30 3B9,314,1F31
3B9,342,1FD6 3BF,300,1F78 3BF,301,3CC 3BF,313,1F40 3BF,314,1F41
3C1,313,1FE4 3C1,314,1FE5 3C5,300,1F7A 3C5,301,3CD 3C5,304,1FE1
3C5,306,1FE0 3C5,308,3CB 3C5,313,1F50 3C5,314,1F51 3C5,342,1FE6
3C9,300,1F7C 3C9,301,3CE 3C9,313,1F60 3C9,314,1F61 3C9,342,1FF6
3C9,345,1FF3 3CA,300,1FD2 3CA,301,390 3CA,342,1FD7 3CB,300,1FE2
3CB,301,3B0 3CB,342,1FE7 3CE,345,1FF4 3D2,301,3D3 3D2,308,3D4 406,308,407
410,306,4D0 410,308,4D2 413,301,403 415,300,400 415,306,4D6 415,308,401
416,306,4C1 416,308,4DC 417,308,4DE 418,300,40D 418,304,4E2 418,306,419
418,308,4E4 41A,301,40C 41E,308,4E6 423,304,4EE 423,306,40E 423,308,4F0
423,30B,4F2 427,308,4F4 42B,308,4F8 42D,308,4EC 430,306,4D1 430,308,4D3
433,301,453 435,300,450 435,306,4D7 435,308,451 436,306,4C2 436,308,4DD
437,308,4DF 438,300,45D 438,304,4E3 438,306,439 438,308,4E5 43A,301,45C
43E,308,4E7 443,304,4EF 443,306,45E 443,308,4F1 443,30B,4F3 447,308,4F5
44B,308,4F9 44D,308,4ED 456,308,457 474,30F,476 475,30F,477 4D8,308,4DA
4D9,308,4DB 4E8,308,4EA 4E9,308,4EB 627,653,622 627,654,623 627,655,625
648,654,624 64A,654,626 6C1,654,6C2 6D2,654,6D3 6D5,654,6C0 928,93C,929
930,93C,931 933,93C,934 9C7,9BE,9CB 9C7,9D7,9CC B47,B3E,B4B B47,B56,B48
B47,B57,B4C B92,BD7,B94 BC6,BBE,BCA BC6,BD7,BCC BC7,BBE,BCB C46,C56,C48
CBF,CD5,CC0 CC6,CC2,CCA CC6,CD5,CC7 CC6,CD6,CC8 CCA,CD5,CCB D46,D3E,D4A
D46,D57,D4C D47,D3E,D4B DD9,DCA,DDA DD9,DCF,DDC DD9,DDF,DDE DDC,DCA,DDD
1025,102E,1026 1B05,1B35,1B06 1B07,1B35,1B08 1B09,1B35,1B0A 1B0B,1B35,1B0C
1B0D,1B35,1B0E 1B11,1B35,1B12 1B3A,1B35,1B3B 1B3C,1B35,1B3D 1B3E,1B35,1B40
1B3F,1B35,1B41 1B42,1B35,1B43 1E36,304,1E38 1E37,304,1E39 1E5A,304,1E5C
1E5B,304,1E5D 1E62,307,1E68 1E63,307,1E69 1EA0,302,1EAC 1EA0,306,1EB6
1EA1,302,1EAD 1EA1,306,1EB7 1EB8,302,1EC6 1EB9,302,1EC7 1ECC,302,1ED8
1ECD,302,1ED9 1F00,300,1F02 1F00,301,1F04 1F00,342,1F06 1F00,345,1F80
1F01,300,1F03 1F01,301,1F05 1F01,342,1F07 1F01,345,1F81 1F02,345,1F82
1F03,345,1F83 1F04,345,1F84 1F05,345,1F85 1F06,345,1F86 1F07,345,1F87
1F08,300,1F0A 1F08,301,1F0C 1F08,342,1F0E 1F08,345,1F88 1F09,300,1F0B
1F09,301,1F0D 1F09,342,1F0F 1F09,345,1F89 1F0A,345,1F8A 1F0B,345,1F8B
1F0C,345,1F8C 1F0D,345,1F8D 1F0E,345,1F8E 1F0F,345,1F8F 1F10,300,1F12
1F10,301,1F14 1F11,300,1F13 1F11,301,1F15 1F18,300,1F1A 1F18,301,1F1C
1F19,300,1F1B 1F19,301,1F1D 1F20,300,1F22 1F20,301,1F24 1F20,342,1F26
1F20,345,1F90 1F21,300,1F23 1F21,301,1F25 1F21,342,1F27 1F21,345,1F91
1F22,345,1F92 1F23,345,1F93 1F24,345,1F94 1F25,345,1F95 1F26,345,1F96
1F27,345,1F97 1F28,300,1F2A 1F28,301,1F2C 1F28,342,1F2E 1F28,345,1F98
1F29,300,1F2B 1F29,301,1F2D 1F29,342,1F2F 1F29,345,1F99 1F2A,345,1F9A
1F2B,345,1F9B 1F2C,345,1F9C 1F2D,345,1F9D 1F2E,345,1F9E 1F2F,345,1F9F
1F30,300,1F32 1F30,301,1F34 1F30,342,1F36 1F31,300,1F33 1F31,301,1F35
1F31,342,1F37 1F38,300,1F3A 1F38,301,1F3C 1F38,342,1F3E 1F39,300,1F3B
1F39,301,1F3D 1F39,342,1F3F 1F40,300,1F42 1F40,301,1F44 1F41,300,1F43
1F41,301,1F45 1F48,300,1F4A 1F48,301,1F4C 1F49,300,1F4B 1F49,301,1F4D
1F50,300,1F52 1F50,301,1F54 1F50,342,1F56 1F51,300,1F53 1F51,301,1F55
1F51,342,1F57 1F59,300,1F5B 1F59,301,1F5D 1F59,342,1F5F 1F60,300,1F62
1F60,301,1F64 1F60,342,1F66 1F60,345,1FA0 1F61,300,1F63 1F61,301,1F65
1F61,342,1F67 1F61,345,1FA1 1F62,345,1FA2 1F63,345,1FA3 1F64,345,1FA4
1F65,345,1FA5 1F66,345,1FA6 1F67,345,1FA7 1F68,300,1F6A 1F68,301,1F6C
1F68,342,1F6E 1F68,345,1FA8 1F69,300,1F6B 1F69,301,1F6D 1F69,342,1F6F
1F69,345,1FA9 1F6A,345,1FAA 1F6B,345,1FAB 1F6C,345,1FAC 1F6D,345,1FAD
1F6E,345,1FAE 1F6F,345,1FAF 1F70,345,1FB2 1F74,345,1FC2 1F7C,345,1FF2
1FB6,345,1FB7 1FBF,300,1FCD 1FBF,301,1FCE 1FBF,342,1FCF 1FC6,345,1FC7
1FF6,345,1FF7 1FFE,300,1FDD 1FFE,301,1FDE 1FFE,342,1FDF 2190,338,219A
2192,338,219B 2194,338,21AE 21D0,338,21CD 21D2,338,21CF 21D4,338,21CE
2203,338,2204 2208,338,2209 220B,338,220C 2223,338,2224 2225,338,2226
223C,338,2241 2243,338,2244 2245,338,2247 2248,338,2249 224D,338,226D
2261,338,2262 2264,338,2270 2265,338,2271 2272,338,2274 2273,338,2275
2276,338,2278 2277,338,2279 227A,338,2280 227B,338,2281 227C,338,22E0
227D,338,22E1 2282,338,2284 2283,338,2285 2286,338,2288 2287,338,2289
2291,338,22E2 2292,338,22E3 22A2,338,22AC 22A8,338,22AD 22A9,338,22AE
22AB,338,22AF 22B2,338,22EA 22B3,338,22EB 22B4,338,22EC 22B5,338,22ED
3046,3099,3094 304B,3099,304C 304D,3099,304E 304F,3099,3050 3051,3099,3052
3053,3099,3054 3055,3099,3056 3057,3099,3058 3059,3099,305A 305B,3099,305C
305D,3099,305E 305F,3099,3060 3061,3099,3062 3064,3099,3065 3066,3099,3067
3068,3099,3069 306F,3099,3070 306F,309A,3071 3072,3099,3073 3072,309A,3074
3075,3099,3076 3075,309A,3077 3078,3099,3079 3078,309A,307A 307B,3099,307C
307B,309A,307D 309D,3099,309E 30A6,3099,30F4 30AB,3099,30AC 30AD,3099,30AE
30AF,3099,30B0 30B1,3099,30B2 30B3,3099,30B4 30B5,3099,30B6 30B7,3099,30B8
30B9,3099,30BA 30BB,3099,30BC 30BD,3099,30BE 30BF,3099,30C0 30C1,3099,30C2
30C4,3099,30C5 30C6,3099,30C7 30C8,3099,30C9 30CF,3099,30D0 30CF,309A,30D1
30D2,3099,30D3 30D2,309A,30D4 30D5,3099,30D6 30D5,309A,30D7 30D8,3099,30D9
30D8,309A,30DA 30DB,3099,30DC 30DB,309A,30DD 30EF,3099,30F7 30F0,3099,30F8
30F1,3099,30F9 30F2,3099,30FA 30FD,3099,30FE 105D2,307,105C9
105DA,307,105E4 11099,110BA,1109A 1109B,110BA,1109C 110A5,110BA,110AB
11131,11127,1112E 11132,11127,1112F 11347,1133E,1134B 11347,11357,1134C
11382,113C9,11383 11384,113BB,11385 1138B,113C2,1138E 11390,113C9,11391
113C2,113B8,113C7 113C2,113C2,113C5 113C2,113C9,113C8 114B9,114B0,114BC
114B9,114BA,114BB 114B9,114BD,114BE 115B8,115AF,115BA 115B9,115AF,115BB
11935,11930,11938 1611E,1611E,16121 1611E,1611F,16123 1611E,16120,16125
1611E,16129,16122 16121,1611F,16126 16121,16120,16128 16122,1611F,16127
16129,1611F,16124 16D63,16D67,16D69 16D67,16D67,16D68 16D69,16D67,16D6A
`

var compositionTable = parseCompositionTable(compositionTableData)

func parseCompositionTable(data string) map[[2]rune]rune {
	out := make(map[[2]rune]rune)
	for _, entry := range strings.Fields(data) {
		fields := strings.Split(entry, ",")
		if len(fields) != 3 {
			panic("cqt: malformed composition table entry " + entry)
		}
		var scalars [3]rune
		for i, field := range fields {
			cp, err := strconv.ParseInt(field, 16, 32)
			if err != nil {
				panic("cqt: malformed composition table entry " + entry)
			}
			scalars[i] = rune(cp)
		}
		out[[2]rune{scalars[0], scalars[1]}] = scalars[2]
	}
	return out
}

// The Hangul syllables compose arithmetically, per UAX #15 section X6.
const (
	hangulSBase  = 0xAC00
	hangulLBase  = 0x1100
	hangulVBase  = 0x1161
	hangulTBase  = 0x11A7
	hangulLCount = 19
	hangulVCount = 21
	hangulTCount = 28
	hangulSCount = hangulLCount * hangulVCount * hangulTCount
)

// primaryComposite reports the single scalar that canonical composition maps
// (a, b) onto, if there is one.
func primaryComposite(a, b rune) (rune, bool) {
	if a >= hangulLBase && a < hangulLBase+hangulLCount &&
		b >= hangulVBase && b < hangulVBase+hangulVCount {
		return hangulSBase + ((a-hangulLBase)*hangulVCount+(b-hangulVBase))*hangulTCount, true
	}
	if a >= hangulSBase && a < hangulSBase+hangulSCount &&
		(a-hangulSBase)%hangulTCount == 0 &&
		b > hangulTBase && b < hangulTBase+hangulTCount {
		return a + (b - hangulTBase), true
	}
	composed, ok := compositionTable[[2]rune{a, b}]
	return composed, ok
}

// combiningClass is the Canonical_Combining_Class of r. x/text's trie is right
// here for every scalar, astral ones included; it is only the recomposition
// step that this package declines to use.
func combiningClass(r rune) int {
	var buf [utf8.UTFMax]byte
	n := utf8.EncodeRune(buf[:], r)
	return int(norm.NFC.Properties(buf[:n]).CCC())
}

// canonicalCompose is the composition half of NFKC, per UAX #15 section X5 as
// amended by Corrigendum #5: in a sequence beginning with starter S, a scalar C
// is blocked from S when some scalar B lies between them and B is either a
// starter or has a combining class greater than or equal to C's.
func canonicalCompose(runes []rune) []rune {
	out := make([]rune, 0, len(runes))
	starter := -1 // index in out of the starter currently accumulating
	between := -1 // combining class of the last scalar appended after it
	for _, r := range runes {
		class := combiningClass(r)
		if starter >= 0 && between < class {
			if composed, ok := primaryComposite(out[starter], r); ok {
				out[starter] = composed
				continue
			}
		}
		if class == 0 {
			starter = len(out)
			between = -1
		} else {
			between = class
		}
		out = append(out, r)
	}
	return out
}

// nfkc is step 4.
//
// It is deliberately NOT golang.org/x/text/unicode/norm's NFKC. That package's
// recomposition builds its lookup key by clipping both scalars to 16 bits --
// forminfo.go: key := uint32(uint16(a))<<16 + uint32(uint16(b)) -- with no
// domain check on a. An astral starter therefore hits the entry belonging to an
// unrelated BMP pair, so NFKC("a" + U+10041 + U+0301) returns "a" + U+00C1: a
// Linear B syllable is deleted and a Latin capital appears in its place. The
// same clipping runs in reverse, because astral entries are stored under
// clipped keys, so NFKC(U+05D2 U+0307) returns the Todhri letter U+105C9 from
// Hebrew input. Decomposition and canonical ordering are unaffected, verified
// scalar by scalar against the reference, and remain x/text's work; only the
// composition happens here.
func nfkc(text string) string {
	return string(canonicalCompose([]rune(norm.NFKD.String(text))))
}

// canonicalizeProse runs steps 4 through 7, once each, in order.
//
// The autocorrect tables run before space removal. A client that swaps an emoji
// for its emoticon spelling, or the reverse, is exactly the kind of tooling
// transformation CQT exists to survive, so "hello <emoji>", "hello :)" and
// "hello :-)" must all reach the same bytes. Mapping to the canonical spelling
// first puts a colon where the space rule can see it.
//
// The cost of a single pass is that ": )" ends at ":)" rather than ":-)", since
// nothing revisits the tables after the space closes the gap. That is an oddity
// somebody typed, not something a tool did to their text.
func canonicalizeProse(text string) string {
	text = nfkc(text)
	text = removeInvisibles(text)
	text = normalizeQuotation(text)
	text = collapseWhitespace(text)
	text = mapRunes(text, func(r rune) (rune, bool) {
		if DashPunctuation[r] {
			return '-', true
		}
		return 0, false
	})
	text = collapseRun(text, '-', 2, "-")
	text = strings.ReplaceAll(text, "、", ",")
	text = strings.ReplaceAll(text, "。", ".")
	text = strings.ReplaceAll(text, "…", "...")
	text = collapseRun(text, '.', 4, "...")
	text = strings.ReplaceAll(text, "⁄", "/")
	text = mapRunes(text, func(r rune) (rune, bool) {
		if quoteCharacters[r] {
			return '\'', true
		}
		return 0, false
	})
	for _, pair := range autocorrectPairs {
		text = strings.ReplaceAll(text, pair.from, pair.to)
	}
	for _, pair := range asciiAutocorrectPairs {
		text = strings.ReplaceAll(text, pair.from, pair.to)
	}
	text = applyGuardedEmoticons(text)
	text = removeSpacesAdjacentToPunctuation(text)
	text = strings.ReplaceAll(text, "&", " & ")
	return collapseWhitespace(text)
}

// Algorithm317 returns the CQT 3.17 canonical UTF-8 byte stream for plaintext.
func Algorithm317(plaintext string) []byte {
	// Strip what cannot be plain text BEFORE recognizing anything. Otherwise an
	// override hidden inside a fence or a URL is copied through untouched, and
	// the span becomes a channel for exactly the spoof this removal prevents.
	runes := stripDisallowed(decode(plaintext))
	runes = removeArtifacts(runes)
	runes = normalizeLineTerminators(runes)
	runes = rightTrimLines(runes)
	text, protected := protect(runes)
	text = canonicalizeProse(text)
	return []byte(restore(text, protected))
}
