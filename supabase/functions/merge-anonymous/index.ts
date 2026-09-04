// After a real sign-in, move the previous anonymous user's activity onto the new account and delete the anonymous user.
// POST { anon_access_token } with the NEW user's JWT in Authorization.
import { admin, error, json, userFromRequest } from "../_shared/admin.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return error(405, "method_not_allowed");
  const target = await userFromRequest(req);
  if (!target || target.is_anonymous) return error(401, "sign_in_required");
  const body = await req.json().catch(() => ({}));
  if (typeof body.anon_access_token !== "string") return error(400, "missing_token");

  const { data: anonData, error: anonErr } = await admin.auth.getUser(body.anon_access_token);
  if (anonErr || !anonData.user || !anonData.user.is_anonymous) return error(400, "invalid_anonymous_token");
  const anonId = anonData.user.id;
  if (anonId === target.id) return json({ ok: true, merged: false });

  const { data, error: mergeErr } = await admin.rpc("merge_anonymous_user", { p_anon: anonId, p_target: target.id });
  if (mergeErr) return error(500, "merge_failed", mergeErr.message);
  const { error: delErr } = await admin.auth.admin.deleteUser(anonId);
  return json({ ok: true, merged: true, moved: data, anonymous_deleted: !delErr });
});
