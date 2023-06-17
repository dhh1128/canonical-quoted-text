# canonical-text
An algorithm for canonicalizing text.

### Purpose
In our modern world, text moves across many system boundaries. We see a post on social media on our phones, copy it, and paste it in a text to a friend. She emails it to a journalist acquaintance, who speaks a different language and uses a different operating system. Eventually, a student cites the journalist in a paper they're writing. Somewhere along the way, a comma disappears, or capitalization or spelling changes, or the codepage changes, or smart quotes turn into dumb quotes, or two hyphens become an em dash.

In this scenario, how can we decide if the final text *the same* as the original?

Opinions about what constitutes *sameness* vary. There is no objectively *correct* answer. However, many situations call for a *deterministic* answer. The algorithm documented here provides such an option: two chunks of text are *the same* if, when transformed by this algorithm, they produce output that matches byte-for-byte. 

### Official name and version

The name of this algorithm is "canonical text 1.15". The "1" in this string versions the logic, and the "15" in it references version 15 of the Unicode standard. If the same logic is applied to a different version of unicode, the final number should be adjusted accordingly. Logic changes will be reflected in changes to the first numeric component.

### Goals

Given any two input text samples and a literate, thoughtful human who knows the natural language(s) that they embody, the intent is to provide an algorithm that achieves the following goals:

1. If the human considers the samples to embody substantively the same content, the algorithm produces output that is byte-for-byte identical.
2. If the human considers the samples to embody different content, the algorithm produces output that differs in some way.
3. As much as possible, the output of the algorithm should retain the meaning of the original (meaning that the human should *also* view the input and the output as having equivalence).

The third goal is less important than the other two, and may be sacrificed in corner cases. For example, the text of a primer on half-width and full-width CJK forms in Unicode might be distorted by the algorithm, which requires half of those characters to be replaced during canonicalization.  

### Algorithm

Start with input content.

1. Transform the input to plain text.

    >"Plain text" means that the text is ready to be interpreted as IANA media type `text/plain`: it contains no markup intended as instructions to a different formatting engine (escape sequences, HTML/XML tags, and character entities). Many programs that edit rich text already implement such transformations &mdash; when a user copies text, they place both a richly formatted and a "plain text" version of the content on the clipboard. Intent matters; including an HTML tag in plain text is canonical, if the plain text is *intended* to be an instruction about how to construct an HTML tag &mdash; and it is not canonical otherwise. Intent is a function of the input media type. Thus, the text vectors for this algorithm show normative transformations for this step, organized by input media type.

2. Encode the text as UTF-8.
3. Transform the text to [Unicode's NFKC form](https://www.unicode.org/reports/tr15/). (This step is a no-op if the output of step 1 contains no bytes with the high bit set.)
4. Normalize CJK.
   1. Convert [half-width CJK to full-width CJK characters](https://en.wikipedia.org/wiki/Halfwidth_and_fullwidth_forms).
   2. For all [small-form variants](https://www.unicode.org/charts/PDF/UFE50.pdf) or [half- and full-width forms](https://www.unicode.org/charts/PDF/UFE50.pdf) that have an ASCII equivalent, replace with the ASCII equivalent.
5. Normalize whitespace.
   1. Trim all leading and trailing whitespace, where "whitespace" means any item in the unicode character DB that is defined to have `White_Space=yes`.
   2. Replace all instances of the `U+2028 Line Separator` character or the `U+2029 Paragraph Separator` character with an ASCII line feed (byte `0x0D`, written in many programming languages as `\n` and in Unicode notation as `U+000D`). 
   3. Replace all ASCII carriage returns (byte `0x0A`, written in many programming languages as `\r`) with an ASCII line feed.
   4. Replace all sequences of multiple ASCII line feed characters (matched greedily) with a single ASCII line feed.
   5. Replace all instances of the `U+200B Zero Width Space` or `U+FEFF Zero Width Non-Breaking Space` or `U+00A0 Non-Breaking Space` characters with an ASCII space (byte `0x20`). 
   6. Replace all sequences of one or more whitespace characters (as defined above) with a single ASCII space (byte `0x20`).
6. Normalize punctuation.
   1. Replace all hyphen and dash characters in the Unicode character inventory with the more conventional ASCII hyphen `-` (byte `0x2D`).
   2. Replace an ellipsis (`U+2026`) with three instances of the ASCII full stop `.` (byte `0x2E`).
   3. Replace the ASCII double-quote character `"` (byte `0x22`) as well as left- and right single quotes (aka "smart apostrophe", `U+2018` and `U+2019`) and left- and right double quotes (aka "smart quotes", `U+201C` and `U+201D`) plus guillemets (&#x00AB; and &#x00BB; -- double angle quotes familiar from French and other languages, `U+00AB` and `U+00BB`) and their single-angle equivalents (&#x2039; and &#x203A;, `U+2039` and `U+203A`); with the ASCII apostrophe `'` (byte `0x27`)
   4. Remove all spaces that immediately precede or immediately follow a punctuation character.

Result = canonicalized output.