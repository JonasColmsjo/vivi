#!/usr/bin/env python3
"""Parse r2 izzj JSON from stdin, categorize strings by PE section."""
import json, sys, re
from collections import defaultdict

data = json.load(sys.stdin)
by_sec = defaultdict(list)
for s in data:
    sec = s.get('section') or 'header'
    by_sec[sec].append(s['string'])

categories = [
    ('File paths / extensions', re.compile(
        r'\.(exe|dll|bat|txt|bmp|jpg|pml|etl|enc|dmp|doc|pdf|zip)', re.I)),
    ('Registry keys', re.compile(
        r'HKLM|HKCU|CurrentVersion|RegCreate|RegSet|RegDelete', re.I)),
    ('Crypto / passwords / ransom', re.compile(
        r'password|decrypt|encrypt|cipher|ransom|key|hash|crypt|seed|attempt', re.I)),
    ('URLs / IPs / domains', re.compile(
        r'https?://[^ "]+|(?<![0-9.])\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?![0-9.])', re.I)),
    ('Process / injection / evasion', re.compile(
        r'CreateRemoteThread|VirtualAlloc|WriteProcessMemory|NtUnmap|IsDebugger|Sleep|sandbox|vmware|vbox', re.I)),
]

# Section summary
sections = sorted(by_sec.keys(), key=lambda s: -len(by_sec[s]))
print()
print('[Section summary]')
for sec in sections:
    print(f'  {sec:12s}  {len(by_sec[sec]):4d} strings')
print()

# Categorized strings with section tags
for cat_name, pat in categories:
    hits = []
    for sec, strings in by_sec.items():
        for s in strings:
            if pat.search(s):
                hits.append((sec, s))
    if hits:
        print(f'[{cat_name}]')
        seen = set()
        for sec, s in sorted(hits, key=lambda x: x[0]):
            key = s.strip()
            if key not in seen:
                seen.add(key)
                print(f'  [{sec:8s}] {s}')
        print()

total = sum(len(v) for v in by_sec.values())
print(f'Total: {total} strings')
