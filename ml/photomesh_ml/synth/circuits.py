"""Random textbook DC circuits on a lattice, with their exact netlist, meshes and question.

The drawing is a grid of "windows" (like a two-loop textbook problem): wires run along lattice
edges and every edge can carry one element. The electrical nodes follow from the plain-wire
edges, so the JSON label is exact by construction, and the solver must accept the result before
the circuit is used.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from typing import Optional

from ..schema import Circuit, Component, Unknown, ValidationError, node_letter
from ..solver import SolveError, solve

LPoint = tuple[float, float]  # (row, col); jumper endpoints sit at half columns

KIND_WEIGHTS = {
    "resistor": 0.56, "voltage_source": 0.13, "current_source": 0.05, "battery": 0.06,
    "capacitor": 0.05, "inductor": 0.05, "lamp": 0.05, "switch_open": 0.02, "switch_closed": 0.03,
}
ID_PREFIX = {"resistor": "R", "voltage_source": "V", "current_source": "I", "battery": "E", "capacitor": "C",
             "inductor": "L", "lamp": "Lp", "switch_open": "S", "switch_closed": "S", "other": "D"}
# Symbols the app cannot solve; they train the tracer's "other" class and the JSON's "unsupported" list.
OTHER_SUBTYPES = {"diode": "D", "led": "D", "zener": "D", "ac_source": "V"}
# What a reader calls an element that carries no label (RecognitionPrompt rule 4; batteries count as V).
FALLBACK_PREFIX = {"resistor": "R", "voltage_source": "V", "current_source": "I", "battery": "V", "capacitor": "C",
                   "inductor": "L", "lamp": "Lp", "switch_open": "S", "switch_closed": "S", "other": "D"}

R_NICE = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 24, 25, 30, 40, 47, 50, 60, 75, 80, 100, 120, 150, 180, 200, 220, 250,
          270, 300, 330, 390, 400, 470, 500, 560, 600, 680, 750, 820, 1000, 1200, 1500, 1800, 2000, 2200, 2700, 3300,
          3900, 4700, 5000, 5600, 6800, 8200, 10000, 12000, 15000, 22000, 33000, 47000, 100000, 220000, 1000000]
V_NICE = [1.5, 2, 3, 4, 4.5, 5, 6, 7, 8, 9, 10, 12, 15, 18, 20, 24, 25, 30, 36, 40, 48, 50, 60, 100, 120]
I_NICE = [0.001, 0.002, 0.003, 0.005, 0.01, 0.02, 0.025, 0.05, 0.1, 0.2, 0.25, 0.5, 1, 2, 3, 4, 5, 10]
C_NICE = [10e-9, 22e-9, 47e-9, 100e-9, 220e-9, 470e-9, 1e-6, 2.2e-6, 4.7e-6, 10e-6, 22e-6, 47e-6, 100e-6, 220e-6, 470e-6, 1e-3]
L_NICE = [10e-6, 47e-6, 100e-6, 220e-6, 470e-6, 1e-3, 2e-3, 4.7e-3, 5e-3, 10e-3, 20e-3, 47e-3, 50e-3, 100e-3, 0.2, 0.5, 1, 2]


@dataclass
class Edge:
    a: LPoint
    b: LPoint
    kind: Optional[str] = None      # None = plain wire
    id: str = ""
    value: Optional[float] = None
    positive_at_a: bool = True      # + terminal / arrow head sits at end `a` (top or left)
    show_name: bool = True
    show_value: bool = True
    subtype: Optional[str] = None   # for kind == "other": diode | led | zener | ac_source

    @property
    def horizontal(self) -> bool:
        return self.a[0] == self.b[0]

    @property
    def is_wire(self) -> bool:
        return self.kind is None

    def other(self, p: LPoint) -> LPoint:
        return self.b if p == self.a else self.a

    @property
    def positive_end(self) -> LPoint:
        return self.a if self.positive_at_a else self.b

    @property
    def negative_end(self) -> LPoint:
        return self.b if self.positive_at_a else self.a


@dataclass
class LatticeCircuit:
    rows: int
    cols: int
    edges: list[Edge]
    node_of_point: dict[LPoint, str]
    ground_point: Optional[LPoint]
    circuit: Circuit
    junctions: list[LPoint]
    faces: list[list[Edge]]      # inner faces, clockwise as seen on screen
    seed: int = 0
    crossings: list[tuple[LPoint, Edge, Edge, bool]] = field(default_factory=list)   # (point, jumper, crossed wire, drawn as hop)

    @property
    def component_edges(self) -> list[Edge]:
        return [e for e in self.edges if not e.is_wire]

    def degree(self, p: LPoint) -> int:
        return sum(1 for e in self.edges if p in (e.a, e.b))

    @property
    def points(self) -> list[LPoint]:
        seen: list[LPoint] = []
        for e in self.edges:
            for p in (e.a, e.b):
                if p not in seen:
                    seen.append(p)
        return seen


class _UnionFind:
    def __init__(self, items):
        self.parent = {x: x for x in items}

    def find(self, x):
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra


def _lattice_edges(rows: int, cols: int) -> list[Edge]:
    edges = []
    for r in range(rows + 1):
        for c in range(cols):
            edges.append(Edge((r, c), (r, c + 1)))
    for r in range(rows):
        for c in range(cols + 1):
            edges.append(Edge((r, c), (r + 1, c)))
    return edges


def _is_boundary(e: Edge, rows: int, cols: int) -> bool:
    if e.horizontal:
        return e.a[0] in (0, rows)
    return e.a[1] in (0, cols)


def sample_value(kind: str, rng: random.Random) -> Optional[float]:
    if kind in ("resistor", "lamp"):
        pool = R_NICE if kind == "resistor" else [v for v in R_NICE if v <= 1000]
        return float(rng.choice(pool))
    if kind in ("voltage_source", "battery"):
        return float(rng.choice(V_NICE))
    if kind == "current_source":
        return float(rng.choice(I_NICE))
    if kind == "capacitor":
        return float(rng.choice(C_NICE)) if rng.random() < 0.8 else None
    if kind == "inductor":
        return float(rng.choice(L_NICE)) if rng.random() < 0.8 else None
    return None


def _pick_kind(rng: random.Random) -> str:
    kinds = list(KIND_WEIGHTS)
    weights = [KIND_WEIGHTS[k] for k in kinds]
    return rng.choices(kinds, weights)[0]


def planar_faces(edges: list[Edge]) -> tuple[list[tuple[list[LPoint], list[Edge]]], int]:
    """All faces of the planar lattice graph as (vertices, edges); returns them and the outer index."""
    adj: dict[LPoint, list[tuple[LPoint, Edge]]] = {}
    for e in edges:
        adj.setdefault(e.a, []).append((e.b, e))
        adj.setdefault(e.b, []).append((e.a, e))
    for v, nbrs in adj.items():
        nbrs.sort(key=lambda t: math.atan2(t[0][0] - v[0], t[0][1] - v[1]))  # angle in (x=col, y=row)
    visited: set[tuple[LPoint, LPoint]] = set()
    faces: list[tuple[list[LPoint], list[Edge]]] = []
    for e in edges:
        for start in ((e.a, e.b), (e.b, e.a)):
            if start in visited:
                continue
            verts: list[LPoint] = []
            fedges: list[Edge] = []
            u, v = start
            guard = 0
            while (u, v) not in visited and guard < 10000:
                guard += 1
                visited.add((u, v))
                edge = next(ed for nb, ed in adj[u] if nb == v)
                verts.append(u)
                fedges.append(edge)
                nbrs = adj[v]
                idx = next(i for i, (nb, _) in enumerate(nbrs) if nb == u)
                u, v = v, nbrs[(idx - 1) % len(nbrs)][0]
            faces.append((verts, fedges))
    areas = [_signed_area(verts) for verts, _ in faces]
    outer = max(range(len(faces)), key=lambda i: abs(areas[i])) if faces else -1
    return faces, outer


def _signed_area(verts: list[LPoint]) -> float:
    total = 0.0
    for i in range(len(verts)):
        r0, c0 = verts[i]
        r1, c1 = verts[(i + 1) % len(verts)]
        total += c0 * r1 - c1 * r0  # x = col, y = row (y down): positive = clockwise on screen
    return total / 2


def inner_faces_clockwise(edges: list[Edge]) -> list[list[Edge]]:
    faces, outer = planar_faces(edges)
    out: list[list[Edge]] = []
    for i, (verts, fedges) in enumerate(faces):
        if i == outer or len(fedges) < 3:
            continue
        if _signed_area(verts) < 0:
            fedges = list(reversed(fedges))
        out.append(fedges)
    return out


QUESTION_TEMPLATES = {
    "current": ["Find the current through {el}.", "Determine the current in {el}.", "Calculate the current flowing through {el}.",
                "What is the current through {el}?", "Find I through {el}.", "Find I_{el}.", "I_{el} = ?"],
    "voltage": ["Find the voltage across {el}.", "Determine the voltage drop across {el}.", "What is the voltage across {el}?",
                "Find V across {el}.", "Find V_{el}."],
    "power": ["Find the power dissipated in {el}.", "Calculate the power absorbed by {el}.", "Determine the power in {el}.", "P_{el} = ?"],
    "node": ["Find the voltage at node {n}.", "Determine the node voltage V_{n}.", "What is V_{n}?", "Find the potential at node {n}."],
    "between": ["Find V_{a}{b}.", "Find the voltage between {a} and {b}.", "Determine the voltage between nodes {a} and {b}."],
}
JOINERS = [" and ", ", and ", "; ", " Also ", " Then "]


def _make_question(rng: random.Random, circuit: Circuit, labelled: set[str]) -> tuple[list[Unknown], Optional[str]]:
    if rng.random() < 0.15:
        return [], None
    elements = [c for c in circuit.components if c.dc_role == "resistor" and c.id in labelled] or [c for c in circuit.components if c.id in labelled]
    nodes = [n for n in circuit.nodes if n != circuit.ground_node]
    count = 1 if rng.random() < 0.7 else 2
    unknowns: list[Unknown] = []
    parts: list[str] = []
    if not elements and not nodes:
        return [], None
    for _ in range(count):
        choice = rng.choices(["current", "voltage", "power", "node", "between"], [0.45, 0.25, 0.1, 0.12, 0.08])[0]
        if choice in ("current", "voltage", "power") and not elements:
            choice = "node"
        if choice in ("current", "voltage", "power"):
            el = rng.choice(elements)
            u = Unknown(choice, element=el.id)
            text = rng.choice(QUESTION_TEMPLATES[choice]).format(el=el.id)
        elif choice == "node" and nodes:
            n = rng.choice(nodes)
            u = Unknown("voltage", node=n)
            text = rng.choice(QUESTION_TEMPLATES["node"]).format(n=n)
        elif choice == "between" and len(nodes) >= 2:
            a, b = rng.sample(nodes, 2)
            u = Unknown("voltage", between=[a, b])
            text = rng.choice(QUESTION_TEMPLATES["between"]).format(a=a, b=b)
        elif elements:
            el = rng.choice(elements)
            u = Unknown("current", element=el.id)
            text = rng.choice(QUESTION_TEMPLATES["current"]).format(el=el.id)
        elif nodes:
            n = rng.choice(nodes)
            u = Unknown("voltage", node=n)
            text = rng.choice(QUESTION_TEMPLATES["node"]).format(n=n)
        else:
            continue
        if any(u == x for x in unknowns):
            continue
        unknowns.append(u)
        parts.append(text)
    if not unknowns:
        return [], None
    if len(parts) == 1:
        question = parts[0]
    else:
        joiner = rng.choice(JOINERS)
        first = parts[0].rstrip(".?")
        question = first + joiner + (parts[1][0].lower() + parts[1][1:] if joiner.strip() in ("and", ", and", ";") else parts[1])
    return unknowns, question


def generate(rng: random.Random, rows: Optional[int] = None, cols: Optional[int] = None, max_tries: int = 400) -> LatticeCircuit:
    """A random valid lattice circuit; raises RuntimeError if none is found in `max_tries`."""
    for attempt in range(max_tries):
        R = rows or rng.choice([1, 1, 1, 1, 2, 2])
        C = cols or rng.choice([1, 2, 2, 2, 3, 3])
        if R == 2 and C == 3 and rng.random() < 0.5:
            C = 2
        lattice = _try_generate(rng, R, C)
        if lattice is not None:
            return lattice
    raise RuntimeError("could not generate a valid circuit")


def _try_generate(rng: random.Random, rows: int, cols: int) -> Optional[LatticeCircuit]:
    edges = _lattice_edges(rows, cols)
    keep: list[Edge] = []
    for e in edges:
        if _is_boundary(e, rows, cols) or rng.random() < 0.7:
            keep.append(e)
    # Remove dangling stubs (degree-1 lattice points) until none remain.
    changed = True
    while changed:
        changed = False
        deg: dict[LPoint, int] = {}
        for e in keep:
            deg[e.a] = deg.get(e.a, 0) + 1
            deg[e.b] = deg.get(e.b, 0) + 1
        for e in list(keep):
            if deg.get(e.a, 0) < 2 or deg.get(e.b, 0) < 2:
                keep.remove(e)
                changed = True
    if len(keep) < 4:
        return None

    # A jumper: a vertical branch between two half-column points on the outer rails that crosses the
    # middle rail without touching it (drawn as a hop, or as a plain crossing).
    crossings: list[tuple[LPoint, Edge, Edge, bool]] = []
    if rows == 2 and rng.random() < 0.4:
        def find_edge(a: LPoint, b: LPoint) -> Optional[Edge]:
            return next((e for e in keep if {e.a, e.b} == {a, b}), None)
        candidates = []
        for c in range(cols):
            top, mid, bottom = find_edge((0, c), (0, c + 1)), find_edge((1, c), (1, c + 1)), find_edge((2, c), (2, c + 1))
            if top and mid and bottom:
                candidates.append((c, top, mid, bottom))
        if candidates:
            c, top, mid, bottom = rng.choice(candidates)
            T: LPoint = (0, c + 0.5)
            B: LPoint = (2, c + 0.5)
            keep.remove(top)
            keep.remove(bottom)
            keep += [Edge((0, c), T), Edge(T, (0, c + 1)), Edge((2, c), B), Edge(B, (2, c + 1))]
            jumper = Edge(T, B)
            keep.append(jumper)
            crossings.append(((1, c + 0.5), jumper, mid, rng.random() < 0.7))

    # Elements. Sources prefer vertical edges (textbook: the source on the left rung).
    n_sources = 0
    n_current = 0
    p_comp = rng.uniform(0.45, 0.8)
    for e in keep:
        if any(e is x[1] for x in crossings):
            e.kind = rng.choices(["resistor", "capacitor", "inductor", "lamp"], [0.7, 0.1, 0.1, 0.1])[0]
            continue
        if rng.random() > p_comp:
            continue
        kind = _pick_kind(rng)
        if kind in ("voltage_source", "battery", "current_source"):
            if n_sources >= 2 or (kind == "current_source" and n_current >= 1):
                kind = "resistor"
            elif e.horizontal and rng.random() < 0.5:
                kind = "resistor"
        if kind in ("voltage_source", "battery", "current_source"):
            n_sources += 1
            n_current += kind == "current_source"
        e.kind = kind
    for x in crossings:  # the crossed rail must stay a plain wire
        x[2].kind = None
    comps = [e for e in keep if e.kind]
    if not any(e.kind in ("voltage_source", "battery", "current_source") for e in comps):
        verticals = [e for e in keep if not e.horizontal and e.is_wire] or [e for e in keep if e.is_wire and not any(e is x[2] for x in crossings)]
        if not verticals:
            return None
        verticals.sort(key=lambda e: (e.a[1], e.a[0]))
        e = verticals[0]
        e.kind = rng.choices(["voltage_source", "battery", "current_source"], [0.7, 0.2, 0.1])[0]
        comps = [e for e in keep if e.kind]
    if not any(e.kind in ("resistor", "lamp") for e in comps):
        wires = [e for e in keep if e.is_wire and not any(e is x[2] for x in crossings)]
        if not wires:
            return None
        rng.choice(wires).kind = "resistor"
        comps = [e for e in keep if e.kind]
    if len(comps) < 2 or len(comps) > 9:
        return None

    # Electrical nodes from plain wires.
    points = sorted({p for e in keep for p in (e.a, e.b)})
    uf = _UnionFind(points)
    for e in keep:
        if e.is_wire:
            uf.union(e.a, e.b)
    root_of = {p: uf.find(p) for p in points}
    for e in comps:
        if root_of[e.a] == root_of[e.b]:
            return None  # element in parallel with a wire

    # Ids: labelled elements are named per kind in reading order (batteries as E or V); unlabelled
    # ones get the reader's fallback names (R, V, I, C, L, Lp, S) numbered after the labelled ones.
    for e in comps:
        e.show_name = rng.random() < 0.85
        e.show_value = True
        e.value = sample_value(e.kind, rng)
        if e.kind in ("voltage_source", "battery", "current_source"):
            e.positive_at_a = rng.random() < (0.72 if not e.horizontal else 0.5)
    reading = sorted(comps, key=lambda e: ((e.a[0] + e.b[0]) / 2, (e.a[1] + e.b[1]) / 2))
    battery_prefix = "E" if rng.random() < 0.6 else "V"
    counters: dict[str, int] = {}
    used_ids: set[str] = set()
    for e in reading:
        if not e.show_name:
            continue
        prefix = battery_prefix if e.kind == "battery" else ID_PREFIX[e.kind]
        counters[prefix] = counters.get(prefix, 0) + 1
        e.id = f"{prefix}{counters[prefix]}"
        used_ids.add(e.id)
    for e in reading:
        if e.show_name:
            continue
        prefix = FALLBACK_PREFIX[e.kind]
        while True:
            counters[prefix] = counters.get(prefix, 0) + 1
            candidate = f"{prefix}{counters[prefix]}"
            if candidate not in used_ids:
                break
        e.id = candidate
        used_ids.add(e.id)

    # Ground.
    bottom = [p for p in points if p[0] == rows and float(p[1]).is_integer()]
    ground_point: Optional[LPoint] = None
    has_vsource = any(e.kind in ("voltage_source", "battery") for e in comps)
    if rng.random() < 0.5 or not has_vsource:
        candidates = sorted(bottom, key=lambda p: p[1])
        ground_point = candidates[0] if rng.random() < 0.55 else rng.choice(candidates)
    # Node names: ground "0", others a, b, c ... left to right.
    roots = sorted({root_of[p] for p in points}, key=lambda r: min((p[1], p[0]) for p in points if root_of[p] == r))
    if ground_point is not None:
        ground_root = root_of[ground_point]
    else:
        main = min((e for e in comps if e.kind in ("voltage_source", "battery")), key=lambda e: e.id)
        ground_root = root_of[main.negative_end]
    names: dict[LPoint, str] = {}
    letter = 0
    for r in roots:
        name = "0" if r == ground_root else node_letter(letter)
        if r != ground_root:
            letter += 1
        names[r] = name
    node_of_point = {p: names[root_of[p]] for p in points}

    components: list[Component] = []
    for e in comps:
        if e.kind in ("voltage_source", "battery"):
            a, b = node_of_point[e.positive_end], node_of_point[e.negative_end]   # + terminal first
        elif e.kind == "current_source":
            a, b = node_of_point[e.negative_end], node_of_point[e.positive_end]   # arrow head = "to" node
        else:
            a, b = node_of_point[e.a], node_of_point[e.b]
        components.append(Component(e.id, e.kind, e.value, a, b))
    circuit = Circuit(components=components, ground_node="0")
    try:
        solution = solve(circuit)
    except (ValidationError, SolveError):
        return None
    # Reject degenerate textbook problems: no floating node, every resistor carries some current.
    if any(math.isnan(v) for v in solution.node_voltages.values()):
        return None
    for c in circuit.components:
        i = solution.currents.get(c.id)
        if c.dc_role == "resistor" and (i is None or abs(i) < 1e-12):
            return None
        if i is not None and abs(i) > 1e4:
            return None

    # Occasionally one resistor becomes a symbol the app cannot solve (diode, LED, zener, AC source):
    # the drawing keeps it, the JSON lists it under "unsupported" and the app will say so.
    if rng.random() < 0.08:
        resistors = [e for e in comps if e.kind == "resistor"]
        if len(resistors) >= 2:
            victim = rng.choice(resistors)
            old_id = victim.id
            victim.kind = "other"
            victim.subtype = rng.choices(list(OTHER_SUBTYPES), [0.5, 0.2, 0.1, 0.2])[0]
            victim.value = None
            victim.positive_at_a = rng.random() < 0.5
            prefix = OTHER_SUBTYPES[victim.subtype]
            n = 1
            while f"{prefix}{n}" in used_ids:
                n += 1
            victim.id = f"{prefix}{n}"
            used_ids.add(victim.id)
            circuit.components = [c for c in circuit.components if c.id != old_id]
            circuit.unsupported = [f"{victim.id} ({victim.subtype.replace('_', ' ')})"]

    circuit.unknowns, circuit.question = _make_question(rng, circuit, {e.id for e in comps if e.show_name and e.kind != "other"})

    faces = inner_faces_clockwise(keep) if not crossings else []
    circuit.meshes = [[e.id for e in face if e.kind and e.kind != "other"] for face in faces]
    circuit.meshes = [m for m in circuit.meshes if len(m) >= 2]

    degree: dict[LPoint, int] = {}
    for e in keep:
        degree[e.a] = degree.get(e.a, 0) + 1
        degree[e.b] = degree.get(e.b, 0) + 1
    junctions = [p for p, d in degree.items() if d >= 3]
    return LatticeCircuit(rows, cols, keep, node_of_point, ground_point, circuit, junctions, faces, crossings=crossings)
