"""Reading the text on a circuit: values ("4.7kΩ", "15 mA"), names ("R1", "Vs") and questions.

Mirrors `QuantityFormatter.parseValue` in the app and the unknown kinds in `CircuitModel.swift`.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional

PREFIXES = {
    "p": 1e-12, "n": 1e-9, "u": 1e-6, "µ": 1e-6, "μ": 1e-6, "m": 1e-3,
    "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9,
}

# Unit spellings -> (unit symbol, quantity family)
UNITS = {
    "ω": ("Ω", "resistance"), "Ω": ("Ω", "resistance"), "Ω": ("Ω", "resistance"), "ohm": ("Ω", "resistance"), "ohms": ("Ω", "resistance"), "r": ("Ω", "resistance"),
    "v": ("V", "voltage"), "volt": ("V", "voltage"), "volts": ("V", "voltage"),
    "a": ("A", "current"), "amp": ("A", "current"), "amps": ("A", "current"), "ampere": ("A", "current"), "amperes": ("A", "current"),
    "f": ("F", "capacitance"), "farad": ("F", "capacitance"), "farads": ("F", "capacitance"),
    "h": ("H", "inductance"), "henry": ("H", "inductance"), "henries": ("H", "inductance"),
    "w": ("W", "power"), "watt": ("W", "power"), "watts": ("W", "power"),
    "hz": ("Hz", "frequency"),
}

# Which quantity family a component kind carries.
FAMILY_FOR_KIND = {
    "resistor": "resistance", "lamp": "resistance",
    "voltage_source": "voltage", "battery": "voltage",
    "current_source": "current",
    "capacitor": "capacitance", "inductor": "inductance",
}

_NUMBER = r"(?P<num>\d+(?:[.,]\d+)?|[.,]\d+)"
_VALUE_RE = re.compile(
    r"^\s*(?P<sign>[-−])?\s*" + _NUMBER +
    r"\s*(?:[×x]\s*10\s*\^?\s*(?P<exp>[-−]?\d+))?"
    r"\s*(?P<prefix>[pnuµμmkKMG])?\s*(?P<unit>[A-Za-zΩΩω]{0,7})?\s*$"
)
# "4k7", "2M2", "4R7" style (prefix used as the decimal point)
_RKM_RE = re.compile(r"^\s*(?P<a>\d+)(?P<p>[pnuµμmkKMGRr])(?P<b>\d+)\s*(?P<unit>[A-Za-zΩΩω]{0,5})?\s*$")


@dataclass
class ParsedText:
    kind: str                       # "value" | "name" | "question" | "other"
    value: Optional[float] = None   # base SI units for "value"
    unit: Optional[str] = None      # "Ω", "V", "A", "F", "H", "W" or None (bare number)
    family: Optional[str] = None    # "resistance" | "voltage" | ...
    name: Optional[str] = None      # "R1" for "name"
    text: str = ""


def _to_float(num: str) -> float:
    return float(num.replace(",", "."))


def parse_value(text: str) -> Optional[float]:
    """Number in base SI units, or None. Accepts prefixes and unit words; 'k' and 'K' both mean kilo."""
    parsed = parse_text(text)
    return parsed.value if parsed.kind == "value" else None


def parse_text(text: str) -> ParsedText:
    raw = text
    text = text.strip().replace("Ω", "Ω")
    if not text:
        return ParsedText("other", text=raw)
    # Strip a leading "R1 =" / "V1:" style name from a combined label ("R1 = 4.7k").
    name_match = re.match(r"^\s*([A-Za-z]{1,3}[_]?[0-9]{0,3}(?:[a-z]{0,2})?)\s*[=:]\s*(.+)$", text)
    if name_match and _looks_like_name(name_match.group(1)):
        inner = parse_text(name_match.group(2))
        if inner.kind == "value":
            inner.name = name_match.group(1).replace("_", "")
            inner.text = raw
            return inner

    m = _RKM_RE.match(text)
    if m and m.group("p") not in ("R", "r") or (m and m.group("p") in ("R", "r")):
        p = m.group("p")
        mult = 1.0 if p in ("R", "r") else PREFIXES[p]
        val = _to_float(m.group("a") + "." + m.group("b")) * mult
        unit_key = (m.group("unit") or "").lower()
        unit, family = UNITS.get(unit_key, (None, None))
        if p in ("R", "r") and unit is None:
            unit, family = "Ω", "resistance"
        return ParsedText("value", value=val, unit=unit, family=family, text=raw)

    m = _VALUE_RE.match(text)
    if m:
        unit_raw = m.group("unit") or ""
        prefix = m.group("prefix")
        unit_key = unit_raw.lower()
        # "10mA": prefix m, unit A. "12m" alone: ambiguous, treat as milli with no unit.
        # A capital 'M' before a unit is mega, a lowercase 'm' is milli (already distinct keys).
        # Handle the case where the prefix was swallowed into the unit ("mA" parsed as unit "mA").
        if unit_key and unit_key not in UNITS and prefix is None and unit_raw[0] in PREFIXES and unit_raw[1:].lower() in UNITS:
            prefix, unit_raw = unit_raw[0], unit_raw[1:]
            unit_key = unit_raw.lower()
        if unit_key and unit_key not in UNITS:
            return ParsedText("other", text=raw)
        # A bare "k" or "M" with no number-looking unit: still a value.
        val = _to_float(m.group("num"))
        if m.group("exp"):
            val *= 10 ** int(m.group("exp").replace("−", "-"))
        if prefix:
            val *= PREFIXES[prefix]
        if m.group("sign"):
            val = -val
        unit, family = UNITS.get(unit_key, (None, None))
        return ParsedText("value", value=val, unit=unit, family=family, text=raw)

    if _looks_like_name(text):
        return ParsedText("name", name=text.replace("_", "").replace(" ", ""), text=raw)

    if _looks_like_question(text):
        return ParsedText("question", text=raw)
    return ParsedText("other", text=raw)


_NAME_RE = re.compile(r"^\s*(?:R|V|I|E|C|L|Lp|B|S|SW|Rs|RL|Vs|Is|Vin|Vout|VS|IS)\s*_?\s*(?:[0-9]{1,3}|[a-zA-Z])?\s*$")


def _looks_like_name(text: str) -> bool:
    t = text.strip()
    if not t or len(t) > 6:
        return False
    return bool(_NAME_RE.match(t))


_QUESTION_WORDS = ("find", "calculate", "determine", "compute", "what", "solve", "evaluate", "obtain", "?")


def _looks_like_question(text: str) -> bool:
    t = text.lower()
    return any(w in t for w in _QUESTION_WORDS) and len(t) > 6


# ---------------------------------------------------------------------------------------------
# Questions -> unknowns ({"kind": "current", "element": "R2"} ...), the app's `Unknown` shape.

_ELEMENT = r"(?P<el>(?:R|V|I|E|C|L|Lp|B|S)\s*_?\s*\{?\s*[0-9A-Za-z]{1,3}\s*\}?)"
_NODE = r"(?P<node>[a-z]|[0-9]{1,2})"

_PATTERNS = [
    ("current", re.compile(r"\b(?:current|i)\s*(?:flowing\s*)?(?:through|in|of|across|via)\s*(?:the\s*)?(?:resistor|element|source|lamp|inductor|capacitor|branch)?\s*" + _ELEMENT, re.I)),
    ("current", re.compile(r"\bI\s*_?\s*\{?\s*" + r"(?P<el>(?:R|Lp|L|E|C|V)\s*[0-9A-Za-z]{1,3})" + r"\s*\}?", re.I)),
    ("voltage", re.compile(r"\b(?:voltage|potential difference|v|drop)\s*(?:drop\s*)?(?:across|over|on|of)\s*(?:the\s*)?(?:resistor|element|source|lamp|inductor|capacitor)?\s*" + _ELEMENT, re.I)),
    ("voltage", re.compile(r"\bV\s*_?\s*\{?\s*" + r"(?P<el>(?:R|Lp|L|C|I)\s*[0-9A-Za-z]{1,3})" + r"\s*\}?", re.I)),
    ("power", re.compile(r"\bpower\s*(?:dissipated|absorbed|delivered|consumed|supplied|developed)?\s*(?:in|by|of|across|through)\s*(?:the\s*)?(?:resistor|element|source|lamp)?\s*" + _ELEMENT, re.I)),
    ("power", re.compile(r"\bP\s*_?\s*\{?\s*" + r"(?P<el>(?:R|Lp|L|C|V|I|E)\s*[0-9A-Za-z]{1,3})" + r"\s*\}?", re.I)),
]
_NODE_VOLTAGE = re.compile(r"\b(?:node\s*voltage|voltage|potential)\s*(?:at|of)\s*(?:node\s*)?" + _NODE + r"\b", re.I)
_BETWEEN = re.compile(r"\b(?:voltage\s*)?(?:between|from)\s*(?:nodes?\s*)?(?P<a>[a-z]|[0-9]{1,2})\s*(?:and|to)\s*(?:nodes?\s*)?(?P<b>[a-z]|[0-9]{1,2})\b", re.I)
_VAB = re.compile(r"\bV\s*_?\s*\{?\s*(?P<a>[a-z])\s*(?P<b>[a-z])\s*\}?(?![A-Za-z0-9])")
_VNODE = re.compile(r"\bV\s*_?\s*\{?\s*(?P<node>[a-z])\s*\}?(?![A-Za-z0-9])")


def _clean_element(el: str) -> str:
    return re.sub(r"[\s_{}]", "", el)


def parse_question(text: str) -> list[dict]:
    """Best-effort extraction of what a problem statement asks for. Order follows the text."""
    if not text:
        return []
    found: list[tuple[int, dict]] = []
    seen: set[str] = set()

    def add(pos: int, unknown: dict) -> None:
        key = str(sorted(unknown.items()))
        if key not in seen:
            seen.add(key)
            found.append((pos, unknown))

    for kind, pattern in _PATTERNS:
        for m in pattern.finditer(text):
            add(m.start(), {"kind": kind, "element": _clean_element(m.group("el"))})
    for m in _BETWEEN.finditer(text):
        add(m.start(), {"kind": "voltage", "between": [m.group("a"), m.group("b")]})
    for m in _VAB.finditer(text):
        add(m.start(), {"kind": "voltage", "between": [m.group("a"), m.group("b")]})
    for m in _NODE_VOLTAGE.finditer(text):
        add(m.start(), {"kind": "voltage", "node": m.group("node")})
    for m in _VNODE.finditer(text):
        add(m.start(), {"kind": "voltage", "node": m.group("node")})
    found.sort(key=lambda t: t[0])
    return [u for _, u in found]


def format_value(value: float, unit: str, style: str = "engineering") -> str:
    """"4.7 kΩ" style text for rendering labels (mirrors the app's QuantityFormatter loosely)."""
    if value == 0:
        return f"0 {unit}".strip()
    mag = abs(value)
    for exp, prefix in ((9, "G"), (6, "M"), (3, "k"), (0, ""), (-3, "m"), (-6, "µ"), (-9, "n"), (-12, "p")):
        if mag >= 10 ** exp:
            scaled = value / 10 ** exp
            break
    else:
        scaled, prefix = value * 1e12, "p"
    text = f"{scaled:.3g}"
    if "e" in text:
        text = f"{scaled:.0f}"
    return f"{text} {prefix}{unit}".strip()
