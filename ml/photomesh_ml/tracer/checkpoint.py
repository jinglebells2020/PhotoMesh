"""Checkpoint I/O shared by training, evaluation, inference and export."""
from __future__ import annotations

from pathlib import Path
from typing import Optional

import torch

from ..classes import TRACER_CLASSES
from .model import CircuitNet


def save_checkpoint(path: Path, model: CircuitNet, config: dict, epoch: int, metrics: Optional[dict], extra: Optional[dict] = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"model": model.state_dict(), "config": dict(config), "classes": TRACER_CLASSES, "epoch": epoch, "metrics": metrics}
    if extra:
        payload.update(extra)
    torch.save(payload, path)


def load_checkpoint(path: str | Path, device: torch.device | str = "cpu") -> tuple[CircuitNet, dict]:
    ckpt = torch.load(str(path), map_location=device)
    cfg = ckpt["config"]
    model = CircuitNet(cfg["backbone"], cfg.get("width", 64), pretrained=False).to(device)
    state = ckpt.get("ema") or ckpt["model"]
    model.load_state_dict(state)
    model.eval()
    return model, ckpt
