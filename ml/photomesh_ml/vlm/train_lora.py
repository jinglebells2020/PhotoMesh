"""LoRA fine-tuning of a small open vision-language model on photo -> netlist JSON.

    python -m photomesh_ml.vlm.train_lora --model Qwen/Qwen3-VL-2B-Instruct \
        --train data/vlm/train.jsonl --val data/vlm/val.jsonl --out runs/vlm-qwen3-2b \
        --epochs 2 --batch 4 --grad-accum 4 --lr 1e-4 --lora-r 32 --max-pixels 802816 --bf16 --merge

Works with any `AutoModelForImageTextToText` checkpoint whose processor accepts images inside chat
messages (Qwen2.5-VL, Qwen3-VL, SmolVLM/SmolVLM2, Idefics3 ...). Only the language model's
projections get LoRA adapters by default; `--train-vision` adds the vision tower.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import time
from pathlib import Path
from typing import Optional

import torch
from PIL import Image, ImageOps
from torch.utils.data import DataLoader, Dataset

from ..eval.metrics import summarize
from ..schema import Circuit, ValidationError
from ..eval.benchmark import score_text
from .prompt import SYSTEM_PROMPT, USER_PROMPT

PROJ = {"q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj", "fc1", "fc2", "out_proj"}
VISION_HINTS = ("visual", "vision", "image_encoder", "vision_tower", "vision_model", "connector", "merger", "multi_modal_projector")


class JsonlImageDataset(Dataset):
    def __init__(self, path: str, limit: int = 0):
        self.base = Path(path).parent
        self.rows = [json.loads(l) for l in Path(path).read_text(encoding="utf-8").splitlines() if l.strip()]
        if limit:
            self.rows = self.rows[:limit]

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, i: int):
        row = self.rows[i]
        p = Path(row["image"])
        img = ImageOps.exif_transpose(Image.open(p if p.is_absolute() else self.base / p)).convert("RGB")
        return img, row["target"], row


def build_messages(image: Image.Image, target: Optional[str] = None) -> list[dict]:
    msgs = [
        {"role": "system", "content": [{"type": "text", "text": SYSTEM_PROMPT}]},
        {"role": "user", "content": [{"type": "image", "image": image}, {"type": "text", "text": USER_PROMPT}]},
    ]
    if target is not None:
        msgs.append({"role": "assistant", "content": [{"type": "text", "text": target}]})
    return msgs


class Collator:
    def __init__(self, processor):
        self.processor = processor

    def __call__(self, items):
        convs = [build_messages(img, tgt) for img, tgt, _ in items]
        batch = self.processor.apply_chat_template(convs, add_generation_prompt=False, tokenize=True, return_dict=True, return_tensors="pt", padding=True)
        labels = batch["input_ids"].clone()
        labels[batch["attention_mask"] == 0] = -100
        for i, (img, _, _) in enumerate(items):
            prompt = self.processor.apply_chat_template(build_messages(img), add_generation_prompt=True, tokenize=True, return_dict=True, return_tensors="pt")
            labels[i, : prompt["input_ids"].shape[1]] = -100
        batch["labels"] = labels
        return batch


def configure_processor(processor, max_pixels: int, min_pixels: int) -> None:
    ip = getattr(processor, "image_processor", None)
    if ip is None:
        return
    if hasattr(ip, "max_pixels"):
        ip.max_pixels = max_pixels
        ip.min_pixels = min_pixels
    elif hasattr(ip, "size") and isinstance(ip.size, dict) and "longest_edge" in ip.size:
        ip.size = {"longest_edge": int(math.sqrt(max_pixels))}
    if hasattr(processor, "tokenizer"):
        processor.tokenizer.padding_side = "right"


def lora_target_names(model, train_vision: bool) -> list[str]:
    names = []
    for n, m in model.named_modules():
        if not isinstance(m, torch.nn.Linear):
            continue
        leaf = n.rsplit(".", 1)[-1]
        if leaf not in PROJ:
            continue
        if not train_vision and any(h in n.lower() for h in VISION_HINTS):
            continue
        if leaf in ("fc1", "fc2", "out_proj") and not train_vision:
            continue
        names.append(n)
    return names


@torch.no_grad()
def generate_text(model, processor, image: Image.Image, max_new_tokens: int = 1024) -> str:
    inputs = processor.apply_chat_template(build_messages(image), add_generation_prompt=True, tokenize=True, return_dict=True, return_tensors="pt")
    inputs = {k: (v.to(model.device) if isinstance(v, torch.Tensor) else v) for k, v in inputs.items()}
    out = model.generate(**inputs, max_new_tokens=max_new_tokens, do_sample=False)
    new = out[0, inputs["input_ids"].shape[1]:]
    return processor.tokenizer.decode(new, skip_special_tokens=True)


@torch.no_grad()
def generate_texts(model, processor, images: list[Image.Image], max_new_tokens: int = 1024) -> list[str]:
    """Batched greedy generation: prompts are left-padded so every sequence starts generating at
    the same position; a batch of eight is several times faster than one image at a time."""
    if len(images) == 1:
        return [generate_text(model, processor, images[0], max_new_tokens)]
    tok = processor.tokenizer
    previous = tok.padding_side
    tok.padding_side = "left"
    try:
        inputs = processor.apply_chat_template([build_messages(img) for img in images], add_generation_prompt=True, tokenize=True,
                                               return_dict=True, return_tensors="pt", padding=True)
    finally:
        tok.padding_side = previous
    inputs = {k: (v.to(model.device) if isinstance(v, torch.Tensor) else v) for k, v in inputs.items()}
    out = model.generate(**inputs, max_new_tokens=max_new_tokens, do_sample=False, pad_token_id=tok.pad_token_id)
    new = out[:, inputs["input_ids"].shape[1]:]
    return [tok.decode(row, skip_special_tokens=True) for row in new]


def evaluate(model, processor, ds: JsonlImageDataset, limit: int, max_new_tokens: int) -> dict:
    model.eval()
    scores = []
    samples = []
    for i in range(min(limit, len(ds))):
        img, target, row = ds[i]
        text = generate_text(model, processor, img, max_new_tokens)
        scores.append(score_text(text, target))
        if i < 2:
            samples.append(text[:300])
    model.train()
    summary = summarize(scores)
    summary["samples"] = samples
    return summary


def main(argv: Optional[list[str]] = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", default="Qwen/Qwen3-VL-2B-Instruct")
    parser.add_argument("--train", required=True)
    parser.add_argument("--val", default=None)
    parser.add_argument("--out", required=True)
    parser.add_argument("--epochs", type=float, default=2)
    parser.add_argument("--batch", type=int, default=4)
    parser.add_argument("--grad-accum", type=int, default=4)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--warmup", type=int, default=50)
    parser.add_argument("--lora-r", type=int, default=32)
    parser.add_argument("--lora-alpha", type=int, default=64)
    parser.add_argument("--lora-dropout", type=float, default=0.05)
    parser.add_argument("--train-vision", action="store_true")
    parser.add_argument("--max-pixels", type=int, default=802816, help="image token budget (Qwen: pixels / 784 tokens)")
    parser.add_argument("--min-pixels", type=int, default=200704)
    parser.add_argument("--bf16", action="store_true")
    parser.add_argument("--gradient-checkpointing", action="store_true")
    parser.add_argument("--eval-every", type=int, default=500)
    parser.add_argument("--eval-samples", type=int, default=32)
    parser.add_argument("--max-new-tokens", type=int, default=1024)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--max-steps", type=int, default=0)
    parser.add_argument("--merge", action="store_true", help="also save the merged full model for vLLM")
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args(argv)

    from peft import LoraConfig, get_peft_model
    from transformers import AutoModelForImageTextToText, AutoProcessor

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    device = torch.device(args.device)
    dtype = torch.bfloat16 if (args.bf16 and device.type == "cuda") else torch.float32
    processor = AutoProcessor.from_pretrained(args.model)
    configure_processor(processor, args.max_pixels, args.min_pixels)
    model = AutoModelForImageTextToText.from_pretrained(args.model, torch_dtype=dtype)
    if args.gradient_checkpointing:
        model.gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})
        model.enable_input_require_grads()
    targets = lora_target_names(model, args.train_vision)
    if not targets:
        raise SystemExit("no LoRA target modules found for this architecture")
    config = LoraConfig(r=args.lora_r, lora_alpha=args.lora_alpha, lora_dropout=args.lora_dropout, target_modules=targets, task_type="CAUSAL_LM")
    model = get_peft_model(model, config)
    model.to(device)
    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    total = sum(p.numel() for p in model.parameters())
    print(f"LoRA on {len(targets)} linear layers: {trainable / 1e6:.1f}M trainable of {total / 1e6:.0f}M")

    train_ds = JsonlImageDataset(args.train, args.limit)
    val_ds = JsonlImageDataset(args.val, 0) if args.val else None
    loader = DataLoader(train_ds, batch_size=args.batch, shuffle=True, collate_fn=Collator(processor), num_workers=2, drop_last=True)
    steps_per_epoch = max(1, len(loader) // args.grad_accum)
    total_steps = int(args.epochs * steps_per_epoch)
    if args.max_steps:
        total_steps = min(total_steps, args.max_steps)
    optimizer = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=args.lr, weight_decay=0.0, betas=(0.9, 0.999))

    def lr_at(step: int) -> float:
        if step < args.warmup:
            return args.lr * (step + 1) / args.warmup
        progress = (step - args.warmup) / max(1, total_steps - args.warmup)
        return args.lr * 0.5 * (1 + math.cos(math.pi * min(1.0, progress)))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    log = (out / "log.jsonl").open("a")
    step = 0
    micro = 0
    running = 0.0
    t0 = time.time()
    model.train()
    done = False
    while not done:
        for batch in loader:
            batch = {k: (v.to(device) if isinstance(v, torch.Tensor) else v) for k, v in batch.items()}
            with torch.autocast(device.type, dtype=torch.bfloat16, enabled=dtype == torch.bfloat16):
                loss = model(**batch).loss / args.grad_accum
            loss.backward()
            running += float(loss.detach())
            micro += 1
            if micro % args.grad_accum != 0:
                continue
            for g in optimizer.param_groups:
                g["lr"] = lr_at(step)
            torch.nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], 1.0)
            optimizer.step()
            optimizer.zero_grad(set_to_none=True)
            step += 1
            if step % 10 == 0:
                entry = {"step": step, "loss": round(running / 10, 4), "lr": lr_at(step), "elapsed": round(time.time() - t0)}
                print(entry, flush=True)
                log.write(json.dumps(entry) + "\n")
                log.flush()
                running = 0.0
            if val_ds is not None and step % args.eval_every == 0:
                summary = evaluate(model, processor, val_ds, args.eval_samples, args.max_new_tokens)
                print({"eval": summary}, flush=True)
                log.write(json.dumps({"step": step, "eval": summary}) + "\n")
                log.flush()
            if step >= total_steps:
                done = True
                break
    model.save_pretrained(out / "adapter")
    processor.save_pretrained(out / "adapter")
    if val_ds is not None:
        summary = evaluate(model, processor, val_ds, args.eval_samples, args.max_new_tokens)
        print({"final_eval": summary}, flush=True)
        (out / "final_eval.json").write_text(json.dumps(summary, indent=1))
    if args.merge:
        merged = model.merge_and_unload()
        merged.save_pretrained(out / "merged", safe_serialization=True)
        processor.save_pretrained(out / "merged")
        print("merged model saved to", out / "merged")
    print("done", out)


if __name__ == "__main__":
    main()
