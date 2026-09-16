"""Scale-to-zero deployment on Modal: pay only while a request is being served.

    pip install modal && modal setup
    modal volume create photomesh-models && modal volume put photomesh-models runs/vlm/merged /merged
    modal deploy photomesh_ml/serve/modal_app.py

The container keeps vLLM warm for `scaledown_window` seconds after the last request, then stops.
An L4 (24 GB) runs a 2B-4B model comfortably; cold starts are ~40-60 s, so keep a small window if
traffic is bursty or a longer one if a few users scan back-to-back.
"""
from __future__ import annotations

import os
import subprocess
import time

import modal

MODEL_DIR = "/models/merged"
SERVED_NAME = "photomesh-vlm"

image = (
    modal.Image.from_registry("vllm/vllm-openai:latest", add_python="3.11")
    .pip_install("fastapi>=0.110", "requests", "pillow", "numpy")
    .add_local_dir("photomesh_ml", remote_path="/srv/photomesh_ml")
    .env({"PYTHONPATH": "/srv"})
)
volume = modal.Volume.from_name("photomesh-models")
app = modal.App("photomesh-recognizer")


@app.cls(
    image=image, gpu="L4", volumes={"/models": volume}, scaledown_window=300, timeout=600,
    secrets=[modal.Secret.from_name("photomesh-fallback", required_keys=[])],  # FALLBACK_API_KEY etc., optional
)
@modal.concurrent(max_inputs=8)
class Recognizer:
    @modal.enter()
    def start(self):
        self.proc = subprocess.Popen([
            "python", "-m", "vllm.entrypoints.openai.api_server", "--model", MODEL_DIR, "--served-model-name", SERVED_NAME,
            "--port", "8001", "--max-model-len", "8192", "--gpu-memory-utilization", "0.85", "--limit-mm-per-prompt", '{"image": 1}',
        ])
        import requests
        for _ in range(150):
            try:
                if requests.get("http://127.0.0.1:8001/v1/models", timeout=2).ok:
                    break
            except Exception:  # noqa: BLE001
                pass
            time.sleep(2)
        os.environ.setdefault("VLM_ENDPOINT", "http://127.0.0.1:8001/v1/chat/completions")
        os.environ.setdefault("VLM_MODEL", SERVED_NAME)

    @modal.asgi_app()
    def web(self):
        from photomesh_ml.serve.app import app as fastapi_app
        return fastapi_app
