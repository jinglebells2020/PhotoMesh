// PhotoMesh telemetry collector – a Cloudflare Worker that stores each upload as one JSON
// object in an R2 bucket. Deploy: `npm i -g wrangler && wrangler deploy` in this folder after
// creating the bucket (`wrangler r2 bucket create photomesh-data`) and setting the secret
// (`wrangler secret put INGEST_KEY`). Then put the worker URL + key in the app under
// Settings → Privacy & data → Upload endpoint.
export default {
  async fetch(request, env) {
    if (request.method !== "POST") return new Response("PhotoMesh telemetry", { status: 200 });
    if (request.headers.get("X-PhotoMesh-Key") !== env.INGEST_KEY) return new Response("forbidden", { status: 403 });
    const body = await request.text();
    if (body.length > 25 * 1024 * 1024) return new Response("too large", { status: 413 });
    let install = "unknown";
    try { install = (JSON.parse(body).installId || "unknown").replace(/[^A-Za-z0-9-]/g, ""); } catch { return new Response("bad json", { status: 400 }); }
    const day = new Date().toISOString().slice(0, 10);
    const key = `${day}/${install}/${crypto.randomUUID()}.json`;
    await env.DATA.put(key, body, { httpMetadata: { contentType: "application/json" } });
    return new Response(JSON.stringify({ stored: key }), { status: 200, headers: { "Content-Type": "application/json" } });
  },
};
