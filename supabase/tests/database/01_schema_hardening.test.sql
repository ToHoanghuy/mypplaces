-- Structural / hardening checks: RLS everywhere, grants, helper function hygiene, constraints.
begin;
select plan(36);
select tests.seed_users();

select tables_are('public', array[
  'audit_log','invitations','journal_members','journal_places','journal_visits','journals',
  'memories','memory_attachments','place_members','places','profiles','visit_members',
  'visit_participants','visits'], 'public schema contains exactly the expected tables');

select is((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
          0::bigint, 'RLS is enabled on every public table');

select is((select count(*) from pg_constraint
            where contype = 'f' and confdeltype = 'c' and connamespace = 'public'::regnamespace),
          0::bigint, 'no ON DELETE CASCADE foreign keys in public');

select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'private') and p.prosecdef
              -- public.rls_auto_enable() is created by the hosted Supabase platform (event trigger, pins pg_catalog)
              and p.proname <> 'rls_auto_enable'
              and not coalesce(p.proconfig @> array['search_path=""'], false)),
          0::bigint, 'every SECURITY DEFINER function pins search_path to empty');

select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and (p.proname like 'can\_%' or p.proname like 'is\_%active%' or p.proname like 'is\_%owner')
              and not (p.prosecdef and p.provolatile = 's')),
          0::bigint, 'RLS helper functions are SECURITY DEFINER + STABLE');

select is((select bool_and(not has_table_privilege('anon', c.oid, 'select,insert,update,delete'))
             from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r'),
          true, 'anon has no privilege on any public table');

select ok(not has_table_privilege('authenticated', 'public.places', 'delete'), 'authenticated cannot hard-DELETE places');
select ok(not has_table_privilege('authenticated', 'public.visits', 'delete'), 'authenticated cannot hard-DELETE visits');
select ok(not has_table_privilege('authenticated', 'public.memories', 'delete'), 'authenticated cannot hard-DELETE memories');
select ok(not has_table_privilege('authenticated', 'public.journals', 'delete'), 'authenticated cannot hard-DELETE journals');
select ok(not has_table_privilege('authenticated', 'public.invitations', 'select'), 'authenticated has no direct access to invitations (token_hash)');
select ok(not has_table_privilege('authenticated', 'public.journal_members', 'insert')
      and not has_table_privilege('authenticated', 'public.journal_members', 'update')
      and not has_table_privilege('authenticated', 'public.journal_members', 'delete'), 'membership tables are read-only for clients');
select ok(not has_table_privilege('authenticated', 'public.audit_log', 'insert'), 'clients cannot write audit_log');
select ok(has_function_privilege('authenticated', 'private.can_read_place(uuid)', 'execute'), 'authenticated may execute policy helpers');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and (p.proname like 'can\_%' or p.proname like 'is\_%' or p.proname = 'memory_visible')
              and not has_function_privilege('authenticated', p.oid, 'execute')),
          0::bigint, 'authenticated can EXECUTE every private can_*/is_* helper (policies run with caller privileges)');
select ok(not has_function_privilege('anon', 'public.accept_invitation(text)', 'execute'), 'anon cannot execute RPCs');
select ok(not has_function_privilege('authenticated', 'public.expire_pending_invitations()', 'execute'), 'expire_pending_invitations is service_role only');
select ok(not has_function_privilege('authenticated', 'private.write_audit(text,text,uuid,uuid,jsonb)', 'execute'), 'clients cannot call write_audit');

select is((select public from storage.buckets where id = 'memory-media'), false, 'memory-media bucket is private');
select is((select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'memory_media_%'),
          3::bigint, 'three storage policies (select/insert/delete); no update policy => no overwrite');
select is((select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
            and policyname like 'memory_media_%' and cmd = 'UPDATE'), 0::bigint, 'no UPDATE policy on storage objects');

-- ---- profile bootstrap -----------------------------------------------------------
select is((select display_name from public.profiles where id = tests.u('alice')), 'Alice', 'profile created from auth.users metadata');

-- ---- constraints (as superuser, so only the constraint can be the cause) ----------
select throws_ok($$insert into public.places (id, owner_id, title, latitude, longitude)
                   values (gen_random_uuid(), tests.u('alice'), 'X', 91, 0)$$, '23514', null, 'latitude > 90 rejected');
select throws_ok($$insert into public.places (id, owner_id, title, latitude, longitude)
                   values (gen_random_uuid(), tests.u('alice'), 'X', 0, 181)$$, '23514', null, 'longitude > 180 rejected');
select throws_ok($$insert into public.places (id, owner_id, title, latitude, longitude)
                   values (gen_random_uuid(), tests.u('alice'), '   ', 0, 0)$$, '23514', null, 'blank title rejected');
select throws_ok($$insert into public.places (id, owner_id, title, latitude, longitude, provider)
                   values (gen_random_uuid(), tests.u('alice'), 'X', 0, 0, 'apple')$$, '23514', null, 'provider without provider_place_id rejected');

insert into public.places (id, owner_id, title, latitude, longitude, provider, provider_place_id)
values ('11111111-0000-0000-0000-000000000001', tests.u('alice'), 'Cafe A', 10.77, 106.70, 'apple', 'P1');
select throws_ok($$insert into public.places (owner_id, title, latitude, longitude, provider, provider_place_id)
                    values (tests.u('alice'), 'Cafe A2', 10.77, 106.70, 'apple', 'P1')$$, '23505', null, 'provider id unique per owner (live rows)');
select lives_ok($$insert into public.places (owner_id, title, latitude, longitude, provider, provider_place_id)
                    values (tests.u('bob'), 'Cafe A (bob)', 10.77, 106.70, 'apple', 'P1')$$, 'same provider id allowed for another owner');

select throws_ok($$insert into public.visits (place_id, owner_id, created_by, visited_at, timezone_id)
                   values ('11111111-0000-0000-0000-000000000001', tests.u('alice'), tests.u('alice'), now(), 'Mars/Olympus')$$,
                 '22023', null, 'invalid IANA timezone_id rejected');
select lives_ok($$insert into public.visits (place_id, owner_id, created_by, visited_at, timezone_id)
                   values ('11111111-0000-0000-0000-000000000001', tests.u('alice'), tests.u('alice'), now(), 'Asia/Ho_Chi_Minh')$$,
                'valid IANA timezone_id accepted');

select throws_ok($$insert into public.place_members (place_id, user_id, role)
                   values ('11111111-0000-0000-0000-000000000001', tests.u('bob'), 'OWNER')$$,
                 '23514', null, 'membership table rejects OWNER role (decision 2)');
select throws_ok($$insert into public.invitations (resource_type, place_id, invited_by, role, token_hash, expires_at)
                   values ('PLACE', '11111111-0000-0000-0000-000000000001', tests.u('alice'), 'OWNER', 'h1', now() + interval '1 day')$$,
                 '23514', null, 'invitation role OWNER rejected');
select throws_ok($$insert into public.invitations (resource_type, place_id, visit_id, invited_by, role, token_hash, expires_at)
                   values ('PLACE', '11111111-0000-0000-0000-000000000001', gen_random_uuid(), tests.u('alice'), 'VIEWER', 'h2', now() + interval '1 day')$$,
                 '23514', null, 'invitation must reference exactly one resource FK');
select throws_ok($$insert into public.invitations (resource_type, journal_id, invited_by, role, token_hash, expires_at)
                   values ('PLACE', gen_random_uuid(), tests.u('alice'), 'VIEWER', 'h3', now() + interval '1 day')$$,
                 '23514', null, 'invitation resource FK must match resource_type');

select throws_ok($$insert into public.visit_participants (visit_id, user_id, display_name_snapshot, added_by)
                   select id, null, '  ', tests.u('alice') from public.visits limit 1$$, '23514', null, 'guest participant needs a label');

select throws_ok($$insert into public.audit_log (action, resource_type) values ('X', 'PLACE'); update public.audit_log set action = 'Y'$$,
                 '42501', 'audit_log is append-only', 'audit_log rejects UPDATE even for superuser');
select * from finish();
rollback;
