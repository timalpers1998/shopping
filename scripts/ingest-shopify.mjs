// Pulls public Shopify product feeds (/products.json) for a list of brands and either
//  (a) prints normalized rows as JSON (--out file.json), or
//  (b) posts them to the hosted ingest-catalog function (--ref <project-ref>, needs EMBED_WEBHOOK_SECRET).
// Usage: node scripts/ingest-shopify.mjs [--out rows.json] [--ref abcd1234] [--limit 60] [--brands scripts/shopify-brands.json]
import { readFileSync, writeFileSync } from "node:fs";

const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith("--") ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith("--") ? all[i + 1] : true] : []).filter(Boolean));
const brands = JSON.parse(readFileSync(args.brands ?? "scripts/shopify-brands.json", "utf8"));
const limit = Number(args.limit ?? 60);
const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 FeedIngest/0.1";

const FASHION = /(dress|jean|denim|coat|jacket|sneaker|shoe|boot|loafer|tee|t-shirt|shirt|blouse|sweater|cardigan|hoodie|pant|trouser|skirt|legging|bra|sock|hat|cap|bag|tote|belt|scarf|blazer|suit|short|jumper|parka|puffer|fleece|sandal|heel|flat|romper|jumpsuit|top|tank|polo|chino|cashmere|linen|wool|knit|crew|zip|vest|slipper|runner|trainer|mule|clog)/i;
const SKIP = /(gift card|e-gift|sample|coverage|protection|warranty|donation|shipping|membership|bundle set of|sock pack)/i;

async function fetchStore(b) {
  const rows = [];
  for (let page = 1; rows.length < limit && page <= 4; page++) {
    const res = await fetch(`https://${b.domain}/products.json?limit=250&page=${page}`, { headers: { "user-agent": UA, accept: "application/json" } });
    if (!res.ok) { console.error(`  ${b.domain}: HTTP ${res.status}`); break; }
    const json = await res.json();
    const products = json.products ?? [];
    if (products.length === 0) break;
    for (const p of products) {
      if (rows.length >= limit) break;
      const img = p.images?.[0]?.src; const v = p.variants?.[0];
      if (!img || !v || SKIP.test(p.title)) continue;
      const text = `${p.title} ${p.product_type ?? ""} ${(p.tags ?? []).join(" ")}`;
      const category = b.category ?? (FASHION.test(text) ? "fashion" : null);
      if (!category) continue;
      const price = Number(v.price);
      if (!Number.isFinite(price) || price <= 0) continue;
      const desc = (p.body_html ?? "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim().slice(0, 300);
      rows.push({
        title: p.title, description: desc, image_url: img.split("?")[0], price: price.toFixed(2), currency: "USD",
        url: `https://${b.domain}/products/${p.handle}`, brand: b.name, category, external_id: String(p.id),
        audience: b.audience ?? "unisex", style_tags: b.style_tags ?? [],
      });
    }
  }
  return rows;
}

const all = [];
for (const b of brands) {
  process.stderr.write(`${b.name} (${b.domain})… `);
  try { const rows = await fetchStore(b); process.stderr.write(`${rows.length} products\n`); all.push({ brand: b, rows }); }
  catch (e) { process.stderr.write(`failed: ${e.message}\n`); }
}

if (args.out) {
  writeFileSync(args.out, JSON.stringify(all, null, 2));
  console.log(`wrote ${all.reduce((n, x) => n + x.rows.length, 0)} rows for ${all.length} brands to ${args.out}`);
}
if (args.ref) {
  const secret = process.env.EMBED_WEBHOOK_SECRET;
  if (!secret) { console.error("EMBED_WEBHOOK_SECRET is required for --ref"); process.exit(1); }
  for (const { brand: b, rows } of all) {
    if (rows.length === 0) continue;
    const res = await fetch(`https://${args.ref}.supabase.co/functions/v1/ingest-catalog`, {
      method: "POST", headers: { "content-type": "application/json", "x-embed-secret": secret },
      body: JSON.stringify({ network: "generic", category: rows[0].category,
        brand: { handle: b.handle, display_name: b.name, avatar_url: b.logo ?? `https://loremflickr.com/200/200/logo?lock=${b.handle.length % 9}`, website_url: `https://${b.domain}` },
        source: { rows }, options: { style_tags: b.style_tags ?? [] } }),
    });
    console.log(b.name, res.status, (await res.text()).slice(0, 200));
  }
}
