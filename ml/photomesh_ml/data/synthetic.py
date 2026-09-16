"""Generator output (labels/*.json) -> records."""
from __future__ import annotations

import json
from pathlib import Path

from .records import Record, Symbol


def convert(root: Path) -> list[Record]:
    root = Path(root).resolve()
    records: list[Record] = []
    for label_path in sorted((root / "labels").glob("*.json")):
        d = json.loads(label_path.read_text(encoding="utf-8"))
        sup = d["supervision"]
        symbols = [Symbol(cls=s["cls"], box=s["box"], polarity=s["polarity"], terminals=s["terminals"], id=s.get("id")) for s in sup["symbols"]]
        symbols += [Symbol(cls="text", box=t["box"], text=t["text"], id=t.get("component")) for t in sup["texts"]]
        seed = int(d.get("seed", 0))
        records.append(Record(image=str(root / d["image"]), width=d["width"], height=d["height"], source="synthetic",
                              group=f"synth-{seed % 10}", symbols=symbols, junctions=sup["junctions"],
                              wire_mask=str(root / d["mask"]) if d.get("mask") else None, texts_complete=True,
                              circuit=d["circuit"], meta={"style": d.get("style"), "photo": d.get("photo"), "seed": seed}))
    return records
