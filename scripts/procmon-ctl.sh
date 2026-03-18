#!/usr/bin/env bash
# procmon-ctl.sh — Start/stop ProcMon on Windows VM via PsExec
#
# ProcMon is a GUI app that won't capture events from a telnet session.
# We use PsExec -i to launch it in the interactive desktop session.
#
# Usage:
#   procmon-ctl.sh <host> <vmip> <user> <pass> start <name> [procmon_exe] [psexec_exe]
#   procmon-ctl.sh <host> <vmip> <user> <pass> stop [procmon_exe] [psexec_exe]
#   procmon-ctl.sh <host> <vmip> <user> <pass> status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

HOST="${1:?usage: procmon-ctl.sh <host> <vmip> <user> <pass> start|stop|status [name] [procmon_exe] [psexec_exe]}"
VMIP="${2:?}"
VMUSER="${3:?}"
VMPASS="${4:?}"
ACTION="${5:?}"
NAME="${6:-procmon}"
PROCMON="${7:-C:\\WINDOWS\\system32\\svcmon.exe}"
PSEXEC="${8:-C:\\local\\Sysinternals\\PsExec.exe}"

TASKLIST='C:\WINDOWS\system32\tasklist.exe'

# Run a command on the VM via telnet, capture output
vm_exec() {
    local cmd="$1"
    local timeout="${2:-10}"
    "$SCRIPT_DIR/vm-exec.exp" "$HOST" "$VMIP" "$VMUSER" "$VMPASS" "$cmd" "$timeout" 2>&1
}

# Check if ProcMon is running (matches tasklist output line with PID)
procmon_running() {
    vm_exec "$TASKLIST /fi \"imagename eq svcmon.exe\"" 10 | grep -qP "svcmon\.exe\s+\d+"
}

case "$ACTION" in
    start)
        echo "=== Starting ProcMon (backing file: C:\\${NAME}.PML) ==="

        # Check if already running
        if procmon_running; then
            echo "ProcMon is already running. Stop it first."
            exit 1
        fi

        # Delete old PML if exists
        vm_exec "del C:\\${NAME}.PML 2>nul" 10 >/dev/null || true

        # Launch ProcMon in interactive session via PsExec
        vm_exec "$PSEXEC -i -d $PROCMON /AcceptEula /Quiet /Minimized /BackingFile C:\\${NAME}" 15
        sleep 8

        # Verify
        if procmon_running; then
            echo "ProcMon is running and capturing events."
        else
            echo "WARNING: Could not verify ProcMon status (telnet check failed)."
            echo "PsExec reported it started — continuing anyway."
            echo "If capture is empty, check VM desktop for EULA dialogs."
        fi
        ;;

    stop)
        echo "=== Stopping ProcMon (clean /Terminate via PsExec) ==="

        # Check if running
        if ! procmon_running; then
            echo "ProcMon is not running."
            exit 0
        fi

        # Send /Terminate via PsExec in interactive session
        vm_exec "$PSEXEC -i -d $PROCMON /Terminate" 15
        sleep 5

        # Verify stopped
        if procmon_running; then
            echo "WARNING: ProcMon still running after /Terminate. Retrying..."
            sleep 5
            if procmon_running; then
                echo "ERROR: ProcMon still running. Stop from VNC or use: taskkill /f /im svcmon.exe"
                exit 1
            fi
        fi

        echo "ProcMon terminated cleanly."
        ;;

    status)
        if procmon_running; then
            echo "ProcMon is RUNNING"
            vm_exec "$TASKLIST /fi \"imagename eq svcmon.exe\"" 10 | grep -P "svcmon\.exe\s+\d+" || true
        else
            echo "ProcMon is NOT running"
        fi
        # Show PML files
        echo ""
        echo "PML files on C:\\:"
        vm_exec "dir C:\\*.PML" 10 | grep -iP "\d+.*\.PML" || echo "  (none)"
        ;;

    *)
        echo "Usage: procmon-ctl.sh <host> <vmip> <user> <pass> start|stop|status [name] [procmon_exe] [psexec_exe]"
        exit 1
        ;;
esac
