"""From CircuitNet maps to the app's netlist: the reference implementation of the on-device assembler.

The Swift port follows the same steps:
1. decode symbol peaks -> boxes, class, polarity;
2. wire mask minus symbol/text boxes -> connected components = candidate nodes;
3. each terminal joins the component touching it; crossovers bridge opposite arms; grounds name "0";
4. OCR strings are parsed and attached to the nearest compatible symbol;
5. the JSON the app already decodes, plus a confidence for cloud escalation.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from ..classes import APP_KINDS, POLARITY, TRACER_CLASSES
from ..schema import Circuit, Component, Unknown, ValidationError, natural_key, node_letter
from ..textparse import FAMILY_FOR_KIND, parse_question, parse_text

Point = tuple[float, float]


@dataclass
class Detection:
    cls: str
    score: float
    box: list[float]              # px in the analysed image
    polarity: str                 # right | up | left | down
    polarity_probs: Optional[np.ndarray] = None
    class_probs: Optional[np.ndarray] = None   # symbol heat of every class at the peak cell

    @property
    def centre(self) -> Point:
        return (self.box[0] + self.box[2]) / 2, (self.box[1] + self.box[3]) / 2

    @property
    def horizontal(self) -> bool:
        """The current axis comes from the polarity head (right/left = horizontal) for every symbol:
        box shape misleads for circles and for capacitors/batteries whose plates run across the axis."""
        return self.polarity in ("right", "left")


@dataclass
class TextItem:
    box: list[float]
    text: str


@dataclass
class Assembly:
    circuit: Circuit
    confidence: float
    detections: list[Detection]
    nodes_px: dict[str, list[Point]] = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)
    attached_fraction: float = 0.0     # share of component terminals that found a wire


# ---------------------------------------------------------------------------- decoding

def _local_maxima(heat: np.ndarray) -> np.ndarray:
    """3x3 max-pool equality on [K, h, w]."""
    padded = np.pad(heat, ((0, 0), (1, 1), (1, 1)), constant_values=-1)
    stacked = np.stack([padded[:, dy:dy + heat.shape[1], dx:dx + heat.shape[2]] for dy in range(3) for dx in range(3)])
    return heat >= stacked.max(axis=0)


def decode_symbols(heat: np.ndarray, size: np.ndarray, offset: np.ndarray, polarity: np.ndarray, stride: int = 4,
                   threshold: float = 0.3, max_detections: int = 64) -> list[Detection]:
    """heat [K,h,w] probabilities, size/offset [2,h,w], polarity [4,h,w] probabilities."""
    peaks = _local_maxima(heat) & (heat >= threshold)
    ks, ys, xs = np.nonzero(peaks)
    scores = heat[ks, ys, xs]
    order = np.argsort(-scores)[:max_detections]
    dets: list[Detection] = []
    for i in order:
        k, y, x = int(ks[i]), int(ys[i]), int(xs[i])
        cx = (x + float(offset[0, y, x])) * stride
        cy = (y + float(offset[1, y, x])) * stride
        w = max(2.0, float(size[0, y, x]) * stride)
        h = max(2.0, float(size[1, y, x]) * stride)
        probs = polarity[:, y, x]
        det = Detection(TRACER_CLASSES[k], float(scores[i]), [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], POLARITY[int(np.argmax(probs))], probs.copy(), heat[:, y, x].copy())
        # suppress duplicates: another detection whose centre lies inside this box (or vice versa) and overlaps a lot
        if any(_iou(det.box, d.box) > 0.55 for d in dets):
            continue
        dets.append(det)
    return dets


def _iou(a: list[float], b: list[float]) -> float:
    ix0, iy0, ix1, iy1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    if inter == 0:
        return 0.0
    area = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / area if area > 0 else 0.0


# ---------------------------------------------------------------------------- connected components

def label_components(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """8-connected component labelling by merging horizontal runs (fast enough in pure numpy/python)."""
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    parent: list[int] = [0]
    prev_runs: list[tuple[int, int, int]] = []  # (x0, x1, label) of the previous row
    next_label = 1

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    for y in range(h):
        row = mask[y]
        if not row.any():
            prev_runs = []
            continue
        padded = np.concatenate([[0], row.astype(np.int8), [0]])
        diff = np.diff(padded)
        starts = np.nonzero(diff == 1)[0]
        ends = np.nonzero(diff == -1)[0]  # exclusive
        runs: list[tuple[int, int, int]] = []
        for x0, x1 in zip(starts, ends):
            lab = 0
            for px0, px1, pl in prev_runs:
                if px0 <= x1 and x0 <= px1:  # 8-connectivity: touching or overlapping incl. diagonals
                    if lab == 0:
                        lab = pl
                    else:
                        union(lab, pl)
            if lab == 0:
                lab = next_label
                parent.append(lab)
                next_label += 1
            labels[y, x0:x1] = lab
            runs.append((int(x0), int(x1), lab))
        prev_runs = runs
    # flatten
    lut = np.zeros(next_label, np.int32)
    remap: dict[int, int] = {}
    for lab in range(1, next_label):
        root = find(lab)
        if root not in remap:
            remap[root] = len(remap) + 1
        lut[lab] = remap[root]
    return lut[labels], len(remap)


# ---------------------------------------------------------------------------- assembly

def _dilate(mask: np.ndarray, r: int) -> np.ndarray:
    out = mask.copy()
    for _ in range(r):
        p = np.pad(out, 1)
        out = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:] | p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:]
    return out


def close_mask(mask: np.ndarray, r: int) -> np.ndarray:
    """Morphological closing (bridges 1-2 px gaps in predicted strokes)."""
    if r <= 0:
        return mask
    return ~_dilate(~_dilate(mask, r), r)


def _window_labels(labels: np.ndarray, x0: float, y0: float, x1: float, y1: float) -> np.ndarray:
    h, w = labels.shape
    xa, ya = max(0, int(math.floor(x0))), max(0, int(math.floor(y0)))
    xb, yb = min(w, int(math.ceil(x1))), min(h, int(math.ceil(y1)))
    if xa >= xb or ya >= yb:
        return np.zeros(0, np.int32)
    win = labels[ya:yb, xa:xb]
    return win[win > 0]


def _nearest_label(labels: np.ndarray, point: Point, reach: float) -> Optional[int]:
    """Label of the wire pixel closest to `point` within `reach` pixels."""
    h, w = labels.shape
    x0, y0 = max(0, int(point[0] - reach)), max(0, int(point[1] - reach))
    x1, y1 = min(w, int(point[0] + reach) + 1), min(h, int(point[1] + reach) + 1)
    if x0 >= x1 or y0 >= y1:
        return None
    win = labels[y0:y1, x0:x1]
    ys, xs = np.nonzero(win)
    if xs.size == 0:
        return None
    d2 = (xs + x0 - point[0]) ** 2 + (ys + y0 - point[1]) ** 2
    i = int(np.argmin(d2))
    return int(win[ys[i], xs[i]]) if d2[i] <= reach * reach else None


def _majority(values: np.ndarray) -> Optional[int]:
    if values.size == 0:
        return None
    ids, counts = np.unique(values, return_counts=True)
    return int(ids[np.argmax(counts)])


def _terminal_label(labels: np.ndarray, point: Point, direction: Point, radii: tuple[int, ...]) -> Optional[int]:
    """Looks for wire pixels just outside a box edge, in growing windows along `direction`."""
    px, py = point
    dx, dy = direction
    for r in radii:
        if dx != 0:   # horizontal search window beside a left/right terminal
            x0, x1 = (px, px + r) if dx > 0 else (px - r, px)
            y0, y1 = py - r, py + r
        else:
            y0, y1 = (py, py + r) if dy > 0 else (py - r, py)
            x0, x1 = px - r, px + r
        lab = _majority(_window_labels(labels, x0, y0, x1, y1))
        if lab is not None:
            return lab
    return None


def _terminals(det: Detection) -> list[tuple[Point, Point]]:
    x0, y0, x1, y1 = det.box
    cx, cy = det.centre
    if det.horizontal:
        return [((x0, cy), (-1.0, 0.0)), ((x1, cy), (1.0, 0.0))]
    return [((cx, y0), (0.0, -1.0)), ((cx, y1), (0.0, 1.0))]


def _peak_near(prob: np.ndarray, point: Point, reach: float) -> tuple[float, Point]:
    h, w = prob.shape
    x0, y0 = max(0, int(point[0] - reach)), max(0, int(point[1] - reach))
    x1, y1 = min(w, int(point[0] + reach) + 1), min(h, int(point[1] + reach) + 1)
    if x0 >= x1 or y0 >= y1:
        return 0.0, point
    win = prob[y0:y1, x0:x1]
    j = int(np.argmax(win))
    py, px = divmod(j, win.shape[1])
    return float(win[py, px]), (float(px + x0), float(py + y0))


def _refine_terminal(point: Point, direction: Point, prob: np.ndarray, reach: float) -> Point:
    """Snap a box-edge terminal to the terminal-heat peak nearby, staying on the box edge line."""
    score, peak = _peak_near(prob, point, reach)
    if score < 0.3:
        return point
    if direction[0] != 0:      # left/right edge: slide along y only
        return (point[0], peak[1])
    return (peak[0], point[1])  # top/bottom edge: slide along x only


def _settle_axis(det: Detection, prob: np.ndarray, reach: float) -> Detection:
    """When the polarity head is unsure, take the axis whose two edge midpoints carry more terminal heat."""
    probs = det.polarity_probs
    if probs is None or float(np.max(probs)) >= 0.6:
        return det
    x0, y0, x1, y1 = det.box
    cx, cy = det.centre
    horizontal = _peak_near(prob, (x0, cy), reach)[0] + _peak_near(prob, (x1, cy), reach)[0]
    vertical = _peak_near(prob, (cx, y0), reach)[0] + _peak_near(prob, (cx, y1), reach)[0]
    if abs(horizontal - vertical) < 0.2:
        return det
    if horizontal > vertical:
        polarity = "right" if probs[POLARITY.index("right")] >= probs[POLARITY.index("left")] else "left"
    else:
        polarity = "up" if probs[POLARITY.index("up")] >= probs[POLARITY.index("down")] else "down"
    return Detection(det.cls, det.score, det.box, polarity, det.polarity_probs)


def _positive_index(det: Detection, terminals) -> int:
    """Which terminal (0 or 1) the polarity points at."""
    want = {"right": (1.0, 0.0), "left": (-1.0, 0.0), "up": (0.0, -1.0), "down": (0.0, 1.0)}[det.polarity]
    return max(range(2), key=lambda i: terminals[i][1][0] * want[0] + terminals[i][1][1] * want[1])


def assemble(detections: list[Detection], wire_prob: np.ndarray, image_size: tuple[int, int], ocr: Optional[list[TextItem]] = None,  # noqa: C901
             junction_prob: Optional[np.ndarray] = None, wire_threshold: float = 0.5, min_component_px: int = 12,
             box_margin: float = 1.5, closing: int = -1, terminal_prob: Optional[np.ndarray] = None,
             body_removal: str = "span", unit_kinds: bool = True) -> Assembly:
    W, H = image_size
    scale = max(W, H) / 640.0
    radii = tuple(int(round(r * scale)) for r in (3, 6, 10, 16, 24))
    notes: list[str] = []
    comps = [d for d in detections if d.cls in APP_KINDS]
    grounds = [d for d in detections if d.cls == "ground"]
    crossovers = [d for d in detections if d.cls == "crossover"]
    others = [d for d in detections if d.cls == "other"]
    model_texts = [d for d in detections if d.cls == "text"]

    if closing < 0:
        closing = max(1, int(round(max(W, H) / 160)))
    wire = close_mask(wire_prob >= wire_threshold, closing)
    if terminal_prob is not None:
        comps = [_settle_axis(d, terminal_prob, radii[-1]) for d in comps]
    for d in comps + grounds + crossovers + others:
        x0, y0, x1, y1 = d.box
        m = box_margin
        if d.cls in APP_KINDS and body_removal == "span":
            # the body is whatever lies between the two terminals; extend the box to them
            for (pt, direction) in _terminals(d):
                if terminal_prob is not None:
                    pt = _refine_terminal(pt, direction, terminal_prob, radii[2])
                x0, y0, x1, y1 = min(x0, pt[0]), min(y0, pt[1]), max(x1, pt[0]), max(y1, pt[1])
            if d.horizontal:
                y0, y1 = y0 - 0.15 * (y1 - y0), y1 + 0.15 * (y1 - y0)
            else:
                x0, x1 = x0 - 0.15 * (x1 - x0), x1 + 0.15 * (x1 - x0)
        wire[max(0, int(y0 - m)):min(H, int(math.ceil(y1 + m))), max(0, int(x0 - m)):min(W, int(math.ceil(x1 + m)))] = False
    labels, count = label_components(wire)
    if count:
        sizes = np.bincount(labels.ravel(), minlength=count + 1)
        small = np.nonzero(sizes < min_component_px)[0]
        if small.size:
            labels[np.isin(labels, small)] = 0

    parent = list(range(count + 1))

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    # Crossovers bridge left<->right and top<->bottom arms.
    for d in crossovers:
        x0, y0, x1, y1 = d.box
        cx, cy = d.centre
        arms = {
            "left": _terminal_label(labels, (x0, cy), (-1.0, 0.0), radii), "right": _terminal_label(labels, (x1, cy), (1.0, 0.0), radii),
            "top": _terminal_label(labels, (cx, y0), (0.0, -1.0), radii), "bottom": _terminal_label(labels, (cx, y1), (0.0, 1.0), radii),
        }
        if arms["left"] and arms["right"]:
            union(arms["left"], arms["right"])
        if arms["top"] and arms["bottom"]:
            union(arms["top"], arms["bottom"])

    # Component terminals (snapped to terminal-heat peaks: leads rarely leave a box exactly mid-edge).
    attachments: list[list[Optional[int]]] = []
    free_terminals: list[tuple[int, int, Point]] = []
    for ci, d in enumerate(comps):
        labs: list[Optional[int]] = []
        for k, (pt, direction) in enumerate(_terminals(d)):
            if terminal_prob is not None:
                pt = _refine_terminal(pt, direction, terminal_prob, radii[2])
            lab = _terminal_label(labels, pt, direction, radii)
            if lab is None:
                # predicted masks can leave a gap where a lead meets the body: take the nearest wire pixel
                reach = 0.5 * max(d.box[2] - d.box[0], d.box[3] - d.box[1])
                lab = _nearest_label(labels, pt, max(reach, radii[1]))
            labs.append(lab)
            if lab is None:
                free_terminals.append((ci, k, pt))
        attachments.append(labs)
    # Terminals that touch another symbol directly (no wire between) share a fresh node.
    extra = count
    for i, (ci, k, pt) in enumerate(free_terminals):
        if attachments[ci][k] is not None:
            continue
        extra += 1
        parent.append(extra)
        attachments[ci][k] = extra
        for cj, kj, qt in free_terminals[i + 1:]:
            if attachments[cj][kj] is None and math.dist(pt, qt) <= radii[-1]:
                attachments[cj][kj] = extra

    # Ground symbols.
    ground_root: Optional[int] = None
    for d in grounds:
        x0, y0, x1, y1 = d.box
        cx, _ = d.centre
        lab = _terminal_label(labels, (cx, y0), (0.0, -1.0), radii) or _terminal_label(labels, ((x0 + x1) / 2, y1), (0.0, 1.0), radii)
        if lab is None:
            continue
        if ground_root is None:
            ground_root = lab
        else:
            union(ground_root, lab)

    # Nodes.
    roots: dict[int, str] = {}
    node_pixels: dict[str, list[Point]] = {}
    for labs in attachments:
        for lab in labs:
            if lab is not None:
                roots.setdefault(find(lab), "")
    ground_name = None
    if ground_root is not None and find(ground_root) in roots:
        ground_name = find(ground_root)
    # left-to-right order by the node's mean x over wire pixels (fresh nodes use their terminal)
    centroids: dict[int, Point] = {}
    for root in roots:
        members = [lab for lab in range(1, count + 1) if find(lab) == root]
        if members:
            ys, xs = np.nonzero(np.isin(labels, members))
            centroids[root] = (float(xs.mean()), float(ys.mean())) if xs.size else (0.0, 0.0)
            node_pixels[root] = list(zip(xs.astype(float), ys.astype(float)))
        else:
            pts = [pt for ci, labs in enumerate(attachments) for k, lab in enumerate(labs) if lab is not None and find(lab) == root for pt, _ in [_terminals(comps[ci])[k]]]
            centroids[root] = pts[0] if pts else (0.0, 0.0)
            node_pixels[root] = pts
    order = sorted(roots, key=lambda r: (centroids[r][0], centroids[r][1]))
    letter = 0
    for root in order:
        if root == ground_name:
            roots[root] = "0"
        else:
            roots[root] = node_letter(letter)
            letter += 1

    # OCR: values and names are assigned globally (closest pairs first), one value and one name per symbol.
    names: dict[int, str] = {}
    values: dict[int, float] = {}
    question_lines: list[str] = []
    node_letters: dict[str, str] = {}
    value_candidates: list[tuple[float, int, int]] = []   # (distance, text index, component index)
    name_candidates: list[tuple[float, int, int]] = []
    parsed_texts = []
    if ocr:
        for ti, t in enumerate(ocr):
            parsed = parse_text(t.text)
            parsed_texts.append(parsed)
            tc = ((t.box[0] + t.box[2]) / 2, (t.box[1] + t.box[3]) / 2)
            if parsed.kind == "question":
                question_lines.append(t.text.strip())
            elif parsed.kind == "value":
                for ci, dist in _component_distances(comps, tc, parsed.family):
                    value_candidates.append((dist, ti, ci))
                    if parsed.name:
                        name_candidates.append((dist, ti, ci))
            elif parsed.kind == "name":
                for ci, dist in _component_distances(comps, tc, None):
                    # a name's prefix says what it can name: "I.." is a current (source or annotation), never a resistor
                    if not _name_fits(parsed.name, comps[ci].cls):
                        dist *= 4.0
                    name_candidates.append((dist, ti, ci))
            elif len(t.text.strip()) == 1 and t.text.strip().islower() and count:
                reach = max(radii[-1], 2.0 * (t.box[3] - t.box[1]), 2.0 * (t.box[2] - t.box[0]))
                lab = _nearest_label(labels, tc, reach)
                if lab is not None and find(lab) in roots and roots[find(lab)] != "0":
                    node_letters[roots[find(lab)]] = t.text.strip()
        used_values: set[int] = set()
        used_names: set[int] = set()
        value_dist: dict[int, float] = {}
        for dist, ti, ci in sorted(value_candidates):
            if ti in used_values or ci in values or dist > 4.0:
                continue
            used_values.add(ti)
            values[ci] = parsed_texts[ti].value
            value_dist[ci] = dist
            if parsed_texts[ti].name and ci not in names:
                names[ci] = parsed_texts[ti].name
                used_names.add(ti)
        for dist, ti, ci in sorted(name_candidates):
            if ti in used_names or ci in names or dist > 4.0:
                continue
            if parsed_texts[ti].kind == "value" and parsed_texts[ti].name is None:
                continue
            used_names.add(ti)
            names[ci] = parsed_texts[ti].name
        # Whatever is neither a value, a name nor a node letter belongs to the problem statement.
        leftovers = [(ocr[ti].box[1], ocr[ti].box[0], ocr[ti].text.strip()) for ti, parsed in enumerate(parsed_texts)
                     if parsed.kind == "other" and len(ocr[ti].text.strip()) > 3]
        question_lines = [(ocr[ti].box[1], ocr[ti].box[0], ocr[ti].text.strip()) for ti, parsed in enumerate(parsed_texts) if parsed.kind == "question"] + leftovers
        question_lines = [text for _, _, text in sorted(question_lines)]
    # Respect drawn node letters when they are unique; the other nodes take the remaining letters
    # in left-to-right order, so no two nodes ever share a name.
    if node_letters and len(set(node_letters.values())) == len(node_letters):
        drawn = {root: node_letters[name] for root, name in roots.items() if name in node_letters}
        used = set(drawn.values())
        renamed: dict[int, str] = {}
        i = 0
        for root in order:
            name = roots[root]
            if name == "0":
                renamed[root] = "0"
            elif root in drawn:
                renamed[root] = drawn[root]
            else:
                while node_letter(i) in used:
                    i += 1
                renamed[root] = node_letter(i)
                used.add(node_letter(i))
        roots = renamed

    # A read unit outranks the detector's kind: "12 V" cannot sit on a current source. Within the
    # unit's family, the class the detector scored highest is kept (voltage source vs battery).
    family_kinds = {"resistance": ["resistor", "lamp"], "voltage": ["voltage_source", "battery"], "current": ["current_source"],
                    "capacitance": ["capacitor"], "inductance": ["inductor"]}
    for ci, value in (list(values.items()) if unit_kinds else []):
        ti = next((t for t, parsed in enumerate(parsed_texts) if parsed.kind == "value" and parsed.value == value and parsed.family), None)
        family = parsed_texts[ti].family if ti is not None else None
        kinds = family_kinds.get(family or "")
        d = comps[ci]
        if not kinds or d.cls in kinds or d.class_probs is None:
            continue   # no unit evidence, or a detector with no class distribution (ground truth) is trusted
        dist = value_dist.get(ci, 4.0)
        certainty = float(d.class_probs[TRACER_CLASSES.index(d.cls)])
        # a label right next to the symbol outranks the detector; a far label only when the detector is unsure
        if dist <= (1.8 if certainty >= 0.9 else 3.0):
            best = max(kinds, key=lambda k: float(d.class_probs[TRACER_CLASSES.index(k)]))
            comps[ci] = Detection(best, d.score, d.box, d.polarity, d.polarity_probs, d.class_probs)
            notes.append(f"kind set by unit: {d.cls} -> {best}")

    # Ids in reading order per kind for unnamed components.
    prefix = {"resistor": "R", "voltage_source": "V", "current_source": "I", "battery": "V", "capacitor": "C", "inductor": "L", "lamp": "Lp", "switch_open": "S", "switch_closed": "S"}
    counters: dict[str, int] = {}
    used = set(names.values())
    ids: dict[int, str] = dict(names)
    for ci in sorted(range(len(comps)), key=lambda i: (round(comps[i].centre[1] / (40 * scale)), comps[i].centre[0])):
        if ci in ids:
            continue
        p = prefix[comps[ci].cls]
        while True:
            counters[p] = counters.get(p, 0) + 1
            cand = f"{p}{counters[p]}"
            if cand not in used:
                break
        ids[ci] = cand
        used.add(cand)

    components: list[Component] = []
    connected = 0
    for ci, d in enumerate(comps):
        labs = attachments[ci]
        terms = _terminals(d)
        node_names = [roots.get(find(lab)) if lab is not None else None for lab in labs]
        connected += sum(1 for n in node_names if n)
        a, b = node_names
        if d.cls in ("voltage_source", "battery", "current_source"):
            pos = _positive_index(d, terms)
            if d.cls == "current_source":
                a, b = node_names[1 - pos], node_names[pos]   # current flows from -> to (arrow head)
            else:
                a, b = node_names[pos], node_names[1 - pos]
        value = values.get(ci)
        if value is None and d.cls in ("switch_open", "switch_closed", "capacitor", "inductor"):
            value = 0.0
        components.append(Component(ids[ci], d.cls, value, a or f"?{ci}a", b or f"?{ci}b",
                                    [d.box[0] / W, d.box[1] / H, d.box[2] / W, d.box[3] / H], "horizontal" if d.horizontal else "vertical"))

    circuit = Circuit(components=components, ground_node="0")
    if ground_name is None:
        vs = [c for c in components if c.kind in ("voltage_source", "battery")]
        if vs:
            fallback = sorted(vs, key=lambda c: natural_key(c.id))[0].node_b
        elif components:
            counts: dict[str, int] = {}
            for c in components:
                counts[c.node_a] = counts.get(c.node_a, 0) + 1
                counts[c.node_b] = counts.get(c.node_b, 0) + 1
            fallback = max(counts, key=counts.get)
        else:
            fallback = "0"
        if fallback != "0":
            # rename: fallback -> "0", and shift letters so a, b, c... stay contiguous
            others_sorted = sorted({n for c in components for n in (c.node_a, c.node_b) if n != fallback and not n.startswith("?")}, key=natural_key)
            mapping = {fallback: "0"}
            for i, n in enumerate(others_sorted):
                mapping[n] = node_letter(i)
            circuit = circuit.renaming_nodes(lambda n: mapping.get(n, n))
    circuit.unsupported = [f"X{i + 1} (unsupported symbol)" for i, _ in enumerate(others)]
    circuit.question = " ".join(question_lines) if question_lines else None
    circuit.unknowns = [Unknown(**u) for u in parse_question(circuit.question or "")]
    # node points: junction peak inside the node if available, else the wire pixel nearest the centroid
    node_points: dict[str, list[float]] = {}
    for root, name in roots.items():
        pts = node_pixels.get(root, [])
        if not pts:
            continue
        best = None
        if junction_prob is not None and len(pts) > 0:
            arr = np.array(pts)
            xs, ys = arr[:, 0].astype(int).clip(0, W - 1), arr[:, 1].astype(int).clip(0, H - 1)
            j = junction_prob[ys, xs]
            if j.max() > 0.3:
                best = pts[int(np.argmax(j))]
        if best is None:
            cx, cy = centroids[root]
            best = min(pts, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
        final_name = circuit.ground_node if name == "0" else name
        node_points[final_name] = [best[0] / W, best[1] / H]
    circuit.node_points = {n: p for n, p in node_points.items() if n in circuit.nodes}

    total_terms = 2 * len(comps)
    conf = (min([d.score for d in comps], default=0.0)) * (connected / total_terms if total_terms else 0.0)
    missing = [c.id for c in components if c.value is None and c.kind in ("resistor", "lamp", "voltage_source", "battery", "current_source")]
    if missing:
        conf *= 0.6
        notes.append("values missing: " + ", ".join(missing))
    try:
        circuit.validated()
    except ValidationError as exc:
        conf *= 0.5
        notes.append(f"validation: {exc}")
    circuit.confidence = round(conf, 3)
    circuit.notes = "; ".join(notes) if notes else None
    return Assembly(circuit, conf, detections, {name: node_pixels.get(root, []) for root, name in roots.items()}, notes,
                    attached_fraction=(connected / total_terms if total_terms else 0.0))


_NAME_PREFIX_KINDS = {
    "R": {"resistor"}, "V": {"voltage_source", "battery"}, "E": {"battery", "voltage_source"}, "B": {"battery"},
    "I": {"current_source"}, "C": {"capacitor"}, "L": {"inductor", "lamp"}, "S": {"switch_open", "switch_closed"},
}


def _name_fits(name: str, cls: str) -> bool:
    letters = "".join(ch for ch in name if ch.isalpha())
    if letters.lower().startswith("lp"):
        return cls == "lamp"
    if not letters:
        return True
    kinds = _NAME_PREFIX_KINDS.get(letters[0].upper())
    return kinds is None or cls in kinds


def _component_distances(comps: list[Detection], point: Point, family: Optional[str]) -> list[tuple[int, float]]:
    """Distance from a text centre to every symbol, in units of the symbol's size; incompatible units cost 3x."""
    out = []
    for i, d in enumerate(comps):
        cx, cy = d.centre
        size = max(d.box[2] - d.box[0], d.box[3] - d.box[1], 1.0)
        dist = math.hypot(point[0] - cx, point[1] - cy) / size
        if family is not None and FAMILY_FOR_KIND.get(d.cls) != family:
            dist *= 3.0
        out.append((i, dist))
    return out
