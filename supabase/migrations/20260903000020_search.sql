-- Discover: full-text search over posts and products, plus trending products for the empty state.
alter table public.posts add column if not exists search_tsv tsvector
  generated always as (to_tsvector('english', coalesce(caption, '')) || array_to_tsvector(style_tags)) stored;
create index posts_search_idx on public.posts using gin (search_tsv);
alter table public.products add column if not exists search_tsv tsvector
  generated always as (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(brand, '') || ' ' || coalesce(merchant, '') || ' ' || coalesce(description, ''))) stored;
create index products_search_idx on public.products using gin (search_tsv);

create or replace function public.search_posts(p_query text, p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  with q as (select websearch_to_tsquery('english', coalesce(p_query, '')) as tsq),
  hits as (
    select p.id, ts_rank(p.search_tsv, q.tsq) + 0.5 * coalesce((
      select max(ts_rank(pr.search_tsv, q.tsq)) from public.post_products pp join public.products pr on pr.id = pp.product_id where pp.post_id = p.id), 0) as rank
    from public.posts p, q
    where p.status = 'published' and (p.search_tsv @@ q.tsq or exists (
      select 1 from public.post_products pp join public.products pr on pr.id = pp.product_id where pp.post_id = p.id and pr.search_tsv @@ q.tsq))
    order by rank desc, p.published_at desc limit p_limit)
  select jsonb_build_object('items', coalesce((select jsonb_agg(public.post_card(id, auth.uid()) order by rank desc) from hits), '[]'::jsonb))
$$;

create or replace function public.trending_products(p_limit int default 24) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'title', pr.title, 'image_url', pr.image_url, 'price_cents', pr.price_cents, 'currency', pr.currency,
           'merchant', pr.merchant, 'brand', pr.brand, 'url', pr.url, 'post_id', x.post_id, 'redirect_id', x.redirect_id) order by x.score desc), '[]'::jsonb)
  from (
    select pr.id, max(pp.post_id::text)::uuid as post_id, max(r.id) as redirect_id,
           (pr.click_count * 3 + sum(coalesce(p.like_count, 0)) + 2 * sum(coalesce(p.save_count, 0)))::float / greatest(count(*), 1) as score
    from public.products pr
    join public.post_products pp on pp.product_id = pr.id
    join public.posts p on p.id = pp.post_id and p.status = 'published'
    left join public.redirects r on r.product_id = pr.id and r.post_id = pp.post_id
    where pr.image_url is not null
    group by pr.id
    order by score desc, max(p.published_at) desc limit p_limit) x
  join public.products pr on pr.id = x.id
$$;
