"""Turn a run's log.jsonl into a markdown training report (loss curves, mAP, wire IoU, end-to-end).

    python -m photomesh_ml.tracer.report --run runs/tracer [--out runs/tracer/report.md]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def build_report(run: Path) -> str:
    epochs: dict[int, dict] = {}
    for line in (run / "log.jsonl").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        entry = json.loads(line)
        e = entry.get("epoch")
        if e is None:
            continue
        row = epochs.setdefault(e, {})
        if "train" in entry:
            row["loss"] = entry["train"].get("total")
            row["heat"] = entry["train"].get("heat")
            row["wire_loss"] = entry["train"].get("wire")
            row["seconds"] = entry.get("seconds")
            val = entry.get("val") or {}
            row["mAP"] = (val.get("detection") or {}).get("mAP")
            row["P"] = (val.get("all") or {}).get("precision")
            row["R"] = (val.get("all") or {}).get("recall")
            row["wire_iou"] = val.get("wire_iou")
        if "e2e" in entry:
            overall = entry["e2e"].get("overall", entry["e2e"])
            row["e2e_correct"] = overall.get("correct")
            row["e2e_topology"] = overall.get("topology_ok")
    lines = ["| epoch | loss | heat | wire loss | mAP@0.5 | P | R | wire IoU | e2e correct | e2e topology | s/epoch |", "| --- " * 11 + "|"]

    def f(v, digits=3):
        return "" if v is None else (f"{v:.{digits}f}" if isinstance(v, float) else str(v))

    for e in sorted(epochs):
        r = epochs[e]
        lines.append(f"| {e} | {f(r.get('loss'))} | {f(r.get('heat'))} | {f(r.get('wire_loss'))} | {f(r.get('mAP'))} | {f(r.get('P'))} | {f(r.get('R'))} | {f(r.get('wire_iou'))} | {f(r.get('e2e_correct'))} | {f(r.get('e2e_topology'))} | {f(r.get('seconds'), 0)} |")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()
    text = build_report(Path(args.run))
    print(text)
    if args.out:
        Path(args.out).write_text(text + "\n")


if __name__ == "__main__":
    main()
