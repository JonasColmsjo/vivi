#!/usr/bin/env bash
# Disassemble a binary or minidump region and analyze with Claude.
# Usage: disasm-analyze.sh <binary> <start-addr> [end-addr] [--context <annotated.c|ghidra-dir>]
set -euo pipefail

binary="$1"
start="$2"
shift 2

# Parse remaining args
end=""
context_path=""
while [ $# -gt 0 ]; do
    case "$1" in
        --context) context_path="$2"; shift 2 ;;
        0x*) end="$1"; shift ;;
        *) shift ;;
    esac
done

if [ ! -f "$binary" ]; then
    echo "Error: Binary not found: $binary" >&2
    exit 1
fi

# Detect file type
filetype=$(file -b "$binary")
start_dec=$((start))
start_hex=$(printf '%x' "$start_dec")
echo "--- Disassembling $binary from 0x${start_hex} ---" >&2
echo "    File type: $filetype" >&2

if [ -n "$end" ]; then
    end_dec=$((end))
    nbytes=$(( end_dec - start_dec ))
else
    nbytes=800
fi

if echo "$filetype" | grep -qi "mini dump\|minidump\|mdmp"; then
    echo "    Extracting $nbytes bytes from minidump..." >&2
    tmpbin=$(mktemp /tmp/disasm-XXXXXX.bin)
    trap "rm -f '$tmpbin'" EXIT
    eval "$(micromamba shell hook -s bash 2>/dev/null)" 2>/dev/null
    micromamba activate ~/micromamba-base 2>/dev/null
    python3 -c "
import sys
from minidump.minidumpfile import MinidumpFile
mf = MinidumpFile.parse(sys.argv[1])
r = mf.get_reader()
d = r.read(int(sys.argv[2]), int(sys.argv[3]))
open(sys.argv[4], 'wb').write(d)
print(f'Extracted {len(d)} bytes from VA 0x{int(sys.argv[2]):x}')
" "$binary" "$start_dec" "$nbytes" "$tmpbin" >&2
    disasm=$(objdump -D -b binary -m i386 -M intel \
        --adjust-vma="$start" "$tmpbin" 2>/dev/null \
        | grep -E '^\s+[0-9a-f]+:' | head -200)
    source_note="NOTE: This disassembly was extracted from a Windows minidump (crash dump).
It shows the actual in-memory code at runtime, which may differ from the
static PE due to UPX unpacking, relocations, or self-modifying code.
"
else
    if [ -n "$end" ]; then
        disasm=$(set +o pipefail; objdump -d -M intel "$binary" 2>/dev/null \
            | awk "/^ *${start_hex}:/{found=1} found{print} /^ *${end#0x}:/{exit}")
    else
        disasm=$(set +o pipefail; objdump -d -M intel "$binary" 2>/dev/null \
            | awk "/^ *${start_hex}:/{found=1} found{if(++n>200)exit; print}")
    fi
    source_note=""
fi

if [ -z "$disasm" ]; then
    echo "Error: No instructions found at 0x${start_hex}" >&2
    exit 1
fi

# Build context
context=""
if [ -n "$context_path" ]; then
    scriptdir="$(dirname "$0")"
    context=$(echo "$disasm" | "$scriptdir/extract-context.sh" "$context_path" "$start_hex")
fi

# Build prompt
prompt="You are analyzing x86-32 malware disassembly (Intel syntax, from objdump).
${source_note}
Your task: identify the best addresses for GDB breakpoints and watchpoints.

For each interesting address, output a table row with:
- Address (hex)
- Type: hbreak (code) or watch (data write) or rwatch (data read)
- What happens there (1 line)
- Why it's useful for debugging

Also identify:
- Global data addresses referenced (mov to/from absolute addresses)
- API calls (call to trampolines/IAT)
- Loops and their bounds
- Crypto operations (xor, rol, ror, shift patterns)

Output format:
1. A markdown table of recommended breakpoints/watchpoints
2. A short summary of what the code does
3. Any data addresses worth monitoring with watchpoints"

if [ -n "$context" ]; then
    prompt="${prompt}

ADDITIONAL CONTEXT (prior analysis):
${context}"
fi

# Output file: next to the binary, named by address range
bindir=$(dirname "$binary")
binbase=$(basename "$binary" | sed 's/\.[^.]*$//')
outfile="${bindir}/${binbase}-disasm-${start_hex}${end:+-${end#0x}}.md"

unset CLAUDECODE

# Save prompt to temp file (avoids shell arg length issues)
promptfile=$(mktemp /tmp/disasm-prompt-XXXXXX.txt)
trap "rm -f '$promptfile'" EXIT
printf '%s\n\n--- DISASSEMBLY ---\n%s' "$prompt" "$disasm" > "$promptfile"
echo "    Prompt size: $(wc -c < "$promptfile") bytes" >&2
echo "    Output: $outfile" >&2
echo "    Running claude..." >&2

claude -p "$(cat "$promptfile")" > "$outfile" 2>&1
cat "$outfile"
echo "" >&2
echo "Saved to: $outfile" >&2
