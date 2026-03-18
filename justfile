host := if path_exists(".host") == "true" { trim(`cat .host`) } else { "tcentre1" }
HOST := if host == "tcentre2" { "tcentre2" } else { "tcentre1" }
VIVI := env_var("HOME") + "/repos/gizur-vivi"

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
    @echo "  just templates                        List base VMs with sizes"
    @echo "  just install <os> <name>              Fresh install from ISO (just install --list)"
    @echo "  just launch <base> <name>             Create sandbox (host-only, no internet)"
    @echo "  just launch <base> <name> --bridge   Create sandbox with internet access"
    @echo "  just launch <base> <name> --no-network Create sandbox without network"
    @echo "  just connect <name>                   Open VNC/virt-manager to sandbox"
    @echo "  just snapshot <name> create            Take snapshot (timestamp name)"
    @echo "  just snapshot <name> create <snap>     Take snapshot with custom name"
    @echo "  just snapshot <name> revert <snap>     Revert to snapshot"
    @echo "  just stop <name>                       Stop and remove sandbox"
    @echo "  just save <name> [template-name]       Save instance as reusable template"
    @echo "  just destroy <name>                    Stop, delete, confirm"
    @echo ""
    @echo "TARGETS"
    @echo "  setup"
    @echo "    Install local dependencies (remmina, vncviewer)."
    @echo "    Runs ansible-playbook locally with --ask-become-pass."
    @echo ""
    @echo "  templates [--delete <name>]"
    @echo "    List available base VM templates with disk sizes."
    @echo "    --delete <name>   Delete a template (asks for confirmation)"
    @echo "    Requires external disk mounted on the host."
    @echo ""
    @echo "  install <os> <name> [--bridge|--no-network]"
    @echo "    Fresh OS install from ISO. Supported OS types:"
    @echo "    Run 'just install --list' for available OS types and specs."
    @echo "    <name>      Instance name (used in connect/stop/destroy/snapshot)"
    @echo "    Default: host-only network (no internet). --bridge for internet access."
    @echo "    --no-network  Disable network completely"
    @echo "    ISOs from: /mnt/ext/Installation_files/"
    @echo ""
    @echo "  launch <base> <name> [--bridge|--no-network]"
    @echo "    Create a linked clone (VMware) or COW instance (KVM) from <base>."
    @echo "    <base>      Template name from 'just templates'"
    @echo "    <name>      Instance name (used in connect/stop/destroy/snapshot)"
    @echo "    Default: host-only network (no internet). --bridge for internet access."
    @echo "    --no-network  Disable network completely"
    @echo ""
    @echo "  connect <name>"
    @echo "    Connect to a running sandbox via VNC (VMware) or virt-manager (KVM)."
    @echo "    Auto-starts the VM if stopped."
    @echo ""
    @echo "  start <name>"
    @echo "    Start a stopped sandbox without opening a viewer."
    @echo ""
    @echo "  stop <name> [hard|soft|--keep]"
    @echo "    Stop and remove a sandbox."
    @echo "    VMware: soft (default) = graceful, hard = power off"
    @echo "    KVM:    tries telnet shutdown, then ACPI, force-kills as last resort"
    @echo "    --keep  (KVM) Keep the instance disk after stopping"
    @echo ""
    @echo "  destroy <name>"
    @echo "    Permanently delete a sandbox (asks for confirmation)."
    @echo "    Stops the VM if running, then removes all files."
    @echo ""
    @echo "  snapshot <name> create|list|revert|delete [snapshot]"
    @echo "    create [snap]   Create snapshot (default name: YYYYMMDD-HHMMSS)"
    @echo "    list            List all snapshots"
    @echo "    revert <snap>   Revert VM to a named snapshot"
    @echo "    delete <snap>   Delete a named snapshot"
    @echo ""
    @echo "  status"
    @echo "    Show running VMs, base templates with sizes, sandboxes with"
    @echo "    state/VNC port, and free disk space for each storage location."
    @echo ""
    @echo "  save <name> [template-name]"
    @echo "    Save an instance as a reusable template."
    @echo "    Stops the VM, flattens the disk (removes backing chain),"
    @echo "    and copies to the templates directory."
    @echo "    <name>            Instance to save"
    @echo "    [template-name]   Name for the template (default: same as instance)"
    @echo "    VMware: copies sandbox to /mnt/ext/vmware/<template>.vmwarevm/"
    @echo "    KVM:    converts instance disk to /mnt/vm/kvm/templates/<template>.qcow2"
    @echo ""
    @echo "  hypervisor [kvm|vmware|status]"
    @echo "    Switch between KVM and VMware on the host (mutually exclusive)."
    @echo "    status (default) shows which hypervisor is active."
    @echo ""
    @echo "  cdrom list|prepare|mount|eject [args]"
    @echo "    CD-ROM management for tool and OS ISOs."
    @echo "    list                        List available tool and OS ISOs"
    @echo "    prepare <name> <path>       Build ISO from directory, save as tool ISO"
    @echo "    mount <vm> <name>           Mount ISO on VM"
    @echo "    eject <vm>                  Eject CD-ROM"
    @echo "    Example: just cdrom prepare xptools /mnt/ext/Installation_files/xp-tools"
    @echo "    Example: just cdrom mount win10-test xptools"
    @echo ""
    @echo "  convert <base>"
    @echo "    Convert a VMware VMDK to qcow2 for use with KVM."
    @echo "    Output: /mnt/vm/kvm/templates/<template>.qcow2"
    @echo ""
    @echo "  for-pull <name> <vm-path> [local-dest]"
    @echo "    Copy a file from an instance disk to local machine."
    @echo "    Auto-mounts the instance if not already mounted."
    @echo "    <vm-path>     Absolute path inside the VM (e.g. /WINDOWS/system32/config/software)"
    @echo "    [local-dest]  Local destination (default: current directory)"
    @echo ""
    @echo "  for-inspect <name> mount|umount|ls|info [path]"
    @echo "    Mount an instance's disk read-only via qemu-nbd --snapshot."
    @echo "    Safe while VM is running (uses copy-on-write overlay)."
    @echo "    mount         Mount with qemu-nbd"
    @echo "    umount        Unmount and disconnect NBD"
    @echo "    ls [path]     List files (auto-mounts if needed)"
    @echo "    info          Show image, NBD, and mount info"
    @echo ""
    @echo "  for-registry-inspect <name> [SAM|SYSTEM|SOFTWARE|SECURITY|NTUSER|all]"
    @echo "    Parse Windows registry hives from an instance using qemu-nbd."
    @echo "    Default: all hives. Auto-mounts if needed."
    @echo ""
    @echo "  for-registry <name> import|export|edit <hive> [args]"
    @echo "    Offline registry operations (VM must be stopped). Uses reged (chntpw)."
    @echo "    import <hive> <regfile>      Import .reg file into hive"
    @echo "    export <hive> <key> [out]    Export key to .reg format"
    @echo "    edit <hive>                  Interactive editor"
    @echo "    Hives: SAM, SYSTEM, SOFTWARE, SECURITY, NTUSER, DEFAULT"
    @echo ""
    @echo "  setup [local|sysinternals|pe-sieve|python-2.7|python-3.4|defender-off|defender-status] [vm-name]"
    @echo "    Install tools. Without args: local dependencies (remmina, vncviewer)."
    @echo "    sysinternals <vm>   Install Sysinternals Suite from Alex313031/Windows-XP-Stuffz"
    @echo "    pe-sieve <vm>       Install pe-sieve + mal_unpack (IAT reconstruction, auto-unpacking)"
    @echo "    python-2.7 <vm>     Install Python 2.7.18 (last XP-compatible 2.x)"
    @echo "    python-3.4 <vm>     Install Python 3.4.4 (last XP-compatible 3.x)"
    @echo "    defender-off <vm>   Disable Defender real-time/behavior monitoring + add C:\\local,C:\\tmp exclusions"
    @echo "    defender-status <vm> Show current Defender protection status"
    @echo "    Downloads are cached in \$TOOLS_CACHE on the host."
    @echo ""
    @echo "  ip <name>"
    @echo "    Get VM IP address (virsh domifaddr + ARP fallback)."
    @echo ""
    @echo "  ssh <name> [cmd]"
    @echo "    SSH into a VM or run a command via SSH."
    @echo "    Auto-detects OS: XP (freeSSHd) gets legacy key options."
    @echo "    Example: just ssh winxp-xorist           Interactive shell"
    @echo "    Example: just ssh winxp-xorist 'dir C:\\\\'"
    @echo ""
    @echo "  scp <name> pull|push <remote-path> <local-path>"
    @echo "    SCP files to/from a VM via the host."
    @echo "    pull: copy file from VM to local machine"
    @echo "    push: copy file from local machine to VM"
    @echo "    Example: just scp winxp-xorist pull 'C:\\file.txt' ./file.txt"
    @echo "    Example: just scp winxp-xorist push ./tool.exe 'C:\\tool.exe'"
    @echo ""
    @echo "  telnet <name> <command> [timeout=30]"
    @echo "    Run a command inside a Windows VM via telnet (expect)."
    @echo "    Example: just telnet winxp-dyn 'dir C:\\\\'"
    @echo "    Example: just telnet winxp-dyn 'tasklist' 60"
    @echo ""
    @echo "  sync-clock <name>"
    @echo "    Sync VM clock to host time via telnet."
    @echo ""
    @echo "  procmon <name> start|stop|status [capture-name]"
    @echo "    Manage ProcMon on a Windows VM via PsExec."
    @echo "    start [name]   Start ProcMon (backing file: C:\\<name>.PML)"
    @echo "    stop           Stop ProcMon cleanly (/Terminate)"
    @echo "    status         Check if running + list PML files"
    @echo "    Requires Sysinternals installed: just setup sysinternals <vm>"
    @echo ""
    @echo "  memdump <vm> list|dump|run [args] [delay=8] [output] [dest]"
    @echo "    Dump process memory via ProcDump (CLI, works from telnet)."
    @echo "    list                                  List processes (non-system marked <---)"
    @echo "    dump <pid-or-name> [out]              Dump already-running process"
    @echo "    run <cmd> [delay=8] [out] [dest=.]    Launch, dump, stop VM, pull dump locally"
    @echo "    The 'run' action does the full flow: launch -> wait -> dump -> stop -> pull."
    @echo "    Delay = seconds between launch and dump (default 8, enough for UPX unpack)."
    @echo "    Example: just da-memdump winxp-dyn run 'C:\\malware\\sample.exe' 8 sample-dump ./out/"
    @echo ""
    @echo "  virdump <vm> dump|list|analyze|clean [args]"
    @echo "    Full VM RAM dump via virsh (hypervisor-side, invisible to guest)."
    @echo "    dump [local-dest]                   Dump VM RAM + pull locally"
    @echo "    dump --no-pull                      Dump but keep on host only"
    @echo "    list                                List dumps on host"
    @echo "    analyze <file> <plugin> [args]      Run Volatility 3 on dump"
    @echo "    clean                               Delete dumps from host"
    @echo "    Volatility plugins: windows.pslist, windows.malfind, windows.dumpfiles"
    @echo ""
    @echo "  re packing|crypto|unpack|strings|known-plaintext <file-or-vm>"
    @echo "    Static reverse engineering of PE executables."
    @echo "    packing          Check for UPX/packer compression, section entropy"
    @echo "    crypto           Detect known crypto algorithms (TEA, AES, Blowfish, etc.)"
    @echo "    unpack <.dmp>    Extract unpacked PE from ProcDump memory dump"
    @echo "    strings <.exe>   Show imports and categorized strings"
    @echo "    decompile <.exe> Decompile to C (r2ghidra), saves <name>-pseudocode.txt"
    @echo "    annotate <.exe>  Add function names + comments via Claude → <name>-annotated.c"
    @echo "    context <.exe>   Auto-generate context.txt from packing/crypto/strings analysis"
    @echo "    annotate-deep <.exe> [--context <file>]"
    @echo "                     Ghidra + call graph + bottom-up LLM annotation (deep analysis)"
    @echo "                     Auto-generates context.txt if --context not provided"
    @echo "    ghidra-decompile <.exe>  Ghidra headless → functions.json + callgraph.json"
    @echo "    known-plaintext  Extract encryption key (mount clean template vs infected disk)"
    @echo "                     Usage: just sa-re known-plaintext <vm-instance>"
    @echo "                            just sa-re known-plaintext 'orig.txt encrypted.txt'"
    @echo ""
    @echo "  ftp start|stop|pull <name> <vm-path> [local-dest]"
    @echo "    Manage FTP server and transfer files from VMs."
    @echo "    start                          Start FTP server on host (port 21)"
    @echo "    stop                           Stop FTP server"
    @echo "    pull <vm> <path> [dest]        Pull file from VM via FTP"
    @echo "    Example: just ftp pull winxp-dyn 'C:\\procmon.PML' ./out/"
    @echo ""
    @echo "  snapshot-state <vm> <phase> <outdir>"
    @echo "    Capture filesystem listing + registry hive dumps from a mounted VM."
    @echo "    <phase>     Label (baseline, post, etc.)"
    @echo "    <outdir>    Output directory for files.txt and registry JSON"
    @echo "    Requires VM disk mounted: just for-inspect <vm> mount"
    @echo ""
    @echo "  setup-tools <vm> [tools-source-dir]"
    @echo "    Build ISO with XP tools (Sysinternals, 7-Zip, VC++ runtimes, etc.)"
    @echo "    and install on VM. Uses TOOLS_SOURCE from config.sh by default."
    @echo ""
    @echo "  run-sample <vm> <sample> <outdir> [wait=60]"
    @echo "    Execute a malware sample with full ProcMon capture."
    @echo "    1. Start ProcMon  2. Execute malware  3. Wait  4. Stop ProcMon  5. Pull PML"
    @echo "    Samples defined in config.sh (MALWARE_CMD associative array)."
    @echo "    See malware/samples.sh.template for format."
    @echo ""
    @echo "  analyze <dir> [--json]"
    @echo "    Run filesystem diff, registry diff, and ProcMon CSV analysis"
    @echo "    on baseline/post artifacts in the given directory."
    @echo ""
    @echo "  trace <action> <vm> [args]"
    @echo "    Manage ETW (logman) traces on Windows VMs via telnet."
    @echo "    start <vm> [name] [flags]     Start ETW trace (logman)"
    @echo "    stop <vm> [name]              Stop ETW trace, convert to CSV"
    @echo "    status <vm>                   Show active ETW sessions"
    @echo "    pull <vm> [name] [dest]       Pull trace files (TFTP/FTP)"
    @echo ""
    @echo "    Logman flags: process,img,fileio,registry,thread,disk,net"
    @echo "    Default flags: process,img,fileio,registry,thread"
    @echo "    Example: just da-trace start winxp-dyn mytrace process,fileio,registry"
    @echo ""
    @echo "ARM VMs (Linux, serial console — auto-detected by template/instance)"
    @echo "  just launch debian-12-nocloud-arm64 myvm   Create ARM sandbox from template"
    @echo "  just launch debian-12-nocloud-arm64 myvm --hostonly"
    @echo "  just start myvm                            Start existing ARM instance"
    @echo "  just connect myvm                          Attach serial console (Ctrl-] to detach)"
    @echo "  just telnet myvm 'uname -a'                  Run command via serial"
    @echo "  just snapshot myvm create|list|revert|delete [snap]"
    @echo "  just stop myvm                             Graceful shutdown"
    @echo "  just destroy myvm                          Delete instance"
    @echo "  ARM VMs are standalone qemu-system-aarch64 (not libvirt)."
    @echo "  arm64 kernel runs ARM 32-bit binaries (CONFIG_COMPAT=y)."
    @echo "  Login: root (no password) via serial console."

# Switch default host: just host-set tcentre1|tcentre2
host-set target:
    #!/usr/bin/env bash
    case "{{target}}" in
        tcentre1|tcentre2)
            echo "{{target}}" > .host
            echo "Default host set to {{target}}"
            ;;
        *)
            echo "Unknown host: {{target}}"
            echo "Available: tcentre1 (home), tcentre2 (office)"
            exit 1
            ;;
    esac

# Show host resource usage (CPU, memory): just host-top
host-top:
    ssh -t {{HOST}} "TERM=xterm-256color htop"

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

# List running sandboxes/instances: just list
list:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" list

# List or delete VM templates: just templates [--delete <name>]
templates *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" templates {{args}}

# Install OS from ISO: just install --list | just install <os> <name> [--bridge|--no-network]
install +args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" install {{args}}

# Launch VM sandbox (host-only default): just launch <base> <name> [--bridge|--no-network]
launch base name *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" launch "{{base}}" "{{name}}" {{args}}

# Connect to a VM: just connect <name>
connect name:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" connect "{{name}}"

# Take screenshot of running VM: just screenshot <name> [output.png]
screenshot name output="":
    {{VIVI}}/scripts/vm.sh "{{HOST}}" screenshot "{{name}}" "{{output}}"

# Start a stopped VM: just start <name> [--bridge|--hostonly|--no-network]
start name *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" start "{{name}}" {{args}}

# Graceful shutdown (keeps instance): just shutdown <name>
shutdown name:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" shutdown "{{name}}"

# Rename a VM instance or template: just rename <old-name> <new-name>
rename old new:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" rename "{{old}}" "{{new}}"

# Destroy a VM (stop + delete): just destroy <name>
destroy name:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" destroy "{{name}}"

# Manage VM snapshots: just snapshot <name> create|list|revert|delete [snapshot]
snapshot name *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" snapshot "{{name}}" {{args}}

# Save an instance as a reusable template: just save <name> [template-name] [--force]
save name *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" save "{{name}}" {{args}}

# CD-ROM management: just cdrom list|prepare|mount|eject [args]
cdrom *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" cdrom {{args}}

# Copy files into a VM via ISO: just share <name> <file1> [file2...]
share name *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" share "{{name}}" {{args}}

# Show status of VMs and sandboxes: just status
status:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" status

# Verify host network setup (virbr0 bridge, virbr1 hostonly, DHCP, NAT): just host-check-network
host-check-network:
    #!/usr/bin/env bash
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

# Switch hypervisor: just host-hypervisor kvm|vmware|status
host-hypervisor *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" hypervisor {{args}}

# Convert VMware VMDK to qcow2: just convert <base>
convert base:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" convert "{{base}}"

# Pull file from stopped instance disk: just for-pull <name> <vm-path> [local-dest]
for-pull name vm_path *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" pull "{{name}}" "{{vm_path}}" {{args}}

# Inspect stopped instance disk (read-only via NBD): just for-inspect <name> mount|umount|ls|info [path]
for-inspect name *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect "{{name}}" {{args}}

# Parse Windows registry from stopped instance disk: just for-registry-inspect <name> [hive]
for-registry-inspect name *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect-registry "{{name}}" {{args}}

# Attach GDB server to running VM: just da-debug <name> [port=1234]
da-debug name port="1234":
    {{VIVI}}/scripts/vm.sh "{{HOST}}" debug "{{name}}" "{{port}}"

# Generate GDB script and start debug session: just da-debug-trace <name> <config.toml> [port=1234]
da-debug-trace name config port="1234":
    #!/usr/bin/env bash
    set -euo pipefail
    host_ip=$(echo "{{HOST}}" | sed 's/.*@//')
    gdb_script="/tmp/debug-{{name}}-$$.gdb"

    # Generate GDB script
    python3 "{{VIVI}}/scripts/gen-gdb-script.py" "{{config}}" "${host_ip}:{{port}}" "$gdb_script"

    # Start GDB server on the VM
    echo "Starting GDB server on {{name}}:{{port}}..."
    {{VIVI}}/scripts/vm.sh "{{HOST}}" debug "{{name}}" "{{port}}"

    echo ""
    echo "GDB script: $gdb_script"
    echo ""
    echo "=== In terminal 1: ==="
    echo "  gdb -x $gdb_script"
    echo "  (gdb) continue"
    echo ""
    echo "=== In terminal 2: ==="
    echo "  just telnet {{name}} '<malware command>'"
    echo ""
    echo "GDB will break at OEP, capture CR3, then set conditional breakpoints."

# Reset Windows user password (offline SAM edit): just reset-password <name-or-template> [username] [new-password]
reset-password name *args:
    {{VIVI}}/scripts/vm.sh "{{HOST}}" reset-password "{{name}}" {{args}}

# Offline Windows registry on stopped instance: just for-registry <name> import|export|edit <hive> [regfile|key]
for-registry name *args:
    #!/usr/bin/env bash
    args="{{args}}"
    {{VIVI}}/scripts/vm.sh "{{HOST}}" registry "{{name}}" $args

# Manage ETW/ProcMon traces: just da-trace start|stop|status|pull|procmon-start|procmon-stop|procmon-status <vm> [args]
da-trace action name *args:
    #!/usr/bin/env bash
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    {{VIVI}}/scripts/trace.sh "{{action}}" "{{name}}" {{args}}

# Get VM IP address: just ip <name>
ip name:
    @{{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "{{name}}"

# SSH into VM or run command: just ssh <name> [cmd]
ssh name *args:
    #!/usr/bin/env bash
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    args="{{args}}"
    vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "{{name}}")
    opts=$(vm_ssh_opts "{{HOST}}" "{{name}}")
    if [ -z "$args" ]; then
        echo "SSH into {{name}} at $vmip..."
        ssh -t {{HOST}} "sshpass -p '$VM_PASS' ssh $opts -o StrictHostKeyChecking=no '${VM_USER}@${vmip}'"
    else
        echo "Running on {{name}} ($vmip): $args"
        ssh {{HOST}} "sshpass -p '$VM_PASS' ssh $opts -o StrictHostKeyChecking=no '${VM_USER}@${vmip}' '$args'"
    fi

# SFTP files to/from VM: just scp <name> pull <remote> <local> | push <local> <remote>
scp name direction src dest:
    {{VIVI}}/scripts/vm-scp.sh "{{HOST}}" "{{name}}" "{{direction}}" "{{src}}" "{{dest}}"

# Run command inside VM (telnet for Windows, serial for ARM): just telnet <name> <command> [timeout]
telnet name cmd timeout="30":
    #!/usr/bin/env bash
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    if is_arm_instance "{{name}}"; then
        {{VIVI}}/scripts/vm-arm.sh exec "{{name}}" "{{cmd}}" "{{timeout}}"
    else
        vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "{{name}}")
        echo "Connecting to {{name}} at $vmip..."
        {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "{{cmd}}" "{{timeout}}"
    fi

# Sync VM clock to host time: just sync-clock <name>
sync-clock name:
    #!/usr/bin/env bash
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "{{name}}")
    host_time=$(ssh {{HOST}} "date +%H:%M:%S")
    host_date=$(ssh {{HOST}} "date +%m/%d/%Y")
    echo "Setting {{name}} clock to $host_date $host_time"
    {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "time $host_time" 10
    {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "date $host_date" 10
    echo "Done."

# Manage ProcMon on VM: just da-procmon <name> start|stop|status [capture-name]
da-procmon name *args:
    #!/usr/bin/env bash
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    args="{{args}}"
    action="${args%% *}"
    rest="${args#* }"
    [ "$action" = "$rest" ] && rest=""
    capture_name="${rest:-procmon}"

    if [ -z "$action" ]; then
        echo "Usage: just da-procmon <vm-name> start|stop|status [capture-name]"
        exit 0
    fi

    vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "{{name}}")
    {{VIVI}}/scripts/procmon-ctl.sh "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "$action" "$capture_name" "$PROCMON_EXE" "$PSEXEC_EXE"

# Dump process memory via ProcDump: just da-memdump <vm> list|dump|run <args> [delay=8] [output-name]
da-memdump name *args:
    #!/usr/bin/env bash
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    args="{{args}}"
    action="${args%% *}"
    rest="${args#* }"
    [ "$action" = "$rest" ] && rest=""

    if [ -z "$action" ]; then
        echo "Usage: just da-memdump <vm> list|dump|run [args]"
        echo ""
        echo "  list                                  List processes (non-system marked <---)"
        echo "  dump <pid-or-name> [output]           Dump already-running process"
        echo "  run <cmd> [delay=8] [output] [dest]   Launch, dump, stop, pull locally"
        echo ""
        echo "The 'run' action does the full flow: launch malware, wait <delay>s,"
        echo "dump with ProcDump, stop VM, mount disk, pull dump to <dest>."
        echo ""
        echo "Examples:"
        echo "  just da-memdump winxp-dyn list"
        echo "  just da-memdump winxp-dyn dump sample.exe sample-dump"
        echo "  just da-memdump winxp-dyn run 'C:\\malware-test\\sample.exe' 8 sample-dump ./out/"
        exit 0
    fi

    vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "{{name}}")

    case "$action" in
        list)
            {{VIVI}}/scripts/memdump.sh "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" list
            ;;
        dump)
            target="${rest%% *}"
            rest2="${rest#* }"
            [ "$target" = "$rest2" ] && rest2=""
            outname="${rest2:-memdump}"
            if [ -z "$target" ]; then
                echo "Usage: just da-memdump <vm> dump <pid-or-name> [output-name]"
                exit 1
            fi
            {{VIVI}}/scripts/memdump.sh "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" dump "$target" "$outname" "$PROCDUMP_EXE"
            ;;
        run)
            # Parse: run <cmd> [delay] [output] [local-dest]
            runcmd="${rest%% *}"
            rest2="${rest#* }"
            [ "$runcmd" = "$rest2" ] && rest2=""
            delay="${rest2%% *}"
            rest3="${rest2#* }"
            [ "$delay" = "$rest3" ] && rest3=""
            # If delay is not a number, treat it as output name
            if [ -n "$delay" ] && ! [[ "$delay" =~ ^[0-9]+$ ]]; then
                outname="$delay"
                delay="8"
                local_dest="${rest3%% *}"
            else
                delay="${delay:-8}"
                outname="${rest3%% *}"
                rest4="${rest3#* }"
                [ "$outname" = "$rest4" ] && rest4=""
                local_dest="$rest4"
            fi
            outname="${outname:-memdump}"
            local_dest="${local_dest:-.}"
            if [ -z "$runcmd" ]; then
                echo "Usage: just da-memdump <vm> run <cmd> [delay=8] [output] [local-dest]"
                echo "Example: just da-memdump winxp-dyn run 'C:\\malware\\sample.exe' 8 sample-dump ./out/"
                exit 1
            fi

            # Step 1: Launch + dump
            {{VIVI}}/scripts/memdump.sh "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" run "$runcmd" "$delay" "$outname" "$PROCDUMP_EXE"

            # Step 2: Stop VM (keep disk)
            echo ""
            echo "=== Stopping VM (keeping disk) ==="
            {{VIVI}}/scripts/vm.sh "{{HOST}}" stop "{{name}}" --keep

            # Step 3: Mount disk, find and pull dump
            echo ""
            echo "=== Pulling dump from disk ==="
            {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect "{{name}}" mount

            # Find the .dmp file on the mounted disk
            mntdir="${KVMDIR}/mnt/{{name}}-live"
            dmpfile=$(ssh "{{HOST}}" "find '$mntdir' -maxdepth 1 -name '${outname}*.dmp' -type f 2>/dev/null | head -1")
            if [ -z "$dmpfile" ]; then
                echo "ERROR: Dump file ${outname}*.dmp not found on disk"
                {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect "{{name}}" umount
                exit 1
            fi

            dmpname=$(basename "$dmpfile")
            mkdir -p "$local_dest"
            echo "Pulling $dmpname -> ${local_dest}/${dmpname}"
            scp "{{HOST}}:${dmpfile}" "${local_dest}/${dmpname}"

            # Step 4: Unmount
            {{VIVI}}/scripts/vm.sh "{{HOST}}" inspect "{{name}}" umount

            echo ""
            echo "=== Done ==="
            echo "Dump saved: ${local_dest}/${dmpname}"
            ;;
        *)
            echo "Unknown action: $action"
            echo "Usage: just da-memdump <vm> list|dump|run [args]"
            exit 1
            ;;
    esac

# Dump full VM RAM via virsh: just da-virdump <vm> dump|list|analyze|clean [args]
da-virdump name *args:
    #!/usr/bin/env bash
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    args="{{args}}"
    action="${args%% *}"
    rest="${args#* }"
    [ "$action" = "$rest" ] && rest=""

    if [ -z "$action" ]; then
        {{VIVI}}/scripts/virdump.sh "{{HOST}}" help
        exit 0
    fi

    case "$action" in
        dump)
            {{VIVI}}/scripts/virdump.sh "{{HOST}}" dump "{{name}}" $rest
            ;;
        list)
            {{VIVI}}/scripts/virdump.sh "{{HOST}}" list
            ;;
        analyze)
            {{VIVI}}/scripts/virdump.sh "{{HOST}}" analyze $rest
            ;;
        clean)
            {{VIVI}}/scripts/virdump.sh "{{HOST}}" clean
            ;;
        *)
            {{VIVI}}/scripts/virdump.sh "{{HOST}}" help
            exit 1
            ;;
    esac

# FTP server and file transfer: just ftp start|stop|pull <name> <vm-path> [local-dest]
ftp *args:
    #!/usr/bin/env bash
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    args="{{args}}"
    action="${args%% *}"
    rest="${args#* }"
    [ "$action" = "$rest" ] && rest=""

    case "$action" in
        start|stop)
            {{VIVI}}/scripts/ftp-server.sh "{{HOST}}" "$HOST_ROOT_VAL" "$FTPDIR" "$FTP_BIND" "$FTP_PYTHON" "$action"
            ;;
        pull)
            # Parse: pull <vm-name> <vm-path> [local-dest]
            vm_name="${rest%% *}"
            rest2="${rest#* }"
            [ "$vm_name" = "$rest2" ] && rest2=""
            vm_file="${rest2%% *}"
            rest3="${rest2#* }"
            [ "$vm_file" = "$rest3" ] && rest3=""
            local_dest="${rest3:-.}"

            if [ -z "$vm_name" ] || [ -z "$vm_file" ]; then
                echo "Usage: just ftp pull <vm-name> <vm-path> [local-dest]"
                echo "Example: just ftp pull winxp-dyn 'C:\\procmon.PML' ./artifacts/"
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
            echo "Usage: just ftp start|stop|pull <name> <vm-path> [local-dest]"
            echo ""
            echo "  start                              Start FTP server on host"
            echo "  stop                               Stop FTP server"
            echo "  pull <vm> <vm-path> [local-dest]   Pull file from VM via FTP"
            ;;
        *)
            echo "Unknown ftp action: $action"
            exit 1
            ;;
    esac

# Capture filesystem + registry state from stopped VM: just for-snapshot <vm> <phase> <outdir>
for-snapshot vm phase outdir:
    {{VIVI}}/scripts/snapshot-state.sh "{{HOST}}" "{{vm}}" "{{phase}}" "{{outdir}}"

# [DEPRECATED: prefer `just for-inject` + `just setup pe-sieve` for stopped VMs] Build and install tools ISO on VM: just setup-tools <vm> [tools-source-dir]
setup-tools vm *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"
    args="{{args}}"
    tools_src="${args:-$TOOLS_SOURCE}"
    iso_path="/tmp/setup-tools-$$.iso"
    vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "{{vm}}")

    echo "=== Building tools ISO ==="
    {{VIVI}}/scripts/build-tools-iso.sh "{{HOST}}" "$iso_path" "$tools_src"

    echo ""
    echo "=== Attaching ISO to {{vm}} ==="
    just cdrom mount "{{vm}}" "$iso_path"

    echo ""
    echo "(waiting 5s for CD mount...)"
    sleep 5
    {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" "D:\\setup.bat" 120

    echo ""
    echo "=== Ejecting ISO ==="
    just cdrom eject "{{vm}}"

    echo ""
    echo "=== Cleaning up ISO ==="
    ssh "{{HOST}}" "rm -f '$iso_path'" 2>/dev/null || true
    echo "Setup complete."

# Execute malware with ProcMon + optional network capture: just da-run-sample <vm> <sample> <outdir> [wait=60] [net=off|on] [file=]
da-run-sample vm sample outdir wait="60" net="off" file="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"

    # Source samples.sh from the importing justfile's directory if it exists
    if [ -f "{{justfile_directory()}}/samples.sh" ]; then
        source "{{justfile_directory()}}/samples.sh"
    fi

    # Look up malware command from config
    if [ -z "${MALWARE_CMD[{{sample}}]+x}" ]; then
        echo "Unknown sample: {{sample}}"
        echo "Define MALWARE_CMD[{{sample}}] in config.sh or samples.sh"
        echo ""
        echo "Available samples:"
        for key in "${!MALWARE_CMD[@]}"; do
            echo "  $key"
        done
        exit 1
    fi
    malware_cmd="${MALWARE_CMD[{{sample}}]}"

    # If file= is set, copy it to tcentre and share via ISO
    if [ -n "{{file}}" ]; then
        local_file="{{file}}"
        if [ ! -f "$local_file" ]; then
            echo "Error: local file not found: $local_file"
            exit 1
        fi
        # Rename to sample name so it appears as e.g. D:\unknown0.exe in the VM
        ext="${local_file##*.}"
        remote_tmp="/tmp/{{sample}}.${ext}"
        echo "=== Copying sample to $HOST ==="
        scp "$local_file" "$HOST:$remote_tmp"
        echo "=== Sharing sample to {{vm}} via ISO ==="
        just share {{vm}} "$remote_tmp"
        echo "ISO mounted — file available as D:\\{{sample}}.${ext} in VM"
        echo "Waiting 15s for Windows to detect CD..."
        sleep 15
    fi

    vmip=$({{VIVI}}/scripts/vm-ip.sh "{{HOST}}" "{{vm}}")
    pml_name="procmon-{{sample}}"
    mkdir -p "{{outdir}}"

    echo "VM IP: $vmip"

    if [ "{{net}}" = "on" ]; then
        echo "=== Step 0: Start network capture ==="
        just da-netcap start "{{outdir}}"
        just da-netcap inetsim-start "{{outdir}}"
        sleep 2
    fi

    echo "=== Step 1: Start ProcMon ==="
    just da-procmon {{vm}} start "$pml_name"

    echo "=== Step 2: Execute malware ({{sample}}) ==="
    {{VIVI}}/scripts/vm-exec.exp "{{HOST}}" "$vmip" "$VM_USER" "$VM_PASS" \
        "$malware_cmd" 15 || true
    echo "Malware executed"

    echo "=== Step 3: Waiting {{wait}}s for malware activity ==="
    sleep "{{wait}}"

    echo "=== Step 4: Stop ProcMon ==="
    just da-procmon {{vm}} stop

    echo "=== Step 5: Pull PML from disk ==="
    echo "Stopping VM to extract PML..."
    just stop {{vm}}
    sleep 2
    just for-pull {{vm}} "C:/${pml_name}.PML" "{{outdir}}/" || echo "WARNING: PML extraction failed (ProcMon may not have saved)"

    if [ "{{net}}" = "on" ]; then
        echo "=== Step 6: Stop network capture ==="
        just da-netcap stop "{{outdir}}"
        just da-netcap inetsim-stop "{{outdir}}"
    fi

    echo ""
    echo "============================================"
    echo "Done! PML saved to {{outdir}}/"
    if [ "{{net}}" = "on" ]; then
        echo "Network capture saved to {{outdir}}/"
    fi
    echo ""
    echo "Next steps:"
    echo "  just for-inspect {{vm}} mount"
    echo "  just snapshot-state {{vm}} post {{outdir}}"
    echo "  just for-inspect {{vm}} umount"
    echo "  just sa-analyze {{outdir}}"

# Network capture: just da-netcap start|stop|inetsim-start|inetsim-stop <outdir> [iface=virbr1]
da-netcap action outdir="." iface="virbr1":
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{VIVI}}/scripts/lib.sh"
    setup_host "{{HOST}}"

    action="{{action}}"
    outdir="{{outdir}}"
    iface="{{iface}}"
    pidfile="/tmp/netcap-tcpdump.pid"
    inetsim_pid="/tmp/netcap-inetsim.pid"

    case "$action" in
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
            # Stop dnsmasq to free port 53, create custom config binding to virbr1 IP
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
            echo "Usage: just da-netcap start|stop|inetsim-start|inetsim-stop <outdir> [iface]"
            exit 1
            ;;
    esac

# Static RE: just sa-re packing|crypto|unpack|strings|decompile|annotate|known-plaintext <file-or-vm>
sa-re action file *args:
    #!/usr/bin/env bash
    set -euo pipefail
    f="{{file}}"
    args="{{args}}"
    # known-plaintext accepts VM names, not just files
    if [ "{{action}}" != "known-plaintext" ] && [ ! -f "$f" ]; then
        echo "File not found: $f"
        exit 1
    fi

    case "{{action}}" in
    packing)
        echo "=== File Info ==="
        file "$f"
        echo ""
        echo "Size: $(stat -c%s "$f") bytes"
        sha256sum "$f"
        echo ""

        echo "=== Packer Detection ==="
        # file(1) detects UPX, ASPack, PECompact, etc.
        packer=$(file "$f" | grep -oiE '\bUPX\b|\bASPack\b|\bPECompact\b|\bThemida\b|\bVMProtect\b|\bArmadillo\b|\bMPRESS\b|\bMEW\b|\bFSG\b|\bPetite\b|\bNsPack\b|\btElock\b' || true)
        if [ -n "$packer" ]; then
            echo "Detected by file(1): $packer"
        else
            echo "file(1): No known packer detected"
        fi
        echo ""

        # UPX unpack test
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

        # PE section entropy (high entropy = packed/encrypted)
        echo "=== Section Entropy (r2) ==="
        r2 -q -e bin.cache=true -c 'iS entropy' "$f" 2>/dev/null
        echo ""
        echo "Entropy guide: >7.0 = likely packed/encrypted, 5-7 = normal code, <5 = data/resources"
        echo ""

        # PE header info
        echo "=== PE Metadata ==="
        r2 -q -e bin.cache=true -c 'iI' "$f" 2>/dev/null
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

        PYTHON="${PYTHON_ENV:-$HOME/micromamba-base/bin}/python3"
        if ! "$PYTHON" -c "import minidump" 2>/dev/null; then
            echo "ERROR: minidump package not found."
            echo "Install: ${PYTHON_ENV:-$HOME/micromamba-base/bin}/pip install minidump"
            exit 1
        fi

        # Derive output name: foo.dmp -> foo-unpacked.exe
        outdir=$(dirname "$f")
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
        echo "Total strings: $total_strings (use 'just sa-re strings $outfile' for full list)"
        ;;

    strings)
        echo "=== Strings in $f ==="
        echo ""

        echo "--- Imports (r2) ---"
        imports=$(r2 -q -e bin.cache=true -c 'ii' "$f" 2>/dev/null | grep 'FUNC' || true)
        if [ -n "$imports" ]; then
            echo "$imports"
        else
            echo "  (no import table — packed or memory-dumped PE)"
        fi
        echo ""

        echo "--- Interesting strings ---"
        allstrings=$(strings "$f")
        echo ""
        echo "[File paths / extensions]"
        echo "$allstrings" | grep -iE '\.(exe|dll|bat|txt|bmp|jpg|pml|etl|enc|dmp)' | grep -iE '\\|/' | sort -u | head -20
        echo ""
        echo "[Registry keys]"
        echo "$allstrings" | grep -iE 'HKLM|HKCU|CurrentVersion|RegCreate|RegSet|RegDelete' | sort -u | head -20
        echo ""
        echo "[Crypto / passwords / ransom]"
        echo "$allstrings" | grep -iE 'password|decrypt|encrypt|cipher|ransom|key|hash|crypt|seed|attempt' | sort -u | head -20
        echo ""
        echo "[URLs / IPs / domains]"
        echo "$allstrings" | grep -oiE 'https?://[^ "]+|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | head -20 || true
        echo ""

        total=$(echo "$allstrings" | wc -l)
        echo "Total: $total strings (use 'strings $f' for full output)"
        ;;

    decompile)
        # Auto-save path: <basename>-pseudocode.txt next to input file
        outdir=$(dirname "$f")
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
            # Auto-decompile first
            outdir=$(dirname "$f")
            basename_no_ext=$(basename "$f" | sed 's/\.[^.]*$//')
            pseudocode="${outdir}/${basename_no_ext}-pseudocode.txt"
            if [ ! -f "$pseudocode" ]; then
                echo "Decompiling first..."
                just sa-re decompile "$f"
            fi
            f="$pseudocode"
        fi

        if [ ! -f "$f" ]; then
            echo "File not found: $f"
            echo "Usage: just sa-re annotate <pseudocode.txt or binary.exe>"
            exit 1
        fi

        outdir=$(dirname "$f")
        basename_no_ext=$(basename "$f" | sed 's/-pseudocode\.txt$//' | sed 's/\.[^.]*$//')
        annotated="${outdir}/${basename_no_ext}-annotated.c"

        "{{VIVI}}/scripts/annotate.sh" "$f" "$annotated"
        ;;

    context)
        # Auto-generate context file for annotate-deep from packing/crypto/strings analysis
        if [ ! -f "$f" ]; then
            echo "File not found: $f"
            echo "Usage: just sa-re context <binary.exe>"
            exit 1
        fi
        outdir=$(dirname "$f")
        basename_no_ext=$(basename "$f" | sed 's/\.[^.]*$//')
        context_file="${outdir}/context.txt"

        echo "=== Generating context from static analysis ==="
        echo "Collecting packing, crypto, and strings data..."

        # Run all three analyses and capture output
        analysis=$(
            echo "=== PACKING ANALYSIS ==="
            just sa-re packing "$f" 2>/dev/null
            echo ""
            echo "=== CRYPTO ANALYSIS ==="
            just sa-re crypto "$f" 2>/dev/null
            echo ""
            echo "=== STRINGS ANALYSIS ==="
            just sa-re strings "$f" 2>/dev/null
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
            echo "Usage: just sa-re annotate-deep <binary.exe> [--context <notes.txt>]"
            exit 1
        fi
        ctx_args=""
        if echo "$args" | grep -q -- '--context'; then
            ctx_file=$(echo "$args" | sed 's/.*--context //' | awk '{print $1}')
            ctx_args="--context $ctx_file"
        else
            # Auto-generate context if not provided
            auto_ctx="$(dirname "$f")/context.txt"
            if [ ! -f "$auto_ctx" ]; then
                echo "No --context provided, auto-generating..."
                just sa-re context "$f"
            fi
            if [ -f "$auto_ctx" ]; then
                ctx_args="--context $auto_ctx"
            fi
        fi
        "{{VIVI}}/scripts/annotate-deep.sh" "$f" "" $ctx_args
        ;;

    ghidra-decompile)
        # Ghidra headless decompile only (produces functions.json + callgraph.json)
        if [ ! -f "$f" ]; then
            echo "File not found: $f"
            echo "Usage: just sa-re ghidra-decompile <binary.exe>"
            exit 1
        fi
        basename_no_ext=$(basename "$f" | sed 's/\.[^.]*$//')
        workdir="$(dirname "$f")/${basename_no_ext}-ghidra"
        mkdir -p "$workdir"

        echo "=== Ghidra headless decompilation ==="
        echo "Output: $workdir/"
        eval "$(micromamba shell hook -s bash)"
        micromamba activate ~/micromamba-base
        python3 "{{VIVI}}/scripts/ghidra/export.py" "$f" "$workdir"

        echo ""
        echo "Functions: $(python3 -c "import json; print(len(json.load(open('$workdir/functions.json'))))")"
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
        # For file-pair mode, use: just sa-re known-plaintext "orig encrypted"
        # For VM mode, use: just sa-re known-plaintext <vm-instance>

        if [ -f "$f" ]; then
            # Single file — error, need two files or a VM name
            echo "For file pair mode, provide two paths:"
            echo "  just sa-re known-plaintext 'original.txt encrypted.txt.EnCiPhErEd'"
            echo ""
            echo "For VM disk mode, provide the instance name:"
            echo "  just sa-re known-plaintext <vm-instance>"
            exit 1
        fi

        # Check if two files were provided (space-separated in quotes)
        if echo "$f" | grep -q ' '; then
            orig_file="${f%% *}"
            enc_file="${f#* }"
            if [ -f "$orig_file" ] && [ -f "$enc_file" ]; then
                PYTHON="${PYTHON_ENV:-$HOME/micromamba-base/bin}/python3"
                "$PYTHON" "{{VIVI}}/scripts/known-plaintext.py" "$orig_file" "$enc_file"
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
            echo "Is the VM stopped with --keep? (just stop <vm> --keep)"
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

    *)
        echo "Usage: just sa-re packing|crypto|unpack|strings|decompile|annotate|known-plaintext <file-or-vm>"
        echo ""
        echo "  packing          Check for UPX/packer compression, section entropy"
        echo "  crypto           Detect known encryption algorithms (TEA, AES, Blowfish, etc.)"
        echo "  unpack           Extract unpacked PE from ProcDump .dmp file"
        echo "  strings          Show imports and categorized strings from a PE"
        echo "  decompile        Generate pseudo-code for all functions (r2ghidra C or r2 pdc)"
        echo "  annotate         Add function names + comments via Claude (from .exe or pseudocode.txt)"
        echo "  known-plaintext  Extract encryption key by comparing clean vs encrypted files"
        echo ""
        echo "Typical workflow:"
        echo "  just sa-re packing sample.exe              # Is it packed?"
        echo "  just da-memdump <vm> run <cmd> 8 dump ./   # Dump unpacked from memory"
        echo "  just sa-re unpack dump.dmp                 # Extract PE -> dump-unpacked.exe"
        echo "  just sa-re crypto dump-unpacked.exe        # What crypto does it use?"
        echo "  just sa-re strings dump-unpacked.exe       # What strings are visible?"
        echo ""
        echo "Known-plaintext attack (extract encryption key):"
        echo "  just sa-re known-plaintext <vm-instance>                # Mount template + instance"
        echo "  just sa-re known-plaintext 'original.txt encrypted.txt' # Compare two local files"
        exit 1
        ;;
    esac

# Run analysis diffs on artifacts directory: just sa-analyze <dir> [--json]
sa-analyze *args:
    #!/usr/bin/env bash
    args="{{args}}"
    dir="${args%% *}"
    rest="${args#* }"
    [ "$dir" = "$rest" ] && rest=""
    flags="$rest"

    if [ -z "$dir" ]; then
        echo "Usage: just sa-analyze <artifacts-dir> [--json]"
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
        python3 "$scripts/filesystem-diff.py" "$dir/baseline-files.txt" "$dir/post-files.txt" $flags
    fi

    # Registry diffs
    for hive in SOFTWARE SYSTEM NTUSER SECURITY SAM; do
        if [ -f "$dir/baseline-${hive}.json" ] && [ -f "$dir/post-${hive}.json" ]; then
            echo ""
            echo "============================================"
            python3 "$scripts/registry-diff.py" "$dir/baseline-${hive}.json" "$dir/post-${hive}.json" $flags
        fi
    done

    # ProcMon CSV
    csv=$(find "$dir" -maxdepth 1 -iname "*.csv" 2>/dev/null | head -1)
    if [ -n "$csv" ]; then
        echo ""
        echo "============================================"
        python3 "$scripts/parse-procmon-csv.py" "$csv" $flags
    fi

# Analyze binary disassembly with Claude: just sa-disasm <binary|dump> <start-addr> [end-addr] [--context <annotated.c|ghidra-dir>]
sa-disasm binary start *args:
    {{VIVI}}/scripts/disasm-analyze.sh "{{binary}}" "{{start}}" {{args}}

# Copy local files into a stopped VM's C:\ drive: just for-inject <name> <file1> [file2...]
for-inject name *files:
    #!/usr/bin/env bash
    set -euo pipefail
    files="{{files}}"
    if [ -z "$files" ]; then
        echo "Usage: just for-inject <vm-name> <file1> [file2...]" >&2
        exit 1
    fi
    # Wait for VM to be stopped (up to 30s)
    for i in $(seq 1 30); do
        state=$(ssh {{HOST}} "virsh domstate {{name}}" 2>/dev/null)
        [ "$state" = "shut off" ] && break
        [ "$i" = "1" ] && echo "Waiting for {{name}} to stop..."
        sleep 1
    done
    if [ "$state" != "shut off" ]; then
        echo "Error: {{name}} must be stopped (current state: $state)" >&2
        echo "  just stop {{name}} --keep" >&2
        exit 1
    fi
    # Get disk path from virsh
    disk=$(ssh {{HOST}} "virsh domblklist {{name}} --details | awk '/disk/{print \$4}'")
    if [ -z "$disk" ]; then
        echo "Error: Could not find disk for {{name}}" >&2
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
    echo "Done. Start VM with: just start {{name}}"

# Run GDB Python script on VM: just da-gdb-run <name> <script.py> <sample-path> <output-log> [port=1234]
da-gdb-run name script sample output port="1234":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{script}}" ]; then
        echo "Error: Script not found: {{script}}" >&2
        exit 1
    fi
    if [ ! -f "{{sample}}" ]; then
        echo "Error: Sample not found: {{sample}}" >&2
        exit 1
    fi
    sample_name="$(basename "{{sample}}")"
    # Revert to clean state and stop VM
    echo "Reverting {{name}} to clean snapshot..."
    just snapshot {{name}} revert clean
    echo "Stopping {{name}} for disk injection..."
    ssh {{HOST}} "virsh shutdown {{name}}" 2>/dev/null || true
    for i in $(seq 1 30); do
        state=$(ssh {{HOST}} "virsh domstate {{name}}" 2>/dev/null)
        [ "$state" = "shut off" ] && break
        sleep 1
    done
    if [ "$state" != "shut off" ]; then
        echo "Force stopping..."
        ssh {{HOST}} "virsh destroy {{name}}" 2>/dev/null || true
        sleep 2
    fi
    # Inject sample into VM disk
    just for-inject {{name}} "{{sample}}"
    # Start VM and wait for boot
    echo "Starting {{name}}..."
    ssh {{HOST}} "virsh start {{name}}"
    echo "Waiting for VM to boot..."
    sleep 15
    # Start GDB server
    echo "Starting GDB server on {{name}}:{{port}}..."
    ssh {{HOST}} "virsh qemu-monitor-command {{name}} --hmp 'gdbserver tcp::{{port}}'" 2>/dev/null || true
    # Copy GDB script to host and start in background
    scp -q "{{script}}" {{HOST}}:/tmp/gdb-run-script.py
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
        just telnet {{name}} "copy C:\\$sample_name C:\\$exe_name" || true
    fi
    just telnet {{name}} "start C:\\$exe_name" || true
    # Wait for GDB to finish and collect output
    echo "Waiting for GDB to complete..."
    ssh {{HOST}} "while pgrep -f 'gdb.*gdb-run-script' >/dev/null; do sleep 2; done"
    ssh {{HOST}} "cat /tmp/gdb-run.log" | tee "{{output}}"
    echo ""
    echo "Output saved to: {{output}}"
