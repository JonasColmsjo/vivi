# Windows CLI Tools for Digital Forensics

Comprehensive reference of command-line tools for Windows forensics, dynamic malware analysis, and incident response. Covers built-in Windows tools, Sysinternals, and third-party utilities. Notes on Windows XP compatibility where relevant.

---

## 1. Built-in Windows Tools

### Process & Service Management

| Tool              | Purpose                                              | XP?  | Example                                          |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `tasklist`        | List running processes with PID, memory, session     | Yes  | `tasklist /v /fo csv`                            |
| `taskkill`        | Kill processes by PID or name                        | Yes  | `taskkill /f /im malware.exe`                    |
| `sc`              | Service control (query, start, stop, create, delete) | Yes  | `sc query state= all`                            |
| `net start`       | List running services                                | Yes  | `net start`                                      |
| `net stop`        | Stop a service                                       | Yes  | `net stop "Service Name"`                        |
| `wmic process`    | Detailed process info (cmdline, parent PID, owner)   | Yes  | `wmic process get Name,ProcessId,ParentProcessId,CommandLine /format:csv` |
| `wmic service`    | Service details (path, start mode, state)            | Yes  | `wmic service get Name,PathName,StartMode,State` |
| `at`              | Schedule tasks (XP), runs in interactive session     | Yes  | `at 14:30 /interactive cmd /c start procmon.exe` |
| `schtasks`        | Task scheduler (Vista+), replaces `at`               | No*  | `schtasks /query /fo list /v`                    |

*`schtasks` exists on XP but with limited functionality.

### Network

| Tool              | Purpose                                              | XP?  | Example                                          |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `netstat`         | Active connections, listening ports, owning PID      | Yes  | `netstat -anob`                                  |
| `ipconfig`        | Network adapter configuration, DNS cache             | Yes  | `ipconfig /all`, `ipconfig /displaydns`          |
| `nbtstat`         | NetBIOS name table, cache, sessions                  | Yes  | `nbtstat -c`, `nbtstat -S`                       |
| `arp`             | ARP cache (IP-to-MAC mappings)                       | Yes  | `arp -a`                                         |
| `route`           | Routing table                                        | Yes  | `route print`                                    |
| `nslookup`        | DNS lookup                                           | Yes  | `nslookup malware-c2.com`                        |
| `ping`            | Connectivity test                                    | Yes  | `ping -n 1 192.168.100.1`                        |
| `tftp`            | TFTP client (built-in on XP, removed in Vista+)     | Yes  | `tftp -i 192.168.100.1 PUT file.pml`            |
| `ftp`             | FTP client                                           | Yes  | `ftp 192.168.100.1`                              |
| `net use`         | Map/list network shares                              | Yes  | `net use \\host\share /user:name pass`           |
| `net session`     | Active SMB sessions                                  | Yes  | `net session`                                    |
| `net view`        | Browse network shares                                | Yes  | `net view \\host`                                |
| `netsh`           | Network config, firewall rules, packet capture (7+)  | Part | `netsh firewall show state` (XP), `netsh trace start` (7+) |

### File System

| Tool              | Purpose                                              | XP?  | Example                                          |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `dir`             | List files with timestamps, sizes, attributes        | Yes  | `dir /s /a /t:w C:\`                            |
| `attrib`          | View/set file attributes (hidden, system, readonly)  | Yes  | `attrib +h +s file.exe`                          |
| `icacls`          | File permissions (ACLs)                              | No   | `icacls C:\Windows\System32\*.exe`               |
| `cacls`           | File permissions (legacy, XP)                        | Yes  | `cacls C:\file.exe`                              |
| `cipher`          | EFS encryption status, wipe deleted data             | Yes  | `cipher /u /n /h`                                |
| `compact`         | NTFS compression status                              | Yes  | `compact /s:C:\`                                 |
| `fsutil`          | NTFS metadata, USN journal, hardlinks                | Yes  | `fsutil usn readjournal C:`                      |
| `type`            | Print file contents                                  | Yes  | `type C:\ransom-note.txt`                        |
| `copy`            | Copy files                                           | Yes  | `copy C:\file.exe C:\evidence\`                 |
| `xcopy`           | Extended copy with subdirectories                    | Yes  | `xcopy /s /e /h source dest`                     |
| `robocopy`        | Robust copy (Vista+), retry logic, logging           | No   | `robocopy src dst /mir /log:copy.log`            |
| `find`            | Search file contents for strings                     | Yes  | `find /i "malware" C:\logs\*.log`               |
| `findstr`         | Regex search in files                                | Yes  | `findstr /s /i "password" C:\*.txt`             |
| `tree`            | Directory tree structure                             | Yes  | `tree /f C:\Users > tree.txt`                   |
| `fc`              | Compare two files                                    | Yes  | `fc /b file1.exe file2.exe`                      |
| `comp`            | Binary file comparison                               | Yes  | `comp file1 file2 /m`                            |

### Registry

| Tool              | Purpose                                              | XP?  | Example                                          |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `reg query`       | Read registry keys/values                            | Yes  | `reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` |
| `reg add`         | Create/modify registry values                        | Yes  | `reg add HKLM\...\Run /v name /d "path" /f`     |
| `reg delete`      | Delete registry keys/values                          | Yes  | `reg delete HKLM\...\Run /v name /f`            |
| `reg export`      | Export registry branch to .reg file                  | Yes  | `reg export HKLM\SOFTWARE soft.reg`              |
| `reg save`        | Save hive to binary file (for offline analysis)      | Yes  | `reg save HKLM\SYSTEM system.hiv`               |
| `reg compare`     | Compare two registry keys                            | Yes  | `reg compare HKLM\key1 HKLM\key2`               |

### User & Group Management

| Tool              | Purpose                                              | XP?  | Example                                          |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `net user`        | List users, create/modify accounts                   | Yes  | `net user`, `net user hacker /add`               |
| `net localgroup`  | List/modify local groups                             | Yes  | `net localgroup Administrators`                  |
| `whoami`          | Current user and privileges                          | No*  | `whoami /priv /groups`                           |
| `logoff`          | Log off a session                                    | Yes  | `logoff`                                         |

*`whoami` not on XP by default (available as resource kit tool).

### System Information

| Tool              | Purpose                                              | XP?  | Example                                          |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `systeminfo`      | OS version, hotfixes, boot time, network config      | Yes  | `systeminfo`                                     |
| `hostname`        | Computer name                                        | Yes  | `hostname`                                       |
| `ver`             | OS version string                                    | Yes  | `ver`                                            |
| `set`             | Environment variables                                | Yes  | `set`                                            |
| `wmic os`         | Detailed OS info                                     | Yes  | `wmic os get Caption,Version,BuildNumber,LastBootUpTime` |
| `wmic qfe`        | Installed hotfixes/patches                           | Yes  | `wmic qfe list full`                             |
| `wmic startup`    | Startup programs                                     | Yes  | `wmic startup get Caption,Command,Location`      |
| `wmic logicaldisk`| Disk info                                            | Yes  | `wmic logicaldisk get Name,Size,FreeSpace`       |
| `wmic useraccount`| User account details                                 | Yes  | `wmic useraccount get Name,SID,Status`           |
| `driverquery`     | Installed drivers                                    | Yes  | `driverquery /v /fo csv`                         |

### Event Logs

| Tool              | Purpose                                              | XP?  | Example                                          |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `wevtutil`        | Query/export event logs (Vista+)                     | No   | `wevtutil qe Security /c:50 /f:text`            |
| `eventquery.vbs`  | Query event logs (XP)                                | Yes  | `cscript eventquery.vbs /l Security`             |
| `wmic ntevent`    | Query event logs via WMI                             | Yes  | `wmic ntevent where "LogFile='Security'" get TimeGenerated,Message /format:csv` |

### Shutdown & Power

| Tool              | Purpose                                              | XP?  | Example                                          |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `shutdown`        | Shutdown/restart/logoff                              | Yes  | `shutdown -s` (XP), `shutdown /s /t 0` (Vista+) |

**XP note**: Use `-s` not `/s` flag style. `-t 0` not always supported.

---

## 2. Sysinternals Suite (CLI Tools)

All tools from https://live.sysinternals.com/ — most work on XP SP3.

### Process Analysis

| Tool              | Purpose                                              | XP?  | Notes                                            |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `pslist`          | List processes with CPU/memory/thread counts         | Yes  | `pslist -t` (tree view)                          |
| `psinfo`          | System information (OS, hotfixes, uptime)            | Yes  | `psinfo -h -s -d`                                |
| `pskill`          | Kill process by PID or name                          | Yes  | `pskill malware.exe`                             |
| `psservice`       | Service management with detailed info                | Yes  | `psservice query`                                |
| `psloglist`       | Dump event logs to text/CSV                          | Yes  | `psloglist -s Security`                          |
| `psloggedon`      | Show logged-on users (local + remote)                | Yes  | `psloggedon`                                     |
| `listdlls`        | List DLLs loaded by each process                     | Yes  | `listdlls -u` (unsigned only)                    |
| `handle`          | List open handles (files, registry, mutexes)         | Yes  | `handle -a -p malware.exe`                       |
| `PsExec`          | Run commands as another user/session/remote           | Yes  | `psexec -i -s cmd.exe` (interactive SYSTEM cmd)  |

**PsExec `-i` flag**: Critical for running GUI apps from a non-interactive session (like telnet). On XP (no Session 0 isolation), `-i` launches the process in the interactive desktop session. This is how to run ProcMon from telnet:
```
psexec -i -d "C:\Tools\Procmon.exe" /AcceptEula /Quiet /BackingFile C:\procmon-sample
```
- `-i`: interactive session (shows GUI on desktop)
- `-d`: don't wait for process to exit
- `-s`: run as SYSTEM (optional, useful for more access)

### Autoruns / Persistence

| Tool              | Purpose                                              | XP?  | Notes                                            |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `autorunsc`       | CLI autoruns — lists ALL persistence mechanisms      | Yes  | `autorunsc -a * -m -h -s -c > autoruns.csv`     |

**autorunsc flags**:
- `-a *` — all categories (boot, logon, services, drivers, scheduled tasks, etc.)
- `-m` — hide Microsoft entries (show only third-party)
- `-h` — show file hashes
- `-s` — verify digital signatures
- `-c` — CSV output
- `-v` — check VirusTotal (requires internet)
- `-t` — tab-delimited output

This is the **best CLI tool for finding malware persistence**. Use it for baseline vs post-infection comparison.

### File & Disk

| Tool              | Purpose                                              | XP?  | Notes                                            |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `sigcheck`        | Verify digital signatures, show file version info    | Yes  | `sigcheck -e -u C:\Windows\System32\`           |
| `streams`         | Show NTFS alternate data streams                     | Yes  | `streams -s C:\`                                |
| `du`              | Disk usage by directory                              | Yes  | `du -v C:\Users`                                |
| `junction`        | List/create NTFS junction points                     | Yes  | `junction C:\suspicious-link`                    |
| `sdelete`         | Secure delete (overwrite)                            | Yes  | `sdelete -p 3 file.exe`                         |

### Network

| Tool              | Purpose                                              | XP?  | Notes                                            |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `tcpview`         | GUI — live TCP/UDP connections with process names     | Yes  | (GUI only, use `netstat -anob` for CLI)          |
| `psping`          | TCP/ICMP ping with latency stats                     | Yes  | `psping -t host:port`                            |
| `whois`           | WHOIS lookup                                         | Yes  | `whois malware-domain.com`                       |

### Monitoring (Mostly GUI, some CLI modes)

| Tool              | Purpose                                              | XP?  | Notes                                            |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `Procmon`         | Process Monitor — file/reg/net/process activity      | Yes  | See section below                                |
| `ProcDump`        | Create process memory dumps on triggers              | Yes  | `procdump -ma malware.exe dump.dmp`              |
| `FileMon`         | Legacy file system monitor (precursor to ProcMon)    | Yes  | Standalone, lighter than ProcMon                 |
| `RegMon`          | Legacy registry monitor (precursor to ProcMon)       | Yes  | Standalone, lighter than ProcMon                 |
| `Diskmon`         | Disk I/O monitor                                     | Yes  | GUI only                                         |

### ProcMon CLI Reference

ProcMon is a GUI app but has extensive CLI flags for automation:

```
Procmon.exe /AcceptEula /Quiet /Minimized /BackingFile C:\log
Procmon.exe /Terminate
Procmon.exe /OpenLog C:\log.PML /SaveAs C:\log.CSV
Procmon.exe /LoadConfig C:\filter.pmc
```

| Flag               | Purpose                                             |
|---------------------|-----------------------------------------------------|
| `/AcceptEula`      | Skip EULA dialog (required for first run)            |
| `/Quiet`           | No confirmation dialogs                              |
| `/Minimized`       | Start minimized to tray                              |
| `/BackingFile path` | Log to file instead of virtual memory               |
| `/Terminate`       | Stop a running ProcMon instance                      |
| `/OpenLog path`    | Open a PML/PML file                                  |
| `/SaveAs path`     | Export to CSV/XML (use with /OpenLog)                |
| `/LoadConfig path` | Load a filter configuration (.pmc)                   |
| `/NoFilter`        | Disable all filters                                  |
| `/NoConnect`       | Don't auto-start capture                             |
| `/Profiling`       | Enable profiling events                              |
| `/Runtime N`       | Auto-stop after N seconds                            |

**Critical XP limitation**: ProcMon is a GUI app. It MUST run in an interactive desktop session. Launching from telnet or a Windows service session will silently fail (process starts but no driver/capture). Solutions:
1. **PsExec `-i -d`**: Launch ProcMon in the interactive session from telnet
2. **`at /interactive`**: Schedule ProcMon to run in the interactive session
3. **Start from VNC**: Manually start before detonation
4. **Use FileMon + RegMon**: Separate legacy tools, may work better from services

---

## 3. ETW (Event Tracing for Windows) — ProcMon Alternative

ETW is a kernel-level tracing framework. On Vista+ it can replace ProcMon for CLI-only monitoring. Limited on XP.

### logman (Vista+)

```cmd
:: Start a kernel trace (file I/O, registry, process, network)
logman create trace "MalwareTrace" -p "Microsoft-Windows-Kernel-Process" -o C:\trace.etl
logman start "MalwareTrace"

:: ... run malware ...

logman stop "MalwareTrace"
logman delete "MalwareTrace"

:: Convert to readable format
tracerpt C:\trace.etl -o C:\trace.csv -of csv
```

### Key ETW Providers

| Provider                              | Events                              |
|---------------------------------------|-------------------------------------|
| `Microsoft-Windows-Kernel-Process`    | Process create/exit                 |
| `Microsoft-Windows-Kernel-File`       | File operations                     |
| `Microsoft-Windows-Kernel-Registry`   | Registry operations                 |
| `Microsoft-Windows-Kernel-Network`    | Network connections                 |
| `Microsoft-Windows-DNS-Client`        | DNS queries                         |

**XP note**: ETW exists on XP but with far fewer providers. `logman` is available but the kernel providers above are Vista+. On XP, ProcMon/FileMon/RegMon remain the best options.

---

## 4. Third-Party CLI Forensics Tools

### Memory Acquisition & Analysis

| Tool              | Purpose                                              | XP?  | Notes                                            |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `winpmem`         | Acquire physical memory dump                         | Yes  | `winpmem_mini.exe memdump.raw`                   |
| `DumpIt`          | One-click memory dump (Moonsols)                     | Yes  | Just run — creates dump in current dir           |
| `Volatility`      | Memory forensics framework (runs on analyst machine) | N/A  | `vol.py -f dump.raw --profile=WinXPSP3x86 pslist` |
| `strings`         | Extract printable strings from binaries              | Yes  | `strings malware.exe > strings.txt`              |

### Disk & File Analysis

| Tool              | Purpose                                              | XP?  | Notes                                            |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `md5sum`/`certutil` | File hashing                                       | Yes  | `certutil -hashfile file.exe MD5` (XP+)         |
| `sha256deep`      | Recursive hashing                                    | Yes  | `sha256deep -r C:\ > hashes.txt`                |
| `foremost`        | File carving (runs on Linux)                         | N/A  | `foremost -i disk.dd -o output/`                 |

### Network Capture

| Tool              | Purpose                                              | XP?  | Notes                                            |
|-------------------|------------------------------------------------------|------|--------------------------------------------------|
| `RawCap`          | Lightweight packet capture (no WinPcap needed)       | Yes  | `RawCap.exe 192.168.100.50 capture.pcap`        |
| `WinDump`         | tcpdump for Windows (needs WinPcap)                  | Yes  | `windump -i 1 -w capture.pcap`                  |
| `netsh trace`     | Built-in packet capture (Win7+)                      | No   | `netsh trace start capture=yes`                  |

### File Transfer (from XP VM to host)

| Method            | Built-in? | Direction     | Notes                                            |
|-------------------|-----------|---------------|--------------------------------------------------|
| `tftp`            | Yes (XP)  | Push/Pull     | `tftp -i host PUT file` — best for XP           |
| `ftp`             | Yes       | Push/Pull     | Requires FTP server on host                      |
| `net use` + `copy`| Yes       | Push/Pull     | SMB share: `net use Z: \\host\share`             |
| `bitsadmin`       | Yes (XP+) | Pull only     | `bitsadmin /transfer dl http://host/file C:\f`   |
| `certutil`        | Yes (XP+) | Pull only     | `certutil -urlcache -split -f http://host/f C:\f`|
| `VBScript wget`   | Yes       | Pull only     | See below                                        |
| `PowerShell`      | No (XP)   | Pull only     | Not available on XP                              |

**VBScript wget (universal XP method)**:
```vbs
' wget.vbs — Usage: cscript wget.vbs http://host/file output.exe
Set args = WScript.Arguments
Set http = CreateObject("MSXML2.XMLHTTP")
http.Open "GET", args(0), False
http.Send
Set stream = CreateObject("ADODB.Stream")
stream.Type = 1
stream.Open
stream.Write http.ResponseBody
stream.SaveToFile args(1), 2
stream.Close
```

---

## 5. WMIC Quick Reference

WMIC is extremely powerful for forensics on XP. Key aliases:

```cmd
wmic process list full                          :: All process details
wmic process where name="malware.exe" get CommandLine,ParentProcessId
wmic startup list full                          :: All autostart entries
wmic service where state="running" list full    :: Running services
wmic ntevent where "LogFile='Security' AND EventCode='4624'" list  :: Logon events
wmic qfe list full                              :: Installed patches
wmic product get Name,Version                   :: Installed software
wmic os get LastBootUpTime                      :: Last boot time
wmic useraccount list full                      :: User accounts
wmic group list full                            :: Groups
wmic share list full                            :: Network shares
wmic nicconfig get Description,IPAddress,MACAddress  :: Network config
wmic /output:C:\info.html os list full /format:htable  :: HTML report
```

WMIC output formats: `/format:csv`, `/format:list`, `/format:htable`, `/format:table`
Redirect: `wmic /output:C:\out.csv process list full /format:csv`

---

## 6. Forensics Workflow: CLI-Only Baseline & Post-Infection

### Baseline Capture (before detonation)

```cmd
:: Save to C:\baseline\
mkdir C:\baseline

:: Processes
tasklist /v /fo csv > C:\baseline\processes.csv
wmic process get Name,ProcessId,ParentProcessId,CommandLine,ExecutablePath /format:csv > C:\baseline\wmic-procs.csv

:: Network
netstat -anob > C:\baseline\netstat.txt
ipconfig /all > C:\baseline\ipconfig.txt
ipconfig /displaydns > C:\baseline\dns-cache.txt
arp -a > C:\baseline\arp.txt

:: Autoruns/persistence
autorunsc -a * -m -h -c > C:\baseline\autoruns.csv
reg export HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run C:\baseline\run-hklm.reg
reg export HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run C:\baseline\run-hkcu.reg

:: Services
sc query state= all > C:\baseline\services.txt

:: File listing (key directories)
dir /s /a /t:w C:\WINDOWS\system32\ > C:\baseline\system32-files.txt
dir /s /a /t:w "C:\Documents and Settings\" > C:\baseline\user-files.txt

:: Scheduled tasks
at > C:\baseline\at-tasks.txt

:: System info
systeminfo > C:\baseline\sysinfo.txt
```

### Post-Infection Capture

Same commands but output to `C:\post\`. Then diff locally:
```bash
# On analyst machine after pulling both directories via TFTP
diff baseline/processes.csv post/processes.csv
diff baseline/autoruns.csv post/autoruns.csv
diff baseline/netstat.txt post/netstat.txt
comm -13 <(sort baseline/system32-files.txt) <(sort post/system32-files.txt)
```

---

## 7. Key Registry Locations for Malware Analysis

### Persistence (Run keys)

```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce
HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServices      (9x/XP)
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServicesOnce  (9x/XP)
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Userinit
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run
HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run
```

### Services

```
HKLM\SYSTEM\CurrentControlSet\Services\<ServiceName>
  ImagePath    = executable path
  Start        = 2 (auto), 3 (manual), 4 (disabled)
  Type         = 0x10 (own process), 0x20 (shared)
```

### Browser Helper Objects (BHOs)

```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects\
```

### Shell Extensions / File Associations

```
HKCR\exefile\shell\open\command
HKCR\.exe
HKLM\SOFTWARE\Classes\exefile\shell\open\command
```

### AppInit DLLs (DLL injection)

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\AppInit_DLLs
```

### Image File Execution Options (debugger hijack)

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\<target.exe>\Debugger
```

---

## 8. XP-Specific Notes

1. **No Session 0 isolation**: All interactive users share Session 0. PsExec `-i` works reliably.
2. **No UAC**: Everything runs as admin if logged in as admin.
3. **No PowerShell**: Use VBScript, batch files, or WMIC.
4. **TFTP built-in**: Best file transfer method for XP VMs.
5. **`at /interactive`**: Schedules commands to run in the interactive desktop session.
6. **Telnet server**: Must install via Add/Remove Programs > Windows Components. Configure NTLM auth mode via registry:
   ```
   reg add HKLM\SOFTWARE\Microsoft\TelnetServer\1.0 /v NTLM /t REG_DWORD /d 2 /f
   ```
   Value 2 = plaintext auth (needed for Linux telnet clients).
7. **`shutdown -s`**: Use dash flags, not slash flags. No `-t 0` needed.
8. **ProcMon works on XP SP3** but must run in interactive session (not from telnet/service).
9. **FileMon/RegMon**: Legacy predecessors of ProcMon. Separate tools, potentially easier to run from non-interactive sessions.
10. **certutil**: Available on XP for hashing (`-hashfile`) and downloading (`-urlcache`).
