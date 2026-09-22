"""Downsize record images (phone photos are 12 MP; the tracer trains at 640 px) and scale labels.

    python -m photomesh_ml.data.downsize --records data/records/train.jsonl --out data/records_small/train.jsonl --max-side 1600

Rewrites images larger than `max_side` into `<out dir>/images/`, scales boxes, terminals,
junctions and the wire/ink masks, and writes a new JSONL. Untouched images keep their paths.
"""
from __future__ import annotations

import argparse
import hashlib
from dataclasses import replace
from pathlib import Path

import warnings
from typing import Optional

from PIL import Image

from .orientation import oriented_size
from .records import Record, open_record_image, read_jsonl, resolve_path, write_jsonl


def downsize_record(record: Record, out_dir: Path, max_side: int, jsonl_dir: Path | None) -> Optional[Record]:
    """The record with its photo shrunk to `max_side` (None when the photo cannot be read)."""
    try:
        return _downsize(record, out_dir, max_side, jsonl_dir)
    except Exception as exc:   # one unreadable photo must not sink a 100k-record split
        warnings.warn(f"{record.image}: {type(exc).__name__}: {exc}; record dropped")
        return None


def _downsize(record: Record, out_dir: Path, max_side: int, jsonl_dir: Path | None) -> Record:
    src = resolve_path(record.image, jsonl_dir)
    scale = max_side / max(record.width, record.height)
    if scale >= 1.0:
        return record
    name = hashlib.sha1(str(src).encode()).hexdigest()[:16]
    (out_dir / "images").mkdir(parents=True, exist_ok=True)
    dst = out_dir / "images" / f"{name}.jpg"
    new_w, new_h = int(round(record.width * scale)), int(round(record.height * scale))
    with Image.open(src) as probe:   # header only: the label frame must match the record before anything is scaled
        frame = oriented_size(*probe.size, record.orientation)
    if frame != (record.width, record.height):
        raise ValueError(f"photo is {frame} in its label frame but the record says {(record.width, record.height)}")
    if not dst.exists():
        # Opened in the label frame (EXIF applied only when the record says the labels were drawn
        # that way) and written upright, so the output record needs no orientation.
        open_record_image(record, jsonl_dir).resize((new_w, new_h), Image.LANCZOS).save(dst, "JPEG", quality=90)

    def pt(p):
        return [p[0] * scale, p[1] * scale]

    symbols = [replace(s, box=[v * scale for v in s.box], terminals=[pt(p) for p in s.terminals] if s.terminals else None) for s in record.symbols]
    junctions = [pt(p) for p in record.junctions] if record.junctions is not None else None
    wire_mask = ink_mask = None
    for attr in ("wire_mask", "ink_mask"):
        path = getattr(record, attr)
        if path:
            m = Image.open(resolve_path(path, jsonl_dir)).convert("L").resize((new_w, new_h), Image.BILINEAR)
            m = m.point(lambda v: 255 if v > 100 else 0) if attr == "wire_mask" else m
            mdst = out_dir / "images" / f"{name}.{attr}.png"
            m.save(mdst)
            if attr == "wire_mask":
                wire_mask = str(mdst)
            else:
                ink_mask = str(mdst)
    return replace(record, image=str(dst), width=new_w, height=new_h, symbols=symbols, junctions=junctions, wire_mask=wire_mask,
                   ink_mask=ink_mask, orientation=1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--records", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--max-side", type=int, default=1600)
    parser.add_argument("--workers", type=int, default=1)
    args = parser.parse_args()
    src = Path(args.records)
    out = Path(args.out)
    records = read_jsonl(src)
    if args.workers > 1:
        from functools import partial
        from multiprocessing import Pool
        with Pool(args.workers) as pool:
            done = pool.map(partial(downsize_record, out_dir=out.parent, max_side=args.max_side, jsonl_dir=src.parent), records, chunksize=8)
    else:
        done = [downsize_record(r, out.parent, args.max_side, src.parent) for r in records]
    kept = [r for r in done if r is not None]
    n = write_jsonl(kept, out)
    changed = sum(1 for a, b in zip(records, done) if b is not None and a.image != b.image)
    print(f"{n} records written to {out}; {changed} images downsized; {len(done) - len(kept)} dropped")


if __name__ == "__main__":
    main()
