# Real-photo netlists labelled by Claude

Circuit netlists (the app's JSON) for photos from Digitize-HCD and CGHD, written by Claude
(`claude-fable-5-1`) looking at each photo directly, then filtered by the same checks
`vlm.distill` applies to a teacher model:

1. the JSON parses and passes `Circuit.validated()` (ids, node names, source values present, ...);
2. the DC solver (`solver.solvable`) finds a unique solution;
3. the component boxes agree with the dataset's own symbol annotation: recall, precision and
   class accuracy all ≥ 0.9 at IoU ≥ 0.3 (`vlm.distill.box_agreement`), so a label that
   invents, drops or mis-types a component is rejected even when it solves.

The queue was built with `scripts/label_queue.py prepare` from `data/records/{train,val,test}.jsonl`:
in-scope photos only (no symbol outside the app's classes, at most 12 components), held-out
(val/test) photos first. Photos whose source has no written value were left out up front (91 of 538).

| | queued | labelled | accepted | rejected by the checks | set aside |
|---|---|---|---|---|---|
| Digitize-HCD, held-out (val/test) | 62 | 62 | 46 | 12 | 4 |
| CGHD, held-out drafters | 16 | 16 | 16 | 2 (later fixed: 0) | 0 |
| Digitize-HCD, training split | 369 | 369 | 272 | 19 | 78 |
| **total** | **447** | **447** | **334** | **33** | **80** |

(`skipped.txt` lists 87 entries: a few photos were tried, rejected, and then set aside.)

"Set aside" photos are drawings that have no well-posed DC answer, recorded with the reason in
`skipped.txt`: a current source with no DC return path or two current sources in series (27),
an inductor or plain wire shorting a voltage source or a current source driving a short (20),
sources written as step functions such as `5(1-u(t)) A` (9), and values or symbols that cannot
be read (30: a component with no value, a scribbled polarity, a capacitor symbol labelled in
henries). One annotation error was found the other way round (`0266`: the dataset labels the
ground symbol as a capacitor; the netlist is right, the check rejects it).

The 33 rejections in `rejected.jsonl` keep the reason: 22 are "unsolvable" drawings Claude
labelled faithfully (the solver refuses them for the same reasons as above), 5 have a source or
resistor without a value, and 6 are box disagreements — in three of them the dataset's box is the
one that is off, the rest are Claude's.

## Conventions

The same as the app's prompt (`RecognitionPrompt.swift`): node `0` is the drawn ground, or the
negative terminal of the main voltage source when nothing is grounded; other nodes are `a`, `b`, …
left to right; ids follow the drawing's labels when there are any; boxes are image fractions;
current-source direction follows the arrow; a source value written negative (`-2 A`) is kept
negative. When a drawing's symbol and label disagree (an inductor symbol labelled `10 Ω`) the
label follows the **symbol**, as the dataset annotation does, with the written number as the
value; `notes` says so. Capacitors written `MF` on these sheets are read as millifarads.

Rows are in the distillation format (`image` relative to the data root laid out as in the README:
`cghd/...`, `Digitize-HCD Dataset/...`; `target` is the circuit; `answers[0]` carries the
box-agreement numbers). `train.jsonl` (272 photos from the training records) drops straight into

    python -m photomesh_ml.vlm.build_dataset --synthetic data/synth --distilled labels/claude/train.jsonl --data-root data --out data/vlm

`heldout.jsonl` (62 photos from the val/test records: the CGHD test drafters and the Digitize-HCD
val/test image ids, see `docs/experiments.md`) is the set models are scored on end to end. Keep it
out of every training set.
