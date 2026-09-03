# CQT
This is a spec for a simple but powerful algorithm for canonicalizing chunks of text that flow not via files but via chat, copy/paste, or other non-file-oriented channels (social media, SMS, email, etc.).

## Try it out!
You can use an [interactive form to run the algorithm on arbitrary text](https://dhh1128.github.io/canonical-quoted-text/form.html).

## Implementations
Each implementation lives in its own directory under [impl/](impl), with a test harness beside it that runs the normative vectors in [goldens/cqt3.17.json](goldens/cqt3.17.json). A reference implementation is in [python](impl/python/cqt.py); see also [javascript](impl/js/cqt.js), [java](impl/java/Cqt.java), [go](impl/go/cqt.go), [rust](impl/rust/cqt.rs), and [swift](impl/swift/Cqt.swift). Whether any given implementation conforms is a question the vectors answer; see [Conformance](#conformance). Code is in the public domain; see [LICENSE](https://github.com/dhh1128/canonical-quoted-text/blob/main/LICENSE).

## Building on CQT

If you are writing an application that produces or checks CQT commitments rather than implementing the algorithm itself, see [Advice for apps using CQT](advice-for-apps-using-cqt.md). It is non-normative and revisable, and it covers what this document deliberately does not: which channels destroy protected content, where to take a digest, what a composer and a verifier each owe the user, and how to unnest a quoted reply.

## Purpose
Cryptographic hashes and signatures are usually applied to files or data structures. However, a very important category of communication is not file-oriented. In our modern world, lots of text moves across system boundaries using mechanisms that are prone to reformatting and error due to their inherent fuzziness. We see a post on social media on our phones, copy it, and paste it into a text to a friend. She emails it to a journalist acquaintance, who moves it into a word processor that is configured to use a different locale with different autocorrect and punctuation settings. Eventually, a student cites the journalist in a paper they're writing. Somewhere along the way, whitespace is deleted, capitalization or spelling is altered, the codepage changes, smart quotes turn into dumb quotes or two hyphens become an em dash.

In this scenario, how can we evaluate whether the final text is *the same* as the original?

Of course, opinions about what constitutes *sameness* vary. There is no objectively correct answer. However, we can create *deterministic* answers that are useful. They can help us decide whether minor text changes are likely to matter, and check to see whether a digital signature matches a piece of text.

The algorithm documented here is for such cases. It says that two chunks of text are *the same* if, when transformed by the algorithm, they produce output that matches byte-for-byte.

Sometimes a quotation contains a fragment that must survive exactly &mdash; a command, a hash, a snippet of code. Such a fragment is not human-friendly text at all; it is machine-readable syntax, and the transformations that make prose comparable would destroy it. CQT 3.17 adds a way to mark those fragments so they are set aside, left alone, and put back untouched. See [Protected content](#protected-content).

## Official name and version

The full name of this algorithm is "canonical quoted text 3.17", but it is typically abbreviated "cqt3.17".

The name contains two numbers. The first number ("3") versions the logic of the algorithm, and the second number ("17") references the version of the Unicode standard that documents certain details. CQT 1.14 and CQT 2.17 are different algorithms; see [Conformance](#conformance).

`cqt3.17` names one exact function, frozen at publication. Neither number is a compatibility signal, and a protocol that uses CQT MUST bind the exact ASCII identifier `cqt3.17` in whatever it signs. What that commits everyone to, and how this document may still change without breaking it, is in [Appendix: what the version numbers promise](#appendix-what-the-version-numbers-promise).

The output of this algorithm can be piped to a digest function to produce a *canonical hash* of text. For example: `canonical hash = Blake3(cqt3.17(text))`. The output can also be piped directly to a digital signature function to produce a *signature over canonical text*. Perhaps better, because it allows text value to be disclosed later, a signature can take as input a canonical hash: `signature over canonical hash = EdDSA(Blake3(cqt3.17(text)))`.

## Goals

Given any two input text samples and a literate, thoughtful human who knows the natural language(s) that they embody, the intent is to provide an algorithm that achieves the following goals:

1. If the human considers the samples to embody the same semantic content (differing only in insignificant stylistic choices like whitespace), the algorithm produces output that is byte-for-byte identical.
2. If the human considers the samples to embody different content, the algorithm produces output that differs.
3. As much as possible, the human should *also* view the output of the algorithm as semantically equivalent to the input.
4. The algorithm should be easy to implement in a programming language that has good Unicode support.

We live in an imperfect world, so this algorithm makes calculated tradeoffs in the first two goals. Also, the third goal is less important than the first two and might be sacrificed in corner cases. For more on this, see [Caveats](#caveats).

One goal is deliberately absent: the algorithm is not required to be idempotent. Its output is a canonical form derived from human text, and nothing promises that running the algorithm on that output a second time yields the same bytes again. Nor does the output have to remain distinguishable from machine-readable syntax; a sentence that happens to end up looking like a code fence is still just a sentence that was canonicalized once.

## Protected content

Sometimes a quotation contains a fragment that must survive exactly: a command, a hash, a snippet of code. Such a fragment is not human-friendly text at all. It is machine-readable syntax, and the transformations that make prose comparable would destroy it.

A *protected span* is a run of characters the algorithm recognizes as machine-readable syntax rather than prose. None of the transformations in steps 4 through 7 inspects or alters what it says. Its line structure is another matter &mdash; an inline span's interior line endings fold to a space, so the bytes are not untouched either &mdash; and the paragraph after next says what happens to it. There are three kinds: a fenced code block, an inline code span, and an HTTP(S) URL.

Recognition happens once, on the input, before any transformation. Either the input satisfies the pattern or it does not. A span that only *becomes* recognizable later, because normalization folded a fullwidth character into a backtick or removing an invisible closed a gap in `http://`, was not machine-readable syntax when it arrived, and is treated as the prose it was.

A protected span is not quite untouched bytes. It is text canonicalized under a reduced rule set, and the line that divides the two is this: **line structure belongs to the channel, and everything else belongs to the author.** Transport rewrites line endings, trailing whitespace and indentation without asking and without telling anyone, so those are normalized inside a span as well as outside it. Transport does not rewrite tabs, invisibles, quotes or letter case inside a code block, so none of those is touched. Two spans of the same content that differ only in what a mail gateway did to their line structure produce the same bytes; in every other respect the author's bytes are reproduced exactly.

Two consequences follow, and they are the difference between the two backtick-delimited kinds. An inline code span carries no line structure at all: a line ending inside one folds to a single space, so a span survives being rewrapped. A fenced block carries line structure by definition, so it does not survive a channel that reflows or strips newlines. Reach for a fence when the line breaks are the point, and for an inline span otherwise.

For the transformations that surround it, a complete protected span behaves as a single character that is neither whitespace nor punctuation. A space beside a span is therefore an ordinary space, subject to every rule that governs one: it collapses with its neighbours in step 6.2, and step 7.9 removes it when punctuation on the other side binds across it, so `https://example.test/a )` reaches `https://example.test/a)`. What the span guarantees is that the space is not swallowed *by the span*, not that it survives.

The grammar of each kind is in [Recognizing protected content](#recognizing-protected-content), after the algorithm.

## Algorithm

Start with input content that has been transformed into plain text.

>This is a precondition rather than a step in our algorithm. "Plain text" means that the text is ready to be interpreted as IANA media type `text/plain`: it contains no markup intended as instructions to a different formatting engine (e.g., escape sequences, HTML/XML tags, character entities...). Many programs that edit rich text already implement such transformations &mdash; when a user copies text, they place both a richly formatted and a "plain text" version of the content on the clipboard. However, intent matters; including an HTML tag in plain text is correct, if the plain text is *intended* to be an instruction about how to construct an HTML tag &mdash; and it is not correct otherwise.

1. Convert the text to Unicode, eliminating codepages as a source of difference. Represent the data in whichever encoding of Unicode (UTF-8, UTF-16, UTF-32...) is convenient; subsequent steps are described as Unicode operations rather than byte operations.

    Where the host language stores text as UTF-16 &mdash; JavaScript, Java, Swift &mdash; a well-formed surrogate pair is one character and MUST be treated as the scalar it encodes. An implementation that walks code units rather than scalar values will mis-handle every astral character, including the emoji in step 5.

2. Finish making the text plain, by removing three kinds of character that cannot belong to it. This is still precondition work rather than canonicalization, so it happens before anything is recognized or transformed.

    1. Remove any unpaired surrogate (`U+D800` to `U+DFFF` with no partner). These are not Unicode scalar values, they encode nothing, and they have no UTF-8 representation.

        Whether this step can ever do anything depends on the host. Java, JavaScript and other UTF-16 languages let a string hold a lone surrogate, so there it is reachable. Swift, Rust and Go strings cannot hold one, so there it is vacuous. Either is conforming. What a byte-oriented implementation should do with input that is not well-formed UTF-8 in the first place is outside this specification; decoding is the caller's responsibility.
    2. Remove any character whose General Category is `Cc` and that is not in the whitespace set in step 6.2 &mdash; NUL and its neighbors. A control character is not plain text. `Cc` is `U+0000`..`U+001F` and `U+007F`..`U+009F`, fixed for all time by the stability policy in [UAX #44](https://www.unicode.org/reports/tr44/), so no character database is needed to apply this step.
    3. Remove `U+202D LEFT-TO-RIGHT OVERRIDE` and `U+202E RIGHT-TO-LEFT OVERRIDE`. An override forces every character in its scope to render in a chosen direction regardless of what that character is, so Latin letters can be made to display in reverse. That is an instruction to a rendering engine rather than a statement about the text, and it is the mechanism behind bidirectional spoofing, in which a signer sees one thing and signs another.

        The other bidi controls stay, because they describe the text rather than override it. Marks (`U+061C`, `U+200E`, `U+200F`) only influence how neighboring neutral characters resolve, and isolates (`U+2066` to `U+2069`) scope a direction without overriding anything. Both are ordinary parts of correct Arabic and Hebrew.
    4. Remove `U+FEFF`. As a byte order mark it is a serialization signature rather than writing, and Unicode deprecates its other use, as a zero width no-break space, in favor of `U+2060 WORD JOINER`. It is removed here rather than with the invisibles in step 5 because it is not text, which is also why it comes out of a protected span &mdash; the same reason a `Cc` scalar and a directional override already do.
    5. Replace every line terminator with `U+000A LINE FEED`. The terminators are `U+000D U+000A` taken as one, and singly `U+000A`, `U+000B`, `U+000C`, `U+000D`, `U+0085`, `U+2028` and `U+2029`.

        Prose is unaffected, because step 6.2 collapses any of these to a single space either way. What this changes is the interior of a protected span, where CRLF and LF used to produce different bytes for the same block. MIME `text/plain` is CRLF-canonical, so email converts as a matter of course, and a block that has been through a mail gateway would otherwise never match the block that was signed. From here on, LF is the only line terminator, and "horizontal whitespace" below means the `White_Space` set of step 6.2 without it. That set still nominally contains VT, FF, CR, NEL and the two separators; this step has just removed every one of them, so the two readings coincide and nothing turns on which is meant.
    6. Remove the whole run of horizontal whitespace that immediately precedes a line ending or the end of the input.

        Same reasoning. Editors trim on save, mailers pad, chat clients strip, and nobody can see any of it. Scoping the rule to whitespace before a line ending is what leaves an inline code span of nothing but a space and a tab intact, since that whitespace is not at a line end.

3. Recognize [protected content](#protected-content) and set each span aside, leaving behind a placeholder. Steps 4 through 8 never see the contents of a span.

    The placeholder MUST be built from scalars that step 2 has already removed from the input. Otherwise the input can contain a placeholder of its own, and step 8 will substitute a span's contents into a position the author never marked &mdash; two different inputs then produce identical bytes, which is Goal 2 failing on text an attacker chooses.

    Not every control character qualifies. `U+0009` through `U+000D` and `U+0085` are `Cc` but they are also `White_Space`, so step 2 keeps them. Only `U+0000`..`U+0008`, `U+000E`..`U+001F` and `U+007F`..`U+009F` are provably gone. The reference implementation uses `U+0000` followed by `CQT`, the span's ordinal in ASCII digits, and `U+0000`.

    Each span gets its own placeholder, distinct from every other, or step 8 cannot tell them apart.

    A placeholder MUST also survive steps 4 through 7 unaltered, and MUST NOT be read as prose by any of them. It MUST be unchanged by NFKC; MUST NOT be one of the three invisibles removed in step 5; MUST NOT be `>` or horizontal whitespace, which step 6.1 reads as a quote prefix; MUST NOT be `White_Space`, `Terminal_Punctuation`, `Ps`, `Pi`, `Pe`, `Pf`, or a member of the `Pd` set; MUST NOT be a quote character from step 7.6, a source in either autocorrect table, or a variation selector; and MUST NOT be `&amp;`, `.`, `-`, `U+2026` or `U+2044`. A placeholder built as the previous paragraph requires satisfies all of this. Treating it as neither whitespace nor punctuation is also what lets an ordinary space beside a protected span stay an ordinary word-separating space.

4. Normalize the text to [Unicode's Normalization Form KC (NFKC)](https://www.unicode.org/reports/tr15/). This converts CJK characters from halfwidth to fullwidth forms, breaks ligatures, decomposes fractions, standardizes variants, handles diacritics uniformly, flattens super- and subscripts, converts all numbers to Arabic numerals, and eliminates many other unimportant differences.

    This is the only step that depends on a character database, and most runtimes ship an older one; see [Implementing on a runtime whose Unicode is older](#implementing-on-a-runtime-whose-unicode-is-older). An implementation that has to supply its own NFKC needs three things from the Unicode 17 data: the canonical and compatibility decomposition mappings, the canonical combining class of every character, and the table of primary composites. Derive the third from the decomposition mappings *minus the composition exclusions*; inverting the mappings alone gives the wrong answer for the excluded composites.

5. Remove invisible characters that carry no meaning of their own. These are layout artifacts that editors, mailers and sanitizers inject and remove without asking.

    1. Remove `U+00AD SOFT HYPHEN`, `U+200B ZERO WIDTH SPACE`, and `U+2060 WORD JOINER`. `U+FEFF` is not here; step 2.4 has already removed it.
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

6. Normalize line structure and whitespace. This eliminates invisible differences that are attributable to the preference of a typist, to variable layout choices, or to how many times a message has been quoted on its way here.

    1. Normalize quotation.

        First, the marker. For each line, if it begins with zero or more horizontal whitespace characters followed by `>`, replace that whitespace, the `>`, and every following character that is horizontal whitespace or another `>` with a single `>`. A line whose whole content is that prefix is dropped, as is an empty line, because mailers disagree about whether a blank line inside a quoted region keeps its marker and nothing downstream would have preserved it anyway.

        Every remaining line is now either *quoted*, meaning it begins with `>`, or *unquoted*. Join consecutive lines of the same kind into one line, their contents separated by a single space, a joined quoted line carrying exactly one leading `>`. Keep the line ending wherever a quoted line meets an unquoted one.

        Quoting is what the channels this algorithm serves do to text, and until this step it defeated comparison outright: `> alpha` and `alpha` differ, and so do `> alpha` and `>> alpha`. Afterwards, depth and marker spelling are insignificant while quotedness is not, so the same quotation reaches the same bytes however many hops it has taken and whichever of `> `, `>`, `>>` or `> > ` a client along the way emitted.

        Joining is what makes the number of markers independent of how a client wrapped the text, which matters because reflowing a quotation is the commonest thing a mail client does to a reply. Keeping the boundary is what makes a quotation's *extent* survive, and marking only where one starts would be worse than useless: it would look as though quotation were being tracked while `> Did you murder that man?` followed by `No!` still reached the same bytes as `> Did you murder that man? No!`. Every version of this algorithm before 3.17 collapsed those two, because quotation extent is line structure and 6.2 was throwing line structure away.

        The property this guarantees is important. A signer commits to their own words together with a quoted chunk, as quoted. Whether the inner material is quoted well, or attributed clearly, is not this algorithm's concern &mdash; and quotations at different depths deliberately flow together, so it does not preserve who said what inside them. What it does guarantee is that **the division between the signer's own words and the quoted material survives**: two messages that draw that line in different places cannot reach the same bytes. The only exception is text a reader could not disambiguate either, namely a line of the signer's own words that itself begins with `>`.

        This step runs after recognition, so it never reaches inside a protected span. That is what keeps a Python session's `>>> ` prompts intact inside a fenced block. It also means a quoted fence is not restored to being a fence; recovering the original nesting is the job of whatever protocol carries the text, not of this algorithm. See [Unnesting is not part of this algorithm](#unnesting-is-not-part-of-this-algorithm).
    2. Replace each run of one or more Unicode 17 `White_Space` characters with a single space `U+0020`, or with a single `U+000A` if the run contains one. The set is `U+0009`..`U+000D`, `U+0020`, `U+0085`, `U+00A0`, `U+1680`, `U+2000`..`U+200A`, `U+2028`, `U+2029`, `U+202F`, `U+205F`, and `U+3000`. Step 2.5 has already replaced every line terminator in that set with `U+000A`, and step 6.1 has joined every line within a passage of one kind, so the only line endings that can still be present are the boundaries 6.1 chose to keep.
    3. Trim leading and trailing spaces and line endings.

    This deliberately converts line structure into spaces, with one exception: a line ending survives where the text changes between quoted and unquoted. That exception exists for the same reason the rest of the rule does. A line break generally carries no meaning and is therefore noise; a line break between one speaker and another carries all of the meaning there is, so discarding it would let a reply be read as part of the question it answers.

    Everywhere else the rule stands, and CQT remains unsuitable for unfenced poetry, source code, tables, or anything else where a line break carries meaning &mdash; which is what fenced blocks are for.

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

        The three whose second character is a letter &mdash; `:D`, `:p` and `:o` &mdash; convert only when the character that follows is not an ASCII letter, digit, `-` or `_`. Without that guard the table rewrites identifiers: `did:peer` becomes `did:-peer`, `urn:oid` becomes `urn:-oid`, and `did:keri:DKxy...` becomes `did:keri:-DKxy...` because a `D`-coded CESR key follows the colon. The guard is on the trailing side only, so `lol:p` still converts.

    9. Attach punctuation to the side it binds to, by removing a space that separates it from what it belongs with. Remove a run of spaces when the character after the run has General Category `Pe` or `Pf`, or has the Unicode 17 `Terminal_Punctuation` property; and remove a run of spaces when the character before it has General Category `Ps` or `Pi`. The test is on the run, not on each space within it.

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

## Recognizing protected content

The three kinds of protected span, in the precedence recognition applies to them.

Fenced code blocks are recognized first. Inline code spans and HTTP(S) URLs are then recognized in whatever prose remains, which is a set of segments, each lying between two fences or at one end of the input. Scanning happens within a segment and never across one, so a backtick before a fence cannot pair with a backtick after it, and a URL stops at a fence boundary.

Within a segment, scan left to right and take whichever span begins first. The two kinds cannot begin at the same place, since a code span starts at a backtick and a URL at an `h`, so no tie-break is needed. They can still meet: a backtick ends a URL span, and then opens a code span of its own, so in `http://a.test/x` followed by a backtick the URL stops there and the backtick begins something new.

### Fenced code blocks

For fence recognition, a line ending is exactly LF (`U+000A`). Step 2.5 has already replaced every other line terminator with one, so a CR, a NEL or a LINE SEPARATOR in the input does end a line here &mdash; not because this grammar recognizes it, but because by the time this grammar runs it has become an LF. A complete line is the text from the start of the input, or from just after a line ending, up to and including the next line ending or the end of the input.

An opening fence is a complete line containing, in order: any amount of horizontal whitespace; a run of three or more backticks; an optional info string containing no backtick; and then a line ending or the end of input. A closing fence is a later complete line containing any amount of horizontal whitespace, a backtick run at least as long as the opening one, and then a line ending or the end of input. Step 2.6 has already removed any whitespace between that run and the line ending.

There is no limit of three spaces on either line. CommonMark imposes one so that a fence can be told apart from a four-space indented code block; this algorithm has no indented code blocks, so the limit would protect nothing and would cost a fence that a quoting client had indented. Both delimiter lines are reproduced at column zero whatever their indentation was, so two copies of a block that differ only in how far a mail gateway pushed them over produce the same bytes. Indentation *inside* the block is content and is never touched, which is what Python depends on.

The closing run may be longer than the opening one, and a block that needs to contain a run of backticks is opened with a longer run than any it contains. Requiring the two to match exactly would be worse rather than tidier, because an opener that fails to close now protects everything after it.

The protected span covers the opening and closing lines, the line ending that follows the closing line, and the line ending that precedes the opening line. Taking the preceding line ending keeps the fence at the start of a line after the surrounding prose has been flattened into spaces.

When one fence begins on the line after another ends, that preceding line ending has already been taken by the earlier span. Spans never overlap: the later span begins where the earlier one ended, and the shared line ending belongs to the earlier.

An opening fence with no closing fence protects everything from where it begins to the end of the input.

Truncation is ordinary. A "show more" fold, a message length limit, an SMS split, a quoting client that trims &mdash; any of them can remove a closing line. Were the block to become prose when that happens, a one-line loss would reinterpret the entire remainder and produce total divergence, so the rule instead makes it a slope: what is lost is the bytes that were lost. This is also what CommonMark does, which means an author's intuition already matches.

An unmatched run *inside* a line is still prose. An opener has to be a complete line, so backticks in the middle of a sentence cannot start anything.

### Inline code spans

A run of one or more backticks opens an inline code span when a later run of exactly the same length exists and is not part of a longer run. The pair of delimiters and everything between them is protected.

Runs are maximal. An unmatched run is prose in its entirety, and scanning resumes after the whole run; no shorter piece of an unmatched run may open a span.

This is the one place where a small perturbation is not given a slope. Inserting a single backtick upstream shifts the pairing of every span after it, so `` Take `x--y` and `p--q` `` and the same text with one extra backtick reach `Take \`x--y\` and \`p--q\`` and ``Take ``x-y` and `p-q``` &mdash; two spans the perturbation never touched are silently unprotected. An unterminated *fence* is given the end of the input for exactly this reason, and an unmatched inline run is deliberately not: protecting to the end of the segment would mean one stray backtick in a sentence swallowing the paragraph after it, which is a worse failure than the one it prevents. Parity is inherent to paired delimiters and the choice here is between two bad outcomes, not between a bad one and a good one.

Inside the span, each run of one or more line endings, together with any horizontal whitespace that follows it, becomes a single space. An inline code span therefore carries no line structure, and a span whose text a channel has rewrapped produces the same bytes as one it has not. This is the whole of the difference between the two backtick-delimited kinds, and it is why an inline span is the right choice unless the line breaks are the content.

### URI spans

Three forms are recognized at any position in unprotected prose.

**Any scheme followed by `://`.** A scheme is an ASCII letter followed by ASCII letters, digits, `+`, `-` and `.`. There is no list of permitted schemes, because the `://` is what makes recognition safe: those three characters do not occur in prose, so `ftp://`, `ws://`, `file://` and `git://` are no more ambiguous than `https://`.

**`mailto:`, when an `@` appears before the next whitespace.** A bare scheme cannot be recognized on its own, because "note:", "here is the data:" and "what I did:" are all ordinary English. `mailto:` is admitted because the `@` gives it a shape a sentence does not have.

**`data:`, when it presents a well-formed [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397) header**: an optional `type/subtype`, then zero or more `;attribute=value` parameters, then an optional `;base64`, then the mandatory comma. Type, subtype, attribute and value are each an [RFC 2045](https://www.rfc-editor.org/rfc/rfc2045#section-5.1) token, which is printable ASCII other than space, control characters and the tspecials `()<>@,;:\"/[]?=`. The mediatype may be omitted, so `data:,Hello` is a data URI &mdash; but `data:abc,x` is not, because `abc` is not a mediatype.

The comparison is ASCII-only: a character outside `A`-`Z` and `a`-`z` never matches a scheme character, so `U+017F LATIN SMALL LETTER LONG S` does not match `s`. [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986#section-3.1) allows only ASCII letters in a scheme, and an implementation whose case-insensitive comparison applies Unicode case folding will protect text that is not a URI.

The scheme is lowercased using ASCII case only, and so is the host of a URI that has an authority; [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986#section-3.1) defines both as case-insensitive, so this is an equivalence the URL standard states rather than one invented here. Everything else is left exactly as written: userinfo before an `@`, and the path, query and fragment, are all case-sensitive and are reproduced byte for byte. Lowercasing is ASCII-only for the same reason recognition is, and because a Unicode case fold is locale-sensitive for the dotted capital I.

A `data:` URI carries case-insensitive fields of its own, defined by [RFC 2045](https://www.rfc-editor.org/rfc/rfc2045#section-5.1) rather than by RFC 3986: the type, the subtype, and each parameter's attribute name. Those are lowercased, and `;base64` folds with them, being an attribute name with no value. A parameter's *value* is not lowercased &mdash; `charset` values happen to be case-insensitive, but that is RFC 2046 speaking about one parameter rather than a rule about values &mdash; and neither is the payload. So `DATA:TEXT/PLAIN;CharSet=UTF-8,ABC` becomes `data:text/plain;charset=UTF-8,ABC`.

Any other URI with no authority has its scheme lowercased and nothing else. In `mailto:`, that leaves the address alone: SMTP makes the local part case-sensitive, and the domain after the `@` is not an RFC 3986 authority, so `MAILTO:Alice@Example.TEST` becomes `mailto:Alice@Example.TEST`. Folding the domain would mean teaching this recognizer the internal grammar of every scheme it admits.

Recognition is lexical. CQT does not validate the host, resolve the URI, or touch the network.

The span begins at the first character of the scheme, whatever its case, and runs until the first Unicode 17 whitespace character, the first `<`, `>`, `"` or backtick, or the first unmatched closing parenthesis. Parentheses are counted from the end of the recognized prefix, so `https://example.test/Foo_(bar)` is one span. Other trailing punctuation is included rather than guessed to be prose, because it may legally belong to the URL. Percent encoding, non-ASCII spelling, scheme case, repeated hyphens, query ampersands and fragments all survive exactly.

## Worked examples

These are chosen to be dense rather than typical. Each one exercises many rules at once, because the interactions are where implementations diverge; most vectors in [goldens/cqt3.17.json](goldens/cqt3.17.json) test rules one at a time instead.

All three examples are themselves vectors &mdash; `worked-example-typography`, `worked-example-fences` and `worked-example-invisibles` &mdash; so every conforming implementation produces the output shown here, and a test asserts that these blocks and those vectors agree.

Each example gives its input, then its output, then a table pairing the fragments that changed with the step that changed them. Fragments not in the table came through untouched.

### A quotation with mixed scripts and typography

A line from a French press release, pasted through a word processor on the way to a chat client.

Input:

```text
“Le rapport ﬁnal — R&D, 1⁄2 fait — coûte 3--4 k€ ; voir https://example.test/a--b?q=1&r=2 … et c’est prêt !” 😊  日本語も：「テスト」。  राम। श्याम
```

Output:

```text
'Le rapport final - R & D, 1/2 fait - coûte 3-4 k€; voir https://example.test/a--b?q=1&r=2... et c'est prêt!':-) 日本語も:'テスト'. राम। श्याम
```

In the input | becomes | because
--- | --- | ---
<code>&#x201c;</code> <code>&#x201d;</code> <code>&#x2019;</code> <code>&#x300c;</code> <code>&#x300d;</code> | `'` | every quote character folds onto the ASCII apostrophe (step 7.6)
<code>&#xfb01;</code> | `fi` | NFKC breaks the ligature (step 4)
<code>&#xff1a;</code> | `:` | NFKC maps the fullwidth colon to its ASCII form (step 4)
<code>&#x2014;</code> | `-` | every character in the dash category becomes an ASCII hyphen (step 7.1)
`3--4` | `3-4` | a run of two or more hyphens collapses to one (step 7.2)
<code>&#x3002;</code> | `.` | the ideographic full stop becomes an ordinary one (step 7.3)
<code>&#x2026;</code> | `...` | the ellipsis expands to three full stops (step 7.4)
<code>1&#x2044;2</code> | `1/2` | the fraction slash becomes an ordinary slash (step 7.5)
<code>&#x1f60a;</code> | `:-)` | an autocorrect substitution is run backwards (step 7.7)
`R&D` | `R & D` | a bare ampersand is spaced out whatever surrounds it (step 7.10)
`k€ ;` and `prêt !` | `k€;` and `prêt!` | French typography spaces these; both bind to their left, so the space goes (step 7.9)
`https://example.test/a--b?q=1&r=2` | unchanged | a URL is a protected span, so neither step 7.2 nor step 7.10 ever sees it (step 3)
`राम। श्याम` | unchanged | the danda binds left, and nothing binds rightward, so the space after it stays (step 7.9)
two spaces | one space | a run of whitespace collapses to a single space (step 6.2)

Two rows above depend on an earlier one having already fired. The ellipsis is expanded to `...` by step 7.4 and only then attached leftward by step 7.9, which is why the space between it and the URL disappears: <code>&#x2026;</code> is not terminal punctuation, but `.` is. The emoji loses the space in front of it for the same reason, having become something that starts with a colon.

### A reply that quotes what it answers

An email reply, with the marker spelled three different ways because three different clients touched it.

Input:

```text
> I checked with the team and they say
>the 14th is tight but possible.
Then let's commit to it.

  >> Shall I tell the customer?
Yes -- and cc me.
```

Output:

```text
>I checked with the team and they say the 14th is tight but possible.
Then let's commit to it.
>Shall I tell the customer?
Yes - and cc me.
```

In the input | becomes | because
--- | --- | ---
`> ` and `>` on the first two lines | one `>` for the pair | both lines are quoted, so they join into one passage carrying a single marker (step 6.1)
the line ending between them | a space | lines within a passage are joined, so how a client wrapped the quotation stops mattering (step 6.1)
`  >> ` | `>` | the indentation and the depth both go; whether text is quoted is significant, how many hops it has taken is not (step 6.1)
the line ending after `possible.` | kept | it separates quoted text from unquoted, and that boundary is what stops a quotation absorbing the reply beneath it (step 6.1)
the blank line | removed | a blank line belongs to whatever surrounds it, so it can neither split a passage nor create one (step 6.1)
`--` | `-` | a run of two or more hyphens collapses to one (step 7.2)

Three line endings survive in the output and every other one becomes a space. Each survivor marks a change of voice. Without them the first answer would run into the question above it, and `>I checked ... possible. Then let us commit to it.` would be indistinguishable from a message in which the sender had quoted both sentences.

### Prose wrapped around machine-readable syntax

A chat message giving someone advice, with a command, a snippet and a complaint in it.

Input:

````text
Run  it with `--dry-run  &  --verbose` first.
```python
subprocess.run("ls  -l && pwd", shell=True)   # don’t  do  this
```
I keep typing ``` and getting nothing.
````

Output:

````text
Run it with `--dry-run  &  --verbose` first.
```python
subprocess.run("ls  -l && pwd", shell=True)   # don’t  do  this
```
I keep typing ``` and getting nothing.
````

In the input | becomes | because
--- | --- | ---
the doubled spaces in the prose | single spaces | prose gets the whole algorithm, so a run of whitespace collapses (step 6.2)
the inline code span | unchanged | it is protected, so its doubled spaces, the `--` of each flag and its unspaced `&` are never seen by steps 6.1, 7.2 and 7.10 (step 3)
the ```` ```python ```` block | unchanged | it is protected too, so its doubled spaces, its `&&`, its double quotes and its curly apostrophe all survive (step 3)
the line endings around the fence | unchanged | the span takes the line ending before the opening fence and the one after the closing fence, which is what keeps the fence at the start of a line (step 3)
the trailing ```` ``` ```` | unchanged | an opener has to be a complete line, and these sit in the middle of one, so they are three ordinary characters of prose

Only the first line changes. Everything the author marked survives exactly, including five things &mdash; a doubled space, a doubled hyphen, an unspaced ampersand, an ASCII double quote and a curly apostrophe &mdash; that the prose rules would have rewritten had they appeared a few characters earlier.

### Invisible characters

Nothing here is legible as text, so a character that cannot be seen is written as its codepoint in angle brackets. `<200B>` stands for one `U+200B`, and the angle brackets are notation rather than input.

Input:

```text
ปาก<200B>กา a<200B>b  soft<00AD>hyphen  file<202E>gnp.exe  a<0000>b  क्<200D>ष
```

Output:

```text
ปาก<200B>กา ab softhyphen filegnp.exe ab क्<200D>ष
```

In the input | becomes | because
--- | --- | ---
`ปาก<200B>กา` | unchanged | Thai writes without spaces and divides words with `U+200B`; both neighbors qualify (step 5.2)
`a<200B>b` | `ab` | here the neighbors are Latin, so the same character is a layout artifact (step 5.1)
`soft<00AD>hyphen` | `softhyphen` | a soft hyphen is a hint to a line breaker (step 5.1)
`file<202E>gnp.exe` | `filegnp.exe` | the override displays this as `fileexe.png`, so it cannot be signed as one thing and read as another (step 2.3)
`a<0000>b` | `ab` | a control character is not plain text (step 2.2)
`क्<200D>ष` | unchanged | the zero width joiner selects the conjunct, changing which glyph a reader sees (step 5.3)

An unpaired surrogate is removed here too, by step 2.1, but it cannot appear in this example: JSON has no portable spelling for a lone surrogate, so no vector could pin it, and on three of the six runtimes in this repository a string cannot hold one in the first place.

## Conformance

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in [BCP 14](https://www.rfc-editor.org/info/bcp14) &mdash; [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) &mdash; when, and only when, they appear in all capitals. The algorithm's own steps are written as plain imperatives rather than as obligations; a keyword appears where a duty falls on a party, which is to say on an implementer, a protocol, or a verifier.

The algorithm in this document and the vectors in [goldens/cqt3.17.json](goldens/cqt3.17.json) are normative. An implementation MUST implement the complete algorithm and MUST produce, byte-for-byte, the output that every vector specifies. Where a vector and this prose disagree, the vector controls, and the disagreement is a defect in this document that MUST be reported rather than generalized to other inputs.

The Python implementation in [impl/python/cqt.py](impl/python/cqt.py) is a reference, not a source of normative behavior.

CQT 1.14 and CQT 2.17 are different and incompatible algorithms. Hashes and signatures identified as `cqt1.14` or `cqt2.17` remain historical data and MUST NOT be recomputed or relabeled as `cqt3.17`. See the [CQT 2.17 legacy notice](cqt2.17.md).

### Implementing on a runtime whose Unicode is older

As of the date when this spec was written, several runtimes ship a Unicode version behind 17, and normalization is the only part of this algorithm that is version-sensitive. The four character sets above are enumerated here precisely so property lookups need not be. An implementation has three options, and the vectors will tell it whether it succeeded.

Raise the runtime, where the ecosystem offers a version with Unicode 17 tables. This is the least clever option and the most reliable.

Substitute a proxy, where a character's properties are wrong in the runtime's tables but the character influences normalization *only* through the property in question. Replace it with a different character the runtime already gives the correct property, normalize with the stock normalizer, and swap back. The result is exact rather than approximate, because the normalizer is never asked about a character whose data it has wrong. Restoration is unambiguous because canonical ordering is a stable sort, so proxies emerge in the order they entered.

Pre-substitute a decomposition, where a character's compatibility mapping is missing. `U+A7F1` maps to `S` under Unicode 17 and to itself under 16, and both have combining class 0, so replacing it before normalizing is exact.

Whichever route is taken, test the normalizer on *sequences* and not only on single characters. A platform normalizer can have correct tables for every scalar and still be wrong when it recomposes: while this specification was being written, `golang.org/x/text` was found to truncate a supplementary-plane starter to 16 bits before its composite lookup, so `U+10041` followed by `U+0301` produced `U+00C1`, and the same clipping made Hebrew `U+05D2 U+0307` produce a Todhri letter. Per-scalar checking cannot find that class of defect. The vectors `astral-starter-survives-normalization` and `hebrew-letter-with-combining-dot` exist to catch it.

What defeats all three is a change to composition itself &mdash; a new primary composite, or a change to the composition exclusion list &mdash; because no substitute behaves like a character that composes differently. Between Unicode 16 and 17 there is no such change, which is why a Unicode 16 runtime can be made exactly conformant. That is a fact about those two versions and not a general guarantee.

A later revision may add vectors, and an implementation that passed before may fail afterwards. That is not a change to the algorithm and it invalidates no signature; it means the implementation was always wrong and nothing had caught it yet. This is not hypothetical &mdash; one of the ports here passed every vector for a day while silently corrupting Hebrew text, until a vector was added that could see it.

An implementation in this repository is conformant exactly insofar as it passes every vector, and no further. Each one carries its own test harness that runs the vectors, so its status is a fact that can be checked rather than a claim made here; an implementation whose harness does not pass MUST NOT be used to produce or verify a `cqt3.17` commitment.

CQT 3.17 never rejects text. Every input produces output; there are no error conditions and no failure modes to specify. Human text has spelling errors and grammar errors, but it does not have syntax errors, and an algorithm that canonicalizes it has no business complaining about it.

## Unnesting is not part of this algorithm

Step 6.1 makes quoting depth insignificant, which is what a canonical form needs. It does not recover the message that was quoted, and it cannot: by design it collapses the very depth that would tell you how many hops a passage has taken.

Recovering the original nesting &mdash; taking a reply, peeling off one level of `>`, and asking whether what emerges carries a signature of its own &mdash; is a protocol's job, performed on the raw text before this algorithm runs. Canonical form is not something to transport; it is recomputed at the moment a signature is checked, one nesting level at a time, and the raw text remains available throughout.

Nothing about that procedure is versioned here, deliberately. It is the part of the problem where practice is still being learned, and a rule that lives outside the frozen function can be corrected without invalidating a signature.

Two things are worth stating for anyone building it. A verification failure is not proof of duplicity; it is proof of duplicity **or** of quoting that was lossy or accidental, and reporting the disjunction honestly is the correct result. And the narrowest claim that can succeed is the right claim to make, because quoters excerpt, and a claim over more text than survived the hop cannot be checked at all.

## Caveats
This algorithm collapses some differences that are usually insignificant in written text. Note the word "usually". The algorithm might not distinguish certain input texts having subtle distinctions. For example:

* Because the algorithm collapses the distinction between halfwidth and fullwidth forms, two Chinese sentences &mdash; one written with halfwidth forms, and the other written with fullwidth forms &mdash; will produce the same output.
* Because of the conversion of certain mathematical operators to ASCII, and because the algorithm normalizes punctuation, two sentences that contain mathematical or computer science expressions might produce the same output when they are actually slightly different (e.g., the expression `i--` and the expression `i-` produce identical output; so do <code>x&#xb2;</code>, <code>x&#x2082;</code>, and <code>x2</code>). Fenced blocks and inline code spans exist so that such text can be exempted.
* Markup escapes are not decoded. An entity keeps its ampersand, and step 7.10 spaces it out: `A &amp; B` reaches `A & amp; B` and `caf&eacute;` reaches `caf & eacute;`. That is deterministic, so two escaped copies still agree, but an escaped copy will never agree with an unescaped one. An application that stores text HTML-escaped MUST decode before calling CQT.

    This is a deliberate choice rather than an omission, and it was measured before it was made. Decoding the five XML predefined entities &mdash; `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;` &mdash; was specified, implemented and tested, and then rejected on the evidence. In a corpus of 30,732 real messages, entities in a `text/plain` part turned out to be an artifact of machine-generated bulk mail, where a template engine strips tags without decoding: 5.81% of bulk messages carried one of the five, against **0.34% of messages that were replies in a human conversation**. Text that someone composes and signs is the second population, not the first. Two further findings pointed the same way. Roughly 39% of the messages that did carry an entity carried it inside a URL, where a protected span puts it beyond reach of any such rule. And the standard escapers do not emit only those five: both Python's `html.escape` and PHP's `htmlspecialchars` spell the apostrophe as a numeric character reference, and numeric references cannot be decoded safely at any point in this algorithm &mdash; before step 2 they can synthesize backticks and line endings that fabricate protection, and after it they can rebuild a span placeholder from `&#0;` or restore a directional override that step 2.3 removed.

    The general principle is worth stating, since it will be proposed again. Every other rule here rewrites one character as another on the authority of Unicode or of RFC 3986. A rule that decoded entities would instead assert that a sequence of characters means something other than itself, on the authority of HTML, inside a document this specification defines as not being HTML. That is a different kind of rule, and a roughly 0.3% improvement does not justify inclusion.
* A `data:` URI is protected only when it is well formed, and the payload is held to the same standard. `data:text/plain,a--b` is protected; `data:abc,a--b` is prose, and its doubled hyphen collapses like any other, because `abc` is not a mediatype. Inside the URI, RFC 2397 defines the data as `*urlchar`, and a raw `"` is not one &mdash; so `data:application/json,{"a":"x--y"}` is recognized but the span ends at the first quote, and what follows canonicalizes as prose. Percent-encode the payload and the whole thing survives exactly. A URI that matches its grammar is protected, and text that does not is text.
* Tabs are never expanded. A tab is meaningful in the syntaxes protected content exists to carry &mdash; a Makefile recipe line requires one and is an error with spaces, Go is canonically tab-indented, and TSV is defined by them &mdash; and expanding one would require inventing a tab stop width. Transport preserves tabs in any case; what it mangles is line endings and trailing space, which step 2 now normalizes.
* Quoting depth is insignificant, so `> alpha`, `>> alpha` and `> > alpha` all reach the same bytes, and so does prose that begins with a doubled `>` for some other reason. Quotedness itself is preserved, and so is the boundary: `> alpha` never reaches the same bytes as `alpha`, and neither does `> alpha` followed by `beta` reach the same bytes as `> alpha beta`.
* Because depth is insignificant, two quotations at different depths that are adjacent to each other join into one. A message in which `>> question` is answered by `> answer` therefore reaches the same bytes as one in which a single speaker was quoted saying both. The distinction between quoted and unquoted survives; the distinction between one quoted speaker and another does not.
* Because the algorithm normalizes punctuation, text that is picky about punctuation may lose precision. For example, the instruction from an English teacher, `Always place a comma inside double quotes: "abc,"` is normalized to the same value as `Always place a comma inside double quotes: 'abc,'` (which contains no double quotes, despite what the text says).
* Removing `U+200B` costs something in Thai, Lao and Khmer even with the exemption in step 5.2, because the exemption requires both neighbors to be in those scripts. A `U+200B` that divides a Thai word from a Latin one is treated as an artifact and removed.

This algorithm also leaves intact some differences that some audiences may wish to collapse. Notably, *it does not normalize case*, and it does not fold visually confusable characters; a caller who wants to warn a signer about mixed-script text should use [Unicode Technical Standard #39](https://www.unicode.org/reports/tr39/) alongside CQT rather than in place of it. Also:

* A poetry sample written on separate lines produces different output from poetry written with lines separated by slashes ("Once upon a midnight dreary / While I pondered, weak and weary").
* Emojis that differ only in skin tone are considered different.
* ASCII emphasis (e.g., `I'm *really* serious`) is untouched and does not equate to italics or bolded text.
* Most dingbats (e.g., fancy versions of question marks and check marks) are not normalized.
* The autocorrect replacements do not all interact with spacing the same way, because step 7.9 asks which side punctuation binds to. A replacement that begins with a colon binds left, so `hello \u2639` becomes `hello:-(` with the space gone. One that begins with an opening parenthesis binds right, so `hello \u00a9` becomes `hello (c)` with the space intact, and therefore still differs from `hello(c)`. Both follow from 7.9 as written, but the convergence is narrower for `\u00a9`, `\u00ae` and `\u2022` than for the emoticons.
* Because each step runs once, a transformation that would have enabled an earlier step does not get a second chance. `:)` becomes `:-)`, and so does `hello :)`, because the emoticon is recognized before the space in front of it is removed. But `: )` becomes `:)` and stops there: closing the gap produces an emoticon that step 7.8 has already gone past. Text that has been mangled into `: )` by something upstream will not be recovered.

### High-entropy identifiers in prose

This algorithm normalizes punctuation, and some of that normalization destroys machine-readable identifiers that a person pastes into prose without marking them.

The rule that does the most damage is the hyphen-run collapse in step 7.2. Base64url uses `-` as one of its 64 characters, so a doubled hyphen occurs inside just over 1% of 44-character values &mdash; a KERI AID, a JWT segment, a `did:ion` or `did:webvh` body &mdash; and CQT rewrites it to a single hyphen. The change is silent, and the result still looks like a valid identifier. PEM armor fares worse and fares that way every time: `-----BEGIN PUBLIC KEY-----` becomes `-BEGIN PUBLIC KEY-`.

Many encodings are unaffected. Hexadecimal of any length, UUIDs, bech32 and RFC 4648 base32 addresses, base58 (Bitcoin, `did:key`, CID v0), standard base64, ULIDs and LEIs all pass through untouched, because none of them can produce a character this algorithm rewrites. Case is never normalized, so a mixed-case checksum such as EIP-55 is safe. A value that appears inside an HTTP(S) URL is already a protected span and needs nothing further.

The [entviz gallery](https://dhh1128.github.io/entviz/gallery.html) collects representative values across most of these families &mdash; UUIDs, hashes, blockchain and bech32 addresses, SSH keys, CIDs, snowflakes, LEIs, DIDs, URNs and CESR primitives &mdash; and is a reasonable corpus to test an integration against.

**Mark any such value as protected content.** Inline backticks are enough for a single identifier, and a fenced block is right for a key, a certificate, or anything that spans lines. Inside either, no transformation applies and the bytes are reproduced exactly.

This is the only reliable answer, and it is deliberate rather than an omission. CQT could not recognize a high-entropy token automatically without a heuristic, and any heuristic broad enough to catch a bare AID would also fire on ordinary words. Protection is explicit because the author is the only party who knows which characters are load-bearing.

An application that helps people compose text destined for CQT should nonetheless consider warning when a value like this appears without backticks around it. What makes a heuristic unusable inside this algorithm is that a false positive would silently change the bytes being signed; in an editor, a false positive is a prompt the author dismisses. The recognition that cannot be specified here is safe and useful one layer up, at the moment the author can still fix it.

### On the output

Finally, the output of this algorithm is a canonical form, not a substitute for the input. Running CQT on its own output may produce something different again, and that is expected: the algorithm is a projection from human text, applied once, at the moment something is signed or verified.

## Appendix: what the version numbers promise

Neither number is a compatibility signal. `cqt3.17` names one exact function, and anything that computes different bytes gets a different name. A change to the logic here produces `cqt4.17`; adopting a later Unicode produces `cqt3.18`. Both break existing signatures, because both change the output for some inputs &mdash; moving from Unicode 16 to 17 altered one compatibility mapping and gave 34 characters a combining class they had not had, which is enough to change the canonical form of any text containing them. There is no version of this algorithm that is "compatible enough" with another, which is why a verifier MUST reject an identifier it does not support rather than falling back to one it does.

Once published, `cqt3.17` is frozen. A defect found in it is not repaired by amending this document; it is repaired by publishing a new algorithm under a new number, leaving this one in place with its defect intact, because signatures already made depend on exactly the bytes it produces today.

This document may still be revised, so long as the bytes do not move. A revision MAY correct prose, state a behavior that was always required but never written down, add vectors that pin behavior already mandated, or fix a reference implementation that disagreed with this specification. It MUST NOT change what any conforming implementation outputs. Revisions are dated, and this is the **2026-08-30 revision**.

Cite the revision when reporting conformance, and bind only `cqt3.17` into anything signed. A signature that named a revision would reject bytes that are identical to the ones it covers.

