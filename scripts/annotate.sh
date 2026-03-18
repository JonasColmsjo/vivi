#!/usr/bin/env bash
# Split decompiled pseudocode into per-function chunks, annotate each with
# Claude, then reassemble into a single annotated file.
#
# Usage: ./scripts/annotate.sh <pseudocode.txt> <output.c>

set -euo pipefail

INPUT="$1"
OUTPUT="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_FILE="${SCRIPT_DIR}/annotate-prompt.txt"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if [ ! -f "$INPUT" ]; then
    echo "Input file not found: $INPUT" >&2
    exit 1
fi

# ── Split into header + per-function chunks ──────────────────────────

echo "=== Splitting into functions ==="

# Header = everything before first "// ────" separator
FIRST_SEP=$(grep -n '^// ────' "$INPUT" | head -1 | cut -d: -f1)
if [ -z "$FIRST_SEP" ]; then
    echo "No function separators found in $INPUT" >&2
    exit 1
fi

head -n $((FIRST_SEP - 1)) "$INPUT" > "$TMPDIR/000-header.txt"

# Split on the separator pattern. Each function starts with two separator
# lines (// ────) followed by // funcname (addr) then another // ────.
# We split on the blank line before each separator pair.
tail -n +"$FIRST_SEP" "$INPUT" | awk -v tmpdir="$TMPDIR" '
BEGIN { chunk = 0; file = "" }
/^\/\/ ────/ {
    if (prev_is_blank || NR <= 2) {
        chunk++
        file = sprintf("%s/%03d-func.txt", tmpdir, chunk)
    }
}
{
    if (file != "") print >> file
    prev_is_blank = ($0 == "")
}
'

NFUNCS=$(ls "$TMPDIR"/*-func.txt 2>/dev/null | wc -l)
echo "Found $NFUNCS functions"

# ── Build per-function prompt ────────────────────────────────────────

FUNC_PROMPT=$(cat <<'FPROMPT'
You are a malware reverse engineer analyzing a SINGLE decompiled C function from Xorist ransomware.

Context:
- Xorist ransomware, TEA encryption (delta 0x9E3779B9), big-endian (bswap)
- TEA key at globals 0x406585-0x406591 (4 x 32-bit), round count at 0x4065a5
- Files encrypted from byte 71 onward, extension .EnCiPhErEd
- Windows API: CreateFile, ReadFile, WriteFile, FindFirstFile, FindNextFile,
  RegSetValueEx, MessageBox, CryptCreateHash, CryptHashData

Your task:
1. Keep ALL code lines exactly as-is — do not modify any code
2. Add a block comment before the function with:
   - SUGGESTED NAME: <meaningful_name>
   - What the function does
   - Parameters and return value
   - Notable constants, algorithms, or API calls
3. Add inline comments on important lines
4. Identify: encryption, key derivation, file enumeration, registry persistence,
   ransom note, anti-analysis

CRITICAL OUTPUT RULES:
- Output ONLY raw C code with comments. Nothing else.
- Do NOT wrap output in markdown code fences (no ``` ever).
- Do NOT include any conversational text, questions, or explanations outside of C comments.
- Start your output with the first line of code or comment. End with the last line of code.
FPROMPT
)

# ── Summary prompt for the header ────────────────────────────────────

SUMMARY_PROMPT=$(cat <<'SPROMPT'
You are a malware reverse engineer. Below is the header section of a decompiled Xorist ransomware binary, followed by all the annotated functions with their SUGGESTED NAME comments.

Your task:
1. Keep the original header (function list, crypto references) exactly as-is
2. Add a SUMMARY SECTION at the very top with:
   - A table mapping each function address to its suggested name and role
   - Overall program flow description
   - Key findings (encryption scheme, persistence, etc.)
CRITICAL OUTPUT RULES:
- Output ONLY raw C code/comments. Nothing else.
- Do NOT wrap output in markdown code fences (no ``` ever).
- Do NOT include any conversational text, questions, or explanations outside of C comments.
- Start your output with the first line of code or comment. End with the last line of code.
SPROMPT
)

# ── Annotate each function (parallel, max PARALLEL at a time) ────────

PARALLEL=10
echo "=== Annotating functions ($PARALLEL parallel) ==="

annotate_func() {
    local chunk="$1"
    local prompt="$2"
    local outchunk="${chunk%.txt}-annotated.txt"
    CLAUDECODE= claude -p "$prompt" --allowedTools "" < "$chunk" 2>/dev/null \
        | grep -v '^```' > "$outchunk"
}
export -f annotate_func

# Build job list
job_chunks=()
for chunk in "$TMPDIR"/*-func.txt; do
    func_label=$(grep '// .*(0x' "$chunk" | head -1 | sed 's|^// *||')
    echo "  queued: $func_label"
    job_chunks+=("$chunk")
done

# Run in batches of PARALLEL
total=${#job_chunks[@]}
for ((i=0; i<total; i+=PARALLEL)); do
    batch=("${job_chunks[@]:i:PARALLEL}")
    echo ""
    echo "--- Batch $((i/PARALLEL + 1)) (functions $((i+1))-$((i+${#batch[@]})) of $total) ---"

    pids=()
    for chunk in "${batch[@]}"; do
        annotate_func "$chunk" "$FUNC_PROMPT" &
        pids+=($!)
    done

    # Wait for all in this batch
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Report results
    for chunk in "${batch[@]}"; do
        outchunk="${chunk%.txt}-annotated.txt"
        func_label=$(grep '// .*(0x' "$chunk" | head -1 | sed 's|^// *||')
        lines=$(wc -l < "$outchunk" 2>/dev/null || echo 0)
        echo "  done: $func_label ($lines lines)"
    done
done

# ── Build summary using header + all annotated functions ─────────────

echo "=== Generating summary ==="

# Collect all SUGGESTED NAME lines for the summary prompt
{
    cat "$TMPDIR/000-header.txt"
    echo ""
    echo "=== Annotated function names ==="
    grep -h 'SUGGESTED NAME' "$TMPDIR"/*-annotated.txt 2>/dev/null || true
} > "$TMPDIR/summary-input.txt"

CLAUDECODE= claude -p "$SUMMARY_PROMPT" --allowedTools "" < "$TMPDIR/summary-input.txt" 2>/dev/null \
    | grep -v '^```' > "$TMPDIR/000-header-annotated.txt"

# ── Reassemble ───────────────────────────────────────────────────────

echo "=== Assembling final output ==="

{
    cat "$TMPDIR/000-header-annotated.txt"
    echo ""
    for chunk in "$TMPDIR"/*-func-annotated.txt; do
        echo ""
        cat "$chunk"
    done
} > "$OUTPUT"

lines=$(wc -l < "$OUTPUT")
echo "=== Done: $OUTPUT ($lines lines) ==="
