#!/usr/bin/env bash
# The whole GPU recipe as one unattended job for a RunPod pod. Runs under a hard time cap, writes
# progress to /workspace/job.log, packs artifacts into /workspace/results.tar.gz, then terminates
# its own pod after a grace window (so a forgotten pod cannot keep billing).
#
# Required env: RUNPOD_API_KEY, RUNPOD_POD_ID (set by RunPod), OPENROUTER_API_KEY (for distillation).
# Tunables: SYNTH_COUNT, TRACER_EPOCHS, TRACER_SIZE, DISTILL_LIMIT, VLM_SYNTH, VLM_EPOCHS, MAX_HOURS, GRACE_MIN.
set -uo pipefail
cd /workspace
export PYTHONUNBUFFERED=1
SYNTH_COUNT=${SYNTH_COUNT:-12000}
TRACER_EPOCHS=${TRACER_EPOCHS:-12}
TRACER_SIZE=${TRACER_SIZE:-640}
DISTILL_LIMIT=${DISTILL_LIMIT:-1000}
VLM_SYNTH=${VLM_SYNTH:-5000}
VLM_EPOCHS=${VLM_EPOCHS:-1}
MAX_HOURS=${MAX_HOURS:-5}
GRACE_MIN=${GRACE_MIN:-45}
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
  tar czf results.tar.gz --ignore-failed-read runs/tracer/results runs/tracer/last.pt runs/tracer/log.jsonl runs/tracer/CircuitNet.mlpackage \
      runs/vlm/adapter runs/vlm/log.jsonl runs/vlm/final_eval.json runs/vlm/bench_student.summary.json runs/vlm/bench_teacher.summary.json \
      runs/vlm/bench_student.jsonl data/distill/train.jsonl data/distill/train.rejected.jsonl 2>/dev/null
  ls -la results.tar.gz 2>/dev/null
  echo "JOB_DONE $(date -u +%H:%M:%S)"
  touch /workspace/DONE
  echo "grace window ${GRACE_MIN} min for downloads, then self-terminate"
  sleep $(( GRACE_MIN * 60 ))
  terminate_self
}
# hard cap: whatever happens, the pod dies after MAX_HOURS + grace
( sleep $(( MAX_HOURS * 3600 + GRACE_MIN * 60 + 600 )); echo "HARD CAP reached"; terminate_self ) &
run_capped() { timeout --foreground "$1" bash -c "$2"; local rc=$?; [ $rc -ne 0 ] && echo "step exited with $rc"; return 0; }

stage "environment"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true
nproc; free -g | head -2; df -h /workspace | tail -1
python -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"

stage "install"
tar xzf ml.tar.gz
pip install -q -e "ml[tracer,export,vlm,dev]" huggingface_hub 2>&1 | tail -2
python -c "import transformers, peft, coremltools; print('transformers', transformers.__version__, 'peft', peft.__version__)"
cd /workspace/ml

stage "synthetic data (${SYNTH_COUNT})"
run_capped 40m "python -m photomesh_ml.synth.generate --out /workspace/data/synth --count ${SYNTH_COUNT} --seed 0 --workers $(nproc)"

stage "real datasets"
mkdir -p /workspace/data
run_capped 30m "cd /workspace/data && curl -sS -L -o dhcd.zip 'https://prod-dcd-datasets-public-files-eu-west-1.s3.eu-west-1.amazonaws.com/c4ec3d20-38ea-4f1d-96f9-cd504e998a6e' && python -c \"import zipfile; zipfile.ZipFile('dhcd.zip').extractall('dhcd')\" && rm -f dhcd.zip && ls dhcd"
run_capped 40m "python -c \"from huggingface_hub import snapshot_download; snapshot_download('lowercaseonly/cghd', repo_type='dataset', local_dir='/workspace/data/cghd', max_workers=16)\" && ls /workspace/data/cghd | head"

stage "convert + downsize"
run_capped 30m "python -m photomesh_ml.data.convert_cli --synthetic /workspace/data/synth --digitize-hcd '/workspace/data/dhcd/Digitize-HCD Dataset' --cghd /workspace/data/cghd --out /workspace/data/records"
for split in train val test; do
  run_capped 40m "python -m photomesh_ml.data.downsize --records /workspace/data/records/${split}.jsonl --out /workspace/data/records_small/${split}.jsonl --max-side 1600 --workers $(nproc)"
done

stage "tracer training (${TRACER_EPOCHS} epochs at ${TRACER_SIZE}px)"
run_capped 150m "python -m photomesh_ml.tracer.train --train /workspace/data/records_small/train.jsonl --val /workspace/data/records_small/val.jsonl \
  --backbone mobilenet_v3_large --size ${TRACER_SIZE} --epochs ${TRACER_EPOCHS} --batch 16 --workers $(( $(nproc) > 12 ? 12 : $(nproc) )) \
  --source-weights synthetic=1,cghd=3,digitize_hcd=2,mosaic=1 --balance-rare 1.0 --e2e-records /workspace/data/records_small/val.jsonl --e2e-limit 60 \
  --out /workspace/runs/tracer"

stage "tracer evaluation + calibration + export"
run_capped 40m "DEVICE=cuda bash scripts/evaluate_run.sh /workspace/runs/tracer /workspace/data/records_small 300"
run_capped 15m "python -m photomesh_ml.tracer.export_coreml --checkpoint /workspace/runs/tracer/results/calibrated.pt --size ${TRACER_SIZE} --out /workspace/runs/tracer/CircuitNet.mlpackage"

stage "teacher distillation (${DISTILL_LIMIT} real images)"
run_capped 60m "python -m photomesh_ml.vlm.distill --records /workspace/data/records_small/train.jsonl --sources digitize_hcd,cghd --out /workspace/data/distill/train.jsonl \
  --model google/gemini-3.6-flash --samples 1 --workers 8 --limit ${DISTILL_LIMIT} --max-side 1280"

stage "VLM dataset + LoRA (${VLM_EPOCHS} epoch, ${VLM_SYNTH} synthetic + distilled)"
run_capped 20m "python -m photomesh_ml.vlm.build_dataset --synthetic /workspace/data/synth --limit-synthetic ${VLM_SYNTH} --distilled /workspace/data/distill/train.jsonl --out /workspace/data/vlm --max-side 1024"
run_capped 110m "python -m photomesh_ml.vlm.train_lora --model Qwen/Qwen3-VL-2B-Instruct --train /workspace/data/vlm/train.jsonl --val /workspace/data/vlm/val.jsonl \
  --out /workspace/runs/vlm --epochs ${VLM_EPOCHS} --batch 4 --grad-accum 4 --lr 1e-4 --lora-r 32 --bf16 --gradient-checkpointing --eval-every 400 --eval-samples 30 --max-pixels 802816"

stage "VLM evaluation: student vs teacher on the held-out set"
run_capped 40m "python -m photomesh_ml.vlm.infer --model Qwen/Qwen3-VL-2B-Instruct --adapter /workspace/runs/vlm/adapter --jsonl /workspace/data/vlm/val.jsonl --limit 120 --out /workspace/runs/vlm/preds_val.jsonl"
run_capped 10m "python -m photomesh_ml.eval.benchmark --jsonl /workspace/data/vlm/val.jsonl --limit 120 --predictions /workspace/runs/vlm/preds_val.jsonl --out /workspace/runs/vlm/bench_student.jsonl"
run_capped 20m "python -m photomesh_ml.eval.benchmark --jsonl /workspace/data/vlm/val.jsonl --limit 60 --model google/gemini-3.5-flash-lite --fast --out /workspace/runs/vlm/bench_teacher.jsonl"

cd /workspace
finish
