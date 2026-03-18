#!/usr/bin/env python3
"""Known-plaintext attack: compare original file vs encrypted to extract key.

Given a plaintext file and its encrypted counterpart, this script:
1. XORs them byte-by-byte to find the key stream
2. Detects if a short key repeats (XOR cipher)
3. Analyzes 8-byte TEA block structure if XOR key doesn't repeat
4. Reports the encryption method and key

Usage:
    known-plaintext.py <original> <encrypted> [--block-size N]
    known-plaintext.py --dir <clean-mount> <infected-mount> [--ext .EnCiPhErEd]

The --dir mode finds matching files automatically.
"""
import sys
import os
import argparse
from math import gcd
from collections import Counter


def xor_bytes(a: bytes, b: bytes) -> bytes:
    """XOR two byte strings (truncated to shorter length)."""
    return bytes(x ^ y for x, y in zip(a, b))


def find_repeating_key(keystream: bytes, max_key_len: int = 256) -> tuple[int, bytes] | None:
    """Detect if keystream is a repeating key. Returns (period, key) or None."""
    n = len(keystream)
    if n < 16:
        return None

    for period in range(1, min(max_key_len + 1, n // 2)):
        candidate = keystream[:period]
        match = True
        for i in range(period, min(n, period * 20)):  # check up to 20 repetitions
            if keystream[i] != candidate[i % period]:
                match = False
                break
        if match:
            # Verify over more data
            mismatches = 0
            check_len = min(n, period * 100)
            for i in range(check_len):
                if keystream[i] != candidate[i % period]:
                    mismatches += 1
            if mismatches == 0:
                return (period, candidate)
    return None


def analyze_blocks(keystream: bytes, block_size: int = 8) -> dict:
    """Analyze keystream at block granularity (for block ciphers like TEA)."""
    n = len(keystream)
    n_blocks = n // block_size
    if n_blocks < 2:
        return {"blocks": 0}

    blocks = [keystream[i*block_size:(i+1)*block_size] for i in range(n_blocks)]

    # Check if all blocks are identical (ECB with same plaintext blocks would differ,
    # but a simple XOR would repeat)
    unique_blocks = len(set(blocks))

    # Check if keystream blocks repeat with a period
    for period in range(1, min(n_blocks // 2 + 1, 32)):
        match = True
        for i in range(period, min(n_blocks, period * 10)):
            if blocks[i] != blocks[i % period]:
                match = False
                break
        if match:
            return {
                "blocks": n_blocks,
                "unique": unique_blocks,
                "block_period": period,
                "repeating_key": b''.join(blocks[:period]),
            }

    return {
        "blocks": n_blocks,
        "unique": unique_blocks,
        "block_period": None,
    }


def analyze_pair(orig_path: str, enc_path: str, block_size: int = 8, verbose: bool = True):
    """Compare original vs encrypted file and extract key information."""
    with open(orig_path, 'rb') as f:
        orig = f.read()
    with open(enc_path, 'rb') as f:
        enc = f.read()

    if verbose:
        print(f"  Original:  {len(orig):,} bytes  {orig_path}")
        print(f"  Encrypted: {len(enc):,} bytes  {enc_path}")

    # Check size relationship
    if len(orig) != len(enc):
        size_diff = len(enc) - len(orig)
        if verbose:
            print(f"  Size diff: {size_diff:+,} bytes")
            if size_diff > 0:
                print(f"  Encrypted file is larger — may have header/padding")
            else:
                print(f"  Encrypted file is smaller — unusual")

    # XOR the overlapping portion
    min_len = min(len(orig), len(enc))
    keystream = xor_bytes(orig[:min_len], enc[:min_len])

    if verbose:
        print(f"  Keystream: {min_len:,} bytes")
        print()

    # Check if keystream is all zeros (files are identical)
    if all(b == 0 for b in keystream):
        if verbose:
            print("  Files are IDENTICAL — no encryption applied")
        return {"method": "none", "key": None}

    # Detect header skip — find first non-zero byte in keystream
    skip = 0
    for i, b in enumerate(keystream):
        if b != 0:
            skip = i
            break
    if skip > 0:
        if verbose:
            print(f"  Header skip: first {skip} bytes are NOT encrypted")
            print(f"  Encryption starts at byte {skip}")
            print()
        # Re-analyze from the encrypted portion only
        keystream = keystream[skip:]
        orig = orig[skip:]
        enc = enc[skip:]
        min_len = len(keystream)

    # Check for repeating XOR key
    result = find_repeating_key(keystream)
    if result:
        period, key = result
        if verbose:
            print(f"  === XOR cipher detected ===")
            print(f"  Key length: {period} bytes")
            print(f"  Key (hex):  {key.hex()}")
            if period <= 32:
                # Try to display as ASCII
                printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in key)
                print(f"  Key (ascii): {printable}")
            print()
            # Verify: decrypt first 64 bytes
            print(f"  Verification (first 64 bytes of decrypted):")
            decrypted = xor_bytes(enc[:64], (key * (64 // period + 1))[:64])
            print(f"    {decrypted[:64]}")
        return {"method": "xor", "key_len": period, "key": key}

    # No simple XOR — analyze block structure
    if verbose:
        print(f"  No repeating XOR key found")
        print()

    # Check for offset/header in encrypted file
    # Some ransomware prepends a header — try XORing with offsets
    if len(enc) > len(orig):
        header_size = len(enc) - len(orig)
        if verbose:
            print(f"  Trying with {header_size}-byte header offset...")
        shifted_ks = xor_bytes(orig, enc[header_size:header_size + len(orig)])
        shifted_result = find_repeating_key(shifted_ks)
        if shifted_result:
            period, key = shifted_result
            if verbose:
                print(f"  === XOR cipher with {header_size}-byte header ===")
                print(f"  Key length: {period} bytes")
                print(f"  Key (hex):  {key.hex()}")
                printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in key)
                print(f"  Key (ascii): {printable}")
            return {"method": "xor+header", "header_size": header_size,
                    "key_len": period, "key": key}

    # Block cipher analysis
    if verbose:
        print(f"  === Block analysis ({block_size}-byte blocks) ===")
    ba = analyze_blocks(keystream, block_size)
    if verbose:
        print(f"  Total blocks: {ba['blocks']}")
        print(f"  Unique keystream blocks: {ba.get('unique', '?')}")
        if ba.get('block_period'):
            print(f"  Block period: {ba['block_period']}")
            bkey = ba['repeating_key']
            print(f"  Block key (hex): {bkey.hex()}")
        else:
            print(f"  No block-level repetition — true block cipher (TEA-CBC or similar)")
    if verbose:
        print()

    # Show first few keystream blocks for manual analysis
    if verbose:
        print(f"  First 8 keystream blocks ({block_size} bytes each):")
        for i in range(min(8, len(keystream) // block_size)):
            block = keystream[i*block_size:(i+1)*block_size]
            print(f"    [{i}] {block.hex()}")
        print()

        # Show byte frequency distribution of keystream
        freq = Counter(keystream)
        entropy = -sum((c/min_len) * __import__('math').log2(c/min_len)
                       for c in freq.values() if c > 0)
        print(f"  Keystream entropy: {entropy:.2f} bits/byte (8.0 = perfectly random)")
        if entropy > 7.5:
            print(f"  High entropy — consistent with block cipher (TEA, AES)")
        elif entropy > 6.0:
            print(f"  Moderate entropy — may be a weak cipher or partial encryption")
        else:
            print(f"  Low entropy — likely XOR with structured key")

    return {"method": "block_cipher", "analysis": ba}


def find_matching_files(clean_dir: str, infected_dir: str, ext: str = ".EnCiPhErEd") -> list:
    """Find files in clean_dir that have encrypted counterparts in infected_dir."""
    pairs = []
    for root, dirs, files in os.walk(clean_dir):
        for fname in files:
            orig_path = os.path.join(root, fname)
            # Compute relative path
            rel = os.path.relpath(orig_path, clean_dir)
            # Look for encrypted version
            enc_path = os.path.join(infected_dir, rel + ext)
            if os.path.exists(enc_path):
                orig_size = os.path.getsize(orig_path)
                if orig_size > 0:  # skip empty files
                    pairs.append((orig_path, enc_path, orig_size))
    return pairs


def main():
    parser = argparse.ArgumentParser(
        description="Known-plaintext attack: extract encryption key from original+encrypted file pair")
    parser.add_argument("files", nargs="*", help="<original> <encrypted> OR with --dir: <clean-mount> <infected-mount>")
    parser.add_argument("--dir", action="store_true", help="Directory mode: find matching file pairs")
    parser.add_argument("--ext", default=".EnCiPhErEd", help="Encrypted file extension (default: .EnCiPhErEd)")
    parser.add_argument("--block-size", type=int, default=8, help="Block size for analysis (default: 8 = TEA)")
    parser.add_argument("--limit", type=int, default=5, help="Max file pairs to analyze in --dir mode")
    parser.add_argument("--all", action="store_true", help="Analyze all matching pairs (not just --limit)")
    args = parser.parse_args()

    if args.dir:
        if len(args.files) != 2:
            print("Usage: known-plaintext.py --dir <clean-mount> <infected-mount>", file=sys.stderr)
            sys.exit(1)
        clean_dir, infected_dir = args.files

        print(f"Scanning for file pairs...")
        print(f"  Clean:    {clean_dir}")
        print(f"  Infected: {infected_dir}")
        print(f"  Extension: {args.ext}")
        print()

        pairs = find_matching_files(clean_dir, infected_dir, args.ext)
        if not pairs:
            print("No matching file pairs found.")
            print(f"  Check that encrypted files have '{args.ext}' appended to original name")
            sys.exit(1)

        # Sort by size — skip very small files (ransomware often has min size)
        # Try medium-sized files first (1KB-100KB range is ideal)
        pairs.sort(key=lambda x: x[2])
        # Partition: skip files < 256 bytes (likely below encryption threshold)
        small = [(o, e, s) for o, e, s in pairs if s < 256]
        medium = [(o, e, s) for o, e, s in pairs if 256 <= s <= 102400]
        large = [(o, e, s) for o, e, s in pairs if s > 102400]
        if small:
            print(f"  Skipping {len(small)} files < 256 bytes (likely below encryption threshold)")
        pairs = medium + large
        if not pairs:
            print("No files >= 256 bytes found with encrypted counterparts.")
            sys.exit(1)

        print(f"Found {len(pairs)} matching file pairs")
        print()

        # Show all pairs
        print(f"{'Size':>10s}  File")
        print(f"{'─'*10}  {'─'*60}")
        for orig, enc, size in pairs[:20]:
            rel = os.path.relpath(orig, clean_dir)
            print(f"{size:>10,}  {rel}")
        if len(pairs) > 20:
            print(f"  ... and {len(pairs) - 20} more")
        print()

        # Analyze pairs
        limit = len(pairs) if args.all else min(args.limit, len(pairs))
        results = []
        for i, (orig, enc, size) in enumerate(pairs[:limit]):
            rel = os.path.relpath(orig, clean_dir)
            print(f"═══ [{i+1}/{limit}] {rel} ({size:,} bytes) ═══")
            result = analyze_pair(orig, enc, args.block_size)
            results.append(result)
            print()

        # Cross-file ECB detection: same plaintext block → same ciphertext block?
        print("═══ Cross-File ECB Analysis ═══")
        # Collect (plaintext_block, ciphertext_block) pairs at each offset
        block_map = {}  # offset -> list of (pt_block, ct_block, file_idx)
        for i, (orig, enc, size) in enumerate(pairs[:limit]):
            with open(orig, 'rb') as f:
                pt = f.read()
            with open(enc, 'rb') as f:
                ct = f.read()
            # Find encryption start
            ks = xor_bytes(pt, ct)
            skip_bytes = 0
            for j, b in enumerate(ks):
                if b != 0:
                    skip_bytes = j
                    break
            if skip_bytes > 0:
                pt = pt[skip_bytes:]
                ct = ct[skip_bytes:]
            for blk_idx in range(min(len(pt), len(ct)) // args.block_size):
                pt_blk = pt[blk_idx*args.block_size:(blk_idx+1)*args.block_size]
                ct_blk = ct[blk_idx*args.block_size:(blk_idx+1)*args.block_size]
                if pt_blk not in block_map:
                    block_map[pt_blk] = []
                block_map[pt_blk].append((ct_blk, i, blk_idx))

        # Check if same plaintext always produces same ciphertext (ECB)
        ecb_matches = 0
        ecb_mismatches = 0
        for pt_blk, entries in block_map.items():
            if len(entries) < 2:
                continue
            ct_blocks = set(e[0] for e in entries)
            if len(ct_blocks) == 1:
                ecb_matches += 1
            else:
                ecb_mismatches += 1

        if ecb_matches + ecb_mismatches > 0:
            print(f"  Plaintext blocks seen in multiple files: {ecb_matches + ecb_mismatches}")
            print(f"  Same PT → same CT (ECB): {ecb_matches}")
            print(f"  Same PT → different CT:  {ecb_mismatches}")
            if ecb_mismatches == 0 and ecb_matches > 0:
                print(f"  → TEA-ECB mode confirmed! Same key for all files.")
                print(f"  → Key can be recovered with TEA brute-force on known PT/CT pair")
            elif ecb_mismatches > 0:
                print(f"  → NOT ECB — likely CBC or CTR mode (per-file IV/nonce)")
        else:
            print(f"  No overlapping plaintext blocks across files")
            print(f"  (files too small or too different to detect ECB vs CBC)")
        print()

        # Show a known PT/CT pair for brute-force
        # Find a pair where we have a clean 8-byte block
        for pt_blk, entries in block_map.items():
            if len(entries) >= 2:
                ct_blk = entries[0][0]
                print(f"  Sample PT/CT pair (for TEA key recovery):")
                print(f"    Plaintext:  {pt_blk.hex()}")
                print(f"    Ciphertext: {ct_blk.hex()}")
                break
        print()

        # Summary
        print("═══ Summary ═══")
        methods = Counter(r["method"] for r in results)
        for method, count in methods.most_common():
            print(f"  {method}: {count} file(s)")

        # If XOR key found, show it prominently
        xor_results = [r for r in results if r["method"] in ("xor", "xor+header")]
        if xor_results:
            keys = set(r["key"].hex() for r in xor_results)
            if len(keys) == 1:
                key = xor_results[0]["key"]
                print()
                print(f"  *** ENCRYPTION KEY FOUND ***")
                print(f"  Method: XOR")
                print(f"  Key length: {len(key)} bytes")
                print(f"  Key (hex): {key.hex()}")
                printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in key)
                print(f"  Key (ascii): {printable}")
                if xor_results[0].get("header_size"):
                    print(f"  Header size: {xor_results[0]['header_size']} bytes")
            else:
                print()
                print(f"  WARNING: Different keys found across files!")
                for r in xor_results:
                    print(f"    {r['key'].hex()}")

    else:
        if len(args.files) != 2:
            print("Usage: known-plaintext.py <original> <encrypted>", file=sys.stderr)
            print("       known-plaintext.py --dir <clean-mount> <infected-mount>", file=sys.stderr)
            sys.exit(1)

        orig_path, enc_path = args.files
        if not os.path.exists(orig_path):
            print(f"File not found: {orig_path}", file=sys.stderr)
            sys.exit(1)
        if not os.path.exists(enc_path):
            print(f"File not found: {enc_path}", file=sys.stderr)
            sys.exit(1)

        print(f"═══ Known-Plaintext Analysis ═══")
        print()
        analyze_pair(orig_path, enc_path, args.block_size)


if __name__ == "__main__":
    main()
