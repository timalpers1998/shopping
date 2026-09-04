create table public.scrape_cache (
  url_hash text primary key,
  url text not null,
  payload jsonb not null,
  fetched_at timestamptz not null default now()
);
alter table public.scrape_cache enable row level security;

create or replace function public.upsert_product_from_scrape(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_full_user() then raise exception 'anonymous_not_allowed' using errcode = '42501'; end if;
  insert into public.products (merchant, brand, title, image_url, price_cents, currency, url, external_id, source_network, created_by)
  values (coalesce(p ->> 'merchant', ''), p ->> 'brand', coalesce(p ->> 'title', p ->> 'url'), p ->> 'image_url', (p ->> 'price_cents')::int,
          coalesce(p ->> 'currency', 'USD'), p ->> 'url', p ->> 'external_id', coalesce(p ->> 'source_network', 'scrape'), auth.uid())
  on conflict (url_hash) do update set
    title = coalesce(excluded.title, products.title), image_url = coalesce(excluded.image_url, products.image_url),
    price_cents = coalesce(excluded.price_cents, products.price_cents), brand = coalesce(excluded.brand, products.brand), updated_at = now()
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;
