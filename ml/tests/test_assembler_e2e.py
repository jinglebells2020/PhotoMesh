"""The reference assembler must recover the generator's netlist from perfect maps."""
import numpy as np
import pytest

from photomesh_ml.eval.metrics import score_prediction, summarize
from photomesh_ml.synth.generate import make_sample
from photomesh_ml.tracer.assemble import Detection, TextItem, assemble


def _perfect_maps(sample):
    dets = [Detection(s.cls, 1.0, list(s.box), s.polarity) for s in sample.symbols]
    ocr = [TextItem(list(t.box), t.text) for t in sample.texts]
    wire_prob = sample.wire_mask.astype(np.float32) / 255.0
    return dets, ocr, wire_prob


@pytest.mark.parametrize("photo", [False, True])
def test_assembler_recovers_synthetic_netlists(photo):
    scores = []
    failures = []
    for seed in range(20):
        sample = make_sample(1000 + seed, augment_photo=photo)
        dets, ocr, wire = _perfect_maps(sample)
        result = assemble(dets, wire, (sample.width, sample.height), ocr)
        labelled = {t.component for t in sample.texts if t.role in ("name", "combined") and t.component}
        s = score_prediction(result.circuit, sample.circuit, labelled)
        scores.append(s)
        if not s.correct:
            failures.append((seed, s.as_dict(), result.circuit.dumps(), sample.circuit.dumps()))
    summary = summarize(scores)
    assert summary["correct"] >= 0.9, (summary, failures[:2])
