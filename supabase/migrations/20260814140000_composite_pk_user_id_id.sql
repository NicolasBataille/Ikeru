-- Composite primary key (user_id, id) on every synced table, plus the index the
-- pull actually paginates on.
--
-- ---------------------------------------------------------------------------
-- WHY: a merged bug, found by probing the live project on 2026-08-14
-- ---------------------------------------------------------------------------
--
-- The primary key was `id` alone — the UUID the client generates. That makes a
-- row id unique across ALL users, while the same logical row must legitimately
-- exist once per user.
--
-- The reachable failure, reproduced against this project before writing this:
--
--   1. A refresh token is rejected, so `AnonymousIdentityManager` mints a fresh
--      anonymous identity. The old account is now unreachable — no token left
--      for it, so its rows can never be deleted.
--   2. `CloudSyncCoordinator` sees the identity change, resets the cursors, and
--      the pull reads a cold start.
--   3. Rule 1 fires: empty server + populated local ⇒ `seedFromLocal`, which
--      calls `markEverythingUnsynced()` and re-pushes every local row.
--   4. Those rows carry the SAME client UUIDs, still present under the old
--      account. Every single push comes back:
--
--          403  42501  new row violates row-level security policy for table "cards"
--
--   The learner's history can never be seeded onto the new account. This is the
--   server-side twin of the "wipe → re-enable pushes nothing" defect fixed in
--   lot 2 round 3 — except no client change can fix it.
--
-- Lot 2's tests could not catch this: no in-memory fake server enforces a
-- cross-user primary-key conflict.
--
-- ---------------------------------------------------------------------------
-- WHY THIS SHAPE, and why it costs the client nothing
-- ---------------------------------------------------------------------------
--
-- Verified on a scratch table (`_pk_probe`, dropped at the end of this file)
-- before touching anything real:
--
--   A inserts, sending NO user_id, no on_conflict   → 201
--   B inserts the SAME id                           → 201   (no collision)
--   A re-upserts the same id                        → 200   (still idempotent)
--   result: two rows, same id, different owners, each correct
--
-- PostgREST infers the conflict target from the primary key, and `user_id` is
-- still filled by its `auth.uid()` default — so the client keeps never sending
-- it, which was the deliberate rule from lot 1 (a client-supplied user_id that
-- mismatched the bearer token would be a hazard worth avoiding entirely).
--
-- Dropping the old keys is safe: `pg_constraint` confirms no foreign key
-- references these `id` columns. `profile_id` / `card_id` / `entry_id` are
-- plain uuid columns with no enforced constraint.
--
-- ---------------------------------------------------------------------------
-- WHEN
-- ---------------------------------------------------------------------------
--
-- Applied while every table held zero rows. Free today; a data migration
-- later. If this file is ever replayed against a populated database, check
-- first that no two users share a row id — this migration would fail loudly
-- rather than silently merge them, which is the correct outcome.

alter table public.profiles                drop constraint profiles_pkey,                add primary key (user_id, id);
alter table public.rpg_states              drop constraint rpg_states_pkey,              add primary key (user_id, id);
alter table public.cards                   drop constraint cards_pkey,                   add primary key (user_id, id);
alter table public.review_logs             drop constraint review_logs_pkey,             add primary key (user_id, id);
alter table public.vocabulary_entries      drop constraint vocabulary_entries_pkey,      add primary key (user_id, id);
alter table public.vocabulary_encounters   drop constraint vocabulary_encounters_pkey,   add primary key (user_id, id);
alter table public.exercise_outcome_logs   drop constraint exercise_outcome_logs_pkey,   add primary key (user_id, id);
alter table public.companion_chat_messages drop constraint companion_chat_messages_pkey, add primary key (user_id, id);

-- The pull paginates with `order=server_updated_at.asc,id.asc`, scoped to one
-- user by RLS — see `PostgRESTPullTransport.keysetFilter`. This is the index
-- that keyset walk needs; without it every page is a sort over that user's
-- whole table. Nothing covered it before this migration.
create index if not exists profiles_keyset_idx                on public.profiles                (user_id, server_updated_at, id);
create index if not exists rpg_states_keyset_idx              on public.rpg_states              (user_id, server_updated_at, id);
create index if not exists cards_keyset_idx                   on public.cards                   (user_id, server_updated_at, id);
create index if not exists review_logs_keyset_idx             on public.review_logs             (user_id, server_updated_at, id);
create index if not exists vocabulary_entries_keyset_idx      on public.vocabulary_entries      (user_id, server_updated_at, id);
create index if not exists vocabulary_encounters_keyset_idx   on public.vocabulary_encounters   (user_id, server_updated_at, id);
create index if not exists exercise_outcome_logs_keyset_idx   on public.exercise_outcome_logs   (user_id, server_updated_at, id);
create index if not exists companion_chat_messages_keyset_idx on public.companion_chat_messages (user_id, server_updated_at, id);

-- Scratch table used to validate the shape above. Nothing references it.
drop table if exists public._pk_probe;
