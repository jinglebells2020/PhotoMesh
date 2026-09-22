# PhotoMesh

Photomath, but for circuit analysis. Point the camera at a schematic or a hand‑drawn
loop and get a step‑by‑step solution.

The SwiftUI app mirrors Photomath's UI/UX one‑to‑one (red accent swapped for a deep green,
`#126B3D`). Behind it sits a real pipeline: the photo goes to a vision‑language model through
OpenRouter, comes back as a netlist, and a deterministic Swift engine solves it with **both**
nodal analysis and mesh analysis, producing textbook‑style steps for each. The user picks the
method to follow.

## What's built

| Screen | Status |
| --- | --- |
| Camera home (menu, help, adjustable viewfinder + crosshair, shutter, Calculator, album, flashlight, hint pill) | Done, pixel layout matched to Photomath |
| Left slide‑out menu (Language, Settings, Help center, About us, PhotoMesh Plus) | Done, tap + edge‑swipe + drag to close |
| Help center with playable demonstrations (scan, draw, steps, calculator) drawn live by the app itself | Done, `HelpDemos.swift` |
| Calculator sheet (dotted input line, live `= result`, Show Solution, history) | Done |
| Custom keyboard (abc / history / arrows / return / delete row, four category chips, key grid, press bubble, long‑press alternates on green‑dot keys) | Done |
| Help center ("How to use" cards) | Done |
| Settings (circuit settings with pickers) | Done, persisted with `@AppStorage` |
| Language bottom sheet | Done |
| About us, PhotoMesh Plus | Done (layout only, no purchases) |
| Solutions sheet (one card per method) → Solving Steps (Next Step, Why, feedback) → Circuit detail (netlist, node voltages, element results) | Done |
| Photo → netlist recognition (OpenRouter, `google/gemini-3.5-flash-lite` first, `gemini-3.6-flash` on doubt) | Done; testers use a built-in, rate-limited key |
| DC solver: series/parallel reduction (when it applies) + nodal (MNA, supernodes) + mesh (planar windows, supermeshes), cross‑checked | Done, unit‑tested |
| Textbook walkthroughs: given/find, KCL/KVL term by term, fractions cleared, systems solved by elimination one step at a time, power‑balance and KCL check | Done |
| Capacitors, inductors, lamps, batteries and switches (solved at DC steady state, drawn with their own symbols) | Done |
| Current flow animated on the schematic (moving dots along wires and around meshes) | Done |
| Schematic redrawn from the photo, fixed window above the steps that zooms to what each step talks about | Done |
| Full‑screen circuit explorer (pinch, pan, tap a node or part for details in a floating card) | Done |
| Hand‑drawn circuit entry on a dot grid (Draw button on the home screen): lines, cornered wires and loops, zigzag/box resistors, coils, circle sources, parts slot into wires, tap actions, hold‑to‑move, Draw/Erase/Ground modes, parts palette, pan/zoom | Done |
| Step equations typeset as LaTeX (fractions, subscripts, units) | Done |
| "Check the circuit" step after a scan with an editor for parts, values, nodes, ground and the question | Done |
| History of solved circuits (button right of the shutter) | Done |
| Circuit lab (Plus): Tweak mode re-solves live as values are dragged and switches flipped; Simulate mode plays the circuit in time with plots, a scrubber and switch events | Done, `ExplorerModel`, `TransientSimulator` |
| Exports (Plus): LTspice schematic (.asc) + SPICE netlist (.cir), PDF of any step-by-step solution | Done, `SpiceExport`, `StepsPDFExporter` |
| Feedback loop: bonus scans for sharing, corrections, ratings and a survey; uploads to the collector baked into the build; worker with D1 stats and per-install deletion; dataset and report tools | Done, `ScanCredits`, `ContributeSheet`, `tools/telemetry-worker`, `tools/dataset` |
| Circuits course (modules 1–2 free, rest Plus): 9 modules, 38 animated lessons with quizzes; opens with the water-in-pipes analogy and then follows the classic first-year syllabus | Done, `Features/Course` |
| PhotoMesh Plus via RevenueCat (paywall, Customer Center, `photocircuits_pro` entitlement), feature gates in `PlusAccess` | Done |
| AC solving, dependent sources | Next |

The camera runs on device only. In the Simulator the home screen shows a neutral
backdrop and the shutter still runs the full capture → solutions flow. Without an API key
(or with *Use sample circuit* switched on in Settings) the flow solves a built‑in two‑loop
circuit through the real engine, so every screen can be exercised without hardware or credits.

## How a scan is solved

1. **Capture** – the viewfinder crop is down‑scaled to 1280 px and sent as JPEG.
2. **Read** – `CircuitRecognizer` asks the model (system prompt in `RecognitionPrompt.swift`)
   for strict JSON: components with node ids, source polarity / current direction, ground node,
   mesh hints, and what the question asks. `CircuitPayload` decodes it tolerantly and
   `Circuit.validated()` rejects shorted sources, dangling parts, disconnected graphs and
   unsupported elements with a readable message.
3. **Solve** – `CircuitAnalyzer` first redraws the circuit for DC steady state when needed
   (capacitors and open switches become opens, inductors and closed switches become shorts that
   merge their nodes, lamps solve as resistors, batteries as voltage sources; a step explains
   each replacement and the results are read back onto the drawn elements). Then it runs
   - `ReductionAnalysis` (only when there is one source and the resistors form a plain
     series/parallel pattern): combines two resistors per step with the rule and the arithmetic
     shown, applies Ohm's law to the equivalent, then undoes each combination, sharing the
     current along series parts and the voltage across parallel parts;
   - `NodalAnalysis`: modified nodal analysis internally; the walkthrough lists every current
     leaving a node ("through R1 to a: (Vb − Va)/R1 = (Vb − 9)/1000"), clears the fractions
     with a common multiple so the equations have whole‑number coefficients, handles nodes
     fixed by sources (including sources chained off a fixed node) and supernodes, and solves
     the system by numbered elimination steps followed by back‑substitution
     (`SystemNarrator`), checked against the matrix solution;
   - `MeshAnalysis`: meshes are the windows of the drawing (planar face enumeration from the
     layout, falling back to the recognizer's hints or a cycle basis), all clockwise so shared
     resistors read R·(I₁ − I₂); KVL lists each element crossed, the sum, the expansion and the
     collected equation; current sources become known mesh currents or supermeshes; a negative
     result gets a "read the signs" step.
   Every method opens with a given/find step and closes with a power‑balance + KCL check
   (both computed, never assumed) and the answer. The methods are compared element by
   element; the UI shows whether they agree.

   The narrated algebra is exact: while a system is being solved every coefficient and every
   intermediate value is kept as a fraction (`Fraction` in `StepAlgebra.swift`) whenever the
   circuit's numbers allow it, so the working reads "Vc = 4600/775 = 184/31" and a value
   substituted into the next equation is the exact one. When a fraction would be unreadable
   (E12 values give things like 6534/4001) the lines switch to decimals carrying one guard
   digit, chosen so that redoing the printed arithmetic reproduces the printed result
   (12/140.74 = 85.26 mA). Elimination multipliers are the smallest whole numbers that make
   the two coefficients match; when those would exceed two digits the pivot row is scaled by
   the ratio itself ("(27/6991)×(1)"). Explanations are given in full the first time a rule
   is used and briefly afterwards.
4. **Present** – one card per method on the Solutions sheet, each opening its own walkthrough.

Values are formatted with engineering prefixes (37.5 mA, 4.7 kΩ) following the settings.

### PhotoMesh Plus: what the subscription unlocks

The free app scans (rate-limited on the shared key), draws, solves and explains. Plus adds
the parts that turn it from an answer key into a lab and a course; `PlusFeature` lists them
and every gate goes through `PlusAccess.allows(_:)` (Settings → Subscription has a developer
"Pretend Plus" toggle for testing):

- **Unlimited scans.** No hourly or daily cap.
- **Circuit lab.** The explorer has three modes. *Inspect* is the old tap-to-read view.
  *Tweak* shows a slider per element (a hundredfold either way for R, C, L; zero to double
  for sources) and a toggle per switch; the schematic re-solves through the normal engine
  after every change, the currents keep moving, and the question's answer is shown before and
  after. *Simulate* runs `TransientSimulator` (backward-Euler nodal analysis with companion
  models for capacitors and inductors, switches as 1 mΩ / 1 GΩ, an automatic window of five
  time constants) and plays the result: the schematic shows the instantaneous voltages and
  currents, the dots slow down as currents die away, plots of chosen node voltages and element
  currents carry a cursor, and a switch can be flipped at the playhead, which re-runs the
  simulation with that event. A circuit with no DC steady state (a source, a resistor and a
  capacitor in one loop) cannot be solved by the step methods, so the Solutions screen offers
  "Simulate in the lab" instead of a dead end.
- **The course.** Nine modules: an analogy-first opener, *Water and wires* (pressure is voltage,
  flow rate is current, a narrow pipe is resistance, the pump is the battery; no formula until
  the last lesson), then the order of Alexander & Sadiku / Nilsson & Riedel:
  foundations (charge, current, voltage, power), basic laws (Ohm, KCL, KVL, series and parallel,
  dividers, Y–Δ), methods (nodal, supernodes, mesh, supermeshes), theorems (superposition,
  source transformation, Thévenin, Norton, maximum power), capacitors and inductors, first-order
  transients, second-order circuits, and an AC introduction (sinusoids, phasors, impedance, AC
  power). Every circuit in a lesson is solved live by the engine and drawn with the same
  schematic as a scan, lit up keyframe by keyframe; the method lessons auto-play the engine's
  own solving steps; the transient lessons run the simulator; the concept animations
  (`ConceptAnimations.swift`, `WaterAnimations.swift`) are drawn on a Canvas. Each lesson ends with a quiz that explains
  every answer; progress and best scores are kept on the device. Modules 1 and 2 and the first
  lesson of every other module are free.
- **Exports.** From the explorer, an LTspice schematic laid out like the drawing (symbols on
  the 16 px grid, nets named after the nodes, wires split at every junction) plus a plain SPICE
  netlist, with element names given the letter SPICE expects; from the steps screen, an A4 PDF
  of the walkthrough with the equations typeset by SwiftMath and the solved schematic on page one.

### The visual companion

The recognizer also returns where every symbol sits in the picture (a normalized bounding
box and orientation) plus one point per node. `SchematicLayoutEngine` turns that into a clean
schematic: terminals are assigned to nodes, nearly‑aligned coordinates are snapped, and each
node is wired as a rail with perpendicular drops (the rail position comes from the node point,
so a ground rail below the components comes out where the book drew it). Junction dots and the
ground symbol are derived, not recognized.

Every solving step carries a `StepFocus`: the nodes, elements or meshes it talks about, whether
to zoom onto them, and which node voltages / currents / mesh currents are known at that point.
`SchematicWindow` (top of the Solving Steps screen) animates its camera to that focus, dims
everything else, draws current arrows with values, node voltages, and circulating mesh arrows.
Steps that know the currents also show them moving. `FlowField` (Engine) is built once per
step: one track per conductor, following what is drawn (the current zigzags through an ANSI
resistor and rides the humps of a coil, goes straight through boxes, sources, lamps, batteries
and closed switches), oriented the way the current really flows, with a speed proportional to
the current and the potential at either end. `SchematicView` draws two layers under one
animated camera: the schematic, redrawn only when the camera or the step changes, and a light
canvas above it that places dots along the tracks ~30 times a second, so pinching and zooming
never stall the motion. What the picture teaches is deliberately the physics: dots move at the
same speed before and after a resistor in series (current is not used up) and split at a
junction in proportion to the branch currents; their colour follows the potential, cool blue at
the lowest node and warm orange at the highest, so they fade across every resistor (energy given
up) and brighten again through a source. A capacitor at DC carries no current, so no dots pass
it and the plates show the charge they hold (+ and − marks, more for a larger voltage across
it); an inductor at DC is a wire and the dots ride through its coil. Mesh steps show dots
circulating around each window, reversed for a negative mesh current. The animation runs only
while such a step is open and respects Reduce Motion.

**Node names.** Nodes are named the way a textbook names them: letters `a`, `b`, `c`… from left
to right, with the reference node `0`, so node voltages read *Va*, *Vb* (typeset as V with a
subscript) and never clash with source names like V1. Whatever the recognizer or the sketch
called a node, `Circuit.withLetterNodes()` renames it on the way in. A supernode step draws a
dashed, lightly tinted boundary around the tied nodes and the source between them, labelled
"supernode", exactly the region the KCL equation is written for.

**Drawing conventions.** The schematic follows what a student sees in a textbook or lecture
figure (checked against a dozen Wikipedia / Commons figures on nodal analysis, mesh analysis,
Kirchhoff's laws, current dividers, Thévenin and Wheatstone bridges): parts and nodes are
labelled with subscripts (R₁, V₁, n₂), every place where three or more conductors meet gets a
filled junction dot, the reference node carries a ground symbol, current arrows sit beside the
wire, and a voltage step marks + and − on each element (the passive sign convention, + where
the current enters). Textbook figures leave plain corners bare, but many people read a dot at
every connection point as "these are joined", so by default the schematic also draws a smaller
dot at every corner where two wires turn (`SchematicLayout.corners`, never on a terminal or a
junction). Settings → *Node dots* switches to the strict textbook style (junctions only). A
step that talks about nodes ("Identify the nodes", "Choose the reference") additionally marks
each analysed node with an accent dot at its label, the way an analysis figure marks node 1,
node 2 even between two series parts.
The expand button (or a tap) opens `CircuitExplorerView`: free pinch/pan, double‑tap to fit, tap
a component or wire to read about it in the floating card at the bottom.

The ground symbol and the dots are drawn in screen points with a floor on their size, so a
zoomed‑out circuit keeps a legible ground instead of a speck.

The window is live: drag to pan, pinch to zoom, double‑tap to refit. The next step's focus
takes the camera back over (a re‑centre chip appears whenever you have moved it). New steps and
the answer scroll themselves into view, and the down arrow on an open step advances like the
Next Step button. At the end, a thumbs‑up asks for an App Store rating (at most twice, never
again once rated); a thumbs‑down opens a short feedback form stored on the device
(`FeedbackStore`), with an option to send it by email.

### Drawing a circuit by hand

The *Draw* button on the home screen opens a dot‑grid canvas (the keyboard calculator is the
second tab). One finger draws, two fingers pan, pinch zooms, and every stroke is recognized on
the spot, judged in finger coordinates so it behaves the same at any zoom:

| You draw | You get |
|---|---|
| A straight stroke, or one with corners | Axis‑aligned wire(s); ends magnet onto terminals, wire ends and wire interiors (T‑junctions) |
| A big closed outline | A rectangular loop of four wires |
| A zigzag, or a small box/square | A resistor (a square faces the way the nearby wires run) |
| A row of humps on one side, or cursive loops | An inductor |
| A circle or oval, closed or not | A bubble asks: voltage source, current source, lamp or battery |
| Two short parallel marks side by side | A capacitor |
| A short mark / anything the recognizer is unsure about | A bubble with the possible parts, likeliest first |
| The Parts button | Any part dropped in the middle, ready to drag |

**How recognition works.** `StrokeRecognizer` is a point‑cloud template matcher (the "$P"
family: the stroke is resampled to 32 points, stood upright if it is taller than wide, stretched
to the unit square and centred, then matched greedily against every template, so drawing
direction, start point and speed do not matter). The built‑in templates are synthesized
(`StrokeTemplateFactory`): zigzags with 3–7 peaks, sharp and rounded, with and without lead
lines; coils as humps or loops; boxes of several aspects with rounded corners; circles and
ovals, left open or overshooting. On top of the template distances, `StrokeClassifier` applies a
few scale‑free shape facts that settle the classic confusions: self‑crossings (loops), the
sharpness of the extremes on each side of the axis and the bow of the stroke between them
(humps are arcs standing on a baseline, a zigzag's diagonals are straight), and the fill of the
outline (a box fills ≈95% of its tightest rectangle, a circle ≈79%). The closest family wins
only when it is clearly ahead; otherwise the canvas *asks*, with the likely answers first. The
whole thing runs in ~3 ms per stroke.

**It learns your hand.** Every correction is a lesson: picking a part from the bubble, changing
the type in the value sheet or from the part's menu adds that stroke to a per‑user library
(`StrokeLibrary`, up to 16 examples per kind, kept in Application Support), and those templates
take part in every later match. Settings → *Forget taught strokes* clears it. The Linux
harness `recogtest` scores the recognizer on thousands of synthetic hand‑style strokes
(different generators from the templates, with tremor, tilt, uneven speed, overshoot): boxes,
circles, loops and wire paths ≥96% committed correctly, humps ≈98%, zigzags ≈89% committed plus
≈9% asked with the right answer first, and wrong commits ≤2–3% per class. Real fingers are the
test that matters, which is why the correction loop is one tap and teaches as it goes. When
enough corrected strokes have been collected (they are the ideal labelled dataset), the same
architecture can carry a small Core ML model trained on them; the template library is the
bridge until then.

**The value sheet** opens right after a part is recognized. It shows what the part was read as
and a row of alternatives (the recognizer's other candidates first): tap one to change the type
on the spot (units follow), *Done* saves, *Later* skips, and a red *Not a part, remove it* takes
the placement back together with everything it did to the wires. Tap a part any time for its
actions: value, rotate, flip (or toggle a switch), mark as the unknown, change type, delete;
double‑tap rotates about the connected terminal. Hold a part, wire or ground and drag to move
it. The toolbar has Draw, Erase and Ground modes, Parts, Undo, Redo and Clear. The “?” button
replays the tips. Bubbles measure themselves and stay inside the canvas; long lists scroll.

**What the drawing shows is what the circuit is.** A part drawn on a wire slots into it (the
wire is cut at the terminals, a short wire is taken over, a part at the end of a wire is pulled
inside it, and it slides a step to avoid swallowing a junction). A part drawn across a wire
lands one terminal on it. Beyond that, `seat` now enforces that no wire may pass through a
part's body or end inside it: the part is squeezed to end on such a wire (down to two grid
steps), slid so a terminal lands on the wire it was drawn across, or, drawn between two rails,
made to span exactly those rails; a terminal that stops a step short of a rail is stretched onto
it. So a resistor dropped between the rails of a loop is connected, not merely touching. Any
terminal that still hangs free is ringed in red on the canvas as you draw, so a loose end is
seen before *Solve* reports it. `SketchDocument` derives the nodes with union‑find (T‑junctions
included), builds the `Circuit` with exact geometry, and the same engine and screens take it
from there. All of this is exercised on Linux by the sketch harness.

### Typeset steps

Every equation line in the solving steps is typeset. The engine still produces plain text
(`(V₂ − 12)/100 + V₂/220 = 0`); `Engine/EquationLaTeX.swift` converts it to LaTeX
(`\frac{V_{2} - 12}{100} + \frac{V_{2}}{220} = 0`: fractions, subscripts, upright units, prose
in `\text{}`), and `MathText` renders it natively with the
[SwiftMath](https://github.com/mgriebling/SwiftMath) package (no web view). If a line ever fails
to parse it falls back to the plain text, and the plain text stays the accessibility label. The
converter is checked against the full corpus of lines the engine emits for the test circuits.

### Checking a scan

The "Is this what's on the page?" card and the circuit card at the top of Solutions show the
schematic in an `InteractiveSchematic`: pinch to zoom, drag to pan once zoomed, double‑tap to
fit; until you zoom, the page keeps scrolling normally. Solutions lists the circuit card first
(what was solved), then a card per method (how).

After recognition the Solutions sheet first shows the redrawn circuit, the part list, the ground
node and the question next to a thumbnail of the photo. *Looks right* solves; *Fix something*
opens an editor where parts can be added or removed and their type, value, name and terminal
nodes changed, the ground node picked, and the question edited. Turn the check off in Settings →
Recognition if you prefer straight‑to‑answer.

### History

Every solved circuit (scanned or drawn) is kept on the device; the History button right of the
shutter lists them with a thumbnail, and tapping one re‑runs the engine and opens its solutions.

### Cost and routing

Every scan goes to a cheap first pass (`google/gemini-3.5-flash-lite`, low reasoning effort,
about 2–3 s and $0.002 per scan on the test set). The result is validated and solved with both
methods immediately; if it does not validate, finds no circuit, or the methods disagree, the scan
is re-read once by the stronger `google/gemini-3.6-flash`. Both models, the fast first pass and
the escalation are configurable under Settings → Recognition. A benchmark over the test
schematics (`scratchpad` script, seven images, answers checked by solving the netlists) gave:

| Model | Correct | Avg time | Cost / scan |
| --- | --- | --- | --- |
| gemini-3.6-flash | 7/7 | 10 s | $0.0088 |
| gemini-3.6-flash, low reasoning | 7/7 | 6 s | $0.0058 |
| gemini-3.5-flash-lite, low reasoning | 7/7 (21/21 on repeats) | 2.4 s | $0.0022 |
| gpt-5-nano, low reasoning | 7/7 | 11 s | $0.0009 |
| gemini-2.5-flash-lite | 5/7 | 2.5 s | $0.0006 |

The image costs a flat ~1,090 input tokens at any resolution; the prompt is ~1,200. Reasoning
tokens (billed as output) dominate, which is why the fast first pass matters.

### Data collection and the feedback loop

Off until the user opts in (a one-time card after the first solve, or Settings → Privacy & data):

- **Anonymous usage**: events such as `first_open`, `app_open`, `app_background` (seconds active),
  `capture`, `recognition` (model, tier, latency, tokens, outcome), `solve`, `solve_failed`,
  `steps_opened`, `steps_completed`, `why_opened`, `explorer_mode`, `export`, `lesson_opened`,
  `lesson_completed`, `plus_gate`, `paywall_shown`, `purchase_started/completed/failed`,
  `credits_earned/spent`, `scan_accepted/corrected` (with a `CorrectionDiff`: how many parts were
  added, removed, retyped, revalued or rewired). Every event carries a random install id, a session
  id, app and OS version, device model, locale, whether Plus is active and the install's age. No images.
- **Scans**: the picture (JPEG, ≤1280 px) with the recognized netlist and, when the user used
  *Fix something*, the corrected netlist plus the diff. These are the evaluation and training set.
- **Feedback and the survey** are explicit submissions and always go out: a thumbs rating carries
  the method, the question, reasons, comment and the circuit as a SPICE netlist so a report can be
  reproduced; the five-question survey (role, stage, uses, wish, 0–10 recommendation) goes out once.

**Bonus scans** thank people for helping (`ScanCredits`): +10 for turning scan sharing on, +2 per
rated walkthrough (3 a day), +2 per corrected misread while sharing is on (5 a day), +5 for the
survey, banked up to 60. A bonus scan is spent only when the beta allowance window is full
(`UsageAllowance`), so it never costs a subscriber anything. The program lives in one screen,
*Help & bonus scans* (side menu → Give feedback, Settings → Privacy & data, and the "limit reached"
card), which also shows what was shared and offers *Delete my shared data*.

**Pipeline.** Everything is stored locally first (`Analytics`, Application Support/PhotoMesh/analytics),
can be exported as one JSON file, and uploads itself in batches under 6 MB (retry with backoff,
event files rotated so an upload never races a write) to the collector baked into the build:
the TestFlight workflow embeds the `TELEMETRY_ENDPOINT` and `TELEMETRY_KEY` secrets with
`tools/embed-key.sh --telemetry`, next to the OpenRouter key. `tools/telemetry-worker` is the
Cloudflare Worker: it files each upload per install in R2 (`installs/<id>/{events,samples,images}`),
indexes it in D1, answers `GET /stats` (installs, solves per day, recognition outcomes by model,
accept vs corrected rate, correction kinds, feedback helpful rate and reasons, survey by role with
NPS, credits, the Plus funnel, session length) and honours `POST /forget`. `tools/dataset` syncs
the bucket, builds `train/val.jsonl` split by install, writes every corrected scan as a fixture in
the recognition benchmark's format, and prints the same report from the files without a database.
`PrivacyInfo.xcprivacy` and `docs/privacy.html` describe all of it.

### Recognition setup

Settings → Recognition → *OpenRouter API key*. The key is kept in the device Keychain and only
sent to `openrouter.ai`. For Xcode runs you can instead set an `OPENROUTER_API_KEY` environment
variable in the scheme. The model id is editable; any OpenRouter model with image input works.

### Engine tests

The engine is plain Foundation code, so it also builds on Linux. A development harness feeds
sixteen fixtures through the solver: series loop, loaded divider, two sources, current source
(both orientations), supermesh, supernode, Wheatstone bridge, DC parts (battery, inductor,
lamp, capacitor, switch), a source with its + terminal on the ground side, a parallel‑only
network, two batteries in series, and two E12‑valued networks (a ladder and a bridge). For
each one it checks hand‑computed values, that every offered method agrees on every element
current, and that no method fell back from the narrated solve.

On top of that a step verifier reads every line of every step: it splits each line at its
"=" signs, evaluates every segment that is arithmetic (numbers with SI prefixes and units,
fractions, squares) or a known symbol (node voltages, element values, element currents and
voltages, mesh currents, all taken from the true solution) and requires all segments to
agree. So "17·Vb − 2·Vc = 100" is checked against the real node voltages, "(85.263 mA)²·100 Ω
= 727 mW" is checked as arithmetic, and a "→ Vb = 6.581 V" line is checked against the
division written above it. The last run verified about 1,150 such equalities with none wrong.
A separate corpus check converts every produced line to LaTeX and rejects anything the
typesetter could not render.

Three more harnesses cover the Plus features: `simtest` compares the transient simulator with
the closed-form RC, RL and RLC responses (charging, decay after a switch opens, a settled start,
an underdamped overshoot of exactly 10·(1 + e^(−πζ/√(1−ζ²)))) to within a percent; `exporttest`
re-derives the netlist from every generated LTspice schematic by joining coincident wire ends
and pins, and requires it to match the circuit, with polarised parts the right way round and
every coordinate on the grid; `demotest` runs every circuit embedded in the course through the
solver (and the simulator where it applies) so a lesson can never show a circuit the engine
would not accept.

## Project layout

```
PhotoMesh.xcodeproj/          Xcode 16 project (file‑system synchronized group – just add files)
PhotoMesh/
  App/                        @main entry, AppRouter (sheets + drawer state)
  Theme/PMTheme.swift         colors, button styles, logo mark, wordmark
  Support/                    AppSettings (keys + option enums), APIConfiguration (Keychain), Haptics
  Engine/                     pure-Swift solver
    CircuitModel.swift        Circuit / Component / validation / graph helpers
    NodalAnalysis.swift       node-voltage method + steps (with StepFocus)
    MeshAnalysis.swift        mesh-current method, loop detection + steps
    CircuitAnalyzer.swift     DC redraw, runs every method, cross-checks, builds the layout
    ReductionAnalysis.swift   series/parallel simplification walkthrough
    StepAlgebra.swift         nice numbers, fraction clearing, narrated elimination
    SchematicLayout.swift     geometry → schematic drawing primitives
    CircuitPayload.swift      tolerant JSON decoding of the model output
    Units.swift               engineering-notation formatter / parser
    EquationLaTeX.swift       plain equation lines → LaTeX
  Services/
    OpenRouterClient.swift    chat completions with image input
    RecognitionPrompt.swift   the system prompt
    CircuitRecognizer.swift   photo → Circuit
    CircuitSolverService.swift  VLM solver, offline sample solver, calculator solver
  Features/
    Root/RootView.swift       drawer container + sheet host + safe-area plumbing
    Camera/                   CameraController (AVFoundation), preview, viewfinder, home screen
    Menu/SideMenuView.swift
    Calculator/               keyboard model + view, expression evaluator, calculator sheet
    Help/                     How‑to‑use sheet with illustrations
    Settings/                 Settings (incl. Recognition + Diagnostics), Language, About, Plus
    Solutions/                Solutions sheet, Solving Steps (MathText), Circuit detail, editor
    Schematic/                Canvas renderer, animated step window, full-screen explorer
    Sketch/                   Hand-drawn canvas, UIKit gesture host, stroke classifier, editing rules, sketch → netlist
    History/                  Saved circuits sheet (store in Support/HistoryStore.swift)
.github/workflows/testflight.yml        archive + upload to TestFlight
```

Requirements: Xcode 16 or newer, iOS 17 deployment target. The one package dependency
(SwiftMath, for typeset equations) resolves automatically when the project opens.

## Run it

1. Open `PhotoMesh.xcodeproj`.
2. Select the `PhotoMesh` target → Signing & Capabilities → pick your team.
   Change the bundle identifier if `com.photomesh.app` is taken in your account.
3. Run on an iPhone for the camera, or on the Simulator for everything else.

## Tester builds: built-in key and limits

Testers never see an API key. A Release build reads photos with a key baked into the app:

- `tools/embed-key.sh <key>` writes the key, XOR-obfuscated, into `Support/BuiltinKey.swift`;
  the TestFlight workflow does this from the `OPENROUTER_TESTER_KEY` secret and a check step
  fails the build if a key was ever committed. Locally: embed, archive, then
  `tools/embed-key.sh --clear` (add `tools/embed-key.sh --check` to a pre-commit hook if you like).
- Obfuscation only keeps the key out of `strings`; anyone determined can recover it from the
  IPA. Create a dedicated key on openrouter.ai **with a credit limit** and rotate it when the beta
  ends.
- Per device, `UsageAllowance` caps calls on the built-in key to 12 an hour and 40 a day (rolling
  windows; a second-pass read counts too and is skipped when out of allowance). Over the limit the
  scan fails with a message saying when it resets; Settings → Recognition shows what is left.
  Drawing circuits by hand and the sample circuit are unlimited.
- Key entry, model choice and the fast/escalate switches only appear in Debug builds, or after
  tapping the version in About seven times (a personal key entered there is not metered).

With no key at all a Release build falls back to the sample circuit and says so.

## Ship to TestFlight

Builds are signed and uploaded by the `TestFlight` GitHub Actions workflow (manual trigger,
or automatically on pushes to `main`). It needs an App Store Connect API key plus a
distribution certificate – never an Apple ID password.

One‑time setup (about 10 minutes):

1. **App record** – in App Store Connect create the app with your bundle identifier.
2. **API key** – App Store Connect → Users and Access → Integrations → App Store Connect API →
   generate a key with the *App Manager* role. Note the Key ID and Issuer ID and download the `.p8`.
3. **Distribution certificate** – Xcode → Settings → Accounts → your team → Manage Certificates →
   `+` → Apple Distribution. Then in Keychain Access export that certificate (with private key)
   as a `.p12` with a password.
4. **Secrets** – add these to the GitHub repository (Settings → Secrets and variables → Actions):

   | Secret | Value |
   | --- | --- |
   | `APPLE_TEAM_ID` | 10‑character team ID |
   | `BUNDLE_ID` | the bundle identifier from step 1 |
   | `ASC_KEY_ID` | API key ID |
   | `ASC_ISSUER_ID` | API issuer ID |
   | `ASC_PRIVATE_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
   | `DIST_CERT_P12_BASE64` | `base64 -i dist.p12 \| pbcopy` |
   | `DIST_CERT_PASSWORD` | the `.p12` password |
   | `KEYCHAIN_PASSWORD` | any random string |

5. Run the workflow from the Actions tab. When it finishes, the build appears in
   App Store Connect → TestFlight within a few minutes; add yourself as an internal tester
   and install from the TestFlight app.

Alternative with zero secrets: connect the repository to **Xcode Cloud** (Xcode → Product →
Xcode Cloud → Create Workflow) and choose "TestFlight (Internal Testing Only)" as the
post‑action. Xcode Cloud manages signing itself.

### If a scan fails

Settings → Recognition → *Diagnostics* keeps the last requests: image size, HTTP status, timing,
token counts and any transport error code. The failure card on the Solutions sheet shows the
same lines under *Show diagnostics*. Copy and paste them into an issue.

## Next phase

- Polish the step ↔ schematic choreography (per‑step annotations, KCL current arrows at the node).
- More methods (series/parallel reduction, superposition, Thévenin) and more elements
  (dependent sources, AC phasors).
