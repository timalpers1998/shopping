// Service-role only. Turns an affiliate/product feed (CSV or JSON rows) into a brand author, products and one image post per product.
// POST { network, brand:{handle,display_name,avatar_url?,website_url?}, category, source:{rows:[...]} | {url} | {storage_path}, options:{dry_run?, max_rows?, style_tags?} }
import { parse } from "jsr:@std/csv@1";
import { admin, error, isTrusted, json } from "../_shared/admin.ts";

type Row = Record<string, string>;
const MAPPINGS: Record<string, Record<string, string[]>> = {
  generic: { title: ["title", "name"], description: ["description"], image_url: ["image_url", "image"], price: ["price"], currency: ["currency"], url: ["url", "link"], brand: ["brand"], category: ["category"], external_id: ["external_id", "sku", "id"] },
  rakuten: { title: ["product_name"], description: ["long_description", "short_description"], image_url: ["image_url"], price: ["retail_price", "price"], currency: ["currency"], url: ["product_url"], brand: ["brand"], category: ["primary_category"], external_id: ["sku", "product_id"] },
  impact: { title: ["Name"], description: ["Description"], image_url: ["ImageUrl"], price: ["CurrentPrice"], currency: ["Currency"], url: ["Url"], brand: ["Manufacturer"], category: ["Category"], external_id: ["Id", "Sku"] },
  amazon: { title: ["Title"], description: ["Description"], image_url: ["LargeImage", "ImageUrl"], price: ["Price"], currency: ["Currency"], url: ["DetailPageURL"], brand: ["Brand"], category: ["ProductGroup"], external_id: ["ASIN"] },
};

function pick(row: Row, keys: string[]) { for (const k of keys) { const v = row[k] ?? row[k.toLowerCase()]; if (v != null && String(v).trim() !== "") return String(v).trim(); } return null; }
function toCategory(s: string | null): "fashion" | "home" | "beauty" {
  const t = (s ?? "").toLowerCase();
  if (/home|furniture|decor|kitchen|bed|bath/.test(t)) return "home";
  if (/beauty|skin|makeup|hair|fragrance/.test(t)) return "beauty";
  return "fashion";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return error(405, "method_not_allowed");
  if (!isTrusted(req)) return error(401, "unauthorized");
  const body = await req.json().catch(() => ({}));
  const network = body.network ?? "generic";
  const map = MAPPINGS[network] ?? MAPPINGS.generic;
  const maxRows = Math.min(Number(body.options?.max_rows ?? 5000), 20000);

  let rows: Row[] = [];
  if (body.source?.rows) rows = body.source.rows;
  else if (body.source?.url) {
    const r = await fetch(body.source.url); const text = await r.text();
    rows = body.source.url.endsWith(".json") ? JSON.parse(text) : (parse(text, { skipFirstRow: true }) as Row[]);
  } else if (body.source?.storage_path) {
    const { data, error: e } = await admin.storage.from("ingest").download(body.source.storage_path);
    if (e || !data) return error(400, "source_unreadable", e?.message);
    const text = await data.text();
    rows = body.source.storage_path.endsWith(".json") ? JSON.parse(text) : (parse(text, { skipFirstRow: true }) as Row[]);
  } else return error(400, "missing_source");
  if (rows.length > maxRows) return error(413, "too_many_rows");

  const skipped: { row: number; reason: string }[] = [];
  const products = rows.map((row, i) => {
    const title = pick(row, map.title), url = pick(row, map.url), image = pick(row, map.image_url);
    if (!title || !url || !image) { skipped.push({ row: i, reason: "missing title/url/image" }); return null; }
    const price = pick(row, map.price); const cents = price ? Math.round(parseFloat(price.replace(/[^0-9.]/g, "")) * 100) : null;
    return {
      title, url, image_url: image, description: pick(row, map.description), brand: pick(row, map.brand) ?? body.brand?.display_name,
      price_cents: Number.isFinite(cents) ? cents : null, currency: (pick(row, map.currency) ?? "USD").toUpperCase().slice(0, 3),
      category: body.category ?? toCategory(pick(row, map.category)), external_id: pick(row, map.external_id),
    };
  }).filter(Boolean);

  if (body.options?.dry_run) return json({ ok: true, dry_run: true, rows_read: rows.length, products: products.length, skipped });

  const { data, error: e } = await admin.rpc("ingest_products", {
    p: { network, brand: body.brand, category: body.category ?? "fashion", style_tags: body.options?.style_tags ?? [], products },
  });
  if (e) return error(500, "ingest_failed", e.message);
  return json({ ok: true, rows_read: rows.length, skipped, ...data });
});
