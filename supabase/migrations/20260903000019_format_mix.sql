-- Format mixing: avoid long runs of the same media kind in addition to the author rule.
create or replace function public.apply_author_diversity(p_ids uuid[]) returns uuid[]
language plpgsql stable set search_path = public as $$
declare
  v_out uuid[] := '{}'; v_deferred uuid[] := '{}'; v_id uuid; v_author uuid; v_kind text;
  v_meta jsonb; a1 uuid; a2 uuid; k1 text; k2 text; k3 text;
begin
  select coalesce(jsonb_object_agg(id::text, jsonb_build_object('a', author_id, 'k', kind)), '{}'::jsonb) into v_meta from public.posts where id = any(p_ids);
  foreach v_id in array p_ids loop
    v_author := (v_meta -> v_id::text ->> 'a')::uuid;
    v_kind := v_meta -> v_id::text ->> 'k';
    if (v_author = a1 and v_author = a2) or (v_kind = k1 and v_kind = k2 and v_kind = k3) then
      v_deferred := v_deferred || v_id;
    else
      v_out := v_out || v_id; a2 := a1; a1 := v_author; k3 := k2; k2 := k1; k1 := v_kind;
    end if;
  end loop;
  return v_out || v_deferred;
end $$;
