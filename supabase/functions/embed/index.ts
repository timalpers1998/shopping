// Computes gte-small text embeddings for posts, products, style anchors and brands.
// Called by a database webhook ({table,id}), by pg_cron ({mode:"sweep"}), or ad hoc ({text}).
import { admin, error, isTrusted, json, SUPABASE_URL } from "../_shared/admin.ts";
import { tagPost, taggerEnabled } from "./tagger.ts";

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

/** Posts without style tags get them from Claude first, then the embedding text is rebuilt. */
async function maybeTag(r: Pending): Promise<Pending> {
  if (r.table !== "posts" || !taggerEnabled()) return r;
  const { data: post } = await admin.from("posts").select("caption, category, style_tags, audience").eq("id", r.id).maybeSingle();
  if (!post || (post.style_tags ?? []).length > 0) return r;
  const { data: media } = await admin.from("post_media").select("external_url, thumbnail_url, storage_path").eq("post_id", r.id).order("position").limit(1).maybeSingle();
  const { data: prods } = await admin.from("post_products").select("products(title, brand)").eq("post_id", r.id);
  const imageUrl = media?.external_url ?? media?.thumbnail_url ?? (media?.storage_path ? `${SUPABASE_URL}/storage/v1/object/public/media/${media.storage_path}` : null);
  // deno-lint-ignore no-explicit-any
  const products = (prods ?? []).map((x: any) => x.products ? `${x.products.title} by ${x.products.brand ?? ""}`.trim() : "").filter(Boolean);
  const tags = await tagPost({ imageUrl, caption: post.caption, products, category: post.category });
  if (!tags) return r;
  const update: Record<string, unknown> = { style_tags: tags.style_tags };
  if (post.audience === "unisex" && tags.audience !== "unknown") update.audience = tags.audience;
  await admin.from("posts").update(update).eq("id", r.id);
  const { data: text } = await admin.rpc("post_embedding_text", { p_post_id: r.id });
  return { ...r, text: typeof text === "string" ? text : r.text };
}

async function processRows(rows: Pending[]) {
  const failed: { id: string; error: string }[] = [];
  let processed = 0;
  for (const row of rows) {
    const r = await maybeTag(row);
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

  if (body.mode === "purchases" && typeof body.user_id === "string") {
    const { data: rows, error: pe } = await admin.rpc("pending_purchase_embeddings", { p_user: body.user_id });
    if (pe) return error(500, "pending_failed", pe.message);
    const result = await processRows((rows ?? []) as Pending[]);
    const { data: taste, error: te } = await admin.rpc("apply_purchase_taste", { p_user: body.user_id });
    return json({ ok: !te, mode: "purchases", ...result, taste: te ? te.message : taste });
  }

  const limit = Math.min(Number(body.limit ?? 100), 200);
  const { data, error: e } = await admin.rpc("pending_embeddings", { p_limit: body.table && body.id ? 500 : limit });
  if (e) return error(500, "pending_failed", e.message);
  let rows = (data ?? []) as Pending[];
  if (body.table && body.id) rows = rows.filter((r) => r.table === body.table && r.id === String(body.id));

  const result = await processRows(rows);
  return json({ ok: true, mode: body.mode ?? (body.table ? "webhook" : "sweep"), remaining_hint: rows.length === limit, ...result });
});
