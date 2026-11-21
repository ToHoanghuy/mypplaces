-- MYP-4 (21/11/2026): per-viewer custom order for the "Địa điểm" list (drag to reorder).
-- Each user orders the Places THEY can see (own + shared with them); the order of a shared Place is
-- private to each viewer, so it lives in its own table instead of on public.places.
-- No ON DELETE CASCADE (schema rule): Places are soft-deleted and map_places hides them.
-- Writes go through set_place_order(ids[]) (full-list replace, idempotent => safe for outbox replay);
-- direct table writes are also allowed but RLS limits them to the caller's own rows and to Places
-- the caller can read.

create table public.place_user_order (
  user_id    uuid not null default auth.uid() references public.profiles (id),
  place_id   uuid not null references public.places (id),
  position   integer not null constraint place_user_order_position_nonneg check (position >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, place_id)
);
comment on table public.place_user_order is 'Per-viewer custom sort order of Places in the iOS list (MYP-4). Own rows only.';
create index place_user_order_place_id_idx on public.place_user_order (place_id);   -- FK covering

alter table public.place_user_order enable row level security;

create policy place_user_order_select on public.place_user_order for select to authenticated
  using (user_id = (select auth.uid()));
create policy place_user_order_insert on public.place_user_order for insert to authenticated
  with check (user_id = (select auth.uid()) and private.can_read_place(place_id));
create policy place_user_order_update on public.place_user_order for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and private.can_read_place(place_id));
create policy place_user_order_delete on public.place_user_order for delete to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.place_user_order from anon, authenticated;
grant select, insert, update, delete on public.place_user_order to authenticated;

-- Replace the caller's whole order with p_place_ids (index 0 = top). Unreadable / unknown ids are
-- ignored, duplicates keep their first position, rows for Places not in the list are removed.
-- Returns the number of Places stored.
create function public.set_place_order(p_place_ids uuid[]) returns integer
language plpgsql security invoker set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_n   integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_place_ids), 0) > 2000 then
    raise exception 'too many places (max 2000)' using errcode = '22023';
  end if;

  delete from public.place_user_order o
  where o.user_id = v_uid and not (o.place_id = any (coalesce(p_place_ids, '{}'::uuid[])));

  insert into public.place_user_order (user_id, place_id, position, updated_at)
  select v_uid, r.id, (row_number() over (order by r.first_ord) - 1)::integer, now()
  from (
    select t.id, min(t.ord) as first_ord
    from unnest(coalesce(p_place_ids, '{}'::uuid[])) with ordinality as t (id, ord)
    where t.id is not null and private.can_read_place(t.id)
    group by t.id
  ) r
  on conflict (user_id, place_id) do update
    set position = excluded.position, updated_at = excluded.updated_at;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.set_place_order(uuid[]) from public, anon, authenticated;
grant execute on function public.set_place_order(uuid[]) to authenticated;
