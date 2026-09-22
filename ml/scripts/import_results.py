"""Copy the small, reportable parts of a RunPod results tarball into docs/results/<name>/.

    python scripts/import_results.py results.tar.gz docs/results/runpod-4090-real

Kept: tracer summaries and training report, calibration parameters, VLM training log, final
eval and benchmark summaries, distillation counts. Weights, Core ML packages and per-image
prediction files stay out of the repository (they are listed in MANIFEST.md instead).
"""
from __future__ import annotations

import json
import sys
import tarfile
from pathlib import Path

KEEP_SUFFIXES = (".summary.json", ".md")
KEEP_NAMES = {"final_eval.json", "log.jsonl", "calibration.json"}


def main() -> None:
    src, dest = Path(sys.argv[1]), Path(sys.argv[2])
    dest.mkdir(parents=True, exist_ok=True)
    manifest: list[str] = []
    distill = {"accepted": 0, "rejected": 0, "reasons": {}}
    with tarfile.open(src) as tar:
        for m in tar.getmembers():
            if not m.isfile():
                continue
            name = Path(m.name)
            manifest.append(f"{m.name} ({m.size / 1e6:.1f} MB)")
            if name.name == "train.jsonl" and "distill" in m.name:
                distill["accepted"] = sum(1 for line in tar.extractfile(m).read().decode("utf-8").splitlines() if line.strip())
                continue
            if name.name == "train.rejected.jsonl":
                for line in tar.extractfile(m).read().decode("utf-8").splitlines():
                    if not line.strip():
                        continue
                    reason = str(json.loads(line).get("rejected", "?")).split(":")[0].split(";")[0][:40]
                    distill["reasons"][reason] = distill["reasons"].get(reason, 0) + 1
                    distill["rejected"] += 1
                continue
            if name.suffix in KEEP_SUFFIXES or name.name in KEEP_NAMES:
                if name.name == "log.jsonl" and m.size > 5_000_000:
                    continue
                out = dest / ("vlm" if "runs/vlm" in m.name else "tracer") / name.name
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(tar.extractfile(m).read())
    (dest / "distill.json").write_text(json.dumps(distill, indent=2) + "\n")
    (dest / "MANIFEST.md").write_text("Files in the results tarball (weights and per-image outputs are not committed):\n\n" +
                                      "\n".join(f"- {line}" for line in sorted(manifest)) + "\n")
    print(json.dumps(distill))
    for p in sorted(dest.rglob("*")):
        if p.is_file():
            print(p.relative_to(dest), p.stat().st_size)


if __name__ == "__main__":
    main()
