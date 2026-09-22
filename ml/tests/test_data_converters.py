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
    # the fixture photo is the 4032x3024 original shrunk 8x; labels follow the photo, not the XML size
    assert r.group == "drafter_1" and (r.width, r.height) == (504, 378) and r.orientation == 1
    assert r.meta["xml_size"] == [4032, 3024]
    assert all(s.box[2] <= 504 and s.box[3] <= 378 for s in r.symbols)
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


# ----------------------------------------------------------------------------- EXIF orientation
from PIL import Image, ImageDraw  # noqa: E402

from photomesh_ml.data import downsize  # noqa: E402
from photomesh_ml.data.orientation import apply_orientation, detect_label_orientation, open_oriented  # noqa: E402

BOX = [20.0, 20.0, 80.0, 60.0]   # the one "symbol" on the upright page


def _upright_page(w: int = 240, h: int = 160, box=BOX) -> Image.Image:
    img = Image.new("L", (w, h), 255)
    ImageDraw.Draw(img).rectangle([int(v) for v in box], fill=0)
    return img


def _store(img: Image.Image, path: Path, code: int) -> None:
    """Write `img` as a camera would: pixels as given, orientation tag telling viewers how to turn them."""
    exif = Image.Exif()
    exif[0x0112] = code
    img.save(path, exif=exif.tobytes())


def test_orientation_swap_frames_decided_by_size(tmp_path):
    upright = _upright_page()
    raw = upright.transpose(Image.Transpose.ROTATE_90)          # what the sensor stored; tag 6 turns it back
    path = tmp_path / "photo.png"
    _store(raw, path, 6)
    # labeller applied EXIF (annotation size = upright size)
    assert detect_label_orientation(path, upright.size, [BOX]) == (6, 240, 160)
    # labeller worked on the stored pixels (annotation size = raw size)
    assert detect_label_orientation(path, raw.size, [BOX]) == (1, 160, 240)
    # a stroke mask in the label frame wins over the annotation size
    mask = tmp_path / "mask.png"
    upright.save(mask)
    assert detect_label_orientation(path, (1000, 1000), [BOX], mask) == (6, 240, 160)
    # and the pixels come back upright, without the tag that would turn them again
    opened = open_oriented(path, 6)
    assert opened.size == upright.size
    assert list(opened.convert("L").getdata()) == list(upright.getdata())
    assert "exif" not in opened.info and opened.getexif().get(0x0112) is None


def test_orientation_180_decided_by_ink(tmp_path):
    upright = _upright_page()
    raw = upright.transpose(Image.Transpose.ROTATE_180)
    path = tmp_path / "photo.png"
    _store(raw, path, 3)
    # sizes agree either way: the frame whose labels cover the ink wins
    assert detect_label_orientation(path, upright.size, [BOX]) == (3, 240, 160)
    raw_frame_box = [[240 - BOX[2], 160 - BOX[3], 240 - BOX[0], 160 - BOX[1]]]
    assert detect_label_orientation(path, upright.size, raw_frame_box) == (1, 240, 160)
    mask = tmp_path / "mask.png"
    upright.save(mask)
    assert detect_label_orientation(path, None, None, mask) == (3, 240, 160)


def test_orientation_bogus_annotation_size_uses_the_photo(tmp_path):
    page = _upright_page()
    path = tmp_path / "photo.png"
    page.save(path)
    assert detect_label_orientation(path, (1000, 1000), [BOX]) == (1, 240, 160)
    assert apply_orientation(page, 1).size == page.size


def test_downsize_writes_upright_pixels(tmp_path):
    upright = _upright_page(480, 320, box=[40, 40, 160, 120])
    raw = upright.transpose(Image.Transpose.ROTATE_90)
    src = tmp_path / "photo.png"
    _store(raw, src, 6)
    record = Record(image=str(src), width=480, height=320, source="cghd", group="d", orientation=6,
                    symbols=[Symbol(cls="resistor", box=[40, 40, 160, 120])], junctions=[[100.0, 200.0]])
    out = downsize.downsize_record(record, tmp_path / "small", max_side=240, jsonl_dir=None)
    assert out is not None and out.orientation == 1 and (out.width, out.height) == (240, 160)
    assert out.symbols[0].box == [20, 20, 80, 60] and out.junctions == [[50.0, 100.0]]
    shrunk = Image.open(out.image).convert("L")
    assert shrunk.size == (240, 160)
    assert shrunk.getpixel((50, 40)) < 60 and shrunk.getpixel((200, 120)) > 200     # ink where the box says
    # a photo the record mis-describes is dropped, not silently mislabelled
    bad = Record(image=str(src), width=999, height=320, source="cghd", group="d", orientation=6)
    assert downsize.downsize_record(bad, tmp_path / "small", max_side=240, jsonl_dir=None) is None


def test_record_orientation_roundtrip():
    r = Record(image="a.jpg", width=10, height=20, source="cghd", group="d", orientation=8)
    assert Record.from_json(r.to_json()).orientation == 8
    legacy = {k: v for k, v in r.to_json().items() if k != "orientation"}
    assert Record.from_json(legacy).orientation == 1
