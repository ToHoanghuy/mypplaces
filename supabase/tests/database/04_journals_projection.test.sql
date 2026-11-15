-- Journals: membership, linking rules, live scoped projection (decision 5 / ERD-04), archive, soft delete.
begin;
select plan(69);
select tests.seed_users();

-- Fixtures: alice owns Cafe A (+2 visits, sibling visit, private notes), Home; bob owns Bob Bar (+visit).
insert into public.places (id, owner_id, title, latitude, longitude, address, provider, provider_place_id) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('alice'), 'Cafe A', 10.7769, 106.7009, 'Secret Street 1', 'apple', 'X1'),
  ('11111111-0000-0000-0000-00000000000b', tests.u('alice'), 'Home',   10.8000, 106.6000, 'My home', null, null),
  ('11111111-0000-0000-0000-0000000000b1', tests.u('bob'),   'Bob Bar', 10.7000, 106.8000, 'Bob street', null, null);
insert into public.visits (id, place_id, owner_id, created_by, visited_at, timezone_id, note) values
  ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), '2026-11-01 05:00+00', 'Asia/Ho_Chi_Minh', 'v1 PRIVATE NOTE'),
  ('22222222-0000-0000-0000-000000000002', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), '2026-11-02 05:00+00', 'Asia/Ho_Chi_Minh', 'v2 sibling'),
  ('22222222-0000-0000-0000-0000000000b1', '11111111-0000-0000-0000-0000000000b1', tests.u('bob'),   tests.u('bob'),   '2026-11-04 05:00+00', 'Asia/Ho_Chi_Minh', 'bob visit');
insert into public.visit_participants (visit_id, user_id, display_name_snapshot, added_by) values
  ('22222222-0000-0000-0000-000000000001', null, 'Secret Guest', tests.u('alice'));
insert into public.memories (id, author_id, place_id, body) values
  ('55555555-0000-0000-0000-000000000001', tests.u('alice'), '11111111-0000-0000-0000-00000000000a', 'private place memory');
insert into public.journals (id, owner_id, title) values
  ('33333333-0000-0000-0000-000000000001', tests.u('alice'), 'Trip 1');
insert into public.journal_members (journal_id, user_id, role, status) values
  ('33333333-0000-0000-0000-000000000001', tests.u('bob'),   'EDITOR', 'ACTIVE'),
  ('33333333-0000-0000-0000-000000000001', tests.u('carol'), 'VIEWER', 'ACTIVE'),
  ('33333333-0000-0000-0000-000000000001', tests.u('erin'),  'VIEWER', 'REMOVED');

-- ============ linking rules ========================================================
select tests.authenticate_as('alice');
select lives_ok($$insert into public.journal_places (id, journal_id, place_id) values ('66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a')$$,
                'Journal owner links her own Place');
select lives_ok($$insert into public.journal_visits (id, journal_id, visit_id) values ('77777777-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001')$$,
                'Journal owner links her own Visit (association only, nothing is copied)');
select throws_ok($$insert into public.journal_places (journal_id, place_id) values ('33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a')$$,
                 '23505', null, 'duplicate Place link rejected (UNIQUE journal_id, place_id)');
select throws_ok($$insert into public.journal_visits (journal_id, visit_id) values ('33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001')$$,
                 '23505', null, 'duplicate Visit link rejected');
select throws_ok($$insert into public.journal_places (journal_id, place_id, added_by) values ('33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000b', tests.u('bob'))$$,
                 '42501', null, 'added_by cannot be forged');
select tests.clear_authentication();

select tests.authenticate_as('carol');
select throws_ok($$insert into public.journal_places (journal_id, place_id) values ('33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a')$$,
                 '42501', null, 'Journal Viewer cannot link');
select is(tests.affected($$delete from public.journal_places where id = '66666666-0000-0000-0000-000000000001'$$), 0::bigint, 'Journal Viewer cannot unlink');
select tests.clear_authentication();

select tests.authenticate_as('bob');
select throws_ok($$insert into public.journal_places (journal_id, place_id) values ('33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000b')$$,
                 '42501', null, 'Journal Editor cannot link a Place he does not own (linking exposes a projection; only the Place owner decides)');
select lives_ok($$insert into public.journal_places (id, journal_id, place_id) values ('66666666-0000-0000-0000-0000000000b1', '33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-0000000000b1')$$,
                'Journal Editor links his own Place');
select lives_ok($$insert into public.journal_visits (id, journal_id, visit_id) values ('77777777-0000-0000-0000-0000000000b1', '33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-0000000000b1')$$,
                'Journal Editor links his own Visit');
select tests.clear_authentication();

select tests.authenticate_as('dave');
select throws_ok($$insert into public.journal_places (journal_id, place_id) values ('33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000b')$$,
                 '42501', null, 'Non-member cannot link into the Journal');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select is((select count(*)::int from public.journals), 1, '[6.3] Owner reads own Journal');
select tests.clear_authentication();

-- ============ [6.3] Journal Viewer reads linked Place via projection only ===============
select tests.authenticate_as('carol');
select results_eq($$select title, category::text, latitude, longitude from public.journal_places_projection('33333333-0000-0000-0000-000000000001') order by title$$,
                  $$values ('Bob Bar'::text, 'OTHER'::text, 10.7::float8, 106.8::float8), ('Cafe A'::text, 'OTHER'::text, 10.7769::float8, 106.7009::float8)$$,
                  '[6.3][D5] Journal Viewer sees linked Places through the projection (scoped fields)');
select is(position('address' in pg_get_function_result('public.journal_places_projection(uuid)'::regprocedure)), 0, '[D5] place projection exposes no address');
select is(position('provider' in pg_get_function_result('public.journal_places_projection(uuid)'::regprocedure)), 0, '[D5] place projection exposes no provider id');
select is_empty($$select * from public.places$$, '[6.3][D5] direct Place table access denied for Journal member');
select is_empty($$select * from public.places where id = '11111111-0000-0000-0000-00000000000a'$$, '[D5] ...even for a Place linked into the Journal');
select is_empty($$select * from public.visits$$, '[D5] direct Visit table access denied for Journal member');
select results_eq($$select visit_id, place_title, visited_at from public.journal_visits_projection('33333333-0000-0000-0000-000000000001') order by visited_at$$,
                  $$values ('22222222-0000-0000-0000-000000000001'::uuid, 'Cafe A'::text, '2026-11-01 05:00+00'::timestamptz),
                           ('22222222-0000-0000-0000-0000000000b1'::uuid, 'Bob Bar'::text, '2026-11-04 05:00+00'::timestamptz)$$,
                  '[D5] linked Visits are projected (date + place title); sibling Visit V2 is not');
select is(position('note' in pg_get_function_result('public.journal_visits_projection(uuid)'::regprocedure)), 0, '[D5] visit projection exposes no private note');
select is(position('participant' in pg_get_function_result('public.journal_visits_projection(uuid)'::regprocedure)), 0, '[D5] visit projection exposes no participants');
select is_empty($$select * from public.visit_participants$$, 'participants are not readable through the Journal');
select is_empty($$select * from public.memories where id = '55555555-0000-0000-0000-000000000001'$$, '[D5] Journal access does not expose Place memories');
select is((select count(*)::int from public.journal_places), 2, 'association rows (ids only) readable by Journal members');
select tests.clear_authentication();

-- ============ projection is LIVE (no snapshot) ==========================================
select tests.authenticate_as('alice');
select is(tests.affected($$update public.places set title = 'Cafe A (renamed)', latitude = 11.0 where id = '11111111-0000-0000-0000-00000000000a'$$), 1::bigint, 'owner renames Place and moves the pin');
select is(tests.affected($$update public.visits set visited_at = '2026-11-09 05:00+00' where id = '22222222-0000-0000-0000-000000000001'$$), 1::bigint, 'owner edits Visit date');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select results_eq($$select title, latitude from public.journal_places_projection('33333333-0000-0000-0000-000000000001') where place_id = '11111111-0000-0000-0000-00000000000a'$$,
                  $$values ('Cafe A (renamed)'::text, 11.0::float8)$$, '[D5] projection reflects the rename immediately (live, not a snapshot)');
select is((select visited_at from public.journal_visits_projection('33333333-0000-0000-0000-000000000001') where visit_id = '22222222-0000-0000-0000-000000000001'),
          '2026-11-09 05:00+00'::timestamptz, '[D5] projection reflects the Visit edit immediately');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select is(tests.affected($$update public.places set deleted_at = now() where id = '11111111-0000-0000-0000-00000000000a'$$), 1::bigint, 'owner soft-deletes Cafe A');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is((select count(*)::int from public.journal_places_projection('33333333-0000-0000-0000-000000000001') where place_id = '11111111-0000-0000-0000-00000000000a'), 0, '[D5] soft-deleted Place disappears from the projection');
select is((select count(*)::int from public.journal_visits_projection('33333333-0000-0000-0000-000000000001') where visit_id = '22222222-0000-0000-0000-000000000001'), 0, '[D5] Visit of a soft-deleted Place disappears too (no place fields leak)');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select is(tests.affected($$update public.places set deleted_at = null where id = '11111111-0000-0000-0000-00000000000a'$$), 1::bigint, 'owner restores Cafe A');
select tests.clear_authentication();

-- ============ who can call the projection ================================================
select tests.authenticate_as('dave');
select is((select count(*)::int from public.journal_places_projection('33333333-0000-0000-0000-000000000001')), 0, 'non-member gets an empty projection (no existence leak)');
select is((select count(*)::int from public.journal_visits_projection('33333333-0000-0000-0000-000000000001')), 0, 'non-member gets an empty visit projection');
select tests.clear_authentication();
select tests.authenticate_as('erin');
select is((select count(*)::int from public.journal_places_projection('33333333-0000-0000-0000-000000000001')), 0, '[6.3] removed Journal member gets an empty projection');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is((select count(*)::int from public.journal_places_projection('33333333-0000-0000-0000-000000000001')), 2, 'Journal Editor gets the projection');
select tests.clear_authentication();

-- ============ unlink semantics ===========================================================
select tests.authenticate_as('bob');
select is(tests.affected($$delete from public.journal_places where id = '66666666-0000-0000-0000-000000000001'$$), 1::bigint, 'Journal Editor can unlink a Place (acceptance scenario)');
select tests.clear_authentication();
select is((select count(*)::int from public.places where id = '11111111-0000-0000-0000-00000000000a' and deleted_at is null), 1, 'unlinking only deletes the association: Place remains');
select is((select count(*)::int from public.visits where place_id = '11111111-0000-0000-0000-00000000000a'), 2, '...and its Visits remain');
select tests.authenticate_as('alice');
select lives_ok($$select public.remove_member('JOURNAL', '33333333-0000-0000-0000-000000000001', tests.u('bob'))$$, 'owner removes Journal editor bob');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is((select count(*)::int from public.journal_places_projection('33333333-0000-0000-0000-000000000001')), 0, '[6.3] removed editor loses the projection');
select is(tests.affected($$delete from public.journal_places where id = '66666666-0000-0000-0000-0000000000b1'$$), 1::bigint, 'Place owner can still withdraw his own Place from the Journal after removal');
select throws_ok($$insert into public.journal_visits (journal_id, visit_id) values ('33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-0000000000b1')$$, '42501', null, 'removed editor cannot link again');
select tests.clear_authentication();

-- ============ Journal metadata, archive, soft delete =====================================
select tests.authenticate_as('carol');
select is(tests.affected($$update public.journals set title = 'viewer edit' where id = '33333333-0000-0000-0000-000000000001'$$), 0::bigint, 'Journal Viewer cannot edit Journal');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select is(tests.affected($$update public.journals set title = 'Trip 1 (renamed)' where id = '33333333-0000-0000-0000-000000000001'$$), 1::bigint, 'Journal owner edits metadata');
select throws_ok($$update public.journals set end_date = '2026-01-01', start_date = '2026-02-01' where id = '33333333-0000-0000-0000-000000000001'$$, '23514', null, 'end_date before start_date rejected');
select throws_ok($$insert into public.journals (owner_id, title) values (tests.u('bob'), 'forged owner')$$, '42501', null, 'Client forges owner_id on Journal -> denied');
select lives_ok($$insert into public.journals (id, title) values ('33333333-0000-0000-0000-000000000009', 'Mine')$$, 'owner_id defaults to auth.uid()');
select is((select owner_id from public.journals where id = '33333333-0000-0000-0000-000000000009'), tests.u('alice'), 'Journal owner stamped by server');
select is((select count(*)::int from public.journal_members where journal_id = '33333333-0000-0000-0000-000000000009'), 0, '[D2] no owner membership row is created (owner_id is the source of truth)');
select throws_ok($$delete from public.journals where id = '33333333-0000-0000-0000-000000000009'$$, '42501', null, 'hard DELETE of a Journal not allowed');
select is(tests.affected($$update public.journals set archived_at = now() where id = '33333333-0000-0000-0000-000000000001'$$), 1::bigint, 'owner archives the Journal');
select throws_ok($$insert into public.memories (journal_id, body) values ('33333333-0000-0000-0000-000000000001', 'into archived')$$, '42501', null, 'archived Journal rejects new Memories (even from the owner)');
select throws_ok($$insert into public.journal_places (journal_id, place_id) values ('33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000b')$$, '42501', null, 'archived Journal rejects new links');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is((select count(*)::int from public.journal_visits_projection('33333333-0000-0000-0000-000000000001')), 2, 'archived Journal stays readable (both Visit links)');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select is(tests.affected($$update public.journals set archived_at = null where id = '33333333-0000-0000-0000-000000000001'$$), 1::bigint, 'owner unarchives');
select lives_ok($$insert into public.memories (journal_id, body) values ('33333333-0000-0000-0000-000000000001', 'now ok')$$, 'contributions work again after unarchive');
select is(tests.affected($$update public.journals set deleted_at = now() where id = '33333333-0000-0000-0000-000000000001'$$), 1::bigint, 'owner soft-deletes the Journal');
select is((select count(*)::int from public.journals where id = '33333333-0000-0000-0000-000000000001'), 1, 'owner still sees the tombstone');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is_empty($$select * from public.journals where id = '33333333-0000-0000-0000-000000000001'$$, 'members no longer see a soft-deleted Journal');
select is((select count(*)::int from public.journal_visits_projection('33333333-0000-0000-0000-000000000001')), 0, 'projection of a soft-deleted Journal is empty');
select tests.clear_authentication();
select is((select count(*)::int from public.places where deleted_at is null), 3, 'deleting a Journal never touches canonical Places');

-- ============ membership visibility & profiles ============================================
select tests.authenticate_as('alice');
select is(tests.affected($$update public.journals set deleted_at = null where id = '33333333-0000-0000-0000-000000000001'$$), 1::bigint, 'owner restores the Journal');
select is((select count(*)::int from public.journal_members where journal_id = '33333333-0000-0000-0000-000000000001'), 3, 'owner sees all membership rows incl. REMOVED history');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is((select count(*)::int from public.journal_members where journal_id = '33333333-0000-0000-0000-000000000001'), 1, 'member sees only ACTIVE rows (bob was removed, erin removed; carol herself)');
select is((select count(*)::int from public.profiles where id = tests.u('alice')), 1, 'member reads the owner''s profile');
select is((select count(*)::int from public.profiles where id = tests.u('dave')), 0, 'member cannot read unrelated profiles');
select tests.clear_authentication();
select tests.authenticate_as('erin');
select is((select status::text from public.journal_members where journal_id = '33333333-0000-0000-0000-000000000001'), 'REMOVED', 'removed member sees only her own REMOVED row');
select is_empty($$select * from public.journals$$, '[6.3] removed Journal member cannot read the Journal');
select tests.clear_authentication();

select * from finish();
rollback;
