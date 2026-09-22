# Trained models

`CircuitNet-v2.mlpackage` (6.6 MB, Core ML ML Program, 640×640 RGB input, stride-4 heads) is the
on-device tracer from the RTX 4090 run described in `docs/experiments.md` (second pass, calibrated
confidence): MobileNetV3-Large backbone, trained on 12,000 synthetic images plus Digitize-HCD and CGHD.
Symbol mAP@0.5 0.97 on synthetic test images, 0.81 on held-out CGHD test drafters.

Outputs: `symbol_heat` [13 classes], `symbol_size`, `symbol_off`, `polarity` [4], `wire`, `junction`,
`terminal`, all at 160×160; the class order is `photomesh_ml.classes.TRACER_CLASSES`. The assembler
that turns the maps into a netlist is `photomesh_ml/tracer/assemble.py` (Swift port pending, see
`docs/on-device.md`).

Not in the repository (too large): the PyTorch checkpoints (27 MB each) and the Qwen3-VL-2B LoRA
adapter (144 MB); regenerate them with `scripts/runpod_job.sh` or ask for the archive from the run.
