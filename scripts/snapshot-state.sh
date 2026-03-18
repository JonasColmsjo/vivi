#!/usr/bin/env bash
# snapshot-state.sh — Capture filesystem listing + registry hive dumps from a mounted VM
#
# Usage: snapshot-state.sh <host> <vm-name> <phase> <outdir>
#   phase: baseline | post (or any label)
#   outdir: directory where output files are written
#
# Requires: VM disk mounted via `just inspect <vm> mount`
# Output:
#   <outdir>/<phase>-files.txt          Sorted file listing
#   <outdir>/<phase>-SOFTWARE.json      Registry hive dump (SOFTWARE)
#   <outdir>/<phase>-SYSTEM.json        Registry hive dump (SYSTEM)
#   <outdir>/<phase>-NTUSER.json        Registry hive dump (NTUSER)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

HOST_ARG="${1:?usage: snapshot-state.sh <host> <vm-name> <phase> <outdir>}"
VM_NAME="${2:?}"
PHASE="${3:?}"
OUTDIR="${4:?}"

setup_host "$HOST_ARG"
mkdir -p "$OUTDIR"

mntdir="$KVMDIR/mnt/${VM_NAME}-live"

echo "=== Snapshot state: $VM_NAME / $PHASE ==="

if ! ssh "$HOST_ROOT_VAL" "mountpoint -q '$mntdir'" 2>/dev/null; then
    echo "VM disk not mounted. Run: just inspect $VM_NAME mount"
    exit 1
fi

# 1. Filesystem listing
echo "Capturing file listing..."
ssh "$HOST" "find '$mntdir' -type f 2>/dev/null | sort" > "$OUTDIR/${PHASE}-files.txt"
count=$(wc -l < "$OUTDIR/${PHASE}-files.txt")
echo "  Saved $count files to $OUTDIR/${PHASE}-files.txt"

# 2. Registry hive dumps
for hive in SOFTWARE SYSTEM NTUSER; do
    echo "Dumping $hive registry..."
    hivefile=$(find_hive "$hive" "$mntdir")

    if [ -z "$hivefile" ]; then
        echo "  WARNING: $hive hive not found at expected path"
        continue
    fi

    ssh "$HOST" "
        tmpfile=\$(mktemp /tmp/reg_${hive}_XXXXXX)
        cp '$hivefile' \"\$tmpfile\"
        /home/me/forensics-venv/bin/registry-dump \"\$tmpfile\" 2>/dev/null
        rm -f \"\$tmpfile\"
    " > "$OUTDIR/${PHASE}-${hive}.json" 2>/dev/null
    lines=$(wc -l < "$OUTDIR/${PHASE}-${hive}.json")
    echo "  Saved $lines entries to $OUTDIR/${PHASE}-${hive}.json"
done

echo "Done. Snapshot saved to $OUTDIR/"
