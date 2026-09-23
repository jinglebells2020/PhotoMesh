"""A small DC solver (modified nodal analysis) used as the judge of recognition correctness.

Two netlists are "the same circuit" for PhotoMesh when the app would print the same answers, so
instead of graph isomorphism we compare element currents and voltages. Conventions follow
`CircuitModel.swift`: a component's current is positive from node_a to node_b through it.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from .schema import Circuit, Component, Unknown, ValidationError, comparable_value


class SolveError(RuntimeError):
    pass


@dataclass
class Solution:
    node_voltages: dict[str, float]
    currents: dict[str, Optional[float]] = field(default_factory=dict)   # a -> b through the element
    voltages: dict[str, Optional[float]] = field(default_factory=dict)   # V(a) - V(b)
    powers: dict[str, Optional[float]] = field(default_factory=dict)     # absorbed, v * i
    alias: dict[str, str] = field(default_factory=dict)                  # original node -> solved node


def solve(circuit: Circuit) -> Solution:
    """Solves the validated DC equivalent and reads results back onto every original element."""
    cleaned = circuit.validated()
    solved, alias = cleaned.dc_equivalent()
    if not solved.components:
        raise SolveError("nothing left to solve at DC")
    if not any(c.is_source for c in solved.components):
        raise SolveError("no source left at DC")
    if not solved.is_connected():
        raise SolveError("disconnected at DC (an open element splits the circuit)")

    nodes = solved.nodes
    ground = solved.ground_node
    index = {n: i for i, n in enumerate(n for n in nodes if n != ground)}
    vsources = [c for c in solved.components if c.dc_role == "voltage_source"]
    n, m = len(index), len(vsources)
    size = n + m
    A = np.zeros((size, size))
    b = np.zeros(size)

    for c in solved.components:
        ia, ib = index.get(c.node_a), index.get(c.node_b)
        if c.dc_role == "resistor":
            g = 1.0 / float(c.value)  # validated: > 0
            if ia is not None:
                A[ia, ia] += g
            if ib is not None:
                A[ib, ib] += g
            if ia is not None and ib is not None:
                A[ia, ib] -= g
                A[ib, ia] -= g
        elif c.dc_role == "current_source":
            current = float(c.value)
            if ia is not None:
                b[ia] -= current
            if ib is not None:
                b[ib] += current
    for j, c in enumerate(vsources):
        col = n + j
        ia, ib = index.get(c.node_a), index.get(c.node_b)
        if ia is not None:
            A[ia, col] += 1.0
            A[col, ia] += 1.0
        if ib is not None:
            A[ib, col] -= 1.0
            A[col, ib] -= 1.0
        b[col] = float(c.value)

    if size == 0:
        raise SolveError("degenerate circuit")
    try:
        x = np.linalg.solve(A, b)
    except np.linalg.LinAlgError as exc:
        raise SolveError(f"singular system: {exc}") from exc
    if not np.all(np.isfinite(x)) or np.linalg.norm(A @ x - b) > 1e-6 * max(1.0, np.linalg.norm(b)):
        raise SolveError("ill-conditioned system")
    if np.linalg.cond(A) > 1e12:
        raise SolveError("ill-conditioned system")

    v = {ground: 0.0}
    for node, i in index.items():
        v[node] = float(x[i])
    sol = Solution(node_voltages={}, alias=alias)
    for node in cleaned.nodes:
        # A node reached only through opens (capacitors, open switches) floats at DC: undefined.
        sol.node_voltages[node] = v.get(alias[node], math.nan)

    solved_current: dict[str, float] = {}
    for c in solved.components:
        va, vb = v[c.node_a], v[c.node_b]
        if c.dc_role == "resistor":
            solved_current[c.id] = (va - vb) / float(c.value)
        elif c.dc_role == "current_source":
            solved_current[c.id] = float(c.value)
    for j, c in enumerate(vsources):
        solved_current[c.id] = float(x[n + j])

    for c in cleaned.components:
        va, vb = v.get(alias[c.node_a]), v.get(alias[c.node_b])
        sol.voltages[c.id] = (va - vb) if (va is not None and vb is not None) else None
        if c.dc_role == "open":
            sol.currents[c.id] = 0.0
        elif c.dc_role == "short":
            sol.currents[c.id] = None  # filled by KCL below when determinable
        else:
            sol.currents[c.id] = solved_current[c.id]

    _fill_short_currents(cleaned, sol)
    for c in cleaned.components:
        i, u = sol.currents.get(c.id), sol.voltages.get(c.id)
        sol.powers[c.id] = (u * i) if (i is not None and u is not None) else None
    return sol


def _fill_short_currents(circuit: Circuit, sol: Solution) -> None:
    """KCL at a node with exactly one unknown short current gives that current; iterate."""
    progress = True
    while progress:
        progress = False
        for node in circuit.nodes:
            unknown = [c for c in circuit.components_at(node) if sol.currents.get(c.id) is None]
            if len(unknown) != 1:
                continue
            short = unknown[0]
            leaving = 0.0
            for c in circuit.components_at(node):
                if c.id == short.id:
                    continue
                i = sol.currents[c.id]
                assert i is not None
                # current leaves `node` through c when node is c.node_a
                leaving += i if c.node_a == node else -i
            i_short = -leaving  # KCL: sum of currents leaving node == 0
            sol.currents[short.id] = i_short if short.node_a == node else -i_short
            progress = True


def evaluate_unknown(circuit: Circuit, sol: Solution, unknown: Unknown) -> Optional[float]:
    """The number the app would print for one unknown (None if it is not determinable)."""
    if unknown.element is not None:
        comp = circuit.component(unknown.element)
        if comp is None:
            return None
        if unknown.kind == "current":
            i = sol.currents.get(comp.id)
            return abs(i) if i is not None else None
        if unknown.kind == "voltage":
            u = sol.voltages.get(comp.id)
            return abs(u) if u is not None else None
        if unknown.kind == "power":
            p = sol.powers.get(comp.id)
            return abs(p) if p is not None else None
        if unknown.kind == "resistance":
            return comp.value
        return None
    if unknown.node is not None:
        value = sol.node_voltages.get(unknown.node)
        return None if value is None or math.isnan(value) else value
    if unknown.between and len(unknown.between) == 2:
        a, b = unknown.between
        if a in sol.node_voltages and b in sol.node_voltages:
            value = sol.node_voltages[a] - sol.node_voltages[b]
            return None if math.isnan(value) else value
    return None


def _same(x: Optional[float], y: Optional[float], rel: float, abs_tol: float) -> bool:
    if x is None or y is None:
        return x is None and y is None
    return abs(x - y) <= max(abs_tol, rel * max(abs(x), abs(y)))


def same_solution(a: Circuit, b: Circuit, rel: float = 1e-3, abs_tol: float = 1e-9) -> bool:
    """True when both circuits solve and describe the same physics: the same node potentials and the same
    current through every element, under some correspondence of node names.

    Element ids must match (the app names elements by their labels, so a wrong id is a wrong answer for
    the user), node names need not. An element without polarity (resistor, capacitor, inductor, lamp,
    switch) may be listed with its terminals the other way round; a source may not, because its terminal
    order is its polarity.
    """
    try:
        sa, sb = solve(a), solve(b)
    except (ValidationError, SolveError):
        return False
    ids_a = {c.id: c for c in a.components}
    ids_b = {c.id: c for c in b.components}
    if ids_a.keys() != ids_b.keys():
        return False
    for cid in ids_a:
        if ids_a[cid].kind != ids_b[cid].kind:
            return False
        if not _same(comparable_value(ids_a[cid]), comparable_value(ids_b[cid]), 1e-6, 0.0):
            return False
    order = sorted(ids_a, key=lambda cid: (not ids_a[cid].is_source, cid))   # sources first: they fix the mapping
    return _match_nodes(order, 0, ids_a, ids_b, sa, sb, {a.ground_node: b.ground_node}, rel, abs_tol)


def _match_nodes(order: list[str], k: int, ids_a: dict, ids_b: dict, sa: Solution, sb: Solution,
                 mapping: dict[str, str], rel: float, abs_tol: float) -> bool:
    """Backtracking over the (at most two) ways each element's terminals can correspond."""
    if k == len(order):
        return True
    cid = order[k]
    ca, cb = ids_a[cid], ids_b[cid]
    ia, ib = sa.currents.get(cid), sb.currents.get(cid)
    ua, ub = sa.voltages.get(cid), sb.voltages.get(cid)
    options = [((ca.node_a, cb.node_a), (ca.node_b, cb.node_b), 1.0)]
    if not ca.is_source:
        options.append(((ca.node_a, cb.node_b), (ca.node_b, cb.node_a), -1.0))
    for first, second, sign in options:
        if not (_same(ia, _scaled(ib, sign), rel, abs_tol) and _same(ua, _scaled(ub, sign), rel, abs_tol)):
            continue
        new = dict(mapping)
        consistent = True
        for n, n2 in (first, second):
            if new.get(n, n2) != n2:
                consistent = False
                break
            new[n] = n2
        if not consistent or len(set(new.values())) != len(new):
            continue
        if not all(_same_or_nan(sa.node_voltages.get(n), sb.node_voltages.get(n2), rel, abs_tol) for n, n2 in new.items()):
            continue
        if _match_nodes(order, k + 1, ids_a, ids_b, sa, sb, new, rel, abs_tol):
            return True
    return False


def _scaled(x: Optional[float], sign: float) -> Optional[float]:
    return None if x is None else sign * x


def _same_or_nan(x: Optional[float], y: Optional[float], rel: float, abs_tol: float) -> bool:
    if x is not None and y is not None and math.isnan(x) and math.isnan(y):
        return True
    return _same(x, y, rel, abs_tol)


def solvable(circuit: Circuit) -> bool:
    try:
        solve(circuit)
        return True
    except (ValidationError, SolveError):
        return False
