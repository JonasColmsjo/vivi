#!/usr/bin/env python3
"""Scan a PE binary for global variable references (DAT_ addresses in Ghidra).

Finds all absolute memory references in code sections that point into data
sections. These are the addresses Ghidra shows as DAT_XXXXXXXX.

Usage: find-globals.py <exe-or-dump>
"""

import struct
import sys
import os
from collections import defaultdict


def parse_pe(data):
    """Parse PE headers, return (image_base, sections)."""
    image_base = 0x400000
    sections = []
    try:
        pe_off = struct.unpack("<I", data[0x3C:0x40])[0]
        if data[pe_off:pe_off + 4] != b"PE\x00\x00":
            return image_base, sections
        num_sec = struct.unpack("<H", data[pe_off + 6:pe_off + 8])[0]
        opt_off = pe_off + 4 + 20
        opt_magic = struct.unpack("<H", data[opt_off:opt_off + 2])[0]
        if opt_magic == 0x10B:
            image_base = struct.unpack("<I", data[opt_off + 28:opt_off + 32])[0]
        elif opt_magic == 0x20B:
            image_base = struct.unpack("<Q", data[opt_off + 24:opt_off + 32])[0]
        opt_size = struct.unpack("<H", data[pe_off + 4 + 16:pe_off + 4 + 18])[0]
        sec_start = opt_off + opt_size
        # Read section characteristics for code/data classification
        for i in range(min(num_sec, 20)):
            off = sec_start + i * 40
            if off + 40 > len(data):
                break
            name = data[off:off + 8].rstrip(b"\x00").decode("ascii", errors="replace")
            vsize, rva, rawsize, rawoff = struct.unpack("<IIII", data[off + 8:off + 24])
            chars = struct.unpack("<I", data[off + 36:off + 40])[0]
            if rawsize > 0 and rva > 0:
                sections.append({
                    "name": name,
                    "rva": rva,
                    "vsize": vsize,
                    "rawoff": rawoff,
                    "rawsize": rawsize,
                    "chars": chars,
                    "va_start": image_base + rva,
                    "va_end": image_base + rva + vsize,
                })
    except Exception:
        pass
    return image_base, sections


def is_code_section(sec):
    """Check if section contains executable code."""
    IMAGE_SCN_CNT_CODE = 0x00000020
    IMAGE_SCN_MEM_EXECUTE = 0x20000000
    return bool(sec["chars"] & (IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE))


def is_data_section(sec):
    """Check if section contains data (initialized or uninitialized)."""
    IMAGE_SCN_CNT_INITIALIZED_DATA = 0x00000040
    IMAGE_SCN_CNT_UNINITIALIZED_DATA = 0x00000080
    return bool(sec["chars"] & (IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_CNT_UNINITIALIZED_DATA))


def main():
    if len(sys.argv) < 2:
        print("Usage: find-globals.py <exe-or-dump>")
        sys.exit(1)

    path = sys.argv[1]
    if not os.path.isfile(path):
        print(f"File not found: {path}")
        sys.exit(1)

    with open(path, "rb") as fh:
        data = fh.read()

    image_base, sections = parse_pe(data)

    if not sections:
        print("Could not parse PE sections.")
        sys.exit(1)

    # Classify sections
    code_secs = [s for s in sections if is_code_section(s)]
    data_secs = [s for s in sections if is_data_section(s)]

    # For packed binaries (UPX etc.), sections may have both code+data flags
    # or unusual flags. Fall back: treat first section as code, rest as data.
    if not code_secs:
        code_secs = sections[:1]
    if not data_secs:
        # In packed PEs, data lives in the same section or later sections.
        # Use: anything NOT the primary code section, plus the code section
        # itself (globals may be in the code section for packed PEs).
        data_secs = sections

    # Build set of all data VAs for quick lookup
    def in_data_range(addr):
        for s in sections:  # check ALL sections — packed PEs mix code+data
            if s["va_start"] <= addr < s["va_end"]:
                return True
        return False

    # Build set of code ranges to exclude (function addresses, thunk stubs)
    code_ranges = set()
    for s in code_secs:
        for a in range(s["va_start"], s["va_end"]):
            code_ranges.add(a)

    print(f"File: {os.path.basename(path)}")
    print(f"Image base: 0x{image_base:08X}")
    for s in sections:
        kind = []
        if is_code_section(s):
            kind.append("CODE")
        if is_data_section(s):
            kind.append("DATA")
        if not kind:
            kind.append(f"0x{s['chars']:08X}")
        print(f"  {s['name']:8s}  VA 0x{s['va_start']:08X}-0x{s['va_end']:08X}  [{', '.join(kind)}]")
    print()

    # Scan code sections for 4-byte absolute address references into data
    # Look for common x86 addressing patterns:
    #   ModR/M with mod=00, r/m=101 -> [disp32]
    #   Also: A1/A3 (MOV EAX, [addr] / MOV [addr], EAX)
    refs = defaultdict(int)  # addr -> count
    ref_sources = defaultdict(list)  # addr -> [source_va, ...]

    for sec in code_secs:
        sec_data = data[sec["rawoff"]:sec["rawoff"] + sec["rawsize"]]
        sec_base = sec["va_start"]

        for i in range(len(sec_data) - 3):
            # Extract potential 4-byte address at this position
            addr = struct.unpack("<I", sec_data[i:i + 4])[0]

            # Must point into the PE image
            if not in_data_range(addr):
                continue

            # Skip if it points into code thunk range (0x4030xx-0x4032xx)
            # These are pointer table entries, not data globals
            if 0x403000 <= addr <= 0x403300:
                continue

            # Heuristic: check if the byte before looks like a valid
            # instruction prefix for an absolute address reference
            if i == 0:
                continue

            valid = False
            prev1 = sec_data[i - 1] if i >= 1 else 0
            prev2 = sec_data[i - 2] if i >= 2 else 0

            # A1 [addr] = MOV EAX, [addr]
            # A3 [addr] = MOV [addr], EAX
            if prev1 in (0xA1, 0xA3):
                valid = True

            # Two-byte opcodes with ModR/M = 05/0D/15/1D/25/2D/35/3D
            # (mod=00, r/m=101 = disp32 addressing)
            # e.g. 8B 05 = MOV EAX,[addr], 89 05 = MOV [addr],EAX
            #      C7 05 = MOV [addr],imm32, C6 05 = MOV [addr],imm8
            #      80 3D = CMP byte [addr],imm8, 83 3D = CMP dword [addr],imm8
            #      FF 25 = JMP [addr], FF 15 = CALL [addr] (skip these - trampolines)
            if i >= 2 and (prev1 & 0xC7) == 0x05:  # mod=00, r/m=101
                if prev2 not in (0xFF,):  # exclude FF 25/FF 15 (trampolines)
                    valid = True

            # 3-byte opcode: 0F xx ModR/M (SSE, conditional moves, etc.)
            if i >= 3:
                prev3 = sec_data[i - 3]
                if prev3 == 0x0F and (prev1 & 0xC7) == 0x05:
                    valid = True

            if valid:
                source_va = sec_base + i - 1  # approximate instruction VA
                refs[addr] += 1
                if len(ref_sources[addr]) < 3:
                    ref_sources[addr].append(source_va)

    if not refs:
        print("No global variable references found.")
        sys.exit(0)

    # Sort by address
    sorted_refs = sorted(refs.items())

    # Group into contiguous clusters
    print(f"=== Global variable references ({len(sorted_refs)} unique addresses) ===")
    print(f"{'Address':>12}  {'Refs':>4}  {'Sample xrefs'}")
    print(f"{'--------':>12}  {'----':>4}  {'------------'}")

    prev_addr = 0
    for addr, count in sorted_refs:
        # Add separator between non-contiguous groups (gap > 16 bytes)
        if prev_addr and addr - prev_addr > 16:
            print()
        xrefs = ", ".join(f"0x{x:08X}" for x in ref_sources[addr][:3])
        if count > 3:
            xrefs += f" (+{count - 3} more)"
        print(f"  0x{addr:08X}  {count:4d}  {xrefs}")
        prev_addr = addr

    # Summary
    print()
    total_refs = sum(refs.values())
    print(f"Total: {len(sorted_refs)} unique globals, {total_refs} references")
    print()
    print("In Ghidra, these appear as DAT_XXXXXXXX.")
    print("Add labels via the rename script or Ghidra's label manager.")


if __name__ == "__main__":
    main()
