# Photocircuits telemetry collector

A Cloudflare Worker that receives the app's opt-in uploads (usage events, feedback, survey answers
and, when the person allowed it, scan pictures with the recognized and corrected netlists) and
files them per install in an R2 bucket, with an optional D1 index for queries.

## Deploy

```
npm install -g wrangler
wrangler login
wrangler r2 bucket create photomesh-data
wrangler secret put INGEST_KEY        # any long random string; the app sends it as X-PhotoMesh-Key
wrangler deploy                        # prints https://photocircuits-telemetry.<account>.workers.dev
```

Recommended, for `GET /stats`:

```
wrangler d1 create photocircuits-telemetry           # paste the database_id into wrangler.toml, uncomment the block
wrangler d1 execute photocircuits-telemetry --remote --file schema.sql
wrangler deploy
```

## Point the app at it

Add two repository secrets on GitHub (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `TELEMETRY_ENDPOINT` | the worker URL, e.g. `https://photocircuits-telemetry.example.workers.dev` |
| `TELEMETRY_KEY` | the same string you gave `wrangler secret put INGEST_KEY` |

Every TestFlight build made after that has the collector baked in (`tools/embed-key.sh --telemetry`
runs in the workflow, the same way the OpenRouter key is embedded). Nothing needs typing on a
device. A developer can still override the endpoint under Settings → Privacy & data → Collected data.

Uploads happen when the app comes to the foreground, after each solve and when it goes to the
background, only when something is pending and only for what the person allowed. Requests are
batched under 6 MB; a failed upload is retried later with a growing pause.

## Routes

| Route | What |
| --- | --- |
| `POST /` | an upload; see `Analytics.UploadPayload` in the app |
| `POST /forget` `{ "installId": "…" }` | erase everything stored for that install; the app's *Delete my shared data* calls it and then starts a new install id |
| `GET /stats?days=30` | installs, events by name, solves per day, recognition outcomes by model, accepted vs corrected scans, correction kinds, feedback helpful rate and reasons, survey by role with NPS, credits by reason, the Plus funnel, average session length |

All but the health check need `X-PhotoMesh-Key`. For example:

```
curl -H "X-PhotoMesh-Key: $KEY" "https://photocircuits-telemetry.example.workers.dev/stats?days=7"
```

## Storage layout

```
installs/<installId>/events/<receivedAt>-<uuid>.jsonl   one event per line (installId and receivedAt added)
installs/<installId>/samples/<sampleId>.json            sample without the picture: model, recognized, corrected, accepted, diff, imageKey, context
installs/<installId>/images/<sampleId>.jpg              the picture (JPEG, longest side ≤ 1280 px)
```

One folder per install keeps a deletion request to a single prefix. `tools/dataset` turns the
`samples` and `images` into a training set and the `events` into a report.

## Test locally

```
node test/run.mjs      # runs the worker in-process against a temp folder and an in-memory SQLite D1 stand-in
```
