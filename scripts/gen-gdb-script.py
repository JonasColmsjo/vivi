#!/usr/bin/env python3
"""Generate a GDB script for debugging malware in a QEMU/KVM VM via GDB stub.

Reads a TOML-like config file with function addresses, data addresses, and
UPX delta, then produces a .gdb script that:
  1. Connects to the QEMU GDB stub
  2. Sets an initial breakpoint at the OEP (or first function)
  3. On first hit: captures CR3, sets CR3-conditional breakpoints
  4. Auto-dumps key memory regions at each breakpoint

Usage: gen-gdb-script.py <config.toml> <host:port> [output.gdb]

Config format (TOML):

    [sample]
    name = "my-sample"
    delta = -0xC00           # runtime offset: runtime_addr = ghidra_addr + delta
    arch = "x64"             # optional: x86 (default) or x64 — controls $eip/$rip

    [breakpoints]
    # name = ghidra_address  (delta applied automatically)
    oep = 0x004021d1
    func_of_interest = 0x004023b4

    [watchpoints]
    # name = address         (data section — no delta)
    tea_key_write = 0x00406585

    [dumps]
    # name = "address size"  (dumped when ANY breakpoint hits)
    tea_key_le = "0x00406585 16"
    tea_key_be = "0x00406595 16"
    md5_hash = "0x00406dc9 16"
    encryption_mode = "0x0040752c 1"
"""

import sys
import re


def parse_config(path):
    """Parse simple TOML-like config."""
    config = {}
    section = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            m = re.match(r'^\[(\w+)\]$', line)
            if m:
                section = m.group(1)
                config[section] = {}
                continue
            m = re.match(r'^(\w+)\s*=\s*(.+)$', line)
            if m and section:
                key = m.group(1)
                val = m.group(2).strip().strip('"').strip("'")
                config[section][key] = val
    return config


def parse_int(s):
    """Parse int from hex or decimal string."""
    s = s.strip()
    if s.startswith('-'):
        return -parse_int(s[1:])
    if s.startswith('0x') or s.startswith('0X'):
        return int(s, 16)
    return int(s)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <config.toml> <host:port> [output.gdb]", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    target = sys.argv[2]
    output = sys.argv[3] if len(sys.argv) > 3 else None

    cfg = parse_config(config_path)

    sample_name = cfg.get('sample', {}).get('name', 'unknown')
    delta = parse_int(cfg.get('sample', {}).get('delta', '0'))
    arch = cfg.get('sample', {}).get('arch', 'x86')
    ip_reg = '$rip' if arch == 'x64' else '$eip'

    breakpoints = cfg.get('breakpoints', {})
    watchpoints = cfg.get('watchpoints', {})
    dumps = cfg.get('dumps', {})

    # Separate OEP from other breakpoints
    oep_addr = None
    other_bps = {}
    for name, addr_str in breakpoints.items():
        addr = parse_int(addr_str) + delta
        if name == 'oep':
            oep_addr = addr
        else:
            other_bps[name] = addr

    if oep_addr is None and other_bps:
        # Use first breakpoint as OEP
        first_name = next(iter(other_bps))
        oep_addr = other_bps.pop(first_name)

    lines = []
    lines.append(f'# Auto-generated GDB script for {sample_name}')
    lines.append(f'# Delta: {delta:#x} ({delta})')
    lines.append(f'# Target: {target}')
    lines.append('')
    lines.append('set pagination off')
    lines.append('set confirm off')
    lines.append('')
    lines.append(f'target remote {target}')
    lines.append('')

    # Define convenience function to dump all regions
    lines.append('# --- Dump helper ---')
    lines.append('define dump_state')
    for name, spec in dumps.items():
        parts = spec.split()
        addr = parts[0]
        size = int(parts[1])
        if size <= 4:
            lines.append(f'  printf "{name}: "')
            lines.append(f'  x/1wx {addr}')
        elif size == 16:
            lines.append(f'  printf "{name}: "')
            lines.append(f'  x/4wx {addr}')
        else:
            lines.append(f'  printf "{name}: "')
            lines.append(f'  x/{size}bx {addr}')
    lines.append('  printf "CR3: 0x%08x\\n", $cr3')
    lines.append('end')
    lines.append('')

    # Step 1: OEP breakpoint
    if oep_addr:
        lines.append(f'# --- Step 1: Break at OEP ({oep_addr:#010x}) ---')
        lines.append(f'break *{oep_addr:#010x}')
        lines.append('commands')
        lines.append('  silent')
        lines.append(f'  printf "\\n=== HIT OEP at {oep_addr:#010x} ===\\n"')
        lines.append('  printf "CR3 = 0x%08x — this is our process\\n", $cr3')
        lines.append(f'  printf "Disassembly at {ip_reg}:\\n"')
        lines.append(f'  x/5i {ip_reg}')
        lines.append('  printf "\\nDumping initial state:\\n"')
        lines.append('  dump_state')
        lines.append('')
        lines.append('  # Set CR3-conditional breakpoints')
        lines.append('  set $target_cr3 = $cr3')
        lines.append('')

        for name, addr in other_bps.items():
            lines.append(f'  # {name}')
            lines.append(f'  break *{addr:#010x} if $cr3 == $target_cr3')

        for name, addr_str in watchpoints.items():
            addr = parse_int(addr_str)
            lines.append(f'  # watchpoint: {name}')
            lines.append(f'  watch *{addr:#010x}')

        lines.append('')
        lines.append('  printf "\\nBreakpoints set with CR3 filter. Continuing...\\n\\n"')
        lines.append('  continue')
        lines.append('end')
        lines.append('')

    # Step 2: Auto-actions for each subsequent breakpoint
    # These are set dynamically (by the OEP commands block), so we use
    # a catch-all approach via GDB's "hook-stop"
    lines.append('# --- Step 2: On every stop, dump state ---')
    lines.append('define hook-stop')
    lines.append('  dump_state')
    lines.append(f'  x/5i {ip_reg}')
    lines.append('end')
    lines.append('')

    lines.append(f'# --- Ready. Run malware in another terminal, then: ---')
    lines.append(f'# continue')
    lines.append('')

    script = '\n'.join(lines)

    if output:
        with open(output, 'w') as f:
            f.write(script)
        print(f"Generated: {output}", file=sys.stderr)
    else:
        print(script)


if __name__ == '__main__':
    main()
