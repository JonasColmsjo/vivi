#!/usr/bin/env bash
# vm-kvm.sh — KVM/libvirt VM operations
# Called by vm.sh dispatcher. Expects lib.sh already sourced and setup_host called.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

action="${1:?usage: vm-kvm.sh <action> [args...]}"
shift

case "$action" in

list)
    has_any=false
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        has_any=true
        vm_name=$(echo "$line" | awk '{print $2}')
        vm_state=$(ssh -n "$HOST" "virsh domstate '$vm_name' 2>/dev/null" || echo "unknown")
        disk="${KVMDIR}/instances/${vm_name}.qcow2"
        size=$(ssh -n "$HOST" "du -h '$disk' 2>/dev/null | cut -f1" || echo "n/a")
        port=$(ssh -n "$HOST" "virsh domdisplay '$vm_name' 2>/dev/null | grep -oP ':\K[0-9]+'" || echo "n/a")
        printf '  %-25s  %-8s  %6s  SPICE :%s\n' "$vm_name" "$vm_state" "$size" "${port:-n/a}"
    done < <(ssh "$HOST" "virsh list --all 2>/dev/null | tail -n +3")

    if [ "$has_any" = false ]; then
        echo "  (none)"
    fi
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
        tpl_path="${KVMTPL}/${tpl}.qcow2"
        if ! ssh "$HOST" "test -f '$tpl_path'" 2>/dev/null; then
            echo "Error: Template '$tpl' not found at $tpl_path"
            exit 1
        fi
        size=$(ssh "$HOST" "du -h '$tpl_path' 2>/dev/null | cut -f1")
        echo "Delete template '$tpl' ($size)?"
        read -p "Continue? [y/N] " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Aborted."
            exit 0
        fi
        ssh "$HOST" "rm -f '$tpl_path'"
        echo "Deleted template '$tpl'."
        exit 0
    fi

    echo "Available templates (use with: just launch <template> <name>):"
    ssh "$HOST" "
        if ls '${KVMTPL}/'*.qcow2 1>/dev/null 2>&1; then
            for f in '${KVMTPL}/'*.qcow2; do
                name=\$(basename \"\$f\" .qcow2)
                size=\$(du -h \"\$f\" | cut -f1)
                printf '  %-30s  %s\n' \"\$name\" \"\$size\"
            done
        else
            echo '  (none — convert VMware templates with: just convert <template>)'
        fi
    "
    ;;

install)
    os="${1:-}"; shift 2>/dev/null || true
    name="${1:-}"; shift 2>/dev/null || true
    args="${*}"

    if [ -z "$name" ]; then
        echo "Usage: just install <os> <name> [--bridge|--no-network]"
        exit 1
    fi

    if [ -z "${os_iso[$os]+x}" ]; then
        echo "Unknown OS: $os"
        echo "Supported: $(echo "${!os_iso[@]}" | tr ' ' '\n' | sort | tr '\n' ' ')"
        ssh "$HOST" "ls '$ISODIR'/*.iso 2>/dev/null | xargs -I{} basename {}"
        exit 1
    fi

    iso="${os_iso[$os]}"; mem="${os_mem[$os]}"; cpus="${os_cpus[$os]}"
    disk_gb="${os_disk[$os]}"; os_variant="${os_variant[$os]}"
    kvm_extra="${os_kvm_extra[$os]}"; product_key="${os_key[$os]}"
    arch="${os_arch[$os]:-}"
    if [ -n "$arch" ]; then
        kvm_extra="$kvm_extra --virt-type qemu --arch $arch"
        # TCG doesn't support hyperv features that os-variant injects, so skip os-variant
        os_variant="generic"
    fi
    iso_path="${ISODIR}/${iso}"

    if ! ssh "$HOST" "test -f '$iso_path'" 2>/dev/null; then
        echo "Error: ISO not found: $iso_path"
        exit 1
    fi

    network="hostonly"
    [[ "$args" == *"no-network"* || "$args" == *"none"* ]] && network="none"
    [[ "$args" == *"bridge"* ]] && network="bridge"

    echo "[kvm] Installing $os as '$name' (${mem}MB RAM, ${cpus} CPU, ${disk_gb}GB disk)"

    disk_path="${KVMDIR}/instances/${name}.qcow2"

    if ssh "$HOST" "virsh dominfo '$name'" &>/dev/null; then
        echo "Error: KVM VM '$name' already exists"
        exit 1
    fi
    if ssh "$HOST" "test -f '$disk_path'" 2>/dev/null; then
        echo "Error: Disk already exists: $disk_path"
        exit 1
    fi

    ssh "$HOST" "mkdir -p '${KVMDIR}/instances'"

    echo "Creating ${disk_gb}GB disk..."
    ssh "$HOST" "qemu-img create -f qcow2 '$disk_path' ${disk_gb}G"

    # Pick NIC model based on OS (XP lacks virtio/e1000 drivers)
    case "$os" in
        winxp*) nic_model="rtl8139" ;;
        *)      nic_model="virtio"  ;;
    esac

    case "$network" in
        bridge)   network_args="--network bridge=$KVM_BRIDGE,model=$nic_model" ;;
        hostonly) network_args="--network bridge=$KVM_HOSTONLY,model=$nic_model" ;;
        none)     network_args="" ;;
    esac

    echo "Starting installer..."
    ssh "$HOST" "virt-install \
        --name '$name' \
        --memory $mem \
        --vcpus $cpus \
        --disk path='$disk_path',format=qcow2 \
        --cdrom '$iso_path' \
        --boot cdrom,hd \
        --os-variant '$os_variant' \
        --graphics spice,listen=0.0.0.0 \
        $network_args \
        $kvm_extra \
        --noautoconsole"

    echo ""
    echo "VM '$name' started — OS installer will boot from ISO."
    [ -n "$product_key" ] && echo "Product key: $product_key"
    echo "Connect: just connect $name"
    ;;

launch)
    base="$1"; shift
    name="$1"; shift
    args="${*}"

    network="hostonly"
    use_efi=false
    [[ "$args" == *"no-network"* || "$args" == *"none"* ]] && network="none"
    [[ "$args" == *"bridge"* ]] && network="bridge"
    [[ "$args" == *"efi"* ]] && use_efi=true

    tpl_img="${KVMTPL}/${base}.qcow2"
    disk="${KVMDIR}/instances/${name}.qcow2"

    if ! ssh "$HOST" "test -f '$tpl_img'" 2>/dev/null; then
        echo "Error: Template not found: $tpl_img"
        echo "Run: just convert $base"
        exit 1
    fi

    if ssh "$HOST" "virsh dominfo '$name'" 2>/dev/null; then
        echo "Error: KVM VM '$name' already exists"
        echo "Use: just stop $name"
        exit 1
    fi

    if ssh "$HOST" "test -f '$disk'" 2>/dev/null; then
        echo "Error: Instance disk already exists: $disk"
        echo "Remove it first or use a different name."
        exit 1
    fi

    echo "Creating instance disk: $disk (backing: $tpl_img)"
    ssh "$HOST" "qemu-img create -f qcow2 -b '$tpl_img' -F qcow2 '$disk'"

    # Generate deterministic MAC from VM name (52:54:00 = QEMU OUI prefix)
    mac_suffix=$(echo -n "$name" | md5sum | sed 's/\(..\)\(..\)\(..\).*/\1:\2:\3/')
    mac="52:54:00:$mac_suffix"

    # Determine bridge for requested network mode
    case "$network" in
        bridge)   bridge="$KVM_BRIDGE"   ;;
        hostonly) bridge="$KVM_HOSTONLY"  ;;
        none)     bridge=""              ;;
    esac

    tpl_xml="${KVMTPL}/${base}.xml"
    if ssh "$HOST" "test -f '$tpl_xml'" 2>/dev/null; then
        # Clone hardware config from saved XML (preserves PCI topology, controllers, etc.)
        echo "Using saved XML template: $tpl_xml"
        ssh "$HOST" "
            xml=\$(cat '$tpl_xml')
            # Replace VM name
            xml=\$(echo \"\$xml\" | sed 's|<name>[^<]*</name>|<name>$name</name>|')
            # Replace UUID (generate new)
            new_uuid=\$(cat /proc/sys/kernel/random/uuid)
            xml=\$(echo \"\$xml\" | sed \"s|<uuid>[^<]*</uuid>|<uuid>\$new_uuid</uuid>|\")
            # Replace disk path
            xml=\$(echo \"\$xml\" | sed \"s|<source file='[^']*${base}[^']*\\.qcow2'|<source file='$disk'|\")
            # Replace MAC address
            xml=\$(echo \"\$xml\" | sed \"s|<mac address='[^']*'/>|<mac address='$mac'/>|\")
            # Handle network
            if [ -n '$bridge' ]; then
                xml=\$(echo \"\$xml\" | sed \"s|<source bridge='[^']*'/>|<source bridge='$bridge'/>|\")
            else
                xml=\$(echo \"\$xml\" | sed '/<interface/,/<\/interface>/d')
            fi
            # Remove CDROM source (template may have had ISO mounted)
            xml=\$(echo \"\$xml\" | sed '/<disk.*device=.cdrom/,/<\/disk>/{s|<source file=[^/]*/>||}')
            # Let libvirt auto-assign SPICE port (avoid conflicts)
            xml=\$(echo \"\$xml\" | sed \"s|port='[0-9]*' autoport|port='-1' autoport|\" | sed \"s|autoport='no'|autoport='yes'|\")
            echo \"\$xml\" > /tmp/vivi-launch-$$.xml
            virsh define /tmp/vivi-launch-$$.xml >/dev/null
            rm -f /tmp/vivi-launch-$$.xml
        "
        echo "Starting KVM VM '$name' (cloned from $base, mac: $mac)..."
        ssh "$HOST" "virsh start '$name'"
    else
        # No saved XML — use virt-install (fresh install or first-time template)
        # Pick NIC model based on OS
        # XP needs rtl8139, Windows needs e1000 (no built-in virtio drivers)
        # Linux gets virtio (kernel has driver)
        case "$base" in
            winxp*)          nic_model="rtl8139" ;;
            win*)            nic_model="e1000"   ;;
            *)               nic_model="virtio"  ;;
        esac

        case "$network" in
            bridge)   network_args="--network bridge=$KVM_BRIDGE,model=$nic_model" ;;
            hostonly) network_args="--network bridge=$KVM_HOSTONLY,model=$nic_model" ;;
            none)     network_args="" ;;
        esac

        # Tune VM settings based on OS type
        os_variant="win10"
        extra_args=""
        case "$base" in
            winxpx64*|winxp64*)
                os_variant="winxp"
                extra_args="--machine pc-i440fx-2.11"
                ;;
            winxp-i386*)
                os_variant="generic"
                extra_args="--machine pc-i440fx-2.11 --virt-type qemu --arch i686"
                ;;
            winxp*)
                os_variant="winxp"
                extra_args="--machine pc-i440fx-2.11"
                ;;
            win81*)
                os_variant="win8.1"
                ;;
            win11*)
                os_variant="win11"
                ;;
        esac

        # EFI firmware (for templates converted from EFI-based VMware VMs)
        efi_args=""
        if $use_efi; then
            vars_src="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
            vars_dst="${KVMDIR}/instances/${name}-VARS.fd"
            ssh "$HOST" "cp '$vars_src' '$vars_dst'"
            efi_args="--boot uefi --machine q35"
        fi

        echo "Starting KVM VM '$name' (os: $os_variant, mac: $mac$(if $use_efi; then echo ', efi'; fi))..."
        ssh "$HOST" "virt-install \
            --name '$name' \
            --memory 4096 \
            --vcpus 2 \
            --disk path='$disk',format=qcow2 \
            --import \
            --os-variant '$os_variant' \
            --graphics spice,listen=0.0.0.0 \
            --mac '$mac' \
            $network_args \
            $extra_args \
            $efi_args \
            --noautoconsole"
    fi

    echo ""
    echo "KVM VM '$name' started."
    echo "Connect: just connect $name"
    ;;

connect)
    name="$1"
    if ! ssh "$HOST" "virsh dominfo '$name'" &>/dev/null; then
        echo "Error: KVM VM '$name' not found"
        ssh "$HOST" "virsh list --all 2>/dev/null" || true
        exit 1
    fi

    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "unknown")
    if [[ "$state" != *"running"* ]]; then
        echo "VM not running, starting..."
        ssh "$HOST" "virsh start '$name'"
        sleep 2
    fi

    port=$(ssh "$HOST" "virsh domdisplay '$name' 2>/dev/null | grep -oP ':\K[0-9]+'")
    if [ -z "$port" ]; then
        echo "Error: Could not get SPICE port for '$name'."
        exit 1
    fi
    echo "Connecting to '$name' via SPICE on port $port..."
    remmina -c "spice://${HOST_IP_VAL}:${port}" &
    ;;

screenshot)
    name="$1"; output="${2:-}"
    if ! ssh "$HOST" "virsh dominfo '$name'" &>/dev/null; then
        echo "Error: KVM VM '$name' not found"
        exit 1
    fi
    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "unknown")
    if [[ "$state" != *"running"* ]]; then
        echo "Error: VM '$name' is not running"
        exit 1
    fi
    remote_file="/tmp/screenshot-${name}-$$.png"
    ssh "$HOST" "virsh screenshot '$name' --file '$remote_file'" >/dev/null
    if [ -z "$output" ]; then
        output="${name}-$(date +%Y%m%d-%H%M%S).png"
    fi
    scp -q "$HOST:$remote_file" "$output"
    ssh "$HOST" "rm -f '$remote_file'"
    echo "Screenshot saved: $output"
    ;;

start)
    name="$1"; shift
    args="${*}"

    if ! ssh "$HOST" "virsh dominfo '$name'" &>/dev/null; then
        echo "Error: KVM VM '$name' not found"
        ssh "$HOST" "virsh list --all 2>/dev/null" || true
        exit 1
    fi

    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "unknown")
    if [[ "$state" == *"running"* ]]; then
        echo "'$name' is already running"
        exit 0
    fi

    # If network flag given, edit XML before starting
    if [[ -n "$args" ]]; then
        network=""
        [[ "$args" == *"bridge"* ]] && network="bridge"
        [[ "$args" == *"hostonly"* ]] && network="hostonly"
        [[ "$args" == *"no-network"* || "$args" == *"none"* ]] && network="none"

        if [ -n "$network" ]; then
            echo "Switching network to: $network"
            case "$network" in
                bridge)
                    ssh "$HOST" "
                        xml=\$(virsh dumpxml --inactive '$name')
                        if echo \"\$xml\" | grep -q '<interface'; then
                            echo \"\$xml\" | sed \"s|<source bridge='[^']*'/>|<source bridge='$KVM_BRIDGE'/>|\" > /tmp/vivi-start-$$.xml
                        else
                            echo \"\$xml\" | sed 's|</devices>|<interface type=\"bridge\"><source bridge=\"$KVM_BRIDGE\"/><model type=\"e1000\"/></interface></devices>|' > /tmp/vivi-start-$$.xml
                        fi
                        virsh define /tmp/vivi-start-$$.xml >/dev/null
                        rm -f /tmp/vivi-start-$$.xml
                    "
                    ;;
                hostonly)
                    ssh "$HOST" "
                        xml=\$(virsh dumpxml --inactive '$name')
                        if echo \"\$xml\" | grep -q '<interface'; then
                            echo \"\$xml\" | sed \"s|<source bridge='[^']*'/>|<source bridge='$KVM_HOSTONLY'/>|\" > /tmp/vivi-start-$$.xml
                        else
                            echo \"\$xml\" | sed 's|</devices>|<interface type=\"bridge\"><source bridge=\"$KVM_HOSTONLY\"/><model type=\"e1000\"/></interface></devices>|' > /tmp/vivi-start-$$.xml
                        fi
                        virsh define /tmp/vivi-start-$$.xml >/dev/null
                        rm -f /tmp/vivi-start-$$.xml
                    "
                    ;;
                none)
                    ssh "$HOST" "
                        virsh dumpxml --inactive '$name' | sed '/<interface/,/<\/interface>/d' > /tmp/vivi-start-$$.xml
                        virsh define /tmp/vivi-start-$$.xml >/dev/null
                        rm -f /tmp/vivi-start-$$.xml
                    "
                    ;;
            esac
        fi
    fi

    echo "Starting '$name'..."
    ssh "$HOST" "virsh start '$name'"
    echo "Running."
    echo "Connect: just connect $name"
    ;;

rename)
    old="$1"; new="$2"
    if [ -z "$old" ] || [ -z "$new" ]; then
        echo "Usage: just rename <old-name> <new-name>"
        exit 1
    fi

    tpl_old="${KVMTPL}/${old}.qcow2"
    tpl_new="${KVMTPL}/${new}.qcow2"
    inst_old="${KVMDIR}/instances/${old}.qcow2"
    inst_new="${KVMDIR}/instances/${new}.qcow2"

    # Check if it's a template
    if ssh "$HOST" "test -f '$tpl_old'" 2>/dev/null; then
        if ssh "$HOST" "test -f '$tpl_new'" 2>/dev/null; then
            echo "Error: Template '$new' already exists"
            exit 1
        fi
        ssh "$HOST" "mv '$tpl_old' '$tpl_new'"
        # Update any instances that use this template as backing file
        for inst in $(ssh "$HOST" "ls ${KVMDIR}/instances/*.qcow2 2>/dev/null"); do
            backing=$(ssh "$HOST" "qemu-img info '$inst' 2>/dev/null | grep 'backing file:' | sed 's/.*backing file: //'")
            if [ "$backing" = "$tpl_old" ]; then
                ssh "$HOST" "qemu-img rebase -u -b '$tpl_new' -F qcow2 '$inst'"
                echo "Updated backing file for $(basename "$inst")"
            fi
        done
        echo "Renamed template '$old' -> '$new'"
        exit 0
    fi

    # Check if it's an instance
    if ssh "$HOST" "virsh dominfo '$old'" &>/dev/null; then
        state=$(ssh "$HOST" "virsh domstate '$old' 2>/dev/null" || echo "unknown")
        if [[ "$state" == *"running"* ]]; then
            echo "Error: VM '$old' is running. Shut it down first: just shutdown $old"
            exit 1
        fi
        if ssh "$HOST" "test -f '$inst_new'" 2>/dev/null; then
            echo "Error: Instance disk '$new' already exists"
            exit 1
        fi
        ssh "$HOST" "virsh domrename '$old' '$new'"
        ssh "$HOST" "mv '$inst_old' '$inst_new'"
        ssh "$HOST" "virsh dumpxml --inactive '$new' > /tmp/rename-$$.xml && sed -i 's|${old}.qcow2|${new}.qcow2|g' /tmp/rename-$$.xml && virsh define /tmp/rename-$$.xml && rm -f /tmp/rename-$$.xml"
        echo "Renamed instance '$old' -> '$new'"
        exit 0
    fi

    echo "Error: '$old' not found as template or instance"
    exit 1
    ;;

shutdown)
    name="$1"
    if ! ssh "$HOST" "virsh dominfo '$name'" &>/dev/null; then
        echo "Error: KVM VM '$name' not found"
        exit 1
    fi
    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "unknown")
    if [[ "$state" != *"running"* ]]; then
        echo "'$name' is already shut off"
        exit 0
    fi
    echo "Sending ACPI shutdown to '$name'..."
    ssh "$HOST" "virsh shutdown '$name'"
    for i in $(seq 1 30); do
        sleep 2
        state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "unknown")
        if [[ "$state" == *"shut off"* ]]; then
            echo "'$name' shut down gracefully."
            exit 0
        fi
    done
    echo "Warning: '$name' did not shut down within 60s. Use 'just destroy $name' to force."
    ;;

stop)
    name="$1"; shift
    args="${*}"

    if ! ssh "$HOST" "virsh dominfo '$name'" &>/dev/null; then
        echo "Error: KVM VM '$name' not found"
        ssh "$HOST" "virsh list --all 2>/dev/null" || true
        exit 1
    fi

    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "shut off")
    if [[ "$state" == *"running"* ]]; then
        echo "WARNING: Force-killing a running VM can corrupt its filesystem (especially XP/NTFS)."
        echo "Attempting graceful shutdown first (telnet, then ACPI)..."
        echo ""
    fi

    kvm_stop_vm "$name" true

    ssh "$HOST" "virsh undefine '$name' --snapshots-metadata" 2>/dev/null || true

    disk="${KVMDIR}/instances/${name}.qcow2"
    if [[ "$args" == *"--keep"* ]]; then
        echo "Keeping disk: $disk"
    else
        ssh "$HOST" "rm -f '$disk'" 2>/dev/null || true
        echo "Removed disk: $disk"
    fi

    echo "KVM VM '$name' stopped and removed."
    ;;

destroy)
    name="$1"
    disk="${KVMDIR}/instances/${name}.qcow2"

    if ! ssh "$HOST" "virsh dominfo '$name'" &>/dev/null && ! ssh "$HOST" "test -f '$disk'" 2>/dev/null; then
        echo "Error: KVM VM '$name' not found"
        ssh "$HOST" "virsh list --all 2>/dev/null" || true
        exit 1
    fi

    echo "This will permanently delete KVM VM '$name'"
    read -p "Continue? [y/N] " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted."
        exit 0
    fi

    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "shut off")
    if [[ "$state" == *"running"* ]]; then
        echo "Stopping VM..."
        ssh "$HOST" "virsh destroy '$name'" 2>/dev/null || true
    fi

    ssh "$HOST" "virsh undefine '$name' --snapshots-metadata" 2>/dev/null || true
    ssh "$HOST" "rm -f '$disk'" 2>/dev/null || true
    echo "Destroyed KVM VM '$name'."
    ;;

snapshot)
    name="$1"; shift
    args="$*"
    subcmd="${args%% *}"
    rest="${args#* }"
    [ "$subcmd" = "$rest" ] && rest=""

    if ! ssh "$HOST" "virsh dominfo '$name'" &>/dev/null; then
        echo "Error: KVM VM '$name' not found"
        ssh "$HOST" "virsh list --all 2>/dev/null" || true
        exit 1
    fi

    case "$subcmd" in
        create)
            snap="${rest:-$(date +%Y%m%d-%H%M%S)}"
            echo "Creating snapshot '$snap'..."
            ssh "$HOST" "virsh snapshot-create-as '$name' '$snap'"
            echo "Snapshot '$snap' created."
            ;;
        list)
            ssh "$HOST" "virsh snapshot-list '$name'"
            ;;
        revert)
            if [ -z "$rest" ]; then
                echo "Usage: just snapshot $name revert <snapshot>"
                echo ""; ssh "$HOST" "virsh snapshot-list '$name'"
                exit 1
            fi
            echo "Reverting to '$rest'..."
            ssh "$HOST" "virsh snapshot-revert '$name' '$rest'"
            echo "Reverted."
            ;;
        delete)
            if [ -z "$rest" ]; then
                echo "Usage: just snapshot $name delete <snapshot>"
                echo ""; ssh "$HOST" "virsh snapshot-list '$name'"
                exit 1
            fi
            echo "Deleting snapshot '$rest'..."
            ssh "$HOST" "virsh snapshot-delete '$name' '$rest'"
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
    shift 2>/dev/null || true
    force="${1:-}"

    src_disk="${KVMDIR}/instances/${name}.qcow2"
    if ! ssh "$HOST" "test -f '$src_disk'" 2>/dev/null; then
        echo "Error: No disk found for '$name' at $src_disk"
        exit 1
    fi

    dest_disk="${KVMTPL}/${template}.qcow2"
    if ssh "$HOST" "test -f '$dest_disk'" 2>/dev/null; then
        old_size=$(ssh "$HOST" "du -h '$dest_disk' 2>/dev/null | cut -f1")
        if [ "$force" = "--force" ] || [ "$force" = "-f" ]; then
            echo "Overwriting template '$template' ($old_size)."
        else
            echo "Template '$template' already exists ($old_size)."
            read -p "Overwrite? [y/N] " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "Aborted."
                exit 0
            fi
        fi
    fi

    kvm_stop_vm "$name"

    ssh "$HOST" "mkdir -p '${KVMTPL}'"

    echo "Converting to standalone template (this may take a few minutes)..."
    tmp_disk="${dest_disk}.tmp"
    ssh "$HOST" "rm -f '$tmp_disk'"
    ssh "$HOST" "qemu-img convert -p -f qcow2 -O qcow2 '$src_disk' '$tmp_disk'"
    ssh "$HOST" "mv -f '$tmp_disk' '$dest_disk'"

    # Save VM XML as template (used by launch to preserve hardware config)
    dest_xml="${KVMTPL}/${template}.xml"
    echo "Saving VM XML template..."
    ssh "$HOST" "virsh dumpxml --inactive '$name' > '$dest_xml'"

    size=$(ssh "$HOST" "du -h '$dest_disk' 2>/dev/null | cut -f1")
    echo ""
    echo "Saved template '$template' ($size) + XML"
    echo "Use with: just launch $template <name>"
    ;;

cdrom)
    subcmd="${1:-}"; shift 2>/dev/null || true
    TOOLS_ISO_DIR="${ISODIR}/tools"

    # Helper: resolve ISO name to path (tools/ first, then ISODIR, then literal)
    resolve_iso() {
        local name="$1"
        if [[ "$name" = /* ]] && ssh "$HOST" "test -f '$name'" 2>/dev/null; then
            echo "$name"; return 0
        fi
        local base="${name%.iso}"
        if ssh "$HOST" "test -f '${TOOLS_ISO_DIR}/${base}.iso'" 2>/dev/null; then
            echo "${TOOLS_ISO_DIR}/${base}.iso"; return 0
        fi
        if ssh "$HOST" "test -f '${ISODIR}/${base}.iso'" 2>/dev/null; then
            echo "${ISODIR}/${base}.iso"; return 0
        fi
        return 1
    }

    # Helper: stop VM and wait until fully shut off
    stop_vm() {
        local vm="$1" state
        state=$(ssh "$HOST" "virsh domstate '$vm' 2>/dev/null" || echo "shut off")
        [[ "$state" == *"shut off"* ]] && return 0
        ssh "$HOST" "virsh shutdown '$vm'" 2>/dev/null || true
        for i in $(seq 1 20); do
            state=$(ssh "$HOST" "virsh domstate '$vm' 2>/dev/null" || echo "shut off")
            [[ "$state" == *"shut off"* ]] && return 0
            sleep 2
        done
        echo "Graceful shutdown timed out, forcing off..."
        ssh "$HOST" "virsh destroy '$vm'" 2>/dev/null || true
        sleep 2
    }

    # Helper: attach ISO to VM
    attach_iso() {
        local vm="$1" iso_path="$2"
        local cdrom_dev
        cdrom_dev=$(ssh "$HOST" "virsh dumpxml '$vm' 2>/dev/null | xmllint --xpath \"string(//disk[@device='cdrom']/target/@dev)\" - 2>/dev/null")

        if [ -n "$cdrom_dev" ]; then
            local state
            state=$(ssh "$HOST" "virsh domstate '$vm' 2>/dev/null" || echo "unknown")
            if [[ "$state" == *"running"* ]]; then
                if ssh "$HOST" "virsh change-media '$vm' '$cdrom_dev' '$iso_path' --update" 2>/dev/null; then
                    :
                else
                    echo "Stopping VM to change media..."
                    stop_vm "$vm"
                    ssh "$HOST" "virsh change-media '$vm' '$cdrom_dev' '$iso_path' --update --config"
                    echo "Starting VM..."
                    ssh "$HOST" "virsh start '$vm'"
                fi
            else
                ssh "$HOST" "virsh change-media '$vm' '$cdrom_dev' '$iso_path' --update --config"
                echo "Starting VM..."
                ssh "$HOST" "virsh start '$vm'"
            fi
        else
            echo "No CD-ROM device, stopping VM to add one..."
            stop_vm "$vm"
            ssh "$HOST" "virsh attach-disk '$vm' '$iso_path' hdc --type cdrom --mode readonly --config"
            echo "Starting VM..."
            ssh "$HOST" "virsh start '$vm'"
        fi
    }

    case "$subcmd" in
        list)
            echo "=== Tool ISOs (${TOOLS_ISO_DIR}/) ==="
            ssh "$HOST" "ls '${TOOLS_ISO_DIR}'/*.iso 2>/dev/null" | while read -r f; do
                size=$(ssh -n "$HOST" "du -h '$f' | cut -f1")
                printf '  %-30s  %s\n' "$(basename "${f%.iso}")" "$size"
            done || echo "  (none — use 'just cdrom prepare <name> <path>' to create)"
            echo ""
            echo "=== OS ISOs (${ISODIR}/) ==="
            ssh "$HOST" "ls '${ISODIR}'/*.iso 2>/dev/null" | while read -r f; do
                size=$(ssh -n "$HOST" "du -h '$f' | cut -f1")
                printf '  %-50s  %s\n' "$(basename "$f")" "$size"
            done
            ;;

        prepare)
            name="${1:-}"; shift 2>/dev/null || true
            src="${1:-}"; shift 2>/dev/null || true
            if [ -z "$name" ] || [ -z "$src" ]; then
                echo "Usage: just cdrom prepare <name> <path>"
                echo "  Build an ISO from a directory or file and save as a named tool ISO."
                echo "  Example: just cdrom prepare xptools /mnt/ext/Installation_files/xp-tools"
                exit 1
            fi
            iso_out="${TOOLS_ISO_DIR}/${name}.iso"
            ssh "$HOST" "mkdir -p '${TOOLS_ISO_DIR}'"
            if ssh "$HOST" "test -d '$src'" 2>/dev/null; then
                echo "Building ISO from directory: $src"
                ssh "$HOST" "genisoimage -o '$iso_out' -J -R -V '${name}' '$src'"
            elif ssh "$HOST" "test -f '$src'" 2>/dev/null; then
                echo "Building ISO from file: $src"
                ssh "$HOST" "tmpdir=\$(mktemp -d) && cp '$src' \"\$tmpdir/\" && genisoimage -o '$iso_out' -J -R -V '${name}' \"\$tmpdir\" && rm -rf \"\$tmpdir\""
            else
                echo "Error: path not found on host: $src"
                exit 1
            fi
            size=$(ssh "$HOST" "du -h '$iso_out' | cut -f1")
            echo "Created: $iso_out ($size)"
            echo "Mount with: just cdrom mount <vm> $name"
            ;;

        mount)
            vm="${1:-}"; shift 2>/dev/null || true
            iso_name="${1:-}"; shift 2>/dev/null || true
            if [ -z "$vm" ] || [ -z "$iso_name" ]; then
                echo "Usage: just cdrom mount <vm> <name>"
                echo "  Mount a tool ISO or OS ISO on a VM."
                echo "  <name> is resolved: tools/<name>.iso → <ISODIR>/<name>.iso → literal path"
                exit 1
            fi
            iso_path=$(resolve_iso "$iso_name") || {
                echo "Error: ISO not found: $iso_name"
                echo "Run 'just cdrom list' to see available ISOs."
                exit 1
            }
            attach_iso "$vm" "$iso_path"
            echo "Mounted $(basename "$iso_path") on '$vm'."
            ;;

        eject)
            vm="${1:-}"
            if [ -z "$vm" ]; then
                echo "Usage: just cdrom eject <vm>"
                exit 1
            fi
            cdrom_dev=$(ssh "$HOST" "virsh dumpxml '$vm' 2>/dev/null | xmllint --xpath \"string(//disk[@device='cdrom']/target/@dev)\" - 2>/dev/null")
            if [ -z "$cdrom_dev" ]; then
                echo "No CD-ROM device found."
            else
                ssh "$HOST" "virsh change-media '$vm' '$cdrom_dev' --eject" 2>/dev/null || true
            fi
            echo "CD-ROM ejected."
            ;;

        *)
            echo "Usage: just cdrom list|prepare|mount|eject [args]"
            echo ""
            echo "  list                        List available tool and OS ISOs"
            echo "  prepare <name> <path>       Build ISO from directory/file, save as tool ISO"
            echo "  mount <vm> <name>           Mount ISO on VM (tool ISO → OS ISO → literal path)"
            echo "  eject <vm>                  Eject CD-ROM from VM"
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
    ssh "$HOST" "
        echo '=== KVM VMs ==='
        virsh list --all 2>/dev/null || echo '  (libvirtd not running or virsh not installed)'

        echo ''
        echo '=== QEMU standalone VMs (ARM etc.) ==='
        qemu_procs=\$(ps -eo pid,args 2>/dev/null | grep 'qemu-system-' | grep -v grep | grep -v libguestfs || true)
        if [ -n \"\$qemu_procs\" ]; then
            echo \"\$qemu_procs\" | while read -r pid rest; do
                arch=\$(echo \"\$rest\" | grep -oP 'qemu-system-\K\S+')
                img=\$(echo \"\$rest\" | grep -oP 'file=\K[^,]+\.qcow2' | head -1)
                printf '  PID %-8s  %-10s  %s\n' \"\$pid\" \"\$arch\" \"\$(basename \"\$img\" 2>/dev/null || echo n/a)\"
            done
        else
            echo '  (none running)'
        fi

        echo ''
        tpl_free=\$(df -h '${KVMTPL}' 2>/dev/null | awk 'NR==2{print \$4}')
        echo \"=== Templates (${KVMTPL}/) — \${tpl_free:-n/a} free ===\"
        if ls '${KVMTPL}/'*.qcow2 1>/dev/null 2>&1; then
            for f in '${KVMTPL}/'*.qcow2; do
                size=\$(du -h \"\$f\" | cut -f1)
                vsize=\$(qemu-img info \"\$f\" 2>/dev/null | grep 'virtual size' | awk '{print \$3, \$4}' || echo 'n/a')
                created=\$(stat -c '%y' \"\$f\" 2>/dev/null | cut -d' ' -f1 || echo 'n/a')
                printf '  %-30s  %s (virtual: %s)  %s\n' \"\$(basename \$f)\" \"\$size\" \"\$vsize\" \"\$created\"
            done
        else
            echo '  (none)'
        fi

        echo ''
        inst_free=\$(df -h '${KVMDIR}/instances' 2>/dev/null | awk 'NR==2{print \$4}')
        echo \"=== Instances (${KVMDIR}/instances/) — \${inst_free:-n/a} free ===\"
        if ls '${KVMDIR}/instances/'*.qcow2 1>/dev/null 2>&1; then
            for f in '${KVMDIR}/instances/'*.qcow2; do
                size=\$(du -h \"\$f\" | cut -f1)
                backing=\$(qemu-img info -U \"\$f\" 2>/dev/null | grep '^backing file:' | sed 's/^backing file: //' || echo 'n/a')
                printf '  %-30s  %s (backing: %s)\n' \"\$(basename \$f)\" \"\$size\" \"\$(basename \$backing 2>/dev/null || echo n/a)\"
            done
        else
            echo '  (none)'
        fi

        echo ''
        echo '=== Disk Usage ==='
        for d in '${KVMTPL}' '${KVMDIR}'/instances; do
            [ -d \"\$d\" ] && du -sh \"\$d\" 2>/dev/null
        done
        if [ -d '${KVMDIR}/mnt' ]; then
            mounts=\$(find '${KVMDIR}/mnt' -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
            [ \"\$mounts\" -gt 0 ] && echo \"\${mounts} mounted image(s) in ${KVMDIR}/mnt/\"
        fi
        [ -d '${KVMDIR}' ] || echo '  KVM directories not yet created'
    "
    ;;

inspect)
    name="$1"; shift
    args="$*"
    subcmd="${args%% *}"
    rest="${args#* }"
    [ "$subcmd" = "$rest" ] && rest=""

    img="${KVMDIR}/instances/${name}.qcow2"
    mntdir="${KVMDIR}/mnt/${name}-live"
    nbd_dev="/dev/nbd0"

    if ! ssh "$HOST" "test -f '$img'" 2>/dev/null; then
        echo "Error: Instance image not found: $img"
        echo "Available instances:"
        ssh "$HOST" "ls ${KVMDIR}/instances/*.qcow2 2>/dev/null | sed 's|.*/||;s|\.qcow2||'" || echo "  (none)"
        exit 1
    fi

    case "$subcmd" in
        mount)
            if ssh "$HOST_ROOT_VAL" "mountpoint -q '$mntdir'" 2>/dev/null; then
                echo "Already mounted at $mntdir"
                exit 0
            fi
            nbd_connect "$img" "$nbd_dev"
            ssh "$HOST_ROOT_VAL" "mkdir -p '$mntdir'"
            echo "Mounting ${nbd_dev}p1 at $mntdir (read-only)..."
            ssh "$HOST_ROOT_VAL" "mount -o ro,norecovery ${nbd_dev}p1 '$mntdir'" || \
                ssh "$HOST_ROOT_VAL" "ntfs-3g -o ro ${nbd_dev}p1 '$mntdir'" || {
                    echo "Error: mount failed. Trying with ntfs3..."
                    ssh "$HOST_ROOT_VAL" "mount -t ntfs3 -o ro ${nbd_dev}p1 '$mntdir'"
                }
            echo "Mounted. Browse with: just for-inspect $name ls /"
            ;;
        umount)
            nbd_disconnect "$mntdir" "$nbd_dev"
            ;;
        ls)
            path="${rest:-/}"
            if ! ssh "$HOST_ROOT_VAL" "mountpoint -q '$mntdir'" 2>/dev/null; then
                nbd_connect "$img" "$nbd_dev"
                ssh "$HOST_ROOT_VAL" "mkdir -p '$mntdir'"
                echo "Auto-mounting ${nbd_dev}p1 at $mntdir (read-only)..."
                ssh "$HOST_ROOT_VAL" "mount -o ro,norecovery ${nbd_dev}p1 '$mntdir'" || \
                    ssh "$HOST_ROOT_VAL" "ntfs-3g -o ro ${nbd_dev}p1 '$mntdir'" 2>/dev/null
            fi
            ssh "$HOST" "ls -la '${mntdir}${path}'"
            ;;
        info)
            echo "=== Instance Image Info ==="
            ssh "$HOST" "qemu-img info '$img'"
            echo ""
            echo "=== NBD Status ==="
            if nbd_connected "$nbd_dev"; then
                echo "Connected at $nbd_dev"
                ssh "$HOST_ROOT_VAL" "fdisk -l $nbd_dev 2>/dev/null" || true
            else
                echo "Not connected"
            fi
            echo ""
            echo "=== Mount Status ==="
            if ssh "$HOST_ROOT_VAL" "mountpoint -q '$mntdir'" 2>/dev/null; then
                echo "Mounted at $mntdir"
                ssh "$HOST_ROOT_VAL" "df -h '$mntdir'"
            else
                echo "Not mounted"
            fi
            ;;
        "")
            echo "Usage: just for-inspect <name> mount|umount|ls|info [path]"
            echo ""
            echo "  mount       Mount running instance disk read-only (via qemu-nbd --snapshot)"
            echo "  umount      Unmount and disconnect NBD"
            echo "  ls [path]   List files (auto-mounts if needed)"
            echo "  info        Show image, NBD, and mount info"
            echo ""
            echo "Safe while VM is running — uses a copy-on-write snapshot overlay."
            ;;
        *)
            echo "Unknown subcommand: $subcmd"
            echo "Usage: just for-inspect <name> mount|umount|ls|info [path]"
            exit 1
            ;;
    esac
    ;;

pull)
    name="$1"; shift
    vm_path="${1:?Usage: just for-pull <name> <vm-path> [local-dest]}"
    shift
    local_dest="${1:-.}"

    img="${KVMDIR}/instances/${name}.qcow2"
    mntdir="${KVMDIR}/mnt/${name}-live"
    nbd_dev="/dev/nbd0"

    # Auto-mount if not mounted
    if ! ssh "$HOST_ROOT_VAL" "mountpoint -q '$mntdir'" 2>/dev/null; then
        "$0" inspect "$name" mount
    fi

    src_path="${mntdir}${vm_path}"
    if ! ssh "$HOST" "test -e '$src_path'" 2>/dev/null; then
        echo "Error: Not found on VM: $vm_path"
        exit 1
    fi

    filename=$(basename "$vm_path")
    if [ -d "$local_dest" ]; then
        local_dest="${local_dest}/${filename}"
    fi

    echo "Pulling $vm_path -> $local_dest"
    scp "$HOST:${src_path}" "$local_dest"
    echo "Saved to $local_dest"
    ;;

inspect-registry)
    name="$1"; shift
    hive="${1:-all}"

    img="${KVMDIR}/instances/${name}.qcow2"
    mntdir="${KVMDIR}/mnt/${name}-live"
    nbd_dev="/dev/nbd0"

    if ! ssh "$HOST" "test -f '$img'" 2>/dev/null; then
        echo "Error: Instance image not found: $img"
        exit 1
    fi

    # Auto-mount if not mounted
    if ! ssh "$HOST_ROOT_VAL" "mountpoint -q '$mntdir'" 2>/dev/null; then
        echo "Auto-mounting via inspect..."
        "$0" inspect "$name" mount
    fi

    parse_hives "$hive" "$mntdir"
    echo "Tip: Run 'just for-inspect $name umount' when done."
    ;;

reset-password)
    # Reset Windows user password via offline SAM edit (chntpw)
    # Works on stopped instances or templates. VM must NOT be running.
    # Usage: reset-password <name-or-template> [username] [new-password]
    # If new-password is given, a startup script sets it on next boot.
    name="$1"; shift
    user="${1:-me}"
    newpass="${2:-}"

    # Find the qcow2: check instances first, then templates
    img="${KVMDIR}/instances/${name}.qcow2"
    if ! ssh "$HOST" "test -f '$img'" 2>/dev/null; then
        img="${KVMTPL}/${name}.qcow2"
        if ! ssh "$HOST" "test -f '$img'" 2>/dev/null; then
            echo "Error: No instance or template found for '$name'"
            echo "Instances: $(ssh "$HOST" "ls ${KVMDIR}/instances/*.qcow2 2>/dev/null | sed 's|.*/||;s|\.qcow2||' | tr '\n' ' '")"
            echo "Templates: $(ssh "$HOST" "ls ${KVMTPL}/*.qcow2 2>/dev/null | sed 's|.*/||;s|\.qcow2||' | tr '\n' ' '")"
            exit 1
        fi
        echo "Using template: $img"
    else
        echo "Using instance: $img"
    fi

    # Ensure VM is not running (qcow2 would be locked)
    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "shut off")
    if [[ "$state" == *"running"* ]]; then
        echo "Error: VM '$name' is running. Stop it first: just stop $name"
        exit 1
    fi

    # Also check no other instance is using this as a backing file
    nbd_dev="/dev/nbd0"
    mntdir="${KVMDIR}/mnt/${name}-pw"

    echo "Resetting password for user '$user'..."
    echo ""

    # Clean up any stale nbd mounts, then connect read-write
    ssh "$HOST_ROOT_VAL" "
        umount ${nbd_dev}p1 2>/dev/null || true
        qemu-nbd -d $nbd_dev 2>/dev/null || true
        sleep 2
        modprobe nbd max_part=8 2>/dev/null
        qemu-nbd --connect=$nbd_dev --format=qcow2 '$img'
        sleep 2
        partprobe $nbd_dev 2>/dev/null || true
        sleep 1
    "

    # Mount read-write with ntfs-3g
    ssh "$HOST_ROOT_VAL" "mkdir -p '$mntdir'"
    if ! ssh "$HOST_ROOT_VAL" "ntfs-3g ${nbd_dev}p1 '$mntdir'" 2>&1; then
        echo "Error: Failed to mount ${nbd_dev}p1"
        ssh "$HOST_ROOT_VAL" "qemu-nbd -d $nbd_dev" 2>/dev/null || true
        exit 1
    fi

    # Find SAM hive (XP vs Win10 paths)
    sam_path=""
    for p in "WINDOWS/system32/config/SAM" "Windows/System32/config/SAM"; do
        if ssh "$HOST_ROOT_VAL" "test -f '${mntdir}/${p}'" 2>/dev/null; then
            sam_path="${mntdir}/${p}"
            break
        fi
    done
    if [ -z "$sam_path" ]; then
        echo "Error: SAM hive not found"
        ssh "$HOST_ROOT_VAL" "umount '$mntdir'; qemu-nbd -d $nbd_dev" 2>/dev/null || true
        exit 1
    fi

    # Run chntpw to clear password (option 1 = clear, q = quit, y = write)
    # chntpw exits 2 on success (quirk), so don't treat it as error
    ssh "$HOST_ROOT_VAL" "cd '$(dirname "$sam_path")' && printf '1\nq\ny\n' | chntpw -u '$user' SAM" || true

    # If new password given, create a startup script to set it on next boot
    if [ -n "$newpass" ]; then
        echo ""
        echo "Creating startup script to set password on next boot..."
        # Try XP path first, then Win10
        for startup in \
            "${mntdir}/Documents and Settings/All Users/Start Menu/Programs/Startup" \
            "${mntdir}/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"; do
            if ssh "$HOST_ROOT_VAL" "test -d '$(dirname "$startup")'" 2>/dev/null; then
                ssh "$HOST_ROOT_VAL" "mkdir -p '$startup' && printf '@echo off\r\nnet user $user $newpass\r\ndel \"%%~f0\"\r\n' > '$startup/setpass.bat'"
                echo "  Created: setpass.bat (runs once, self-deletes)"
                break
            fi
        done
    fi

    # Cleanup — ensure nbd is fully released
    ssh "$HOST_ROOT_VAL" "
        umount '$mntdir' 2>/dev/null || umount -f '$mntdir' 2>/dev/null || true
        sleep 1
        qemu-nbd -d $nbd_dev
        sleep 1
        rmdir '$mntdir' 2>/dev/null || true
    "

    echo ""
    if [ -n "$newpass" ]; then
        echo "Password cleared for user '$user' in $img"
        echo "New password '$newpass' will be set on next boot via startup script."
    else
        echo "Password cleared for user '$user' in $img"
        echo "Boot the VM and set a new password with:"
        echo "  just telnet <name> 'net user $user <newpassword>'"
    fi
    ;;

registry)
    # Offline Windows registry operations via reged (chntpw suite)
    # VM must be stopped. Mounts disk read-write, operates on hive, unmounts.
    # Usage: vm-kvm.sh registry <name> import <hive> <regfile>
    #        vm-kvm.sh registry <name> export <hive> <key> [outfile]
    #        vm-kvm.sh registry <name> edit <hive>
    #   hive: SAM|SYSTEM|SOFTWARE|SECURITY|NTUSER|DEFAULT
    name="${1:-}"
    subcmd="${2:-}"
    hive_name="${3:-}"
    if [ -z "$name" ] || [ -z "$subcmd" ]; then
        echo "Usage:"
        echo "  registry <name> import <hive> <regfile>   Import .reg file into hive"
        echo "  registry <name> export <hive> <key> [out] Export key to .reg format"
        echo "  registry <name> edit <hive>               Interactive editor"
        echo ""
        echo "Hives: SAM, SYSTEM, SOFTWARE, SECURITY, NTUSER, DEFAULT"
        echo "VM must be stopped."
        exit 1
    fi
    shift 3 || true

    if [ -z "$hive_name" ]; then
        echo "Usage:"
        echo "  registry <name> import <hive> <regfile>   Import .reg file into hive"
        echo "  registry <name> export <hive> <key> [out] Export key to .reg format"
        echo "  registry <name> edit <hive>               Interactive editor"
        echo ""
        echo "Hives: SAM, SYSTEM, SOFTWARE, SECURITY, NTUSER, DEFAULT"
        echo "VM must be stopped."
        exit 1
    fi

    # Find qcow2 (instances first, then templates)
    img="${KVMDIR}/instances/${name}.qcow2"
    if ! ssh "$HOST" "test -f '$img'" 2>/dev/null; then
        img="${KVMTPL}/${name}.qcow2"
        if ! ssh "$HOST" "test -f '$img'" 2>/dev/null; then
            echo "Error: No instance or template found for '$name'"
            exit 1
        fi
    fi

    # Ensure VM is not running
    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "shut off")
    if [[ "$state" == *"running"* ]]; then
        echo "Error: VM '$name' is running. Stop it first."
        exit 1
    fi

    # Map hive name to path
    case "$hive_name" in
        SAM|SYSTEM|SOFTWARE|SECURITY|DEFAULT)
            hive_rel_candidates=("Windows/System32/config/$hive_name" "WINDOWS/system32/config/$hive_name")
            prefix="HKEY_LOCAL_MACHINE\\${hive_name}" ;;
        NTUSER)
            hive_rel_candidates=("Users/me/NTUSER.DAT" "Documents and Settings/me/NTUSER.DAT")
            prefix="HKEY_CURRENT_USER" ;;
        *)
            echo "Error: Unknown hive '$hive_name'. Use: SAM|SYSTEM|SOFTWARE|SECURITY|NTUSER|DEFAULT"
            exit 1 ;;
    esac

    nbd_dev="/dev/nbd0"
    mntdir="${KVMDIR}/mnt/${name}-reg"

    # Mount read-write
    echo "Mounting $name disk..."
    ssh "$HOST_ROOT_VAL" "
        umount ${nbd_dev}p* 2>/dev/null || true
        qemu-nbd -d $nbd_dev 2>/dev/null || true
        sleep 2
        modprobe nbd max_part=8 2>/dev/null || true
        qemu-nbd --connect=$nbd_dev --format=qcow2 '$img'
        sleep 2
        partprobe $nbd_dev 2>/dev/null || true
        sleep 1
    "

    # Find the Windows partition (try p1, p2, p3)
    ssh "$HOST_ROOT_VAL" "mkdir -p '$mntdir'"
    mounted=false
    for part in ${nbd_dev}p1 ${nbd_dev}p2 ${nbd_dev}p3; do
        if ssh "$HOST_ROOT_VAL" "ntfs-3g $part '$mntdir' 2>/dev/null"; then
            # Check if this partition has Windows
            for cand in "${hive_rel_candidates[@]}"; do
                if ssh "$HOST_ROOT_VAL" "test -f '${mntdir}/${cand}'" 2>/dev/null; then
                    hive_path="${mntdir}/${cand}"
                    mounted=true
                    break 2
                fi
            done
            ssh "$HOST_ROOT_VAL" "umount '$mntdir'" 2>/dev/null || true
        fi
    done

    if ! $mounted; then
        echo "Error: Could not find $hive_name hive on any partition"
        ssh "$HOST_ROOT_VAL" "qemu-nbd -d $nbd_dev" 2>/dev/null || true
        exit 1
    fi
    echo "Found hive: $hive_path"

    # Cleanup function
    reg_cleanup() {
        ssh "$HOST_ROOT_VAL" "
            umount '$mntdir' 2>/dev/null || umount -f '$mntdir' 2>/dev/null || true
            sleep 1
            qemu-nbd -d $nbd_dev
            sleep 1
            rmdir '$mntdir' 2>/dev/null || true
        "
    }

    case "$subcmd" in
        import)
            regfile="${1:?usage: registry <name> import <hive> <regfile>}"
            if [ ! -f "$regfile" ]; then
                echo "Error: File not found: $regfile"
                reg_cleanup
                exit 1
            fi
            echo "Importing $regfile into $hive_name..."
            scp -q "$regfile" "$HOST":/tmp/reg-import-$$.reg
            ssh "$HOST_ROOT_VAL" "reged -I -C '$hive_path' '$prefix' /tmp/reg-import-$$.reg"
            ssh "$HOST" "rm -f /tmp/reg-import-$$.reg"
            echo "Import complete."
            ;;
        export)
            # Remaining args: key [outfile]
            # Key may contain spaces, so if last arg looks like a file path, treat it as outfile
            all_args=("$@")
            if [ ${#all_args[@]} -eq 0 ]; then
                echo "usage: registry <name> export <hive> <key> [outfile]"
                reg_cleanup; exit 1
            fi
            # If last arg ends in .reg, it's the outfile
            last_arg="${all_args[${#all_args[@]}-1]}"
            if [[ "$last_arg" == *.reg ]] && [ ${#all_args[@]} -ge 2 ]; then
                outfile="$last_arg"
                key="${all_args[*]:0:${#all_args[@]}-1}"
            else
                outfile="/dev/stdout"
                key="${all_args[*]}"
            fi
            remote_out="/tmp/reg-export-$$.reg"
            ssh "$HOST_ROOT_VAL" "reged -x '$hive_path' '$prefix' '$key' '$remote_out'"
            if [ "$outfile" = "/dev/stdout" ]; then
                ssh "$HOST_ROOT_VAL" "cat '$remote_out'"
            else
                scp -q "$HOST":"$remote_out" "$outfile"
                echo "Exported to $outfile"
            fi
            ssh "$HOST_ROOT_VAL" "rm -f '$remote_out'"
            ;;
        edit)
            echo "Opening interactive registry editor..."
            echo "(Navigate with: cd, ls, cat. Set values with: ed. Quit: q, y to save)"
            echo ""
            ssh -t "$HOST_ROOT_VAL" "reged -e '$hive_path'"
            ;;
        *)
            echo "Unknown subcommand: $subcmd"
            echo "Use: import, export, or edit"
            reg_cleanup
            exit 1
            ;;
    esac

    reg_cleanup
    echo "Done."
    ;;

debug)
    # Usage: vm-kvm.sh debug <name> [port]
    # Attach GDB server to a running VM via QEMU monitor
    name="${1:?usage: vm-kvm.sh debug <name> [port]}"
    port="${2:-1234}"

    # Verify VM is running
    state=$(ssh "$HOST" "virsh domstate '$name' 2>/dev/null" || echo "unknown")
    if [[ "$state" != *"running"* ]]; then
        echo "Error: VM '$name' is not running (state: $state)" >&2
        exit 1
    fi

    echo "Attaching GDB server to '$name' on tcp::${port}..."
    result=$(ssh "$HOST" "virsh qemu-monitor-command '$name' --hmp 'gdbserver tcp::${port}'" 2>&1)
    echo "$result"

    if echo "$result" | grep -qi "error\|failed"; then
        echo "Failed to attach GDB server" >&2
        exit 1
    fi

    host_ip=$(echo "$HOST" | sed 's/.*@//')
    echo ""
    echo "GDB server listening on ${host_ip}:${port}"
    echo ""
    echo "Connect with:"
    echo "  gdb -ex 'target remote ${host_ip}:${port}'"
    echo "  IDA Pro: Debugger → Remote GDB debugger → ${host_ip}:${port}"
    echo "  radare2: r2 -d gdb://${host_ip}:${port}"
    ;;

*)
    echo "Unknown KVM action: $action" >&2
    exit 1
    ;;
esac
