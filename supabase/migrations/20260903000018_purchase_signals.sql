-- Purchase-history import: derived rows from the user's order emails (parsed on-device), price band, auto-follows, taste blend.
alter table public.profiles add column if not exists price_band_source text check (price_band_source in ('quiz', 'purchases'));
alter table public.user_taste add column if not exists purchase_vec extensions.vector(384), add column if not exists purchase_vec_at timestamptz;

create table public.purchase_imports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check (provider in ('gmail', 'outlook', 'fixture')),
  account_label text,
  messages_scanned int not null default 0,
  orders_found int not null default 0,
  items_applied int not null default 0,
  created_at timestamptz not null default now()
);
create index purchase_imports_user_idx on public.purchase_imports (user_id, created_at desc);

create table public.purchase_signals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  import_id uuid references public.purchase_imports(id) on delete set null,
  fingerprint text not null,
  merchant text not null,
  brand text,
  title text not null,
  price_cents int,
  currency char(3) not null default 'USD',
  quantity int not null default 1,
  purchased_at timestamptz not null,
  category public.post_category,
  order_kind text not null default 'confirmation',
  extraction text not null default 'heuristic' check (extraction in ('jsonld', 'heuristic', 'scrape', 'llm')),
  confidence real not null default 0.5,
  image_url text,
  product_url text,
  source text not null default 'email',
  embed_text text,
  embedding extensions.vector(384),
  embedding_model text,
  embedding_input_hash text,
  embedded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, fingerprint, title)
);
create index purchase_signals_user_idx on public.purchase_signals (user_id, purchased_at desc);
create index purchase_signals_pending_idx on public.purchase_signals (id) where embedding is null;

alter table public.purchase_imports enable row level security;
alter table public.purchase_signals enable row level security;
create policy "purchase_imports read own" on public.purchase_imports for select using (user_id = auth.uid());
create policy "purchase_signals read own" on public.purchase_signals for select using (user_id = auth.uid());

create or replace function public.purchase_embedding_text(p_id uuid) returns text
language sql stable set search_path = public as $$
  select lower(coalesce(s.category::text, 'fashion') || ' product. ' || s.title || ' by ' || coalesce(s.brand, s.merchant)
    || '. Brands: ' || coalesce(s.brand, s.merchant) || '. Price: ' || coalesce(public.price_band_for_cents(s.price_cents)::text, 'unknown') || '.')
  from public.purchase_signals s where s.id = p_id
$$;

-- Extend the embedding plumbing with purchase rows.
create or replace function public.pending_embeddings(p_limit int default 100) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select 'posts' as "table", id::text as id, public.post_embedding_text(id) as text from public.posts
      where status = 'published' and (embedding is null or embedding_input_hash is distinct from md5(public.post_embedding_text(id)))
    union all
    select 'products', id::text, public.product_embedding_text(id) from public.products
      where embedding is null or embedding_input_hash is distinct from md5(public.product_embedding_text(id))
    union all
    select 'style_anchors', slug, lower(anchor_text) from public.style_anchors where embedding is null
    union all
    select 'brands', id::text, lower(anchor_text) from public.brands where embedding is null
    union all
    select 'purchase_signals', id::text, public.purchase_embedding_text(id) from public.purchase_signals where embedding is null
    limit p_limit) x
$$;

create or replace function public.pending_purchase_embeddings(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('table', 'purchase_signals', 'id', id::text, 'text', public.purchase_embedding_text(id))), '[]'::jsonb)
  from public.purchase_signals where user_id = p_user and embedding is null
$$;
revoke execute on function public.pending_purchase_embeddings(uuid) from public, anon, authenticated;

create or replace function public.set_embedding(p_table text, p_id text, p_text text, p_embedding extensions.vector, p_model text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_table = 'posts' then
    update public.posts set embed_text = p_text, embedding = p_embedding, embedding_model = p_model, embedding_input_hash = md5(p_text), embedded_at = now() where id = p_id::uuid;
  elsif p_table = 'products' then
    update public.products set embed_text = p_text, embedding = p_embedding, embedding_model = p_model, embedding_input_hash = md5(p_text), embedded_at = now() where id = p_id::uuid;
  elsif p_table = 'style_anchors' then
    update public.style_anchors set embedding = p_embedding, embedding_model = p_model, embedding_input_hash = md5(p_text), embedded_at = now() where slug = p_id;
  elsif p_table = 'brands' then
    update public.brands set embedding = p_embedding, embedding_model = p_model, embedding_input_hash = md5(p_text), embedded_at = now() where id = p_id::uuid;
  elsif p_table = 'purchase_signals' then
    update public.purchase_signals set embed_text = p_text, embedding = p_embedding, embedding_model = p_model, embedding_input_hash = md5(p_text), embedded_at = now() where id = p_id::uuid;
  end if;
end $$;

-- Client RPC: store derived purchase rows, set price band, auto-follow brands, kick embedding + taste blend.
create or replace function public.apply_purchase_signals(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid(); v_import uuid; v_n int := 0; v_median int; v_band public.price_band;
  v_followed uuid[] := '{}'; v_url text; v_secret text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if jsonb_array_length(coalesce(p -> 'items', '[]'::jsonb)) > 500 then raise exception 'too_many_items' using errcode = '22023'; end if;

  insert into public.purchase_imports (user_id, provider, account_label, messages_scanned, orders_found)
  values (v_uid, coalesce(p ->> 'provider', 'gmail'), p ->> 'account_label', coalesce((p ->> 'messages_scanned')::int, 0), coalesce((p ->> 'orders_found')::int, 0))
  returning id into v_import;

  with raw as (
    select * from jsonb_to_recordset(coalesce(p -> 'items', '[]'::jsonb)) as r(
      fingerprint text, merchant text, brand text, title text, price_cents int, currency text, quantity int,
      purchased_at timestamptz, category text, order_kind text, extraction text, confidence real, image_url text, product_url text)
  ), ins as (
    insert into public.purchase_signals (user_id, import_id, fingerprint, merchant, brand, title, price_cents, currency, quantity, purchased_at, category, order_kind, extraction, confidence, image_url, product_url)
    select v_uid, v_import, fingerprint, lower(merchant), nullif(trim(brand), ''), left(trim(title), 200), price_cents, coalesce(upper(currency), 'USD'),
           greatest(coalesce(quantity, 1), 1), purchased_at,
           case when category in ('fashion', 'home', 'beauty') then category::public.post_category else null end,
           coalesce(order_kind, 'confirmation'), coalesce(extraction, 'heuristic'), coalesce(confidence, 0.5), image_url, product_url
    from raw
    where fingerprint is not null and title is not null and merchant is not null and purchased_at is not null and purchased_at > now() - interval '3 years'
    on conflict (user_id, fingerprint, title) do update set
      price_cents = coalesce(excluded.price_cents, purchase_signals.price_cents),
      brand = coalesce(excluded.brand, purchase_signals.brand),
      category = coalesce(excluded.category, purchase_signals.category),
      image_url = coalesce(excluded.image_url, purchase_signals.image_url),
      product_url = coalesce(excluded.product_url, purchase_signals.product_url)
    returning 1)
  select count(*) into v_n from ins;
  update public.purchase_imports set items_applied = v_n where id = v_import;

  if coalesce((p ->> 'set_price_band')::boolean, true) then
    if (select count(*) from public.purchase_signals where user_id = v_uid and price_cents between 100 and 2000000 and currency = 'USD') >= 3 then
      select percentile_cont(0.5) within group (order by price_cents)::int into v_median
        from public.purchase_signals where user_id = v_uid and price_cents between 100 and 2000000 and currency = 'USD';
      v_band := public.price_band_for_cents(v_median);
      update public.profiles set price_band = v_band, price_band_source = 'purchases' where id = v_uid;
    end if;
  end if;

  if coalesce((p ->> 'follow_brands')::boolean, true) then
    with wanted as (
      select distinct lower(coalesce(brand, merchant)) as name, lower(merchant) as merchant from public.purchase_signals where user_id = v_uid
    ), matched as (
      select distinct a.id from public.authors a join wanted w on a.kind = 'brand' and a.is_active and (
        lower(a.display_name) = w.name
        or lower(a.handle) = regexp_replace(w.name, '[^a-z0-9]', '', 'g')
        or (a.website_url is not null and regexp_replace(lower(a.website_url), '^https?://(www\.)?', '') like w.merchant || '%')
        or exists (select 1 from public.brands b where b.author_id = a.id and lower(b.name) = w.name))
    ), ins as (
      insert into public.follows (user_id, author_id) select v_uid, id from matched on conflict do nothing returning author_id)
    select coalesce(array_agg(author_id), '{}') into v_followed from ins;
  end if;

  select value into v_url from public.app_settings where key = 'functions_base_url';
  select value into v_secret from public.app_settings where key = 'embed_webhook_secret';
  if v_url is not null and v_secret is not null then
    perform net.http_post(url := v_url || '/embed',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-embed-secret', v_secret),
      body := jsonb_build_object('mode', 'purchases', 'user_id', v_uid), timeout_milliseconds := 30000);
  end if;

  return jsonb_build_object('import_id', v_import, 'items', v_n, 'price_band', v_band, 'followed_author_ids', to_jsonb(v_followed), 'taste_pending', true);
end $$;

-- Service-role: blend the recency-weighted purchase vector into taste. Called by the embed function after vectors are written.
create or replace function public.apply_purchase_taste(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_p vector(384); v_n int;
begin
  select l2_normalize(sum(public.vec_scale(embedding,
           power(0.5, extract(epoch from now() - purchased_at) / (365.0 * 86400)) * least(quantity, 3) * greatest(confidence, 0.3)))),
         count(*)
    into v_p, v_n
    from public.purchase_signals where user_id = p_user and embedding is not null and category is not null;
  if v_p is null then return jsonb_build_object('applied', false); end if;

  insert into public.user_taste (user_id, taste_vec, purchase_vec, purchase_vec_at, signal_count)
  values (p_user, v_p, v_p, now(), least(v_n, 20))
  on conflict (user_id) do update set
    purchase_vec = excluded.purchase_vec, purchase_vec_at = now(),
    taste_vec = case when user_taste.taste_vec is null then excluded.purchase_vec
                     when user_taste.signal_count < 20 then l2_normalize(public.vec_scale(user_taste.taste_vec, 0.4) + public.vec_scale(excluded.purchase_vec, 0.6))
                     else l2_normalize(public.vec_scale(user_taste.taste_vec, 0.7) + public.vec_scale(excluded.purchase_vec, 0.3)) end,
    session_vec = null, session_vec_at = null, session_signal_count = 0,
    signal_count = user_taste.signal_count + least(v_n, 20), updated_at = now();
  delete from public.feed_snapshots where user_id = p_user;
  return jsonb_build_object('applied', true, 'items', v_n);
end $$;
revoke all on function public.apply_purchase_taste(uuid) from public, anon, authenticated;

create or replace function public.delete_purchase_signals() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid(); v_n int;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  delete from public.purchase_signals where user_id = v_uid; get diagnostics v_n = row_count;
  delete from public.purchase_imports where user_id = v_uid;
  update public.profiles set price_band = null, price_band_source = null where id = v_uid and price_band_source = 'purchases';
  update public.user_taste set purchase_vec = null, purchase_vec_at = null, taste_vec = quiz_vec, session_vec = null, session_vec_at = null, updated_at = now() where user_id = v_uid;
  delete from public.feed_snapshots where user_id = v_uid;
  return jsonb_build_object('deleted', v_n);
end $$;

create or replace function public.get_purchase_imports() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'imports', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'provider', provider, 'account_label', account_label, 'items', items_applied, 'created_at', created_at) order by created_at desc)
                         from public.purchase_imports where user_id = auth.uid()), '[]'::jsonb),
    'brands', coalesce((select jsonb_agg(jsonb_build_object('brand', b, 'items', n, 'image_url', img) order by n desc)
                        from (select coalesce(brand, merchant) b, count(*) n, max(image_url) img from public.purchase_signals where user_id = auth.uid() group by 1) x), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'brand', brand, 'merchant', merchant, 'price_cents', price_cents, 'currency', currency,
                        'purchased_at', purchased_at, 'category', category, 'image_url', image_url, 'product_url', product_url) order by purchased_at desc)
                       from (select * from public.purchase_signals where user_id = auth.uid() order by purchased_at desc limit 200) y), '[]'::jsonb),
    'taste_applied', coalesce((select purchase_vec is not null from public.user_taste where user_id = auth.uid()), false),
    'price_band', (select price_band from public.profiles where id = auth.uid()),
    'price_band_source', (select price_band_source from public.profiles where id = auth.uid()))
$$;

-- Anonymous → real account merge carries purchases along.
create or replace function public.merge_anonymous_user(p_anon uuid, p_target uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n_likes int; n_saves int; n_follows int; n_events int; n_comments int; n_purchases int;
begin
  insert into public.likes (user_id, post_id, created_at) select p_target, post_id, created_at from public.likes where user_id = p_anon on conflict do nothing;
  get diagnostics n_likes = row_count;
  insert into public.saves (user_id, post_id, created_at) select p_target, post_id, created_at from public.saves where user_id = p_anon on conflict do nothing;
  get diagnostics n_saves = row_count;
  insert into public.follows (user_id, author_id, created_at) select p_target, author_id, created_at from public.follows where user_id = p_anon on conflict do nothing;
  get diagnostics n_follows = row_count;
  update public.comments set user_id = p_target where user_id = p_anon;
  get diagnostics n_comments = row_count;
  update public.events set user_id = p_target where user_id = p_anon;
  get diagnostics n_events = row_count;
  insert into public.user_seen (user_id, post_id, seen_count, last_seen_at) select p_target, post_id, seen_count, last_seen_at from public.user_seen where user_id = p_anon
    on conflict (user_id, post_id) do update set seen_count = user_seen.seen_count + excluded.seen_count, last_seen_at = greatest(user_seen.last_seen_at, excluded.last_seen_at);
  insert into public.user_quiz_answers (user_id, style_slug, brand_id) select p_target, style_slug, brand_id from public.user_quiz_answers where user_id = p_anon on conflict do nothing;
  update public.purchase_imports set user_id = p_target where user_id = p_anon;
  insert into public.purchase_signals (user_id, import_id, fingerprint, merchant, brand, title, price_cents, currency, quantity, purchased_at, category, order_kind, extraction, confidence, image_url, product_url, embed_text, embedding, embedding_model, embedding_input_hash, embedded_at)
    select p_target, import_id, fingerprint, merchant, brand, title, price_cents, currency, quantity, purchased_at, category, order_kind, extraction, confidence, image_url, product_url, embed_text, embedding, embedding_model, embedding_input_hash, embedded_at
    from public.purchase_signals where user_id = p_anon on conflict do nothing;
  get diagnostics n_purchases = row_count;
  insert into public.user_taste (user_id, taste_vec, quiz_vec, purchase_vec, purchase_vec_at, signal_count)
    select p_target, taste_vec, quiz_vec, purchase_vec, purchase_vec_at, signal_count from public.user_taste where user_id = p_anon
    on conflict (user_id) do update set
      taste_vec = case when user_taste.taste_vec is null then excluded.taste_vec when excluded.taste_vec is null then user_taste.taste_vec
                       else l2_normalize(public.vec_scale(user_taste.taste_vec, 0.5) + public.vec_scale(excluded.taste_vec, 0.5)) end,
      quiz_vec = coalesce(user_taste.quiz_vec, excluded.quiz_vec),
      purchase_vec = coalesce(user_taste.purchase_vec, excluded.purchase_vec),
      purchase_vec_at = coalesce(user_taste.purchase_vec_at, excluded.purchase_vec_at),
      signal_count = user_taste.signal_count + excluded.signal_count;
  update public.profiles t set audience = coalesce(t.audience, a.audience), price_band = coalesce(t.price_band, a.price_band),
    price_band_source = coalesce(t.price_band_source, a.price_band_source), onboarded_at = coalesce(t.onboarded_at, a.onboarded_at)
    from public.profiles a where t.id = p_target and a.id = p_anon;
  return jsonb_build_object('likes', n_likes, 'saves', n_saves, 'follows', n_follows, 'comments', n_comments, 'events', n_events, 'purchases', n_purchases);
end $$;
revoke all on function public.merge_anonymous_user(uuid, uuid) from public, anon, authenticated;
