"""One record format for every data source, with explicit "unknown" markers.

Real datasets annotate different things (boxes only, boxes + rotation, stroke masks, port crops).
Every field that a source does not provide is `None`, and the tracer masks the matching loss, so
no source is forced to fake labels it does not have.
"""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable, Iterator, Optional

from PIL import Image

from ..classes import POLARITY, TRACER_CLASSES
from .orientation import open_oriented


@dataclass
class Symbol:
    cls: str                                    # one of TRACER_CLASSES
    box: list[float]                            # px [x0, y0, x1, y1]
    polarity: Optional[str] = None              # right | up | left | down; None = unknown
    polarity_candidates: Optional[list[str]] = None   # e.g. ["right", "left"] when only the axis is known
    class_candidates: Optional[list[str]] = None      # e.g. ["switch_open", "switch_closed"]: positive on every candidate
    terminals: Optional[list[list[float]]] = None      # px points; None = unknown
    text: Optional[str] = None                  # for cls == "text"
    id: Optional[str] = None
    source_label: Optional[str] = None          # the dataset's own class name

    def __post_init__(self) -> None:
        if self.cls not in TRACER_CLASSES:
            raise ValueError(f"unknown class {self.cls}")
        if self.polarity is not None and self.polarity not in POLARITY:
            raise ValueError(f"unknown polarity {self.polarity}")

    @property
    def centre(self) -> tuple[float, float]:
        return (self.box[0] + self.box[2]) / 2, (self.box[1] + self.box[3]) / 2

    @property
    def width(self) -> float:
        return self.box[2] - self.box[0]

    @property
    def height(self) -> float:
        return self.box[3] - self.box[1]


@dataclass
class Record:
    image: str                                  # path (absolute, or relative to the JSONL's directory)
    width: int
    height: int
    source: str                                 # synthetic | digitize_hcd | digitize_hcd_ports | cghd | scan
    group: str                                  # drafter / volunteer / seed bucket, used for splits
    symbols: list[Symbol] = field(default_factory=list)
    junctions: Optional[list[list[float]]] = None      # px points; None = not annotated
    wire_mask: Optional[str] = None                    # PNG path, 255 on wire ink (leads, junction dots included)
    ink_mask: Optional[str] = None                     # stroke segmentation (all ink); wire = ink minus symbol/text boxes
    texts_complete: bool = True                        # every text label is annotated
    circuit: Optional[dict] = None                     # the app's JSON when the netlist is known
    meta: dict = field(default_factory=dict)
    orientation: int = 1                              # EXIF code mapping the stored pixels onto the label frame

    @property
    def has_wire_supervision(self) -> bool:
        return self.wire_mask is not None or self.ink_mask is not None

    @property
    def has_terminal_supervision(self) -> bool:
        """True only when every non-text symbol has its terminals (so background is a true negative)."""
        comps = [s for s in self.symbols if s.cls not in ("text", "crossover")]
        return bool(comps) and all(s.terminals is not None for s in comps)

    def to_json(self) -> dict:
        return asdict(self)

    @classmethod
    def from_json(cls, obj: dict) -> "Record":
        symbols = [Symbol(**s) for s in obj.get("symbols", [])]
        rest = {k: v for k, v in obj.items() if k != "symbols"}
        return cls(symbols=symbols, **rest)


def write_jsonl(records: Iterable[Record], path: Path | str) -> int:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with path.open("w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r.to_json(), ensure_ascii=False) + "\n")
            n += 1
    return n


def read_jsonl(path: Path | str) -> list[Record]:
    path = Path(path)
    out: list[Record] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(Record.from_json(json.loads(line)))
    return out


def resolve_path(record_path: str, jsonl_path: Optional[Path]) -> Path:
    p = Path(record_path)
    if p.is_absolute() or jsonl_path is None:
        return p
    return (Path(jsonl_path).parent / p).resolve()


def open_record_image(record: Record, jsonl_path: Optional[Path]) -> "Image.Image":
    """The record's photo in the frame its labels were drawn in (EXIF applied when the record says so)."""
    return open_oriented(resolve_path(record.image, jsonl_path), record.orientation)


def axis_candidates(box: list[float], ratio: float = 1.3) -> Optional[list[str]]:
    """When only the box is known, an elongated symbol still tells us its axis."""
    w, h = box[2] - box[0], box[3] - box[1]
    if w > ratio * h:
        return ["right", "left"]
    if h > ratio * w:
        return ["up", "down"]
    return None


def direction_name(dx: float, dy: float) -> str:
    """Nearest of right/up/left/down for a screen-space vector (y down)."""
    if abs(dx) >= abs(dy):
        return "right" if dx >= 0 else "left"
    return "down" if dy >= 0 else "up"
