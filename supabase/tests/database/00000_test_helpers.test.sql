-- =============================================================================
-- Test helpers (persisted in schema "tests"; this file intentionally does not roll back).
-- Run order is alphabetical, so this file must stay first.
-- =============================================================================
create extension if not exists pgtap with schema extensions;
create schema if not exists tests;

-- Fixed cast of characters used by every test file.
create or replace function tests.u(p_name text) returns uuid
language sql immutable as $$
  select case p_name
    when 'alice' then 'aaaaaaaa-0000-0000-0000-000000000001'::uuid   -- resource owner
    when 'bob'   then 'aaaaaaaa-0000-0000-0000-000000000002'::uuid   -- editor
    when 'carol' then 'aaaaaaaa-0000-0000-0000-000000000003'::uuid   -- viewer
    when 'dave'  then 'aaaaaaaa-0000-0000-0000-000000000004'::uuid   -- outsider / private non-member
    when 'erin'  then 'aaaaaaaa-0000-0000-0000-000000000005'::uuid   -- participant / second editor
  end
$$;

-- Creates auth.users rows (profile rows come from the on_auth_user_created trigger). Run as postgres.
create or replace function tests.seed_users() returns void
language sql as $$
  insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data)
  select tests.u(n), 'authenticated', 'authenticated', n || '@example.test', now(),
         jsonb_build_object('display_name', initcap(n))
  from unnest(array['alice', 'bob', 'carol', 'dave', 'erin']) as n;
$$;

-- Act as an authenticated Supabase user: same GUCs PostgREST sets, plus role switch.
create or replace function tests.authenticate_as(p_id uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_id, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.authenticate_as(p_name text) returns void
language sql as $$ select tests.authenticate_as(tests.u(p_name)); $$;

create or replace function tests.authenticate_as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('role', 'anon', true);
end;
$$;

create or replace function tests.clear_authentication() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  execute 'reset role';
end;
$$;

-- Rows affected by a DML/SELECT statement under the CURRENT role (RLS silently filters UPDATE/DELETE,
-- so "denied" means 0 rows, not an error).
create or replace function tests.affected(p_sql text) returns bigint
language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Storage path per convention: {uploader}/{memory}/{attachment}.{ext}
create or replace function tests.media_path(p_user text, p_memory uuid, p_attachment uuid, p_ext text default 'jpg') returns text
language sql immutable as $$ select tests.u(p_user)::text || '/' || p_memory::text || '/' || p_attachment::text || '.' || p_ext $$;

grant usage on schema tests to anon, authenticated, service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

begin;
select plan(3);
select has_function('tests', 'authenticate_as', array['uuid'], 'test helpers installed');
select tests.seed_users();
select tests.authenticate_as('alice');
select is(auth.uid(), tests.u('alice'), 'authenticate_as sets auth.uid()');
select is(current_user::text, 'authenticated', 'authenticate_as switches role');
select * from finish();
rollback;
