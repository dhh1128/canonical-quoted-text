# CQT 2.17 legacy notice

CQT 2.17 is the superseded algorithm published by this repository before CQT 3.17. Existing hashes and signatures that identify `cqt2.17` remain historical data and MUST NOT be reinterpreted as CQT 3.17.

CQT 2.17 was released as tag [`cqt2.17`](https://github.com/dhh1128/canonical-quoted-text/releases/tag/cqt2.17), commit [`092a1cb`](https://github.com/dhh1128/canonical-quoted-text/tree/092a1cb), the 2026-08-24 revision. The last CQT 2.17 repository state is commit [`551bfd0`](https://github.com/dhh1128/canonical-quoted-text/tree/551bfd0), the 2026-08-25 revision, which added three worked-example vectors and changed no output. Either commit contains the specification, the six implementations, and `goldens/cqt2.17.json`.

Unlike [CQT 1.14](cqt1.14.md), CQT 2.17 was a complete and conformant algorithm: its six implementations agreed with each other and with a normative vector file, and an implementation of it can still be built from that commit. It was superseded rather than repaired.

What CQT 3.17 changes, and why 2.17's output could not simply be corrected in place:

* Every line terminator is folded to LF, and horizontal whitespace before a line ending is removed, before anything is recognized. Under 2.17 the same fenced block delivered with CRLF and with LF produced different bytes, which meant a block that had passed through a mail gateway could not match the block that was signed.
* `U+FEFF` is removed as a precondition, so it comes out of a protected span. Under 2.17 it was treated as a layout invisible and survived inside fences and URLs.
* Quote prefixes are normalized, so quoting depth and marker spelling stop being significant. Under 2.17 a quoted copy of a passage never matched an unquoted one, and `> alpha` never matched `>> alpha`, which defeated comparison in exactly the channels this algorithm was written for.
* An opening fence with no closing fence protects to the end of the input instead of decaying into prose, so losing one line to truncation no longer reinterprets an entire block.
* A line ending inside an inline code span folds to a single space, making such a span survive rewrapping.
* Fence delimiter lines accept any indentation and are reproduced at column zero. Under 2.17 four spaces of indentation silently turned a fence into an inline code span, protecting a different region than the author marked.
* A URL span's scheme and host are lowercased, per RFC 3986.
* `:D`, `:p` and `:o` no longer convert to emoticons when followed by a letter, digit, `-` or `_`. Under 2.17 the emoticon table rewrote `did:peer` to `did:-peer`, `urn:oid` to `urn:-oid`, and a `D`-coded CESR key after a colon to `:-D...`.

Each of those changes the output for some input, so each on its own would require a new identifier. See [Appendix: what the version numbers promise](README.md#appendix-what-the-version-numbers-promise).

Protocols SHOULD migrate by issuing new commitments explicitly identified as `cqt3.17`. They MUST NOT recompute an old `cqt2.17` commitment with CQT 3.17 or silently relabel it.
