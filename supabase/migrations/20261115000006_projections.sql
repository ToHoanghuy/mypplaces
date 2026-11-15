-- =============================================================================
-- MyPlaces – 06: scoped projections (SECURITY DEFINER RPCs over LIVE data, never snapshots)
--
-- (a) Journal projections (decision 5 / ERD-04): Journal members see linked Places/Visits only
--     through these functions, which return a fixed minimal column set. No direct access to
--     places / visits is granted (no policy), no sibling Visits, no private notes, no participants,
--     no address / provider ids.
-- (b) my_visit_places (decision 3): a Visit OWNER can always read a minimal projection
--     (id, title, category, lat/lng) of the Place their Visit belongs to, even if that Place was
--     unshared or soft-deleted. places RLS is NOT widened.
-- Functions are RPC-callable by authenticated users: PostgREST  POST /rpc/<name>.
-- Non-members get an EMPTY result (no existence leak).
-- =============================================================================

create function public.journal_places_projection(p_journal_id uuid)
returns table (
  journal_place_id uuid,
  journal_id       uuid,
  place_id         uuid,
  title            text,
  category         public.place_category,
  latitude         double precision,
  longitude        double precision,
  sort_order       integer,
  added_by         uuid,
  linked_at        timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select jp.id, jp.journal_id, p.id, p.title, p.category, p.latitude, p.longitude,
         jp.sort_order, jp.added_by, jp.created_at
  from public.journal_places jp
  join public.places p on p.id = jp.place_id
  where jp.journal_id = p_journal_id
    and private.can_read_journal(p_journal_id)   -- caller must be Journal owner / ACTIVE member
    and p.deleted_at is null                     -- live: deleted places disappear
  order by jp.sort_order, jp.created_at, jp.id;
$$;

-- Place fields are shown only while the Place is live; visit date/timezone are the shared context.
create function public.journal_visits_projection(p_journal_id uuid)
returns table (
  journal_visit_id uuid,
  journal_id       uuid,
  visit_id         uuid,
  visited_at       timestamptz,
  timezone_id      text,
  place_id         uuid,
  place_title      text,
  place_category   public.place_category,
  latitude         double precision,
  longitude        double precision,
  sort_order       integer,
  added_by         uuid,
  linked_at        timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select jv.id, jv.journal_id, v.id, v.visited_at, v.timezone_id,
         p.id, p.title, p.category, p.latitude, p.longitude,
         jv.sort_order, jv.added_by, jv.created_at
  from public.journal_visits jv
  join public.visits v on v.id = jv.visit_id
  join public.places p on p.id = v.place_id and p.deleted_at is null
  where jv.journal_id = p_journal_id
    and private.can_read_journal(p_journal_id)
    and v.deleted_at is null
  order by v.visited_at, jv.created_at, jv.id;
$$;

-- Decision 3. p_visit_id = null -> all live Visits owned by the caller.
create function public.my_visit_places(p_visit_id uuid default null)
returns table (
  visit_id      uuid,
  place_id      uuid,
  title         text,
  category      public.place_category,
  latitude      double precision,
  longitude     double precision,
  place_deleted boolean
)
language sql stable security definer set search_path = ''
as $$
  select v.id, p.id, p.title, p.category, p.latitude, p.longitude, p.deleted_at is not null
  from public.visits v
  join public.places p on p.id = v.place_id
  where v.owner_id = auth.uid()
    and v.deleted_at is null
    and (p_visit_id is null or v.id = p_visit_id)
  order by v.visited_at desc, v.id;
$$;
