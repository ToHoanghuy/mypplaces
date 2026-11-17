-- =============================================================================
-- MyPlaces – 11 (17/11/2026): personal map read model  (UI decision #2 "Muốn đến" vs "Đã ghé")
--
-- Decision #2 (approved 17/11/2026): there is NO status column. A Place is
--   VISITED        when the caller can see at least one live (deleted_at is null) Visit on it,
--   WANT_TO_VISIT  otherwise.
-- "can see" = the normal visits RLS (Visit owner or ACTIVE visit_member). A Place Viewer/Editor
-- therefore never learns about the owner's Visit history (ERD-03): for them visit_count only counts
-- Visits they own or that were shared with them explicitly.
--
-- security_invoker = true: the view runs with the CALLER's privileges, so RLS of places, visits,
-- memories, memory_attachments and place_members applies to every row and sub-query.
-- Nothing here widens access; it only aggregates what the caller could already read.
--
-- Cover photo (map pin): newest PHOTO attachment of the most recent readable Visit of the Place;
-- falls back to the newest PHOTO attachment of a Memory attached to the Place itself.
-- The client turns cover_storage_path into a short-lived signed URL (storage policy re-checks access).
-- =============================================================================

create view public.map_places
with (security_invoker = true)
as
select
  p.id                                                    as place_id,
  p.owner_id,
  p.title,
  p.category,
  p.latitude,
  p.longitude,
  p.address,
  p.updated_at,
  (p.owner_id = (select auth.uid()))                      as is_owner,
  case when p.owner_id = (select auth.uid()) then 'OWNER'::public.member_role
       else me.role end                                   as my_role,
  (p.owner_id <> (select auth.uid())
     or exists (select 1 from public.place_members m
                where m.place_id = p.id and m.status = 'ACTIVE'))  as is_shared,
  coalesce(vs.visit_count, 0)::integer                    as visit_count,
  vs.last_visited_at,
  case when coalesce(vs.visit_count, 0) > 0 then 'VISITED' else 'WANT_TO_VISIT' end as visit_status,
  cover.memory_id                                         as cover_memory_id,
  cover.storage_path                                      as cover_storage_path
from public.places p
left join lateral (
  select m.role from public.place_members m
  where m.place_id = p.id and m.user_id = (select auth.uid()) and m.status = 'ACTIVE'
) me on true
left join lateral (
  select count(*) as visit_count, max(v.visited_at) as last_visited_at
  from public.visits v
  where v.place_id = p.id and v.deleted_at is null
) vs on true
left join lateral (
  select c.memory_id, c.storage_path
  from (
    select 0 as prio, v.visited_at as sort_at, mem.created_at as mem_at, a.created_at as att_at,
           a.id as att_id, a.memory_id, a.storage_path
    from public.visits v
    join public.memories mem on mem.visit_id = v.id and mem.deleted_at is null and mem.type = 'PHOTO'
    join public.memory_attachments a on a.memory_id = mem.id
    where v.place_id = p.id and v.deleted_at is null
    union all
    select 1, mem.created_at, mem.created_at, a.created_at, a.id, a.memory_id, a.storage_path
    from public.memories mem
    join public.memory_attachments a on a.memory_id = mem.id
    where mem.place_id = p.id and mem.deleted_at is null and mem.type = 'PHOTO'
  ) c
  order by c.prio, c.sort_at desc, c.mem_at desc, c.att_at desc, c.att_id desc
  limit 1
) cover on true
where p.deleted_at is null;

comment on view public.map_places is
  'Personal map read model (security_invoker): live Places the caller can read + derived visit_status '
  '(VISITED if the caller can see >= 1 live Visit, else WANT_TO_VISIT), visit_count, last_visited_at, cover photo path. '
  'RLS of the underlying tables applies; Place members never see the owner''s Visit history (ERD-03).';

-- Deny by default (migration 09): grant read to signed-in users only.
revoke all on public.map_places from anon, authenticated, public;
grant select on public.map_places to authenticated;
