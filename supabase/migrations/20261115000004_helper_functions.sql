-- =============================================================================
-- MyPlaces – 04: authorization helper functions (used by RLS + Storage policies + RPCs)
-- All are SECURITY DEFINER (so policies never recurse through RLS), STABLE, with
-- SET search_path = '' (everything is schema-qualified). They only ever look at auth.uid(),
-- so they can be called by any authenticated user without leaking information about others.
--
-- Vocabulary:
--   is_X_owner(id)          owner_id = auth.uid(), regardless of soft-delete state (tombstone visibility)
--   is_active_X_owner(id)   same, and the resource is not soft-deleted
--   can_read_X(id)          owner (even if soft-deleted)  OR  (not deleted AND ACTIVE member)
--   can_contribute_X(id)    not deleted (journal: and not archived) AND (owner OR ACTIVE EDITOR)
--   "edit metadata" = is_active_X_owner  (ERD-02: Editors never edit Place/Visit/Journal metadata)
-- =============================================================================

-- ---------------------------------------------------------------- place ----
create function private.is_place_owner(p_place_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.places p where p.id = p_place_id and p.owner_id = auth.uid());
$$;

create function private.is_active_place_owner(p_place_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.places p
                 where p.id = p_place_id and p.owner_id = auth.uid() and p.deleted_at is null);
$$;

create function private.can_read_place(p_place_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.places p
    where p.id = p_place_id
      and (p.owner_id = auth.uid()
           or (p.deleted_at is null
               and exists (select 1 from public.place_members m
                           where m.place_id = p.id and m.user_id = auth.uid() and m.status = 'ACTIVE')))
  );
$$;

create function private.can_contribute_place(p_place_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.places p
    where p.id = p_place_id and p.deleted_at is null
      and (p.owner_id = auth.uid()
           or exists (select 1 from public.place_members m
                      where m.place_id = p.id and m.user_id = auth.uid()
                        and m.status = 'ACTIVE' and m.role = 'EDITOR'))
  );
$$;

-- ---------------------------------------------------------------- visit ----
create function private.is_visit_owner(p_visit_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.visits v where v.id = p_visit_id and v.owner_id = auth.uid());
$$;

create function private.is_active_visit_owner(p_visit_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.visits v
                 where v.id = p_visit_id and v.owner_id = auth.uid() and v.deleted_at is null);
$$;

create function private.can_read_visit(p_visit_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.visits v
    where v.id = p_visit_id
      and (v.owner_id = auth.uid()
           or (v.deleted_at is null
               and exists (select 1 from public.visit_members m
                           where m.visit_id = v.id and m.user_id = auth.uid() and m.status = 'ACTIVE')))
  );
$$;

create function private.can_contribute_visit(p_visit_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.visits v
    where v.id = p_visit_id and v.deleted_at is null
      and (v.owner_id = auth.uid()
           or exists (select 1 from public.visit_members m
                      where m.visit_id = v.id and m.user_id = auth.uid()
                        and m.status = 'ACTIVE' and m.role = 'EDITOR'))
  );
$$;

-- -------------------------------------------------------------- journal ----
create function private.is_journal_owner(p_journal_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.journals j where j.id = p_journal_id and j.owner_id = auth.uid());
$$;

create function private.is_active_journal_owner(p_journal_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.journals j
                 where j.id = p_journal_id and j.owner_id = auth.uid() and j.deleted_at is null);
$$;

create function private.can_read_journal(p_journal_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.journals j
    where j.id = p_journal_id
      and (j.owner_id = auth.uid()
           or (j.deleted_at is null
               and exists (select 1 from public.journal_members m
                           where m.journal_id = j.id and m.user_id = auth.uid() and m.status = 'ACTIVE')))
  );
$$;

-- Archived journals are read-only for contributions (BRD UC-08: "Journal archived: mutation rejected").
create function private.can_contribute_journal(p_journal_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.journals j
    where j.id = p_journal_id and j.deleted_at is null and j.archived_at is null
      and (j.owner_id = auth.uid()
           or exists (select 1 from public.journal_members m
                      where m.journal_id = j.id and m.user_id = auth.uid()
                        and m.status = 'ACTIVE' and m.role = 'EDITOR'))
  );
$$;

-- ------------------------------------------------- generic resource owner ----
create function private.is_resource_owner(p_type public.resource_type, p_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select case p_type
    when 'PLACE'   then private.is_place_owner(p_id)
    when 'VISIT'   then private.is_visit_owner(p_id)
    when 'JOURNAL' then private.is_journal_owner(p_id)
  end;
$$;

-- Owner + state of any shareable resource (used by RPCs).
create function private.resource_info(p_type public.resource_type, p_id uuid)
returns table (owner_id uuid, is_deleted boolean, is_archived boolean)
language sql stable security definer set search_path = ''
as $$
  select p.owner_id, p.deleted_at is not null, false
    from public.places p where p_type = 'PLACE' and p.id = p_id
  union all
  select v.owner_id, v.deleted_at is not null, false
    from public.visits v where p_type = 'VISIT' and v.id = p_id
  union all
  select j.owner_id, j.deleted_at is not null, j.archived_at is not null
    from public.journals j where p_type = 'JOURNAL' and j.id = p_id;
$$;

-- --------------------------------------------- memory parent dispatchers ----
create function private.can_read_memory_parent(p_place uuid, p_visit uuid, p_journal uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when p_place   is not null then private.can_read_place(p_place)
    when p_visit   is not null then private.can_read_visit(p_visit)
    when p_journal is not null then private.can_read_journal(p_journal)
    else false end;
$$;

create function private.can_contribute_memory_parent(p_place uuid, p_visit uuid, p_journal uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when p_place   is not null then private.can_contribute_place(p_place)
    when p_visit   is not null then private.can_contribute_visit(p_visit)
    when p_journal is not null then private.can_contribute_journal(p_journal)
    else false end;
$$;

create function private.is_memory_parent_owner(p_place uuid, p_visit uuid, p_journal uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when p_place   is not null then private.is_place_owner(p_place)
    when p_visit   is not null then private.is_visit_owner(p_visit)
    when p_journal is not null then private.is_journal_owner(p_journal)
    else false end;
$$;

-- A memory is visible if its parent is readable; soft-deleted memories only to their author
-- (while they can still read the parent) and to the parent owner (moderation / restore).
create function private.memory_visible(
  p_place uuid, p_visit uuid, p_journal uuid, p_author uuid, p_deleted_at timestamptz
) returns boolean
language sql stable security definer set search_path = ''
as $$
  select private.can_read_memory_parent(p_place, p_visit, p_journal)
     and (p_deleted_at is null
          or p_author = auth.uid()
          or private.is_memory_parent_owner(p_place, p_visit, p_journal));
$$;

-- Memory-id based variants (used by memory_attachments policies; avoid RLS recursion).
create function private.can_read_memory(p_memory_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.memories m
                 where m.id = p_memory_id
                   and private.memory_visible(m.place_id, m.visit_id, m.journal_id, m.author_id, m.deleted_at));
$$;

-- Author of a live memory who may still contribute to its parent (ACTIVE Owner/Editor).
create function private.can_write_own_memory(p_memory_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.memories m
                 where m.id = p_memory_id and m.author_id = auth.uid() and m.deleted_at is null
                   and private.can_contribute_memory_parent(m.place_id, m.visit_id, m.journal_id));
$$;

-- Author, or parent Owner (moderation) – used for deleting attachments.
create function private.can_remove_memory_content(p_memory_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.memories m
                 where m.id = p_memory_id
                   and (m.author_id = auth.uid()
                        or private.is_memory_parent_owner(m.place_id, m.visit_id, m.journal_id)));
$$;

-- ------------------------------------------------------------- profiles ----
-- A profile is readable by: itself; people sharing a Place/Visit/Journal with me (owner or ACTIVE
-- member on both sides); authors of memories I can read; participants of visits I can read.
create function private.can_read_profile(p_profile_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_profile_id = auth.uid()
  or exists (
    select 1 from public.places pl
    where pl.deleted_at is null
      and (pl.owner_id = auth.uid() or exists (select 1 from public.place_members a
            where a.place_id = pl.id and a.user_id = auth.uid() and a.status = 'ACTIVE'))
      and (pl.owner_id = p_profile_id or exists (select 1 from public.place_members b
            where b.place_id = pl.id and b.user_id = p_profile_id and b.status = 'ACTIVE')))
  or exists (
    select 1 from public.visits v
    where v.deleted_at is null
      and (v.owner_id = auth.uid() or exists (select 1 from public.visit_members a
            where a.visit_id = v.id and a.user_id = auth.uid() and a.status = 'ACTIVE'))
      and (v.owner_id = p_profile_id or exists (select 1 from public.visit_members b
            where b.visit_id = v.id and b.user_id = p_profile_id and b.status = 'ACTIVE')))
  or exists (
    select 1 from public.journals j
    where j.deleted_at is null
      and (j.owner_id = auth.uid() or exists (select 1 from public.journal_members a
            where a.journal_id = j.id and a.user_id = auth.uid() and a.status = 'ACTIVE'))
      and (j.owner_id = p_profile_id or exists (select 1 from public.journal_members b
            where b.journal_id = j.id and b.user_id = p_profile_id and b.status = 'ACTIVE')))
  or exists (
    select 1 from public.memories m
    where m.author_id = p_profile_id and m.deleted_at is null
      and private.can_read_memory_parent(m.place_id, m.visit_id, m.journal_id))
  or exists (
    select 1 from public.visit_participants vp
    where vp.user_id = p_profile_id and private.can_read_visit(vp.visit_id));
$$;
