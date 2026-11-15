-- =============================================================================
-- MyPlaces – 05: Row Level Security (deny by default, one policy per operation)
-- Reference: ERD v1.1 §5 (permission matrix), §6 (RLS design), BRD v1.1 §24.
--
-- Decisions encoded here:
--   * no DELETE policy on places / visits / journals / memories  -> soft delete only (UPDATE deleted_at)
--   * membership tables + audit_log: SELECT only; writes go through SECURITY DEFINER RPCs (migration 07)
--   * invitations: RLS on, owner SELECT policy, but NO table grant for clients (see 09): token_hash never
--     leaves the DB; clients use list_invitations()/resolve_invitation()
--   * Place share does NOT expose Visits; Visit access is only owner / ACTIVE visit_member (ERD-03)
--   * Journal members have NO policy on places/visits -> they use the projections of migration 06 (ERD-04)
-- =============================================================================

alter table public.profiles            enable row level security;
alter table public.places              enable row level security;
alter table public.visits              enable row level security;
alter table public.visit_participants  enable row level security;
alter table public.journals            enable row level security;
alter table public.journal_places      enable row level security;
alter table public.journal_visits      enable row level security;
alter table public.memories            enable row level security;
alter table public.memory_attachments  enable row level security;
alter table public.place_members       enable row level security;
alter table public.visit_members       enable row level security;
alter table public.journal_members     enable row level security;
alter table public.invitations         enable row level security;
alter table public.audit_log           enable row level security;

-- --------------------------------------------------------------- profiles ----
create policy profiles_select on public.profiles for select to authenticated
  using (private.can_read_profile(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
-- no INSERT (trigger on auth.users) and no DELETE policy.

-- ----------------------------------------------------------------- places ----
create policy places_select on public.places for select to authenticated
  using (owner_id = (select auth.uid()) or private.can_read_place(id));
create policy places_insert on public.places for insert to authenticated
  with check (owner_id = (select auth.uid()) and deleted_at is null);
create policy places_update on public.places for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- ----------------------------------------------------------------- visits ----
create policy visits_select on public.visits for select to authenticated
  using (owner_id = (select auth.uid()) or private.can_read_visit(id));
-- Decision 1 / ERD-06: the Place owner OR an ACTIVE Place EDITOR may create a Visit on a live Place;
-- the creator is always the Visit owner. Viewers / non-members / removed members cannot.
create policy visits_insert on public.visits for insert to authenticated
  with check (owner_id = (select auth.uid())
              and created_by = (select auth.uid())
              and deleted_at is null
              and private.can_contribute_place(place_id));
create policy visits_update on public.visits for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- ----------------------------------------------------- visit_participants ----
create policy visit_participants_select on public.visit_participants for select to authenticated
  using (private.can_read_visit(visit_id));
-- A participant WITH an account must already be someone the caller can see (shared resource / known
-- account). Otherwise adding an arbitrary UUID would let the caller read that stranger's profile
-- (can_read_profile treats participants of readable visits as visible) and probe account existence.
-- Guest labels (user_id null) are unrestricted. A friend graph (P1) would widen this later.
create policy visit_participants_insert on public.visit_participants for insert to authenticated
  with check (added_by = (select auth.uid())
              and private.is_active_visit_owner(visit_id)
              and (user_id is null or private.can_read_profile(user_id)));
create policy visit_participants_update on public.visit_participants for update to authenticated
  using (private.is_active_visit_owner(visit_id))
  with check (private.is_active_visit_owner(visit_id)
              and (user_id is null or private.can_read_profile(user_id)));
create policy visit_participants_delete on public.visit_participants for delete to authenticated
  using (private.is_active_visit_owner(visit_id));

-- --------------------------------------------------------------- journals ----
create policy journals_select on public.journals for select to authenticated
  using (owner_id = (select auth.uid()) or private.can_read_journal(id));
create policy journals_insert on public.journals for insert to authenticated
  with check (owner_id = (select auth.uid()) and deleted_at is null and archived_at is null);
create policy journals_update on public.journals for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- ------------------------------------------------- journal_places / visits ----
-- Linking is a share of the projection (title/category/coordinates, visit date), so only the
-- OWNER of the Place/Visit may link it; the actor must also be Owner/Editor of a live, non-archived Journal.
-- The owner of the linked Place/Visit can always see/unlink their own link (withdraw consent),
-- even after being removed from the Journal.
create policy journal_places_select on public.journal_places for select to authenticated
  using (private.can_read_journal(journal_id) or private.is_place_owner(place_id));
create policy journal_places_insert on public.journal_places for insert to authenticated
  with check (added_by = (select auth.uid())
              and private.can_contribute_journal(journal_id)
              and private.is_active_place_owner(place_id));
create policy journal_places_update on public.journal_places for update to authenticated
  using (private.can_contribute_journal(journal_id)) with check (private.can_contribute_journal(journal_id));
create policy journal_places_delete on public.journal_places for delete to authenticated
  using (private.can_contribute_journal(journal_id) or private.is_place_owner(place_id));

create policy journal_visits_select on public.journal_visits for select to authenticated
  using (private.can_read_journal(journal_id) or private.is_visit_owner(visit_id));
create policy journal_visits_insert on public.journal_visits for insert to authenticated
  with check (added_by = (select auth.uid())
              and private.can_contribute_journal(journal_id)
              and private.is_active_visit_owner(visit_id));
create policy journal_visits_update on public.journal_visits for update to authenticated
  using (private.can_contribute_journal(journal_id)) with check (private.can_contribute_journal(journal_id));
create policy journal_visits_delete on public.journal_visits for delete to authenticated
  using (private.can_contribute_journal(journal_id) or private.is_visit_owner(visit_id));

-- --------------------------------------------------------------- memories ----
create policy memories_select on public.memories for select to authenticated
  using (private.memory_visible(place_id, visit_id, journal_id, author_id, deleted_at));
-- author_id must be the caller; caller must be Owner/EDITOR of the (single) parent.
create policy memories_insert on public.memories for insert to authenticated
  with check (author_id = (select auth.uid())
              and deleted_at is null
              and private.can_contribute_memory_parent(place_id, visit_id, journal_id));
-- Author edits own memory (only while still Owner/EDITOR of the parent); parent Owner may moderate
-- (the guard trigger limits moderation to deleted_at and audits it).
create policy memories_update on public.memories for update to authenticated
  using ((author_id = (select auth.uid()) and private.can_contribute_memory_parent(place_id, visit_id, journal_id))
         or private.is_memory_parent_owner(place_id, visit_id, journal_id))
  with check ((author_id = (select auth.uid()) and private.can_contribute_memory_parent(place_id, visit_id, journal_id))
         or private.is_memory_parent_owner(place_id, visit_id, journal_id));

-- ------------------------------------------------------ memory_attachments ----
create policy memory_attachments_select on public.memory_attachments for select to authenticated
  using (private.can_read_memory(memory_id));
create policy memory_attachments_insert on public.memory_attachments for insert to authenticated
  with check (private.can_write_own_memory(memory_id)
              and split_part(storage_path, '/', 1) = (select auth.uid())::text);
create policy memory_attachments_delete on public.memory_attachments for delete to authenticated
  using (private.can_remove_memory_content(memory_id));
-- no UPDATE policy: attachment metadata is immutable once finalized.

-- ------------------------------------------------------ membership tables ----
-- Owner sees every row (incl. REMOVED/LEFT history). Members see ACTIVE rows of the same resource
-- and always their own row (so a removed user learns access was revoked).
create policy place_members_select on public.place_members for select to authenticated
  using (user_id = (select auth.uid())
         or private.is_place_owner(place_id)
         or (status = 'ACTIVE' and private.can_read_place(place_id)));
create policy visit_members_select on public.visit_members for select to authenticated
  using (user_id = (select auth.uid())
         or private.is_visit_owner(visit_id)
         or (status = 'ACTIVE' and private.can_read_visit(visit_id)));
create policy journal_members_select on public.journal_members for select to authenticated
  using (user_id = (select auth.uid())
         or private.is_journal_owner(journal_id)
         or (status = 'ACTIVE' and private.can_read_journal(journal_id)));
-- INSERT / UPDATE / DELETE: no policies => only the RPCs (SECURITY DEFINER) can change membership.

-- ------------------------------------------------------------ invitations ----
create policy invitations_select on public.invitations for select to authenticated
  using (invited_by = (select auth.uid())
         or private.is_resource_owner(resource_type, coalesce(place_id, visit_id, journal_id)));
-- INSERT / UPDATE / DELETE: none => create/accept/decline/revoke are RPCs.

-- -------------------------------------------------------------- audit_log ----
create policy audit_log_select on public.audit_log for select to authenticated
  using (actor_id = (select auth.uid())
         or target_user_id = (select auth.uid())
         or (resource_type in ('PLACE', 'VISIT', 'JOURNAL')
             and private.is_resource_owner(resource_type::public.resource_type, resource_id)));
