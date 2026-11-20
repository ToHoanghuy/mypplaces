-- search_pois ranking v2: add query-word coverage (share of query words present as whole words in
-- name + address, weight 0.15). Fixes multi-word queries like "Ốc Oanh Vĩnh Khánh" being outranked by a
-- nearby place matching only part of the words. Signature, grants and security are unchanged.
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
           least(greatest(coalesce(max_results, 10), 1), 20) as lim,
           array_remove(string_to_array(private.vn_norm(left(q, 100)), ' '), '') as w
  ),
  cand as (
    select p.id, p.name, p.category, p.address, p.latitude, p.longitude, p.confidence,
           extensions.word_similarity(nq.n, p.search_norm) as wa,
           greatest(extensions.word_similarity(nq.n, p.name_norm),
                    0.8 * extensions.word_similarity(p.name_norm, nq.n)) as nm,
           extensions.similarity(nq.n, p.name_norm) as s,
           (select avg((' ' || p.search_norm || ' ' like '% ' || t || ' %')::int) from unnest(nq.w) t) as cov,
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
         0.30 * c.wa + 0.25 * c.nm + 0.15 * c.s + 0.10 * c.confidence + 0.15 * coalesce(c.cov, 0)
           + case when c.d is null then 0 else 0.20 / (1 + c.d / 2000.0) end as score
  from cand c
  order by score desc, c.id
  limit (select lim from nq)
$$;

revoke all on function public.search_pois(text, double precision, double precision, integer) from public, anon;
grant execute on function public.search_pois(text, double precision, double precision, integer) to authenticated;
