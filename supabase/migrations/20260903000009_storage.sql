insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('media', 'media', true, 104857600, array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime']),
  ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('ingest', 'ingest', false, 209715200, array['text/csv', 'application/json'])
on conflict (id) do nothing;

-- media/{author_id}/{post_id}/{n}.jpg ; write requires membership of that author and a non-anonymous user
create policy "media public read" on storage.objects for select using (bucket_id = 'media');
create policy "media member write" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.is_full_user() and public.is_author_member(((storage.foldername(name))[1])::uuid));
create policy "media member update" on storage.objects for update to authenticated
  using (bucket_id = 'media' and public.is_author_member(((storage.foldername(name))[1])::uuid));
create policy "media member delete" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.is_author_member(((storage.foldername(name))[1])::uuid));

-- avatars/users/{uid}.jpg or avatars/authors/{author_id}.jpg
create policy "avatars public read" on storage.objects for select using (bucket_id = 'avatars');
create policy "avatars owner write" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (
    ((storage.foldername(name))[1] = 'users' and name like 'users/' || auth.uid()::text || '%') or
    ((storage.foldername(name))[1] = 'authors' and public.is_author_member(split_part((storage.filename(name)), '.', 1)::uuid))));
create policy "avatars owner update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (
    ((storage.foldername(name))[1] = 'users' and name like 'users/' || auth.uid()::text || '%') or
    ((storage.foldername(name))[1] = 'authors' and public.is_author_member(split_part((storage.filename(name)), '.', 1)::uuid))));
