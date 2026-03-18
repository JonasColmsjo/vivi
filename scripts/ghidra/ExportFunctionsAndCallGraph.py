# Ghidra headless script: export decompiled functions and call graph to JSON.
# Usage: analyzeHeadless /tmp/GhidraProject MyProject -import binary.exe \
#        -postScript ExportFunctionsAndCallGraph.py /output/dir
#
# Produces:
#   /output/dir/functions.json  - {addr: {name, address, code, size}}
#   /output/dir/callgraph.json  - {addr: [callee_addr, ...]}

import json
import os
from ghidra.app.decompiler import DecompInterface

# Get output directory from script arguments
args = getScriptArgs()
if len(args) < 1:
    outdir = "/tmp"
    println("WARNING: No output directory specified, using /tmp")
else:
    outdir = args[0]

if not os.path.isdir(outdir):
    os.makedirs(outdir)

# Initialize decompiler
decompiler = DecompInterface()
decompiler.openProgram(currentProgram)

fm = currentProgram.getFunctionManager()
listing = currentProgram.getListing()

functions = {}
call_graph = {}
skipped = 0

println("=== Exporting functions and call graph ===")

for func in fm.getFunctions(True):
    addr = str(func.getEntryPoint())
    name = func.getName()

    # Skip external/thunk/library functions
    if func.isExternal() or func.isThunk():
        skipped += 1
        continue

    # Decompile
    result = decompiler.decompileFunction(func, 60, monitor)
    code = ""
    if result and result.decompileCompleted():
        decomp = result.getDecompiledFunction()
        if decomp:
            code = decomp.getC()

    if not code:
        # Fallback: still record the function but with empty code
        code = "// decompilation failed"

    size = func.getBody().getNumAddresses()

    functions[addr] = {
        "name": name,
        "address": addr,
        "code": code,
        "size": int(size)
    }

    # Build call graph
    callees = []
    called = func.getCalledFunctions(monitor)
    for callee in called:
        callee_addr = str(callee.getEntryPoint())
        callees.append(callee_addr)
    call_graph[addr] = callees

println("Exported %d functions (skipped %d external/thunk)" % (len(functions), skipped))

# Write outputs
functions_path = os.path.join(outdir, "functions.json")
callgraph_path = os.path.join(outdir, "callgraph.json")

with open(functions_path, "w") as f:
    json.dump(functions, f, indent=2)
println("Wrote: " + functions_path)

with open(callgraph_path, "w") as f:
    json.dump(call_graph, f, indent=2)
println("Wrote: " + callgraph_path)

println("=== Done ===")
