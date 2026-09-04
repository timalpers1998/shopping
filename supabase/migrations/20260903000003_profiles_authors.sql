-- profiles: 1:1 with auth.users
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  display_name text,
  avatar_path text,
  is_anonymous boolean not null default true,
  audience public.audience,
  price_band public.price_band,
  onboarded_at timestamptz,
  following_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index profiles_username_idx on public.profiles (lower(username)) where username is not null;
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, is_anonymous, display_name)
  values (new.id, coalesce(new.is_anonymous, false), coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_auth_user();

create or replace function public.handle_auth_user_updated() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set is_anonymous = coalesce(new.is_anonymous, false) where id = new.id;
  return new;
end $$;
create trigger on_auth_user_updated after update of is_anonymous, email on auth.users for each row execute function public.handle_auth_user_updated();

-- authors: creators and brands (both can post)
create table public.authors (
  id uuid primary key default gen_random_uuid(),
  kind public.author_kind not null,
  handle text not null,
  display_name text not null,
  bio text,
  avatar_path text,
  avatar_url text,
  website_url text,
  verified boolean not null default false,
  owner_user_id uuid references public.profiles(id) on delete set null,
  source_network text,
  follower_count int not null default 0,
  post_count int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint authors_handle_format check (handle ~ '^[a-z0-9_.]{2,30}$')
);
create unique index authors_handle_idx on public.authors (lower(handle));
create index authors_owner_idx on public.authors (owner_user_id);
create trigger authors_updated_at before update on public.authors for each row execute function public.set_updated_at();

create table public.author_members (
  author_id uuid not null references public.authors(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.member_role not null default 'editor',
  created_at timestamptz not null default now(),
  primary key (author_id, user_id)
);
create index author_members_user_idx on public.author_members (user_id);

create or replace function public.add_owner_membership() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.owner_user_id is not null then
    insert into public.author_members (author_id, user_id, role) values (new.id, new.owner_user_id, 'owner')
    on conflict do nothing;
  end if;
  return new;
end $$;
create trigger authors_owner_membership after insert on public.authors for each row execute function public.add_owner_membership();

create or replace function public.is_author_member(p_author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.author_members where author_id = p_author and user_id = auth.uid())
$$;
