-- Memories: single parent, author attribution, moderation, parent-scoped access, decision 4.
begin;
select plan(54);
select tests.seed_users();

-- Fixtures
insert into public.places (id, owner_id, title, latitude, longitude) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('alice'), 'Cafe A', 10.77, 106.70);
insert into public.place_members (place_id, user_id, role) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('bob'),   'EDITOR'),
  ('11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'VIEWER');
insert into public.visits (id, place_id, owner_id, created_by, visited_at, timezone_id) values
  ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), now(), 'UTC');
insert into public.visit_members (visit_id, user_id, role) values
  ('22222222-0000-0000-0000-000000000001', tests.u('erin'), 'EDITOR'),
  ('22222222-0000-0000-0000-000000000001', tests.u('dave'), 'VIEWER');
insert into public.journals (id, owner_id, title) values
  ('33333333-0000-0000-0000-000000000001', tests.u('alice'), 'Trip 1'),
  ('33333333-0000-0000-0000-000000000002', tests.u('alice'), 'Trip 2');
insert into public.journal_members (journal_id, user_id, role) values
  ('33333333-0000-0000-0000-000000000001', tests.u('bob'),   'EDITOR'),
  ('33333333-0000-0000-0000-000000000001', tests.u('carol'), 'VIEWER');
insert into public.journal_visits (id, journal_id, visit_id, added_by) values
  ('44444444-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', tests.u('alice')),
  ('44444444-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001', tests.u('alice'));

-- ============ CHECK constraints (as superuser: only the constraint can fail) =========
select throws_ok($$insert into public.memories (author_id, type, body) values (tests.u('alice'), 'NOTE', 'orphan')$$,
                 '23514', null, '[ERD-05] memory with NO parent rejected (one-parent CHECK)');
select throws_ok($$insert into public.memories (author_id, place_id, visit_id, body)
                   values (tests.u('alice'), '11111111-0000-0000-0000-00000000000a', '22222222-0000-0000-0000-000000000001', 'x')$$,
                 '23514', null, '[ERD-05] place + visit parents rejected');
select throws_ok($$insert into public.memories (author_id, place_id, journal_id, body)
                   values (tests.u('alice'), '11111111-0000-0000-0000-00000000000a', '33333333-0000-0000-0000-000000000001', 'x')$$,
                 '23514', null, '[ERD-05] place + journal parents rejected');
select throws_ok($$insert into public.memories (author_id, visit_id, journal_id, body)
                   values (tests.u('alice'), '22222222-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', 'x')$$,
                 '23514', null, '[ERD-05] visit + journal parents rejected');
select throws_ok($$insert into public.memories (author_id, place_id, journal_id, visit_id, body)
                   values (tests.u('alice'), '11111111-0000-0000-0000-00000000000a', '33333333-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', 'x')$$,
                 '23514', null, '[ERD-05] three parents rejected');
select lives_ok($$insert into public.memories (author_id, place_id, body) values (tests.u('alice'), '11111111-0000-0000-0000-00000000000a', 'one parent ok')$$,
                '[ERD-05] exactly one parent accepted');
select throws_ok($$insert into public.memories (author_id, place_id, journal_visit_id, body)
                   values (tests.u('alice'), '11111111-0000-0000-0000-00000000000a', '44444444-0000-0000-0000-000000000001', 'x')$$,
                 '23514', null, '[D4] journal_visit_id is rejected when the parent is a Place');
select throws_ok($$insert into public.memories (author_id, visit_id, journal_visit_id, body)
                   values (tests.u('alice'), '22222222-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000001', 'x')$$,
                 '23514', null, '[D4] journal_visit_id is rejected when the parent is a Visit');
select throws_ok($$insert into public.memories (author_id, journal_id, journal_visit_id, body)
                   values (tests.u('alice'), '33333333-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000002', 'x')$$,
                 '23503', null, '[D4] journal_visit_id must belong to the SAME journal (composite FK)');
select lives_ok($$insert into public.memories (author_id, journal_id, journal_visit_id, body)
                   values (tests.u('alice'), '33333333-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000001', 'ok')$$,
                '[D4] journal parent + journal_visit_id of the same journal accepted');
select throws_ok($$insert into public.memories (author_id, place_id, type, body)
                   values (tests.u('alice'), '11111111-0000-0000-0000-00000000000a', 'NOTE', '   ')$$,
                 '23514', null, 'NOTE needs a non-blank body');
select lives_ok($$insert into public.memories (author_id, place_id, type) values (tests.u('alice'), '11111111-0000-0000-0000-00000000000a', 'PHOTO')$$,
                'PHOTO memory may have no body (attachment carries the content)');
delete from public.memories;  -- reset the memories created by the constraint checks

-- ============ Place-parent memories ===================================================
select tests.authenticate_as('bob');
select lives_ok($$insert into public.memories (id, place_id, body) values ('55555555-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a', 'bob note')$$,
                'Place Editor can create a Memory on the Place');
select is((select author_id from public.memories where id = '55555555-0000-0000-0000-000000000001'), tests.u('bob'), '[6.3] author_id is server-stamped = auth.uid()');
select throws_ok($$insert into public.memories (author_id, place_id, body) values (tests.u('alice'), '11111111-0000-0000-0000-00000000000a', 'forged')$$,
                 '42501', null, '[6.3] Client forges author_id -> denied');
select throws_ok($$insert into public.memories (place_id, journal_id, body) values ('11111111-0000-0000-0000-00000000000a', '33333333-0000-0000-0000-000000000001', 'x')$$,
                 '23514', null, '[ERD-05] a client cannot smuggle a second parent (CHECK holds for authenticated callers too)');
select throws_ok($$insert into public.memories (visit_id, body) values ('22222222-0000-0000-0000-000000000001', 'x')$$,
                 '42501', null, 'Place Editor is not a Visit member: cannot add a Memory to the Visit (no inheritance)');
select tests.clear_authentication();

select tests.authenticate_as('carol');
select throws_ok($$insert into public.memories (place_id, body) values ('11111111-0000-0000-0000-00000000000a', 'viewer note')$$,
                 '42501', null, '[6.3] Viewer inserts Memory -> denied');
select is((select count(*)::int from public.memories where id = '55555555-0000-0000-0000-000000000001'), 1, 'Viewer reads Memories of the shared Place');
select is(tests.affected($$update public.memories set body = 'viewer edit' where id = '55555555-0000-0000-0000-000000000001'$$), 0::bigint, 'Viewer cannot edit a Memory');
select tests.clear_authentication();

select tests.authenticate_as('dave');
select throws_ok($$insert into public.memories (place_id, body) values ('11111111-0000-0000-0000-00000000000a', 'outsider')$$,
                 '42501', null, 'Non-member cannot add a Memory');
select is_empty($$select * from public.memories where id = '55555555-0000-0000-0000-000000000001'$$, 'Non-member cannot read Place memories (no independent right outside the parent)');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select lives_ok($$insert into public.memories (id, place_id, body) values ('55555555-0000-0000-0000-000000000002', '11111111-0000-0000-0000-00000000000a', 'alice note')$$,
                'Owner can create a Memory');
select is((select count(*)::int from public.memories where place_id = '11111111-0000-0000-0000-00000000000a'), 2, 'Owner reads all Memories of the Place (incl. contributor''s)');
select tests.clear_authentication();

select tests.authenticate_as('bob');
select is(tests.affected($$update public.memories set body = 'bob hijacks alice' where id = '55555555-0000-0000-0000-000000000002'$$), 0::bigint,
          '[6.3] Editor updates another user''s Memory -> denied (0 rows)');
select is(tests.affected($$update public.memories set body = 'bob edit' where id = '55555555-0000-0000-0000-000000000001'$$), 1::bigint, 'Editor edits own Memory');
select throws_ok($$update public.memories set author_id = tests.u('alice') where id = '55555555-0000-0000-0000-000000000001'$$, '42501', null, 'author_id is immutable');
select throws_ok($$update public.memories set place_id = null, visit_id = '22222222-0000-0000-0000-000000000001' where id = '55555555-0000-0000-0000-000000000001'$$, '42501', null, 'a Memory cannot be re-parented');
select throws_ok($$delete from public.memories where id = '55555555-0000-0000-0000-000000000001'$$, '42501', null, 'hard DELETE of a Memory not allowed');
select tests.clear_authentication();

-- Moderation by parent owner
select tests.authenticate_as('alice');
select throws_ok($$update public.memories set body = 'rewritten by owner' where id = '55555555-0000-0000-0000-000000000001'$$, '42501', null,
                 'Owner moderation cannot rewrite a contributor''s text');
select is(tests.affected($$update public.memories set deleted_at = now() where id = '55555555-0000-0000-0000-000000000001'$$), 1::bigint, '[ERD-08] parent Owner can moderate (soft-delete) a contributor''s Memory');
select tests.clear_authentication();
select is((select count(*)::int from public.audit_log where action = 'MEMORY_MODERATED' and resource_id = '55555555-0000-0000-0000-000000000001' and actor_id = tests.u('alice') and target_user_id = tests.u('bob')),
          1, 'moderation is audited with actor + contributor');
select tests.authenticate_as('carol');
select is_empty($$select * from public.memories where id = '55555555-0000-0000-0000-000000000001'$$, 'soft-deleted Memory is hidden from other readers');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is((select count(*)::int from public.memories where id = '55555555-0000-0000-0000-000000000001'), 1, '[ERD-08] contributor keeps attribution: author still sees the tombstone');
select tests.clear_authentication();

-- ============ Visit-parent memories ==================================================
select tests.authenticate_as('erin');
select lives_ok($$insert into public.memories (id, visit_id, body) values ('55555555-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000001', 'erin visit note')$$,
                'Visit Editor can add a Memory to the Visit');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select is((select count(*)::int from public.memories where id = '55555555-0000-0000-0000-000000000003'), 1, 'Visit Viewer reads Visit memories');
select throws_ok($$insert into public.memories (visit_id, body) values ('22222222-0000-0000-0000-000000000001', 'viewer')$$, '42501', null, 'Visit Viewer cannot add Memory');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is_empty($$select * from public.memories where id = '55555555-0000-0000-0000-000000000003'$$, 'Place Viewer cannot read Visit memories (no leak through Place share)');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is_empty($$select * from public.memories where id = '55555555-0000-0000-0000-000000000003'$$, 'Place Editor cannot read Visit memories either');
select tests.clear_authentication();

-- ============ Journal-parent memories + decision 4 =====================================
select tests.authenticate_as('bob');
select lives_ok($$insert into public.memories (id, journal_id, journal_visit_id, body)
                   values ('55555555-0000-0000-0000-000000000004', '33333333-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000001', 'journal note about the visit')$$,
                '[D4] Journal Editor adds a Memory in Journal context pointing at a linked Visit');
select results_eq($$select journal_id, visit_id, place_id, journal_visit_id from public.memories where id = '55555555-0000-0000-0000-000000000004'$$,
                  $$values ('33333333-0000-0000-0000-000000000001'::uuid, null::uuid, null::uuid, '44444444-0000-0000-0000-000000000001'::uuid)$$,
                  '[D4] parent is the Journal; journal_visit_id is only a non-parent reference');
select throws_ok($$insert into public.memories (journal_id, body) values ('33333333-0000-0000-0000-000000000002', 'x')$$, '42501', null, 'Editor of Journal 1 cannot write into Journal 2');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is((select count(*)::int from public.memories where id = '55555555-0000-0000-0000-000000000004'), 1, 'Journal Viewer reads Journal memories');
select throws_ok($$insert into public.memories (journal_id, body) values ('33333333-0000-0000-0000-000000000001', 'viewer')$$, '42501', null, 'Journal Viewer cannot add Memory');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select is_empty($$select * from public.memories where id = '55555555-0000-0000-0000-000000000004'$$, 'Visit Viewer cannot read Journal memories (journal_visit_id grants nothing)');
select tests.clear_authentication();

-- Unlinking the visit from the journal keeps the memory (SET NULL only on journal_visit_id)
select tests.authenticate_as('alice');
select is(tests.affected($$delete from public.journal_visits where id = '44444444-0000-0000-0000-000000000001'$$), 1::bigint, 'owner unlinks the Visit from the Journal');
select tests.clear_authentication();
select results_eq($$select journal_id, journal_visit_id from public.memories where id = '55555555-0000-0000-0000-000000000004'$$,
                  $$values ('33333333-0000-0000-0000-000000000001'::uuid, null::uuid)$$,
                  '[D4] memory survives the unlink; only journal_visit_id is nulled, parent unchanged');

-- ============ revocation ==============================================================
select tests.authenticate_as('alice');
select lives_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('carol'))$$, 'owner removes viewer carol');
select lives_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('bob'))$$, 'owner removes editor bob');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is_empty($$select * from public.memories where place_id = '11111111-0000-0000-0000-00000000000a'$$, '[6.3] Removed member reads Memories after revocation -> denied');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is_empty($$select * from public.memories where place_id = '11111111-0000-0000-0000-00000000000a'$$, 'Removed editor reads nothing on the Place');
select throws_ok($$insert into public.memories (place_id, body) values ('11111111-0000-0000-0000-00000000000a', 'back door')$$, '42501', null, 'Removed editor cannot add Memories');
select is(tests.affected($$update public.memories set body = 'late edit' where id = '55555555-0000-0000-0000-000000000001'$$), 0::bigint, 'Removed editor cannot edit his earlier Memory');
select tests.clear_authentication();
select is((select author_id from public.memories where id = '55555555-0000-0000-0000-000000000001'), tests.u('bob'), '[ERD-08] contributor content keeps created attribution after removal');

select * from finish();
rollback;
