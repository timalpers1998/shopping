create type public.author_kind as enum ('creator', 'brand');
create type public.post_kind as enum ('image', 'carousel', 'video');
create type public.post_status as enum ('draft', 'published', 'hidden', 'removed');
create type public.media_kind as enum ('image', 'video');
create type public.post_category as enum ('fashion', 'home', 'beauty');
create type public.audience as enum ('womens', 'mens', 'unisex');
create type public.price_band as enum ('budget', 'mid', 'premium', 'luxury');
create type public.member_role as enum ('owner', 'editor');
create type public.event_type as enum (
  'view', 'skip', 'impression', 'dwell_short', 'dwell_med', 'dwell_long',
  'like', 'unlike', 'save', 'unsave', 'comment', 'follow', 'unfollow',
  'click_out', 'share', 'hide', 'video_complete', 'carousel_swipe', 'quiz_complete'
);
