#!/usr/bin/env bash
# Bottom-up LLM annotation of a decompiled binary.
# Uses Ghidra for decompilation, call graph for topological ordering,
# and Claude for annotation with callee context injection.
#
# Usage: ./scripts/annotate-deep.sh <binary.exe> [output.c] [--context <file>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="${SCRIPT_DIR}/annotate-deep-prompt.txt"
PARALLEL=10

# ── Parse arguments ──────────────────────────────────────────────────

BINARY=""
OUTPUT=""
CONTEXT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --context) CONTEXT_FILE="$2"; shift 2 ;;
        *) if [ -z "$BINARY" ]; then BINARY="$1"
           elif [ -z "$OUTPUT" ]; then OUTPUT="$1"
           fi; shift ;;
    esac
done

if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
    echo "Usage: $0 <binary.exe> [output.c] [--context <file>]" >&2
    exit 1
fi

BINARY="$(cd "$(dirname "$BINARY")" && pwd)/$(basename "$BINARY")"
basename_no_ext=$(basename "$BINARY" | sed 's/\.[^.]*$//')
WORKDIR="$(dirname "$BINARY")/${basename_no_ext}-ghidra"
[ -z "$OUTPUT" ] && OUTPUT="$(dirname "$BINARY")/${basename_no_ext}-annotated-deep.c"

CONTEXT=""
if [ -n "$CONTEXT_FILE" ] && [ -f "$CONTEXT_FILE" ]; then
    CONTEXT=$(cat "$CONTEXT_FILE")
fi

mkdir -p "$WORKDIR"
echo "Binary:  $BINARY"
echo "Workdir: $WORKDIR"
echo "Output:  $OUTPUT"
[ -n "$CONTEXT_FILE" ] && echo "Context: $CONTEXT_FILE"
echo ""

# ── Stage 1: Ghidra decompile ───────────────────────────────────────

if [ -f "$WORKDIR/functions.json" ] && [ -f "$WORKDIR/callgraph.json" ]; then
    echo "=== Stage 1: Ghidra decompilation (cached) ==="
else
    echo "=== Stage 1: Ghidra headless decompilation ==="
    eval "$(micromamba shell hook -s bash)"
    micromamba activate ~/micromamba-base
    python3 "${SCRIPT_DIR}/ghidra/export.py" "$BINARY" "$WORKDIR"

    if [ ! -f "$WORKDIR/functions.json" ]; then
        echo "ERROR: Ghidra export failed" >&2
        exit 1
    fi
fi

func_count=$(python3 -c "import json; print(len(json.load(open('$WORKDIR/functions.json'))))")
echo "  Functions: $func_count"

# ── Stage 2: Topological sort ───────────────────────────────────────

if [ -f "$WORKDIR/waves.json" ]; then
    echo "=== Stage 2: Topological sort (cached) ==="
else
    echo "=== Stage 2: Topological sort ==="
    eval "$(micromamba shell hook -s bash)"
    micromamba activate ~/micromamba-base
    python3 "${SCRIPT_DIR}/analysis/topo-sort.py" "$WORKDIR"
fi

# ── Stage 3: Bottom-up annotation ───────────────────────────────────

echo "=== Stage 3: Bottom-up annotation ==="

# Initialize summaries file if not present
SUMMARIES="$WORKDIR/summaries.json"
[ -f "$SUMMARIES" ] || echo '{}' > "$SUMMARIES"
mkdir -p "$WORKDIR/annotated"

PROMPT_TPL=$(cat "$PROMPT_TEMPLATE")

annotate_one() {
    local workdir="$1"
    local addr="$2"
    local prompt_tpl="$3"
    local context="$4"
    local summaries_file="$workdir/summaries.json"
    local outfile="$workdir/annotated/${addr}.c"

    # Skip if already done
    if [ -f "$outfile" ]; then
        return 0
    fi

    # Extract function code and check if trivial
    local code
    local is_trivial
    read -r is_trivial < <(python3 -c "
import json, sys
with open('$workdir/functions.json') as f:
    funcs = json.load(f)
addr = '$addr'
if addr in funcs:
    print('1' if funcs[addr].get('trivial', False) else '0')
else:
    sys.exit(1)
")
    code=$(python3 -c "
import json, sys
with open('$workdir/functions.json') as f:
    funcs = json.load(f)
addr = '$addr'
if addr in funcs:
    print(funcs[addr]['code'])
else:
    sys.exit(1)
")

    # Trivial functions: skip LLM, generate a simple annotation
    if [ "$is_trivial" = "1" ]; then
        {
            echo "// SUGGESTED NAME: trampoline_${addr}"
            echo "// Trivial indirect call trampoline — calls through function pointer."
            echo "$code"
            echo "// SUMMARY: Trampoline that calls a dynamically resolved function pointer."
        } > "$outfile"
        # Update summaries
        python3 -c "
import json, fcntl
with open('$summaries_file', 'r+') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    sums = json.load(f)
    sums['$addr'] = 'Trampoline that calls a dynamically resolved function pointer.'
    f.seek(0); f.truncate()
    json.dump(sums, f, indent=2)
    fcntl.flock(f, fcntl.LOCK_UN)
"
        return 0
    fi

    # Build callee summaries
    local callee_context
    callee_context=$(python3 -c "
import json, fcntl
with open('$workdir/callgraph.json') as f:
    cg = json.load(f)
with open('$summaries_file') as f:
    fcntl.flock(f, fcntl.LOCK_SH)
    sums = json.load(f)
    fcntl.flock(f, fcntl.LOCK_UN)
with open('$workdir/functions.json') as f:
    funcs = json.load(f)
addr = '$addr'
callees = cg.get(addr, [])
lines = []
for c in callees:
    name = funcs.get(c, {}).get('name', c)
    summary = sums.get(c, '')
    if summary:
        lines.append(f'- {name} ({c}): {summary}')
    elif c in funcs:
        lines.append(f'- {name} ({c}): (not yet analyzed)')
    else:
        lines.append(f'- {name} ({c}): (external/library function)')
if lines:
    print('\n'.join(lines))
else:
    print('(none — this is a leaf function)')
")

    # Build prompt
    local prompt
    prompt="${prompt_tpl//\{CALLEE_SUMMARIES\}/$callee_context}"
    if [ -n "$context" ]; then
        prompt="${prompt//\{CONTEXT\}/$context}"
    else
        prompt="${prompt//\{CONTEXT\}/(no additional context provided)}"
    fi

    # Call Claude
    echo "$code" | CLAUDECODE= claude -p "$prompt" --allowedTools "" 2>/dev/null \
        | grep -v '^```' > "$outfile"

    # Extract SUMMARY line
    local summary
    summary=$(grep '^// SUMMARY:' "$outfile" | head -1 | sed 's|^// SUMMARY: *||')
    if [ -n "$summary" ]; then
        # Atomically update summaries.json
        python3 -c "
import json, fcntl
addr = '$addr'
summary = '''$summary'''
with open('$summaries_file', 'r+') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    sums = json.load(f)
    sums[addr] = summary
    f.seek(0)
    f.truncate()
    json.dump(sums, f, indent=2)
    fcntl.flock(f, fcntl.LOCK_UN)
"
    fi
}
export -f annotate_one

# Process wave by wave
eval "$(micromamba shell hook -s bash)"
micromamba activate ~/micromamba-base

wave_count=$(python3 -c "import json; print(len(json.load(open('$WORKDIR/waves.json'))))")

for ((w=0; w<wave_count; w++)); do
    # Get addresses in this wave
    addrs=$(python3 -c "
import json
with open('$WORKDIR/waves.json') as f:
    waves = json.load(f)
wave = waves[$w]
for group in wave:
    # For SCC groups, join with comma
    print(','.join(group))
")

    # Separate trivial vs non-trivial, count pending
    trivial_addrs=()
    nontrivial_addrs=()
    total=0
    pending=0
    for group in $addrs; do
        for addr in ${group//,/ }; do
            total=$((total + 1))
            [ -f "$WORKDIR/annotated/${addr}.c" ] && continue
            pending=$((pending + 1))
            is_triv=$(python3 -c "
import json
with open('$WORKDIR/functions.json') as f:
    funcs = json.load(f)
print('1' if funcs.get('$addr', {}).get('trivial', False) else '0')
")
            if [ "$is_triv" = "1" ]; then
                trivial_addrs+=("$addr")
            else
                nontrivial_addrs+=("$addr")
            fi
        done
    done

    if [ "$pending" -eq 0 ]; then
        echo "  Wave $((w+1))/$wave_count: $total functions (all cached)"
        continue
    fi
    echo "  Wave $((w+1))/$wave_count: $total functions ($pending pending, ${#trivial_addrs[@]} trivial, ${#nontrivial_addrs[@]} LLM)"

    # Process trivial functions first (synchronous, instant)
    for addr in "${trivial_addrs[@]}"; do
        annotate_one "$WORKDIR" "$addr" "$PROMPT_TPL" "$CONTEXT"
    done

    # Process non-trivial functions in parallel batches
    pids=()
    running=0
    for addr in "${nontrivial_addrs[@]}"; do
        annotate_one "$WORKDIR" "$addr" "$PROMPT_TPL" "$CONTEXT" &
        pids+=($!)
        running=$((running + 1))

        if [ "$running" -ge "$PARALLEL" ]; then
            for pid in "${pids[@]}"; do wait "$pid"; done
            pids=()
            running=0
        fi
    done
    # Wait for remaining
    for pid in "${pids[@]}"; do wait "$pid"; done

    # Report wave results
    done_count=$(ls "$WORKDIR"/annotated/*.c 2>/dev/null | wc -l)
    echo "    Wave $((w+1)) complete (total annotated: $done_count)"
done

# ── Stage 4: Summary pass ───────────────────────────────────────────

echo "=== Stage 4: Generating summary ==="

SUMMARY_INPUT=$(python3 -c "
import json
with open('$WORKDIR/functions.json') as f:
    funcs = json.load(f)
with open('$SUMMARIES') as f:
    sums = json.load(f)
with open('$WORKDIR/sorted_functions.json') as f:
    sorted_funcs = json.load(f)

lines = []
for group in sorted_funcs:
    for addr in group:
        name = funcs.get(addr, {}).get('name', addr)
        summary = sums.get(addr, '(no summary)')
        suggested = ''
        afile = '$WORKDIR/annotated/' + addr + '.c'
        try:
            with open(afile) as af:
                for line in af:
                    if 'SUGGESTED NAME' in line:
                        suggested = line.strip().split('SUGGESTED NAME:')[-1].strip()
                        break
        except FileNotFoundError:
            pass
        sname = suggested if suggested else name
        lines.append(f'{addr}  {sname:40s}  {summary}')

print('\n'.join(lines))
")

SUMMARY_PROMPT=$(cat <<'SPROMPT'
You are a malware reverse engineer. Below is a function summary table from a decompiled Windows PE binary.

Create a comprehensive analysis header as C block comments:
1. A table mapping each function address to its suggested name and role
2. Overall program flow (initialization → persistence → payload → cleanup)
3. Key findings: encryption, persistence, evasion, network, etc.

CRITICAL OUTPUT RULES:
- Output ONLY C block comments (/* */ or //). Nothing else.
- Do NOT wrap output in markdown code fences (no ``` ever).
- Do NOT include any conversational text outside of C comments.
SPROMPT
)

echo "$SUMMARY_INPUT" | CLAUDECODE= claude -p "$SUMMARY_PROMPT" --allowedTools "" 2>/dev/null \
    | grep -v '^```' > "$WORKDIR/summary-header.c"

# ── Stage 5: Assemble ───────────────────────────────────────────────

echo "=== Stage 5: Assembling final output ==="

{
    cat "$WORKDIR/summary-header.c"
    echo ""

    # Output functions in topological order (callers after callees)
    python3 -c "
import json
with open('$WORKDIR/sorted_functions.json') as f:
    sorted_funcs = json.load(f)
for group in sorted_funcs:
    for addr in group:
        print(addr)
" | while read -r addr; do
        afile="$WORKDIR/annotated/${addr}.c"
        if [ -f "$afile" ]; then
            echo ""
            cat "$afile"
        fi
    done
} > "$OUTPUT"

lines=$(wc -l < "$OUTPUT")
echo ""
echo "=== Done: $OUTPUT ($lines lines) ==="
