-- EWMA taste update for one event.
create or replace function public.apply_taste_update(p_user uuid, p_vec extensions.vector, p_w real, p_alpha real, p_tier text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
declare t vector(384); n int; a real; k real; sv vector(384); sn int; sat timestamptz;
begin
  if p_vec is null or p_w = 0 then return; end if;
  insert into public.user_taste (user_id) values (p_user) on conflict do nothing;
  select taste_vec, signal_count, session_vec, session_signal_count, session_vec_at into t, n, sv, sn, sat
    from public.user_taste where user_id = p_user for update;

  -- long-term vector
  if t is null then
    -- cold start: bootstrap from the w-weighted mean of positive signals once we have enough of them
    update public.user_taste set signal_count = n + 1 where user_id = p_user;
    if p_w > 0 and n + 1 >= 5 then
      select l2_normalize(sum(public.vec_scale(p.embedding, sw.w))) into t
      from public.events e join public.posts p on p.id = e.post_id join public.signal_weights sw on sw.type = e.type
      where e.user_id = p_user and sw.w > 0 and p.embedding is not null;
      if t is not null then update public.user_taste set taste_vec = t where user_id = p_user; end if;
    end if;
  else
    a := case when p_w > 0 then p_alpha * (1 + 1.5 * greatest(0, 20 - n) / 20.0) else least(p_alpha, 0.08) end;
    k := a * p_w / (1 - a);
    t := l2_normalize(t + public.vec_scale(p_vec, k));
    if (n + 1) % 50 = 0 then
      t := coalesce((select l2_normalize(public.vec_scale(t, 0.9) + public.vec_scale(quiz_vec, 0.1)) from public.user_taste where user_id = p_user and quiz_vec is not null), t);
    end if;
    update public.user_taste set taste_vec = t, signal_count = n + 1, updated_at = now() where user_id = p_user;
  end if;

  -- short-term session vector (medium and strong signals only)
  if p_tier in ('medium', 'strong') then
    if sv is null or sat is null or sat < now() - interval '30 minutes' then
      sv := coalesce(t, p_vec); sn := 0;
    end if;
    a := case when p_w > 0 then 0.30 else 0.08 end;
    k := a * p_w / (1 - a);
    sv := l2_normalize(sv + public.vec_scale(p_vec, k));
    update public.user_taste set session_vec = sv, session_vec_at = now(), session_signal_count = sn + 1 where user_id = p_user;
  end if;
end $$;

-- Statement-level trigger: counters, seen table, taste updates for a whole batch.
create or replace function public.trg_events_apply() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  insert into public.post_stats as s (post_id, impressions, skips, likes, saves, comments, click_outs, hides, dwell_ms_sum)
  select post_id,
         count(*) filter (where type in ('impression', 'dwell_short', 'dwell_med', 'dwell_long')),
         count(*) filter (where type = 'skip'),
         count(*) filter (where type = 'like') - count(*) filter (where type = 'unlike'),
         count(*) filter (where type = 'save') - count(*) filter (where type = 'unsave'),
         count(*) filter (where type = 'comment'),
         count(*) filter (where type = 'click_out'),
         count(*) filter (where type = 'hide'),
         coalesce(sum(dwell_ms), 0)
  from new_events where post_id is not null group by post_id
  on conflict (post_id) do update set
    impressions = s.impressions + excluded.impressions, skips = s.skips + excluded.skips,
    likes = greatest(s.likes + excluded.likes, 0), saves = greatest(s.saves + excluded.saves, 0),
    comments = s.comments + excluded.comments, click_outs = s.click_outs + excluded.click_outs,
    hides = s.hides + excluded.hides, dwell_ms_sum = s.dwell_ms_sum + excluded.dwell_ms_sum, updated_at = now();

  update public.posts p set impression_count = p.impression_count + x.n
  from (select post_id, count(*) n from new_events where type in ('impression', 'dwell_short', 'dwell_med', 'dwell_long', 'skip') and post_id is not null group by post_id) x
  where p.id = x.post_id;

  insert into public.user_seen (user_id, post_id, seen_count, last_seen_at)
  select user_id, post_id, count(*), max(created_at) from new_events
  where post_id is not null and type in ('impression', 'dwell_short', 'dwell_med', 'dwell_long', 'skip') group by user_id, post_id
  on conflict (user_id, post_id) do update set seen_count = user_seen.seen_count + excluded.seen_count, last_seen_at = excluded.last_seen_at;

  for r in
    select e.user_id, sw.w, sw.alpha, sw.tier,
           case when e.type in ('follow', 'unfollow') then
                  (select avg(embedding) from (select embedding from public.posts where author_id = e.author_id and embedding is not null order by published_at desc limit 20) z)
                else p.embedding end as emb
    from new_events e
    join public.signal_weights sw on sw.type = e.type
    left join public.posts p on p.id = e.post_id
    where sw.w <> 0
    order by e.created_at, e.id
  loop
    if r.emb is not null then
      perform public.apply_taste_update(r.user_id, l2_normalize(r.emb), r.w, r.alpha, r.tier);
    end if;
  end loop;
  return null;
end $$;

create trigger events_apply after insert on public.events
referencing new table as new_events for each statement execute function public.trg_events_apply();

-- Embedding webhook: ask the edge function to (re)embed a row. Uses pg_net so it never blocks the transaction.
create or replace function public.enqueue_embed() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_url text; v_secret text;
begin
  select value into v_url from public.app_settings where key = 'functions_base_url';
  select value into v_secret from public.app_settings where key = 'embed_webhook_secret';
  if v_url is null or v_secret is null then return null; end if;
  perform net.http_post(
    url := v_url || '/embed',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-embed-secret', v_secret),
    body := jsonb_build_object('table', tg_table_name, 'id', coalesce(new.id::text, new.slug)),
    timeout_milliseconds := 15000);
  return null;
end $$;

create trigger posts_embed after insert or update of caption, style_tags, category, status, embedding_input_hash on public.posts
  for each row when (new.status = 'published' and (new.embedding is null or new.embedding_input_hash is null))
  execute function public.enqueue_embed();
create trigger products_embed after insert or update of title, brand, description on public.products
  for each row when (new.embedding is null or new.embedding_input_hash is null)
  execute function public.enqueue_embed();
create trigger style_anchors_embed after insert or update of anchor_text on public.style_anchors
  for each row when (new.embedding is null) execute function public.enqueue_embed();
create trigger brands_embed after insert or update of anchor_text on public.brands
  for each row when (new.embedding is null) execute function public.enqueue_embed();

-- Rows still waiting for an embedding; used by the sweep.
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
    limit p_limit) x
$$;
revoke execute on function public.pending_embeddings(int) from public, anon, authenticated;

-- Service-role helper the embed function calls to write a vector back.
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
  end if;
end $$;
revoke execute on function public.set_embedding(text, text, text, extensions.vector, text) from public, anon, authenticated;

-- Maintenance jobs
create or replace function public.maintenance_daily() returns void
language sql security definer set search_path = public as $$
  delete from public.feed_snapshots where built_at < now() - interval '24 hours';
  delete from auth.users where is_anonymous and last_sign_in_at < now() - interval '30 days'
    and not exists (select 1 from public.events e where e.user_id = auth.users.id and e.created_at > now() - interval '30 days');
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('feed_maintenance_daily', '0 4 * * *', $cron$select public.maintenance_daily()$cron$);
    perform cron.schedule('feed_embed_sweep', '*/5 * * * *', $cron$
      select net.http_post(
        url := (select value from public.app_settings where key = 'functions_base_url') || '/embed',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-embed-secret', (select value from public.app_settings where key = 'embed_webhook_secret')),
        body := '{"mode":"sweep","limit":100}'::jsonb, timeout_milliseconds := 30000)
      where exists (select 1 from public.app_settings where key = 'functions_base_url')$cron$);
  end if;
end $$;
