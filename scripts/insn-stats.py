#!/usr/bin/env python3
"""Instruction frequency statistics per PE section.

Usage: insn-stats.py <binary> [--top N] [--section NAME]

Disassembles executable sections with Capstone and reports:
- Instruction mnemonic frequency (Zipf-like distribution)
- Operand type distribution (register, memory, immediate)
- Section-by-section comparison
"""
import sys
import argparse
from collections import Counter, defaultdict

try:
    import lief
except ImportError:
    sys.exit("pip install lief")
try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_MODE_64
except ImportError:
    sys.exit("pip install capstone")


def disassemble_section(data, base_addr, bits=32):
    """Disassemble bytes and return (instructions, coverage_info).

    instructions: list of (mnemonic, op_str) — real instructions only
    coverage_info: dict with byte counts for code, padding, data
    """
    mode = CS_MODE_32 if bits == 32 else CS_MODE_64
    cs = Cs(CS_ARCH_X86, mode)
    cs.detail = False

    instructions = []
    code_bytes = 0
    padding_bytes = 0
    total_decoded = 0

    for insn in cs.disasm(data, base_addr):
        total_decoded += insn.size
        # Null-byte artifacts: "add byte ptr [eax], al" from 0x00 runs
        if insn.mnemonic == 'add' and insn.bytes[0] == 0x00:
            padding_bytes += insn.size
            continue
        code_bytes += insn.size
        instructions.append((insn.mnemonic, insn.op_str))

    # Count raw null and 0xFF bytes for the undecoded remainder
    null_bytes = data.count(b'\x00') if isinstance(data, (bytes, bytearray)) else 0
    ff_bytes = data.count(b'\xff') if isinstance(data, (bytes, bytearray)) else 0

    coverage = {
        'total': len(data),
        'decoded': total_decoded,
        'code': code_bytes,
        'padding': padding_bytes,
        'undecoded': len(data) - total_decoded,
        'null_bytes': null_bytes,
        'ff_bytes': ff_bytes,
    }
    return instructions, coverage


def classify_operand(op):
    """Classify an operand string as register, memory, or immediate."""
    op = op.strip()
    if not op:
        return None
    if op.startswith('[') or 'ptr' in op:
        return 'memory'
    if op.startswith('0x') or op.startswith('-0x') or op.lstrip('-').isdigit():
        return 'immediate'
    return 'register'


def print_freq(counter, label, top_n):
    """Print frequency table with rank, count, and percentage."""
    total = sum(counter.values())
    if total == 0:
        print(f"  (no {label})")
        return
    print(f"  {'Rank':<6} {'Count':>7} {'%':>7}  {label.title()}")
    print(f"  {'─'*6} {'─'*7} {'─'*7}  {'─'*20}")
    for rank, (item, count) in enumerate(counter.most_common(top_n), 1):
        pct = count * 100 / total
        print(f"  {rank:<6} {count:>7} {pct:>6.1f}%  {item}")
    if len(counter) > top_n:
        print(f"  ... and {len(counter) - top_n} more (total: {total})")
    else:
        print(f"  Total: {total}")


def main():
    parser = argparse.ArgumentParser(description="PE instruction statistics")
    parser.add_argument("binary", help="PE file to analyze")
    parser.add_argument("--top", type=int, default=25, help="Top N instructions (default: 25)")
    parser.add_argument("--section", help="Analyze only this section")
    args = parser.parse_args()

    pe = lief.parse(args.binary)
    if pe is None:
        sys.exit(f"Failed to parse: {args.binary}")

    bits = 32 if pe.header.machine == lief.PE.Header.MACHINE_TYPES.I386 else 64

    # Collect instructions and coverage per section
    section_insns = {}
    section_cov = {}
    for section in pe.sections:
        name = section.name.rstrip('\x00')
        if args.section and name != args.section:
            continue
        # Only disassemble sections with execute permission
        chars = section.characteristics
        if not (chars & int(lief.PE.Section.CHARACTERISTICS.MEM_EXECUTE)):
            continue
        data = bytes(section.content)
        if not data:
            continue
        base = pe.optional_header.imagebase + section.virtual_address
        insns, cov = disassemble_section(data, base, bits)
        section_insns[name] = insns
        section_cov[name] = cov

    if not section_cov:
        sys.exit("No executable sections found")

    # Section coverage overview
    print("=== Section Coverage ===")
    print()
    print(f"  {'Section':<10} {'Size':>8} {'Code':>8} {'Padding':>8} {'Undecoded':>10}  {'Code%':>6}  Assessment")
    print(f"  {'─'*10} {'─'*8} {'─'*8} {'─'*8} {'─'*10}  {'─'*6}  {'─'*20}")
    for name, cov in section_cov.items():
        code_pct = cov['code'] * 100 / max(cov['total'], 1)
        # Assess what the section likely contains
        if code_pct > 40:
            assessment = "executable code"
        elif cov['null_bytes'] > cov['total'] * 0.7:
            assessment = "mostly null (unpacked target?)"
        elif cov['ff_bytes'] > cov['total'] * 0.5:
            assessment = "mostly 0xFF fill"
        elif cov['padding'] > cov['total'] * 0.5:
            assessment = "null-padded data"
        else:
            assessment = "data (not code)"
        print(f"  {name:<10} {cov['total']:>8} {cov['code']:>8} {cov['padding']:>8} {cov['undecoded']:>10}  {code_pct:>5.1f}%  {assessment}")
    print()

    # Per-section instruction stats (only for sections with real code)
    all_mnemonics = Counter()
    all_operands = Counter()

    for name, insns in section_insns.items():
        if not insns:
            continue
        cov = section_cov[name]
        code_pct = cov['code'] * 100 / max(cov['total'], 1)

        mnemonics = Counter(m for m, _ in insns)
        operands = Counter()
        for _, op_str in insns:
            for op in op_str.split(','):
                cls = classify_operand(op)
                if cls:
                    operands[cls] += 1

        print(f"=== {name} ({len(insns)} instructions, {code_pct:.0f}% code coverage) ===")
        print()
        print("[Instruction frequency]")
        print_freq(mnemonics, "mnemonic", args.top)
        print()
        print("[Operand types]")
        print_freq(operands, "type", 10)
        print()

        all_mnemonics.update(mnemonics)
        all_operands.update(operands)

    # Combined stats if multiple sections with code
    sections_with_code = [n for n, i in section_insns.items() if i]
    if len(sections_with_code) > 1:
        total_insns = sum(len(section_insns[n]) for n in sections_with_code)
        print(f"=== Combined ({total_insns} instructions across {len(sections_with_code)} sections) ===")
        print()
        print("[Instruction frequency]")
        print_freq(all_mnemonics, "mnemonic", args.top)
        print()
        print("[Operand types]")
        print_freq(all_operands, "type", 10)
        print()

    # Summary
    print(f"[Summary]")
    print(f"  Unique mnemonics: {len(all_mnemonics)}")
    print(f"  Total instructions: {sum(all_mnemonics.values())}")
    ratio = sum(all_operands.values()) / max(sum(all_mnemonics.values()), 1)
    print(f"  Avg operands/insn: {ratio:.2f}")


if __name__ == "__main__":
    main()
