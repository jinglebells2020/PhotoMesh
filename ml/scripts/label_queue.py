"""Hand-labelling queue: the same acceptance checks as `vlm.distill`, for answers written by a person
or by a model that can look at the photos directly (no API).

    python scripts/label_queue.py prepare --records data/records/train.jsonl [--records ...] --out data/label \
        --sources digitize_hcd,cghd --max-components 12 --skip data/distill/train.jsonl
    python scripts/label_queue.py check --queue data/label --labeller claude-fable-5-1
    python scripts/label_queue.py export --queue data/label --data-root data --out labels/claude

`prepare` selects in-scope photos (no unsupported symbol, at most N app components), writes each one
downsized in its label frame to <out>/images/NNNN.jpg and the queue to <out>/queue.jsonl.
`check` validates every <out>/answers/NNNN.json (schema, solver, box agreement with the annotation)
and writes <out>/train.jsonl (accepted, in the distillation format) and <out>/rejected.jsonl.
`export` copies the accepted rows (train.jsonl for photos from the train records, heldout.jsonl for
val/test photos), the rejected rows and <queue>/skipped.txt into a repository folder with image paths
relative to the data root, so they survive a fresh checkout (`vlm.build_dataset --data-root` resolves them).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from photomesh_ml.classes import APP_KINDS  # noqa: E402
from photomesh_ml.data.records import Record, open_record_image, read_jsonl  # noqa: E402
from photomesh_ml.schema import Circuit, ValidationError  # noqa: E402
from photomesh_ml.solver import solvable  # noqa: E402
from photomesh_ml.vlm.distill import box_agreement  # noqa: E402


def prepare(args) -> None:
    out = Path(args.out)
    (out / "images").mkdir(parents=True, exist_ok=True)
    (out / "answers").mkdir(parents=True, exist_ok=True)
    skip = set()
    for p in args.skip:
        for line in Path(p).read_text(encoding="utf-8").splitlines():
            if line.strip():
                skip.add(Path(json.loads(line)["image"]).name)
    sources = set(args.sources.split(","))
    rows: list[tuple[Record, Path]] = []
    for rec_path in args.records:
        jsonl = Path(rec_path)
        for r in read_jsonl(jsonl):
            if r.source not in sources or Path(r.image).name in skip:
                continue
            comps = [s for s in r.symbols if s.cls in APP_KINDS]
            if any(s.cls == "other" for s in r.symbols) or not comps or len(comps) > args.max_components:
                continue
            rows.append((r, jsonl))
    rows.sort(key=lambda t: (t[0].source, Path(t[0].image).name))
    with (out / "queue.jsonl").open("w", encoding="utf-8") as f:
        for i, (r, jsonl) in enumerate(rows):
            img = open_record_image(r, jsonl)
            scale = min(1.0, args.max_side / max(img.size))
            if scale < 1.0:
                img = img.resize((int(round(img.width * scale)), int(round(img.height * scale))))
            name = f"{i:04d}.jpg"
            img.save(out / "images" / name, "JPEG", quality=88)
            f.write(json.dumps({"index": i, "queue_image": str(out / "images" / name), "width": img.width, "height": img.height,
                                "record": r.to_json(), "jsonl": str(jsonl)}, ensure_ascii=False) + "\n")
    print(f"{len(rows)} photos queued in {out} (skipped {len(skip)} already labelled)")


def unmatched(circuit: Circuit, record: Record, width: int, height: int) -> str:
    """Which predicted and annotated boxes found no partner (fractions of the queue image)."""
    from photomesh_ml.vlm.distill import _iou
    sx, sy = 1.0 / record.width, 1.0 / record.height
    truths = [(s.cls, [s.box[0] * sx, s.box[1] * sy, s.box[2] * sx, s.box[3] * sy]) for s in record.symbols if s.cls in APP_KINDS]
    preds = [(c.id, c.kind, list(c.box)) for c in circuit.components if c.box is not None]
    used = set()
    lonely_p = []
    for cid, kind, pb in preds:
        best, best_iou = None, 0.3
        for j, (tc, tb) in enumerate(truths):
            if j in used:
                continue
            v = _iou(pb, tb)
            if v >= best_iou:
                best, best_iou = j, v
        if best is None:
            lonely_p.append(f"{cid}/{kind}@{[round(v, 2) for v in pb]}")
        else:
            used.add(best)
    lonely_t = [f"{tc}@{[round(v, 2) for v in tb]}" for j, (tc, tb) in enumerate(truths) if j not in used]
    return f"unmatched predictions {lonely_p}; unmatched annotations {lonely_t}"


def check(args) -> None:
    out = Path(args.queue)
    queue = [json.loads(line) for line in (out / "queue.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]
    accepted, rejected, pending = [], [], 0
    for q in queue:
        ans = out / "answers" / f"{q['index']:04d}.json"
        if not ans.exists():
            pending += 1
            continue
        record = Record.from_json(q["record"])
        entry: dict = {"model": args.labeller}
        text = ans.read_text(encoding="utf-8")
        try:
            circuit = Circuit.from_json(text)
            circuit.validated()
        except (ValidationError, ValueError) as exc:
            entry["error"] = f"invalid: {exc}"
        else:
            if not solvable(circuit):
                entry["error"] = "unsolvable"
            else:
                agreement = box_agreement(circuit, record, q["width"], q["height"])
                entry["agreement"] = agreement
                if min(agreement["recall"], agreement["precision"], agreement["class_acc"]) < args.min_agreement:
                    entry["error"] = f"boxes disagree with the annotation: {unmatched(circuit, record, q['width'], q['height'])}"
                entry["circuit"] = circuit.to_json(2)
        row = {"image": q["record"]["image"], "width": q["width"], "height": q["height"], "source": record.source, "group": record.group,
               "answers": [entry], "index": q["index"]}
        if "error" in entry:
            row["rejected"] = entry["error"]
            rejected.append(row)
        else:
            row["target"] = entry["circuit"]
            row["teacher"] = args.labeller
            accepted.append(row)
    for name, rows in (("train.jsonl", accepted), ("rejected.jsonl", rejected)):
        with (out / name).open("w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"accepted {len(accepted)}, rejected {len(rejected)}, pending {pending} of {len(queue)}")
    for r in rejected:
        print(f"  {r['index']:04d} {Path(r['image']).name}: {r['rejected'][:200]}")


def export(args) -> None:
    queue, out, root = Path(args.queue), Path(args.out), Path(os.path.abspath(args.data_root))  # symlinks kept: the root may be assembled from links
    out.mkdir(parents=True, exist_ok=True)
    # which records file each photo came from: val/test rows are held out, everything else may be trained on
    origin = {q["index"]: Path(q["jsonl"]).stem for q in
              (json.loads(line) for line in (queue / "queue.jsonl").read_text(encoding="utf-8").splitlines() if line.strip())}
    counts = {}

    def relative(row: dict) -> dict:
        image = Path(os.path.abspath(row["image"]))
        try:
            row["image"] = str(image.relative_to(root))
        except ValueError:
            raise SystemExit(f"{image} is not under the data root {root}")
        return row

    def write(name: str, rows: list[dict]) -> None:
        with (out / name).open("w", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
        counts[name] = len(rows)

    accepted = [relative(json.loads(line)) for line in (queue / "train.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]
    write("train.jsonl", [r for r in accepted if origin.get(r["index"]) not in ("val", "test")])
    write("heldout.jsonl", [r for r in accepted if origin.get(r["index"]) in ("val", "test")])
    rejected = queue / "rejected.jsonl"
    if rejected.exists():
        write("rejected.jsonl", [relative(json.loads(line)) for line in rejected.read_text(encoding="utf-8").splitlines() if line.strip()])
    skipped = queue / "skipped.txt"
    if skipped.exists():
        (out / "skipped.txt").write_text(skipped.read_text(encoding="utf-8"), encoding="utf-8")
        counts["skipped.txt"] = sum(1 for line in skipped.read_text(encoding="utf-8").splitlines() if line.strip())
    print(f"exported to {out}: {counts}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--records", action="append", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--sources", default="digitize_hcd,cghd")
    p.add_argument("--max-components", type=int, default=12)
    p.add_argument("--max-side", type=int, default=1280)
    p.add_argument("--skip", action="append", default=[], help="distillation outputs whose photos are already labelled")
    c = sub.add_parser("check")
    c.add_argument("--queue", required=True)
    c.add_argument("--labeller", default="claude")
    c.add_argument("--min-agreement", type=float, default=0.9)
    e = sub.add_parser("export")
    e.add_argument("--queue", required=True)
    e.add_argument("--data-root", required=True, help="directory the exported image paths are made relative to")
    e.add_argument("--out", required=True)
    args = parser.parse_args()
    {"prepare": prepare, "check": check, "export": export}[args.cmd](args)


if __name__ == "__main__":
    main()
