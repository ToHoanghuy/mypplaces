-- =============================================================================
-- MyPlaces – 09: privileges (deny by default) + realtime publication
-- Supabase grants ALL on new public tables/functions to anon/authenticated by default; here we
-- revoke everything and grant back exactly what the permission matrix needs. RLS stays the
-- row-level layer; GRANTs are the first, coarse layer (e.g. nobody can DELETE places, nobody but
-- RPCs can write memberships, anon has nothing).
-- New objects added by FUTURE migrations must add their own GRANTs (default privileges below are
-- revoked so a forgotten GRANT fails closed).
-- =============================================================================

alter default privileges for role postgres in schema public revoke all on tables    from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public  from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

grant usage on schema private to authenticated;

-- ------------------------------------------------------------ table grants ----
grant select on public.profiles to authenticated;
grant update (display_name, avatar_path) on public.profiles to authenticated;

grant select, insert, update on public.places   to authenticated;   -- no DELETE: soft delete only
grant select, insert, update on public.visits   to authenticated;
grant select, insert, update on public.journals to authenticated;
grant select, insert, update on public.memories to authenticated;

grant select, insert, update, delete on public.visit_participants to authenticated;
grant select, insert, update, delete on public.journal_places     to authenticated;
grant select, insert, update, delete on public.journal_visits     to authenticated;
grant select, insert, delete         on public.memory_attachments to authenticated;

grant select on public.place_members   to authenticated;   -- writes: RPC only
grant select on public.visit_members   to authenticated;
grant select on public.journal_members to authenticated;
grant select on public.audit_log       to authenticated;
-- public.invitations: NO grant to clients (token_hash). Use list_invitations() / resolve_invitation().

-- --------------------------------------------------------- function grants ----
-- Public RPCs
grant execute on function
  public.create_invitation(public.resource_type, uuid, public.member_role, text, uuid, interval),
  public.resolve_invitation(text),
  public.accept_invitation(text),
  public.decline_invitation(text),
  public.revoke_invitation(uuid),
  public.list_invitations(public.resource_type, uuid),
  public.change_member_role(public.resource_type, uuid, uuid, public.member_role),
  public.remove_member(public.resource_type, uuid, uuid),
  public.leave_resource(public.resource_type, uuid),
  public.unshare_resource(public.resource_type, uuid),
  public.transfer_ownership(public.resource_type, uuid, uuid, public.member_role),
  public.journal_places_projection(uuid),
  public.journal_visits_projection(uuid),
  public.my_visit_places(uuid)
to authenticated;
grant execute on function public.expire_pending_invitations() to service_role;

-- Helpers referenced by RLS / Storage policies are evaluated with the caller's privileges
grant execute on function
  private.is_place_owner(uuid), private.is_active_place_owner(uuid),
  private.can_read_place(uuid), private.can_contribute_place(uuid),
  private.is_visit_owner(uuid), private.is_active_visit_owner(uuid),
  private.can_read_visit(uuid), private.can_contribute_visit(uuid),
  private.is_journal_owner(uuid), private.is_active_journal_owner(uuid),
  private.can_read_journal(uuid), private.can_contribute_journal(uuid),
  private.is_resource_owner(public.resource_type, uuid),
  private.can_read_memory_parent(uuid, uuid, uuid),
  private.can_contribute_memory_parent(uuid, uuid, uuid),
  private.is_memory_parent_owner(uuid, uuid, uuid),
  private.memory_visible(uuid, uuid, uuid, uuid, timestamptz),
  private.can_read_memory(uuid), private.can_write_own_memory(uuid),
  private.can_remove_memory_content(uuid), private.can_read_profile(uuid),
  private.is_valid_media_path(text), private.can_read_memory_path(text),
  private.can_upload_memory_path(text), private.can_remove_memory_path(text)
to authenticated;

-- --------------------------------------------------------------- realtime ----
-- Realtime applies the same RLS to change events. Only tables whose rows are RLS-protected are added.
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime' and not puballtables) then
    foreach t in array array['places', 'visits', 'visit_participants', 'journals', 'journal_places',
                             'journal_visits', 'memories', 'memory_attachments',
                             'place_members', 'visit_members', 'journal_members'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;
