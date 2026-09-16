"""Symbol-level detection metrics: per-class average precision at an IoU threshold (VOC-style)."""
from __future__ import annotations

from dataclasses import dataclass


def iou(a, b) -> float:
    ix0, iy0, ix1, iy1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    area = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / area if area > 0 else 0.0


@dataclass
class DetectionSet:
    """Predictions and truths for one image: lists of (cls, box, score) and (cls, box)."""
    predictions: list[tuple[str, list[float], float]]
    truths: list[tuple[str, list[float]]]


def average_precision(images: list[DetectionSet], cls: str, iou_threshold: float = 0.5) -> tuple[float, int]:
    """AP (all-point interpolation) for one class and the number of ground-truth boxes."""
    records = []   # (score, is_tp)
    n_truth = 0
    for img in images:
        truths = [b for c, b in img.truths if c == cls]
        n_truth += len(truths)
        used = [False] * len(truths)
        preds = sorted([(s, b) for c, b, s in img.predictions if c == cls], key=lambda t: -t[0])
        for score, box in preds:
            best, best_iou = -1, iou_threshold
            for j, tb in enumerate(truths):
                if used[j]:
                    continue
                v = iou(box, tb)
                if v >= best_iou:
                    best, best_iou = j, v
            if best >= 0:
                used[best] = True
                records.append((score, True))
            else:
                records.append((score, False))
    if n_truth == 0:
        return float("nan"), 0
    records.sort(key=lambda t: -t[0])
    tp = fp = 0
    precisions, recalls = [], []
    for _, is_tp in records:
        tp += is_tp
        fp += not is_tp
        precisions.append(tp / (tp + fp))
        recalls.append(tp / n_truth)
    # all-point interpolation
    ap = 0.0
    prev_r = 0.0
    for i in range(len(recalls)):
        p_max = max(precisions[i:]) if precisions else 0.0
        ap += (recalls[i] - prev_r) * p_max
        prev_r = recalls[i]
    return ap, n_truth


def mean_average_precision(images: list[DetectionSet], classes: list[str], iou_threshold: float = 0.5) -> dict:
    per_class = {}
    aps = []
    for c in classes:
        ap, n = average_precision(images, c, iou_threshold)
        per_class[c] = {"ap": None if n == 0 else round(ap, 4), "n": n}
        if n:
            aps.append(ap)
    return {"mAP": round(sum(aps) / len(aps), 4) if aps else None, "per_class": per_class}
