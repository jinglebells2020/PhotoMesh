"""The app's own scans (Settings -> Privacy & data -> Collected data, or the telemetry worker's uploads) -> records.

An export is `Analytics.UploadPayload`: {"installId", "exportedAt", "events": [...], "samples": [...]}
where each sample is a `RecognitionSample`:
    {"id", "timestamp", "model", "recognized": <Swift Circuit>, "corrected": <Swift Circuit>?, "accepted": bool,
     "imageWidth", "imageHeight", "imageBase64": <JPEG>?}
The Swift `Circuit` is encoded with its property names (components[].kind / nodeA / nodeB, groundNode,
geometry.placements[id].box{minX..maxY}, geometry.nodePoints{node: {x, y}}); this module maps it to the
recognizer JSON the rest of the pipeline uses. A corrected netlist is ground truth; an accepted one is
what the user let through (weaker, flagged in `meta["truth"]`).
"""
from __future__ import annotations

import base64
import io
import json
from pathlib import Path
from typing import Any, Optional

from PIL import Image

from ..classes import TRACER_CLASSES
from ..schema import DC_ROLE, KIND_ALIASES
from .records import Record, Symbol


def swift_circuit_to_json(obj: dict) -> dict:
    """Swift `Circuit` (Codable, property names) -> the recognizer's JSON shape."""
    components = []
    geometry = obj.get("geometry") or {}
    placements = geometry.get("placements") or {}
    for c in obj.get("components") or []:
        kind = KIND_ALIASES.get(str(c.get("kind", "")).lower(), None)
        if kind is None:
            continue
        a, b = c.get("nodeA") or c.get("node_a"), c.get("nodeB") or c.get("node_b")
        entry: dict[str, Any] = {"id": c.get("id"), "type": kind, "value": c.get("value")}
        role = DC_ROLE[kind]
        if role == "voltage_source":
            entry["positive_node"], entry["negative_node"] = a, b
        elif role == "current_source":
            entry["from_node"], entry["to_node"] = a, b
        else:
            entry["node_a"], entry["node_b"] = a, b
        placement = placements.get(c.get("id"))
        if placement and "box" in placement:
            box = placement["box"]
            entry["box"] = [box.get("minX"), box.get("minY"), box.get("maxX"), box.get("maxY")]
            entry["orientation"] = "horizontal" if placement.get("isHorizontal", True) else "vertical"
        components.append(entry)
    node_points = {}
    for node, pt in (geometry.get("nodePoints") or {}).items():
        if isinstance(pt, dict) and "x" in pt and "y" in pt:
            node_points[node] = [pt["x"], pt["y"]]
    return {
        "components": components,
        "ground_node": obj.get("groundNode") or obj.get("ground_node") or "0",
        "node_points": node_points,
        "meshes": obj.get("meshes") or [],
        "unknowns": obj.get("unknowns") or [],
        "question": obj.get("question"),
        "unsupported": obj.get("unsupported") or [],
        "confidence": None,
        "notes": obj.get("notes"),
    }


def _samples_from_file(path: Path) -> tuple[str, list[dict]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict) and "samples" in data:
        return str(data.get("installId") or "scan"), list(data["samples"])
    if isinstance(data, dict) and "recognized" in data:
        return "scan", [data]
    if isinstance(data, list):
        return "scan", [d for d in data if isinstance(d, dict) and "recognized" in d]
    return "scan", []


def convert(paths: list[Path], out_dir: Path, keep_accepted: bool = True) -> list[Record]:
    """Reads export files or directories of per-sample JSON files; writes images under `out_dir/images`."""
    out_dir = Path(out_dir).resolve()
    (out_dir / "images").mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    for p in paths:
        p = Path(p)
        files += sorted(p.glob("*.json")) if p.is_dir() else [p]
    records: list[Record] = []
    for file in files:
        install, samples = _samples_from_file(file)
        for sample in samples:
            corrected = sample.get("corrected")
            recognized = sample.get("recognized")
            truth_source = "corrected" if corrected else ("accepted" if sample.get("accepted") else None)
            if truth_source is None or (truth_source == "accepted" and not keep_accepted):
                continue
            circuit = swift_circuit_to_json(corrected or recognized)
            sid = str(sample.get("id") or f"{file.stem}-{len(records)}")
            image_b64 = sample.get("imageBase64")
            if not image_b64:
                continue
            raw = base64.b64decode(image_b64)
            image_path = out_dir / "images" / f"{sid}.jpg"
            if not image_path.exists():
                image_path.write_bytes(raw)
            with Image.open(io.BytesIO(raw)) as img:
                width, height = img.size
            symbols: list[Symbol] = []
            for c in circuit["components"]:
                if "box" not in c or any(v is None for v in c["box"]):
                    continue
                x0, y0, x1, y1 = c["box"]
                cls = c["type"] if c["type"] in TRACER_CLASSES else "other"
                horizontal = c.get("orientation") == "horizontal"
                symbols.append(Symbol(cls=cls, box=[x0 * width, y0 * height, x1 * width, y1 * height], polarity=None,
                                      polarity_candidates=["right", "left"] if horizontal else ["up", "down"], id=c["id"]))
            records.append(Record(image=str(image_path), width=width, height=height, source="scan", group=install, symbols=symbols,
                                  junctions=None, wire_mask=None, texts_complete=False, circuit=circuit,
                                  meta={"truth": truth_source, "model": sample.get("model"), "timestamp": sample.get("timestamp"),
                                        "sample_id": sid, "accepted": bool(sample.get("accepted"))}))
    return records
