#!/usr/bin/env python3
"""Topological sort of call graph with SCC handling.

Reads functions.json and callgraph.json, produces sorted_functions.json.
Functions are sorted leaves-first (reverse topological order).
Mutually recursive functions (SCCs) are grouped together.

Usage: python3 topo-sort.py <workdir>
"""

import json
import sys
from pathlib import Path

try:
    import networkx as nx
except ImportError:
    print("ERROR: networkx not installed. Run: just setup", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <workdir>", file=sys.stderr)
        sys.exit(1)

    workdir = Path(sys.argv[1])
    functions_path = workdir / "functions.json"
    callgraph_path = workdir / "callgraph.json"

    with open(functions_path) as f:
        functions = json.load(f)
    with open(callgraph_path) as f:
        call_graph = json.load(f)

    # Build directed graph (caller -> callee)
    G = nx.DiGraph()
    for addr in functions:
        G.add_node(addr)
    for caller, callees in call_graph.items():
        for callee in callees:
            if callee in functions:  # skip external functions
                G.add_edge(caller, callee)

    # Find strongly connected components (cycles)
    sccs = list(nx.strongly_connected_components(G))
    scc_map = {}  # node -> scc_id
    scc_groups = {}  # scc_id -> list of addresses
    for i, scc in enumerate(sccs):
        scc_groups[i] = sorted(scc)
        for node in scc:
            scc_map[node] = i

    # Build condensation DAG (each SCC = one node)
    C = nx.DiGraph()
    for i in scc_groups:
        C.add_node(i)
    for caller, callees in call_graph.items():
        if caller not in scc_map:
            continue
        caller_scc = scc_map[caller]
        for callee in callees:
            if callee in scc_map:
                callee_scc = scc_map[callee]
                if caller_scc != callee_scc:
                    C.add_edge(caller_scc, callee_scc)

    # Topological sort of condensation: leaves first
    topo_order = list(reversed(list(nx.topological_sort(C))))

    # Expand back to function groups
    sorted_functions = []
    for scc_id in topo_order:
        group = scc_groups[scc_id]
        sorted_functions.append(group)

    # Compute waves (groups of independent SCCs that can run in parallel)
    # A wave = all SCCs whose dependencies are in earlier waves
    scc_depth = {}
    for scc_id in topo_order:
        max_dep = -1
        for pred in C.predecessors(scc_id):
            # predecessors in condensation = SCCs that this SCC calls
            # Wait — edges are caller->callee, so we need successors
            pass
        # Recompute: in our graph, edge = caller->callee
        # For bottom-up, a node's depth = max(depth of callees) + 1
        # Leaves (no callees) have depth 0
        max_dep = -1
        for succ in C.successors(scc_id):
            if succ in scc_depth:
                max_dep = max(max_dep, scc_depth[succ])
        scc_depth[scc_id] = max_dep + 1

    # Group by wave
    max_wave = max(scc_depth.values()) if scc_depth else 0
    waves = [[] for _ in range(max_wave + 1)]
    for scc_id in topo_order:
        wave = scc_depth[scc_id]
        waves[wave].append(scc_groups[scc_id])

    # Stats
    leaf_count = sum(1 for g in sorted_functions if len(g) == 1
                     and not list(C.successors(scc_map[g[0]])))
    multi_sccs = [g for g in sorted_functions if len(g) > 1]

    stats = {
        "total_functions": len(functions),
        "total_groups": len(sorted_functions),
        "leaf_count": leaf_count,
        "scc_count": len(multi_sccs),
        "max_scc_size": max((len(g) for g in multi_sccs), default=0),
        "wave_count": len(waves),
        "wave_sizes": [sum(len(g) for g in w) for w in waves],
    }

    # Write outputs
    out_sorted = workdir / "sorted_functions.json"
    out_waves = workdir / "waves.json"
    out_stats = workdir / "stats.json"

    with open(out_sorted, "w") as f:
        json.dump(sorted_functions, f, indent=2)
    with open(out_waves, "w") as f:
        json.dump(waves, f, indent=2)
    with open(out_stats, "w") as f:
        json.dump(stats, f, indent=2)

    print(f"Functions: {stats['total_functions']}, "
          f"Groups: {stats['total_groups']}, "
          f"Leaves: {stats['leaf_count']}, "
          f"SCCs: {stats['scc_count']} (max size {stats['max_scc_size']}), "
          f"Waves: {stats['wave_count']}")
    print(f"Wave sizes: {stats['wave_sizes']}")
    print(f"Wrote: {out_sorted}, {out_waves}, {out_stats}")


if __name__ == "__main__":
    main()
