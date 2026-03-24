#!/usr/bin/env bash
# trace.sh — Logman ETW trace management on Windows VMs via telnet
# Usage: trace.sh <action> [args...]
# Called by justfile. Expects lib.sh already sourced and setup_host called.
#
# On XP, the kernel trace provider uses the "NT Kernel Logger" session
# (ID 65535). Symbolic flags like (process,fileio) fail via telnet, so
# we pass hex flags to the provider GUID instead.
#
# Hex flag reference (EVENT_TRACE_FLAG_*):
#   process  = 0x00000001   thread   = 0x00000002   img      = 0x00000004
#   disk     = 0x00000100   fileio   = 0x02000000   registry = 0x00020000
#   net      = 0x00010000
# Default: process+thread+img+fileio+registry = 0x12020007

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

action="${1:?usage: trace.sh <action> [args...]}"
shift

KERNEL_GUID="{9e814aad-3204-11d2-9a82-006008a86939}"
DEFAULT_FLAGS="0x12020007"   # process+thread+img+fileio+registry

# --- Telnet command runner ---
# Runs a command on the XP VM via telnet and returns output.
# Usage: telnet_cmd <ip> <command> [wait_secs]
telnet_cmd() {
    local ip="$1"
    local cmd="$2"
    local wait="${3:-4}"
    ssh "$HOST" "{ sleep 3; printf 'me\r\n'; sleep 3; printf '${VM_PASS}\r\n'; sleep 3; printf '${cmd}\r\n'; sleep ${wait}; printf 'exit\r\n'; sleep 1; } | telnet '$ip' 23 2>&1 | cat" 2>&1
}

# Run multiple commands in a single telnet session
# Usage: telnet_cmds <ip> <cmd1> <cmd2> ... (each cmd gets 4s)
telnet_cmds() {
    local ip="$1"; shift
    local script=""
    script+="sleep 3; printf 'me\r\n'; sleep 3; printf '${VM_PASS}\r\n'; sleep 3; "
    for cmd in "$@"; do
        script+="printf '${cmd}\r\n'; sleep 4; "
    done
    script+="printf 'exit\r\n'; sleep 1"
    ssh "$HOST" "{ $script } | telnet '$ip' 23 2>&1 | cat" 2>&1
}

# Filter telnet noise from output
filter_telnet() {
    grep -v "^Trying\|^Connected\|^Escape\|^Welcome\|^login:\|^password:\|^\*===" | grep -v "^$"
}

# Get VM IP
get_vm_ip() {
    local name="$1"
    local ip
    ip=$(kvm_vm_ip "$name")
    if [ -z "$ip" ]; then
        echo "Error: Cannot determine IP for VM '$name'" >&2
        echo "Check with: ssh $HOST 'ip neigh show | grep 192.168.100'" >&2
        exit 1
    fi
    echo "$ip"
}

case "$action" in

start)
    # Start the NT Kernel Logger ETW trace
    # Usage: trace.sh start <vm-name> [trace-name] [hex-flags]
    name="${1:?Usage: trace.sh start <vm-name> [trace-name] [hex-flags]}"
    trace="${2:-maltrace}"
    flags="${3:-$DEFAULT_FLAGS}"

    ip=$(get_vm_ip "$name")
    echo "Starting NT Kernel Logger on '$name' ($ip)..."
    echo "  Flags:  $flags"
    echo "  Output: C:\\${trace}.etl"

    # NT Kernel Logger is a special session name that enables the kernel provider.
    # Using the GUID with hex flags avoids the parenthesized flag syntax
    # which breaks over telnet on XP.
    output=$(telnet_cmd "$ip" \
        "logman create trace \"NT Kernel Logger\" -p ${KERNEL_GUID} ${flags} 0xff -o C:\\\\${trace}.etl -ets" 6)
    echo "$output" | filter_telnet | tail -5

    echo ""
    echo "Trace running. Stop with: just da-trace stop $name $trace"
    ;;

stop)
    # Stop the NT Kernel Logger and convert ETL to CSV
    # Usage: trace.sh stop <vm-name> [trace-name]
    name="${1:?Usage: trace.sh stop <vm-name> [trace-name]}"
    trace="${2:-maltrace}"

    ip=$(get_vm_ip "$name")
    echo "Stopping NT Kernel Logger on '$name' ($ip)..."

    output=$(telnet_cmd "$ip" "logman stop \"NT Kernel Logger\" -ets" 4)
    echo "$output" | filter_telnet | tail -3

    echo ""
    echo "Converting ETL to CSV..."
    # XP tracerpt: no -of flag, uses -o for CSV output
    output=$(telnet_cmd "$ip" "tracerpt C:\\\\${trace}.etl -o C:\\\\${trace}.csv -y" 15)
    echo "$output" | filter_telnet | tail -5

    echo ""
    echo "Files on VM:"
    output=$(telnet_cmd "$ip" "dir C:\\\\${trace}.*" 4)
    echo "$output" | filter_telnet | grep -E "\.etl|\.csv|Directory" || true

    echo ""
    echo "Pull with: just da-trace pull $name $trace"
    ;;

status)
    # Show active logman traces
    # Usage: trace.sh status <vm-name>
    name="${1:?Usage: trace.sh status <vm-name>}"

    ip=$(get_vm_ip "$name")
    echo "Active traces on '$name' ($ip):"
    output=$(telnet_cmd "$ip" "logman query -ets" 6)
    echo "$output" | filter_telnet | tail -20
    ;;

pull)
    # Pull trace files from VM via TFTP (<10MB) or remind to use FTP
    # Usage: trace.sh pull <vm-name> [trace-name] [local-dest]
    name="${1:?Usage: trace.sh pull <vm-name> [trace-name] [local-dest]}"
    trace="${2:-maltrace}"
    local_dest="${3:-.}"

    ip=$(get_vm_ip "$name")

    echo "Checking trace files on VM..."
    output=$(telnet_cmd "$ip" "dir C:\\\\${trace}.*" 4)
    echo "$output" | filter_telnet | grep -E "\.etl|\.csv|Directory" || true

    echo ""
    echo "Uploading via TFTP..."
    for ext in csv etl; do
        output=$(telnet_cmd "$ip" "tftp -i 192.168.100.1 PUT C:\\\\${trace}.${ext}" 15)
        result=$(echo "$output" | grep -i "transfer\|timed out\|error" || echo "(no status)")
        echo "  ${trace}.${ext}: $result"
    done

    # Copy from host to local
    tftp_dir="/mnt/vm/kvm/mnt/tftp"
    echo ""
    for ext in csv etl; do
        src="${tftp_dir}/${trace}.${ext}"
        if ssh "$HOST" "test -f '$src'" 2>/dev/null; then
            dest="${local_dest}/${trace}.${ext}"
            echo "Pulling ${trace}.${ext} -> $dest"
            scp "$HOST:${src}" "$dest"
        else
            echo "Warning: ${trace}.${ext} not on host. Too large for TFTP? Use: just ftp pull $name 'C:\\${trace}.${ext}'"
        fi
    done

    # Convert FILETIME timestamps to human-readable
    csv_file="${local_dest}/${trace}.csv"
    if [ -f "$csv_file" ]; then
        readable="${local_dest}/${trace}-readable.csv"
        echo "Converting timestamps -> $readable"
        python3 -c "
import datetime
for line in open('${csv_file}'):
    parts = line.split(',')
    if len(parts) > 3:
        try:
            t = int(parts[3].strip())
            dt = datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=t // 10)
            print(dt.strftime('%H:%M:%S.%f') + ',' + line.rstrip())
        except ValueError:
            print('Time,' + line.rstrip())
    else:
        print(line.rstrip())
" > "$readable"
        echo "Done. $(wc -l < "$readable") lines."
    fi
    ;;

*)
    echo "Usage: trace.sh <action> <vm-name> [args...]"
    echo ""
    echo "Actions:"
    echo "  start <vm> [name] [hex-flags]  Start NT Kernel Logger ETW trace"
    echo "  stop <vm> [name]               Stop trace, convert ETL to CSV"
    echo "  status <vm>                    Show active ETW sessions"
    echo "  pull <vm> [name] [dest]        Pull trace files locally (TFTP)"
    echo ""
    echo "Default hex flags: $DEFAULT_FLAGS (process+thread+img+fileio+registry)"
    echo ""
    echo "Hex flag reference:"
    echo "  process=0x1  thread=0x2  img=0x4  disk=0x100"
    echo "  net=0x10000  registry=0x20000  fileio=0x2000000"
    echo ""
    echo "Example: just da-trace start winxp-dyn mytrace 0x12020107"
    echo "         (adds disk I/O to default flags)"
    exit 1
    ;;
esac
