import math

import pytest

from photomesh_ml.textparse import parse_question, parse_text, parse_value, format_value


@pytest.mark.parametrize("text, expected", [
    ("4.7k", 4700.0), ("4.7 kΩ", 4700.0), ("4k7", 4700.0), ("2M2", 2.2e6), ("4R7", 4.7),
    ("12V", 12.0), ("12 V", 12.0), ("1.5V", 1.5), ("15mA", 0.015), ("15 mA", 0.015), ("2 A", 2.0),
    ("100µF", 100e-6), ("100uF", 100e-6), ("10 μF", 10e-6), ("22nF", 22e-9), ("3mH", 3e-3), ("5μH", 5e-6),
    ("220", 220.0), ("2,2k", 2200.0), ("1e3", None), ("R1", None), ("Find I", None), ("1MΩ", 1e6), ("10 ohms", 10.0),
    ("100 Ω", 100.0), ("2kHz", 2000.0), ("-5V", -5.0),
])
def test_parse_value(text, expected):
    got = parse_value(text)
    if expected is None:
        assert got is None
    else:
        assert got is not None and math.isclose(got, expected, rel_tol=1e-9)


def test_parse_text_families():
    assert parse_text("4.7kΩ").family == "resistance"
    assert parse_text("9 V").family == "voltage"
    assert parse_text("20 mA").family == "current"
    assert parse_text("47 µF").family == "capacitance"
    assert parse_text("R12").kind == "name" and parse_text("R12").name == "R12"
    assert parse_text("Vs").kind == "name"
    assert parse_text("Find the current through R2.").kind == "question"
    p = parse_text("R1 = 4.7k")
    assert p.kind == "value" and p.name == "R1" and p.value == 4700.0


@pytest.mark.parametrize("text, expected", [
    ("Find the current through R2.", [{"kind": "current", "element": "R2"}]),
    ("Determine the voltage across R3 and the power dissipated in R1", [{"kind": "voltage", "element": "R3"}, {"kind": "power", "element": "R1"}]),
    ("Calculate I_R2 and V_ab", [{"kind": "current", "element": "R2"}, {"kind": "voltage", "between": ["a", "b"]}]),
    ("What is the voltage at node b?", [{"kind": "voltage", "node": "b"}]),
    ("Find the voltage between a and c.", [{"kind": "voltage", "between": ["a", "c"]}]),
    ("Find V_{R1}", [{"kind": "voltage", "element": "R1"}]),
    ("Find I through the lamp Lp1", [{"kind": "current", "element": "Lp1"}]),
    ("", []),
])
def test_parse_question(text, expected):
    assert parse_question(text) == expected


def test_format_value():
    assert format_value(4700, "Ω") == "4.7 kΩ"
    assert format_value(0.015, "A") == "15 mA"
    assert format_value(12, "V") == "12 V"
    assert format_value(100e-6, "F") == "100 µF"
