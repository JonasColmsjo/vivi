#!/usr/bin/env python3
"""Extract the main executable (unpacked) from a ProcDump minidump.

When a packed binary (UPX, etc.) runs, the packer stub decompresses the
original code into memory. ProcDump captures this unpacked state. This
script extracts the main module's memory image as a PE file.

Usage:
    extract-pe-from-dump.py <dump.dmp> [output.exe] [--module NAME]

Output is a PE executable with the unpacked code. Section headers still
reference the original (packed) layout, but the code/data is unpacked.

Requires: pip install minidump
"""
import sys
import argparse
from minidump.minidumpfile import MinidumpFile


def main():
    parser = argparse.ArgumentParser(
        description="Extract unpacked PE from ProcDump minidump")
    parser.add_argument("dmpfile", help="ProcDump .dmp file")
    parser.add_argument("output", nargs="?", help="Output PE file (default: <basename>-unpacked.exe)")
    parser.add_argument("--module", help="Module name to extract (default: main exe, not a .dll)")
    parser.add_argument("--list", action="store_true", help="List modules and exit")
    args = parser.parse_args()

    mf = MinidumpFile.parse(args.dmpfile)

    if args.list:
        print(f"Modules in {args.dmpfile}:")
        print(f"  {'Base':>12s}  {'Size':>8s}  Name")
        print(f"  {'─'*12}  {'─'*8}  {'─'*40}")
        for mod in mf.modules.modules:
            print(f"  0x{mod.baseaddress:08x}  {mod.size:>8,}  {mod.name}")
        return

    # Find target module
    target = None
    if args.module:
        for mod in mf.modules.modules:
            if args.module.lower() in mod.name.lower():
                target = mod
                break
        if not target:
            print(f"Module '{args.module}' not found. Use --list to see modules.", file=sys.stderr)
            sys.exit(1)
    else:
        # Default: first module that is NOT a .dll (the main exe)
        for mod in mf.modules.modules:
            if not mod.name.lower().endswith(".dll"):
                target = mod
                break
        if not target:
            print("No non-DLL module found. Use --module to specify.", file=sys.stderr)
            sys.exit(1)

    base = target.baseaddress
    size = target.size
    print(f"Module: {target.name}")
    print(f"  Base: 0x{base:08x}")
    print(f"  Size: {size:,} bytes ({size // 1024}KB)")

    # Read memory page by page (4KB)
    reader = mf.get_reader()
    data = bytearray(size)
    page_size = 4096
    ok_pages = 0
    fail_pages = 0

    for offset in range(0, size, page_size):
        chunk = min(page_size, size - offset)
        try:
            page = reader.read(base + offset, chunk)
            data[offset:offset + chunk] = page
            ok_pages += 1
        except Exception:
            fail_pages += 1

    print(f"  Pages: {ok_pages} read, {fail_pages} failed")

    # Verify PE
    if data[:2] != b'MZ':
        print("WARNING: No MZ header — module memory may be corrupt", file=sys.stderr)
    else:
        pe_offset = int.from_bytes(data[0x3c:0x40], 'little')
        if data[pe_offset:pe_offset + 4] == b'PE\x00\x00':
            print(f"  PE signature at 0x{pe_offset:x}: OK")
        else:
            print(f"  PE signature at 0x{pe_offset:x}: MISSING", file=sys.stderr)

    # Output path
    if args.output:
        outpath = args.output
    else:
        import os
        basename = os.path.splitext(os.path.basename(args.dmpfile))[0]
        outpath = os.path.join(os.path.dirname(args.dmpfile) or ".", f"{basename}-unpacked.exe")

    with open(outpath, 'wb') as f:
        f.write(bytes(data))

    print(f"\nSaved: {outpath} ({len(data):,} bytes)")


if __name__ == "__main__":
    main()
