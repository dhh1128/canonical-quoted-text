#!/usr/bin/env python3
"""Measure real-world quote-prefix shape against the R-NEQA rule.

Reads either pipermail .txt archives or a real mbox (Google Takeout), walking
MIME to find the text/plain part and decoding transfer encodings and charsets.

Emits aggregate statistics only -- never message content, never an address --
so it is safe to point at a personal mailbox.

R-NEQA under test: one quote level is '>' followed by at most one space.
Strip the minimum depth across non-blank lines of the selected block.

Usage:  quote-survey.py <file>...
"""
import re, sys, mailbox, email
from collections import Counter


def depth(line):
    """Quote depth of a line, and the remainder after stripping all levels."""
    i, d = 0, 0
    while i < len(line) and line[i] == '>':
        i += 1
        d += 1
        if i < len(line) and line[i] == ' ':
            i += 1
    return d, line[i:]


def decode(part):
    payload = part.get_payload(decode=True)
    if payload is None:
        return ''
    charset = part.get_content_charset() or 'utf-8'
    try:
        return payload.decode(charset, errors='replace')
    except LookupError:
        return payload.decode('utf-8', errors='replace')


def parts_of(msg):
    """(plain, html) bodies of a message, either may be ''."""
    plain = html = ''
    for part in msg.walk():
        ct = part.get_content_type()
        if part.get_filename():
            continue
        if ct == 'text/plain' and not plain:
            plain = decode(part)
        elif ct == 'text/html' and not html:
            html = decode(part)
    return plain, html


def messages(path):
    """Yield (plain_body, html_body, is_multipart_alternative)."""
    head = open(path, 'rb').read(4096)
    if b'\nFrom ' in head or head.startswith(b'From '):
        try:
            for msg in mailbox.mbox(path):
                plain, html = parts_of(msg)
                yield plain, html, msg.get_content_type() == 'multipart/alternative'
            return
        except Exception:
            pass
    # pipermail .txt fallback: no MIME survives, body is already text/plain
    text = open(path, encoding='utf-8', errors='replace').read()
    for p in re.split(r'(?m)^From \S+.*\d{4}$', text)[1:]:
        yield p.partition('\n\n')[2], '', False


def blocks(body):
    """Maximal runs of consecutive quoted lines -- what a human would select."""
    run = []
    for line in body.split('\n'):
        if depth(line)[0] > 0:
            run.append(line)
        elif run:
            yield run
            run = []
    if run:
        yield run


stats, depths, styles = Counter(), Counter(), Counter()
for path in sys.argv[1:]:
    for body, html, alt in messages(path):
        stats['messages'] += 1
        if alt:
            stats['multipart_alternative'] += 1
        if html:
            stats['has_html_part'] += 1
        if not body:
            stats['no_text_plain_part'] += 1
            continue
        seen = False
        for blk in blocks(body):
            if len(blk) < 2:
                stats['blocks_single_line'] += 1
                continue
            seen = True
            stats['blocks'] += 1
            ds = [depth(l)[0] for l in blk if depth(l)[1].strip()]
            if not ds:
                continue
            lo, hi = min(ds), max(ds)
            depths[lo] += 1
            stats['uniform_depth' if lo == hi else 'mixed_depth'] += 1
            if lo == hi:
                stats['fully_dequoted_by_R-NEQA'] += 1
            for l in blk:
                m = re.match(r'((?:>[ ]?)+)', l)
                if not m:
                    continue
                s = m.group(1)
                styles['tight  >>' if '>>' in s else
                       'spaced > >' if '> >' in s else
                       'single > ' if s == '> ' else
                       'single >  (no space)'] += 1
        if seen:
            stats['messages_with_a_quoted_block'] += 1
        if re.search(r'(?m)^-+\s*Original Message\s*-+', body, re.I):
            stats['outlook_style_no_prefix'] += 1
        if re.search(r'(?m)^\s*\|', body):
            stats['pipe_quoting_present'] += 1

print('--- corpus')
for k in ('messages', 'multipart_alternative', 'has_html_part', 'no_text_plain_part',
          'messages_with_a_quoted_block', 'blocks', 'blocks_single_line',
          'outlook_style_no_prefix', 'pipe_quoting_present'):
    print(f'{k:34} {stats[k]}')
print('--- blocks of 2+ lines')
for k in ('uniform_depth', 'mixed_depth', 'fully_dequoted_by_R-NEQA'):
    print(f'{k:34} {stats[k]}')
print('--- minimum depth of block')
for d in sorted(depths):
    print(f'  depth {d:<28} {depths[d]}')
print('--- prefix spelling, per quoted line')
for s, n in styles.most_common():
    print(f'  {s:<32} {n}')
