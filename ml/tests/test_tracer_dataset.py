import json
from pathlib import Path

import pytest
import torch
from PIL import Image

from photomesh_ml.data import digitize_hcd, synthetic
from photomesh_ml.synth.generate import make_sample, sample_to_label
from photomesh_ml.tracer.dataset import MAX_OBJECTS, TracerDataset, collate

FIX = Path(__file__).parent / "fixtures"


def _write_synthetic(root: Path, seeds):
    for sub in ("images", "masks", "labels"):
        (root / sub).mkdir(parents=True, exist_ok=True)
    for i, seed in enumerate(seeds):
        s = make_sample(seed, augment_photo=False, out_long=512)
        name = f"{i:06d}"
        s.image.save(root / "images" / f"{name}.jpg")
        Image.fromarray(s.wire_mask, "L").save(root / "masks" / f"{name}.png")
        label = sample_to_label(s, f"images/{name}.jpg", f"masks/{name}.png")
        label["seed"] = seed
        (root / "labels" / f"{name}.json").write_text(json.dumps(label))


def test_dataset_items_and_mosaic(tmp_path):
    _write_synthetic(tmp_path / "synth", [5, 6])
    records = synthetic.convert(tmp_path / "synth") + digitize_hcd.convert_port_crops(FIX / "dhcd") * 3
    ds = TracerDataset(records, input_size=128, train=True, mosaic_ports=True, seed=1)
    kinds = [k for k, _ in ds.items]
    assert kinds.count("record") == 2 and kinds.count("mosaic") == 1
    for i in range(len(ds)):
        item = ds[i]
        assert item["image"].shape == (3, 128, 128) and item["image"].dtype == torch.uint8
        assert item["heat"].shape[1:] == (32, 32) and item["wire"].shape == (1, 32, 32)
        assert item["index"].shape == (MAX_OBJECTS,)
        n = int(item["reg_mask"].sum())
        assert 0 < n < MAX_OBJECTS
        if ds.items[i][0] == "record":
            assert float(item["wire_weight"]) == 1.0 and float(item["junction_weight"]) == 1.0 and float(item["terminal_weight"]) == 1.0
        else:
            assert float(item["wire_weight"]) == 0.0 and float(item["terminal_weight"]) == 1.0
    batch = collate([ds[0], ds[1]])
    assert batch["image"].shape == (2, 3, 128, 128) and batch["heat"].shape[0] == 2
    # geometry follows the letterbox: every positive centre lies inside the map
    assert int(batch["index"].max()) < 32 * 32


def test_rotation_keeps_labels_inside_and_consistent(tmp_path):
    _write_synthetic(tmp_path / "synth", [11])
    records = synthetic.convert(tmp_path / "synth")
    ds = TracerDataset(records, input_size=160, train=True, mosaic_ports=False, seed=3, max_rotation=8.0)
    item = ds[0]
    n = int(item["reg_mask"].sum())
    assert n == len(records[0].symbols)
    assert int(item["index"].max()) < 40 * 40
    # rotated wire ink still lands on the wire target
    assert float(item["wire"].sum()) > 0
