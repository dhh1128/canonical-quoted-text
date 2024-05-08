# canonical-quoted-text
A simple but powerful algorithm for canonicalizing chunks of text that flow not via files but via chat, copy/paste, or other non-file-oriented channels (social media, SMS, email, etc.). Note the reference implementation in python [cqt.py](cqt.py), and ports in javascript [cqt.js](cqt.js), java [Cqt.java](cqt.java), go [cqt.go](cqt.go), and rust [cqt.rs](cqt.rs). Note also the unit tests in [test_cqt.py](test_cqt.py).

### Purpose
Cryptographic hashes and signatures are usually applied to files or data structures. However, a very important category of communication is not file-oriented. In our modern world, lots of text moves across system boundaries using mechanisms that are prone to reformatting and error due to their inherent fuzziness. We see a post on social media on our phones, copy it, and paste it into a text to a friend. She emails it to a journalist acquaintance, who moves it into a word processor that is configured to use a different locale with different autocorrect and punctuation settings. Eventually, a student cites the journalist in a paper they're writing. Somewhere along the way, whitespace is deleted, capitalization or spelling is altered, the codepage changes, smart quotes turn into dumb quotes or two hyphens become an em dash.

In this scenario, how can we evaluate whether the final text is *the same* as the original?

Of course, opinions about what constitutes *sameness* vary. There is no objectively correct answer. However, we can create *deterministic* answers that are useful. They can help us decide whether minor text changes are likely to matter, and check to see whether a digital signature matches a piece of text.

The algorithm documented here is for such cases. It says that two chunks of text are *the same* if, when transformed by the algorithm, they produce output that matches byte-for-byte.

### Official name and version

The full name of this algorithm is "canonical quoted text 1.14", but it is typically abbreviated "cqt1.14".

The name contains two numbers. The first number ("1") versions the logic of the algorithm, and the second number ("14") references a version of the Unicode standard that documents certain details. For all mainstream modern languages, the Unicode standard is fairly stable, so the algorithm is likely to produce identical or near-identical results even if the second number varies slightly. This is similar to the spirit of [semver.org](https://semver.org), but its definition of minor version semantics varies from it slightly. 

The output of this algorithm can be piped to a hashing function to produce a *canonical hash* of text. For example: `canonical hash = Blake3(cqt1.14(text))`. The output of this algorithm can also be piped directly to a digital signature function to produce a *signature over canonical text* for text. For example: `signature over canonical text = EdDSA(cqt1.14(text))`. Perhaps better (because it allows text value to be disclosed later), a signature can also take as input a canonical hash, producing a *signature over canonical hash*. For example: `signature over canonical hash = EdDSA(Blake3(cqt1.14(text)))`. This formal notation can be used in specs and machine-processable metadata. If machines are parsing such expressions, all strings in the notations MUST be compared case-insensitively, with whitespace and all punctuation except parentheses removed.

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


1. Convert the text to Unicode, eliminating codepages as a source of difference. Represent the data in whichever encoding of Unicode (UTF-8, UTF-16, UTF-32...) is convenient; subsequent steps are described as Unicode operations rather than byte operations.

2. Normalize the text to [Unicode's Normalization Form KC (NFKC)](https://www.unicode.org/reports/tr15/). This converts Chinese, Japanese, and Korean languages ([CJK](https://en.wikipedia.org/wiki/CJK_characters)) from [halfwidth]((https://en.wikipedia.org/wiki/Halfwidth_and_Fullwidth_Forms_(Unicode_block))) to [fullwidth](https://en.wikipedia.org/wiki/Halfwidth_and_Fullwidth_Forms_(Unicode_block)) forms, breaks ligatures, decomposes fractions, standardizes variants, handles diacritics uniformly, flattens super- and subscripts, converts all numbers to Arabic numerals, and eliminates many other unimportant differences.

3. Replace all instances of the ampersand (&amp; `U+0038`), the small ampersand (&#xFE60;, `U+FE60`), and the fullwidth ampersand (&#xFF06; `U+FF06`) with ` and ` (the word "and" with a space before and after).

3. Normalize whitespace. This eliminates invisible differences that are attributable to the preference of a typist or that constitute variable layout choices.
    1. Replace each run of any of the following characters with a single space: `U+2028 Line Separator`, `U+2029 Paragraph Separator`, `U+200B Zero Width Space`, `U+FEFF Zero Width Non-Breaking Space`, `U+00A0 Non-Breaking Space`, `U+3000 ideographic space`, carriage return `U+000A` (`\r`), line feed `U+000D` (`\n`), tab (`\t`).
    2. Trim all leading and trailing whitespace, where "whitespace" means any item in the [Unicode Character DB](https://www.unicode.org/reports/tr44/) that is defined to have `White_Space=yes`.
    3. Replace all sequences of two or more whitespace characters with a single space `U+0020`.
   
4. Normalize punctuation. This eliminates differences that are hard to see, that might be introduced by autocorrect in editors, or that are attributable to the preference of a typist.
   1. Replace all characters in the Unicode dash punctuation category (Pd); see [this list](https://unicodeplus.com/category/Pd) with the more conventional ASCII hyphen `-` (`U+002D`).
   2. Replace any runs of multiple hyphens with a single hyphen.
   3. Convert some CJK characters (from Unicode's CJK Symbols and Punctuation block from the fullwidth half of the CJK Halfwidth and Fullwidth Forms block) into their ASCII equivalents:
   
       CJK character | Codepoint | ASCII equivalent
       --- |---------------| ---
       Ideographic comma <code>&#x3001;</code> | `U+3001` | , (ordinary comma, `U+002C`)
       Ideographic full stop <code>&#x3002;</code> | `U+3002` |  , (ordinary full stop, `U+002E`)
       CJK fullwidth ASCII printable chars | `U+FF01` to `U+FF5E` | codepoint - 0xFEE0: ordinary ! to ~
   
   4. Replace an ellipsis (&#x2026; `U+2026`) with three instances of the period/full stop `.` (`U+002E`).
   5. Truncate any run of more than 3 full stops.
   6. Replace the fraction slash (&#x2044; `U+2044`) with the ordinary slash `/` (`U+002F`).
   7. Replace various characters that are used as quotes with the least common denominator, the ASCII apostrophe `'` (`U+0027`):
   
       Quote Char | Codepoint
       --- | --- 
       ASCII double-quote `"` | (`U+0022`)
       Left smart apostrophe <code>&#x2018;</code> | `U+2018`
       Right smart apostrophe <code>&#x2019;</code> | `U+2019`
       Left smart double quote <code>&#x201c;</code> | `U+201C`
       Right smart double quote <code>&#x201d;</code> | `U+201D`
       Left guillemet <code>&#x00AB;</code> | `U+00AB`
       Right guillement <code>&#x00BB;</code> | `U+00BB`
       Single left-angle quote <code>&#x2039;</code> | `U+2039`
       Single right-angle quote <code>&#x203A;</code> | `U+203A`
       CJK left-angle quote <code>&#x3008;</code> | `U+3008`
       CJK right-angle quote <code>&#x3009;</code> | `U+3009`
       CJK double left-angle quote <code>&#x300A;</code> | `U+300A`
       CJK double right-angle quote <code>&#x300B;</code> | `U+300B`
       CJK left corner bracket <code>&#x300C;</code> | `U+300C`
       CJK right corner bracket <code>&#x300D;</code> | `U+300D`
   
   8. Remove all spaces that immediately precede or immediately follow a punctuation character.
   9. Undo some common autocorrect transformations in word processors by converting fancier Unicode characters to their ASCII equivalents:
   
       Unicode character | Codepoint | ASCII equivalent
       --- | --- | ---
       &#x1f60A; | `U+1F60A` | :-)
       &#x1f610; | `U+1F610` | :-&vert;
       &#x2639; | `U+2639` | :-(
       &#x1f603; | `U+1F603` | :-D
       &#x1f61D; | `U+1F61D` | :-p
       &#x1f632; | `U+1F632` | :-o
       &#x1f609; | `U+1F609` | ;-)
       &#x2764; | `U+2764` | <3
       &#x1f494; | `U+1F494` | </3
       &copy; | `U+00A9` | (c)
       &reg; | `U+00AE` | (R)
       &bull; | `U+2022` | *
   
   10. Replace some ASCII emojis with their canonical equivalent:
   
       Non-canonical | Canonical equivalent
       --- | ---
       :) | :-)
       :&vert; | :-&vert;
       :( | :-(
       :D | :-D
       :p | :-p
       :o | :-o
       ;) | ;-)

5. Transform the text to UTF-8 to produce a canonical byte stream.

### Caveats
This algorithm collapses some differences that are usually insignificant in written text. Note the word "usually". The algorithm may not distinguish certain input texts having subtle distinctions. For example:

* Because the algorithm collapses the distinction between halfwidth and fullwidth forms, two Chinese sentences &mdash; one written with halfwidth forms, and the other written with fullwidth forms &mdash; will produce the same output.
* Because of the conversion of certain mathematical operators to ASCII, and because the algorithm normalizes punctuation, two sentences that contain mathematical or computer science expressions might produce the same output when they are actually slightly different (e.g., the expression `i--` and the expression `i-` produce identical output; so do <code>x&#xb2;</code>, <code>x&#x2082;</code>, and <code>x2</code>).
* Because the algorithm normalizes punctuation, text that is picky about punctuation may lose precision. For example, the instruction from an English teacher, `Always place a comma inside double quotes: "abc,"` is normalized to the same value as `Always place a comma inside double quotes: 'abc',` (which contains no double quotes, despite what the text says).  

This algorithm also leaves intact some differences that some audiences may wish to collapse. Notably, it does not normalize case. Also: 

* A poetry sample written on separate lines produces different output from poetry written with lines separated by slashes ("Once upon a midnight dreary / While I pondered, weak and weary").
* Emojis that differ only in skin tone are considered different.
* ASCII emphasis (e.g., `I'm *really* serious`) is untouched and does not equate to italics or bolded text.
* Most dingbats (e.g., fancy versions of question marks and check marks) are not normalized.
