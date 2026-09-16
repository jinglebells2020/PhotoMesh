"""Label real photos with the cloud teacher, keeping only answers the data can vouch for.

    python -m photomesh_ml.vlm.distill --records data/records/train.jsonl --out data/distill/train.jsonl \
        --model google/gemini-3.6-flash --samples 2 --workers 4

Every accepted target passed three checks:
1. it parses and validates like in the app;
2. its components agree with the dataset's own symbol boxes (class and position, IoU >= 0.3),
   with recall and precision of at least `--min-agreement` over the app-solvable symbols;
3. with `--samples > 1` (or `--second-model`), independent answers solve to the same currents.
Rejections are logged next to the output with their reason, so the filter can be tuned.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional

from ..classes import APP_KINDS
from ..data.records import Record, read_jsonl, resolve_path
from ..schema import Circuit, ValidationError
from ..solver import same_solution, solvable
from .client import chat_json, jpeg_bytes
from .prompt import SYSTEM_PROMPT, USER_PROMPT


def _iou(a, b) -> float:
    ix0, iy0, ix1, iy1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    area = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / area if area > 0 else 0.0


def box_agreement(circuit: Circuit, record: Record, width: int, height: int, iou_threshold: float = 0.3) -> dict:
    """How well the teacher's components line up with the annotated symbols."""
    truth = [s for s in record.symbols if s.cls in APP_KINDS]
    pred = [c for c in circuit.components if c.box is not None]
    sx, sy = width / record.width, height / record.height
    matched_t: set[int] = set()
    matched_p = 0
    class_ok = 0
    for i, c in enumerate(pred):
        pb = [c.box[0] * width, c.box[1] * height, c.box[2] * width, c.box[3] * height]
        best, best_iou = None, iou_threshold
        for j, s in enumerate(truth):
            if j in matched_t:
                continue
            tb = [s.box[0] * sx, s.box[1] * sy, s.box[2] * sx, s.box[3] * sy]
            iou = _iou(pb, tb)
            if iou >= best_iou:
                best, best_iou = j, iou
        if best is not None:
            matched_t.add(best)
            matched_p += 1
            if truth[best].cls == c.kind or (truth[best].cls == "switch_open" and c.kind == "switch_closed"):
                class_ok += 1
    unsupported_truth = sum(1 for s in record.symbols if s.cls == "other")
    return {
        "truth": len(truth), "pred": len(pred), "matched": matched_p, "class_ok": class_ok,
        "recall": matched_p / len(truth) if truth else 1.0,
        "precision": matched_p / len(pred) if pred else (1.0 if not truth else 0.0),
        "class_acc": class_ok / matched_p if matched_p else 1.0,
        "unsupported_truth": unsupported_truth, "unsupported_pred": len(circuit.unsupported),
    }


def label_one(record: Record, jsonl_dir: Optional[Path], args) -> dict:
    path = resolve_path(record.image, jsonl_dir)
    jpeg, w, h = jpeg_bytes(str(path), args.max_side)
    answers: list[dict] = []
    models = [args.model] * args.samples + ([args.second_model] if args.second_model else [])
    for i, model in enumerate(models):
        try:
            result = chat_json(args.endpoint, args.api_key, model, SYSTEM_PROMPT, USER_PROMPT, jpeg,
                               temperature=args.temperature if i == 0 else max(args.temperature, 0.4), max_tokens=args.max_tokens,
                               fast_reasoning=args.fast)
        except Exception as exc:  # noqa: BLE001
            answers.append({"model": model, "error": f"request: {exc}"})
            continue
        entry: dict = {"model": result.model, "latency": round(result.latency, 2), "prompt_tokens": result.prompt_tokens,
                       "completion_tokens": result.completion_tokens, "reasoning_tokens": result.reasoning_tokens}
        try:
            circuit = Circuit.from_json(result.text)
            circuit.validated()
        except ValidationError as exc:
            entry["error"] = f"invalid: {exc}"
            entry["text"] = result.text[:2000]
            answers.append(entry)
            continue
        if not solvable(circuit):
            entry["error"] = "unsolvable"
            answers.append(entry)
            continue
        agreement = box_agreement(circuit, record, w, h)
        entry["agreement"] = agreement
        if agreement["recall"] < args.min_agreement or agreement["precision"] < args.min_agreement or agreement["class_acc"] < args.min_agreement:
            entry["error"] = "boxes disagree with the annotation"
        if record.symbols and any(s.cls == "other" for s in record.symbols) and not circuit.unsupported and args.require_unsupported:
            entry["error"] = "unsupported symbols not reported"
        entry["circuit"] = circuit.to_json(2)
        answers.append(entry)
    good = [a for a in answers if "circuit" in a and "error" not in a]
    out = {"image": str(path), "width": w, "height": h, "source": record.source, "group": record.group, "answers": answers}
    if not good:
        out["rejected"] = "; ".join(a.get("error", "?") for a in answers)
        return out
    if len(models) > 1:
        circuits = [Circuit.from_json(a["circuit"]) for a in good]
        chosen = None
        for i in range(len(circuits)):
            for j in range(i + 1, len(circuits)):
                if same_solution(circuits[i], circuits[j]):
                    chosen = good[i]
                    break
            if chosen:
                break
        if chosen is None:
            out["rejected"] = "answers disagree"
            return out
        out["agreement_votes"] = sum(1 for c in circuits if same_solution(c, Circuit.from_json(chosen["circuit"])))
    else:
        chosen = good[0]
    out["target"] = chosen["circuit"]
    out["teacher"] = chosen["model"]
    return out


def main(argv: Optional[list[str]] = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--records", action="append", required=True)
    parser.add_argument("--sources", default="digitize_hcd,cghd,scan", help="record sources to label")
    parser.add_argument("--out", required=True)
    parser.add_argument("--endpoint", default="https://openrouter.ai/api/v1/chat/completions")
    parser.add_argument("--api-key-env", default="OPENROUTER_API_KEY")
    parser.add_argument("--model", default="google/gemini-3.6-flash")
    parser.add_argument("--second-model", default=None, help="a different teacher whose answer must agree")
    parser.add_argument("--samples", type=int, default=1, help="answers per image from --model")
    parser.add_argument("--temperature", type=float, default=0.1)
    parser.add_argument("--fast", action="store_true", help="low reasoning effort")
    parser.add_argument("--max-tokens", type=int, default=6000)
    parser.add_argument("--max-side", type=int, default=1280)
    parser.add_argument("--min-agreement", type=float, default=0.9)
    parser.add_argument("--require-unsupported", action="store_true", help="reject answers that ignore annotated unsupported symbols")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args(argv)
    args.api_key = os.environ.get(args.api_key_env)
    if not args.api_key and "openrouter" in args.endpoint:
        sys.exit(f"set {args.api_key_env}")

    sources = set(args.sources.split(","))
    records: list[Record] = []
    jsonl_dir = None
    for p in args.records:
        jsonl_dir = jsonl_dir or Path(p)
        records += [r for r in read_jsonl(p) if r.source in sources]
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    done: set[str] = set()
    if out.exists():
        for line in out.read_text(encoding="utf-8").splitlines():
            if line.strip():
                done.add(json.loads(line)["image"])
    todo = [r for r in records if str(resolve_path(r.image, jsonl_dir)) not in done]
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(records)} records, {len(done)} done, {len(todo)} to label with {args.model} x{args.samples}" + (f" + {args.second_model}" if args.second_model else ""))
    lock = threading.Lock()
    accepted = rejected = 0
    tokens_in = tokens_out = 0
    with out.open("a", encoding="utf-8") as f, (out.with_suffix(".rejected.jsonl")).open("a", encoding="utf-8") as rej, ThreadPoolExecutor(args.workers) as pool:
        futures = {pool.submit(label_one, r, jsonl_dir, args): r for r in todo}
        for k, fut in enumerate(as_completed(futures), 1):
            try:
                result = fut.result()
            except Exception as exc:  # noqa: BLE001
                result = {"image": futures[fut].image, "rejected": f"exception: {exc}"}
            for a in result.get("answers", []):
                tokens_in += a.get("prompt_tokens") or 0
                tokens_out += a.get("completion_tokens") or 0
            with lock:
                if "target" in result:
                    f.write(json.dumps(result, ensure_ascii=False) + "\n")
                    f.flush()
                    accepted += 1
                else:
                    rej.write(json.dumps(result, ensure_ascii=False) + "\n")
                    rej.flush()
                    rejected += 1
            if k % 20 == 0 or k == len(todo):
                print(f"{k}/{len(todo)} accepted {accepted} rejected {rejected} tokens in {tokens_in} out {tokens_out}", flush=True)
    print(f"done: accepted {accepted}, rejected {rejected} -> {out}")


if __name__ == "__main__":
    main()
