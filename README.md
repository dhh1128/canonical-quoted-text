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
`unstable-protected-syntax` | The candidate output would parse or canonicalize differently on a second pass, including when normalization would create an unclosed fence.

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

A run of one or more backticks opens inline code when a later run of exactly the same length exists and is not part of a longer backtick run. The complete pair of delimiters and everything between them is protected. An unmatched run of backticks is ordinary prose.

### HTTP(S) URL spans

The ASCII strings `http://` and `https://` are recognized case-insensitively at any position in unprotected prose. Recognition is lexical; CQT does not validate the host, resolve the URL, or access the network.

The protected span begins with the `h` and continues until the first:

- Unicode 17 whitespace character;
- control character;
- `<`, `>`, `"`, or backtick; or
- unmatched closing parenthesis.

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
8. Remove an ASCII space if the scalar immediately before or after it has a Unicode 17 General Category beginning with `P`.
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

Restore protected spans, then repeat protected-span recognition and prose canonicalization once on the candidate output. If the second result differs or raises a protected-syntax error, reject the original input with `unstable-protected-syntax`. This prevents removed prose characters from creating a different arrangement of backtick delimiters or URL boundaries.

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
Output: 'Down with ignorance,up with education!'
```

Ampersands and protected URL data:

```text
Input:  Research ＆ Development: https://example.test/a--b?x=1&y=2
Output: Research & Development:https://example.test/a--b?x=1&y=2
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
