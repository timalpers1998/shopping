create table public.redirects (
  id text primary key default public.gen_short_id(8),
  product_id uuid not null references public.products(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  author_id uuid references public.authors(id) on delete set null,
  url text not null,
  network text not null default 'direct',
  affiliate_params jsonb not null default '{}'::jsonb,
  hit_count int not null default 0,
  created_at timestamptz not null default now()
);
create unique index redirects_post_product_idx on public.redirects (post_id, product_id);
create index redirects_product_idx on public.redirects (product_id);

create table public.redirect_hits (
  id bigint generated always as identity primary key,
  redirect_id text not null references public.redirects(id) on delete cascade,
  click_id uuid,
  ip_hash text,
  user_agent text,
  referer text,
  created_at timestamptz not null default now()
);
create index redirect_hits_redirect_idx on public.redirect_hits (redirect_id, created_at desc);

create or replace function public.post_products_create_redirect() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_url text; v_author uuid; v_network text;
begin
  select pr.url, p.author_id, case when pr.source_network in ('amazon', 'rakuten', 'impact') then pr.source_network else 'direct' end
    into v_url, v_author, v_network
  from public.products pr, public.posts p where pr.id = new.product_id and p.id = new.post_id;
  insert into public.redirects (product_id, post_id, author_id, url, network)
  values (new.product_id, new.post_id, v_author, v_url, v_network)
  on conflict (post_id, product_id) do nothing;
  return new;
end $$;
create trigger post_products_redirect after insert on public.post_products for each row execute function public.post_products_create_redirect();

create or replace function public.products_refresh_redirect_url() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.url is distinct from new.url then
    update public.redirects set url = new.url where product_id = new.id;
  end if;
  return new;
end $$;
create trigger products_redirect_url after update of url on public.products for each row execute function public.products_refresh_redirect_url();

-- Called by the redirect edge function with the service role.
create or replace function public.record_redirect_hit(p_redirect_id text, p_ip_hash text, p_ua text, p_click_id uuid default null, p_referer text default null)
returns table (url text, network text, affiliate_params jsonb)
language plpgsql security definer set search_path = public as $$
declare r public.redirects%rowtype;
begin
  select * into r from public.redirects where id = p_redirect_id;
  if not found then return; end if;
  insert into public.redirect_hits (redirect_id, click_id, ip_hash, user_agent, referer) values (r.id, p_click_id, p_ip_hash, p_ua, p_referer);
  update public.redirects set hit_count = hit_count + 1 where id = r.id;
  update public.products set click_count = click_count + 1 where id = r.product_id;
  if r.post_id is not null then update public.posts set click_count = click_count + 1 where id = r.post_id; end if;
  return query select r.url, r.network, r.affiliate_params;
end $$;
revoke all on function public.record_redirect_hit(text, text, text, uuid, text) from public, anon, authenticated;
