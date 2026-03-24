# vivi

VM sandbox manager for dynamic malware analysis and reverse engineering. Manages KVM and VMware virtual machines on remote Linux hosts via SSH.

## Features

- **Triple hypervisor support**: KVM/libvirt, VMware Workstation, ARM QEMU standalone
- **Dynamic analysis**: ETW/logman tracing, ProcMon capture, filesystem and registry diffing
- **Static analysis**: Ghidra headless decompilation with LLM bottom-up annotation pipeline
- **Snapshot management**: create, revert, delete — supports both hypervisors
- **Network isolation**: host-only (default), bridged (internet), or air-gapped
- **SSH + telnet automation**: Windows XP through Win11, ARM Linux guests

## Prerequisites

- Linux host with KVM or VMware Workstation
- `just`, `ansible`, `expect`, `remmina` on the control machine
- Python environment (micromamba recommended)

## Setup

```bash
cp config.sh.template config.sh   # Edit with your host details
just setup                         # Install local dependencies (Ansible)
just docs                          # Full CLI reference
```

`config.sh` is gitignored. It holds SSH aliases, storage paths, VM credentials, and malware sample definitions.

## Quick start

```bash
just vm templates                                   # List base VMs with sizes
just vm install <os> <name>                         # Fresh install from ISO (just vm install --list)
just vm launch <base> <name>                        # Create sandbox (host-only, no internet)
just vm launch <base> <name> --bridge               # Create sandbox with internet access
just vm launch <base> <name> --no-network           # Create sandbox without network
just vm connect <name>                              # Open VNC/virt-manager to sandbox
just vm snapshot <name> create                      # Take snapshot (timestamp name)
just vm snapshot <name> create <snap>               # Take snapshot with custom name
just vm snapshot <name> revert <snap>               # Revert to snapshot
just vm pause <name>                                # Pause a running VM
just vm resume <name>                               # Resume a paused VM
just vm stop <name>                                 # Stop and remove sandbox
just vm save <name> [template-name]                 # Save instance as reusable template
just vm destroy <name>                              # Stop, delete, confirm
```

Aliases: `just launch`, `just start`, `just connect`, `just stop`

## Dynamic analysis workflow

```bash
# Capture baseline filesystem + registry state
just disk inspect winxp-dyn mount
just disk snapshot-state winxp-dyn baseline ./artifacts/sample
just disk inspect winxp-dyn umount

# Run the sample (60s timeout)
just da detonate winxp-dyn sample ./artifacts/sample 60

# Capture post-infection state and diff
just disk inspect winxp-dyn mount
just disk snapshot-state winxp-dyn post ./artifacts/sample
just disk inspect winxp-dyn umount

just sa analyze ./artifacts/sample
just vm snapshot winxp-dyn revert clean
```

## ETW tracing

```bash
just da trace start winxp-dyn mytrace              # process + thread + fileio + registry
just da trace start winxp-dyn mytrace 0x12020107   # add disk I/O
# ... run malware ...
just da trace stop winxp-dyn mytrace
just da trace pull winxp-dyn mytrace ./traces/
```

> Note: XP logman captures no FileIO events. Use ProcMon for filesystem visibility. See [`docs/logman-vs-procmon.md`](docs/logman-vs-procmon.md).

## ProcMon capture

```bash
just setup sysinternals winxp-dyn
just da procmon winxp-dyn start my-capture
# ... run malware ...
just da procmon winxp-dyn stop
just vm ftp pull winxp-dyn 'C:\my-capture.PML' ./artifacts/
```

## ARM Linux sandbox (e.g. Mirai)

```bash
just launch debian-12-nocloud-arm64 mirai-sandbox --hostonly
just connect mirai-sandbox                    # serial console (Ctrl-] to detach)
just vm telnet mirai-sandbox 'uname -a'
just vm snapshot mirai-sandbox create pre-infection
```

## LLM annotation pipeline (Ghidra + call graph)

Bottom-up annotation: callee summaries feed into caller prompts for full call-graph context.

```bash
just sa re annotate-deep path/to/unpacked.exe
just sa re annotate-deep path/to/unpacked.exe --context path/to/notes.txt
just sa re ghidra-decompile path/to/unpacked.exe
```

Pipeline: Ghidra export → topological sort → per-function LLM annotation (10 parallel, resumable) → assembled `.c` file.

## Network modes

| Flag            | Bridge  | Internet | Use case               |
|-----------------|---------|----------|------------------------|
| (default)       | virbr1  | No       | Malware analysis       |
| `--bridge`      | virbr0  | Yes      | OS install, downloads  |
| `--no-network`  | —       | No       | Air-gapped             |

## Structure

| Path                          | Purpose                                          |
|-------------------------------|--------------------------------------------------|
| `justfile`                    | CLI dispatcher — all user-facing targets         |
| `config.sh.template`          | Configuration template (copy to `config.sh`)     |
| `scripts/vm.sh`               | Main dispatcher (routes to hypervisor backends)  |
| `scripts/vm-kvm.sh`           | KVM/libvirt operations                           |
| `scripts/vm-vmware.sh`        | VMware Workstation operations                    |
| `scripts/vm-arm.sh`           | ARM QEMU standalone operations                   |
| `scripts/lib.sh`              | Shared functions                                 |
| `scripts/snapshot-state.sh`   | Filesystem + registry state capture              |
| `scripts/trace.sh`            | ETW trace management via telnet                  |
| `scripts/annotate-deep.sh`    | LLM annotation orchestrator                     |
| `scripts/analysis/`           | Python tools: fs-diff, reg-diff, topo-sort       |
| `scripts/ghidra/`             | Ghidra headless export scripts                   |
| `ansible/`                    | Setup playbooks (local deps, KVM host, tools)    |
| `docs/`                       | Reference: logman vs ProcMon, Windows CLI tools  |

## Reference

- [Windows CLI forensics tools](docs/windows-cli-forensics-tools.md)
- [Logman vs ProcMon](docs/logman-vs-procmon.md)
