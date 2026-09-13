# PhotoMesh

Photomath, but for circuit analysis. Point the camera at a schematic or a hand‑drawn
loop and get a step‑by‑step solution.

This is the first milestone: a SwiftUI iOS app whose UI/UX mirrors Photomath one‑to‑one,
with the red accent swapped for a deep green (`#126B3D`). Recognition and solving are
stubbed behind a `CircuitSolverService` protocol so a vision‑language‑model API can be
dropped in next.

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
| Solutions sheet → Solving Steps (Next Step, Why, feedback) → Circuit detail | Done, driven by a mock solver |
| VLM recognition / real solving | Not started (next phase) |

The camera runs on device only. In the Simulator the home screen shows a neutral
backdrop and the shutter still runs the full capture → solutions flow with a placeholder
image, so every screen can be exercised without hardware.

## Project layout

```
PhotoMesh.xcodeproj/          Xcode 16 project (file‑system synchronized group – just add files)
PhotoMesh/
  App/                        @main entry, AppRouter (sheets + drawer state)
  Theme/PMTheme.swift         colors, button styles, logo mark, wordmark
  Support/                    AppSettings (keys + option enums), Haptics
  Features/
    Root/RootView.swift       drawer container + sheet host
    Camera/                   CameraController (AVFoundation), preview, viewfinder, home screen
    Menu/SideMenuView.swift
    Calculator/               keyboard model + view, expression evaluator, calculator sheet
    Help/                     How‑to‑use sheet with illustrations
    Settings/                 Settings, Language, About, Plus
    Solutions/                Solutions sheet, Solving Steps, Circuit detail + schematic canvas
  Services/CircuitSolverService.swift   protocol + MockCircuitSolver
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

## Next phase

- Replace the math keyboard with circuit‑oriented manual entry (components, values, topology).
- Implement `CircuitSolverService` against a VLM API: send the cropped viewfinder image,
  receive a netlist + steps, render them in the existing Solutions / Solving Steps screens.
- Design the circuit representation (interactive schematic, per‑element values, mesh/nodal views).
