#!/usr/bin/env python3
"""Build the training / evaluation set from the collector's per-install folders.

Reads  <raw>/installs/<install>/samples/*.json and the matching images/*.jpg.
Writes <out>/samples.jsonl, train.jsonl, val.jsonl, eval/<id>.{jpg,json}, stats.md.
"""
import argparse
import hashlib
import json
import shutil
import sys
from collections import Counter, defaultdict
from pathlib import Path

KIND_TO_TYPE = {
    "resistor": "resistor", "voltage_source": "voltage_source", "current_source": "current_source", "capacitor": "capacitor",
    "inductor": "inductor", "lamp": "lamp", "battery": "battery", "switch_open": "switch_open", "switch_closed": "switch_closed",
}


def to_payload(circuit: dict) -> dict:
    """The app's Circuit encoding → the recognizer's payload format used by the benchmark fixtures."""
    components = []
    for c in circuit.get("components", []):
        kind = c.get("kind", "resistor")
        entry = {"id": c.get("id"), "type": KIND_TO_TYPE.get(kind, kind)}
        if kind not in ("switch_open", "switch_closed"):
            entry["value"] = c.get("value")
        a, b = c.get("nodeA"), c.get("nodeB")
        if kind in ("voltage_source", "battery"):
            entry["positive_node"], entry["negative_node"] = a, b
        elif kind == "current_source":
            entry["from_node"], entry["to_node"] = a, b
        else:
            entry["node_a"], entry["node_b"] = a, b
        components.append(entry)
    unknowns = []
    for u in circuit.get("unknowns", []):
        item = {"kind": u.get("kind")}
        for field in ("element", "node", "between"):
            if u.get(field) is not None:
                item[field] = u[field]
        unknowns.append(item)
    payload = {"components": components, "ground_node": circuit.get("groundNode", "0"), "meshes": circuit.get("meshes", []), "unknowns": unknowns,
               "question": circuit.get("question"), "unsupported": circuit.get("unsupported", []), "confidence": 1.0, "notes": None}
    return payload


def netlist_signature(circuit: dict) -> str:
    """Order-free fingerprint of a circuit, to compare recognized against corrected."""
    parts = []
    for c in circuit.get("components", []):
        nodes = (c.get("nodeA"), c.get("nodeB"))
        if c.get("kind") not in ("voltage_source", "battery", "current_source"):
            nodes = tuple(sorted(str(n) for n in nodes))
        parts.append(f"{c.get('id')}:{c.get('kind')}:{c.get('value')}:{nodes[0]}-{nodes[1]}")
    return "|".join(sorted(parts)) + f"#g={circuit.get('groundNode')}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", default="data/raw")
    parser.add_argument("--out", default="data/dataset")
    parser.add_argument("--val-fraction", type=float, default=0.2, help="share of installs held out for validation")
    parser.add_argument("--min-side", type=int, default=200, help="drop pictures smaller than this on their longer side")
    args = parser.parse_args()

    raw = Path(args.raw)
    out = Path(args.out)
    (out / "images").mkdir(parents=True, exist_ok=True)
    (out / "eval").mkdir(parents=True, exist_ok=True)

    rows = []
    seen_hashes = set()
    duplicates = missing_images = small = 0
    by_model = defaultdict(Counter)
    dominant = Counter()
    per_install = Counter()

    loaded = []
    for sample_path in sorted(raw.glob("installs/*/samples/*.json")):
        try:
            loaded.append((sample_path, json.loads(sample_path.read_text())))
        except json.JSONDecodeError:
            continue
    # Corrected scans first, so when the same picture was shared twice the labelled copy is the one kept.
    loaded.sort(key=lambda item: (not bool(item[1].get("corrected")), item[1].get("timestamp") or "", str(item[0])))

    for sample_path, sample in loaded:
        install = sample.get("installId") or sample_path.parts[-3]
        image_key = sample.get("imageKey")
        image_path = raw / image_key if image_key else None
        if not image_path or not image_path.exists():
            missing_images += 1
            continue
        if max(sample.get("imageWidth", 0), sample.get("imageHeight", 0)) < args.min_side:
            small += 1
            continue
        data = image_path.read_bytes()
        digest = hashlib.sha1(data).hexdigest()
        if digest in seen_hashes:
            duplicates += 1
            continue
        seen_hashes.add(digest)

        recognized = sample.get("recognized") or {}
        corrected = sample.get("corrected")
        label = corrected or recognized
        changed = bool(corrected) and netlist_signature(recognized) != netlist_signature(corrected)
        sample_id = sample.get("id") or sample_path.stem
        rel_image = f"images/{sample_id}.jpg"
        shutil.copyfile(image_path, out / rel_image)
        model = sample.get("model") or "?"
        by_model[model]["total"] += 1
        by_model[model]["accepted" if sample.get("accepted") else "corrected"] += 1
        if changed:
            by_model[model]["changed"] += 1
        diff = sample.get("diff") or {}
        if corrected:
            dominant[diff.get("dominant", "unknown")] += 1
        per_install[install] += 1
        rows.append({
            "id": sample_id, "install": install, "timestamp": sample.get("timestamp"), "model": model,
            "accepted": bool(sample.get("accepted")), "changed": changed, "image": rel_image, "sha1": digest,
            "width": sample.get("imageWidth"), "height": sample.get("imageHeight"),
            "recognized": recognized, "corrected": corrected, "label": label, "label_payload": to_payload(label), "diff": diff or None,
            "context": sample.get("context") or {},
        })
        if corrected:
            shutil.copyfile(image_path, out / "eval" / f"{sample_id}.jpg")
            (out / "eval" / f"{sample_id}.json").write_text(json.dumps(to_payload(corrected), indent=1))

    def split_of(install: str) -> str:
        bucket = int(hashlib.sha1(install.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF
        return "val" if bucket < args.val_fraction else "train"

    with (out / "samples.jsonl").open("w") as all_f, (out / "train.jsonl").open("w") as train_f, (out / "val.jsonl").open("w") as val_f:
        for row in rows:
            line = json.dumps(row) + "\n"
            all_f.write(line)
            (val_f if split_of(row["install"]) == "val" else train_f).write(line)

    train = sum(1 for r in rows if split_of(r["install"]) == "train")
    lines = [
        "# Dataset", "",
        f"- samples: {len(rows)} ({train} train, {len(rows) - train} val, split by install; {len(per_install)} installs)",
        f"- corrected: {sum(1 for r in rows if r['corrected'])} (of which {sum(1 for r in rows if r['changed'])} actually change the netlist)",
        f"- dropped: {duplicates} duplicate pictures, {missing_images} without a picture, {small} too small", "",
        "## Accept rate by model", "", "| model | scans | accepted | corrected | netlist changed |", "| --- | ---: | ---: | ---: | ---: |",
    ]
    for model, c in sorted(by_model.items(), key=lambda kv: -kv[1]["total"]):
        lines.append(f"| {model} | {c['total']} | {c['accepted']} ({100 * c['accepted'] / max(1, c['total']):.0f}%) | {c['corrected']} | {c['changed']} |")
    lines += ["", "## What corrections change", "", "| dominant change | count |", "| --- | ---: |"]
    for kind, n in dominant.most_common():
        lines.append(f"| {kind} | {n} |")
    (out / "stats.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwritten to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
