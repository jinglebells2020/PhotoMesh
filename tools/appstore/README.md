# App Store screenshots

Photomath-style store images for Photocircuits: a bold two-colour page, a two-line headline,
a framed device capture and a scatter of circuit-symbol doodles. Everything is one HTML
template (`index.html` + `style.css`), the slides are data (`slides.js`), the doodles are tiny
SVG paths (`doodles.js`), and `render.mjs` photographs each slide with headless Chromium at the
exact pixel sizes App Store Connect asks for.

```
cd tools/appstore
npm install                       # playwright; Chromium downloads on a Mac, is reused in the cloud container
node render.mjs                   # iPhone 6.9"  1320 × 2868  (the size Apple requires)
node render.mjs --device iphone69,iphone65,ipad13
node render.mjs --slides 2,4      # only some slides
open out/preview-iphone69.png     # contact sheet of the run
```

Output lands in `out/<device>/NN-slug.png`, ready to drag into App Store Connect. `out/` is
ignored by git.

## Capturing the screens

The frames show real captures, not mock-ups. Take them on an iPhone with a 6.9" screen (16 Pro
Max, 17 Pro Max) or in that simulator (⌘S saves a PNG), at 1320 × 2868; other iPhone sizes are
fitted but lose a little sharpness. Before capturing: Settings → turn on *Pretend Plus* under
the developer rows so nothing is locked, put the device in Do Not Disturb, and prefer a clean
status bar (the simulator shows 9:41 and a full battery by default). Drop the files into
`screens/` and point a slide at them.

Screens still wanted for a full set (add them to `slides.js` when captured): the camera pointed
at a textbook circuit for the opening slide, the course (Learn circuits → Water and wires),
the practice screen with a correct answer, and the Plus paywall.

## Editing slides

Each entry in `slides.js`:

| Field | Meaning |
| --- | --- |
| `headline` | two or three short lines; keep the second line the longer one |
| `screenshot` | the capture used for every device |
| `screenshots` | optional per-device captures, e.g. `{ ipad13: { src: "screens/steps-ipad.png", frame: "tablet" } }` |
| `bg`, `bg2`, `corner` | page colour, the corner colour and which corner it cuts (`tr`, `tl`, `bl`, `br`) |
| `fg` | headline colour: white on the dark pages, ink on yellow |
| `tilt` | degrees the phone is turned; alternate −3, 0, 3 |
| `blob` | soft circle behind the phone that peeks out at the sides |
| `doodles` | `{ d, x, y, w, rot, color }`: symbol name, position in % of the page, size in px at the 6.9" reference |

Keep doodles out of the headline band (roughly 6–17 % of the height). Sizes are relative to
the 6.9" page, so the same slide renders correctly at every device size.

## iPad

Apple wants iPad screenshots to show the app on an iPad. The generator renders the iPhone
composition at 2064 × 2752 as a fallback; for submission, capture the same screens on a 13"
iPad simulator and add them as `screenshots.ipad13` with `frame: "tablet"`.

## Fonts and licence

Headlines use Inter (SIL Open Font License), bundled in `fonts/` so the render is identical on
every machine. The device frames, doodles and colours are drawn by the template; nothing here is
a third-party asset.
