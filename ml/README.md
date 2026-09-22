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
kind the app solves, wire crossovers (hops and plain crossings), node letters, and now and then a
symbol the app cannot solve (diode, LED, zener, AC source) so the reader learns to flag it. Drawn
in a hand-drawn style (wobble, handwriting fonts, lined/grid paper, pencil) or a printed style,
then photographed (perspective, lighting, shadows, blur, JPEG). Each sample carries the app's JSON,
symbol boxes with polarity and terminal points, junctions, text boxes with strings and a wire-ink
mask.

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
| app scans (opt-in, `data/scans.py`) | ✓ from the app's placements | axis only | – | – | – | – | ✓ corrected (gold) / accepted (silver) |

Label frames: phone photos carry an EXIF rotation, and the CGHD labellers applied it for 293 of the 3,293 photos but not for the rest, while two drafters' XML sizes are simply wrong. `data/orientation.py` works out, per photo, which frame the boxes were drawn in (stroke-mask size, then annotation size, then ink-versus-label agreement for 180° turns); the record stores that orientation and every loader opens photos through `open_record_image`, so nothing trains or scores on sideways boxes.

## 2. On-device tracer (CircuitNet)

```bash
python -m photomesh_ml.tracer.train --train data/records/train.jsonl --val data/records/val.jsonl \
    --backbone mobilenet_v3_large --size 640 --epochs 40 --batch 16 --out runs/tracer \
    --source-weights synthetic=1,cghd=3,digitize_hcd=2,mosaic=1 --e2e-records data/records/val.jsonl
python -m photomesh_ml.tracer.evaluate --checkpoint runs/tracer/last.pt --records data/records/test.jsonl --ocr gt --tta --out results/tracer_test
python -m photomesh_ml.tracer.infer --checkpoint runs/tracer/last.pt --image photo.jpg --ocr ocr.json --tta --debug overlay.png
python -m photomesh_ml.tracer.export_coreml --checkpoint runs/tracer/last.pt --size 640 --out CircuitNet.mlpackage
bash scripts/reproduce.sh      # the whole recipe with one command
```

Training keeps an EMA of the weights (warm-up so early evaluations are meaningful), samples sources
with configurable weights, applies small random rotations, and reports per-class mAP@0.5, wire IoU
and, with `--e2e-records`, the end-to-end netlist accuracy on held-out synthetic circuits after
every epoch. `tracer.infer` runs the whole on-device path (letterbox → maps → assembler → JSON);
with `--tta` it reads the photo at three scales, keeps the reading the others agree with (solver
checked) and scales the confidence by that agreement, which is what gates cloud escalation.
`tracer.evaluate` scores a labelled set with bootstrap confidence intervals, per-style breakdowns,
symbol mAP, a class confusion matrix, confidence reliability bins and the coverage the confidence
gate reaches at 95 % precision. `tracer.calibrate` fits a logistic model from assembly features
(symbol scores, attached terminals, missing values, validation, multi-scale agreement) to
"the reading was correct" and stores it in the checkpoint, so the phone compares a calibrated
probability against its escalation threshold. `tracer.report` turns a run's log into a markdown
table. The assembler also lets a read unit correct the detector's kind ("12 V" next to a symbol
the detector called a current source), guarded by label distance and detector certainty; on the
same checkpoint this raised fully-correct readings from 42 % to 57 % (`docs/experiments.md`).
`--balance-rare` over-samples images with rare kinds (switches, capacitors, current sources).

Outputs at stride 4: `symbol_heat` [13 classes], `symbol_size`, `symbol_off`, `polarity` [right/up/left/down],
`wire`, `junction`, `terminal`. The Core ML contract and the step-by-step assembler specification
for the Swift port are in [`docs/on-device.md`](docs/on-device.md).
`tracer/assemble.py` turns the maps plus OCR strings into the app's JSON and is the reference for
the Swift port (steps: decode peaks → wire mask minus symbols → connected components → terminals
join components (snapped to terminal-heat peaks) → crossovers bridge → ground names node 0 → OCR
values/names/question → JSON + confidence). On perfect maps from the generator, crossovers and
unsupported symbols included, it reproduces 96 % of topologies and 90 % of complete answers on 160
random circuits (95 % bootstrap interval 0.85–0.94, `docs/experiments.md`); the rest is label
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

Serving (`photomesh_ml/serve`): vLLM hosts the merged model with decoding constrained to the output
schema (`vlm/output_schema.json`, so the small model never returns malformed JSON); a small FastAPI
front validates every answer like the app does, escalates once to the cloud model when the small one fails or is unsure,
and speaks `/v1/chat/completions` so the app only needs a different endpoint URL (Settings →
Recognition → Models → Endpoint, developer builds). `Dockerfile` for your own GPU box,
`modal_app.py` for scale-to-zero.

Cost sketch (estimates, to be measured): a 2B model in fp16 on an L4 answers a 1024 px scan in
about 1–2 s and serves ~10 scans/s batched; at ~$0.70/h on demand that is well under $0.0001 per
scan when busy, and $0 idle on Modal/RunPod-style serverless (cold start ~40–60 s). A T4 works with
AWQ 4-bit weights at roughly half the speed. Compare: the current cloud path costs ~$0.002–0.009
per scan.

Self-training loop (rejection-sampling fine-tuning): point `vlm.distill --endpoint` at the student's
own vLLM server with `--samples 2`; only answers that validate, agree with the datasets' boxes and
solve identically twice are kept, then rebuild the dataset and fine-tune again.

### Running the whole recipe on a RunPod GPU, unattended

```bash
export RUNPOD_API_KEY=...   OPENROUTER_API_KEY=...
python scripts/runpod_control.py create --gpu "NVIDIA GeForce RTX 4090" --cloud COMMUNITY --disk 80 \
    --env OPENROUTER_API_KEY=$OPENROUTER_API_KEY --env MAX_HOURS=5 --job scripts/runpod_job.sh --code ml
python scripts/runpod_control.py log  POD_ID --token TOKEN --tail 40           # progress
python scripts/runpod_control.py download POD_ID workspace/results.tar.gz results.tar.gz --token TOKEN
python scripts/runpod_control.py terminate POD_ID; python scripts/runpod_control.py list   # nothing left running
```

`scripts/runpod_job.sh` generates the synthetic set, downloads Digitize-HCD and CGHD, converts and
downsizes, trains and evaluates the tracer (calibration + Core ML export), distils teacher labels
for real photos, fine-tunes the VLM with LoRA and benchmarks it against the teacher. It runs under
a hard time cap, packs `results.tar.gz`, waits a grace window for the download and then terminates
its own pod, so a forgotten pod cannot keep billing. The controller talks to the pod only over
HTTPS (RunPod's API and the pod's Jupyter contents API), so it works from anywhere.

## 4. What "correct" means

`eval/metrics.py` scores a prediction the way the user experiences it: every element found with
its kind and value (matched by position), the same currents and voltages on every element after
solving both netlists (so polarity and connectivity errors are caught even when node names differ),
labels that appear in the drawing kept as ids, the reference node and the question's unknowns the
same, and the asked quantities equal. `summarize()` reports `correct`, `topology_ok`, `answer_ok`,
component precision/recall, kind and value accuracy, with bootstrap 95 % intervals and per-group
breakdowns; `eval/detection.py` adds per-class AP@0.5. The full protocol, baselines and result
tables live in [`docs/experiments.md`](docs/experiments.md).

## 5. Status

Done and measured (details and every table: [`docs/experiments.md`](docs/experiments.md), result files in
`docs/results/`):

- **CircuitNet on a GPU with real data** (MobileNetV3-Large, 640 px, 10 epochs on 12,000 synthetic images
  plus Digitize-HCD and CGHD, 25 min on one RTX 4090). On 300 held-out synthetic test images with
  ground-truth text it reads 84 % of circuits fully correctly (95 % CI 79–88; 88 % with the unit-based
  kind rule off), symbol mAP@0.5 0.95, 47 ms per image on the GPU host. On real photos from held-out
  CGHD drafters symbol mAP@0.5 is 0.73 (test) and 0.54 (val, much denser pages), polarity 0.97–1.00;
  Digitize-HCD 0.98 (its split is by image id, so in-distribution). Exported to a 6.6 MB Core ML package.
- **Qwen3-VL-2B LoRA** fine-tuned on the same pod on 5,000 synthetic samples plus the 85 real photos
  the teacher labelled before the OpenRouter account ran out of credit; student numbers in
  `docs/experiments.md`.
- Unit tests (78), the synthetic generator with previews, both converters with per-photo label-frame
  detection, the assembler on ground-truth maps (90 % fully correct, 96 % topology on 160 circuits),
  Core ML + ONNX export, the unattended RunPod recipe.

Not yet done: the Swift port of the assembler ([`docs/on-device.md`](docs/on-device.md)) and the
Core ML integration in the app; end-to-end numbers on real photos (they need real netlists: more
teacher labelling once the OpenRouter account has credit, or corrected scans from the app); the
teacher-versus-student benchmark (same reason); switches on real drawings (see the second pass in
the experiments doc); the app-scan converter on real exports.

## Licences

Datasets: Digitize-HCD and CGHD are CC BY 4.0 (credit them in About). Fonts: SIL OFL from
google/fonts, downloaded on first use. Models: Qwen3-VL is Apache-2.0; SmolVLM is Apache-2.0;
torchvision backbones are BSD. Nothing here depends on AGPL code (Ultralytics YOLO was avoided for
that reason).
