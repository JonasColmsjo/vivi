#!/usr/bin/env python3
"""Diff two sorted file listings (baseline vs post-infection).

Usage: filesystem-diff.py <baseline-files.txt> <post-files.txt> [--json]

Input: one file path per line (output of `find <mntdir> -type f | sort`).
Output: new files, deleted files, with suspicious-location flags.
"""

import json
import re
import sys
from pathlib import Path

SUSPICIOUS_PATTERNS = [
    (r"system32[/\\]", "system32"),
    (r"[/\\]Temp[/\\]", "Temp"),
    (r"[/\\]tmp[/\\]", "tmp"),
    (r"Startup[/\\]", "Startup"),
    (r"Start Menu[/\\]", "Start Menu"),
    (r"[/\\]Recycler[/\\]", "Recycler"),
    (r"[/\\]AppData[/\\]", "AppData"),
    (r"[/\\]Application Data[/\\]", "Application Data"),
    (r"[/\\]Local Settings[/\\]", "Local Settings"),
    (r"\.(exe|dll|bat|cmd|vbs|js|scr|pif|com|ps1)$", "executable"),
    (r"HOW.TO.DECRYPT", "ransom note"),
    (r"README.*\.txt$", "possible ransom note"),
    (r"DECRYPT", "ransom-related"),
]


def classify(path):
    """Return list of suspicious tags for a file path."""
    tags = []
    for pattern, label in SUSPICIOUS_PATTERNS:
        if re.search(pattern, path, re.IGNORECASE):
            tags.append(label)
    return tags


def load_files(filepath):
    """Load file listing, stripping the mount-point prefix for comparison."""
    files = set()
    with open(filepath, "r", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line:
                files.add(line)
    return files


def strip_prefix(files):
    """Find common prefix and strip it for cleaner display."""
    if not files:
        return {}, ""
    sample = next(iter(files))
    # Find the mount point prefix (e.g., /mnt/vm/kvm/mnt/winxp1-live)
    # by looking for common Windows directory markers
    prefix = ""
    for f in files:
        for marker in ["/WINDOWS/", "/Windows/", "/Documents and Settings/", "/Users/", "/Program Files/"]:
            idx = f.find(marker)
            if idx > 0:
                prefix = f[:idx]
                break
        if prefix:
            break

    stripped = {}
    for f in files:
        key = f[len(prefix):] if prefix and f.startswith(prefix) else f
        stripped[key] = f
    return stripped, prefix


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <baseline-files.txt> <post-files.txt> [--json]", file=sys.stderr)
        sys.exit(1)

    baseline_file = sys.argv[1]
    post_file = sys.argv[2]
    output_json = "--json" in sys.argv

    baseline_raw = load_files(baseline_file)
    post_raw = load_files(post_file)

    baseline_stripped, prefix = strip_prefix(baseline_raw)
    post_stripped, _ = strip_prefix(post_raw)

    baseline_keys = set(baseline_stripped.keys())
    post_keys = set(post_stripped.keys())

    new_files = sorted(post_keys - baseline_keys)
    deleted_files = sorted(baseline_keys - post_keys)

    if output_json:
        result = {
            "new_files": [{"path": f, "tags": classify(f)} for f in new_files],
            "deleted_files": [{"path": f, "tags": classify(f)} for f in deleted_files],
            "mount_prefix": prefix,
        }
        print(json.dumps(result, indent=2))
        return

    # Text output
    print(f"=== Filesystem Diff: {Path(baseline_file).name} -> {Path(post_file).name} ===")
    if prefix:
        print(f"Mount prefix stripped: {prefix}\n")

    # Suspicious new files first
    suspicious_new = [(f, classify(f)) for f in new_files if classify(f)]
    if suspicious_new:
        print("!! SUSPICIOUS NEW FILES !!")
        for f, tags in suspicious_new:
            print(f"  [{'|'.join(tags)}] {f}")
        print()

    print(f"--- New files ({len(new_files)}) ---")
    for f in new_files:
        tags = classify(f)
        marker = f" [{', '.join(tags)}]" if tags else ""
        print(f"  + {f}{marker}")

    print(f"\n--- Deleted files ({len(deleted_files)}) ---")
    for f in deleted_files:
        tags = classify(f)
        marker = f" [{', '.join(tags)}]" if tags else ""
        print(f"  - {f}{marker}")

    print(f"\nSummary: {len(new_files)} new, {len(deleted_files)} deleted")


if __name__ == "__main__":
    main()
