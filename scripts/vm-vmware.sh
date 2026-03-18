#!/usr/bin/env bash
# vm-vmware.sh — VMware VM operations
# Called by vm.sh dispatcher. Expects lib.sh already sourced and setup_host called.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

action="${1:?usage: vm-vmware.sh <action> [args...]}"
shift

case "$action" in

list)
    ssh "$HOST" "
        if [ -d '$SBXDIR' ] && ls '$SBXDIR'/*/*.vmx 1>/dev/null 2>&1; then
            for vmx in '$SBXDIR'/*/*.vmx; do
                dir=\$(basename \$(dirname \"\$vmx\"))
                size=\$(du -sh \$(dirname \"\$vmx\") 2>/dev/null | cut -f1)
                port=\$(grep 'RemoteDisplay.vnc.port' \"\$vmx\" 2>/dev/null | grep -oP '[0-9]+' || echo 'n/a')
                if vmrun list 2>/dev/null | grep -q \"\$vmx\"; then
                    state='running'
                else
                    state='stopped'
                fi
                printf '  %-25s  %-8s  %6s  VNC :%s\n' \"\$dir\" \"\$state\" \"\$size\" \"\$port\"
            done
        else
            echo '  (none)'
        fi
    "
    ;;

templates)
    args="${*}"
    # Handle --delete
    if [[ "$args" == "--delete "* ]]; then
        tpl="${args#--delete }"
        tpl="${tpl%% *}"
        if [ -z "$tpl" ]; then
            echo "Usage: just templates --delete <name>"
            exit 1
        fi
        tpl_dir=""
        for d in "${VMBASE_VAL}/${tpl}" "${VMBASE_VAL}/${tpl}.vmwarevm"; do
            if ssh "$HOST" "test -d '$d'" 2>/dev/null; then
                tpl_dir="$d"
                break
            fi
        done
        if [ -z "$tpl_dir" ]; then
            echo "Error: Template '$tpl' not found"
            exit 1
        fi
        size=$(ssh "$HOST" "du -sh '$tpl_dir' 2>/dev/null | cut -f1")
        echo "Delete template '$tpl' ($size)?"
        read -p "Continue? [y/N] " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Aborted."
            exit 0
        fi
        ssh "$HOST" "rm -rf '$tpl_dir'"
        echo "Deleted template '$tpl'."
        exit 0
    fi

    require_ext_mount
    echo "Available templates (use with: just launch <template> <name>):"
    ssh "$HOST" "
        for vmx in \$(find '$VMBASE_VAL' -maxdepth 2 -name '*.vmx' 2>/dev/null | sort); do
            dir=\$(dirname \"\$vmx\")
            name=\$(basename \"\$dir\" .vmwarevm)
            size=\$(du -sh \"\$dir\" 2>/dev/null | cut -f1)
            printf '  %-30s  %s\n' \"\$name\" \"\$size\"
        done
    "
    ;;

install)
    all_args="$*"
    os="${all_args%% *}"
    rest="${all_args#* }"
    [ "$os" = "$rest" ] && rest=""
    name="${rest%% *}"
    args="${rest#* }"
    [ "$name" = "$args" ] && args=""

    if [ -z "$name" ]; then
        echo "Usage: just install <os> <name> [--no-network]"
        exit 1
    fi

    # Look up OS preset
    if [ -z "${os_iso[$os]+x}" ]; then
        echo "Unknown OS: $os"
        echo "Supported: winxp, win10, win11"
        ssh "$HOST" "ls '$ISODIR'/*.iso 2>/dev/null | xargs -I{} basename {}"
        exit 1
    fi

    iso="${os_iso[$os]}"; mem="${os_mem[$os]}"; cpus="${os_cpus[$os]}"
    disk_gb="${os_disk[$os]}"; guest_os="${os_guest[$os]}"
    vmware_hw="${os_vmware_hw[$os]}"; product_key="${os_key[$os]}"
    iso_path="${ISODIR}/${iso}"

    if ! ssh "$HOST" "test -f '$iso_path'" 2>/dev/null; then
        echo "Error: ISO not found: $iso_path"
        exit 1
    fi

    network=true
    [[ "$args" == *"--no-network"* ]] && network=false

    require_ext_mount

    echo "[vmware] Installing $os as '$name' (${mem}MB RAM, ${cpus} CPU, ${disk_gb}GB disk)"

    dest_dir="${SBXDIR}/${name}"
    dest_vmx="${dest_dir}/${name}.vmx"
    dest_vmdk="${dest_dir}/disk.vmdk"

    if ssh "$HOST" "test -d '$dest_dir'" 2>/dev/null; then
        echo "Error: '$name' already exists at $dest_dir"
        exit 1
    fi

    ssh "$HOST" "mkdir -p '$dest_dir'"

    echo "Creating ${disk_gb}GB disk..."
    ssh "$HOST" "vmware-vdiskmanager -c -s ${disk_gb}GB -a lsilogic -t 1 '$dest_vmdk'" 2>/dev/null \
        || ssh "$HOST" "qemu-img create -f vmdk '$dest_vmdk' ${disk_gb}G"

    # Networking
    net_type="custom"
    net_extra='ethernet0.startConnected = "FALSE"'
    if [ "$network" = true ]; then
        net_type="bridged"
        net_extra="ethernet0.vnet = \"$VMWARE_NIC\""
    fi

    port=$(next_vnc_port)

    echo "Creating VM configuration..."
    vmx_lines='.encoding = "UTF-8"'
    vmx_lines="$vmx_lines"$'\n''config.version = "8"'
    vmx_lines="$vmx_lines"$'\n''virtualHW.version = "21"'
    vmx_lines="$vmx_lines"$'\n'"displayName = \"$name\""
    vmx_lines="$vmx_lines"$'\n'"guestOS = \"$guest_os\""
    vmx_lines="$vmx_lines"$'\n'"memsize = \"$mem\""
    vmx_lines="$vmx_lines"$'\n'"numvcpus = \"$cpus\""

    if [ "$vmware_hw" = "ide" ]; then
        vmx_lines="$vmx_lines"$'\n'"$(printf 'ide0%s0.present = "TRUE"\nide0%s0.fileName = "disk.vmdk"' : :)"
        vmx_lines="$vmx_lines"$'\n'"$(printf 'ide1%s0.present = "TRUE"\nide1%s0.deviceType = "cdrom-image"\nide1%s0.fileName = "%s"\nide1%s0.startConnected = "TRUE"' : : : "$iso_path" :)"
    else
        vmx_lines="$vmx_lines"$'\n'"$(printf 'scsi0.virtualDev = "lsisas1068"\nscsi0.present = "TRUE"\nscsi0%s0.present = "TRUE"\nscsi0%s0.fileName = "disk.vmdk"' : :)"
        vmx_lines="$vmx_lines"$'\n'"$(printf 'sata0.present = "TRUE"\nsata0%s0.present = "TRUE"\nsata0%s0.deviceType = "cdrom-image"\nsata0%s0.fileName = "%s"\nsata0%s0.startConnected = "TRUE"' : : : "$iso_path" :)"
    fi

    vmx_lines="$vmx_lines"$'\n''ethernet0.present = "TRUE"'
    vmx_lines="$vmx_lines"$'\n'"ethernet0.connectionType = \"$net_type\""
    vmx_lines="$vmx_lines"$'\n'"$net_extra"
    vmx_lines="$vmx_lines"$'\n''ethernet0.virtualDev = "e1000"'
    vmx_lines="$vmx_lines"$'\n''RemoteDisplay.vnc.enabled = "TRUE"'
    vmx_lines="$vmx_lines"$'\n'"RemoteDisplay.vnc.port = \"$port\""
    vmx_lines="$vmx_lines"$'\n''firmware = "bios"'

    printf '%s\n' "$vmx_lines" | ssh "$HOST" "cat > '$dest_vmx'"

    echo "Starting $name..."
    ssh "$HOST" "vmrun -T ws start '$dest_vmx' nogui"

    echo ""
    echo "VM '$name' running on VNC port $port — OS installer will boot from ISO."
    [ -n "$product_key" ] && echo "Product key: $product_key"
    echo "Connect: just connect $name"
    ;;

launch)
    base="$1"; shift
    name="$1"; shift
    args="${*}"
    full_name="${base}-${name}"

    network=true
    [[ "$args" == *"--no-network"* ]] && network=false

    require_ext_mount

    vmx=$(find_base_vmx "$base")
    if [ -z "$vmx" ]; then
        echo "Error: Base VM '$base' not found. Available bases:"
        ssh "$HOST" "find '$VMBASE_VAL' -maxdepth 2 -name '*.vmx' 2>/dev/null | while read -r f; do basename \"\$(dirname \"\$f\")\" .vmwarevm; done | sort"
        exit 1
    fi

    dest_dir="${SBXDIR}/${full_name}"
    dest_vmx="${dest_dir}/${full_name}.vmx"
    if ssh "$HOST" "test -d '$dest_dir'" 2>/dev/null; then
        echo "Error: Sandbox '$full_name' already exists"
        echo "Use: just destroy ${name}"
        exit 1
    fi

    ssh "$HOST" "mkdir -p '$SBXDIR'"

    echo "Cloning $base -> $full_name (linked clone)..."
    ssh "$HOST" "vmrun -T ws clone '$vmx' '$dest_vmx' linked -cloneName='$full_name'"

    if [ "$network" = true ]; then
        echo "Enabling bridged networking ($VMWARE_NIC)..."
        ssh "$HOST" "sed -i 's/ethernet0.connectionType = \"nat\"/ethernet0.connectionType = \"bridged\"/' '$dest_vmx'"
        ssh "$HOST" "grep -q 'ethernet0.vnet' '$dest_vmx' && sed -i 's/ethernet0.vnet = .*/ethernet0.vnet = \"$VMWARE_NIC\"/' '$dest_vmx' || printf 'ethernet0.vnet = \"$VMWARE_NIC\"\n' >> '$dest_vmx'"
    else
        ssh "$HOST" "sed -i 's/ethernet0.connectionType = \"nat\"/ethernet0.connectionType = \"custom\"/' '$dest_vmx'"
        ssh "$HOST" "printf 'ethernet0.startConnected = \"FALSE\"\n' >> '$dest_vmx'"
    fi

    port=$(next_vnc_port)
    ssh "$HOST" "printf 'RemoteDisplay.vnc.enabled = \"TRUE\"\nRemoteDisplay.vnc.port = \"${port}\"\n' >> '$dest_vmx'"

    echo "Starting $full_name..."
    ssh "$HOST" "vmrun -T ws start '$dest_vmx' nogui"

    echo ""
    if [ "$network" = true ]; then
        echo "Sandbox '$full_name' running on VNC port $port (bridged network on $VMWARE_NIC)"
    else
        echo "Sandbox '$full_name' running on VNC port $port (network disconnected)"
    fi
    echo "Connect: just connect $name"
    ;;

connect)
    name="$1"
    vmx=$(find_sandbox_vmx "$name")
    if [ -z "$vmx" ]; then
        echo "Error: No sandbox matching '*-${name}' found"
        echo "Running sandboxes:"
        ssh "$HOST" "vmrun list 2>/dev/null"
        exit 1
    fi

    port=$(ssh "$HOST" "grep 'RemoteDisplay.vnc.port' '$vmx' 2>/dev/null | grep -oP '[0-9]+'")
    if [ -z "$port" ]; then
        echo "Error: No VNC port configured for this sandbox"
        exit 1
    fi

    if ! ssh "$HOST" "vmrun list 2>/dev/null | grep -q '$vmx'"; then
        echo "VM not running, starting..."
        ssh "$HOST" "vmrun -T ws start '$vmx' nogui"
        sleep 2
    fi

    echo "Connecting to $(basename "$(dirname "$vmx")") on VNC port $port..."
    remmina -c "vnc://${HOST_IP_VAL}:${port}" &
    ;;

start)
    name="$1"
    vmx=$(find_sandbox_vmx "$name")
    if [ -z "$vmx" ]; then
        echo "Error: No sandbox matching '*-${name}' found"
        exit 1
    fi

    if ssh "$HOST" "vmrun list 2>/dev/null | grep -q '$vmx'"; then
        echo "$(basename "$(dirname "$vmx")") is already running"
        exit 0
    fi

    echo "Starting $(basename "$(dirname "$vmx")")..."
    ssh "$HOST" "vmrun -T ws start '$vmx' nogui"
    port=$(ssh "$HOST" "grep 'RemoteDisplay.vnc.port' '$vmx' 2>/dev/null | grep -oP '[0-9]+'")
    echo "Running. VNC port: $port"
    echo "Connect: just connect $name"
    ;;

stop)
    name="$1"; shift
    mode="${1:-soft}"
    vmx=$(find_sandbox_vmx "$name")
    if [ -z "$vmx" ]; then
        echo "Error: No sandbox matching '*-${name}' found"
        exit 1
    fi

    echo "Stopping $(basename "$(dirname "$vmx")") ($mode)..."
    ssh "$HOST" "vmrun -T ws stop '$vmx' '$mode'"
    echo "Stopped."
    ;;

destroy)
    name="$1"
    vmx=$(find_sandbox_vmx "$name")
    if [ -z "$vmx" ]; then
        echo "Error: No sandbox matching '*-${name}' found"
        exit 1
    fi

    dir=$(dirname "$vmx")
    full_name=$(basename "$dir")

    echo "This will permanently delete sandbox '$full_name'"
    read -p "Continue? [y/N] " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted."
        exit 0
    fi

    if ssh "$HOST" "vmrun list 2>/dev/null | grep -q '$vmx'"; then
        echo "Stopping VM..."
        ssh "$HOST" "vmrun -T ws stop '$vmx' hard" 2>/dev/null || true
    fi

    echo "Deleting VM..."
    ssh "$HOST" "vmrun -T ws deleteVM '$vmx'" 2>/dev/null || true
    ssh "$HOST" "rm -rf '$dir'" 2>/dev/null || true
    echo "Destroyed '$full_name'."
    ;;

snapshot)
    name="$1"; shift
    args="$*"
    subcmd="${args%% *}"
    rest="${args#* }"
    [ "$subcmd" = "$rest" ] && rest=""

    vmx=$(find_sandbox_vmx "$name")
    if [ -z "$vmx" ]; then
        echo "Error: No sandbox matching '*-${name}' found"
        exit 1
    fi

    case "$subcmd" in
        create)
            snap="${rest:-$(date +%Y%m%d-%H%M%S)}"
            echo "Creating snapshot '$snap'..."
            ssh "$HOST" "vmrun snapshot '$vmx' '$snap'"
            echo "Snapshot '$snap' created."
            ;;
        list)
            ssh "$HOST" "vmrun listSnapshots '$vmx'"
            ;;
        revert)
            if [ -z "$rest" ]; then
                echo "Usage: just snapshot $name revert <snapshot>"
                echo ""; ssh "$HOST" "vmrun listSnapshots '$vmx'"
                exit 1
            fi
            echo "Reverting to '$rest'..."
            ssh "$HOST" "vmrun revertToSnapshot '$vmx' '$rest'"
            echo "Reverted. Start with: just start $name"
            ;;
        delete)
            if [ -z "$rest" ]; then
                echo "Usage: just snapshot $name delete <snapshot>"
                echo ""; ssh "$HOST" "vmrun listSnapshots '$vmx'"
                exit 1
            fi
            echo "Deleting snapshot '$rest'..."
            ssh "$HOST" "vmrun deleteSnapshot '$vmx' '$rest'"
            echo "Deleted."
            ;;
        *)
            echo "Usage: just snapshot <name> create|list|revert|delete [snapshot]"
            echo ""
            echo "  create [name]   Create snapshot (default: timestamp)"
            echo "  list            List snapshots"
            echo "  revert <name>   Revert to snapshot"
            echo "  delete <name>   Delete snapshot"
            ;;
    esac
    ;;

save)
    name="$1"; shift
    template="${1:-$name}"

    vmx=$(find_sandbox_vmx "$name")
    if [ -z "$vmx" ]; then
        echo "Error: No sandbox matching '$name' found"
        exit 1
    fi
    src_dir=$(dirname "$vmx")

    dest_dir="${VMBASE_VAL}/${template}.vmwarevm"
    if ssh "$HOST" "test -d '$dest_dir'" 2>/dev/null; then
        old_size=$(ssh "$HOST" "du -sh '$dest_dir' 2>/dev/null | cut -f1")
        echo "Template '$template' already exists ($old_size)."
        read -p "Overwrite? [y/N] " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Aborted."
            exit 0
        fi
        ssh "$HOST" "rm -rf '$dest_dir'"
    fi

    if ssh "$HOST" "vmrun list 2>/dev/null | grep -q '$vmx'"; then
        echo "Stopping VM first..."
        ssh "$HOST" "vmrun -T ws stop '$vmx' soft" 2>/dev/null || true
    fi

    echo "Copying $src_dir -> $dest_dir ..."
    ssh "$HOST" "cp -a '$src_dir' '$dest_dir'"

    old_vmx_name=$(basename "$vmx")
    new_vmx_name="${template}.vmx"
    if [ "$old_vmx_name" != "$new_vmx_name" ]; then
        ssh "$HOST" "mv '$dest_dir/$old_vmx_name' '$dest_dir/$new_vmx_name'"
    fi

    size=$(ssh "$HOST" "du -sh '$dest_dir' 2>/dev/null | cut -f1")
    echo "Saved template '$template' ($size)"
    echo "Use with: just launch $template <name>"
    ;;

cdrom)
    name="$1"; shift
    args="$*"
    subcmd="${args%% *}"

    case "$subcmd" in
        eject)
            vmx=$(find_sandbox_vmx "$name")
            if [ -z "$vmx" ]; then echo "Error: No sandbox '$name' found"; exit 1; fi
            ssh "$HOST" "vmrun -T ws disconnectNamedDevice '$vmx' cdrom0" 2>/dev/null || true
            echo "CD-ROM ejected."
            ;;
        list)
            echo "Available ISOs:"
            ssh "$HOST" "ls '$ISODIR'/*.iso 2>/dev/null" | while read -r f; do
                size=$(ssh "$HOST" "du -h '$f' | cut -f1")
                printf '  %-50s  %s\n' "$(basename "$f")" "$size"
            done
            ;;
        "")
            echo "Usage: just cdrom <name> <iso>|eject|list"
            echo ""
            echo "  <iso>    ISO filename from $ISODIR"
            echo "  eject    Eject the current CD-ROM"
            echo "  list     List available ISOs"
            ;;
        *)
            iso_name="$subcmd"
            if [[ "$iso_name" = /* ]]; then
                iso_path="$iso_name"
            else
                [[ "$iso_name" != *.iso ]] && iso_name="${iso_name}.iso"
                iso_path="${ISODIR}/${iso_name}"
            fi

            if ! ssh "$HOST" "test -f '$iso_path'" 2>/dev/null; then
                echo "Error: ISO not found: $iso_path"
                echo "Available ISOs:"
                ssh "$HOST" "ls '$ISODIR'/*.iso 2>/dev/null | xargs -I{} basename {}"
                exit 1
            fi

            vmx=$(find_sandbox_vmx "$name")
            if [ -z "$vmx" ]; then echo "Error: No sandbox '$name' found"; exit 1; fi
            ssh "$HOST" "vmrun -T ws connectNamedDevice '$vmx' cdrom0" 2>/dev/null || true
            ssh "$HOST" "
                sed -i '/\.deviceType = \"cdrom-image\"/!b; n; s|\.fileName = \".*\"|.fileName = \"$iso_path\"|' '$vmx'
            " 2>/dev/null || true
            ssh "$HOST" "vmrun -T ws insertDisc '$vmx' '$iso_path'" 2>/dev/null || true
            echo "Mounted $iso_name on '$name'."
            ;;
    esac
    ;;

share)
    name="$1"; shift
    args="$*"

    if [ -z "$args" ]; then
        echo "Usage: just share <name> <file1> [file2...]"
        echo ""
        echo "Packages files into an ISO and mounts it as CD-ROM on the VM."
        echo "Paths are relative to $ISODIR on the host."
        exit 1
    fi

    # Build file list
    files=""
    for f in $args; do
        if [[ "$f" = /* ]]; then
            files="$files '$f'"
        else
            files="$files '${ISODIR}/$f'"
        fi
    done

    ssh "$HOST" "for f in $files; do
        if [ ! -f \"\$f\" ]; then
            echo \"Error: file not found: \$f\"
            exit 1
        fi
    done"

    iso_path="/tmp/share-${name}.iso"

    # Eject existing media first
    "$0" cdrom "$name" eject 2>/dev/null || true

    echo "Creating ISO from: $args"
    ssh "$HOST" "
        rm -f '$iso_path'
        tmpdir=\$(mktemp -d /tmp/share-${name}-XXXXXX)
        for f in $files; do
            cp \"\$f\" \"\$tmpdir/\"
        done
        genisoimage -quiet -J -r -o '$iso_path' \"\$tmpdir\"
        rm -rf \"\$tmpdir\"
    "

    echo "Mounting ISO on '$name'..."
    "$0" cdrom "$name" "$iso_path"
    ;;

status)
    echo "=== Running VMs ==="
    ssh "$HOST" "vmrun list 2>/dev/null"

    echo ""
    ext_free=$(ssh "$HOST" "df -h /mnt/ext 2>/dev/null | awk 'NR==2{print \$4}'" 2>/dev/null || echo "n/a")
    echo "=== Base VMs (${VMBASE_VAL}) — ${ext_free} free ==="
    if ssh "$HOST" "mountpoint -q /mnt/ext" 2>/dev/null; then
        ssh "$HOST" "
            for vmx in \$(find '$VMBASE_VAL' -maxdepth 2 -name '*.vmx' 2>/dev/null | sort); do
                dir=\$(dirname \"\$vmx\")
                name=\$(basename \"\$dir\" .vmwarevm)
                size=\$(du -sh \"\$dir\" 2>/dev/null | cut -f1)
                printf '  %-30s  %s\n' \"\$name\" \"\$size\"
            done
        "
    else
        echo "(external disk not mounted — ssh $HOST_ROOT_VAL 'mount $EXT_DEV_VAL /mnt/ext')"
    fi

    echo ""
    sbx_free=$(ssh "$HOST" "df -h '$SBXDIR' 2>/dev/null | awk 'NR==2{print \$4}'" 2>/dev/null)
    sbx_free="${sbx_free:-n/a}"
    echo "=== Sandboxes (${SBXDIR}) — ${sbx_free} free ==="
    ssh "$HOST" "
        if [ -d '$SBXDIR' ] && ls '$SBXDIR'/*/*.vmx 1>/dev/null 2>&1; then
            for vmx in '$SBXDIR'/*/*.vmx; do
                dir=\$(basename \$(dirname \"\$vmx\"))
                port=\$(grep 'RemoteDisplay.vnc.port' \"\$vmx\" 2>/dev/null | grep -oP '[0-9]+' || echo 'n/a')
                if vmrun list 2>/dev/null | grep -q \"\$vmx\"; then
                    state='running'
                else
                    state='stopped'
                fi
                printf '  %-30s  %-10s  VNC :%s\n' \"\$dir\" \"\$state\" \"\$port\"
            done
        else
            echo '  (none)'
        fi
    "
    ;;

*)
    echo "Unknown VMware action: $action" >&2
    exit 1
    ;;
esac
