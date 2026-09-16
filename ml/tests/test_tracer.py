import numpy as np
import pytest
import torch

from photomesh_ml.classes import CLASS_INDEX, TRACER_CLASSES
from photomesh_ml.data.records import Record, Symbol
from photomesh_ml.tracer.assemble import decode_symbols, label_components
from photomesh_ml.tracer.losses import total_loss
from photomesh_ml.tracer.model import CircuitNet, normalize
from photomesh_ml.tracer.targets import build_targets, gaussian_radius


def test_targets_shapes_and_masks():
    record = Record(image="x", width=128, height=128, source="synthetic", group="g", symbols=[
        Symbol("resistor", [20, 30, 60, 40], "right", terminals=[[20, 35], [60, 35]]),
        Symbol("voltage_source", [80, 20, 100, 40], "up", terminals=[[90, 20], [90, 40]]),
        Symbol("switch_open", [10, 90, 40, 100], class_candidates=["switch_open", "switch_closed"]),
        Symbol("text", [70, 90, 100, 100], text="4.7k"),
    ], junctions=[[64, 64]])
    wire = np.zeros((128, 128), np.uint8)
    wire[35, 0:20] = 255
    t = build_targets(record, (128, 128), 4, wire)
    assert t.heat.shape == (len(TRACER_CLASSES), 32, 32)
    assert t.heat[CLASS_INDEX["resistor"]].max() == pytest.approx(1.0)
    assert t.heat[CLASS_INDEX["text"]].max() == pytest.approx(1.0)
    # the ambiguous switch produces an ignore region instead of a peak
    assert t.heat[CLASS_INDEX["switch_open"]].max() == 0
    assert t.heat_weight[CLASS_INDEX["switch_closed"], 23, 5] == 0
    assert len(t.index) == 3
    assert t.polarity_weight.tolist() == [1.0, 1.0, 0.0]
    assert t.wire_weight == 1.0 and t.wire[0, 8, 0] == 1.0
    assert t.junction_weight == 1.0 and t.junction[0, 16, 16] == pytest.approx(1.0)
    assert t.terminal_weight == 0.0     # the switch has no terminals -> whole head masked


def test_gaussian_radius_grows_with_box():
    assert gaussian_radius(10, 10) < gaussian_radius(30, 30)


def test_label_components_8_connectivity():
    m = np.zeros((6, 6), bool)
    m[0, 0] = m[1, 1] = m[2, 2] = True      # diagonal chain
    m[5, 0:3] = True                         # separate run
    labels, n = label_components(m)
    assert n == 2
    assert labels[0, 0] == labels[1, 1] == labels[2, 2]
    assert labels[5, 0] != labels[0, 0]


def test_decode_symbols_finds_peak():
    K, h, w = len(TRACER_CLASSES), 16, 16
    heat = np.zeros((K, h, w), np.float32)
    heat[CLASS_INDEX["resistor"], 5, 7] = 0.9
    heat[CLASS_INDEX["resistor"], 5, 8] = 0.6
    size = np.zeros((2, h, w), np.float32)
    size[:, 5, 7] = [8, 3]
    off = np.zeros((2, h, w), np.float32)
    pol = np.zeros((4, h, w), np.float32)
    pol[0] = 1.0
    dets = decode_symbols(heat, size, off, pol, stride=4, threshold=0.3)
    assert len(dets) == 1
    d = dets[0]
    assert d.cls == "resistor" and d.polarity == "right"
    assert d.box == pytest.approx([28 - 16, 20 - 6, 28 + 16, 20 + 6])


def test_model_forward_backward_tiny():
    model = CircuitNet("tiny", width=32)
    x = normalize(torch.randint(0, 255, (2, 3, 128, 128), dtype=torch.uint8))
    out = model(x)
    assert out["symbol_heat"].shape == (2, len(TRACER_CLASSES), 32, 32)
    assert out["wire"].shape == (2, 1, 32, 32)
    B, N = 2, 4
    batch = {
        "heat": torch.zeros(B, len(TRACER_CLASSES), 32, 32), "heat_weight": torch.ones(B, len(TRACER_CLASSES), 32, 32),
        "size": torch.ones(B, N, 2), "offset": torch.zeros(B, N, 2), "index": torch.zeros(B, N, dtype=torch.long),
        "reg_mask": torch.tensor([[1, 1, 0, 0], [1, 0, 0, 0]], dtype=torch.float32),
        "polarity": torch.zeros(B, N, 4), "polarity_weight": torch.ones(B, N),
        "wire": torch.zeros(B, 1, 32, 32), "wire_weight": torch.tensor([1.0, 0.0]),
        "junction": torch.zeros(B, 1, 32, 32), "junction_weight": torch.tensor([1.0, 1.0]),
        "terminal": torch.zeros(B, 1, 32, 32), "terminal_weight": torch.tensor([0.0, 0.0]),
    }
    batch["heat"][0, 0, 3, 3] = 1.0
    batch["polarity"][:, :, 0] = 1.0
    loss, terms = total_loss(out, batch)
    assert torch.isfinite(loss)
    loss.backward()
    assert all(k in terms for k in ("heat", "size", "off", "polarity", "wire", "junction", "terminal"))
