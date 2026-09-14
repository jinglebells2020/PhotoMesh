# PhotoMesh telemetry collector

Tiny Cloudflare Worker that receives the app's opt-in uploads (usage events and, when the user
allowed it, scan pictures with recognized and corrected netlists) and stores each upload as a
JSON object in an R2 bucket, keyed by day and install id.

```
npm install -g wrangler
wrangler login
wrangler r2 bucket create photomesh-data
wrangler secret put INGEST_KEY        # any long random string
wrangler deploy
```

Put the printed worker URL and the same key into the app: Settings → Privacy & data →
Upload endpoint / key. Uploads happen when the app comes to the foreground and after each
solve, only when there is something pending.

Each stored object matches `Analytics.UploadPayload` in the app:

```json
{
  "installId": "…",
  "exportedAt": "2026-09-14T10:00:00Z",
  "events":  [{ "name": "recognition", "timestamp": "…", "properties": { "model": "…", "ms": 2400, "outcome": "ok" } }],
  "samples": [{ "model": "…", "accepted": false, "recognized": { "components": [] }, "corrected": { "components": [] }, "imageBase64": "…" }]
}
```

The `samples` with a `corrected` circuit are the training/evaluation set: picture in, wrong
netlist, right netlist.
