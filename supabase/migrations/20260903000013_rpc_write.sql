create or replace function public.toggle_like(p_post_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_on boolean; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  insert into public.likes (user_id, post_id) values (v_uid, p_post_id) on conflict do nothing;
  if found then v_on := true; else delete from public.likes where user_id = v_uid and post_id = p_post_id; v_on := false; end if;
  insert into public.events (user_id, post_id, author_id, type)
    select v_uid, p_post_id, author_id, case when v_on then 'like' else 'unlike' end::public.event_type from public.posts where id = p_post_id;
  return jsonb_build_object('active', v_on, 'count', (select like_count from public.posts where id = p_post_id));
end $$;

create or replace function public.toggle_save(p_post_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_on boolean; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  insert into public.saves (user_id, post_id) values (v_uid, p_post_id) on conflict do nothing;
  if found then v_on := true; else delete from public.saves where user_id = v_uid and post_id = p_post_id; v_on := false; end if;
  insert into public.events (user_id, post_id, author_id, type)
    select v_uid, p_post_id, author_id, case when v_on then 'save' else 'unsave' end::public.event_type from public.posts where id = p_post_id;
  return jsonb_build_object('active', v_on, 'count', (select save_count from public.posts where id = p_post_id));
end $$;

create or replace function public.toggle_follow(p_author_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_on boolean; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  insert into public.follows (user_id, author_id) values (v_uid, p_author_id) on conflict do nothing;
  if found then v_on := true; else delete from public.follows where user_id = v_uid and author_id = p_author_id; v_on := false; end if;
  insert into public.events (user_id, author_id, type) values (v_uid, p_author_id, case when v_on then 'follow' else 'unfollow' end::public.event_type);
  return jsonb_build_object('active', v_on, 'count', (select follower_count from public.authors where id = p_author_id));
end $$;

create or replace function public.add_comment(p_post_id uuid, p_body text, p_parent_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_uid uuid := auth.uid();
begin
  if not public.is_full_user() then raise exception 'anonymous_not_allowed' using errcode = '42501'; end if;
  insert into public.comments (post_id, user_id, parent_id, body) values (p_post_id, v_uid, p_parent_id, trim(p_body)) returning id into v_id;
  insert into public.events (user_id, post_id, author_id, type) select v_uid, p_post_id, author_id, 'comment' from public.posts where id = p_post_id;
  return public.comment_card(v_id);
end $$;

create or replace function public.delete_comment(p_comment_id uuid) returns void
language sql security definer set search_path = public as $$
  delete from public.comments where id = p_comment_id and user_id = auth.uid()
$$;

-- Batch event ingestion from the app. Derives skip/dwell buckets from `view` events.
create or replace function public.record_events(p_events jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_n int;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if jsonb_array_length(p_events) > 200 then raise exception 'too_many_events' using errcode = '22023'; end if;

  with raw as (
    select * from jsonb_to_recordset(p_events) as r(
      id uuid, type text, occurred_at timestamptz, session_id uuid, post_id uuid, product_id uuid, author_id uuid,
      category text, position int, dwell_ms int, media_index int, click_id uuid)
  ),
  normalized as (
    select
      r.id,
      case
        when r.type = 'view' then
          case when coalesce(r.dwell_ms, 0) < 1000 then 'skip'
               when r.dwell_ms < 3000 then 'impression'
               when r.dwell_ms < 8000 then 'dwell_short'
               when r.dwell_ms < 20000 then 'dwell_med'
               else 'dwell_long' end
        when r.type in ('click_out', 'hide', 'share', 'video_complete', 'carousel_swipe', 'quiz_complete') then r.type
        else null end as type,
      r.occurred_at, r.session_id, r.post_id, r.product_id, r.author_id, r.category, r.position,
      least(greatest(coalesce(r.dwell_ms, 0), 0), 600000) as dwell_ms, r.media_index, r.click_id
    from raw r
  ),
  ins as (
    insert into public.events (client_id, user_id, session_id, post_id, product_id, author_id, type, dwell_ms, position, media_index, click_id, category, client_ts)
    select n.id, v_uid, n.session_id, n.post_id, n.product_id, n.author_id, n.type::public.event_type, n.dwell_ms, n.position, n.media_index, n.click_id, n.category, n.occurred_at
    from normalized n
    where n.type is not null and (n.post_id is null or exists (select 1 from public.posts p where p.id = n.post_id))
    on conflict (client_id) do nothing
    returning 1
  )
  select count(*) into v_n from ins;
  return v_n;
end $$;

-- Composer: create a post with media and products in one transaction.
create or replace function public.create_post(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_author uuid := (p ->> 'author_id')::uuid; v_post uuid := coalesce((p ->> 'id')::uuid, gen_random_uuid());
  m jsonb; pr jsonb; v_product uuid; i int := 0;
begin
  if not public.is_full_user() then raise exception 'anonymous_not_allowed' using errcode = '42501'; end if;
  if not public.is_author_member(v_author) then raise exception 'not_author_member' using errcode = '42501'; end if;

  insert into public.posts (id, author_id, kind, caption, category, audience, style_tags, status, source)
  values (v_post, v_author, (p ->> 'kind')::public.post_kind, coalesce(p ->> 'caption', ''),
          coalesce((p ->> 'category')::public.post_category, 'fashion'), coalesce((p ->> 'audience')::public.audience, 'unisex'),
          coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p -> 'style_tags', '[]'::jsonb)) x), '{}'),
          coalesce((p ->> 'status')::public.post_status, 'published'), 'app');

  for m in select * from jsonb_array_elements(coalesce(p -> 'media', '[]'::jsonb)) loop
    insert into public.post_media (post_id, position, kind, storage_path, external_url, width, height, duration_ms, thumbnail_path)
    values (v_post, coalesce((m ->> 'position')::int, i), (m ->> 'kind')::public.media_kind, m ->> 'storage_path', m ->> 'external_url',
            (m ->> 'width')::int, (m ->> 'height')::int, (m ->> 'duration_ms')::int, m ->> 'thumbnail_path');
    i := i + 1;
  end loop;

  i := 0;
  for pr in select * from jsonb_array_elements(coalesce(p -> 'products', '[]'::jsonb)) loop
    if pr ? 'product_id' then
      v_product := (pr ->> 'product_id')::uuid;
    else
      insert into public.products (merchant, brand, title, image_url, price_cents, currency, url, source_network, category, created_by)
      values (coalesce(pr ->> 'merchant', ''), pr ->> 'brand', pr ->> 'title', pr ->> 'image_url', (pr ->> 'price_cents')::int,
              coalesce(pr ->> 'currency', 'USD'), pr ->> 'url', coalesce(pr ->> 'source_network', 'scrape'),
              coalesce((p ->> 'category')::public.post_category, 'fashion'), v_uid)
      on conflict (url_hash) do update set
        title = coalesce(excluded.title, products.title), image_url = coalesce(excluded.image_url, products.image_url),
        price_cents = coalesce(excluded.price_cents, products.price_cents), brand = coalesce(excluded.brand, products.brand), updated_at = now()
      returning id into v_product;
    end if;
    insert into public.post_products (post_id, product_id, position) values (v_post, v_product, coalesce((pr ->> 'position')::int, i)) on conflict do nothing;
    i := i + 1;
  end loop;

  return public.post_card(v_post, v_uid);
end $$;

create or replace function public.create_creator_author(p_handle text, p_display_name text, p_bio text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_full_user() then raise exception 'anonymous_not_allowed' using errcode = '42501'; end if;
  insert into public.authors (kind, handle, display_name, bio, owner_user_id) values ('creator', lower(p_handle), p_display_name, p_bio, auth.uid()) returning id into v_id;
  return public.author_card(v_id, auth.uid());
end $$;

create or replace function public.submit_quiz(p_audience text, p_price_band text, p_styles text[], p_brand_ids uuid[]) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid(); v_s vector(384); v_b vector(384); v_q vector(384);
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  delete from public.user_quiz_answers where user_id = v_uid;
  insert into public.user_quiz_answers (user_id, style_slug) select v_uid, s from unnest(p_styles) s where exists (select 1 from public.style_anchors a where a.slug = s);
  insert into public.user_quiz_answers (user_id, brand_id) select v_uid, b from unnest(p_brand_ids) b where exists (select 1 from public.brands x where x.id = b);

  select avg(embedding) into v_s from public.style_anchors where slug = any(p_styles) and embedding is not null;
  select avg(embedding) into v_b from public.brands where id = any(p_brand_ids) and embedding is not null;
  if v_s is null and v_b is null then
    v_q := null;
  elsif v_b is null then v_q := l2_normalize(v_s);
  elsif v_s is null then v_q := l2_normalize(v_b);
  else v_q := l2_normalize(public.vec_scale(v_s, 0.7) + public.vec_scale(v_b, 0.3)); end if;

  update public.profiles set audience = nullif(p_audience, 'both')::public.audience, price_band = p_price_band::public.price_band, onboarded_at = now() where id = v_uid;

  if v_q is not null then
    insert into public.user_taste (user_id, taste_vec, quiz_vec, signal_count)
    values (v_uid, v_q, v_q, 0)
    on conflict (user_id) do update set
      quiz_vec = excluded.quiz_vec,
      taste_vec = case when user_taste.taste_vec is null then excluded.quiz_vec
                       else l2_normalize(public.vec_scale(user_taste.taste_vec, 0.5) + public.vec_scale(excluded.quiz_vec, 0.5)) end,
      updated_at = now();
  end if;
  insert into public.events (user_id, type) values (v_uid, 'quiz_complete');
end $$;

create or replace function public.get_quiz_catalog() returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'styles', (select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'label', label, 'image_url', image_url) order by sort_order), '[]'::jsonb) from public.style_anchors where is_active),
    'brands', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'price_band', price_band, 'logo_url', logo_url) order by sort_order, name), '[]'::jsonb) from public.brands where is_active))
$$;
