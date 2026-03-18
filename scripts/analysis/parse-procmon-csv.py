#!/usr/bin/env python3
"""Parse ProcMon CSV export and extract IoCs for malware analysis.

Usage: parse-procmon-csv.py <procmon.csv> [--process NAME] [--json]

Handles UTF-8-BOM and UTF-16 encodings (common with Windows XP ProcMon exports).
Extracts: file operations, registry operations, network activity, mutexes, child processes.
Flags persistence registry keys and deduplicates repeated operations.
"""

import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

PERSISTENCE_PATTERNS = [
    r"CurrentVersion\\Run\b",
    r"CurrentVersion\\RunOnce\b",
    r"CurrentVersion\\RunServices\b",
    r"Services\\",
    r"Startup",
    r"Winlogon\\",
    r"Policies\\Explorer\\Run",
    r"Shell Folders",
]

# ProcMon CSV columns (standard order)
# Time of Day, Process Name, PID, Operation, Path, Result, Detail
COL_TIME = "Time of Day"
COL_PROC = "Process Name"
COL_PID = "PID"
COL_OP = "Operation"
COL_PATH = "Path"
COL_RESULT = "Result"
COL_DETAIL = "Detail"


def is_persistence_path(path):
    for pat in PERSISTENCE_PATTERNS:
        if re.search(pat, path, re.IGNORECASE):
            return True
    return False


def open_csv(filepath):
    """Open ProcMon CSV handling various encodings."""
    # Try UTF-8-BOM first (most common), then UTF-16, then latin-1
    for enc in ["utf-8-sig", "utf-16", "latin-1"]:
        try:
            f = open(filepath, "r", encoding=enc, errors="replace")
            # Read first line to verify it's valid CSV
            first = f.readline()
            if COL_TIME in first or "Time" in first:
                f.seek(0)
                return f
            f.close()
        except (UnicodeError, UnicodeDecodeError):
            continue
    # Fallback
    return open(filepath, "r", encoding="utf-8", errors="replace")


def parse_procmon(filepath, process_filter=None):
    """Parse ProcMon CSV and categorize operations."""
    file_ops = defaultdict(set)      # path -> set of operations
    reg_ops = defaultdict(set)       # path -> set of operations
    net_ops = set()                  # (addr, port, op)
    mutex_ops = set()                # mutex names
    child_procs = set()              # (parent, child)
    persistence = []                 # (path, operation, detail)
    all_processes = set()

    f = open_csv(filepath)
    reader = csv.DictReader(f)

    for row in reader:
        proc = row.get(COL_PROC, "").strip()
        op = row.get(COL_OP, "").strip()
        path = row.get(COL_PATH, "").strip()
        result = row.get(COL_RESULT, "").strip()
        detail = row.get(COL_DETAIL, "").strip()

        all_processes.add(proc)

        if process_filter and proc.lower() != process_filter.lower():
            continue

        # File operations
        if op in ("CreateFile", "WriteFile", "SetDispositionInformationFile",
                   "SetRenameInformationFile", "CloseFile") and path and not path.startswith("HK"):
            file_ops[path].add(op)

        # Registry operations
        elif op in ("RegCreateKey", "RegSetValue", "RegDeleteKey", "RegDeleteValue",
                     "RegOpenKey", "RegQueryValue") and path:
            reg_ops[path].add(op)
            if is_persistence_path(path) and op in ("RegCreateKey", "RegSetValue"):
                persistence.append((path, op, detail))

        # Network
        elif op in ("TCP Connect", "TCP Send", "TCP Receive", "UDP Send", "UDP Receive"):
            net_ops.add((path, op))

        # Process creation
        elif op == "Process Create":
            child_procs.add((proc, detail))

        # Mutex / named objects
        elif op == "CreateFile" and ("\\BaseNamedObjects\\" in path or "Mutant" in path):
            mutex_name = path.split("\\")[-1]
            mutex_ops.add(mutex_name)

    f.close()
    return {
        "file_ops": file_ops,
        "reg_ops": reg_ops,
        "net_ops": net_ops,
        "mutex_ops": mutex_ops,
        "child_procs": child_procs,
        "persistence": persistence,
        "all_processes": all_processes,
    }


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <procmon.csv> [--process NAME] [--json]", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]
    process_filter = None
    output_json = "--json" in sys.argv

    for i, arg in enumerate(sys.argv):
        if arg == "--process" and i + 1 < len(sys.argv):
            process_filter = sys.argv[i + 1]

    data = parse_procmon(filepath, process_filter)

    if output_json:
        result = {
            "file_creates": sorted([p for p, ops in data["file_ops"].items() if "CreateFile" in ops]),
            "file_writes": sorted([p for p, ops in data["file_ops"].items() if "WriteFile" in ops]),
            "file_deletes": sorted([p for p, ops in data["file_ops"].items()
                                     if "SetDispositionInformationFile" in ops]),
            "registry_creates": sorted([p for p, ops in data["reg_ops"].items() if "RegCreateKey" in ops]),
            "registry_sets": sorted([p for p, ops in data["reg_ops"].items() if "RegSetValue" in ops]),
            "network": sorted([{"addr": a, "op": o} for a, o in data["net_ops"]], key=lambda x: x["addr"]),
            "mutexes": sorted(data["mutex_ops"]),
            "child_processes": sorted([{"parent": p, "child": c} for p, c in data["child_procs"]],
                                       key=lambda x: x["parent"]),
            "persistence": [{"path": p, "op": o, "detail": d} for p, o, d in data["persistence"]],
            "processes_seen": sorted(data["all_processes"]),
        }
        print(json.dumps(result, indent=2, default=str))
        return

    # Text output
    print(f"=== ProcMon Analysis: {Path(filepath).name} ===")
    if process_filter:
        print(f"Filtered to process: {process_filter}")
    print(f"Processes observed: {', '.join(sorted(data['all_processes']))}\n")

    # Persistence alerts
    if data["persistence"]:
        print("!! PERSISTENCE MECHANISMS !!")
        seen = set()
        for path, op, detail in data["persistence"]:
            key = (path, op)
            if key not in seen:
                seen.add(key)
                print(f"  [{op}] {path}")
                if detail:
                    print(f"          Detail: {detail[:120]}")
        print()

    # File operations (deduplicated)
    creates = sorted([p for p, ops in data["file_ops"].items() if "CreateFile" in ops])
    writes = sorted([p for p, ops in data["file_ops"].items() if "WriteFile" in ops])
    deletes = sorted([p for p, ops in data["file_ops"].items() if "SetDispositionInformationFile" in ops])

    print(f"--- File Creates ({len(creates)}) ---")
    if len(creates) > 50:
        # Show first 20 and summarize
        for f in creates[:20]:
            print(f"  {f}")
        print(f"  ... and {len(creates) - 20} more")
        # Show extension summary
        exts = defaultdict(int)
        for f in creates:
            ext = Path(f).suffix.lower() or "(no ext)"
            exts[ext] += 1
        print("  Extension summary:")
        for ext, count in sorted(exts.items(), key=lambda x: -x[1])[:10]:
            print(f"    {ext}: {count}")
    else:
        for f in creates:
            print(f"  {f}")

    print(f"\n--- File Writes ({len(writes)}) ---")
    if len(writes) > 50:
        for f in writes[:20]:
            print(f"  {f}")
        print(f"  ... and {len(writes) - 20} more")
    else:
        for f in writes:
            print(f"  {f}")

    if deletes:
        print(f"\n--- File Deletes ({len(deletes)}) ---")
        for f in deletes[:30]:
            print(f"  {f}")
        if len(deletes) > 30:
            print(f"  ... and {len(deletes) - 30} more")

    # Registry (deduplicated, focus on creates/sets)
    reg_creates = sorted([p for p, ops in data["reg_ops"].items() if "RegCreateKey" in ops])
    reg_sets = sorted([p for p, ops in data["reg_ops"].items() if "RegSetValue" in ops])

    print(f"\n--- Registry Creates ({len(reg_creates)}) ---")
    if len(reg_creates) > 30:
        for r in reg_creates[:15]:
            print(f"  {r}")
        print(f"  ... and {len(reg_creates) - 15} more")
    else:
        for r in reg_creates:
            print(f"  {r}")

    print(f"\n--- Registry SetValue ({len(reg_sets)}) ---")
    if len(reg_sets) > 30:
        for r in reg_sets[:15]:
            print(f"  {r}")
        print(f"  ... and {len(reg_sets) - 15} more")
    else:
        for r in reg_sets:
            print(f"  {r}")

    # Network
    if data["net_ops"]:
        print(f"\n--- Network ({len(data['net_ops'])}) ---")
        for addr, op in sorted(data["net_ops"]):
            print(f"  [{op}] {addr}")
    else:
        print("\n--- Network: none ---")

    # Mutexes
    if data["mutex_ops"]:
        print(f"\n--- Mutexes ({len(data['mutex_ops'])}) ---")
        for m in sorted(data["mutex_ops"]):
            print(f"  {m}")

    # Child processes
    if data["child_procs"]:
        print(f"\n--- Child Processes ({len(data['child_procs'])}) ---")
        for parent, child in sorted(data["child_procs"]):
            print(f"  {parent} -> {child}")


if __name__ == "__main__":
    main()
