-- MYP-4 per-viewer Place order. Tags: [ORD-1] structure/grants, [ORD-2] own rows only,
-- [ORD-3] only readable Places, [ORD-4] set_place_order semantics, [ORD-5] anon denied.
begin;
select plan(28);
select tests.seed_users();

insert into public.places (id, owner_id, title, latitude, longitude) values
  ('33333333-0000-0000-0000-00000000000a', tests.u('alice'), 'Shared A',  10.77, 106.70),
  ('33333333-0000-0000-0000-00000000000b', tests.u('alice'), 'Private B', 10.78, 106.71),
  ('33333333-0000-0000-0000-00000000000c', tests.u('alice'), 'Private C', 10.79, 106.72);
insert into public.place_members (place_id, user_id, role, status) values
  ('33333333-0000-0000-0000-00000000000a', tests.u('bob'),   'VIEWER', 'ACTIVE'),
  ('33333333-0000-0000-0000-00000000000a', tests.u('carol'), 'VIEWER', 'LEFT');

-- ------------------------------------------------------------------ [ORD-1] ----
select ok((select relrowsecurity from pg_class where oid = 'public.place_user_order'::regclass), '[ORD-1] RLS enabled');
select table_privs_are('public', 'place_user_order', 'authenticated', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'], '[ORD-1] authenticated: CRUD (RLS-limited)');
select table_privs_are('public', 'place_user_order', 'anon', array[]::text[], '[ORD-5] anon: no privileges');
select ok(not (select prosecdef from pg_proc where oid = 'public.set_place_order(uuid[])'::regprocedure), '[ORD-1] set_place_order is SECURITY INVOKER');
select ok(exists (select 1 from pg_indexes where indexname = 'place_user_order_place_id_idx'), '[ORD-1] FK covering index on place_id');

-- ------------------------------------------------------------------ owner alice ----
select tests.authenticate_as('alice');
select is(public.set_place_order(array['33333333-0000-0000-0000-00000000000b', '33333333-0000-0000-0000-00000000000a', '33333333-0000-0000-0000-00000000000c']::uuid[]), 3, '[ORD-4] owner stores 3 positions');
select results_eq($$select place_id::text from public.place_user_order order by position$$,
  array['33333333-0000-0000-0000-00000000000b', '33333333-0000-0000-0000-00000000000a', '33333333-0000-0000-0000-00000000000c'], '[ORD-4] positions follow array order');
select results_eq($$select position from public.place_user_order order by position$$, array[0, 1, 2], '[ORD-4] positions are dense from 0');
select tests.clear_authentication();

-- ------------------------------------------------------------------ viewer bob ----
select tests.authenticate_as('bob');
select is((select count(*)::int from public.place_user_order), 0, '[ORD-2] viewer cannot see the owner''s order');
select is(public.set_place_order(array['33333333-0000-0000-0000-00000000000a']::uuid[]), 1, '[ORD-3] viewer orders a shared Place');
select is(public.set_place_order(array['33333333-0000-0000-0000-00000000000b', '33333333-0000-0000-0000-00000000000a']::uuid[]), 1, '[ORD-3] unreadable Place in the list is ignored');
select is((select position from public.place_user_order where place_id = '33333333-0000-0000-0000-00000000000a'), 0, '[ORD-3] ignored id does not take a position');
select throws_ok($$insert into public.place_user_order (place_id, position) values ('33333333-0000-0000-0000-00000000000b', 5)$$, '42501', null, '[ORD-3] direct insert for an unreadable Place is denied');
select throws_ok($$insert into public.place_user_order (user_id, place_id, position) values (tests.u('alice'), '33333333-0000-0000-0000-00000000000a', 5)$$, '42501', null, '[ORD-2] cannot insert a row for another user');
select is(tests.affected($$update public.place_user_order set position = 9 where user_id = tests.u('alice')$$), 0::bigint, '[ORD-2] cannot update another user''s rows');
select is(tests.affected($$delete from public.place_user_order where user_id = tests.u('alice')$$), 0::bigint, '[ORD-2] cannot delete another user''s rows');
select throws_ok($$update public.place_user_order set place_id = '33333333-0000-0000-0000-00000000000c'$$, '42501', null, '[ORD-3] cannot move own row onto an unreadable Place');
select throws_ok($$update public.place_user_order set position = -1$$, '23514', null, '[ORD-1] negative position rejected');
select tests.clear_authentication();

-- ------------------------------------------------------------------ others ----
select tests.authenticate_as('carol');
select is(public.set_place_order(array['33333333-0000-0000-0000-00000000000a']::uuid[]), 0, '[ORD-3] LEFT member cannot order the Place');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select is(public.set_place_order(array['33333333-0000-0000-0000-00000000000a', '33333333-0000-0000-0000-00000000000b']::uuid[]), 0, '[ORD-3] stranger stores nothing');
select throws_ok($$select public.set_place_order(array_fill(gen_random_uuid(), array[2001]))$$, '22023', null, '[ORD-4] list size is capped');
select tests.clear_authentication();

-- ------------------------------------------------------------------ alice again ----
select tests.authenticate_as('alice');
select results_eq($$select place_id::text from public.place_user_order order by position$$,
  array['33333333-0000-0000-0000-00000000000b', '33333333-0000-0000-0000-00000000000a', '33333333-0000-0000-0000-00000000000c'], '[ORD-2] owner order unaffected by the viewer''s order');
select is(public.set_place_order(array['33333333-0000-0000-0000-00000000000c', '33333333-0000-0000-0000-00000000000c', '33333333-0000-0000-0000-00000000000a']::uuid[]), 2, '[ORD-4] duplicates collapse to first position');
select results_eq($$select place_id::text from public.place_user_order order by position$$,
  array['33333333-0000-0000-0000-00000000000c', '33333333-0000-0000-0000-00000000000a'], '[ORD-4] full replace: ids not in the list are removed');
select is(public.set_place_order(array['33333333-0000-0000-0000-00000000000c', '33333333-0000-0000-0000-00000000000a']::uuid[]), 2, '[ORD-4] replaying the same order is idempotent');
select is((select count(*)::int from public.place_user_order), 2, '[ORD-4] replay does not duplicate rows');
select tests.clear_authentication();

select tests.authenticate_as('bob');
select results_eq($$select place_id::text from public.place_user_order$$, array['33333333-0000-0000-0000-00000000000a'], '[ORD-2] viewer order unaffected by the owner''s reorder');
select tests.clear_authentication();

select tests.authenticate_as_anon();
select throws_ok($$select public.set_place_order(array[]::uuid[])$$, '42501', null, '[ORD-5] anon cannot call set_place_order');
select tests.clear_authentication();

select * from finish();
rollback;
