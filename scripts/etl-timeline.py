#!/usr/bin/env python3
"""Parse a tracerpt CSV (from XP logman ETW) and print a simplified timeline.

Usage:
    python3 etl-timeline.py <tracerpt.csv> [--filter PID] [--no-registry] [--registry-writes-only]

Examples:
    python3 etl-timeline.py sample-logman.csv
    python3 etl-timeline.py sample-logman.csv --filter 916
    python3 etl-timeline.py sample-logman.csv --registry-writes-only
"""
import sys
import csv
import datetime
import argparse
import re
from collections import defaultdict


def filetime_to_dt(filetime):
    """Convert Windows FILETIME (100ns since 1601-01-01) to datetime."""
    return datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=filetime // 10)


def parse_csv(path):
    """Parse tracerpt CSV, handling its quirky whitespace-padded fields."""
    events = []
    with open(path, newline="") as f:
        for line in f:
            # Skip header
            if "Event Name" in line:
                continue
            parts = [p.strip() for p in line.split(",")]
            if len(parts) < 7:
                continue
            event = {
                "name": parts[0],
                "type": parts[1],
                "tid": parts[2],
                "filetime": int(parts[3]) if parts[3].isdigit() else 0,
                "kernel_ms": parts[4],
                "user_ms": parts[5],
                "data": parts[6:],
            }
            events.append(event)
    return events


def build_process_map(events):
    """Map PIDs to process names from Process Start events."""
    pmap = {}
    for e in events:
        if e["name"] == "Process" and e["type"] == "Start":
            # data: ..., PID, ParentPID, ..., "name.exe", ...
            # Find the quoted process name and PID
            pid = None
            pname = None
            for i, d in enumerate(e["data"]):
                if d.startswith('"') and d.endswith('"') and ".exe" in d.lower():
                    pname = d.strip('"')
                    # PID is typically data[1] for Process Start
                    break
            # PID from data[1] (after UniqueProcessKey)
            if len(e["data"]) > 1:
                try:
                    pid = int(e["data"][1])
                except ValueError:
                    pass
            if pid and pname:
                pmap[pid] = pname
    return pmap


def build_tid_to_pid(events):
    """Map TIDs to PIDs from Thread Start events."""
    tmap = {}
    for e in events:
        if e["name"] == "Thread" and e["type"] == "Start":
            # data: ProcessId, ThreadId, ...
            if len(e["data"]) >= 2:
                try:
                    pid = int(e["data"][0])
                    tid_dec = int(e["data"][1])
                    tmap[tid_dec] = pid
                except ValueError:
                    pass
    return tmap


def format_timeline(events, filter_pid=None, show_registry=True, registry_writes_only=False):
    """Format events into a readable timeline."""
    pmap = build_process_map(events)
    tmap = build_tid_to_pid(events)

    # Also map TID hex from event records
    tid_hex_to_pid = {}
    for tid_dec, pid in tmap.items():
        tid_hex_to_pid[f"0x{tid_dec:04X}"] = pid

    lines = []
    t0 = None

    for e in events:
        if t0 is None and e["filetime"] > 0:
            t0 = e["filetime"]

        ft = e["filetime"]
        if ft == 0:
            continue
        dt = filetime_to_dt(ft)
        ts = dt.strftime("%H:%M:%S.%f")[:-3]

        # Relative time
        if t0:
            rel = (ft - t0) / 10_000_000  # seconds
            rel_str = f"+{rel:7.2f}s"
        else:
            rel_str = "       "

        tid = e["tid"]
        pid = tid_hex_to_pid.get(tid.upper(), tid_hex_to_pid.get(tid, None))
        proc = pmap.get(pid, "") if pid else ""
        pid_str = f"[{pid}:{proc}]" if pid and proc else f"[{tid}]"

        if filter_pid and pid != filter_pid:
            continue

        name = e["name"]
        etype = e["type"]
        data = e["data"]

        if name == "Process":
            if etype == "Start":
                pname = next((d.strip('"') for d in data if ".exe" in d.lower()), "?")
                ppid = None
                cpid = None
                if len(data) > 1:
                    try:
                        cpid = int(data[1])
                    except ValueError:
                        pass
                if len(data) > 2:
                    try:
                        ppid = int(data[2])
                    except ValueError:
                        pass
                parent = pmap.get(ppid, f"PID {ppid}") if ppid else "?"
                line = f"PROC START  {pname} (PID {cpid}) <- {parent}"
                lines.append((ts, rel_str, pid_str, line))
            elif etype == "End":
                cpid = None
                if len(data) > 1:
                    try:
                        cpid = int(data[1])
                    except ValueError:
                        pass
                pname = pmap.get(cpid, "?")
                line = f"PROC END    {pname} (PID {cpid})"
                lines.append((ts, rel_str, pid_str, line))

        elif name == "Image" and etype == "Load":
            fname = next((d.strip('"') for d in data if d.strip('"').startswith("\\")), "?")
            line = f"DLL LOAD    {fname}"
            lines.append((ts, rel_str, pid_str, line))

        elif name == "Thread":
            if etype == "Start":
                tpid = data[0] if data else "?"
                ttid = data[1] if len(data) > 1 else "?"
                line = f"THREAD {etype:<6s} TID {ttid} in PID {tpid}"
                lines.append((ts, rel_str, pid_str, line))
            elif etype == "End":
                line = f"THREAD END"
                lines.append((ts, rel_str, pid_str, line))

        elif name == "Registry":
            if not show_registry:
                continue
            if registry_writes_only and etype not in ("SetValue", "Create", "DeleteValue"):
                continue
            vname = next((d.strip('"') for d in data if d.startswith('"')), "")
            line = f"REG {etype:<18s} {vname}"
            lines.append((ts, rel_str, pid_str, line))

        elif name == "HWConfig":
            line = f"HWCONFIG    {etype}"
            lines.append((ts, rel_str, pid_str, line))

    return lines


def print_summary(events):
    """Print event count summary."""
    counts = defaultdict(lambda: defaultdict(int))
    for e in events:
        counts[e["name"]][e["type"]] += 1

    print("=" * 60)
    print("EVENT SUMMARY")
    print("=" * 60)
    for name in sorted(counts):
        total = sum(counts[name].values())
        print(f"  {name}: {total}")
        for etype in sorted(counts[name], key=lambda x: -counts[name][x]):
            print(f"    {etype}: {counts[name][etype]}")
    print()


def print_process_tree(events):
    """Print process tree from Process Start events.

    Marks non-operator processes with <--- arrow. Operator (vivi) processes
    are those in the telnet control chain: tlntsess, cmd.exe spawned by
    tlntsess, logman, tasklist, findstr, and similar admin tools.
    """
    pmap = build_process_map(events)

    # Operator tools — processes we expect from telnet/vivi control
    OPERATOR_NAMES = {
        "tlntsess.exe", "cmd.exe", "logman.exe", "tasklist.exe",
        "findstr.exe", "tracerpt.exe", "tftp.exe", "ftp.exe",
        "at.exe", "net.exe", "reg.exe", "ipconfig.exe", "ping.exe",
        "taskkill.exe", "dir.exe", "shutdown.exe",
    }

    # Build parent map: cpid -> ppid
    parent_of = {}
    proc_list = []
    for e in events:
        if e["name"] == "Process" and e["type"] == "Start":
            data = e["data"]
            pname = next((d.strip('"') for d in data if ".exe" in d.lower()), "?")
            cpid = ppid = None
            try:
                cpid = int(data[1])
            except (ValueError, IndexError):
                pass
            try:
                ppid = int(data[2])
            except (ValueError, IndexError):
                pass
            if cpid:
                parent_of[cpid] = ppid
            proc_list.append((e["filetime"], cpid, ppid, pname))

    # Tools that are always operator-controlled (even if parent is unknown)
    ALWAYS_OPERATOR = {"logman.exe", "tracerpt.exe", "tftp.exe", "ftp.exe"}

    def is_operator(pid, pname):
        """A process is operator-controlled if it's a known tool AND
        descends from a tlntsess.exe chain (or is always operator-controlled)."""
        name_lower = pname.lower()
        if name_lower in ALWAYS_OPERATOR:
            return True
        if name_lower not in OPERATOR_NAMES:
            return False
        # Walk up the parent chain — must hit tlntsess.exe
        visited = set()
        current = pid
        while current and current not in visited:
            visited.add(current)
            parent_name = pmap.get(current, "").lower()
            if parent_name == "tlntsess.exe":
                return True
            current = parent_of.get(current)
        return False

    print("=" * 60)
    print("PROCESS TREE")
    print("=" * 60)
    for ft, cpid, ppid, pname in proc_list:
        dt = filetime_to_dt(ft)
        ts = dt.strftime("%H:%M:%S")
        parent = pmap.get(ppid, f"PID {ppid}")
        if is_operator(cpid, pname):
            marker = ""
        elif is_operator(ppid, pmap.get(ppid, "")):
            marker = "  <=== DETONATION"
        else:
            marker = "  <---"
        print(f"  {ts}  {parent} -> {pname} (PID {cpid}){marker}")
    print()


def main():
    parser = argparse.ArgumentParser(description="ETL/tracerpt CSV timeline viewer")
    parser.add_argument("csv_file", help="tracerpt CSV file")
    parser.add_argument("--filter", type=int, help="Show only events for this PID")
    parser.add_argument("--no-registry", action="store_true", help="Hide all registry events")
    parser.add_argument("--registry-writes-only", action="store_true",
                        help="Only show registry SetValue/Create/Delete")
    parser.add_argument("--summary-only", action="store_true", help="Only show summary, no timeline")
    args = parser.parse_args()

    events = parse_csv(args.csv_file)
    print(f"Loaded {len(events)} events from {args.csv_file}\n")

    print_summary(events)
    print_process_tree(events)

    if args.summary_only:
        return

    show_reg = not args.no_registry
    lines = format_timeline(events, args.filter, show_reg, args.registry_writes_only)

    print("=" * 60)
    print("TIMELINE")
    print("=" * 60)
    for ts, rel, pid_str, line in lines:
        print(f"{ts} {rel} {pid_str:<30s} {line}")


if __name__ == "__main__":
    main()
