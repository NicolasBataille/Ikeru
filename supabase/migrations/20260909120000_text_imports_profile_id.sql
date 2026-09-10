-- `text_imports.profile_id` — the owner the app-side model gained in
-- IkeruSchemaV6 (P1-1 / OBS2-022, 2026-09-09).
--
-- The table's own header announced this trade: it promotes every field to a
-- column and keeps no `payload` blob, so a new field on `TextImport` needs a
-- DDL migration. This is the first one.
--
-- `vocabulary_entries.profile_id` needs nothing: the baseline migration
-- created it on 2026-08-10, and the app pushed `null` into it until now.
--
-- Nullable, no foreign key, no backfill — for the same reasons the baseline
-- gave `vocabulary_entries.profile_id` none: the profile is a client-side
-- notion (`profiles` rows are pushed by the same client, and a row can
-- legitimately arrive before its profile does), and a row a pre-V6 device
-- pushes carries `null`, which the app resolves on pull (`OwnershipAdoption`).
--
-- ⚠️ Deploy order: this must be applied BEFORE a V6 build reaches a device.
-- PostgREST rejects an upsert that names an unknown column, and the client
-- pushes `profile_id` on every `text_imports` row — the whole batch would
-- fail with a 400 until the column exists.
--
-- Idempotent, like every migration in this directory.

alter table public.text_imports
  add column if not exists profile_id uuid;

comment on column public.text_imports.profile_id is
  'Owning UserProfile.id, client-side notion (no FK). Null for rows pushed by an app older than IkeruSchemaV6; the app attributes them on pull.';
