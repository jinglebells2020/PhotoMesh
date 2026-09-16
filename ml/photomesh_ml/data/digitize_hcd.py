"""Digitize-HCD (Mendeley 10.17632/rngcz5wtv8.2, CC BY 4.0) -> records.

Layout of the extracted zip:
    Digitize-HCD Dataset/
      Component Symbol and Text Label Data/
        component_annotations.json   COCO: 17 categories, bbox = [x, y, w, h]
        text_annotations.json        MMOCR OCRDataset: data_list[].instances[] {polygon, bbox[x0,y0,x1,y1], text}
        Circuit Diagram Images/circuit_N.jpg
      Component Port Location Data/<Class>/{Input Images,Output Heatmaps,XY Coordinates}/

Full images give symbol boxes (no polarity) and text boxes with strings. The 320x320 port crops
give terminal points and, for DC sources, polarity (Positive/Negative, Flowing From/To).
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Iterable, Optional

from .records import Record, Symbol, axis_candidates, direction_name

CLASS_MAP = {
    "Resistor": "resistor", "Capacitor": "capacitor", "Inductor": "inductor", "GND": "ground",
    "Wire Crossover": "crossover", "V-DC": "voltage_source", "I-DC": "current_source",
    "V-DC (one port)": "other", "V-AC": "other", "I-AC": "other", "Diode": "other", "Zener Diode": "other",
    "BJT-NPN": "other", "BJT-PNP": "other", "MOSFET-N": "other", "MOSFET-P": "other", "Op-Amp": "other",
}
PORT_DIR_MAP = {"Resistor": "resistor", "Capacitor": "capacitor", "Inductor": "inductor", "GND": "ground",
                "V-DC": "voltage_source", "I-DC": "current_source", "Wire Crossover": "crossover",
                "Diode": "other", "Zener Diode": "other", "BJT-NPN": "other", "BJT-PNP": "other", "MOSFET-N": "other",
                "MOSFET-P": "other", "Op-Amp": "other", "V-AC": "other", "I-AC": "other", "V-DC (one-port)": "other"}
NON_POLAR_AXIS = {"resistor", "capacitor", "inductor", "other", "crossover"}


def _find_dir(root: Path, name: str) -> Optional[Path]:
    for p in root.rglob(name):
        if p.is_dir():
            return p
    return None


def convert_full_images(root: Path, groups: int = 20) -> list[Record]:
    root = Path(root).resolve()
    comp_path = next(root.rglob("component_annotations.json"))
    text_path = next(root.rglob("text_annotations.json"))
    images_dir = _find_dir(root, "Circuit Diagram Images") or comp_path.parent
    comp = json.loads(comp_path.read_text(encoding="utf-8"))
    text = json.loads(text_path.read_text(encoding="utf-8"))
    names = {c["id"]: c["name"] for c in comp["categories"]}
    by_image: dict[int, list[dict]] = {}
    for a in comp["annotations"]:
        by_image.setdefault(a["image_id"], []).append(a)
    texts_by_file: dict[str, list[dict]] = {d["file_name"]: d.get("instances", []) for d in text.get("data_list", [])}

    records: list[Record] = []
    for im in comp["images"]:
        file_name = im["file_name"]
        image_path = images_dir / file_name
        symbols: list[Symbol] = []
        for a in by_image.get(im["id"], []):
            x, y, w, h = a["bbox"]
            box = [float(x), float(y), float(x + w), float(y + h)]
            label = names[a["category_id"]]
            cls = CLASS_MAP.get(label, "other")
            symbols.append(Symbol(cls=cls, box=box, polarity=None,
                                  polarity_candidates=axis_candidates(box) if cls in NON_POLAR_AXIS else None,
                                  source_label=label))
        for inst in texts_by_file.get(file_name, []):
            x0, y0, x1, y1 = inst["bbox"]
            symbols.append(Symbol(cls="text", box=[float(x0), float(y0), float(x1), float(y1)], text=inst.get("text")))
        number = int(re.sub(r"\D", "", file_name) or 0)
        records.append(Record(image=str(image_path), width=int(im["width"]), height=int(im["height"]), source="digitize_hcd",
                              group=f"dhcd-{number % groups:02d}", symbols=symbols, junctions=None, wire_mask=None,
                              texts_complete=True, meta={"file_name": file_name}))
    return records


def _parse_ports(text: str) -> tuple[list[list[float]], dict[str, list[float]]]:
    """'Negative 25 118\\nPositive 291 225' or '171 26 182 293' -> points and named points."""
    points: list[list[float]] = []
    named: dict[str, list[float]] = {}
    for line in text.strip().splitlines():
        parts = line.strip().split()
        if not parts:
            continue
        if parts[0].replace("-", "").isdigit():
            nums = [float(v) for v in parts]
            for i in range(0, len(nums) - 1, 2):
                points.append([nums[i], nums[i + 1]])
        else:
            name = " ".join(p for p in parts if not p.replace("-", "").replace(".", "").isdigit())
            nums = [float(p) for p in parts if p.replace("-", "").replace(".", "").isdigit()]
            if len(nums) >= 2:
                named[name] = [nums[0], nums[1]]
                points.append([nums[0], nums[1]])
    return points, named


def convert_port_crops(root: Path, size: int = 320, margin: float = 0.03) -> list[Record]:
    """Each 320x320 crop is one symbol filling the crop: box ~ the crop, terminals from the txt."""
    root = Path(root).resolve()
    port_root = _find_dir(root, "Component Port Location Data")
    if port_root is None:
        return []
    records: list[Record] = []
    for class_dir in sorted(p for p in port_root.iterdir() if p.is_dir()):
        cls = PORT_DIR_MAP.get(class_dir.name)
        if cls is None:
            continue
        images = class_dir / "Input Images"
        coords = class_dir / "XY Coordinates"
        if not images.is_dir() or not coords.is_dir():
            continue
        for img in sorted(images.glob("*.jpg")):
            txt = coords / (img.stem + ".txt")
            if not txt.exists():
                continue
            points, named = _parse_ports(txt.read_text(encoding="utf-8", errors="ignore"))
            pad = size * margin
            box = [pad, pad, size - pad, size - pad]
            polarity: Optional[str] = None
            candidates: Optional[list[str]] = None
            centre = (size / 2, size / 2)
            if cls == "voltage_source" and "Positive" in named:
                px, py = named["Positive"]
                polarity = direction_name(px - centre[0], py - centre[1])
            elif cls == "current_source" and "Flowing To" in named:
                px, py = named["Flowing To"]
                polarity = direction_name(px - centre[0], py - centre[1])
            elif cls == "ground":
                polarity = "down"
            elif len(points) == 2:
                (ax, ay), (bx, by) = points
                candidates = ["right", "left"] if abs(bx - ax) >= abs(by - ay) else ["up", "down"]
            records.append(Record(image=str(img), width=size, height=size, source="digitize_hcd_ports", group="ports",
                                  symbols=[Symbol(cls=cls, box=box, polarity=polarity, polarity_candidates=candidates,
                                                  terminals=points or None, source_label=class_dir.name)],
                                  junctions=None, wire_mask=None, texts_complete=False,
                                  meta={"crop": True}))
    return records


def convert(root: Path, include_ports: bool = True) -> list[Record]:
    records = convert_full_images(root)
    if include_ports:
        records += convert_port_crops(root)
    return records
