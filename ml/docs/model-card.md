# Model card: PhotoMesh CircuitNet (on-device tracer) and the PhotoMesh VLM (cloud tier)

## Intended use
Read a photo of a DC circuit drawn by hand or printed in a textbook and produce the netlist the
PhotoMesh app solves: elements (resistor, voltage/current source, battery, capacitor, inductor,
lamp, switch), values, node connectivity, source polarity, the reference node and the question.
CircuitNet runs on the phone and answers most clean cases; the VLM tier runs on a small GPU and
takes the escalations. Neither model is meant for AC analysis, dependent sources, transistors or
integrated circuits; those are reported as unsupported so the app can say so.

## Training data
- Synthetic circuits from `photomesh_ml.synth` (exact labels; hand-drawn and printed styles;
  photographed with perspective, lighting, blur and JPEG; crossovers, unsupported symbols, current
  annotations).
- Digitize-HCD (CC BY 4.0): symbol boxes, text labels, port crops with polarity.
- CGHD (CC BY 4.0): symbol boxes with rotation, junctions, stroke masks.
- App scans (opt-in, corrected netlists) once collected.
- For the VLM: teacher answers on real photos, kept only when consistent with the datasets'
  annotations and with each other.

## Evaluation
`docs/experiments.md` defines the metrics (user-facing correctness with bootstrap intervals,
solver-checked topology, answers, symbol mAP, calibrated-confidence coverage at 95 % precision)
and holds the result tables. The GPU run with real data (RTX 4090, MobileNetV3-Large at 640 px,
second pass with the switch fix): 89 % of held-out synthetic circuits fully correct with ground-truth
text (95 % CI 85–92), symbol mAP@0.5 0.97 on synthetic test images, 0.81 on held-out CGHD test
drafters, 0.59 on the denser CGHD val drafters, 0.99 on Digitize-HCD (in-distribution split).
End-to-end correctness on real photos is not measured yet: real netlists exist only for the 85
teacher-labelled photos. The cloud-tier student (Qwen3-VL-2B LoRA, one epoch) wires 28 % of held-out
val circuits correctly and is not deployed.

## Known limitations and failure modes
- Kind confusions between visually similar symbols at low resolution (current vs voltage source,
  inductor vs resistor); read units correct many of them, and higher input resolution and real data
  are the intended fixes.
- Connectivity depends on the wire mask; breaks at corners and bleed through bodies are handled
  by closing and terminal-span removal but not eliminated.
- Values depend on OCR; handwritten "k" vs "K" and "u" vs "µ" are normalised, but unreadable digits
  are unrecoverable.
- Synthetic layouts are lattice based; free-form layouts, curved wires and non-standard symbols are
  under-represented until real data is in.
- The confidence is calibrated on synthetic data unless re-fitted on real scans; escalation
  thresholds should be re-derived per data source.
- Dense hand-drawn pages (the CGHD val drafters average 48 labelled boxes per photo) halve the
  symbol mAP compared with sparser drafters; text boxes are the bulk of the loss.
- Switches were never learnt from real drawings in the first GPU run (the source's single `switch`
  label was masked out of both switch channels); the second pass supervises every candidate channel
  and lifts switch AP on CGHD from 0.00 to 0.69 (test) / 0.42 (val). Open versus closed on a real
  drawing is still decided by which channel fires harder, not by any real label.
- Digitize-HCD numbers are in-distribution: its split is by image id, so a volunteer's style can
  appear on both sides. CGHD holds out whole drafters and is the number to quote.

## Safety and privacy
Photos stay on the device unless the user opts into scan sharing or the reading is escalated to the
cloud tier; the server keeps no images by default. No personal data is used for training.

## Licences
Datasets CC BY 4.0 (credit in the app's About screen); fonts SIL OFL; backbones BSD; Qwen3-VL
Apache-2.0; SmolVLM Apache-2.0. No AGPL components.
