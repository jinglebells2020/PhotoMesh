"""CGHD, the DFKI hand-drawn circuit dataset (Zenodo 14042961 / HF lowercaseonly/cghd, CC BY 4.0) -> records.

Layout: drafter_N/{annotations/*.xml, images/*.jpg, segmentation/*.jpg, instances/*.json, spice/*.asc}
plus classes.json and classes_ports.json at the root. Annotations are PASCAL VOC with two
extensions inside <bndbox>: <rotation> (degrees, counter-clockwise on screen, checked against the
images) and a <text> child on text objects.

Rotation + the class port table give the polarity of DC sources and batteries, and terminal
points for two-terminal symbols drawn close to an axis. The binary segmentation maps (stroke vs
background) give wire supervision once symbol and text boxes are removed.
"""
from __future__ import annotations

import json
import math
from dataclasses import replace
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Optional

from .orientation import detect_label_orientation
from .records import Record, Symbol, axis_candidates, direction_name

CLASS_MAP = {
    "resistor": "resistor", "resistor.adjustable": "other", "resistor.photo": "other",
    "capacitor.unpolarized": "capacitor", "capacitor.polarized": "capacitor", "capacitor.adjustable": "capacitor",
    "inductor": "inductor", "inductor.ferrite": "inductor", "inductor.coupled": "other", "transformer": "other",
    "voltage.dc": "voltage_source", "voltage.battery": "battery", "voltage.ac": "other",
    "gnd": "ground", "vss": "other", "junction": "__junction__", "crossover": "crossover", "terminal": "other",
    "text": "text", "switch": "__switch__", "lamp": "lamp", "relay": "other", "fuse": "other", "socket": "other",
    "probe.current": "other", "probe.voltage": "other", "__background__": None,
}
TWO_TERMINAL = {"resistor", "capacitor", "inductor", "voltage_source", "battery", "lamp", "current_source"}
NON_POLAR_AXIS = {"resistor", "capacitor", "inductor", "lamp", "other"}


def _rotate_screen(dx: float, dy: float, degrees: float) -> tuple[float, float]:
    """Counter-clockwise on screen (y down) by `degrees`."""
    t = math.radians(degrees)
    return dx * math.cos(t) + dy * math.sin(t), -dx * math.sin(t) + dy * math.cos(t)


def _near_axis(degrees: float, tolerance: float = 20.0) -> bool:
    r = degrees % 90
    return min(r, 90 - r) <= tolerance


def parse_annotation(xml_path: Path, ports: dict) -> tuple[int, int, list[Symbol], list[list[float]]]:
    root = ET.parse(xml_path).getroot()
    size = root.find("size")
    width, height = int(size.find("width").text), int(size.find("height").text)
    symbols: list[Symbol] = []
    junctions: list[list[float]] = []
    for obj in root.findall("object"):
        label = (obj.find("name").text or "").strip()
        bb = obj.find("bndbox")
        x0, y0, x1, y1 = [float(bb.find(k).text) for k in ("xmin", "ymin", "xmax", "ymax")]
        box = [x0, y0, x1, y1]
        rot_el = bb.find("rotation")
        rotation = float(rot_el.text) if rot_el is not None and rot_el.text else None
        mapped = CLASS_MAP.get(label, "other")
        if mapped is None:
            continue
        if mapped == "__junction__":
            junctions.append([(x0 + x1) / 2, (y0 + y1) / 2])
            continue
        text_el = obj.find("text")
        text = text_el.text.strip() if (text_el is not None and text_el.text) else None
        if mapped == "text":
            symbols.append(Symbol(cls="text", box=box, text=text, source_label=label))
            continue
        cls = mapped
        class_candidates = None
        if mapped == "__switch__":
            cls, class_candidates = "switch_open", ["switch_open", "switch_closed"]
        polarity: Optional[str] = None
        candidates: Optional[list[str]] = None
        terminals: Optional[list[list[float]]] = None
        port_list = ports.get(label, [])
        if rotation is not None and cls in ("voltage_source", "battery") and port_list:
            pos = next((p for p in port_list if p["name"] == "positive"), None)
            if pos is not None:
                dx, dy = pos["position"][0] - 0.5, pos["position"][1] - 0.5
                rx, ry = _rotate_screen(dx, dy, rotation)
                polarity = direction_name(rx, ry)
        elif cls in NON_POLAR_AXIS:
            if rotation is not None:
                candidates = ["right", "left"] if _near_axis(rotation) and (rotation % 180) < 45 or (rotation % 180) > 135 else ["up", "down"]
                if not _near_axis(rotation):
                    candidates = None
            else:
                candidates = axis_candidates(box)
        if cls in TWO_TERMINAL and rotation is not None and _near_axis(rotation) and len(port_list) == 2:
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            terminals = []
            for p in port_list:
                dx, dy = p["position"][0] - 0.5, p["position"][1] - 0.5
                rx, ry = _rotate_screen(dx, dy, rotation)
                # snap to the box edge midpoint in that direction
                if abs(rx) >= abs(ry):
                    terminals.append([x1 if rx > 0 else x0, cy])
                else:
                    terminals.append([cx, y1 if ry > 0 else y0])
        if cls == "ground":
            polarity = "down" if rotation is None or _near_axis(rotation) and (rotation % 360) < 45 else None
        symbols.append(Symbol(cls=cls, box=box, polarity=polarity, polarity_candidates=candidates, class_candidates=class_candidates,
                              terminals=terminals, text=text, source_label=label))
    return width, height, symbols, junctions


def _scaled(symbol: Symbol, sx: float, sy: float) -> Symbol:
    x0, y0, x1, y1 = symbol.box
    return replace(symbol, box=[x0 * sx, y0 * sy, x1 * sx, y1 * sy],
                   terminals=[[x * sx, y * sy] for x, y in symbol.terminals] if symbol.terminals else None)


def convert(root: Path, drafters: Optional[list[str]] = None) -> list[Record]:
    root = Path(root).resolve()
    ports = json.loads((root / "classes_ports.json").read_text(encoding="utf-8")) if (root / "classes_ports.json").exists() else {}
    records: list[Record] = []
    for drafter_dir in sorted(p for p in root.glob("drafter_*") if p.is_dir()):
        if drafters and drafter_dir.name not in drafters:
            continue
        ann_dir = drafter_dir / "annotations"
        if not ann_dir.is_dir():
            continue
        for xml_path in sorted(ann_dir.glob("*.xml")):
            stem = xml_path.stem
            image = next((p for p in (drafter_dir / "images").glob(stem + ".*") if p.suffix.lower() in (".jpg", ".jpeg", ".png")), None)
            if image is None:
                continue
            xml_w, xml_h, symbols, junctions = parse_annotation(xml_path, ports)
            seg = next(iter((drafter_dir / "segmentation").glob(stem + ".*")), None) if (drafter_dir / "segmentation").is_dir() else None
            # Boxes are in pixels of whichever frame the labeller saw; the XML size is only a hint (two
            # drafters ship 1000x1000 for 12 MP photos), so the frame is detected from the photo itself.
            orientation, width, height = detect_label_orientation(image, (xml_w, xml_h), [s.box for s in symbols], seg)
            if (width, height) != (xml_w, xml_h):
                # A photo resized uniformly after labelling (boxes still fit the XML frame) is rescaled;
                # a bogus XML size (boxes already in photo pixels) is simply ignored.
                sx, sy = width / xml_w, height / xml_h
                fits = all(s.box[2] <= xml_w + 1 and s.box[3] <= xml_h + 1 for s in symbols)
                if fits and abs(sx - sy) <= 0.02 * max(sx, sy):
                    symbols = [_scaled(s, sx, sy) for s in symbols]
                    junctions = [[x * sx, y * sy] for x, y in junctions]
            records.append(Record(image=str(image), width=width, height=height, source="cghd", group=drafter_dir.name,
                                  symbols=symbols, junctions=junctions, wire_mask=None, ink_mask=str(seg) if seg else None,
                                  texts_complete=True, meta={"circuit": stem.split("_")[0], "xml_size": [xml_w, xml_h]},
                                  orientation=orientation))
    return records
