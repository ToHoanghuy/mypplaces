-- =============================================================================
-- MyPlaces – 02: tables, constraints, indexes
-- Conventions:
--   * client-generated UUID primary keys (default gen_random_uuid()) => idempotent creates
--   * timestamps are timestamptz (UTC instants); visits also keep an IANA timezone_id
--   * soft delete via deleted_at; NO "ON DELETE CASCADE" between domain tables
--   * owner_id / author_id / created_by default to auth.uid(); RLS WITH CHECK forces them = auth.uid()
-- =============================================================================

-- ---------------------------------------------------------------- profiles ----
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete restrict,
  display_name text not null
    constraint profiles_display_name_len check (char_length(btrim(display_name)) between 1 and 40),
  avatar_path  text
    constraint profiles_avatar_path_len check (avatar_path is null or char_length(avatar_path) <= 512),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.profiles is 'Minimal public profile. Created by trigger on auth.users. Never stores email.';

-- ------------------------------------------------------------------ places ----
create table public.places (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null default auth.uid() references public.profiles (id),
  title             text not null
    constraint places_title_len check (char_length(btrim(title)) between 1 and 100),
  category          public.place_category not null default 'OTHER',
  latitude          double precision not null
    constraint places_latitude_range check (latitude between -90 and 90),
  longitude         double precision not null
    constraint places_longitude_range check (longitude between -180 and 180),
  address           text
    constraint places_address_len check (address is null or char_length(address) <= 500),
  provider          text
    constraint places_provider_len check (provider is null or char_length(btrim(provider)) between 1 and 50),
  provider_place_id text
    constraint places_provider_place_id_len check (provider_place_id is null or char_length(btrim(provider_place_id)) between 1 and 255),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  constraint places_provider_pair check ((provider is null) = (provider_place_id is null))
);
comment on table public.places is 'Canonical place (geographic entity). visited_at lives on visits, not here (BRD v1.1 §32.2).';

-- Dedup only per owner and only for live rows (two users may both save the same provider place).
create unique index places_owner_provider_uidx
  on public.places (owner_id, provider, provider_place_id)
  where provider_place_id is not null and deleted_at is null;
create index places_owner_created_idx   on public.places (owner_id, created_at desc) where deleted_at is null;
create index places_owner_category_idx  on public.places (owner_id, category) where deleted_at is null;
create index places_owner_coord_idx     on public.places (owner_id, latitude, longitude) where deleted_at is null;

-- ------------------------------------------------------------------ visits ----
create table public.visits (
  id          uuid primary key default gen_random_uuid(),
  place_id    uuid not null references public.places (id),
  owner_id    uuid not null default auth.uid() references public.profiles (id),
  created_by  uuid not null default auth.uid() references public.profiles (id),
  visited_at  timestamptz not null,
  timezone_id text not null
    constraint visits_timezone_len check (char_length(timezone_id) between 1 and 64),
  note        text
    constraint visits_note_len check (note is null or char_length(note) <= 1000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
comment on table public.visits is 'One visit to a place. owner_id is the Visit owner (decision 1 / ERD-06: creator owns it).';
create index visits_place_visited_idx on public.visits (place_id, visited_at desc) where deleted_at is null;
create index visits_owner_visited_idx on public.visits (owner_id, visited_at desc) where deleted_at is null;

-- ------------------------------------------------------ visit_participants ----
create table public.visit_participants (
  id                    uuid primary key default gen_random_uuid(),
  visit_id              uuid not null references public.visits (id),
  user_id               uuid references public.profiles (id),
  display_name_snapshot text
    constraint visit_participants_name_len check (display_name_snapshot is null or char_length(btrim(display_name_snapshot)) <= 40),
  added_by              uuid not null default auth.uid() references public.profiles (id),
  created_at            timestamptz not null default now(),
  -- ERD-01: a guest (no account) is allowed, but then it needs a label.
  constraint visit_participants_user_or_label
    check (user_id is not null or char_length(btrim(coalesce(display_name_snapshot, ''))) >= 1)
);
comment on table public.visit_participants is 'People who were actually present at a visit. Grants NO access (ERD-01).';
create unique index visit_participants_visit_user_uidx
  on public.visit_participants (visit_id, user_id) where user_id is not null;
create index visit_participants_visit_idx on public.visit_participants (visit_id);
create index visit_participants_user_idx  on public.visit_participants (user_id) where user_id is not null;

-- ---------------------------------------------------------------- journals ----
create table public.journals (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references public.profiles (id),
  title       text not null
    constraint journals_title_len check (char_length(btrim(title)) between 1 and 120),
  description text
    constraint journals_description_len check (description is null or char_length(description) <= 2000),
  cover_path  text
    constraint journals_cover_path_len check (cover_path is null or char_length(cover_path) <= 512),
  start_date  date,
  end_date    date,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  archived_at timestamptz,
  deleted_at  timestamptz,
  constraint journals_date_range check (start_date is null or end_date is null or end_date >= start_date)
);
create index journals_owner_created_idx on public.journals (owner_id, created_at desc) where deleted_at is null;

-- ------------------------------------------------- journal_places / visits ----
create table public.journal_places (
  id         uuid primary key default gen_random_uuid(),
  journal_id uuid not null references public.journals (id),
  place_id   uuid not null references public.places (id),
  added_by   uuid not null default auth.uid() references public.profiles (id),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint journal_places_journal_place_uq unique (journal_id, place_id)
);
create index journal_places_journal_sort_idx on public.journal_places (journal_id, sort_order);
create index journal_places_place_idx        on public.journal_places (place_id);

create table public.journal_visits (
  id         uuid primary key default gen_random_uuid(),
  journal_id uuid not null references public.journals (id),
  visit_id   uuid not null references public.visits (id),
  added_by   uuid not null default auth.uid() references public.profiles (id),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint journal_visits_journal_visit_uq unique (journal_id, visit_id),
  -- target of the composite FK memories(journal_visit_id, journal_id) (decision 4)
  constraint journal_visits_id_journal_uq unique (id, journal_id)
);
create index journal_visits_journal_sort_idx on public.journal_visits (journal_id, sort_order);
create index journal_visits_visit_idx        on public.journal_visits (visit_id);

-- --------------------------------------------------------------- memories ----
create table public.memories (
  id               uuid primary key default gen_random_uuid(),
  author_id        uuid not null default auth.uid() references public.profiles (id),
  place_id         uuid references public.places (id),
  visit_id         uuid references public.visits (id),
  journal_id       uuid references public.journals (id),
  -- Decision 4: NON-parent context pointer, only meaningful when journal_id is the parent.
  journal_visit_id uuid,
  type             public.memory_type not null default 'NOTE',
  body             text
    constraint memories_body_len check (body is null or char_length(body) <= 2000),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  -- ERD-05: exactly one parent
  constraint memories_exactly_one_parent check (num_nonnulls(place_id, visit_id, journal_id) = 1),
  constraint memories_journal_visit_needs_journal check (journal_visit_id is null or journal_id is not null),
  constraint memories_note_needs_body check (type <> 'NOTE' or char_length(btrim(coalesce(body, ''))) >= 1),
  -- The link must belong to the SAME journal. Unlinking a visit from a journal must not be blocked
  -- by memories, so only journal_visit_id (never journal_id) is nulled (PostgreSQL 15+ syntax).
  constraint memories_journal_visit_fk foreign key (journal_visit_id, journal_id)
    references public.journal_visits (id, journal_id) on delete set null (journal_visit_id)
);
create index memories_place_created_idx   on public.memories (place_id, created_at desc)   where place_id is not null   and deleted_at is null;
create index memories_visit_created_idx   on public.memories (visit_id, created_at desc)   where visit_id is not null   and deleted_at is null;
create index memories_journal_created_idx on public.memories (journal_id, created_at desc) where journal_id is not null and deleted_at is null;
create index memories_author_idx          on public.memories (author_id);
create index memories_journal_visit_idx   on public.memories (journal_visit_id) where journal_visit_id is not null;

-- ------------------------------------------------------ memory_attachments ----
-- Storage path convention: {uploader_id}/{memory_id}/{attachment_id}.{jpg|jpeg|png|heic}
create table public.memory_attachments (
  id             uuid primary key default gen_random_uuid(),
  memory_id      uuid not null references public.memories (id),
  storage_bucket text not null default 'memory-media'
    constraint memory_attachments_bucket check (storage_bucket = 'memory-media'),
  storage_path   text not null unique
    constraint memory_attachments_path_format check (
      storage_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$'
    ),
  mime_type      text not null
    constraint memory_attachments_mime check (mime_type in ('image/jpeg', 'image/png', 'image/heic')),
  size_bytes     bigint not null
    constraint memory_attachments_size check (size_bytes between 1 and 10485760),
  width          integer constraint memory_attachments_width check (width is null or width > 0),
  height         integer constraint memory_attachments_height check (height is null or height > 0),
  created_at     timestamptz not null default now(),
  -- path = {uploader}/{memory_id}/{id}.ext : memory segment and file name must match the row
  constraint memory_attachments_path_memory check (split_part(storage_path, '/', 2) = memory_id::text),
  constraint memory_attachments_path_id     check (split_part(split_part(storage_path, '/', 3), '.', 1) = id::text)
);
create index memory_attachments_memory_idx on public.memory_attachments (memory_id);

-- ------------------------------------------------------ membership tables ----
-- Only EDITOR / VIEWER rows (decision 2). Written exclusively by the RPCs of migration 07.
create table public.place_members (
  id         uuid primary key default gen_random_uuid(),
  place_id   uuid not null references public.places (id),
  user_id    uuid not null references public.profiles (id),
  role       public.member_role not null check (role in ('EDITOR', 'VIEWER')),
  status     public.member_status not null default 'ACTIVE',
  invited_by uuid references public.profiles (id),
  joined_at  timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint place_members_uq unique (place_id, user_id)
);
create index place_members_user_status_idx     on public.place_members (user_id, status);
create index place_members_place_status_idx    on public.place_members (place_id, status);

create table public.visit_members (
  id         uuid primary key default gen_random_uuid(),
  visit_id   uuid not null references public.visits (id),
  user_id    uuid not null references public.profiles (id),
  role       public.member_role not null check (role in ('EDITOR', 'VIEWER')),
  status     public.member_status not null default 'ACTIVE',
  invited_by uuid references public.profiles (id),
  joined_at  timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint visit_members_uq unique (visit_id, user_id)
);
create index visit_members_user_status_idx  on public.visit_members (user_id, status);
create index visit_members_visit_status_idx on public.visit_members (visit_id, status);

create table public.journal_members (
  id         uuid primary key default gen_random_uuid(),
  journal_id uuid not null references public.journals (id),
  user_id    uuid not null references public.profiles (id),
  role       public.member_role not null check (role in ('EDITOR', 'VIEWER')),
  status     public.member_status not null default 'ACTIVE',
  invited_by uuid references public.profiles (id),
  joined_at  timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint journal_members_uq unique (journal_id, user_id)
);
create index journal_members_user_status_idx    on public.journal_members (user_id, status);
create index journal_members_journal_status_idx on public.journal_members (journal_id, status);

-- ------------------------------------------------------------- invitations ----
create table public.invitations (
  id                       uuid primary key default gen_random_uuid(),
  resource_type            public.resource_type not null,
  place_id                 uuid references public.places (id),
  visit_id                 uuid references public.visits (id),
  journal_id               uuid references public.journals (id),
  invited_by               uuid not null default auth.uid() references public.profiles (id),
  invitee_user_id          uuid references public.profiles (id),
  invitee_email_normalized text
    constraint invitations_email_normalized check (
      invitee_email_normalized is null
      or (invitee_email_normalized = lower(btrim(invitee_email_normalized))
          and char_length(invitee_email_normalized) between 3 and 254)),
  role                     public.member_role not null
    constraint invitations_role_not_owner check (role in ('EDITOR', 'VIEWER')),
  token_hash               text not null unique,       -- sha256 hex of the raw token; raw token is never stored
  status                   public.invitation_status not null default 'PENDING',
  expires_at               timestamptz not null,
  accepted_by              uuid references public.profiles (id),
  accepted_at              timestamptz,
  created_at               timestamptz not null default now(),
  -- exactly one resource FK, matching resource_type
  constraint invitations_exactly_one_resource check (
       (resource_type = 'PLACE'   and place_id   is not null and visit_id is null     and journal_id is null)
    or (resource_type = 'VISIT'   and visit_id   is not null and place_id is null     and journal_id is null)
    or (resource_type = 'JOURNAL' and journal_id is not null and place_id is null     and visit_id   is null)),
  constraint invitations_accepted_consistent check (
    status <> 'ACCEPTED' or (accepted_by is not null and accepted_at is not null))
);
create index invitations_status_expires_idx on public.invitations (status, expires_at);
create index invitations_place_idx   on public.invitations (place_id,   status) where place_id   is not null;
create index invitations_visit_idx   on public.invitations (visit_id,   status) where visit_id   is not null;
create index invitations_journal_idx on public.invitations (journal_id, status) where journal_id is not null;
create index invitations_invited_by_idx on public.invitations (invited_by);
-- "Unique active invite" policy: at most one PENDING invitation per (resource, invitee).
-- create_invitation() revokes/replaces the previous one instead of failing.
create unique index invitations_pending_user_uidx
  on public.invitations ((coalesce(place_id, visit_id, journal_id)), invitee_user_id)
  where status = 'PENDING' and invitee_user_id is not null;
create unique index invitations_pending_email_uidx
  on public.invitations ((coalesce(place_id, visit_id, journal_id)), invitee_email_normalized)
  where status = 'PENDING' and invitee_email_normalized is not null;

-- --------------------------------------------------------------- audit_log ----
create table public.audit_log (
  id             bigint generated always as identity primary key,
  actor_id       uuid,                       -- no FK: audit must outlive accounts
  action         text not null,
  resource_type  text not null
    constraint audit_log_resource_type check (resource_type in ('PLACE', 'VISIT', 'JOURNAL', 'MEMORY', 'INVITATION')),
  resource_id    uuid,
  target_user_id uuid,
  metadata       jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index audit_log_resource_idx on public.audit_log (resource_type, resource_id, created_at desc);
create index audit_log_actor_idx    on public.audit_log (actor_id, created_at desc);
create index audit_log_target_idx   on public.audit_log (target_user_id, created_at desc) where target_user_id is not null;
