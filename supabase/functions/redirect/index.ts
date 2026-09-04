// GET /redirect/:id[?c=<click uuid>] → logs the hit, wraps affiliate params, 302s to the merchant.
import { admin } from "../_shared/admin.ts";

function buildOutbound(url: string, network: string, params: Record<string, string>): string {
  const u = new URL(url);
  switch (network) {
    case "amazon":
      if (params.tag) u.searchParams.set("tag", params.tag);
      return u.toString();
    case "rakuten":
      if (params.id && params.mid) return `https://click.linksynergy.com/deeplink?id=${encodeURIComponent(params.id)}&mid=${encodeURIComponent(params.mid)}&murl=${encodeURIComponent(u.toString())}`;
      return u.toString();
    case "impact":
      if (params.base) return `${params.base}?u=${encodeURIComponent(u.toString())}`;
      return u.toString();
    default:
      return u.toString();
  }
}

async function sha256(s: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const notFound = () => new Response("<h1>This link has expired.</h1>", { status: 404, headers: { "content-type": "text/html" } });

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const id = url.searchParams.get("id") ?? parts[parts.length - 1];
  if (!id || id === "redirect") return notFound();

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "";
  const day = new Date().toISOString().slice(0, 10);
  const ipHash = await sha256(ip + day + (Deno.env.get("IP_SALT") ?? "feed"));
  const click = url.searchParams.get("c");

  const { data, error } = await admin.rpc("record_redirect_hit", {
    p_redirect_id: id, p_ip_hash: ipHash, p_ua: req.headers.get("user-agent") ?? "",
    p_click_id: click && /^[0-9a-f-]{36}$/i.test(click) ? click : null, p_referer: req.headers.get("referer"),
  });
  if (error || !data || data.length === 0) return notFound();
  const row = data[0] as { url: string; network: string; affiliate_params: Record<string, string> };
  return new Response(null, {
    status: 302,
    headers: { location: buildOutbound(row.url, row.network, row.affiliate_params ?? {}), "cache-control": "no-store", "referrer-policy": "no-referrer-when-downgrade" },
  });
});
