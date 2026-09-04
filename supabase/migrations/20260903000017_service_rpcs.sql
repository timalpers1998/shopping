-- Service-role-only helpers used by edge functions.

create or replace function public.merge_anonymous_user(p_anon uuid, p_target uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n_likes int; n_saves int; n_follows int; n_events int; n_comments int;
begin
  insert into public.likes (user_id, post_id, created_at) select p_target, post_id, created_at from public.likes where user_id = p_anon on conflict do nothing;
  get diagnostics n_likes = row_count;
  insert into public.saves (user_id, post_id, created_at) select p_target, post_id, created_at from public.saves where user_id = p_anon on conflict do nothing;
  get diagnostics n_saves = row_count;
  insert into public.follows (user_id, author_id, created_at) select p_target, author_id, created_at from public.follows where user_id = p_anon on conflict do nothing;
  get diagnostics n_follows = row_count;
  update public.comments set user_id = p_target where user_id = p_anon;
  get diagnostics n_comments = row_count;
  -- events: plain re-parent (no statement trigger side effects because this is an UPDATE)
  update public.events set user_id = p_target where user_id = p_anon;
  get diagnostics n_events = row_count;
  insert into public.user_seen (user_id, post_id, seen_count, last_seen_at) select p_target, post_id, seen_count, last_seen_at from public.user_seen where user_id = p_anon
    on conflict (user_id, post_id) do update set seen_count = user_seen.seen_count + excluded.seen_count, last_seen_at = greatest(user_seen.last_seen_at, excluded.last_seen_at);
  insert into public.user_quiz_answers (user_id, style_slug, brand_id) select p_target, style_slug, brand_id from public.user_quiz_answers where user_id = p_anon on conflict do nothing;
  -- taste: keep the anonymous vector if the target has none, otherwise blend
  insert into public.user_taste (user_id, taste_vec, quiz_vec, signal_count) select p_target, taste_vec, quiz_vec, signal_count from public.user_taste where user_id = p_anon
    on conflict (user_id) do update set
      taste_vec = case when user_taste.taste_vec is null then excluded.taste_vec when excluded.taste_vec is null then user_taste.taste_vec
                       else l2_normalize(public.vec_scale(user_taste.taste_vec, 0.5) + public.vec_scale(excluded.taste_vec, 0.5)) end,
      quiz_vec = coalesce(user_taste.quiz_vec, excluded.quiz_vec),
      signal_count = user_taste.signal_count + excluded.signal_count;
  update public.profiles t set audience = coalesce(t.audience, a.audience), price_band = coalesce(t.price_band, a.price_band), onboarded_at = coalesce(t.onboarded_at, a.onboarded_at)
    from public.profiles a where t.id = p_target and a.id = p_anon;
  return jsonb_build_object('likes', n_likes, 'saves', n_saves, 'follows', n_follows, 'comments', n_comments, 'events', n_events);
end $$;
revoke all on function public.merge_anonymous_user(uuid, uuid) from public, anon, authenticated;

create or replace function public.ingest_products(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_author uuid; v_network text := coalesce(p ->> 'network', 'generic'); v_cat public.post_category := coalesce((p ->> 'category')::public.post_category, 'fashion');
  v_tags text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p -> 'style_tags', '[]'::jsonb)) x), '{}');
  pr jsonb; v_product uuid; v_created int := 0; v_updated int := 0; v_posts int := 0; v_existed boolean; v_post uuid; v_merchant text;
begin
  insert into public.authors (kind, handle, display_name, avatar_url, website_url, verified, source_network)
  values ('brand', lower(p -> 'brand' ->> 'handle'), p -> 'brand' ->> 'display_name', p -> 'brand' ->> 'avatar_url', p -> 'brand' ->> 'website_url', true, v_network)
  on conflict ((lower(handle))) do update set display_name = excluded.display_name, avatar_url = coalesce(excluded.avatar_url, authors.avatar_url), updated_at = now()
  returning id into v_author;

  for pr in select * from jsonb_array_elements(coalesce(p -> 'products', '[]'::jsonb)) loop
    v_merchant := regexp_replace(lower(split_part(split_part(pr ->> 'url', '://', 2), '/', 1)), '^www\.', '');
    select exists (select 1 from public.products where url_hash = md5(pr ->> 'url')) into v_existed;
    insert into public.products (author_id, merchant, brand, title, description, image_url, price_cents, currency, price_fetched_at, url, external_id, source_network, category)
    values (v_author, v_merchant, pr ->> 'brand', pr ->> 'title', pr ->> 'description', pr ->> 'image_url', (pr ->> 'price_cents')::int, coalesce(pr ->> 'currency', 'USD'), now(),
            pr ->> 'url', pr ->> 'external_id', v_network, coalesce((pr ->> 'category')::public.post_category, v_cat))
    on conflict (url_hash) do update set title = excluded.title, description = excluded.description, image_url = excluded.image_url,
      price_cents = excluded.price_cents, price_fetched_at = now(), brand = excluded.brand, updated_at = now()
    returning id into v_product;
    if v_existed then v_updated := v_updated + 1; else v_created := v_created + 1; end if;

    if not exists (select 1 from public.post_products pp join public.posts po on po.id = pp.post_id where pp.product_id = v_product and po.source = 'ingest') then
      insert into public.posts (author_id, kind, caption, category, audience, style_tags, status, source, published_at)
      values (v_author, 'image', (pr ->> 'title') || coalesce('. ' || split_part(pr ->> 'description', '. ', 1), ''), coalesce((pr ->> 'category')::public.post_category, v_cat), 'unisex', v_tags, 'published', 'ingest',
              now() - (random() * interval '14 days'))
      returning id into v_post;
      insert into public.post_media (post_id, position, kind, external_url) values (v_post, 0, 'image', pr ->> 'image_url');
      insert into public.post_products (post_id, product_id, position) values (v_post, v_product, 0);
      v_posts := v_posts + 1;
    end if;
  end loop;
  return jsonb_build_object('brand_author_id', v_author, 'products_created', v_created, 'products_updated', v_updated, 'posts_created', v_posts);
end $$;
revoke all on function public.ingest_products(jsonb) from public, anon, authenticated;
