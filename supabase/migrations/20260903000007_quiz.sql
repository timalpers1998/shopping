create table public.style_anchors (
  slug text primary key,
  label text not null,
  category public.post_category not null default 'fashion',
  anchor_text text not null,
  image_url text,
  sort_order smallint not null default 0,
  is_active boolean not null default true,
  embedding extensions.vector(384),
  embedding_model text,
  embedding_input_hash text,
  embedded_at timestamptz
);

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  price_band public.price_band not null,
  style_tags text[] not null default '{}',
  anchor_text text not null,
  logo_url text,
  author_id uuid references public.authors(id) on delete set null,
  sort_order smallint not null default 0,
  is_active boolean not null default true,
  embedding extensions.vector(384),
  embedding_model text,
  embedding_input_hash text,
  embedded_at timestamptz
);

create table public.user_quiz_answers (
  user_id uuid not null references public.profiles(id) on delete cascade,
  style_slug text references public.style_anchors(slug) on delete cascade,
  brand_id uuid references public.brands(id) on delete cascade,
  created_at timestamptz not null default now(),
  check ((style_slug is not null) <> (brand_id is not null))
);
create index user_quiz_answers_user_idx on public.user_quiz_answers (user_id);
