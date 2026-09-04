// Computes gte-small text embeddings for posts, products, style anchors and brands.
// Called by a database webhook ({table,id}), by pg_cron ({mode:"sweep"}), or ad hoc ({text}).
import { admin, error, isTrusted, json, SUPABASE_URL } from "../_shared/admin.ts";

/** First trusted call after deploy writes the settings the database needs to call back into functions. */
async function ensureSettings() {
  const secret = Deno.env.get("EMBED_WEBHOOK_SECRET");
  const rows = [
    { key: "functions_base_url", value: `${SUPABASE_URL}/functions/v1` },
    { key: "public_storage_base", value: `${SUPABASE_URL}/storage/v1/object/public` },
    ...(secret ? [{ key: "embed_webhook_secret", value: secret }] : []),
  ];
  await admin.from("app_settings").upsert(rows, { onConflict: "key" });
}

const MODEL = "gte-small";
// deno-lint-ignore no-explicit-any
const session = new (globalThis as any).Supabase.ai.Session(MODEL);

async function embed(text: string): Promise<number[]> {
  const out = await session.run(text, { mean_pool: true, normalize: true });
  return Array.from(out as Float32Array | number[]);
}

type Pending = { table: string; id: string; text: string };

async function processRows(rows: Pending[]) {
  const failed: { id: string; error: string }[] = [];
  let processed = 0;
  for (const r of rows) {
    try {
      if (!r.text || r.text.trim().length === 0) continue;
      const vec = await embed(r.text.slice(0, 2000));
      const { error: e } = await admin.rpc("set_embedding", {
        p_table: r.table, p_id: r.id, p_text: r.text, p_embedding: `[${vec.join(",")}]`, p_model: MODEL,
      });
      if (e) throw e;
      processed++;
    } catch (err) {
      failed.push({ id: r.id, error: String((err as Error).message ?? err) });
    }
  }
  return { processed, failed };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return error(405, "method_not_allowed");
  if (!isTrusted(req)) return error(401, "unauthorized");
  const body = await req.json().catch(() => ({}));
  if (body.mode === "sweep" || body.mode === "bootstrap") await ensureSettings();
  if (body.mode === "bootstrap") return json({ ok: true, bootstrapped: true });

  if (typeof body.text === "string") {
    return json({ model: MODEL, embedding: await embed(body.text) });
  }

  const limit = Math.min(Number(body.limit ?? 100), 200);
  const { data, error: e } = await admin.rpc("pending_embeddings", { p_limit: body.table && body.id ? 500 : limit });
  if (e) return error(500, "pending_failed", e.message);
  let rows = (data ?? []) as Pending[];
  if (body.table && body.id) rows = rows.filter((r) => r.table === body.table && r.id === String(body.id));

  const result = await processRows(rows);
  return json({ ok: true, mode: body.mode ?? (body.table ? "webhook" : "sweep"), remaining_hint: rows.length === limit, ...result });
});
