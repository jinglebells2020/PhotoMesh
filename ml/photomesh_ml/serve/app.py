"""PhotoMesh recognition server.

Sits in front of a vLLM instance serving the fine-tuned model and speaks the same protocol the app
already uses (POST /v1/chat/completions with an image part), so the app only needs a different
endpoint URL. Every answer is parsed and validated; if the small model fails validation or reports
low confidence, the request is escalated once to the cloud model (same tiering as the app does
today, but server-side and metered in one place).

Environment:
    VLM_ENDPOINT        http://127.0.0.1:8001/v1/chat/completions   (vLLM OpenAI server)
    VLM_MODEL           photomesh-vlm                                (served model name)
    FALLBACK_ENDPOINT   https://openrouter.ai/api/v1/chat/completions (optional)
    FALLBACK_MODEL      google/gemini-3.6-flash
    FALLBACK_API_KEY    ...
    MIN_CONFIDENCE      0.6
    CLIENT_KEYS         comma-separated bearer tokens the app must present (optional)

Run:  uvicorn photomesh_ml.serve.app:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import base64
import json
import os
import time
import uuid
from typing import Any, Optional

from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel

from ..schema import Circuit, ValidationError
from ..solver import solvable
from ..vlm.client import chat_json
from ..vlm.prompt import SYSTEM_PROMPT, USER_PROMPT

VLM_ENDPOINT = os.environ.get("VLM_ENDPOINT", "http://127.0.0.1:8001/v1/chat/completions")
VLM_MODEL = os.environ.get("VLM_MODEL", "photomesh-vlm")
FALLBACK_ENDPOINT = os.environ.get("FALLBACK_ENDPOINT")
FALLBACK_MODEL = os.environ.get("FALLBACK_MODEL", "google/gemini-3.6-flash")
FALLBACK_API_KEY = os.environ.get("FALLBACK_API_KEY")
MIN_CONFIDENCE = float(os.environ.get("MIN_CONFIDENCE", "0.6"))
CLIENT_KEYS = {k.strip() for k in os.environ.get("CLIENT_KEYS", "").split(",") if k.strip()}

app = FastAPI(title="PhotoMesh recognition")


def _check_auth(authorization: Optional[str]) -> None:
    if not CLIENT_KEYS:
        return
    token = (authorization or "").removeprefix("Bearer ").strip()
    if token not in CLIENT_KEYS:
        raise HTTPException(401, "invalid client key")


def _image_from_messages(messages: list[dict]) -> Optional[bytes]:
    for m in messages:
        content = m.get("content")
        if isinstance(content, list):
            for part in content:
                if part.get("type") == "image_url":
                    url = part.get("image_url", {}).get("url", "")
                    if url.startswith("data:"):
                        return base64.b64decode(url.split(",", 1)[1])
    return None


def _quality(text: str) -> tuple[Optional[Circuit], str]:
    """Would the app accept this answer? Returns the circuit and a reason when not."""
    try:
        circuit = Circuit.from_json(text)
    except ValidationError as exc:
        return None, f"unreadable: {exc}"
    if circuit.error:
        return circuit, "no_circuit"
    try:
        circuit.validated()
    except ValidationError as exc:
        return circuit, f"invalid: {exc}"
    if not solvable(circuit):
        return circuit, "unsolvable"
    if circuit.confidence is not None and circuit.confidence < MIN_CONFIDENCE:
        return circuit, f"low confidence {circuit.confidence}"
    return circuit, ""


def recognize(image_jpeg: bytes, system: str = SYSTEM_PROMPT, user_text: str = USER_PROMPT) -> dict[str, Any]:
    started = time.time()
    tiers: list[dict] = []
    local = chat_json(VLM_ENDPOINT, None, VLM_MODEL, system, user_text, image_jpeg, temperature=0.0, max_tokens=2048, timeout=60, retries=2)
    circuit, reason = _quality(local.text)
    tiers.append({"tier": "local", "model": local.model, "latency": round(local.latency, 2), "reason": reason})
    text, model = local.text, local.model
    if reason and reason != "no_circuit" and FALLBACK_ENDPOINT and FALLBACK_API_KEY:
        cloud = chat_json(FALLBACK_ENDPOINT, FALLBACK_API_KEY, FALLBACK_MODEL, system, user_text, image_jpeg, temperature=0.1, max_tokens=8000)
        circuit2, reason2 = _quality(cloud.text)
        tiers.append({"tier": "cloud", "model": cloud.model, "latency": round(cloud.latency, 2), "reason": reason2})
        if not reason2 or circuit is None:
            text, model, circuit = cloud.text, cloud.model, circuit2
    return {"text": text, "model": model, "tiers": tiers, "circuit": circuit.to_json() if circuit else None, "latency": round(time.time() - started, 2)}


class RecognizeRequest(BaseModel):
    image_base64: str


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True, "model": VLM_MODEL, "fallback": bool(FALLBACK_ENDPOINT and FALLBACK_API_KEY)}


@app.post("/v1/recognize")
def v1_recognize(req: RecognizeRequest, authorization: Optional[str] = Header(None)) -> dict:
    _check_auth(authorization)
    return recognize(base64.b64decode(req.image_base64))


@app.post("/v1/chat/completions")
async def chat_completions(request: Request, authorization: Optional[str] = Header(None)) -> dict:
    """OpenAI-shaped, so `OpenRouterClient` in the app works unchanged against this server."""
    _check_auth(authorization)
    body = await request.json()
    messages = body.get("messages") or []
    image = _image_from_messages(messages)
    if image is None:
        raise HTTPException(400, "an image part is required")
    system = next((m["content"] for m in messages if m.get("role") == "system" and isinstance(m.get("content"), str)), SYSTEM_PROMPT)
    user_text = USER_PROMPT
    for m in messages:
        if m.get("role") == "user" and isinstance(m.get("content"), list):
            for part in m["content"]:
                if part.get("type") == "text":
                    user_text = part.get("text") or user_text
    result = recognize(image, system, user_text)
    return {
        "id": f"chatcmpl-{uuid.uuid4().hex[:12]}", "object": "chat.completion", "created": int(time.time()), "model": result["model"],
        "choices": [{"index": 0, "message": {"role": "assistant", "content": result["text"]}, "finish_reason": "stop"}],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        "photomesh": {"tiers": result["tiers"], "latency": result["latency"]},
    }
