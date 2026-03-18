#!/usr/bin/env bash
# vm-ip.sh — Get VM IP address with multiple fallbacks
# Usage: vm-ip.sh <host> <vm_name>
# Tries: virsh domifaddr, dnsmasq leases, ip neigh (ARP)
# Prints IP address or exits 1
set -euo pipefail

HOST="${1:?usage: vm-ip.sh <host> <vm_name>}"
VM="${2:?}"

# Try virsh domifaddr first (works with qemu guest agent)
vmip=$(ssh "$HOST" "virsh domifaddr '$VM' 2>/dev/null | grep -oP '([0-9]+\.){3}[0-9]+' | head -1" 2>/dev/null || true)

# Fall back to ARP/neighbor via MAC address, filtered to the VM's bridge
if [ -z "$vmip" ]; then
    mac=$(ssh "$HOST" "virsh domiflist '$VM' 2>/dev/null | grep -oP '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1" 2>/dev/null || true)
    bridge=$(ssh "$HOST" "virsh domiflist '$VM' 2>/dev/null | awk 'NR>2 && \$3 {print \$3; exit}'" 2>/dev/null || true)
    if [ -n "$mac" ]; then
        if [ -n "$bridge" ]; then
            vmip=$(ssh "$HOST" "ip neigh show dev '$bridge' | grep -i '$mac' | awk '{print \$1}' | head -1" 2>/dev/null || true)
        fi
        # Fallback: any interface (but take first match only)
        if [ -z "$vmip" ]; then
            vmip=$(ssh "$HOST" "ip neigh | grep -i '$mac' | awk '{print \$1}' | head -1" 2>/dev/null || true)
        fi
    fi
fi

if [ -z "$vmip" ]; then
    echo "ERROR: Cannot determine IP for VM '$VM' on $HOST" >&2
    exit 1
fi

echo "$vmip"
