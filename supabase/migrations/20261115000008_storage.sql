-- =============================================================================
-- MyPlaces – 08: private Storage bucket + storage.objects policies
-- Path convention (also enforced by a CHECK on memory_attachments.storage_path):
--     memory-media / {uploader_id}/{memory_id}/{attachment_id}.{jpg|jpeg|png|heic}
-- Path secrecy is NOT authorization (ERD §7): every policy resolves the memory and checks the
-- caller's rights on the memory's parent (Place / Visit / Journal).
--   read   : the attachment row exists AND caller can read the memory (=> parent readable)
--   upload : caller is the memory's author AND ACTIVE Owner/EDITOR of its parent, path folder 1 = caller
--   delete : memory author or parent Owner (moderation)
--   update : NO policy => objects cannot be overwritten (BRD §25.4: no overwrite of the same path)
-- Flow: 1) create memory row  2) upload object  3) insert memory_attachments row (finalize).
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('memory-media', 'memory-media', false, 10485760, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create function private.is_valid_media_path(p_path text) returns boolean
language sql immutable set search_path = ''
as $$
  select coalesce(p_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$', false);
$$;

create function private.can_read_memory_path(p_path text) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.memory_attachments a
                 where a.storage_path = p_path and private.can_read_memory(a.memory_id));
$$;

create function private.can_upload_memory_path(p_path text) returns boolean
language sql stable security definer set search_path = ''
as $$
  select case when private.is_valid_media_path(p_path)
              then split_part(p_path, '/', 1) = auth.uid()::text
                   and private.can_write_own_memory(split_part(p_path, '/', 2)::uuid)
              else false end;
$$;

create function private.can_remove_memory_path(p_path text) returns boolean
language sql stable security definer set search_path = ''
as $$
  select case when private.is_valid_media_path(p_path)
              then private.can_remove_memory_content(split_part(p_path, '/', 2)::uuid)
              else false end;
$$;

create policy memory_media_select on storage.objects for select to authenticated
  using (bucket_id = 'memory-media' and private.can_read_memory_path(name));
create policy memory_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'memory-media' and private.can_upload_memory_path(name));
create policy memory_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'memory-media' and private.can_remove_memory_path(name));
