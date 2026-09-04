// POST { url } → product card fields scraped from the merchant page. Requires a signed-in, non-anonymous user.
import { admin, error, json, userFromRequest } from "../_shared/admin.ts";

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 FeedBot/0.1 (+https://feed.app/bot)";
const TRACKING = /^(utm_|fbclid|gclid|ref$|tag$|_ga|mc_)/;

type Scraped = {
  ok: boolean; canonical_url: string; merchant: string; brand?: string | null; title?: string | null; image_url?: string | null;
  price_cents?: number | null; currency?: string | null; external_id?: string | null; source: string; missing: string[];
};

function canonicalize(raw: string): URL {
  const u = new URL(raw);
  if (!/^https?:$/.test(u.protocol)) throw new Error("invalid_url");
  u.hash = "";
  for (const k of Array.from(u.searchParams.keys())) if (TRACKING.test(k)) u.searchParams.delete(k);
  u.hostname = u.hostname.toLowerCase();
  return u;
}

async function assertPublicHost(host: string) {
  if (/^(localhost|.*\.local|.*\.internal)$/i.test(host)) throw new Error("blocked_host");
  try {
    const addrs = await Deno.resolveDns(host, "A");
    for (const a of addrs) {
      if (/^(10\.|127\.|0\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(a)) throw new Error("blocked_host");
    }
  } catch (e) {
    if ((e as Error).message === "blocked_host") throw e;
  }
}

function merchantOf(host: string) {
  const parts = host.replace(/^www\./, "").split(".");
  const multi = ["co.uk", "com.au", "co.jp", "com.br"];
  const last2 = parts.slice(-2).join(".");
  return multi.includes(last2) ? parts.slice(-3).join(".") : last2;
}

function parsePrice(v: unknown): number | null {
  if (v == null) return null;
  const s = String(v).replace(/[^0-9.,]/g, "").replace(/,(?=\d{3}\b)/g, "");
  const n = parseFloat(s.replace(",", "."));
  return Number.isFinite(n) ? Math.round(n * 100) : null;
}

function meta(html: string, name: string): string | null {
  const re = new RegExp(`<meta[^>]+(?:property|name)=["']${name.replace(/[:.]/g, "\\$&")}["'][^>]*content=["']([^"']+)["']`, "i");
  const re2 = new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["']${name.replace(/[:.]/g, "\\$&")}["']`, "i");
  return html.match(re)?.[1] ?? html.match(re2)?.[1] ?? null;
}

function decode(s: string | null | undefined) {
  return s ? s.replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").trim() : s ?? null;
}

// deno-lint-ignore no-explicit-any
function findProduct(node: any): any | null {
  if (!node || typeof node !== "object") return null;
  if (Array.isArray(node)) { for (const n of node) { const p = findProduct(n); if (p) return p; } return null; }
  const t = node["@type"];
  if (t === "Product" || (Array.isArray(t) && t.includes("Product"))) return node;
  if (node["@graph"]) return findProduct(node["@graph"]);
  return null;
}

async function fetchHtml(u: URL): Promise<string> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const res = await fetch(u, { headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" }, redirect: "follow", signal: ctrl.signal });
    if (!res.ok) throw new Error(`upstream_${res.status}`);
    const ct = res.headers.get("content-type") ?? "";
    if (!ct.includes("html")) throw new Error("not_html");
    const text = await res.text();
    return text.slice(0, 2_000_000);
  } finally { clearTimeout(timer); }
}

async function scrape(raw: string): Promise<Scraped> {
  const u = canonicalize(raw);
  await assertPublicHost(u.hostname);
  const merchant = merchantOf(u.hostname);
  const base: Scraped = { ok: false, canonical_url: u.toString(), merchant, source: "partial", missing: [] };

  // Amazon: ASIN fallback (no price; PA-API / proxy can be added later).
  if (/(^|\.)amazon\./.test(u.hostname) || /(^|\.)(a\.co|amzn\.to)$/.test(u.hostname)) {
    const asin = u.pathname.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/)?.[1] ?? null;
    return { ...base, ok: !!asin, source: "amazon_asin", merchant: "amazon.com", external_id: asin,
      image_url: asin ? `https://images-na.ssl-images-amazon.com/images/P/${asin}.jpg` : null, title: null, price_cents: null, missing: ["title", "price"] };
  }

  // Shopify fast path.
  const handle = u.pathname.match(/\/products\/([a-z0-9-]+)/i)?.[1];
  if (handle) {
    try {
      const r = await fetch(`${u.origin}/products/${handle}.js`, { headers: { "user-agent": UA, accept: "application/json" } });
      if (r.ok) {
        const j = await r.json();
        const img = j.images?.[0] ?? j.featured_image;
        return { ...base, ok: true, source: "shopify", title: j.title ?? null, brand: j.vendor ?? null, price_cents: typeof j.price === "number" ? j.price : parsePrice(j.price),
          currency: "USD", image_url: img ? (img.startsWith("//") ? "https:" + img : img) : null, missing: [] };
      }
    } catch { /* fall through */ }
  }

  const html = await fetchHtml(u);
  let title: string | null = null, image: string | null = null, brand: string | null = null, price: number | null = null, currency: string | null = null, source = "og";

  for (const m of html.matchAll(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {
      const p = findProduct(JSON.parse(m[1].trim()));
      if (p) {
        title = p.name ?? null;
        const im = Array.isArray(p.image) ? p.image[0] : p.image;
        image = typeof im === "string" ? im : im?.url ?? null;
        brand = typeof p.brand === "string" ? p.brand : p.brand?.name ?? null;
        const offer = Array.isArray(p.offers) ? p.offers[0] : p.offers;
        price = parsePrice(offer?.price ?? offer?.lowPrice);
        currency = offer?.priceCurrency ?? null;
        source = "jsonld";
        break;
      }
    } catch { /* ignore bad json */ }
  }
  title ??= decode(meta(html, "og:title")) ?? decode(html.match(/<title[^>]*>([^<]+)<\/title>/i)?.[1]);
  image ??= meta(html, "og:image:secure_url") ?? meta(html, "og:image") ?? meta(html, "twitter:image");
  brand ??= decode(meta(html, "product:brand")) ?? decode(meta(html, "og:site_name"));
  price ??= parsePrice(meta(html, "product:price:amount") ?? meta(html, "og:price:amount") ?? html.match(/itemprop=["']price["'][^>]*content=["']([^"']+)/i)?.[1]);
  currency ??= meta(html, "product:price:currency") ?? meta(html, "og:price:currency") ?? (price != null ? "USD" : null);
  if (image?.startsWith("//")) image = "https:" + image;
  if (image && !/^https?:/.test(image)) image = new URL(image, u).toString();

  const missing = [!title && "title", !image && "image", price == null && "price"].filter(Boolean) as string[];
  return { ...base, ok: !!title, source, title, image_url: image, brand, price_cents: price, currency, missing };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return error(405, "method_not_allowed");
  const user = await userFromRequest(req);
  if (!user || user.is_anonymous) return error(401, "sign_in_required");
  const body = await req.json().catch(() => ({}));
  if (typeof body.url !== "string") return error(400, "invalid_url");

  let canonical: string;
  try { canonical = canonicalize(body.url).toString(); } catch { return error(400, "invalid_url"); }
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical)))).map((b) => b.toString(16).padStart(2, "0")).join("");

  const cached = await admin.from("scrape_cache").select("payload, fetched_at").eq("url_hash", hash).maybeSingle();
  if (cached.data && Date.now() - new Date(cached.data.fetched_at).getTime() < 24 * 3600e3) return json(cached.data.payload);

  try {
    const result = await scrape(body.url);
    if (result.ok) await admin.from("scrape_cache").upsert({ url_hash: hash, url: canonical, payload: result, fetched_at: new Date().toISOString() });
    return json(result, result.ok ? 200 : 422);
  } catch (e) {
    const msg = (e as Error).message ?? "scrape_failed";
    if (msg === "blocked_host") return error(403, "blocked_host");
    if (msg === "invalid_url") return error(400, "invalid_url");
    return json({ ok: false, code: msg.startsWith("upstream_") ? msg : "unscrapable", canonical_url: canonical, merchant: merchantOf(new URL(canonical).hostname), missing: ["title", "image", "price"] }, 422);
  }
});
