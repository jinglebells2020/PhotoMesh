"""Train CircuitNet.

    python -m photomesh_ml.tracer.train --train data/records/train.jsonl --val data/records/val.jsonl \
        --backbone mobilenet_v3_large --size 640 --epochs 40 --batch 16 --out runs/tracer

Checkpoints hold the model, the config and the class list; `--resume` continues a run.
"""
from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path
from typing import Optional

import numpy as np
import torch
from torch.utils.data import DataLoader

from ..classes import TRACER_CLASSES
from ..data.records import Record, read_jsonl
from .assemble import decode_symbols
from .dataset import TracerDataset, collate
from .losses import total_loss
from .model import CircuitNet, normalize


def load_records(paths: list[str]) -> tuple[list[Record], Optional[Path]]:
    records: list[Record] = []
    base: Optional[Path] = None
    for p in paths:
        records += read_jsonl(p)
        base = base or Path(p)
    return records, base


def evaluate(model: CircuitNet, loader: DataLoader, device: torch.device, stride: int = 4, threshold: float = 0.3) -> dict:
    """Per-class precision/recall of symbol centres (IoU >= 0.5) and wire IoU on annotated samples."""
    model.eval()
    tp = {c: 0 for c in TRACER_CLASSES}
    fp = {c: 0 for c in TRACER_CLASSES}
    fn = {c: 0 for c in TRACER_CLASSES}
    wire_inter = wire_union = 0.0
    with torch.no_grad():
        for batch in loader:
            x = normalize(batch["image"].to(device))
            out = model.predict(x)
            B = x.shape[0]
            for b in range(B):
                heat = out["symbol_heat"][b].cpu().numpy()
                dets = decode_symbols(heat, out["symbol_size"][b].cpu().numpy(), out["symbol_off"][b].cpu().numpy(), out["polarity"][b].cpu().numpy(), stride, threshold)
                # ground truth boxes from targets: reconstruct from index/size/offset
                gt = []
                n = int(batch["reg_mask"][b].sum())
                w = heat.shape[2]
                for i in range(n):
                    idx = int(batch["index"][b, i])
                    cy, cx = divmod(idx, w)
                    ox, oy = batch["offset"][b, i].tolist()
                    bw, bh = batch["size"][b, i].tolist()
                    k = int(torch.argmax(batch["heat"][b, :, cy, cx]))
                    ccx, ccy = (cx + ox) * stride, (cy + oy) * stride
                    gt.append((TRACER_CLASSES[k], [ccx - bw * stride / 2, ccy - bh * stride / 2, ccx + bw * stride / 2, ccy + bh * stride / 2]))
                matched = set()
                for d in dets:
                    best, best_iou = None, 0.5
                    for gi, (gcls, gbox) in enumerate(gt):
                        if gi in matched or gcls != d.cls:
                            continue
                        iou = _iou(d.box, gbox)
                        if iou >= best_iou:
                            best, best_iou = gi, iou
                    if best is None:
                        fp[d.cls] += 1
                    else:
                        matched.add(best)
                        tp[d.cls] += 1
                for gi, (gcls, _) in enumerate(gt):
                    if gi not in matched:
                        fn[gcls] += 1
                if float(batch["wire_weight"][b]) > 0:
                    pred = (out["wire"][b, 0].cpu().numpy() > 0.5)
                    truth = batch["wire"][b, 0].numpy() > 0.5
                    wire_inter += float((pred & truth).sum())
                    wire_union += float((pred | truth).sum())
    report = {}
    for c in TRACER_CLASSES:
        p = tp[c] / (tp[c] + fp[c]) if tp[c] + fp[c] else None
        r = tp[c] / (tp[c] + fn[c]) if tp[c] + fn[c] else None
        report[c] = {"precision": p, "recall": r, "n": tp[c] + fn[c]}
    total_tp, total_fp, total_fn = sum(tp.values()), sum(fp.values()), sum(fn.values())
    report["all"] = {"precision": total_tp / max(1, total_tp + total_fp), "recall": total_tp / max(1, total_tp + total_fn), "n": total_tp + total_fn}
    report["wire_iou"] = wire_inter / wire_union if wire_union else None
    model.train()
    return report


def _iou(a, b) -> float:
    ix0, iy0, ix1, iy1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    area = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / area if area > 0 else 0.0


def save_checkpoint(path: Path, model: CircuitNet, args: argparse.Namespace, epoch: int, metrics: Optional[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save({"model": model.state_dict(), "config": {"backbone": args.backbone, "width": args.width, "size": args.size, "stride": 4},
                "classes": TRACER_CLASSES, "epoch": epoch, "metrics": metrics}, path)


def load_checkpoint(path: str, device: torch.device) -> tuple[CircuitNet, dict]:
    ckpt = torch.load(path, map_location=device)
    cfg = ckpt["config"]
    model = CircuitNet(cfg["backbone"], cfg["width"], pretrained=False).to(device)
    model.load_state_dict(ckpt["model"])
    return model, ckpt


def main(argv: Optional[list[str]] = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--train", action="append", required=True, help="records JSONL (repeatable)")
    parser.add_argument("--val", action="append", default=[])
    parser.add_argument("--backbone", default="mobilenet_v3_large", choices=["tiny", "mobilenet_v3_large", "resnet18"])
    parser.add_argument("--width", type=int, default=64)
    parser.add_argument("--size", type=int, default=640)
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch", type=int, default=16)
    parser.add_argument("--lr", type=float, default=2e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--out", default="runs/tracer")
    parser.add_argument("--resume", default=None)
    parser.add_argument("--max-steps", type=int, default=0, help="stop early (smoke tests)")
    parser.add_argument("--no-mosaic", action="store_true")
    parser.add_argument("--no-pretrained", action="store_true")
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args(argv)

    device = torch.device(args.device)
    train_records, train_base = load_records(args.train)
    train_ds = TracerDataset(train_records, args.size, True, jsonl_dir=train_base, mosaic_ports=not args.no_mosaic)
    train_loader = DataLoader(train_ds, args.batch, shuffle=True, num_workers=args.workers, collate_fn=collate, drop_last=True, persistent_workers=args.workers > 0)
    val_loader = None
    if args.val:
        val_records, val_base = load_records(args.val)
        val_ds = TracerDataset([r for r in val_records if r.source != "digitize_hcd_ports"], args.size, False, jsonl_dir=val_base, mosaic_ports=False)
        val_loader = DataLoader(val_ds, max(1, args.batch // 2), shuffle=False, num_workers=args.workers, collate_fn=collate)

    if args.resume:
        model, ckpt = load_checkpoint(args.resume, device)
        start_epoch = int(ckpt.get("epoch", 0)) + 1
    else:
        model = CircuitNet(args.backbone, args.width, pretrained=not args.no_pretrained).to(device)
        start_epoch = 0
    params = [p for p in model.parameters() if p.requires_grad]
    optimizer = torch.optim.AdamW(params, lr=args.lr, weight_decay=args.weight_decay)
    steps_per_epoch = len(train_loader)
    total_steps = max(1, args.epochs * steps_per_epoch)
    warmup = min(500, total_steps // 10)

    def lr_at(step: int) -> float:
        if step < warmup:
            return args.lr * (step + 1) / warmup
        progress = (step - warmup) / max(1, total_steps - warmup)
        return args.lr * 0.5 * (1 + math.cos(math.pi * progress))

    scaler = torch.amp.GradScaler("cuda", enabled=device.type == "cuda")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    log = (out / "log.jsonl").open("a")
    step = start_epoch * steps_per_epoch
    print(f"train {len(train_ds)} items, {steps_per_epoch} steps/epoch, backbone {args.backbone}, device {device}")
    model.train()
    for epoch in range(start_epoch, args.epochs):
        t0 = time.time()
        running: dict[str, float] = {}
        for batch in train_loader:
            for g in optimizer.param_groups:
                g["lr"] = lr_at(step)
            x = normalize(batch["image"].to(device, non_blocking=True))
            targets = {k: (v.to(device) if isinstance(v, torch.Tensor) else v) for k, v in batch.items() if k != "image"}
            with torch.autocast(device.type, enabled=device.type == "cuda"):
                outputs = model(x)
                loss, terms = total_loss({k: v.float() for k, v in outputs.items()}, targets)
            optimizer.zero_grad(set_to_none=True)
            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(params, 10.0)
            scaler.step(optimizer)
            scaler.update()
            for k, v in terms.items():
                running[k] = running.get(k, 0.0) + v
            running["total"] = running.get("total", 0.0) + float(loss.detach())
            running["n"] = running.get("n", 0) + 1
            step += 1
            if step % 50 == 0:
                avg = {k: round(v / running["n"], 4) for k, v in running.items() if k != "n"}
                print(f"epoch {epoch} step {step} lr {lr_at(step):.2e} {avg}", flush=True)
            if args.max_steps and step >= args.max_steps:
                break
        metrics = evaluate(model, val_loader, device) if val_loader is not None else None
        avg = {k: v / max(1, running.get("n", 1)) for k, v in running.items() if k != "n"}
        entry = {"epoch": epoch, "step": step, "train": avg, "val": metrics, "seconds": round(time.time() - t0, 1)}
        log.write(json.dumps(entry) + "\n")
        log.flush()
        if metrics:
            print(f"epoch {epoch}: all P {metrics['all']['precision']:.3f} R {metrics['all']['recall']:.3f} wire IoU {metrics['wire_iou']}", flush=True)
        save_checkpoint(out / "last.pt", model, args, epoch, metrics)
        if args.max_steps and step >= args.max_steps:
            break
    print("done", out / "last.pt")


if __name__ == "__main__":
    main()
