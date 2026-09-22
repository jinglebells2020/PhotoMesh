// Runs the worker in-process: a folder stands in for R2, node:sqlite for D1. Writes the same
// layout the real bucket gets, so tools/dataset can be tried on the result:
//   node test/run.mjs [outDir]
import worker from "../worker.js";
import { mkdirSync, writeFileSync, readdirSync, rmSync, statSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const out = process.argv[2] || join(here, "out");
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

// R2 stand-in
const bucket = {
  keys: new Set(),
  async put(key, value, opts) {
    const path = join(out, key);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, typeof value === "string" ? value : Buffer.from(value));
    this.keys.add(key);
  },
  async list({ prefix = "", delimiter, cursor, limit = 1000 }) {
    const all = [...this.keys].filter((k) => k.startsWith(prefix)).sort();
    if (delimiter) {
      const prefixes = new Set();
      const objects = [];
      for (const key of all) {
        const rest = key.slice(prefix.length);
        const i = rest.indexOf(delimiter);
        if (i >= 0) prefixes.add(prefix + rest.slice(0, i + 1)); else objects.push({ key });
      }
      return { objects, delimitedPrefixes: [...prefixes], truncated: false };
    }
    return { objects: all.map((key) => ({ key })), truncated: false };
  },
  async delete(keys) {
    for (const key of Array.isArray(keys) ? keys : [keys]) {
      this.keys.delete(key);
      rmSync(join(out, key), { force: true });
    }
  },
};

// D1 stand-in over node:sqlite
const sqlite = new DatabaseSync(":memory:");
sqlite.exec(readFileSync(join(here, "..", "schema.sql"), "utf8"));
const db = {
  prepare(sql) {
    return {
      bind(...args) {
        const stmt = sqlite.prepare(sql);
        return {
          sql,
          args,
          async all() { return { results: stmt.all(...args) }; },
          async run() { return stmt.run(...args); },
        };
      },
    };
  },
  async batch(statements) {
    for (const s of statements) await s.run();
    return [];
  },
};

const env = { INGEST_KEY: "test-key", DATA: bucket, DB: db };
const call = (method, path, body, key = "test-key") =>
  worker.fetch(new Request("https://collector.test" + path, {
    method, headers: { "X-PhotoMesh-Key": key, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined,
  }), env);

// A 1×1 JPEG so the image files are real pictures.
const tinyJPEG = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=";
const now = new Date();
const iso = (minutesAgo) => new Date(now.getTime() - minutesAgo * 60000).toISOString();
const circuit = (r2 = 220) => ({
  components: [
    { id: "V1", kind: "voltage_source", value: 12, nodeA: "a", nodeB: "0" },
    { id: "R1", kind: "resistor", value: 100, nodeA: "a", nodeB: "b" },
    { id: "R2", kind: "resistor", value: r2, nodeA: "b", nodeB: "0" },
  ],
  groundNode: "0", meshes: [["V1", "R1", "R2"]], unknowns: [{ kind: "current", element: "R1" }], question: "Find the current.", unsupported: [],
});
const context = { app: "1.0 (109)", os: "18.6", device: "iPhone", locale: "en_US", plus: false, install_days: 3, session: "s1", shares_scans: true };
const ev = (name, minutesAgo, properties = {}) => ({ id: crypto.randomUUID(), timestamp: iso(minutesAgo), name, properties: { ...context, ...properties } });

function picture(installId) {
  return Buffer.concat([Buffer.from(tinyJPEG, "base64"), Buffer.from(installId.slice(0, 4))]).toString("base64");
}

function payload(installId, corrected) {
  return {
    schema: 2, installId, exportedAt: iso(0), context,
    events: [
      ev("app_open", 30), ev("capture", 29),
      ev("recognition", 28, { model: "google/gemini-3.5-flash-lite", tier: "primary", ms: 2400, outcome: corrected ? "doubtful" : "ok", components: 3 }),
      ev("solve", 27, { source: "scan", model: "google/gemini-3.5-flash-lite", components: 3, methods: 3, agree: true, ms: 3100 }),
      ev("steps_opened", 26, { method: "nodal", steps: 6 }), ev("steps_completed", 20, { method: "nodal", steps: 6 }),
      ev("feedback", 19, { helpful: !corrected, reasons: corrected ? "A step is wrong" : "", comment: corrected ? "Sign of I2 looks off" : "", method: "Nodal analysis", netlist: "* Photocircuits\nV1 a 0 12\n" }),
      ev("credits_earned", 19, { reason: "feedback", credits: 2, balance: 12 }),
      ev("survey", 18, { role: "Student", stage: "First circuits course", uses: "Checking homework answers|Learning the method step by step", wish: "AC circuits", nps: 9 }),
      ev("plus_gate", 10, { feature: "lab" }), ev("paywall_shown", 10, { plus: false }),
      ev("app_background", 5, { active_seconds: 1500 }),
    ],
    samples: [
      { id: crypto.randomUUID(), timestamp: iso(28), model: "google/gemini-3.5-flash-lite", recognized: circuit(), corrected: corrected ? circuit(2200) : null,
        accepted: !corrected, imageWidth: 1280, imageHeight: 960, imageBase64: picture(installId),
        diff: corrected ? { added: 0, removed: 0, retyped: 0, revalued: 1, rewired: 0, groundChanged: false, questionChanged: false, unknownsChanged: false, dominant: "revalued" } : null },
    ],
  };
}

let failures = 0;
const check = (cond, what) => { console.log((cond ? "ok   " : "FAIL ") + what); if (!cond) failures++; };

const forbidden = await call("POST", "/", payload("A".repeat(12), false), "wrong");
check(forbidden.status === 403, "wrong key is refused");
const badId = await call("POST", "/", { installId: "x", events: [] });
check(badId.status === 400, "bad install id is refused");

const installs = ["11111111-aaaa-4bbb-8ccc-000000000001", "22222222-aaaa-4bbb-8ccc-000000000002", "33333333-aaaa-4bbb-8ccc-000000000003"];
for (const [i, id] of installs.entries()) {
  const res = await call("POST", "/", payload(id, i !== 0));
  const body = await res.json();
  check(res.status === 200 && body.stored.events === 12 && body.stored.samples === 1, `upload ${i + 1} stored (${JSON.stringify(body.stored)})`);
}
const layout = readdirSync(join(out, "installs", installs[1])).sort();
check(JSON.stringify(layout) === JSON.stringify(["events", "images", "samples"]), "per-install layout: " + layout.join(", "));
const image = readdirSync(join(out, "installs", installs[1], "images"))[0];
check(statSync(join(out, "installs", installs[1], "images", image)).size > 100, "image decoded from base64 (" + image + ")");

const stats = await (await call("GET", "/stats?days=7")).json();
check(stats.indexed && stats.installs.total === 3, `stats: ${stats.installs.total} installs indexed`);
check(stats.samples.total === 3 && stats.samples.corrected === 2, `stats: samples ${JSON.stringify(stats.samples)}`);
check(stats.feedback.total === 3 && stats.feedback.helpful === 1, `stats: feedback ${JSON.stringify(stats.feedback)}`);
check(stats.corrections[0] && stats.corrections[0].dominant === "revalued", "stats: dominant correction kind is revalued");
check(stats.survey[0] && stats.survey[0].role === "Student" && stats.survey[0].nps === 9, "stats: survey by role with NPS");
check(stats.plusFunnel.gates === 3 && stats.plusFunnel.paywall_shown === 3, "stats: plus funnel");
check(stats.daily.length >= 1 && stats.daily[stats.daily.length - 1].solves === 3, "stats: solves per day");

const forgot = await (await call("POST", "/forget", { installId: installs[2] })).json();
const remaining = existsSync(join(out, "installs", installs[2])) ? readdirSync(join(out, "installs", installs[2]), { recursive: true }).filter((f) => statSync(join(out, "installs", installs[2], f)).isFile()) : [];
check(forgot.objects === 3 && remaining.length === 0, `forget removed ${forgot.objects} objects, ${remaining.length} files left`);
const after = await (await call("GET", "/stats?days=7")).json();
check(after.installs.total === 2 && after.samples.total === 2, "forget removed the index rows too");

console.log(failures ? `WORKER TEST FAILURES: ${failures}` : "WORKER TEST OK");
console.log("layout written to " + out);
process.exit(failures ? 1 : 0);
