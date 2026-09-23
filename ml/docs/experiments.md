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
| unit-based kind correction, guarded by distance and detector certainty (the default until the GPU run) | 0.522 | 0.511 | 0.953 |

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

<!-- gpu-run:start -->
### GPU run with real data: CircuitNet, MobileNetV3-Large at 640 px (one RTX 4090, 22 Sep 2026)

The target configuration from the recipe, run unattended by `scripts/runpod_job.sh` on a rented RTX 4090
(secure cloud, $0.74/h). Result files: `docs/results/runpod-4090-real/`.

| item | value |
| --- | --- |
| data | 12,000 synthetic images (9,600 / 1,200 / 1,200 by seed bucket); Digitize-HCD 1,277 photos (1,085 / 128 / 64 by image-id bucket) and 69,759 port crops pasted into at most 3,000 mosaics per epoch; CGHD 3,293 photos (2,909 / 288 / 96, whole drafters held out). Photos downsized to 1,600 px; every photo opened in its label frame |
| model | CircuitNet, MobileNetV3-Large backbone (ImageNet init), 640 px input, stride-4 heads, 6.6 MB as a Core ML package |
| training | 10 epochs of 1,037 steps, batch 16, AdamW 1e-3 cosine with warm-up, EMA, source weights synthetic 1 / CGHD 3 / Digitize-HCD 2 / mosaics 1, rare-class balancing 1.0; 16,594 items per epoch, 141–152 s per epoch, 25 min in total |
| evaluation | end-to-end on the first 300 held-out synthetic test images with ground-truth text (only synthetic and distilled records carry a netlist); real photos scored on boxes with `tracer.detect_eval`; confidence calibrated on val |

Training curve (validation is the mixed val split: synthetic, Digitize-HCD, CGHD; end-to-end on 60 synthetic val images):

| epoch | loss | heat | wire loss | mAP@0.5 | P | R | wire IoU | e2e correct | e2e topology | s/epoch |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 3.592 | 1.344 | 0.174 | 0.712 | 0.815 | 0.830 | 0.902 | 0.617 | 0.700 | 152 |
| 1 | 1.991 | 0.591 | 0.080 | 0.789 | 0.835 | 0.869 | 0.908 | 0.650 | 0.717 | 152 |
| 2 | 1.789 | 0.511 | 0.072 | 0.825 | 0.869 | 0.882 | 0.912 | 0.717 | 0.783 | 148 |
| 3 | 1.660 | 0.459 | 0.066 | 0.852 | 0.879 | 0.890 | 0.916 | 0.733 | 0.817 | 145 |
| 4 | 1.549 | 0.415 | 0.063 | 0.855 | 0.874 | 0.895 | 0.916 | 0.783 | 0.833 | 147 |
| 5 | 1.494 | 0.388 | 0.060 | 0.869 | 0.894 | 0.895 | 0.915 | 0.767 | 0.817 | 143 |
| 6 | 1.407 | 0.351 | 0.058 | 0.871 | 0.889 | 0.901 | 0.918 | 0.750 | 0.833 | 143 |
| 7 | 1.355 | 0.332 | 0.055 | 0.881 | 0.902 | 0.901 | 0.920 | 0.783 | 0.833 | 142 |
| 8 | 1.321 | 0.318 | 0.054 | 0.884 | 0.908 | 0.901 | 0.921 | 0.783 | 0.833 | 141 |
| 9 | 1.304 | 0.311 | 0.054 | 0.883 | 0.910 | 0.901 | 0.921 | 0.783 | 0.833 | 142 |

End-to-end on the synthetic test set (300 images, ground-truth text unless noted):

| setting | correct [95% CI] | topology | structure | answers | kind acc | mAP@0.5 | coverage@95% prec. | Brier |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tracer, GT text | 0.837 [0.7933, 0.8767] | 0.873 | 0.880 | 0.860 | 0.990 | 0.9465 | 0.077 | 0.1694 |
| + three-scale majority (TTA) | 0.843 [0.8, 0.8833] | 0.877 | 0.883 | 0.867 | 0.991 | 0.9577 | 0.17 | 0.1645 |
| tracer, no text | 0.000 [0.0, 0.0] | 0.000 | 0.917 | 0.000 | 0.998 | 0.9465 |  | 0.0465 |
| ablation: no unit-based kinds | 0.880 [0.8433, 0.9167] | 0.910 | 0.917 | 0.897 | 0.998 | 0.9465 | 0.207 | 0.1644 |
| ablation: box removal, closing 1, wire 0.5 | 0.833 [0.79, 0.8733] | 0.870 | 0.877 | 0.857 | 0.990 | 0.9465 | 0.077 | 0.1696 |
| calibrated confidence (fit on val) | 0.837 [0.7933, 0.8767] | 0.873 | 0.880 | 0.860 | 0.990 | 0.9465 | 0.147 | 0.1154 |
| unit-based kinds gated on detector uncertainty | 0.850 [0.81, 0.8867] | 0.887 | 0.893 | 0.873 | 0.993 | 0.9466 | 0.147 | 0.1132 |

Breakdown of the default setting: 89.4 % correct with 1–3 elements (n=66), 85.6 % with 4–5 (n=118), 78.4 % with 6 or more (n=116); hand-drawn 83.0 % against printed 84.7 %; photographed 83.6 % against flat 84.0 %. Component recall and precision are 1.00 / 1.00, value accuracy 0.996, ids 0.993, reference node 0.880. Mean latency 47 ms per image on the GPU host including the assembler.

What still fails on synthetic data: 104 missed text labels, 7 missed switch_closed labels, 2 missed crossover labels (text boxes overlapping symbols, the closed switch's tiny contact), plus a couple of capacitor/battery swaps. Calibration: Brier 0.1694 raw, 0.1154 after fitting on val; the gate that keeps 95 % precision accepts 7.7 % of images raw, 14.7 % calibrated, 17.0 % with three-scale voting.

**The unit-based kind rule reversed sign.** On the CPU model it added three points; on this model turning it off raises correct readings from 0.837 to 0.880 and kind accuracy from 0.990 to 0.998. With a strong detector the flips came from values attached to the wrong neighbour, not from wrong kinds. Gating the rule on detector uncertainty (class probability below 0.9, label within three cells) recovers part of the loss (0.850 correct, kind accuracy 0.993, row above), but off is still best, so the rule is now off by default and kept as an option (`--unit-kinds`) for weaker detectors.

Real photos, held-out drafters and volunteers, boxes only (`tracer.detect_eval`, IoU 0.5, image-level bootstrap, classes the source cannot tell apart merged):

| split | source | images | boxes | mAP@0.5 [95 % CI] | polarity acc. (n) | weakest classes (AP, n) |
| --- | --- | --- | --- | --- | --- | --- |
| test | cghd | 96 | 1740 | 0.728 [0.704, 0.755] | 0.982 (111) | switch_closed|switch_open (0.00, 16), crossover (0.53, 124), ground (0.69, 88) |
| test | digitize_hcd | 64 | 1409 | 0.985 [0.973, 0.995] | n/a | current_source (0.95, 38), capacitor (0.98, 103), inductor (0.98, 105) |
| test + TTA | cghd | 96 | 1740 | 0.729 [0.694, 0.761] | 1.0 (109) | switch_closed|switch_open (0.00, 16), crossover (0.60, 124), ground (0.71, 88) |
| test + TTA | digitize_hcd | 64 | 1409 | 0.984 [0.972, 0.992] | n/a | current_source (0.95, 38), inductor (0.97, 105), capacitor (0.98, 103) |
| val | cghd | 288 | 13709 | 0.542 [0.510, 0.578] | 0.9691 (259) | switch_closed|switch_open (0.00, 52), lamp (0.19, 32), battery (0.38, 128) |
| val | digitize_hcd | 128 | 3125 | 0.978 [0.969, 0.988] | n/a | current_source (0.93, 68), capacitor (0.98, 190), resistor (0.98, 346) |

Reading the real-photo numbers: Digitize-HCD is close to solved for boxes (0.98), but its split is by image id, so the same volunteers' styles appear in train and test; treat it as in-distribution. CGHD holds out whole drafters and is the honest number: 0.73 on the test drafters and 0.54 on the val drafters, who draw far denser pages (48 boxes per photo against 18); text AP drops from 0.97 to 0.65 there and dominates the count. Polarity on the sources and batteries whose rotation is annotated is 0.97–0.98. Switches score zero on real photos in this run: CGHD has one `switch` label, the converter stored it as switch_open with both candidates, and the target builder masked both channels, so the model only ever saw synthetic switches. Batteries (0.38) and lamps (0.19) on the val drafters are the other weak classes.

#### Second pass: candidate-channel positives (three more epochs from the weights above)

The target builder now puts the Gaussian on every candidate channel, so a real switch is a positive for both switch classes and synthetic data teaches the open/closed split. Three epochs at 5e-4 from the checkpoint above (`--init`), everything else unchanged.

| setting | correct [95% CI] | topology | structure | answers | kind acc | mAP@0.5 | coverage@95% prec. | Brier |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tracer v2, GT text | 0.887 [0.85, 0.92] | 0.920 | 0.927 | 0.900 | 0.999 | 0.9665 | 0.133 | 0.1629 |
| + three-scale majority (TTA) | 0.883 [0.8433, 0.9167] | 0.923 | 0.930 | 0.903 | 1.000 | 0.9801 | 0.143 | 0.1665 |
| tracer v2, no text | 0.000 [0.0, 0.0] | 0.000 | 0.927 | 0.000 | 0.999 | 0.9665 |  | 0.047 |
| ablation: unit-based kinds on (gated on detector uncertainty) | 0.850 [0.8067, 0.8867] | 0.887 | 0.893 | 0.867 | 0.992 | 0.9665 | 0.067 | 0.166 |
| calibrated confidence (fit on val) | 0.887 [0.85, 0.92] | 0.920 | 0.927 | 0.900 | 0.999 | 0.9665 | 0.07 | 0.1002 |

| split | source | images | boxes | mAP@0.5 [95 % CI] | polarity acc. (n) | weakest classes (AP, n) |
| --- | --- | --- | --- | --- | --- | --- |
| test | cghd | 96 | 1740 | 0.807 [0.764, 0.849] | 0.9913 (115) | crossover (0.53, 124), switch_closed|switch_open (0.69, 16), inductor (0.69, 24) |
| test | digitize_hcd | 64 | 1409 | 0.989 [0.983, 0.995] | n/a | capacitor (0.97, 103), crossover (0.98, 69), other (0.98, 244) |
| test + TTA | cghd | 96 | 1740 | 0.792 [0.755, 0.828] | 1.0 (105) | switch_closed|switch_open (0.56, 16), crossover (0.57, 124), ground (0.67, 88) |
| test + TTA | digitize_hcd | 64 | 1409 | 0.985 [0.975, 0.993] | n/a | crossover (0.97, 69), inductor (0.97, 105), current_source (0.97, 38) |
| val | cghd | 288 | 13709 | 0.589 [0.553, 0.626] | 0.9468 (263) | lamp (0.21, 32), switch_closed|switch_open (0.42, 52), battery (0.43, 128) |
| val | digitize_hcd | 128 | 3125 | 0.982 [0.973, 0.990] | n/a | current_source (0.93, 68), capacitor (0.98, 190), resistor (0.98, 346) |

Switch AP on CGHD goes from 0.00 to 0.69 on the test drafters and 0.42 on the val drafters; CGHD mAP 0.728 → 0.807 (test), 0.542 → 0.589 (val), with the bootstrap intervals no longer overlapping on test; synthetic end-to-end 0.880 → 0.887 (both with the unit rule off), symbol mAP 0.9465 → 0.9665. Three extra epochs cost 8 minutes of GPU time. The calibrated gate is more conservative on this model (7.0 % coverage at 95 % precision, Brier 0.1002): the confidence features were fit on val where the v2 model is already near its ceiling, so the logistic fit has little signal to separate errors; refitting on real scans is the planned fix.

#### Cloud tier: Qwen3-VL-2B LoRA on the same pod

Teacher labelling (`vlm.distill`, google/gemini-3.6-flash, one sample, solver-checked): 85 real photos accepted, 722 rejected — 382 requests refused (HTTP 402, no credit), 294 invalid netlists (unsupported elements, missing values), 26 boxes disagree with the annotation, 20 unsolvable. The rejections are mostly honest: Digitize-HCD and CGHD are full of op-amp, transistor and AC circuits that the app's DC scope refuses, and the OpenRouter account ran out of credit part-way (HTTP 402), which also skipped the teacher benchmark.

Student: Qwen3-VL-2B-Instruct with LoRA r=32 on 4,930 training samples (5,000 synthetic minus the val share, plus the accepted real photos), one epoch, batch 2 × accumulation 8, bf16, gradient checkpointing, 802,816 max pixels; the batch-4 setting from the recipe ran out of memory on 24 GB.

| student on the held-out VLM val set | n | valid JSON | correct [95% CI] | topology | answers | comp. recall / precision | kind acc | value acc | reference node | unsupported_ok |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Qwen3-VL-2B + LoRA r=32, greedy | 120 | 0.75 | 0.283 [0.2083, 0.3667] | 0.267 | 0.375 | 0.96 / 0.99 | 0.992 | 0.935 | 0.48 | 0.97 |

The student sees the components (recall 0.96, kinds and values right when found) but wires them wrongly in most images: node assignment, not symbol reading, is what one epoch on 4,930 mostly synthetic samples does not teach a 2B model. The val set is 155 samples of the same mix (synthetic plus distilled), so this is not a real-photo number either. The comparison against the cloud teacher is missing for lack of OpenRouter credit, so the student cannot be called a replacement for the cloud tier yet.

Training-loop evaluation on 30 val samples agrees: correct 0.33 [0.1667, 0.5], component recall 0.96, kind accuracy 0.994, box IoU 0.85. LoRA training loss fell from 0.44 to 0.06 over the 308 optimizer steps (51 min).

<!-- gpu-run:end -->

### Real photos end to end, scored against Claude's netlists (23 Sep 2026, CPU)

The 335 accepted labels in [`labels/claude/`](../labels/claude/README.md) give the first end-to-end
numbers on real photos. The held-out file holds the 62 photos from the val/test records (46
Digitize-HCD, 16 CGHD from the test drafters); the tracer never saw their boxes. The 272 training-split
photos (273 after one label was corrected later) are reported separately: the tracer trained on their symbol boxes (not on any wiring), so that
number is in-distribution for detection and only says how far the wire tracing is from the symbols.
All runs: `tracer.evaluate`, CircuitNet v2 (calibrated), 640 px, ground-truth text, unit rule off,
one CPU core each (latency is the CPU figure, 2.5 s a photo).

| set | n | correct [95% CI] | topology | valid netlist | comp. recall / precision | kind acc | value acc | mAP@0.5 | ground node |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| held-out, all | 62 | 0.177 [0.0806, 0.2742] | 0.177 | 0.226 | 0.983 / 0.991 | 1.000 | 0.985 | 0.983 | 0.21 |
| held-out, CGHD test drafters | 16 | 0.438 | 0.438 | 0.50 | 0.93 / 0.98 | 1.00 | 0.92 | – | 0.50 |
| held-out, Digitize-HCD | 46 | 0.087 | 0.087 | 0.13 | 0.99 / 1.00 | 1.00 | 0.99 | – | 0.11 |
| training-split photos | 272 | 0.118 [0.0809, 0.1581] | 0.121 | 0.169 | 0.998 / 0.999 | 0.996 | 0.979 | 0.994 | 0.165 |

The symbols are essentially solved on these photos (recall 0.98, every kind right, values right where
the text is given) and the netlists are still wrong four times out of five. The failure is one thing:
the traced wires do not reach the terminals. 39 of the 62 held-out netlists are rejected as
`danglingElement` (a component with a terminal on no net), 6 more because the tracer kept an
`X` element it could not attach, and the predicted circuits have more nodes than the truth in 49 of
62 photos and fewer in none: nets fragment, they never merge. By circuit size: 1–3 elements 0.125
(n=8), 4–5 elements 0.364 (n=22), 6+ elements 0.062 (n=32). CGHD is the source whose stroke maps
trained the wire head (284 images) and it scores 0.44; Digitize-HCD contributed no wire supervision
at all and scores 0.09. The calibrated confidence is useless here (Brier 0.71: 59 of 62 photos are
rated above 0.8 and 19 % of those are right), which is what a gate fit on synthetic val should do
on an out-of-distribution failure and is the reason the app must not trust it on photos yet.

Assembler knobs on the same held-out photos (the wire head is unchanged; only the post-processing moves):

| setting | correct [95% CI] | topology | valid |
| --- | --- | --- | --- |
| default (wire threshold 0.4, closing radius max(W,H)/160, span body removal) | 0.177 [0.0806, 0.2742] | 0.177 | 0.226 |
| unit-based kinds on | 0.129 [0.0484, 0.2097] | 0.129 | 0.16 |
| three-scale majority (`--tta`) | 0.258 [0.1613, 0.371] | 0.258 | 0.306 |
| wire threshold 0.25 (training-split photos, 272) | 0.121 [0.0846, 0.1618] vs 0.118 default | 0.125 | 0.17 |
| box body removal (training-split photos, 272) | 0.118 [0.0809, 0.1581], identical to default | 0.121 | 0.169 |

Lowering the wire threshold changes one photo in 272 and removing the body by box changes none: the
wire probability near the terminals is not low, it is absent, so no post-processing recovers it.
Test-time augmentation is the one knob that moves the number (0.18 → 0.26, intervals overlapping),
because the three scales see the thin scan lines differently and the majority fills some gaps.

What this changes in the plan: the tracer's next training run needs wire supervision on the Digitize-HCD
style (its scans have no stroke maps; the netlists can supervise the assembler's output but not the
pixels, so the options are pseudo-masks from the netlist plus the symbol boxes, or a few hundred
stroke maps drawn for that source), and the Core ML package in the repository should be read as a
symbol detector until then. The cloud tier is scored on the same 62 photos below.

