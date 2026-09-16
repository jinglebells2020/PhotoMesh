import json
import math

import pytest

from photomesh_ml.schema import Circuit, Component, Unknown, ValidationError, parse_json_text
from photomesh_ml.solver import SolveError, evaluate_unknown, same_solution, solve

PROMPT_EXAMPLE = """
{
  "components": [
    {"id": "R1", "type": "resistor", "value": 100, "node_a": "a", "node_b": "b", "box": [0.30, 0.20, 0.46, 0.26], "orientation": "horizontal"},
    {"id": "R2", "type": "resistor", "value": "4.7k", "node_a": "b", "node_b": 0},
    {"id": "V1", "type": "voltage_source", "value": 12, "positive_node": "a", "negative_node": "0", "box": [0.12, 0.42, 0.20, 0.56], "orientation": "vertical"},
    {"id": "I1", "type": "current_source", "value": 0.002, "from_node": "0", "to_node": "b", "box": [0.60, 0.42, 0.68, 0.56], "orientation": "vertical"}
  ],
  "ground_node": "0",
  "node_points": {"0": [0.5, 0.74], "a": [0.25, 0.22], "b": [0.62, 0.22]},
  "meshes": [["V1", "R1", "R2"]],
  "unknowns": [{"kind": "current", "element": "R2"}],
  "question": "Find the current through R2.",
  "unsupported": [],
  "confidence": 0.9,
  "notes": "short remarks"
}
"""


def divider(r1=100.0, r2=200.0, v=12.0) -> Circuit:
    return Circuit(components=[
        Component("V1", "voltage_source", v, "a", "0"),
        Component("R1", "resistor", r1, "a", "b"),
        Component("R2", "resistor", r2, "b", "0"),
    ])


def test_tolerant_parse_and_roundtrip():
    c = Circuit.from_json("```json\n" + PROMPT_EXAMPLE + "\n```")
    assert [x.id for x in c.components] == ["R1", "R2", "V1", "I1"]
    assert c.component("R2").value == 4700.0 and c.component("R2").node_b == "0"
    assert c.component("V1").node_a == "a" and c.component("I1").node_b == "b"
    assert c.unknowns == [Unknown("current", element="R2")]
    j = c.to_json()
    assert j["components"][2]["positive_node"] == "a"
    assert j["components"][3]["from_node"] == "0"
    again = Circuit.from_json(json.dumps(j))
    assert again.to_json() == j
    assert c.nodes == ["0", "a", "b"]


def test_parse_json_text_rejects_prose():
    with pytest.raises(ValidationError):
        parse_json_text("no json here")


def test_validation_errors():
    with pytest.raises(ValidationError) as e:
        Circuit(components=[Component("V1", "voltage_source", 5, "a", "a"), Component("R1", "resistor", 1, "a", "b"), Component("R2", "resistor", 1, "b", "a")]).validated()
    assert e.value.code == "shortedSource"
    with pytest.raises(ValidationError) as e:
        Circuit(components=[Component("V1", "voltage_source", 5, "a", "0"), Component("R1", "resistor", 1, "a", "b")]).validated()
    assert e.value.code == "danglingElement"
    with pytest.raises(ValidationError) as e:
        Circuit(components=[Component("R1", "resistor", 1, "a", "0"), Component("R2", "resistor", 1, "a", "0")]).validated()
    assert e.value.code == "noSource"
    with pytest.raises(ValidationError) as e:
        Circuit(components=[Component("V1", "voltage_source", 5, "a", "0"), Component("R1", "resistor", 1, "a", "0"), Component("R2", "resistor", 1, "c", "d"), Component("R3", "resistor", 1, "c", "d")]).validated()
    assert e.value.code == "disconnected"
    with pytest.raises(ValidationError) as e:
        Circuit(components=[Component("V1", "voltage_source", 5, "a", "0"), Component("R1", "resistor", None, "a", "0")]).validated()
    assert e.value.code == "missingValue"


def test_ground_fallback_to_source_negative():
    c = Circuit(components=[Component("V1", "voltage_source", 5, "x", "y"), Component("R1", "resistor", 10, "x", "y")], ground_node="0")
    v = c.validated()
    assert v.ground_node == "y"
    assert v.nodes == ["y", "x"]


def test_letter_nodes():
    c = Circuit(components=[Component("V1", "voltage_source", 5, "n2", "0"), Component("R1", "resistor", 10, "n2", "n10"), Component("R2", "resistor", 10, "n10", "0")])
    lettered = c.with_letter_nodes()
    assert lettered.nodes == ["0", "a", "b"]
    assert lettered.component("R1").node_a == "a" and lettered.component("R1").node_b == "b"


def test_divider_solution():
    sol = solve(divider())
    assert math.isclose(sol.currents["R1"], 0.04)
    assert math.isclose(sol.currents["R2"], 0.04)
    assert math.isclose(sol.currents["V1"], -0.04)  # a -> 0 through the source is against the push
    assert math.isclose(sol.node_voltages["b"], 8.0)
    assert math.isclose(sol.voltages["R1"], 4.0)
    assert math.isclose(sol.powers["V1"], -0.48)
    assert math.isclose(sum(p for p in sol.powers.values()), 0.0, abs_tol=1e-12)


def test_current_source_and_supernode():
    c = Circuit(components=[
        Component("I1", "current_source", 0.002, "0", "a"),
        Component("R1", "resistor", 1000, "a", "0"),
        Component("R2", "resistor", 1000, "a", "b"),
        Component("V1", "voltage_source", 1, "b", "0"),
    ])
    sol = solve(c)
    assert math.isclose(sol.node_voltages["b"], 1.0)
    # KCL at a: 2 mA in = Va/1000 + (Va - 1)/1000 -> Va = 1.5
    assert math.isclose(sol.node_voltages["a"], 1.5)
    assert math.isclose(sol.currents["R2"], 0.0005)


def test_dc_parts():
    c = Circuit(components=[
        Component("E1", "battery", 9, "a", "0"),
        Component("S1", "switch_closed", 0, "a", "b"),
        Component("L1", "inductor", 1e-3, "b", "c"),
        Component("Lp1", "lamp", 90, "c", "d"),
        Component("C1", "capacitor", 1e-6, "d", "0"),
        Component("R1", "resistor", 90, "d", "0"),
    ])
    sol = solve(c)
    assert math.isclose(sol.currents["Lp1"], 0.05)
    assert math.isclose(sol.currents["C1"], 0.0)
    assert math.isclose(sol.currents["S1"], 0.05)
    assert math.isclose(sol.currents["L1"], 0.05)
    assert math.isclose(sol.voltages["L1"], 0.0)
    assert math.isclose(sol.node_voltages["d"], 4.5)


def test_same_solution_ignores_node_names_but_not_polarity():
    a = divider()
    b = a.renaming_nodes(lambda n: {"a": "top", "b": "mid", "0": "gnd"}[n])
    b.ground_node = "gnd"
    assert same_solution(a, b)
    flipped = divider()
    flipped.components[0] = Component("V1", "voltage_source", 12, "0", "a")
    assert not same_solution(a, flipped)
    wrong_value = divider(r2=220)
    assert not same_solution(a, wrong_value)


def test_unknown_evaluation():
    c = divider()
    c.unknowns = [Unknown("current", element="R2"), Unknown("voltage", node="b"), Unknown("voltage", between=["a", "b"]), Unknown("power", element="R1")]
    sol = solve(c)
    values = [evaluate_unknown(c, sol, u) for u in c.unknowns]
    assert [round(v, 6) for v in values] == [0.04, 8.0, 4.0, 0.16]


def test_singular_circuit_is_reported():
    c = Circuit(components=[Component("V1", "voltage_source", 5, "a", "0"), Component("V2", "voltage_source", 3, "a", "0"), Component("R1", "resistor", 1, "a", "0")])
    with pytest.raises(SolveError):
        solve(c)
