-- Public URL for a storage object. Base is stored in app_settings once the project is linked.
create or replace function public.storage_public_url(p_bucket text, p_path text) returns text
language sql stable set search_path = public as $$
  select case when p_path is null then null
    else coalesce((select value from public.app_settings where key = 'public_storage_base'), 'storage:/') || '/' || p_bucket || '/' || p_path end
$$;

create or replace function public.author_card(p_author_id uuid, p_viewer uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', a.id, 'handle', a.handle, 'display_name', a.display_name,
    'avatar_url', coalesce(a.avatar_url, public.storage_public_url('avatars', a.avatar_path)),
    'kind', a.kind, 'is_verified', a.verified, 'bio', a.bio,
    'follower_count', a.follower_count, 'post_count', a.post_count,
    'is_following', exists (select 1 from public.follows f where f.author_id = a.id and f.user_id = p_viewer),
    'is_member', exists (select 1 from public.author_members m where m.author_id = a.id and m.user_id = p_viewer))
  from public.authors a where a.id = p_author_id
$$;

create or replace function public.post_card(p_post_id uuid, p_viewer uuid, p_rank real default null) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'kind', p.kind, 'caption', p.caption, 'created_at', coalesce(p.published_at, p.created_at),
    'category', p.category, 'style_tags', to_jsonb(p.style_tags), 'rank_score', p_rank,
    'author', public.author_card(p.author_id, p_viewer),
    'media', coalesce((select jsonb_agg(jsonb_build_object(
        'id', m.id, 'type', m.kind,
        'url', coalesce(m.external_url, public.storage_public_url('media', m.storage_path)),
        'thumbnail_url', coalesce(m.thumbnail_url, public.storage_public_url('media', m.thumbnail_path)),
        'width', m.width, 'height', m.height,
        'duration_seconds', case when m.duration_ms is null then null else m.duration_ms / 1000.0 end,
        'position', m.position) order by m.position)
      from public.post_media m where m.post_id = p.id), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'title', pr.title,
        'image_url', coalesce(pr.image_url, public.storage_public_url('media', pr.image_path)),
        'price_cents', case when pr.source_network = 'amazon' and (pr.price_fetched_at is null or pr.price_fetched_at < now() - interval '24 hours') then null else pr.price_cents end,
        'currency', pr.currency, 'merchant', pr.merchant, 'brand', pr.brand, 'url', pr.url,
        'redirect_id', (select r.id from public.redirects r where r.post_id = p.id and r.product_id = pr.id),
        'position', pp.position) order by pp.position)
      from public.post_products pp join public.products pr on pr.id = pp.product_id where pp.post_id = p.id), '[]'::jsonb),
    'stats', jsonb_build_object('likes', p.like_count, 'comments', p.comment_count, 'saves', p.save_count),
    'viewer', jsonb_build_object(
      'liked', exists (select 1 from public.likes l where l.post_id = p.id and l.user_id = p_viewer),
      'saved', exists (select 1 from public.saves s where s.post_id = p.id and s.user_id = p_viewer)))
  from public.posts p where p.id = p_post_id
$$;

create or replace function public.get_post(p_post_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  select public.post_card(p.id, auth.uid()) into v from public.posts p
  where p.id = p_post_id and (p.status = 'published' or public.is_author_member(p.author_id));
  if v is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  return v;
end $$;

create or replace function public.get_author_profile(p_author_id uuid default null, p_handle text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from public.authors where (p_author_id is not null and id = p_author_id) or (p_handle is not null and lower(handle) = lower(p_handle)) limit 1;
  if v_id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'author', public.author_card(v_id, auth.uid()),
    'posts', (select coalesce(jsonb_agg(public.post_card(p.id, auth.uid()) order by p.published_at desc, p.id desc), '[]'::jsonb)
              from (select id, published_at from public.posts where author_id = v_id and status = 'published' order by published_at desc, id desc limit 18) p),
    'next_cursor', (select case when count(*) > 18 then (select to_char(published_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || id
                                                              from (select id, published_at from public.posts where author_id = v_id and status = 'published' order by published_at desc, id desc offset 17 limit 1) x)
                    else null end from public.posts where author_id = v_id and status = 'published'));
end $$;

create or replace function public.get_author_posts(p_author_id uuid, p_cursor text default null, p_limit int default 18) returns jsonb
language sql stable security definer set search_path = public as $$
  with cur as (
    select case when p_cursor is null then null else split_part(p_cursor, '|', 1)::timestamptz end as ts,
           case when p_cursor is null then null else split_part(p_cursor, '|', 2)::uuid end as id
  ),
  page as (
    select p.id, p.published_at from public.posts p, cur
    where p.author_id = p_author_id and p.status = 'published' and (cur.ts is null or (p.published_at, p.id) < (cur.ts, cur.id))
    order by p.published_at desc, p.id desc limit p_limit + 1
  ),
  lim as (select * from page order by published_at desc, id desc limit p_limit)
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(public.post_card(id, auth.uid()) order by published_at desc, id desc) from lim), '[]'::jsonb),
    'next_cursor', case when (select count(*) from page) > p_limit
      then (select to_char(published_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || id from lim order by published_at asc, id asc limit 1) end)
$$;

create or replace function public.get_saved_posts(p_cursor text default null, p_limit int default 18) returns jsonb
language sql stable security definer set search_path = public as $$
  with cur as (
    select case when p_cursor is null then null else split_part(p_cursor, '|', 1)::timestamptz end as ts,
           case when p_cursor is null then null else split_part(p_cursor, '|', 2)::uuid end as id
  ),
  page as (
    select s.post_id, s.created_at from public.saves s join public.posts p on p.id = s.post_id, cur
    where s.user_id = auth.uid() and p.status = 'published' and (cur.ts is null or (s.created_at, s.post_id) < (cur.ts, cur.id))
    order by s.created_at desc, s.post_id desc limit p_limit + 1
  ),
  lim as (select * from page order by created_at desc, post_id desc limit p_limit)
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(public.post_card(post_id, auth.uid()) order by created_at desc, post_id desc) from lim), '[]'::jsonb),
    'next_cursor', case when (select count(*) from page) > p_limit
      then (select to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || post_id from lim order by created_at asc, post_id asc limit 1) end)
$$;

create or replace function public.comment_card(p_comment_id uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'post_id', c.post_id, 'text', c.body, 'created_at', c.created_at,
    'author', jsonb_build_object(
      'id', pr.id, 'handle', coalesce(pr.username, 'user_' || left(pr.id::text, 6)),
      'display_name', coalesce(pr.display_name, pr.username, 'User'),
      'avatar_url', public.storage_public_url('avatars', pr.avatar_path), 'kind', 'creator', 'is_verified', false, 'is_following', false))
  from public.comments c join public.profiles pr on pr.id = c.user_id where c.id = p_comment_id
$$;

create or replace function public.get_comments(p_post_id uuid, p_cursor text default null, p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  with cur as (
    select case when p_cursor is null then null else split_part(p_cursor, '|', 1)::timestamptz end as ts,
           case when p_cursor is null then null else split_part(p_cursor, '|', 2)::uuid end as id
  ),
  page as (
    select c.id, c.created_at from public.comments c, cur
    where c.post_id = p_post_id and not c.is_hidden and (cur.ts is null or (c.created_at, c.id) > (cur.ts, cur.id))
    order by c.created_at asc, c.id asc limit p_limit + 1
  ),
  lim as (select * from page order by created_at asc, id asc limit p_limit)
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(public.comment_card(id) order by created_at asc, id asc) from lim), '[]'::jsonb),
    'next_cursor', case when (select count(*) from page) > p_limit
      then (select to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || id from lim order by created_at desc, id desc limit 1) end)
$$;

create or replace function public.get_me() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'username', p.username, 'display_name', p.display_name,
    'avatar_url', public.storage_public_url('avatars', p.avatar_path),
    'is_anonymous', p.is_anonymous, 'onboarded', p.onboarded_at is not null,
    'audience', p.audience, 'price_band', p.price_band, 'following_count', p.following_count,
    'authors', coalesce((select jsonb_agg(public.author_card(m.author_id, p.id)) from public.author_members m where m.user_id = p.id), '[]'::jsonb))
  from public.profiles p where p.id = auth.uid()
$$;

revoke execute on function public.post_card(uuid, uuid, real), public.author_card(uuid, uuid), public.comment_card(uuid), public.storage_public_url(text, text) from public;
