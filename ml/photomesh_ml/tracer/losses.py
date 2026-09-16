"""Losses for CircuitNet with per-sample / per-region masking for partially-annotated sources."""
from __future__ import annotations

import torch
import torch.nn.functional as F


def focal_heatmap(pred_logits: torch.Tensor, gt: torch.Tensor, weight: torch.Tensor | None = None,
                  alpha: float = 2.0, beta: float = 4.0) -> torch.Tensor:
    """CenterNet penalty-reduced focal loss on logits; `weight` zeroes ignored cells."""
    pred = torch.sigmoid(pred_logits).clamp(1e-4, 1 - 1e-4)
    pos = (gt >= 0.999).float()
    neg = 1.0 - pos
    neg_weights = torch.pow(1 - gt, beta)
    pos_loss = torch.log(pred) * torch.pow(1 - pred, alpha) * pos
    neg_loss = torch.log(1 - pred) * torch.pow(pred, alpha) * neg_weights * neg
    if weight is not None:
        pos_loss = pos_loss * weight
        neg_loss = neg_loss * weight
    num_pos = pos.sum().clamp(min=1.0)
    return -(pos_loss.sum() + neg_loss.sum()) / num_pos


def gather_at(feat: torch.Tensor, index: torch.Tensor) -> torch.Tensor:
    """feat [B, C, h, w], index [B, N] flat -> [B, N, C]."""
    B, C, h, w = feat.shape
    flat = feat.view(B, C, h * w).permute(0, 2, 1)
    idx = index.unsqueeze(-1).expand(-1, -1, C)
    return flat.gather(1, idx)


def regression_l1(feat: torch.Tensor, index: torch.Tensor, target: torch.Tensor, mask: torch.Tensor) -> torch.Tensor:
    pred = gather_at(feat, index)
    m = mask.unsqueeze(-1).expand_as(pred)
    return (F.l1_loss(pred * m, target * m, reduction="sum") / (m.sum() + 1e-4))


def polarity_ce(feat: torch.Tensor, index: torch.Tensor, target_dist: torch.Tensor, weight: torch.Tensor) -> torch.Tensor:
    logits = gather_at(feat, index)                      # [B, N, 4]
    logp = F.log_softmax(logits, dim=-1)
    ce = -(target_dist * logp).sum(-1)                   # [B, N]
    return (ce * weight).sum() / (weight.sum() + 1e-4)


def masked_bce_dice(pred_logits: torch.Tensor, gt: torch.Tensor, sample_weight: torch.Tensor) -> torch.Tensor:
    """BCE + Dice on [B, 1, h, w], each sample weighted (0 disables it)."""
    w = sample_weight.view(-1, 1, 1, 1)
    bce = F.binary_cross_entropy_with_logits(pred_logits, gt, reduction="none")
    bce = (bce * w).sum() / (w.sum() * gt[0].numel() + 1e-4)
    p = torch.sigmoid(pred_logits)
    inter = (p * gt * w).sum(dim=(1, 2, 3))
    denom = (p * w).sum(dim=(1, 2, 3)) + (gt * w).sum(dim=(1, 2, 3))
    dice = 1 - (2 * inter + 1) / (denom + 1)
    dice = (dice * sample_weight).sum() / (sample_weight.sum() + 1e-4)
    return bce + dice


def masked_focal(pred_logits: torch.Tensor, gt: torch.Tensor, sample_weight: torch.Tensor) -> torch.Tensor:
    w = sample_weight.view(-1, 1, 1, 1).expand_as(gt)
    return focal_heatmap(pred_logits, gt, w)


def total_loss(out: dict[str, torch.Tensor], batch: dict[str, torch.Tensor], weights: dict[str, float] | None = None) -> tuple[torch.Tensor, dict[str, float]]:
    weights = weights or {}
    terms = {
        "heat": focal_heatmap(out["symbol_heat"], batch["heat"], batch["heat_weight"]),
        "size": 0.1 * regression_l1(out["symbol_size"], batch["index"], batch["size"], batch["reg_mask"]),
        "off": regression_l1(out["symbol_off"], batch["index"], batch["offset"], batch["reg_mask"]),
        "polarity": polarity_ce(out["polarity"], batch["index"], batch["polarity"], batch["polarity_weight"] * batch["reg_mask"]),
        "wire": masked_bce_dice(out["wire"], batch["wire"], batch["wire_weight"]),
        "junction": masked_focal(out["junction"], batch["junction"], batch["junction_weight"]),
        "terminal": masked_focal(out["terminal"], batch["terminal"], batch["terminal_weight"]),
    }
    total = sum(weights.get(k, 1.0) * v for k, v in terms.items())
    return total, {k: float(v.detach()) for k, v in terms.items()}
