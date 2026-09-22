// Photocircuits telemetry collector: a Cloudflare Worker that receives the app's opt-in uploads
// and files them so they can be queried and turned into a training set.
//
// Routes (everything but GET / needs the X-PhotoMesh-Key header):
//   POST /            an upload from the app: { schema, installId, exportedAt, context, events[], samples[] }
//   POST /forget      { installId }: erase everything stored for that install (the in-app "Delete my shared data")
//   GET  /stats?days=30   counts for a quick look; most of them need the D1 index
//
// R2 layout (binding DATA), one folder per install so a deletion request is one prefix:
//   installs/<installId>/events/<receivedAt>-<uuid>.jsonl   one event per line, install id and receipt time added
//   installs/<installId>/samples/<sampleId>.json            the sample without the picture, plus imageKey and the upload context
//   installs/<installId>/images/<sampleId>.jpg              the picture
//
// Optional D1 index (binding DB, created from schema.sql): installs, events and samples tables so
// accuracy, feedback and funnel numbers are one SQL query away. Without it the objects are still
// stored and tools/dataset/report.py computes the same numbers from the files.

const MAX_BODY = 30 * 1024 * 1024;
const ID = /^[A-Za-z0-9-]{8,64}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    if (request.method === "GET" && path === "/") return text("Photocircuits telemetry collector");
    if (!env.INGEST_KEY || request.headers.get("X-PhotoMesh-Key") !== env.INGEST_KEY) return text("forbidden", 403);
    try {
      if (request.method === "POST" && (path === "/" || path.endsWith("/ingest"))) return await ingest(request, env);
      if (request.method === "POST" && path.endsWith("/forget")) return await forget(request, env);
      if (request.method === "GET" && path.endsWith("/stats")) return await stats(url, env);
    } catch (error) {
      return text("error: " + (error && error.message ? error.message : String(error)), 500);
    }
    return text("not found", 404);
  },
};

// MARK: Ingest

async function ingest(request, env) {
  if (Number(request.headers.get("Content-Length") || 0) > MAX_BODY) return text("too large", 413);
  const body = await request.text();
  if (body.length > MAX_BODY) return text("too large", 413);
  let payload;
  try {
    payload = JSON.parse(body);
  } catch {
    return text("bad json", 400);
  }
  const install = String(payload.installId || "");
  if (!ID.test(install)) return text("bad install id", 400);
  const events = Array.isArray(payload.events) ? payload.events.filter((e) => e && typeof e === "object") : [];
  const samples = Array.isArray(payload.samples) ? payload.samples.filter((s) => s && typeof s === "object") : [];
  const context = payload.context && typeof payload.context === "object" ? payload.context : {};
  const received = new Date().toISOString();
  const stamp = received.replace(/[:.]/g, "-");
  const puts = [];

  if (events.length) {
    const lines = events.map((e) => JSON.stringify({ ...e, installId: install, receivedAt: received }));
    puts.push(env.DATA.put(`installs/${install}/events/${stamp}-${crypto.randomUUID()}.jsonl`, lines.join("\n") + "\n", {
      httpMetadata: { contentType: "application/x-ndjson" },
    }));
  }

  const stored = [];
  for (const sample of samples) {
    const id = String(sample.id || crypto.randomUUID());
    if (!ID.test(id)) continue;
    const { imageBase64, ...rest } = sample;
    let imageKey = null;
    if (typeof imageBase64 === "string" && imageBase64.length > 0) {
      imageKey = `installs/${install}/images/${id}.jpg`;
      puts.push(env.DATA.put(imageKey, decodeBase64(imageBase64), { httpMetadata: { contentType: "image/jpeg" } }));
    }
    const record = { ...rest, id, installId: install, receivedAt: received, imageKey, context };
    puts.push(env.DATA.put(`installs/${install}/samples/${id}.json`, JSON.stringify(record), { httpMetadata: { contentType: "application/json" } }));
    stored.push({ id, record });
  }
  await Promise.all(puts);
  if (env.DB) await index(env.DB, install, context, received, events, stored);
  return json({ stored: { events: events.length, samples: stored.length } });
}

function decodeBase64(base64) {
  const binary = atob(base64.replace(/\s+/g, ""));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// MARK: D1 index

async function index(db, install, context, received, events, samples) {
  const str = (value) => (value == null ? null : String(value));
  const statements = [
    db.prepare(
      `INSERT INTO installs (install_id, first_seen, last_seen, app, os, device, locale, plus, uploads)
       VALUES (?1, ?2, ?2, ?3, ?4, ?5, ?6, ?7, 1)
       ON CONFLICT(install_id) DO UPDATE SET last_seen = excluded.last_seen, app = excluded.app, os = excluded.os,
         device = excluded.device, locale = excluded.locale, plus = excluded.plus, uploads = installs.uploads + 1`
    ).bind(install, received, str(context.app), str(context.os), str(context.device), str(context.locale), context.plus ? 1 : 0),
  ];
  for (const event of events) {
    const ts = typeof event.timestamp === "string" ? event.timestamp : received;
    const props = event.properties && typeof event.properties === "object" ? event.properties : {};
    statements.push(
      db.prepare(`INSERT OR IGNORE INTO events (id, install_id, ts, day, name, app, session, props) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`)
        .bind(String(event.id || crypto.randomUUID()), install, ts, ts.slice(0, 10), String(event.name || "?"), str(props.app), str(props.session), JSON.stringify(props))
    );
  }
  for (const { id, record } of samples) {
    const ts = typeof record.timestamp === "string" ? record.timestamp : received;
    const components = record.recognized && Array.isArray(record.recognized.components) ? record.recognized.components.length : 0;
    statements.push(
      db.prepare(
        `INSERT OR IGNORE INTO samples (id, install_id, ts, day, model, accepted, corrected, components, image_key, diff, dominant)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)`
      ).bind(id, install, ts, ts.slice(0, 10), String(record.model || "?"), record.accepted ? 1 : 0, record.corrected ? 1 : 0, components,
        record.imageKey, record.diff ? JSON.stringify(record.diff) : null, record.diff && record.diff.dominant ? String(record.diff.dominant) : null)
    );
  }
  for (let i = 0; i < statements.length; i += 100) await db.batch(statements.slice(i, i + 100));
}

// MARK: Stats

async function stats(url, env) {
  const days = Math.max(1, Math.min(365, Number(url.searchParams.get("days") || 30)));
  const since = new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);
  if (!env.DB) {
    const installs = await listPrefixes(env.DATA, "installs/");
    return json({ days, indexed: false, installs: installs.length, note: "Bind a D1 database (see README) for event counts, accuracy and feedback rates." });
  }
  const q = async (sql, ...binds) => (await env.DB.prepare(sql).bind(...binds).all()).results;
  const one = async (sql, ...binds) => (await q(sql, ...binds))[0] || {};
  const installs = await one(`SELECT COUNT(*) AS total, SUM(last_seen >= ?1) AS active, SUM(plus) AS plus FROM installs`, since);
  const events = await q(`SELECT name, COUNT(*) AS n FROM events WHERE day >= ?1 GROUP BY name ORDER BY n DESC`, since);
  const daily = await q(
    `SELECT day, SUM(name = 'solve') AS solves, SUM(name = 'recognition') AS recognitions, SUM(name = 'app_open') AS opens,
            COUNT(DISTINCT install_id) AS installs FROM events WHERE day >= ?1 GROUP BY day ORDER BY day`, since);
  const recognition = await q(
    `SELECT json_extract(props, '$.model') AS model, json_extract(props, '$.tier') AS tier, json_extract(props, '$.outcome') AS outcome,
            COUNT(*) AS n, ROUND(AVG(json_extract(props, '$.ms'))) AS avg_ms
     FROM events WHERE name = 'recognition' AND day >= ?1 GROUP BY model, tier, outcome ORDER BY n DESC`, since);
  const samples = await one(`SELECT COUNT(*) AS total, SUM(accepted) AS accepted, SUM(corrected) AS corrected FROM samples WHERE day >= ?1`, since);
  const corrections = await q(`SELECT dominant, COUNT(*) AS n FROM samples WHERE corrected = 1 AND day >= ?1 GROUP BY dominant ORDER BY n DESC`, since);
  const feedback = await one(
    `SELECT COUNT(*) AS total, SUM(json_extract(props, '$.helpful') = 1) AS helpful FROM events WHERE name = 'feedback' AND day >= ?1`, since);
  const feedbackReasons = await q(
    `SELECT json_extract(props, '$.reasons') AS reasons, json_extract(props, '$.method') AS method, COUNT(*) AS n
     FROM events WHERE name = 'feedback' AND json_extract(props, '$.helpful') = 0 AND day >= ?1 GROUP BY reasons, method ORDER BY n DESC LIMIT 12`, since);
  const survey = await q(
    `SELECT json_extract(props, '$.role') AS role, COUNT(*) AS n, ROUND(AVG(json_extract(props, '$.nps')), 1) AS nps FROM events WHERE name = 'survey' GROUP BY role ORDER BY n DESC`);
  const credits = await q(
    `SELECT json_extract(props, '$.reason') AS reason, COUNT(*) AS awards, SUM(json_extract(props, '$.credits')) AS credits
     FROM events WHERE name = 'credits_earned' AND day >= ?1 GROUP BY reason`, since);
  const plusFunnel = await one(
    `SELECT SUM(name = 'plus_gate') AS gates, SUM(name = 'paywall_shown') AS paywall_shown, SUM(name = 'purchase_started') AS started,
            SUM(name = 'purchase_completed') AS completed, SUM(name = 'purchase_failed') AS failed FROM events WHERE day >= ?1`, since);
  const sessions = await one(
    `SELECT COUNT(*) AS n, ROUND(AVG(json_extract(props, '$.active_seconds'))) AS avg_seconds FROM events WHERE name = 'app_background' AND day >= ?1`, since);
  return json({ days, since, indexed: true, installs, events, daily, recognition, samples, corrections, feedback, feedbackReasons, survey, credits, plusFunnel, sessions });
}

// MARK: Forget

async function forget(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return text("bad json", 400);
  }
  const install = String((body && body.installId) || "");
  if (!ID.test(install)) return text("bad install id", 400);
  let deleted = 0;
  let cursor;
  do {
    const page = await env.DATA.list({ prefix: `installs/${install}/`, cursor, limit: 1000 });
    if (page.objects.length) {
      await env.DATA.delete(page.objects.map((o) => o.key));
      deleted += page.objects.length;
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  if (env.DB) {
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM events WHERE install_id = ?1`).bind(install),
      env.DB.prepare(`DELETE FROM samples WHERE install_id = ?1`).bind(install),
      env.DB.prepare(`DELETE FROM installs WHERE install_id = ?1`).bind(install),
    ]);
  }
  return json({ forgotten: install, objects: deleted });
}

// MARK: Helpers

async function listPrefixes(bucket, prefix) {
  const prefixes = [];
  let cursor;
  do {
    const page = await bucket.list({ prefix, delimiter: "/", cursor, limit: 1000 });
    prefixes.push(...(page.delimitedPrefixes || []));
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return prefixes;
}

function text(body, status = 200) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body, null, 2), { status, headers: { "Content-Type": "application/json" } });
}
