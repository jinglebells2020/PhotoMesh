"""Minimal OpenAI-compatible chat client (OpenRouter, vLLM, or our own server) with image input."""
from __future__ import annotations

import base64
import json
import time
from dataclasses import dataclass
from typing import Optional

import requests


@dataclass
class ChatResult:
    text: str
    model: str
    prompt_tokens: Optional[int]
    completion_tokens: Optional[int]
    reasoning_tokens: Optional[int]
    latency: float
    raw: dict


def image_data_url(jpeg_bytes: bytes) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(jpeg_bytes).decode("ascii")


def chat_json(endpoint: str, api_key: Optional[str], model: str, system: str, user_text: str, image_jpeg: Optional[bytes],
              temperature: float = 0.1, max_tokens: int = 4000, fast_reasoning: bool = False, timeout: float = 120,
              retries: int = 3, extra_body: Optional[dict] = None) -> ChatResult:
    content: list[dict] = [{"type": "text", "text": user_text}]
    if image_jpeg is not None:
        content.append({"type": "image_url", "image_url": {"url": image_data_url(image_jpeg)}})
    body: dict = {
        "model": model, "temperature": temperature, "max_tokens": max_tokens,
        "response_format": {"type": "json_object"},
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": content}],
    }
    if fast_reasoning:
        body["reasoning"] = {"effort": "low"}
    if extra_body:
        body.update(extra_body)
    headers = {"Content-Type": "application/json", "HTTP-Referer": "https://photomesh.app", "X-Title": "PhotoMesh ML"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    last: Optional[Exception] = None
    for attempt in range(retries):
        started = time.time()
        try:
            resp = requests.post(endpoint, headers=headers, data=json.dumps(body), timeout=timeout)
            if resp.status_code >= 500 or resp.status_code == 429:
                raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:200]}")
            resp.raise_for_status()
            data = resp.json()
            if "error" in data and data["error"]:
                raise RuntimeError(str(data["error"])[:300])
            choice = (data.get("choices") or [{}])[0]
            message = choice.get("message", {})
            text = message.get("content")
            if isinstance(text, list):
                text = "".join(part.get("text", "") for part in text)
            if not text:
                raise RuntimeError(f"empty content (finish_reason={choice.get('finish_reason')})")
            usage = data.get("usage") or {}
            details = usage.get("completion_tokens_details") or {}
            return ChatResult(text=text, model=data.get("model", model), prompt_tokens=usage.get("prompt_tokens"),
                              completion_tokens=usage.get("completion_tokens"), reasoning_tokens=details.get("reasoning_tokens"),
                              latency=time.time() - started, raw=data)
        except Exception as exc:  # noqa: BLE001
            last = exc
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"chat request failed after {retries} attempts: {last}")


def jpeg_bytes(image_path: str, max_side: int = 1280, quality: int = 85) -> tuple[bytes, int, int]:
    """Same preprocessing as the app: longest side <= max_side, JPEG."""
    import io
    from PIL import Image, ImageOps
    img = ImageOps.exif_transpose(Image.open(image_path)).convert("RGB")
    w, h = img.size
    scale = min(1.0, max_side / max(w, h))
    if scale < 1.0:
        img = img.resize((int(round(w * scale)), int(round(h * scale))), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality)
    return buf.getvalue(), img.width, img.height
