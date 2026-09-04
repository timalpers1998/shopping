alter table public.profiles enable row level security;
alter table public.authors enable row level security;
alter table public.author_members enable row level security;
alter table public.follows enable row level security;
alter table public.posts enable row level security;
alter table public.post_media enable row level security;
alter table public.products enable row level security;
alter table public.post_products enable row level security;
alter table public.likes enable row level security;
alter table public.saves enable row level security;
alter table public.comments enable row level security;
alter table public.events enable row level security;
alter table public.post_stats enable row level security;
alter table public.user_seen enable row level security;
alter table public.user_taste enable row level security;
alter table public.signal_weights enable row level security;
alter table public.ranking_params enable row level security;
alter table public.feed_snapshots enable row level security;
alter table public.app_settings enable row level security;
alter table public.style_anchors enable row level security;
alter table public.brands enable row level security;
alter table public.user_quiz_answers enable row level security;
alter table public.redirects enable row level security;
alter table public.redirect_hits enable row level security;

-- profiles
create policy "profiles read" on public.profiles for select using (true);
create policy "profiles update own" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- authors
create policy "authors read" on public.authors for select using (is_active or public.is_author_member(id));
create policy "authors create creator" on public.authors for insert to authenticated
  with check (public.is_full_user() and owner_user_id = auth.uid() and kind = 'creator');
create policy "authors update member" on public.authors for update using (public.is_author_member(id));

create policy "author_members read" on public.author_members for select using (user_id = auth.uid() or public.is_author_member(author_id));
create policy "author_members owner manage" on public.author_members for all
  using (exists (select 1 from public.author_members m where m.author_id = author_members.author_id and m.user_id = auth.uid() and m.role = 'owner'));

-- social
create policy "follows read own" on public.follows for select using (user_id = auth.uid());
create policy "follows insert own" on public.follows for insert to authenticated with check (user_id = auth.uid());
create policy "follows delete own" on public.follows for delete using (user_id = auth.uid());

create policy "posts read published" on public.posts for select using (status = 'published' or public.is_author_member(author_id));
create policy "posts insert member" on public.posts for insert to authenticated with check (public.is_full_user() and public.is_author_member(author_id));
create policy "posts update member" on public.posts for update using (public.is_author_member(author_id));
create policy "posts delete member" on public.posts for delete using (public.is_author_member(author_id));

create policy "post_media read" on public.post_media for select
  using (exists (select 1 from public.posts p where p.id = post_id and (p.status = 'published' or public.is_author_member(p.author_id))));
create policy "post_media write member" on public.post_media for all to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id and public.is_author_member(p.author_id)))
  with check (exists (select 1 from public.posts p where p.id = post_id and public.is_author_member(p.author_id)));

create policy "products read" on public.products for select using (true);
create policy "products insert full user" on public.products for insert to authenticated with check (public.is_full_user() and created_by = auth.uid());
create policy "products update creator" on public.products for update using (created_by = auth.uid() or (author_id is not null and public.is_author_member(author_id)));

create policy "post_products read" on public.post_products for select
  using (exists (select 1 from public.posts p where p.id = post_id and (p.status = 'published' or public.is_author_member(p.author_id))));
create policy "post_products write member" on public.post_products for all to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id and public.is_author_member(p.author_id)))
  with check (exists (select 1 from public.posts p where p.id = post_id and public.is_author_member(p.author_id)));

create policy "likes read own" on public.likes for select using (user_id = auth.uid());
create policy "likes insert own" on public.likes for insert to authenticated with check (user_id = auth.uid());
create policy "likes delete own" on public.likes for delete using (user_id = auth.uid());
create policy "saves read own" on public.saves for select using (user_id = auth.uid());
create policy "saves insert own" on public.saves for insert to authenticated with check (user_id = auth.uid());
create policy "saves delete own" on public.saves for delete using (user_id = auth.uid());

create policy "comments read" on public.comments for select using (not is_hidden or user_id = auth.uid());
create policy "comments insert full user" on public.comments for insert to authenticated with check (public.is_full_user() and user_id = auth.uid());
create policy "comments update own" on public.comments for update using (user_id = auth.uid());
create policy "comments delete own" on public.comments for delete using (user_id = auth.uid());

-- events: insert-only for the owner (via RPC or direct)
create policy "events insert own" on public.events for insert to authenticated with check (user_id = auth.uid());
create policy "user_seen read own" on public.user_seen for select using (user_id = auth.uid());
create policy "user_taste read own" on public.user_taste for select using (user_id = auth.uid());
create policy "feed_snapshots read own" on public.feed_snapshots for select using (user_id = auth.uid());
create policy "post_stats read" on public.post_stats for select using (true);
create policy "signal_weights read" on public.signal_weights for select using (true);
create policy "ranking_params read" on public.ranking_params for select using (true);

-- quiz
create policy "style_anchors read" on public.style_anchors for select using (is_active);
create policy "brands read" on public.brands for select using (is_active);
create policy "quiz answers read own" on public.user_quiz_answers for select using (user_id = auth.uid());

-- redirects: ids are public; hits and settings are service-role only (no policies)
create policy "redirects read" on public.redirects for select using (true);
