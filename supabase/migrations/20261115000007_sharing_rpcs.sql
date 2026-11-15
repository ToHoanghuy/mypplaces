-- =============================================================================
-- MyPlaces – 07: invitation + membership RPCs (all SECURITY DEFINER, atomic, audited)
--
-- Error contract (PostgREST maps SQLSTATE 'PTxxx' to HTTP xxx; message = stable error code):
--   PT401 AUTH_REQUIRED | PT400 VALIDATION_ERROR/INVALID_ROLE/... | PT403 FORBIDDEN
--   PT404 INVITATION_NOT_FOUND/RESOURCE_NOT_FOUND/MEMBER_NOT_FOUND
--   PT409 INVITATION_USED/ALREADY_MEMBER/OWNER_*/... | PT410 INVITATION_EXPIRED/REVOKED/DECLINED
-- Expiry is evaluated from expires_at at call time (status is not trusted alone); the EXPIRED
-- status itself is persisted by expire_pending_invitations() (run by pg_cron / service role),
-- because an RPC that raises cannot persist a status change.
-- =============================================================================

-- ------------------------------------------------------------- internals ----
create function private.hash_token(p_token text) returns text
language sql immutable set search_path = ''
as $$ select encode(sha256(convert_to(btrim(p_token), 'UTF8')), 'hex'); $$;

create function private.require_auth() returns uuid
language plpgsql stable set search_path = ''
as $$
declare v uuid := auth.uid();
begin
  if v is null then
    raise exception 'AUTH_REQUIRED' using errcode = 'PT401';
  end if;
  return v;
end;
$$;

-- Verified e-mail of the caller (lower-cased) or null.
create function private.caller_verified_email() returns text
language sql stable security definer set search_path = ''
as $$
  select lower(btrim(u.email)) from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
$$;

create function private.resource_table(p_type public.resource_type) returns text
language sql immutable set search_path = ''
as $$ select case p_type when 'PLACE' then 'places' when 'VISIT' then 'visits' when 'JOURNAL' then 'journals' end; $$;

create function private.member_table(p_type public.resource_type) returns text
language sql immutable set search_path = ''
as $$ select case p_type when 'PLACE' then 'place_members' when 'VISIT' then 'visit_members' when 'JOURNAL' then 'journal_members' end; $$;

create function private.member_fk(p_type public.resource_type) returns text
language sql immutable set search_path = ''
as $$ select case p_type when 'PLACE' then 'place_id' when 'VISIT' then 'visit_id' when 'JOURNAL' then 'journal_id' end; $$;

-- Locks and returns the membership row (if any). Identifiers come from the closed whitelist above.
create function private.member_lock(p_type public.resource_type, p_res_id uuid, p_user_id uuid)
returns table (member_id uuid, role public.member_role, status public.member_status)
language plpgsql security definer set search_path = ''
as $$
begin
  return query execute format(
    'select m.id, m.role, m.status from public.%I m where m.%I = $1 and m.user_id = $2 for update',
    private.member_table(p_type), private.member_fk(p_type))
  using p_res_id, p_user_id;
end;
$$;

-- Insert a new ACTIVE membership or reactivate a REMOVED/LEFT one.
create function private.member_activate(
  p_type public.resource_type, p_res_id uuid, p_user_id uuid, p_role public.member_role, p_invited_by uuid
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  execute format(
    'insert into public.%1$I (%2$I, user_id, role, status, invited_by, joined_at)
       values ($1, $2, $3, ''ACTIVE'', $4, now())
     on conflict (%2$I, user_id) do update
       set role = excluded.role, status = ''ACTIVE'', invited_by = excluded.invited_by,
           joined_at = now(), updated_at = now()',
    private.member_table(p_type), private.member_fk(p_type))
  using p_res_id, p_user_id, p_role, p_invited_by;
end;
$$;

create function private.member_set(
  p_type public.resource_type, p_member_id uuid, p_role public.member_role, p_status public.member_status
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  execute format(
    'update public.%I set role = coalesce($2, role), status = coalesce($3, status) where id = $1',
    private.member_table(p_type))
  using p_member_id, p_role, p_status;
end;
$$;

-- Common guard: caller must be the Owner of the resource. Returns the resource state.
create function private.assert_owner(p_type public.resource_type, p_id uuid)
returns table (is_deleted boolean, is_archived boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := private.require_auth();
  r record;
begin
  select * into r from private.resource_info(p_type, p_id);
  if not found or r.owner_id is distinct from v_uid then
    raise exception 'FORBIDDEN' using errcode = 'PT403';
  end if;
  return query select r.is_deleted, r.is_archived;
end;
$$;

-- -------------------------------------------------------- create_invitation ----
create function public.create_invitation(
  p_resource_type     public.resource_type,
  p_resource_id       uuid,
  p_role              public.member_role,
  p_invitee_email     text default null,
  p_invitee_user_id   uuid default null,
  p_ttl               interval default interval '7 days'
) returns table (invitation_id uuid, token text, expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
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
  if p_ttl is null or p_ttl <= interval '0' or p_ttl > interval '30 days' then
    raise exception 'INVALID_EXPIRY' using errcode = 'PT400', detail = 'ttl must be in (0, 30 days].';
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
$$;

-- -------------------------------------------------------- resolve_invitation ----
-- Minimal preview for the invitee (BRD UC-10). Raw token in, no token hash out.
create function public.resolve_invitation(p_token text)
returns table (
  invitation_id        uuid,
  resource_type        public.resource_type,
  resource_id          uuid,
  resource_title       text,
  resource_visited_at  timestamptz,
  resource_cover_path  text,
  inviter_display_name text,
  role                 public.member_role,
  expires_at           timestamptz,
  email_bound          boolean
)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := private.require_auth();
  i     public.invitations%rowtype;
begin
  select * into i from public.invitations x where x.token_hash = private.hash_token(coalesce(p_token, ''));
  if not found then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'PT404';
  end if;
  if (i.invitee_user_id is not null and i.invitee_user_id <> v_uid)
     or (i.invitee_email_normalized is not null and i.invitee_email_normalized is distinct from private.caller_verified_email()) then
    raise exception 'FORBIDDEN' using errcode = 'PT403';
  end if;
  if i.status = 'ACCEPTED' then raise exception 'INVITATION_USED'     using errcode = 'PT409'; end if;
  if i.status = 'REVOKED'  then raise exception 'INVITATION_REVOKED'  using errcode = 'PT410'; end if;
  if i.status = 'DECLINED' then raise exception 'INVITATION_DECLINED' using errcode = 'PT410'; end if;
  if i.status = 'EXPIRED' or i.expires_at <= now() then
    raise exception 'INVITATION_EXPIRED' using errcode = 'PT410';
  end if;

  return query
  select i.id, i.resource_type, coalesce(i.place_id, i.visit_id, i.journal_id),
         case i.resource_type
           when 'PLACE'   then (select p.title from public.places p where p.id = i.place_id)
           when 'JOURNAL' then (select j.title from public.journals j where j.id = i.journal_id)
         end,
         case when i.resource_type = 'VISIT' then (select v.visited_at from public.visits v where v.id = i.visit_id) end,
         case when i.resource_type = 'JOURNAL' then (select j.cover_path from public.journals j where j.id = i.journal_id) end,
         (select pr.display_name from public.profiles pr where pr.id = i.invited_by),
         i.role, i.expires_at,
         (i.invitee_user_id is not null or i.invitee_email_normalized is not null);
end;
$$;

-- -------------------------------------------------------- accept_invitation ----
create function public.accept_invitation(p_token text)
returns table (resource_type public.resource_type, resource_id uuid, role public.member_role)
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := private.require_auth();
  i       public.invitations%rowtype;
  v_res   uuid;
  v_owner record;
  v_mem   record;
begin
  -- Row lock: two devices accepting the same token serialize here; the loser sees ACCEPTED.
  select * into i from public.invitations x
   where x.token_hash = private.hash_token(coalesce(p_token, '')) for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'PT404';
  end if;

  if (i.invitee_user_id is not null and i.invitee_user_id <> v_uid)
     or (i.invitee_email_normalized is not null and i.invitee_email_normalized is distinct from private.caller_verified_email()) then
    raise exception 'FORBIDDEN' using errcode = 'PT403';
  end if;
  if i.status = 'ACCEPTED' then raise exception 'INVITATION_USED'     using errcode = 'PT409'; end if;
  if i.status = 'REVOKED'  then raise exception 'INVITATION_REVOKED'  using errcode = 'PT410'; end if;
  if i.status = 'DECLINED' then raise exception 'INVITATION_DECLINED' using errcode = 'PT410'; end if;
  if i.status = 'EXPIRED' or i.expires_at <= now() then
    raise exception 'INVITATION_EXPIRED' using errcode = 'PT410';
  end if;

  v_res := coalesce(i.place_id, i.visit_id, i.journal_id);
  select * into v_owner from private.resource_info(i.resource_type, v_res);
  if not found or v_owner.is_deleted then
    raise exception 'RESOURCE_NOT_FOUND' using errcode = 'PT404';
  end if;
  if v_owner.owner_id = v_uid then
    raise exception 'ALREADY_OWNER' using errcode = 'PT409';
  end if;

  select * into v_mem from private.member_lock(i.resource_type, v_res, v_uid);
  if found and v_mem.status = 'ACTIVE' then
    raise exception 'ALREADY_MEMBER' using errcode = 'PT409';
  end if;

  perform private.member_activate(i.resource_type, v_res, v_uid, i.role, i.invited_by);

  update public.invitations x
     set status = 'ACCEPTED', accepted_by = v_uid, accepted_at = now()
   where x.id = i.id;

  perform private.write_audit('INVITATION_ACCEPTED', 'INVITATION', i.id, i.invited_by,
    jsonb_build_object('resource_type', i.resource_type, 'resource_id', v_res, 'role', i.role,
                       'reactivated', v_mem.member_id is not null));

  return query select i.resource_type, v_res, i.role;
end;
$$;

-- ------------------------------------------------- decline / revoke invitation ----
create function public.decline_invitation(p_token text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := private.require_auth();
  i     public.invitations%rowtype;
begin
  select * into i from public.invitations x
   where x.token_hash = private.hash_token(coalesce(p_token, '')) for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'PT404';
  end if;
  if (i.invitee_user_id is not null and i.invitee_user_id <> v_uid)
     or (i.invitee_email_normalized is not null and i.invitee_email_normalized is distinct from private.caller_verified_email()) then
    raise exception 'FORBIDDEN' using errcode = 'PT403';
  end if;
  if i.status = 'ACCEPTED' then raise exception 'INVITATION_USED'     using errcode = 'PT409'; end if;
  if i.status = 'REVOKED'  then raise exception 'INVITATION_REVOKED'  using errcode = 'PT410'; end if;
  if i.status = 'DECLINED' then raise exception 'INVITATION_DECLINED' using errcode = 'PT410'; end if;
  if i.status = 'EXPIRED' or i.expires_at <= now() then
    raise exception 'INVITATION_EXPIRED' using errcode = 'PT410';
  end if;

  update public.invitations x set status = 'DECLINED' where x.id = i.id;
  perform private.write_audit('INVITATION_DECLINED', 'INVITATION', i.id, i.invited_by,
    jsonb_build_object('resource_type', i.resource_type, 'resource_id', coalesce(i.place_id, i.visit_id, i.journal_id)));
end;
$$;

create function public.revoke_invitation(p_invitation_id uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := private.require_auth();
  i     public.invitations%rowtype;
  v_res uuid;
begin
  select * into i from public.invitations x where x.id = p_invitation_id for update;
  if not found then
    raise exception 'FORBIDDEN' using errcode = 'PT403';   -- same answer as "not yours": no enumeration
  end if;
  v_res := coalesce(i.place_id, i.visit_id, i.journal_id);
  perform 1 from private.assert_owner(i.resource_type, v_res);
  if i.status <> 'PENDING' then
    raise exception 'INVITATION_NOT_PENDING' using errcode = 'PT409';
  end if;
  update public.invitations x set status = 'REVOKED' where x.id = i.id;
  perform private.write_audit('INVITATION_REVOKED', 'INVITATION', i.id, i.invitee_user_id,
    jsonb_build_object('resource_type', i.resource_type, 'resource_id', v_res));
end;
$$;

-- Owner's view of invitations (token_hash is never returned).
create function public.list_invitations(p_resource_type public.resource_type, p_resource_id uuid)
returns table (
  id uuid, role public.member_role, status public.invitation_status,
  invitee_user_id uuid, invitee_email_normalized text,
  expires_at timestamptz, accepted_by uuid, accepted_at timestamptz, created_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform 1 from private.assert_owner(p_resource_type, p_resource_id);
  return query
  select i.id, i.role,
         case when i.status = 'PENDING' and i.expires_at <= now() then 'EXPIRED'::public.invitation_status else i.status end,
         i.invitee_user_id, i.invitee_email_normalized, i.expires_at, i.accepted_by, i.accepted_at, i.created_at
  from public.invitations i
  where i.resource_type = p_resource_type
    and coalesce(i.place_id, i.visit_id, i.journal_id) = p_resource_id
  order by i.created_at desc;
end;
$$;

-- ----------------------------------------------------------- change role ----
create function public.change_member_role(
  p_resource_type public.resource_type, p_resource_id uuid, p_user_id uuid, p_role public.member_role
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_state record;
  v_mem   record;
begin
  select * into v_state from private.assert_owner(p_resource_type, p_resource_id);
  if p_role is null or p_role not in ('EDITOR', 'VIEWER') then
    raise exception 'INVALID_ROLE' using errcode = 'PT400';
  end if;
  if v_state.is_deleted then
    raise exception 'RESOURCE_UNAVAILABLE' using errcode = 'PT409';
  end if;
  select * into v_mem from private.member_lock(p_resource_type, p_resource_id, p_user_id);
  if not found or v_mem.status <> 'ACTIVE' then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'PT404';
  end if;
  if v_mem.role <> p_role then
    perform private.member_set(p_resource_type, v_mem.member_id, p_role, null);
    perform private.write_audit('MEMBER_ROLE_CHANGED', p_resource_type::text, p_resource_id, p_user_id,
      jsonb_build_object('from', v_mem.role, 'to', p_role));
  end if;
end;
$$;

-- ----------------------------------------------------------- remove member ----
create function public.remove_member(
  p_resource_type public.resource_type, p_resource_id uuid, p_user_id uuid
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := private.require_auth();
  v_mem record;
begin
  perform 1 from private.assert_owner(p_resource_type, p_resource_id);
  if p_user_id = v_uid then
    raise exception 'OWNER_CANNOT_BE_REMOVED' using errcode = 'PT409',
      detail = 'Transfer ownership first (BRULE-JR-13).';
  end if;
  select * into v_mem from private.member_lock(p_resource_type, p_resource_id, p_user_id);
  if not found or v_mem.status <> 'ACTIVE' then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'PT404';
  end if;
  perform private.member_set(p_resource_type, v_mem.member_id, null, 'REMOVED');
  perform private.write_audit('MEMBER_REMOVED', p_resource_type::text, p_resource_id, p_user_id,
    jsonb_build_object('role', v_mem.role));
end;
$$;

-- ---------------------------------------------------------- leave resource ----
create function public.leave_resource(p_resource_type public.resource_type, p_resource_id uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := private.require_auth();
  v_state record;
  v_mem   record;
begin
  select * into v_state from private.resource_info(p_resource_type, p_resource_id);
  if found and v_state.owner_id = v_uid then
    raise exception 'OWNER_MUST_TRANSFER' using errcode = 'PT409',
      detail = 'Owner cannot leave: transfer ownership or archive/delete the resource (BRULE-JR-13).';
  end if;
  select * into v_mem from private.member_lock(p_resource_type, p_resource_id, v_uid);
  if not found or v_mem.status <> 'ACTIVE' then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'PT404';
  end if;
  perform private.member_set(p_resource_type, v_mem.member_id, null, 'LEFT');
  perform private.write_audit('MEMBER_LEFT', p_resource_type::text, p_resource_id, v_uid,
    jsonb_build_object('role', v_mem.role));
end;
$$;

-- ------------------------------------------------------------------ unshare ----
-- Owner revokes all access: every ACTIVE member -> REMOVED, every PENDING invitation -> REVOKED.
create function public.unshare_resource(p_resource_type public.resource_type, p_resource_id uuid)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_removed integer;
  v_revoked integer;
begin
  perform 1 from private.assert_owner(p_resource_type, p_resource_id);
  execute format('update public.%I set status = ''REMOVED'' where %I = $1 and status = ''ACTIVE''',
                 private.member_table(p_resource_type), private.member_fk(p_resource_type))
    using p_resource_id;
  get diagnostics v_removed = row_count;

  update public.invitations i set status = 'REVOKED'
   where i.status = 'PENDING' and coalesce(i.place_id, i.visit_id, i.journal_id) = p_resource_id;
  get diagnostics v_revoked = row_count;

  perform private.write_audit('RESOURCE_UNSHARED', p_resource_type::text, p_resource_id, null,
    jsonb_build_object('members_removed', v_removed, 'invitations_revoked', v_revoked));
  return v_removed;
end;
$$;

-- ------------------------------------------------------ transfer ownership ----
create function public.transfer_ownership(
  p_resource_type       public.resource_type,
  p_resource_id         uuid,
  p_new_owner_id        uuid,
  p_previous_owner_role public.member_role default 'EDITOR'   -- NULL = previous owner loses access
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid     uuid := private.require_auth();
  v_state   record;
  v_mem     record;
  v_revoked integer;
begin
  select * into v_state from private.assert_owner(p_resource_type, p_resource_id);
  if v_state.is_deleted then
    raise exception 'RESOURCE_UNAVAILABLE' using errcode = 'PT409';
  end if;
  if p_new_owner_id is null or p_new_owner_id = v_uid then
    raise exception 'INVALID_NEW_OWNER' using errcode = 'PT400';
  end if;
  if p_previous_owner_role = 'OWNER' then
    raise exception 'INVALID_ROLE' using errcode = 'PT400';
  end if;

  -- the new owner must already be an ACTIVE member (explicit, consented flow)
  select * into v_mem from private.member_lock(p_resource_type, p_resource_id, p_new_owner_id);
  if not found or v_mem.status <> 'ACTIVE' then
    raise exception 'NEW_OWNER_NOT_MEMBER' using errcode = 'PT409';
  end if;

  execute format('update public.%I set owner_id = $2 where id = $1', private.resource_table(p_resource_type))
    using p_resource_id, p_new_owner_id;

  -- owner lives in owner_id only: drop the new owner's membership row, give the old owner a member role
  execute format('delete from public.%I where id = $1', private.member_table(p_resource_type)) using v_mem.member_id;
  if p_previous_owner_role is not null then
    perform private.member_activate(p_resource_type, p_resource_id, v_uid, p_previous_owner_role, p_new_owner_id);
  end if;

  -- invitations issued by the previous owner must not outlive the transfer
  update public.invitations i set status = 'REVOKED'
   where i.status = 'PENDING' and coalesce(i.place_id, i.visit_id, i.journal_id) = p_resource_id;
  get diagnostics v_revoked = row_count;

  perform private.write_audit('OWNERSHIP_TRANSFERRED', p_resource_type::text, p_resource_id, p_new_owner_id,
    jsonb_build_object('from', v_uid, 'to', p_new_owner_id,
                       'previous_owner_role', p_previous_owner_role, 'invitations_revoked', v_revoked));
end;
$$;

-- ------------------------------------------------------------ housekeeping ----
-- Persist EXPIRED for stale PENDING invitations (schedule with pg_cron or call from an Edge Function).
create function public.expire_pending_invitations() returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_n integer;
begin
  update public.invitations i set status = 'EXPIRED' where i.status = 'PENDING' and i.expires_at <= now();
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
