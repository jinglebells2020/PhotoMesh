#!/usr/bin/env bash
# Starts vLLM (OpenAI server on :8001) and the PhotoMesh front (on :8000).
set -euo pipefail
python -m vllm.entrypoints.openai.api_server \
  --model "${MODEL_PATH}" --served-model-name "${VLM_MODEL}" --port 8001 \
  --max-model-len "${MAX_MODEL_LEN}" --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
  --limit-mm-per-prompt '{"image": 1}' --dtype auto ${VLLM_EXTRA_ARGS:-} &
for i in $(seq 1 120); do
  if curl -sf http://127.0.0.1:8001/v1/models >/dev/null 2>&1; then break; fi
  sleep 2
done
exec uvicorn photomesh_ml.serve.app:app --host 0.0.0.0 --port 8000 --workers 2
