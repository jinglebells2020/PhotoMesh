"""Detection-only evaluation of a tracer checkpoint on any records, real photos included.

    python -m photomesh_ml.tracer.detect_eval --checkpoint runs/tracer/last.pt --records data/records_small/test.jsonl \
        --sources cghd,digitize_hcd --device cuda --out runs/tracer/results/detect_test

`tracer.evaluate` needs a netlist for the solver-as-judge, which only synthetic and distilled
records have. This scores boxes alone: mAP@0.5 per source with an image-level bootstrap interval,
per-class AP, and polarity accuracy on matched symbols whose polarity is annotated, so the numbers
cover the photos the phone will actually see.
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path
from typing import Optional

from ..classes import POLARITY, TRACER_CLASSES
from ..data.records import Record, open_record_image, read_jsonl
from ..eval.detection import DetectionSet, iou, mean_average_precision
from .infer import Tracer


def polarity_matches(record: Record, detections, iou_threshold: float = 0.5) -> tuple[int, int]:
    """(matched, correct) over truth symbols with an annotated polarity."""
    matched = correct = 0
    used: set[int] = set()
    for truth in record.symbols:
        if truth.polarity not in POLARITY:
            continue
        best, best_iou = None, iou_threshold
        for i, det in enumerate(detections):
            if i in used or det.cls != truth.cls:
                continue
            v = iou(det.box, truth.box)
            if v >= best_iou:
                best, best_iou = i, v
        if best is None:
            continue
        used.add(best)
        matched += 1
        correct += detections[best].polarity == truth.polarity
    return matched, correct


def merged_classes(record: Record) -> dict[str, str]:
    """Class names the annotation cannot tell apart (e.g. CGHD's one `switch` label, stored as
    switch_open with both candidates) are scored as one merged class for that image."""
    mapping: dict[str, str] = {}
    for s in record.symbols:
        if s.class_candidates and len(s.class_candidates) > 1:
            merged = "|".join(sorted(s.class_candidates))
            for c in s.class_candidates:
                mapping[c] = merged
    return mapping


def evaluate_source(tracer: Tracer, records: list[Record], jsonl_dir: Optional[Path], tta: bool, bootstrap: int,
                    seed: int = 0) -> dict:
    sets: list[DetectionSet] = []
    matched = correct = 0
    classes = list(TRACER_CLASSES)
    for record in records:
        result = tracer.recognize(open_record_image(record, jsonl_dir), None, tta=tta)
        merge = merged_classes(record)
        for name in merge.values():
            if name not in classes:
                classes.append(name)
        sets.append(DetectionSet(predictions=[(merge.get(d.cls, d.cls), list(d.box), d.score) for d in result.detections],
                                 truths=[(merge.get(s.cls, s.cls), list(s.box)) for s in record.symbols]))
        m, c = polarity_matches(record, result.detections)
        matched += m
        correct += c
    summary = mean_average_precision(sets, classes)
    if bootstrap and sets:
        rng = random.Random(seed)
        maps = []
        for _ in range(bootstrap):
            sample = [sets[rng.randrange(len(sets))] for _ in sets]
            v = mean_average_precision(sample, classes)["mAP"]
            if v is not None:
                maps.append(v)
        maps.sort()
        if maps:
            summary["mAP_ci95"] = [maps[int(0.025 * len(maps))], maps[min(len(maps) - 1, int(0.975 * len(maps)))]]
    summary["images"] = len(sets)
    summary["truth_boxes"] = sum(len(s.truths) for s in sets)
    summary["polarity"] = {"matched": matched, "accuracy": round(correct / matched, 4) if matched else None}
    return summary


def markdown(results: dict) -> str:
    lines = ["| source | images | boxes | mAP@0.5 [95% CI] | polarity acc. (n) | weakest classes (AP, n) |",
             "| --- | --- | --- | --- | --- | --- |"]
    for source, s in results.items():
        ci = s.get("mAP_ci95")
        ci_txt = f" [{ci[0]:.3f}, {ci[1]:.3f}]" if ci else ""
        per = [(c, v["ap"], v["n"]) for c, v in s["per_class"].items() if v["ap"] is not None]
        weakest = ", ".join(f"{c} ({ap:.2f}, {n})" for c, ap, n in sorted(per, key=lambda t: t[1])[:3])
        pol = s["polarity"]
        pol_txt = f"{pol['accuracy']:.3f} ({pol['matched']})" if pol["accuracy"] is not None else "n/a"
        lines.append(f"| {source} | {s['images']} | {s['truth_boxes']} | {s['mAP']}{ci_txt} | {pol_txt} | {weakest} |")
    return "\n".join(lines)


def main(argv: Optional[list[str]] = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--records", required=True)
    parser.add_argument("--sources", default="", help="comma-separated; default: every source in the file")
    parser.add_argument("--limit", type=int, default=0, help="images per source (0 = all)")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--threshold", type=float, default=0.3)
    parser.add_argument("--tta", action="store_true")
    parser.add_argument("--bootstrap", type=int, default=300)
    parser.add_argument("--out", default=None, help="prefix for .json and .md outputs")
    args = parser.parse_args(argv)
    records = read_jsonl(args.records)
    jsonl_dir = Path(args.records)
    sources = [s for s in args.sources.split(",") if s] or sorted({r.source for r in records})
    tracer = Tracer(args.checkpoint, device=args.device, threshold=args.threshold)
    results = {}
    for source in sources:
        rows = [r for r in records if r.source == source and r.symbols]
        if args.limit:
            rows = rows[:args.limit]
        if not rows:
            continue
        results[source] = evaluate_source(tracer, rows, jsonl_dir, args.tta, args.bootstrap)
        print(f"{source}: {results[source]['images']} images, mAP@0.5 {results[source]['mAP']}", flush=True)
    table = markdown(results)
    print(table)
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.with_suffix(".json").write_text(json.dumps(results, indent=2) + "\n")
        out.with_suffix(".md").write_text(table + "\n")


if __name__ == "__main__":
    main()
