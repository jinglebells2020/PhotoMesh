"""Metrics for photo -> netlist recognition.

A prediction is "right" when the app would show the user the right circuit and the right numbers:
- every element found with its kind and value (matched by position when boxes exist, else by id),
- the same electrical connectivity and polarity (checked by solving both netlists),
- labels the drawing shows are kept as ids (unlabelled elements may be numbered any way),
- the question's unknowns and the reference node agree.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from ..schema import Circuit, Component, ValidationError, comparable_value
from ..solver import SolveError, evaluate_unknown, same_solution, solve


def _iou(a: list[float], b: list[float]) -> float:
    ix0, iy0, ix1, iy1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    area = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / area if area > 0 else 0.0


def match_components(pred: Circuit, truth: Circuit, iou_threshold: float = 0.25) -> list[tuple[int, int, float]]:
    """Greedy pairs (pred_index, truth_index, iou). Uses boxes when both sides have them, ids otherwise."""
    pairs: list[tuple[float, int, int]] = []
    for i, p in enumerate(pred.components):
        for j, t in enumerate(truth.components):
            if p.box is not None and t.box is not None:
                iou = _iou(p.box, t.box)
                if iou >= iou_threshold:
                    pairs.append((iou + (0.01 if p.kind == t.kind else 0.0), i, j))
            elif p.id == t.id:
                pairs.append((1.0, i, j))
    pairs.sort(reverse=True)
    used_p: set[int] = set()
    used_t: set[int] = set()
    out: list[tuple[int, int, float]] = []
    for score, i, j in pairs:
        if i in used_p or j in used_t:
            continue
        used_p.add(i)
        used_t.add(j)
        out.append((i, j, min(score, 1.0)))
    return out


@dataclass
class Score:
    valid: bool = False            # the app would accept the prediction (validation passes)
    solvable: bool = False
    n_truth: int = 0
    n_pred: int = 0
    n_matched: int = 0
    kind_ok: int = 0
    value_ok: int = 0
    ids_ok: bool = True            # labelled elements keep their labels
    ground_ok: bool = False
    topology_ok: bool = False      # same currents/voltages on every element after relabelling
    structure_ok: bool = False     # same connectivity and polarity with all values set to 1 (independent of OCR)
    unknowns_ok: bool = False
    answer_ok: bool = False        # the asked quantities come out the same
    correct: bool = False          # everything the user sees is right
    unsupported_ok: bool = True    # both sides agree on whether the drawing holds symbols the app cannot solve
    box_iou_mean: Optional[float] = None
    error: Optional[str] = None

    def as_dict(self) -> dict:
        return self.__dict__.copy()


def score_prediction(pred: Optional[Circuit], truth: Circuit, labelled_ids: Optional[set[str]] = None, rel: float = 1e-3) -> Score:
    s = Score(n_truth=len(truth.components))
    if pred is None:
        s.error = "no prediction"
        return s
    s.n_pred = len(pred.components)
    try:
        pred.validated()
        s.valid = True
    except ValidationError as exc:
        s.error = str(exc)
    matches = match_components(pred, truth)
    s.n_matched = len(matches)
    ious = [m[2] for m in matches if pred.components[m[0]].box is not None]
    s.box_iou_mean = sum(ious) / len(ious) if ious else None
    relabel: dict[str, str] = {}
    for i, j, _ in matches:
        p, t = pred.components[i], truth.components[j]
        if p.kind == t.kind:
            s.kind_ok += 1
        if _value_close(comparable_value(p), comparable_value(t)):
            s.value_ok += 1
        relabel[p.id] = t.id
        if labelled_ids is not None and t.id in labelled_ids and p.id != t.id:
            s.ids_ok = False
    s.unsupported_ok = bool(pred.unsupported) == bool(truth.unsupported)
    if truth.unsupported:
        # The app refuses to solve either circuit; what the user sees is the list of unsupported
        # symbols and the parts that were read, so that is what must match.
        s.correct = bool(s.unsupported_ok and s.n_matched == s.n_truth == s.n_pred and s.kind_ok == s.n_truth and s.value_ok == s.n_truth and s.ids_ok)
        return s
    if s.n_matched != s.n_truth or s.n_pred != s.n_truth:
        return _finish(s)
    # Same circuit? Relabel the prediction with the truth's ids and compare solutions.
    relabelled = Circuit(components=[Component(relabel.get(c.id, c.id), c.kind, c.value, c.node_a, c.node_b, c.box, c.orientation) for c in pred.components],
                         ground_node=pred.ground_node, unknowns=list(pred.unknowns), question=pred.question)
    s.structure_ok = same_solution(_unit_values(relabelled), _unit_values(truth), rel=rel)
    try:
        sol_p, sol_t = solve(relabelled), solve(truth)
        s.solvable = True
    except (ValidationError, SolveError) as exc:
        s.error = s.error or str(exc)
        return _finish(s)
    s.topology_ok = same_solution(relabelled, truth, rel=rel)
    # Reference node: the truth's ground must map onto the prediction's ground.
    s.ground_ok = _same_node(relabelled, truth, sol_p, sol_t, truth.ground_node, rel)
    pred_unknowns = {_unknown_key(u, relabel) for u in relabelled.unknowns}
    truth_unknowns = {_unknown_key(u, {}) for u in truth.unknowns}
    s.unknowns_ok = pred_unknowns == truth_unknowns
    answers = []
    for u in truth.unknowns:
        a, b = evaluate_unknown(relabelled, sol_p, u), evaluate_unknown(truth, sol_t, u)
        answers.append(a is not None and b is not None and abs(a - b) <= max(1e-9, rel * max(abs(a), abs(b))))
    s.answer_ok = all(answers) if answers else s.topology_ok
    return _finish(s)


def _unit_values(circuit: Circuit) -> Circuit:
    """The same wiring with every readable value replaced by 1, so structure can be judged without OCR."""
    out = circuit.renaming_nodes(lambda n: n)
    for c in out.components:
        if c.kind in ("resistor", "lamp", "voltage_source", "battery", "current_source"):
            c.value = 1.0
    return out


def _finish(s: Score) -> Score:
    s.correct = bool(s.valid and s.unsupported_ok and s.n_matched == s.n_truth == s.n_pred and s.kind_ok == s.n_truth and s.value_ok == s.n_truth
                     and s.topology_ok and s.ids_ok and s.ground_ok and s.unknowns_ok and s.answer_ok)
    return s


def _same_node(a: Circuit, b: Circuit, sa, sb, node_b: str, rel: float) -> bool:
    """Does `node_b` of circuit b correspond to a's ground? Compare through element terminals."""
    for tb in b.components:
        if tb.node_a == node_b or tb.node_b == node_b:
            ta = a.component(tb.id)
            if ta is None:
                return False
            side_b = "a" if tb.node_a == node_b else "b"
            node_a = ta.node_a if side_b == "a" else ta.node_b
            return node_a == a.ground_node
    return False


def _unknown_key(u, relabel: dict[str, str]) -> tuple:
    return (u.kind, relabel.get(u.element, u.element) if u.element else None, u.node, tuple(u.between) if u.between else None)


def _value_close(x: Optional[float], y: Optional[float], rel: float = 0.01) -> bool:
    if x is None or y is None:
        return x is None and y is None
    return abs(x - y) <= rel * max(abs(x), abs(y), 1e-12)


def bootstrap_ci(flags: list[bool] | list[float], n_boot: int = 2000, seed: int = 0, level: float = 0.95) -> tuple[float, float]:
    """Percentile bootstrap interval for a mean (rates are means of 0/1 flags)."""
    import random
    values = [float(v) for v in flags]
    n = len(values)
    if n == 0:
        return (0.0, 0.0)
    rng = random.Random(seed)
    means = []
    for _ in range(n_boot):
        total = 0.0
        for _ in range(n):
            total += values[rng.randrange(n)]
        means.append(total / n)
    means.sort()
    lo = means[int((1 - level) / 2 * n_boot)]
    hi = means[min(n_boot - 1, int((1 + level) / 2 * n_boot))]
    return (lo, hi)


def summarize_by(scores: list[Score], keys: list[str]) -> dict[str, dict]:
    """Summaries per group, e.g. by drawing style; `keys[i]` labels `scores[i]`."""
    groups: dict[str, list[Score]] = {}
    for s, k in zip(scores, keys):
        groups.setdefault(str(k), []).append(s)
    return {k: summarize(v) for k, v in sorted(groups.items())}


def summarize(scores: list[Score], ci: bool = True) -> dict:
    n = len(scores)
    if n == 0:
        return {}
    matched = sum(s.n_matched for s in scores)
    truth = sum(s.n_truth for s in scores)
    pred = sum(s.n_pred for s in scores)
    out = {
        "n": n,
        "valid": sum(s.valid for s in scores) / n,
        "correct": sum(s.correct for s in scores) / n,
        "topology_ok": sum(s.topology_ok for s in scores) / n,
        "structure_ok": sum(s.structure_ok for s in scores) / n,
        "answer_ok": sum(s.answer_ok for s in scores) / n,
        "component_recall": matched / truth if truth else None,
        "component_precision": matched / pred if pred else None,
        "kind_acc": sum(s.kind_ok for s in scores) / matched if matched else None,
        "value_acc": sum(s.value_ok for s in scores) / matched if matched else None,
        "ids_ok": sum(s.ids_ok for s in scores) / n,
        "ground_ok": sum(s.ground_ok for s in scores) / n,
        "box_iou": sum(s.box_iou_mean for s in scores if s.box_iou_mean is not None) / max(1, sum(1 for s in scores if s.box_iou_mean is not None)),
        "unsupported_ok": sum(s.unsupported_ok for s in scores) / n,
    }
    if ci and n >= 5:
        out["correct_ci95"] = [round(v, 4) for v in bootstrap_ci([s.correct for s in scores])]
        out["topology_ci95"] = [round(v, 4) for v in bootstrap_ci([s.topology_ok for s in scores])]
    return out
