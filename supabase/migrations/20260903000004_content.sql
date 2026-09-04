create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.authors(id) on delete cascade,
  kind public.post_kind not null,
  caption text not null default '',
  category public.post_category not null default 'fashion',
  audience public.audience not null default 'unisex',
  style_tags text[] not null default '{}',
  price_band public.price_band,
  status public.post_status not null default 'published',
  source text not null default 'app',
  published_at timestamptz,
  like_count int not null default 0,
  save_count int not null default 0,
  comment_count int not null default 0,
  click_count int not null default 0,
  impression_count int not null default 0,
  embed_text text,
  embedding extensions.vector(384),
  embedding_model text,
  embedding_input_hash text,
  embedded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index posts_published_idx on public.posts (published_at desc, id desc) where status = 'published';
create index posts_author_published_idx on public.posts (author_id, published_at desc) where status = 'published';
create index posts_category_published_idx on public.posts (category, published_at desc) where status = 'published';
create index posts_embedding_hnsw on public.posts using hnsw (embedding extensions.vector_cosine_ops) with (m = 16, ef_construction = 64);
create index posts_needs_embedding_idx on public.posts (id) where embedding is null and status = 'published';
create trigger posts_updated_at before update on public.posts for each row execute function public.set_updated_at();

create or replace function public.posts_set_published_at() returns trigger
language plpgsql as $$
begin
  if new.status = 'published' and new.published_at is null then new.published_at = now(); end if;
  return new;
end $$;
create trigger posts_published_at before insert or update of status on public.posts for each row execute function public.posts_set_published_at();

create or replace function public.posts_maintain_author_count() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.status = 'published' then
    update public.authors set post_count = post_count + 1 where id = new.author_id;
  elsif tg_op = 'DELETE' and old.status = 'published' then
    update public.authors set post_count = greatest(post_count - 1, 0) where id = old.author_id;
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
    if new.status = 'published' then update public.authors set post_count = post_count + 1 where id = new.author_id;
    elsif old.status = 'published' then update public.authors set post_count = greatest(post_count - 1, 0) where id = new.author_id; end if;
  end if;
  return coalesce(new, old);
end $$;
create trigger posts_author_count after insert or update of status or delete on public.posts for each row execute function public.posts_maintain_author_count();

create table public.post_media (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  position smallint not null default 0,
  kind public.media_kind not null,
  storage_path text,
  external_url text,
  width int,
  height int,
  duration_ms int,
  thumbnail_path text,
  thumbnail_url text,
  created_at timestamptz not null default now(),
  unique (post_id, position),
  constraint post_media_source check ((storage_path is not null) <> (external_url is not null))
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references public.authors(id) on delete set null,
  merchant text not null,
  brand text,
  title text not null,
  description text,
  image_url text,
  image_path text,
  price_cents int,
  currency char(3) not null default 'USD',
  price_fetched_at timestamptz,
  url text not null,
  url_hash text generated always as (md5(url)) stored,
  external_id text,
  source_network text not null default 'manual',
  category public.post_category,
  in_stock boolean not null default true,
  click_count int not null default 0,
  embed_text text,
  embedding extensions.vector(384),
  embedding_model text,
  embedding_input_hash text,
  embedded_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index products_url_hash_idx on public.products (url_hash);
create unique index products_external_idx on public.products (source_network, merchant, external_id) where external_id is not null;
create index products_author_idx on public.products (author_id);
create index products_merchant_idx on public.products (merchant);
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();

create table public.post_products (
  post_id uuid not null references public.posts(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  position smallint not null default 0,
  primary key (post_id, product_id)
);
create index post_products_product_idx on public.post_products (product_id);

-- price band helper from a median product price
create or replace function public.price_band_for_cents(p_cents int) returns public.price_band
language sql immutable as $$
  select case
    when p_cents is null then null
    when p_cents < 5000 then 'budget'::public.price_band
    when p_cents < 15000 then 'mid'::public.price_band
    when p_cents < 50000 then 'premium'::public.price_band
    else 'luxury'::public.price_band end
$$;

-- Text that gets embedded. Same skeleton for posts, products, anchors and brands.
create or replace function public.post_embedding_text(p_post_id uuid) returns text
language sql stable set search_path = public as $$
  select lower(
    p.category::text || ' post for ' || p.audience::text || '. Style: ' || coalesce(array_to_string(p.style_tags, ', '), '') || '. '
    || left(regexp_replace(p.caption, '(https?://\S+|[#@]\S+)', '', 'g'), 200) || '. Products: '
    || coalesce((select string_agg(pr.title || ' by ' || coalesce(pr.brand, pr.merchant), '; ' order by pp.position)
                 from public.post_products pp join public.products pr on pr.id = pp.product_id where pp.post_id = p.id), '')
    || '. Brands: '
    || coalesce((select string_agg(distinct coalesce(pr.brand, pr.merchant), ', ')
                 from public.post_products pp join public.products pr on pr.id = pp.product_id where pp.post_id = p.id), '')
    || '. Price: ' || coalesce(p.price_band::text, 'unknown') || '.')
  from public.posts p where p.id = p_post_id
$$;

create or replace function public.product_embedding_text(p_product_id uuid) returns text
language sql stable set search_path = public as $$
  select lower(
    coalesce(pr.category::text, 'fashion') || ' product. ' || pr.title || ' by ' || coalesce(pr.brand, pr.merchant) || '. '
    || coalesce(left(pr.description, 120), '') || '. Brands: ' || coalesce(pr.brand, pr.merchant)
    || '. Price: ' || coalesce(public.price_band_for_cents(pr.price_cents)::text, 'unknown') || '.')
  from public.products pr where pr.id = p_product_id
$$;

-- Keep posts.price_band in sync with tagged products (median price).
create or replace function public.posts_refresh_price_band(p_post_id uuid) returns void
language sql set search_path = public as $$
  update public.posts p set price_band = public.price_band_for_cents((
    select percentile_cont(0.5) within group (order by pr.price_cents)::int
    from public.post_products pp join public.products pr on pr.id = pp.product_id
    where pp.post_id = p_post_id and pr.price_cents is not null))
  where p.id = p_post_id
$$;

create or replace function public.post_products_changed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.posts_refresh_price_band(coalesce(new.post_id, old.post_id));
  update public.posts set embedding_input_hash = null where id = coalesce(new.post_id, old.post_id);
  return coalesce(new, old);
end $$;
create trigger post_products_changed after insert or delete on public.post_products for each row execute function public.post_products_changed();
