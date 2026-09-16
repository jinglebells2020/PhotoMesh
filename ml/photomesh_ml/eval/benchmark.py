"""Score any OpenAI-compatible recognizer (cloud teacher, self-hosted vLLM, our server) on a labelled set.

    python -m photomesh_ml.eval.benchmark --jsonl data/vlm/val.jsonl --limit 100 \
        --endpoint https://openrouter.ai/api/v1/chat/completions --model google/gemini-3.5-flash-lite --fast \
        --out results/gemini-lite.jsonl

    python -m photomesh_ml.eval.benchmark --jsonl data/vlm/val.jsonl --predictions results/student.jsonl

Rows of --jsonl carry {"image", "target"} (build_dataset output); predictions carry {"image", "text"}.
"""
from __future__ import annotations

import argparse
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional

from ..schema import Circuit, ValidationError
from ..vlm.client import chat_json, jpeg_bytes
from ..vlm.prompt import SYSTEM_PROMPT, USER_PROMPT
from .metrics import Score, score_prediction, summarize


def score_text(text: Optional[str], target: dict | str) -> Score:
    truth = Circuit.from_json(target)
    if text is None:
        return score_prediction(None, truth)
    try:
        pred = Circuit.from_json(text)
    except ValidationError as exc:
        s = score_prediction(None, truth)
        s.error = f"unreadable: {exc}"
        return s
    return score_prediction(pred, truth)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jsonl", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--predictions", default=None, help="score these instead of calling an endpoint")
    parser.add_argument("--endpoint", default="https://openrouter.ai/api/v1/chat/completions")
    parser.add_argument("--api-key-env", default="OPENROUTER_API_KEY")
    parser.add_argument("--model", default="google/gemini-3.5-flash-lite")
    parser.add_argument("--fast", action="store_true")
    parser.add_argument("--max-side", type=int, default=1280)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()
    base = Path(args.jsonl).parent
    rows = [json.loads(l) for l in Path(args.jsonl).read_text(encoding="utf-8").splitlines() if l.strip()]
    if args.limit:
        rows = rows[: args.limit]

    texts: dict[str, Optional[str]] = {}
    latencies: list[float] = []
    tokens = {"prompt": 0, "completion": 0, "reasoning": 0}
    if args.predictions:
        for l in Path(args.predictions).read_text(encoding="utf-8").splitlines():
            if l.strip():
                p = json.loads(l)
                texts[p["image"]] = p.get("text")
    else:
        api_key = os.environ.get(args.api_key_env)

        def run(row: dict) -> tuple[str, Optional[str], Optional[dict]]:
            path = base / row["image"] if not Path(row["image"]).is_absolute() else Path(row["image"])
            jpeg, _, _ = jpeg_bytes(str(path), args.max_side)
            try:
                r = chat_json(args.endpoint, api_key, args.model, SYSTEM_PROMPT, USER_PROMPT, jpeg, fast_reasoning=args.fast)
                return row["image"], r.text, {"latency": r.latency, "prompt": r.prompt_tokens or 0, "completion": r.completion_tokens or 0, "reasoning": r.reasoning_tokens or 0}
            except Exception as exc:  # noqa: BLE001
                return row["image"], None, {"error": str(exc)}

        with ThreadPoolExecutor(args.workers) as pool:
            for k, (image, text, info) in enumerate(pool.map(run, rows), 1):
                texts[image] = text
                if info and "latency" in info:
                    latencies.append(info["latency"])
                    for key in ("prompt", "completion", "reasoning"):
                        tokens[key] += info[key]
                if k % 10 == 0:
                    print(f"{k}/{len(rows)}", flush=True)
    scores = []
    details = []
    for row in rows:
        s = score_text(texts.get(row["image"]), row["target"])
        scores.append(s)
        details.append({"image": row["image"], "source": row.get("source"), "text": texts.get(row["image"]), "score": s.as_dict()})
    summary = summarize(scores)
    if latencies:
        summary["latency_mean_s"] = sum(latencies) / len(latencies)
        summary["tokens"] = tokens
    by_source: dict[str, list[Score]] = {}
    for row, s in zip(rows, scores):
        by_source.setdefault(row.get("source", "?"), []).append(s)
    print(json.dumps({"summary": summary, "by_source": {k: summarize(v) for k, v in by_source.items()}}, indent=1))
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        with Path(args.out).open("w", encoding="utf-8") as f:
            for d in details:
                f.write(json.dumps(d, ensure_ascii=False) + "\n")
        Path(args.out).with_suffix(".summary.json").write_text(json.dumps({"summary": summary, "model": args.model if not args.predictions else args.predictions}, indent=1))


if __name__ == "__main__":
    main()
