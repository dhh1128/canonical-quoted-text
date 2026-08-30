# Research

Evidence for the empirical claims in the specification, and the scripts that produced it.

The [Caveats](../README.md#caveats) section cites numbers — how often a doubled hyphen appears in a 44-character base64url value, how often an HTML entity reaches the plain-text part of real mail, what a chat client does to backticks. A cited number whose evidence lives nowhere is a claim nobody can check, which is the same objection the [normative vectors](../goldens/cqt3.17.json) exist to answer. This directory is where those numbers come from.

Nothing here is normative. The specification and the vectors are; these are measurements that informed decisions, taken on dated corpora, and they will age.

## What is here

- `findings.md` — the aggregate results, with the corpus and date for each.
- `clipboard/` — raw clipboard captures from eleven applications, and what they show.
- `scripts/` — everything used to produce the above, so any of it can be re-run.

## Corpora

Two corpora are **not** vendored.

A Google Takeout export of a personal Gmail account, 4.9 GB, was used for the mail measurements. It is other people's correspondence and cannot be published. Every script that reads it emits aggregate counts only — never a body, a subject or an address — so the numbers in `findings.md` can be published even though their source cannot.

Public mailing list archives supplied a second, reproducible mail corpus. Rather than vendor 6.7 MB of third-party mail, fetch it:

```
for m in 2019-April 2019-May 2019-June; do
  curl -sO "https://mail.python.org/pipermail/python-dev/$m.txt"
  curl -sO "https://mail.python.org/pipermail/python-list/$m.txt"
done
```

## Re-running

The scripts import the reference implementation from `../impl/python`, which needs `unicodedata2`:

```
python3 -m venv .venv && .venv/bin/pip install unicodedata2
.venv/bin/python scripts/quote-survey.py *.txt
.venv/bin/python scripts/analyze-clipdump.py
```

`scripts/clipdump.sh` and `scripts/clipdump.ps1` capture clipboard flavors on Linux/macOS and on Windows respectively; the PowerShell one is required on Windows, because the WSL interop bridge re-encodes text and this measurement is byte-level. `scripts/reconstruct-from-html.py` tests whether protection markers a renderer stripped can be rebuilt from the HTML clipboard flavor.

## Privacy

The clipboard captures use a synthetic test message with nothing private in it. One artifact needed redaction anyway: the Windows `CF_HTML` clipboard format carries a `SourceURL:` header naming the page a selection came from, and in six captures that named a real profile or account page. Those headers read `SourceURL:[redacted]`; nothing else was altered. Anyone adding captures should check for the same thing.
