create or replace function public.rp(p_key text) returns real
language sql stable set search_path = public as $$ select value from public.ranking_params where key = p_key $$;

create or replace function public.price_boost(p_user public.price_band, p_post public.price_band) returns real
language sql immutable as $$
  select case
    when p_user is null or p_post is null then 0
    else (case abs(array_position(array['budget','mid','premium','luxury'], p_user::text) - array_position(array['budget','mid','premium','luxury'], p_post::text))
          when 0 then 0.08 when 1 then 0.02 when 2 then -0.05 else -0.10 end)::real end
$$;

-- Builds one ranked batch of post ids for a session, excluding ids already in the snapshot.
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
    select p.id, p.author_id, p.published_at, p.embedding, p.price_band
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
  explore as (
    select b.id, 'explore' as src from base b join public.post_stats s on s.post_id = b.id
    where b.id not in (select id from sim)
      and ((s.likes + 2*s.saves + 2*s.comments + 3*s.click_outs)::float / (s.impressions + 50) > 0.05
           or (b.published_at > now() - interval '14 days' and s.impressions < 50))
    order by random() limit 40
  ),
  cands as (
    select id, bool_and(src = 'explore') as is_explore
    from (select * from sim union all select * from followed union all select * from trending union all select * from explore) u
    group by id
  ),
  scored as (
    select c.id, b.author_id, c.is_explore,
        w_sim * (case when v_q is null then 0 else least(1.0, greatest(0.0, ((1 - (b.embedding <=> v_q)) - sim_floor) / sim_range)) end)
      + w_rec * exp(-extract(epoch from now() - b.published_at) / 3600.0 / tau)
      + w_pop * ln(1 + 10 * greatest(0, (s.likes + 2*s.saves + 2*s.comments + 3*s.click_outs - 0.5*s.hides)::float / (s.impressions + 50)))
      + w_follow * (case when f.author_id is not null then 1 else 0 end)
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

-- Strict "no more than 2 in a row by the same author".
create or replace function public.apply_author_diversity(p_ids uuid[]) returns uuid[]
language plpgsql stable set search_path = public as $$
declare
  v_out uuid[] := '{}'; v_deferred uuid[] := '{}'; v_prev1 uuid; v_prev2 uuid; v_id uuid; v_author uuid; v_authors jsonb;
begin
  select coalesce(jsonb_object_agg(id::text, author_id), '{}'::jsonb) into v_authors from public.posts where id = any(p_ids);
  foreach v_id in array p_ids loop
    v_author := (v_authors ->> v_id::text)::uuid;
    if v_author = v_prev1 and v_author = v_prev2 then
      v_deferred := v_deferred || v_id;
    else
      v_out := v_out || v_id; v_prev2 := v_prev1; v_prev1 := v_author;
    end if;
  end loop;
  return v_out || v_deferred;
end $$;

create or replace function public.get_feed(p_category text, p_session_id uuid, p_cursor text default null, p_limit int default 10) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_offset int := coalesce(nullif(p_cursor, '')::int, 0);
  v_ids uuid[]; v_slice uuid[]; v_new uuid[]; v_items jsonb; v_next text;
  v_ts timestamptz; v_kid uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  if p_category = 'following' then
    if p_cursor is not null and p_cursor <> '' then
      v_ts := split_part(p_cursor, '|', 1)::timestamptz; v_kid := split_part(p_cursor, '|', 2)::uuid;
    end if;
    with page as (
      select p.id, p.published_at from public.posts p
      join public.follows f on f.author_id = p.author_id and f.user_id = v_uid
      where p.status = 'published' and (v_ts is null or (p.published_at, p.id) < (v_ts, v_kid))
      order by p.published_at desc, p.id desc limit p_limit + 1
    ),
    lim as (select * from page order by published_at desc, id desc limit p_limit)
    select coalesce((select jsonb_agg(public.post_card(id, v_uid) order by published_at desc, id desc) from lim), '[]'::jsonb),
           case when (select count(*) from page) > p_limit
             then (select to_char(published_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || id from lim order by published_at asc, id asc limit 1) end
    into v_items, v_next;
    return jsonb_build_object('request_id', 'following', 'items', v_items, 'next_cursor', v_next);
  end if;
  select post_ids into v_ids from public.feed_snapshots
    where user_id = v_uid and session_id = p_session_id and category = p_category;
  if v_ids is null then
    v_ids := public.apply_author_diversity(public.build_feed(p_session_id, p_category, 60, false));
    if coalesce(array_length(v_ids, 1), 0) < p_limit then
      v_ids := public.apply_author_diversity(public.build_feed(p_session_id, p_category, 60, true));
    end if;
    insert into public.feed_snapshots (user_id, session_id, category, post_ids) values (v_uid, p_session_id, p_category, v_ids)
      on conflict (user_id, session_id, category) do update set post_ids = excluded.post_ids, built_at = now();
    v_offset := 0;
  end if;

  if v_offset + p_limit > coalesce(array_length(v_ids, 1), 0) then
    v_new := public.build_feed(p_session_id, p_category, 60, false);
    if coalesce(array_length(v_new, 1), 0) = 0 then
      -- catalog exhausted for this session: allow repeats rather than an empty feed
      v_new := array(select unnest(public.build_feed(p_session_id, p_category, 60, true)) except select unnest(v_ids[greatest(1, v_offset - 20):v_offset + p_limit]));
    end if;
    if coalesce(array_length(v_new, 1), 0) > 0 then
      v_ids := v_ids || public.apply_author_diversity(v_new);
      update public.feed_snapshots set post_ids = v_ids, extended_at = now()
        where user_id = v_uid and session_id = p_session_id and category = p_category;
    end if;
  end if;

  v_slice := v_ids[v_offset + 1 : v_offset + p_limit];
  select coalesce(jsonb_agg(public.post_card(x.id, v_uid) order by x.ord), '[]'::jsonb) into v_items
    from unnest(v_slice) with ordinality as x(id, ord)
    join public.posts p on p.id = x.id and p.status = 'published';
  v_next := case when coalesce(array_length(v_slice, 1), 0) > 0 then (v_offset + array_length(v_slice, 1))::text else null end;
  return jsonb_build_object('request_id', p_session_id::text || ':' || v_offset, 'items', v_items, 'next_cursor', v_next);
end $$;

revoke execute on function public.build_feed(uuid, text, int, boolean), public.apply_author_diversity(uuid[]), public.rp(text) from public;
