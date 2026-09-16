"""CLI: render N synthetic circuit photos with labels.

    python -m photomesh_ml.synth.generate --out data/synth --count 2000 --seed 0 --workers 4

Writes `images/NNNNNN.jpg`, `masks/NNNNNN.png` (wire ink) and `labels/NNNNNN.json`:

    {"image": ..., "width": W, "height": H, "style": "hand"|"print", "photo": bool,
     "circuit": <the app's JSON, coordinates as fractions>,
     "supervision": {"symbols": [{"cls", "box"(px), "orientation", "polarity", "terminals", "id"}],
                     "junctions": [[x, y]], "texts": [{"box", "text", "role", "component"}]}}
"""
from __future__ import annotations

import argparse
import json
import random
from multiprocessing import Pool
from pathlib import Path
from typing import Optional

from .augment import Sample, augment
from .circuits import generate as generate_lattice
from .render import random_style, render


def make_sample(seed: int, style: str = "mixed", augment_photo: Optional[bool] = None, out_long: Optional[int] = None) -> Sample:
    rng = random.Random(seed)
    lattice = generate_lattice(rng)
    hand = None if style == "mixed" else (style == "hand")
    rendered = render(lattice, rng, random_style(rng, hand))
    return augment(rendered, rng, out_long=out_long, photo=augment_photo)


def sample_to_label(sample: Sample, image_rel: str, mask_rel: Optional[str]) -> dict:
    return {
        "image": image_rel,
        "mask": mask_rel,
        "width": sample.width,
        "height": sample.height,
        "style": sample.style,
        "photo": sample.photo,
        "circuit": sample.circuit.to_json(digits=4),
        "supervision": {
            "symbols": [{"cls": s.cls, "box": [round(v, 1) for v in s.box], "orientation": s.orientation, "polarity": s.polarity,
                         "terminals": [[round(x, 1), round(y, 1)] for x, y in s.terminals], "id": s.id} for s in sample.symbols],
            "junctions": [[round(x, 1), round(y, 1)] for x, y in sample.junctions],
            "texts": [{"box": [round(v, 1) for v in t.box], "text": t.text, "role": t.role, "component": t.component} for t in sample.texts],
        },
    }


def _write_one(args: tuple) -> str:
    out, index, seed, style, no_augment = args
    from PIL import Image  # noqa: F401  (workers import lazily)
    try:
        sample = make_sample(seed, style, augment_photo=False if no_augment else None)
    except RuntimeError:
        sample = make_sample(seed + 1_000_003, style, augment_photo=False if no_augment else None)
    name = f"{index:06d}"
    out = Path(out)
    sample.image.save(out / "images" / f"{name}.jpg", "JPEG", quality=92)
    Image.fromarray(sample.wire_mask, "L").save(out / "masks" / f"{name}.png")
    label = sample_to_label(sample, f"images/{name}.jpg", f"masks/{name}.png")
    label["seed"] = seed
    (out / "labels" / f"{name}.json").write_text(json.dumps(label, ensure_ascii=False))
    return name


def main(argv: Optional[list[str]] = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--style", choices=["mixed", "hand", "print"], default="mixed")
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--no-augment", action="store_true", help="clean renders without perspective/lighting")
    args = parser.parse_args(argv)
    out = Path(args.out)
    for sub in ("images", "masks", "labels"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    from .fonts import ensure_fonts
    ensure_fonts(download=True)
    jobs = [(str(out), i, args.seed * 1_000_000 + i, args.style, args.no_augment) for i in range(args.count)]
    if args.workers > 1:
        with Pool(args.workers) as pool:
            for k, _ in enumerate(pool.imap_unordered(_write_one, jobs, chunksize=4), 1):
                if k % 100 == 0:
                    print(f"{k}/{len(jobs)}", flush=True)
    else:
        for k, job in enumerate(jobs, 1):
            _write_one(job)
            if k % 100 == 0:
                print(f"{k}/{len(jobs)}", flush=True)
    print(f"wrote {len(jobs)} samples to {out}")


if __name__ == "__main__":
    main()
