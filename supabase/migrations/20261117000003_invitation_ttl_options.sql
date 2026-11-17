-- =============================================================================
-- MyPlaces – 13 (17/11/2026): invitation expiry options  (UI decision #5)
-- Approved: the share sheet offers 1 / 7 / 30 days, default 7. Before this migration the server
-- accepted any ttl in (0, 30 days]. The server is the source of truth for business rules, so
-- create_invitation() now accepts EXACTLY 1 day, 7 days or 30 days (default unchanged: 7 days);
-- anything else -> PT400 INVALID_EXPIRY (same error code as before, so clients need no change).
-- Only the ttl check changes; signature, grants, behaviour and audit are identical to migration 07.
-- No CHECK constraint on invitations: expiry tests/ops legitimately move expires_at, and the table
-- is written only by this RPC (clients have no grant on public.invitations).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_invitation(p_resource_type public.resource_type, p_resource_id uuid, p_role public.member_role, p_invitee_email text DEFAULT NULL::text, p_invitee_user_id uuid DEFAULT NULL::uuid, p_ttl interval DEFAULT '7 days'::interval)
 RETURNS TABLE(invitation_id uuid, token text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid       uuid := private.require_auth();
  v_state     record;
  v_email     text := nullif(lower(btrim(p_invitee_email)), '');
  v_token     text;
  v_id        uuid;
  v_expires   timestamptz;
  v_replaced  integer;
begin
  if p_role is null or p_role not in ('EDITOR', 'VIEWER') then
    raise exception 'INVALID_ROLE' using errcode = 'PT400', detail = 'Only EDITOR or VIEWER can be invited.';
  end if;
  -- UI decision #5 (17/11/2026): only 1, 7 (default) or 30 days.
  if p_ttl is null or p_ttl not in (interval '1 day', interval '7 days', interval '30 days') then
    raise exception 'INVALID_EXPIRY' using errcode = 'PT400', detail = 'ttl must be 1, 7 or 30 days.';
  end if;
  if v_email is not null and (char_length(v_email) not between 3 and 254 or position('@' in v_email) < 2) then
    raise exception 'INVALID_EMAIL' using errcode = 'PT400';
  end if;

  select * into v_state from private.assert_owner(p_resource_type, p_resource_id);
  if v_state.is_deleted or v_state.is_archived then
    raise exception 'RESOURCE_UNAVAILABLE' using errcode = 'PT409', detail = 'Resource is deleted or archived.';
  end if;

  if p_invitee_user_id = v_uid or (v_email is not null and v_email = private.caller_verified_email()) then
    raise exception 'CANNOT_INVITE_SELF' using errcode = 'PT400';
  end if;
  if p_invitee_user_id is not null then
    if exists (select 1 from private.member_lock(p_resource_type, p_resource_id, p_invitee_user_id) m
               where m.status = 'ACTIVE') then
      raise exception 'ALREADY_MEMBER' using errcode = 'PT409';
    end if;
  end if;

  -- "Replace" policy: a new invitation for the same invitee revokes the previous pending one.
  update public.invitations i
     set status = 'REVOKED'
   where i.status = 'PENDING'
     and coalesce(i.place_id, i.visit_id, i.journal_id) = p_resource_id
     and ((p_invitee_user_id is not null and i.invitee_user_id = p_invitee_user_id)
          or (v_email is not null and i.invitee_email_normalized = v_email));
  get diagnostics v_replaced = row_count;

  v_token   := encode(extensions.gen_random_bytes(32), 'hex');   -- 256-bit random token
  v_expires := now() + p_ttl;

  insert into public.invitations (
    resource_type, place_id, visit_id, journal_id, invited_by,
    invitee_user_id, invitee_email_normalized, role, token_hash, status, expires_at)
  values (
    p_resource_type,
    case when p_resource_type = 'PLACE'   then p_resource_id end,
    case when p_resource_type = 'VISIT'   then p_resource_id end,
    case when p_resource_type = 'JOURNAL' then p_resource_id end,
    v_uid, p_invitee_user_id, v_email, p_role, private.hash_token(v_token), 'PENDING', v_expires)
  returning id into v_id;

  perform private.write_audit('INVITATION_CREATED', 'INVITATION', v_id, p_invitee_user_id,
    jsonb_build_object('resource_type', p_resource_type, 'resource_id', p_resource_id,
                       'role', p_role, 'expires_at', v_expires, 'replaced_pending', v_replaced,
                       'email_bound', v_email is not null));

  return query select v_id, v_token, v_expires;
end;
$function$;
