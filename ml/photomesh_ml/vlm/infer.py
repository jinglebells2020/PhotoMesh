"""Run the fine-tuned model on images (transformers, or vLLM for speed) and write predictions.

    python -m photomesh_ml.vlm.infer --model runs/vlm-qwen3-2b/merged --image photo.jpg
    python -m photomesh_ml.vlm.infer --model runs/vlm-qwen3-2b/merged --jsonl data/vlm/val.jsonl --out results/student.jsonl --vllm
"""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import torch
from PIL import Image, ImageOps

from .prompt import SYSTEM_PROMPT, USER_PROMPT
from .train_lora import build_messages, configure_processor, generate_text


def _load_image(path: Path, max_side: int) -> Image.Image:
    img = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    w, h = img.size
    scale = min(1.0, max_side / max(w, h))
    if scale < 1.0:
        img = img.resize((int(round(w * scale)), int(round(h * scale))), Image.LANCZOS)
    return img


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", required=True, help="merged model dir or base model id")
    parser.add_argument("--adapter", default=None, help="LoRA adapter dir to load on top of --model")
    parser.add_argument("--image", action="append", default=[])
    parser.add_argument("--jsonl", default=None)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--out", default=None)
    parser.add_argument("--max-side", type=int, default=1280)
    parser.add_argument("--max-pixels", type=int, default=802816)
    parser.add_argument("--max-new-tokens", type=int, default=1024)
    parser.add_argument("--vllm", action="store_true")
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = parser.parse_args()

    images: list[tuple[str, Path]] = [(p, Path(p)) for p in args.image]
    if args.jsonl:
        base = Path(args.jsonl).parent
        for l in Path(args.jsonl).read_text(encoding="utf-8").splitlines():
            if l.strip():
                row = json.loads(l)
                p = Path(row["image"])
                images.append((row["image"], p if p.is_absolute() else base / p))
    if args.limit:
        images = images[: args.limit]

    results = []
    if args.vllm:
        from vllm import LLM, SamplingParams
        llm = LLM(model=args.model, max_model_len=8192, limit_mm_per_prompt={"image": 1})
        params = SamplingParams(temperature=0.0, max_tokens=args.max_new_tokens)
        prompts = []
        for _, path in images:
            img = _load_image(path, args.max_side)
            prompts.append({"prompt": None, "multi_modal_data": {"image": img},
                            "messages": build_messages(img)})
        t0 = time.time()
        outputs = llm.chat([p["messages"] for p in prompts], params)
        elapsed = time.time() - t0
        for (name, _), o in zip(images, outputs):
            results.append({"image": name, "text": o.outputs[0].text, "latency": elapsed / len(images)})
    else:
        from transformers import AutoModelForImageTextToText, AutoProcessor
        processor = AutoProcessor.from_pretrained(args.adapter or args.model)
        configure_processor(processor, args.max_pixels, 200704)
        dtype = torch.bfloat16 if args.device.startswith("cuda") else torch.float32
        model = AutoModelForImageTextToText.from_pretrained(args.model, torch_dtype=dtype)
        if args.adapter:
            from peft import PeftModel
            model = PeftModel.from_pretrained(model, args.adapter)
        model.to(args.device).eval()
        for name, path in images:
            img = _load_image(path, args.max_side)
            t0 = time.time()
            text = generate_text(model, processor, img, args.max_new_tokens)
            results.append({"image": name, "text": text, "latency": round(time.time() - t0, 2)})
            print(name, round(time.time() - t0, 2), "s", text[:160].replace("\n", " "))
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        with Path(args.out).open("w", encoding="utf-8") as f:
            for r in results:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print("wrote", args.out)
    elif not args.jsonl:
        for r in results:
            print(r["text"])


if __name__ == "__main__":
    main()
