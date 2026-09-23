#!/usr/bin/env bash
# Second RunPod job: retrain the VLM on the real-photo netlists in labels/claude and score it end to end.
# Baseline first: the earlier adapter (5,000 synthetic + 85 teacher labels) on the 62 held-out real photos;
# then a fresh LoRA on synthetic circuits + the 272 training-split photos (x3), scored on the same 62 photos
# and on synthetic/real val. Writes /workspace/job.log, packs /workspace/results7.tar.gz, terminates its own
# pod after a grace window (a hard cap terminates it even if a stage hangs).
#
# Inputs, uploaded to /workspace before this file (the pod starts the job as soon as job.sh appears):
#   ml.tar.gz          the ml/ package with labels/claude (python scripts/runpod_control.py pack ml ml.tar.gz)
#   real_photos.tar.gz the labelled photos, laid out under dataroot/ as labels/claude's image paths expect
#                      (cghd/..., "Digitize-HCD Dataset/..."), any size; build_dataset downsizes them
#   adapter_v1/        the earlier LoRA adapter (adapter_config.json, adapter_model.safetensors)
# Required env: RUNPOD_API_KEY, RUNPOD_POD_ID (both set by runpod_control.py create).
set -uo pipefail
cd /workspace
export PYTHONUNBUFFERED=1 PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True TOKENIZERS_PARALLELISM=false
SYNTH_COUNT=${SYNTH_COUNT:-2000}
REAL_REPEAT=${REAL_REPEAT:-3}
VLM_EPOCHS=${VLM_EPOCHS:-2}
MAX_HOURS=${MAX_HOURS:-2.0}
GRACE_MIN=${GRACE_MIN:-15}
START=$(date +%s)

terminate_self() {
  echo "[$(date -u +%H:%M:%S)] terminating pod ${RUNPOD_POD_ID:-?}"
  curl -sS -m 30 -H "Content-Type: application/json" "https://api.runpod.io/graphql?api_key=${RUNPOD_API_KEY}" \
    -d "{\"query\":\"mutation { podTerminate(input: {podId: \\\"${RUNPOD_POD_ID}\\\"}) }\"}" || true
  sleep 60
  curl -sS -m 30 -H "Authorization: Bearer ${RUNPOD_API_KEY}" -X DELETE "https://rest.runpod.io/v1/pods/${RUNPOD_POD_ID}" || true
}
stage() { echo; echo "===== [$(date -u +%H:%M:%S)] $* (elapsed $(( ($(date +%s) - START) / 60 )) min) ====="; }
finish() {
  stage "packing results"
  cd /workspace
  tar czf results7.tar.gz --ignore-failed-read runs/vlm2 data/vlm_heldout/val.jsonl data/vlm/val.jsonl 2>/dev/null
  ls -la results7.tar.gz 2>/dev/null
  echo "JOB_DONE $(date -u +%H:%M:%S)"
  touch /workspace/DONE7
  echo "grace window ${GRACE_MIN} min for downloads, then self-terminate"
  sleep $(( GRACE_MIN * 60 ))
  terminate_self
}
( sleep $(( $(python3 -c "print(int(${MAX_HOURS} * 3600))") + GRACE_MIN * 60 + 600 )); echo "HARD CAP reached"; terminate_self ) &
run_capped() { timeout --foreground "$1" bash -c "$2"; local rc=$?; [ $rc -ne 0 ] && echo "step exited with $rc"; return 0; }

stage "environment"
echo "pod id set: $([ -n "${RUNPOD_POD_ID:-}" ] && echo yes || echo NO), api key set: $([ -n "${RUNPOD_API_KEY:-}" ] && echo yes || echo NO)"
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader || true
nproc; df -h /workspace | tail -1
cd /workspace && tar xzf ml.tar.gz && ls ml/labels/claude/ && mkdir -p data && tar xzf real_photos.tar.gz -C data && ls data/dataroot
ls /workspace/adapter_v1 | head -3

stage "install"
run_capped 20m "pip install -q -e 'ml[tracer,export,vlm,dev]' huggingface_hub 2>&1 | tail -2"
cd /workspace/ml
python -c "import torch, transformers, peft; print('torch', torch.__version__, 'transformers', transformers.__version__, 'peft', peft.__version__, 'cuda', torch.cuda.is_available())"

stage "synthetic data (${SYNTH_COUNT})"
run_capped 30m "python -m photomesh_ml.synth.generate --out /workspace/data/synth --count ${SYNTH_COUNT} --workers $(nproc) --seed 7"
ls /workspace/data/synth/labels | wc -l

stage "VLM datasets: synthetic + real x${REAL_REPEAT} (train/val), and the 62 held-out real photos"
REPEATS=""; for i in $(seq 1 ${REAL_REPEAT}); do REPEATS="${REPEATS} --distilled /workspace/ml/labels/claude/train.jsonl"; done
run_capped 20m "python -m photomesh_ml.vlm.build_dataset --synthetic /workspace/data/synth --limit-synthetic ${SYNTH_COUNT} ${REPEATS} --data-root /workspace/data/dataroot --out /workspace/data/vlm --max-side 1024"
run_capped 10m "python -m photomesh_ml.vlm.build_dataset --distilled /workspace/ml/labels/claude/heldout.jsonl --data-root /workspace/data/dataroot --out /workspace/data/vlm_heldout --max-side 1024 --val-fraction 1.0"
wc -l /workspace/data/vlm/train.jsonl /workspace/data/vlm/val.jsonl /workspace/data/vlm_heldout/val.jsonl
mkdir -p /workspace/runs/vlm2

stage "baseline: earlier adapter (synthetic + 85 teacher labels) on the 62 held-out real photos"
run_capped 25m "python -m photomesh_ml.vlm.infer --model Qwen/Qwen3-VL-2B-Instruct --adapter /workspace/adapter_v1 --jsonl /workspace/data/vlm_heldout/val.jsonl --batch 4 --out /workspace/runs/vlm2/preds_heldout_v1.jsonl"
run_capped 10m "python -m photomesh_ml.eval.benchmark --jsonl /workspace/data/vlm_heldout/val.jsonl --predictions /workspace/runs/vlm2/preds_heldout_v1.jsonl --out /workspace/runs/vlm2/bench_heldout_v1.jsonl"

stage "LoRA (${VLM_EPOCHS} epochs, ${SYNTH_COUNT} synthetic + 272 real x${REAL_REPEAT}; batch 2 x accum 8)"
run_capped 70m "python -m photomesh_ml.vlm.train_lora --model Qwen/Qwen3-VL-2B-Instruct --train /workspace/data/vlm/train.jsonl --val /workspace/data/vlm/val.jsonl \
  --out /workspace/runs/vlm2 --epochs ${VLM_EPOCHS} --batch 2 --grad-accum 8 --lr 1e-4 --lora-r 32 --bf16 --gradient-checkpointing --eval-every 400 --eval-samples 30 --max-pixels 802816"
ls /workspace/runs/vlm2

stage "new adapter on the 62 held-out real photos and on 120 synthetic/real val samples"
run_capped 25m "python -m photomesh_ml.vlm.infer --model Qwen/Qwen3-VL-2B-Instruct --adapter /workspace/runs/vlm2/adapter --jsonl /workspace/data/vlm_heldout/val.jsonl --batch 4 --out /workspace/runs/vlm2/preds_heldout_v2.jsonl"
run_capped 10m "python -m photomesh_ml.eval.benchmark --jsonl /workspace/data/vlm_heldout/val.jsonl --predictions /workspace/runs/vlm2/preds_heldout_v2.jsonl --out /workspace/runs/vlm2/bench_heldout_v2.jsonl"
run_capped 30m "python -m photomesh_ml.vlm.infer --model Qwen/Qwen3-VL-2B-Instruct --adapter /workspace/runs/vlm2/adapter --jsonl /workspace/data/vlm/val.jsonl --limit 120 --batch 4 --out /workspace/runs/vlm2/preds_val_v2.jsonl"
run_capped 10m "python -m photomesh_ml.eval.benchmark --jsonl /workspace/data/vlm/val.jsonl --limit 120 --predictions /workspace/runs/vlm2/preds_val_v2.jsonl --out /workspace/runs/vlm2/bench_val_v2.jsonl"

finish
