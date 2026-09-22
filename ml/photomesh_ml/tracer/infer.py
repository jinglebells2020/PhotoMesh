"""End-to-end tracer inference: image -> CircuitNet -> assembler -> the app's JSON.

    python -m photomesh_ml.tracer.infer --checkpoint runs/tracer/last.pt --image photo.jpg [--ocr ocr.json] [--tta] [--debug out.png]

`--ocr` is a JSON list of {"box": [x0, y0, x1, y1], "text": "..."} in image pixels (on the phone
this comes from Vision; here from a file or, for evaluation, from the record's text labels).
With `--tta` the image is also read at two other scales and the netlists are compared with the
solver; the share of agreeing readings scales the confidence (consistency-based confidence, in
the spirit of RREV's IPFE).
"""
from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image, ImageOps

from ..schema import Circuit
from ..solver import same_solution
from .assemble import Assembly, Detection, TextItem, assemble, decode_symbols
from .checkpoint import load_checkpoint
from .model import normalize

# Features the calibrated confidence is computed from (see tracer/calibrate.py).
FEATURE_NAMES = ["min_score", "mean_score", "attached", "values_missing", "valid", "n_components", "agreement", "unsupported"]


@dataclass
class Letterbox:
    scale: float
    tx: float
    ty: float
    size: int

    def to_input(self, x: float, y: float) -> tuple[float, float]:
        return x * self.scale + self.tx, y * self.scale + self.ty

    def to_image(self, x: float, y: float) -> tuple[float, float]:
        return (x - self.tx) / self.scale, (y - self.ty) / self.scale


@dataclass
class TracerResult:
    circuit: Circuit
    confidence: float
    agreement: Optional[float]
    detections: list[Detection]            # in image pixels
    assembly: Assembly
    letterbox: Letterbox
    maps: dict[str, np.ndarray] = field(default_factory=dict)
    latency: float = 0.0
    features: dict[str, float] = field(default_factory=dict)


def assembly_features(assembly: Assembly, agreement: Optional[float]) -> dict[str, float]:
    comps = [d for d in assembly.detections if d.cls not in ("text", "ground", "crossover", "other")]
    scores = [d.score for d in comps]
    notes = " ".join(assembly.notes)
    return {
        "min_score": min(scores) if scores else 0.0,
        "mean_score": sum(scores) / len(scores) if scores else 0.0,
        "attached": assembly.attached_fraction,
        "values_missing": 1.0 if "values missing" in notes else 0.0,
        "valid": 0.0 if "validation" in notes else 1.0,
        "n_components": float(len(comps)),
        "agreement": agreement if agreement is not None else 1.0,
        "unsupported": 1.0 if assembly.circuit.unsupported else 0.0,
    }


class Tracer:
    def __init__(self, checkpoint: str | Path, device: str = "cpu", threshold: float = 0.3, wire_threshold: float = 0.4,
                 closing: int = -1, body_removal: str = "span", unit_kinds: bool = False):
        self.device = torch.device(device)
        self.model, ckpt = load_checkpoint(checkpoint, self.device)
        self.size = int(ckpt["config"].get("size", 640))
        self.stride = int(ckpt["config"].get("stride", 4))
        self.threshold = threshold
        self.wire_threshold = wire_threshold
        self.closing = closing
        self.body_removal = body_removal
        self.unit_kinds = unit_kinds
        self.calibration = ckpt.get("calibration")

    # ------------------------------------------------------------------ preprocessing
    def letterbox(self, image: Image.Image, scale_mult: float = 1.0) -> tuple[torch.Tensor, Letterbox]:
        S = self.size
        w, h = image.size
        scale = S / max(w, h) * scale_mult
        tx, ty = (S - w * scale) / 2, (S - h * scale) / 2
        border = np.asarray(image)[[0, -1], :, :].reshape(-1, 3)
        fill = tuple(int(v) for v in np.median(border, axis=0))
        inv = (1 / scale, 0.0, -tx / scale, 0.0, 1 / scale, -ty / scale)
        boxed = image.transform((S, S), Image.AFFINE, inv, resample=Image.BILINEAR, fillcolor=fill)
        tensor = torch.from_numpy(np.asarray(boxed, np.uint8).copy()).permute(2, 0, 1).unsqueeze(0)
        return tensor, Letterbox(scale, tx, ty, S)

    @torch.no_grad()
    def maps(self, tensor: torch.Tensor) -> dict[str, np.ndarray]:
        out = self.model.predict(normalize(tensor.to(self.device)))
        S = self.size
        full = {k: F.interpolate(out[k], size=(S, S), mode="bilinear", align_corners=False)[0, 0].cpu().numpy() for k in ("wire", "junction", "terminal")}
        return {
            "symbol_heat": out["symbol_heat"][0].cpu().numpy(), "symbol_size": out["symbol_size"][0].cpu().numpy(),
            "symbol_off": out["symbol_off"][0].cpu().numpy(), "polarity": out["polarity"][0].cpu().numpy(), **full,
        }

    # ------------------------------------------------------------------ one reading
    def read(self, image: Image.Image, ocr: Optional[list[TextItem]] = None, scale_mult: float = 1.0) -> tuple[Assembly, Letterbox, dict[str, np.ndarray]]:
        tensor, box = self.letterbox(image, scale_mult)
        maps = self.maps(tensor)
        dets = decode_symbols(maps["symbol_heat"], maps["symbol_size"], maps["symbol_off"], maps["polarity"], self.stride, self.threshold)
        ocr_in = None
        if ocr:
            ocr_in = []
            for t in ocr:
                x0, y0 = box.to_input(t.box[0], t.box[1])
                x1, y1 = box.to_input(t.box[2], t.box[3])
                ocr_in.append(TextItem([x0, y0, x1, y1], t.text))
        assembly = assemble(dets, maps["wire"], (self.size, self.size), ocr_in, maps["junction"], wire_threshold=self.wire_threshold,
                            terminal_prob=maps["terminal"], closing=self.closing, body_removal=self.body_removal, unit_kinds=self.unit_kinds)
        return assembly, box, maps

    def recognize(self, image: Image.Image, ocr: Optional[list[TextItem]] = None, tta: bool = False) -> TracerResult:
        started = time.time()
        image = ImageOps.exif_transpose(image).convert("RGB")
        assembly, box, maps = self.read(image, ocr)
        agreement = None
        if tta:
            # Read at three scales; keep the reading most others agree with (solver-checked), and
            # scale the confidence by that agreement (consistency as confidence, cf. RREV's IPFE).
            readings = [(assembly, box, maps)] + [self.read(image, ocr, mult) for mult in (0.85, 1.15)]
            votes = [sum(same_solution(r[0].circuit, o[0].circuit) for o in readings if o is not r) for r in readings]
            best = max(range(len(readings)), key=lambda i: (votes[i], readings[i][0].confidence, -i))
            assembly, box, maps = readings[best]
            agreement = votes[best] / (len(readings) - 1)
        circuit = _to_image_coords(assembly.circuit, box, image.size)
        features = assembly_features(assembly, agreement)
        if self.calibration:
            z = self.calibration["bias"] + sum(w * features[k] for w, k in zip(self.calibration["weights"], self.calibration["features"]))
            confidence = 1.0 / (1.0 + math.exp(-z))
        else:
            confidence = assembly.confidence * ((0.5 + 0.5 * agreement) if agreement is not None else 1.0)
        circuit.confidence = round(confidence, 3)
        dets = [Detection(d.cls, d.score, [*box.to_image(d.box[0], d.box[1]), *box.to_image(d.box[2], d.box[3])], d.polarity, d.polarity_probs) for d in assembly.detections]
        return TracerResult(circuit, confidence, agreement, dets, assembly, box, maps, time.time() - started, features)


def _to_image_coords(circuit: Circuit, box: Letterbox, image_size: tuple[int, int]) -> Circuit:
    W, H = image_size
    out = circuit.renaming_nodes(lambda n: n)
    S = box.size
    for c in out.components:
        if c.box is None:
            continue
        x0, y0 = box.to_image(c.box[0] * S, c.box[1] * S)
        x1, y1 = box.to_image(c.box[2] * S, c.box[3] * S)
        c.box = [max(0.0, x0 / W), max(0.0, y0 / H), min(1.0, x1 / W), min(1.0, y1 / H)]
    points = {}
    for node, (fx, fy) in out.node_points.items():
        x, y = box.to_image(fx * S, fy * S)
        points[node] = [min(1.0, max(0.0, x / W)), min(1.0, max(0.0, y / H))]
    out.node_points = points
    return out


def load_ocr(path: Optional[str]) -> Optional[list[TextItem]]:
    if not path:
        return None
    rows = json.loads(Path(path).read_text(encoding="utf-8"))
    return [TextItem([float(v) for v in r["box"]], str(r["text"])) for r in rows]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--ocr", default=None)
    parser.add_argument("--tta", action="store_true")
    parser.add_argument("--threshold", type=float, default=0.3)
    parser.add_argument("--wire-threshold", type=float, default=0.4)
    parser.add_argument("--body-removal", choices=["span", "box"], default="span")
    parser.add_argument("--debug", default=None, help="write an overlay PNG")
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    tracer = Tracer(args.checkpoint, args.device, args.threshold, args.wire_threshold, body_removal=args.body_removal)
    image = Image.open(args.image)
    result = tracer.recognize(image, load_ocr(args.ocr), args.tta)
    print(result.circuit.dumps())
    print(f"# confidence {result.confidence:.3f} agreement {result.agreement} latency {result.latency:.2f}s detections {len(result.detections)}", flush=True)
    if args.debug:
        from .debug import render_assembly
        tensor, box = tracer.letterbox(ImageOps.exif_transpose(image).convert("RGB"))
        boxed = Image.fromarray(tensor[0].permute(1, 2, 0).numpy())
        render_assembly(boxed, result.assembly).save(args.debug)
        print("wrote", args.debug)


if __name__ == "__main__":
    main()
