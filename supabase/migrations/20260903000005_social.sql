create table public.follows (
  user_id uuid not null references public.profiles(id) on delete cascade,
  author_id uuid not null references public.authors(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, author_id)
);
create index follows_author_idx on public.follows (author_id, created_at desc);

create or replace function public.follows_maintain_counts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.authors set follower_count = follower_count + 1 where id = new.author_id;
    update public.profiles set following_count = following_count + 1 where id = new.user_id;
  else
    update public.authors set follower_count = greatest(follower_count - 1, 0) where id = old.author_id;
    update public.profiles set following_count = greatest(following_count - 1, 0) where id = old.user_id;
  end if;
  return coalesce(new, old);
end $$;
create trigger follows_counts after insert or delete on public.follows for each row execute function public.follows_maintain_counts();

create table public.likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index likes_post_idx on public.likes (post_id);

create table public.saves (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index saves_post_idx on public.saves (post_id);
create index saves_user_created_idx on public.saves (user_id, created_at desc);

create or replace function public.likes_maintain_counts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then update public.posts set like_count = like_count + 1 where id = new.post_id;
  else update public.posts set like_count = greatest(like_count - 1, 0) where id = old.post_id; end if;
  return coalesce(new, old);
end $$;
create trigger likes_counts after insert or delete on public.likes for each row execute function public.likes_maintain_counts();

create or replace function public.saves_maintain_counts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then update public.posts set save_count = save_count + 1 where id = new.post_id;
  else update public.posts set save_count = greatest(save_count - 1, 0) where id = old.post_id; end if;
  return coalesce(new, old);
end $$;
create trigger saves_counts after insert or delete on public.saves for each row execute function public.saves_maintain_counts();

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade,
  body text not null check (length(body) between 1 and 1000),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index comments_post_idx on public.comments (post_id, created_at);
create trigger comments_updated_at before update on public.comments for each row execute function public.set_updated_at();

create or replace function public.comments_maintain_counts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and not new.is_hidden then update public.posts set comment_count = comment_count + 1 where id = new.post_id;
  elsif tg_op = 'DELETE' and not old.is_hidden then update public.posts set comment_count = greatest(comment_count - 1, 0) where id = old.post_id;
  elsif tg_op = 'UPDATE' and old.is_hidden is distinct from new.is_hidden then
    update public.posts set comment_count = greatest(comment_count + (case when new.is_hidden then -1 else 1 end), 0) where id = new.post_id;
  end if;
  return coalesce(new, old);
end $$;
create trigger comments_counts after insert or update of is_hidden or delete on public.comments for each row execute function public.comments_maintain_counts();
