-- enqueue_embed referenced new.slug on tables without that column, which fails at runtime once functions_base_url is set.
create or replace function public.enqueue_embed() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_url text; v_secret text; j jsonb := to_jsonb(new);
begin
  select value into v_url from public.app_settings where key = 'functions_base_url';
  select value into v_secret from public.app_settings where key = 'embed_webhook_secret';
  if v_url is null or v_secret is null then return null; end if;
  perform net.http_post(
    url := v_url || '/embed',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-embed-secret', v_secret),
    body := jsonb_build_object('table', tg_table_name, 'id', coalesce(j ->> 'id', j ->> 'slug')),
    timeout_milliseconds := 15000);
  return null;
end $$;
