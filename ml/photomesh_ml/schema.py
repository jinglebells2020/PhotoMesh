"""The circuit description the app consumes.

This is a Python twin of `CircuitPayload.swift` (tolerant decoding of the recognizer's JSON) and of
the parts of `CircuitModel.swift` every training/eval stage needs: node naming, validation and the
DC steady-state redraw. Keep the two in sync; the JSON key names here are the contract.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any, Callable, Iterable, Optional

from .textparse import parse_value

KINDS = ("resistor", "voltage_source", "current_source", "battery", "capacitor", "inductor", "lamp",
         "switch_open", "switch_closed")

KIND_ALIASES = {
    "resistor": "resistor", "r": "resistor",
    "voltage_source": "voltage_source", "voltagesource": "voltage_source", "dc_voltage_source": "voltage_source", "v": "voltage_source",
    "battery": "battery", "cell": "battery",
    "current_source": "current_source", "currentsource": "current_source", "dc_current_source": "current_source", "i": "current_source",
    "capacitor": "capacitor", "c": "capacitor",
    "inductor": "inductor", "coil": "inductor", "l": "inductor",
    "lamp": "lamp", "bulb": "lamp", "light_bulb": "lamp", "light": "lamp",
    "switch_open": "switch_open", "open_switch": "switch_open", "switch": "switch_open",
    "switch_closed": "switch_closed", "closed_switch": "switch_closed",
}

# How each element behaves at DC steady state (ComponentKind.dcRole).
DC_ROLE = {
    "resistor": "resistor", "lamp": "resistor",
    "voltage_source": "voltage_source", "battery": "voltage_source",
    "current_source": "current_source",
    "capacitor": "open", "switch_open": "open",
    "inductor": "short", "switch_closed": "short",
}
UNIT_SYMBOL = {"resistor": "Ω", "lamp": "Ω", "voltage_source": "V", "battery": "V", "current_source": "A",
               "capacitor": "F", "inductor": "H", "switch_open": "", "switch_closed": ""}
UNKNOWN_KINDS = ("current", "voltage", "power", "resistance")


def natural_key(text: str) -> list:
    """Sort key matching Swift's `.numeric, .caseInsensitive` comparison (R2 < R10)."""
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", text)]


def node_letter(index: int) -> str:
    """0 -> a, 25 -> z, 26 -> aa (Circuit.nodeLetter)."""
    n = max(index, 0)
    name = ""
    while True:
        name = chr(97 + n % 26) + name
        n = n // 26 - 1
        if n < 0:
            return name


def is_letter_node(node: str) -> bool:
    return 0 < len(node) <= 2 and node.isascii() and node.isalpha() and node.islower()


class ValidationError(ValueError):
    """Raised for circuits the app would reject; `code` mirrors CircuitValidationError."""

    def __init__(self, code: str, detail: str = ""):
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code
        self.detail = detail


@dataclass
class Component:
    id: str
    kind: str
    value: Optional[float]
    node_a: str          # + terminal for voltage sources; current flows a -> b inside current sources
    node_b: str
    box: Optional[list[float]] = None      # [x0, y0, x1, y1] as fractions of the image
    orientation: Optional[str] = None      # "horizontal" | "vertical"

    @property
    def dc_role(self) -> str:
        return DC_ROLE[self.kind]

    @property
    def is_source(self) -> bool:
        return self.dc_role in ("voltage_source", "current_source")

    @property
    def analyzed_kind(self) -> str:
        role = self.dc_role
        return role if role in ("resistor", "voltage_source", "current_source") else self.kind

    @property
    def has_value(self) -> bool:
        return self.kind not in ("switch_open", "switch_closed")

    def other_node(self, node: str) -> str:
        return self.node_b if node == self.node_a else self.node_a

    def touches(self, node: str) -> bool:
        return node in (self.node_a, self.node_b)

    def to_json(self, digits: int = 2) -> dict:
        d: dict[str, Any] = {"id": self.id, "type": self.kind, "value": self.value}
        role = self.dc_role
        if role == "voltage_source":
            d["positive_node"], d["negative_node"] = self.node_a, self.node_b
        elif role == "current_source":
            d["from_node"], d["to_node"] = self.node_a, self.node_b
        else:
            d["node_a"], d["node_b"] = self.node_a, self.node_b
        if self.box is not None:
            d["box"] = [round(float(v), digits) for v in self.box]
            d["orientation"] = self.orientation or ("horizontal" if (self.box[2] - self.box[0]) >= (self.box[3] - self.box[1]) else "vertical")
        return d


@dataclass
class Unknown:
    kind: str
    element: Optional[str] = None
    node: Optional[str] = None
    between: Optional[list[str]] = None

    def to_json(self) -> dict:
        d: dict[str, Any] = {"kind": self.kind}
        if self.element is not None:
            d["element"] = self.element
        if self.node is not None:
            d["node"] = self.node
        if self.between is not None:
            d["between"] = list(self.between)
        return d

    @classmethod
    def from_json(cls, obj: dict) -> Optional["Unknown"]:
        kind = str(obj.get("kind", "")).lower()
        if kind not in UNKNOWN_KINDS:
            return None
        between = obj.get("between")
        return cls(kind=kind, element=_flex_str(obj.get("element")), node=_flex_str(obj.get("node")),
                   between=[_flex_str(x) for x in between] if isinstance(between, list) else None)


def _flex_str(value: Any) -> Optional[str]:
    """Node ids may arrive as numbers ("0" -> 0)."""
    if value is None:
        return None
    if isinstance(value, bool):
        return str(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value == int(value) else str(value)
    text = str(value).strip()
    return text


def _flex_number(value: Any) -> Optional[float]:
    """Numbers may arrive as strings like "4.7k"."""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return parse_value(str(value))


@dataclass
class Circuit:
    components: list[Component] = field(default_factory=list)
    ground_node: str = "0"
    meshes: list[list[str]] = field(default_factory=list)
    unknowns: list[Unknown] = field(default_factory=list)
    question: Optional[str] = None
    notes: Optional[str] = None
    unsupported: list[str] = field(default_factory=list)
    node_points: dict[str, list[float]] = field(default_factory=dict)
    confidence: Optional[float] = None
    error: Optional[str] = None

    # ----------------------------------------------------------------------------- structure
    @property
    def nodes(self) -> list[str]:
        seen: list[str] = []
        for c in self.components:
            for n in (c.node_a, c.node_b):
                if n not in seen:
                    seen.append(n)
        others = sorted((n for n in seen if n != self.ground_node), key=natural_key)
        return ([self.ground_node] if self.ground_node in seen else []) + others

    def component(self, cid: str) -> Optional[Component]:
        return next((c for c in self.components if c.id == cid), None)

    def components_at(self, node: str) -> list[Component]:
        return [c for c in self.components if c.touches(node)]

    @property
    def voltage_sources(self) -> list[Component]:
        return [c for c in self.components if c.kind == "voltage_source"]

    def is_connected(self) -> bool:
        nodes = self.nodes
        if not nodes:
            return True
        adjacency: dict[str, set[str]] = {n: set() for n in nodes}
        for c in self.components:
            adjacency[c.node_a].add(c.node_b)
            adjacency[c.node_b].add(c.node_a)
        seen = {nodes[0]}
        stack = [nodes[0]]
        while stack:
            for nxt in adjacency[stack.pop()]:
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        return len(seen) == len(nodes)

    # ----------------------------------------------------------------------------- JSON
    @classmethod
    def from_json(cls, obj: Any) -> "Circuit":
        """Tolerant decoding, mirroring CircuitPayload: fences, string numbers, numeric node ids."""
        if isinstance(obj, (str, bytes)):
            obj = parse_json_text(obj if isinstance(obj, str) else obj.decode("utf-8"))
        if not isinstance(obj, dict):
            raise ValidationError("unreadable", "top level is not an object")
        circuit = cls()
        err = obj.get("error")
        if err:
            circuit.error = str(err)
        unsupported = obj.get("unsupported") or []
        circuit.unsupported = [s for s in (_flex_str(u) for u in unsupported if u is not None) if s]
        used: set[str] = set()
        for index, raw in enumerate(obj.get("components") or []):
            if not isinstance(raw, dict):
                continue
            cid = (_flex_str(raw.get("id")) or "").strip() or f"X{index + 1}"
            while cid in used:
                cid += "'"
            used.add(cid)
            type_text = str(raw.get("type", "")).lower().replace(" ", "_")
            kind = KIND_ALIASES.get(type_text)
            if kind is None:
                if type_text and not any(cid in u for u in circuit.unsupported):
                    circuit.unsupported.append(f"{cid} ({raw.get('type')})")
                continue
            value = _flex_number(raw.get("value"))
            if value is None and kind in ("switch_open", "switch_closed", "capacitor", "inductor"):
                value = 0.0
            role = DC_ROLE[kind]
            if role == "voltage_source":
                a = _flex_str(raw.get("positive_node")) or _flex_str(raw.get("node_a"))
                b = _flex_str(raw.get("negative_node")) or _flex_str(raw.get("node_b"))
            elif role == "current_source":
                a = _flex_str(raw.get("from_node")) or _flex_str(raw.get("node_a"))
                b = _flex_str(raw.get("to_node")) or _flex_str(raw.get("node_b"))
            else:
                a = _flex_str(raw.get("node_a")) or _flex_str(raw.get("positive_node")) or _flex_str(raw.get("from_node"))
                b = _flex_str(raw.get("node_b")) or _flex_str(raw.get("negative_node")) or _flex_str(raw.get("to_node"))
            if not a or not b:
                raise ValidationError("bad_component", cid)
            box = None
            raw_box = raw.get("box")
            if isinstance(raw_box, list) and len(raw_box) == 4:
                vals = [_flex_number(v) for v in raw_box]
                if all(v is not None for v in vals):
                    x0, y0, x1, y1 = vals  # type: ignore[misc]
                    box = [min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)]
            orientation = None
            o = str(raw.get("orientation") or "").lower()
            if o.startswith("h"):
                orientation = "horizontal"
            elif o.startswith("v"):
                orientation = "vertical"
            elif box is not None:
                orientation = "horizontal" if (box[2] - box[0]) >= (box[3] - box[1]) else "vertical"
            circuit.components.append(Component(cid, kind, value, a, b, box, orientation))
        circuit.ground_node = _flex_str(obj.get("ground_node")) or "0"
        circuit.meshes = [[_flex_str(x) or "" for x in mesh] for mesh in (obj.get("meshes") or []) if isinstance(mesh, list)]
        circuit.unknowns = [u for u in (Unknown.from_json(x) for x in (obj.get("unknowns") or []) if isinstance(x, dict)) if u]
        q = obj.get("question")
        circuit.question = str(q) if q else None
        n = obj.get("notes")
        circuit.notes = str(n) if n else None
        conf = obj.get("confidence")
        circuit.confidence = float(conf) if isinstance(conf, (int, float)) and not isinstance(conf, bool) else None
        for node, pair in (obj.get("node_points") or {}).items():
            if isinstance(pair, list) and len(pair) == 2:
                x, y = _flex_number(pair[0]), _flex_number(pair[1])
                if x is not None and y is not None:
                    circuit.node_points[_flex_str(node) or str(node)] = [x, y]
        return circuit

    def to_json(self, digits: int = 2) -> dict:
        if self.error:
            return {"error": self.error}
        return {
            "components": [c.to_json(digits) for c in self.components],
            "ground_node": self.ground_node,
            "node_points": {k: [round(float(v), digits) for v in pt] for k, pt in self.node_points.items()},
            "meshes": [list(m) for m in self.meshes],
            "unknowns": [u.to_json() for u in self.unknowns],
            "question": self.question,
            "unsupported": list(self.unsupported),
            "confidence": self.confidence,
            "notes": self.notes,
        }

    def dumps(self, digits: int = 2) -> str:
        return json.dumps(self.to_json(digits), ensure_ascii=False, separators=(", ", ": "))

    # ----------------------------------------------------------------------------- naming
    def renaming_nodes(self, rename: Callable[[str], str]) -> "Circuit":
        copy = Circuit(
            components=[Component(c.id, c.kind, c.value, rename(c.node_a), rename(c.node_b), list(c.box) if c.box else None, c.orientation) for c in self.components],
            ground_node=rename(self.ground_node),
            meshes=[list(m) for m in self.meshes],
            unknowns=[Unknown(u.kind, u.element, rename(u.node) if u.node else None, [rename(x) for x in u.between] if u.between else None) for u in self.unknowns],
            question=self.question, notes=self.notes, unsupported=list(self.unsupported),
            node_points={}, confidence=self.confidence, error=self.error,
        )
        for node, pt in self.node_points.items():
            copy.node_points.setdefault(rename(node), list(pt))
        return copy

    def with_letter_nodes(self) -> "Circuit":
        """a, b, c... in natural order of the current names; the reference node keeps its own name."""
        others = [n for n in self.nodes if n != self.ground_node]
        if not others or all(is_letter_node(n) for n in others):
            return self
        mapping = {self.ground_node: self.ground_node}
        for index, node in enumerate(others):
            mapping[node] = node_letter(index)
        return self.renaming_nodes(lambda n: mapping.get(n, n))

    # ----------------------------------------------------------------------------- validation
    def validated(self) -> "Circuit":
        """Port of `Circuit.validated()`: cleans trivial issues, raises on anything unsolvable."""
        if self.error:
            raise ValidationError("no_circuit", self.error)
        if not self.components:
            raise ValidationError("noComponents")
        if self.unsupported:
            raise ValidationError("unsupportedElements", ", ".join(self.unsupported))
        cleaned = self.renaming_nodes(lambda n: n)
        cleaned.components = [c for c in cleaned.components if not (c.node_a == c.node_b and not c.is_source)]
        for c in cleaned.components:
            if c.is_source and c.node_a == c.node_b:
                raise ValidationError("shortedSource", c.id)
            if c.dc_role == "resistor" and not (c.value is not None and c.value > 0):
                raise ValidationError("nonPositiveResistor" if c.value is not None else "missingValue", c.id)
            if c.is_source and c.value is None:
                raise ValidationError("missingValue", c.id)
        if not any(c.is_source for c in cleaned.components):
            raise ValidationError("noSource")
        nodes = cleaned.nodes
        if cleaned.ground_node not in nodes:
            if cleaned.voltage_sources:
                cleaned.ground_node = cleaned.voltage_sources[0].node_b
            elif nodes:
                cleaned.ground_node = max(nodes, key=lambda n: len(cleaned.components_at(n)))
            else:
                raise ValidationError("missingGround")
            return cleaned.validated()
        for node in nodes:
            attached = cleaned.components_at(node)
            if len(attached) < 2:
                raise ValidationError("danglingElement", attached[0].id if attached else node)
        if not cleaned.is_connected():
            raise ValidationError("disconnected")
        return cleaned

    # ----------------------------------------------------------------------------- DC redraw
    def dc_equivalent(self) -> tuple["Circuit", dict[str, str]]:
        """Capacitors/open switches removed, inductors/closed switches merge their nodes, lamps ->
        resistors, batteries -> voltage sources. Returns the solvable circuit and node aliases."""
        parent = {n: n for n in self.nodes}

        def find(n: str) -> str:
            while parent[n] != n:
                n = parent[n]
            return n

        for c in self.components:
            if c.dc_role != "short":
                continue
            a, b = find(c.node_a), find(c.node_b)
            if a == b:
                continue
            if a == self.ground_node:
                keep = a
            elif b == self.ground_node:
                keep = b
            else:
                keep = a if natural_key(a) <= natural_key(b) else b
            drop = b if keep == a else a
            parent[drop] = keep
        alias = {n: find(n) for n in self.nodes}
        solved = Circuit(ground_node=alias.get(self.ground_node, self.ground_node), unknowns=list(self.unknowns),
                         question=self.question, notes=self.notes, unsupported=list(self.unsupported))
        for c in self.components:
            if c.dc_role in ("open", "short"):
                continue
            solved.components.append(Component(c.id, c.analyzed_kind, c.value, alias[c.node_a], alias[c.node_b], c.box, c.orientation))
        for node, pt in self.node_points.items():
            solved.node_points.setdefault(alias.get(node, node), list(pt))
        return solved, alias


def parse_json_text(text: str) -> dict:
    """The model's answer as a dict: tolerates markdown fences and prose around the object."""
    body = text.strip()
    if body.startswith("```"):
        lines = body.split("\n")[1:]
        body = "\n".join(lines)
        end = body.rfind("```")
        if end >= 0:
            body = body[:end]
    start, end = body.find("{"), body.rfind("}")
    if start < 0 or end < start:
        raise ValidationError("unreadable", "no JSON object")
    try:
        return json.loads(body[start:end + 1])
    except json.JSONDecodeError as exc:
        raise ValidationError("unreadable", str(exc)) from exc


def load_circuit(text_or_obj: Any) -> Circuit:
    return Circuit.from_json(text_or_obj)


def circuits_equal_structure(a: Circuit, b: Circuit) -> bool:
    """Same component ids, kinds and values; node names are compared through `solver`, not here."""
    if len(a.components) != len(b.components):
        return False
    ka = {c.id: (c.kind, c.value) for c in a.components}
    kb = {c.id: (c.kind, c.value) for c in b.components}
    if ka.keys() != kb.keys():
        return False
    for cid, (kind, value) in ka.items():
        kind_b, value_b = kb[cid]
        if kind != kind_b:
            return False
        if (value is None) != (value_b is None):
            return False
        if value is not None and value_b is not None and not _close(value, value_b):
            return False
    return True


def comparable_value(component: "Component") -> Optional[float]:
    """The value that matters at DC: switches, capacitors and inductors have none (None == 0)."""
    if component.kind in ("switch_open", "switch_closed", "capacitor", "inductor"):
        return 0.0
    return component.value


def _close(x: float, y: float, rel: float = 1e-6) -> bool:
    return abs(x - y) <= rel * max(1.0, abs(x), abs(y))
