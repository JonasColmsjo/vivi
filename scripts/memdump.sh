#!/usr/bin/env bash
# memdump.sh — Dump process memory from Windows VM via ProcDump (telnet)
#
# Usage:
#   memdump.sh <host> <vmip> <user> <pass> list
#   memdump.sh <host> <vmip> <user> <pass> dump <pid-or-name> [output-name] [procdump_exe]
#   memdump.sh <host> <vmip> <user> <pass> run <cmd> [delay] [output-name] [procdump_exe]
#
# ProcDump is a CLI tool — works directly from telnet, no PsExec needed.
#
# The "run" action launches a command and dumps it in a single telnet session,
# which is critical for short-lived processes (e.g. malware that exits in <40s).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

HOST="${1:?usage: memdump.sh <host> <vmip> <user> <pass> list|dump|run [args...]}"
VMIP="${2:?}"
VMUSER="${3:?}"
VMPASS="${4:?}"
ACTION="${5:?}"
shift 5

PROCDUMP_DEFAULT='C:\local\Sysinternals\procdump.exe'

# Run a command on the VM via telnet
vm_exec() {
    local cmd="$1"
    local timeout="${2:-10}"
    "$SCRIPT_DIR/vm-exec.exp" "$HOST" "$VMIP" "$VMUSER" "$VMPASS" "$cmd" "$timeout" 2>&1
}

# Run multiple commands in a single telnet session via raw telnet.
# Each command gets a configurable wait time.
# Usage: telnet_session "cmd1" wait1 "cmd2" wait2 ...
telnet_session() {
    local script=""
    script+="sleep 3; printf '${VMUSER}\r\n'; sleep 3; printf '${VMPASS}\r\n'; sleep 3; "
    while [ $# -ge 2 ]; do
        local cmd="$1"
        local wait="$2"
        shift 2
        script+="printf '${cmd}\r\n'; sleep ${wait}; "
    done
    script+="printf 'exit\r\n'; sleep 1"
    ssh "$HOST" "{ $script } | telnet '$VMIP' 23 2>&1 | cat" 2>&1
}

case "$ACTION" in
    list)
        echo "=== Running processes on $VMIP ==="
        output=$(vm_exec "tasklist" 15)
        # Show all processes, highlight non-system ones
        echo "$output" | grep -P '^\S+\.exe\s+\d+' | while IFS= read -r line; do
            name=$(echo "$line" | awk '{print tolower($1)}')
            case "$name" in
                system|smss.exe|csrss.exe|winlogon.exe|services.exe|lsass.exe|\
                svchost.exe|spoolsv.exe|alg.exe|wdfmgr.exe|tlntsvr.exe|\
                wmiprvse.exe|explorer.exe|ctfmon.exe)
                    echo "  $line"
                    ;;
                *)
                    echo "  $line  <---"
                    ;;
            esac
        done
        ;;

    dump)
        target="${1:?Usage: memdump.sh ... dump <pid-or-name> [output-name] [procdump_exe]}"
        outname="${2:-memdump}"
        procdump="${3:-$PROCDUMP_DEFAULT}"

        # Resolve process name to PID if not numeric
        if [[ "$target" =~ ^[0-9]+$ ]]; then
            pid="$target"
            echo "Dumping PID $pid..."
        else
            echo "Looking up PID for '$target'..."
            output=$(vm_exec "tasklist /fi \"imagename eq $target\"" 10)
            pid=$(echo "$output" | grep -iP "${target}\s+\d+" | head -1 | awk '{print $2}')
            if [ -z "$pid" ]; then
                echo "ERROR: Process '$target' not found."
                echo "Running processes:"
                vm_exec "tasklist" 10 | grep -P '^\S+\.exe\s+\d+' || true
                exit 1
            fi
            pname=$(echo "$output" | grep -iP "${target}\s+\d+" | head -1 | awk '{print $1}')
            echo "Found: $pname (PID $pid)"
        fi

        dmpfile="C:\\${outname}-${pid}.dmp"
        echo "Dumping to $dmpfile..."
        echo "  Command: $procdump -accepteula -ma $pid $dmpfile"

        # Run procdump — -ma = full memory dump
        output=$(vm_exec "$procdump -accepteula -ma $pid C:\\${outname}-${pid}.dmp" 60)
        echo "$output" | grep -v "^$" | tail -10

        # Verify dump was created
        echo ""
        echo "=== Dump files ==="
        vm_exec "dir C:\\${outname}*.dmp" 10 | grep -iP "\d+.*\.dmp" || echo "  (no .dmp files found — dump may have failed)"

        echo ""
        echo "Pull with: just ftp pull <vm> 'C:\\${outname}-${pid}.dmp' ./"
        ;;

    run)
        # Launch a command and dump it in a single telnet session.
        # Critical for short-lived processes like malware.
        runcmd="${1:?Usage: memdump.sh ... run <cmd> [delay] [output-name] [procdump_exe]}"
        delay="${2:-8}"
        outname="${3:-memdump}"
        procdump="${4:-$PROCDUMP_DEFAULT}"

        # Derive process name from the command for procdump target
        # Extract filename from path: C:\path\to\foo.exe -> foo.exe
        procname=$(echo "$runcmd" | grep -oP '[^\\/]+\.exe' | tail -1)
        if [ -z "$procname" ]; then
            echo "ERROR: Cannot determine .exe name from command: $runcmd"
            echo "The command must contain a path ending in .exe"
            exit 1
        fi

        echo "=== Launch + Dump ==="
        echo "  Command:  $runcmd"
        echo "  Process:  $procname"
        echo "  Delay:    ${delay}s (after launch, before dump)"
        echo "  Output:   C:\\${outname}.dmp"
        echo "  ProcDump: $procdump"
        echo ""

        # Escape backslashes for printf in the telnet session
        # The command goes through: bash -> ssh -> bash -> printf -> telnet
        # We need double-escaped backslashes for the ssh layer
        runcmd_esc=$(echo "$runcmd" | sed 's/\\/\\\\\\\\/g')
        procdump_esc=$(echo "$procdump" | sed 's/\\/\\\\\\\\/g')

        echo "Launching $procname and dumping after ${delay}s..."

        # Single telnet session:
        # 1. "start <cmd>" — launches in background so telnet stays responsive
        # 2. wait <delay> seconds — let UPX unpack, malware initialize
        # 3. procdump -ma <name> — dump by process name
        # 4. dir — verify dump exists
        output=$(telnet_session \
            "start ${runcmd_esc}" "$delay" \
            "${procdump_esc} -accepteula -ma ${procname} C:\\\\${outname}" 20 \
            "dir C:\\\\${outname}*" 4)

        # Show relevant output (skip telnet login noise)
        echo "$output" | grep -v "^Trying\|^Connected\|^Escape\|^Welcome\|^login:\|^password:\|^\*===" | grep -v "^$" | tail -20

        # Check if dump was created
        if echo "$output" | grep -qi "dump.*complete\|\.dmp"; then
            echo ""
            echo "=== Success ==="
            # Extract the actual dump filename from procdump output
            dmpname=$(echo "$output" | grep -oP 'C:\\[^\s]+\.dmp' | head -1)
            if [ -n "$dmpname" ]; then
                echo "Dump file: $dmpname"
                echo "Pull with: just ftp pull <vm> '$dmpname' ./"
            else
                echo "Check dump files: just exec <vm> 'dir C:\\${outname}*'"
            fi
        else
            echo ""
            echo "=== Dump may have failed ==="
            echo "Possible causes:"
            echo "  - Process exited before dump (increase delay? current: ${delay}s)"
            echo "  - Process name mismatch (expected: $procname)"
            echo "Check: just memdump <vm> list"
        fi
        ;;

    *)
        echo "Usage: memdump.sh <host> <vmip> <user> <pass> list|dump|run [args...]"
        echo ""
        echo "Actions:"
        echo "  list                                        List running processes"
        echo "  dump <pid-or-name> [out] [exe]              Dump already-running process"
        echo "  run  <cmd> [delay=8] [out] [exe]            Launch + dump in one session"
        echo ""
        echo "Examples:"
        echo "  memdump.sh host ip user pass list"
        echo "  memdump.sh host ip user pass dump sample.exe sample-dump"
        echo "  memdump.sh host ip user pass run 'C:\\malware\\sample.exe' 8 sample-dump"
        exit 1
        ;;
esac
