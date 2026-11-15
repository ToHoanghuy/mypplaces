-- =============================================================================
-- MyPlaces – 10: covering indexes for foreign keys (Supabase performance advisor 0001)
-- Found by get_advisors(performance) on the hosted project after migrations 01-09.
-- Without these, deleting/updating a profile (or a journal_visits row, ON DELETE SET NULL) scans the child table.
-- Security advisor findings (SECURITY DEFINER RPCs executable by `authenticated`) are intentional:
-- each RPC checks auth.uid() and the caller's rights itself; anon/PUBLIC have no EXECUTE.
-- =============================================================================
create index if not exists invitations_accepted_by_idx      on public.invitations (accepted_by);
create index if not exists invitations_invitee_user_idx     on public.invitations (invitee_user_id);
create index if not exists place_members_invited_by_idx     on public.place_members (invited_by);
create index if not exists visit_members_invited_by_idx     on public.visit_members (invited_by);
create index if not exists journal_members_invited_by_idx   on public.journal_members (invited_by);
create index if not exists journal_places_added_by_idx      on public.journal_places (added_by);
create index if not exists journal_visits_added_by_idx      on public.journal_visits (added_by);
create index if not exists visit_participants_added_by_idx  on public.visit_participants (added_by);
create index if not exists visits_created_by_idx            on public.visits (created_by);
-- full (non-partial) index so the composite FK (journal_visit_id, journal_id) is covered for ON DELETE SET NULL
create index if not exists memories_journal_visit_fk_idx    on public.memories (journal_visit_id, journal_id);
