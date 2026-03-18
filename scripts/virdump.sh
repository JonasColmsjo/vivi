#!/usr/bin/env bash
# virdump.sh — Full VM memory dump via virsh (hypervisor-side)
#
# Usage:
#   virdump.sh <host> <action> <vm-name> [args...]
#
# Dumps entire VM RAM from the host. Invisible to the guest OS.
# The dump file can be analyzed with Volatility 3.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

HOST="${1:?usage: virdump.sh <host> <action> <vm-name> [args...]}"
ACTION="${2:?}"
shift 2

DUMPDIR="/mnt/vm/kvm/mnt/memdump"

case "$ACTION" in
    dump)
        name="${1:?Usage: virdump.sh <host> dump <vm-name> [local-dest]}"
        local_dest="${2:-.}"

        # Verify VM is running
        state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "unknown")
        if [[ "$state" != *"running"* ]]; then
            echo "ERROR: VM '$name' is not running (state: $state)"
            exit 1
        fi

        # Get VM memory size
        mem_kb=$(ssh "$HOST" "virsh dominfo '$name' 2>/dev/null | grep 'Used memory' | awk '{print \$3}'" || echo "?")
        mem_mb=$((${mem_kb:-0} / 1024))
        echo "=== VM Memory Dump ==="
        echo "  VM:     $name"
        echo "  State:  $state"
        echo "  RAM:    ${mem_mb}MB"
        echo ""

        # Create dump directory on host
        ssh "$HOST" "mkdir -p '$DUMPDIR'"

        timestamp=$(date +%Y%m%d-%H%M%S)
        dumpfile="${DUMPDIR}/${name}-${timestamp}.raw"

        echo "Dumping VM memory to $dumpfile..."
        echo "  (VM will be PAUSED during dump, then resumed)"
        echo ""

        # virsh dump with --memory-only: dumps RAM, pauses VM briefly
        ssh "$HOST" "virsh dump '$name' '$dumpfile' --memory-only" 2>&1

        # Verify
        size=$(ssh "$HOST" "stat -c%s '$dumpfile' 2>/dev/null" || echo "0")
        size_mb=$((size / 1024 / 1024))
        echo ""
        echo "Dump complete: ${size_mb}MB"

        # Pull to local if requested
        if [ "$local_dest" != "--no-pull" ]; then
            mkdir -p "$local_dest"
            local_file="${local_dest}/${name}-${timestamp}.raw"
            echo "Pulling to $local_file..."
            scp "$HOST:$dumpfile" "$local_file"
            echo "Saved: $local_file (${size_mb}MB)"
        else
            echo "Dump on host: $dumpfile"
            echo "Pull with: scp $HOST:$dumpfile ."
        fi

        echo ""
        echo "Analyze with Volatility 3:"
        echo "  vol -f ${name}-${timestamp}.raw windows.pslist"
        echo "  vol -f ${name}-${timestamp}.raw windows.malfind"
        echo "  vol -f ${name}-${timestamp}.raw windows.dumpfiles --pid <PID>"
        ;;

    list)
        echo "=== Memory dumps on $HOST ==="
        ssh "$HOST" "ls -lhS '$DUMPDIR'/*.raw 2>/dev/null" || echo "  (none)"
        ;;

    analyze)
        dumpfile="${1:?Usage: virdump.sh <host> analyze <dump-file> <plugin> [args...]}"
        plugin="${2:?Usage: virdump.sh <host> analyze <dump-file> <plugin> [args...]}"
        shift 2
        extra_args="$*"

        # Check if dump is local or on host
        if [ -f "$dumpfile" ]; then
            # Local file — run volatility locally
            if command -v vol &>/dev/null; then
                vol -f "$dumpfile" "$plugin" $extra_args
            elif command -v vol3 &>/dev/null; then
                vol3 -f "$dumpfile" "$plugin" $extra_args
            else
                echo "ERROR: Volatility 3 not found locally."
                echo "Install: pip install volatility3"
                exit 1
            fi
        else
            # Try on host
            remote_path="$dumpfile"
            # If just a filename, prepend dump dir
            if [[ "$dumpfile" != /* ]]; then
                remote_path="${DUMPDIR}/${dumpfile}"
            fi
            if ! ssh "$HOST" "test -f '$remote_path'" 2>/dev/null; then
                echo "ERROR: Dump file not found: $dumpfile"
                echo "  Checked local: $dumpfile"
                echo "  Checked host:  $remote_path"
                exit 1
            fi
            echo "Running Volatility on $HOST..."
            ssh "$HOST" "/home/me/forensics-venv/bin/vol -f '$remote_path' $plugin $extra_args" 2>&1 || {
                echo ""
                echo "If Volatility is not installed on host, install with:"
                echo "  ssh $HOST '/home/me/forensics-venv/bin/pip install volatility3'"
                exit 1
            }
        fi
        ;;

    clean)
        echo "=== Cleaning memory dumps on $HOST ==="
        ssh "$HOST" "ls -lhS '$DUMPDIR'/*.raw 2>/dev/null" || { echo "  (none)"; exit 0; }
        echo ""
        read -rp "Delete all dumps? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            ssh "$HOST" "rm -f '$DUMPDIR'/*.raw"
            echo "Deleted."
        fi
        ;;

    *)
        echo "Usage: virdump.sh <host> dump|list|analyze|clean <vm-name> [args...]"
        echo ""
        echo "Actions:"
        echo "  dump <vm> [local-dest]                  Dump full VM RAM (virsh dump)"
        echo "  dump <vm> --no-pull                     Dump but keep on host only"
        echo "  list                                    List dumps on host"
        echo "  analyze <file> <plugin> [args]          Run Volatility 3 on dump"
        echo "  clean                                   Delete dumps from host"
        echo ""
        echo "Volatility plugins:"
        echo "  windows.pslist                          List processes"
        echo "  windows.malfind                         Detect injected/unpacked code"
        echo "  windows.dumpfiles --pid <PID>           Extract files from process memory"
        echo "  windows.memmap --pid <PID> --dump       Dump process memory pages"
        echo "  windows.handles --pid <PID>             List open handles"
        exit 1
        ;;
esac
