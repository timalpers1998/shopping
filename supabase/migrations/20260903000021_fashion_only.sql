-- Narrow the product to fashion only, and rank creator fits above ingested catalog photos.
-- Reversible on purpose: non-fashion content is hidden, not deleted, and the enum keeps its values.

-- 1. Hide everything that is not fashion, and the authors left with nothing to show.
update public.posts set status = 'hidden' where category <> 'fashion' and status = 'published';
update public.authors a set is_active = false
where a.kind = 'brand'
  and not exists (select 1 from public.posts p where p.author_id = a.id and p.status = 'published');

-- 2. Fits rank above catalog. A "fit" is anything composed in the app (source <> 'ingest'):
--    a creator's outfit photo, or a brand's own styled post. Ingested catalog rows are product shots.
insert into public.ranking_params (key, value, note) values
  ('w_fit', 0.12, 'boost for posts composed in-app (creator fits) over ingested catalog photos')
on conflict (key) do update set value = excluded.value, note = excluded.note;

create or replace function public.build_feed(p_session uuid, p_category text, p_limit int default 60, p_ignore_snapshot boolean default false)
returns uuid[]
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_q vector(384);
  v_audience public.audience;
  v_band public.price_band;
  v_ids uuid[];
  w_sim real := public.rp('w_sim'); w_rec real := public.rp('w_recency'); tau real := public.rp('tau_hours');
  w_pop real := public.rp('w_pop'); w_follow real := public.rp('w_follow'); seen_pen real := public.rp('seen_penalty');
  sim_floor real := public.rp('sim_floor'); sim_range real := public.rp('sim_range'); auth_pen real := public.rp('author_penalty');
  blend real := public.rp('session_blend'); every int := public.rp('explore_every')::int;
  w_fit real := coalesce(public.rp('w_fit'), 0);
begin
  select p.audience, p.price_band into v_audience, v_band from public.profiles p where p.id = v_uid;
  select case when t.session_vec is not null and t.session_vec_at > now() - interval '30 minutes' and t.session_signal_count >= 3
              then l2_normalize(public.vec_scale(t.taste_vec, 1 - blend) + public.vec_scale(t.session_vec, blend))
              else t.taste_vec end
    into v_q from public.user_taste t where t.user_id = v_uid;

  set local hnsw.ef_search = 100;

  with already as (
    select unnest(post_ids) as id from public.feed_snapshots
    where not p_ignore_snapshot and user_id = v_uid and session_id = p_session and category = p_category
  ),
  base as (
    select p.id, p.author_id, p.published_at, p.embedding, p.price_band, p.source
    from public.posts p
    where p.status = 'published' and p.embedding is not null
      and (p_category = 'for_you' or p.category::text = p_category)
      and (v_audience is null or p.audience in (v_audience, 'unisex'))
      and p.id not in (select id from already)
  ),
  sim as (
    select b.id, 'sim' as src from base b where v_q is not null order by b.embedding <=> v_q limit 200
  ),
  followed as (
    select b.id, 'follow' as src from base b
    join public.follows f on f.author_id = b.author_id and f.user_id = v_uid
    where b.published_at > now() - interval '7 days'
    order by b.published_at desc limit 50
  ),
  trending as (
    select b.id, 'trend' as src from base b join public.post_stats s on s.post_id = b.id
    where b.published_at > now() - interval '30 days'
    order by (s.likes + 2*s.saves + 2*s.comments + 3*s.click_outs)::float / (s.impressions + 50) desc, b.published_at desc limit 50
  ),
  -- Fits are scarce next to hundreds of catalog rows, so they get their own candidate pool.
  fits as (
    select b.id, 'fit' as src from base b where b.source <> 'ingest'
    order by b.published_at desc limit 60
  ),
  explore as (
    select b.id, 'explore' as src from base b join public.post_stats s on s.post_id = b.id
    where b.id not in (select id from sim)
      and ((s.likes + 2*s.saves + 2*s.comments + 3*s.click_outs)::float / (s.impressions + 50) > 0.05
           or (b.published_at > now() - interval '14 days' and s.impressions < 50))
    order by random() limit 40
  ),
  cands as (
    select id, bool_and(src = 'explore') as is_explore
    from (select * from sim union all select * from followed union all select * from trending union all select * from fits union all select * from explore) u
    group by id
  ),
  scored as (
    select c.id, b.author_id, c.is_explore,
        w_sim * (case when v_q is null then 0 else least(1.0, greatest(0.0, ((1 - (b.embedding <=> v_q)) - sim_floor) / sim_range)) end)
      + w_rec * exp(-extract(epoch from now() - b.published_at) / 3600.0 / tau)
      + w_pop * ln(1 + 10 * greatest(0, (s.likes + 2*s.saves + 2*s.comments + 3*s.click_outs - 0.5*s.hides)::float / (s.impressions + 50)))
      + w_follow * (case when f.author_id is not null then 1 else 0 end)
      + w_fit * (case when b.source <> 'ingest' then 1 else 0 end)
      + public.price_boost(v_band, b.price_band)
      - seen_pen * least(coalesce(us.seen_count, 0), 2)
      + 1e-6 * (abs(hashtext(coalesce(v_uid::text, '') || p_session::text || b.id::text)) % 1000) as score
    from cands c
    join base b on b.id = c.id
    join public.post_stats s on s.post_id = b.id
    left join public.follows f on f.author_id = b.author_id and f.user_id = v_uid
    left join public.user_seen us on us.user_id = v_uid and us.post_id = b.id and us.last_seen_at > now() - interval '14 days'
  ),
  diversified as (
    select *, score - auth_pen * (row_number() over (partition by author_id order by score desc) - 1) as dscore from scored
  ),
  main as (select id, row_number() over (order by dscore desc) as rn from diversified where not is_explore),
  expl as (select id, row_number() over (order by dscore desc) as rn from diversified where is_explore),
  slots as (
    select id, rn + (rn - 1) / (every - 1) as slot from main
    union all
    select id, rn * every as slot from expl
  )
  select array_agg(id order by slot) into v_ids from (select id, slot from slots order by slot limit p_limit) x;

  return coalesce(v_ids, '{}'::uuid[]);
end $$;
revoke execute on function public.build_feed(uuid, text, int, boolean) from public;

-- 3. Ingest stays fashion-only while the app is narrowed.
create or replace function public.ingest_products(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_author uuid; v_network text := coalesce(p ->> 'network', 'generic'); v_cat public.post_category := coalesce((p ->> 'category')::public.post_category, 'fashion');
  v_tags text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p -> 'style_tags', '[]'::jsonb)) x), '{}');
  pr jsonb; v_product uuid; v_created int := 0; v_updated int := 0; v_posts int := 0; v_existed boolean; v_post uuid; v_merchant text; v_skipped int := 0;
begin
  if v_cat <> 'fashion' then raise exception 'fashion_only' using errcode = '22023'; end if;

  insert into public.authors (kind, handle, display_name, avatar_url, website_url, verified, source_network)
  values ('brand', lower(p -> 'brand' ->> 'handle'), p -> 'brand' ->> 'display_name', p -> 'brand' ->> 'avatar_url', p -> 'brand' ->> 'website_url', true, v_network)
  on conflict ((lower(handle))) do update set display_name = excluded.display_name, avatar_url = coalesce(excluded.avatar_url, authors.avatar_url), is_active = true, updated_at = now()
  returning id into v_author;

  for pr in select * from jsonb_array_elements(coalesce(p -> 'products', '[]'::jsonb)) loop
    if coalesce(pr ->> 'category', 'fashion') <> 'fashion' then v_skipped := v_skipped + 1; continue; end if;
    v_merchant := regexp_replace(lower(split_part(split_part(pr ->> 'url', '://', 2), '/', 1)), '^www\.', '');
    select exists (select 1 from public.products where url_hash = md5(pr ->> 'url')) into v_existed;
    insert into public.products (author_id, merchant, brand, title, description, image_url, price_cents, currency, price_fetched_at, url, external_id, source_network, category)
    values (v_author, v_merchant, pr ->> 'brand', pr ->> 'title', pr ->> 'description', pr ->> 'image_url', (pr ->> 'price_cents')::int, coalesce(pr ->> 'currency', 'USD'), now(),
            pr ->> 'url', pr ->> 'external_id', v_network, 'fashion')
    on conflict (url_hash) do update set title = excluded.title, description = excluded.description, image_url = excluded.image_url,
      price_cents = excluded.price_cents, price_fetched_at = now(), brand = excluded.brand, updated_at = now()
    returning id into v_product;
    if v_existed then v_updated := v_updated + 1; else v_created := v_created + 1; end if;

    if not exists (select 1 from public.post_products pp join public.posts po on po.id = pp.post_id where pp.product_id = v_product and po.source = 'ingest') then
      insert into public.posts (author_id, kind, caption, category, audience, style_tags, status, source, published_at)
      values (v_author, 'image', (pr ->> 'title') || coalesce('. ' || split_part(pr ->> 'description', '. ', 1), ''), 'fashion', 'unisex', v_tags, 'published', 'ingest',
              now() - (random() * interval '14 days'))
      returning id into v_post;
      insert into public.post_media (post_id, position, kind, external_url) values (v_post, 0, 'image', pr ->> 'image_url');
      insert into public.post_products (post_id, product_id, position) values (v_post, v_product, 0);
      v_posts := v_posts + 1;
    end if;
  end loop;
  return jsonb_build_object('brand_author_id', v_author, 'products_created', v_created, 'products_updated', v_updated, 'posts_created', v_posts, 'skipped_non_fashion', v_skipped);
end $$;
revoke all on function public.ingest_products(jsonb) from public, anon, authenticated;
