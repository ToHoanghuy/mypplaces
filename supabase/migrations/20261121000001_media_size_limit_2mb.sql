-- Client-side compression (21/11/2026): the app now uploads JPEG <= 1600 px, quality 0.7 -> 0.5
-- (measured 248-464 KB per photo). Tighten the server-side guard from 10 MB to 2 MB.
-- Safe for existing data: largest object in memory-media was 970 KB when this was applied, and the
-- previous app build (2048 px, q 0.82) produced <= ~1.4 MB on sample photos. MIME allowlist unchanged.
update storage.buckets
   set file_size_limit = 2097152
 where id = 'memory-media';

alter table public.memory_attachments drop constraint memory_attachments_size;
alter table public.memory_attachments
  add constraint memory_attachments_size check (size_bytes between 1 and 2097152);
