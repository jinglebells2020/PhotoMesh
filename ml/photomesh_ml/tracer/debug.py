"""Overlay of an assembly result: wire pixels coloured per node, symbol boxes, terminals, ids."""
from __future__ import annotations

import colorsys

import numpy as np
from PIL import Image, ImageDraw

from .assemble import Assembly, _terminals


def render_assembly(image: Image.Image, assembly: Assembly) -> Image.Image:
    img = image.convert("RGB").copy()
    arr = np.asarray(img).copy()
    names = sorted(assembly.nodes_px)
    for i, name in enumerate(names):
        h = (i * 0.618) % 1.0
        r, g, b = [int(255 * v) for v in colorsys.hsv_to_rgb(h, 0.9, 0.9)]
        for x, y in assembly.nodes_px[name]:
            xi, yi = int(x), int(y)
            if 0 <= yi < arr.shape[0] and 0 <= xi < arr.shape[1]:
                arr[max(0, yi - 1):yi + 2, max(0, xi - 1):xi + 2] = (r, g, b)
    img = Image.fromarray(arr)
    d = ImageDraw.Draw(img)
    for det in assembly.detections:
        x0, y0, x1, y1 = det.box
        d.rectangle([x0, y0, x1, y1], outline=(255, 0, 0) if det.cls != "text" else (255, 200, 0), width=2)
        d.text((x0, max(0, y0 - 11)), f"{det.cls[:6]} {det.polarity}", fill=(255, 0, 0))
        if det.cls in ("resistor", "voltage_source", "current_source", "battery", "capacitor", "inductor", "lamp", "switch_open", "switch_closed"):
            for (px, py), _ in _terminals(det):
                d.ellipse([px - 4, py - 4, px + 4, py + 4], outline=(0, 0, 255), width=2)
    for c in assembly.circuit.components:
        if c.box:
            w, h = img.size
            d.text((c.box[0] * w, c.box[3] * h + 2), f"{c.id}: {c.node_a}-{c.node_b}", fill=(0, 0, 160))
    for name, pts in assembly.nodes_px.items():
        if pts:
            x, y = pts[len(pts) // 2]
            d.text((x + 4, y + 4), name, fill=(0, 120, 0))
    return img
