-- =============================================================================
-- MyPlaces – 01: extensions, private schema, enums
-- Sources: BRD v1.1 (10/11/2026), ERD & Permission Design v1.1.
-- =============================================================================

-- pgcrypto: only used for extensions.gen_random_bytes() (invitation tokens).
create extension if not exists pgcrypto with schema extensions;

-- Schema "private" holds RLS helper functions and internal trigger functions.
-- It is NOT exposed through PostgREST (only "public" is), so helpers are not callable as REST RPC.
create schema if not exists private;
revoke all on schema private from public;

-- Place categories (BRD §8.1). Unknown category -> OTHER.
create type public.place_category as enum (
  'FOOD', 'CAFE', 'TRAVEL', 'HOTEL', 'SHOPPING', 'ENTERTAINMENT', 'OTHER'
);

-- Role vocabulary of the ERD. Membership tables and invitations only ever hold
-- EDITOR / VIEWER (CHECK constraints); the single OWNER lives in <resource>.owner_id (decision 2).
create type public.member_role as enum ('OWNER', 'EDITOR', 'VIEWER');

create type public.member_status as enum ('ACTIVE', 'REMOVED', 'LEFT');

create type public.invitation_status as enum (
  'PENDING', 'ACCEPTED', 'DECLINED', 'REVOKED', 'EXPIRED'
);

-- Shareable resources (Place, Visit, Journal).
create type public.resource_type as enum ('PLACE', 'VISIT', 'JOURNAL');

-- Memory type. MVP: short note + photo (photo = Memory with attachment(s)).
create type public.memory_type as enum ('NOTE', 'PHOTO');
