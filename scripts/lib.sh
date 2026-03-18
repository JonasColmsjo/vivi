#!/usr/bin/env bash
# lib.sh — Shared functions for VM management scripts
# Source this file; do not execute directly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../config.sh
if [ ! -f "$REPO_DIR/config.sh" ]; then
    echo "Error: config.sh not found. Copy the template and edit it:" >&2
    echo "  cp config.sh.template config.sh" >&2
    exit 1
fi
source "$REPO_DIR/config.sh"

# --- Host setup ---

# Resolve host-specific variables into simple globals.
# Usage: setup_host "tcentre1"
setup_host() {
    local h="${1:?usage: setup_host <host>}"
    export HOST="$h"
    export HOST_IP_VAL="${HOST_IP[$h]}"
    export HOST_ROOT_VAL="${HOST_ROOT[$h]}"
    export VMBASE_VAL="${VMBASE[$h]}"
    export EXT_DEV_VAL="${EXT_DEV[$h]}"
}

# --- Hypervisor detection ---

# Detect active hypervisor on HOST. Prints "kvm", "vmware", or "none".
detect_hypervisor() {
    ssh "$HOST" "
      vmw=\$(vmrun list 2>/dev/null | head -1 | grep -oP '[0-9]+' || echo 0)
      kvm=\$(virsh list --name 2>/dev/null | grep -c . || true)
      if [ \"\$vmw\" -gt 0 ]; then echo vmware
      elif [ \"\$kvm\" -gt 0 ]; then echo kvm
      elif lsmod | grep -qw vmmon; then echo vmware
      elif lsmod | grep -qw kvm_intel; then echo kvm
      else echo none; fi
    "
}

# Detect hypervisor and fail if none active. Prints "kvm" or "vmware".
require_hypervisor() {
    local hv
    hv=$(detect_hypervisor)
    if [ "$hv" = "none" ]; then
        echo "No hypervisor active. Run: just hypervisor kvm|vmware" >&2
        exit 1
    fi
    echo "$hv"
}

# --- External disk ---

# Ensure external disk is mounted on HOST.
require_ext_mount() {
    if ! ssh "$HOST" "mountpoint -q /mnt/ext" 2>/dev/null; then
        echo "External disk not mounted. Mounting..."
        ssh "$HOST_ROOT_VAL" "mount $EXT_DEV_VAL /mnt/ext"
    fi
}

# --- VNC port allocation ---

# Find next available VNC port on HOST (starting at 5901).
next_vnc_port() {
    ssh "$HOST" "
        used=\$(grep -rh 'RemoteDisplay.vnc.port' '$SBXDIR'/*/*.vmx 2>/dev/null | grep -oP '[0-9]+' | sort -n)
        p=5901
        while echo \"\$used\" | grep -qx \"\$p\" 2>/dev/null; do p=\$((p+1)); done
        echo \$p
    "
}

# --- VMX lookup ---

# Find a VMX file in SBXDIR by sandbox name. Prints path or empty string.
find_sandbox_vmx() {
    local name="$1"
    ssh "$HOST" "find '$SBXDIR' -maxdepth 2 \( -name '*-${name}.vmx' -o -name '${name}.vmx' \) 2>/dev/null | head -1"
}

# Find a base VMX in VMBASE by template name. Prints path or empty string.
find_base_vmx() {
    local base="$1"
    ssh "$HOST" "
        for d in '$VMBASE_VAL'/'${base}' '$VMBASE_VAL'/'${base}'.vmwarevm; do
            if [ -d \"\$d\" ]; then
                find \"\$d\" -maxdepth 1 -name '*.vmx' 2>/dev/null | head -1
                break
            fi
        done
    "
}

# --- NBD helpers (for inspect) ---

nbd_connected() {
    local nbd_dev="${1:-/dev/nbd0}"
    ssh "$HOST_ROOT_VAL" "test -b ${nbd_dev}p1" 2>/dev/null
}

nbd_connect() {
    local img="$1"
    local nbd_dev="${2:-/dev/nbd0}"
    if nbd_connected "$nbd_dev"; then
        echo "NBD already connected at $nbd_dev"
        return 0
    fi
    echo "Connecting $img via qemu-nbd (snapshot, read-only)..."
    ssh "$HOST_ROOT_VAL" "modprobe nbd max_part=8 2>/dev/null; qemu-nbd --connect=$nbd_dev --read-only --snapshot '$img'"
    for i in 1 2 3 4 5; do
        if ssh "$HOST_ROOT_VAL" "test -b ${nbd_dev}p1" 2>/dev/null; then
            echo "NBD connected: ${nbd_dev}p1"
            return 0
        fi
        sleep 1
    done
    echo "Warning: ${nbd_dev}p1 not found — trying partprobe..."
    ssh "$HOST_ROOT_VAL" "partprobe $nbd_dev 2>/dev/null" || true
    sleep 1
    if ! ssh "$HOST_ROOT_VAL" "test -b ${nbd_dev}p1" 2>/dev/null; then
        echo "Error: No partition found. Check with: ssh $HOST_ROOT_VAL fdisk -l $nbd_dev"
        exit 1
    fi
}

nbd_disconnect() {
    local mntdir="$1"
    local nbd_dev="${2:-/dev/nbd0}"
    if ssh "$HOST_ROOT_VAL" "mountpoint -q '$mntdir'" 2>/dev/null; then
        echo "Unmounting $mntdir..."
        ssh "$HOST_ROOT_VAL" "umount '$mntdir'"
    fi
    if nbd_connected "$nbd_dev" || ssh "$HOST_ROOT_VAL" "test -b $nbd_dev" 2>/dev/null; then
        echo "Disconnecting NBD..."
        ssh "$HOST_ROOT_VAL" "qemu-nbd --disconnect $nbd_dev"
    fi
    echo "Disconnected."
}

# --- Registry hive paths ---

# XP-style paths
declare -A HIVE_PATHS_XP
HIVE_PATHS_XP=(
    [SAM]="WINDOWS/system32/config/SAM"
    [SYSTEM]="WINDOWS/system32/config/system"
    [SOFTWARE]="WINDOWS/system32/config/software"
    [SECURITY]="WINDOWS/system32/config/SECURITY"
    [NTUSER]="Documents and Settings/${VM_USER}/NTUSER.DAT"
)

# Vista+ paths
declare -A HIVE_PATHS_VISTA
HIVE_PATHS_VISTA=(
    [SAM]="Windows/System32/config/SAM"
    [SYSTEM]="Windows/System32/config/SYSTEM"
    [SOFTWARE]="Windows/System32/config/SOFTWARE"
    [SECURITY]="Windows/System32/config/SECURITY"
    [NTUSER]="Users/${VM_USER}/NTUSER.DAT"
)

# Find hive file trying both XP and Vista+ paths. Prints full path or empty.
find_hive() {
    local name="$1"
    local mntdir="$2"
    local path1="${mntdir}/${HIVE_PATHS_XP[$name]}"
    local path2="${mntdir}/${HIVE_PATHS_VISTA[$name]}"
    if ssh "$HOST" "test -f '$path1'" 2>/dev/null; then
        echo "$path1"
    elif ssh "$HOST" "test -f '$path2'" 2>/dev/null; then
        echo "$path2"
    else
        echo ""
    fi
}

# Parse a single registry hive with regipy. Args: hive_name mntdir
parse_hive() {
    local name="$1"
    local mntdir="$2"
    local full_path
    full_path=$(find_hive "$name" "$mntdir")

    echo "=== $name ==="
    if [ -z "$full_path" ]; then
        echo "  (not found — tried XP and Vista+ paths)"
        echo ""
        return
    fi
    echo "  Path: $full_path"

    ssh "$HOST" "
        tmpfile=\$(mktemp /tmp/reg_${name}_XXXXXX)
        cp '$full_path' \"\$tmpfile\"
        /home/me/forensics-venv/bin/registry-dump \"\$tmpfile\" 2>/dev/null | head -200
        rm -f \"\$tmpfile\"
    " 2>/dev/null || echo "  (regipy parse failed — is regipy installed?)"
    echo ""
}

# Parse one or all hives. Args: hive_name_or_all mntdir
parse_hives() {
    local hive="$1"
    local mntdir="$2"
    if [ "$hive" = "all" ]; then
        for h in SAM SYSTEM SOFTWARE SECURITY NTUSER; do
            parse_hive "$h" "$mntdir"
        done
    else
        local hive_upper
        hive_upper=$(echo "$hive" | tr '[:lower:]' '[:upper:]')
        if [ -z "${HIVE_PATHS_XP[$hive_upper]+x}" ]; then
            echo "Unknown hive: $hive"
            echo "Available: SAM, SYSTEM, SOFTWARE, SECURITY, NTUSER, all"
            exit 1
        fi
        parse_hive "$hive_upper" "$mntdir"
    fi
}

# --- ARM QEMU helpers ---

# Check if an instance is an ARM VM (has UEFI vars file)
is_arm_instance() {
    local name="$1"
    ssh "$HOST" "test -f '${KVMDIR}/instances/${name}-vars.fd'" 2>/dev/null
}

# Check if ARM QEMU process is running for an instance
arm_is_running() {
    local name="$1"
    local pidfile="${KVMDIR}/instances/${name}.pid"
    ssh "$HOST" "test -f '$pidfile' && kill -0 \$(cat '$pidfile') 2>/dev/null"
}

# Send command to QEMU monitor socket
arm_monitor_cmd() {
    local name="$1"
    local cmd="$2"
    local sock="${KVMDIR}/instances/${name}-monitor.sock"
    ssh "$HOST" "echo '$cmd' | socat - UNIX-CONNECT:'$sock'"
}

# Execute command on ARM VM via serial socket and capture output
arm_serial_exec() {
    local name="$1"
    local cmd="$2"
    local timeout="${3:-10}"
    local sock="${KVMDIR}/instances/${name}-serial.sock"
    # Write a temporary Python script on the remote host to avoid quoting hell
    ssh "$HOST" "cat > /tmp/vivi-serial-exec.py << 'PYEOF'
import socket, time, re, sys

sock_path = sys.argv[1]
cmd = sys.argv[2]
timeout = int(sys.argv[3])

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
s.settimeout(2)

def recv_all(deadline):
    out = b''
    while time.time() < deadline:
        try:
            chunk = s.recv(4096)
            if not chunk: break
            out += chunk
        except socket.timeout:
            break
    return out.decode(errors='replace')

def clean(text):
    # Strip ANSI escapes, bracketed paste, and carriage returns
    text = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', text)
    text = re.sub(r'\[\?[0-9]+[a-z]', '', text)
    text = text.replace('\r', '')
    return text

# Break out of any stale state and ensure we're at a shell prompt
s.sendall(b'\x03\n')  # Ctrl-C + Enter
time.sleep(2)
prompt = recv_all(time.time() + 2)

if 'login:' in prompt or 'Password:' in prompt:
    # At login prompt - log in as root (nocloud image: root, no password)
    if 'Password:' in prompt:
        s.sendall(b'\x03\n')  # Cancel current login
        time.sleep(1)
        recv_all(time.time() + 2)
    s.sendall(b'root\n')
    time.sleep(3)
    recv_all(time.time() + 2)

# Now at shell - send command with markers on separate lines
marker = 'VIVI' + str(int(time.time()))
# Use newlines so markers appear on their own output lines (not in command echo)
full_cmd = f'echo {marker}S\n'
s.sendall(full_cmd.encode())
time.sleep(0.5)
s.sendall(f'{cmd}\n'.encode())
time.sleep(0.5)
s.sendall(f'echo {marker}E\n'.encode())

out = ''
deadline = time.time() + timeout
end_marker = f'\n{marker}E'
while time.time() < deadline:
    try:
        chunk = s.recv(4096).decode(errors='replace')
        if not chunk: break
        out += chunk
        # Look for end marker as output (on its own line), not in command echo
        if end_marker in out: break
    except socket.timeout:
        if end_marker in out: break

s.close()

# Clean ANSI escapes before extracting markers
out = clean(out)

# Split into lines and find marker boundaries
lines = out.split('\n')
start_idx = None
end_idx = None
for i, line in enumerate(lines):
    stripped = line.strip().replace('\r', '')
    if stripped == marker + 'S' and start_idx is None:
        start_idx = i
    elif stripped == marker + 'E':
        end_idx = i
        break

if start_idx is not None and end_idx is not None:
    # Get lines between markers, skip command echo lines (contain prompt)
    result_lines = []
    for line in lines[start_idx+1:end_idx]:
        stripped = line.strip().replace('\r', '')
        # Skip prompt lines and empty echo commands
        if 'root@' in stripped and '#' in stripped:
            continue
        if stripped.startswith('echo ' + marker):
            continue
        result_lines.append(stripped)
    print('\n'.join(result_lines).strip())
else:
    print(out.strip())
PYEOF
python3 /tmp/vivi-serial-exec.py '$sock' '$cmd' '$timeout'"
}

# --- SSH options per OS ---

# Return SSH options needed for a VM's SSH server.
# XP (freeSSHd) needs legacy key types; Win10+ uses standard OpenSSH.
# Args: host vm_name
vm_ssh_opts() {
    local host="$1"
    local name="$2"
    local inst_img="${KVMDIR}/instances/${name}.qcow2"
    local base
    base=$(ssh "$host" "qemu-img info '$inst_img' 2>/dev/null | grep 'backing file:' | sed 's/.*\///' | sed 's/\.qcow2//'" 2>/dev/null || echo "")
    [ -z "$base" ] && base="$name"
    case "$base" in
        winxp*|winxpx64*)
            echo "-o HostkeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1"
            ;;
        *)
            echo ""
            ;;
    esac
}

# --- VM IP discovery ---

# Find IP of a running KVM VM. Tries virsh domifaddr, then dnsmasq leases.
# Prints IP or empty string.
kvm_vm_ip() {
    local name="$1"
    local ip
    # Try virsh domifaddr (works with qemu guest agent)
    ip=$(ssh "$HOST" "virsh domifaddr '$name' 2>/dev/null | grep -oP '([0-9]+\.){3}[0-9]+' | head -1" 2>/dev/null)
    if [ -n "$ip" ]; then echo "$ip"; return; fi
    # Fall back to matching MAC in dnsmasq leases
    local mac
    mac=$(ssh "$HOST" "virsh domiflist '$name' 2>/dev/null | grep -oP '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1" 2>/dev/null)
    if [ -n "$mac" ]; then
        ip=$(ssh "$HOST_ROOT_VAL" "grep -i '$mac' /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        if [ -n "$ip" ]; then echo "$ip"; return; fi
    fi
    echo ""
}

# --- Telnet shutdown ---

# Shut down a Windows VM via telnet (sends "shutdown -s").
# Args: vm_ip
telnet_shutdown() {
    local ip="$1"
    echo "Sending shutdown command via telnet to $ip..."
    ssh "$HOST" "
        { echo '$VM_USER'; sleep 1; echo '$VM_PASS'; sleep 1; echo 'shutdown -s'; sleep 1; echo 'exit'; } \
        | telnet '$ip' 23 2>&1
    " || true
}

# --- KVM stop helper ---

# Gracefully stop a KVM VM. Args: vm_name [force]
# Tries: 1) telnet shutdown (if reachable), 2) virsh shutdown, 3) force (if enabled)
kvm_stop_vm() {
    local name="$1"
    local force="${2:-false}"
    local state
    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "shut off")
    if [[ "$state" != *"running"* ]]; then return; fi

    # Try telnet shutdown first (safer for XP — avoids NTFS corruption)
    local ip
    ip=$(kvm_vm_ip "$name")
    if [ -n "$ip" ]; then
        if ssh "$HOST" "echo quit | timeout 2 telnet '$ip' 23 2>&1 | grep -q Connected" 2>/dev/null; then
            telnet_shutdown "$ip"
            echo "Waiting for shutdown (telnet)..."
            for i in $(seq 1 60); do
                state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "shut off")
                if [[ "$state" == *"shut off"* ]]; then
                    echo "VM '$name' shut down gracefully via telnet."
                    return
                fi
                sleep 2
            done
        fi
    fi

    # Fall back to virsh shutdown (ACPI)
    echo "Sending ACPI shutdown to '$name'..."
    ssh "$HOST" "virsh shutdown '$name'" 2>/dev/null || true
    for i in $(seq 1 60); do
        state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "shut off")
        if [[ "$state" == *"shut off"* ]]; then
            echo "VM '$name' shut down gracefully via ACPI."
            return
        fi
        sleep 2
    done

    # Force kill as last resort
    if [ "$force" = "true" ]; then
        echo "WARNING: Force-killing VM. This may corrupt the filesystem (especially XP/NTFS)!"
        ssh "$HOST" "virsh destroy '$name'" 2>/dev/null || true
    else
        echo "Error: VM did not shut down within 120s."
        echo "Shut down from inside the VM first, or use: just stop $name"
        exit 1
    fi
}
