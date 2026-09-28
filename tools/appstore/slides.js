// One entry per App Store screenshot, in store order. Positions are percentages of the page,
// sizes are pixels at the 6.9" reference (1320 × 2868) and scale with the page.
//
//   screenshot  a full-resolution device screenshot in ./screens (any iPhone size; it is fitted)
//   bg / bg2    the page colour and the corner colour; corner picks which corner bg2 cuts across
//   fg          headline colour
//   tilt        degrees the phone is turned
//   blob        optional soft circle behind the phone: { color, x, y, d }
//   doodles     [{ d: name from doodles.js, x, y, w, rot, color }]
const INK = "#16181c";
const WHITE = "rgba(255,255,255,0.92)";
const GREEN = "#126B3D";
const YELLOW = "#FFD34D";
const CORAL = "#F2695C";
const TEAL = "#0F7C86";
const CHARCOAL = "#24262B";
const MINT = "#BDE7CF";

window.SLIDES = [
  {
    slug: "solve",
    screenshot: "screens/solutions.png",
    headline: ["Point at a circuit.", "Get the whole solution."],
    bg: GREEN, bg2: YELLOW, corner: "tr", fg: "#fff", tilt: -3,
    blob: { color: MINT, x: 50, y: 62, d: 1500 },
    doodles: [
      { d: "resistor", x: 1.5, y: 1.6, w: 120, rot: -14, color: WHITE },
      { d: "omega", x: 91, y: 1.4, w: 90, rot: 8, color: INK },
      { d: "node", x: 0.5, y: 22, w: 150, rot: 0, color: WHITE },
      { d: "battery", x: 86, y: 26, w: 170, rot: 90, color: INK },
      { d: "current", x: 0, y: 44, w: 170, rot: 0, color: WHITE },
      { d: "capacitor", x: 85, y: 50, w: 150, rot: -90, color: INK },
      { d: "ground", x: 3, y: 66, w: 130, rot: 0, color: WHITE },
      { d: "lamp", x: 87, y: 70, w: 130, rot: 0, color: INK },
      { d: "plus", x: 4, y: 88, w: 90, rot: 20, color: WHITE },
      { d: "switch", x: 84, y: 89, w: 160, rot: 0, color: INK },
    ],
  },
  {
    slug: "flow",
    screenshot: "screens/steps-flow.png",
    headline: ["Watch the current flow", "as you solve"],
    bg: CORAL, bg2: TEAL, corner: "bl", fg: "#fff", tilt: 0,
    blob: { color: YELLOW, x: 50, y: 58, d: 1400 },
    doodles: [
      { d: "arrow", x: 1.5, y: 1.4, w: 130, rot: 0, color: INK },
      { d: "dots", x: 88, y: 1.8, w: 120, rot: 0, color: INK },
      { d: "inductor", x: 0, y: 22, w: 190, rot: 90, color: INK },
      { d: "loop", x: 86, y: 24, w: 140, rot: 0, color: INK },
      { d: "current", x: 85, y: 46, w: 170, rot: -90, color: INK },
      { d: "sine", x: 0, y: 46, w: 170, rot: -70, color: INK },
      { d: "omega", x: 2, y: 68, w: 110, rot: -6, color: INK },
      { d: "resistor", x: 86, y: 66, w: 170, rot: 70, color: INK },
      { d: "switch", x: 2, y: 88, w: 160, rot: 0, color: WHITE },
      { d: "ground", x: 89, y: 88, w: 120, rot: 0, color: INK },
    ],
  },
  {
    slug: "steps",
    screenshot: "screens/steps-read.png",
    headline: ["Every step, written", "the way it's marked"],
    bg: TEAL, bg2: YELLOW, corner: "tl", fg: "#fff", tilt: 3,
    blob: { color: CORAL, x: 50, y: 60, d: 1450 },
    doodles: [
      { d: "volt", x: 2, y: 1.2, w: 100, rot: -10, color: INK },
      { d: "capacitor", x: 88, y: 1.6, w: 130, rot: 0, color: WHITE },
      { d: "battery", x: 0.5, y: 22, w: 170, rot: -90, color: WHITE },
      { d: "omega", x: 88, y: 24, w: 110, rot: 12, color: WHITE },
      { d: "node", x: 86, y: 46, w: 150, rot: 180, color: INK },
      { d: "resistor", x: 0, y: 46, w: 200, rot: 70, color: INK },
      { d: "sine", x: 1, y: 68, w: 160, rot: 0, color: INK },
      { d: "lamp", x: 87, y: 68, w: 130, rot: 0, color: WHITE },
      { d: "plus", x: 4, y: 90, w: 80, rot: 0, color: WHITE },
      { d: "arrow", x: 86, y: 90, w: 140, rot: 0, color: INK },
    ],
  },
  {
    slug: "lab",
    screenshot: "screens/lab-simulate.png",
    headline: ["Tweak the values.", "Simulate in time."],
    bg: CHARCOAL, bg2: GREEN, corner: "br", fg: "#fff", tilt: 0,
    blob: { color: TEAL, x: 50, y: 60, d: 1380 },
    doodles: [
      { d: "sine", x: 1.5, y: 1.4, w: 130, rot: 0, color: WHITE },
      { d: "switch", x: 88, y: 1.6, w: 120, rot: 0, color: WHITE },
      { d: "capacitor", x: 0, y: 22, w: 170, rot: 90, color: WHITE },
      { d: "inductor", x: 86, y: 24, w: 170, rot: 90, color: WHITE },
      { d: "arrow", x: 86, y: 46, w: 150, rot: -90, color: WHITE },
      { d: "dots", x: 0, y: 46, w: 160, rot: 90, color: WHITE },
      { d: "omega", x: 2, y: 68, w: 110, rot: 0, color: WHITE },
      { d: "battery", x: 86, y: 68, w: 160, rot: 90, color: WHITE },
      { d: "loop", x: 2, y: 88, w: 130, rot: 0, color: WHITE },
      { d: "ground", x: 88, y: 88, w: 120, rot: 0, color: WHITE },
    ],
  },
  {
    slug: "draw",
    screenshot: "screens/draw.png",
    headline: ["No photo?", "Draw it with a finger."],
    bg: YELLOW, bg2: CORAL, corner: "tr", fg: INK, tilt: -3,
    blob: { color: MINT, x: 50, y: 62, d: 1450 },
    doodles: [
      { d: "resistor", x: 1.5, y: 1.6, w: 130, rot: 12, color: INK },
      { d: "lamp", x: 90, y: 1.4, w: 100, rot: 0, color: WHITE },
      { d: "switch", x: 0, y: 22, w: 180, rot: -90, color: INK },
      { d: "battery", x: 86, y: 26, w: 170, rot: 90, color: INK },
      { d: "omega", x: 2, y: 46, w: 120, rot: -8, color: INK },
      { d: "node", x: 84, y: 48, w: 150, rot: 180, color: INK },
      { d: "current", x: 0, y: 66, w: 170, rot: 0, color: INK },
      { d: "capacitor", x: 85, y: 70, w: 150, rot: -90, color: INK },
      { d: "ground", x: 4, y: 88, w: 130, rot: 0, color: INK },
      { d: "plus", x: 90, y: 89, w: 90, rot: 15, color: INK },
    ],
  },
];
