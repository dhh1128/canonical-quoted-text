# CQT 1.14 legacy notice

CQT 1.14 is the superseded algorithm published by this repository before CQT 2.17. Existing hashes and signatures that identify `cqt1.14` remain historical data and MUST NOT be reinterpreted as CQT 2.17.

The last pre-revision repository state is commit [`f4f6783`](https://github.com/dhh1128/canonical-quoted-text/tree/f4f6783). It contains the original prose and implementations.

CQT 1.14 is documentation-only in the revised release. Its implementations were not mutually conformant: among other differences, the Python implementation discarded its final autocorrect stages, JavaScript did not remove punctuation-adjacent spaces, several astral Unicode escapes were malformed, and some ports had no build or test harness. No corrected executable behavior is assigned retroactively to the identifier `cqt1.14`.

Protocols SHOULD migrate by issuing new commitments explicitly identified as `cqt2.17`. They MUST NOT recompute an old `cqt1.14` commitment with CQT 2.17 or silently relabel it.
