#!/usr/bin/env bash
# vm-arm.sh — ARM QEMU standalone VM operations.
# Called by vm.sh when an ARM VM is detected.
# Usage: vm-arm.sh <action> [args...]
#
# ARM VMs run as standalone qemu-system-aarch64 processes (not libvirt-managed).
# Detection: instance has a -vars.fd file, or template name contains "arm64".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

action="${1:?usage: vm-arm.sh <action> [args...]}"
shift

INSTDIR="${KVMDIR}/instances"

# Start QEMU for an ARM instance. Args: name [network-mode]
# network-mode: bridge (default), hostonly, none
_arm_start() {
    local name="$1"
    local netmode="${2:-bridge}"
    local img="${INSTDIR}/${name}.qcow2"
    local vars="${INSTDIR}/${name}-vars.fd"
    local pidfile="${INSTDIR}/${name}.pid"
    local serial_sock="${INSTDIR}/${name}-serial.sock"
    local monitor_sock="${INSTDIR}/${name}-monitor.sock"

    if arm_is_running "$name" 2>/dev/null; then
        echo "VM '$name' is already running (PID $(ssh "$HOST" "cat '$pidfile'"))"
        return 0
    fi

    # Clean up stale sockets
    ssh "$HOST" "rm -f '$serial_sock' '$monitor_sock' '$pidfile'"

    # Network config
    local net_args
    case "$netmode" in
        none)     net_args="-nic none" ;;
        hostonly) net_args="-netdev bridge,id=net0,br=${KVM_HOSTONLY} -device virtio-net-pci,netdev=net0" ;;
        *)        net_args="-netdev bridge,id=net0,br=${KVM_BRIDGE} -device virtio-net-pci,netdev=net0" ;;
    esac

    echo "Starting ARM VM '$name' (${ARM_MEM}MB, ${ARM_CPUS} CPUs, net=$netmode)..."
    ssh "$HOST" "qemu-system-aarch64 \
        -M virt -cpu ${ARM_CPU_MODEL} -m ${ARM_MEM}M -smp ${ARM_CPUS} \
        -drive if=pflash,format=raw,readonly=on,file=${ARM_PFLASH} \
        -drive if=pflash,format=raw,file=${vars} \
        -drive if=virtio,format=qcow2,file=${img} \
        ${net_args} \
        -serial unix:${serial_sock},server,nowait \
        -monitor unix:${monitor_sock},server,nowait \
        -display none -daemonize \
        -pidfile ${pidfile}"

    echo "VM '$name' started (PID $(ssh "$HOST" "cat '$pidfile'"))"
    echo "Waiting for boot..."
    sleep 20
    echo "Ready. Connect with: just connect $name"
}

case "$action" in

launch)
    base="${1:?usage: vm-arm.sh launch <base> <name> [--no-network|--hostonly]}"
    name="${2:?usage: vm-arm.sh launch <base> <name> [--no-network|--hostonly]}"
    netflag="${3:-}"
    tpl="${KVMTPL}/${base}.qcow2"
    img="${INSTDIR}/${name}.qcow2"
    vars="${INSTDIR}/${name}-vars.fd"

    if ssh "$HOST" "test -f '$img'" 2>/dev/null; then
        echo "Instance '$name' already exists: $img"
        echo "Use 'just start $name' to start it, or 'just destroy $name' to remove."
        exit 1
    fi

    if ! ssh "$HOST" "test -f '$tpl'" 2>/dev/null; then
        echo "Error: Template not found: $tpl"
        echo "Available ARM templates:"
        ssh "$HOST" "ls ${KVMTPL}/*arm64*.qcow2 2>/dev/null | sed 's|.*/||;s|\.qcow2||'" || echo "  (none)"
        exit 1
    fi

    echo "Creating ARM instance '$name' from template '$base'..."
    ssh "$HOST" "qemu-img create -f qcow2 -b '$tpl' -F qcow2 '$img'"
    ssh "$HOST" "cp '${ARM_PFLASH_VARS}' '$vars'"
    ssh "$HOST" "qemu-img snapshot -c clean '$img'"
    echo "Created instance with 'clean' snapshot."

    # Determine network mode
    netmode="bridge"
    case "$netflag" in
        --no-network) netmode="none" ;;
        --hostonly)   netmode="hostonly" ;;
    esac

    _arm_start "$name" "$netmode"
    ;;

start)
    name="${1:?usage: vm-arm.sh start <name> [--no-network|--hostonly]}"
    netflag="${2:-}"
    img="${INSTDIR}/${name}.qcow2"
    vars="${INSTDIR}/${name}-vars.fd"

    if ! ssh "$HOST" "test -f '$img'" 2>/dev/null; then
        echo "Error: Instance not found: $img"
        exit 1
    fi
    if ! ssh "$HOST" "test -f '$vars'" 2>/dev/null; then
        echo "Error: UEFI vars not found: $vars (not an ARM instance?)"
        exit 1
    fi

    netmode="bridge"
    case "$netflag" in
        --no-network) netmode="none" ;;
        --hostonly)   netmode="hostonly" ;;
    esac

    _arm_start "$name" "$netmode"
    ;;

stop)
    name="${1:?usage: vm-arm.sh stop <name>}"
    pidfile="${INSTDIR}/${name}.pid"

    if ! arm_is_running "$name" 2>/dev/null; then
        echo "VM '$name' is not running."
        exit 0
    fi

    echo "Sending poweroff to '$name'..."
    arm_monitor_cmd "$name" "system_powerdown" 2>/dev/null || true

    # Wait for clean shutdown
    for i in $(seq 1 30); do
        if ! arm_is_running "$name" 2>/dev/null; then
            echo "VM '$name' shut down gracefully."
            ssh "$HOST" "rm -f '${INSTDIR}/${name}-serial.sock' '${INSTDIR}/${name}-monitor.sock' '$pidfile'" 2>/dev/null || true
            exit 0
        fi
        sleep 2
    done

    # Force quit via monitor
    echo "Graceful shutdown timed out. Sending quit..."
    arm_monitor_cmd "$name" "quit" 2>/dev/null || true
    sleep 2

    # Last resort: kill
    if arm_is_running "$name" 2>/dev/null; then
        echo "Force-killing..."
        ssh "$HOST" "kill \$(cat '$pidfile') 2>/dev/null" || true
    fi

    ssh "$HOST" "rm -f '${INSTDIR}/${name}-serial.sock' '${INSTDIR}/${name}-monitor.sock' '$pidfile'" 2>/dev/null || true
    echo "VM '$name' stopped."
    ;;

destroy)
    name="${1:?usage: vm-arm.sh destroy <name>}"

    # Stop if running
    if arm_is_running "$name" 2>/dev/null; then
        "$0" stop "$name"
    fi

    echo "Deleting ARM instance '$name'..."
    echo "  ${INSTDIR}/${name}.qcow2"
    echo "  ${INSTDIR}/${name}-vars.fd"
    read -rp "Continue? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Cancelled."
        exit 0
    fi

    ssh "$HOST" "rm -f '${INSTDIR}/${name}.qcow2' '${INSTDIR}/${name}-vars.fd' \
        '${INSTDIR}/${name}.pid' '${INSTDIR}/${name}-serial.sock' '${INSTDIR}/${name}-monitor.sock'"
    echo "Destroyed '$name'."
    ;;

connect)
    name="${1:?usage: vm-arm.sh connect <name>}"

    if ! arm_is_running "$name" 2>/dev/null; then
        echo "VM '$name' is not running. Starting..."
        _arm_start "$name"
    fi

    echo "Attaching to serial console of '$name'..."
    echo "  Press Ctrl-] to detach."
    echo ""
    ssh -t "$HOST" "socat -,rawer,escape=0x1d UNIX-CONNECT:'${INSTDIR}/${name}-serial.sock'"
    ;;

exec)
    name="${1:?usage: vm-arm.sh exec <name> <command> [timeout]}"
    cmd="${2:?usage: vm-arm.sh exec <name> <command> [timeout]}"
    timeout="${3:-10}"

    if ! arm_is_running "$name" 2>/dev/null; then
        echo "Error: VM '$name' is not running."
        exit 1
    fi

    arm_serial_exec "$name" "$cmd" "$timeout"
    ;;

snapshot)
    name="${1:?usage: vm-arm.sh snapshot <name> create|list|revert|delete [snap]}"
    subcmd="${2:?usage: vm-arm.sh snapshot <name> create|list|revert|delete [snap]}"
    snap="${3:-}"
    img="${INSTDIR}/${name}.qcow2"

    if ! ssh "$HOST" "test -f '$img'" 2>/dev/null; then
        echo "Error: Instance not found: $img"
        exit 1
    fi

    case "$subcmd" in
        create)
            if [ -z "$snap" ]; then
                snap=$(date +%Y%m%d-%H%M%S)
            fi
            # Back up UEFI vars alongside snapshot
            ssh "$HOST" "cp '${INSTDIR}/${name}-vars.fd' '${INSTDIR}/${name}-vars-${snap}.fd'"
            ssh "$HOST" "qemu-img snapshot -c '$snap' '$img'"
            echo "Created snapshot '$snap' for '$name'"
            ;;
        list)
            ssh "$HOST" "qemu-img snapshot -l '$img'"
            ;;
        revert)
            if [ -z "$snap" ]; then
                echo "Usage: vm-arm.sh snapshot <name> revert <snap>"
                exit 1
            fi
            if arm_is_running "$name" 2>/dev/null; then
                echo "Error: Stop VM before reverting. Run: just stop $name"
                exit 1
            fi
            ssh "$HOST" "qemu-img snapshot -a '$snap' '$img'"
            # Restore UEFI vars if backup exists
            if ssh "$HOST" "test -f '${INSTDIR}/${name}-vars-${snap}.fd'" 2>/dev/null; then
                ssh "$HOST" "cp '${INSTDIR}/${name}-vars-${snap}.fd' '${INSTDIR}/${name}-vars.fd'"
            fi
            echo "Reverted '$name' to snapshot '$snap'"
            ;;
        delete)
            if [ -z "$snap" ]; then
                echo "Usage: vm-arm.sh snapshot <name> delete <snap>"
                exit 1
            fi
            ssh "$HOST" "qemu-img snapshot -d '$snap' '$img'"
            ssh "$HOST" "rm -f '${INSTDIR}/${name}-vars-${snap}.fd'"
            echo "Deleted snapshot '$snap' from '$name'"
            ;;
        *)
            echo "Usage: vm-arm.sh snapshot <name> create|list|revert|delete [snap]"
            exit 1
            ;;
    esac
    ;;

status)
    echo "=== ARM VM Instances ==="
    ssh "$HOST" "
        for f in '${INSTDIR}'/*-vars.fd; do
            [ -f \"\$f\" ] || continue
            name=\$(basename \"\$f\" -vars.fd)
            img=\"${INSTDIR}/\${name}.qcow2\"
            pidfile=\"${INSTDIR}/\${name}.pid\"
            size=\$(du -h \"\$img\" 2>/dev/null | cut -f1)
            if [ -f \"\$pidfile\" ] && kill -0 \$(cat \"\$pidfile\") 2>/dev/null; then
                state=\"running PID=\$(cat \"\$pidfile\")\"
            else
                state='stopped'
            fi
            snaps=\$(qemu-img snapshot -l \"\$img\" 2>/dev/null | grep -c '^ *[0-9]' || echo 0)
            printf '  %-25s  %s  %s  (%s snapshots)\n' \"\$name\" \"\$size\" \"\$state\" \"\$snaps\"
        done
    " 2>/dev/null || echo "  (none)"
    ;;

*)
    echo "Unknown ARM action: $action"
    echo "Available: launch, start, stop, destroy, connect, exec, snapshot, status"
    exit 1
    ;;
esac
