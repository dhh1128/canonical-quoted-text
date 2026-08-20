# Canonical Quoted Text 2.17

Canonical Quoted Text (CQT) canonicalizes human-readable prose before it is hashed or signed. It is intended for text that crosses reformatting-prone boundaries such as chat, social media, email, and copy/paste.

This repository contains the **draft CQT 2.17 specification**. The `2` identifies this revision of the algorithm; `17` pins every Unicode-dependent operation to Unicode 17.0.0. CQT 1.14 is incompatible and is documented in [cqt1.14.md](cqt1.14.md).

## Conformance

The algorithm in this document and [goldens/cqt2.17.json](goldens/cqt2.17.json) are normative. An implementation MUST implement the complete algorithm and MUST pass every golden vector byte-for-byte. For an input present in the golden file, the golden result controls if it conflicts with prose. Such a conflict is a specification defect and MUST be reported rather than generalized to other inputs.

The Python implementation in [cqt.py](cqt.py) is the first reference implementation. It is not an independent source of normative behavior.

A conforming implementation MUST:

- use the Unicode 17.0.0 character database and Unicode 17 NFKC algorithm;
- produce the required deterministic error for rejected input;
- produce exactly the specified UTF-8 bytes for accepted input;
- be idempotent: applying CQT 2.17 to the UTF-8 output decoded as Unicode MUST produce the same bytes.

## Input and errors

Input is a sequence of Unicode scalar values representing plain text. Decoding from a byte encoding is the caller's responsibility.

Before recognizing protected content or performing normalization, scan the input from left to right. At each position, test the conditions below in table order and report the first error encountered:

Error code | Condition
--- | ---
`invalid-unicode-scalar` | The host-language input contains an isolated UTF-16 surrogate rather than Unicode scalar values.
`unassigned-code-point` | A scalar has Unicode 17 General Category `Cn`, including designated noncharacters. This is the Unicode Normalization Process for Stabilized Strings constraint that prevents future assignments from changing CQT 2.17.
`disallowed-bidi-control` | A scalar is one of `U+061C`, `U+200E`, `U+200F`, `U+202A`–`U+202E`, or `U+2066`–`U+2069`.
`disallowed-control` | A scalar has General Category `Cc` and is not in the Unicode 17 `White_Space` set listed below.
`unclosed-fence` | A recognized opening code fence has no valid closing fence.
`unstable-protected-syntax` | The candidate output would parse or canonicalize differently on a second pass, or normalization creates protected content the input did not have. Either includes the case where normalization would create an unclosed fence.

Validation applies inside protected content too. In particular, a bidi control is never made acceptable by placing it in code or a URL.

## Protected content

Protected content is recognized on the original input, before NFKC. A protected span is copied unchanged to the output and encoded as UTF-8. NFKC, invisible removal, whitespace normalization, punctuation rules, and autocorrect mappings do not inspect its contents.

For surrounding normalization, each complete protected span behaves like a single non-whitespace, non-punctuation character. Thus ordinary spaces surrounding inline code or a URL remain ordinary word-separating spaces.

Recognition has this precedence: fenced code blocks, then inline code and HTTP(S) URLs in the remaining prose.

### Fenced code blocks

For fence recognition, a line ending is exactly LF (`U+000A`), CR (`U+000D`), or the two-scalar sequence CRLF. Other Unicode separators do not form fence lines.

An opening fence is a complete line containing:

1. zero to three ASCII spaces;
2. a run of three or more backticks;
3. an optional info string containing no backtick;
4. a line ending or end of input.

A closing fence is a later complete line containing zero to three ASCII spaces, a backtick run at least as long as the opening run, optional ASCII spaces or tabs, and then a line ending or end of input.

The protected span includes the opening and closing lines, the closing line ending when present, and the line ending immediately before the opening fence when present. This keeps the fence at the start of a line after surrounding prose is flattened. All line endings and content within the span are preserved exactly. An opening fence without a closing fence is an `unclosed-fence` error.

### Inline code spans

A run of one or more backticks opens inline code when a later run of exactly the same length exists and is not part of a longer backtick run. The complete pair of delimiters and everything between them is protected.

Runs are maximal. An unmatched run is ordinary prose, and scanning resumes after the whole run; no shorter piece of it opens a span. Below, the run of three finds no partner, so it does not become a run of two that pairs with the later one, and both space runs collapse.

````text
Input:  a  ```  ``
Output: a ``` ``
````

### HTTP(S) URL spans

The ASCII strings `http://` and `https://` are recognized case-insensitively at any position in unprotected prose. The comparison is ASCII-only. A scalar outside `A`-`Z` and `a`-`z` never matches a scheme character, so `U+017F LATIN SMALL LETTER LONG S` does not match `s`; [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986#section-3.1) allows only ASCII letters in a scheme. An implementation that folds case the Unicode way instead will protect spans that are not URLs. Recognition is lexical; CQT does not validate the host, resolve the URL, or access the network.

The protected span begins with the `h` and continues until the first:

- Unicode 17 whitespace character;
- `<`, `>`, `"`, or backtick; or
- unmatched closing parenthesis.

No control character ends the span. Every `Cc` scalar is either in the `White_Space` set above, which already ends it, or rejected as `disallowed-control` before recognition starts.

Parentheses within the URL are counted, so `https://example.test/Foo_(bar)` is one protected span. Other trailing punctuation is included rather than guessed to be prose, because it may legally belong to the URL. Percent encoding, Unicode spelling, scheme case, repeated hyphens, query ampersands, fragments, and allowed invisible format characters are all preserved exactly.

## Prose algorithm

Conceptually replace every protected span with a distinct non-whitespace, non-punctuation token. Apply the following ordered steps to the resulting prose and tokens, then restore every protected span exactly.

### 1. Unicode normalization

Normalize prose to Unicode 17 Normalization Form KC (NFKC), as specified by [Unicode Standard Annex #15](https://www.unicode.org/reports/tr15/). No host runtime's newer or older Unicode behavior may be substituted.

### 2. Invisible characters

Remove these four layout-only characters from prose:

- `U+00AD SOFT HYPHEN`
- `U+200B ZERO WIDTH SPACE`
- `U+2060 WORD JOINER`
- `U+FEFF ZERO WIDTH NO-BREAK SPACE`

Do not remove `U+200C ZERO WIDTH NON-JOINER` or `U+200D ZERO WIDTH JOINER`; they can be linguistically meaningful. Other accepted format and variation characters are preserved unless another rule explicitly transforms them.

Keep `U+200B` when the scalar before it and the scalar after it both have Unicode 17 `Line_Break` value `SA`. Those scripts write without spaces between words and use `U+200B` to divide them, so removing it merges words their readers keep apart. Both neighbors must qualify. A `U+200B` dropped in by a mailer at a script boundary, or anywhere in Latin, Cyrillic, Arabic, Devanagari, or CJK text, still goes. The set covers Thai, Lao, Khmer, Myanmar, Tai Tham, New Tai Lue, and Ahom:

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

### 3. Whitespace

Replace each run of Unicode 17 `White_Space` characters with one ASCII space `U+0020`, then remove leading and trailing ASCII spaces. The exact set is:

```text
U+0009..U+000D  U+0020  U+0085  U+00A0  U+1680
U+2000..U+200A  U+2028  U+2029  U+202F  U+205F  U+3000
```

This deliberately converts line structure to spaces outside protected content. CQT is unsuitable for unfenced poetry, source code, tables, or other text where line breaks carry meaning.

### 4. Punctuation and autocorrect

Apply these transformations in order:

1. Replace every Unicode 17 `Dash_Punctuation` (`Pd`) scalar with ASCII `-`. The complete set is `U+002D`, `U+058A`, `U+05BE`, `U+1400`, `U+1806`, `U+2010`–`U+2015`, `U+2E17`, `U+2E1A`, `U+2E3A`, `U+2E3B`, `U+2E40`, `U+2E5D`, `U+301C`, `U+3030`, `U+30A0`, `U+FE31`, `U+FE32`, `U+FE58`, `U+FE63`, `U+FF0D`, `U+10D6E`, and `U+10EAD`.
2. Replace every run of two or more ASCII hyphens with one hyphen.
3. Replace `U+3001 IDEOGRAPHIC COMMA` with `,` and `U+3002 IDEOGRAPHIC FULL STOP` with `.`. NFKC has already converted fullwidth ASCII forms.
4. Replace `U+2026 HORIZONTAL ELLIPSIS` with `...`, then truncate every run of four or more periods to exactly three.
5. Replace `U+2044 FRACTION SLASH` with `/`.
6. Replace `U+0022`, `U+00AB`, `U+00BB`, `U+2018`, `U+2019`, `U+201C`, `U+201D`, `U+2039`, `U+203A`, and `U+3008`–`U+300D` with ASCII apostrophe `'` (`U+0027`).
7. Apply the autocorrect tables below, longest source first when one source prefixes another.
8. Remove an ASCII space if the scalar after it has General Category `Pe` or `Pf`, or has the Unicode 17 `Terminal_Punctuation` property. Also remove it if the scalar before it has General Category `Ps` or `Pi`. Punctuation that closes or ends a phrase binds to its left; punctuation that opens one binds to its right.

    No space is removed on the other side, or around any other punctuation, so `Pd` dashes, `Pc` connectors, the solidus, and the ASCII apostrophe keep their spacing. The apostrophe needs no exception of its own, because `Terminal_Punctuation` omits it; step 6 above has already folded every quote onto it and lost the difference between an opening and a closing one.

    Below ASCII 128 the property holds exactly `!`, `,`, `.`, `:`, `;`, and `?`. The complete Unicode 17 set is:

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
9. Repeat steps 1 through 8 of this section until none changes the text. This fixed point is required because removing a space can create a repeated punctuation run or ASCII emoticon across the former boundary.
10. Replace every `&` with ` & `, collapse resulting ASCII-space runs, and trim. Because NFKC maps small and fullwidth ampersands to `&`, `A&B`, `A & B`, and `Ａ＆Ｂ` all become `A & B`.

Unicode/editor form | Canonical form
--- | ---
`😊` | `:-)`
`😐` | `:-|`
`☹` or `☹️` | `:-(`
`😃` | `:-D`
`😝` | `:-p`
`😲` | `:-o`
`😉` | `;-)`
`❤` or `❤️` | `<3`
`💔` | `</3`
`©` | `(c)`
`®` | `(R)`
`•` | `*`

ASCII variant | Canonical form
--- | ---
`:)` | `:-)`
`:|` | `:-|`
`:(` | `:-(`
`:D` | `:-D`
`:p` | `:-p`
`:o` | `:-o`
`;)` | `;-)`

The punctuation-space rule follows these mappings so typographic and ASCII inputs converge. For example, `hello 😊` and `hello :)` both produce `hello:-)`.

### 5. Output

Restore protected spans, then repeat protected-span recognition and prose canonicalization once on the candidate output. If the second result differs or raises a protected-syntax error, reject the original input with `unstable-protected-syntax`.

Comparing the two results is not enough, because normalization can invent protected content and still settle. Apply steps 1 and 2 alone to the prose, restore the spans, and recognize protected content again. If that recognition differs from the recognition on the original input, reject with `unstable-protected-syntax`.

`http<U+200B>://example.test/a--b` holds no URL; the invisible breaks the scheme. So the prose rules collapse `--` to `-` inside what the reader sees as a link, and the result is a URL that was never protected. A byte comparison misses it, because a third pass changes nothing. NFKC does the same whenever it builds a delimiter, out of a fullwidth `ｈｔｔｐｓ：／／`, a long s, a mathematical letter, or `U+FF40 FULLWIDTH GRAVE ACCENT`, which becomes a backtick.

The test covers steps 1 and 2 only. A span may grow in step 4, where removing a space next to punctuation joins it to a preceding URL. `see https://example.test/a , then` depends on that, as do the French `voir https://example.test/a !` and sentence endings in Devanagari, Arabic, and CJK. Nothing inside the link changes there. Only normalization that creates protected content is unstable.

Encode a stable result as UTF-8 without a byte-order mark. These bytes are the CQT 2.17 output.

## Markdown posture

CQT 2.17 recognizes Markdown-style code delimiters as a practical way to mark exact content, but it is not a Markdown parser and does not promise that canonical output is valid Markdown. Outside protected spans, headings, lists, emphasis, tables, hard breaks, link labels, and other markup are normalized as prose. HTTP(S) destinations are protected by URL recognition.

If a protocol needs to sign rendered Markdown semantics rather than textual content, it should define a separate, versioned Markdown profile with a named parser and dialect.

## Security and protocol integration

CQT does not fold case or Unicode confusables. Callers MAY use [Unicode Technical Standard #39](https://www.unicode.org/reports/tr39/) to warn signers about mixed-script or visually confusable text, but a confusable skeleton MUST NOT replace CQT output.

CQT output contains no algorithm prefix. A hashing or signing protocol that uses CQT 2.17 MUST cryptographically bind the exact ASCII identifier `cqt2.17` in its signed envelope or other unambiguous domain separation. A verifier MUST reject an unsupported or mismatched identifier; it must not silently use a locally available Unicode or CQT version.

For example, a signed structured payload can carry both `"alg": "blake3-256(cqt2.17(text))"` and the digest of the CQT output, with both fields covered by the signature. CQT itself does not prescribe a hash, signature algorithm, or envelope encoding.

## Worked examples

Ordinary prose:

```text
Input:  “Down  with ignorance, up with education!”
Output: 'Down with ignorance, up with education!'
```

Ampersands and protected URL data:

```text
Input:  Research ＆ Development: https://example.test/a--b?x=1&y=2
Output: Research & Development: https://example.test/a--b?x=1&y=2
```

Fenced precision-sensitive content:

````text
Input and output are identical:

```python
token = "A  &  B--C"
```
````

## Python reference implementation

Install and test in an isolated environment:

```console
python -m venv .venv
.venv/bin/pip install -e '.[test]'
.venv/bin/pytest -q
```

The Python package uses `unicodedata2==17.0.0` rather than the standard-library Unicode database, whose version varies with Python releases.
