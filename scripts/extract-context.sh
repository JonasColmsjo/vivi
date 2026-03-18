#!/usr/bin/env bash
# Extract context from an annotated C file or Ghidra directory for disasm analysis.
# Usage: extract-context.sh <context-path> <start-hex> <disasm-text>
#   context-path: annotated .c file or Ghidra export directory
#   start-hex:    start address without 0x prefix (e.g. 4021d1)
#   disasm-text:  disassembly text (read from stdin)
set -euo pipefail

context_path="$1"
start_hex="$2"
disasm=$(cat)  # read disasm from stdin

context=""

if [ -f "$context_path" ]; then
    # Annotated C file: extract header + target function + callee summaries
    echo "    Loading annotated pseudocode: $context_path" >&2

    # Header: everything before first function definition (function map, program flow, globals)
    header=$(awk '/^void FUN_|^uint FUN_|^int FUN_|^void entry/{exit} {print}' "$context_path")
    context="=== ANNOTATED PSEUDOCODE — HEADER (function map, program flow, globals) ===
$header"

    # Extract target function (match FUN_00<addr> or entry)
    func_pattern="FUN_00${start_hex}"
    func_block=$(awk -v pat="$func_pattern" '
        /^\/\*/{block=""; in_block=1}
        in_block{block=block $0 "\n"}
        /^\/\/ SUMMARY:/{
            if (block ~ pat || block ~ "void entry[(]void[)]") {print block; found=1}
            in_block=0; block=""
        }
        END{if(!found) print ""}
    ' "$context_path")

    if [ -n "$func_block" ]; then
        context="$context

=== DECOMPILATION OF TARGET FUNCTION ===
$func_block"
    fi

    # Extract SUGGESTED NAME + SUMMARY for each called function
    called_addrs=$(echo "$disasm" | grep -oP 'call\s+0x\K[0-9a-f]+' | sort -u)
    summaries=""
    for addr in $called_addrs; do
        summary=$(awk -v addr="00${addr}" '
            /SUGGESTED NAME:/{name=$0}
            /^void FUN_|^uint FUN_|^int FUN_/{
                if (index($0, addr)) { funcline=$0 }
            }
            /\/\/ SUMMARY:/{
                if (funcline && index(funcline, addr)) {
                    gsub(/.*SUGGESTED NAME: /, "", name)
                    gsub(/\/\/ SUMMARY: /, "", $0)
                    print name ": " $0
                    exit
                }
                funcline=""
                name=""
            }
        ' "$context_path")
        if [ -n "$summary" ]; then
            summaries="${summaries}
  0x${addr}: ${summary}"
        fi
    done
    if [ -n "$summaries" ]; then
        context="$context

=== CALLED FUNCTIONS (summaries) ===$summaries"
    fi

elif [ -d "$context_path" ]; then
    # Ghidra export directory
    echo "    Loading Ghidra context: $context_path" >&2
    [ -f "$context_path/summaries.json" ] && \
        context="=== FUNCTION SUMMARIES ===
$(cat "$context_path/summaries.json")"
    [ -f "$context_path/callgraph.json" ] && \
        context="$context

=== CALL GRAPH ===
$(cat "$context_path/callgraph.json")"
    addr_file="$context_path/annotated/$(printf '%08x' $((0x${start_hex}))).c"
    if [ -f "$addr_file" ]; then
        context="$context

=== GHIDRA DECOMPILATION (0x${start_hex}) ===
$(cat "$addr_file")"
    fi
else
    echo "    Warning: context path not found: $context_path" >&2
fi

echo "$context"
