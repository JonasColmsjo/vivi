host := if path_exists(".host") == "true" { trim(`cat .host`) } else { "tcentre1" }
HOST := if host == "tcentre2" { "tcentre2" } else { "tcentre1" }
VIVI := env_var("HOME") + "/repos/gizur-vivi"
PYTHON := env_var("HOME") + "/micromamba-base/bin/python3"

# List available targets (host=tcentre1 home [default], host=tcentre2 office)
default:
    @echo "host={{HOST}} (tcentre1=home [default], tcentre2=office)"
    @echo ""
    @just --list

# Show detailed usage for all targets
docs:
    @echo "VM Sandbox Manager — detailed usage"
    @echo "===================================="
    @echo "Set host with: just host=tcentre2 <target>"
    @echo "  tcentre1 = home server (default)"
    @echo "  tcentre2 = office server"
    @echo ""
    @echo "WORKFLOW"
    @echo "  just vm templates                        List base VMs with sizes"
    @echo "  just vm install <os> <name>              Fresh install from ISO (just vm install --list)"
    @echo "  just vm launch <base> <name>             Create sandbox (host-only, no internet)"
    @echo "  just vm launch <base> <name> --bridge    Create sandbox with internet access"
    @echo "  just vm launch <base> <name> --no-network Create sandbox without network"
    @echo "  just vm connect <name>                   Open VNC/virt-manager to sandbox"
    @echo "  just vm snapshot <name> create            Take snapshot (timestamp name)"
    @echo "  just vm snapshot <name> create <snap>     Take snapshot with custom name"
    @echo "  just vm snapshot <name> revert <snap>     Revert to snapshot"
    @echo "  just vm pause <name>                      Pause a running VM"
    @echo "  just vm resume <name>                     Resume a paused VM"
    @echo "  just vm stop <name>                       Stop and remove sandbox"
    @echo "  just vm save <name> [template-name]       Save instance as reusable template"
    @echo "  just vm destroy <name>                    Stop, delete, confirm"
    @echo ""
    @echo "  Aliases: just launch, just start, just connect, just stop"
    @echo ""
    @echo "TARGET GROUPS"
    @echo ""
    @echo "  vm <subcommand> [args]"
    @echo "    VM lifecycle and management. Run 'just vm' for full subcommand list."
    @echo "    launch, start, stop, connect, destroy, snapshot, list, status,"
    @echo "    templates, install, save, rename, convert, screenshot, cdrom, share,"
    @echo "    resume, pause, reset-password, ip, ssh, scp, telnet, sync-clock, ftp"
    @echo ""
    @echo "  host set|top|check-network|hypervisor [args]"
    @echo "    Host management."
    @echo "    set <tcentre1|tcentre2>   Set default host"
    @echo "    top                       Show host resource usage (htop)"
    @echo "    check-network             Verify network setup (bridges, DHCP, NAT)"
    @echo "    hypervisor [kvm|vmware]   Switch or check hypervisor"
    @echo ""
    @echo "  disk pull|inspect|registry-inspect|registry|snapshot-state|inject [args]"
    @echo "    Disk operations on stopped VMs."
    @echo "    pull <name> <vm-path> [dest]           Pull file from VM disk"
    @echo "    inspect <name> mount|umount|ls|info    Mount/inspect disk (read-only via NBD)"
    @echo "    registry-inspect <name> [hive]         Parse Windows registry hives"
    @echo "    registry <name> import|export|edit <hive> Offline registry operations"
    @echo "    snapshot-state <vm> <phase> <outdir>   Capture filesystem + registry state"
    @echo "    inject <name> <file1> [file2...]       Copy files into stopped VM disk"
    @echo ""
    @echo "  setup [local|analysis|sysinternals|pe-sieve|python-2.7|python-3.4|defender-off|defender-status] [vm-name]"
    @echo "    Install tools. Without args: local dependencies (remmina, vncviewer)."
    @echo "    sysinternals <vm>   Install Sysinternals Suite"
    @echo "    pe-sieve <vm>       Install pe-sieve + mal_unpack"
    @echo "    python-2.7 <vm>     Install Python 2.7.18 (last XP-compatible 2.x)"
    @echo "    python-3.4 <vm>     Install Python 3.4.4 (last XP-compatible 3.x)"
    @echo "    defender-off <vm>   Disable Defender real-time/behavior monitoring"
    @echo "    defender-status <vm> Show current Defender protection status"
    @echo ""
    @echo "  da debug|debug-trace|trace|procmon|memdump|virdump|netcap|run|gdb-run [args]"
    @echo "    Dynamic analysis."
    @echo "    debug <name> [port]                    Attach GDB server to running VM"
    @echo "    debug-trace <name> <config> [port]     GDB with trace config"
    @echo "    trace <action> <vm> [args]             ETW/logman traces"
    @echo "    procmon <name> start|stop|status [name] ProcMon management"
    @echo "    memdump <vm> list|dump|run [args]       Process memory dump via ProcDump"
    @echo "    virdump <vm> dump|list|analyze|clean    Full VM RAM dump via virsh"
    @echo "    netcap <action> [outdir] [iface]        Network capture (tcpdump + INetSim)"
    @echo "    detonate <vm> <sample> <outdir> [wait] [net] [etw] Execute malware (ProcMon + optional ETW/netcap)"
    @echo "    gdb-run <name> <script> <sample> <out>  GDB Python script on VM"
    @echo ""
    @echo "  sa re|analyze|disasm [args]"
    @echo "    Static analysis."
    @echo "    re <action> <file>    Static RE (pe, crypto, unpack, yara, vt, decompile, ...)"
    @echo "    analyze <dir>         Diff analysis on artifacts directory"
    @echo "    disasm <binary> <addr> Disassembly with Claude"
    @echo ""
    @echo "ARM VMs (Linux, serial console — auto-detected by template/instance)"
    @echo "  just vm launch debian-12-nocloud-arm64 myvm   Create ARM sandbox from template"
    @echo "  just vm launch debian-12-nocloud-arm64 myvm --hostonly"
    @echo "  just vm start myvm                            Start existing ARM instance"
    @echo "  just vm connect myvm                          Attach serial console (Ctrl-] to detach)"
    @echo "  just vm telnet myvm 'uname -a'                Run command via serial"
    @echo "  just vm snapshot myvm create|list|revert|delete [snap]"
    @echo "  just vm stop myvm                             Graceful shutdown"
    @echo "  just vm destroy myvm                          Delete instance"
    @echo "  ARM VMs are standalone qemu-system-aarch64 (not libvirt)."
    @echo "  arm64 kernel runs ARM 32-bit binaries (CONFIG_COMPAT=y)."
    @echo "  Login: root (no password) via serial console."

# Host management: just host set|top|check-network|hypervisor [args]
host *args:
    #!/usr/bin/env bash
    set -euo pipefail
    args="{{args}}"
    host_action="${args%% *}"
    rest="${args#* }"
    [ "$host_action" = "$rest" ] && rest=""

    case "$host_action" in
    set)
        target="${rest%% *}"
        case "$target" in
            tcentre1|tcentre2)
                echo "$target" > .host
                echo "Default host set to $target"
                ;;
            *)
                echo "Unknown host: $target"
                echo "Available: tcentre1 (home), tcentre2 (office)"
                exit 1
                ;;
        esac
        ;;

    top)
        ssh -t {{HOST}} "TERM=xterm-256color htop"
        ;;

    check-network)
        source "{{VIVI}}/scripts/lib.sh"
        setup_host "{{HOST}}"
        host="{{HOST}}"
        ok=0; fail=0
        pass() { echo "  [OK] $1"; ok=$((ok+1)); }
        err()  { echo "  [FAIL] $1"; fail=$((fail+1)); }

        echo "Network check on $host"
        echo "========================"

        # 1. Bridge interfaces exist and are UP
        echo ""
        echo "Bridges:"
        for br in virbr0 virbr1; do
            state=$(ssh "$host" "ip -br link show $br 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
            if [ "$state" = "UP" ]; then
                pass "$br is UP"
            else
                err "$br is ${state:-missing}"
            fi
        done

        # 2. IP addresses
        echo ""
        echo "IP addresses:"
        virbr0_ip=$(ssh "$host" "ip -4 addr show virbr0 2>/dev/null | grep -oP 'inet \K[0-9.]+'" 2>/dev/null)
        virbr1_ip=$(ssh "$host" "ip -4 addr show virbr1 2>/dev/null | grep -oP 'inet \K[0-9.]+'" 2>/dev/null)
        [ "$virbr0_ip" = "${KVM_BRIDGE_IP:-192.168.122.1}" ] && pass "virbr0 = $virbr0_ip" || err "virbr0 = ${virbr0_ip:-none} (expected 192.168.122.1)"
        [ "$virbr1_ip" = "${FTP_BIND:-192.168.100.1}" ] && pass "virbr1 = $virbr1_ip" || err "virbr1 = ${virbr1_ip:-none} (expected ${FTP_BIND:-192.168.100.1})"

        # 3. DHCP (dnsmasq) running for both bridges
        echo ""
        echo "DHCP (dnsmasq):"
        for net in default hostonly; do
            if ssh "$host" "pgrep -f 'dnsmasq.*${net}.conf' >/dev/null 2>&1"; then
                pass "dnsmasq ($net) running"
            else
                err "dnsmasq ($net) not running"
            fi
        done

        # 4. DNS listening on both bridges
        echo ""
        echo "DNS listeners:"
        for ip in "$virbr0_ip" "$virbr1_ip"; do
            if ssh "$host" "ss -tlnp | grep -q '${ip}:53'" 2>/dev/null; then
                pass "DNS on $ip:53"
            else
                err "DNS not listening on $ip:53"
            fi
        done

        # 5. NAT/masquerade for virbr0 (bridge = internet)
        echo ""
        echo "NAT (virbr0 internet access):"
        if ssh "$host" "sudo iptables -t nat -L LIBVIRT_PRT -n 2>/dev/null | grep -q 'MASQUERADE.*192.168.122'" 2>/dev/null; then
            pass "MASQUERADE for 192.168.122.0/24"
        else
            err "No MASQUERADE rule for virbr0 subnet"
        fi

        # 6. IP forwarding
        echo ""
        echo "IP forwarding:"
        fwd=$(ssh "$host" "cat /proc/sys/net/ipv4/ip_forward" 2>/dev/null)
        [ "$fwd" = "1" ] && pass "ip_forward = 1" || err "ip_forward = ${fwd:-unknown}"

        # 7. bridge.conf allows both bridges
        echo ""
        echo "QEMU bridge access (/etc/qemu/bridge.conf):"
        for br in virbr0 virbr1; do
            if ssh "$host" "grep -q 'allow $br' /etc/qemu/bridge.conf 2>/dev/null"; then
                pass "allow $br"
            else
                err "$br not in bridge.conf"
            fi
        done

        # 8. No masquerade for virbr1 (hostonly = isolated)
        echo ""
        echo "Isolation (virbr1 no internet):"
        if ssh "$host" "sudo iptables -t nat -L -n 2>/dev/null | grep -q 'MASQUERADE.*192.168.100'" 2>/dev/null; then
            err "MASQUERADE found for 192.168.100.0/24 — hostonly is NOT isolated!"
        else
            pass "No MASQUERADE for 192.168.100.0/24 (isolated)"
        fi

        # Summary
        echo ""
        echo "========================"
        echo "Results: $ok passed, $fail failed"
        [ "$fail" -eq 0 ] && echo "All network checks passed." || echo "Some checks failed — review above."
        ;;

    hypervisor)
        {{VIVI}}/scripts/vm.sh "{{HOST}}" hypervisor $rest
        ;;

    "")
        echo "Usage: just host <subcommand> [args]"
        echo ""
        echo "Subcommands:"
        echo "  set <tcentre1|tcentre2>   Set default host"
        echo "  top                       Show host resource usage (htop)"
        echo "  check-network             Verify network setup"
        echo "  hypervisor [kvm|vmware]   Switch or check hypervisor"
        exit 1
        ;;

    *)
        echo "Unknown host subcommand: $host_action"
        echo "Usage: just host set|top|check-network|hypervisor [args]"
        exit 1
        ;;
    esac

# Install local deps or VM tools: just setup [local|analysis|sysinternals|pe-sieve|python-2.7|python-3.4|defender-off|defender-status] [vm-name]
setup *args:
    #!/usr/bin/env bash
    args="{{args}}"
    pkg="${args%% *}"
    rest="${args#* }"
    [ "$pkg" = "$rest" ] && rest=""

    case "$pkg" in
        ""|local)
            ansible-playbook -i localhost, -c local ansible/setup-local.yml --ask-become-pass
            ;;
        analysis)
            ansible-playbook -i localhost, -c local ansible/setup-analysis-tools.yml --ask-become-pass
            ;;
        sysinternals|pe-sieve|python-2.7|python-3.4)
            vm="${rest:-}"
            if [ -z "$vm" ]; then
                echo "Usage: just setup $pkg <vm-name>"
                echo "Example: just setup $pkg winxp-dyn"
                exit 1
            fi
            {{VIVI}}/scripts/setup-vm.sh "{{HOST}}" "$vm" "$pkg"
            ;;
        defender-off)
            vm="${rest:-}"
            if [ -z "$vm" ]; then
                echo "Usage: just setup defender-off <vm-name>"
                exit 1
            fi
            source "{{VIVI}}/scripts/lib.sh"
            setup_host "{{HOST}}"
            vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$vm")
            opts=$(vm_ssh_opts "{{HOST}}" "$vm")
            run_on_vm() {
                ssh {{HOST}} "sshpass -p '$VM_PASS' ssh $opts -o StrictHostKeyChecking=no '${VM_USER}@${vmip}' '$1'"
            }
            echo "=== Disabling Defender on $vm ($vmip) ==="
            echo "  Disabling real-time monitoring..."
            run_on_vm 'powershell -Command Set-MpPreference -DisableRealtimeMonitoring 1'
            echo "  Disabling behavior monitoring..."
            run_on_vm 'powershell -Command Set-MpPreference -DisableBehaviorMonitoring 1'
            echo "  Disabling on-access (IOAV) protection..."
            run_on_vm 'powershell -Command Set-MpPreference -DisableIOAVProtection 1'
            echo "  Disabling script scanning..."
            run_on_vm 'powershell -Command Set-MpPreference -DisableScriptScanning 1'
            echo "  Setting sample submission to Never..."
            run_on_vm 'powershell -Command Set-MpPreference -SubmitSamplesConsent 2'
            echo "  Adding exclusion paths (C:\\local, C:\\tmp)..."
            run_on_vm 'powershell -Command Add-MpPreference -ExclusionPath C:\local'
            run_on_vm 'powershell -Command Add-MpPreference -ExclusionPath C:\tmp'
            echo ""
            echo "=== Verifying ==="
            run_on_vm 'powershell -Command Get-MpPreference' | grep -E 'Disable|Exclusion|SubmitSamples'
            echo ""
            echo "Done. Note: real-time protection re-enables on reboot — run this again after restarting the VM."
            ;;
        defender-status)
            vm="${rest:-}"
            if [ -z "$vm" ]; then
                echo "Usage: just setup defender-status <vm-name>"
                exit 1
            fi
            source "{{VIVI}}/scripts/lib.sh"
            setup_host "{{HOST}}"
            vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$vm")
            opts=$(vm_ssh_opts "{{HOST}}" "$vm")
            echo "=== Defender status on $vm ($vmip) ==="
            ssh {{HOST}} "sshpass -p '$VM_PASS' ssh $opts -o StrictHostKeyChecking=no '${VM_USER}@${vmip}' 'powershell -Command Get-MpComputerStatus'" \
                | grep -E 'RealTimeProtection|BehaviorMonitor|IoavProtection|IsTamperProtected|AntivirusEnabled'
            echo ""
            echo "=== Exclusions ==="
            ssh {{HOST}} "sshpass -p '$VM_PASS' ssh $opts -o StrictHostKeyChecking=no '${VM_USER}@${vmip}' 'powershell -Command Get-MpPreference'" \
                | grep -E 'ExclusionPath|ExclusionExtension|ExclusionProcess'
            ;;
        *)
            echo "Unknown package: $pkg"
            echo ""
            echo "Usage:"
            echo "  just setup                          Install local dependencies"
            echo "  just setup analysis                 Install analysis tools (procmon-parser, etl-parser, etc.)"
            echo "  just setup sysinternals <vm>        Install Sysinternals Suite into VM"
            echo "  just setup pe-sieve <vm>            Install pe-sieve + mal_unpack into VM"
            echo "  just setup python-2.7 <vm>          Install Python 2.7.18 into VM"
            echo "  just setup python-3.4 <vm>          Install Python 3.4.4 into VM"
            echo "  just setup defender-off <vm>        Disable Defender real-time/behavior monitoring + add exclusions"
            echo "  just setup defender-status <vm>     Show current Defender protection status"
            exit 1
            ;;
    esac

# VM management: just vm launch|start|stop|connect|destroy|snapshot|list|status|... [args]
vm *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    args="{{args}}"
    subcmd="${args%% *}"
    rest="${args#* }"
    [ "$subcmd" = "$rest" ] && rest=""

    # Helper: parse positional args from rest string
    arg1="${rest%% *}"; rest2="${rest#* }"; [ "$arg1" = "$rest2" ] && rest2=""
    arg2="${rest2%% *}"; rest3="${rest2#* }"; [ "$arg2" = "$rest3" ] && rest3=""
    arg3="${rest3%% *}"; rest4="${rest3#* }"; [ "$arg3" = "$rest4" ] && rest4=""
    arg4="${rest4%% *}"; rest5="${rest4#* }"; [ "$arg4" = "$rest5" ] && rest5=""

    case "$subcmd" in
        list)
            {{VIVI}}/scripts/vm.sh "{{HOST}}" list
            ;;
        templates)
            {{VIVI}}/scripts/vm.sh "{{HOST}}" templates $rest
            ;;
        install)
            if [ -z "$rest" ]; then echo "Usage: just vm install --list | just vm install <os> <name> [--bridge|--no-network]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" install $rest
            ;;
        launch)
            if [ -z "$arg1" ] || [ -z "$arg2" ]; then echo "Usage: just vm launch <base> <name> [--bridge|--no-network]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" launch "$arg1" "$arg2" $rest3
            ;;
        connect)
            if [ -z "$arg1" ]; then echo "Usage: just vm connect <name>"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" connect "$arg1"
            ;;
        screenshot)
            if [ -z "$arg1" ]; then echo "Usage: just vm screenshot <name> [output.png]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" screenshot "$arg1" "${arg2:-}"
            ;;
        start)
            if [ -z "$arg1" ]; then echo "Usage: just vm start <name> [--bridge|--hostonly|--no-network]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" start "$arg1" $rest2
            ;;
        resume)
            if [ -z "$arg1" ]; then echo "Usage: just vm resume <name>"; exit 1; fi
            ssh {{HOST}} "virsh resume '$arg1'"
            ;;
        pause)
            if [ -z "$arg1" ]; then echo "Usage: just vm pause <name>"; exit 1; fi
            ssh {{HOST}} "virsh suspend '$arg1'"
            ;;
        stop)
            if [ -z "$arg1" ]; then echo "Usage: just vm stop <name> [--keep]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" shutdown "$arg1" $rest2
            ;;
        rename)
            if [ -z "$arg1" ] || [ -z "$arg2" ]; then echo "Usage: just vm rename <old> <new>"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" rename "$arg1" "$arg2"
            ;;
        destroy)
            if [ -z "$arg1" ]; then echo "Usage: just vm destroy <name>"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" destroy "$arg1"
            ;;
        snapshot)
            if [ -z "$arg1" ]; then echo "Usage: just vm snapshot <name> create|list|revert|delete [snapshot]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" snapshot "$arg1" $rest2
            ;;
        save)
            if [ -z "$arg1" ]; then echo "Usage: just vm save <name> [template-name] [--force]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" save "$arg1" $rest2
            ;;
        cdrom)
            {{VIVI}}/scripts/vm.sh "{{HOST}}" cdrom $rest
            ;;
        share)
            if [ -z "$arg1" ]; then echo "Usage: just vm share <name> <file1> [file2...]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" share "$arg1" $rest2
            ;;
        status)
            {{VIVI}}/scripts/vm.sh "{{HOST}}" status
            ;;
        convert)
            if [ -z "$arg1" ]; then echo "Usage: just vm convert <base>"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" convert "$arg1"
            ;;
        reset-password)
            if [ -z "$arg1" ]; then echo "Usage: just vm reset-password <name> [username] [new-password]"; exit 1; fi
            {{VIVI}}/scripts/vm.sh "{{HOST}}" reset-password "$arg1" $rest2
            ;;
        ip)
            if [ -z "$arg1" ]; then echo "Usage: just vm ip <name>"; exit 1; fi
            {{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$arg1"
            ;;
        ssh)
            if [ -z "$arg1" ]; then echo "Usage: just vm ssh <name> [cmd]"; exit 1; fi
            vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$arg1")
            opts=$(vm_ssh_opts "{{HOST}}" "$arg1")
            if [ -z "$rest2" ]; then
                echo "SSH into $arg1 at $vmip..."
                ssh -t {{HOST}} "sshpass -p '$VM_PASS' ssh $opts -o StrictHostKeyChecking=no '${VM_USER}@${vmip}'"
            else
                echo "Running on $arg1 ($vmip): $rest2"
                ssh {{HOST}} "sshpass -p '$VM_PASS' ssh $opts -o StrictHostKeyChecking=no '${VM_USER}@${vmip}' '$rest2'"
            fi
            ;;
        scp)
            # scp <name> <direction> <src> <dest>
            if [ -z "$arg1" ] || [ -z "$arg2" ] || [ -z "$arg3" ] || [ -z "$arg4" ]; then
                echo "Usage: just vm scp <name> pull|push <src> <dest>"
                exit 1
            fi
            {{VIVI}}/scripts/vm-scp.sh "{{HOST}}" "$arg1" "$arg2" "$arg3" "$arg4"
            ;;
        telnet)
            # telnet <name> <cmd> [timeout]
            if [ -z "$arg1" ] || [ -z "$arg2" ]; then echo "Usage: just vm telnet <name> <command> [timeout]"; exit 1; fi
            timeout_val="${arg3:-30}"
            if is_arm_instance "$arg1"; then
                {{VIVI}}/scripts/vm-arm.sh exec "$arg1" "$arg2" "$timeout_val"
            else
                vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$arg1")
                echo "Connecting to $arg1 at $vmip..."
                {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "$arg2" "$timeout_val"
            fi
            ;;
        sync-clock)
            if [ -z "$arg1" ]; then echo "Usage: just vm sync-clock <name>"; exit 1; fi
            vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$arg1")
            host_time=$(ssh {{HOST}} "date +%H:%M:%S")
            host_date=$(ssh {{HOST}} "date +%m/%d/%Y")
            echo "Setting $arg1 clock to $host_date $host_time"
            {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "time $host_time" 10
            {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "date $host_date" 10
            echo "Done."
            ;;
        ftp)
            # ftp start|stop|pull <name> <vm-path> [local-dest]
            ftp_action="$arg1"
            case "$ftp_action" in
                start|stop)
                    {{VIVI}}/scripts/ftp-server.sh "{{HOST}}" "$HOST_ROOT_VAL" "$FTPDIR" "$FTP_BIND" "$FTP_PYTHON" "$ftp_action"
                    ;;
                pull)
                    # pull <vm-name> <vm-path> [local-dest]
                    vm_name="$arg2"
                    vm_file="$arg3"
                    local_dest="${arg4:-.}"
                    if [ -z "$vm_name" ] || [ -z "$vm_file" ]; then
                        echo "Usage: just vm ftp pull <vm-name> <vm-path> [local-dest]"
                        echo "Example: just vm ftp pull winxp-dyn 'C:\\procmon.PML' ./artifacts/"
                        exit 1
                    fi
                    vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$vm_name")
                    # Ensure FTP server is running
                    if ! ssh {{HOST}} "ss -tlnp | grep -q ':21 '" 2>/dev/null; then
                        echo "Starting FTP server..."
                        {{VIVI}}/scripts/ftp-server.sh "{{HOST}}" "$HOST_ROOT_VAL" "$FTPDIR" "$FTP_BIND" "$FTP_PYTHON" start
                        sleep 2
                    fi
                    filename=$(basename "$vm_file")
                    ssh {{HOST}} "rm -f '${FTPDIR}/${filename}'" 2>/dev/null || true
                    # Create FTP script and upload from VM
                    {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" \
                        "(echo open ${FTP_BIND}&echo user anonymous x&echo binary&echo put ${vm_file}&echo quit)> C:\\ftp-upload.txt" 10
                    echo "Uploading $filename via FTP..."
                    {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" \
                        "ftp -n -s:C:\\ftp-upload.txt" 120 || true
                    sleep 3
                    if ssh {{HOST}} "test -f '${FTPDIR}/${filename}'" 2>/dev/null; then
                        size=$(ssh {{HOST}} "stat -c%s '${FTPDIR}/${filename}'")
                        echo "FTP upload complete: ${size} bytes"
                        if [ -d "$local_dest" ]; then
                            local_dest="${local_dest}/${filename}"
                        fi
                        echo "Pulling to $local_dest..."
                        scp "{{HOST}}:${FTPDIR}/${filename}" "$local_dest"
                        echo "Saved: $local_dest"
                    else
                        echo "ERROR: File not found in ${FTPDIR}/. Transfer may have failed."
                        exit 1
                    fi
                    ;;
                "")
                    echo "Usage: just vm ftp start|stop|pull <name> <vm-path> [local-dest]"
                    echo ""
                    echo "  start                              Start FTP server on host"
                    echo "  stop                               Stop FTP server"
                    echo "  pull <vm> <vm-path> [local-dest]   Pull file from VM via FTP"
                    ;;
                *)
                    echo "Unknown ftp action: $ftp_action"
                    exit 1
                    ;;
            esac
            ;;
        "")
            echo "Usage: just vm <subcommand> [args]"
            echo ""
            echo "Subcommands:"
            echo "  list                                    List running sandboxes/instances"
            echo "  templates [--delete <name>]             List or delete VM templates"
            echo "  install <os> <name> [opts]              Install OS from ISO"
            echo "  launch <base> <name> [opts]             Create sandbox from template"
            echo "  connect <name>                          Open VNC/SPICE/serial console"
            echo "  screenshot <name> [output.png]          Take screenshot"
            echo "  start <name> [opts]                     Start a stopped VM"
            echo "  resume <name>                           Resume a paused VM"
            echo "  pause <name>                            Pause a running VM"
            echo "  stop <name> [--keep]                    Graceful shutdown"
            echo "  rename <old> <new>                      Rename VM instance or template"
            echo "  destroy <name>                          Stop + delete VM"
            echo "  snapshot <name> create|list|revert|delete [snap]"
            echo "  save <name> [template-name] [--force]   Save instance as template"
            echo "  cdrom list|prepare|mount|eject [args]   CD-ROM management"
            echo "  share <name> <file1> [file2...]         Copy files into VM via ISO"
            echo "  status                                  Show VMs and sandboxes status"
            echo "  convert <base>                          Convert VMDK to qcow2"
            echo "  reset-password <name> [user] [pass]     Reset Windows password"
            echo "  ip <name>                               Get VM IP address"
            echo "  ssh <name> [cmd]                        SSH into VM or run command"
            echo "  scp <name> pull|push <src> <dest>       Copy files to/from VM"
            echo "  telnet <name> <cmd> [timeout]           Run command via telnet/serial"
            echo "  sync-clock <name>                       Sync VM clock to host time"
            echo "  ftp start|stop|pull [args]              FTP server and file transfer"
            exit 1
            ;;
        *)
            echo "Unknown vm subcommand: $subcmd"
            echo "Run 'just vm' for usage."
            exit 1
            ;;
    esac

# Alias: just launch <base> <name> [args]
launch base name *args:
    just vm launch "{{base}}" "{{name}}" {{args}}

# Alias: just start <name> [args]
start name *args:
    just vm start "{{name}}" {{args}}

# Alias: just connect <name>
connect name:
    just vm connect "{{name}}"

# Alias: just stop <name> [args]
stop name *args:
    just vm stop "{{name}}" {{args}}

# Disk operations (stopped VMs): just disk pull|inspect|registry-inspect|registry|snapshot-state|inject [args]
disk *args:
    #!/usr/bin/env bash
    set -euo pipefail
    args="{{args}}"
    disk_action="${args%% *}"
    rest="${args#* }"
    [ "$disk_action" = "$rest" ] && rest=""

    case "$disk_action" in
    pull)
        # Parse: pull <name> <vm-path> [local-dest]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        vm_path="${rest2%% *}"
        extra="${rest2#* }"
        [ "$vm_path" = "$extra" ] && extra=""
        if [ -z "$name" ] || [ -z "$vm_path" ]; then
            echo "Usage: just disk pull <name> <vm-path> [local-dest]"
            exit 1
        fi
        {{VIVI}}/scripts/vm.sh "{{HOST}}" pull "$name" "$vm_path" $extra
        ;;

    inspect)
        # Parse: inspect <name> mount|umount|ls|info [path]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        if [ -z "$name" ]; then
            echo "Usage: just disk inspect <name> mount|umount|ls|info [path]"
            exit 1
        fi
        {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect "$name" $rest2
        ;;

    registry-inspect)
        # Parse: registry-inspect <name> [hive]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        if [ -z "$name" ]; then
            echo "Usage: just disk registry-inspect <name> [SAM|SYSTEM|SOFTWARE|SECURITY|NTUSER|all]"
            exit 1
        fi
        {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect-registry "$name" $rest2
        ;;

    registry)
        # Parse: registry <name> import|export|edit <hive> [regfile|key]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        if [ -z "$name" ]; then
            echo "Usage: just disk registry <name> import|export|edit <hive> [regfile|key]"
            exit 1
        fi
        {{VIVI}}/scripts/vm.sh "{{HOST}}" registry "$name" $rest2
        ;;

    snapshot-state)
        # Parse: snapshot-state <vm> <phase> <outdir>
        vm="${rest%% *}"
        rest2="${rest#* }"
        [ "$vm" = "$rest2" ] && rest2=""
        phase="${rest2%% *}"
        outdir="${rest2#* }"
        [ "$phase" = "$outdir" ] && outdir=""
        if [ -z "$vm" ] || [ -z "$phase" ] || [ -z "$outdir" ]; then
            echo "Usage: just disk snapshot-state <vm> <phase> <outdir>"
            exit 1
        fi
        {{VIVI}}/scripts/snapshot-state.sh "{{HOST}}" "$vm" "$phase" "$outdir"
        ;;

    inject)
        # Parse: inject <name> <file1> [file2...]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        files="$rest2"
        if [ -z "$name" ] || [ -z "$files" ]; then
            echo "Usage: just disk inject <name> <file1> [file2...]" >&2
            exit 1
        fi
        # Wait for VM to be stopped (up to 30s)
        for i in $(seq 1 30); do
            state=$(ssh {{HOST}} "virsh domstate $name" 2>/dev/null)
            [ "$state" = "shut off" ] && break
            [ "$i" = "1" ] && echo "Waiting for $name to stop..."
            sleep 1
        done
        if [ "$state" != "shut off" ]; then
            echo "Error: $name must be stopped (current state: $state)" >&2
            echo "  just vm stop $name --keep" >&2
            exit 1
        fi
        # Get disk path from virsh
        disk=$(ssh {{HOST}} "virsh domblklist $name --details | awk '/disk/{print \$4}'")
        if [ -z "$disk" ]; then
            echo "Error: Could not find disk for $name" >&2
            exit 1
        fi
        # Copy each file to host, then inject via virt-copy-in
        for f in $files; do
            if [ ! -f "$f" ]; then
                echo "Error: File not found: $f" >&2
                exit 1
            fi
            fname="$(basename "$f")"
            echo "Injecting $fname → C:\\"
            scp -q "$f" {{HOST}}:/tmp/"$fname"
            ssh {{HOST}} "sudo virt-copy-in -a '$disk' /tmp/$fname /"
        done
        echo "Done. Start VM with: just vm start $name"
        ;;

    "")
        echo "Usage: just disk <subcommand> [args]"
        echo ""
        echo "Subcommands:"
        echo "  pull <name> <vm-path> [dest]       Pull file from stopped VM disk"
        echo "  inspect <name> mount|umount|ls|info Inspect stopped VM disk (read-only)"
        echo "  registry-inspect <name> [hive]      Parse Windows registry hives"
        echo "  registry <name> import|export|edit   Offline registry operations"
        echo "  snapshot-state <vm> <phase> <outdir> Capture filesystem + registry state"
        echo "  inject <name> <file1> [file2...]     Copy files into stopped VM disk"
        exit 1
        ;;

    *)
        echo "Unknown disk subcommand: $disk_action"
        echo "Usage: just disk pull|inspect|registry-inspect|registry|snapshot-state|inject [args]"
        exit 1
        ;;
    esac

# Dynamic analysis: just da detonate|debug|debug-trace|trace|procmon|memdump|virdump|netcap|gdb-run [args]
da *args:
    #!/usr/bin/env bash
    set -euo pipefail
    args="{{args}}"
    da_action="${args%% *}"
    rest="${args#* }"
    [ "$da_action" = "$rest" ] && rest=""

    case "$da_action" in
    debug)
        # Parse: debug <name> [port]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        port="${rest2:-1234}"
        if [ -z "$name" ]; then
            echo "Usage: just da debug <name> [port=1234]"
            exit 1
        fi
        {{VIVI}}/scripts/vm.sh "{{HOST}}" debug "$name" "$port"
        ;;

    debug-trace)
        # Parse: debug-trace <name> <config> [port]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        config="${rest2%% *}"
        rest3="${rest2#* }"
        [ "$config" = "$rest3" ] && rest3=""
        port="${rest3:-1234}"
        if [ -z "$name" ] || [ -z "$config" ]; then
            echo "Usage: just da debug-trace <name> <config.yaml|config.toml> [port=1234]"
            exit 1
        fi
        host_ip=$(echo "{{HOST}}" | sed 's/.*@//')
        gdb_script="/tmp/debug-${name}-$$.gdb"
        "{{PYTHON}}" "{{VIVI}}/scripts/gen-gdb-script.py" "$config" "${host_ip}:${port}" "$gdb_script"
        echo "Starting GDB server on ${name}:${port}..."
        {{VIVI}}/scripts/vm.sh "{{HOST}}" debug "$name" "$port"
        echo ""
        echo "GDB script: $gdb_script"
        echo ""
        echo "=== In terminal 1: ==="
        echo "  gdb -x $gdb_script"
        echo "  (gdb) continue"
        echo ""
        echo "=== In terminal 2: ==="
        echo "  just vm telnet ${name} '<malware command>'"
        echo ""
        echo "GDB will break at OEP, capture CR3, then set conditional breakpoints."
        ;;

    trace)
        # Parse: trace <action> <vm> [args]
        trace_action="${rest%% *}"
        rest2="${rest#* }"
        [ "$trace_action" = "$rest2" ] && rest2=""
        trace_name="${rest2%% *}"
        trace_extra="${rest2#* }"
        [ "$trace_name" = "$trace_extra" ] && trace_extra=""
        if [ -z "$trace_action" ] || [ -z "$trace_name" ]; then
            echo "Usage: just da trace <action> <vm> [args]"
            echo "Actions: start, stop, status, pull"
            exit 1
        fi
        source "{{VIVI}}/scripts/lib.sh"
        setup_host "{{HOST}}"
        {{VIVI}}/scripts/trace.sh "$trace_action" "$trace_name" $trace_extra
        ;;

    procmon)
        # Parse: procmon <name> start|stop|status [capture-name]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        pm_action="${rest2%% *}"
        rest3="${rest2#* }"
        [ "$pm_action" = "$rest3" ] && rest3=""
        capture_name="${rest3:-procmon}"
        if [ -z "$name" ] || [ -z "$pm_action" ]; then
            echo "Usage: just da procmon <vm-name> start|stop|status [capture-name]"
            exit 0
        fi
        source "{{VIVI}}/scripts/lib.sh"
        setup_host "{{HOST}}"
        vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$name")
        {{VIVI}}/scripts/procmon-ctl.sh "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "$pm_action" "$capture_name" "$PROCMON_EXE" "$PSEXEC_EXE"
        ;;

    memdump)
        # Parse: memdump <vm> list|dump|run [args]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        md_action="${rest2%% *}"
        md_rest="${rest2#* }"
        [ "$md_action" = "$md_rest" ] && md_rest=""

        source "{{VIVI}}/scripts/lib.sh"
        setup_host "{{HOST}}"

        if [ -z "$name" ] || [ -z "$md_action" ]; then
            echo "Usage: just da memdump <vm> list|dump|run [args]"
            echo ""
            echo "  list                                  List processes (non-system marked <---)"
            echo "  dump <pid-or-name> [output]           Dump already-running process"
            echo "  run <cmd> [delay=8] [output] [dest]   Launch, dump, stop, pull locally"
            echo ""
            echo "The 'run' action does the full flow: launch malware, wait <delay>s,"
            echo "dump with ProcDump, stop VM, mount disk, pull dump to <dest>."
            echo ""
            echo "Examples:"
            echo "  just da memdump winxp-dyn list"
            echo "  just da memdump winxp-dyn dump sample.exe sample-dump"
            echo "  just da memdump winxp-dyn run 'C:\\malware-test\\sample.exe' 8 sample-dump ./out/"
            exit 0
        fi

        vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$name")

        case "$md_action" in
            list)
                {{VIVI}}/scripts/memdump.sh "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" list
                ;;
            dump)
                target="${md_rest%% *}"
                rest3="${md_rest#* }"
                [ "$target" = "$rest3" ] && rest3=""
                outname="${rest3:-memdump}"
                if [ -z "$target" ]; then
                    echo "Usage: just da memdump <vm> dump <pid-or-name> [output-name]"
                    exit 1
                fi
                {{VIVI}}/scripts/memdump.sh "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" dump "$target" "$outname" "$PROCDUMP_EXE"
                ;;
            run)
                # Parse: run <cmd> [delay] [output] [local-dest]
                runcmd="${md_rest%% *}"
                rest3="${md_rest#* }"
                [ "$runcmd" = "$rest3" ] && rest3=""
                delay="${rest3%% *}"
                rest4="${rest3#* }"
                [ "$delay" = "$rest4" ] && rest4=""
                # If delay is not a number, treat it as output name
                if [ -n "$delay" ] && ! [[ "$delay" =~ ^[0-9]+$ ]]; then
                    outname="$delay"
                    delay="8"
                    local_dest="${rest4%% *}"
                else
                    delay="${delay:-8}"
                    outname="${rest4%% *}"
                    rest5="${rest4#* }"
                    [ "$outname" = "$rest5" ] && rest5=""
                    local_dest="$rest5"
                fi
                outname="${outname:-memdump}"
                local_dest="${local_dest:-.}"
                if [ -z "$runcmd" ]; then
                    echo "Usage: just da memdump <vm> run <cmd> [delay=8] [output] [local-dest]"
                    echo "Example: just da memdump winxp-dyn run 'C:\\malware\\sample.exe' 8 sample-dump ./out/"
                    exit 1
                fi

                # Step 1: Launch + dump
                {{VIVI}}/scripts/memdump.sh "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" run "$runcmd" "$delay" "$outname" "$PROCDUMP_EXE"

                # Step 2: Stop VM (keep disk)
                echo ""
                echo "=== Stopping VM (keeping disk) ==="
                {{VIVI}}/scripts/vm.sh "{{HOST}}" stop "$name" --keep

                # Step 3: Mount disk, find and pull dump
                echo ""
                echo "=== Pulling dump from disk ==="
                {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect "$name" mount

                # Find the .dmp file on the mounted disk
                mntdir="${KVMDIR}/mnt/${name}-live"
                dmpfile=$(ssh "{{HOST}}" "find '$mntdir' -maxdepth 1 -name '${outname}*.dmp' -type f 2>/dev/null | head -1")
                if [ -z "$dmpfile" ]; then
                    echo "ERROR: Dump file ${outname}*.dmp not found on disk"
                    {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect "$name" umount
                    exit 1
                fi

                dmpname=$(basename "$dmpfile")
                mkdir -p "$local_dest"
                echo "Pulling $dmpname -> ${local_dest}/${dmpname}"
                scp "{{HOST}}:${dmpfile}" "${local_dest}/${dmpname}"

                # Step 4: Unmount
                {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect "$name" umount

                echo ""
                echo "=== Done ==="
                echo "Dump saved: ${local_dest}/${dmpname}"
                ;;
            *)
                echo "Unknown action: $md_action"
                echo "Usage: just da memdump <vm> list|dump|run [args]"
                exit 1
                ;;
        esac
        ;;

    virdump)
        # Parse: virdump <vm> dump|list|analyze|clean [args]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        vd_action="${rest2%% *}"
        vd_rest="${rest2#* }"
        [ "$vd_action" = "$vd_rest" ] && vd_rest=""

        source "{{VIVI}}/scripts/lib.sh"
        setup_host "{{HOST}}"

        if [ -z "$name" ] || [ -z "$vd_action" ]; then
            {{VIVI}}/scripts/virdump.sh "{{HOST}}" help
            exit 0
        fi

        case "$vd_action" in
            dump)
                {{VIVI}}/scripts/virdump.sh "{{HOST}}" dump "$name" $vd_rest
                ;;
            list)
                {{VIVI}}/scripts/virdump.sh "{{HOST}}" list
                ;;
            analyze)
                {{VIVI}}/scripts/virdump.sh "{{HOST}}" analyze $vd_rest
                ;;
            clean)
                {{VIVI}}/scripts/virdump.sh "{{HOST}}" clean
                ;;
            *)
                {{VIVI}}/scripts/virdump.sh "{{HOST}}" help
                exit 1
                ;;
        esac
        ;;

    netcap)
        # Parse: netcap <action> [outdir] [iface]
        nc_action="${rest%% *}"
        rest2="${rest#* }"
        [ "$nc_action" = "$rest2" ] && rest2=""
        outdir="${rest2%% *}"
        rest3="${rest2#* }"
        [ "$outdir" = "$rest3" ] && rest3=""
        iface="${rest3:-virbr1}"
        outdir="${outdir:-.}"

        source "{{VIVI}}/scripts/lib.sh"
        setup_host "{{HOST}}"

        if [ -z "$nc_action" ]; then
            echo "Usage: just da netcap start|stop|inetsim-start|inetsim-stop <outdir> [iface]"
            exit 1
        fi

        pidfile="/tmp/netcap-tcpdump.pid"
        inetsim_pid="/tmp/netcap-inetsim.pid"

        case "$nc_action" in
            start)
                mkdir -p "$outdir"
                pcap="$outdir/capture-$(date +%Y%m%d-%H%M%S).pcap"
                echo "=== Starting tcpdump on $iface ==="
                ssh "$HOST" "sudo rm -f /tmp/netcap.pcap; \
                    nohup sudo tcpdump -i $iface -w /tmp/netcap.pcap -U > /dev/null 2>&1 & \
                    echo \$! > /tmp/netcap-tcpdump.pid"
                echo "Capturing to: $pcap (remote: /tmp/netcap.pcap)"
                echo "$pcap" > /tmp/netcap-outfile
                ;;

            stop)
                echo "=== Stopping tcpdump ==="
                ssh "$HOST" "sudo kill \$(cat /tmp/netcap-tcpdump.pid 2>/dev/null) 2>/dev/null || true"
                sleep 1
                pcap=$(cat /tmp/netcap-outfile 2>/dev/null || echo "$outdir/capture.pcap")
                mkdir -p "$(dirname "$pcap")"
                scp "$HOST":/tmp/netcap.pcap "$pcap" 2>/dev/null || echo "Warning: no pcap to copy"
                ssh "$HOST" "rm -f /tmp/netcap.pcap /tmp/netcap-tcpdump.pid" 2>/dev/null || true
                rm -f /tmp/netcap-outfile
                if [ -f "$pcap" ]; then
                    echo "Saved: $pcap ($(stat -c%s "$pcap") bytes)"
                    echo ""
                    echo "Quick analysis:"
                    echo "  tcpdump -r '$pcap' -n | head -50"
                    echo "  tcpdump -r '$pcap' -n 'port 53'          # DNS queries"
                    echo "  tcpdump -r '$pcap' -n 'port 80 or 443'   # HTTP/HTTPS"
                fi
                ;;

            inetsim-start)
                echo "=== Starting INetSim on $HOST (bind: 192.168.100.1) ==="
                ssh "$HOST" "sudo systemctl stop dnsmasq 2>/dev/null || true; \
                    printf 'service_bind_address 192.168.100.1\ndns_default_ip 192.168.100.1\nstart_service dns\nstart_service http\nstart_service https\nstart_service smtp\nstart_service ftp\nreport_dir /tmp/inetsim-report\n' > /tmp/inetsim-malware.conf; \
                    nohup sudo inetsim --conf /tmp/inetsim-malware.conf > /dev/null 2>&1 & \
                    echo \$! > /tmp/netcap-inetsim.pid"
                echo "INetSim running — faking DNS, HTTP, SMTP, FTP on 192.168.100.1"
                echo "VM DNS should point to 192.168.100.1 for full capture"
                ;;

            inetsim-stop)
                echo "=== Stopping INetSim ==="
                ssh "$HOST" "sudo killall inetsim 2>/dev/null || true
                    sudo systemctl start dnsmasq 2>/dev/null || true"
                mkdir -p "$outdir"
                scp -r "$HOST":/tmp/inetsim-report "$outdir/inetsim-report" 2>/dev/null || echo "No report to copy"
                ssh "$HOST" "sudo rm -rf /tmp/inetsim-report /tmp/netcap-inetsim.pid" 2>/dev/null || true
                if [ -d "$outdir/inetsim-report" ]; then
                    echo "INetSim report saved: $outdir/inetsim-report/"
                fi
                ;;

            *)
                echo "Usage: just da netcap start|stop|inetsim-start|inetsim-stop <outdir> [iface]"
                exit 1
                ;;
        esac
        ;;

    detonate)
        # Parse: detonate <vm> <sample> <outdir> [wait] [net] [etw] [file]
        vm="${rest%% *}"
        rest2="${rest#* }"
        [ "$vm" = "$rest2" ] && rest2=""
        sample="${rest2%% *}"
        rest3="${rest2#* }"
        [ "$sample" = "$rest3" ] && rest3=""
        run_outdir="${rest3%% *}"
        rest4="${rest3#* }"
        [ "$run_outdir" = "$rest4" ] && rest4=""
        # Parse optional: wait, net, etw, file
        wait_val="${rest4%% *}"
        rest5="${rest4#* }"
        [ "$wait_val" = "$rest5" ] && rest5=""
        net_val="${rest5%% *}"
        rest6="${rest5#* }"
        [ "$net_val" = "$rest6" ] && rest6=""
        etw_val="${rest6%% *}"
        rest7="${rest6#* }"
        [ "$etw_val" = "$rest7" ] && rest7=""
        file_val="$rest7"
        # Defaults
        wait_val="${wait_val:-60}"
        net_val="${net_val:-off}"
        etw_val="${etw_val:-on}"
        file_val="${file_val:-}"

        if [ -z "$vm" ] || [ -z "$sample" ] || [ -z "$run_outdir" ]; then
            echo "Usage: just da detonate <vm> <sample> <outdir> [wait=60] [net=off|on] [etw=on|off] [file=]"
            exit 1
        fi

        source "{{VIVI}}/scripts/lib.sh"
        setup_host "{{HOST}}"

        # Source samples.sh from the importing justfile's directory if it exists
        if [ -f "{{justfile_directory()}}/samples.sh" ]; then
            source "{{justfile_directory()}}/samples.sh"
        fi

        # Look up malware command from config
        if [ -z "${MALWARE_CMD[$sample]+x}" ]; then
            echo "Unknown sample: $sample"
            echo "Define MALWARE_CMD[$sample] in config.sh or samples.sh"
            echo ""
            echo "Available samples:"
            for key in "${!MALWARE_CMD[@]}"; do
                echo "  $key"
            done
            exit 1
        fi
        malware_cmd="${MALWARE_CMD[$sample]}"

        # If file is set, copy it to tcentre and share via ISO
        if [ -n "$file_val" ]; then
            local_file="$file_val"
            if [ ! -f "$local_file" ]; then
                echo "Error: local file not found: $local_file"
                exit 1
            fi
            ext="${local_file##*.}"
            remote_tmp="/tmp/${sample}.${ext}"
            echo "=== Copying sample to $HOST ==="
            scp "$local_file" "$HOST:$remote_tmp"
            echo "=== Sharing sample to $vm via ISO ==="
            just vm share $vm "$remote_tmp"
            echo "ISO mounted — file available as D:\\${sample}.${ext} in VM"
            echo "Waiting 15s for Windows to detect CD..."
            sleep 15
        fi

        vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "$vm")
        pml_name="procmon-${sample}"
        mkdir -p "$run_outdir"

        echo "VM IP: $vmip"

        step=1

        if [ "$net_val" = "on" ]; then
            echo "=== Step $step: Start network capture ==="
            just da netcap start "$run_outdir"
            just da netcap inetsim-start "$run_outdir"
            sleep 2
            step=$((step + 1))
        fi

        if [ "$etw_val" = "on" ]; then
            echo "=== Step $step: Start ETW trace ==="
            just da trace start $vm "$sample"
            step=$((step + 1))
        fi

        echo "=== Step $step: Start ProcMon ==="
        just da procmon $vm start "$pml_name"
        step=$((step + 1))

        echo "=== Step $step: Execute malware ($sample) ==="
        {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" \
            "$malware_cmd" 15 || true
        echo "Malware executed"
        step=$((step + 1))

        echo "=== Step $step: Waiting ${wait_val}s for malware activity ==="
        sleep "$wait_val"
        step=$((step + 1))

        echo "=== Step $step: Stop ProcMon ==="
        just da procmon $vm stop
        step=$((step + 1))

        if [ "$etw_val" = "on" ]; then
            echo "=== Step $step: Stop ETW trace ==="
            just da trace stop $vm "$sample"
            step=$((step + 1))
        fi

        echo "=== Step $step: Pull PML from disk ==="
        echo "Stopping VM to extract PML..."
        just vm stop $vm
        sleep 2
        just disk pull $vm "C:/${pml_name}.PML" "$run_outdir/" || echo "WARNING: PML extraction failed (ProcMon may not have saved)"
        step=$((step + 1))

        if [ "$etw_val" = "on" ]; then
            echo "=== Step $step: Pull ETW traces ==="
            just da trace pull $vm "$sample" "$run_outdir"
            step=$((step + 1))
        fi

        if [ "$net_val" = "on" ]; then
            echo "=== Step $step: Stop network capture ==="
            just da netcap stop "$run_outdir"
            just da netcap inetsim-stop "$run_outdir"
            step=$((step + 1))
        fi

        echo ""
        echo "============================================"
        echo "Done! Traces saved to $run_outdir/"
        [ "$etw_val" = "on" ] && echo "  ETW: ${sample}.etl, ${sample}.csv"
        echo "  ProcMon: ${pml_name}.PML"
        [ "$net_val" = "on" ] && echo "  Network: capture-*.pcap"
        echo ""
        echo "Next steps:"
        echo "  just disk inspect $vm mount"
        echo "  just disk snapshot-state $vm post $run_outdir"
        echo "  just disk inspect $vm umount"
        echo "  just sa analyze $run_outdir"
        ;;

    gdb-run)
        # Parse: gdb-run <name> <script.py> <sample> <output> [port]
        name="${rest%% *}"
        rest2="${rest#* }"
        [ "$name" = "$rest2" ] && rest2=""
        script="${rest2%% *}"
        rest3="${rest2#* }"
        [ "$script" = "$rest3" ] && rest3=""
        gdb_sample="${rest3%% *}"
        rest4="${rest3#* }"
        [ "$gdb_sample" = "$rest4" ] && rest4=""
        output="${rest4%% *}"
        rest5="${rest4#* }"
        [ "$output" = "$rest5" ] && rest5=""
        port="${rest5:-1234}"

        if [ -z "$name" ] || [ -z "$script" ] || [ -z "$gdb_sample" ] || [ -z "$output" ]; then
            echo "Usage: just da gdb-run <name> <script.py> <sample> <output> [port=1234]"
            exit 1
        fi

        if [ ! -f "$script" ]; then
            echo "Error: Script not found: $script" >&2
            exit 1
        fi
        if [ ! -f "$gdb_sample" ]; then
            echo "Error: Sample not found: $gdb_sample" >&2
            exit 1
        fi
        sample_name="$(basename "$gdb_sample")"
        # Revert to clean state and stop VM
        echo "Reverting $name to clean snapshot..."
        just vm snapshot $name revert clean
        echo "Stopping $name for disk injection..."
        ssh {{HOST}} "virsh shutdown $name" 2>/dev/null || true
        for i in $(seq 1 30); do
            state=$(ssh {{HOST}} "virsh domstate $name" 2>/dev/null)
            [ "$state" = "shut off" ] && break
            sleep 1
        done
        if [ "$state" != "shut off" ]; then
            echo "Force stopping..."
            ssh {{HOST}} "virsh destroy $name" 2>/dev/null || true
            sleep 2
        fi
        # Inject sample into VM disk
        just disk inject $name "$gdb_sample"
        # Start VM and wait for boot
        echo "Starting $name..."
        ssh {{HOST}} "virsh start $name"
        echo "Waiting for VM to boot..."
        sleep 15
        # Start GDB server
        echo "Starting GDB server on ${name}:${port}..."
        ssh {{HOST}} "virsh qemu-monitor-command $name --hmp 'gdbserver tcp::${port}'" 2>/dev/null || true
        # Copy GDB script to host and start in background
        scp -q "$script" {{HOST}}:/tmp/gdb-run-script.py
        echo "Starting GDB..."
        ssh {{HOST}} "nohup gdb -batch -x /tmp/gdb-run-script.py > /tmp/gdb-run.log 2>&1 &"
        echo "Waiting for GDB to connect and set breakpoint..."
        sleep 10
        # Detonate the sample (rename .ex_ → .exe if needed)
        exe_name="${sample_name%.ex_}.exe"
        if [ "$exe_name" = "$sample_name" ]; then
            exe_name="$sample_name"
        fi
        echo "Detonating C:\\$exe_name..."
        if [ "$exe_name" != "$sample_name" ]; then
            just vm telnet $name "copy C:\\$sample_name C:\\$exe_name" || true
        fi
        just vm telnet $name "start C:\\$exe_name" || true
        # Wait for GDB to finish and collect output
        echo "Waiting for GDB to complete..."
        ssh {{HOST}} "while pgrep -f 'gdb.*gdb-run-script' >/dev/null; do sleep 2; done"
        ssh {{HOST}} "cat /tmp/gdb-run.log" | tee "$output"
        echo ""
        echo "Output saved to: $output"
        ;;

    "")
        echo "Usage: just da <subcommand> [args]"
        echo ""
        echo "Subcommands:"
        echo "  debug <name> [port]                    Attach GDB server to running VM"
        echo "  debug-trace <name> <config> [port]     GDB with trace config"
        echo "  trace <action> <vm> [args]             ETW/logman traces"
        echo "  procmon <name> start|stop|status [name] ProcMon management"
        echo "  memdump <vm> list|dump|run [args]       Process memory dump via ProcDump"
        echo "  virdump <vm> dump|list|analyze|clean    Full VM RAM dump via virsh"
        echo "  netcap <action> [outdir] [iface]        Network capture"
        echo "  detonate <vm> <sample> <outdir> [wait] [net] [etw] Execute malware (ProcMon + optional ETW/netcap)"
        echo "  gdb-run <name> <script> <sample> <out>  GDB Python script on VM"
        exit 1
        ;;

    *)
        echo "Unknown da subcommand: $da_action"
        echo "Usage: just da detonate|debug|debug-trace|trace|procmon|memdump|virdump|netcap|gdb-run [args]"
        exit 1
        ;;
    esac

# Static analysis: just sa re|analyze|disasm [args]
sa *args:
    #!/usr/bin/env bash
    set -euo pipefail
    args="{{args}}"
    sa_action="${args%% *}"
    rest="${args#* }"
    [ "$sa_action" = "$rest" ] && rest=""

    case "$sa_action" in
    re)
        # Parse: re <action> <file> [extra-args]
        action="${rest%% *}"
        rest2="${rest#* }"
        [ "$action" = "$rest2" ] && rest2=""
        file="${rest2%% *}"
        extra="${rest2#* }"
        [ "$file" = "$extra" ] && extra=""
        args="$extra"

        if [ -z "$action" ] || [ -z "$file" ]; then
            echo "Usage: just sa re <action> <file-or-project> [args...]"
            echo "Run 'just sa re help' for available actions."
            exit 1
        fi

        f="$file"
        project=""

    # Project-aware resolution: if file is a project name, resolve binary from projects/config.yaml
    if [ ! -f "$f" ] && [ -d "projects/$f" ]; then
        project="$f"
        projdir="projects/$project"
        artifacts="projects/config.yaml"

        # Helper: look up a value from config.yaml under <project>.<section>.<key>
        # Usage: yaml_lookup <section> <key>
        yaml_lookup() {
            local section="$1" key="$2"
            [ ! -f "$artifacts" ] && return
            awk -v proj="$project" -v sec="$section" -v k="$key" '
                /^[^ #]/ { cur_proj = $0; sub(/:.*/, "", cur_proj) }
                cur_proj == proj && /^  [^ ]/ { cur_sec = $0; gsub(/[: ]/, "", cur_sec) }
                cur_proj == proj && cur_sec == sec && $0 ~ "^    " k ":" {
                    val = $0; sub(/.*: */, "", val); sub(/ *#.*/, "", val)
                    gsub(/["\x27]/, "", val); gsub(/^ *| *$/, "", val)
                    if (val != "") print val; exit
                }
            ' "$artifacts"
        }

        # Check if a filename or --flag was passed in args
        exe_key=""
        explicit_file=""
        remaining_args=""
        for a in $args; do
            case "$a" in
                --original)          exe_key="original" ;;
                --unpacked)          exe_key="unpacked" ;;
                --packed|--packed-*) exe_key="packed_exe" ;;
                --dump)              exe_key="dump" ;;
                *)
                    # If it's a file in exe/, use it directly
                    if [ -f "$projdir/exe/$a" ]; then
                        explicit_file="$a"
                    else
                        remaining_args="$remaining_args $a"
                    fi
                    ;;
            esac
        done
        args="${remaining_args# }"

        if [ -n "$explicit_file" ]; then
            # Direct filename: just sa re pe xorist X.ex_
            f="$projdir/exe/$explicit_file"
            echo "Project: $project → $f"
        else
            if [ -z "$exe_key" ]; then
                # Per-action default: some targets need unpacked code
                case "$action" in
                    crypto|decompile|annotate|annotate-deep|context|ghidra-decompile|trampolines|globals)
                        exe_key="unpacked"
                        ;;
                    *)
                        # Use sa.default from config.yaml
                        exe_key=""
                        configured=$(yaml_lookup sa default)
                        [ -n "$configured" ] && exe_key="$configured"
                        [ -z "$exe_key" ] && exe_key="unpacked"
                        ;;
                esac
            fi

            # Priority 1: project.yaml ghidra_program (authoritative, set by pipeline)
            proj_yaml="$projdir/project.yaml"
            if [ -f "$proj_yaml" ]; then
                gp=$(grep "^ghidra_program:" "$proj_yaml" | sed 's/^[^:]*: *//' | sed 's/ *#.*//' | tr -d '"')
                if [ -n "$gp" ] && [ -f "$projdir/exe/$gp" ]; then
                    resolved="$gp"
                    f="$projdir/exe/$gp"
                fi
            fi

            # Priority 2: config.yaml exe.<key> (legacy nested config)
            if [ -z "$f" ]; then
                resolved=$(yaml_lookup exe "$exe_key")
                if [ -n "$resolved" ] && [ -f "$projdir/exe/$resolved" ]; then
                    f="$projdir/exe/$resolved"
                fi
            fi
            if [ -z "$f" ]; then
                # Fallback 2: find first binary in exe/
                f=$(find "$projdir/exe" -maxdepth 1 -type f \( -name '*.exe' -o -name '*.dll' -o -name '*.elf' -o -name '*.bin' -o -name '*.dmp' \) 2>/dev/null | head -1)
                if [ -z "$f" ]; then
                    echo "No binary found in $projdir/exe/"
                    echo "Place your sample there and update $artifacts"
                    exit 1
                fi
                [ -n "$resolved" ] && echo "Warning: '$exe_key: $resolved' not found, using fallback: $f" >&2
            fi
            # Show which exe was selected and how to switch
            alt_key=""
            case "$exe_key" in
                packed_exe|original) alt_key="unpacked" ;;
                unpacked)            alt_key="packed" ;;
            esac
            hint=""
            [ -n "$alt_key" ] && hint="  (switch: --${alt_key})"
            echo "Project: $project ($exe_key) → $f${hint}"
        fi
        echo ""
    fi

    # known-plaintext accepts VM names, not just files
    if [ "$action" != "known-plaintext" ] && [ ! -f "$f" ]; then
        echo "File not found: $f"
        exit 1
    fi

    case "$action" in
    pe)
        echo "=== File Info ==="
        file "$f"
        echo "Size: $(stat -c%s "$f") bytes"
        echo ""
        echo "=== Hashes ==="
        sha256sum "$f"
        md5sum "$f"
        echo ""

        echo "=== Packer Detection ==="
        packer=$(file "$f" | grep -oiE '\bUPX\b|\bASPack\b|\bPECompact\b|\bThemida\b|\bVMProtect\b|\bArmadillo\b|\bMPRESS\b|\bMEW\b|\bFSG\b|\bPetite\b|\bNsPack\b|\btElock\b' || true)
        if [ -n "$packer" ]; then
            echo "Detected by file(1): $packer"
        else
            echo "file(1): No known packer detected"
        fi
        echo ""
        if command -v upx &>/dev/null; then
            echo "=== UPX Unpack Test ==="
            tmp="/tmp/re-upx-test-$$.exe"
            cp "$f" "$tmp"
            if upx -t "$tmp" 2>&1; then
                echo "UPX: valid, can unpack with: upx -d <file>"
            else
                echo "UPX: not standard UPX (may be modified header)"
            fi
            rm -f "$tmp"
            echo ""
        fi

        echo "=== PE Metadata ==="
        r2 -q -e bin.cache=true -c 'iI' "$f" 2>/dev/null
        echo ""

        echo "=== Sections + Entropy ==="
        r2 -q -e bin.cache=true -c 'iS entropy' "$f" 2>/dev/null
        echo ""
        echo "Entropy guide: >7.0 = likely packed/encrypted, 5-7 = normal code, <5 = data/resources"
        echo ""

        echo "=== Entry Point ==="
        r2 -q -e bin.cache=true -c 'ie' "$f" 2>/dev/null
        echo ""

        echo "=== Imports (DLLs) ==="
        r2 -q -e bin.cache=true -c 'il' "$f" 2>/dev/null
        echo ""

        echo "=== Imports (functions) ==="
        imports=$(r2 -q -e bin.cache=true -c 'ii' "$f" 2>/dev/null || true)
        if [ -n "$imports" ]; then
            echo "$imports"
        else
            echo "  (no import table — packed or memory-dumped PE)"
        fi
        echo ""

        echo "=== Exports ==="
        r2 -q -e bin.cache=true -c 'iE' "$f" 2>/dev/null
        echo ""

        echo "=== Resources ==="
        r2 -q -e bin.cache=true -c 'iR' "$f" 2>/dev/null
        echo ""

        echo "=== Strings ==="
        # Extract strings with section info via r2 JSON, categorize per section
        r2 -q -e bin.cache=true -e str.search.min=6 -c 'izzj' "$f" 2>/dev/null \
            | "{{PYTHON}}" "{{VIVI}}/scripts/strings-by-section.py"
        ;;

    crypto)
        echo "=== Crypto Algorithm Detection ==="
        echo "Scanning: $f"
        echo ""

        found=0

        # TEA/XTEA/XXTEA — delta constant 0x9E3779B9
        hits=$(r2 -q -e bin.cache=true -c '/x b979379e' "$f" 2>/dev/null | grep -c 'hit' || true)
        if [ "$hits" -gt 0 ]; then
            echo "TEA/XTEA/XXTEA:  $hits hits (delta=0x9E3779B9)"
            r2 -q -e bin.cache=true -c '/x b979379e' "$f" 2>/dev/null | grep 'hit'
            echo ""
            found=1
        fi

        # AES — Rijndael S-box (first 8 bytes)
        hits=$(r2 -q -e bin.cache=true -c '/x 637c777bf26b6fc5' "$f" 2>/dev/null | grep -c 'hit' || true)
        if [ "$hits" -gt 0 ]; then
            echo "AES (Rijndael):   $hits hits (S-box match)"
            r2 -q -e bin.cache=true -c '/x 637c777bf26b6fc5' "$f" 2>/dev/null | grep 'hit'
            echo ""
            found=1
        fi

        # Blowfish — P-array starts with pi digits 0x243F6A88
        hits=$(r2 -q -e bin.cache=true -c '/x 886a3f24' "$f" 2>/dev/null | grep -c 'hit' || true)
        if [ "$hits" -gt 0 ]; then
            echo "Blowfish:         $hits hits (P-array=0x243F6A88)"
            r2 -q -e bin.cache=true -c '/x 886a3f24' "$f" 2>/dev/null | grep 'hit'
            echo ""
            found=1
        fi

        # RC5/RC6 — constant 0xB7E15163
        hits=$(r2 -q -e bin.cache=true -c '/x 6351e1b7' "$f" 2>/dev/null | grep -c 'hit' || true)
        if [ "$hits" -gt 0 ]; then
            echo "RC5/RC6:          $hits hits (P=0xB7E15163)"
            r2 -q -e bin.cache=true -c '/x 6351e1b7' "$f" 2>/dev/null | grep 'hit'
            echo ""
            found=1
        fi

        # MD5 — init constant 0x67452301
        hits=$(r2 -q -e bin.cache=true -c '/x 01234567' "$f" 2>/dev/null | grep -c 'hit' || true)
        if [ "$hits" -gt 0 ]; then
            echo "MD5/SHA-1:        $hits hits (init=0x67452301)"
            r2 -q -e bin.cache=true -c '/x 01234567' "$f" 2>/dev/null | grep 'hit'
            echo ""
            found=1
        fi

        # SHA-256 — init constant 0x6A09E667
        hits=$(r2 -q -e bin.cache=true -c '/x 67e6096a' "$f" 2>/dev/null | grep -c 'hit' || true)
        if [ "$hits" -gt 0 ]; then
            echo "SHA-256:          $hits hits (init=0x6A09E667)"
            r2 -q -e bin.cache=true -c '/x 67e6096a' "$f" 2>/dev/null | grep 'hit'
            echo ""
            found=1
        fi

        # CRC32 — polynomial 0xEDB88320
        hits=$(r2 -q -e bin.cache=true -c '/x 2083b8ed' "$f" 2>/dev/null | grep -c 'hit' || true)
        if [ "$hits" -gt 0 ]; then
            echo "CRC32:            $hits hits (poly=0xEDB88320)"
            r2 -q -e bin.cache=true -c '/x 2083b8ed' "$f" 2>/dev/null | grep 'hit'
            echo ""
            found=1
        fi

        # ChaCha20/Salsa20 — "expand 32-byte k"
        hits=$(r2 -q -e bin.cache=true -c '/x 657870616e642033322d62797465206b' "$f" 2>/dev/null | grep -c 'hit' || true)
        if [ "$hits" -gt 0 ]; then
            echo "ChaCha20/Salsa20: $hits hits (\"expand 32-byte k\")"
            r2 -q -e bin.cache=true -c '/x 657870616e642033322d62797465206b' "$f" 2>/dev/null | grep 'hit'
            echo ""
            found=1
        fi

        # Windows CryptoAPI imports
        echo "=== Windows CryptoAPI Imports ==="
        crypto_imports=$(r2 -q -e bin.cache=true -c 'ii' "$f" 2>/dev/null | grep -i 'crypt\|hash' || true)
        if [ -n "$crypto_imports" ]; then
            echo "$crypto_imports"
            found=1
        else
            echo "  None"
        fi
        echo ""

        if [ "$found" -eq 0 ]; then
            echo "No known crypto constants found."
            echo "May use custom/obfuscated crypto, or constants are encrypted by packer."
        fi
        ;;

    unpack)
        echo "=== Extract Unpacked PE from Memory Dump ==="
        echo ""

        # Check if input is a .dmp file
        if [[ "$f" != *.dmp ]]; then
            echo "Expected a .dmp file (ProcDump minidump), got: $f"
            exit 1
        fi

        if ! "{{PYTHON}}" -c "import minidump" 2>/dev/null; then
            echo "ERROR: minidump package not found."
            echo "Install: $(dirname "{{PYTHON}}")/pip install minidump"
            exit 1
        fi

        # Derive output name: foo.dmp -> foo-unpacked.exe
        # In project mode, save to projects/<name>/exe/
        if [ -n "$project" ]; then
            outdir="projects/$project/exe"
        else
            outdir=$(dirname "$f")
        fi
        basename=$(basename "$f" .dmp)
        outfile="${outdir}/${basename}-unpacked.exe"

        "$PYTHON" "{{VIVI}}/scripts/extract-pe-from-dump.py" "$f" "$outfile"

        echo ""
        echo "=== Verification ==="
        file "$outfile"
        echo "Size: $(stat -c%s "$outfile") bytes"
        echo ""

        # Auto-run packing + crypto checks on the extracted PE
        echo "=== Packing Check ==="
        packer=$(file "$outfile" | grep -oiE '\bUPX\b|\bASPack\b|\bPECompact\b|\bThemida\b|\bVMProtect\b' || true)
        if [ -n "$packer" ]; then
            echo "PE header still says: $packer (section names from packer, but code is unpacked)"
        else
            echo "No packer signatures in PE header"
        fi
        echo ""

        echo "=== Section Entropy ==="
        r2 -q -e bin.cache=true -c 'iS entropy' "$outfile" 2>/dev/null
        echo ""

        echo "=== Crypto Constants ==="
        for pattern_name in "TEA:b979379e" "AES:637c777bf26b6fc5" "Blowfish:886a3f24"; do
            name="${pattern_name%%:*}"
            hex="${pattern_name##*:}"
            hits=$(r2 -q -e bin.cache=true -c "/x $hex" "$outfile" 2>/dev/null | grep -c 'hit' || true)
            if [ "$hits" -gt 0 ]; then
                echo "  $name: $hits hits"
            fi
        done
        echo ""

        echo "=== Interesting Strings ==="
        strings "$outfile" | grep -iE '\.exe|decrypt|encrypt|password|\.enciphered|how to|ransom|key|registry\\\\.*run|seed|temp\\\\' | sort -u | head -30
        echo ""
        total_strings=$(strings "$outfile" | wc -l)
        echo "Total strings: $total_strings (use 'just sa re pe $outfile' for full analysis)"

        # Auto-update config.yaml in project mode
        if [ -n "$project" ]; then
            artifacts="projects/config.yaml"
            outname=$(basename "$outfile")
            if [ -f "$artifacts" ]; then
                # Update the unpacked: line within this project's exe: block
                awk -v proj="$project" -v val="$outname" '
                    /^[^ #]/ { cur = $0; sub(/:.*/, "", cur) }
                    cur == proj && /^\s*unpacked:/ { $0 = "    unpacked: " val; done=1 }
                    { print }
                ' "$artifacts" > "${artifacts}.tmp" && mv "${artifacts}.tmp" "$artifacts"
                echo "Updated $artifacts: $project.exe.unpacked → $outname"
            fi
        fi
        ;;

    decompile)
        # Auto-save path: projects/<name>/sa/ in project mode, else next to input file
        if [ -n "$project" ]; then
            outdir="projects/$project/sa"
        else
            outdir=$(dirname "$f")
        fi
        basename=$(basename "$f" | sed 's/\.[^.]*$//')
        outfile="${outdir}/${basename}-pseudocode.txt"

        # Strip ANSI codes helper
        strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

        {
        echo "=== Pseudo-code Decompilation ==="
        echo "File: $f"
        echo ""

        # Analyze and list real functions (skip tiny IAT stubs ≤ 6 bytes)
        echo "=== Functions ==="
        funcs=$(r2 -q -e bin.cache=true -c 'aaa; afl' "$f" 2>/dev/null | strip_ansi)
        echo "$funcs" | awk '{if ($3 > 6) print}' | while read -r line; do
            addr=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{print $3}')
            name=$(echo "$line" | awk '{print $4}')
            echo "  $addr  ${size}B  $name"
        done
        echo ""

        # Find crypto constants and mark which functions contain them
        echo "=== Crypto Constant References ==="
        refs=$(r2 -q -e bin.cache=true -c 'aaa; /x b979379e' "$f" 2>/dev/null | strip_ansi)
        if echo "$refs" | grep -q 'hit'; then
            echo "  TEA delta 0x9E3779B9:"
            echo "$refs" | grep 'hit' | while read -r line; do
                addr=$(echo "$line" | awk '{print $1}')
                echo "    $addr"
            done
        fi
        echo ""

        # Check if r2ghidra is available (pdg = real C decompilation)
        if r2 -q -c 'e asm.arch=x86; pdg' /dev/null 2>&1 | grep -q 'Missing plugin'; then
            echo "=== Pseudo-code (r2 pdc — install r2ghidra for C output: ansible-playbook ansible/setup-local.yml) ==="
            decomp_cmd="pdc"
        else
            echo "=== Decompiled C (r2ghidra pdg) ==="
            decomp_cmd="pdg"
        fi

        r2 -q -e bin.cache=true -c 'aaa; afl' "$f" 2>/dev/null | strip_ansi | awk '{if ($3 > 6) print $1, $4}' | while read -r addr name; do
            echo ""
            echo "// ────────────────────────────────────────"
            echo "// $name ($addr)"
            echo "// ────────────────────────────────────────"
            r2 -q -e bin.cache=true -c "aaa; $decomp_cmd @ $name" "$f" 2>/dev/null | strip_ansi
        done
        } | tee "$outfile"

        echo ""
        echo "Saved: $outfile ($(wc -l < "$outfile") lines)"
        ;;

    annotate)
        # Annotate decompiled pseudo-code with meaningful names and comments
        # Input: a -pseudocode.txt file (from decompile action), or a PE (auto-decompiles first)
        if [[ "$f" == *.exe || "$f" == *.dll ]]; then
            # Auto-decompile first — look in sa/ for project mode
            if [ -n "$project" ]; then
                outdir="projects/$project/sa"
            else
                outdir=$(dirname "$f")
            fi
            basename_no_ext=$(basename "$f" | sed 's/\.[^.]*$//')
            pseudocode="${outdir}/${basename_no_ext}-pseudocode.txt"
            if [ ! -f "$pseudocode" ]; then
                echo "Decompiling first..."
                just sa re decompile "$f"
            fi
            f="$pseudocode"
        fi

        if [ ! -f "$f" ]; then
            echo "File not found: $f"
            echo "Usage: just sa re annotate <pseudocode.txt or binary.exe>"
            exit 1
        fi

        if [ -n "$project" ]; then
            outdir="projects/$project/sa"
        else
            outdir=$(dirname "$f")
        fi
        basename_no_ext=$(basename "$f" | sed 's/-pseudocode\.txt$//' | sed 's/\.[^.]*$//')
        annotated="${outdir}/${basename_no_ext}-annotated.c"

        "{{VIVI}}/scripts/annotate.sh" "$f" "$annotated"
        ;;

    context)
        # Auto-generate context file for annotate-deep from packing/crypto/strings analysis
        if [ ! -f "$f" ]; then
            echo "File not found: $f"
            echo "Usage: just sa re context <binary.exe>"
            exit 1
        fi
        if [ -n "$project" ]; then
            outdir="projects/$project/sa"
        else
            outdir=$(dirname "$f")
        fi
        basename_no_ext=$(basename "$f" | sed 's/\.[^.]*$//')
        context_file="${outdir}/context.txt"

        echo "=== Generating context from static analysis ==="
        echo "Collecting packing, crypto, and strings data..."

        # Run all three analyses and capture output
        analysis=$(
            echo "=== PE ANALYSIS ==="
            just sa re pe "$f" 2>/dev/null
            echo ""
            echo "=== CRYPTO ANALYSIS ==="
            just sa re crypto "$f" 2>/dev/null
        )

        echo "$analysis" | CLAUDECODE= claude -p "$(cat "{{VIVI}}/scripts/context-prompt.txt")" --allowedTools "" 2>/dev/null \
            | grep -v '^```' > "$context_file"

        lines=$(wc -l < "$context_file")
        echo ""
        echo "Saved: $context_file ($lines lines)"
        cat "$context_file"
        ;;

    annotate-deep)
        # Deep annotation: Ghidra decompile → call graph → bottom-up LLM annotation
        # Input: PE binary. Optional: --context <file> for sample-specific notes
        if [ ! -f "$f" ]; then
            echo "File not found: $f"
            echo "Usage: just sa re annotate-deep <binary.exe> [--context <notes.txt>]"
            exit 1
        fi
        ctx_args=""
        basename_no_ext=$(basename "$f" | sed 's/\.[^.]*$//')
        if [ -n "$project" ]; then
            output_file="projects/$project/sa/${basename_no_ext}-annotated-deep.c"
            auto_ctx="projects/$project/sa/context.txt"
        else
            output_file=""
            auto_ctx="$(dirname "$f")/context.txt"
        fi
        if echo "$args" | grep -q -- '--context'; then
            ctx_file=$(echo "$args" | sed 's/.*--context //' | awk '{print $1}')
            ctx_args="--context $ctx_file"
        else
            # Auto-generate context if not provided
            if [ ! -f "$auto_ctx" ]; then
                echo "No --context provided, auto-generating..."
                just sa re context "$f"
            fi
            if [ -f "$auto_ctx" ]; then
                ctx_args="--context $auto_ctx"
            fi
        fi
        "{{VIVI}}/scripts/annotate-deep.sh" "$f" "$output_file" $ctx_args
        ;;

    ghidra-decompile)
        # Ghidra headless decompile only (produces functions.json + callgraph.json)
        if [ ! -f "$f" ]; then
            echo "File not found: $f"
            echo "Usage: just sa re ghidra-decompile <binary.exe>"
            exit 1
        fi
        basename_no_ext=$(basename "$f" | sed 's/\.[^.]*$//')
        if [ -n "$project" ]; then
            workdir="projects/$project/sa/${basename_no_ext}-ghidra"
        else
            workdir="$(dirname "$f")/${basename_no_ext}-ghidra"
        fi
        mkdir -p "$workdir"

        echo "=== Ghidra headless decompilation ==="
        echo "Output: $workdir/"
        eval "$(micromamba shell hook -s bash)"
        micromamba activate ~/micromamba-base
        "{{PYTHON}}" "{{VIVI}}/scripts/ghidra/export.py" "$f" "$workdir"

        echo ""
        echo "Functions: $("{{PYTHON}}" -c "import json; print(len(json.load(open('$workdir/functions.json'))))")"
        echo "Files: $workdir/functions.json, $workdir/callgraph.json"
        ;;

    known-plaintext)
        echo "=== Known-Plaintext Attack ==="
        echo ""

        # f can be:
        #   1. Two local files: "original.txt encrypted.txt.EnCiPhErEd"
        #   2. A VM instance name (mounts template + instance disks)
        # Detect mode by checking if f contains a space (two files) or is a VM name

        # Check if it's two files separated by space — but justfile already split on space
        # So f is actually the first arg. We need to handle this differently.
        # For file-pair mode, use: just sa re known-plaintext "orig encrypted"
        # For VM mode, use: just sa re known-plaintext <vm-instance>

        if [ -f "$f" ]; then
            # Single file — error, need two files or a VM name
            echo "For file pair mode, provide two paths:"
            echo "  just sa re known-plaintext 'original.txt encrypted.txt.EnCiPhErEd'"
            echo ""
            echo "For VM disk mode, provide the instance name:"
            echo "  just sa re known-plaintext <vm-instance>"
            exit 1
        fi

        # Check if two files were provided (space-separated in quotes)
        if echo "$f" | grep -q ' '; then
            orig_file="${f%% *}"
            enc_file="${f#* }"
            if [ -f "$orig_file" ] && [ -f "$enc_file" ]; then
                "{{PYTHON}}" "{{VIVI}}/scripts/known-plaintext.py" "$orig_file" "$enc_file"
                exit 0
            fi
        fi

        # VM disk mode — mount template (clean) and instance (infected) via NBD
        vm_name="$f"
        echo "VM instance: $vm_name"
        echo ""

        source "{{VIVI}}/scripts/lib.sh"
        setup_host "{{HOST}}"

        # Find the instance disk and its backing template
        inst_img="${KVMDIR}/instances/${vm_name}.qcow2"
        if ! ssh "{{HOST}}" "test -f '$inst_img'"; then
            echo "Instance disk not found: $inst_img"
            echo "Is the VM stopped with --keep? (just vm stop <vm> --keep)"
            exit 1
        fi

        # Get the backing file (template) from the qcow2 header
        template=$(ssh "{{HOST}}" "qemu-img info '$inst_img' 2>/dev/null | grep 'backing file:' | sed 's/backing file: //'")
        if [ -z "$template" ]; then
            echo "No backing file found — instance is not based on a template"
            echo "Cannot determine clean reference disk"
            exit 1
        fi
        echo "Template (clean): $template"
        echo "Instance (infected): $inst_img"
        echo ""

        # Mount both disks via NBD on different devices
        mnt_clean="${KVMDIR}/mnt/${vm_name}-clean"
        mnt_infected="${KVMDIR}/mnt/${vm_name}-infected"

        # Create mount points
        ssh "$HOST_ROOT_VAL" "mkdir -p '$mnt_clean' '$mnt_infected'"

        echo "=== Mounting clean template on nbd0 ==="
        nbd_connect "$template" /dev/nbd0
        ssh "$HOST_ROOT_VAL" "ntfs-3g -o ro /dev/nbd0p1 '$mnt_clean' 2>/dev/null || mount -t ntfs3 -o ro /dev/nbd0p1 '$mnt_clean' 2>/dev/null || mount -o ro /dev/nbd0p1 '$mnt_clean'"
        echo "Mounted: $mnt_clean"

        echo ""
        echo "=== Mounting infected instance on nbd1 ==="
        nbd_connect "$inst_img" /dev/nbd1
        ssh "$HOST_ROOT_VAL" "ntfs-3g -o ro /dev/nbd1p1 '$mnt_infected' 2>/dev/null || mount -t ntfs3 -o ro /dev/nbd1p1 '$mnt_infected' 2>/dev/null || mount -o ro /dev/nbd1p1 '$mnt_infected'"
        echo "Mounted: $mnt_infected"

        echo ""
        echo "=== Detecting encrypted extension ==="
        # Find encrypted files by looking for common ransomware extensions
        ext=$(ssh "$HOST_ROOT_VAL" "find '$mnt_infected' -maxdepth 4 -type f \( -name '*.EnCiPhErEd' -o -name '*.encrypted' -o -name '*.locked' -o -name '*.crypto' -o -name '*.crypt' \) 2>/dev/null | head -1 | grep -oP '\\.[^.]+$'" 2>/dev/null || true)
        ext="${ext:-.EnCiPhErEd}"
        echo "Encrypted extension: $ext"
        echo ""

        # Run the known-plaintext analysis remotely (files are on the host)
        # Copy the script to the host and run there
        scp -q "{{VIVI}}/scripts/known-plaintext.py" "{{HOST}}:/tmp/known-plaintext.py"
        ssh "{{HOST}}" "python3 /tmp/known-plaintext.py --dir '$mnt_clean' '$mnt_infected' --ext '$ext' --limit 5"

        echo ""
        echo "=== Cleanup ==="
        # Unmount both
        nbd_disconnect "$mnt_infected" /dev/nbd1
        nbd_disconnect "$mnt_clean" /dev/nbd0
        ssh "$HOST_ROOT_VAL" "rmdir '$mnt_clean' '$mnt_infected' 2>/dev/null" || true
        echo "Done."
        ;;

    trampolines)
        # Scan PE/dump for FF 25 (JMP [addr]) and FF 15 (CALL [addr]) trampolines
        "{{PYTHON}}" "{{VIVI}}/scripts/find-trampolines.py" "$f"
        ;;

    globals)
        # Scan PE for absolute memory references to data sections (Ghidra's DAT_ addresses)
        "{{PYTHON}}" "{{VIVI}}/scripts/find-globals.py" "$f"
        ;;

    byte-dist|byte-dist-freq)
        # Interactive byte frequency distribution (plotly in browser)
        # byte-dist: sorted by hex value (00-FF), byte-dist-freq: sorted by frequency (most common first)
        sort_mode="hex"
        if [ "$action" = "byte-dist-freq" ]; then sort_mode="freq"; fi
        xxd -p "$f" | fold -w2 | sort | uniq -c | awk '{print $2, $1}' | Rscript -e '
            library(plotly)
            d <- read.table("stdin", col.names=c("byte","count"))
            sort_mode <- commandArgs(TRUE)[2]
            if (sort_mode == "freq") {
                d <- d[order(-d$count),]
            } else {
                d <- d[order(strtoi(d$byte,16)),]
            }
            fname <- commandArgs(TRUE)[1]
            total <- sum(d$count)
            zero_count <- d$count[d$byte == "00"]
            if (length(zero_count) == 0) zero_count <- 0
            zero_pct <- sprintf("%.1f", 100 * zero_count / total)
            ff_count <- d$count[d$byte == "ff"]
            if (length(ff_count) == 0) ff_count <- 0
            ff_pct <- sprintf("%.1f", 100 * ff_count / total)
            sort_label <- if (sort_mode == "freq") " [by frequency]" else ""
            title <- paste0(fname, " (", total, " bytes, 0x00: ", zero_pct, "%, 0xFF: ", ff_pct, "%)", sort_label)
            d <- d[d$byte != "00",]
            d$byte <- factor(d$byte, levels=d$byte)
            p <- plot_ly(d, x=~byte, y=~count, type="bar", marker=list(color="steelblue")) |> layout(title=list(text=title, font=list(size=28, color="white")), xaxis=list(title="Byte (hex)", categoryorder="array", categoryarray=d$byte), yaxis=list(title="Count"), margin=list(t=80), paper_bgcolor="#1e1e1e", plot_bgcolor="#2d2d2d", font=list(color="#cccccc"))
            htmlwidgets::saveWidget(p, "/tmp/byte-dist.html", selfcontained=TRUE)
            browseURL("/tmp/byte-dist.html")
        ' "$(basename "$f")" "$sort_mode"
        ;;

    yara)
        echo "=== YARA Scan ==="
        echo "File: $f"
        echo ""
        if ! command -v yara &>/dev/null; then
            echo "yara not installed. Install with: sudo apt install yara"
            exit 1
        fi
        # Search for rules: explicit path in args, or scan repo for .yar/.yara files
        if [ -n "$args" ] && [ -f "$args" ]; then
            echo "--- $(basename "$args") ---"
            yara "$args" "$f" 2>&1 || echo "  (no match)"
        elif [ -n "$args" ] && [ -d "$args" ]; then
            rules=$(find "$args" -name '*.yar' -o -name '*.yara' 2>/dev/null)
            if [ -z "$rules" ]; then
                echo "No YARA rules found in: $args"
            else
                echo "$rules" | while read -r rule; do
                    echo "--- $(basename "$rule") ---"
                    yara "$rule" "$f" 2>&1 || echo "  (no match)"
                    echo ""
                done
            fi
        else
            # Search current directory tree
            rules=$(find "." -name '*.yar' -o -name '*.yara' 2>/dev/null)
            if [ -z "$rules" ]; then
                echo "No YARA rules found in current directory."
                echo "Usage: just sa re yara <file> [rules-file-or-dir]"
            else
                echo "$rules" | while read -r rule; do
                    echo "--- $(basename "$rule") ---"
                    yara "$rule" "$f" 2>&1 || echo "  (no match)"
                    echo ""
                done
            fi
        fi
        ;;

    vt)
        echo "=== VirusTotal Lookup (hash only, no upload) ==="
        echo ""
        api_key="${VT_API_KEY:-}"
        if [ -z "$api_key" ]; then
            echo "VT_API_KEY not set. Export it or skip this step."
            echo "  export VT_API_KEY=your_key"
            exit 1
        fi
        hash=$(sha256sum "$f" | awk '{print $1}')
        echo "File: $f"
        echo "SHA256: $hash"
        echo ""
        response=$(curl -s -H "x-apikey: $api_key" \
            "https://www.virustotal.com/api/v3/files/$hash")
        echo "$response" | "{{PYTHON}}" -c "
    import json, sys
    try:
        d = json.load(sys.stdin)
        a = d.get('data', {}).get('attributes', {})
        if not a:
            err = d.get('error', {})
            if err:
                print(f\"VT Error: {err.get('code', 'unknown')} — {err.get('message', '')}\")
            else:
                print('Not found on VirusTotal')
            sys.exit(0)
        print(f\"Name:           {a.get('meaningful_name', 'n/a')}\")
        print(f\"Type:           {a.get('type_description', 'n/a')}\")
        stats = a.get('last_analysis_stats', {})
        mal = stats.get('malicious', 0)
        total = sum(stats.values())
        print(f\"Detection:      {mal}/{total}\")
        print(f\"Popular threat: {a.get('popular_threat_classification', {}).get('suggested_threat_label', 'n/a')}\")
        names = a.get('names', [])[:5]
        if names:
            print(f\"Known names:    {', '.join(names)}\")
        tags = a.get('tags', [])
        if tags:
            print(f\"Tags:           {', '.join(tags)}\")
        print(f\"First seen:     {a.get('first_submission_date', 'n/a')}\")
        print(f\"Last analysis:  {a.get('last_analysis_date', 'n/a')}\")
        results = a.get('last_analysis_results', {})
        detections = [(k, v['result']) for k, v in results.items() if v.get('category') == 'malicious' and v.get('result')]
        if detections:
            print()
            print('Top detections:')
            for av, result in sorted(detections)[:15]:
                print(f'  {av:25s} {result}')
    except Exception as e:
        print(f'Parse error: {e}')
        print(sys.stdin.read()[:500])
    " 2>&1
        echo ""
        ;;

    insn-stats)
        # Instruction frequency statistics per PE section (capstone + lief)
        "{{PYTHON}}" "{{VIVI}}/scripts/insn-stats.py" "$f" $args
        ;;

    heuristics)
        # Scan for malware-typical assembly patterns (PEB walk, API hashing, XOR loops, etc.)
        "{{PYTHON}}" "{{VIVI}}/scripts/malware-heuristics.py" "$f" $args
        ;;

    *)
        echo "Usage: just sa re <action> <file-or-project> [args...]"
        echo ""
        echo "Actions:"
        echo "  pe               Full PE analysis: file info, hashes, packing, sections, imports, exports, resources, strings"
        echo "  crypto           Detect known encryption algorithms (TEA, AES, Blowfish, etc.)"
        echo "  unpack           Extract unpacked PE from ProcDump .dmp file"
        echo "  yara             YARA rule scan: just sa re yara <file> [rules-file-or-dir]"
        echo "  vt               VirusTotal hash lookup (requires VT_API_KEY, no upload)"
        echo "  decompile        Generate pseudo-code for all functions (r2ghidra C or r2 pdc)"
        echo "  annotate         Add function names + comments via Claude (from .exe or pseudocode.txt)"
        echo "  annotate-deep    Ghidra decompile → call graph → bottom-up LLM annotation"
        echo "  context          Auto-generate context file for annotate-deep"
        echo "  ghidra-decompile Ghidra headless decompile (functions.json + callgraph.json)"
        echo "  known-plaintext  Extract encryption key by comparing clean vs encrypted files"
        echo "  trampolines      Scan PE for FF 25/FF 15 indirect JMP/CALL trampolines (IAT thunks)"
        echo "  globals          Scan PE for global variable references (Ghidra DAT_ addresses)"
        echo "  byte-dist        Interactive byte frequency distribution (plotly, sorted by hex value)"
        echo "  byte-dist-freq   Same as byte-dist but sorted by frequency (most common first)"
        echo "  insn-stats       Instruction frequency per section [--top N] [--section NAME]"
        echo "  heuristics       Scan for malware assembly patterns (XOR loops, PEB walk, anti-debug) [-v]"
        echo ""
        echo "Project mode (auto-resolves binary from projects/<name>/exe/):"
        echo "  just sa re pe xorist                       # Same as: just sa re pe projects/xorist/exe/xorist-dump-unpacked.exe"
        echo "  just sa re decompile xorist                # Output → projects/xorist/sa/"
        echo "  just sa re annotate-deep xorist            # Output → projects/xorist/sa/"
        echo ""
        echo "Typical workflow:"
        echo "  just sa re pe sample.exe                   # Full PE triage"
        echo "  just sa re crypto sample.exe               # What crypto does it use?"
        echo "  just sa re yara sample.exe rules/          # Scan with YARA rules"
        echo "  just sa re vt sample.exe                   # Check VirusTotal"
        echo "  just da memdump <vm> run <cmd> 8 dump ./   # Dump unpacked from memory"
        echo "  just sa re unpack dump.dmp                 # Extract PE -> dump-unpacked.exe"
        echo "  just sa re pe dump-unpacked.exe            # Analyze the unpacked PE"
        echo ""
        echo "Known-plaintext attack (extract encryption key):"
        echo "  just sa re known-plaintext <vm-instance>                # Mount template + instance"
        echo "  just sa re known-plaintext 'original.txt encrypted.txt' # Compare two local files"
        exit 1
        ;;
    esac
        ;; # end re)

    analyze)
        # Parse: analyze <dir> [--json]
        dir="${rest%% *}"
        rest2="${rest#* }"
        [ "$dir" = "$rest2" ] && rest2=""
        flags="$rest2"

        if [ -z "$dir" ]; then
            echo "Usage: just sa analyze <artifacts-dir> [--json]"
            echo ""
            echo "Runs filesystem diff, registry diff, and ProcMon CSV analysis"
            echo "on baseline/post files in the given directory."
            echo ""
            echo "Expected files:"
            echo "  baseline-files.txt, post-files.txt"
            echo "  baseline-SOFTWARE.json, post-SOFTWARE.json (etc.)"
            echo "  *.CSV or *.csv (ProcMon export)"
            exit 0
        fi

        scripts="{{VIVI}}/scripts/analysis"

        # Filesystem diff
        if [ -f "$dir/baseline-files.txt" ] && [ -f "$dir/post-files.txt" ]; then
            echo "============================================"
            "{{PYTHON}}" "$scripts/filesystem-diff.py" "$dir/baseline-files.txt" "$dir/post-files.txt" $flags
        fi

        # Registry diffs
        for hive in SOFTWARE SYSTEM NTUSER SECURITY SAM; do
            if [ -f "$dir/baseline-${hive}.json" ] && [ -f "$dir/post-${hive}.json" ]; then
                echo ""
                echo "============================================"
                "{{PYTHON}}" "$scripts/registry-diff.py" "$dir/baseline-${hive}.json" "$dir/post-${hive}.json" $flags
            fi
        done

        # ProcMon CSV
        csv=$(find "$dir" -maxdepth 1 -iname "*.csv" 2>/dev/null | head -1)
        if [ -n "$csv" ]; then
            echo ""
            echo "============================================"
            "{{PYTHON}}" "$scripts/parse-procmon-csv.py" "$csv" $flags
        fi
        ;;

    disasm)
        # Parse: disasm <binary> <start> [extra-args]
        binary="${rest%% *}"
        rest2="${rest#* }"
        [ "$binary" = "$rest2" ] && rest2=""
        start_addr="${rest2%% *}"
        extra="${rest2#* }"
        [ "$start_addr" = "$extra" ] && extra=""

        if [ -z "$binary" ] || [ -z "$start_addr" ]; then
            echo "Usage: just sa disasm <binary|dump> <start-addr> [end-addr] [--context <annotated.c|ghidra-dir>]"
            exit 1
        fi
        {{VIVI}}/scripts/disasm-analyze.sh "$binary" "$start_addr" $extra
        ;;

    "")
        echo "Usage: just sa <subcommand> [args]"
        echo ""
        echo "Subcommands:"
        echo "  re <action> <file>    Static RE analysis (pe, crypto, unpack, yara, vt, decompile, ...)"
        echo "  analyze <dir>         Diff analysis on artifacts directory"
        echo "  disasm <binary> <addr> Disassembly with Claude"
        echo ""
        echo "Run 'just sa re help' for full list of RE actions."
        exit 1
        ;;

    *)
        echo "Unknown sa subcommand: $sa_action"
        echo "Usage: just sa re|analyze|disasm [args]"
        exit 1
        ;;
    esac


