// Renders every slide in slides.js at App Store sizes with headless Chromium.
//   node render.mjs                        6.9" iPhone (1320 × 2868), the one Apple requires
//   node render.mjs --device iphone69,iphone65,ipad13
//   node render.mjs --slides 1,3           only some slides (1-based)
//   node render.mjs --out ../../dist/appstore
// Output: out/<device>/<nn>-<slug>.png plus out/preview-<device>.png, a contact sheet.
import { chromium } from "playwright";
import { existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const DEVICES = {
  iphone69: { w: 1320, h: 2868, label: 'iPhone 6.9"' },
  iphone65: { w: 1242, h: 2688, label: 'iPhone 6.5"' },
  ipad13: { w: 2064, h: 2752, label: 'iPad 13"' },
};

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const devices = option("device", "iphone69").split(",").map((d) => d.trim()).filter((d) => DEVICES[d]);
const only = option("slides", "").split(",").map((n) => Number(n)).filter((n) => n > 0);
const out = resolve(here, option("out", "out"));
const noPreview = args.includes("--no-preview");

function chromiumPath() {
  if (process.env.CHROMIUM_PATH) return process.env.CHROMIUM_PATH;
  const shared = "/opt/pw-browsers/chromium";
  try { if (statSync(shared).isFile()) return shared; } catch {}
  return undefined;
}

async function launch() {
  try {
    return await chromium.launch();
  } catch (error) {
    const path = chromiumPath();
    if (!path) throw error;
    return await chromium.launch({ executablePath: path });
  }
}

const browser = await launch();
try {
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  const pageURL = pathToFileURL(join(here, "index.html")).href;
  await page.goto(pageURL);
  const slugs = await page.evaluate(() => window.SLIDES.map((s) => s.slug));
  const indices = slugs.map((_, i) => i).filter((i) => only.length === 0 || only.includes(i + 1));

  for (const key of devices) {
    const { w, h, label } = DEVICES[key];
    const dir = join(out, key);
    mkdirSync(dir, { recursive: true });
    const files = [];
    for (const i of indices) {
      await page.setViewportSize({ width: w, height: h });
      await page.goto(`${pageURL}?slide=${i}&w=${w}&h=${h}&device=${key}`);
      await page.evaluate(() => document.fonts.ready);
      await page.waitForFunction(() => Array.from(document.images).every((img) => img.complete && img.naturalWidth > 0));
      const file = join(dir, `${String(i + 1).padStart(2, "0")}-${slugs[i]}.png`);
      await page.screenshot({ path: file, type: "png" });
      files.push(file);
      console.log(`${label}  ${w}×${h}  ${file}`);
    }
    if (!noPreview && files.length) {
      const thumb = 300;
      const html = `<!doctype html><body style="margin:0;background:#111;display:flex;gap:16px;padding:16px">${files
        .map((f) => `<img src="${pathToFileURL(f).href}" style="width:${thumb}px;height:${Math.round((thumb * h) / w)}px;display:block">`)
        .join("")}</body>`;
      const previewFile = join(out, `preview-${key}.html`);
      writeFileSync(previewFile, html);
      await page.setViewportSize({ width: files.length * (thumb + 16) + 16, height: Math.round((thumb * h) / w) + 32 });
      await page.goto(pathToFileURL(previewFile).href);
      await page.waitForFunction(() => Array.from(document.images).every((img) => img.complete && img.naturalWidth > 0));
      await page.screenshot({ path: join(out, `preview-${key}.png`), type: "png" });
      console.log(`contact sheet  ${join(out, `preview-${key}.png`)}`);
    }
  }
} finally {
  await browser.close();
}
