-- Place / Visit RLS. Tags: [6.3] = mandatory case of ERD §6.3, [D1]..[D5] = approved decisions, [ERD-xx] = ERD defaults.
begin;
select plan(80);
select tests.seed_users();

-- Fixtures (postgres bypasses RLS).
insert into public.places (id, owner_id, title, latitude, longitude, address) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('alice'), 'Cafe A', 10.7769, 106.7009, 'Secret Street 1'),
  ('11111111-0000-0000-0000-00000000000b', tests.u('alice'), 'Home',   10.8000, 106.6000, 'My home');
insert into public.place_members (place_id, user_id, role) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('bob'),   'EDITOR'),
  ('11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'VIEWER');
insert into public.visits (id, place_id, owner_id, created_by, visited_at, timezone_id, note) values
  ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), '2026-11-01 05:00+00', 'Asia/Ho_Chi_Minh', 'v1 private note'),
  ('22222222-0000-0000-0000-000000000002', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), '2026-11-02 05:00+00', 'Asia/Ho_Chi_Minh', 'v2 private note'),
  ('22222222-0000-0000-0000-000000000003', '11111111-0000-0000-0000-00000000000b', tests.u('alice'), tests.u('alice'), '2026-11-03 05:00+00', 'Asia/Ho_Chi_Minh', 'home visit');
insert into public.visit_members (visit_id, user_id, role) values
  ('22222222-0000-0000-0000-000000000001', tests.u('dave'), 'VIEWER');
insert into public.visit_participants (visit_id, user_id, display_name_snapshot, added_by) values
  ('22222222-0000-0000-0000-000000000001', tests.u('erin'), null, tests.u('alice')),
  ('22222222-0000-0000-0000-000000000001', null, 'Uncle Tom', tests.u('alice'));

-- ============ anonymous ==========================================================
select tests.authenticate_as_anon();
select throws_ok($$select * from public.places$$, '42501', null, '[6.3] Anonymous reads private Place -> denied');
select throws_ok($$select * from public.visits$$, '42501', null, '[6.3] Anonymous reads Visit -> denied');
select throws_ok($$select * from public.my_visit_places()$$, '42501', null, '[D3] Anonymous cannot call my_visit_places');
select throws_ok($$select * from public.journal_places_projection('11111111-0000-0000-0000-00000000000a')$$, '42501', null, '[D5] Anonymous cannot call journal projection');
select tests.clear_authentication();

-- ============ owner ==============================================================
select tests.authenticate_as('alice');
select is((select count(*)::int from public.places), 2, '[6.3] Owner reads own Places');
select is((select count(*)::int from public.visits), 3, '[6.3] Owner reads own Visits');
select tests.clear_authentication();

-- ============ place VIEWER carol ==================================================
select tests.authenticate_as('carol');
select is((select title from public.places where id = '11111111-0000-0000-0000-00000000000a'), 'Cafe A', '[6.3] Active Place Viewer reads Place');
select is((select count(*)::int from public.places), 1, 'Place Viewer sees only the shared Place, not the owner''s other Places');
select is_empty($$select * from public.visits$$, '[6.3][ERD-03] Place Viewer reads sibling Visit via direct REST -> denied');
select is_empty($$select * from public.visits where id = '22222222-0000-0000-0000-000000000001'$$, '[6.3] Place Viewer cannot fetch a Visit by guessed id');
select throws_ok($$insert into public.visits (place_id, visited_at, timezone_id)
                   values ('11111111-0000-0000-0000-00000000000a', now(), 'UTC')$$, '42501', null, 'Place Viewer cannot create a Visit');
select is(tests.affected($$update public.places set title = 'hacked' where id = '11111111-0000-0000-0000-00000000000a'$$), 0::bigint, 'Place Viewer cannot update Place (0 rows)');
select is((select count(*)::int from public.place_members), 2, 'Place Viewer sees the ACTIVE member rows of the shared Place');
select is((select count(*)::int from public.profiles where id = tests.u('alice')), 1, 'co-member (owner) profile is readable');
select is((select count(*)::int from public.profiles where id = tests.u('dave')), 0, 'unrelated profile is not readable');
select tests.clear_authentication();

-- ============ place EDITOR bob ====================================================
select tests.authenticate_as('bob');
select is((select count(*)::int from public.places), 1, 'Place Editor reads the shared Place');
select is_empty($$select * from public.visits$$, '[ERD-03] Place Editor does not see the owner''s Visits');
select is(tests.affected($$update public.places set title = 'edited by editor' where id = '11111111-0000-0000-0000-00000000000a'$$), 0::bigint,
          '[ERD-02] Place Editor cannot edit Place metadata (0 rows)');
select lives_ok($$insert into public.visits (id, place_id, visited_at, timezone_id, note)
                   values ('22222222-0000-0000-0000-000000000004', '11111111-0000-0000-0000-00000000000a', '2026-11-05 05:00+00', 'Asia/Ho_Chi_Minh', 'bob visit')$$,
                '[D1] Place Editor may create a Visit on the shared Place');
select is((select owner_id from public.visits where id = '22222222-0000-0000-0000-000000000004'), tests.u('bob'),
          '[D1][ERD-06] the editor owns the Visit he created (owner_id defaults to auth.uid())');
select is((select created_by from public.visits where id = '22222222-0000-0000-0000-000000000004'), tests.u('bob'), '[D1] created_by = editor');
select throws_ok($$insert into public.visits (place_id, owner_id, created_by, visited_at, timezone_id)
                   values ('11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('bob'), now(), 'UTC')$$,
                 '42501', null, '[6.3] Client forges owner_id on Visit -> denied');
select throws_ok($$insert into public.visits (place_id, owner_id, created_by, visited_at, timezone_id)
                   values ('11111111-0000-0000-0000-00000000000a', tests.u('bob'), tests.u('alice'), now(), 'UTC')$$,
                 '42501', null, '[6.3] Client forges created_by on Visit -> denied');
select throws_ok($$insert into public.visits (place_id, visited_at, timezone_id)
                   values ('11111111-0000-0000-0000-00000000000b', now(), 'UTC')$$,
                 '42501', null, 'Editor of Place A cannot create a Visit on a different, unshared Place');
select is(tests.affected($$update public.visits set note = 'x' where id = '22222222-0000-0000-0000-000000000001'$$), 0::bigint,
          'Editor cannot update another owner''s Visit');
select is(tests.affected($$update public.visits set note = 'my edit' where id = '22222222-0000-0000-0000-000000000004'$$), 1::bigint,
          'Visit owner (editor) can edit own Visit metadata');
select results_eq($$select visit_id, title, latitude, longitude from public.my_visit_places()$$,
                  $$values ('22222222-0000-0000-0000-000000000004'::uuid, 'Cafe A', 10.7769::float8, 106.7009::float8)$$,
                  '[D3] Visit owner reads the minimal Place projection (title + coordinates)');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select is_empty($$select * from public.visits where id = '22222222-0000-0000-0000-000000000004'$$,
                '[6.3] Place owner cannot read the editor''s Visit ("read other private visits": No)');
select tests.clear_authentication();

-- ============ visit VIEWER dave (no Place membership) ===============================
select tests.authenticate_as('dave');
select is((select count(*)::int from public.visits), 1, '[6.3] Visit Viewer reads the shared Visit only');
select is((select id from public.visits), '22222222-0000-0000-0000-000000000001'::uuid, '[6.3] ...and it is the shared one');
select is_empty($$select * from public.visits where id = '22222222-0000-0000-0000-000000000002'$$, '[6.3] Visit Viewer: sibling Visit denied');
select is_empty($$select * from public.places$$, 'Visit share does not expose the Place (no Place access)');
select is(tests.affected($$update public.visits set note = 'x' where id = '22222222-0000-0000-0000-000000000001'$$), 0::bigint, 'Visit Viewer cannot update the Visit');
select is((select count(*)::int from public.visit_participants where visit_id = '22222222-0000-0000-0000-000000000001'), 2, 'Visit readers see the participant list');
select is_empty($$select * from public.my_visit_places()$$, '[D3] Visit Viewer (not owner) gets no Place projection');
select throws_ok($$insert into public.visit_participants (visit_id, display_name_snapshot)
                   values ('22222222-0000-0000-0000-000000000001', 'Intruder')$$, '42501', null, 'Visit Viewer cannot add participants');
select tests.clear_authentication();

-- ============ participant who is not a member: erin =================================
select tests.authenticate_as('erin');
select is_empty($$select * from public.visits$$, '[6.3] Participant (not member) reads Visit -> denied');
select is_empty($$select * from public.visit_participants$$, 'Participant (not member) cannot read the participant list');
select is((select count(*)::int from public.profiles), 1, 'Participant can only read her own profile');
select tests.clear_authentication();

-- ============ participants managed by Visit owner (ERD-01) ===========================
select tests.authenticate_as('alice');
select lives_ok($$insert into public.visit_participants (visit_id, display_name_snapshot)
                   values ('22222222-0000-0000-0000-000000000001', 'Aunt Lan')$$, '[ERD-01] guest participant (label only) can be stored');
select throws_ok($$insert into public.visit_participants (visit_id, user_id)
                   values ('22222222-0000-0000-0000-000000000001', tests.u('erin'))$$, '23505', null, 'same user cannot be a participant twice');
select lives_ok($$insert into public.visit_participants (visit_id, display_name_snapshot)
                   values ('22222222-0000-0000-0000-000000000001', 'Aunt Lan')$$, 'duplicate guest labels are allowed (no account to dedupe on)');
select is((select count(*)::int from public.visit_members where visit_id = '22222222-0000-0000-0000-000000000001'), 1,
          '[ERD-01] participants never create membership');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select throws_ok($$insert into public.visit_participants (visit_id, display_name_snapshot)
                   values ('22222222-0000-0000-0000-000000000001', 'Nope')$$, '42501', null, 'non-owner cannot add a participant');
select tests.clear_authentication();

-- ============ participants cannot be used to harvest profiles ==========================
select tests.authenticate_as('dave');
select lives_ok($$insert into public.places (id, title, latitude, longitude) values ('11111111-0000-0000-0000-0000000000d1', 'Dave own', 2, 2)$$, 'dave creates his own Place');
select lives_ok($$insert into public.visits (id, place_id, visited_at, timezone_id) values ('22222222-0000-0000-0000-0000000000d1', '11111111-0000-0000-0000-0000000000d1', now(), 'UTC')$$, '...and his own Visit');
select throws_ok($$insert into public.visit_participants (visit_id, user_id) values ('22222222-0000-0000-0000-0000000000d1', 'aaaaaaaa-0000-0000-0000-0000000000ff')$$,
                 '42501', null, 'cannot add an unknown/unrelated account UUID as participant (no account-existence probing)');
select is((select count(*)::int from public.profiles where id = tests.u('carol')), 0, 'carol (unrelated to dave) is not readable');
select throws_ok($$insert into public.visit_participants (visit_id, user_id) values ('22222222-0000-0000-0000-0000000000d1', tests.u('carol'))$$,
                 '42501', null, 'cannot add a stranger''s account as participant to read her profile');
select is((select count(*)::int from public.profiles where id = tests.u('carol')), 0, '...and her profile stays unreadable');
select tests.clear_authentication();

-- ============ forged ids / immutable columns =========================================
select tests.authenticate_as('dave');
select throws_ok($$insert into public.places (owner_id, title, latitude, longitude)
                   values (tests.u('alice'), 'forged', 1, 1)$$, '42501', null, '[6.3] Client forges owner_id on Place -> denied');
select lives_ok($$insert into public.places (id, title, latitude, longitude, created_at)
                   values ('11111111-0000-0000-0000-00000000000c', 'Dave place', 1, 1, '2000-01-01')$$, 'owner_id defaults to auth.uid()');
select is((select owner_id from public.places where id = '11111111-0000-0000-0000-00000000000c'), tests.u('dave'), '[6.3] server stamps owner_id = auth.uid()');
select is((select created_at from public.places where id = '11111111-0000-0000-0000-00000000000c'), now(), 'created_at is server generated (client value ignored)');
select throws_ok($$insert into public.places (id, title, latitude, longitude)
                   values ('11111111-0000-0000-0000-00000000000c', 'again', 1, 1)$$, '23505', null, 'plain retry with the same client UUID conflicts (23505)');
select lives_ok($$insert into public.places (id, title, latitude, longitude)
                   values ('11111111-0000-0000-0000-00000000000c', 'again', 1, 1) on conflict (id) do nothing$$, 'idempotent create: ON CONFLICT DO NOTHING (PostgREST ignore-duplicates)');
select is((select title from public.places where id = '11111111-0000-0000-0000-00000000000c'), 'Dave place', '...and does not overwrite the existing row');
select throws_ok($$update public.places set owner_id = tests.u('alice') where id = '11111111-0000-0000-0000-00000000000c'$$, '42501', null, 'owner cannot hand a Place over by direct UPDATE (use transfer_ownership)');
select throws_ok($$delete from public.places where id = '11111111-0000-0000-0000-00000000000c'$$, '42501', null, 'hard DELETE of a Place is not allowed (soft delete only)');
select is(tests.affected($$update public.places set deleted_at = now() where id = '11111111-0000-0000-0000-00000000000c'$$), 1::bigint, 'owner soft-deletes own Place via UPDATE deleted_at');
select is((select count(*)::int from public.places where id = '11111111-0000-0000-0000-00000000000c'), 1, 'owner still sees the tombstone');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select throws_ok($$update public.visits set place_id = '11111111-0000-0000-0000-00000000000b' where id = '22222222-0000-0000-0000-000000000001'$$,
                 '42501', null, 'visits.place_id is immutable');
select tests.clear_authentication();

-- ============ removal, unshare, soft delete; Visit owner keeps minimal projection [D3] ====
select tests.authenticate_as('alice');
select lives_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('bob'))$$, 'owner removes editor bob from the Place');
select tests.clear_authentication();

select tests.authenticate_as('bob');
select is_empty($$select * from public.places where id = '11111111-0000-0000-0000-00000000000a'$$, '[6.3] Removed member reads resource after revocation -> denied');
select is((select count(*)::int from public.visits where id = '22222222-0000-0000-0000-000000000004'), 1, '[D3] removed editor still reads his own Visit');
select is((select title from public.my_visit_places('22222222-0000-0000-0000-000000000004')), 'Cafe A',
          '[D3] ...and still gets the minimal Place projection after being unshared');
select throws_ok($$insert into public.visits (place_id, visited_at, timezone_id)
                   values ('11111111-0000-0000-0000-00000000000a', now(), 'UTC')$$, '42501', null, 'removed editor cannot create new Visits on the Place');
select is((select status::text from public.place_members where user_id = tests.u('bob')), 'REMOVED', 'removed user can see own membership row (knows access was revoked)');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select is(tests.affected($$update public.places set deleted_at = now() where id = '11111111-0000-0000-0000-00000000000a'$$), 1::bigint, 'owner soft-deletes the Place');
select throws_ok($$insert into public.visits (place_id, visited_at, timezone_id)
                   values ('11111111-0000-0000-0000-00000000000a', now(), 'UTC')$$, '42501', null, '[§8] soft-deleted Place prevents new Visits');
select is((select deleted_at is not null from public.places where id = '11111111-0000-0000-0000-00000000000a'), true, 'owner still reads the tombstone');
select tests.clear_authentication();

select tests.authenticate_as('carol');
select is_empty($$select * from public.places where id = '11111111-0000-0000-0000-00000000000a'$$, 'members no longer see a soft-deleted Place');
select tests.clear_authentication();

select tests.authenticate_as('bob');
select results_eq($$select title, place_deleted from public.my_visit_places()$$, $$values ('Cafe A'::text, true)$$,
                  '[D3] Visit owner reads the projection even when the Place is soft-deleted');
select is_empty($$select * from public.places$$, '[D3] places RLS is NOT widened: direct SELECT on the deleted/unshared Place stays empty');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select is(tests.affected($$update public.places set deleted_at = null where id = '11111111-0000-0000-0000-00000000000a'$$), 1::bigint, 'owner restores the Place');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is((select count(*)::int from public.places where id = '11111111-0000-0000-0000-00000000000a'), 1, 'after restore the remaining Viewer reads the Place again');
select tests.clear_authentication();
select is((select count(*)::int from public.audit_log where action in ('RESOURCE_DELETED', 'RESOURCE_RESTORED', 'MEMBER_REMOVED')), 4, -- dave's Place delete, Cafe A delete + restore, bob removal
          'lifecycle + member removal are audited');

-- ============ profiles =============================================================
select tests.authenticate_as('carol');
select is(tests.affected($$update public.profiles set display_name = 'Carol X' where id = tests.u('carol')$$), 1::bigint, 'user updates own profile');
select is(tests.affected($$update public.profiles set display_name = 'Pwned' where id = tests.u('alice')$$), 0::bigint, 'user cannot update someone else''s profile');
select throws_ok($$update public.profiles set id = tests.u('dave') where id = tests.u('carol')$$, '42501', null, 'profile id is immutable');
select tests.clear_authentication();

select * from finish();
rollback;
