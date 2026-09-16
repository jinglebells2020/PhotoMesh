import base64
import io
import json
import math
from pathlib import Path

import pytest
import torch
from PIL import Image

from photomesh_ml.data import scans, synthetic
from photomesh_ml.eval.detection import DetectionSet, mean_average_precision
from photomesh_ml.eval.metrics import bootstrap_ci
from photomesh_ml.schema import Circuit
from photomesh_ml.solver import solve
from photomesh_ml.synth.generate import make_sample, sample_to_label
from photomesh_ml.tracer.checkpoint import save_checkpoint
from photomesh_ml.tracer.evaluate import evaluate_records, ocr_from_record
from photomesh_ml.tracer.infer import Tracer
from photomesh_ml.tracer.model import CircuitNet


def _swift_sample(with_correction: bool) -> dict:
    img = Image.new("RGB", (400, 300), (250, 250, 250))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    circuit = {
        "components": [
            {"id": "V1", "kind": "voltage_source", "value": 12, "nodeA": "a", "nodeB": "0"},
            {"id": "R1", "kind": "resistor", "value": 100, "nodeA": "a", "nodeB": "b"},
            {"id": "R2", "kind": "resistor", "value": 200, "nodeA": "b", "nodeB": "0"},
        ],
        "groundNode": "0", "meshes": [], "unknowns": [{"kind": "current", "element": "R2"}], "question": "Find I through R2.",
        "unsupported": [],
        "geometry": {"placements": {"V1": {"box": {"minX": 0.1, "minY": 0.4, "maxX": 0.2, "maxY": 0.6}, "isHorizontal": False},
                                    "R1": {"box": {"minX": 0.3, "minY": 0.2, "maxX": 0.5, "maxY": 0.3}, "isHorizontal": True},
                                    "R2": {"box": {"minX": 0.6, "minY": 0.4, "maxX": 0.7, "maxY": 0.6}, "isHorizontal": False}},
                     "nodePoints": {"0": {"x": 0.5, "y": 0.8}, "a": {"x": 0.25, "y": 0.2}, "b": {"x": 0.55, "y": 0.2}}, "aspectRatio": 1.33},
    }
    corrected = json.loads(json.dumps(circuit))
    corrected["components"][2]["value"] = 220
    return {"id": "ABC-1", "timestamp": "2026-09-16T10:00:00Z", "model": "google/gemini-3.5-flash-lite", "recognized": circuit,
            "corrected": corrected if with_correction else None, "accepted": not with_correction,
            "imageWidth": 400, "imageHeight": 300, "imageBase64": base64.b64encode(buf.getvalue()).decode()}


def test_scan_export_conversion(tmp_path):
    payload = {"installId": "install-1", "exportedAt": "2026-09-16T10:00:00Z", "events": [], "samples": [_swift_sample(True), {**_swift_sample(False), "id": "ABC-2"}]}
    (tmp_path / "export.json").write_text(json.dumps(payload))
    records = scans.convert([tmp_path / "export.json"], tmp_path / "out")
    assert len(records) == 2
    corrected = next(r for r in records if r.meta["truth"] == "corrected")
    circuit = Circuit.from_json(corrected.circuit)
    assert circuit.component("R2").value == 220 and circuit.component("V1").node_a == "a"
    sol = solve(circuit)
    assert math.isclose(sol.currents["R2"], 12 / 320)
    assert corrected.width == 400 and corrected.group == "install-1"
    assert [s.cls for s in corrected.symbols] == ["voltage_source", "resistor", "resistor"]
    assert corrected.symbols[1].box == [120.0, 60.0, 200.0, 90.0] and corrected.symbols[0].polarity_candidates == ["up", "down"]
    assert Path(corrected.image).exists()
    accepted = next(r for r in records if r.meta["truth"] == "accepted")
    assert Circuit.from_json(accepted.circuit).component("R2").value == 200


def test_detection_ap_and_bootstrap():
    images = [DetectionSet(predictions=[("resistor", [0, 0, 10, 10], 0.9), ("resistor", [50, 50, 60, 60], 0.8), ("resistor", [100, 100, 110, 110], 0.3)],
                           truths=[("resistor", [0, 0, 10, 10]), ("resistor", [50, 50, 60, 60]), ("ground", [80, 80, 90, 90])])]
    result = mean_average_precision(images, ["resistor", "ground", "lamp"])
    assert result["per_class"]["resistor"]["ap"] == pytest.approx(1.0)      # both truths found before the false positive
    assert result["per_class"]["ground"]["ap"] == 0.0 and result["per_class"]["lamp"]["ap"] is None
    assert result["mAP"] == pytest.approx(0.5)
    lo, hi = bootstrap_ci([True] * 30 + [False] * 10, n_boot=300)
    assert 0.55 < lo < 0.75 < hi < 0.95


def _synthetic_dir(root: Path, seeds):
    for sub in ("images", "masks", "labels"):
        (root / sub).mkdir(parents=True, exist_ok=True)
    for i, seed in enumerate(seeds):
        s = make_sample(seed, augment_photo=False, out_long=384)
        name = f"{i:06d}"
        s.image.save(root / "images" / f"{name}.jpg")
        Image.fromarray(s.wire_mask, "L").save(root / "masks" / f"{name}.png")
        label = sample_to_label(s, f"images/{name}.jpg", f"masks/{name}.png")
        label["seed"] = seed
        (root / "labels" / f"{name}.json").write_text(json.dumps(label))


def test_tracer_inference_and_evaluation(tmp_path):
    torch.manual_seed(0)
    model = CircuitNet("tiny", width=16)
    ckpt = tmp_path / "tiny.pt"
    save_checkpoint(ckpt, model, {"backbone": "tiny", "width": 16, "size": 128, "stride": 4}, 0, None)
    _synthetic_dir(tmp_path / "synth", [7, 8])
    records = synthetic.convert(tmp_path / "synth")
    tracer = Tracer(ckpt, "cpu", threshold=0.3)
    image = Image.open(records[0].image)
    result = tracer.recognize(image, ocr_from_record(records[0]), tta=True)
    assert 0.0 <= result.confidence <= 1.0 and result.agreement is not None and 0.0 <= result.agreement <= 1.0
    assert result.letterbox.size == 128 and result.maps["wire"].shape == (128, 128)
    json.loads(result.circuit.dumps())  # serialisable app JSON
    summary, details = evaluate_records(tracer, records, None, limit=2, tta=False, ocr="gt")
    assert summary["overall"]["n"] == 2 and "detection" in summary and len(details) == 2
    assert set(summary["by_style"]) <= {"hand", "print"}
