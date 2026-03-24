#!/usr/bin/env python3
"""Scan a PE binary or memory dump for FF 25 (JMP [addr]) and FF 15 (CALL [addr])
trampolines — indirect jumps/calls through pointer tables (IAT thunks, etc.).

Usage: find-trampolines.py <exe-or-dump>
"""

import struct
import sys
import os
from collections import Counter


def parse_pe_sections(data):
    """Parse PE headers to extract section VA mappings."""
    image_base = 0x400000
    sections = []
    try:
        pe_off = struct.unpack("<I", data[0x3C:0x40])[0]
        if data[pe_off:pe_off + 4] != b"PE\x00\x00":
            return image_base, sections
        num_sec = struct.unpack("<H", data[pe_off + 6:pe_off + 8])[0]
        opt_off = pe_off + 4 + 20
        opt_magic = struct.unpack("<H", data[opt_off:opt_off + 2])[0]
        if opt_magic == 0x10B:  # PE32
            image_base = struct.unpack("<I", data[opt_off + 28:opt_off + 32])[0]
        elif opt_magic == 0x20B:  # PE32+
            image_base = struct.unpack("<Q", data[opt_off + 24:opt_off + 32])[0]
        opt_size = struct.unpack("<H", data[pe_off + 4 + 16:pe_off + 4 + 18])[0]
        sec_start = opt_off + opt_size
        for i in range(min(num_sec, 20)):  # cap at 20 to skip junk
            off = sec_start + i * 40
            if off + 40 > len(data):
                break
            name = data[off:off + 8].rstrip(b"\x00").decode("ascii", errors="replace")
            vsize, rva, rawsize, rawoff = struct.unpack("<IIII", data[off + 8:off + 24])
            if rawsize > 0 and rva > 0:
                sections.append((name, rva, vsize, rawoff, rawsize))
    except Exception:
        pass
    return image_base, sections


def file_to_va(foff, image_base, sections):
    """Convert file offset to VA using section mapping."""
    for _, rva, vsize, rawoff, rawsize in sections:
        if rawoff <= foff < rawoff + rawsize:
            return image_base + rva + (foff - rawoff)
    return None


def main():
    if len(sys.argv) < 2:
        print("Usage: find-trampolines.py <exe-or-dump>")
        sys.exit(1)

    path = sys.argv[1]
    if not os.path.isfile(path):
        print(f"File not found: {path}")
        sys.exit(1)

    with open(path, "rb") as fh:
        data = fh.read()

    image_base, sections = parse_pe_sections(data)

    # Collect all trampolines
    jmps = []
    calls = []

    # Determine plausible target range: within the PE image
    pe_start = image_base
    pe_end = image_base
    for _, rva, vsize, _, _ in sections:
        sec_end = image_base + rva + vsize
        if sec_end > pe_end:
            pe_end = sec_end

    for i in range(len(data) - 5):
        opcode = data[i]
        modrm = data[i + 1]
        if opcode == 0xFF and modrm in (0x25, 0x15):
            target = struct.unpack("<I", data[i + 2:i + 6])[0]
            va = file_to_va(i, image_base, sections)
            if va is None:
                continue
            # Filter: target pointer must be within the PE image
            if target < pe_start or target >= pe_end:
                continue
            kind = "JMP" if modrm == 0x25 else "CALL"
            if kind == "JMP":
                jmps.append((va, target))
            else:
                calls.append((va, target))

    if not jmps and not calls:
        print("No FF 25 / FF 15 trampolines found.")
        sys.exit(0)

    all_targets = [t for _, t in jmps] + [t for _, t in calls]
    min_target = min(all_targets)
    max_target = max(all_targets)

    # Print summary
    print(f"File: {os.path.basename(path)}")
    print(f"Image base: 0x{image_base:08X}")
    if sections:
        print(f"Sections: {', '.join(n for n, _, _, _, _ in sections)}")
    print()

    if jmps:
        print(f"=== JMP [addr] trampolines ({len(jmps)} found) ===")
        print(f"{'Stub VA':>12}  {'Opcode':>8}  {'Ptr Target':>12}  Note")
        print(f"{'--------':>12}  {'------':>8}  {'----------':>12}  ----")
        for va, target in sorted(jmps):
            note = ""
            if any(s_va == target for s_va, _ in jmps):
                note = "(ptr overlaps stub)"
            print(f"  0x{va:08X}  FF 25     0x{target:08X}  {note}")

        jmp_targets = sorted(set(t for _, t in jmps))
        print()
        print(f"Pointer table range: 0x{jmp_targets[0]:08X} - 0x{jmp_targets[-1]:08X}")
        print(f"Unique pointer slots: {len(jmp_targets)}")

    if calls:
        print()
        print(f"=== CALL [addr] trampolines ({len(calls)} found) ===")
        print(f"{'Stub VA':>12}  {'Opcode':>8}  {'Ptr Target':>12}")
        print(f"{'--------':>12}  {'------':>8}  {'----------':>12}")
        for va, target in sorted(calls):
            print(f"  0x{va:08X}  FF 15     0x{target:08X}")

    print()
    print(f"Total: {len(jmps)} JMP + {len(calls)} CALL = {len(jmps) + len(calls)} trampolines")
    print()
    print("To resolve API names at runtime, use cdb/WinDbg:")
    print(f"  dps {min_target:08X} {max_target + 4:08X}")


if __name__ == "__main__":
    main()
