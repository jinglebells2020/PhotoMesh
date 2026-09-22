#!/usr/bin/env bash
# Final evaluation of a tracer run: main result, ablations, calibration, training report.
#   bash scripts/evaluate_run.sh RUN_DIR RECORDS_DIR [LIMIT]
# RECORDS_DIR must hold val.jsonl (calibration) and test.jsonl (reporting).
set -euo pipefail
cd "$(dirname "$0")/.."
RUN=$1; REC=$2; LIMIT=${3:-0}; DEVICE=${DEVICE:-cpu}
OUT="$RUN/results"; mkdir -p "$OUT"
CK="$RUN/last.pt"
python -m photomesh_ml.tracer.report --run "$RUN" --out "$OUT/training.md"
python -m photomesh_ml.tracer.evaluate --checkpoint "$CK" --records "$REC/test.jsonl" --limit "$LIMIT" --ocr gt --device "$DEVICE" --out "$OUT/test_gt"
python -m photomesh_ml.tracer.evaluate --checkpoint "$CK" --records "$REC/test.jsonl" --limit "$LIMIT" --ocr gt --tta --device "$DEVICE" --out "$OUT/test_gt_tta"
python -m photomesh_ml.tracer.evaluate --checkpoint "$CK" --records "$REC/test.jsonl" --limit "$LIMIT" --ocr none --device "$DEVICE" --out "$OUT/test_noocr"
python -m photomesh_ml.tracer.evaluate --checkpoint "$CK" --records "$REC/test.jsonl" --limit "$LIMIT" --ocr gt --no-unit-kinds --device "$DEVICE" --out "$OUT/ablation_no_unit_kinds"
python -m photomesh_ml.tracer.evaluate --checkpoint "$CK" --records "$REC/test.jsonl" --limit "$LIMIT" --ocr gt --body-removal box --closing 1 --wire-threshold 0.5 --device "$DEVICE" --out "$OUT/ablation_assembler_v1"
cp "$CK" "$OUT/calibrated.pt"
python -m photomesh_ml.tracer.calibrate --checkpoint "$OUT/calibrated.pt" --records "$REC/val.jsonl" --limit "$LIMIT" --ocr gt --device "$DEVICE"
python -m photomesh_ml.tracer.evaluate --checkpoint "$OUT/calibrated.pt" --records "$REC/test.jsonl" --limit "$LIMIT" --ocr gt --device "$DEVICE" --out "$OUT/test_gt_calibrated"
python - "$OUT" <<'PYEOF'
import json, sys
from pathlib import Path
out = Path(sys.argv[1])
rows = []
for name, label in [("test_gt", "tracer, GT text"), ("test_gt_tta", "+ three-scale majority (TTA)"), ("test_noocr", "tracer, no text"),
                    ("ablation_no_unit_kinds", "ablation: no unit-based kinds"), ("ablation_assembler_v1", "ablation: box removal, closing 1, wire 0.5"),
                    ("test_gt_calibrated", "calibrated confidence (fit on val)")]:
    p = out / f"{name}.summary.json"
    if not p.exists():
        continue
    s = json.load(open(p)); o = s["overall"]
    ci = o.get("correct_ci95", ["", ""])
    gate = s.get("confidence_gate_95") or {}
    rows.append(f"| {label} | {o['correct']:.3f} [{ci[0]}, {ci[1]}] | {o['topology_ok']:.3f} | {o.get('structure_ok', 0):.3f} | {o['answer_ok']:.3f} | {o['kind_acc']:.3f} | {s['detection']['mAP']} | {gate.get('coverage', '')} | {s.get('confidence', {}).get('brier', '')} |")
table = "| setting | correct [95% CI] | topology | structure | answers | kind acc | mAP@0.5 | coverage@95% prec. | Brier |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n" + "\n".join(rows)
(out / "summary.md").write_text(table + "\n")
print(table)
PYEOF
echo "results in $OUT"
