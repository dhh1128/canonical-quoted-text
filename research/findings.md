# Findings

Measurements that informed CQT 3.17. Each states its corpus and date. None of this is normative.

## Clipboard round-trip through eleven applications (2026-08-29)

One synthetic message — an inline code span with doubled spaces, a fenced Python block, a `>` quoted line, a URL carrying `--` and a query ampersand, a long line to force wrapping, and straight quotes, `--` and an em dash — pasted into each application, sent, and copied back out of the rendered transcript. Raw captures in `clipboard/`.

**Eleven samples produced six distinct byte strings and three canonical forms.**

| | applications | result |
| --- | --- | --- |
| returned the source **byte-identical** | Discord, Facebook (web), Google Messages (browser), Signal Desktop, Slack *without* formatting, WhatsApp Desktop | **verifies** |
| markers stripped by a renderer | Facebook Messenger, GitHub (rendered issue), Gmail (rendered), VS Code (markdown preview) | fails — but all four reach *one* canonical form |
| markers stripped, plus an artifact | Slack *with* formatting | fails on its own |

The variable is **rendering, not the application**, and Slack supplies the controlled experiment: the same message, pasted twice, differing only in whether its "apply formatting?" prompt was accepted. Declined, the copy is byte-identical to the source and verifies. Accepted, the backticks, the fence and the `>` are gone.

Two details worth keeping. Slack's formatted copy is alone in its canonical form because ` ```python ` leaves the bare word `python` behind as a line of text — the info string leaks into the prose. And CQT is doing real work in the middle row: four renderers emitted four different plain-text serializations, differing in blank-line placement and paragraph merging, and canonicalization collapsed them to identical bytes.

Everything else survived everywhere. The URL came through intact in all eleven, doubled hyphen and query ampersand included, because recognition keys on the literal `https://` rather than on a delimiter a renderer can eat. Prose `--`, straight quotes and the em dash were never autocorrected on the copy path. No capture contained CRLF, an NBSP, or an HTML entity.

### Reconstructing markers from the HTML flavor

Every browser-based application also offered a `text/html` flavor. Mapping `<pre>` back to a fence, `<blockquote>` to `>` and `<code>` to backticks recovers **97.7%** of the canonical form for the four that stripped markers — up from a complete mismatch.

The residue is almost entirely one thing: the fence's info string. `python` lives in a `class="language-python"` attribute rather than in the text, so a flattener that ignores attributes loses it. A reconstructor that knows the convention would recover it, but the convention differs per site, which is exactly why this belongs in a protocol rather than in the algorithm.

Facebook Messenger is the exception, and instructively so: its HTML carried no `<pre>` at all, having flattened the code block into ordinary paragraphs. Where the renderer discarded the structure, nothing downstream can rebuild it.

Note also that doubled spaces inside an inline span survived into the HTML for Messenger and GitHub, and were collapsed for Gmail and VS Code. That is per-site CSS, not a general property of HTML.

## Quote prefixes in real mail (2026-08-29)

30,732 messages from a personal Gmail Takeout export, plus 2,992 from python-dev and python-list.

- **41.5%** of messages contain a quoted block; 17,893 blocks of two or more lines.
- **61% uniform depth, 39% mixed.** The public-list corpus gave 62/38 independently.
- Minimum depth is 1 for the large majority. A long tail runs out to depth 41, some of which is likely decorative `>>>>>>` separator lines rather than real nesting; the two were not distinguished.
- All four marker spellings occur in volume: `>>` on 769,441 lines, `> ` on 428,862, `>` on 243,517, `> >` on 19,286. This is why one quote level is `>` plus *at most one* space rather than `> `.
- Outlook's prefix-free "-----Original Message-----" style: 64 messages, 0.2%.

Re-quoting stability, tested by re-quoting 3,013 real blocks in five client styles: **2,997 of 3,013** reach the same canonical form as the unquoted block under step 6.1, against 0 of 3,013 before it. All sixteen failures contain a backtick, and all have the same cause — an inline code span straddling a line break, so the injected `> ` lands inside protected content.

## Quotation boundaries and reflow (2026-08-29)

2,000 real quoted blocks, reflowed the way a mail client reflows a reply — strip the markers, rewrap, re-add them. This decided how step 6.1 marks quotation.

| marking rule | reflowed at 60 vs at 72 | reflowed vs original |
| --- | --- | --- |
| one `>` per line | 37 / 2000 | 154 / 2000 |
| one `>` per passage, boundary kept | **1643 / 2000** | **1769 / 2000** |

Marking every line makes the number of markers track how the client wrapped the text, so any reflow changes the canonical form. Joining the lines of a passage removes that dependence. Keeping the line ending at the boundary is separate, and it is what stops a quoted question absorbing the reply beneath it; without it, `> Did you murder that man?` followed by `No!` reaches the same bytes as `> Did you murder that man? No!`, as it did in every version before 3.17.

Letting a blank line continue a passage rather than split it is worth 271 of those cases on its own, 88% against 75%, and costs nothing because blank lines do not survive step 6 in any case.

A variant that keeps a boundary wherever the *depth* changes, rather than only where quotedness changes, was measured and rejected: it defeats the same attack one level in and moves zero vectors, but costs about 3% on reflow-versus-original, and attribution inside quoted material is the unnesting layer's job — that layer reads raw text, where depth is intact.

**Outer-partition invariant.** 120,000 generated messages, mixing quoted and unquoted chunks in five marker spellings, including multi-line fenced blocks, fences containing a line that begins with `>`, fences with blank lines and fences with info strings: **zero cases** where two messages dividing their text differently between the signer's own words and the quoted material reached the same bytes. A shortened version of this search runs in the test suite.

## HTML entities in the plain-text part (2026-08-29)

Same Takeout corpus, 27,898 messages carrying a `text/plain` part. This decided against decoding entities; see the Caveats section of the specification.

| message class | any entity | one of the five XML predefined |
| --- | --- | --- |
| bulk (List-Unsubscribe / List-Id / Precedence) | 6.76% | 5.81% |
| replies (In-Reply-To / References) | **0.36%** | **0.34%** |
| other | 3.55% | 1.15% |

Entities in plain text are an artifact of machine-generated mail, where a template engine strips tags without decoding. Text a person composes and signs is the second row. Of the messages that did carry an entity, roughly 39% carried it inside a URL, where a protected span puts it beyond reach of any decoding rule. Numeric character references appeared in 0.77% of plain parts — more than half as often as all five named ones — and cannot be decoded safely at any point in the algorithm.

By occurrence the five dominate: `&gt;` 1373, `&lt;` 1292, `&amp;` 1100, `&quot;` 388, `&apos;` 130, against `&nbsp;` 226 and a thin tail.

## Do a message's two representations agree? (2026-08-29)

26,899 messages carrying both a `text/plain` and a `text/html` part, with the HTML flattened by the deliberately naive tag-stripper in `scripts/mbox-survey.py`.

| | count | share |
| --- | --- | --- |
| canonicalize identically | 2,915 | 10.8% |
| differ only in spacing | 430 | 1.6% |
| within 5% in length | 9,557 | 35.5% |
| outright different | 13,997 | 52.0% |

A better flattener would raise the first row, so 10.8% is a floor. But a 52% majority differing by more than 5% in length means the parts genuinely carry different content — HTML boilerplate, tracking, footers the plain part never had. **Verifying that a message's two representations agree is therefore not a usable defense** against a sender who makes them disagree deliberately; it would reject roughly 88% of honest mail.

Also: **8.5%** of messages carry no `text/plain` part at all.

## Doubled hyphens in base64url (2026-08-29)

Base64url uses `-` as one of its 64 characters, so a doubled hyphen — which step 7.2 collapses — appears in **1.05%** of randomly generated 44-character values (211 of 20,000). That is the rate at which a bare KERI AID, a JWT segment or a `did:ion` body is silently corrupted in unprotected prose.

All 77 distinct samples in the [entviz gallery](https://dhh1128.github.io/entviz/gallery.html) pass through CQT 3.17 unchanged. Three were corrupted under 2.17 — `did:peer`, `did:prism` and `urn:oid`, all by the emoticon table rewriting `:p` and `:o` — which is what the guard in step 7.8 exists to fix.
