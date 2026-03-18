#!/usr/bin/env python3
"""Diff two regipy JSON registry dumps (baseline vs post-infection).

Usage: registry-diff.py <baseline.json> <post.json> [--json]

Input: newline-delimited JSON from `registry-dump` (regipy).
Each line: {"path": "\\Registry\\...", "values": [...], ...}

Output: new keys, changed values, deleted keys, persistence flags.
"""

import json
import sys
import re
from pathlib import Path

PERSISTENCE_PATTERNS = [
    r"CurrentVersion\\Run\b",
    r"CurrentVersion\\RunOnce\b",
    r"CurrentVersion\\RunServices\b",
    r"CurrentVersion\\Explorer\\Shell Folders",
    r"CurrentVersion\\Explorer\\User Shell Folders",
    r"Services\\",
    r"Startup",
    r"Winlogon\\",
    r"CurrentVersion\\Policies\\Explorer\\Run",
    r"Environment\\",
    r"Command Processor\\AutoRun",
]


def is_persistence_key(path):
    for pat in PERSISTENCE_PATTERNS:
        if re.search(pat, path, re.IGNORECASE):
            return True
    return False


def parse_registry_dump(filepath):
    """Parse newline-delimited JSON from registry-dump into a dict keyed by path."""
    entries = {}
    with open(filepath, "r", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            path = obj.get("path", "")
            if not path:
                continue
            # Store values as a comparable dict
            values = {}
            for v in obj.get("values", []):
                vname = v.get("name", "(Default)")
                vdata = v.get("value", "")
                values[vname] = vdata
            entries[path] = {
                "values": values,
                "timestamp": obj.get("timestamp", ""),
            }
    return entries


def diff_registries(baseline, post):
    baseline_keys = set(baseline.keys())
    post_keys = set(post.keys())

    new_keys = sorted(post_keys - baseline_keys)
    deleted_keys = sorted(baseline_keys - post_keys)
    common_keys = baseline_keys & post_keys

    changed = []
    for key in sorted(common_keys):
        bvals = baseline[key]["values"]
        pvals = post[key]["values"]
        if bvals != pvals:
            # Find specific value changes
            all_names = set(list(bvals.keys()) + list(pvals.keys()))
            diffs = []
            for name in sorted(all_names):
                bv = bvals.get(name)
                pv = pvals.get(name)
                if bv != pv:
                    diffs.append({
                        "name": name,
                        "before": bv,
                        "after": pv,
                    })
            changed.append({"path": key, "changes": diffs})

    return new_keys, deleted_keys, changed


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <baseline.json> <post.json> [--json]", file=sys.stderr)
        sys.exit(1)

    baseline_file = sys.argv[1]
    post_file = sys.argv[2]
    output_json = "--json" in sys.argv

    baseline = parse_registry_dump(baseline_file)
    post = parse_registry_dump(post_file)

    new_keys, deleted_keys, changed = diff_registries(baseline, post)

    if output_json:
        result = {
            "new_keys": new_keys,
            "deleted_keys": deleted_keys,
            "changed_keys": changed,
            "persistence_keys": [k for k in new_keys if is_persistence_key(k)]
                + [c["path"] for c in changed if is_persistence_key(c["path"])],
        }
        print(json.dumps(result, indent=2, default=str))
        return

    # Text output
    print(f"=== Registry Diff: {Path(baseline_file).name} -> {Path(post_file).name} ===\n")

    # Persistence alerts first
    persistence_new = [k for k in new_keys if is_persistence_key(k)]
    persistence_changed = [c for c in changed if is_persistence_key(c["path"])]
    if persistence_new or persistence_changed:
        print("!! PERSISTENCE MECHANISMS DETECTED !!")
        for k in persistence_new:
            print(f"  [NEW] {k}")
            vals = post[k]["values"]
            for name, val in vals.items():
                print(f"        {name} = {val}")
        for c in persistence_changed:
            print(f"  [CHANGED] {c['path']}")
            for d in c["changes"]:
                print(f"        {d['name']}: {d['before']} -> {d['after']}")
        print()

    print(f"--- New keys ({len(new_keys)}) ---")
    for k in new_keys:
        marker = " [PERSISTENCE]" if is_persistence_key(k) else ""
        print(f"  + {k}{marker}")
        vals = post[k]["values"]
        for name, val in vals.items():
            vstr = str(val)
            if len(vstr) > 120:
                vstr = vstr[:120] + "..."
            print(f"      {name} = {vstr}")

    print(f"\n--- Deleted keys ({len(deleted_keys)}) ---")
    for k in deleted_keys:
        print(f"  - {k}")

    print(f"\n--- Changed values ({len(changed)}) ---")
    for c in changed:
        marker = " [PERSISTENCE]" if is_persistence_key(c["path"]) else ""
        print(f"  ~ {c['path']}{marker}")
        for d in c["changes"]:
            before = str(d["before"])[:80] if d["before"] is not None else "(none)"
            after = str(d["after"])[:80] if d["after"] is not None else "(none)"
            print(f"      {d['name']}: {before} -> {after}")

    print(f"\nSummary: {len(new_keys)} new, {len(deleted_keys)} deleted, {len(changed)} changed")


if __name__ == "__main__":
    main()
