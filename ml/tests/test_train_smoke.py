"""The training CLI runs end to end on tiny data with every option that changes the loop."""
import json
from pathlib import Path

from PIL import Image

from photomesh_ml.data.records import write_jsonl
from photomesh_ml.data import synthetic
from photomesh_ml.synth.generate import make_sample, sample_to_label
from photomesh_ml.tracer import detect_eval, train


def test_train_cli_smoke(tmp_path):
    root = tmp_path / "synth"
    for sub in ("images", "masks", "labels"):
        (root / sub).mkdir(parents=True, exist_ok=True)
    for i, seed in enumerate([21, 22, 23, 24]):
        s = make_sample(seed, augment_photo=False, out_long=256)
        name = f"{i:06d}"
        s.image.save(root / "images" / f"{name}.jpg")
        Image.fromarray(s.wire_mask, "L").save(root / "masks" / f"{name}.png")
        label = sample_to_label(s, f"images/{name}.jpg", f"masks/{name}.png")
        label["seed"] = seed
        (root / "labels" / f"{name}.json").write_text(json.dumps(label))
    records = synthetic.convert(root)
    jsonl = tmp_path / "records.jsonl"
    write_jsonl(records, jsonl)
    out = tmp_path / "run"
    train.main(["--train", str(jsonl), "--val", str(jsonl), "--backbone", "tiny", "--width", "16", "--size", "128", "--epochs", "1",
                "--batch", "2", "--workers", "0", "--max-steps", "2", "--out", str(out), "--balance-rare", "1.0", "--ema", "0.9",
                "--e2e-records", str(jsonl), "--e2e-limit", "2", "--no-mosaic", "--device", "cpu"])
    assert (out / "last.pt").exists()
    lines = [json.loads(l) for l in (out / "log.jsonl").read_text().splitlines() if l.strip()]
    assert any("e2e" in l for l in lines) and any("val" in l for l in lines)
    val = next(l for l in lines if "val" in l)["val"]
    assert "detection" in val and "mAP" in val["detection"]
    # detection-only evaluation runs on the same records and writes a per-source summary
    detect_eval.main(["--checkpoint", str(out / "last.pt"), "--records", str(jsonl), "--limit", "2", "--bootstrap", "5",
                      "--out", str(out / "detect")])
    summary = json.loads((out / "detect.json").read_text())
    assert summary["synthetic"]["images"] == 2 and "mAP" in summary["synthetic"] and "polarity" in summary["synthetic"]
    assert (out / "detect.md").read_text().startswith("| source |")
