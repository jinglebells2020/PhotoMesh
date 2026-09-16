# Approaches considered for photo → netlist

PhotoMesh needs one thing from a picture: the netlist the solver eats (elements, values, which
terminals share a node, source polarity, the reference node, the question). "OCR" here is a
graph-extraction problem with three sub-problems of very different difficulty:

| Sub-problem | Difficulty | Evidence |
| --- | --- | --- |
| Symbols (where is each resistor / source / ground) | solved at nano-model size | YOLOv8 reaches 98.9 % mAP50 on Digitize-HCD ([thesis](https://repository.iutoic-dhaka.edu/items/28bfa4cc-8424-4ff9-a8bd-d75cd7ac27fa)) |
| Values and names ("4.7 kΩ", "R2") | easy on print, medium on handwriting | 11,936 handwritten labels in Digitize-HCD, character set is digits, few letters, Ω, µ |
| Connectivity (which terminals share a node, + polarity) | the hard part | the DFKI pipeline on CGHD reports no end-to-end netlist number; its 59-class detector reached 18 % mAP ([paper](https://arxiv.org/abs/2402.11093)) |

## Families of models that trace lines or extract graphs

**1. Modular pipelines from P&ID digitisation.** Piping-and-instrumentation drawings are the closest
industrial analogue: symbol detection, text detection/recognition, line tracing, then graph assembly
(Rahul et al. 2019, Paliwal et al. 2021 "Digitize-PID", Kim et al. 2022). Lines are found by
segmentation or Hough transforms and followed pixel by pixel; symbol ports are looked up from a
library. Strength: each stage is small, inspectable and trainable from partial labels. Weakness: the
assembly heuristics carry the accuracy, and hand-drawn wobble breaks straight-line assumptions.
*Taken:* the stage split, port lookup by symbol orientation, and the idea that connectivity is a
connected-components problem on "ink minus symbols".

**2. Line-segment detectors.** M-LSD (mobile), HAWP, LETR predict straight segments and junctions
end to end and run in real time on phones. They would give wires as vectors directly, but hand-drawn
wires are curved, overshoot at corners and cross; every segment must still be re-assembled into
nodes. *Not taken* as the primary tracer; the same information comes out of a wire mask plus a
junction heatmap, which tolerates curves.

**3. Image-to-graph transformers.** Relationformer (Shit et al. 2022) predicts graph nodes and
edges in one shot from an image (road networks, vessel graphs); scene-graph DETR variants do the same
for objects and relations. Elegant and exactly the output we want, but data-hungry (tens of
thousands of labelled graphs) and heavier than a CenterNet-style network; the edge head does not
transfer from road data. *Deferred*: worth revisiting once the synthetic generator plus distilled
real data give >50k graphs.

**4. Vector-output models.** DeepSVG/Im2Vec/LIVE vectorise drawings into paths; StarVector and
OmniSVG are VLMs that emit SVG code. They trace beautifully but carry no electrical semantics, so a
second model would still be needed to interpret the paths. *Not taken.*

**5. Iterative tracing agents.** RoadTracer walks a graph one step at a time; RREV (Ou et al.,
Drones 2022) predicts a vehicle's future waypoints from a single front image, with two specialist
models for "junction" versus "non-junction" scenes and a confidence score computed from the
consistency of independent predictions (IPFE), fused across frames. Sequential tracers are slow and
fragile on dense diagrams. *Taken from RREV:* the specialist split (junctions are the rare, hard
case and get their own head and heatmap), consistency-based confidence (agreement between the
on-device tracer and the cloud model, or between augmented views, gates escalation), and multi-frame
fusion (the app has a live viewfinder, so predictions can be accumulated over several frames before
the shutter).

**6. Vision-language models that emit the JSON directly.** This is what the app does today with a
cloud model, and it is the most robust to messy photos, printed textbooks and question text. Small
open VLMs (Qwen3-VL 2B/4B, SmolVLM2, Gemma 3n, FastVLM) can be fine-tuned to emit the exact JSON.
The cost is size (300 MB–3 GB) and seconds of latency, so on a phone it is a stretch and in the
cloud it needs a GPU. *Taken as the second tier and as the teacher.*

## What we build

```
                     phone (Core ML, iOS 17+)                          cloud (one small GPU, scale-to-zero)
photo ──► CircuitNet ──► symbols + polarity + wire mask ──► assembler ──► JSON ──┐
          (5–8 MB)      junctions + terminals               (Swift port of      │ low confidence /
   └────► Vision OCR ──► values, names, question ───────────► tracer/assemble)   │ validation fails
                                                                                 ▼
                                                     fine-tuned Qwen3-VL-2B (LoRA, merged) via vLLM ──► JSON
                                                     escalates once more to the big cloud model if it also fails
```

- One dataset pipeline feeds both tiers: the synthetic generator (exact netlists + pixel masks),
  Digitize-HCD and CGHD (real symbols, text, ports, rotations, stroke masks) and teacher-labelled
  real photos filtered by the datasets' own annotations.
- One judge for both tiers: the solver. A recognition is right when the app would print the same
  numbers (`photomesh_ml/eval/metrics.py`).
- The assembler is written once in Python as the reference and ported to Swift for the app.

## Why not only a VLM on the phone?

The user's requirement is "at least partially on device". A 2B VLM quantised to 4 bits is ~1.5 GB
and takes seconds on an iPhone 15 Pro; FastVLM-0.5B is the only realistic candidate and its
licence is research-only. A 6 MB CenterNet-style network answers in tens of milliseconds on any
iPhone from 2020 on, handles the common textbook cases, and hands the rest to the cloud tier.
Apple's iOS 27 Foundation Models framework now accepts images; it is a free third option for the
"question text → unknowns" step and worth a one-afternoon experiment with the same prompt.
