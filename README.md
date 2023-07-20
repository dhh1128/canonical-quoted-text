# canonical-quoted-text
A simple but powerful algorithm for canonicalizing chunks of text that flow not via files but via chat, copy/paste, or other non-file-oriented channels (social media, SMS, email, etc.).

### Purpose
Cryptographic hashes and signatures are usually applied to files or data structures. However, a very important category of communication is not file-oriented. In our modern world, lots of text moves across system boundaries using mechanisms that are prone to reformatting and error due to their inherent fuzziness. We see a post on social media on our phones, copy it, and paste it into a text to a friend. She emails it to a journalist acquaintance, who moves it into a word processor that is configured to use a different locale with different autocorrect and punctuation settings. Eventually, a student cites the journalist in a paper they're writing. Somewhere along the way, a comma disappears, capitalization or spelling is altered, the codepage changes, smart quotes turn into dumb quotes or two hyphens become an em dash.

In this scenario, how can we evaluate whether the final text is *the same* as the original?

Of course, opinions about what constitutes *sameness* vary. There is no objectively correct answer. However, we can create *deterministic* answers that are useful. They can help us decide whether minor text changes are likely to matter, and check to see whether a digital signature matches a piece of text.

The algorithm documented here is for such cases. It says that two chunks of text are *the same* if, when transformed by the algorithm, they produce output that matches byte-for-byte.

### Official name and version

The full name of this algorithm is "canonical quoted text 1.15", but it is typically abbreviated "cqt1.15".

The name contains two numbers. The first number ("1") versions the logic of the algorithm, and the second number ("15") references a version of the Unicode standard that documents certain details. For all mainstream modern languages, the Unicode standard is fairly stable, so the algorithm is likely to produce identical or near-identical results even if the second number varies slightly. This is similar to the spirit of [semver.org](https://semver.org), but its definition of minor version semantics varies from it slightly. 

The output of this algorithm can be piped to a hashing function to produce a canonical hash. The recommended notation for such an operation uses a lowercase hash name and parentheses around this algorithm: `Blake3(fct1.15)`. The output of this algorithm can also be piped to a digital signature function to produce a canonical digital signature. The notation pattern is similar: `EdDSA(fct1.15)`. A signature can also take as input a hash of the output of this function: `EdDSA(Blake3(fct1.15))`. All strings in these notations MUST be compared case-insensitively, with whitespace and all punctuation except parentheses removed.

### Goals

Given any two input text samples and a literate, thoughtful human who knows the natural language(s) that they embody, the intent is to provide an algorithm that achieves the following goals:

1. If the human considers the samples to embody the same semantic content (differing only in insignificant stylistic choices like whitespace), the algorithm produces output that is byte-for-byte identical.
2. If the human considers the samples to embody different content, the algorithm produces output that differs.
3. As much as possible, the human should *also* view the output of the algorithm as semantically equivalent to the input.
4. The algorithm should be easy to implement in a programming language that has good Unicode support.

We live in an imperfect world, so this algorithm makes calculated tradeoffs in the first two goals. Also, the third goal is less important than the first two and might be sacrificed in corner cases. For more on this, see [Caveats](#caveats).

### Algorithm

Start with input content that has been transformed into plain text.

>This is a precondition rather than a step in our algorithm. "Plain text" means that the text is ready to be interpreted as IANA media type `text/plain`: it contains no markup intended as instructions to a different formatting engine (e.g., escape sequences, HTML/XML tags, character entities...). Many programs that edit rich text already implement such transformations &mdash; when a user copies text, they place both a richly formatted and a "plain text" version of the content on the clipboard. However, intent matters; including an HTML tag in plain text is correct, if the plain text is *intended* to be an instruction about how to construct an HTML tag &mdash; and it is not correct otherwise. In other words, any required transformation depends on the initial media type.

1. Convert the text to Unicode, eliminating codepages as a source of difference. Representing the data in whichever encoding of Unicode (UTF-8, UTF-16, UTF-32...) is convenient; subsequent steps are described as Unicode operations rather than byte operations.

2. Normalize the text to [Unicode's NFKC form](https://www.unicode.org/reports/tr15/). This converts CJK from half-width to full-width forms, breaks ligatures, decomposes fractions, standardizes variants, handles diacritics uniformly, flattens super- and subscripts, converts all numbers to Arabic numerals, and eliminates many other unimportant differences.

3. Normalize whitespace. This eliminates differences that are invisible, or that are attributable to the preference of a typist. 
   1. Trim all leading and trailing whitespace, where "whitespace" means any item in the Unicode character DB that is defined to have `White_Space=yes`.
   2. Replace all instances of the `U+2028 Line Separator` character or the `U+2029 Paragraph Separator` character with a line feed (`U+000D`, written in many programming languages as `\n`). 
   3. Replace all carriage returns (`U+000A`, written in many programming languages as `\r`) with a line feed.
   4. Trim leading and trailing whitespace on each line.
   5. Replace all sequences of multiple ASCII line feed characters with a single ASCII line feed.
   6. Replace all instances of `U+200B Zero Width Space` or `U+FEFF Zero Width Non-Breaking Space` or `U+00A0 Non-Breaking Space` or `U+3000 ideographic space` with a simple space (`U+0020`). 
   7. Replace all sequences of two or more spaces with a single space.
   
4. Normalize punctuation. This eliminates differences that are hard to see, that might be introduced by autocorrect in editors, or that are attributable to the preference of a typist.
   1. Replace all hyphen and dash characters in the Unicode character inventory with the more conventional hyphen `-` (`U+002D`).
   2. Replace any runs of multiple hyphens with a single hyphen.
   3. Replace an ellipsis (`U+2026`) with three instances of the period/full stop `.` (`U+002E`).
   4. Truncate any run of more than 3 full stops.
   5. Replace the fraction slash (`U+2044`) with the ordinary slash `/` (`U+002F`).
   5. Replace the ASCII double-quote character `"` (`U+0022`) as well as left- and right single quotes (aka "smart apostrophe", `U+2018` and `U+2019`) and left- and right double quotes (aka "smart quotes", `U+201C` and `U+201D`) plus guillemets (&#x00AB; and &#x00BB; -- double angle quotes familiar from French and other languages, `U+00AB` and `U+00BB`) and their single-angle equivalents (&#x2039; and &#x203A;, `U+2039` and `U+203A`); with the ASCII apostrophe `'` (byte `0x27`)
   6. Remove all spaces that immediately precede or immediately follow a punctuation character.

5. Transform the text to UTF-8 to produce a canonical byte stream.

### Caveats
For example, a paragraph of text that explains half-width and full-width CJK forms in Unicode might be distorted by the algorithm, if it contained samples of both since the algorithm collapses that distinction. Similarly, since the algorithm collapses all runs of hyphens to a single hyphen, text that contains source code having a unary -- operator becomes indistinguishable from text that contains a unary - operator (e.g., `--i` and `-i` produce the same output). 