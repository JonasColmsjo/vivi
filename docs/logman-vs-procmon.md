# Logman vs ProcMon: Xorist Ransomware Test

Test date: 2026-03-10
VM: winxp-dyn (Windows XP SP3, host-only on virbr1)
Host: tcentre1
Sample: `C:\malware-test\xorist.exe` (39,936 bytes, from STUDENT_LABS `X.ex_`)

## Test setup

Both tests used the same pre-xorist-logman snapshot (clean XP with extracted STUDENT_LABS and test target files in `C:\malware-test\targets\`).

Xorist behavior observed: encrypts files across C:\ with `.EnCiPhErEd` extension, drops `HOW TO DECRYPT FILES.txt` ransom notes in every directory, stays resident (PID visible in tasklist).

## Results summary

| Metric                    | Logman (ETW)          | ProcMon                    |
|---------------------------|-----------------------|----------------------------|
| Total events              | 53,146                | 353,735                    |
| Xorist-attributed events  | ~5,300 (thread 0x0628)| 47,249                     |
| File I/O events           | **0**                 | 48,512 (Read+Write+Create) |
| Registry events           | 52,382                | 54,858                     |
| Process/thread events     | 193                   | 6,706                      |
| Image load events         | 519                   | 519                        |
| Trace file size           | 4.2 MB (.etl)         | 129 MB (.PML)              |
| CSV/parsed size           | 7.7 MB                | N/A (parsed in Python)     |
| Overhead                  | Low                   | Medium-high                |
| Automation from telnet    | Yes (direct CLI)      | No (needs `at /interactive`) |

## Key findings

### 1. Logman misses file I/O on XP

Despite requesting `EVENT_TRACE_FLAG_FILE_IO` (0x02000000), **zero FileIO events** appeared in the logman trace. The XP kernel trace provider (v5.1) has limited FileIO support — it logs file name resolution metadata but not actual read/write/rename operations.

This is a critical gap for ransomware analysis, where the primary behavior is file encryption.

### 2. ProcMon captures the full encryption lifecycle

ProcMon recorded the complete Xorist attack chain:

- **1,350 SetRenameInformationFile** — renaming files to `.EnCiPhErEd`
- **3,357 WriteFile** — writing encrypted content + ransom notes
- **6,151 CreateFile** — opening files for encryption and creating ransom notes
- **4,044 ReadFile** — reading file contents before encryption
- **2,794 QueryDirectory** — enumerating directories to find targets
- **12,451 events touching `HOW TO DECRYPT FILES.txt`** — ransom note drops

### 3. Registry coverage is comparable

Both tools captured similar registry activity. Logman's 52K registry events include RunDown events (baseline enumeration at trace start), while ProcMon's 55K are all runtime events.

Key Xorist registry operations (visible in both):
- Checks `Image File Execution Options\xorist.exe` (anti-debug)
- Queries Terminal Server settings
- Checks `Compatibility32\xorist` and `IME Compatibility\xorist`

### 4. DLL loads are identical

Both captured the same 14 DLLs loaded by xorist.exe:
ntdll.dll, kernel32.dll, advapi32.dll, rpcrt4.dll, secur32.dll, comctl32.dll, gdi32.dll, user32.dll, shell32.dll, msvcrt.dll, shlwapi.dll, uxtheme.dll, comctl32.dll (WinSxS variant)

The GUI DLLs (gdi32, user32, shell32, comctl32) confirm Xorist has a GUI component (the ransom popup).

### 5. Logman is far easier to automate

Starting logman from telnet is a single command:
```cmd
logman create trace "NT Kernel Logger" -p {9e814aad-...} 0x12020007 0xff -o C:\trace.etl -ets
```

ProcMon requires `at /interactive` scheduling with a 1+ minute delay, then verification, and `/Terminate` via the same mechanism.

## When to use which

| Scenario                                    | Use           |
|---------------------------------------------|---------------|
| Automated batch analysis pipeline           | Logman        |
| Registry-focused analysis (persistence etc) | Logman        |
| File system behavior (ransomware, droppers) | **ProcMon**   |
| Full visibility into a single sample        | **ProcMon**   |
| Low-overhead continuous monitoring          | Logman        |
| XP malware analysis                         | **Both** (logman for registry, procmon for files) |
| Vista+/Win7+ malware analysis               | Logman improves significantly (better FileIO) |

## Recommendation

For XP dynamic analysis, **run both simultaneously**: logman captures registry and process events with zero GUI overhead, while ProcMon fills the critical FileIO gap. The logman ETL is small enough to always collect (4MB vs 129MB for ProcMon).

On Vista+ and Windows 7+, logman's kernel trace gains proper FileIO support and becomes a viable standalone option for automated pipelines.

## Artifacts

- `traces/xorist-logman.csv` — 53K events, 7.7MB
- `traces/xorist-logman.etl` — raw ETW trace, 4.2MB
- `traces/xorist-procmon.PML` — 354K events, 129MB
