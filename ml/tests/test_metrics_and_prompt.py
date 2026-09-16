import json

from photomesh_ml.eval.benchmark import score_text
from photomesh_ml.eval.metrics import score_prediction, summarize
from photomesh_ml.schema import Circuit, Component, Unknown
from photomesh_ml.vlm.prompt import SYSTEM_PROMPT, USER_PROMPT, target_text


def truth():
    c = Circuit(components=[
        Component("V1", "voltage_source", 12, "a", "0", [0.1, 0.4, 0.2, 0.6], "vertical"),
        Component("R1", "resistor", 100, "a", "b", [0.3, 0.2, 0.5, 0.3], "horizontal"),
        Component("R2", "resistor", 200, "b", "0", [0.6, 0.4, 0.7, 0.6], "vertical"),
    ], unknowns=[Unknown("current", element="R2")], question="Find the current through R2.")
    c.node_points = {"0": [0.5, 0.8], "a": [0.25, 0.2], "b": [0.55, 0.2]}
    return c


def test_correct_prediction_with_other_node_names_and_unlabelled_ids():
    pred = truth().renaming_nodes(lambda n: {"a": "n1", "b": "n2", "0": "gnd"}[n])
    pred.ground_node = "gnd"
    pred.components[2].id = "Rx"          # unlabelled element numbered differently
    pred.unknowns = [Unknown("current", element="Rx")]
    s = score_prediction(pred, truth(), labelled_ids={"V1", "R1"})
    assert s.correct and s.topology_ok and s.answer_ok and s.unknowns_ok and s.ground_ok


def test_wrong_polarity_and_value_are_caught():
    flipped = truth()
    flipped.components[0] = Component("V1", "voltage_source", 12, "0", "a", [0.1, 0.4, 0.2, 0.6], "vertical")
    s = score_prediction(flipped, truth())
    assert not s.topology_ok and not s.correct and s.n_matched == 3
    wrong = truth()
    wrong.components[1].value = 120
    s = score_prediction(wrong, truth())
    assert s.value_ok == 2 and not s.correct


def test_missing_component_and_invalid_json():
    partial = truth()
    partial.components = partial.components[:2]
    s = score_prediction(partial, truth())
    assert s.n_matched == 2 and not s.correct
    s = score_text("not json at all", truth().to_json())
    assert not s.valid and "unreadable" in (s.error or "")
    summary = summarize([s])
    assert summary["correct"] == 0.0


def test_prompt_matches_swift_and_target_shape():
    assert SYSTEM_PROMPT.startswith("You are PhotoMesh's circuit reader")
    assert '"node_points"' in SYSTEM_PROMPT and USER_PROMPT.endswith("JSON.")
    text = target_text(truth(), confidence=0.9)
    obj = json.loads(text)
    assert list(obj.keys()) == ["components", "ground_node", "node_points", "meshes", "unknowns", "question", "unsupported", "confidence", "notes"]
    assert obj["components"][0]["positive_node"] == "a"
    back = Circuit.from_json(text)
    assert score_prediction(back, truth()).correct
