#!/usr/bin/env bash
# vm-scp.sh — SFTP files to/from VMs via the host
# Usage: vm-scp.sh <host> <vm-name> pull|push <remote-path> <local-path>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

host="${1:?usage: vm-scp.sh <host> <vm-name> pull|push <src> <dest>}"
name="${2:?}"
direction="${3:?}"
src="${4:?}"
dest="${5:?}"

# Validate remote path for Windows VMs using SFTP
# SFTP root = C:\, so paths must be Unix-style:
#   /tmp/foo.txt      = C:\tmp\foo.txt
#   /local/foo.txt    = C:\local\foo.txt
# Common mistakes:
#   c:\local\foo.txt  -> becomes /c:\local\foo.txt (WRONG)
#   C:\tmp\foo.txt    -> becomes /C:\tmp\foo.txt   (WRONG)
remote_path=""
case "$direction" in
    push) remote_path="$dest" ;;
    pull) remote_path="$src" ;;
esac
if [[ -n "$remote_path" && "$remote_path" =~ ^[a-zA-Z]:\\ ]]; then
    echo "ERROR: Remote path looks like a Windows path: $remote_path" >&2
    echo "" >&2
    echo "SFTP maps '/' to 'C:\\', so use Unix-style paths:" >&2
    echo "  /tmp/foo.txt      = C:\\tmp\\foo.txt" >&2
    echo "  /local/foo.txt    = C:\\local\\foo.txt" >&2
    echo "" >&2
    # Auto-convert: c:\local\foo.txt -> /local/foo.txt
    converted=$(echo "$remote_path" | sed 's|^[a-zA-Z]:\\|/|; s|\\|/|g')
    echo "Hint: try: $converted" >&2
    exit 1
fi

setup_host "$host"
vmip=$("$SCRIPT_DIR/vm-ip.sh" "$host" "$name")
opts=$(vm_ssh_opts "$host" "$name")
tmpid=$$

case "$direction" in
    pull)
        # pull <remote-path> <local-path>
        echo "Pull ${name}:${src} -> ${dest}"
        ssh "$host" "sshpass -p '${VM_PASS}' sftp ${opts} -o StrictHostKeyChecking=no '${VM_USER}@${vmip}' <<SFTP
get \"${src}\" /tmp/scp-pull-${tmpid}
SFTP"
        scp "${host}:/tmp/scp-pull-${tmpid}" "${dest}"
        ssh "$host" "rm -f /tmp/scp-pull-${tmpid}"
        ;;
    push)
        # push <local-path> <remote-path>
        # If dest ends with / or has no file extension, treat as directory
        # and append the source filename
        basename_src=$(basename "$src")
        if [[ "$dest" == */ ]] || [[ "$(basename "$dest")" != *.* ]]; then
            dest="${dest%/}/${basename_src}"
        fi
        echo "Push ${src} -> ${name}:${dest}"
        scp "${src}" "${host}:/tmp/scp-push-${tmpid}"
        ssh "$host" "sshpass -p '${VM_PASS}' sftp ${opts} -o StrictHostKeyChecking=no '${VM_USER}@${vmip}' <<SFTP
put /tmp/scp-push-${tmpid} \"${dest}\"
SFTP"
        ssh "$host" "rm -f /tmp/scp-push-${tmpid}"
        ;;
    *)
        echo "Usage: vm-scp.sh <host> <vm-name> pull|push <src> <dest>"
        exit 1
        ;;
esac
