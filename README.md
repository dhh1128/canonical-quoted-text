# CQT
This is a spec for a simple but powerful algorithm for canonicalizing chunks of text that flow not via files but via chat, copy/paste, or other non-file-oriented channels (social media, SMS, email, etc.).

## Try it out!
You can use an [interactive form to run the algorithm on arbitrary text](https://dhh1128.github.io/canonical-quoted-text/form.html).

## Implementations
Each implementation lives in its own directory under [impl/](impl), with a test harness beside it that runs the normative vectors in [goldens/cqt2.17.json](goldens/cqt2.17.json). A reference implementation is in [python](impl/python/cqt.py); see also [javascript](impl/js/cqt.js), [java](impl/java/Cqt.java), [go](impl/go/cqt.go), [rust](impl/rust/cqt.rs), and [swift](impl/swift/Cqt.swift). Whether any given implementation conforms is a question the vectors answer; see [Conformance](#conformance). Code is in the public domain; see [LICENSE](https://github.com/dhh1128/canonical-quoted-text/blob/main/LICENSE).

## Purpose
Cryptographic hashes and signatures are usually applied to files or data structures. However, a very important category of communication is not file-oriented. In our modern world, lots of text moves across system boundaries using mechanisms that are prone to reformatting and error due to their inherent fuzziness. We see a post on social media on our phones, copy it, and paste it into a text to a friend. She emails it to a journalist acquaintance, who moves it into a word processor that is configured to use a different locale with different autocorrect and punctuation settings. Eventually, a student cites the journalist in a paper they're writing. Somewhere along the way, whitespace is deleted, capitalization or spelling is altered, the codepage changes, smart quotes turn into dumb quotes or two hyphens become an em dash.

In this scenario, how can we evaluate whether the final text is *the same* as the original?

Of course, opinions about what constitutes *sameness* vary. There is no objectively correct answer. However, we can create *deterministic* answers that are useful. They can help us decide whether minor text changes are likely to matter, and check to see whether a digital signature matches a piece of text.

The algorithm documented here is for such cases. It says that two chunks of text are *the same* if, when transformed by the algorithm, they produce output that matches byte-for-byte.

Sometimes a quotation contains a fragment that must survive exactly &mdash; a command, a hash, a snippet of code. Such a fragment is not human-friendly text at all; it is machine-readable syntax, and the transformations that make prose comparable would destroy it. CQT 2.17 adds a way to mark those fragments so they are set aside, left alone, and put back untouched. See [Protected content](#protected-content).

## Official name and version

The full name of this algorithm is "canonical quoted text 2.17", but it is typically abbreviated "cqt2.17".

The name contains two numbers. The first number ("2") versions the logic of the algorithm, and the second number ("17") references the version of the Unicode standard that documents certain details. CQT 1.14 is a different algorithm; see [Conformance](#conformance).

Unlike 1.14, the Unicode number is exact rather than approximate. Every operation below that consults the Unicode Character Database MUST use Unicode 17.0.0, and an implementation MUST NOT substitute whatever version its runtime happens to ship. The reference implementation depends on `unicodedata2==17.0.0` rather than Python's standard library for this reason, and refuses to load if the versions disagree.

The output of this algorithm can be piped to a digest function to produce a *canonical hash* of text. For example: `canonical hash = Blake3(cqt2.17(text))`. The output can also be piped directly to a digital signature function to produce a *signature over canonical text*. Perhaps better, because it allows text value to be disclosed later, a signature can take as input a canonical hash: `signature over canonical hash = EdDSA(Blake3(cqt2.17(text)))`.

A protocol that uses CQT MUST bind the exact ASCII identifier `cqt2.17` in whatever it signs, so a verifier cannot silently substitute a different algorithm or Unicode version. A verifier MUST reject an identifier it does not support rather than falling back to one it does.

## Goals

Given any two input text samples and a literate, thoughtful human who knows the natural language(s) that they embody, the intent is to provide an algorithm that achieves the following goals:

1. If the human considers the samples to embody the same semantic content (differing only in insignificant stylistic choices like whitespace), the algorithm produces output that is byte-for-byte identical.
2. If the human considers the samples to embody different content, the algorithm produces output that differs.
3. As much as possible, the human should *also* view the output of the algorithm as semantically equivalent to the input.
4. The algorithm should be easy to implement in a programming language that has good Unicode support.

We live in an imperfect world, so this algorithm makes calculated tradeoffs in the first two goals. Also, the third goal is less important than the first two and might be sacrificed in corner cases. For more on this, see [Caveats](#caveats).

One goal is deliberately absent: the algorithm is not required to be idempotent. Its output is a canonical form derived from human text, and nothing promises that running the algorithm on that output a second time yields the same bytes again. Nor does the output have to remain distinguishable from machine-readable syntax; a sentence that happens to end up looking like a code fence is still just a sentence that was canonicalized once.

## Protected content

A *protected span* is a run of characters that the algorithm recognizes as machine-readable syntax rather than prose. Its bytes are copied to the output unchanged. None of the transformations in the algorithm below inspects or alters its contents.

Recognition happens once, on the input, before any transformation. This is the whole of the test: either the input satisfies the pattern or it does not. A span that only *becomes* recognizable later &mdash; because normalization folded a fullwidth character into a backtick, or because removing an invisible closed a gap in `http://` &mdash; was not machine-readable syntax when it arrived, and is treated as the prose it was.

For the transformations that surround it, a complete protected span behaves as a single character that is neither whitespace nor punctuation. Ordinary spaces on either side of it remain ordinary word-separating spaces.

Recognition has this precedence: fenced code blocks first, then inline code spans and HTTP(S) URLs in whatever prose remains.

The prose that remains is a set of segments, each lying between two fences or at one end of the input. Scanning happens within a segment and never across one, so a backtick before a fence cannot pair with a backtick after it, and a URL stops at a fence boundary.

Within a segment, scan left to right and take whichever span begins first. The two kinds cannot begin at the same place, since a code span starts at a backtick and a URL at an `h`, so no tie-break is needed. They can still meet: a backtick ends a URL span, and then opens a code span of its own, so in `http://a.test/x` followed by a backtick the URL stops there and the backtick begins something new.

### Fenced code blocks

For fence recognition, a line ending is exactly LF (`U+000A`), CR (`U+000D`), or the two-character sequence CRLF. Other Unicode separators do not end a line. A complete line is the text from the start of the input, or from just after a line ending, up to and including the next line ending or the end of the input.

An opening fence is a complete line containing, in order: zero to three ASCII spaces; a run of three or more backticks; an optional info string containing no backtick; and then a line ending or the end of input. A closing fence is a later complete line containing zero to three ASCII spaces, a backtick run at least as long as the opening one, optional ASCII spaces or tabs, and then a line ending or the end of input.

The protected span covers the opening and closing lines, the line ending that follows the closing line, and the line ending that precedes the opening line. Taking the preceding line ending keeps the fence at the start of a line after the surrounding prose has been flattened into spaces.

When one fence begins on the line after another ends, that preceding line ending has already been taken by the earlier span. Spans never overlap: the later span begins where the earlier one ended, and the shared line ending belongs to the earlier.

An opening fence with no closing fence is not a fence. The pattern requires both lines; when the second one is missing, the pattern is simply absent, and the backticks are prose like any other characters. Failing to match is not an error.

Scanning then resumes on the line after the failed opener, not after the block it appeared to open. A line inside that block may therefore open a fence of its own. A run of four backticks with no four-backtick closer is prose, and a three-backtick line beneath it can still open a fence that closes later.

### Inline code spans

A run of one or more backticks opens an inline code span when a later run of exactly the same length exists and is not part of a longer run. The pair of delimiters and everything between them is protected.

Runs are maximal. An unmatched run is prose in its entirety, and scanning resumes after the whole run; no shorter piece of an unmatched run may open a span.

### HTTP(S) URL spans

The ASCII strings `http://` and `https://` are recognized case-insensitively at any position in unprotected prose. The comparison is ASCII-only: a character outside `A`-`Z` and `a`-`z` never matches a scheme character, so `U+017F LATIN SMALL LETTER LONG S` does not match `s`. [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986#section-3.1) allows only ASCII letters in a scheme, and an implementation whose case-insensitive comparison applies Unicode case folding will protect text that is not a URL.

Recognition is lexical. CQT does not validate the host, resolve the URL, or touch the network.

The span begins at the character that matched the `h` of the scheme, whatever its case, and runs until the first Unicode 17 whitespace character, the first `<`, `>`, `"` or backtick, or the first unmatched closing parenthesis. Parentheses inside the URL are counted, beginning after the `://`, so `https://example.test/Foo_(bar)` is one span. Other trailing punctuation is included rather than guessed to be prose, because it may legally belong to the URL. Percent encoding, non-ASCII spelling, scheme case, repeated hyphens, query ampersands and fragments all survive exactly.

## Algorithm

Start with input content that has been transformed into plain text.

>This is a precondition rather than a step in our algorithm. "Plain text" means that the text is ready to be interpreted as IANA media type `text/plain`: it contains no markup intended as instructions to a different formatting engine (e.g., escape sequences, HTML/XML tags, character entities...). Many programs that edit rich text already implement such transformations &mdash; when a user copies text, they place both a richly formatted and a "plain text" version of the content on the clipboard. However, intent matters; including an HTML tag in plain text is correct, if the plain text is *intended* to be an instruction about how to construct an HTML tag &mdash; and it is not correct otherwise.

1. Convert the text to Unicode, eliminating codepages as a source of difference. Represent the data in whichever encoding of Unicode (UTF-8, UTF-16, UTF-32...) is convenient; subsequent steps are described as Unicode operations rather than byte operations.

    Where the host language stores text as UTF-16 &mdash; JavaScript, Java, Swift &mdash; a well-formed surrogate pair is one character and MUST be treated as the scalar it encodes. An implementation that walks code units rather than scalar values will mis-handle every astral character, including the emoji in step 5.

2. Finish making the text plain, by removing three kinds of character that cannot belong to it. This is still precondition work rather than canonicalization, so it happens before anything is recognized or transformed.

    1. Remove any unpaired surrogate (`U+D800` to `U+DFFF` with no partner). These are not Unicode scalar values, they encode nothing, and they have no UTF-8 representation.

        Whether this step can ever do anything depends on the host. Java, JavaScript and other UTF-16 languages let a string hold a lone surrogate, so there it is reachable. Swift, Rust and Go strings cannot hold one, so there it is vacuous. Either is conforming. What a byte-oriented implementation should do with input that is not well-formed UTF-8 in the first place is outside this specification; decoding is the caller's responsibility.
    2. Remove any character whose General Category is `Cc` and that is not in the whitespace set in step 6.1 &mdash; NUL and its neighbors. A control character is not plain text. `Cc` is `U+0000`..`U+001F` and `U+007F`..`U+009F`, fixed for all time by the stability policy in [UAX #44](https://www.unicode.org/reports/tr44/), so no character database is needed to apply this step.
    3. Remove `U+202D LEFT-TO-RIGHT OVERRIDE` and `U+202E RIGHT-TO-LEFT OVERRIDE`. An override forces every character in its scope to render in a chosen direction regardless of what that character is, so Latin letters can be made to display in reverse. That is an instruction to a rendering engine rather than a statement about the text, and it is the mechanism behind bidirectional spoofing, in which a signer sees one thing and signs another.

        The other bidi controls stay, because they describe the text rather than override it. Marks (`U+061C`, `U+200E`, `U+200F`) only influence how neighboring neutral characters resolve, and isolates (`U+2066` to `U+2069`) scope a direction without overriding anything. Both are ordinary parts of correct Arabic and Hebrew.

3. Recognize [protected content](#protected-content) and set each span aside, leaving behind a placeholder. Steps 4 through 8 never see the contents of a span.

    The placeholder MUST be built from scalars that step 2 has already removed from the input. Otherwise the input can contain a placeholder of its own, and step 8 will substitute a span's contents into a position the author never marked &mdash; two different inputs then produce identical bytes, which is Goal 2 failing on text an attacker chooses.

    Not every control character qualifies, and the trap is worth naming. `U+0009` through `U+000D` and `U+0085` are `Cc` but they are also `White_Space`, so step 2 keeps them. Only `U+0000`..`U+0008`, `U+000E`..`U+001F` and `U+007F`..`U+009F` are provably gone. The reference implementation uses `U+0000` followed by `CQT`, the span's ordinal in ASCII digits, and `U+0000`.

    Each span gets its own placeholder, distinct from every other, or step 8 cannot tell them apart.

    A placeholder must also survive steps 4 through 7 unaltered, and must not be read as prose by any of them. It must be unchanged by NFKC; must not be one of the four invisibles removed in step 5; must not be `White_Space`, `Terminal_Punctuation`, `Ps`, `Pi`, `Pe`, `Pf`, or a member of the `Pd` set; must not be a quote character from step 7.6, a source in either autocorrect table, or a variation selector; and must not be `&amp;`, `.`, `-`, `U+2026` or `U+2044`. A placeholder built as the previous paragraph requires satisfies all of this. Treating it as neither whitespace nor punctuation is also what lets an ordinary space beside a protected span stay an ordinary word-separating space.

4. Normalize the text to [Unicode's Normalization Form KC (NFKC)](https://www.unicode.org/reports/tr15/). This converts CJK characters from halfwidth to fullwidth forms, breaks ligatures, decomposes fractions, standardizes variants, handles diacritics uniformly, flattens super- and subscripts, converts all numbers to Arabic numerals, and eliminates many other unimportant differences.

    This is the only step that depends on a character database, and most runtimes ship an older one; see [Implementing on a runtime whose Unicode is older](#implementing-on-a-runtime-whose-unicode-is-older). An implementation that has to supply its own NFKC needs three things from the Unicode 17 data: the canonical and compatibility decomposition mappings, the canonical combining class of every character, and the table of primary composites. Derive the third from the decomposition mappings *minus the composition exclusions*; inverting the mappings alone gives the wrong answer for the excluded composites.

5. Remove invisible characters that carry no meaning of their own. These are layout artifacts that editors, mailers and sanitizers inject and remove without asking.

    1. Remove `U+00AD SOFT HYPHEN`, `U+200B ZERO WIDTH SPACE`, `U+2060 WORD JOINER`, and `U+FEFF ZERO WIDTH NO-BREAK SPACE`.
    2. Keep `U+200B` when the character before it and the character after it both have Unicode 17 `Line_Break` property value `SA`. Those scripts &mdash; Thai, Lao, Khmer, Myanmar, Tai Tham, New Tai Lue and Ahom &mdash; write without spaces between words and use `U+200B` to divide them, so removing it merges words their readers keep apart. Both neighbors must qualify, so a `U+200B` dropped in by a mailer at a script boundary still goes.

        Neighbors are the characters adjacent in the text as it stands when this step begins, not the ones that survive it. In `\u0E01\u200B\u200B\u0E01` each zero width space sees the other as its neighbor, so neither qualifies and both are removed. Note also that Ahom is above the BMP; an implementation whose neighbor lookup reads UTF-16 code units rather than scalars will see surrogate halves and get this wrong.

        The set is 757 scalars:

        ```text
        U+0E01..U+0E3A  U+0E40..U+0E4E  U+0E81..U+0E82  U+0E84  U+0E86..U+0E8A
        U+0E8C..U+0EA3  U+0EA5  U+0EA7..U+0EBD  U+0EC0..U+0EC4  U+0EC6
        U+0EC8..U+0ECE  U+0EDC..U+0EDF  U+1000..U+103F  U+1050..U+108F
        U+109A..U+109F  U+1780..U+17D3  U+17D7  U+17DC..U+17DD  U+1950..U+196D
        U+1970..U+1974  U+1980..U+19AB  U+19B0..U+19C9  U+19DE..U+19DF
        U+1A20..U+1A5E  U+1A60..U+1A7C  U+1AA0..U+1AAD  U+A9E0..U+A9EF
        U+A9FA..U+A9FE  U+AA60..U+AAC2  U+AADB..U+AADF  U+11700..U+1171A
        U+1171D..U+1172B  U+1173A..U+1173B  U+1173F..U+11746
        ```
    3. Keep `U+200C ZERO WIDTH NON-JOINER` and `U+200D ZERO WIDTH JOINER` everywhere. They select conjunct and half-forms in Indic scripts and change what a reader sees.

6. Normalize whitespace. This eliminates invisible differences that are attributable to the preference of a typist or that constitute variable layout choices.

    1. Replace each run of one or more Unicode 17 `White_Space` characters with a single space `U+0020`. The set is `U+0009`..`U+000D`, `U+0020`, `U+0085`, `U+00A0`, `U+1680`, `U+2000`..`U+200A`, `U+2028`, `U+2029`, `U+202F`, `U+205F`, and `U+3000`.
    2. Trim leading and trailing spaces.

    This deliberately converts line structure into spaces. CQT is unsuitable for unfenced poetry, source code, tables, or anything else where a line break carries meaning &mdash; which is what fenced blocks are for.

7. Normalize punctuation. This eliminates differences that are hard to see, that might be introduced by autocorrect in editors, or that are attributable to the preference of a typist.

    1. Replace all characters in the Unicode 17 dash punctuation category (`Pd`) with the ASCII hyphen `-` (`U+002D`). The complete set is `U+002D`, `U+058A`, `U+05BE`, `U+1400`, `U+1806`, `U+2010`..`U+2015`, `U+2E17`, `U+2E1A`, `U+2E3A`, `U+2E3B`, `U+2E40`, `U+2E5D`, `U+301C`, `U+3030`, `U+30A0`, `U+FE31`, `U+FE32`, `U+FE58`, `U+FE63`, `U+FF0D`, `U+10D6E`, and `U+10EAD`.
    2. Replace any run of two or more hyphens with a single hyphen.
    3. Replace the ideographic comma <code>&#x3001;</code> (`U+3001`) with an ordinary comma, and the ideographic full stop <code>&#x3002;</code> (`U+3002`) with an ordinary full stop. NFKC has already handled the fullwidth ASCII forms.
    4. Replace an ellipsis <code>&#x2026;</code> (`U+2026`) with three full stops, then truncate any run of four or more full stops to exactly three.
    5. Replace the fraction slash <code>&#x2044;</code> (`U+2044`) with the ordinary slash `/` (`U+002F`).
    6. Replace the following quote characters with the least common denominator, the ASCII apostrophe `'` (`U+0027`): `U+0022`, <code>&#x2018;</code> `U+2018`, <code>&#x2019;</code> `U+2019`, <code>&#x201C;</code> `U+201C`, <code>&#x201D;</code> `U+201D`, <code>&#x00AB;</code> `U+00AB`, <code>&#x00BB;</code> `U+00BB`, <code>&#x2039;</code> `U+2039`, <code>&#x203A;</code> `U+203A`, and <code>&#x3008;</code> `U+3008` through <code>&#x300D;</code> `U+300D`.
    7. Undo some common autocorrect transformations by converting fancier Unicode characters to their ASCII equivalents. Scan the text once from left to right, taking at each position the first rule below whose source matches, and resume after what it produced; no rule is applied to the output of another:

        Unicode character | Codepoint | ASCII equivalent
        --- | --- | ---
        <code>&#x1f60A;</code> | `U+1F60A` | `:-)`
        <code>&#x1f610;</code> | `U+1F610` | <code>:-&#124;</code>
        <code>&#x2639;</code> | `U+2639` | `:-(`
        <code>&#x1f603;</code> | `U+1F603` | `:-D`
        <code>&#x1f61D;</code> | `U+1F61D` | `:-p`
        <code>&#x1f632;</code> | `U+1F632` | `:-o`
        <code>&#x1f609;</code> | `U+1F609` | `;-)`
        <code>&#x2764;</code> | `U+2764` | `<3`
        <code>&#x1f494;</code> | `U+1F494` | `</3`
        &copy; | `U+00A9` | `(c)`
        &reg; | `U+00AE` | `(R)`
        &bull; | `U+2022` | `*`

        One trailing variation selector is part of the character it follows, for every entry in the table. `U+FE0F VARIATION SELECTOR-16` asks for the emoji rendering and `U+FE0E VARIATION SELECTOR-15` for the text rendering; neither changes what the character is, and an emoji picker or keyboard adds them without the user knowing. So <code>&#x00a9;</code>, <code>&#x00a9;&#xfe0f;</code> and <code>&#x00a9;&#xfe0e;</code> all become `(c)`. Exactly one selector is absorbed, in any combination, so a second one survives as ordinary text: <code>&#x00a9;&#xfe0f;&#xfe0f;</code> becomes `(c)` followed by a lone `U+FE0F`.

    8. Replace some ASCII emoticons with their canonical equivalent: `:)`, <code>:&#124;</code>, `:(`, `:D`, `:p`, `:o` and `;)` become `:-)`, <code>:-&#124;</code>, `:-(`, `:-D`, `:-p`, `:-o` and `;-)`.

    9. Attach punctuation to the side it binds to, by removing a space that separates it from what it belongs with. Remove a space when the character after it has General Category `Pe` or `Pf`, or has the Unicode 17 `Terminal_Punctuation` property; and remove a space when the character before it has General Category `Ps` or `Pi`.

        Neighbors are the characters adjacent in the text as this step begins, as in step 5.2. Punctuation is not symmetric. What closes or ends a phrase binds to its left, and what opens one binds to its right, so `Really ? Yes .` becomes `Really? Yes.` while `Really? Yes.` is left alone. No space is removed on the other side of such a character, or around any other punctuation, so dashes, connectors, the solidus and the apostrophe keep their spacing.

        The opening and closing classes are `Ps`, `Pi`, `Pe` and `Pf`, 178 scalars in all. They are enumerated here for the same reason as the other sets, so that no step of this algorithm depends on the character database a runtime happens to ship:

        ```text
        U+0028..U+0029  U+005B  U+005D  U+007B  U+007D  U+00AB  U+00BB
        U+0F3A..U+0F3D  U+169B..U+169C  U+2018..U+201F  U+2039..U+203A
        U+2045..U+2046  U+207D..U+207E  U+208D..U+208E  U+2308..U+230B
        U+2329..U+232A  U+2768..U+2775  U+27C5..U+27C6  U+27E6..U+27EF
        U+2983..U+2998  U+29D8..U+29DB  U+29FC..U+29FD  U+2E02..U+2E05
        U+2E09..U+2E0A  U+2E0C..U+2E0D  U+2E1C..U+2E1D  U+2E20..U+2E29  U+2E42
        U+2E55..U+2E5C  U+3008..U+3011  U+3014..U+301B  U+301D..U+301F
        U+FD3E..U+FD3F  U+FE17..U+FE18  U+FE35..U+FE44  U+FE47..U+FE48
        U+FE59..U+FE5E  U+FF08..U+FF09  U+FF3B  U+FF3D  U+FF5B  U+FF5D
        U+FF5F..U+FF60  U+FF62..U+FF63
        ```

        Below ASCII 128, `Terminal_Punctuation` holds exactly `!`, `,`, `.`, `:`, `;` and `?`. It deliberately excludes the solidus, which would otherwise turn `A / B` into `A/ B`, and the apostrophe, which step 7.6 has just made ambiguous by folding every quote character onto it. Remove the whole run of spaces, not one of them; after step 6 a run is never longer than one, but the two readings differ if the order ever changes. The complete set is 291 scalars:

        ```text
        U+0021  U+002C  U+002E  U+003A..U+003B  U+003F  U+037E  U+0387  U+0589
        U+05C3  U+060C  U+061B  U+061D..U+061F  U+06D4  U+0700..U+070A  U+070C
        U+07F8..U+07F9  U+0830..U+0835  U+0837..U+083E  U+085E  U+0964..U+0965
        U+0E5A..U+0E5B  U+0F08  U+0F0D..U+0F12  U+104A..U+104B  U+1361..U+1368
        U+166E  U+16EB..U+16ED  U+1735..U+1736  U+17D4..U+17D6  U+17DA
        U+1802..U+1805  U+1808..U+1809  U+1944..U+1945  U+1AA8..U+1AAB
        U+1B4E..U+1B4F  U+1B5A..U+1B5B  U+1B5D..U+1B5F  U+1B7D..U+1B7F
        U+1C3B..U+1C3F  U+1C7E..U+1C7F  U+2024  U+203C..U+203D  U+2047..U+2049
        U+2CF9..U+2CFB  U+2E2E  U+2E3C  U+2E41  U+2E4C  U+2E4E..U+2E4F
        U+2E53..U+2E54  U+3001..U+3002  U+A4FE..U+A4FF  U+A60D..U+A60F
        U+A6F3..U+A6F7  U+A876..U+A877  U+A8CE..U+A8CF  U+A92F  U+A9C7..U+A9C9
        U+AA5D..U+AA5F  U+AADF  U+AAF0..U+AAF1  U+ABEB  U+FE12  U+FE15..U+FE16
        U+FE50..U+FE52  U+FE54..U+FE57  U+FF01  U+FF0C  U+FF0E  U+FF1A..U+FF1B
        U+FF1F  U+FF61  U+FF64  U+1039F  U+103D0  U+10857  U+1091F
        U+10A56..U+10A57  U+10AF0..U+10AF5  U+10B3A..U+10B3F  U+10B99..U+10B9C
        U+10F55..U+10F59  U+10F86..U+10F89  U+11047..U+1104D  U+110BE..U+110C1
        U+11141..U+11143  U+111C5..U+111C6  U+111CD  U+111DE..U+111DF
        U+11238..U+1123C  U+112A9  U+113D4..U+113D5  U+1144B..U+1144D
        U+1145A..U+1145B  U+115C2..U+115C5  U+115C9..U+115D7  U+11641..U+11642
        U+1173C..U+1173E  U+11944  U+11946  U+11A42..U+11A43  U+11A9B..U+11A9C
        U+11AA1..U+11AA2  U+11C41..U+11C43  U+11C71  U+11EF7..U+11EF8
        U+11F43..U+11F44  U+12470..U+12474  U+16A6E..U+16A6F  U+16AF5
        U+16B37..U+16B39  U+16B44  U+16D6E..U+16D6F  U+16E97..U+16E98  U+1BC9F
        U+1DA87..U+1DA8A
        ```

    10. Replace every `&` with ` & `, then collapse runs of spaces and trim, whether or not the text contained an ampersand. Because NFKC has already mapped the small and fullwidth ampersands onto `&`, the inputs `A&B`, `A & B` and `Ａ＆Ｂ` all produce `A & B`.

8. Put every protected span back exactly where its placeholder is.

9. Transform the text to UTF-8, with no byte order mark, to produce a canonical byte stream.

Each step runs once, in order. Nothing is repeated until it settles, and nothing looks at the output to decide whether the input was acceptable.

## Worked examples

These are chosen to be dense rather than typical. Each one exercises many rules at once, because the interactions are where implementations diverge. The vectors in [goldens/cqt2.17.json](goldens/cqt2.17.json) test rules one at a time.

### A quotation with mixed scripts and typography

```text
Input:
“Le rapport ﬁnal — R&D, 1⁄2 fait — coûte 3--4 k€ ; voir https://example.test/a--b?q=1&r=2 … et c’est prêt !” 😊  日本語も：「テスト」。  राम। श्याम

Output:
'Le rapport final - R & D, 1/2 fait - coûte 3-4 k€; voir https://example.test/a--b?q=1&r=2... et c'est prêt!':-) 日本語も:'テスト'. राम। श्याम
```

Fifteen rules fire here. The smart quotes and the CJK corner brackets both collapse onto the ASCII apostrophe. The <code>&#xfb01;</code> ligature becomes `fi` under NFKC, and the fullwidth colon becomes an ASCII colon. Both em dashes become hyphens, and `3--4` collapses to `3-4` &mdash; but `a--b` inside the URL does not, because the URL is a protected span, and neither does the `&` in its query string. The bare `&` in `R&D` is spaced out to `R & D`. The fraction slash becomes an ordinary slash. The ellipsis becomes three full stops, which then bind leftward onto the URL. French typography puts a space before `!` and `;`; those spaces are removed, because both characters bind to their left. The Devanagari danda keeps the space that follows it, because nothing binds rightward there &mdash; the rule is about which side punctuation attaches to, not about deleting spaces near punctuation. The emoji becomes `:-)` and then loses the space in front of it, since a colon binds left.

### Prose wrapped around machine-readable syntax

````text
Input:
Before  the  fence, `A  &  B--C` stays.
```python
x = "A  &  B--C"   # two  spaces survive
```
After, an unclosed ``` is only prose.

Output:
Before the fence, `A  &  B--C` stays.
```python
x = "A  &  B--C"   # two  spaces survive
```
After, an unclosed ``` is only prose.
````

The prose loses its doubled spaces; everything inside the inline code span and the fenced block keeps its own, along with the doubled hyphens and the unspaced ampersands that the prose rules would have rewritten. The line endings around the fence survive, while the line ending after it does not, having been flattened into the space before `After`. The trailing <code>&#x60;&#x60;&#x60;</code> has no closing fence, so it is not a fence at all, and it passes through as the three ordinary characters it is.

### Invisible characters

Nothing here is legible as text, so the codepoints are given instead.

```text
Input:   ปาก<200B>กา a<200B>b  soft<00AD>hyphen  file<202E>gnp.exe  a<0000>b  क्<200D>ष  x<D800>y
Output:  ปาก<200B>กา ab softhyphen filegnp.exe ab क्<200D>ष xy
```

The `U+200B` between two Thai characters survives, because Thai divides words with it; the one between `a` and `b` does not. The soft hyphen goes, as a layout artifact. The right-to-left override goes as part of making the text plain, so `file<202E>gnp.exe` &mdash; which displays as `fileexe.png` &mdash; cannot be signed as one thing while being read as another. The NUL goes for the same reason, and so does the unpaired surrogate. The zero width joiner in the Devanagari conjunct stays, because it changes which glyph a reader sees.

## Conformance

The algorithm in this document and the vectors in [goldens/cqt2.17.json](goldens/cqt2.17.json) are normative. An implementation MUST implement the complete algorithm and MUST produce, byte-for-byte, the output that every vector specifies. Where a vector and this prose disagree, the vector controls, and the disagreement is a defect in this document that MUST be reported rather than generalized to other inputs.

The Python implementation in [impl/python/cqt.py](impl/python/cqt.py) is a reference, not a source of normative behavior.

CQT 1.14 is a different and incompatible algorithm. Hashes and signatures identified as `cqt1.14` remain historical data and MUST NOT be recomputed or relabeled as `cqt2.17`.

### Implementing on a runtime whose Unicode is older

Most runtimes ship a Unicode version behind 17, and normalization is the only part of this algorithm that is version-sensitive; the four character sets above are enumerated here precisely so property lookups need not be. An implementation has three options, and the vectors will tell it whether it succeeded.

Raise the runtime, where the ecosystem offers a version with Unicode 17 tables. This is the least clever option and the most reliable.

Substitute a proxy, where a character's properties are wrong in the runtime's tables but the character influences normalization *only* through the property in question. Replace it with a different character the runtime already gives the correct property, normalize with the stock normalizer, and swap back. The result is exact rather than approximate, because the normalizer is never asked about a character whose data it has wrong. Restoration is unambiguous because canonical ordering is a stable sort, so proxies emerge in the order they entered.

Pre-substitute a decomposition, where a character's compatibility mapping is missing. `U+A7F1` maps to `S` under Unicode 17 and to itself under 16, and both have combining class 0, so replacing it before normalizing is exact.

Whichever route is taken, test the normalizer on *sequences* and not only on single characters. A platform normalizer can have correct tables for every scalar and still be wrong when it recomposes: while this specification was being written, `golang.org/x/text` was found to truncate a supplementary-plane starter to 16 bits before its composite lookup, so `U+10041` followed by `U+0301` produced `U+00C1`, and the same clipping made Hebrew `U+05D2 U+0307` produce a Todhri letter. Per-scalar checking cannot find that class of defect. The vectors `astral-starter-survives-normalization` and `hebrew-letter-with-combining-dot` exist to catch it.

What defeats all three is a change to composition itself &mdash; a new primary composite, or a change to the composition exclusion list &mdash; because no substitute behaves like a character that composes differently. Between Unicode 16 and 17 there is no such change, which is why a Unicode 16 runtime can be made exactly conformant. That is a fact about those two versions and not a general guarantee.

An implementation in this repository is conformant exactly insofar as it passes every vector, and no further. Each one carries its own test harness that runs the vectors, so its status is a fact that can be checked rather than a claim made here; an implementation whose harness does not pass MUST NOT be used to produce or verify a `cqt2.17` commitment.

CQT 2.17 never rejects text. Every input produces output; there are no error conditions and no failure modes to specify. Human text has spelling errors and grammar errors, but it does not have syntax errors, and an algorithm that canonicalizes it has no business complaining about it.

## Caveats
This algorithm collapses some differences that are usually insignificant in written text. Note the word "usually". The algorithm may not distinguish certain input texts having subtle distinctions. For example:

* Because the algorithm collapses the distinction between halfwidth and fullwidth forms, two Chinese sentences &mdash; one written with halfwidth forms, and the other written with fullwidth forms &mdash; will produce the same output.
* Because of the conversion of certain mathematical operators to ASCII, and because the algorithm normalizes punctuation, two sentences that contain mathematical or computer science expressions might produce the same output when they are actually slightly different (e.g., the expression `i--` and the expression `i-` produce identical output; so do <code>x&#xb2;</code>, <code>x&#x2082;</code>, and <code>x2</code>). Fenced blocks and inline code spans exist so that such text can be exempted.
* Because the algorithm normalizes punctuation, text that is picky about punctuation may lose precision. For example, the instruction from an English teacher, `Always place a comma inside double quotes: "abc,"` is normalized to the same value as `Always place a comma inside double quotes: 'abc,'` (which contains no double quotes, despite what the text says).
* Removing `U+200B` costs something in Thai, Lao and Khmer even with the exemption in step 5.2, because the exemption requires both neighbors to be in those scripts. A `U+200B` that divides a Thai word from a Latin one is treated as an artifact and removed.

This algorithm also leaves intact some differences that some audiences may wish to collapse. Notably, *it does not normalize case*, and it does not fold visually confusable characters; a caller who wants to warn a signer about mixed-script text should use [Unicode Technical Standard #39](https://www.unicode.org/reports/tr39/) alongside CQT rather than in place of it. Also:

* A poetry sample written on separate lines produces different output from poetry written with lines separated by slashes ("Once upon a midnight dreary / While I pondered, weak and weary").
* Emojis that differ only in skin tone are considered different.
* ASCII emphasis (e.g., `I'm *really* serious`) is untouched and does not equate to italics or bolded text.
* Most dingbats (e.g., fancy versions of question marks and check marks) are not normalized.
* The autocorrect replacements do not all interact with spacing the same way, because step 7.9 asks which side punctuation binds to. A replacement that begins with a colon binds left, so `hello \u2639` becomes `hello:-(` with the space gone. One that begins with an opening parenthesis binds right, so `hello \u00a9` becomes `hello (c)` with the space intact, and therefore still differs from `hello(c)`. Both follow from 7.9 as written, but the convergence is narrower for `\u00a9`, `\u00ae` and `\u2022` than for the emoticons.
* Because each step runs once, a transformation that would have enabled an earlier step does not get a second chance. `:)` becomes `:-)`, and so does `hello :)`, because the emoticon is recognized before the space in front of it is removed. But `: )` becomes `:)` and stops there: closing the gap produces an emoticon that step 7.8 has already gone past. Text that has been mangled into `: )` by something upstream will not be recovered.

Finally, the output of this algorithm is a canonical form, not a substitute for the input. Running CQT on its own output may produce something different again, and that is expected: the algorithm is a projection from human text, applied once, at the moment something is signed or verified.
