"""EXIF orientation versus the frame the labels were drawn in.

Phone photos carry an EXIF orientation tag. Annotation tools disagree on whether to apply it
before the labeller draws boxes: in CGHD roughly a tenth of the photos are labelled in the
rotated frame, a few in the stored frame, and two drafters ship XML sizes that are simply wrong
(1000 x 1000 for 12 MP photos). Every record therefore carries the orientation code that maps
the stored pixels onto the label frame, and every consumer opens images through
`open_oriented` instead of guessing.

`apply_orientation` transposes the pixels itself rather than calling `ImageOps.exif_transpose`,
which re-serialises the EXIF block and crashes on the zero-denominator rationals some cameras write.
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional, Sequence

import numpy as np
from PIL import Image

EXIF_ORIENTATION = 0x0112
_TRANSPOSE = {
    2: Image.Transpose.FLIP_LEFT_RIGHT, 3: Image.Transpose.ROTATE_180, 4: Image.Transpose.FLIP_TOP_BOTTOM,
    5: Image.Transpose.TRANSPOSE, 6: Image.Transpose.ROTATE_270, 7: Image.Transpose.TRANSVERSE, 8: Image.Transpose.ROTATE_90,
}
SWAPS_AXES = {5, 6, 7, 8}
_PROBE_SIDE = 320


def read_exif_orientation(img: Image.Image) -> int:
    """The EXIF orientation code (1 when absent, zero, out of range or unreadable)."""
    try:
        code = int(img.getexif().get(EXIF_ORIENTATION, 1) or 1)
    except Exception:
        return 1
    return code if code in _TRANSPOSE else 1


def oriented_size(width: int, height: int, code: int) -> tuple[int, int]:
    return (height, width) if code in SWAPS_AXES else (width, height)


def apply_orientation(img: Image.Image, code: int) -> Image.Image:
    """Pixels transposed by an EXIF orientation code; the result carries no EXIF/XMP so nothing
    downstream (Pillow's exif_transpose in the tracer, for instance) rotates it a second time."""
    method = _TRANSPOSE.get(code)
    out = img.transpose(method) if method is not None else img.copy()
    for key in ("exif", "xmp", "Raw profile type exif"):
        out.info.pop(key, None)
    return out


def open_oriented(path: Path | str, code: int = 1, mode: str = "RGB") -> Image.Image:
    with Image.open(path) as img:
        return apply_orientation(img, code).convert(mode)


def _agreement(gray: Image.Image, frame_size: tuple[int, int], stroke: Optional[Image.Image],
               boxes: Optional[Sequence[Sequence[float]]]) -> float:
    """How much of the ink sits where the labels say it should, relative to the whole page."""
    w, h = frame_size
    scale = _PROBE_SIDE / max(w, h)
    pw, ph = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    dark = 255.0 - np.asarray(gray.resize((pw, ph), Image.BILINEAR), dtype=np.float32)
    base = float(dark.mean()) + 1e-3
    if stroke is not None and stroke.size == frame_size:
        hit = np.asarray(stroke.resize((pw, ph), Image.NEAREST)) < 128     # black strokes on white
        return float(dark[hit].mean() / base) if hit.any() else 0.0
    if boxes:
        inside = np.zeros((ph, pw), dtype=bool)
        for x0, y0, x1, y1 in boxes:
            xa, ya = max(0, int(x0 * scale)), max(0, int(y0 * scale))
            xb, yb = min(pw, int(np.ceil(x1 * scale))), min(ph, int(np.ceil(y1 * scale)))
            if xb > xa and yb > ya:
                inside[ya:yb, xa:xb] = True
        return float(dark[inside].mean() / base) if inside.any() else 0.0
    return 0.0


def detect_label_orientation(image_path: Path | str, label_size: Optional[tuple[int, int]] = None,
                             boxes: Optional[Sequence[Sequence[float]]] = None,
                             mask_path: Optional[Path | str] = None) -> tuple[int, int, int]:
    """(orientation, width, height): the EXIF code that maps the stored pixels onto the frame the
    labels were drawn in, and that frame's size.

    Decision order: the stroke mask's size (it is drawn in the label frame), then the annotation's
    own size, both only when the two candidate frames differ in shape; otherwise (180-degree turns,
    square photos, bogus sizes) the frame whose ink agrees better with the labels wins.
    """
    with Image.open(image_path) as img:
        raw = img.size
        code = read_exif_orientation(img)
        if code == 1:
            return 1, raw[0], raw[1]
        rotated = oriented_size(raw[0], raw[1], code)
        stroke: Optional[Image.Image] = None
        if mask_path is not None:
            with Image.open(mask_path) as m:
                stroke = m.convert("L")
        if raw != rotated:
            if stroke is not None and stroke.size in (raw, rotated):
                chosen = code if stroke.size == rotated else 1
                return chosen, *oriented_size(raw[0], raw[1], chosen)
            if label_size is not None and tuple(label_size) in (raw, rotated):
                chosen = code if tuple(label_size) == rotated else 1
                return chosen, *oriented_size(raw[0], raw[1], chosen)
        gray = img.convert("L")
    scores = {}
    for candidate in (code, 1):
        frame = apply_orientation(gray, candidate)
        scores[candidate] = _agreement(frame, frame.size, stroke, boxes)
    chosen = code if scores[code] >= scores[1] else 1
    return chosen, *oriented_size(raw[0], raw[1], chosen)
