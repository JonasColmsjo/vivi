#!/usr/bin/env python3
"""Parse a ProcMon PML file and print a simplified timeline.

Usage:
    pml-timeline.py <file.PML> [--filter PID|name] [--registry-writes] [--file-io] [--no-dll] [--summary-only]

Examples:
    pml-timeline.py sample-procmon.PML --summary-only
    pml-timeline.py sample-procmon.PML --filter sample.exe --registry-writes --file-io
    pml-timeline.py sample-procmon.PML --filter sample.exe --no-dll
"""
import sys
import argparse
import datetime
from collections import defaultdict, OrderedDict
from procmon_parser import ProcmonLogsReader


# event_class: 1=Process, 2=Registry, 3=FileSystem, 4=Profiling, 5=Network
CLASS_NAMES = {1: "Process", 2: "Registry", 3: "FileSystem", 4: "Profiling", 5: "Network"}

# Registry write operations
REG_WRITE_OPS = {"RegSetValue", "RegCreateKey", "RegDeleteKey", "RegDeleteValue", "RegRenameKey"}

# Registry paths that are security/forensic-relevant (matched case-insensitive)
REG_INTERESTING_KEYWORDS = [
    "sam", "security", "crypt", "password", "secret", "seed",
    "lsa", "dpapi", "protect", "credential", "ntlm",
    "currentversion\\run", "policies", "firewall",
    "winlogon", "safer", "explorer\\shell", "explorer\\user shell",
    "desktop", "userinit", "shell\\open\\command",
    "enciphered", "services\\shared",
]

# File I/O operations worth showing (skip metadata/lock/close noise)
FILE_IO_OPS = {
    "CreateFile", "WriteFile", "ReadFile", "SetDispositionInformationFile",
    "SetRenameInformationFile", "CloseFile",
}
# Noisy file ops to skip
FILE_IO_SKIP = {
    "FASTIO_RELEASE_FOR_SECTION_SYNCHRONIZATION",
    "FASTIO_ACQUIRE_FOR_SECTION_SYNCHRONIZATION",
    "FASTIO_RELEASE_FOR_CC_FLUSH", "FASTIO_ACQUIRE_FOR_CC_FLUSH",
    "FASTIO_CHECK_IF_POSSIBLE", "FASTIO_RELEASE_FOR_MOD_WRITE",
    "FASTIO_ACQUIRE_FOR_MOD_WRITE", "IRP_MJ_CLEANUP",
    "IRP_MJ_CLOSE", "FASTIO_LOCK",
    "QueryInformationVolume", "QueryOpen",
    "QuerySecurityFile", "SetSecurityFile",
}


def match_filter(event, filt):
    """Check if event matches the filter (PID or process name)."""
    if filt is None:
        return True
    try:
        return event.process.pid == int(filt)
    except ValueError:
        return event.process.process_name.lower() == filt.lower()


def format_details(details):
    """Format the details dict into a readable string."""
    if not details:
        return ""
    if isinstance(details, OrderedDict) or isinstance(details, dict):
        parts = []
        for k, v in details.items():
            sv = str(v)
            if len(sv) > 80:
                sv = sv[:77] + "..."
            parts.append(f"{k}={sv}")
        return ", ".join(parts)
    return str(details)[:120]


def main():
    parser = argparse.ArgumentParser(description="ProcMon PML timeline viewer")
    parser.add_argument("pml_file", help="ProcMon .PML file")
    parser.add_argument("--filter", help="Filter by PID (number) or process name")
    parser.add_argument("--registry-writes", action="store_true",
                        help="Show registry write operations with values")
    parser.add_argument("--registry-timeline", action="store_true",
                        help="Show registry timeline (writes + security-relevant reads)")
    parser.add_argument("--file-io", action="store_true",
                        help="Show file I/O summary (counts, top files)")
    parser.add_argument("--file-summary", action="store_true",
                        help="Compact file I/O overview: folders, extensions, counts (1-2 screens)")
    parser.add_argument("--file-timeline", action="store_true",
                        help="Show file I/O timeline (reads, writes, renames)")
    parser.add_argument("--no-dll", action="store_true",
                        help="Hide DLL load events")
    parser.add_argument("--summary-only", action="store_true",
                        help="Only show summary, no timeline")
    args = parser.parse_args()

    with open(args.pml_file, "rb") as f:
        reader = ProcmonLogsReader(f)
        total = len(reader)
        print(f"Loaded {total} events from {args.pml_file}\n")

        # --- Collect stats and build process map ---
        proc_map = {}       # pid -> process_name
        parent_map = {}     # pid -> parent_pid
        op_counts = defaultdict(lambda: defaultdict(int))
        proc_starts = []
        proc_ends = {}

        # Operator process names (vivi/telnet control chain)
        OPERATOR_NAMES = {
            "tlntsess.exe", "cmd.exe", "logman.exe", "tasklist.exe",
            "findstr.exe", "tracerpt.exe", "tftp.exe", "ftp.exe",
            "at.exe", "net.exe", "reg.exe", "ipconfig.exe", "ping.exe",
            "taskkill.exe", "shutdown.exe", "procmon.exe",
        }
        ALWAYS_OPERATOR = {"logman.exe", "tracerpt.exe", "tftp.exe", "ftp.exe", "procmon.exe"}

        registry_writes = []
        registry_timeline = []  # writes + security-relevant reads
        file_io_events = []
        file_timeline_events = []  # meaningful file ops for timeline
        dll_loads = []
        network_events = []
        timeline_events = []

        # File ops worth showing in a timeline
        FILE_TIMELINE_OPS = {
            "CreateFile", "ReadFile", "WriteFile",
            "SetRenameInformationFile", "SetDispositionInformationFile",
            "SetEndOfFileInformationFile",
        }

        for i in range(total):
            e = reader[i]
            pname = e.process.process_name
            pid = e.process.pid
            ppid = e.process.parent_pid
            op = e.operation
            cls = e.event_class

            proc_map[pid] = pname
            if ppid:
                parent_map[pid] = ppid

            cls_name = CLASS_NAMES.get(cls, str(cls))
            op_counts[cls_name][op] += 1

            # Collect network events (unfiltered, for summary)
            if cls == 5:
                network_events.append(e)

            if not match_filter(e, args.filter):
                continue

            # Process start/end
            # Process_Create is logged under the PARENT process.
            # Process_Start is logged under the CHILD process itself.
            # Use Process_Create for the tree (has child PID + path).
            if op == "Process_Create":
                child_pid = (e.details or {}).get("PID", None)
                child_path = e.path or ""
                child_name = child_path.rsplit("\\", 1)[-1] if child_path else "?"
                ts = e.date_filetime
                if child_pid:
                    proc_map[child_pid] = child_name
                    parent_map[child_pid] = pid
                proc_starts.append((ts, child_pid or 0, pid, child_name, child_path))
            elif op == "Process_Exit":
                proc_ends[pid] = e.date_filetime

            # Registry writes
            if op in REG_WRITE_OPS:
                registry_writes.append(e)
                registry_timeline.append(e)
            elif cls == 2 and op in ("RegQueryValue", "RegOpenKey"):
                path_lower = (e.path or "").lower()
                for kw in REG_INTERESTING_KEYWORDS:
                    if kw in path_lower:
                        registry_timeline.append(e)
                        break

            # File I/O
            if cls == 3 and op not in FILE_IO_SKIP:
                file_io_events.append(e)
            if cls == 3 and op in FILE_TIMELINE_OPS:
                file_timeline_events.append(e)

            # DLL loads
            if op == "Load_Image":
                dll_loads.append(e)

        # --- Print summary ---
        print("=" * 70)
        print("EVENT SUMMARY")
        print("=" * 70)
        for cls_name in sorted(op_counts):
            total_cls = sum(op_counts[cls_name].values())
            print(f"  {cls_name}: {total_cls}")
            for op in sorted(op_counts[cls_name], key=lambda x: -op_counts[cls_name][x])[:10]:
                print(f"    {op}: {op_counts[cls_name][op]}")
            remaining = len(op_counts[cls_name]) - 10
            if remaining > 0:
                print(f"    ... and {remaining} more operation types")
        print()

        # --- Process tree ---
        def is_operator(pid, pname):
            if pname.lower() in ALWAYS_OPERATOR:
                return True
            if pname.lower() not in OPERATOR_NAMES:
                return False
            visited = set()
            current = pid
            while current and current not in visited:
                visited.add(current)
                pn = proc_map.get(current, "").lower()
                if pn == "tlntsess.exe":
                    return True
                current = parent_map.get(current)
            return False

        print("=" * 70)
        print("PROCESS TREE")
        print("=" * 70)
        for ts, pid, ppid, pname, path in proc_starts:
            parent = proc_map.get(ppid, f"PID {ppid}")
            if is_operator(pid, pname):
                marker = ""
            elif is_operator(ppid, proc_map.get(ppid, "")):
                marker = "  <=== DETONATION"
            else:
                marker = "  <---"
            dt = datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=ts // 10)
            tstr = dt.strftime("%H:%M:%S")
            print(f"  {tstr}  {parent} -> {pname} (PID {pid}){marker}")
        print()

        # --- Network summary (always shown) ---
        if network_events:
            print("=" * 70)
            print("NETWORK ACTIVITY")
            print("=" * 70)
            by_process = defaultdict(lambda: defaultdict(int))
            by_process_targets = defaultdict(set)
            for e in network_events:
                pn = e.process.process_name
                by_process[pn][e.operation] += 1
                by_process_targets[pn].add(e.path)

            for pn in sorted(by_process):
                ops = by_process[pn]
                total_n = sum(ops.values())
                ops_str = ", ".join(f"{op}: {c}" for op, c in sorted(ops.items(), key=lambda x: -x[1]))
                print(f"  {pn} ({total_n} events): {ops_str}")
                for target in sorted(by_process_targets[pn]):
                    print(f"    {target}")
            print()
        else:
            print("=" * 70)
            print("NETWORK ACTIVITY")
            print("=" * 70)
            print("  No network events captured.")
            print()

        # --- Registry writes ---
        if args.registry_writes:
            print("=" * 70)
            print("REGISTRY WRITES")
            print("=" * 70)
            for e in registry_writes:
                dt = datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=e.date_filetime // 10)
                tstr = dt.strftime("%H:%M:%S.%f")[:-3]
                det = format_details(e.details)
                result = "OK" if e.result == 0 else f"0x{e.result:08X}"
                print(f"  {tstr}  {e.operation:<18s} {result}  {e.path}")
                if det:
                    print(f"           {' ' * 18}        {det}")
            print(f"\n  Total registry writes: {len(registry_writes)}")
            print()

        # --- Registry timeline ---
        if args.registry_timeline:
            print("=" * 70)
            print("REGISTRY TIMELINE (writes + security-relevant reads)")
            print("=" * 70)
            last_ft = None
            phase = 0
            for e in registry_timeline:
                dt = datetime.datetime(1601, 1, 1) + datetime.timedelta(
                    microseconds=e.date_filetime // 10)
                tstr = dt.strftime("%H:%M:%S.%f")[:-3]

                # Time gap separator (>1 second gap = new phase)
                if last_ft and (e.date_filetime - last_ft) > 10_000_000:
                    gap = (e.date_filetime - last_ft) / 10_000_000
                    phase += 1
                    print(f"\n  {'─' * 60}")
                    print(f"  ── {gap:.1f}s gap ──")
                    print(f"  {'─' * 60}\n")
                last_ft = e.date_filetime

                op = e.operation
                path = e.path or ""
                ok = e.result == 0
                result = "OK" if ok else f"FAIL(0x{e.result:08X})"
                det = dict(e.details) if e.details else {}

                if op == "RegSetValue":
                    data = det.get("Data", "")
                    typ = det.get("Type", "")
                    print(f"  {tstr}  WRITE   {result:<20s} {path}")
                    if data:
                        print(f"               value: {typ} = {data}")
                elif op == "RegCreateKey":
                    print(f"  {tstr}  CREATE  {result:<20s} {path}")
                elif op == "RegDeleteKey":
                    print(f"  {tstr}  DELETE  {result:<20s} {path}")
                elif op == "RegDeleteValue":
                    print(f"  {tstr}  DELVAL  {result:<20s} {path}")
                elif op == "RegRenameKey":
                    print(f"  {tstr}  RENAME  {result:<20s} {path}")
                else:
                    tag = "READ " if ok else "READ?"
                    data = det.get("Data", "")
                    typ = det.get("Type", "")
                    print(f"  {tstr}  {tag}   {result:<20s} {path}")
                    if data and ok:
                        print(f"               value: {typ} = {data}")

            print(f"\n  Total: {len(registry_timeline)} events "
                  f"({len(registry_writes)} writes, "
                  f"{len(registry_timeline) - len(registry_writes)} reads)")
            print()

        # --- File summary (compact) ---
        if args.file_summary:
            print("=" * 70)
            print("FILE ACTIVITY SUMMARY")
            print("=" * 70)

            # Collect stats from file_timeline_events
            folder_stats = defaultdict(lambda: {"reads": 0, "writes": 0, "renames": 0, "files": set()})
            ext_renamed_to = defaultdict(int)   # extension -> count of renames TO it
            ext_read = defaultdict(int)          # extension -> files read
            ransom_notes = defaultdict(int)      # filename -> count of drops
            total_read = 0
            total_written = 0
            total_renamed = 0
            total_deleted = 0
            created_files = defaultdict(int)     # path -> write bytes (new files)
            skip_paths = {"C:\\$Mft", "C:\\$LogFile", "C:\\$Directory",
                          "C:\\$Extend\\$UsnJrnl:$J"}

            for e in file_timeline_events:
                path = e.path or ""
                if path in skip_paths:
                    continue
                op = e.operation
                det = dict(e.details) if e.details else {}

                # Folder = everything up to last backslash
                sep = path.rfind("\\")
                folder = path[:sep] if sep > 0 else path
                fname = path[sep + 1:] if sep > 0 else path

                folder_stats[folder]["files"].add(fname)

                if op == "ReadFile":
                    length = det.get("Length", 0)
                    if isinstance(length, int):
                        total_read += length
                        folder_stats[folder]["reads"] += length
                    ext = fname.rsplit(".", 1)[-1].lower() if "." in fname else ""
                    if ext:
                        ext_read[ext] += 1
                elif op == "WriteFile":
                    length = det.get("Length", 0)
                    if isinstance(length, int):
                        total_written += length
                        folder_stats[folder]["writes"] += length
                    # Track new file drops (ransom notes etc.)
                    if fname.upper().startswith("HOW TO") or "DECRYPT" in fname.upper():
                        ransom_notes[fname] += 1
                elif op == "SetRenameInformationFile":
                    target = det.get("FileName", "")
                    total_renamed += 1
                    folder_stats[folder]["renames"] += 1
                    # Extension of rename target
                    if "." in target:
                        ext = target.rsplit(".", 1)[-1]
                        ext_renamed_to[ext] += 1
                elif op == "SetDispositionInformationFile":
                    if det.get("Delete"):
                        total_deleted += 1

            # --- Totals ---
            print(f"\n  Read:    {total_read:>12,} bytes")
            print(f"  Written: {total_written:>12,} bytes")
            print(f"  Renamed: {total_renamed:>7,} files")
            print(f"  Deleted: {total_deleted:>7,} files")

            # --- Rename targets (encrypted extensions) ---
            if ext_renamed_to:
                print(f"\n  --- Renamed to extension ---")
                for ext, count in sorted(ext_renamed_to.items(), key=lambda x: -x[1]):
                    print(f"    .{ext:<30s} {count:>5} files")

            # --- Ransom notes ---
            if ransom_notes:
                total_notes = sum(ransom_notes.values())
                note_name = next(iter(ransom_notes))
                print(f"\n  --- Ransom notes dropped ---")
                print(f"    {note_name:<35s} {total_notes:>5} copies")

            # --- Top folders by file count ---
            print(f"\n  --- Folders (by files touched) ---")
            sorted_folders = sorted(folder_stats.items(),
                                    key=lambda x: len(x[1]["files"]), reverse=True)
            # Collapse to max ~30 lines: show top folders, group small ones
            shown_folders = 0
            other_files = 0
            other_renames = 0
            for folder, stats in sorted_folders:
                nfiles = len(stats["files"])
                if shown_folders < 25:
                    r_str = f"  ({stats['renames']} encrypted)" if stats["renames"] else ""
                    w_str = ""
                    if stats["writes"] > 0 and stats["renames"] == 0:
                        w_str = f"  ({stats['writes']:,}B written)"
                    print(f"    {nfiles:>4} files  {folder}{r_str}{w_str}")
                    shown_folders += 1
                else:
                    other_files += nfiles
                    other_renames += stats["renames"]
            if other_files:
                r_str = f"  ({other_renames} encrypted)" if other_renames else ""
                remaining = len(sorted_folders) - 25
                print(f"    {other_files:>4} files  ... {remaining} more folders{r_str}")

            # --- Extensions read (targeted file types) ---
            if ext_read:
                print(f"\n  --- File types read (by read ops) ---")
                shown_ext = 0
                for ext, count in sorted(ext_read.items(), key=lambda x: -x[1]):
                    if shown_ext >= 15:
                        break
                    print(f"    .{ext:<20s} {count:>6} reads")
                    shown_ext += 1
                remaining = len(ext_read) - shown_ext
                if remaining > 0:
                    print(f"    ... and {remaining} more extensions")

            print()

        if args.summary_only:
            return

        # --- File I/O ---
        if args.file_io:
            print("=" * 70)
            print("FILE I/O")
            print("=" * 70)
            # Deduplicate and show meaningful ops
            seen_create = set()
            write_counts = defaultdict(int)
            read_counts = defaultdict(int)
            deletes = []
            renames = []
            creates = []

            for e in file_io_events:
                op = e.operation
                path = e.path or ""
                if op == "CreateFile":
                    det = e.details or {}
                    disposition = det.get("Disposition", "")
                    # Only show creates that open/create files (skip duplicates)
                    key = (path, str(disposition))
                    if key not in seen_create:
                        seen_create.add(key)
                        creates.append(e)
                elif op == "WriteFile":
                    write_counts[path] += 1
                elif op == "ReadFile":
                    read_counts[path] += 1
                elif op == "SetDispositionInformationFile":
                    det = e.details or {}
                    if det.get("Delete", False):
                        deletes.append(e)
                elif op == "SetRenameInformationFile":
                    renames.append(e)

            # Show file creates with write activity
            print(f"\n  Files created/opened: {len(creates)}")
            print(f"  Files written to: {len(write_counts)}")
            print(f"  Files read from: {len(read_counts)}")
            print(f"  Files deleted: {len(deletes)}")
            print(f"  Files renamed: {len(renames)}")

            if write_counts:
                print(f"\n  --- Files written (by write count) ---")
                for path, count in sorted(write_counts.items(), key=lambda x: -x[1])[:50]:
                    print(f"    [{count:>4} writes] {path}")

            if read_counts:
                print(f"\n  --- Files read (by read count, top 30) ---")
                for path, count in sorted(read_counts.items(), key=lambda x: -x[1])[:30]:
                    print(f"    [{count:>4} reads]  {path}")

            if deletes:
                print(f"\n  --- Files deleted ---")
                for e in deletes:
                    dt = datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=e.date_filetime // 10)
                    tstr = dt.strftime("%H:%M:%S.%f")[:-3]
                    print(f"    {tstr}  {e.path}")

            if renames:
                print(f"\n  --- Files renamed ---")
                for e in renames[:50]:
                    dt = datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=e.date_filetime // 10)
                    tstr = dt.strftime("%H:%M:%S.%f")[:-3]
                    target = (e.details or {}).get("FileName", "?")
                    print(f"    {tstr}  {e.path}")
                    print(f"              -> {target}")
            print()

        # --- File timeline ---
        if args.file_timeline:
            print("=" * 70)
            print("FILE I/O TIMELINE")
            print("=" * 70)

            # Group consecutive ops on the same file into a single line
            # Pattern: Open -> Read(N bytes) -> Write(N bytes) -> Rename -> next file
            pending = {}  # path -> {reads: bytes, writes: bytes, first_ts, last_ts}
            output_lines = []

            def flush_pending(path):
                if path not in pending:
                    return
                p = pending.pop(path)
                dt = datetime.datetime(1601, 1, 1) + datetime.timedelta(
                    microseconds=p["first_ts"] // 10)
                tstr = dt.strftime("%H:%M:%S.%f")[:-3]
                parts = []
                if p["reads"] > 0:
                    parts.append(f"read {p['reads']:,} bytes")
                if p["writes"] > 0:
                    parts.append(f"wrote {p['writes']:,} bytes")
                if p.get("renamed"):
                    parts.append(f"renamed -> {p['renamed']}")
                if p.get("deleted"):
                    parts.append("DELETED")
                if p.get("created"):
                    parts.append(f"[{p['created']}]")
                action = ", ".join(parts) if parts else "opened"
                output_lines.append((p["first_ts"], tstr, path, action))

            def ensure_pending(path, ts):
                if path not in pending:
                    pending[path] = {
                        "reads": 0, "writes": 0,
                        "first_ts": ts, "last_ts": ts,
                        "renamed": None, "deleted": False, "created": None,
                    }
                pending[path]["last_ts"] = ts

            last_ft = None
            for e in file_timeline_events:
                op = e.operation
                path = e.path or ""
                ts = e.date_filetime
                det = dict(e.details) if e.details else {}

                # Time gap > 0.5s = flush all pending
                if last_ft and (ts - last_ft) > 5_000_000:
                    for p in list(pending.keys()):
                        flush_pending(p)
                last_ft = ts

                if op == "CreateFile":
                    # New file access — flush any previous pending for this path
                    flush_pending(path)
                    ensure_pending(path, ts)
                    disp = det.get("Disposition", "")
                    if disp:
                        pending[path]["created"] = disp
                elif op == "ReadFile":
                    ensure_pending(path, ts)
                    length = det.get("Length", 0)
                    if isinstance(length, int):
                        pending[path]["reads"] += length
                elif op == "WriteFile":
                    ensure_pending(path, ts)
                    length = det.get("Length", 0)
                    if isinstance(length, int):
                        pending[path]["writes"] += length
                elif op == "SetRenameInformationFile":
                    ensure_pending(path, ts)
                    target = det.get("FileName", "?")
                    pending[path]["renamed"] = target
                    flush_pending(path)
                elif op == "SetDispositionInformationFile":
                    ensure_pending(path, ts)
                    if det.get("Delete"):
                        pending[path]["deleted"] = True
                    flush_pending(path)
                elif op == "SetEndOfFileInformationFile":
                    ensure_pending(path, ts)

            # Flush remaining
            for p in list(pending.keys()):
                flush_pending(p)

            # Print with time gap separators
            prev_ft = None
            # Skip NTFS metadata noise ($Mft, $LogFile, $Directory, $Extend)
            skip_paths = {"C:\\$Mft", "C:\\$LogFile", "C:\\$Directory",
                          "C:\\$Extend\\$UsnJrnl:$J"}
            shown = 0
            for ft, tstr, path, action in output_lines:
                if path in skip_paths:
                    continue

                if prev_ft and (ft - prev_ft) > 10_000_000:
                    gap = (ft - prev_ft) / 10_000_000
                    print(f"\n  {'─' * 60}")
                    print(f"  ── {gap:.1f}s gap ──")
                    print(f"  {'─' * 60}\n")
                prev_ft = ft

                print(f"  {tstr}  {path}")
                print(f"               {action}")
                shown += 1

            ntfs_skipped = len(output_lines) - shown
            print(f"\n  Total: {shown} file operations shown"
                  f"{f' ({ntfs_skipped} NTFS metadata ops hidden)' if ntfs_skipped else ''}")
            print()

        # --- DLL loads ---
        if not args.no_dll:
            print("=" * 70)
            print("DLL LOADS")
            print("=" * 70)
            for e in dll_loads:
                dt = datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=e.date_filetime // 10)
                tstr = dt.strftime("%H:%M:%S.%f")[:-3]
                print(f"  {tstr}  {e.path}")
            print(f"\n  Total DLL loads: {len(dll_loads)}")
            print()


if __name__ == "__main__":
    main()
