# gizur-vivi

VM sandbox manager for dynamic malware analysis and reverse engineering. Manages KVM and VMware virtual machines on remote hosts via SSH.

## Structure

| Path                              | Purpose                                                  |
|-----------------------------------|----------------------------------------------------------|
| `justfile`                        | Thin wrappers delegating to scripts/                     |
| `config.sh`                       | **Gitignored** — host config, paths, credentials         |
| `config.sh.template`              | Template for config.sh — copy and edit                   |
| `scripts/lib.sh`                  | Shared functions (hypervisor detection, NBD, registry)    |
| `scripts/vm.sh`                   | Main dispatcher — routes to vm-kvm.sh, vm-vmware.sh, or vm-arm.sh |
| `scripts/vm-kvm.sh`              | All KVM/libvirt operations                                |
| `scripts/vm-arm.sh`              | ARM QEMU standalone VM operations (not libvirt)           |
| `scripts/vm-vmware.sh`           | All VMware Workstation operations                         |
| `scripts/vm-exec.exp`            | Telnet command execution on Windows VMs (expect)          |
| `scripts/vm-scp.sh`             | SFTP file transfer to/from VMs (freeSSHd + OpenSSH)       |
| `scripts/vm-ip.sh`               | VM IP discovery (virsh domifaddr + ARP fallback)          |
| `scripts/procmon-ctl.sh`         | ProcMon lifecycle (start/stop/status) via PsExec          |
| `scripts/ftp-server.sh`          | FTP server for large file transfers from VMs              |
| `scripts/setup-vm.sh`            | Install tools into VMs (Sysinternals, Python)             |
| `scripts/build-tools-iso.sh`    | Build XP tools ISO (7-Zip, VC++ runtimes, etc.)           |
| `scripts/snapshot-state.sh`     | Capture filesystem + registry state from mounted VM        |
| `scripts/trace.sh`               | ETW trace management (logman) via telnet                  |
| `scripts/ghidra/`               | Ghidra headless scripts (decompile + call graph export)   |
| `scripts/annotate-deep.sh`      | Bottom-up LLM annotation orchestrator (Ghidra + call graph) |
| `scripts/analysis/`              | Python analysis tools (filesystem-diff, registry-diff, topo-sort, parse-procmon-csv) |
| `requirements.txt`                | Python dependencies (all packages in one place)              |
| `ansible/setup-local.yml`         | Ansible: install local dependencies (remmina, Ghidra, VNC) |
| `ansible/setup-kvm-forensics.yml` | Ansible: install KVM/libvirt + forensic tools on host    |

## Setup

```bash
cp config.sh.template config.sh    # Edit with your host details
just setup                          # Install local dependencies
just docs                           # Full usage reference
```

## Configuration

`config.sh` is gitignored. Copy `config.sh.template` and edit:
- Host SSH aliases and IPs
- Storage paths (KVM templates, ISOs, sandboxes)
- VM credentials (for telnet access)
- Networking (bridge names, host-only IPs)
- FTP server settings
- Guest tool paths (Sysinternals, PsExec)
- Tools source directory (`TOOLS_SOURCE`)
- Malware sample definitions (`MALWARE_CMD` associative array, or via `samples.sh` in consumer repos)

## Architecture

The justfile is a thin dispatcher. Each target calls `./scripts/vm.sh <host> <action> [args...]`, which:
1. Sources `config.sh` (via `lib.sh`) for host-specific variables and OS presets
2. Detects the active hypervisor (KVM or VMware) on the remote host
3. Dispatches to `scripts/vm-kvm.sh` or `scripts/vm-vmware.sh`

Telnet-based targets (`exec`, `sync-clock`, `procmon`, `ftp`) source `lib.sh` directly and use `vm-exec.exp` for command execution.

## Conventions

- **Match QEMU arch to guest OS bitness**: 32-bit guests (e.g. Windows XP x86) MUST run on `qemu-system-i386`, 64-bit guests on `qemu-system-x86_64`. Running a 32-bit guest on `qemu-system-x86_64` breaks GDB hardware breakpoints, hardware watchpoints, and software breakpoints — the x86-64 GDB stub cannot set debug registers for 32-bit code. Always warn when a mismatched combination is detected.
- **NEVER install packages directly on tcentre1/tcentre2** via `apt install` or `ssh root`. Always update the Ansible playbook in `ansible/` and run it. This keeps host configuration reproducible and documented.
- **Copy files to stopped VMs directly** — mount the instance disk (`just disk inspect <name> mount`), copy files into the mounted filesystem, then unmount. No need to build an ISO.
- **All VM operations run over SSH** — the justfile never assumes local execution
- **Triple backend support**: KVM/libvirt, VMware Workstation (mutually exclusive, switch with `just host hypervisor`), and ARM QEMU standalone
- **ARM VM detection**: `vm.sh` auto-routes to `vm-arm.sh` when template name contains `arm64` or instance has a `-vars.fd` file
- **Storage paths on hosts**: `/mnt/vm/kvm/templates/` (templates), `/mnt/vm/kvm/instances/` (running VMs), `/mnt/vm/sandboxes/` (VMware)
- **Forensic tools**: `regipy` and `python-evtx` in `/home/me/forensics-venv/` on the host
- **Config**: Host IPs, paths, credentials, and OS presets are in `config.sh` (not hardcoded in justfile)

## Dynamic analysis workflow

Full malware analysis pipeline — capture baseline, run sample, capture post-state, analyze diffs:

```bash
just disk inspect winxp-dyn mount
just disk snapshot-state winxp-dyn baseline ./artifacts/sample
just disk inspect winxp-dyn umount

just da run winxp-dyn sample ./artifacts/sample 60

just disk inspect winxp-dyn mount
just disk snapshot-state winxp-dyn post ./artifacts/sample
just disk inspect winxp-dyn umount

just sa analyze ./artifacts/sample
just vm snapshot winxp-dyn revert clean
```

## ARM VM workflow (Linux malware analysis)

ARM VMs run as standalone `qemu-system-aarch64` (not libvirt). The arm64 kernel has `CONFIG_COMPAT=y` so ARM 32-bit binaries run natively. Login: root, no password, serial console.

```bash
# Create and launch ARM sandbox
just vm launch debian-12-nocloud-arm64 mirai-sandbox --hostonly

# Interact
just vm connect mirai-sandbox          # serial console (Ctrl-] to detach)
just vm telnet mirai-sandbox 'uname -a'  # run command via serial

# Snapshot management
just vm snapshot mirai-sandbox create pre-infection
just vm snapshot mirai-sandbox revert clean
just vm snapshot mirai-sandbox list

# Lifecycle
just vm stop mirai-sandbox
just vm start mirai-sandbox
just vm destroy mirai-sandbox
```

ARM instance files in `${KVMDIR}/instances/`:
- `<name>.qcow2` — disk (linked clone of template)
- `<name>-vars.fd` — UEFI vars (presence = ARM VM indicator)
- `<name>.pid` — QEMU process ID
- `<name>-serial.sock` — serial console socket
- `<name>-monitor.sock` — QEMU monitor socket
- `<name>-vars-<snap>.fd` — UEFI vars backup per snapshot

Malware samples are defined in `config.sh` via `MALWARE_CMD` associative array, or in a `samples.sh` file in consumer repos that import this justfile. The `da run` target auto-sources `samples.sh` from the importing justfile's directory.

## ProcMon workflow

ProcMon is a GUI app — it cannot run from a telnet session. We use **PsExec -i** to launch it in the interactive desktop session.

```bash
just setup sysinternals winxp-dyn   # Install Sysinternals (one-time)
just da procmon winxp-dyn start my-capture
# ... run malware ...
just da procmon winxp-dyn stop
just vm ftp pull winxp-dyn 'C:\my-capture.PML' ./artifacts/
```

Key rules:
- **PsExec -i -d**: launches ProcMon in interactive session instantly
- **/Terminate**: must be sent from interactive session (PsExec or `at /interactive`)
- **taskkill /f corrupts PML files** — never use it for ProcMon
- **FTP for large files**: TFTP times out >30MB, use `just vm ftp` instead

## Win10 template setup

When creating a new Win10 template, the first step is to **manually install OpenSSH client and server** via the browser/GUI inside the VM. Portable OpenSSH builds (9.5, 9.8) have privilege separation issues on Win10 that cause `sshd-session.exe` crashes (exit 255) and service permission errors. The built-in Windows capability (`Add-WindowsCapability`) also fails without Windows Update access.

**Recommended steps:**
1. Launch VM with network (`--hostonly` + NAT if needed, or bridge)
2. Open Edge/browser, download official Win32-OpenSSH MSI from GitHub releases
3. Install, then verify: `net start sshd`, `ssh me@localhost`
4. Set sshd to auto-start: `sc.exe config sshd start= auto`
5. Save as template: `just vm save <name> <template-name>`

## SSH access

### SSH server per OS

| Guest OS        | SSH server       | Notes                                                       |
|-----------------|------------------|-------------------------------------------------------------|
| winxp, winxpx64 | freeSSHd         | Install from xp-tools ISO; needs legacy key options         |
| win10, win10x64 | Windows OpenSSH  | Install MSI from GitHub releases (built-in capability fails)|
| win11x64        | Windows OpenSSH  | Same as Win10                                               |

### freeSSHd on XP (OpenSSH 10+ compatibility)

OpenSSH 10.0+ removed `ssh-rsa` and `ssh-dss` by default. freeSSHd only supports these legacy algorithms. Required SSH options:

```bash
ssh -o 'HostkeyAlgorithms +ssh-rsa' \
    -o 'PubkeyAcceptedKeyTypes +ssh-rsa' \
    -o 'KexAlgorithms +diffie-hellman-group14-sha1,diffie-hellman-group1-sha1' \
    -o StrictHostKeyChecking=no \
    me@<vm-ip>
```

**Limitations**:
- Shell exec fails (`Failed to Execute process`) — use telnet for command execution
- SCP fails (can't resolve Windows paths) — `just scp` uses SFTP instead, which works

### Usage

```bash
just vm ssh <name>                          # Interactive SSH shell
just vm ssh <name> 'dir C:\'               # Run command via SSH
just vm scp <name> pull C:\file.txt /tmp/   # SCP file from VM
```

The `ssh` target auto-detects XP vs Win10+ from the template name and applies the correct SSH options.

## XP telnet setup

Telnet requires NTLM registry fix and TelnetClients group membership:
```cmd
reg add HKLM\SOFTWARE\Microsoft\TelnetServer\1.0 /v NTLM /t REG_DWORD /d 2 /f
net localgroup TelnetClients me /add
```
Shutdown command on XP: `shutdown -s` (not `/s`, not `-s -t 0`).

## VM hardware compatibility

### NIC models

| Guest OS          | NIC model | Why                                                    |
|-------------------|-----------|--------------------------------------------------------|
| winxp, winxpx64   | rtl8139   | XP has no virtio or e1000 drivers built-in             |
| win10, win10x64   | virtio    | Best performance, drivers included since Vista          |
| win11x64          | virtio    | Best performance, drivers included since Vista          |

NIC model is auto-selected by OS type in `vm-kvm.sh`. Both bridge and hostonly use the same model.

### RAM and CPU limits

| Guest OS         | Max RAM | CPUs | Notes                                                  |
|------------------|---------|------|--------------------------------------------------------|
| 32-bit (any)     | 2 GB    | 1    | 4GB hangs KVM SPICE — 32-bit can only address ~3.5GB  |
| 64-bit Win10/11  | 4 GB    | 2    | Can increase if host has headroom                       |
| XP (32-bit)      | 1 GB    | 1    | Lightweight, 1GB is plenty                              |
| XP x64           | 1 GB    | 1    | 64-bit but old — keep resources low                     |

### Network modes

Default is **hostonly** (no internet) — malware VMs should be isolated.

| Flag           | Bridge  | Internet | Telnet/SSH | Use case                    |
|----------------|---------|----------|------------|-----------------------------|
| (default)      | virbr1  | No       | Yes        | Malware analysis            |
| `--bridge`     | virbr0  | Yes      | Yes        | OS install, tool downloads  |
| `--no-network` | —       | No       | No         | Fully air-gapped            |

### Boot order

`virt-install` does not always add cdrom to boot order. The install command uses `--boot cdrom,hd` explicitly to ensure ISO boot works.

## VM networking

- Host-only bridge: `virbr1`, host IP `192.168.100.1`
- VM gets IP via DHCP — find with: `just vm ip <name>`
- `virsh domifaddr` often fails on XP — `vm-ip.sh` falls back to ARP

## ETW tracing (logman)

Logman manages ETW kernel traces from telnet (no GUI needed). On XP, use the "NT Kernel Logger" session with hex flags — symbolic flags `(process,fileio)` break over telnet.

```bash
just da trace start winxp-dyn mytrace              # Default flags (process+thread+img+fileio+registry)
just da trace start winxp-dyn mytrace 0x12020107   # Add disk I/O
# ... run malware ...
just da trace stop winxp-dyn mytrace
just da trace pull winxp-dyn mytrace ./traces/
```

Key limitation: **XP logman captures no FileIO events** despite the flag. Use ProcMon for file system visibility. On Vista+, logman FileIO works properly. See [`docs/logman-vs-procmon.md`](docs/logman-vs-procmon.md) for detailed comparison.

## Deep annotation pipeline (Ghidra + call graph + LLM)

Bottom-up LLM annotation using call graph awareness. Callee summaries are injected into caller prompts so the LLM understands context.

```bash
just sa re annotate-deep path/to/unpacked.exe
just sa re annotate-deep path/to/unpacked.exe --context path/to/context.txt
just sa re ghidra-decompile path/to/unpacked.exe  # Ghidra only
```

Pipeline stages:
1. **Ghidra headless** → `functions.json` + `callgraph.json` (cached in `<name>-ghidra/`)
2. **Topological sort** → `waves.json` (leaves first, SCCs grouped)
3. **Annotate bottom-up** → per-function `.c` files + `summaries.json` (resumable, 10 parallel)
4. **Summary pass** → top-level analysis header
5. **Assemble** → `<name>-annotated-deep.c`

Key files:
- `scripts/ghidra/ExportFunctionsAndCallGraph.py` — Ghidra Jython export script
- `scripts/analysis/topo-sort.py` — NetworkX SCC + topological sort
- `scripts/annotate-deep.sh` — Main orchestrator
- `scripts/annotate-deep-prompt.txt` — Generic per-function prompt template

The `--context` flag injects sample-specific notes (e.g., encryption algorithm, key addresses).

## Reference docs

- Windows CLI forensics tools: [`docs/windows-cli-forensics-tools.md`](docs/windows-cli-forensics-tools.md)
- Logman vs ProcMon comparison: [`docs/logman-vs-procmon.md`](docs/logman-vs-procmon.md)
