"""Evaluate the tracer end to end on records that carry a netlist (synthetic, distilled, app scans).

    python -m photomesh_ml.tracer.evaluate --checkpoint runs/tracer/last.pt --records data/records/val.jsonl \
        --limit 300 --ocr gt --tta --out results/tracer_val

Reports the user-facing metrics (correct / topology / answers with bootstrap 95% intervals),
breakdowns by drawing style and photo augmentation, and symbol-level mAP@0.5 per class.
`--ocr gt` feeds the record's own text labels to the assembler (isolates the tracer from OCR),
`--ocr none` assembles without any text (values missing, topology still scored).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Optional

import numpy as np

from ..classes import TRACER_CLASSES
from ..data.records import Record, open_record_image, read_jsonl
from ..eval.detection import DetectionSet, mean_average_precision
from ..eval.metrics import Score, score_prediction, summarize, summarize_by
from ..schema import Circuit
from ..textparse import parse_text
from .assemble import TextItem
from .infer import Tracer, TracerResult


def truth_from_record(record: Record) -> Optional[Circuit]:
    return Circuit.from_json(record.circuit) if record.circuit else None


def ocr_from_record(record: Record) -> list[TextItem]:
    return [TextItem(list(s.box), s.text) for s in record.symbols if s.cls == "text" and s.text]


def labelled_ids(record: Record) -> set[str]:
    """Element ids whose name is written in the drawing (those must be kept by a recognizer)."""
    out = set()
    for s in record.symbols:
        if s.cls == "text" and s.text and s.id:
            parsed = parse_text(s.text)
            if parsed.kind == "name" or (parsed.kind == "value" and parsed.name):
                out.add(s.id)
    return out


def evaluate_records(tracer: Tracer, records: list[Record], jsonl_dir: Optional[Path], limit: int = 0, tta: bool = False,
                     ocr: str = "gt", verbose: bool = False) -> tuple[dict, list[dict]]:
    rows = [r for r in records if r.circuit]
    if limit:
        rows = rows[:limit]
    scores: list[Score] = []
    details: list[dict] = []
    det_sets: list[DetectionSet] = []
    styles, photos, sizes = [], [], []
    for i, record in enumerate(rows):
        image = open_record_image(record, jsonl_dir)
        texts = ocr_from_record(record) if ocr == "gt" else None
        result: TracerResult = tracer.recognize(image, texts, tta=tta)
        truth = truth_from_record(record)
        s = score_prediction(result.circuit, truth, labelled_ids(record))
        scores.append(s)
        styles.append(record.meta.get("style", record.source))
        photos.append("photo" if record.meta.get("photo") else "flat")
        n = len(truth.components) if truth else 0
        sizes.append("1-3 elements" if n <= 3 else ("4-5 elements" if n <= 5 else "6+ elements"))
        det_sets.append(DetectionSet(
            predictions=[(d.cls, list(d.box), d.score) for d in result.detections],
            truths=[(sym.cls, list(sym.box)) for sym in record.symbols],
        ))
        details.append({"image": record.image, "source": record.source, "style": styles[-1], "photo": photos[-1],
                        "confidence": result.confidence, "agreement": result.agreement, "latency": round(result.latency, 3),
                        "features": result.features, "prediction": result.circuit.to_json(3), "score": s.as_dict()})
        if verbose and (i + 1) % 20 == 0:
            print(f"{i + 1}/{len(rows)} correct so far {sum(x.correct for x in scores) / len(scores):.3f}", flush=True)
    confusion = _confusion(det_sets)
    summary = {
        "overall": summarize(scores),
        "confusion": confusion,
        "by_style": summarize_by(scores, styles),
        "by_photo": summarize_by(scores, photos),
        "by_size": summarize_by(scores, sizes),
        "detection": mean_average_precision(det_sets, TRACER_CLASSES),
        "mean_latency_s": sum(d["latency"] for d in details) / max(1, len(details)),
    }
    if scores:
        confs = np.array([d["confidence"] for d in details], float)
        ys = np.array([1.0 if s.correct else 0.0 for s in scores])
        summary["confidence"] = {"brier": round(float(np.mean((confs - ys) ** 2)), 4), "calibrated": bool(tracer.calibration),
                                 "reliability": [{"bin": f"{lo:.1f}-{lo + 0.2:.1f}", "n": int(((confs >= lo) & (confs < lo + 0.2 + (1e-9 if lo >= 0.8 else 0))).sum()),
                                                  "mean_conf": round(float(confs[(confs >= lo) & (confs < lo + 0.2 + (1e-9 if lo >= 0.8 else 0))].mean()), 3) if ((confs >= lo) & (confs < lo + 0.2 + (1e-9 if lo >= 0.8 else 0))).any() else None,
                                                  "accuracy": round(float(ys[(confs >= lo) & (confs < lo + 0.2 + (1e-9 if lo >= 0.8 else 0))].mean()), 3) if ((confs >= lo) & (confs < lo + 0.2 + (1e-9 if lo >= 0.8 else 0))).any() else None}
                                                 for lo in (0.0, 0.2, 0.4, 0.6, 0.8)]}
    # Confidence as a gate: how well does it separate right from wrong readings?
    if scores:
        pairs = sorted(zip([d["confidence"] for d in details], [s.correct for s in scores]))
        best = None
        for k in range(1, len(pairs)):
            thr = pairs[k][0]
            kept = [c for conf, c in pairs if conf >= thr]
            if kept:
                precision = sum(kept) / len(kept)
                coverage = len(kept) / len(pairs)
                if precision >= 0.95 and (best is None or coverage > best["coverage"]):
                    best = {"threshold": round(thr, 3), "coverage": round(coverage, 3), "precision": round(precision, 3)}
        summary["confidence_gate_95"] = best
    return summary, details


def _confusion(det_sets: list[DetectionSet], iou_threshold: float = 0.5) -> dict:
    """truth class -> predicted class counts for box-matched pairs (class-agnostic matching), plus misses."""
    from ..eval.detection import iou
    table: dict[str, dict[str, int]] = {}
    for ds in det_sets:
        used = set()
        for tcls, tbox in ds.truths:
            best, best_iou = None, iou_threshold
            for j, (pcls, pbox, score) in enumerate(ds.predictions):
                if j in used:
                    continue
                v = iou(tbox, pbox)
                if v >= best_iou:
                    best, best_iou = j, v
            row = table.setdefault(tcls, {})
            if best is None:
                row["(missed)"] = row.get("(missed)", 0) + 1
            else:
                used.add(best)
                pcls = ds.predictions[best][0]
                row[pcls] = row.get(pcls, 0) + 1
    return {k: dict(sorted(v.items(), key=lambda kv: -kv[1])) for k, v in sorted(table.items())}


def markdown_table(summary: dict) -> str:
    o = summary["overall"]
    lines = ["| metric | value |", "| --- | --- |"]
    for key in ("n", "correct", "correct_ci95", "topology_ok", "topology_ci95", "structure_ok", "answer_ok", "component_recall", "component_precision", "kind_acc", "value_acc", "ground_ok", "unsupported_ok"):
        if key in o:
            v = o[key]
            lines.append(f"| {key} | {v if not isinstance(v, float) else round(v, 3)} |")
    lines.append(f"| symbol mAP@0.5 | {summary['detection']['mAP']} |")
    lines.append(f"| mean latency (s) | {round(summary['mean_latency_s'], 3)} |")
    if summary.get("confidence_gate_95"):
        lines.append(f"| coverage at 95% precision | {summary['confidence_gate_95']} |")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--records", action="append", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--ocr", choices=["gt", "none"], default="gt")
    parser.add_argument("--tta", action="store_true")
    parser.add_argument("--threshold", type=float, default=0.3)
    parser.add_argument("--wire-threshold", type=float, default=0.4)
    parser.add_argument("--body-removal", choices=["span", "box"], default="span")
    parser.add_argument("--closing", type=int, default=-1, help="closing radius in px (-1 = scaled with the input size)")
    parser.add_argument("--no-unit-kinds", action="store_true", help="ablation: do not let OCR units correct symbol kinds")
    parser.add_argument("--out", default=None, help="prefix for .jsonl details, .summary.json and .md")
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    records: list[Record] = []
    base = None
    for p in args.records:
        base = base or Path(p)
        records += read_jsonl(p)
    tracer = Tracer(args.checkpoint, args.device, args.threshold, args.wire_threshold, args.closing, args.body_removal, not args.no_unit_kinds)
    summary, details = evaluate_records(tracer, records, base, args.limit, args.tta, args.ocr, verbose=True)
    print(json.dumps(summary, indent=1))
    print(markdown_table(summary))
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        with open(str(out) + ".jsonl", "w", encoding="utf-8") as f:
            for d in details:
                f.write(json.dumps(d, ensure_ascii=False) + "\n")
        Path(str(out) + ".summary.json").write_text(json.dumps(summary, indent=1))
        Path(str(out) + ".md").write_text(markdown_table(summary) + "\n")
        print("wrote", str(out) + ".{jsonl,summary.json,md}")


if __name__ == "__main__":
    main()
