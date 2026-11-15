-- Invitation lifecycle + membership RPCs + ownership transfer + audit.
begin;
select plan(112);
select tests.seed_users();

insert into public.places (id, owner_id, title, latitude, longitude) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('alice'), 'Cafe A', 10.77, 106.70);
insert into public.visits (id, place_id, owner_id, created_by, visited_at, timezone_id) values
  ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), now(), 'UTC');
insert into public.journals (id, owner_id, title) values
  ('33333333-0000-0000-0000-000000000001', tests.u('alice'), 'Trip 1'),
  ('33333333-0000-0000-0000-000000000002', tests.u('alice'), 'Trip 2');
insert into public.place_members (place_id, user_id, role) values ('11111111-0000-0000-0000-00000000000a', tests.u('bob'), 'EDITOR');
insert into public.journal_members (journal_id, user_id, role) values
  ('33333333-0000-0000-0000-000000000002', tests.u('bob'),   'EDITOR'),
  ('33333333-0000-0000-0000-000000000002', tests.u('carol'), 'VIEWER');

-- ============ creating invitations =====================================================
select tests.authenticate_as('dave');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'VIEWER')$$, 'PT403', 'FORBIDDEN', 'non-owner cannot invite');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'VIEWER')$$, 'PT403', 'FORBIDDEN', 'Editor cannot invite (only Owner manages membership)');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'OWNER')$$, 'PT400', 'INVALID_ROLE', 'cannot invite an OWNER');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'VIEWER', null, null, interval '31 days')$$, 'PT400', 'INVALID_EXPIRY', 'expiry is bounded');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'VIEWER', null, tests.u('alice'))$$, 'PT400', 'CANNOT_INVITE_SELF', 'cannot invite yourself (user id)');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'VIEWER', 'ALICE@example.test')$$, 'PT400', 'CANNOT_INVITE_SELF', 'cannot invite yourself (email, normalized)');
select throws_ok($$select * from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'VIEWER', null, tests.u('bob'))$$, 'PT409', 'ALREADY_MEMBER', 'cannot invite an existing ACTIVE member');
select lives_ok($$select set_config('tests.t1', token, true), set_config('tests.t1_id', invitation_id::text, true)
                  from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'VIEWER')$$,
                'Owner creates a Place invitation (returns the raw token once)');
select tests.clear_authentication();

select is((select count(*)::int from public.invitations where token_hash = current_setting('tests.t1')), 0, 'raw token is not stored');
select is((select token_hash from public.invitations where id = current_setting('tests.t1_id')::uuid),
          encode(sha256(convert_to(current_setting('tests.t1'), 'UTF8')), 'hex'), 'only the sha256 hash of the token is stored');
select is(length(current_setting('tests.t1')), 64, 'token carries 256 bits (64 hex chars)');
select results_eq($$select status::text, role::text, resource_type::text, expires_at > now() from public.invitations where id = current_setting('tests.t1_id')::uuid$$,
                  $$values ('PENDING'::text, 'VIEWER'::text, 'PLACE'::text, true)$$, 'invitation is PENDING with a future expiry');

-- ============ resolve + accept ==========================================================
select tests.authenticate_as('carol');
select is_empty($$select * from public.places$$, '[§33.4] a PENDING invitation grants no access');
select results_eq($$select resource_title, inviter_display_name, role::text, email_bound from public.resolve_invitation(current_setting('tests.t1'))$$,
                  $$values ('Cafe A'::text, 'Alice'::text, 'VIEWER'::text, false)$$, 'invitee gets a minimal preview (title, inviter, role)');
select throws_ok($$select * from public.resolve_invitation('deadbeef')$$, 'PT404', 'INVITATION_NOT_FOUND', 'unknown token -> not found');
select throws_ok($$select * from public.invitations$$, '42501', null, 'clients have no direct access to invitations (token_hash stays server-side)');
select throws_ok($$insert into public.place_members (place_id, user_id, role) values ('11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'EDITOR')$$, '42501', null, 'clients cannot insert memberships directly (no self-service OWNER/EDITOR)');
select results_eq($$select resource_type::text, resource_id, role::text from public.accept_invitation(current_setting('tests.t1'))$$,
                  $$values ('PLACE'::text, '11111111-0000-0000-0000-00000000000a'::uuid, 'VIEWER'::text)$$, 'invitee accepts');
select is((select title from public.places), 'Cafe A', 'after accept the invitee reads the Place');
select is_empty($$select * from public.visits$$, 'accepting a Place share exposes no Visits');
select tests.clear_authentication();
select results_eq($$select status::text, accepted_by from public.invitations where id = current_setting('tests.t1_id')::uuid$$,
                  $$values ('ACCEPTED'::text, tests.u('carol'))$$, 'invitation is consumed atomically with the membership');
select is((select count(*)::int from public.place_members where place_id = '11111111-0000-0000-0000-00000000000a' and user_id = tests.u('carol') and status = 'ACTIVE' and role = 'VIEWER'), 1, 'ACTIVE VIEWER membership created');

select tests.authenticate_as('dave');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t1'))$$, 'PT409', 'INVITATION_USED', '[BRULE-JR-10] a used token cannot be reused by anyone');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t1'))$$, 'PT409', 'INVITATION_USED', 'second accept of the same token (other device) loses');
select tests.clear_authentication();

-- ============ expired ===================================================================
select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t2', token, true), set_config('tests.t2_id', invitation_id::text, true)
                  from public.create_invitation('JOURNAL', '33333333-0000-0000-0000-000000000001', 'EDITOR')$$, 'Owner invites an Editor to Journal 1');
select tests.clear_authentication();
update public.invitations set expires_at = now() - interval '1 minute' where id = current_setting('tests.t2_id')::uuid;
select tests.authenticate_as('dave');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t2'))$$, 'PT410', 'INVITATION_EXPIRED', '[6.3] expired invitation cannot be accepted');
select throws_ok($$select * from public.resolve_invitation(current_setting('tests.t2'))$$, 'PT410', 'INVITATION_EXPIRED', 'expired invitation cannot be previewed');
select is_empty($$select * from public.journals$$, 'no access was granted by the expired invitation');
select tests.clear_authentication();
select is((select count(*)::int from public.journal_members where journal_id = '33333333-0000-0000-0000-000000000001'), 0, 'no membership row was created');
select tests.authenticate_as('alice');
select is((select status::text from public.list_invitations('JOURNAL', '33333333-0000-0000-0000-000000000001')), 'EXPIRED', 'list_invitations reports EXPIRED for stale PENDING rows');
select tests.clear_authentication();
select is(public.expire_pending_invitations(), 1, 'expire_pending_invitations persists EXPIRED');
select is((select status::text from public.invitations where id = current_setting('tests.t2_id')::uuid), 'EXPIRED', '...status is stored');

-- ============ revoked / declined ==========================================================
select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t3', token, true), set_config('tests.t3_id', invitation_id::text, true)
                  from public.create_invitation('JOURNAL', '33333333-0000-0000-0000-000000000001', 'VIEWER')$$, 'Owner creates another invitation');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select throws_ok($$select public.revoke_invitation(current_setting('tests.t3_id')::uuid)$$, 'PT403', 'FORBIDDEN', 'non-owner cannot revoke');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select lives_ok($$select public.revoke_invitation(current_setting('tests.t3_id')::uuid)$$, '[BRULE-JR-11] Owner revokes a pending invitation');
select throws_ok($$select public.revoke_invitation(current_setting('tests.t3_id')::uuid)$$, 'PT409', 'INVITATION_NOT_PENDING', 'revoking twice is rejected');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t3'))$$, 'PT410', 'INVITATION_REVOKED', '[6.3] revoked invitation cannot be accepted');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t4', token, true) from public.create_invitation('JOURNAL', '33333333-0000-0000-0000-000000000001', 'VIEWER')$$, 'Owner creates an invitation to be declined');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select lives_ok($$select public.decline_invitation(current_setting('tests.t4'))$$, 'invitee declines');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t4'))$$, 'PT410', 'INVITATION_DECLINED', 'declined invitation cannot be accepted');
select tests.clear_authentication();

-- ============ identity binding ===========================================================
select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t5', token, true) from public.create_invitation('VISIT', '22222222-0000-0000-0000-000000000001', 'EDITOR', ' ERIN@Example.test ')$$, 'Owner invites a Visit editor by e-mail (normalized)');
select lives_ok($$select set_config('tests.t6', token, true) from public.create_invitation('JOURNAL', '33333333-0000-0000-0000-000000000001', 'VIEWER', null, tests.u('carol'))$$, 'Owner invites a specific account');
select tests.clear_authentication();
select is((select invitee_email_normalized from public.invitations where token_hash = encode(sha256(convert_to(current_setting('tests.t5'), 'UTF8')), 'hex')), 'erin@example.test', 'e-mail stored trimmed + lower-cased');

select tests.authenticate_as('dave');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t5'))$$, 'PT403', 'FORBIDDEN', 'e-mail bound invitation cannot be accepted by another account');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t6'))$$, 'PT403', 'FORBIDDEN', 'user bound invitation cannot be accepted by another account');
select throws_ok($$select * from public.resolve_invitation(current_setting('tests.t6'))$$, 'PT403', 'FORBIDDEN', '...nor previewed');
select tests.clear_authentication();

update auth.users set email_confirmed_at = null where id = tests.u('erin');
select tests.authenticate_as('erin');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t5'))$$, 'PT403', 'FORBIDDEN', 'e-mail binding requires a VERIFIED e-mail');
select tests.clear_authentication();
update auth.users set email_confirmed_at = now() where id = tests.u('erin');
select tests.authenticate_as('erin');
select lives_ok($$select * from public.accept_invitation(current_setting('tests.t5'))$$, 'verified invitee accepts the Visit share');
select is((select count(*)::int from public.visits), 1, 'Visit Editor reads the shared Visit');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select lives_ok($$select * from public.accept_invitation(current_setting('tests.t6'))$$, 'bound account accepts the Journal invitation');
select tests.clear_authentication();

-- ============ edge cases at accept time ===================================================
select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t7', token, true) from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'EDITOR')$$, 'Owner creates an open invitation');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t7'))$$, 'PT409', 'ALREADY_OWNER', 'Owner cannot accept her own invitation');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t7'))$$, 'PT409', 'ALREADY_MEMBER', 'an ACTIVE member cannot accept again (no role escalation through a new invitation)');
select tests.clear_authentication();
select is((select role::text from public.place_members where user_id = tests.u('carol') and place_id = '11111111-0000-0000-0000-00000000000a'), 'VIEWER', '...and the role stays VIEWER');

-- replace policy
select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t8a', token, true) from public.create_invitation('JOURNAL', '33333333-0000-0000-0000-000000000001', 'VIEWER', null, tests.u('dave'))$$, 'first invitation for dave');
select lives_ok($$select set_config('tests.t8b', token, true) from public.create_invitation('JOURNAL', '33333333-0000-0000-0000-000000000001', 'EDITOR', null, tests.u('dave'))$$, 'second invitation for the same invitee replaces the first');
select tests.clear_authentication();
select is((select count(*)::int from public.invitations where status = 'PENDING' and journal_id = '33333333-0000-0000-0000-000000000001' and invitee_user_id = tests.u('dave')), 1, 'unique active invite: one PENDING per (resource, invitee)');
select tests.authenticate_as('dave');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t8a'))$$, 'PT410', 'INVITATION_REVOKED', 'replaced invitation is revoked');
select tests.clear_authentication();

-- ============ role changes ===============================================================
select tests.authenticate_as('carol');
select throws_ok($$select public.change_member_role('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'EDITOR')$$, 'PT403', 'FORBIDDEN', 'a Viewer cannot promote herself');
select throws_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('bob'))$$, 'PT403', 'FORBIDDEN', 'a Viewer cannot remove members');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select throws_ok($$select public.change_member_role('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'EDITOR')$$, 'PT403', 'FORBIDDEN', 'an Editor cannot change roles');
select throws_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('carol'))$$, 'PT403', 'FORBIDDEN', 'an Editor cannot remove members');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select throws_ok($$select public.change_member_role('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'OWNER')$$, 'PT400', 'INVALID_ROLE', 'role cannot be changed to OWNER');
select throws_ok($$select public.change_member_role('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('dave'), 'EDITOR')$$, 'PT404', 'MEMBER_NOT_FOUND', 'cannot change the role of a non-member');
select lives_ok($$select public.change_member_role('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'EDITOR')$$, 'Owner promotes Viewer to Editor');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select lives_ok($$insert into public.memories (place_id, body) values ('11111111-0000-0000-0000-00000000000a', 'now I can write')$$, 'the promoted member can now contribute');
select tests.clear_authentication();
select is((select count(*)::int from public.audit_log where action = 'MEMBER_ROLE_CHANGED' and target_user_id = tests.u('carol') and metadata ->> 'from' = 'VIEWER' and metadata ->> 'to' = 'EDITOR'), 1, 'role change is audited');

-- ============ remove / leave / reactivate ===================================================
select tests.authenticate_as('alice');
select throws_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('alice'))$$, 'PT409', 'OWNER_CANNOT_BE_REMOVED', 'Owner cannot remove herself');
select throws_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('dave'))$$, 'PT404', 'MEMBER_NOT_FOUND', 'cannot remove a non-member');
select lives_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('carol'))$$, 'Owner removes Carol');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is_empty($$select * from public.places$$, '[6.3] removed member is denied on the very next request');
select throws_ok($$insert into public.memories (place_id, body) values ('11111111-0000-0000-0000-00000000000a', 'x')$$, '42501', null, 'removed member cannot contribute');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t9', token, true) from public.create_invitation('PLACE', '11111111-0000-0000-0000-00000000000a', 'VIEWER', null, tests.u('carol'))$$, 'Owner re-invites Carol');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select lives_ok($$select * from public.accept_invitation(current_setting('tests.t9'))$$, 'Carol accepts: membership is reactivated');
select tests.clear_authentication();
select results_eq($$select count(*)::int, min(role::text), min(status::text) from public.place_members where place_id = '11111111-0000-0000-0000-00000000000a' and user_id = tests.u('carol')$$,
                  $$values (1, 'VIEWER'::text, 'ACTIVE'::text)$$, 'reactivation reuses the single (resource,user) row with the NEW role');
select tests.authenticate_as('carol');
select throws_ok($$select public.leave_resource('PLACE', '11111111-0000-0000-0000-00000000000b')$$, 'PT404', 'MEMBER_NOT_FOUND', 'cannot leave a resource you are not in');
select lives_ok($$select public.leave_resource('PLACE', '11111111-0000-0000-0000-00000000000a')$$, 'member leaves');
select is_empty($$select * from public.places$$, 'a member who left has no access');
select tests.clear_authentication();
select is((select status::text from public.place_members where user_id = tests.u('carol')), 'LEFT', 'status LEFT (row and contributions are kept)');
select tests.authenticate_as('alice');
select throws_ok($$select public.leave_resource('PLACE', '11111111-0000-0000-0000-00000000000a')$$, 'PT409', 'OWNER_MUST_TRANSFER', '[BRULE-JR-13] Owner cannot leave without transferring ownership');
select tests.clear_authentication();

-- ============ unshare ===========================================================================
select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t10', token, true) from public.create_invitation('JOURNAL', '33333333-0000-0000-0000-000000000001', 'VIEWER')$$, 'a pending invitation exists on Journal 1');
select is(public.unshare_resource('JOURNAL', '33333333-0000-0000-0000-000000000001'), 1, 'unshare removes every ACTIVE member (carol)');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is_empty($$select * from public.journals where id = '33333333-0000-0000-0000-000000000001'$$, '[§8] unshared Journal is invisible to former members');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select throws_ok($$select * from public.accept_invitation(current_setting('tests.t10'))$$, 'PT410', 'INVITATION_REVOKED', 'unshare also revokes pending invitations');
select tests.clear_authentication();

-- ============ ownership transfer ====================================================================
select tests.authenticate_as('alice');
select lives_ok($$select set_config('tests.t11', token, true) from public.create_invitation('JOURNAL', '33333333-0000-0000-0000-000000000002', 'VIEWER')$$, 'a pending invitation exists on Journal 2');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select throws_ok($$select public.transfer_ownership('JOURNAL', '33333333-0000-0000-0000-000000000002', tests.u('dave'))$$, 'PT403', 'FORBIDDEN', 'non-owner cannot transfer ownership');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select throws_ok($$select public.transfer_ownership('JOURNAL', '33333333-0000-0000-0000-000000000002', tests.u('bob'))$$, 'PT403', 'FORBIDDEN', 'an Editor cannot make himself Owner');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select throws_ok($$select public.transfer_ownership('JOURNAL', '33333333-0000-0000-0000-000000000002', tests.u('dave'))$$, 'PT409', 'NEW_OWNER_NOT_MEMBER', 'new owner must already be an ACTIVE member');
select throws_ok($$select public.transfer_ownership('JOURNAL', '33333333-0000-0000-0000-000000000002', tests.u('alice'))$$, 'PT400', 'INVALID_NEW_OWNER', 'cannot transfer to yourself');
select throws_ok($$select public.transfer_ownership('JOURNAL', '33333333-0000-0000-0000-000000000002', tests.u('bob'), 'OWNER')$$, 'PT400', 'INVALID_ROLE', 'previous owner role cannot be OWNER');
select lives_ok($$select public.transfer_ownership('JOURNAL', '33333333-0000-0000-0000-000000000002', tests.u('bob'))$$, 'Owner transfers Journal 2 to Bob (explicit RPC)');
select tests.clear_authentication();
select results_eq($$select owner_id from public.journals where id = '33333333-0000-0000-0000-000000000002'$$, $$values (tests.u('bob'))$$, 'owner_id changed');
select is((select count(*)::int from public.journal_members where journal_id = '33333333-0000-0000-0000-000000000002' and user_id = tests.u('bob')), 0, '[D2] new owner has no membership row (owner_id only)');
select results_eq($$select role::text, status::text from public.journal_members where journal_id = '33333333-0000-0000-0000-000000000002' and user_id = tests.u('alice')$$,
                  $$values ('EDITOR'::text, 'ACTIVE'::text)$$, 'previous owner stays as an EDITOR');
select is((select count(*)::int from public.journal_members where journal_id = '33333333-0000-0000-0000-000000000002' and role::text = 'OWNER'), 0, 'ERD-07: exactly one Owner (membership holds none)');
select is((select status::text from public.invitations where token_hash = encode(sha256(convert_to(current_setting('tests.t11'), 'UTF8')), 'hex')), 'REVOKED', 'pending invitations of the previous owner are revoked');
select tests.authenticate_as('alice');
select is(tests.affected($$update public.journals set title = 'old owner edit' where id = '33333333-0000-0000-0000-000000000002'$$), 0::bigint, 'previous owner can no longer edit metadata');
select throws_ok($$select public.remove_member('JOURNAL', '33333333-0000-0000-0000-000000000002', tests.u('carol'))$$, 'PT403', 'FORBIDDEN', 'previous owner can no longer manage members');
select is((select count(*)::int from public.journals where id = '33333333-0000-0000-0000-000000000002'), 1, '...but still reads the Journal as Editor');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is(tests.affected($$update public.journals set title = 'new owner edit' where id = '33333333-0000-0000-0000-000000000002'$$), 1::bigint, 'new owner edits metadata');
select lives_ok($$select public.transfer_ownership('JOURNAL', '33333333-0000-0000-0000-000000000002', tests.u('carol'), null)$$, 'transfer with previous_owner_role = NULL (Bob leaves entirely)');
select is_empty($$select * from public.journals where id = '33333333-0000-0000-0000-000000000002'$$, 'previous owner without a role has no access');
select tests.clear_authentication();
select is((select owner_id from public.journals where id = '33333333-0000-0000-0000-000000000002'), tests.u('carol'), 'Carol is now Owner');

-- visit transfer (Erin is an ACTIVE Visit editor from the e-mail invitation)
select tests.authenticate_as('alice');
select lives_ok($$select public.transfer_ownership('VISIT', '22222222-0000-0000-0000-000000000001', tests.u('erin'))$$, 'Visit owner transfers the Visit to a Visit member');
select tests.clear_authentication();
select tests.authenticate_as('erin');
select is(tests.affected($$update public.visits set note = 'erin owns this now' where id = '22222222-0000-0000-0000-000000000001'$$), 1::bigint, 'new Visit owner can edit it');
select results_eq($$select title from public.my_visit_places()$$, $$values ('Cafe A'::text)$$, '[D3] new Visit owner gets the Place projection');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select is(tests.affected($$update public.visits set note = 'old owner edit' where id = '22222222-0000-0000-0000-000000000001'$$), 0::bigint, 'old Visit owner (now Editor) cannot edit Visit metadata');
select tests.clear_authentication();
select is((select count(*)::int from public.audit_log where action = 'OWNERSHIP_TRANSFERRED'), 3, 'every transfer is audited');

-- ============ audit visibility ======================================================================
select tests.authenticate_as('dave');
select is((select count(*)::int from public.audit_log where resource_type = 'PLACE'), 0, 'outsiders cannot read audit entries of other people''s resources');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select cmp_ok((select count(*)::int from public.audit_log), '>', 0, 'actors and targets can read the audit entries that concern them');
select throws_ok($$insert into public.audit_log (action, resource_type) values ('FORGED', 'PLACE')$$, '42501', null, 'clients cannot forge audit entries');
select tests.clear_authentication();
select cmp_ok((select count(distinct action)::int from public.audit_log), '>=', 9, 'audit_log has entries for invitation + membership lifecycle');

select * from finish();
rollback;
