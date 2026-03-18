#!/usr/bin/env python3
"""Export decompiled functions and call graph from a PE binary using Ghidra + PyGhidra.

Usage: python3 export.py <binary> <output_dir>

Produces:
  <output_dir>/functions.json  - {addr: {name, address, code, size}}
  <output_dir>/callgraph.json  - {addr: [callee_addr, ...]}
"""

import json
import os
import sys

GHIDRA_INSTALL = "/opt/ghidra"


def export(binary_path, outdir):
    """Run Ghidra headless analysis and export functions + call graph."""
    import pyghidra

    os.makedirs(outdir, exist_ok=True)

    pyghidra.start(install_dir=GHIDRA_INSTALL)

    from ghidra.app.decompiler import DecompInterface
    from ghidra.util.task import ConsoleTaskMonitor

    monitor = ConsoleTaskMonitor()

    print(f"=== Analyzing {binary_path} ===")

    with pyghidra.open_program(binary_path, analyze=True) as flat_api:
        program = flat_api.getCurrentProgram()

        decompiler = DecompInterface()
        decompiler.openProgram(program)

        fm = program.getFunctionManager()

        functions = {}
        call_graph = {}
        skipped = 0

        for func in fm.getFunctions(True):
            addr = str(func.getEntryPoint())
            name = func.getName()

            if func.isExternal() or func.isThunk():
                skipped += 1
                continue

            result = decompiler.decompileFunction(func, 60, monitor)
            code = ""
            if result and result.decompileCompleted():
                decomp = result.getDecompiledFunction()
                if decomp:
                    code = decomp.getC()

            if not code:
                code = "// decompilation failed"

            size = func.getBody().getNumAddresses()

            # Detect trivial functions (trampolines, single indirect calls)
            trivial = int(size) <= 8 or (
                code.count('\n') <= 6 and
                ('(*)' in code or 'pcRam' in code) and
                code.count(';') <= 2
            )

            functions[addr] = {
                "name": name,
                "address": addr,
                "code": code,
                "size": int(size),
                "trivial": trivial
            }

            callees = []
            for callee in func.getCalledFunctions(monitor):
                callees.append(str(callee.getEntryPoint()))
            call_graph[addr] = callees

        decompiler.dispose()

    print(f"Exported {len(functions)} functions (skipped {skipped} external/thunk)")

    functions_path = os.path.join(outdir, "functions.json")
    callgraph_path = os.path.join(outdir, "callgraph.json")

    with open(functions_path, "w") as f:
        json.dump(functions, f, indent=2)
    print(f"Wrote: {functions_path}")

    with open(callgraph_path, "w") as f:
        json.dump(call_graph, f, indent=2)
    print(f"Wrote: {callgraph_path}")

    print("=== Done ===")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <binary> <output_dir>", file=sys.stderr)
        sys.exit(1)
    export(sys.argv[1], sys.argv[2])
