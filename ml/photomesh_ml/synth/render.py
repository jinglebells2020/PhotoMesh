"""Rasterizes a lattice circuit in a printed or hand-drawn style, with exact supervision.

Output of `render()`:
- the RGB image,
- a wire mask (wires, leads, junction dots and the ground stub; symbol bodies and text excluded),
- symbol boxes with class, orientation, polarity direction and terminal points,
- text boxes with their strings and roles (name / value / combined / question),
- junction points,
- the app-level circuit JSON with normalized boxes and node points.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from ..classes import POLAR_KINDS
from ..schema import Circuit, UNIT_SYMBOL
from ..textparse import format_value
from . import strokes as S
from .circuits import Edge, LatticeCircuit
from .fonts import ensure_fonts, load_font

SS = 2  # supersampling for anti-aliased strokes

Point = tuple[float, float]


@dataclass
class Style:
    hand: bool
    spacing: float
    stroke: float
    wobble: float
    ink_rgb: tuple[int, int, int]
    ink_alpha: float
    pencil: bool
    paper: str
    resistor: str            # "zigzag" | "box"
    font: Path
    font_size: int
    label_mode: str          # "stacked" | "combined" | "value_only"
    corner_dots: bool
    junction_dots: bool
    question_side: str       # "bottom" | "top"
    source_marks: str        # "inside" | "outside"
    name: str = ""


def random_style(rng: random.Random, hand: Optional[bool] = None) -> Style:
    fonts = ensure_fonts(download=False)
    if hand is None:
        hand = rng.random() < 0.6
    spacing = rng.uniform(150, 260)
    if hand:
        pencil = rng.random() < 0.3
        ink = rng.choice([(18, 18, 24), (25, 25, 30), (28, 48, 140), (20, 40, 120), (40, 40, 45)])
        if pencil:
            ink = (70 + rng.randint(0, 25),) * 3
        paper = rng.choices(["white", "cream", "lined", "grid", "whiteboard", "dark"], [0.35, 0.15, 0.2, 0.15, 0.1, 0.05])[0]
        font = rng.choice(fonts["hand"])
        return Style(
            hand=True, spacing=spacing, stroke=spacing * rng.uniform(0.011, 0.024), wobble=spacing * rng.uniform(0.004, 0.014),
            ink_rgb=ink, ink_alpha=rng.uniform(0.7, 0.9) if pencil else rng.uniform(0.85, 1.0), pencil=pencil, paper=paper,
            resistor="zigzag" if rng.random() < 0.75 else "box", font=font, font_size=int(spacing * rng.uniform(0.15, 0.22)),
            label_mode=rng.choices(["stacked", "combined", "value_only"], [0.5, 0.3, 0.2])[0],
            corner_dots=rng.random() < 0.25, junction_dots=rng.random() < 0.7,
            question_side="bottom" if rng.random() < 0.8 else "top", source_marks="inside" if rng.random() < 0.6 else "outside",
            name="hand",
        )
    ink = rng.choice([(0, 0, 0), (15, 15, 15), (30, 30, 30)])
    paper = rng.choices(["white", "cream", "white", "screen"], [0.6, 0.15, 0.15, 0.1])[0]
    font = rng.choice(fonts["print"])
    return Style(
        hand=False, spacing=spacing, stroke=spacing * rng.uniform(0.009, 0.017), wobble=0.0,
        ink_rgb=ink, ink_alpha=1.0, pencil=False, paper=paper,
        resistor="zigzag" if rng.random() < 0.6 else "box", font=font, font_size=int(spacing * rng.uniform(0.13, 0.19)),
        label_mode=rng.choices(["stacked", "combined", "value_only"], [0.55, 0.3, 0.15])[0],
        corner_dots=rng.random() < 0.15, junction_dots=True,
        question_side="bottom" if rng.random() < 0.85 else "top", source_marks="inside",
        name="print",
    )


@dataclass
class SymbolLabel:
    cls: str
    box: list[float]                 # px, [x0, y0, x1, y1]
    orientation: str                 # "horizontal" | "vertical"
    polarity: str                    # "right" | "up" | "left" | "down"
    terminals: list[Point]           # px
    id: str = ""


@dataclass
class TextLabel:
    box: list[float]
    text: str
    role: str                        # "name" | "value" | "combined" | "question"
    component: Optional[str] = None


@dataclass
class Rendered:
    image: Image.Image
    wire_mask: np.ndarray            # uint8 HxW, 255 on wire ink
    symbols: list[SymbolLabel]
    texts: list[TextLabel]
    junctions: list[Point]
    circuit: Circuit
    style: str
    spacing: float

    @property
    def width(self) -> int:
        return self.image.width

    @property
    def height(self) -> int:
        return self.image.height


class _Canvas:
    """Two supersampled 'L' layers: all ink, and wire ink only."""

    def __init__(self, width: int, height: int):
        self.w, self.h = width, height
        self.ink = Image.new("L", (width * SS, height * SS), 0)
        self.wire = Image.new("L", (width * SS, height * SS), 0)
        self.d_ink = ImageDraw.Draw(self.ink)
        self.d_wire = ImageDraw.Draw(self.wire)

    def stroke(self, line: list[Point], width: float, wire: bool) -> None:
        if len(line) < 2:
            return
        pts = [(x * SS, y * SS) for x, y in line]
        w = max(1, int(round(width * SS)))
        targets = [self.d_ink, self.d_wire] if wire else [self.d_ink]
        for d in targets:
            d.line(pts, fill=255, width=w, joint="curve")
            r = w / 2
            for x, y in (pts[0], pts[-1]):
                d.ellipse([x - r, y - r, x + r, y + r], fill=255)

    def disc(self, centre: Point, radius: float, wire: bool) -> None:
        x, y = centre[0] * SS, centre[1] * SS
        r = radius * SS
        self.d_ink.ellipse([x - r, y - r, x + r, y + r], fill=255)
        if wire:
            self.d_wire.ellipse([x - r, y - r, x + r, y + r], fill=255)

    def paste_text(self, layer: Image.Image, x: int, y: int) -> None:
        self.ink.paste(layer, (x * SS, y * SS), mask=layer)


def _text_layer(text: str, font, angle: float) -> Image.Image:
    """Text rendered at SS scale on a transparent 'L' layer, cropped to its ink."""
    dummy = ImageDraw.Draw(Image.new("L", (4, 4), 0))
    x0, y0, x1, y1 = dummy.textbbox((0, 0), text, font=font)
    pad = 6 * SS
    layer = Image.new("L", (int(x1 - x0) + 2 * pad, int(y1 - y0) + 2 * pad), 0)
    ImageDraw.Draw(layer).text((pad - x0, pad - y0), text, font=font, fill=255)
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    bbox = layer.getbbox()
    return layer.crop(bbox) if bbox else layer


def _value_text(kind: str, value: float, rng: random.Random, hand: bool) -> str:
    unit = UNIT_SYMBOL[kind]
    base = format_value(value, unit)          # "4.7 kΩ"
    number, _, suffix = base.partition(" ")
    r = rng.random()
    if kind in ("resistor", "lamp"):
        if r < 0.3:
            return f"{number}{suffix}"        # 4.7kΩ
        if r < 0.45 and suffix != "Ω":
            return f"{number}{suffix[:-1]}"   # 4.7k
        if r < 0.55 and "." in number and suffix != "Ω":
            a, b = number.split(".")
            return f"{a}{suffix[:-1]}{b}"      # 4k7
        if r < 0.65 and value < 1e6:
            return f"{value:g}Ω" if value == int(value) else base
        if r < 0.72:
            return f"{number} {suffix[:-1]}ohm" if suffix != "Ω" else f"{number} ohm"
        return base
    if kind in ("voltage_source", "battery"):
        return f"{number}{suffix}" if r < 0.5 else base
    if kind == "current_source":
        if r < 0.4:
            return f"{number}{suffix}"
        if r < 0.55:
            return f"{value:g} A" if value >= 0.001 else base
        return base
    if kind == "capacitor":
        text = base if r < 0.5 else f"{number}{suffix}"
        if hand and rng.random() < 0.5:
            text = text.replace("µ", "u")
        return text
    if kind == "inductor":
        return base if r < 0.5 else f"{number}{suffix}"
    return base


def _polarity_name(angle: float) -> str:
    a = (math.degrees(angle) + 360) % 360
    if a < 45 or a >= 315:
        return "right"
    if a < 135:
        return "down"
    if a < 225:
        return "left"
    return "up"


def _paper(style: Style, width: int, height: int, rng: random.Random) -> np.ndarray:
    kind = style.paper
    if kind == "white":
        base = np.array([255, 255, 255], float) - rng.uniform(0, 8)
    elif kind == "cream":
        base = np.array([250, 246, 232], float) - rng.uniform(0, 8)
    elif kind == "lined":
        base = np.array([252, 252, 250], float)
    elif kind == "grid":
        base = np.array([250, 250, 246], float)
    elif kind == "whiteboard":
        base = np.array([243, 246, 248], float)
    elif kind == "dark":
        base = np.array([222, 218, 208], float)
    else:  # screen
        base = np.array([255, 255, 255], float)
    paper = np.ones((height, width, 3), np.float32) * base
    if kind == "lined":
        pitch = max(18, int(style.spacing * rng.uniform(0.11, 0.16)))
        offset = rng.randint(0, pitch)
        color = np.array([170, 190, 225], float)
        for y in range(offset, height, pitch):
            paper[y:y + 1, :, :] = color
        if rng.random() < 0.6:
            x = int(width * rng.uniform(0.05, 0.12))
            paper[:, x:x + 2, :] = np.array([230, 140, 140], float)
    elif kind == "grid":
        pitch = max(14, int(style.spacing * rng.uniform(0.08, 0.12)))
        color = np.array([205, 212, 222], float)
        for y in range(rng.randint(0, pitch), height, pitch):
            paper[y:y + 1, :, :] = color
        for x in range(rng.randint(0, pitch), width, pitch):
            paper[:, x:x + 1, :] = color
    noise = rng.uniform(0, 4)
    if noise > 0:
        paper += np.random.RandomState(rng.randint(0, 2**31 - 1)).normal(0, noise, paper.shape)
    return np.clip(paper, 0, 255)


def render(lattice: LatticeCircuit, rng: random.Random, style: Optional[Style] = None) -> Rendered:
    style = style or random_style(rng)
    s = style.spacing
    rows, cols = lattice.rows, lattice.cols
    has_question = lattice.circuit.question is not None
    margin_x = s * rng.uniform(0.55, 0.8)
    margin_top = s * rng.uniform(0.35, 0.6)
    margin_bottom = s * rng.uniform(0.35, 0.6)
    q_height = style.font_size * 2.6 if has_question else 0
    if has_question and style.question_side == "top":
        margin_top += q_height
    else:
        margin_bottom += q_height
    width = int(cols * s + 2 * margin_x)
    height = int(rows * s + margin_top + margin_bottom)

    # Lattice point positions, jittered for sketches.
    pos: dict[tuple[int, int], Point] = {}
    for r in range(rows + 1):
        for c in range(cols + 1):
            jx = rng.gauss(0, s * 0.018) if style.hand else 0.0
            jy = rng.gauss(0, s * 0.018) if style.hand else 0.0
            pos[(r, c)] = (margin_x + c * s + jx, margin_top + r * s + jy)

    canvas = _Canvas(width, height)
    symbols: list[SymbolLabel] = []
    texts: list[TextLabel] = []
    wire_runs = _wire_runs(lattice)

    def hand_line(line: list[Point], amp_scale: float = 1.0, overshoot: float = 0.0) -> list[Point]:
        if not style.hand or style.wobble == 0:
            return line
        return S.wobble(line, rng, style.wobble * amp_scale, step=4.0, overshoot=overshoot)

    def stroke_width(scale: float = 1.0) -> float:
        w = style.stroke * scale
        return w * rng.uniform(0.85, 1.15) if style.hand else w

    # Wires (merged collinear runs are one stroke each).
    for run in wire_runs:
        line = [pos[p] for p in run]
        canvas.stroke(hand_line(line, 1.0, overshoot=s * 0.02 if style.hand else 0.0), stroke_width(), wire=True)

    # Elements: leads (wire) + body (ink) + labels.
    box_pad = style.stroke * 0.6
    for e in lattice.component_edges:
        A, B = pos[e.a], pos[e.b]
        M = ((A[0] + B[0]) / 2, (A[1] + B[1]) / 2)
        ux, uy = B[0] - M[0], B[1] - M[1]
        norm = math.hypot(ux, uy) or 1.0
        ux, uy = ux / norm, uy / norm
        polar = e.kind in POLAR_KINDS
        if polar:
            P = pos[e.positive_end]
            angle = math.atan2(P[1] - M[1], P[0] - M[0])
        else:
            angle = math.atan2(uy, ux)
        body, half, half_h = _body(e.kind, s, style, rng)
        placed = S.place(body, M, angle)
        # Extra marks that are not part of the terminal axis (+/- signs, arrows).
        marks = S.place(_marks(e.kind, s, style, rng), M, angle)
        T_a = (M[0] - ux * half, M[1] - uy * half)
        T_b = (M[0] + ux * half, M[1] + uy * half)
        for lead in ([A, T_a], [T_b, B]):
            canvas.stroke(hand_line(lead, 0.6), stroke_width(), wire=True)
        for line in placed:
            canvas.stroke(hand_line(line, 0.45), stroke_width(rng.uniform(0.9, 1.1)), wire=False)
        for line in marks:
            canvas.stroke(hand_line(line, 0.3), stroke_width(0.9), wire=False)
        x0, y0, x1, y1 = S.bounds(placed + marks if style.source_marks == "inside" or not marks else placed)
        box = [x0 - box_pad, y0 - box_pad, x1 + box_pad, y1 + box_pad]
        orientation = "horizontal" if e.horizontal else "vertical"
        polarity = _polarity_name(angle) if polar else ("right" if e.horizontal else "up")
        symbols.append(SymbolLabel(e.kind, box, orientation, polarity, [T_a, T_b], e.id))
        _place_labels(canvas, texts, e, box, orientation, style, rng, width, height)

    # Ground symbol.
    if lattice.ground_point is not None:
        P = pos[lattice.ground_point]
        lines, half_w, depth = S.ground_symbol(s * 0.2, s * 0.045, s * 0.12)
        placed = S.place(lines, P, 0.0)
        canvas.stroke(hand_line(placed[0], 0.5), stroke_width(), wire=True)
        for line in placed[1:]:
            canvas.stroke(hand_line(line, 0.4), stroke_width(), wire=False)
        x0, y0, x1, y1 = S.bounds(placed[1:])
        symbols.append(SymbolLabel("ground", [x0 - box_pad, y0 - box_pad, x1 + box_pad, y1 + box_pad], "vertical", "down", [P], "GND"))

    # Junction and corner dots.
    junction_px: list[Point] = [pos[p] for p in lattice.junctions]
    dot_r = s * rng.uniform(0.018, 0.028)
    if style.junction_dots:
        for p in junction_px:
            canvas.disc(p, dot_r * (rng.uniform(0.85, 1.15) if style.hand else 1.0), wire=True)
    if style.corner_dots:
        for p in lattice.points:
            if lattice.degree(p) == 2 and p not in lattice.junctions and _is_corner(lattice, p):
                canvas.disc(pos[p], dot_r * 0.75, wire=True)

    # Node letters, drawn when the question refers to nodes (and now and then anyway, textbook style).
    referenced = {u.node for u in lattice.circuit.unknowns if u.node} | {n for u in lattice.circuit.unknowns if u.between for n in u.between}
    if referenced or rng.random() < 0.2:
        node_font = load_font(style.font, int(style.font_size * 0.95))
        wanted = referenced or {n for n in lattice.circuit.nodes if n != "0"}
        for node in wanted:
            anchor = _node_anchor(lattice, node, pos)
            if anchor is None:
                continue
            layer = _text_layer(node, node_font, rng.uniform(-4, 4) if style.hand else 0.0)
            lw, lh = layer.width // SS, layer.height // SS
            ox, oy = rng.choice([(-lw - s * 0.06, -lh - s * 0.04), (s * 0.06, -lh - s * 0.04), (s * 0.06, s * 0.04), (-lw - s * 0.06, s * 0.04)])
            lx, ly = int(min(max(2, anchor[0] + ox), width - lw - 2)), int(min(max(2, anchor[1] + oy), height - lh - 2))
            canvas.paste_text(layer, lx, ly)
            texts.append(TextLabel([float(lx), float(ly), float(lx + lw), float(ly + lh)], node, "node"))
            if rng.random() < 0.5:
                canvas.disc(anchor, dot_r * 0.9, wire=True)

    # Question text.
    if has_question:
        q_font = load_font(style.font, int(style.font_size * 0.95))
        lines = _wrap(lattice.circuit.question, q_font, width - 2 * int(s * 0.25))
        y = int(s * 0.12) if style.question_side == "top" else int(height - margin_bottom + s * 0.18)
        if style.question_side == "top":
            y = int(margin_top - q_height + s * 0.05)
        x = int(s * 0.25) if rng.random() < 0.6 else None
        boxes = []
        for line_text in lines:
            layer = _text_layer(line_text, q_font, rng.uniform(-1.5, 1.5) if style.hand else 0.0)
            lw, lh = layer.width // SS, layer.height // SS
            lx = x if x is not None else (width - lw) // 2
            canvas.paste_text(layer, lx, y)
            boxes.append([lx, y, lx + lw, y + lh])
            y += int(lh * 1.25)
        for b, line_text in zip(boxes, lines):
            texts.append(TextLabel([float(v) for v in b], line_text, "question"))

    # Compose.
    ink = np.asarray(canvas.ink.resize((width, height), Image.BOX), np.float32) / 255.0
    wire = np.asarray(canvas.wire.resize((width, height), Image.BOX), np.float32) / 255.0
    paper = _paper(style, width, height, rng)
    alpha = ink * style.ink_alpha
    if style.pencil:
        texture = np.random.RandomState(rng.randint(0, 2**31 - 1)).uniform(0.55, 1.0, (height, width)).astype(np.float32)
        texture = np.asarray(Image.fromarray((texture * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255.0
        alpha = alpha * texture
    color = np.array(style.ink_rgb, np.float32)
    img = paper * (1 - alpha[..., None]) + color * alpha[..., None]
    image = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    wire_mask = (wire > 0.3).astype(np.uint8) * 255

    circuit = _with_geometry(lattice, symbols, pos, width, height)
    return Rendered(image, wire_mask, symbols, texts, junction_px, circuit, style.name, s)


def _node_anchor(lattice: LatticeCircuit, node: str, pos: dict) -> Optional[Point]:
    """A lattice point of the node to write its letter next to: a junction, else a corner, else any."""
    pts = [p for p, n in lattice.node_of_point.items() if n == node]
    if not pts:
        return None
    for group in ([p for p in pts if p in lattice.junctions], [p for p in pts if _is_corner(lattice, p)], pts):
        if group:
            p = min(group, key=lambda q: (pos[q][0], pos[q][1]))
            return pos[p]
    return None


def _is_corner(lattice: LatticeCircuit, p: tuple[int, int]) -> bool:
    edges = [e for e in lattice.edges if p in (e.a, e.b)]
    return len(edges) == 2 and edges[0].horizontal != edges[1].horizontal


def _wire_runs(lattice: LatticeCircuit) -> list[list[tuple[int, int]]]:
    """Maximal collinear chains of plain-wire edges, each drawn as one stroke."""
    wires = [e for e in lattice.edges if e.is_wire]
    used: set[int] = set()
    runs: list[list[tuple[int, int]]] = []
    by_point: dict[tuple[int, int], list[int]] = {}
    for i, e in enumerate(wires):
        by_point.setdefault(e.a, []).append(i)
        by_point.setdefault(e.b, []).append(i)
    for i, e in enumerate(wires):
        if i in used:
            continue
        used.add(i)
        chain = [e.a, e.b]
        # extend forward from chain[-1] and backward from chain[0] along collinear wire edges
        for direction in (1, -1):
            while True:
                end = chain[-1] if direction == 1 else chain[0]
                prev = chain[-2] if direction == 1 else chain[1]
                nxt = None
                for j in by_point.get(end, []):
                    if j in used:
                        continue
                    w = wires[j]
                    other = w.other(end)
                    if (other[0] - end[0], other[1] - end[1]) == (end[0] - prev[0], end[1] - prev[1]):
                        nxt = (j, other)
                        break
                if nxt is None:
                    break
                used.add(nxt[0])
                if direction == 1:
                    chain.append(nxt[1])
                else:
                    chain.insert(0, nxt[1])
        runs.append(chain)
    return runs


def _body(kind: str, s: float, style: Style, rng: random.Random):
    if kind == "resistor":
        if style.resistor == "zigzag":
            return S.resistor_zigzag(s * rng.uniform(0.36, 0.46), s * rng.uniform(0.05, 0.075), rng.randint(3, 5), rounded=style.hand and rng.random() < 0.4)
        return S.resistor_box(s * rng.uniform(0.34, 0.44), s * rng.uniform(0.12, 0.16))
    if kind == "lamp":
        return S.lamp(s * rng.uniform(0.09, 0.12))
    if kind in ("voltage_source", "current_source"):
        return S.source_circle(s * rng.uniform(0.1, 0.13))
    if kind == "battery":
        return S.battery_plates(s * rng.uniform(0.04, 0.055), s * rng.uniform(0.09, 0.12), cells=1 if rng.random() < 0.7 else 2)
    if kind == "capacitor":
        return S.capacitor_plates(s * rng.uniform(0.045, 0.06), s * rng.uniform(0.09, 0.12))
    if kind == "inductor":
        return S.inductor_humps(s * rng.uniform(0.34, 0.44), rng.randint(3, 5), s * rng.uniform(0.06, 0.09), loops=style.hand and rng.random() < 0.3)
    if kind == "switch_open":
        return S.switch_open(s * rng.uniform(0.3, 0.38), s * rng.uniform(0.07, 0.11))
    if kind == "switch_closed":
        return S.switch_closed(s * rng.uniform(0.3, 0.38), s * 0.015)
    raise ValueError(kind)


def _marks(kind: str, s: float, style: Style, rng: random.Random) -> list[list[Point]]:
    r = s * 0.115
    if kind == "voltage_source":
        size = r * 0.32
        if style.source_marks == "inside":
            return S.plus_mark(r * 0.5, 0.0, size) + S.minus_mark(-r * 0.5, 0.0, size)
        return S.plus_mark(r * 1.55, -r * 0.9, size) + S.minus_mark(-r * 1.55, -r * 0.9, size)
    if kind == "current_source":
        return S.arrow(r * 1.3, r * 0.45)
    return []


def _place_labels(canvas: _Canvas, texts: list[TextLabel], e: Edge, box: list[float], orientation: str,
                  style: Style, rng: random.Random, width: int, height: int) -> None:
    font = load_font(style.font, style.font_size)
    name = e.id if e.show_name else None
    value = _value_text(e.kind, e.value, rng, style.hand) if (e.value is not None and e.show_value) else None
    if e.kind in ("switch_open", "switch_closed"):
        value = None
    if style.label_mode == "value_only" and value:
        name = None
    items: list[tuple[str, str]] = []
    if style.label_mode == "combined" and name and value:
        items.append((f"{name} = {value}" if rng.random() < 0.7 else f"{name}={value}", "combined"))
    else:
        if name:
            items.append((name, "name"))
        if value:
            items.append((value, "value"))
    if not items:
        return
    gap = style.font_size * 0.35
    layers = [(_text_layer(t, font, rng.uniform(-5, 5) if style.hand else 0.0), t, role) for t, role in items]
    sizes = [(l.width / SS, l.height / SS) for l, _, _ in layers]
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if orientation == "horizontal":
        above = rng.random() < 0.7
        total_h = sum(h for _, h in sizes) + gap * (len(sizes) - 1)
        y = (y0 - gap - total_h) if above else (y1 + gap)
        for (layer, text, role), (w, h) in zip(layers, sizes):
            x = cx - w / 2 + rng.uniform(-style.font_size * 0.3, style.font_size * 0.3)
            x = min(max(2.0, x), width - w - 2)
            yy = min(max(2.0, y), height - h - 2)
            canvas.paste_text(layer, int(x), int(yy))
            texts.append(TextLabel([x, yy, x + w, yy + h], text, role, e.id))
            y += h + gap
    else:
        right = rng.random() < 0.65
        total_h = sum(h for _, h in sizes) + gap * (len(sizes) - 1)
        y = cy - total_h / 2
        for (layer, text, role), (w, h) in zip(layers, sizes):
            x = (x1 + gap) if right else (x0 - gap - w)
            x = min(max(2.0, x), width - w - 2)
            yy = min(max(2.0, y), height - h - 2)
            canvas.paste_text(layer, int(x), int(yy))
            texts.append(TextLabel([x, yy, x + w, yy + h], text, role, e.id))
            y += h + gap


def _wrap(text: str, font, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for w in words:
        trial = (current + " " + w).strip()
        if font.getlength(trial) <= max_width or not current:
            current = trial
        else:
            lines.append(current)
            current = w
    if current:
        lines.append(current)
    return lines


def _with_geometry(lattice: LatticeCircuit, symbols: list[SymbolLabel], pos: dict, width: int, height: int) -> Circuit:
    circuit = lattice.circuit.renaming_nodes(lambda n: n)
    by_id = {sym.id: sym for sym in symbols if sym.cls != "ground"}
    for c in circuit.components:
        sym = by_id[c.id]
        x0, y0, x1, y1 = sym.box
        c.box = [x0 / width, y0 / height, x1 / width, y1 / height]
        c.orientation = sym.orientation
    # One representative point per node: a junction of that node, else the middle of its longest wire.
    node_points: dict[str, tuple[float, float]] = {}
    for node in circuit.nodes:
        pts = [p for p, n in lattice.node_of_point.items() if n == node]
        junctions = [p for p in pts if p in lattice.junctions]
        if junctions:
            p = min(junctions, key=lambda q: (pos[q][0], pos[q][1]))
            node_points[node] = pos[p]
            continue
        wires = [e for e in lattice.edges if e.is_wire and lattice.node_of_point[e.a] == node]
        if wires:
            e = max(wires, key=lambda w: math.dist(pos[w.a], pos[w.b]))
            a, b = pos[e.a], pos[e.b]
            node_points[node] = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        elif pts:
            node_points[node] = pos[pts[0]]
    circuit.node_points = {n: [x / width, y / height] for n, (x, y) in node_points.items()}
    return circuit
