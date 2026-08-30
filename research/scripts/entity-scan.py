#!/usr/bin/env python3
"""Do HTML entities actually reach the text/plain part of real mail?

Aggregate counts only -- no content, no addresses. The hypothesis under test is
that some mail generators build text/plain by stripping tags without decoding
entities, so escaped text reaches a plain-text channel unasked.

Usage: entity-scan.py <mbox> [max_messages]
"""
import sys, re, email, email.policy
from collections import Counter

PATH = sys.argv[1]
LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 50000
MAX_MSG = 4 << 20
FROM_LINE = re.compile(rb'^From \S+.*\d{4}\r?\n$')

FIVE = re.compile(r'&(amp|lt|gt|quot|apos);')
NUMERIC = re.compile(r'&#(?:x[0-9A-Fa-f]+|[0-9]+);')
NAMED_ANY = re.compile(r'&[A-Za-z][A-Za-z0-9]{1,30};')
IN_URL = re.compile(r'https?://\S*&(?:amp|lt|gt|quot|apos);|https?://\S*&#')

stats, which = Counter(), Counter()


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


def handle(raw):
    stats['messages'] += 1
    if len(raw) > MAX_MSG:
        return
    try:
        msg = email.message_from_bytes(raw, policy=email.policy.compat32)
    except Exception:
        return
    plain, html = bodies(msg)
    if plain is None:
        return
    stats['with_text_plain'] += 1
    five = FIVE.findall(plain)
    numeric = NUMERIC.findall(plain)
    named = NAMED_ANY.findall(plain)
    if five:
        stats['plain_has_one_of_the_five'] += 1
        for name in five:
            which['&' + name + ';'] += 1
    if numeric:
        stats['plain_has_a_numeric_reference'] += 1
    other = [n for n in named if not FIVE.fullmatch(n)]
    if other:
        stats['plain_has_another_named_entity'] += 1
        for name in other[:20]:
            which[name.lower()] += 1
    if five or numeric or other:
        stats['plain_has_any_entity'] += 1
        if html is not None:
            stats['  ...and the message also had an html part'] += 1
    if IN_URL.search(plain):
        stats['plain_has_an_entity_inside_a_url'] += 1


buf, count = [], 0
with open(PATH, 'rb') as fh:
    for line in fh:
        if FROM_LINE.match(line) and buf:
            handle(b''.join(buf))
            buf = []
            count += 1
            if count >= LIMIT:
                break
        buf.append(line)

print('--- entities in the text/plain part')
for k in ('messages', 'with_text_plain', 'plain_has_any_entity',
          '  ...and the message also had an html part',
          'plain_has_one_of_the_five', 'plain_has_a_numeric_reference',
          'plain_has_another_named_entity', 'plain_has_an_entity_inside_a_url'):
    n = stats[k]
    base = stats['with_text_plain'] or 1
    pct = '' if k in ('messages', 'with_text_plain') else f'   {100*n/base:.2f}%'
    print(f'{k:46} {n}{pct}')
print('--- which entities, by occurrence')
for name, n in which.most_common(20):
    print(f'  {name:<14} {n}')
