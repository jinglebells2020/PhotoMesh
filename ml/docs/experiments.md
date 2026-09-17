# Experiments: protocol, baselines, results

This is the protocol every number in this repository follows, so results stay comparable as the
data and the models change.

## Data splits

| Set | Source | Split rule | Truth |
| --- | --- | --- | --- |
| synth-train / synth-heldout | `photomesh_ml.synth` | seed bucket hashed to train/val/test (10 % / 10 %) | exact |
| dhcd-* | Digitize-HCD full images | volunteer bucket (image id mod 20) hashed | symbols + text; netlist via teacher |
| cghd-* | CGHD photos | drafter hashed (whole drafters held out) | symbols + rotation + junctions; netlist via teacher |
| scans-* | app exports | install id hashed | corrected netlists (gold), accepted (silver) |

`python -m photomesh_ml.data.convert_cli` writes `train/val/test.jsonl` with these rules
(`data/splits.py`, salt `photomesh`). Never tune on `test`.

## Metrics (`eval/metrics.py`, `eval/detection.py`)

- **correct**: the user would see the right circuit and the right numbers: every element found
  (position-matched), right kind and value, same currents and voltages after solving both netlists,
  drawn labels kept as ids, same reference node, same unknowns, same answers. Reported with a
  percentile-bootstrap 95 % interval (2,000 resamples).
- **topology_ok**: the solver agrees on every element (polarity and connectivity), ignoring
  question and ids.
- **answer_ok**: the asked quantities agree (what Photomath-style users check first).
- **component recall / precision, kind and value accuracy**: element level.
- **symbol mAP@0.5**: per-class average precision of the tracer's boxes (VOC all-point).
- **coverage at 95 % precision**: the share of images the confidence gate can accept while 95 % of
  accepted readings are correct. This is the number that sets how often the phone must escalate.

## Baselines to run (GPU / API needed)

| Baseline | Command | What it tells us |
| --- | --- | --- |
| Cloud teacher on synth-heldout | `eval.benchmark --model google/gemini-3.6-flash` | ceiling and teacher error modes on known truth |
| Cloud teacher on scans-test | same with `data/vlm/scans_test.jsonl` | real-photo ceiling |
| Student VLM (2B) | `vlm.infer --vllm` + `eval.benchmark --predictions` | cloud tier quality per $ |
| Tracer, GT OCR | `tracer.evaluate --ocr gt` | tracer quality independent of OCR |
| Tracer, no OCR | `tracer.evaluate --ocr none` | topology-only quality |
| Tracer + TTA | `tracer.evaluate --tta` | value of consistency-based confidence |

Ablations worth running once the GPU runs exist: synthetic-only vs synthetic + real; with and
without port-crop mosaics; with and without the terminal head in the assembler; MobileNetV3 vs
ResNet-18 at 640 vs 768 px; guided JSON decoding on vs off for the student.

## Assembler on perfect maps (this repository, CPU)

Ground-truth maps from the generator through `tracer/assemble.py`, 160 random circuits with
crossovers and unsupported symbols enabled, GT text labels:

| metric | value |
| --- | --- |
| correct | 0.90 (95 % CI 0.85–0.94) |
| topology_ok | 0.96 (95 % CI 0.93–0.99) |
| answer_ok | 0.93 |
| component recall / precision | 1.00 / 1.00 |
| unsupported_ok | 1.00 |

The misses are label ambiguity in dense drawings (a value written between two symbols) and node
letters attached to the wrong wire; both are targets for the next generator/assembler iteration.

## Tracer trained on synthetic data only (this repository, CPU)

A pipeline proof on a 4-core CPU box, not the target model. Setup:

| item | value |
| --- | --- |
| data | 900 synthetic images (`generate --count 900 --seed 100`), split by seed bucket: 720 train / 90 val / 90 test |
| model | CircuitNet, `tiny` backbone, width 48, input 320 px (about 0.9 M parameters) |
| training | 24 epochs, batch 8, AdamW lr 2e-3 cosine with warm-up, EMA 0.998 (warm-up), rotation ±4°, no port mosaics |
| evaluation | `tracer.evaluate` on the 90 test images with ground-truth text, symbol threshold 0.3, wire threshold 0.4 |
| calibration | `tracer.calibrate` on the 90 val images, reported on test |

Interim checkpoint (epoch 7 EMA weights, 90 test images) used for the assembler ablations:

| assembler setting | correct | topology | kind acc |
| --- | --- | --- | --- |
| unit-based kind correction off | 0.422 | 0.433 | 0.913 |
| unit-based kind correction, unguarded | 0.567 | 0.567 | 0.974 |
| unit-based kind correction, guarded by distance and detector certainty (default) | 0.522 | 0.511 | 0.953 |

The unguarded rule regressed the perfect-map test (a resistor label attached to a nearby voltage
source turned the source into a resistor), which is why the guarded version is the default.
The confusion matrix of the interim model explains the remaining kind errors: current sources
read as voltage sources (14/15), inductors as resistors (21/25), capacitors as batteries (4/4) and
switches missed (17/18); rare, fine-detail classes at 320 px, hence `--balance-rare` and the
rebalanced generator mix for the next runs.

Domain gap, qualitatively: the same synthetic-only model on a real CGHD photo (test fixture,
downscaled) finds text boxes and a few resistors and traces only part of the wiring. Real data in
training (Digitize-HCD, CGHD, app scans) is not optional; the converters and loss masking exist for
exactly that.

## Results

Filled in by `tracer.evaluate` (see `results/` in a run directory). Latest entries:

RESULTS_PLACEHOLDER
