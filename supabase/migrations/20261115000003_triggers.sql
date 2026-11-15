-- =============================================================================
-- MyPlaces – 03: audit writer + triggers
--   * audit writer (SECURITY DEFINER; the only way rows enter audit_log)
--   * server-stamped timestamps, updated_at
--   * immutable columns / memory moderation guard (apply to direct client DML only)
--   * IANA timezone validation, profile bootstrap on sign-up, lifecycle audit
-- Guard triggers are SECURITY INVOKER on purpose: they test current_user, which is
-- 'authenticated' / 'anon' for PostgREST requests and the function owner inside our
-- SECURITY DEFINER RPCs (so ownership transfer can legitimately change owner_id).
-- =============================================================================

create function private.write_audit(
  p_action         text,
  p_resource_type  text,
  p_resource_id    uuid,
  p_target_user_id uuid  default null,
  p_metadata       jsonb default '{}'::jsonb
) returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_log (actor_id, action, resource_type, resource_id, target_user_id, metadata)
  values (auth.uid(), p_action, p_resource_type, p_resource_id, p_target_user_id, coalesce(p_metadata, '{}'::jsonb));
$$;

-- audit_log is append-only, even for privileged sessions (disable the trigger deliberately to purge).
create function private.audit_log_append_only() returns trigger
language plpgsql set search_path = ''
as $$
begin
  raise exception 'audit_log is append-only' using errcode = '42501';
end;
$$;
create trigger audit_log_no_update_delete
  before update or delete on public.audit_log
  for each row execute function private.audit_log_append_only();

-- ------------------------------------------------------------ timestamps ----
create function private.set_updated_at() returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- created_at / updated_at are server generated (ERD §3). Client time lives in visited_at.
create function private.stamp_insert_times() returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_updated_at  before update on public.profiles      for each row execute function private.set_updated_at();
create trigger places_updated_at    before update on public.places        for each row execute function private.set_updated_at();
create trigger visits_updated_at    before update on public.visits        for each row execute function private.set_updated_at();
create trigger journals_updated_at  before update on public.journals      for each row execute function private.set_updated_at();
create trigger memories_updated_at  before update on public.memories      for each row execute function private.set_updated_at();
create trigger place_members_updated_at   before update on public.place_members   for each row execute function private.set_updated_at();
create trigger visit_members_updated_at   before update on public.visit_members   for each row execute function private.set_updated_at();
create trigger journal_members_updated_at before update on public.journal_members for each row execute function private.set_updated_at();

create trigger places_stamp   before insert on public.places   for each row execute function private.stamp_insert_times();
create trigger visits_stamp   before insert on public.visits   for each row execute function private.stamp_insert_times();
create trigger journals_stamp before insert on public.journals for each row execute function private.stamp_insert_times();
create trigger memories_stamp before insert on public.memories for each row execute function private.stamp_insert_times();

-- ------------------------------------------------------------- immutables ----
create function private.guard_immutable() returns trigger
language plpgsql set search_path = ''
as $$
declare
  c text;
begin
  if current_user in ('authenticated', 'anon') then
    foreach c in array tg_argv loop
      if (to_jsonb(new) -> c) is distinct from (to_jsonb(old) -> c) then
        raise exception 'column %.% is immutable', tg_table_name, c using errcode = '42501';
      end if;
    end loop;
  end if;
  return new;
end;
$$;

create trigger profiles_immutable          before update on public.profiles
  for each row execute function private.guard_immutable('id', 'created_at');
create trigger places_immutable            before update on public.places
  for each row execute function private.guard_immutable('id', 'owner_id', 'created_at');
create trigger visits_immutable            before update on public.visits
  for each row execute function private.guard_immutable('id', 'place_id', 'owner_id', 'created_by', 'created_at');
create trigger journals_immutable          before update on public.journals
  for each row execute function private.guard_immutable('id', 'owner_id', 'created_at');
create trigger memories_immutable          before update on public.memories
  for each row execute function private.guard_immutable('id', 'author_id', 'place_id', 'visit_id', 'journal_id', 'journal_visit_id', 'created_at');
create trigger visit_participants_immutable before update on public.visit_participants
  for each row execute function private.guard_immutable('id', 'visit_id', 'added_by', 'created_at');
create trigger journal_places_immutable    before update on public.journal_places
  for each row execute function private.guard_immutable('id', 'journal_id', 'place_id', 'added_by', 'created_at');
create trigger journal_visits_immutable    before update on public.journal_visits
  for each row execute function private.guard_immutable('id', 'journal_id', 'visit_id', 'added_by', 'created_at');

-- A parent Owner may MODERATE another author's memory (soft-delete it) but not rewrite it.
create function private.guard_memory_moderation() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon')
     and auth.uid() is distinct from old.author_id
     and (new.body is distinct from old.body or new.type is distinct from old.type) then
    raise exception 'moderators may only change deleted_at of another author''s memory' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger memories_moderation_guard before update on public.memories
  for each row execute function private.guard_memory_moderation();

-- Audit moderation (actor is not the author) – SECURITY DEFINER so clients need no audit privileges.
create function private.audit_memory_moderation() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is not null
     and auth.uid() <> old.author_id
     and new.deleted_at is distinct from old.deleted_at then
    perform private.write_audit(
      'MEMORY_MODERATED', 'MEMORY', old.id, old.author_id,
      jsonb_build_object('deleted', new.deleted_at is not null,
                         'place_id', old.place_id, 'visit_id', old.visit_id, 'journal_id', old.journal_id));
  end if;
  return null;
end;
$$;
create trigger memories_moderation_audit after update on public.memories
  for each row execute function private.audit_memory_moderation();

-- ------------------------------------------------------------- lifecycle ----
create function private.audit_lifecycle() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_type text := tg_argv[0];
begin
  if old.deleted_at is null and new.deleted_at is not null then
    perform private.write_audit('RESOURCE_DELETED', v_type, new.id);
  elsif old.deleted_at is not null and new.deleted_at is null then
    perform private.write_audit('RESOURCE_RESTORED', v_type, new.id);
  end if;
  if v_type = 'JOURNAL' then
    if old.archived_at is null and new.archived_at is not null then
      perform private.write_audit('JOURNAL_ARCHIVED', 'JOURNAL', new.id);
    elsif old.archived_at is not null and new.archived_at is null then
      perform private.write_audit('JOURNAL_UNARCHIVED', 'JOURNAL', new.id);
    end if;
  end if;
  return null;
end;
$$;
create trigger places_lifecycle_audit   after update of deleted_at on public.places
  for each row execute function private.audit_lifecycle('PLACE');
create trigger visits_lifecycle_audit   after update of deleted_at on public.visits
  for each row execute function private.audit_lifecycle('VISIT');
create trigger journals_lifecycle_audit after update of deleted_at, archived_at on public.journals
  for each row execute function private.audit_lifecycle('JOURNAL');

-- ------------------------------------------------------------- timezone ----
create function private.validate_timezone_id() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names n where n.name = new.timezone_id) then
    raise exception 'invalid IANA timezone_id: %', new.timezone_id using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger visits_validate_timezone before insert or update of timezone_id on public.visits
  for each row execute function private.validate_timezone_id();

-- -------------------------------------------------------- profile bootstrap ----
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_name text;
begin
  v_name := left(btrim(coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'User')), 40);
  insert into public.profiles (id, display_name) values (new.id, v_name)
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();
