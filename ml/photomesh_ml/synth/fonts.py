"""Open-licensed fonts for labels: handwriting faces for sketches, print faces for textbook style.

Fonts are downloaded once from the google/fonts repository (all under the SIL Open Font License)
into ~/.cache/photomesh-ml/fonts. DejaVu Sans is the fallback when offline.
"""
from __future__ import annotations

import os
import urllib.request
from pathlib import Path

from PIL import ImageFont

CACHE = Path(os.environ.get("PHOTOMESH_FONT_CACHE", Path.home() / ".cache" / "photomesh-ml" / "fonts"))
BASE = "https://raw.githubusercontent.com/google/fonts/main/"

HANDWRITING = {
    "Caveat.ttf": "ofl/caveat/Caveat%5Bwght%5D.ttf",
    "PatrickHand-Regular.ttf": "ofl/patrickhand/PatrickHand-Regular.ttf",
    "Kalam-Regular.ttf": "ofl/kalam/Kalam-Regular.ttf",
    "IndieFlower-Regular.ttf": "ofl/indieflower/IndieFlower-Regular.ttf",
    "ShadowsIntoLight.ttf": "ofl/shadowsintolight/ShadowsIntoLight.ttf",
    "GochiHand-Regular.ttf": "ofl/gochihand/GochiHand-Regular.ttf",
    "ArchitectsDaughter-Regular.ttf": "ofl/architectsdaughter/ArchitectsDaughter-Regular.ttf",
    "Handlee-Regular.ttf": "ofl/handlee/Handlee-Regular.ttf",
    "ReenieBeanie.ttf": "ofl/reeniebeanie/ReenieBeanie.ttf",
    "NothingYouCouldDo.ttf": "ofl/nothingyoucoulddo/NothingYouCouldDo.ttf",
}
PRINT = {
    "Inter.ttf": "ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf",
    "Roboto.ttf": "ofl/roboto/Roboto%5Bwdth%2Cwght%5D.ttf",
}
FALLBACKS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
]


def ensure_fonts(download: bool = True) -> dict[str, list[Path]]:
    """Returns {"hand": [...], "print": [...]} with whatever is available locally."""
    CACHE.mkdir(parents=True, exist_ok=True)
    out: dict[str, list[Path]] = {"hand": [], "print": []}
    for group, table in (("hand", HANDWRITING), ("print", PRINT)):
        for name, rel in table.items():
            path = CACHE / name
            if not path.exists() and download:
                try:
                    urllib.request.urlretrieve(BASE + rel, path)
                except Exception:
                    continue
            if path.exists() and path.stat().st_size > 1000:
                out[group].append(path)
    fallbacks = [Path(p) for p in FALLBACKS if Path(p).exists()]
    if not out["print"]:
        out["print"] = fallbacks
    if not out["hand"]:
        out["hand"] = fallbacks
    return out


_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}


def load_font(path: Path | str, size: int) -> ImageFont.FreeTypeFont:
    key = (str(path), int(size))
    if key not in _cache:
        _cache[key] = ImageFont.truetype(str(path), int(size))
    return _cache[key]
