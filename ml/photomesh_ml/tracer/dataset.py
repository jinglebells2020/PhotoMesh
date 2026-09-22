"""Torch dataset for CircuitNet: letterboxing, light augmentation, port-crop mosaics, targets."""
from __future__ import annotations

import math
import random
import warnings
from dataclasses import replace
from pathlib import Path
from typing import Optional, Sequence

import numpy as np
import torch
from PIL import Image, ImageFilter
from torch.utils.data import Dataset

from ..classes import TRACER_CLASSES
from ..data.records import Record, Symbol, open_record_image, resolve_path
from .targets import build_targets

MAX_OBJECTS = 256   # regression slots per image; dense CGHD photos carry 130+ boxes once text is counted


def _affine_image(img: Image.Image, scale: float, tx: float, ty: float, size: int, resample, fill, angle: float = 0.0) -> Image.Image:
    """Output = rotate(scale * input) + (tx, ty); rotation by `angle` degrees about the input origin after scaling."""
    a, b, c, d, e, f = _forward_affine(scale, tx, ty, angle)
    det = a * e - b * d
    inv = (e / det, -b / det, (b * f - e * c) / det, -d / det, a / det, (d * c - a * f) / det)
    return img.transform((size, size), Image.AFFINE, inv, resample=resample, fillcolor=fill)


def _forward_affine(scale: float, tx: float, ty: float, angle: float = 0.0) -> tuple[float, float, float, float, float, float]:
    """x' = a x + b y + c, y' = d x + e y + f."""
    t = math.radians(angle)
    cos, sin = math.cos(t), math.sin(t)
    return scale * cos, -scale * sin, tx, scale * sin, scale * cos, ty


def _transform_record(record: Record, scale: float, tx: float, ty: float, angle: float = 0.0) -> Record:
    a, b, c, d, e, f = _forward_affine(scale, tx, ty, angle)

    def pt(p):
        return [a * p[0] + b * p[1] + c, d * p[0] + e * p[1] + f]

    def box(bx):
        x0, y0, x1, y1 = bx
        corners = [pt((x0, y0)), pt((x1, y0)), pt((x1, y1)), pt((x0, y1))]
        xs, ys = [q[0] for q in corners], [q[1] for q in corners]
        return [min(xs), min(ys), max(xs), max(ys)]

    symbols = []
    for s in record.symbols:
        symbols.append(replace(s, box=box(s.box), terminals=[pt(p) for p in s.terminals] if s.terminals else None))
    junctions = [pt(p) for p in record.junctions] if record.junctions is not None else None
    return replace(record, symbols=symbols, junctions=junctions)


def wire_from_ink(ink: np.ndarray, record: Record, margin: int = 2) -> np.ndarray:
    """Stroke segmentation minus every symbol and text box = wire ink."""
    wire = ink.copy()
    h, w = wire.shape
    for s in record.symbols:
        x0, y0, x1, y1 = s.box
        wire[max(0, int(y0) - margin):min(h, int(math.ceil(y1)) + margin), max(0, int(x0) - margin):min(w, int(math.ceil(x1)) + margin)] = 0
    return wire


def _border_colour(img: Image.Image) -> tuple[int, int, int]:
    arr = np.asarray(img.convert("RGB"))
    border = np.concatenate([arr[0], arr[-1], arr[:, 0], arr[:, -1]])
    return tuple(int(v) for v in np.median(border, axis=0))


class TracerDataset(Dataset):
    def __init__(self, records: Sequence[Record], input_size: int = 640, train: bool = True, stride: int = 4,
                 jsonl_dir: Optional[Path] = None, mosaic_ports: bool = True, seed: int = 0, max_rotation: float = 0.0,
                 max_mosaics: int = 3000):
        self.records = list(records)
        self.input_size = input_size
        self.train = train
        self.stride = stride
        self.jsonl_dir = jsonl_dir
        self.mosaic_ports = mosaic_ports
        self.max_rotation = max_rotation
        self.rng = random.Random(seed)
        self.port_records = [r for r in self.records if r.source == "digitize_hcd_ports"]
        # Port crops are only consumed through mosaics; keep one entry per ~6 crops.
        others = [r for r in self.records if r.source != "digitize_hcd_ports"]
        n_mosaic = min(len(self.port_records) // 6, max_mosaics) if mosaic_ports else 0
        self.items: list[tuple[str, Optional[Record]]] = [("record", r) for r in others] + [("mosaic", None)] * n_mosaic

    def __len__(self) -> int:
        return len(self.items)

    # ------------------------------------------------------------------ loading
    def _load_record(self, record: Record) -> tuple[Image.Image, Optional[np.ndarray]]:
        img = open_record_image(record, self.jsonl_dir)
        mask: Optional[np.ndarray] = None
        if record.wire_mask:
            mask = np.asarray(Image.open(resolve_path(record.wire_mask, self.jsonl_dir)).convert("L"))
        elif record.ink_mask:
            ink = np.asarray(Image.open(resolve_path(record.ink_mask, self.jsonl_dir)).convert("L"))
            ink = np.where(ink < 128, 255, 0).astype(np.uint8)   # black strokes on white
            mask = wire_from_ink(ink, record)
        return img, mask

    def _mosaic(self) -> tuple[Record, Image.Image]:
        """4-9 port crops pasted on a paper-coloured canvas at random scales."""
        S = self.input_size
        n = self.rng.randint(4, 9)
        cols = int(math.ceil(math.sqrt(n)))
        cell = S / cols
        paper = tuple(self.rng.choice([(250, 250, 250), (245, 242, 232), (240, 240, 236), (255, 255, 255)]))
        canvas = Image.new("RGB", (S, S), paper)
        symbols: list[Symbol] = []
        for i in range(n):
            rec = self.rng.choice(self.port_records)
            crop = open_record_image(rec, self.jsonl_dir)
            size = int(cell * self.rng.uniform(0.45, 0.95))
            crop = crop.resize((size, size), Image.BILINEAR)
            cx = int((i % cols) * cell + self.rng.uniform(0, max(1, cell - size)))
            cy = int((i // cols) * cell + self.rng.uniform(0, max(1, cell - size)))
            canvas.paste(crop, (cx, cy))
            scale = size / rec.width
            for s in rec.symbols:
                x0, y0, x1, y1 = s.box
                symbols.append(replace(s, box=[cx + x0 * scale, cy + y0 * scale, cx + x1 * scale, cy + y1 * scale],
                                       terminals=[[cx + px * scale, cy + py * scale] for px, py in s.terminals] if s.terminals else None))
        record = Record(image="mosaic", width=S, height=S, source="mosaic", group="mosaic", symbols=symbols, junctions=None,
                        wire_mask=None, texts_complete=False)
        return record, canvas

    # ------------------------------------------------------------------ item
    def __getitem__(self, index: int) -> dict:
        kind, record = self.items[index]
        S = self.input_size
        angle = 0.0
        if kind == "mosaic":
            record, img = self._mosaic()
            mask = None
            scale, tx, ty = 1.0, 0.0, 0.0
        else:
            img, mask = self._load_record(record)
            fit = S / max(record.width, record.height)
            if self.train:
                scale = fit * self.rng.uniform(0.75, 1.15)
                angle = self.rng.uniform(-self.max_rotation, self.max_rotation) if self.max_rotation > 0 else 0.0
                # translate so the rotated, scaled image stays inside the canvas as far as possible
                w, h = record.width * scale, record.height * scale
                t = math.radians(angle)
                bw, bh = abs(w * math.cos(t)) + abs(h * math.sin(t)), abs(w * math.sin(t)) + abs(h * math.cos(t))
                cx, cy = w / 2, h / 2
                rcx, rcy = cx * math.cos(t) - cy * math.sin(t), cx * math.sin(t) + cy * math.cos(t)
                free_x, free_y = S - bw, S - bh
                tx = (bw / 2 - rcx) + self.rng.uniform(min(0, free_x), max(0, free_x))
                ty = (bh / 2 - rcy) + self.rng.uniform(min(0, free_y), max(0, free_y))
            else:
                scale = fit
                tx, ty = (S - record.width * scale) / 2, (S - record.height * scale) / 2
            fill = _border_colour(img)
            img = _affine_image(img, scale, tx, ty, S, Image.BILINEAR, fill, angle)
            if mask is not None:
                mask = np.asarray(_affine_image(Image.fromarray(mask, "L"), scale, tx, ty, S, Image.NEAREST, 0, angle))
        record_t = _transform_record(record, scale, tx, ty, angle)
        if self.train and record.source != "synthetic":
            img = self._photometric(img)
        targets = build_targets(record_t, (S, S), self.stride, mask)
        image = torch.from_numpy(np.asarray(img, np.uint8).copy()).permute(2, 0, 1)
        n = min(len(targets.index), MAX_OBJECTS)
        if len(targets.index) > MAX_OBJECTS:
            # The heatmap still carries every centre; only the per-object regression slots are capped.
            warnings.warn(f"{record.image}: {len(targets.index)} symbols, regression targets capped at {MAX_OBJECTS}")
        pad = MAX_OBJECTS - n
        return {
            "image": image,
            "heat": torch.from_numpy(targets.heat), "heat_weight": torch.from_numpy(targets.heat_weight),
            "size": torch.from_numpy(np.pad(targets.size[:n], ((0, pad), (0, 0)))),
            "offset": torch.from_numpy(np.pad(targets.offset[:n], ((0, pad), (0, 0)))),
            "index": torch.from_numpy(np.pad(targets.index[:n], (0, pad))),
            "reg_mask": torch.from_numpy(np.pad(np.ones(n, np.float32), (0, pad))),
            "polarity": torch.from_numpy(np.pad(targets.polarity[:n], ((0, pad), (0, 0)))),
            "polarity_weight": torch.from_numpy(np.pad(targets.polarity_weight[:n], (0, pad))),
            "wire": torch.from_numpy(targets.wire), "wire_weight": torch.tensor(targets.wire_weight),
            "junction": torch.from_numpy(targets.junction), "junction_weight": torch.tensor(targets.junction_weight),
            "terminal": torch.from_numpy(targets.terminal), "terminal_weight": torch.tensor(targets.terminal_weight),
            "source": record.source,
        }

    def _photometric(self, img: Image.Image) -> Image.Image:
        arr = np.asarray(img).astype(np.float32)
        arr = arr * self.rng.uniform(0.85, 1.1) + self.rng.uniform(-12, 12)
        if self.rng.random() < 0.3:
            img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(self.rng.uniform(0.3, 1.0)))
            arr = np.asarray(img).astype(np.float32)
        if self.rng.random() < 0.3:
            arr += np.random.normal(0, self.rng.uniform(1, 5), arr.shape)
        return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def collate(batch: list[dict]) -> dict:
    out: dict = {}
    for key in batch[0]:
        if key == "source":
            out[key] = [b[key] for b in batch]
        else:
            out[key] = torch.stack([b[key] for b in batch])
    return out
