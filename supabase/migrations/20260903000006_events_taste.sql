-- Append-only client + server events. client_id makes retries idempotent.
create table public.events (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid,
  post_id uuid references public.posts(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  author_id uuid,
  type public.event_type not null,
  dwell_ms int,
  position int,
  media_index int,
  click_id uuid,
  category text,
  client_ts timestamptz,
  created_at timestamptz not null default now()
);
create index events_user_created_idx on public.events (user_id, created_at desc);
create index events_post_type_idx on public.events (post_id, type) where post_id is not null;
create index events_created_brin on public.events using brin (created_at);

create table public.post_stats (
  post_id uuid primary key references public.posts(id) on delete cascade,
  impressions int not null default 0,
  skips int not null default 0,
  likes int not null default 0,
  saves int not null default 0,
  comments int not null default 0,
  click_outs int not null default 0,
  hides int not null default 0,
  dwell_ms_sum bigint not null default 0,
  updated_at timestamptz not null default now()
);

create or replace function public.posts_create_stats() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.post_stats (post_id) values (new.id) on conflict do nothing;
  return new;
end $$;
create trigger posts_create_stats after insert on public.posts for each row execute function public.posts_create_stats();

create table public.user_seen (
  user_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  seen_count int not null default 1,
  last_seen_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index user_seen_last_idx on public.user_seen (user_id, last_seen_at desc);

create table public.user_taste (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  taste_vec extensions.vector(384),
  session_vec extensions.vector(384),
  session_vec_at timestamptz,
  session_signal_count int not null default 0,
  quiz_vec extensions.vector(384),
  signal_count int not null default 0,
  embedding_model text not null default 'gte-small',
  updated_at timestamptz not null default now()
);

-- Tunable signal weights (w) and EWMA step sizes (alpha).
create table public.signal_weights (
  type public.event_type primary key,
  w real not null,
  alpha real not null,
  tier text not null check (tier in ('none', 'weak', 'medium', 'strong'))
);
insert into public.signal_weights (type, w, alpha, tier) values
  ('skip', -0.15, 0.02, 'weak'),
  ('impression', 0, 0, 'none'),
  ('dwell_short', 0.15, 0.02, 'weak'),
  ('dwell_med', 0.30, 0.05, 'medium'),
  ('dwell_long', 0.40, 0.05, 'medium'),
  ('like', 0.60, 0.10, 'strong'),
  ('unlike', 0, 0, 'none'),
  ('comment', 0.70, 0.10, 'strong'),
  ('save', 0.90, 0.10, 'strong'),
  ('unsave', 0, 0, 'none'),
  ('click_out', 1.00, 0.10, 'strong'),
  ('follow', 0.80, 0.10, 'strong'),
  ('unfollow', -0.50, 0.10, 'strong'),
  ('hide', -1.00, 0.10, 'strong'),
  ('share', 0.70, 0.10, 'strong'),
  ('view', 0, 0, 'none'),
  ('video_complete', 0.30, 0.05, 'medium'),
  ('carousel_swipe', 0, 0, 'none'),
  ('quiz_complete', 0, 0, 'none');

create table public.ranking_params (
  key text primary key,
  value real not null,
  note text
);
insert into public.ranking_params (key, value, note) values
  ('w_sim', 0.55, 'weight of normalized cosine similarity'),
  ('w_recency', 0.15, 'weight of exp(-age_h/tau)'),
  ('tau_hours', 72, 'recency decay constant'),
  ('w_pop', 0.12, 'weight of ln(1+10*engagement_rate)'),
  ('w_follow', 0.10, 'bonus when author is followed'),
  ('seen_penalty', 0.30, 'penalty per prior impression (capped at 2)'),
  ('sim_floor', 0.60, 'cosine at which sim_n = 0'),
  ('sim_range', 0.35, 'cosine range mapped to sim_n 0..1'),
  ('author_penalty', 0.15, 'penalty per additional post by same author'),
  ('explore_every', 5, 'explore slot cadence'),
  ('session_blend', 0.30, 'weight of session_vec in the ranking query vector');

create table public.feed_snapshots (
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid not null,
  category text not null default 'for_you',
  post_ids uuid[] not null default '{}',
  built_at timestamptz not null default now(),
  extended_at timestamptz,
  primary key (user_id, session_id, category)
);
create index feed_snapshots_built_idx on public.feed_snapshots (built_at);

create table public.app_settings (
  key text primary key,
  value text not null
);
