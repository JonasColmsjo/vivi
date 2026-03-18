#!/usr/bin/env python3
"""Search a memory dump for the TEA encryption key using a known PT/CT pair.

Slides a 16-byte window across the entire dump, tries each as a TEA key,
and checks if it encrypts the known plaintext to the known ciphertext.

Usage:
    tea-key-search.py <dump> --pt <hex> --ct <hex>
    tea-key-search.py <dump>    # uses default Xorist PT/CT pair

Requires: pip install minidump
"""
import sys
import struct
import argparse
import time


def tea_encrypt(plaintext: bytes, key: bytes) -> bytes:
    """TEA encrypt one 8-byte block with 128-bit key. Standard 32 rounds."""
    v0, v1 = struct.unpack('<II', plaintext)
    k0, k1, k2, k3 = struct.unpack('<IIII', key)
    delta = 0x9E3779B9
    total = 0
    mask = 0xFFFFFFFF
    for _ in range(32):
        total = (total + delta) & mask
        v0 = (v0 + (((v1 << 4) + k0) ^ (v1 + total) ^ ((v1 >> 5) + k1))) & mask
        v1 = (v1 + (((v0 << 4) + k2) ^ (v0 + total) ^ ((v0 >> 5) + k3))) & mask
    return struct.pack('<II', v0, v1)


def tea_decrypt(ciphertext: bytes, key: bytes) -> bytes:
    """TEA decrypt one 8-byte block with 128-bit key. Standard 32 rounds."""
    v0, v1 = struct.unpack('<II', ciphertext)
    k0, k1, k2, k3 = struct.unpack('<IIII', key)
    delta = 0x9E3779B9
    total = (delta * 32) & 0xFFFFFFFF
    mask = 0xFFFFFFFF
    for _ in range(32):
        v1 = (v1 - (((v0 << 4) + k2) ^ (v0 + total) ^ ((v0 >> 5) + k3))) & mask
        v0 = (v0 - (((v1 << 4) + k0) ^ (v1 + total) ^ ((v1 >> 5) + k1))) & mask
        total = (total - delta) & mask
    return struct.pack('<II', v0, v1)


def xtea_encrypt(plaintext: bytes, key: bytes) -> bytes:
    """XTEA encrypt one 8-byte block. 32 rounds."""
    v0, v1 = struct.unpack('<II', plaintext)
    k = struct.unpack('<IIII', key)
    delta = 0x9E3779B9
    total = 0
    mask = 0xFFFFFFFF
    for _ in range(32):
        v0 = (v0 + ((((v1 << 4) ^ (v1 >> 5)) + v1) ^ (total + k[total & 3]))) & mask
        total = (total + delta) & mask
        v1 = (v1 + ((((v0 << 4) ^ (v0 >> 5)) + v0) ^ (total + k[(total >> 11) & 3]))) & mask
    return struct.pack('<II', v0, v1)


def search_dump_file(dump_path: str, pt: bytes, ct: bytes):
    """Search raw file for TEA key."""
    with open(dump_path, 'rb') as f:
        data = f.read()
    return search_data(data, pt, ct, dump_path)


def search_minidump(dump_path: str, pt: bytes, ct: bytes):
    """Search minidump memory regions for TEA key."""
    from minidump.minidumpfile import MinidumpFile
    mf = MinidumpFile.parse(dump_path)
    reader = mf.get_reader()

    # Read all memory from each module + any additional memory regions
    regions = []
    for mod in mf.modules.modules:
        try:
            page_size = 4096
            module_data = bytearray(mod.size)
            for offset in range(0, mod.size, page_size):
                chunk = min(page_size, mod.size - offset)
                try:
                    page = reader.read(mod.baseaddress + offset, chunk)
                    module_data[offset:offset + chunk] = page
                except Exception:
                    pass
            regions.append((mod.name, mod.baseaddress, bytes(module_data)))
        except Exception as e:
            print(f"  Warning: couldn't read {mod.name}: {e}")

    # Also try reading memory ranges from the minidump memory list
    if hasattr(mf, 'memory') and mf.memory is not None:
        for mem_range in mf.memory.infos:
            addr = mem_range.BaseAddress if hasattr(mem_range, 'BaseAddress') else None
            size = mem_range.RegionSize if hasattr(mem_range, 'RegionSize') else None
            if addr is not None and size is not None and size < 50_000_000:
                try:
                    data = reader.read(addr, size)
                    regions.append((f"region@0x{addr:08x}", addr, data))
                except Exception:
                    pass

    print(f"  Loaded {len(regions)} memory regions")
    total_bytes = sum(len(d) for _, _, d in regions)
    print(f"  Total memory: {total_bytes:,} bytes ({total_bytes // 1024 // 1024} MB)")
    print()

    found = []
    t0 = time.time()
    positions_checked = 0

    for name, base_addr, data in regions:
        if len(data) < 16:
            continue
        for i in range(len(data) - 15):
            candidate_key = data[i:i + 16]
            positions_checked += 1
            if tea_encrypt(pt, candidate_key) == ct:
                addr = base_addr + i
                found.append((addr, candidate_key, name))
                print(f"  *** FOUND KEY at 0x{addr:08x} in {name} ***")
                print(f"  Key (hex): {candidate_key.hex()}")
                printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in candidate_key)
                print(f"  Key (ascii): {printable}")
                # Verify decryption
                decrypted = tea_decrypt(ct, candidate_key)
                print(f"  Verify: decrypt({ct.hex()}) = {decrypted.hex()} (expected {pt.hex()}) {'OK' if decrypted == pt else 'MISMATCH'}")
                print()

    elapsed = time.time() - t0
    rate = positions_checked / elapsed if elapsed > 0 else 0
    print(f"  Searched {positions_checked:,} positions in {elapsed:.1f}s ({rate:,.0f}/s)")
    return found


def search_data(data: bytes, pt: bytes, ct: bytes, label: str = ""):
    """Search raw bytes for TEA key."""
    found = []
    t0 = time.time()

    for i in range(len(data) - 15):
        candidate_key = data[i:i + 16]
        if tea_encrypt(pt, candidate_key) == ct:
            found.append((i, candidate_key, label))
            print(f"  *** FOUND KEY at offset 0x{i:x} ***")
            print(f"  Key (hex): {candidate_key.hex()}")
            printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in candidate_key)
            print(f"  Key (ascii): {printable}")
            decrypted = tea_decrypt(ct, candidate_key)
            print(f"  Verify: decrypt({ct.hex()}) = {decrypted.hex()} {'OK' if decrypted == pt else 'MISMATCH'}")
            print()

    elapsed = time.time() - t0
    rate = len(data) / elapsed if elapsed > 0 else 0
    print(f"  Searched {len(data):,} bytes in {elapsed:.1f}s ({rate:,.0f}/s)")
    return found


def main():
    parser = argparse.ArgumentParser(description="Search memory dump for TEA key")
    parser.add_argument("dump", help="Memory dump file (.dmp or raw)")
    parser.add_argument("--pt", required=True,
                        help="Known plaintext (hex, 8 bytes)")
    parser.add_argument("--ct", required=True,
                        help="Known ciphertext (hex, 8 bytes)")
    parser.add_argument("--raw", action="store_true",
                        help="Treat as raw file (not minidump)")
    args = parser.parse_args()

    pt = bytes.fromhex(args.pt)
    ct = bytes.fromhex(args.ct)
    assert len(pt) == 8, "Plaintext must be 8 bytes"
    assert len(ct) == 8, "Ciphertext must be 8 bytes"

    print(f"=== TEA Key Search ===")
    print(f"  Dump: {args.dump}")
    print(f"  PT:   {pt.hex()}")
    print(f"  CT:   {ct.hex()}")
    print()

    # Verify TEA: encrypt zeros with zero key, then decrypt, must round-trip
    test_ct = tea_encrypt(b'\x00' * 8, b'\x00' * 16)
    test_pt = tea_decrypt(test_ct, b'\x00' * 16)
    assert test_pt == b'\x00' * 8, f"TEA round-trip failed"
    print(f"  TEA self-test: OK (zeros -> {test_ct.hex()} -> zeros)")
    print()

    if args.raw or not args.dump.endswith('.dmp'):
        found = search_dump_file(args.dump, pt, ct)
    else:
        try:
            found = search_minidump(args.dump, pt, ct)
        except Exception as e:
            print(f"  Minidump parse failed ({e}), trying as raw file...")
            found = search_dump_file(args.dump, pt, ct)

    if found:
        print(f"=== {len(found)} key(s) found ===")
        for addr, key, name in found:
            print(f"  0x{addr:08x}  {key.hex()}  {name}")
    else:
        print("=== No key found ===")
        print("  Possible reasons:")
        print("  - Key was on stack/heap and got overwritten before dump")
        print("  - Non-standard TEA variant (different rounds or constants)")
        print("  - PT/CT pair is from the unencrypted header region")
        print("  Try: --pt and --ct from a different file pair")


if __name__ == "__main__":
    main()
