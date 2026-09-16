# PhotoMesh ML: photo → netlist recognition, on device and in the cloud

Everything needed to train, evaluate and serve PhotoMesh's own circuit reader instead of (or in
front of) the cloud model the app calls today. Two tiers share one data pipeline, one JSON contract
(`RecognitionPrompt.swift`) and one judge (the DC solver):

| Tier | Model | Runs on | Output |
| --- | --- | --- | --- |
| On-device tracer | **CircuitNet** (`photomesh_ml/tracer`): fully-convolutional multi-task net, MobileNetV3 backbone, 5–8 MB fp16 | iPhone, Core ML, iOS 17+ | symbol boxes + polarity, wire mask, junction and terminal heatmaps → assembled into the app's JSON with the values read by Vision OCR |
| Cloud fallback / teacher | **Small VLM** (`photomesh_ml/vlm`): Qwen3-VL-2B (Apache-2.0) LoRA-fine-tuned to emit the JSON directly, served by vLLM | one L4/T4 GPU, scale-to-zero | the same JSON, plus the question text |

The design and the alternatives that were weighed (P&ID pipelines, line-segment detectors,
image-to-graph transformers, SVG models, RREV-style tracers, VLMs) are in
[`docs/approaches.md`](docs/approaches.md).

## Layout

```
photomesh_ml/
  schema.py        the app's JSON (tolerant decoding, validation, DC redraw) – twin of CircuitPayload/CircuitModel
  solver.py        modified nodal analysis; `same_solution()` is the correctness judge
  textparse.py     "4.7kΩ", "R1 = 220", "Find I through R2" → values, names, unknowns
  classes.py       tracer class list and polarity vocabulary
  synth/           lattice circuits → hand-drawn / printed renders with exact labels and masks, photo augmentation
  data/            one record format; converters for Digitize-HCD, CGHD, synthetic; splits by drafter
  tracer/          CircuitNet model, targets, losses, dataset, train, Core ML/ONNX export, assembler (maps → JSON), debug overlay
  vlm/             prompt (synced from Swift), OpenAI-compatible client, teacher distillation, dataset builder, LoRA training, inference
  eval/            metrics (component match, topology via the solver, answers) and a benchmark CLI for any endpoint
  serve/           FastAPI front (validation + escalation) speaking the app's protocol, Dockerfile, Modal scale-to-zero app
tests/             pytest suite incl. an end-to-end check: perfect maps → assembler → same solution as the generator
```

## Install

```bash
cd ml
python -m venv .venv && . .venv/bin/activate
pip install -e ".[dev]"                 # numpy, pillow, pytest: enough for synth, converters, eval
pip install -e ".[tracer,export]"       # torch, torchvision, coremltools (tracer training + export)
pip install -e ".[vlm]"                 # transformers, peft, datasets (VLM tier)
pytest -q
```

## 1. Data

**Synthetic (unlimited, exact).** Random one-to-six-window textbook DC circuits with every element
kind the app solves, drawn in a hand-drawn style (wobble, handwriting fonts, lined/grid paper,
pencil) or a printed style, then photographed (perspective, lighting, shadows, blur, JPEG). Each
sample carries the app's JSON, symbol boxes with polarity and terminal points, junctions, text boxes
with strings and a wire-ink mask.

```bash
python -m photomesh_ml.synth.generate --out data/synth --count 20000 --seed 0 --workers 8
python -m photomesh_ml.synth.preview --data data/synth --out preview.png --count 12   # eyeball labels
```

**Digitize-HCD** (1,277 scans, 17 classes, 11,936 text labels, port crops; CC BY 4.0,
[Mendeley](https://data.mendeley.com/datasets/rngcz5wtv8/2), 1.95 GB) and **CGHD** (3,173 photos,
59 classes, rotations, stroke masks; CC BY 4.0, [Zenodo](https://zenodo.org/records/14042961) or
[Hugging Face](https://huggingface.co/datasets/lowercaseonly/cghd), 4.4 GB). Unzip and convert:

```bash
python -m photomesh_ml.data.convert_cli --synthetic data/synth \
    --digitize-hcd "data/Digitize-HCD Dataset" --cghd data/cghd --out data/records
# → data/records/{train,val,test}.jsonl, held out by drafter / volunteer bucket
```

What each source supervises (everything else is masked in the loss):

| Source | symbol boxes | polarity | terminals | junctions | wire mask | text strings | netlist |
| --- | --- | --- | --- | --- | --- | --- | --- |
| synthetic | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ exact |
| Digitize-HCD full images | ✓ (17 → app classes + `other`) | axis only | – | – | – | ✓ | via teacher |
| Digitize-HCD port crops (~100k) | ✓ | ✓ for V-DC / I-DC | ✓ | – | – | – | – |
| CGHD | ✓ (59 → app classes + `other`) | ✓ from rotation | ✓ near-axis symbols | ✓ dots | ✓ from stroke maps (284 images) | ✓ | via teacher |
| app scans (opt-in) | – | – | – | – | – | – | ✓ corrected netlists |

## 2. On-device tracer (CircuitNet)

```bash
python -m photomesh_ml.tracer.train --train data/records/train.jsonl --val data/records/val.jsonl \
    --backbone mobilenet_v3_large --size 640 --epochs 40 --batch 16 --out runs/tracer
python -m photomesh_ml.tracer.export_coreml --checkpoint runs/tracer/last.pt --size 640 --out CircuitNet.mlpackage
```

Outputs at stride 4: `symbol_heat` [13 classes], `symbol_size`, `symbol_off`, `polarity` [right/up/left/down],
`wire`, `junction`, `terminal`. The Core ML contract is documented in `tracer/export_coreml.py`.
`tracer/assemble.py` turns the maps plus OCR strings into the app's JSON and is the reference for
the Swift port (steps: decode peaks → wire mask minus symbols → connected components → terminals
join components → crossovers bridge → ground names node 0 → OCR values/names/question → JSON +
confidence). On perfect maps from the generator it reproduces 100 % of topologies and 94 % of
complete answers on 100 random circuits (`tests/test_assembler_e2e.py`); the rest is label
ambiguity in dense drawings.

A 40-epoch run on 20k synthetic + both real sets takes roughly 3–4 h on one L4 (estimate). The
evaluation printed each epoch is per-class precision/recall of symbol centres at IoU 0.5 and the
wire IoU; `eval/benchmark.py` scores full netlists.

## 3. Cloud tier: distil, fine-tune, serve

```bash
export OPENROUTER_API_KEY=...
# Teacher labels for the real photos, kept only when they agree with the datasets' own boxes and
# with each other (2 samples must solve to the same currents). ~$0.01–0.02 per image.
python -m photomesh_ml.vlm.distill --records data/records/train.jsonl --out data/distill/train.jsonl \
    --model google/gemini-3.6-flash --samples 2 --workers 4

python -m photomesh_ml.vlm.build_dataset --synthetic data/synth --distilled data/distill/train.jsonl --out data/vlm
python -m photomesh_ml.vlm.train_lora --model Qwen/Qwen3-VL-2B-Instruct --train data/vlm/train.jsonl --val data/vlm/val.jsonl \
    --out runs/vlm-qwen3-2b --epochs 2 --batch 4 --grad-accum 4 --lr 1e-4 --lora-r 32 --bf16 --gradient-checkpointing --merge
python -m photomesh_ml.eval.benchmark --jsonl data/vlm/val.jsonl --limit 200 --model google/gemini-3.5-flash-lite --fast   # teacher baseline
python -m photomesh_ml.vlm.infer --model runs/vlm-qwen3-2b/merged --jsonl data/vlm/val.jsonl --limit 200 --vllm --out results/student.jsonl
python -m photomesh_ml.eval.benchmark --jsonl data/vlm/val.jsonl --predictions results/student.jsonl
```

Serving (`photomesh_ml/serve`): vLLM hosts the merged model; a small FastAPI front validates every
answer like the app does, escalates once to the cloud model when the small one fails or is unsure,
and speaks `/v1/chat/completions` so the app only needs a different endpoint URL (Settings →
Recognition → Models → Endpoint, developer builds). `Dockerfile` for your own GPU box,
`modal_app.py` for scale-to-zero.

Cost sketch (estimates, to be measured): a 2B model in fp16 on an L4 answers a 1024 px scan in
about 1–2 s and serves ~10 scans/s batched; at ~$0.70/h on demand that is well under $0.0001 per
scan when busy, and $0 idle on Modal/RunPod-style serverless (cold start ~40–60 s). A T4 works with
AWQ 4-bit weights at roughly half the speed. Compare: the current cloud path costs ~$0.002–0.009
per scan.

## 4. What "correct" means

`eval/metrics.py` scores a prediction the way the user experiences it: every element found with
its kind and value (matched by position), the same currents and voltages on every element after
solving both netlists (so polarity and connectivity errors are caught even when node names differ),
labels that appear in the drawing kept as ids, the reference node and the question's unknowns the
same, and the asked quantities equal. `summarize()` reports `correct`, `topology_ok`, `answer_ok`,
component precision/recall, kind and value accuracy.

## 5. Status

Verified in this repository (CPU only, no GPU): the whole pipeline runs end to end on small data:
unit tests, synthetic generation with previews, both converters on fixtures, tracer training steps
with the tiny backbone and Core ML + ONNX export, the assembler on ground-truth maps, LoRA
fine-tuning steps of SmolVLM-256M and its evaluation loop. Not yet done: the real training runs
(need a GPU and the two dataset downloads), the teacher labelling (needs an OpenRouter key), the
Swift port of the assembler and the Core ML integration in the app.

## Licences

Datasets: Digitize-HCD and CGHD are CC BY 4.0 (credit them in About). Fonts: SIL OFL from
google/fonts, downloaded on first use. Models: Qwen3-VL is Apache-2.0; SmolVLM is Apache-2.0;
torchvision backbones are BSD. Nothing here depends on AGPL code (Ultralytics YOLO was avoided for
that reason).
