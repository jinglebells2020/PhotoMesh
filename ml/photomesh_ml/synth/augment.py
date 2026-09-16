"""Photo-style augmentation applied consistently to the image, the wire mask and every label.

Geometry is one homography (rotation + perspective + scale), so points and boxes are mapped
exactly. Photometry (lighting, blur, noise, JPEG) touches the image only.
"""
from __future__ import annotations

import io
import math
import random
from dataclasses import dataclass
from typing import Optional

import numpy as np
from PIL import Image, ImageFilter

from ..schema import Circuit
from .render import Rendered, SymbolLabel, TextLabel

Point = tuple[float, float]


def homography(src: list[Point], dst: list[Point]) -> np.ndarray:
    """3x3 matrix mapping the four `src` points onto `dst` (direct linear transform)."""
    rows = []
    for (x, y), (u, v) in zip(src, dst):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y, -u])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y, -v])
    A = np.array(rows, float)
    _, _, vt = np.linalg.svd(A)
    H = vt[-1].reshape(3, 3)
    return H / H[2, 2]


def transform_points(H: np.ndarray, pts: list[Point]) -> list[Point]:
    if not pts:
        return []
    arr = np.array([[x, y, 1.0] for x, y in pts]).T
    out = H @ arr
    out /= out[2:3]
    return [(float(x), float(y)) for x, y in zip(out[0], out[1])]


def transform_box(H: np.ndarray, box: list[float]) -> list[float]:
    x0, y0, x1, y1 = box
    pts = transform_points(H, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return [min(xs), min(ys), max(xs), max(ys)]


def warp(img: Image.Image, H: np.ndarray, size: tuple[int, int], resample=Image.BILINEAR, fill=(0, 0, 0)) -> Image.Image:
    """Applies the forward homography H (source px -> output px) with PIL's perspective transform."""
    Hinv = np.linalg.inv(H)
    Hinv /= Hinv[2, 2]
    coeffs = tuple(Hinv.flatten()[:8])
    return img.transform(size, Image.PERSPECTIVE, coeffs, resample=resample, fillcolor=fill)


def random_geometry(rng: random.Random, width: int, height: int, out_long: int, photo: bool) -> tuple[np.ndarray, tuple[int, int]]:
    """Rotation + perspective + scale; returns H and the output size."""
    scale = out_long / max(width, height)
    W, Hh = int(round(width * scale)), int(round(height * scale))
    cx, cy = width / 2, height / 2
    corners = [(0.0, 0.0), (float(width), 0.0), (float(width), float(height)), (0.0, float(height))]
    if photo:
        angle = math.radians(rng.gauss(0, 3.0)) if rng.random() < 0.85 else math.radians(rng.uniform(-12, 12))
        strength = rng.choice([0.02, 0.04, 0.07, 0.1]) * min(width, height)
    else:
        angle = math.radians(rng.gauss(0, 0.6))
        strength = 0.005 * min(width, height)
    c, s = math.cos(angle), math.sin(angle)
    dst = []
    for x, y in corners:
        rx = cx + (x - cx) * c - (y - cy) * s
        ry = cy + (x - cx) * s + (y - cy) * c
        # move each corner inward by a random amount (the paper is a skewed quad in the photo)
        ix = strength * rng.uniform(0.0, 1.0) * (1 if x == 0 else -1)
        iy = strength * rng.uniform(0.0, 1.0) * (1 if y == 0 else -1)
        dst.append(((rx + ix) * scale, (ry + iy) * scale))
    H = homography(corners, dst)
    return H, (W, Hh)


def photometric(img: Image.Image, rng: random.Random, photo: bool) -> Image.Image:
    arr = np.asarray(img).astype(np.float32)
    h, w = arr.shape[:2]
    rs = np.random.RandomState(rng.randint(0, 2**31 - 1))
    if photo:
        # illumination plane + soft shadow
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        gx, gy = rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25)
        plane = 1.0 + gx * (xx / w - 0.5) + gy * (yy / h - 0.5)
        if rng.random() < 0.5:
            sx, sy = rng.uniform(0, w), rng.uniform(0, h)
            radius = rng.uniform(0.3, 0.8) * max(w, h)
            shadow = 1.0 - rng.uniform(0.1, 0.35) * np.exp(-((xx - sx) ** 2 + (yy - sy) ** 2) / (2 * radius ** 2))
            plane *= shadow
        arr *= plane[..., None] * rng.uniform(0.85, 1.08)
        # colour cast
        arr *= np.array([rng.uniform(0.94, 1.06), rng.uniform(0.94, 1.06), rng.uniform(0.94, 1.06)], np.float32)
    else:
        arr *= rng.uniform(0.96, 1.04)
    # contrast around the mean
    if rng.random() < 0.5:
        mean = arr.mean()
        arr = (arr - mean) * rng.uniform(0.8, 1.15) + mean
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    if photo and rng.random() < 0.55:
        img = img.filter(ImageFilter.GaussianBlur(rng.uniform(0.3, 1.4)))
    elif rng.random() < 0.2:
        img = img.filter(ImageFilter.GaussianBlur(rng.uniform(0.2, 0.6)))
    arr = np.asarray(img).astype(np.float32)
    if rng.random() < 0.7:
        arr += rs.normal(0, rng.uniform(1.0, 7.0 if photo else 3.0), arr.shape)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    if rng.random() < 0.15:
        img = img.convert("L").convert("RGB")
    quality = rng.randint(45, 92) if photo else rng.randint(70, 95)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality)
    buf.seek(0)
    return Image.open(buf).convert("RGB")


@dataclass
class Sample:
    image: Image.Image
    wire_mask: np.ndarray
    symbols: list[SymbolLabel]
    texts: list[TextLabel]
    junctions: list[Point]
    circuit: Circuit
    style: str
    photo: bool
    spacing: float

    @property
    def width(self) -> int:
        return self.image.width

    @property
    def height(self) -> int:
        return self.image.height


def augment(rendered: Rendered, rng: random.Random, out_long: Optional[int] = None, photo: Optional[bool] = None) -> Sample:
    if photo is None:
        photo = rng.random() < 0.75
    if out_long is None:
        out_long = rng.choice([640, 768, 896, 1024, 1280, 1280])
    H, size = random_geometry(rng, rendered.width, rendered.height, out_long, photo)
    W, Hh = size
    if photo and rng.random() < 0.5:
        fill = tuple(int(v) for v in rng.choice([(70, 60, 55), (120, 105, 90), (40, 40, 45), (160, 150, 140), (90, 95, 100)]))
    else:
        fill = tuple(int(v) for v in np.asarray(rendered.image)[2, 2])
    image = warp(rendered.image, H, size, Image.BICUBIC, fill)
    mask_img = warp(Image.fromarray(rendered.wire_mask, "L"), H, size, Image.BILINEAR, 0)
    wire_mask = (np.asarray(mask_img) > 40).astype(np.uint8) * 255
    image = photometric(image, rng, photo)

    symbols = [SymbolLabel(s.cls, transform_box(H, s.box), s.orientation, s.polarity, transform_points(H, s.terminals), s.id) for s in rendered.symbols]
    texts = [TextLabel(transform_box(H, t.box), t.text, t.role, t.component) for t in rendered.texts]
    junctions = transform_points(H, rendered.junctions)

    circuit = rendered.circuit.renaming_nodes(lambda n: n)
    by_id = {s.id: s for s in symbols}
    for c in circuit.components:
        x0, y0, x1, y1 = by_id[c.id].box
        c.box = [x0 / W, y0 / Hh, x1 / W, y1 / Hh]
    pts = {n: (x * rendered.width, y * rendered.height) for n, (x, y) in rendered.circuit.node_points.items()}
    moved = transform_points(H, list(pts.values()))
    circuit.node_points = {n: [x / W, y / Hh] for n, (x, y) in zip(pts.keys(), moved)}
    return Sample(image, wire_mask, symbols, texts, junctions, circuit, rendered.style, photo, rendered.spacing * (W / rendered.width))
