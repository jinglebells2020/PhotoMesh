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
and holds the result tables. Numbers reported so far come from CPU proof runs on synthetic data;
the GPU runs with real data are the ones that matter for deployment.

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

## Safety and privacy
Photos stay on the device unless the user opts into scan sharing or the reading is escalated to the
cloud tier; the server keeps no images by default. No personal data is used for training.

## Licences
Datasets CC BY 4.0 (credit in the app's About screen); fonts SIL OFL; backbones BSD; Qwen3-VL
Apache-2.0; SmolVLM Apache-2.0. No AGPL components.
