"""Stroke geometry for circuit symbols, clean or with a hand-drawn wobble.

All primitives return polylines (lists of (x, y) floats) in a local frame where the element's
current axis is +x and (0, 0) is the element centre; `place()` rotates/translates them.
"""
from __future__ import annotations

import math
import random
from typing import Iterable, Sequence

Point = tuple[float, float]
Polyline = list[Point]


def place(lines: Iterable[Polyline], centre: Point, angle: float) -> list[Polyline]:
    """Rotates by `angle` radians (image coordinates, y down) and moves to `centre`."""
    c, s = math.cos(angle), math.sin(angle)
    cx, cy = centre
    return [[(cx + x * c - y * s, cy + x * s + y * c) for x, y in line] for line in lines]


def resample(line: Sequence[Point], step: float) -> Polyline:
    """Points every `step` pixels along the polyline; the original endpoints are kept."""
    pts = [tuple(p) for p in line]
    if len(pts) < 2 or step <= 0:
        return pts
    out: Polyline = [pts[0]]
    remaining = step
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg == 0:
            continue
        t = remaining
        while t < seg:
            out.append((x0 + (x1 - x0) * t / seg, y0 + (y1 - y0) * t / seg))
            t += step
        remaining = t - seg
    if out[-1] != pts[-1]:
        out.append(pts[-1])
    return out


def wobble(line: Sequence[Point], rng: random.Random, amplitude: float, step: float = 4.0,
           overshoot: float = 0.0, waves: int = 3) -> Polyline:
    """Hand-drawn look: low-frequency drift plus fine tremor along the stroke, optional overshoot.

    The endpoints are kept (so wires still meet) unless `overshoot` extends them a little.
    """
    pts = resample(line, step)
    n = len(pts)
    if n < 3:
        return list(pts)
    length = sum(math.hypot(x1 - x0, y1 - y0) for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]))
    if length == 0:
        return list(pts)
    phases = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.5, 2.5), rng.uniform(0.3, 1.0)) for _ in range(waves)]
    out: Polyline = []
    dist = 0.0
    for i, (x, y) in enumerate(pts):
        if i > 0:
            px, py = pts[i - 1]
            dist += math.hypot(x - px, y - py)
        # normal direction from the local tangent
        j0, j1 = max(i - 1, 0), min(i + 1, n - 1)
        tx, ty = pts[j1][0] - pts[j0][0], pts[j1][1] - pts[j0][1]
        tl = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / tl, tx / tl
        u = dist / length
        env = math.sin(math.pi * u) ** 0.5 if overshoot == 0 else 1.0  # keep the ends in place
        drift = sum(a * math.sin(2 * math.pi * f * u + p) for p, f, a in phases) / waves
        tremor = rng.gauss(0, 0.25)
        off = amplitude * (drift * env + 0.35 * tremor)
        out.append((x + nx * off, y + ny * off))
    if overshoot > 0:
        (x0, y0), (x1, y1) = out[0], out[1]
        d = math.hypot(x1 - x0, y1 - y0) or 1.0
        o = rng.uniform(0, overshoot)
        out[0] = (x0 - (x1 - x0) / d * o, y0 - (y1 - y0) / d * o)
        (x0, y0), (x1, y1) = out[-2], out[-1]
        d = math.hypot(x1 - x0, y1 - y0) or 1.0
        o = rng.uniform(0, overshoot)
        out[-1] = (x1 + (x1 - x0) / d * o, y1 + (y1 - y0) / d * o)
    return out


# ----------------------------------------------------------------------------- symbol bodies
# Each returns (lines, half_length, half_height): the body spans x in [-half_length, half_length].

def resistor_zigzag(length: float, amplitude: float, peaks: int = 4, rounded: bool = False) -> tuple[list[Polyline], float, float]:
    h = length / 2
    n = peaks * 2
    pts: Polyline = [(-h, 0.0)]
    dx = length / n
    for i in range(1, n):
        x = -h + i * dx
        y = amplitude if i % 2 == 1 else -amplitude
        pts.append((x, y))
    pts.append((h, 0.0))
    if rounded:
        pts = _round_corners(pts, 0.35)
    return [pts], h, amplitude


def resistor_box(length: float, height: float) -> tuple[list[Polyline], float, float]:
    h, v = length / 2, height / 2
    return [[(-h, -v), (h, -v), (h, v), (-h, v), (-h, -v)]], h, v


def inductor_humps(length: float, humps: int = 4, height: float = 10.0, loops: bool = False) -> tuple[list[Polyline], float, float]:
    h = length / 2
    w = length / humps
    pts: Polyline = []
    for k in range(humps):
        x0 = -h + k * w
        steps = 10
        for i in range(steps + 1):
            t = i / steps
            if loops:
                # cursive loop: a little backwards curl at the top of every hump
                x = x0 + w * t - 0.25 * w * math.sin(2 * math.pi * t)
                y = -height * math.sin(math.pi * t)
            else:
                x = x0 + w * t
                y = -height * math.sin(math.pi * t)
            if pts and i == 0:
                continue
            pts.append((x, y))
    return [pts], h, height


def circle(radius: float, segments: int = 40, gap: float = 0.0, start: float = 0.0) -> Polyline:
    n = segments
    total = 2 * math.pi - gap
    return [(radius * math.cos(start + total * i / n), radius * math.sin(start + total * i / n)) for i in range(n + 1)]


def source_circle(radius: float) -> tuple[list[Polyline], float, float]:
    return [circle(radius)], radius, radius


def plus_mark(cx: float, cy: float, size: float) -> list[Polyline]:
    return [[(cx - size, cy), (cx + size, cy)], [(cx, cy - size), (cx, cy + size)]]


def minus_mark(cx: float, cy: float, size: float) -> list[Polyline]:
    return [[(cx - size, cy), (cx + size, cy)]]


def arrow(length: float, head: float, y: float = 0.0) -> list[Polyline]:
    """Arrow along +x centred at the origin (current source: points to the 'to' terminal)."""
    h = length / 2
    return [[(-h, y), (h, y)], [(h - head, y - head * 0.6), (h, y)], [(h - head, y + head * 0.6), (h, y)]]


def capacitor_plates(gap: float, plate: float) -> tuple[list[Polyline], float, float]:
    g = gap / 2
    return [[(-g, -plate), (-g, plate)], [(g, -plate), (g, plate)]], g, plate


def battery_plates(gap: float, long_plate: float, cells: int = 1) -> tuple[list[Polyline], float, float]:
    """Long thin plate on the +x side is positive (drawn first at the left, so the caller flips)."""
    lines: list[Polyline] = []
    pitch = gap
    x = -pitch * (2 * cells - 1) / 2
    for _ in range(cells):
        lines.append([(x, -long_plate * 0.5), (x, long_plate * 0.5)])  # short plate (negative)
        x += pitch
        lines.append([(x, -long_plate), (x, long_plate)])              # long plate (positive)
        x += pitch
    half = pitch * (2 * cells - 1) / 2
    return lines, half, long_plate


def switch_open(length: float, lift: float) -> tuple[list[Polyline], float, float]:
    h = length / 2
    blade_end = (h * 0.75, -lift)
    return [[(-h, 0.0), blade_end]], h, lift


def switch_closed(length: float, tilt: float = 0.0) -> tuple[list[Polyline], float, float]:
    h = length / 2
    return [[(-h, 0.0), (h, -tilt)]], h, max(tilt, 1.0)


def lamp(radius: float) -> tuple[list[Polyline], float, float]:
    k = radius / math.sqrt(2)
    return [circle(radius), [(-k, -k), (k, k)], [(-k, k), (k, -k)]], radius, radius


def ground_symbol(width: float, spacing: float, stub: float) -> tuple[list[Polyline], float, float]:
    """Vertical stub from the attach point at (0, 0) downwards, then three shrinking bars."""
    lines: list[Polyline] = [[(0.0, 0.0), (0.0, stub)]]
    y = stub
    for k, frac in enumerate((1.0, 0.62, 0.28)):
        w = width * frac / 2
        lines.append([(-w, y), (w, y)])
        y += spacing
    return lines, width / 2, y


def dot(radius: float, segments: int = 16) -> Polyline:
    return circle(radius, segments)


def _round_corners(pts: Polyline, amount: float) -> Polyline:
    if len(pts) < 3:
        return pts
    out: Polyline = [pts[0]]
    for i in range(1, len(pts) - 1):
        (x0, y0), (x1, y1), (x2, y2) = pts[i - 1], pts[i], pts[i + 1]
        out.append((x1 + (x0 - x1) * amount, y1 + (y0 - y1) * amount))
        out.append((x1 + (x2 - x1) * amount, y1 + (y2 - y1) * amount))
    out.append(pts[-1])
    return out


def bounds(lines: Iterable[Polyline]) -> tuple[float, float, float, float]:
    xs = [x for line in lines for x, _ in line]
    ys = [y for line in lines for _, y in line]
    return min(xs), min(ys), max(xs), max(ys)
