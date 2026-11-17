-- =============================================================================
-- MyPlaces – 12 (17/11/2026): Personal Timeline + companion suggestions
--
-- (a) my_timeline()  – UI decision #6 + BRD §34.5 Workflow E: "Timeline lấy các Visit mà user có
--     quyền sở hữu/đọc". Returns live Visits the caller OWNS or is an ACTIVE visit_member of, each with
--     its own timezone_id and the wall-clock time in that zone (visited_local), so the client groups /
--     displays every Visit in the zone it was recorded in (not the device zone).
--     Place fields are a MINIMAL projection (title, category, coordinates – never address/provider,
--     never sibling Visits), exactly like the Journal projection (ERD §5.3/§5.4):
--       * Visit owner: always (decision D3, even if the Place was unshared or soft-deleted);
--       * Visit member: only while the Place is live (deleted Place -> place fields null).
--     This replaces the earlier auto-decision "Visit Viewer/Editor không thấy Place" (README §6.3) for
--     the timeline/visit-detail use case only; places RLS is NOT widened.
-- (b) list_companion_suggestions() – UI decision #4: people the caller may pick as an account
--     participant = co-members of a live Place/Visit/Journal shared with the caller (owner or ACTIVE
--     member on both sides) + accounts the caller already added as participants of their own Visits.
--     Every returned id also passes private.can_read_profile(), i.e. exactly the set the
--     visit_participants INSERT policy accepts. Free-text guests need no lookup (display_name_snapshot).
--     Selecting someone never invites them and grants nothing (ERD-01).
-- Both are SECURITY DEFINER with search_path = '' and filter on auth.uid() themselves; non-members get
-- an empty result. anon has no EXECUTE.
-- =============================================================================

create function public.my_timeline(
  p_from      timestamptz           default null,   -- inclusive lower bound on visited_at
  p_to        timestamptz           default null,   -- exclusive upper bound (also usable as a page cursor)
  p_category  public.place_category default null,
  p_visit_id  uuid                  default null,   -- fetch one item (Visit Detail header)
  p_limit     integer               default 100     -- clamped to 1..500
)
returns table (
  visit_id           uuid,
  visited_at         timestamptz,
  timezone_id        text,
  visited_local      timestamp,           -- visited_at expressed in the Visit's own timezone_id
  note               text,
  owner_id           uuid,
  my_role            public.member_role,  -- OWNER / EDITOR / VIEWER on this Visit
  place_id           uuid,
  place_title        text,
  place_category     public.place_category,
  latitude           double precision,
  longitude          double precision,
  place_available    boolean,             -- false when the Place is soft-deleted
  cover_memory_id    uuid,
  cover_storage_path text
)
language sql stable security definer set search_path = ''
as $$
  with me as (select auth.uid() as uid),
  vis as (
    select v.id, v.place_id, v.owner_id, v.visited_at, v.timezone_id, v.note,
           'OWNER'::public.member_role as role
    from public.visits v, me
    where v.owner_id = me.uid and v.deleted_at is null
    union all
    select v.id, v.place_id, v.owner_id, v.visited_at, v.timezone_id, v.note, m.role
    from public.visit_members m
    join public.visits v on v.id = m.visit_id, me
    where m.user_id = me.uid and m.status = 'ACTIVE'
      and v.deleted_at is null and v.owner_id <> me.uid
  )
  select vis.id, vis.visited_at, vis.timezone_id, (vis.visited_at at time zone vis.timezone_id),
         vis.note, vis.owner_id, vis.role,
         vis.place_id,
         case when s.show then p.title     end,
         case when s.show then p.category  end,
         case when s.show then p.latitude  end,
         case when s.show then p.longitude end,
         p.deleted_at is null,
         c.memory_id, c.storage_path
  from vis
  join public.places p on p.id = vis.place_id
  cross join lateral (select (vis.role = 'OWNER' or p.deleted_at is null) as show) s
  left join lateral (
    select a.memory_id, a.storage_path
    from public.memories mem
    join public.memory_attachments a on a.memory_id = mem.id
    where mem.visit_id = vis.id and mem.deleted_at is null and mem.type = 'PHOTO'
    order by mem.created_at desc, a.created_at desc, a.id desc
    limit 1
  ) c on true
  where (p_visit_id is null or vis.id = p_visit_id)
    and (p_from is null or vis.visited_at >= p_from)
    and (p_to   is null or vis.visited_at <  p_to)
    and (p_category is null or (s.show and p.category = p_category))
  order by vis.visited_at desc, vis.id desc
  limit least(greatest(coalesce(p_limit, 100), 1), 500);
$$;

comment on function public.my_timeline(timestamptz, timestamptz, public.place_category, uuid, integer) is
  'Personal Timeline (BRD §34.5): live Visits owned by / shared with the caller, newest first, each with its own '
  'timezone_id + visited_local, minimal Place projection and cover photo path. No sibling Visits, no address.';

create function public.list_companion_suggestions(
  p_query text    default null,   -- optional case-insensitive substring of display_name
  p_limit integer default 30      -- clamped to 1..100
)
returns table (
  user_id        uuid,
  display_name   text,
  avatar_path    text,
  last_shared_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  with me as (select auth.uid() as uid),
  -- live resources the caller owns or is an ACTIVE member of
  my_places as (
    select p.id, p.owner_id, null::timestamptz as my_joined from public.places p, me
     where p.owner_id = me.uid and p.deleted_at is null
    union all
    select p.id, p.owner_id, m.joined_at from public.place_members m
      join public.places p on p.id = m.place_id, me
     where m.user_id = me.uid and m.status = 'ACTIVE' and p.deleted_at is null
  ),
  my_visits as (
    select v.id, v.owner_id, null::timestamptz as my_joined from public.visits v, me
     where v.owner_id = me.uid and v.deleted_at is null
    union all
    select v.id, v.owner_id, m.joined_at from public.visit_members m
      join public.visits v on v.id = m.visit_id, me
     where m.user_id = me.uid and m.status = 'ACTIVE' and v.deleted_at is null
  ),
  my_journals as (
    select j.id, j.owner_id, null::timestamptz as my_joined from public.journals j, me
     where j.owner_id = me.uid and j.deleted_at is null
    union all
    select j.id, j.owner_id, m.joined_at from public.journal_members m
      join public.journals j on j.id = m.journal_id, me
     where m.user_id = me.uid and m.status = 'ACTIVE' and j.deleted_at is null
  ),
  cand as (
    -- owners of resources shared with me
    select r.owner_id as user_id, r.my_joined as at from my_places   r where r.my_joined is not null
    union all
    select r.owner_id, r.my_joined from my_visits   r where r.my_joined is not null
    union all
    select r.owner_id, r.my_joined from my_journals r where r.my_joined is not null
    -- other ACTIVE members of those resources
    union all
    select o.user_id, o.joined_at from my_places r
      join public.place_members o on o.place_id = r.id and o.status = 'ACTIVE'
    union all
    select o.user_id, o.joined_at from my_visits r
      join public.visit_members o on o.visit_id = r.id and o.status = 'ACTIVE'
    union all
    select o.user_id, o.joined_at from my_journals r
      join public.journal_members o on o.journal_id = r.id and o.status = 'ACTIVE'
    -- accounts I already recorded as participants of my own live Visits
    union all
    select vp.user_id, vp.created_at from public.visit_participants vp
      join public.visits v on v.id = vp.visit_id, me
     where v.owner_id = me.uid and v.deleted_at is null and vp.user_id is not null
  )
  select pr.id, pr.display_name, pr.avatar_path, max(c.at)
  from cand c
  join public.profiles pr on pr.id = c.user_id
  cross join me
  where me.uid is not null
    and c.user_id <> me.uid
    and (nullif(btrim(p_query), '') is null
         or strpos(lower(pr.display_name), lower(btrim(p_query))) > 0)
    and private.can_read_profile(pr.id)
  group by pr.id, pr.display_name, pr.avatar_path
  order by max(c.at) desc nulls last, pr.display_name, pr.id
  limit least(greatest(coalesce(p_limit, 30), 1), 100);
$$;

comment on function public.list_companion_suggestions(text, integer) is
  'Companion picker (UI decision #4): co-members of live shared Places/Visits/Journals + accounts already used as '
  'participants on the caller''s Visits. Subset of profiles the caller can read; grants nothing.';

revoke all on function public.my_timeline(timestamptz, timestamptz, public.place_category, uuid, integer) from public, anon;
revoke all on function public.list_companion_suggestions(text, integer) from public, anon;
grant execute on function public.my_timeline(timestamptz, timestamptz, public.place_category, uuid, integer) to authenticated;
grant execute on function public.list_companion_suggestions(text, integer) to authenticated;
