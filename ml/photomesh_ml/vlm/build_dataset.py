"""Assemble the VLM fine-tuning set: synthetic images with exact targets + distilled real photos.

    python -m photomesh_ml.vlm.build_dataset --synthetic data/synth --distilled data/distill/train.jsonl \
        --out data/vlm --max-side 1024 --val-fraction 0.05

Each line of train.jsonl / val.jsonl: {"image": ..., "target": "<json>", "source": ..., "group": ...}.
Images are re-encoded under --out/images with the longest side capped, so training reads small files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps

from ..schema import Circuit
from .prompt import target_text


def _copy_image(src: Path, dst_dir: Path, max_side: int) -> tuple[Path, int, int]:
    dst_dir.mkdir(parents=True, exist_ok=True)
    name = hashlib.sha1(str(src).encode()).hexdigest()[:16] + ".jpg"
    dst = dst_dir / name
    if not dst.exists():
        img = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
        w, h = img.size
        scale = min(1.0, max_side / max(w, h))
        if scale < 1.0:
            img = img.resize((int(round(w * scale)), int(round(h * scale))), Image.LANCZOS)
        img.save(dst, "JPEG", quality=88)
        return dst, img.width, img.height
    with Image.open(dst) as img:
        return dst, img.width, img.height


def _bucket(key: str) -> float:
    return int(hashlib.sha1(key.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--synthetic", action="append", default=[])
    parser.add_argument("--distilled", action="append", default=[])
    parser.add_argument("--data-root", default="data", help="resolves relative image paths in distilled files (e.g. the labels/ folder)")
    parser.add_argument("--out", required=True)
    parser.add_argument("--max-side", type=int, default=1024)
    parser.add_argument("--val-fraction", type=float, default=0.05)
    parser.add_argument("--limit-synthetic", type=int, default=0)
    parser.add_argument("--synthetic-confidence", type=float, default=0.9)
    args = parser.parse_args()
    out = Path(args.out)
    rows: list[dict] = []
    n_synth = 0
    for d in args.synthetic:
        root = Path(d)
        for label_path in sorted((root / "labels").glob("*.json")):
            if args.limit_synthetic and n_synth >= args.limit_synthetic:
                break
            lab = json.loads(label_path.read_text(encoding="utf-8"))
            circuit = Circuit.from_json(lab["circuit"])
            dst, w, h = _copy_image(root / lab["image"], out / "images", args.max_side)
            rows.append({"image": str(dst.relative_to(out)), "width": w, "height": h, "source": "synthetic", "group": f"synth-{lab.get('seed', 0) % 100}",
                         "target": target_text(circuit, confidence=args.synthetic_confidence)})
            n_synth += 1
    n_real = 0
    for d in args.distilled:
        if not Path(d).exists():
            print(f"warning: distilled file {d} not found, skipping")
            continue
        for line in Path(d).read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            if "target" not in row:
                continue
            circuit = Circuit.from_json(row["target"])
            image = Path(row["image"])
            if not image.is_absolute():
                image = Path(args.data_root) / image
            dst, w, h = _copy_image(image, out / "images", args.max_side)
            rows.append({"image": str(dst.relative_to(out)), "width": w, "height": h, "source": row.get("source", "distilled"),
                         "group": row.get("group", "distilled"), "target": target_text(circuit, confidence=circuit.confidence)})
            n_real += 1
    train, val = [], []
    for row in rows:
        (val if _bucket(f"{row['source']}:{row['group']}") < args.val_fraction else train).append(row)
    out.mkdir(parents=True, exist_ok=True)
    for name, part in (("train", train), ("val", val)):
        with (out / f"{name}.jsonl").open("w", encoding="utf-8") as f:
            for row in part:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
        print(f"{name}: {len(part)} rows")
    print(f"synthetic {n_synth}, real {n_real} -> {out}")


if __name__ == "__main__":
    main()
