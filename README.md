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
| Calculator sheet (dotted input line, live `= result`, Show Solution, history) | Done |
| Custom keyboard (abc / history / arrows / return / delete row, four category chips, key grid, press bubble, long‑press alternates on green‑dot keys) | Done |
| Help center ("How to use" cards) | Done |
| Settings (circuit settings with pickers) | Done, persisted with `@AppStorage` |
| Language bottom sheet | Done |
| About us, PhotoMesh Plus | Done (layout only, no purchases) |
| Solutions sheet (one card per method) → Solving Steps (Next Step, Why, feedback) → Circuit detail (netlist, node voltages, element results) | Done |
| Photo → netlist recognition (OpenRouter, `google/gemini-3.6-flash` by default) | Done, key entered in Settings → Recognition |
| DC solver: nodal (MNA, supernodes) + mesh (auto loop detection, supermeshes), cross‑checked | Done, unit‑tested |
| Schematic redrawn from the photo, fixed window above the steps that zooms to what each step talks about | Done |
| Full‑screen circuit explorer (pinch, pan, tap a node or part for details in a floating card) | Done |
| Hand‑drawn circuit entry on a dot grid (Calculator → Draw circuit): continuous recognition, cornered wires, pan/zoom, double‑tap rotate, guided review before solving | Done |
| "Check the circuit" step after a scan with an editor for parts, values, nodes, ground and the question | Done |
| History of solved circuits (button right of the shutter) | Done |
| AC / dependent sources, more methods | Next |

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
3. **Solve** – `CircuitAnalyzer` runs
   - `NodalAnalysis`: modified nodal analysis internally; the steps show known node voltages,
     supernodes, one KCL equation per node in fraction form plus collected form, the solved
     system, element currents, voltages, and the answer;
   - `MeshAnalysis`: uses the recognizer's mesh hints when they form a valid independent set,
     otherwise finds a shortest cycle basis itself; current sources become known mesh currents
     or supermeshes; steps mirror the nodal ones with KVL equations.
   Both methods are compared element by element; the UI shows whether they agree.
4. **Present** – one card per method on the Solutions sheet, each opening its own walkthrough.

Values are formatted with engineering prefixes (37.5 mA, 4.7 kΩ) following the settings.

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
The expand button (or a tap) opens `CircuitExplorerView`: free pinch/pan, double‑tap to fit, tap
a component or wire to read about it in the floating card at the bottom.

The window is live: drag to pan, pinch to zoom, double‑tap to refit. The next step's focus
takes the camera back over (a re‑centre chip appears whenever you have moved it). New steps and
the answer scroll themselves into view, and the down arrow on an open step advances like the
Next Step button. At the end, a thumbs‑up asks for an App Store rating (at most twice, never
again once rated); a thumbs‑down opens a short feedback form stored on the device
(`FeedbackStore`), with an option to send it by email.

### Drawing a circuit by hand

Calculator → *Draw circuit* opens a dot‑grid canvas that never interrupts you: one finger
draws, two fingers pan, pinch zooms. `StrokeClassifier` turns each stroke into an axis‑aligned
wire (a stroke with corners becomes a chain of wires that meet exactly), a resistor (zigzag or
rectangle), or a source (a circle, provisionally a voltage source), and parts snap to the grid
and to nearby wire ends. *Review & solve* then walks through every part that still needs a type
or a value, one at a time, with the part highlighted on the canvas. Tap a part to edit it, flip
it, mark it as the unknown, or delete it; double‑tap rotates it; the Ground tool places the
reference. `SketchDocument` derives the nodes with union‑find (T‑junctions included), builds the
`Circuit` with exact geometry, and the same engine and screens take it from there.

### Checking a scan

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

### Data collection

Off until the user opts in (a one-time card after the first solve, or Settings → Privacy & data):

- **Anonymous usage**: events such as `app_open`, `capture`, `recognition` (model, tier, latency,
  tokens, outcome), `solve`, `solve_failed`, `sketch_solve`, `feedback`, tagged with a random
  install id, app version, OS version, device model and locale. No images.
- **Scans**: the picture (JPEG, ≤1280 px) with the recognized netlist and, when the user used
  *Fix something*, the corrected netlist. These are the evaluation and training set.

Everything is stored locally (`Analytics`, Application Support/PhotoMesh/analytics), can be
exported as one JSON file from Settings → Privacy & data → Collected data, and is uploaded when
an HTTPS endpoint is configured there. `tools/telemetry-worker` is a ready-to-deploy Cloudflare
Worker that stores each upload in an R2 bucket. `PrivacyInfo.xcprivacy` declares the collected
data types and required-reason APIs for App Store review.

### Recognition setup

Settings → Recognition → *OpenRouter API key*. The key is kept in the device Keychain and only
sent to `openrouter.ai`. For Xcode runs you can instead set an `OPENROUTER_API_KEY` environment
variable in the scheme. The model id is editable; any OpenRouter model with image input works.

### Engine tests

The engine is plain Foundation code, so it also builds on Linux. `scratchpad` scripts used
during development fed synthetic schematics (series loop, loaded divider, two sources,
current source, supermesh, supernode, Wheatstone bridge) through the recognizer and the
solver and compared against hand‑computed values; nodal and mesh agree on all of them.

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
    CircuitAnalyzer.swift     runs both methods, cross-checks, builds the layout
    SchematicLayout.swift     geometry → schematic drawing primitives
    CircuitPayload.swift      tolerant JSON decoding of the model output
    Units.swift               engineering-notation formatter / parser
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
    Solutions/                Solutions sheet, Solving Steps, Circuit detail
    Schematic/                Canvas renderer, animated step window, full-screen explorer
    Sketch/                   Hand-drawn canvas, UIKit gesture host, stroke classifier, sketch → netlist
    History/                  Saved circuits sheet (store in Support/HistoryStore.swift)
.github/workflows/testflight.yml        archive + upload to TestFlight
```

Requirements: Xcode 16 or newer, iOS 17 deployment target.

## Run it

1. Open `PhotoMesh.xcodeproj`.
2. Select the `PhotoMesh` target → Signing & Capabilities → pick your team.
   Change the bundle identifier if `com.photomesh.app` is taken in your account.
3. Run on an iPhone for the camera, or on the Simulator for everything else.

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
- Pinch‑zoom on the drawing canvas for large circuits.
