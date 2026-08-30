#!/usr/bin/env python3
"""Stream a Google Takeout mbox and report aggregate statistics only.

Never prints message content, subjects or addresses. Two questions:
  1. quote-prefix shape and prevalence in the text/plain part
  2. how often an honest multipart/alternative's two parts agree under CQT

Usage: mbox-survey.py <mbox> [max_messages]
"""
import sys, re, email, email.policy, html as htmllib
from collections import Counter

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'impl', 'python'))
from cqt import algorithm_3_17 as cqt

PATH = sys.argv[1]
LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 200000
STATUS = '/tmp/mbox-survey-status.log'
MAX_MSG = 4 << 20          # skip messages larger than 4 MB; they are attachments

FROM_LINE = re.compile(rb'^From \S+.*\d{4}\r?\n$')
TAG = re.compile(r'<[^>]{0,4000}>', re.S)
BLOCK_END = re.compile(r'</(p|div|br|tr|li|h[1-6]|blockquote)\s*>|<br\s*/?>', re.I)

stats, depths, styles, agree = Counter(), Counter(), Counter(), Counter()


def quote_depth(line):
    i = d = 0
    while i < len(line) and line[i] in ' \t':
        i += 1
    while i < len(line) and line[i] == '>':
        i += 1
        d += 1
        if i < len(line) and line[i] == ' ':
            i += 1
    return d, line[i:]


def html_to_text(source):
    """Deliberately naive. This is the fuzzy precondition step CQT declines to
    specify, so the agreement rate it produces is indicative, not normative."""
    source = re.sub(r'(?is)<(script|style|head)\b.*?</\1\s*>', ' ', source)
    source = BLOCK_END.sub('\n', source)
    source = TAG.sub('', source)
    return htmllib.unescape(source)


def bodies(msg):
    plain = html = None
    for part in msg.walk():
        if part.get_content_maintype() == 'multipart' or part.get_filename():
            continue
        ctype = part.get_content_type()
        if ctype not in ('text/plain', 'text/html'):
            continue
        try:
            payload = part.get_payload(decode=True)
        except Exception:
            continue
        if payload is None or len(payload) > 1 << 20:
            continue
        charset = part.get_content_charset() or 'utf-8'
        try:
            text = payload.decode(charset, errors='replace')
        except LookupError:
            text = payload.decode('utf-8', errors='replace')
        if ctype == 'text/plain' and plain is None:
            plain = text
        elif ctype == 'text/html' and html is None:
            html = text
    return plain, html


def blocks(body):
    run = []
    for line in body.split('\n'):
        if quote_depth(line)[0] > 0:
            run.append(line)
        elif run:
            yield run
            run = []
    if run:
        yield run


def handle(raw):
    stats['messages'] += 1
    if len(raw) > MAX_MSG:
        stats['skipped_too_large'] += 1
        return
    try:
        msg = email.message_from_bytes(raw, policy=email.policy.compat32)
    except Exception:
        stats['unparseable'] += 1
        return
    plain, html = bodies(msg)
    if msg.get_content_type() == 'multipart/alternative':
        stats['multipart_alternative'] += 1
    if html is not None:
        stats['has_html_part'] += 1
    if plain is None:
        stats['no_text_plain_part'] += 1
        return
    stats['has_text_plain_part'] += 1

    seen = False
    for blk in blocks(plain):
        if len(blk) < 2:
            continue
        seen = True
        stats['blocks'] += 1
        ds = [quote_depth(l)[0] for l in blk if quote_depth(l)[1].strip()]
        if not ds:
            continue
        lo, hi = min(ds), max(ds)
        depths[lo] += 1
        stats['uniform_depth' if lo == hi else 'mixed_depth'] += 1
        for line in blk:
            m = re.match(r'[ \t]*((?:>[ ]?)+)', line)
            if not m:
                continue
            p = m.group(1)
            styles['tight >>' if '>>' in p else
                   'spaced > >' if '> >' in p else
                   'single > ' if p == '> ' else 'single >'] += 1
    if seen:
        stats['messages_with_a_quoted_block'] += 1
    if re.search(r'(?m)^-+\s*Original Message\s*-+', plain, re.I):
        stats['outlook_style_no_prefix'] += 1

    # do the two representations of an honest message agree under CQT?
    if html is not None and plain.strip():
        agree['pairs'] += 1
        try:
            a = cqt(plain)
            b = cqt(html_to_text(html))
        except Exception:
            agree['error'] += 1
            return
        if a == b:
            agree['identical'] += 1
        else:
            sa, sb = a.decode('utf-8', 'replace'), b.decode('utf-8', 'replace')
            if sa.replace(' ', '') == sb.replace(' ', ''):
                agree['differ_only_in_spacing'] += 1
            elif len(sa) and abs(len(sa) - len(sb)) / max(len(sa), len(sb)) < 0.05:
                agree['near_miss_5pct'] += 1
            else:
                agree['different'] += 1


def main():
    buf, count = [], 0
    log = open(STATUS, 'w', buffering=1)
    with open(PATH, 'rb') as fh:
        for line in fh:
            if FROM_LINE.match(line) and buf:
                handle(b''.join(buf))
                buf = []
                count += 1
                if count % 5000 == 0:
                    log.write(f'{count} messages\n')
                if count >= LIMIT:
                    break
            buf.append(line)
    if buf and count < LIMIT:
        handle(b''.join(buf))

    print('--- corpus')
    for k in ('messages', 'skipped_too_large', 'unparseable', 'has_text_plain_part',
              'no_text_plain_part', 'has_html_part', 'multipart_alternative',
              'messages_with_a_quoted_block', 'blocks', 'outlook_style_no_prefix'):
        print(f'{k:34} {stats[k]}')
    print('--- quoted blocks of 2+ lines')
    for k in ('uniform_depth', 'mixed_depth'):
        print(f'{k:34} {stats[k]}')
    print('--- minimum depth')
    for d in sorted(depths):
        print(f'  depth {d:<27} {depths[d]}')
    print('--- prefix spelling, per line')
    for s, n in styles.most_common():
        print(f'  {s:<31} {n}')
    print('--- text/plain vs text/html under CQT')
    for k in ('pairs', 'identical', 'differ_only_in_spacing', 'near_miss_5pct',
              'different', 'error'):
        print(f'  {k:<31} {agree[k]}')


main()
