"""Held-out splits by group (drafter / volunteer bucket), so the model is scored on unseen hands."""
from __future__ import annotations

import hashlib
from typing import Iterable

from .records import Record


def split_name(record: Record, val_fraction: float = 0.1, test_fraction: float = 0.1, salt: str = "photomesh") -> str:
    """Deterministic train/val/test by hashing the group; synthetic data hashes by seed bucket."""
    key = f"{salt}:{record.source}:{record.group}".encode()
    h = int(hashlib.sha1(key).hexdigest()[:8], 16) / 0xFFFFFFFF
    if h < test_fraction:
        return "test"
    if h < test_fraction + val_fraction:
        return "val"
    return "train"


def partition(records: Iterable[Record], **kwargs) -> dict[str, list[Record]]:
    out: dict[str, list[Record]] = {"train": [], "val": [], "test": []}
    for r in records:
        out[split_name(r, **kwargs)].append(r)
    return out
