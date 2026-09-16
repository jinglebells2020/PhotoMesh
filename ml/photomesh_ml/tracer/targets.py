"""Training targets at stride 4 from a record whose geometry is already in input-image pixels."""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

import numpy as np

from ..classes import CLASS_INDEX, POLARITY_INDEX, TRACER_CLASSES
from ..data.records import Record, Symbol


@dataclass
class Targets:
    heat: np.ndarray          # [K, h, w] symbol centre Gaussians
    heat_weight: np.ndarray   # [K, h, w] 0 inside ignore regions
    size: np.ndarray          # [N, 2] (w, h) in stride units for each positive
    offset: np.ndarray        # [N, 2]
    index: np.ndarray         # [N] flat index (y * w + x) of each positive centre
    polarity: np.ndarray      # [N, 4] soft distribution
    polarity_weight: np.ndarray  # [N]
    wire: np.ndarray          # [1, h, w]
    wire_weight: float        # 0 when the sample has no wire supervision
    junction: np.ndarray      # [1, h, w]
    junction_weight: float
    terminal: np.ndarray      # [1, h, w]
    terminal_weight: float


def gaussian_radius(height: float, width: float, min_overlap: float = 0.7) -> float:
    """CenterNet's radius so that any box centre inside it still overlaps the truth by min_overlap."""
    a1 = 1
    b1 = height + width
    c1 = width * height * (1 - min_overlap) / (1 + min_overlap)
    r1 = (b1 + math.sqrt(b1 ** 2 - 4 * a1 * c1)) / 2
    a2 = 4
    b2 = 2 * (height + width)
    c2 = (1 - min_overlap) * width * height
    r2 = (b2 + math.sqrt(b2 ** 2 - 4 * a2 * c2)) / 2
    a3 = 4 * min_overlap
    b3 = -2 * min_overlap * (height + width)
    c3 = (min_overlap - 1) * width * height
    r3 = (b3 + math.sqrt(b3 ** 2 - 4 * a3 * c3)) / 2
    return max(0.0, min(r1, r2, r3))


def draw_gaussian(heat: np.ndarray, cx: int, cy: int, radius: float) -> None:
    """Max-composites a 2D Gaussian (peak 1) centred at an integer cell."""
    r = max(int(radius), 0)
    sigma = (2 * r + 1) / 6.0
    h, w = heat.shape
    y0, y1 = max(0, cy - r), min(h, cy + r + 1)
    x0, x1 = max(0, cx - r), min(w, cx + r + 1)
    if y0 >= y1 or x0 >= x1:
        return
    ys = np.arange(y0, y1)[:, None] - cy
    xs = np.arange(x0, x1)[None, :] - cx
    g = np.exp(-(xs ** 2 + ys ** 2) / (2 * sigma ** 2))
    heat[y0:y1, x0:x1] = np.maximum(heat[y0:y1, x0:x1], g)


def build_targets(record: Record, input_size: tuple[int, int], stride: int = 4, wire_mask: Optional[np.ndarray] = None,
                  point_radius: float = 1.5) -> Targets:
    """`record` symbols/junctions must already be in input pixels; `wire_mask` is HxW uint8 at input size."""
    W, H = input_size
    w, h = W // stride, H // stride
    K = len(TRACER_CLASSES)
    heat = np.zeros((K, h, w), np.float32)
    heat_weight = np.ones((K, h, w), np.float32)
    sizes, offsets, indices, polarities, pol_weights = [], [], [], [], []
    for s in record.symbols:
        x0, y0, x1, y1 = s.box
        bw, bh = (x1 - x0) / stride, (y1 - y0) / stride
        if bw <= 0 or bh <= 0:
            continue
        cx, cy = (x0 + x1) / 2 / stride, (y0 + y1) / 2 / stride
        ci, cj = int(cx), int(cy)
        if not (0 <= ci < w and 0 <= cj < h):
            continue
        if s.class_candidates:
            for name in s.class_candidates:
                k = CLASS_INDEX[name]
                heat_weight[k, max(0, int(y0 / stride)):int(math.ceil(y1 / stride)), max(0, int(x0 / stride)):int(math.ceil(x1 / stride))] = 0.0
            continue
        radius = max(0.0, gaussian_radius(bh, bw))
        draw_gaussian(heat[CLASS_INDEX[s.cls]], ci, cj, radius)
        sizes.append([bw, bh])
        offsets.append([cx - ci, cy - cj])
        indices.append(cj * w + ci)
        dist = np.zeros(4, np.float32)
        if s.polarity is not None:
            dist[POLARITY_INDEX[s.polarity]] = 1.0
            pol_weights.append(1.0)
        elif s.polarity_candidates:
            for name in s.polarity_candidates:
                dist[POLARITY_INDEX[name]] = 1.0 / len(s.polarity_candidates)
            pol_weights.append(1.0)
        else:
            pol_weights.append(0.0)
        polarities.append(dist)

    wire = np.zeros((1, h, w), np.float32)
    wire_weight = 0.0
    if wire_mask is not None:
        m = wire_mask[:h * stride, :w * stride].reshape(h, stride, w, stride).max(axis=(1, 3))
        wire[0] = (m > 127).astype(np.float32)
        wire_weight = 1.0

    junction = np.zeros((1, h, w), np.float32)
    junction_weight = 0.0
    if record.junctions is not None:
        for x, y in record.junctions:
            draw_gaussian(junction[0], int(x / stride), int(y / stride), point_radius)
        junction_weight = 1.0

    terminal = np.zeros((1, h, w), np.float32)
    terminal_weight = 0.0
    if record.has_terminal_supervision:
        for s in record.symbols:
            for x, y in (s.terminals or []):
                draw_gaussian(terminal[0], int(x / stride), int(y / stride), point_radius)
        terminal_weight = 1.0

    n = len(indices)
    return Targets(
        heat=heat, heat_weight=heat_weight,
        size=np.array(sizes, np.float32).reshape(n, 2), offset=np.array(offsets, np.float32).reshape(n, 2),
        index=np.array(indices, np.int64), polarity=np.array(polarities, np.float32).reshape(n, 4),
        polarity_weight=np.array(pol_weights, np.float32),
        wire=wire, wire_weight=wire_weight, junction=junction, junction_weight=junction_weight,
        terminal=terminal, terminal_weight=terminal_weight,
    )
