# Advice for apps using CQT

Non-normative. [CQT 3.17](README.md) and its [vectors](goldens/cqt3.17.json) are the specification; this is what we have learned about building on it, and it will age as channels change. Dated **2026-08-30**. Measurements cited here live in [research/](research/).

The algorithm answers one question: are these two pieces of text the same? Everything an application has to get right is on either side of that question &mdash; which bytes you hand it, and what you do with the answer. That is what this document is about.

## The rule that matters most

**Compute over source, never over rendered output.**

A markdown renderer destroys every mark CQT relies on. It is not the channel that does this and not the network; it is the act of rendering, and the same application will do one or the other depending on a setting. Measured across eleven applications with one test message:

| | applications | what came back |
| --- | --- | --- |
| returned the source **byte-identical** | Discord, Signal Desktop, WhatsApp Desktop, Google Messages, Facebook web, Slack with formatting **declined** | verifies |
| markers stripped | Facebook Messenger, GitHub rendered issue, Gmail rendered view, VS Code markdown preview, Slack with formatting **accepted** | fails |

Slack is the controlled experiment: the same message, pasted twice, differing only in whether its "apply formatting?" prompt was accepted.

The method matters, so it is worth stating. Each message was pasted into the compose box, **sent**, and then copied out of the *rendered transcript* &mdash; not out of the draft. The reader who verifies is copying a received message, and that is the case the table measures.

So the instinct that chat clients eat backticks is wrong, and the correct instinct is narrower and more useful. Most chat clipboards hand back exactly what was typed. What you must never do is take a digest over text a human copied out of a *rendered* view &mdash; a GitHub comment, a Gmail message body, a markdown preview pane. When the marks are stripped, the interior is exposed to prose normalization, so `` `--dry-run  &  --verbose` `` arrives as `-dry-run & -verbose`: the flags are now wrong and nothing in the text says so.

Where an application controls the compose surface, digest what is in the editor rather than what is on the screen. But be precise about what that buys: **a composer controls the bytes it emits and nothing about the path.** It can guarantee that no rendering step stands between the signed text and the wire. It cannot guarantee what a recipient's client renders, or which representation a verifier reads. Those are obligations on the verifier, and they have to be written down separately rather than assumed away.

## What CQT does not give you

The algorithm answers one question, and a working product needs several more answered. None of these is a gap in the specification; they are what surrounds it, and leaving them implicit is how integrations fail.

- **An envelope.** A signature over `cqt3.17(text)` and nothing else commits to no author, no recipient, no purpose, no time, no conversation. Anyone can move it somewhere else and it still verifies. Sign a domain-separated envelope with a specified serialization &mdash; algorithm identifier, canonical digest, key identifier, protocol identifier, claim type, and whatever context you are promising &mdash; and sign its bytes, not an informal concatenation of fields.
- **Key trust.** "This signature is valid for key K" is not "K belongs to Alice." Discovery, certification, rotation, revocation and compromise are all yours.
- **The words for your claim.** CQT defines a deliberately broad equivalence: `i--` and `i-` reach the same bytes, and so do several distinct quotation marks. A UI that says **exact**, **verbatim** or **unaltered** is therefore lying. Say *canonically equivalent under `cqt3.17`*, and show consequential differences where you can compute them.
- **A scope for the badge.** A verified indicator beside a message implies the whole message. If the subject line, sender name, recipients, attachments or link targets are not covered, confine the indicator to what is, visually and unambiguously.

## Failure modes

### A rendered copy loses the marks

Covered above. The failure is silent at the point of copying and loud at the point of verification, which is the right direction but leaves the person holding the failure with no idea why.

**What to do.** If you can read the clipboard's `text/html` flavor, you can often rebuild the marks: mapping `<pre>` to a fence, `<blockquote>` to `>` and `<code>` to backticks recovered 97.7% of the canonical form in our measurements. Treat that as a **lower-confidence candidate**, never as equivalent to a plain-text match, and be aware of the attack it opens: a `<span style="display:none">` is invisible to a human and visible to a tag stripper, so a reconstruction is not what the signer saw.

### A renderer inside the transport

The table above measures rendering at the *copy* step. HTML mail puts a renderer inside the transport instead, and the clipboard captures say nothing about it. A composer that emits `multipart/alternative` has its `text/plain` part generated by a tool from the HTML, and whether that tool round-trips backticks and `>` is a property of the tool, not of the channel. On the receiving side, a library call that asks a message for "its content" picks a part, and if it lands on text derived from the HTML alternative, the marks are gone before verification begins.

**What to do.** For a composer: emit `text/plain`, emit no HTML alternative alongside signed content, and never let a markdown-to-HTML step stand between the signed text and the wire. For a verifier: state which part you read, read that part and no other, and refuse rather than guess when the message does not have it. This is the same decision as the divergent-parts one below, arriving through the marker question instead of the content question.

### The decoding you do before CQT

The specification hands decoding to the caller on purpose, which means every choice in front of the algorithm is yours and is unstated. One client replaces malformed UTF-8 with `U+FFFD` and another drops it; both then run conforming implementations and disagree.

**What to do.** Write down, in order: charset selection, transfer decoding, BOM handling, malformed-input policy, and where the digest is taken relative to all of them. Then pin that order with your own vectors. Two implementations of the same protocol will otherwise diverge on inputs neither party thinks of as unusual.

### Removing your own marker changes the claim

Keeping a signature or marker on a line of its own makes it *removable*, which is necessary and not sufficient. Deleting a whole line still changes structure: it can join a quoted passage to an unquoted one, or consume the line ending a fence had claimed, so the text you verify is not the text minus a line.

**What to do.** Prefer out-of-band signatures. Where the marker must be in-band, specify the framing exactly, preserve the surrounding line structure when you extract it, and pin the extraction with vectors of your own &mdash; including a case where the marker sits next to a fence and one where it sits at a quotation boundary.

### One stray backtick corrupts spans it never touched

Inline spans pair by parity. Insert a single backtick upstream and every pairing after it shifts, so text far from the perturbation is silently unprotected. `` Take `x--y` and `p--q` `` with one extra backtick reaches ``Take ``x-y` and `p-q```.

The trigger set is narrower than it first appears, which is worth knowing before you build defenses against it. The cascade fires only when a backtick is *inserted or deleted*. Moving text as source does neither. Quoting does neither, because step 6.1 rewrites markers and line structure and never touches a span delimiter. What is left is truncation, and any preprocessing of your own that can cut mid-span.

**What to do.** Count backticks before signing &mdash; an odd number of single-backtick runs almost always means a typo, and the consequence is not local. Then handle the two real triggers directly: verify whole messages rather than truncated views, and make your own preprocessing span-aware.

### Truncation

A "show more" fold, a length limit, an SMS split, or your own preprocessing can remove a fence's closing line. CQT 3.17 makes this a slope rather than a cliff &mdash; an unterminated opener protects to the end of the input, so you lose the bytes that were lost rather than the interpretation of the whole block. You still lose.

**What to do.** Verify against the whole message. If your product shows a truncated view, make the untruncated text reachable, and do not offer verification against what is on screen.

### A multi-line inline span

An inline span folds its interior line endings to a single space, so it survives rewrapping. That is the *only* span kind that does. A fenced block preserves line structure by definition and therefore does not survive a channel that reflows.

**What to do.** Use inline spans for identifiers, flags and hashes. Use a fence only when the line breaks are the content, and expect it not to survive reflow. In our re-quoting corpus, every one of the sixteen residual failures was an inline span straddling a line break inside quoted text.

### Text stored HTML-escaped

The specification requires a caller holding HTML-escaped text to decode before calling CQT. Entities are not decoded by the algorithm, and an escaped copy will never agree with an unescaped one.

**What to do.** Decode at a single, documented point in your pipeline, and write down where it is relative to MIME decoding and to the digest. This is the commonest place for two implementations of the same protocol to disagree.

### Divergent MIME parts

A `multipart/alternative` message can say one thing in `text/plain` and another in `text/html`. Sign the plain part, render the HTML, and the reader believes the signature covers what they read.

**What to do.** **Bind which representation was signed**, and read exactly that part. Refusing every `multipart/alternative` message is not a usable fallback in mail &mdash; 62% of real messages are multipart/alternative and 97% carry an HTML part, so a client that refuses them verifies almost nothing and the feature gets switched off. Refusal is what you do when the binding is *absent*, not what you do by default.

Do **not** try to verify that the two parts agree, and do not warn when they differ either: measured over 26,899 real messages, only 10.8% canonicalize identically, so both the check and the warning fire on roughly 88% of honest mail.

### Preprocessing that is not span-aware

Anything your application strips, inserts or rewrites before calling CQT is operating on text whose structure CQT is about to interpret. Removing a line can bisect a fence; inserting one can change quotation boundaries.

**What to do.** Give your preprocessor the same recognizer CQT uses, or restrict it to operations that provably cannot touch a span &mdash; and prove it, rather than assuming. Keep any in-band marker of your own on a line by itself, so removing it is a whole-line operation.

### A bare high-entropy identifier

Base64url uses `-`, so a doubled hyphen appears in just over 1% of 44-character values and CQT collapses it. A KERI AID, a JWT segment, a `did:ion` body: all silently corrupted in unmarked prose. Hex, UUIDs, bech32, base32 and base58 are safe; case is never normalized, so EIP-55 checksums survive.

**What to do.** Mark them, and warn when the author does not.

## Duties of a composer

A composer is any surface where a person writes text that will be signed &mdash; an editor, a chat box, a browser extension over someone else's page.

- **Warn when a high-entropy value appears without backticks.** The specification asks for this explicitly. A heuristic is unusable inside the algorithm, where a false positive silently changes signed bytes; in an editor a false positive is a prompt the author dismisses. Use the [entviz gallery](https://dhh1128.github.io/entviz/gallery.html) as a corpus.
- **Warn on an inline span containing a line break.** It will fold to a space, which is usually what the author wants and occasionally is not.
- **Warn on an odd backtick count.**
- **Show the canonical form before signing,** or at least on request. It is the only way a person can see that their `--` became `-`.
- **Keep any signature or marker of your own alone on its line.**
- **Digest the editor's buffer, not the rendered DOM.**

## Duties of a verifier

- **Fix the claim before you verify it, never by verifying it.** This is the one that will bite hardest, because the natural way to build a tolerant verifier is a security hole. If you try interpretations until one validates, you have not checked a claim; you have searched for a reading that succeeds. An attacker with one authentic signed sentence can then wrap it in a hostile paragraph and collect a verified badge for the whole thing &mdash; signature laundering, and the human sees only the badge. Decide what text the signature is asserted to cover *first*, from structure, and check that. Then show the reader the **exact extent** that was covered, so a badge can never appear to cover bytes it does not.
- **Generate candidates, but bound them and name them.** Within a fixed claim, the received bytes may still be quoted, rewrapped, or a rendered copy, and trying those transformations is legitimate. Make the candidate list protocol-defined and short, canonicalize each, and report **which one matched** &mdash; "verified after removing email quote markers" is a different fact from "verified as received," and collapsing them throws away what the reader needs. Quote-stripping and marker reconstruction belong here, outside the frozen function, where a mistake costs a patch rather than a new algorithm number.
- **Report failure as a disjunction, and default to unverified.** A mismatch is not proof of duplicity. It is proof of *duplicity, or lossy quoting, or a copy taken from rendered output, or an encoding error, or an algorithm-version mismatch, or a bug in your verifier*. Naming the causes is what lets a person act; it is not permission to treat the failure as benign. The status is **unverified**, and it stays unverified until something matches. A UI that says "probably just a copy/paste problem" has taught its users to click through a security control.
- **Distinguish "the marks are absent" from "the text was altered."** This is the one failure a composer cannot prevent: it happens on the recipient's side, in their client, silently. Text whose canonical form differs only by the loss of protection &mdash; markers gone, interiors normalized &mdash; has the shape of rendered output, and you can often say so. Compare the received text against the canonical form of the signed text with protection removed; if *that* matches, you have identified the cause and can tell the reader to fetch the source rather than leaving them with a bare failure.
- **A signer makes the narrowest claim that will survive; a verifier never narrows one.** Quoters excerpt, so a signature over more text than survives the hop cannot be checked, and the party choosing what to cover should choose conservatively. That is advice to the *signer*. The mirror image is an attack: a verifier that shrinks the claim until something matches is laundering signatures. If the asserted extent does not verify, the answer is unverified &mdash; not a smaller claim that does.
- **Treat several materially different matches as ambiguous.** If more than one candidate, depth or reconstruction validates &mdash; potentially against different signatures or identities &mdash; do not silently pick the most favorable. Show each match, its extent and how it was derived, and say the result is ambiguous.
- **Bound the work.** A bot handed megabytes of backticks, or deeply nested quotation, or many candidate-by-signature combinations, will multiply work in span recognition, normalization and depth iteration. Set explicit limits on input size, candidate count, nesting depth and processing time, and return an explicit *indeterminate* rather than hanging or crashing.
- **Bind the algorithm identifier** &mdash; the exact ASCII string `cqt3.17` &mdash; in whatever you sign, and reject an identifier you do not support rather than falling back.

## Unnesting

Quotation depth is insignificant in the canonical form, so recovering the original nesting is your job, performed on the raw text before CQT runs. Canonical form is never transported; it is recomputed at verification, one nesting level at a time.

The gotcha worth stating: a naive one-level peel fails when the quotation arrived at depth two, because peeling once leaves a `>` behind and the inner form no longer matches. The tempting fix is to try depths until one verifies, and that is the same oracle as above &mdash; different depths carve out different claims, so "whichever depth validates" lets the signature choose what it covers. **Take the depth from your quotation parser, not from the search.** Where the structure is genuinely ambiguous, surface the ambiguity rather than resolving it by whichever reading happens to pass, and bound any search you do keep, explicitly and in writing.

What CQT does guarantee is the division between the signer's own words and the quoted material. Two messages that draw that line in different places cannot reach the same bytes. What it does *not* preserve is attribution inside the quoted material: adjacent quotations at different depths join, so `>> question` above `> answer` is byte-identical to both at one depth. If who-said-what inside a quotation matters, it has to be established by an inner signature, verified from the raw text where depth is intact.

## A worked case: a browser extension

The hardest version, because the extension controls neither the text nor the surface.

1. **Read the editor's value, not the page's rendering** &mdash; and know which of three cases you are in, because "the buffer" is not always a thing that exists. A `textarea` or `input` has a `value`, and that is the easy case. A bare `contenteditable` has a DOM tree and no buffer; the DOM *is* the value, and you must define a serialization. A framework-managed editor &mdash; ProseMirror, Slate, Quill &mdash; has a document model that is the real source of truth, reachable only through the framework's own API, and its DOM is a rendering of that model. Read the model where you can get at it. Where you cannot, say in your UI which representation you signed, rather than implying you signed what the person typed.
2. **Write down the whole input pipeline, in order, and forbid anything outside it.** Decoding, MIME part selection, entity decoding, rich-text serialization and extraction are all transformations; "do not normalize" is not implementable advice unless you have said which transformations are the sanctioned ones. Specify the ordered list, then normalize nothing beyond it. These are two different things and the distinction is load-bearing. Turning an editor's content into a string is unavoidable, and for a `contenteditable` it involves real decisions &mdash; what a `<br>` becomes, what a block boundary becomes, what happens to `&nbsp;`. That is not optional cleanup; it is part of your protocol, and two extensions that serialize differently will disagree forever. Write it down and pin it with your own vectors. What you must not do is *further* tidy the resulting text &mdash; collapsing spaces, trimming, fixing quotes &mdash; which is the preprocessing failure mode above.
3. **Compose-time, not display-time.** Sign what the person typed, at the moment they typed it. Do not offer to verify text selected from a rendered page unless you also say the confidence is lower.
4. **Show the original and the canonical form side by side, with the differences marked** &mdash; not the canonical form alone. It is the only affordance the person has for noticing that the page's autocorrect turned their `--` into an em dash. But canonical output is not a safe confirmation format on its own: it can carry bidi marks, zero-width joiners and confusables, its quotation structure has been flattened, and it is not idempotent. Escape the invisibles, show what changed, and never present it as "here is your text."
5. **Expect the page to change under you, and re-check at submission.** A framework can rewrite the editor's contents between your read and the user's click. Reading once and signing that snapshot is not enough: if the page then sends something else, you have signed text nobody transmitted. Re-read at the moment of submission, compare against what you showed, and abort on any difference rather than signing the stale snapshot.

## Keep the original

Store the text the signer actually submitted, not only its canonical form or its digest. Canonicalization is one-way and not idempotent, so canonical bytes cannot reproduce the input, cannot be re-canonicalized safely, and cannot be shown to a person as what was signed. Keep the original text, the decoding metadata, the envelope, the signature, and the revision of the implementation and vectors you used &mdash; that last one is what lets you tell a defect from a disagreement years later.

## Version discipline

`cqt3.17` names one exact function. Anything computing different bytes gets a different name, and there is no version that is compatible enough with another. Bind the identifier, reject what you do not support, and do not recompute an old commitment under a new algorithm.

CQT 2.17 was published and superseded four days later. That is the argument for keeping your own version discipline tight *before* anything is signed, and for writing down now what happens to your durable-tier payloads at a version change &mdash; because the answer is that they are verifiable only while a conformant implementation of their algorithm exists, and building one decades out needs the whole set: this prose, the vector file, the Unicode 17 data the algorithm depends on, the algorithm identifier, and a toolchain that can still run them. The vectors are what make conformance checkable; they do not define behavior for inputs they do not cover, which is why the specification says an implementation is conformant exactly as far as the vectors reach and no further. Preserve all of it, not the part that is easiest to archive.
