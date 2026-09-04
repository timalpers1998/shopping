-- Extensions and shared helpers.
create extension if not exists vector with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- updated_at maintenance
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- 8-char base62 id for redirects
create or replace function public.gen_short_id(p_len int default 8) returns text
language plpgsql volatile as $$
declare
  chars text := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  out text := '';
  bytes bytea := extensions.gen_random_bytes(p_len);
  i int;
begin
  for i in 0..p_len-1 loop
    out := out || substr(chars, (get_byte(bytes, i) % 62) + 1, 1);
  end loop;
  return out;
end $$;

-- scalar multiply for vectors (pgvector has no scalar operator)
create or replace function public.vec_scale(v extensions.vector, k double precision) returns extensions.vector
language sql immutable strict as $$
  select (array_agg(x * k order by ord))::real[]::extensions.vector
  from unnest(v::real[]) with ordinality as t(x, ord)
$$;

create or replace function public.is_full_user() returns boolean
language sql stable as $$
  select auth.uid() is not null
     and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
$$;
