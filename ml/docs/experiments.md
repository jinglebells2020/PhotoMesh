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

Every photo is opened in the frame its labels were drawn in (`Record.orientation`, detected per
photo by `data/orientation.py`); in CGHD that is the EXIF-rotated frame for 293 photos and the
stored frame for the rest. Numbers from before this fix (none are published here) scored those
293 photos against sideways boxes.

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

Produced by `scripts/evaluate_run.sh`; the JSON/markdown behind each table is in `docs/results/`.

### CPU run, tiny backbone, synthetic only (90 held-out test images, ground-truth text unless noted)

| setting | correct [95% CI] | topology | structure | answers | kind acc | mAP@0.5 | coverage@95% prec. | Brier |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tracer, GT text | 0.689 [0.5889, 0.7778] | 0.689 | 0.689 | 0.700 | 0.968 | 0.6715 | 0.067 | 0.2488 |
| + three-scale majority (TTA) | 0.711 [0.6222, 0.8] | 0.700 | 0.711 | 0.700 | 0.980 | 0.6811 | 0.056 | 0.2581 |
| tracer, no text | 0.000 [0.0, 0.0] | 0.000 | 0.656 | 0.000 | 0.951 | 0.6715 |  | 0.0231 |
| ablation: no unit-based kinds | 0.656 [0.5556, 0.7556] | 0.656 | 0.656 | 0.700 | 0.951 | 0.6715 | 0.078 | 0.2409 |
| ablation: box removal, closing 1, wire 0.5 | 0.689 [0.5889, 0.7778] | 0.689 | 0.689 | 0.700 | 0.968 | 0.6715 | 0.067 | 0.2488 |
| calibrated confidence (fit on val) | 0.689 [0.5889, 0.7778] | 0.689 | 0.689 | 0.700 | 0.968 | 0.6715 | 0.189 | 0.1563 |

"structure" is topology with every value set to 1, so the "no text" row shows what the tracer
gets right without any OCR (0.656) even though nothing solves without values. Three-scale majority
voting adds about two points; the unit-based kind rule adds three; the assembler's body-removal
and closing changes make no difference once the wire head is trained (they mattered for the
epoch-4 model, 0.067 → 0.083). Calibration leaves accuracy unchanged by construction and lowers the
Brier score from 0.249 to 0.156, which triples the coverage of the escalation gate at 95 %
precision (0.067 → 0.189, fit on 90 validation images).

Breakdowns (GT text): style hand: 0.65 (n=48) · print: 0.74 (n=42); capture flat: 0.68 (n=22) · photo: 0.69 (n=68); size 1-3 elements: 0.92 (n=12) · 4-5 elements: 0.65 (n=31) · 6+ elements: 0.66 (n=47).
Small circuits are nearly solved; the loss on larger ones comes from a single wrong or missed
symbol per drawing, which the "all elements must be right" definition of correct punishes fully.

Remaining confusions of the final model (class-agnostic box matching, IoU ≥ 0.5):

| truth | n | read as |
| --- | --- | --- |
| capacitor | 4 | battery 4 |
| crossover | 7 | (missed) 1 |
| current_source | 15 | voltage_source 5 |
| ground | 48 | (missed) 1 |
| inductor | 25 | resistor 12 |
| resistor | 332 | inductor 1 |
| switch_closed | 15 | (missed) 12 |
| switch_open | 3 | (missed) 2, resistor 1 |
| text | 937 | (missed) 66 |
| voltage_source | 75 | current_source 2 |

Reliability of the calibrated confidence on the test images:

| confidence bin | n | mean confidence | accuracy |
| --- | --- | --- | --- |
| 0.0-0.2 | 8 | 0.052 | 0.0 |
| 0.6-0.8 | 57 | 0.713 | 0.702 |
| 0.8-1.0 | 25 | 0.868 | 0.88 |

Per-image latency on this CPU: 25 ms for the network plus the assembler at 320 px.

Training curve (EMA weights on 180 held-out images for mAP/IoU; end-to-end on 40 of them):

| epoch | loss | heat | wire loss | mAP@0.5 | P | R | wire IoU | e2e correct | e2e topology | s/epoch |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 9.742 | 3.733 | 0.720 | 0.032 | 0.330 | 0.087 | 0.591 | 0.000 | 0.000 | 108 |
| 1 | 3.002 | 1.213 | 0.225 | 0.225 | 0.505 | 0.523 | 0.782 | 0.000 | 0.000 | 33 |
| 2 | 2.127 | 0.874 | 0.154 | 0.311 | 0.574 | 0.644 | 0.839 | 0.125 | 0.150 | 78 |
| 3 | 1.630 | 0.706 | 0.113 | 0.365 | 0.691 | 0.735 | 0.865 | 0.175 | 0.175 | 84 |
| 4 | 1.415 | 0.602 | 0.110 | 0.391 | 0.741 | 0.763 | 0.881 | 0.250 | 0.275 | 34 |
| 5 | 1.238 | 0.531 | 0.094 | 0.460 | 0.779 | 0.809 | 0.886 | 0.300 | 0.300 | 82 |
| 6 | 1.142 | 0.496 | 0.087 | 0.452 | 0.742 | 0.787 | 0.892 | 0.225 | 0.225 | 35 |
| 7 | 1.058 | 0.465 | 0.082 | 0.496 | 0.814 | 0.832 | 0.894 | 0.275 | 0.300 | 33 |
| 8 | 0.995 | 0.434 | 0.076 | 0.482 | 0.789 | 0.818 | 0.894 | 0.275 | 0.275 | 115 |
| 9 | 0.950 | 0.410 | 0.075 | 0.532 | 0.851 | 0.852 | 0.901 | 0.350 | 0.350 | 33 |
| 10 | 0.889 | 0.390 | 0.071 | 0.538 | 0.833 | 0.849 | 0.904 | 0.350 | 0.350 | 150 |
| 11 | 0.848 | 0.371 | 0.069 | 0.548 | 0.869 | 0.869 | 0.903 | 0.400 | 0.425 | 46 |
| 12 | 0.808 | 0.349 | 0.065 | 0.576 | 0.865 | 0.877 | 0.909 | 0.400 | 0.400 | 42 |
| 13 | 0.789 | 0.343 | 0.063 | 0.586 | 0.857 | 0.875 | 0.910 | 0.425 | 0.425 | 49 |
| 14 | 0.735 | 0.321 | 0.061 | 0.595 | 0.868 | 0.879 | 0.912 | 0.425 | 0.425 | 139 |
| 15 | 0.729 | 0.321 | 0.061 | 0.616 | 0.881 | 0.886 | 0.912 | 0.400 | 0.425 | 127 |
| 16 | 0.690 | 0.300 | 0.058 | 0.626 | 0.879 | 0.894 | 0.914 | 0.425 | 0.450 | 44 |
| 17 | 0.660 | 0.288 | 0.057 | 0.626 | 0.893 | 0.906 | 0.915 | 0.425 | 0.450 | 38 |
| 18 | 0.649 | 0.281 | 0.056 | 0.653 | 0.902 | 0.915 | 0.916 | 0.500 | 0.525 | 56 |
| 19 | 0.643 | 0.284 | 0.056 | 0.654 | 0.904 | 0.913 | 0.917 | 0.500 | 0.525 | 38 |
| 20 | 0.604 | 0.267 | 0.054 | 0.653 | 0.912 | 0.918 | 0.917 | 0.525 | 0.550 | 34 |
| 21 | 0.611 | 0.263 | 0.053 | 0.657 | 0.912 | 0.917 | 0.918 | 0.475 | 0.500 | 33 |
| 22 | 0.600 | 0.267 | 0.053 | 0.656 | 0.914 | 0.917 | 0.918 | 0.500 | 0.500 | 33 |
| 23 | 0.600 | 0.266 | 0.053 | 0.661 | 0.916 | 0.920 | 0.918 | 0.500 | 0.500 | 33 |
