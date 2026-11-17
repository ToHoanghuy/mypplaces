-- UI v1.1 decisions (17/11/2026): map read model (#2), timeline in each Visit's timezone (#6),
-- companion suggestions (#4), invitation expiry options 1/7/30 days (#5).
-- Tags: [UI-2] [UI-4] [UI-5] [UI-6], [ERD-03] = shared Place never exposes the owner's Visit history.
begin;
select plan(61);
select tests.seed_users();

-- ------------------------------------------------------------------ fixtures (postgres) ----
insert into public.places (id, owner_id, title, category, latitude, longitude, address) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('alice'), 'Cafe A',  'CAFE',  10.7769, 106.7009, 'Secret Street 1'),
  ('11111111-0000-0000-0000-00000000000b', tests.u('alice'), 'Wishlist','TRAVEL',16.0544, 108.2022, null),
  ('11111111-0000-0000-0000-00000000000c', tests.u('alice'), 'Gone',    'FOOD',  21.0285, 105.8542, null);
update public.places set deleted_at = now() where id = '11111111-0000-0000-0000-00000000000c';
insert into public.place_members (place_id, user_id, role, status) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('bob'),   'EDITOR', 'ACTIVE'),
  ('11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'VIEWER', 'ACTIVE'),
  ('11111111-0000-0000-0000-00000000000a', tests.u('erin'),  'VIEWER', 'REMOVED');
insert into public.visits (id, place_id, owner_id, created_by, visited_at, timezone_id, note) values
  ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), '2026-11-01 05:00+00', 'Asia/Ho_Chi_Minh', 'first'),
  ('22222222-0000-0000-0000-000000000002', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), '2026-11-02 05:00+00', 'Europe/Paris',     'second'),
  ('22222222-0000-0000-0000-000000000003', '11111111-0000-0000-0000-00000000000c', tests.u('alice'), tests.u('alice'), '2026-11-03 05:00+00', 'Asia/Tokyo',       'on deleted place'),
  ('22222222-0000-0000-0000-000000000009', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), '2026-11-04 05:00+00', 'UTC',              'deleted visit'),
  ('22222222-0000-0000-0000-000000000004', '11111111-0000-0000-0000-00000000000a', tests.u('bob'),   tests.u('bob'),   '2026-11-05 05:00+00', 'Asia/Ho_Chi_Minh', 'bob visit');
update public.visits set deleted_at = now() where id = '22222222-0000-0000-0000-000000000009';
insert into public.visit_members (visit_id, user_id, role) values
  ('22222222-0000-0000-0000-000000000001', tests.u('dave'), 'VIEWER');
insert into public.visit_participants (visit_id, user_id, display_name_snapshot, added_by) values
  ('22222222-0000-0000-0000-000000000001', tests.u('erin'), null, tests.u('alice')),
  ('22222222-0000-0000-0000-000000000001', null, 'Uncle Tom', tests.u('alice'));
insert into public.memories (id, author_id, visit_id, place_id, type, body) values
  ('55555555-0000-0000-0000-000000000001', tests.u('alice'), '22222222-0000-0000-0000-000000000001', null, 'PHOTO', null),
  ('55555555-0000-0000-0000-000000000002', tests.u('alice'), '22222222-0000-0000-0000-000000000002', null, 'PHOTO', null),
  ('55555555-0000-0000-0000-000000000003', tests.u('alice'), null, '11111111-0000-0000-0000-00000000000b', 'PHOTO', null),
  ('55555555-0000-0000-0000-000000000009', tests.u('alice'), '22222222-0000-0000-0000-000000000009', null, 'PHOTO', null);
insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
select a.id, a.mem, tests.media_path('alice', a.mem, a.id), 'image/jpeg', 1000
from (values ('66666666-0000-0000-0000-000000000001'::uuid, '55555555-0000-0000-0000-000000000001'::uuid),
             ('66666666-0000-0000-0000-000000000002'::uuid, '55555555-0000-0000-0000-000000000002'::uuid),
             ('66666666-0000-0000-0000-000000000003'::uuid, '55555555-0000-0000-0000-000000000003'::uuid),
             ('66666666-0000-0000-0000-000000000009'::uuid, '55555555-0000-0000-0000-000000000009'::uuid)) as a(id, mem);

-- ------------------------------------------------------------------ structure ----
select ok((select coalesce(c.reloptions @> array['security_invoker=true'], false) from pg_class c
           where c.oid = 'public.map_places'::regclass), '[UI-2] map_places is a security_invoker view (RLS of base tables applies)');
select ok(has_table_privilege('authenticated', 'public.map_places', 'select'), '[UI-2] authenticated may read map_places');
select ok(not has_table_privilege('anon', 'public.map_places', 'select'), '[UI-2] anon cannot read map_places');
select ok(not has_table_privilege('authenticated', 'public.map_places', 'insert'), '[UI-2] map_places is read-only for clients');
select ok(not has_function_privilege('anon', 'public.my_timeline(timestamptz,timestamptz,public.place_category,uuid,integer)', 'execute'), '[UI-6] anon cannot execute my_timeline');
select ok(not has_function_privilege('anon', 'public.list_companion_suggestions(text,integer)', 'execute'), '[UI-4] anon cannot execute list_companion_suggestions');
select ok(has_function_privilege('authenticated', 'public.my_timeline(timestamptz,timestamptz,public.place_category,uuid,integer)', 'execute'), '[UI-6] authenticated may execute my_timeline');
select ok(has_function_privilege('authenticated', 'public.list_companion_suggestions(text,integer)', 'execute'), '[UI-4] authenticated may execute list_companion_suggestions');
select ok((select not prosecdef from pg_proc where oid = 'public.list_companion_suggestions(text,integer)'::regprocedure),
          '[UI-4] list_companion_suggestions runs as SECURITY INVOKER (RLS of the caller applies)');
select ok((select prosecdef and proconfig @> array['search_path=""'] from pg_proc
           where oid = 'public.my_timeline(timestamptz,timestamptz,public.place_category,uuid,integer)'::regprocedure),
          '[UI-6] my_timeline is SECURITY DEFINER with an empty search_path');
select hasnt_column('public', 'places', 'status', '[UI-2] no status column on places (status is derived)');
select hasnt_column('public', 'places', 'is_favorite', '[UI-3] no favourite column in v1 (P1)');

-- ------------------------------------------------------------------ anonymous ----
select tests.authenticate_as_anon();
select throws_ok($$select * from public.map_places$$, '42501', null, '[UI-2] anonymous cannot read map_places');
select throws_ok($$select * from public.my_timeline()$$, '42501', null, '[UI-6] anonymous cannot call my_timeline');
select throws_ok($$select * from public.list_companion_suggestions()$$, '42501', null, '[UI-4] anonymous cannot call list_companion_suggestions');
select tests.clear_authentication();

-- ------------------------------------------------------------------ map: owner ----
select tests.authenticate_as('alice');
select is((select count(*)::int from public.map_places), 2, '[UI-2] owner map shows live Places only (deleted Place hidden)');
select results_eq($$select visit_count, visit_status, last_visited_at, cover_memory_id, is_owner, my_role::text, is_shared
                    from public.map_places where place_id = '11111111-0000-0000-0000-00000000000a'$$,
                  $$values (2, 'VISITED', '2026-11-02 05:00+00'::timestamptz, '55555555-0000-0000-0000-000000000002'::uuid, true, 'OWNER', true)$$,
                  '[UI-2] owner: Cafe A VISITED, 2 live visits (deleted + Editor''s private visit excluded), cover = newest visit photo, shared');
select results_eq($$select visit_count, visit_status, last_visited_at is null, cover_memory_id, is_shared
                    from public.map_places where place_id = '11111111-0000-0000-0000-00000000000b'$$,
                  $$values (0, 'WANT_TO_VISIT', true, '55555555-0000-0000-0000-000000000003'::uuid, false)$$,
                  '[UI-2] place with no live visit = WANT_TO_VISIT; cover falls back to a Place photo');
select is((select cover_storage_path from public.map_places where place_id = '11111111-0000-0000-0000-00000000000a'),
          tests.media_path('alice', '55555555-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000002'),
          '[UI-2] cover_storage_path is the attachment path (client signs it)');
select tests.clear_authentication();

-- ------------------------------------------------------------------ map: Place VIEWER / EDITOR / visit member ----
select tests.authenticate_as('carol');
select results_eq($$select place_id, visit_count, visit_status, last_visited_at is null, cover_memory_id is null, my_role::text, is_owner, is_shared from public.map_places$$,
                  $$values ('11111111-0000-0000-0000-00000000000a'::uuid, 0, 'WANT_TO_VISIT', true, true, 'VIEWER', false, true)$$,
                  '[UI-2][ERD-03] Place Viewer: only the shared Place; owner''s Visit count/date/photos NOT exposed');
select tests.clear_authentication();

select tests.authenticate_as('bob');
select results_eq($$select visit_count, visit_status, last_visited_at, my_role::text from public.map_places$$,
                  $$values (1, 'VISITED', '2026-11-05 05:00+00'::timestamptz, 'EDITOR')$$,
                  '[UI-2][ERD-03] Place Editor: counts only own Visit, not the owner''s');
select tests.clear_authentication();

select tests.authenticate_as('dave');
select is_empty($$select * from public.map_places$$, '[UI-2] Visit member without Place access has no map Place');
select tests.clear_authentication();

select tests.authenticate_as('erin');
select is_empty($$select * from public.map_places$$, '[UI-2] REMOVED Place member sees nothing on the map');
select tests.clear_authentication();

-- ------------------------------------------------------------------ timeline ----
select tests.authenticate_as('alice');
select results_eq($$select visit_id from public.my_timeline()$$,
                  $$values ('22222222-0000-0000-0000-000000000003'::uuid), ('22222222-0000-0000-0000-000000000002'::uuid), ('22222222-0000-0000-0000-000000000001'::uuid)$$,
                  '[UI-6] owner timeline: own live Visits newest first (deleted Visit and others'' Visits excluded)');
select results_eq($$select timezone_id, visited_local from public.my_timeline() order by visited_at$$,
                  $$values ('Asia/Ho_Chi_Minh', '2026-11-01 12:00'::timestamp), ('Europe/Paris', '2026-11-02 06:00'::timestamp), ('Asia/Tokyo', '2026-11-03 14:00'::timestamp)$$,
                  '[UI-6] each Visit is expressed in its OWN timezone_id (visited_local)');
select results_eq($$select place_title, place_category::text, place_available from public.my_timeline(p_visit_id => '22222222-0000-0000-0000-000000000003')$$,
                  $$values ('Gone', 'FOOD', false)$$,
                  '[UI-6][D3] Visit owner keeps the Place projection even when the Place is soft-deleted');
select results_eq($$select my_role::text, note, cover_memory_id from public.my_timeline(p_visit_id => '22222222-0000-0000-0000-000000000002')$$,
                  $$values ('OWNER', 'second', '55555555-0000-0000-0000-000000000002'::uuid)$$,
                  '[UI-6] owner row: role, note, cover photo of the Visit');
select is((select count(*)::int from public.my_timeline(p_category => 'CAFE')), 2, '[UI-6] category filter');
select is((select count(*)::int from public.my_timeline(p_from => '2026-11-02 00:00+00', p_to => '2026-11-03 00:00+00')), 1, '[UI-6] date range filter [from, to)');
select results_eq($$select visit_id from public.my_timeline(p_limit => 1)$$, $$values ('22222222-0000-0000-0000-000000000003'::uuid)$$, '[UI-6] limit');
select is((select count(*)::int from public.my_timeline(p_limit => 0)), 1, '[UI-6] limit is clamped to >= 1');
select tests.clear_authentication();

select tests.authenticate_as('dave');
select results_eq($$select visit_id, my_role::text, place_title, place_category::text, place_available, cover_memory_id, timezone_id
                    from public.my_timeline()$$,
                  $$values ('22222222-0000-0000-0000-000000000001'::uuid, 'VIEWER', 'Cafe A', 'CAFE', true, '55555555-0000-0000-0000-000000000001'::uuid, 'Asia/Ho_Chi_Minh')$$,
                  '[UI-6] Visit Viewer sees the shared Visit with a minimal Place projection, its own timezone and photo');
select is_empty($$select * from public.my_timeline(p_visit_id => '22222222-0000-0000-0000-000000000002')$$, '[ERD-03] Visit Viewer cannot read a sibling Visit via my_timeline');
select is_empty($$select * from public.places$$, '[ERD-03] places RLS is NOT widened for the Visit member');
select tests.clear_authentication();

select tests.authenticate_as('carol');
select is_empty($$select * from public.my_timeline()$$, '[ERD-03] Place Viewer gets no Visit history from my_timeline');
select tests.clear_authentication();

select tests.authenticate_as('erin');
select is_empty($$select * from public.my_timeline()$$, '[ERD-01] participant (not member) gets no Visit from my_timeline');
select tests.clear_authentication();

select tests.authenticate_as('bob');
select results_eq($$select visit_id, my_role::text from public.my_timeline()$$,
                  $$values ('22222222-0000-0000-0000-000000000004'::uuid, 'OWNER')$$, '[UI-6] Place Editor timeline: only own Visit');
select tests.clear_authentication();

-- ------------------------------------------------------------------ companions ----
select tests.authenticate_as('alice');
select set_eq($$select user_id from public.list_companion_suggestions()$$,
              array[tests.u('bob'), tests.u('carol'), tests.u('dave'), tests.u('erin')],
              '[UI-4] owner: Place co-members + Visit member + account participant');
select is((select count(*)::int from public.list_companion_suggestions() where user_id = tests.u('alice')), 0, '[UI-4] never suggests yourself');
select set_eq($$select user_id from public.list_companion_suggestions('CAR')$$, array[tests.u('carol')], '[UI-4] query filters display_name case-insensitively');
select is_empty($$select * from public.list_companion_suggestions('%')$$, '[UI-4] query is a plain substring (no LIKE wildcards)');
select is((select count(*)::int from public.list_companion_suggestions(null, 1)), 1, '[UI-4] limit');
select is((select display_name from public.list_companion_suggestions() where user_id = tests.u('bob')), 'Bob', '[UI-4] returns display_name');
select lives_ok($$insert into public.visit_participants (visit_id, user_id, added_by)
                  values ('22222222-0000-0000-0000-000000000002', tests.u('carol'), tests.u('alice'))$$,
                '[UI-4] a suggested account is accepted by the visit_participants INSERT policy');
select tests.clear_authentication();

select tests.authenticate_as('bob');
select set_eq($$select user_id from public.list_companion_suggestions()$$, array[tests.u('alice'), tests.u('carol')],
              '[UI-4] Place Editor: owner + ACTIVE co-member; REMOVED member and unrelated Visit people excluded');
select throws_ok($$insert into public.visit_participants (visit_id, user_id, added_by)
                   values ('22222222-0000-0000-0000-000000000004', tests.u('dave'), tests.u('bob'))$$,
                 '42501', null, '[UI-4] a non-suggested account (stranger) is still rejected by the INSERT policy');
select lives_ok($$insert into public.visit_participants (visit_id, display_name_snapshot, added_by)
                  values ('22222222-0000-0000-0000-000000000004', 'Bạn của Bob', tests.u('bob'))$$,
                '[UI-4] free-text companion name is always allowed');
select tests.clear_authentication();

select tests.authenticate_as('dave');
select set_eq($$select user_id from public.list_companion_suggestions()$$, array[tests.u('alice')],
              '[UI-4] Visit Viewer: only the Visit owner (participants of others'' Visits are not suggested)');
select tests.clear_authentication();

select tests.authenticate_as('erin');
select is_empty($$select * from public.list_companion_suggestions()$$, '[UI-4] REMOVED member / plain participant gets no suggestions');
select tests.clear_authentication();

-- ------------------------------------------------------------------ invitation expiry ----
select tests.authenticate_as('alice');
select results_eq($$select expires_at = now() + interval '7 days' from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000b', 'VIEWER')$$,
                  $$values (true)$$, '[UI-5] default expiry is 7 days');
select results_eq($$select expires_at = now() + interval '1 day' from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000b', 'VIEWER', null, null, interval '1 day')$$,
                  $$values (true)$$, '[UI-5] 1 day accepted');
select results_eq($$select expires_at = now() + interval '30 days' from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'EDITOR', null, null, interval '30 days')$$,
                  $$values (true)$$, '[UI-5] 30 days accepted');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000b', 'VIEWER', null, null, interval '3 days')$$,
                 'PT400', 'INVALID_EXPIRY', '[UI-5] 3 days rejected (only 1/7/30)');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000b', 'VIEWER', null, null, interval '12 hours')$$,
                 'PT400', 'INVALID_EXPIRY', '[UI-5] 12 hours rejected');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000b', 'VIEWER', null, null, interval '31 days')$$,
                 'PT400', 'INVALID_EXPIRY', '[UI-5] 31 days rejected');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000b', 'VIEWER', null, null, null)$$,
                 'PT400', 'INVALID_EXPIRY', '[UI-5] null ttl rejected');
select tests.clear_authentication();

-- ------------------------------------------------------------------ live behaviour (postgres mutates, users re-read) ----
update public.memories set deleted_at = now() where id = '55555555-0000-0000-0000-000000000002';
select tests.authenticate_as('alice');
select is((select cover_memory_id from public.map_places where place_id = '11111111-0000-0000-0000-00000000000a'),
          '55555555-0000-0000-0000-000000000001'::uuid, '[UI-2] deleted photo memory no longer used as cover (falls back to previous visit)');
select tests.clear_authentication();

update public.visits set deleted_at = now() where id in ('22222222-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000002');
select tests.authenticate_as('alice');
select results_eq($$select visit_count, visit_status, cover_memory_id is null from public.map_places where place_id = '11111111-0000-0000-0000-00000000000a'$$,
                  $$values (0, 'WANT_TO_VISIT', true)$$, '[UI-2] status is derived live: all visits deleted -> WANT_TO_VISIT');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select is_empty($$select * from public.my_timeline()$$, '[UI-6] deleted shared Visit disappears from the member timeline');
select tests.clear_authentication();

update public.visits set deleted_at = null where id = '22222222-0000-0000-0000-000000000001';
update public.places set deleted_at = now() where id = '11111111-0000-0000-0000-00000000000a';
select tests.authenticate_as('dave');
select results_eq($$select place_id, place_title is null, place_category is null, latitude is null, place_available from public.my_timeline()$$,
                  $$values ('11111111-0000-0000-0000-00000000000a'::uuid, true, true, true, false)$$,
                  '[UI-6] Visit member: Place fields hidden once the Place is soft-deleted');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is_empty($$select * from public.list_companion_suggestions()$$, '[UI-4] soft-deleted shared Place no longer yields suggestions');
select tests.clear_authentication();

select * from finish();
rollback;
