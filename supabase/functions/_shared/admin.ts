import { createClient } from "@supabase/supabase-js";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
export const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
export const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

export const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

export function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });
}

export function error(status: number, code: string, message?: string) {
  return json({ ok: false, code, message: message ?? code }, status);
}

/** True when the request carries the service-role key or the shared webhook secret. */
export function isTrusted(req: Request, secretEnv = "EMBED_WEBHOOK_SECRET"): boolean {
  const auth = req.headers.get("authorization") ?? "";
  if (auth === `Bearer ${SERVICE_ROLE_KEY}`) return true;
  const secret = Deno.env.get(secretEnv);
  const given = req.headers.get("x-embed-secret") ?? req.headers.get("x-webhook-secret");
  return !!secret && !!given && given === secret;
}

/** Resolves the caller's user from a JWT (anon key + bearer). */
export async function userFromRequest(req: Request) {
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error) return null;
  return data.user;
}
