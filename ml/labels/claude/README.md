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

| | labelable | accepted | rejected by the checks | set aside |
|---|---|---|---|---|
| Digitize-HCD, held-out (val/test) | 62 | 46 | 12 | 4 |
| CGHD, held-out drafters | 16 | 16 | 0 | 0 |
| Digitize-HCD, training split | 369 | 273 | 17 | 79 |
| **total** | **447** | **335** | **29** | **83** |

"Set aside" photos are drawings that have no well-posed DC answer, recorded with the reason in
`skipped.txt`: a current source with no DC return path or two current sources in series (27),
an inductor or plain wire shorting a voltage source or a current source driving a short (20),
sources written as step functions such as `5(1-u(t)) A` (9), and values or symbols that cannot
be read (30: a component with no value, a scribbled polarity, a capacitor symbol labelled in
henries). One annotation error was found the other way round (`0266`: the dataset labels the
ground symbol as a capacitor; the netlist is right, the check rejects it).

`rejected.jsonl` keeps 32 rows with the reason: the 29 above plus three photos from the excluded
set that were tried anyway (a source with no written value, an AC source). 18 are "unsolvable"
drawings Claude labelled faithfully (the solver refuses them for the reasons above), 5 lack a value,
and 9 are box or class disagreements with the dataset annotation: in four of them the annotation
is the one that is off (a ground symbol labelled as a capacitor, symbols missing from the
annotation), the rest are symbol-versus-label conflicts or Claude's misreadings. `skipped.txt` has
87 lines: the 83 set-aside photos plus a few that were tried, rejected and then set aside.

## Conventions

The same as the app's prompt (`RecognitionPrompt.swift`): node `0` is the drawn ground, or the
negative terminal of the main voltage source when nothing is grounded; other nodes are `a`, `b`, …
left to right; ids follow the drawing's labels when there are any; boxes are image fractions;
current-source direction follows the arrow; a source value written negative (`-2 A`) is kept
negative. When a drawing's symbol and label disagree (an inductor symbol labelled `10 Ω`) the
label follows the drawn **symbol**, with the written number as the value, and `notes` says so;
the datasets are not consistent about this, so a few such photos fail the box-agreement check
either way. Capacitors written `MF` on these sheets are read as millifarads.

Rows are in the distillation format (`image` relative to the data root laid out as in the README:
`cghd/...`, `Digitize-HCD Dataset/...`; `target` is the circuit; `answers[0]` carries the
box-agreement numbers). `train.jsonl` (273 photos from the training records) drops straight into

    python -m photomesh_ml.vlm.build_dataset --synthetic data/synth --distilled labels/claude/train.jsonl --data-root data --out data/vlm

`heldout.jsonl` (62 photos from the val/test records: the CGHD test drafters and the Digitize-HCD
val/test image ids, see `docs/experiments.md`) is the set models are scored on end to end. Keep it
out of every training set.
