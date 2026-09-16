"""Draws a label overlay (boxes, terminals, junctions, node points, wire mask) for eyeballing data.

    python -m photomesh_ml.synth.preview --data data/synth --out preview.png --count 12
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

COLORS = {"resistor": (220, 40, 40), "voltage_source": (40, 120, 220), "current_source": (30, 160, 160), "battery": (120, 60, 200),
          "capacitor": (230, 140, 20), "inductor": (20, 150, 60), "lamp": (200, 120, 200), "switch_open": (120, 120, 120),
          "switch_closed": (80, 80, 80), "ground": (0, 0, 0), "crossover": (255, 0, 255), "text": (255, 200, 0), "other": (128, 0, 0)}


def overlay(label: dict, root: Path, show_mask: bool = True) -> Image.Image:
    img = Image.open(root / label["image"]).convert("RGB")
    if show_mask and label.get("mask"):
        mask = Image.open(root / label["mask"]).convert("L")
        tint = Image.new("RGB", img.size, (0, 200, 255))
        img = Image.composite(tint, img, mask.point(lambda v: 110 if v > 0 else 0))
    d = ImageDraw.Draw(img)
    sup = label["supervision"]
    for s in sup["symbols"]:
        x0, y0, x1, y1 = s["box"]
        d.rectangle([x0, y0, x1, y1], outline=COLORS.get(s["cls"], (255, 0, 0)), width=2)
        d.text((x0, max(0, y0 - 12)), f"{s['id']} {s['cls'][:8]} {s['polarity']}", fill=COLORS.get(s["cls"], (255, 0, 0)))
        for tx, ty in s["terminals"]:
            d.ellipse([tx - 4, ty - 4, tx + 4, ty + 4], outline=(255, 0, 0), width=2)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        dx, dy = {"right": (1, 0), "left": (-1, 0), "up": (0, -1), "down": (0, 1)}[s["polarity"]]
        d.line([cx, cy, cx + dx * 14, cy + dy * 14], fill=(255, 0, 0), width=2)
    for t in sup["texts"]:
        x0, y0, x1, y1 = t["box"]
        d.rectangle([x0, y0, x1, y1], outline=COLORS["text"], width=1)
    for jx, jy in sup["junctions"]:
        d.ellipse([jx - 6, jy - 6, jx + 6, jy + 6], outline=(0, 160, 0), width=3)
    w, h = img.size
    for node, (fx, fy) in label["circuit"].get("node_points", {}).items():
        x, y = fx * w, fy * h
        d.rectangle([x - 5, y - 5, x + 5, y + 5], fill=(0, 0, 255))
        d.text((x + 7, y - 6), node, fill=(0, 0, 255))
    return img


def contact_sheet(root: Path, count: int, columns: int = 3, cell: int = 420, show_mask: bool = True) -> Image.Image:
    labels = sorted((root / "labels").glob("*.json"))[:count]
    rows = math.ceil(len(labels) / columns)
    sheet = Image.new("RGB", (columns * cell, rows * cell), (60, 60, 60))
    for i, path in enumerate(labels):
        label = json.loads(path.read_text())
        img = overlay(label, root, show_mask)
        img.thumbnail((cell - 8, cell - 8))
        sheet.paste(img, ((i % columns) * cell + 4, (i // columns) * cell + 4))
    return sheet


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--count", type=int, default=12)
    parser.add_argument("--columns", type=int, default=3)
    parser.add_argument("--cell", type=int, default=420)
    parser.add_argument("--no-mask", action="store_true")
    args = parser.parse_args()
    contact_sheet(Path(args.data), args.count, args.columns, args.cell, not args.no_mask).save(args.out)
    print("saved", args.out)


if __name__ == "__main__":
    main()
