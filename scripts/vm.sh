#!/usr/bin/env bash
# vm.sh — Main dispatcher for VM operations.
# Usage: vm.sh <host> <action> [args...]
#
# Sources lib.sh (which sources config.sh), sets up the host,
# detects the hypervisor, and dispatches to vm-kvm.sh or vm-vmware.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

host="${1:?usage: vm.sh <host> <action> [args...]}"
shift
action="${1:?usage: vm.sh <host> <action> [args...]}"
shift

setup_host "$host"

# Actions that handle hypervisor detection internally or don't need one
case "$action" in
    hypervisor)
        cmd="${1:-status}"
        ssh "$HOST_ROOT_VAL" "hypervisor-switch $cmd"
        exit 0
        ;;
    convert)
        base="${1:?usage: vm.sh <host> convert <base>}"
        require_ext_mount

        vmx=$(find_base_vmx "$base")
        if [ -z "$vmx" ]; then
            echo "Error: VMX not found for '$base'. Available VMs:"
            ssh "$HOST" "find '$VMBASE_VAL' -maxdepth 2 -name '*.vmx' 2>/dev/null | while read -r f; do basename \"\$(dirname \"\$f\")\" .vmwarevm; done | sort"
            exit 1
        fi
        vmx_dir=$(dirname "$vmx")

        disk_file=$(ssh "$HOST" "grep -iE '(nvme|scsi|sata|ide)[0-9]+:[0-9]+\.fileName' '$vmx' | grep -iv 'cdrom' | head -1 | sed 's/.*= *\"\(.*\)\"/\1/'" 2>/dev/null)
        if [ -z "$disk_file" ]; then
            echo "Error: No disk found in VMX: $vmx"
            exit 1
        fi

        vmdk="${vmx_dir}/${disk_file}"
        echo "Found disk: $vmdk"

        dest="${KVMTPL}/${base}.qcow2"
        if ssh "$HOST" "test -f '$dest'" 2>/dev/null; then
            echo "qcow2 already exists: $dest"
            ssh "$HOST" "ls -lh '$dest'"
            echo "Delete it first if you want to reconvert."
            exit 0
        fi

        echo "Converting $vmdk -> $dest ..."
        echo "(this may take several minutes for large disks)"
        ssh "$HOST" "qemu-img convert -p -f vmdk -O qcow2 '$vmdk' '$dest'"
        echo ""
        echo "Done. Image info:"
        ssh "$HOST" "qemu-img info '$dest'"
        exit 0
        ;;
    install)
        # Handle --list before hypervisor detection
        first="${1:-}"
        if [ "$first" = "--list" ]; then
            printf '  %-12s  %6s  %3s  %4s  %s\n' "OS" "RAM" "CPU" "DISK" "ISO"
            printf '  %-12s  %6s  %3s  %4s  %s\n' "-----" "----" "---" "----" "---"
            for os in $(echo "${!os_iso[@]}" | tr ' ' '\n' | sort); do
                mem=$((${os_mem[$os]} / 1024))
                key="${os_key[$os]:-}"
                extra="${os_kvm_extra[$os]:-}"
                note=""
                [ -n "$key" ] && note=" (key: $key)"
                [[ "$extra" == *"uefi"* ]] && note="${note} (UEFI+TPM)"
                printf '  %-12s  %4s GB  %3s  %3sG  %s%s\n' \
                    "$os" "$mem" "${os_cpus[$os]}" "${os_disk[$os]}" "${os_iso[$os]}" "$note"
            done
            exit 0
        fi
        ;;
esac

# --- ARM VM detection ---
# Route to vm-arm.sh if the VM is ARM (template name contains "arm64" or instance has -vars.fd)
is_arm=false
case "$action" in
    launch)
        base="${1:-}"
        if [[ "$base" == *arm64* ]]; then is_arm=true; fi
        ;;
    start|stop|connect|destroy|snapshot|exec)
        name="${1:-}"
        if [ -n "$name" ] && ssh "$HOST" "test -f '${KVMDIR}/instances/${name}-vars.fd'" 2>/dev/null; then
            is_arm=true
        fi
        ;;
esac

if [ "$is_arm" = true ]; then
    echo "[arm] $HOST"
    echo ""
    exec "$SCRIPT_DIR/vm-arm.sh" "$action" "$@"
fi

# All other actions need a hypervisor
hv=$(require_hypervisor)
echo "[$hv] $HOST"
echo ""

exec "$SCRIPT_DIR/vm-${hv}.sh" "$action" "$@"
