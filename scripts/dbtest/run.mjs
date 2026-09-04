// Validates every migration + seed against an in-process Postgres (PGlite + pgvector) with stubs for Supabase-only bits
// (auth schema, storage schema, pg_net, pg_cron). Then exercises the feed: events → taste → ranking.
// Run: node scripts/dbtest/run.mjs
import { PGlite } from "@electric-sql/pglite";
import { vector } from "@electric-sql/pglite/vector";
import { readdirSync, readFileSync } from "node:fs";

const db = new PGlite({ extensions: { vector } });
const sql = (q, params) => db.query(q, params);
const claims = { uid: null, anon: false };

async function stubs() {
  await db.exec(`
    create schema if not exists auth; create schema if not exists storage; create schema if not exists net; create schema if not exists cron; create schema if not exists extensions;
    create extension if not exists vector;
    create function gen_random_bytes(n int) returns bytea language sql volatile as $$ select decode(string_agg(lpad(to_hex((random()*255)::int),2,'0'),''), 'hex') from generate_series(1,n) $$;
    create function extensions.gen_salt(t text) returns text language sql volatile as $$ select 'salt' $$;
    create function extensions.crypt(p text, s text) returns text language sql immutable as $$ select md5(p || s) $$;
    create table auth.users (id uuid primary key, instance_id uuid, aud text, role text, email text, encrypted_password text, email_confirmed_at timestamptz,
      raw_app_meta_data jsonb, raw_user_meta_data jsonb, created_at timestamptz default now(), updated_at timestamptz default now(), is_anonymous boolean default false, last_sign_in_at timestamptz default now());
    create table auth.identities (id uuid, user_id uuid, provider_id text, provider text, identity_data jsonb, created_at timestamptz, updated_at timestamptz, last_sign_in_at timestamptz, primary key (provider, provider_id));
    create table _claims (uid uuid, is_anon boolean);
    insert into _claims values (null, false);
    create function auth.uid() returns uuid language sql stable as 'select uid from _claims limit 1';
    create function auth.jwt() returns jsonb language sql stable as $$ select jsonb_build_object('sub', uid, 'is_anonymous', is_anon) from _claims limit 1 $$;
    create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (id uuid default gen_random_uuid(), bucket_id text, name text, owner uuid);
    create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'),1)-1] $$;
    create function storage.filename(name text) returns text language sql immutable as $$ select (string_to_array(name, '/'))[array_length(string_to_array(name, '/'),1)] $$;
    create table net._calls (url text, body jsonb, at timestamptz default now());
    create function net.http_post(url text, headers jsonb default '{}', body jsonb default '{}', timeout_milliseconds int default 1000) returns bigint language plpgsql as $$ begin insert into net._calls(url, body) values (url, body); return 1; end $$;
    create table cron._jobs (name text, schedule text, command text);
    create function cron.schedule(name text, schedule text, command text) returns bigint language plpgsql as $$ begin insert into cron._jobs values (name, schedule, command); return 1; end $$;
    create table pg_ext_stub as select 1;
    create role anon; create role authenticated; create role service_role;
  `);
}

function rewrite(s) {
  return s
    .replace(/create extension if not exists (vector|pgcrypto|pg_net) with schema extensions;/g, "")
    .replace(/create extension if not exists pg_cron;/g, "")
    .replace(/extensions\.(vector_cosine_ops|vector|l2_normalize|gen_random_bytes)/g, "$1")
    .replace(/set search_path = public, extensions/g, "set search_path = public")
    .replace(/if exists \(select 1 from pg_extension where extname = 'pg_cron'\)/g, "if true");
}

async function setUser(uid, anon = false) {
  await sql(`update _claims set uid = $1, is_anon = $2`, [uid, anon]);
}

async function main() {
  await stubs();
  const dir = "supabase/migrations";
  for (const f of readdirSync(dir).sort()) {
    const body = rewrite(readFileSync(`${dir}/${f}`, "utf8"));
    try { await db.exec(body); console.log("ok  ", f); }
    catch (e) { console.error("FAIL", f, "\n", e.message); process.exit(1); }
  }
  try { await db.exec(readFileSync("supabase/seed.sql", "utf8")); console.log("ok   seed.sql"); }
  catch (e) { console.error("FAIL seed.sql\n", e.message); process.exit(1); }

  // Fake embeddings: deterministic pseudo-vectors so cosine has structure (posts sharing style tags are closer).
  const tags = (await sql(`select slug from style_anchors order by sort_order`)).rows.map((r) => r.slug);
  const vecFor = (tagList) => {
    const v = new Array(384).fill(0);
    for (const t of tagList) { const i = tags.indexOf(t); if (i >= 0) for (let k = 0; k < 20; k++) v[(i * 20 + k) % 384] += 1; }
    for (let k = 0; k < 384; k++) v[k] += 0.05 * Math.sin(k);
    const n = Math.hypot(...v); return "[" + v.map((x) => (x / n).toFixed(6)).join(",") + "]";
  };
  for (const r of (await sql(`select id, style_tags from posts`)).rows)
    await sql(`select set_embedding('posts', $1, 'x', $2::vector, 'fake')`, [r.id, vecFor(r.style_tags)]);
  for (const r of (await sql(`select slug from style_anchors`)).rows)
    await sql(`select set_embedding('style_anchors', $1, 'x', $2::vector, 'fake')`, [r.slug, vecFor([r.slug])]);
  for (const r of (await sql(`select id, style_tags from brands`)).rows)
    await sql(`select set_embedding('brands', $1, 'x', $2::vector, 'fake')`, [r.id, vecFor(r.style_tags)]);
  const pending = (await sql(`select jsonb_array_length(pending_embeddings(500)) n`)).rows[0].n;
  console.log("pending embeddings after fake fill:", pending, "(products expected)");

  // Anonymous user browses.
  const uid = "11111111-1111-4111-a111-111111111111";
  await sql(`insert into auth.users (id, is_anonymous) values ($1, true)`, [uid]);
  await setUser(uid, true);
  const session = "22222222-2222-4222-a222-222222222222";
  const page1 = (await sql(`select get_feed('for_you', $1, null, 10) f`, [session])).rows[0].f;
  console.log("cold feed items:", page1.items.length, "next:", page1.next_cursor, "first:", page1.items[0]?.caption?.slice(0, 40));
  if (page1.items.length === 0) throw new Error("empty cold feed");
  const page2 = (await sql(`select get_feed('for_you', $1, $2, 10) f`, [session, page1.next_cursor])).rows[0].f;
  const ids1 = page1.items.map((p) => p.id), ids2 = page2.items.map((p) => p.id);
  console.log("page2 items:", ids2.length, "overlap with page1:", ids2.filter((i) => ids1.includes(i)).length);

  // Quiz: minimalist / old money. Expect the feed to lean that way.
  await sql(`select submit_quiz('womens', 'mid', array['minimalist','old_money','scandi'], array[]::uuid[])`);
  const t0 = (await sql(`select taste_vec::text v from user_taste where user_id = $1`, [uid])).rows[0]?.v;
  if (!t0) throw new Error("quiz did not set taste");
  const s2 = "33333333-3333-4333-a333-333333333333";
  const quizFeed = (await sql(`select get_feed('for_you', $1, null, 20) f`, [s2])).rows[0].f;
  const share = (list, tag) => list.filter((p) => p.style_tags.includes(tag)).length;
  console.log("after quiz: minimalist/old_money posts in top 20 =", share(quizFeed.items, "minimalist") + share(quizFeed.items, "old_money"), "streetwear =", share(quizFeed.items, "streetwear"));

  // Like 10 streetwear posts via events + toggle_like.
  const street = (await sql(`select id from posts where 'streetwear' = any(style_tags) or 'gorpcore' = any(style_tags)`)).rows.map((r) => r.id);
  const evs = street.slice(0, 8).map((id, i) => ({ id: `44444444-4444-4444-a444-${String(i).padStart(12, "0")}`, type: "view", occurred_at: new Date().toISOString(), session_id: s2, post_id: id, dwell_ms: 12000, position: i }));
  const n = (await sql(`select record_events($1::jsonb) n`, [JSON.stringify(evs)])).rows[0].n;
  for (const id of street.slice(0, 6)) await sql(`select toggle_like($1)`, [id]);
  const t1 = (await sql(`select taste_vec::text v, signal_count from user_taste where user_id = $1`, [uid])).rows[0];
  const cos = (await sql(`select 1 - ($1::vector <=> $2::vector) c`, [t0, t1.v])).rows[0].c;
  console.log("recorded events:", n, "signals:", t1.signal_count, "cos(taste0, taste1) =", Number(cos).toFixed(3));
  const stats = (await sql(`select impressions, likes, dwell_ms_sum from post_stats where post_id = $1`, [street[0]])).rows[0];
  console.log("post_stats for first streetwear post:", stats);
  const s3 = "55555555-5555-4555-a555-555555555555";
  const feed3 = (await sql(`select get_feed('for_you', $1, null, 20) f`, [s3])).rows[0].f;
  console.log("after likes: streetwear/gorp in top 20 =", share(feed3.items, "streetwear") + share(feed3.items, "gorpcore"), "; liked flags:", feed3.items.filter((p) => p.viewer.liked).length);
  // structural: no 3 consecutive by same author
  let bad = 0; for (let i = 2; i < feed3.items.length; i++) if (feed3.items[i].author.id === feed3.items[i-1].author.id && feed3.items[i].author.id === feed3.items[i-2].author.id) bad++;
  console.log("3-in-a-row author violations:", bad);
  // following feed
  await sql(`select toggle_follow($1)`, [feed3.items[0].author.id]);
  const fl = (await sql(`select get_feed('following', $1, null, 10) f`, [s3])).rows[0].f;
  console.log("following feed items:", fl.items.length, "is_following:", fl.items[0]?.author.is_following);
  // profile + saved + comments (anonymous comment must fail)
  await sql(`select toggle_save($1)`, [feed3.items[0].id]);
  const saved = (await sql(`select get_saved_posts(null, 10) f`)).rows[0].f;
  console.log("saved:", saved.items.length);
  const prof = (await sql(`select get_author_profile($1) f`, [feed3.items[0].author.id])).rows[0].f;
  console.log("profile posts:", prof.posts.length, "handle:", prof.author.handle);
  let anonCommentBlocked = false;
  try { await sql(`select add_comment($1, 'hi')`, [feed3.items[0].id]); } catch { anonCommentBlocked = true; }
  console.log("anonymous comment blocked:", anonCommentBlocked);
  await setUser(uid, false);
  const c = (await sql(`select add_comment($1, 'love this') f`, [feed3.items[0].id])).rows[0].f;
  const cm = (await sql(`select get_comments($1) f`, [feed3.items[0].id])).rows[0].f;
  console.log("comment added:", c.text, "listed:", cm.items.length);
  // redirect
  const rid = feed3.items[0].products[0].redirect_id;
  const hit = (await sql(`select * from record_redirect_hit($1, 'h', 'ua')`, [rid])).rows[0];
  console.log("redirect resolves to:", hit.url.slice(0, 50), "network:", hit.network);
  // webhook stub was called for embeddings
  const calls = (await sql(`select count(*) n from net._calls`)).rows[0].n;
  console.log("pg_net webhook calls (0 expected until app_settings has functions_base_url):", calls);
  // merge anonymous into a real user
  const real = "66666666-6666-4666-a666-666666666666";
  await sql(`insert into auth.users (id, is_anonymous, email) values ($1, false, 'real@example.com')`, [real]);
  const merged = (await sql(`select merge_anonymous_user($1, $2) f`, [uid, real])).rows[0].f;
  console.log("merged:", merged);

  // Purchase-history import
  await setUser(real, false);
  const items = [
    { fingerprint: "f1", merchant: "everlane.com", brand: "Everlane", title: "Organic cotton box-cut tee", price_cents: 3500, purchased_at: new Date(Date.now() - 30*86400e3).toISOString(), category: "fashion", extraction: "jsonld", confidence: 0.95, image_url: "https://x/1.jpg" },
    { fingerprint: "f2", merchant: "everlane.com", brand: "Everlane", title: "The way-high drape pant", price_cents: 11800, purchased_at: new Date(Date.now() - 60*86400e3).toISOString(), category: "fashion", extraction: "jsonld", confidence: 0.95 },
    { fingerprint: "f3", merchant: "everlane.com", brand: "Everlane", title: "Cashmere crewneck", price_cents: 13000, purchased_at: new Date(Date.now() - 200*86400e3).toISOString(), category: "fashion", extraction: "heuristic", confidence: 0.6 },
    { fingerprint: "f4", merchant: "aritzia.com", brand: "Aritzia", title: "Oversized wool blazer", price_cents: 22800, purchased_at: new Date(Date.now() - 10*86400e3).toISOString(), category: "fashion", extraction: "heuristic", confidence: 0.7 },
    { fingerprint: "f5", merchant: "aritzia.com", brand: "Aritzia", title: "Contour tank", price_cents: 4800, purchased_at: new Date(Date.now() - 12*86400e3).toISOString(), category: "fashion", extraction: "heuristic", confidence: 0.7 },
    { fingerprint: "f6", merchant: "bestbuy.com", brand: null, title: "USB-C cable", price_cents: 1500, purchased_at: new Date(Date.now() - 5*86400e3).toISOString(), category: null, extraction: "heuristic", confidence: 0.5 },
  ];
  const applied = (await sql(`select apply_purchase_signals($1::jsonb) f`, [JSON.stringify({ provider: "fixture", account_label: "t•••@gmail.com", messages_scanned: 120, orders_found: 6, items })])).rows[0].f;
  console.log("purchases applied:", applied.items, "price band:", applied.price_band, "followed:", applied.followed_author_ids.length);
  const nowFollows = (await sql(`select count(*) n from follows f join authors a on a.id = f.author_id where f.user_id = $1 and a.handle in ('everlane','aritzia')`, [real])).rows[0].n;
  console.log("follows everlane+aritzia after import:", nowFollows);
  if (applied.items !== 6 || applied.price_band !== "mid" || Number(nowFollows) !== 2) throw new Error("apply_purchase_signals unexpected");
  const pcalls = (await sql(`select body from net._calls where body->>'mode' = 'purchases'`)).rows.length;
  console.log("embed webhook calls for purchases (0 until app_settings set):", pcalls);
  const tBefore = (await sql(`select taste_vec::text v from user_taste where user_id = $1`, [real])).rows[0]?.v;
  for (const r of (await sql(`select id, title from purchase_signals where user_id = $1`, [real])).rows)
    await sql(`select set_embedding('purchase_signals', $1, 'x', $2::vector, 'fake')`, [r.id, vecFor(/tee|pant|crew|tank/.test(r.title) ? ["minimalist"] : ["workwear"])]);
  const pt = (await sql(`select apply_purchase_taste($1) f`, [real])).rows[0].f;
  const tAfter = (await sql(`select taste_vec::text v, purchase_vec is not null pv, signal_count from user_taste where user_id = $1`, [real])).rows[0];
  const c2 = tBefore ? (await sql(`select 1 - ($1::vector <=> $2::vector) c`, [tBefore, tAfter.v])).rows[0].c : null;
  console.log("purchase taste applied:", pt, "purchase_vec set:", tAfter.pv, "cos(before, after) =", c2 == null ? "n/a" : Number(c2).toFixed(3));
  if (!pt.applied || pt.items !== 5) throw new Error("apply_purchase_taste should use the 5 categorized rows");
  const imports = (await sql(`select get_purchase_imports() f`)).rows[0].f;
  console.log("settings view: imports", imports.imports.length, "brands", imports.brands.map((b) => b.brand + ":" + b.items).join(","), "band", imports.price_band, imports.price_band_source);
  const del = (await sql(`select delete_purchase_signals() f`)).rows[0].f;
  const after = (await sql(`select (select count(*) from purchase_signals where user_id = $1) n, (select price_band from profiles where id = $1) band, (select purchase_vec is null from user_taste where user_id = $1) cleared`, [real])).rows[0];
  console.log("deleted:", del.deleted, "remaining:", after.n, "band:", after.band, "purchase_vec cleared:", after.cleared);
  if (Number(after.n) !== 0 || after.band !== null || !after.cleared) throw new Error("delete_purchase_signals incomplete");
  await sql(`insert into app_settings (key, value) values ('functions_base_url', 'http://stub/functions/v1'), ('embed_webhook_secret', 's') on conflict (key) do update set value = excluded.value`);
  // Catalog ingest (Shopify sample) → brand authors + product posts, visible in the feed once embedded
  const sample = JSON.parse(readFileSync("scripts/shopify-sample.json", "utf8"));
  let created = 0;
  for (const { brand, rows } of sample) {
    const products = rows.map((r) => ({ title: r.title, url: r.url, image_url: r.image_url, description: r.description, brand: r.brand,
      price_cents: Math.round(parseFloat(r.price) * 100), currency: r.currency, category: r.category, external_id: r.external_id }));
    const res = (await sql(`select ingest_products($1::jsonb) f`, [JSON.stringify({ network: "generic", category: rows[0].category,
      brand: { handle: brand.handle, display_name: brand.name, website_url: "https://" + brand.domain }, style_tags: brand.style_tags ?? [], products })])).rows[0].f;
    created += res.posts_created;
  }
  const again = (await sql(`select ingest_products($1::jsonb) f`, [JSON.stringify({ network: "generic", category: "fashion", brand: { handle: sample[0].brand.handle, display_name: sample[0].brand.name },
    products: sample[0].rows.slice(0, 2).map((r) => ({ title: r.title, url: r.url, image_url: r.image_url, brand: r.brand, price_cents: 100, currency: "USD", external_id: r.external_id })) })])).rows[0].f;
  const hooks = (await sql(`select count(*) n from net._calls where body->>'table' in ('posts','products')`)).rows[0].n;
  console.log("ingested posts:", created, "re-run creates:", again.posts_created, "updates:", again.products_updated, "webhook calls:", hooks);
  if (Number(hooks) === 0) throw new Error("embed webhook trigger did not fire");
  if (created < 30 || again.posts_created !== 0 || again.products_updated !== 2) throw new Error("ingest_products unexpected");
  const beauty = (await sql(`select count(*) n from posts where category = 'beauty' and source = 'ingest'`)).rows[0].n;
  for (const r of (await sql(`select id, style_tags from posts where source = 'ingest' and embedding is null`)).rows)
    await sql(`select set_embedding('posts', $1, 'x', $2::vector, 'fake')`, [r.id, vecFor(r.style_tags.length ? r.style_tags : ["minimalist"])]);
  const s4 = "77777777-7777-4777-a777-777777777777";
  const bf = (await sql(`select get_feed('beauty', $1, null, 10) f`, [s4])).rows[0].f;
  const ff = (await sql(`select get_feed('for_you', $1, null, 30) f`, [s4])).rows[0].f;
  let runs = 0; for (let i = 3; i < ff.items.length; i++) if (ff.items[i].kind === ff.items[i-1].kind && ff.items[i].kind === ff.items[i-2].kind && ff.items[i].kind === ff.items[i-3].kind) runs++;
  console.log("beauty posts ingested:", beauty, "beauty feed:", bf.items.length, "for_you w/ ingest:", ff.items.length, "4-in-a-row same format:", runs);
  if (Number(beauty) === 0 || bf.items.length === 0) throw new Error("beauty feed should be populated by ingest");
  const sr = (await sql(`select search_posts('camel coat') f`)).rows[0].f;
  const sr2 = (await sql(`select search_posts('lululemon pant') f`)).rows[0].f;
  const tr = (await sql(`select trending_products(12) f`)).rows[0].f;
  console.log("search 'camel coat':", sr.items.length, "first:", sr.items[0]?.caption?.slice(0, 40), "| 'lululemon pant':", sr2.items.length, "| trending:", tr.length);
  if (sr.items.length === 0 || sr2.items.length === 0 || tr.length === 0) throw new Error("search/trending empty");
  console.log("\nALL DB CHECKS PASSED");
}
main().catch((e) => { console.error("FAILED:", e.message); process.exit(1); });
