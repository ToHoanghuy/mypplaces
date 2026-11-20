-- =============================================================================
-- MyPlaces – 15 (20/11/2026): Overture Places fallback search (read-only POI catalogue)
-- When Apple MKLocalSearch returns too few results, the iOS app calls search_pois() and merges
-- the hits. Data: Overture Maps Foundation "places" theme, filtered to Vietnam (see
-- scripts/overture/README.md for filters + monthly refresh). Licence: CDLA-Permissive-2.0
-- (Meta, Microsoft, ...), Foursquare Apache-2.0, AllThePlaces CC0 → attribution shown in the app.
-- Clients can only SELECT (RLS) and call the RPC; rows are loaded by the postgres role.
-- =============================================================================
create extension if not exists pg_trgm  with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Accent-insensitive Vietnamese normaliser: "Ốc Oanh – Vĩnh Khánh" -> "oc oanh vinh khanh".
-- unaccent maps Đ/đ -> D/d. IMMUTABLE so it can back a generated column + index.
create or replace function private.vn_norm(t text)
returns text
language sql immutable parallel safe
set search_path = ''
as $$
  select btrim(regexp_replace(
           lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(t, ''))),
           '[[:punct:][:space:]]+', ' ', 'g'))
$$;
revoke all on function private.vn_norm(text) from public, anon, authenticated;
grant execute on function private.vn_norm(text) to authenticated;

create table public.poi_overture (
  id          uuid primary key,                       -- Overture GERS id (stable across releases)
  name        text not null check (length(name) between 1 and 200),
  name_norm   text generated always as (private.vn_norm(name)) stored,
  -- name + address, so "Ốc Oanh Vĩnh Khánh" finds "Ốc Oanh" at "534 Vĩnh Khánh"
  search_norm text generated always as (private.vn_norm(name || ' ' || coalesce(address, ''))) stored,
  category    public.place_category not null default 'OTHER',
  address     text check (address is null or length(address) <= 200),
  latitude    double precision not null check (latitude between -90 and 90),
  longitude   double precision not null check (longitude between -180 and 180),
  confidence  real not null check (confidence between 0 and 1)
);
comment on table public.poi_overture is
  'Read-only Vietnam POI catalogue from Overture Maps (places theme). Fallback for search. Attribution: Overture Maps Foundation, © OpenStreetMap contributors.';

create index poi_overture_search_trgm on public.poi_overture using gin (search_norm extensions.gin_trgm_ops);
-- expression GiST (no stored column) for bounding-box / nearest-neighbour lookups: point(lng, lat)
create index poi_overture_location  on public.poi_overture using gist (point(longitude, latitude));

-- One row per import (release id, counts, filters) so the app/ops can see data freshness.
create table public.poi_overture_imports (
  release      text primary key,
  imported_at  timestamptz not null default now(),
  row_count    integer not null,
  filters      text not null
);

alter table public.poi_overture         enable row level security;
alter table public.poi_overture_imports enable row level security;
create policy poi_overture_select on public.poi_overture for select to authenticated using (true);
create policy poi_overture_imports_select on public.poi_overture_imports for select to authenticated using (true);

revoke all on public.poi_overture, public.poi_overture_imports from public, anon, authenticated;
grant select on public.poi_overture, public.poi_overture_imports to authenticated;

-- search_pois: accent-insensitive fuzzy search over name + address, ranked by
--   0.30 word-similarity(query in name+address)
--   + 0.25 name match = max(word-similarity(query in name), 0.8 * word-similarity(name in query))
--   + 0.15 whole-name similarity (exact names win) + 0.20 proximity (if lat/lng; halves at 2 km)
--   + 0.10 confidence.
-- SECURITY INVOKER: runs with the caller's rights (RLS select-only table). Limits are clamped
-- (q ≤ 100 chars, ≥ 2 chars after normalising, 1..20 rows) to keep each call cheap.
create or replace function public.search_pois(
  q text,
  lat double precision default null,
  lng double precision default null,
  max_results integer default 10
)
returns table (
  id uuid, name text, category public.place_category, address text,
  latitude double precision, longitude double precision, confidence real,
  distance_m double precision, score double precision
)
language sql stable security invoker
set search_path = ''
as $$
  with nq as (
    select private.vn_norm(left(q, 100)) as n,
           least(greatest(coalesce(max_results, 10), 1), 20) as lim
  ),
  cand as (
    select p.id, p.name, p.category, p.address, p.latitude, p.longitude, p.confidence,
           extensions.word_similarity(nq.n, p.search_norm) as wa,
           greatest(extensions.word_similarity(nq.n, p.name_norm),
                    0.8 * extensions.word_similarity(p.name_norm, nq.n)) as nm,
           extensions.similarity(nq.n, p.name_norm) as s,
           case when lat is null or lng is null then null else
             2 * 6371000 * asin(sqrt(
               power(sin(radians(p.latitude - lat) / 2), 2) +
               cos(radians(lat)) * cos(radians(p.latitude)) * power(sin(radians(p.longitude - lng) / 2), 2)))
           end as d
    from public.poi_overture p, nq
    where length(nq.n) >= 2
      and (nq.n operator(extensions.<%) p.search_norm or p.search_norm like '%' || nq.n || '%')
  )
  select c.id, c.name, c.category, c.address, c.latitude, c.longitude, c.confidence, c.d,
         0.30 * c.wa + 0.25 * c.nm + 0.15 * c.s + 0.10 * c.confidence
           + case when c.d is null then 0 else 0.20 / (1 + c.d / 2000.0) end as score
  from cand c
  order by score desc, c.id
  limit (select lim from nq)
$$;
revoke all on function public.search_pois(text, double precision, double precision, integer) from public, anon, authenticated;
grant execute on function public.search_pois(text, double precision, double precision, integer) to authenticated;
