-- Storage: private bucket, storage.objects policies tied to memory_attachments / memory parents.
begin;
select plan(46);
select tests.seed_users();
-- Hosted Supabase: storage.protect_delete() blocks direct DELETE on storage tables unless this flag is set
-- (the Storage API sets it). Setting it lets the RLS delete-policy tests run; harmless on plain Postgres.
select set_config('storage.allow_delete_query', 'true', true);

insert into public.places (id, owner_id, title, latitude, longitude) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('alice'), 'Cafe A', 10.77, 106.70);
insert into public.place_members (place_id, user_id, role) values
  ('11111111-0000-0000-0000-00000000000a', tests.u('bob'),   'EDITOR'),
  ('11111111-0000-0000-0000-00000000000a', tests.u('carol'), 'VIEWER');
insert into public.visits (id, place_id, owner_id, created_by, visited_at, timezone_id) values
  ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-00000000000a', tests.u('alice'), tests.u('alice'), now(), 'UTC');
insert into public.visit_members (visit_id, user_id, role) values
  ('22222222-0000-0000-0000-000000000001', tests.u('erin'), 'EDITOR'),
  ('22222222-0000-0000-0000-000000000001', tests.u('dave'), 'VIEWER');
insert into public.memories (id, author_id, place_id, visit_id, type, body) values
  ('55555555-0000-0000-0000-000000000001', tests.u('bob'),   '11111111-0000-0000-0000-00000000000a', null, 'PHOTO', 'bob photo'),
  ('55555555-0000-0000-0000-000000000002', tests.u('erin'),  null, '22222222-0000-0000-0000-000000000001', 'PHOTO', 'erin photo'),
  ('55555555-0000-0000-0000-000000000003', tests.u('alice'), '11111111-0000-0000-0000-00000000000a', null, 'PHOTO', 'alice photo');

-- ============ constraints on the metadata row (superuser) ===============================
select throws_ok(format($f$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
                   values ('aaaaaaaa-1111-0000-0000-0000000000f1', '55555555-0000-0000-0000-000000000001', %L, 'image/jpeg', 10)$f$,
                   tests.media_path('bob', '55555555-0000-0000-0000-000000000002', 'aaaaaaaa-1111-0000-0000-0000000000f1')),
                 '23514', null, 'storage_path memory segment must equal memory_id');
select throws_ok(format($f$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
                   values ('aaaaaaaa-1111-0000-0000-0000000000f2', '55555555-0000-0000-0000-000000000001', %L, 'image/jpeg', 10)$f$,
                   tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-0000000000f9')),
                 '23514', null, 'file name must equal the attachment id (UUID path, never the client file name)');
select throws_ok(format($f$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
                   values ('aaaaaaaa-1111-0000-0000-0000000000f3', '55555555-0000-0000-0000-000000000001', %L, 'image/gif', 10)$f$,
                   tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-0000000000f3', 'gif')),
                 '23514', null, 'only jpg/jpeg/png/heic paths accepted');
select throws_ok(format($f$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
                   values ('aaaaaaaa-1111-0000-0000-0000000000f4', '55555555-0000-0000-0000-000000000001', %L, 'image/gif', 10)$f$,
                   tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-0000000000f4')),
                 '23514', null, 'MIME allowlist (jpeg/png/heic)');
select throws_ok(format($f$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
                   values ('aaaaaaaa-1111-0000-0000-0000000000f5', '55555555-0000-0000-0000-000000000001', %L, 'image/jpeg', 2097153)$f$,
                   tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-0000000000f5')),
                 '23514', null, 'size limit 2 MB (client compresses to <= ~500 KB)');
select is((select file_size_limit from storage.buckets where id = 'memory-media'), 2097152::bigint, 'memory-media bucket limit is 2 MB');
select throws_ok($$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
                   values ('aaaaaaaa-1111-0000-0000-0000000000f6', '55555555-0000-0000-0000-000000000001', '../../etc/passwd', 'image/jpeg', 10)$$,
                 '23514', null, 'path traversal / free-form paths rejected');

-- ============ upload by an Editor =======================================================
select tests.authenticate_as('bob');
select lives_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000001')),
                'Place Editor uploads an object for his own Memory');
select lives_ok(format($f$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes, width, height)
                   values ('aaaaaaaa-1111-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', %L, 'image/jpeg', 12345, 800, 600)$f$,
                tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000001')),
                'author finalizes the attachment metadata row');
select throws_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000001')),
                '23505', null, 'the same path cannot be written twice (no overwrite)');
select throws_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('alice', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000002')),
                '42501', null, 'upload under another user''s folder is denied');
select throws_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('bob', '55555555-0000-0000-0000-000000000003', 'aaaaaaaa-1111-0000-0000-000000000003')),
                '42501', null, 'upload for a Memory authored by someone else is denied');
select throws_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('bob', '55555555-0000-0000-0000-000000000002', 'aaaaaaaa-1111-0000-0000-000000000004')),
                '42501', null, 'upload for a Visit Memory is denied to a mere Place Editor (no inheritance)');
select throws_ok($$insert into storage.objects (bucket_id, name) values ('memory-media', 'anything-goes.jpg')$$, '42501', null, 'free-form object names are denied');
select lives_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000005')),
                'a second upload (not yet finalized) is accepted');
select is((select count(*)::int from storage.objects where name = tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000005')), 0,
          'an unfinalized upload (no memory_attachments row) is not readable');
select is(tests.affected(format($f$update storage.objects set metadata = '{}'::jsonb where name = %L$f$, tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000001'))),
          0::bigint, 'objects cannot be updated/overwritten (no UPDATE policy)');
select throws_ok($$update public.memory_attachments set width = 1$$, '42501', null, 'attachment metadata is immutable for clients');
select is((select count(*)::int from storage.objects where name = tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000001')), 1, 'author reads own finalized object');
select tests.clear_authentication();

-- ============ readers ======================================================================
select tests.authenticate_as('carol');
select is((select count(*)::int from storage.objects where name = tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000001')), 1, 'Place Viewer reads Place media');
select is((select count(*)::int from public.memory_attachments), 1, 'Place Viewer reads attachment metadata');
select throws_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('carol', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000006')),
                '42501', null, 'Viewer cannot upload');
select is(tests.affected(format($f$delete from storage.objects where name = %L$f$, tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000001'))),
          0::bigint, 'Viewer cannot delete objects');
select is(tests.affected($$delete from public.memory_attachments$$), 0::bigint, 'Viewer cannot delete attachment rows');
select throws_ok(format($f$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
                   values ('aaaaaaaa-1111-0000-0000-000000000007', '55555555-0000-0000-0000-000000000001', %L, 'image/png', 5)$f$,
                tests.media_path('carol', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000007', 'png')),
                '42501', null, 'Viewer cannot finalize attachments on someone''s Memory');
select tests.clear_authentication();

select tests.authenticate_as('dave');
select is((select count(*)::int from storage.objects), 0, '[6.3] User guesses Storage object path -> denied (outsider sees no objects)');
select is((select count(*)::int from public.memory_attachments), 0, 'outsider sees no attachment rows');
select tests.clear_authentication();
select tests.authenticate_as_anon();
select is((select count(*)::int from storage.objects), 0, '[6.3] anonymous cannot read any object');
select tests.clear_authentication();

-- Visit-scoped media
select tests.authenticate_as('erin');
select lives_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('erin', '55555555-0000-0000-0000-000000000002', 'aaaaaaaa-1111-0000-0000-000000000010', 'heic')),
                'Visit Editor uploads media for a Visit Memory');
select lives_ok(format($f$insert into public.memory_attachments (id, memory_id, storage_path, mime_type, size_bytes)
                   values ('aaaaaaaa-1111-0000-0000-000000000010', '55555555-0000-0000-0000-000000000002', %L, 'image/heic', 2000)$f$,
                tests.media_path('erin', '55555555-0000-0000-0000-000000000002', 'aaaaaaaa-1111-0000-0000-000000000010', 'heic')),
                'finalize Visit attachment (HEIC)');
select tests.clear_authentication();
select tests.authenticate_as('dave');
select is((select count(*)::int from storage.objects), 1, 'Visit Viewer reads Visit media');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is((select count(*)::int from storage.objects where name like '%/55555555-0000-0000-0000-000000000002/%'), 0, 'Place Viewer cannot read Visit media (Place share does not leak Visits)');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is((select count(*)::int from storage.objects where name like '%/55555555-0000-0000-0000-000000000002/%'), 0, 'Place Editor cannot read Visit media either');
select tests.clear_authentication();

-- ============ moderation, soft delete, revocation ==========================================
select tests.authenticate_as('alice');
select is((select count(*)::int from storage.objects), 2, 'Owner reads Place media (bob''s) and the media of the Visit she owns (erin''s)');
select is(tests.affected($$update public.memories set deleted_at = now() where id = '55555555-0000-0000-0000-000000000001'$$), 1::bigint, 'Owner soft-deletes (moderates) bob''s Memory');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is((select count(*)::int from storage.objects where name like '%/55555555-0000-0000-0000-000000000001/%'), 0, 'media of a soft-deleted Memory is no longer readable by members');
select is((select count(*)::int from public.memory_attachments), 0, 'attachment rows of a soft-deleted Memory are hidden too');
select tests.clear_authentication();
select tests.authenticate_as('alice');
select is(tests.affected($$update public.memories set deleted_at = null where id = '55555555-0000-0000-0000-000000000001'$$), 1::bigint, 'Owner restores the Memory');
select lives_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('carol'))$$, 'Owner removes Carol');
select lives_ok($$select public.remove_member('PLACE', '11111111-0000-0000-0000-00000000000a', tests.u('bob'))$$, 'Owner removes Bob');
select tests.clear_authentication();
select tests.authenticate_as('carol');
select is((select count(*)::int from storage.objects), 0, '[6.3] removed member cannot read media');
select tests.clear_authentication();
select tests.authenticate_as('bob');
select is((select count(*)::int from storage.objects), 0, 'removed contributor cannot read his own earlier upload either');
select throws_ok(format($f$insert into storage.objects (bucket_id, name) values ('memory-media', %L)$f$,
                tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000011')),
                '42501', null, 'removed contributor cannot upload any more');
select tests.clear_authentication();

select tests.authenticate_as('alice');
select is(tests.affected(format($f$delete from storage.objects where name = %L$f$, tests.media_path('bob', '55555555-0000-0000-0000-000000000001', 'aaaaaaaa-1111-0000-0000-000000000001'))),
          1::bigint, 'parent Owner can delete a contributor''s object (moderation)');
select is(tests.affected($$delete from public.memory_attachments where id = 'aaaaaaaa-1111-0000-0000-000000000001'$$), 1::bigint, 'parent Owner can delete the attachment row');
select tests.clear_authentication();

-- other buckets: no policy => closed
insert into storage.buckets (id, name, public) values ('other', 'other', false);
select tests.authenticate_as('alice');
select throws_ok($$insert into storage.objects (bucket_id, name) values ('other', 'x.jpg')$$, '42501', null, 'no policy for other buckets (deny by default)');
select tests.clear_authentication();

select * from finish();
rollback;
