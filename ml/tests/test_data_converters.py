from pathlib import Path

from photomesh_ml.data import cghd, digitize_hcd
from photomesh_ml.data.records import Record, Symbol, read_jsonl, write_jsonl

FIX = Path(__file__).parent / "fixtures"


def test_digitize_hcd_full_images():
    records = digitize_hcd.convert_full_images(FIX / "dhcd")
    assert len(records) == 2
    r = next(r for r in records if r.meta["file_name"] == "circuit_0.jpg")
    kinds = {s.cls for s in r.symbols}
    assert "text" in kinds and "resistor" in kinds
    texts = [s.text for s in r.symbols if s.cls == "text"]
    assert "5V" in texts and any("Ω" in t for t in texts)
    comp = [s for s in r.symbols if s.cls != "text"]
    assert all(s.box[2] > s.box[0] and s.box[3] > s.box[1] for s in comp)
    assert all(s.polarity is None for s in comp)          # full images have no polarity labels
    assert r.junctions is None and r.wire_mask is None    # not annotated -> masked in training
    assert r.width == 2261 and r.height == 1416


def test_digitize_hcd_port_crops():
    records = digitize_hcd.convert_port_crops(FIX / "dhcd")
    by_cls = {r.symbols[0].cls: r for r in records}
    v = by_cls["voltage_source"].symbols[0]
    assert v.polarity == "right"                         # Positive at (291, 225) is right of the centre
    assert v.terminals == [[25.0, 118.0], [291.0, 225.0]]
    res = by_cls["resistor"].symbols[0]
    assert res.polarity is None and res.polarity_candidates == ["up", "down"]
    assert res.terminals == [[171.0, 26.0], [182.0, 293.0]]
    assert all(r.has_terminal_supervision for r in records)


def test_cghd_convert():
    records = cghd.convert(FIX / "cghd")
    assert len(records) == 1
    r = records[0]
    assert r.group == "drafter_1" and r.width == 4032 and r.height == 3024
    labels = {s.source_label for s in r.symbols}
    assert "voltage.dc" in labels and "diode" in labels
    vdc = next(s for s in r.symbols if s.source_label == "voltage.dc")
    assert vdc.cls == "voltage_source" and vdc.polarity == "up"   # rotation 350 -> positive at the top
    assert vdc.terminals is not None and len(vdc.terminals) == 2
    diode = next(s for s in r.symbols if s.source_label == "diode")
    assert diode.cls == "other"
    assert r.junctions is not None and len(r.junctions) > 0
    texts = [s for s in r.symbols if s.cls == "text"]
    assert texts and all(t.text for t in texts)


def test_jsonl_roundtrip(tmp_path):
    r = Record(image="a.jpg", width=10, height=10, source="synthetic", group="g", symbols=[Symbol("resistor", [1, 2, 3, 4], "right", terminals=[[1, 3], [3, 3]])], junctions=[[5, 5]])
    path = tmp_path / "x.jsonl"
    assert write_jsonl([r], path) == 1
    back = read_jsonl(path)
    assert back[0] == r
