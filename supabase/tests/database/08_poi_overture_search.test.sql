-- Overture POI fallback (20/11/2026): read-only catalogue + search_pois() RPC.
-- Tags: [POI-1] RLS/grants read-only, [POI-2] accent-insensitive fuzzy search, [POI-3] ranking by
-- distance, [POI-4] limit clamps, [POI-5] anon has no access.
begin;
select plan(31);
select tests.seed_users();

-- ------------------------------------------------------------------ fixtures (postgres) ----
insert into public.poi_overture (id, name, category, address, latitude, longitude, confidence) values
  ('99999999-0000-0000-0000-000000000001', 'Ốc Oanh',                    'FOOD',   '534 Vĩnh Khánh, Quận 4', 10.7609, 106.7033, 0.96),
  ('99999999-0000-0000-0000-000000000002', 'Ốc Oanh 2',                  'FOOD',   'Hà Nội',                 21.0300, 105.8500, 0.80),
  ('99999999-0000-0000-0000-000000000003', 'Lăng Chủ tịch Hồ Chí Minh', 'TRAVEL', 'Ba Đình, Hà Nội',        21.0368, 105.8346, 0.93),
  ('99999999-0000-0000-0000-000000000004', 'Cà Phê Đinh',                'CAFE',   '13 Đinh Tiên Hoàng',     21.0321, 105.8522, 0.90),
  ('99999999-0000-0000-0000-000000000005', 'Highlands Coffee',           'CAFE',   null,                     10.7800, 106.7000, 0.85),
  ('99999999-0000-0000-0000-000000000006', 'Chùa Vĩnh Khánh',            'TRAVEL', 'Ngõ 267 Hoàng Hoa Thám, Ba Đình', 21.0400, 105.8200, 0.88);
insert into public.poi_overture (id, name, category, latitude, longitude, confidence)
select ('99999999-0000-0000-0001-' || lpad(i::text, 12, '0'))::uuid, 'Phở số ' || i, 'FOOD', 21.0 + i / 1000.0, 105.8, 0.8
from generate_series(1, 25) as i;
insert into public.poi_overture_imports (release, row_count, filters) values ('test', 31, 'fixture');

-- ------------------------------------------------------------------ [POI-1] structure / grants ----
select ok((select relrowsecurity from pg_class where oid = 'public.poi_overture'::regclass), '[POI-1] RLS enabled on poi_overture');
select ok((select relrowsecurity from pg_class where oid = 'public.poi_overture_imports'::regclass), '[POI-1] RLS enabled on poi_overture_imports');
select table_privs_are('public', 'poi_overture', 'authenticated', array['SELECT'], '[POI-1] authenticated: SELECT only on poi_overture');
select table_privs_are('public', 'poi_overture_imports', 'authenticated', array['SELECT'], '[POI-1] authenticated: SELECT only on imports');
select table_privs_are('public', 'poi_overture', 'anon', array[]::text[], '[POI-5] anon: no privileges on poi_overture');
select is((select name_norm from public.poi_overture where id = '99999999-0000-0000-0000-000000000004'), 'ca phe dinh', '[POI-2] name_norm strips accents and Đ -> d');
select is(private.vn_norm('  ỐC   Oanh – Vĩnh Khánh! '), 'oc oanh vinh khanh', '[POI-2] vn_norm folds case, accents, punctuation, spaces');
select ok(exists (select 1 from pg_indexes where indexname = 'poi_overture_search_trgm'), '[POI-2] trigram index on search_norm (name + address)');
select ok(exists (select 1 from pg_indexes where indexname = 'poi_overture_location'), '[POI-3] GiST index on location');
select ok(not (select prosecdef from pg_proc where oid = 'public.search_pois(text, double precision, double precision, integer)'::regprocedure), 'search_pois is SECURITY INVOKER');

-- ------------------------------------------------------------------ authenticated user ----
select tests.authenticate_as('dave');
select is((select count(*)::int from public.poi_overture), 31, '[POI-1] any signed-in user can read the catalogue');
select throws_ok($$insert into public.poi_overture (id, name, latitude, longitude, confidence) values (gen_random_uuid(), 'x', 1, 1, 0.9)$$, '42501', null, '[POI-1] client INSERT is denied');
select throws_ok($$update public.poi_overture set name = 'hacked'$$, '42501', null, '[POI-1] client UPDATE is denied');
select throws_ok($$delete from public.poi_overture$$, '42501', null, '[POI-1] client DELETE is denied');
select throws_ok($$insert into public.poi_overture_imports (release, row_count, filters) values ('x', 1, 'x')$$, '42501', null, '[POI-1] client cannot write import log');

select is((select name from public.search_pois('oc oanh', 10.77, 106.70) limit 1), 'Ốc Oanh', '[POI-2] unaccented query finds accented name (near HCM)');
select is((select name from public.search_pois('ỐC OANH', 21.03, 105.85) limit 1), 'Ốc Oanh 2', '[POI-3] same query near Hà Nội ranks the Hà Nội branch first');
select is((select name from public.search_pois('lang chu tich', 21.03, 105.85) limit 1), 'Lăng Chủ tịch Hồ Chí Minh', '[POI-2] partial words match');
select is((select name from public.search_pois('oc oanh vinh khanh', 21.03, 105.85) limit 1), 'Ốc Oanh', '[POI-2] address words help (name + address search)');
select is((select name from public.search_pois('Ốc Oanh Vĩnh Khánh', 21.0285, 105.8542) limit 1), 'Ốc Oanh', '[POI-3] word coverage beats a nearby partial match (Chùa Vĩnh Khánh in Hà Nội)');
select is((select name from public.search_pois('ca phe dinh') limit 1), 'Cà Phê Đinh', '[POI-2] works without a location');
select ok((select distance_m is null from public.search_pois('ca phe dinh') limit 1), '[POI-3] distance_m is null without a location');
select ok((select distance_m between 0 and 50 from public.search_pois('ca phe dinh', 21.0321, 105.8522) limit 1), '[POI-3] distance_m is metres from the given point');
select is((select count(*)::int from public.search_pois('pho so', 21.0, 105.8, 100)), 20, '[POI-4] max_results is capped at 20');
select is((select count(*)::int from public.search_pois('pho so', 21.0, 105.8, 0)), 1, '[POI-4] max_results below 1 becomes 1');
select is((select count(*)::int from public.search_pois('pho so')), 10, '[POI-4] default 10 results');
select is_empty($$select * from public.search_pois('a')$$, '[POI-4] queries shorter than 2 characters return nothing');
select is_empty($$select * from public.search_pois('ph', 21.0, 105.8)$$, '[POI-4] queries shorter than 3 normalized characters return nothing (cost guard)');
select results_eq($$select name from public.search_pois('oanh', 21.03, 105.85)$$, array['Ốc Oanh 2'], '[POI-4] short query with a location only searches nearby (~28 km box)');
select is_empty($$select * from public.search_pois('zzzz qqqq xxxx')$$, '[POI-2] unrelated query returns nothing');

-- ------------------------------------------------------------------ anon ----
select tests.authenticate_as_anon();
select throws_ok($$select * from public.search_pois('oc oanh')$$, '42501', null, '[POI-5] anon cannot call search_pois');
select tests.clear_authentication();

select * from finish();
rollback;
