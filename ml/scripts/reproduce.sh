#!/usr/bin/env bash
# Full recipe, end to end. Adjust COUNT/EPOCHS/BACKBONE for the machine at hand.
#   bash scripts/reproduce.sh            # synthetic-only tracer run + evaluation
#   DHCD="data/Digitize-HCD Dataset" CGHD=data/cghd bash scripts/reproduce.sh   # with the real datasets
set -euo pipefail
cd "$(dirname "$0")/.."
COUNT=${COUNT:-20000}
EPOCHS=${EPOCHS:-40}
BACKBONE=${BACKBONE:-mobilenet_v3_large}
SIZE=${SIZE:-640}
OUT=${OUT:-runs/tracer}
DATA=${DATA:-data}

python -m photomesh_ml.synth.generate --out "$DATA/synth" --count "$COUNT" --seed 0 --workers "$(nproc)"
ARGS=(--synthetic "$DATA/synth")
[ -n "${DHCD:-}" ] && ARGS+=(--digitize-hcd "$DHCD")
[ -n "${CGHD:-}" ] && ARGS+=(--cghd "$CGHD")
[ -n "${SCANS:-}" ] && ARGS+=(--scans "$SCANS")
python -m photomesh_ml.data.convert_cli "${ARGS[@]}" --out "$DATA/records"

python -m photomesh_ml.tracer.train --train "$DATA/records/train.jsonl" --val "$DATA/records/val.jsonl" \
  --backbone "$BACKBONE" --size "$SIZE" --epochs "$EPOCHS" --batch 16 --out "$OUT" \
  --source-weights synthetic=1,cghd=3,digitize_hcd=2,mosaic=1 --e2e-records "$DATA/records/val.jsonl" --e2e-limit 100
python -m photomesh_ml.tracer.evaluate --checkpoint "$OUT/last.pt" --records "$DATA/records/test.jsonl" --ocr gt --tta --out "$OUT/results/test_gt_tta"
python -m photomesh_ml.tracer.evaluate --checkpoint "$OUT/last.pt" --records "$DATA/records/test.jsonl" --ocr none --out "$OUT/results/test_noocr"
python -m photomesh_ml.tracer.export_coreml --checkpoint "$OUT/last.pt" --size "$SIZE" --out "$OUT/CircuitNet.mlpackage"
echo "done: $OUT"
