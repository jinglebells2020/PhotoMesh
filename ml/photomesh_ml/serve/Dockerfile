# vLLM serving the merged fine-tuned model + the PhotoMesh front (validation, escalation).
# Build:  docker build -t photomesh-recognizer -f photomesh_ml/serve/Dockerfile .
# Run:    docker run --gpus all -p 8000:8000 -v $PWD/runs/vlm/merged:/model \
#             -e FALLBACK_ENDPOINT=https://openrouter.ai/api/v1/chat/completions -e FALLBACK_API_KEY=... photomesh-recognizer
FROM vllm/vllm-openai:latest

WORKDIR /srv
COPY pyproject.toml /srv/
COPY photomesh_ml /srv/photomesh_ml
RUN pip install --no-cache-dir "fastapi>=0.110" "uvicorn>=0.29" requests pillow numpy && pip install --no-cache-dir -e /srv

ENV MODEL_PATH=/model \
    VLM_MODEL=photomesh-vlm \
    VLM_ENDPOINT=http://127.0.0.1:8001/v1/chat/completions \
    MAX_MODEL_LEN=8192 \
    GPU_MEMORY_UTILIZATION=0.85

COPY photomesh_ml/serve/start.sh /srv/start.sh
RUN chmod +x /srv/start.sh
EXPOSE 8000
ENTRYPOINT ["/srv/start.sh"]
