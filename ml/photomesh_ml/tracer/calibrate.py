"""Calibrate the tracer's confidence into a probability that the reading is correct.

    python -m photomesh_ml.tracer.calibrate --checkpoint runs/tracer/last.pt --records data/records/val.jsonl --limit 300

Fits a logistic regression from assembly features (symbol scores, attached terminals, missing
values, validation, size, multi-scale agreement) to "the reading was correct" on labelled data and
stores the weights inside the checkpoint. `Tracer.recognize` then reports the calibrated
probability, which is what the phone compares against its escalation threshold.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import torch

from ..data.records import read_jsonl
from .evaluate import evaluate_records
from .infer import FEATURE_NAMES, Tracer


def fit_logistic(X: np.ndarray, y: np.ndarray, l2: float = 1e-2, steps: int = 3000, lr: float = 0.1) -> tuple[np.ndarray, float]:
    """Plain gradient descent on the regularised log-loss; small problem, no dependencies."""
    n, d = X.shape
    mean, std = X.mean(0), X.std(0) + 1e-6
    Z = (X - mean) / std
    w = np.zeros(d)
    b = float(np.log((y.mean() + 1e-3) / (1 - y.mean() + 1e-3)))
    for _ in range(steps):
        p = 1 / (1 + np.exp(-(Z @ w + b)))
        g = p - y
        w -= lr * (Z.T @ g / n + l2 * w)
        b -= lr * g.mean()
    # fold the standardisation into the weights
    w_raw = w / std
    b_raw = b - float((w * mean / std).sum())
    return w_raw, b_raw


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--records", action="append", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--tta", action="store_true")
    parser.add_argument("--ocr", choices=["gt", "none"], default="gt")
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    records = []
    base = None
    for p in args.records:
        base = base or Path(p)
        records += read_jsonl(p)
    tracer = Tracer(args.checkpoint, args.device)
    tracer.calibration = None   # collect raw features
    _, details = evaluate_records(tracer, records, base, args.limit, args.tta, args.ocr, verbose=True)
    X = np.array([[d["features"][k] for k in FEATURE_NAMES] for d in details], float)
    y = np.array([1.0 if d["score"]["correct"] else 0.0 for d in details])
    if y.sum() == 0 or y.sum() == len(y):
        raise SystemExit(f"cannot calibrate: {int(y.sum())} correct of {len(y)}")
    w, b = fit_logistic(X, y)
    p = 1 / (1 + np.exp(-(X @ w + b)))
    nll = float(-np.mean(y * np.log(p + 1e-9) + (1 - y) * np.log(1 - p + 1e-9)))
    brier = float(np.mean((p - y) ** 2))
    calibration = {"features": FEATURE_NAMES, "weights": [float(v) for v in w], "bias": float(b), "n": int(len(y)),
                   "positive_rate": float(y.mean()), "train_nll": nll, "train_brier": brier}
    ckpt = torch.load(args.checkpoint, map_location="cpu")
    ckpt["calibration"] = calibration
    torch.save(ckpt, args.checkpoint)
    print(json.dumps(calibration, indent=1))
    print("stored calibration in", args.checkpoint)


if __name__ == "__main__":
    main()
