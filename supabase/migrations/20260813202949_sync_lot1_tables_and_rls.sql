-- ⚠️ Rapatriée depuis la base le 2026-08-20 : cette migration était
-- APPLIQUÉE en production sans exister dans le dépôt. Découverte en
-- poussant `text_imports` — le CLI a refusé de pousser tant que
-- l'historique distant contenait des versions sans fichier local.
--
-- Elle n'a PAS été rejouée : le contenu ci-dessous est celui que le
-- serveur a réellement exécuté, relu depuis
-- `supabase_migrations.schema_migrations`. Le dépôt dit désormais la
-- vérité sur ce qui tourne.

-- Ikeru cloud sync — Lot 1 (push-only backup).
--
-- Design note, so the next reader does not mistake this for laziness:
-- each table carries typed IDENTITY and SYNC columns, plus the record itself
-- as jsonb. Lot 1 only pushes; nothing merges field-by-field yet, so
-- normalising every Swift property into a column would mean guessing at
-- field lists the client does not yet serialise — and a wrong column is worse
-- than no column. The payload round-trips losslessly, Postgres can still query
-- into it (payload->>'grade'), and Lot 2 can promote whichever fields the
-- merge rules actually need. See docs/design-specs/2026-08-10-cloud-sync-design.md
--
-- Primary keys are the CLIENT-GENERATED UUIDs the app already uses, which is
-- what makes upsert idempotent: replaying a push is a no-op.
--
-- deleted_at is a TOMBSTONE, not a convenience. Without it a deletion cannot
-- propagate: device B would forever re-send the row device A erased.

create extension if not exists "pgcrypto";

-- One row per synced record, across eight entity tables.
create table public.profiles (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.cards (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  profile_id uuid,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Append-only, and the highest-volume table: the columns that the learner
-- review packet and the confusion aggregate actually read are promoted out of
-- the payload so they can be indexed and grouped server-side.
create table public.review_logs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  card_id uuid,
  occurred_at timestamptz not null,
  grade smallint,
  answered_value text,
  exercise_type text,
  surface text,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.rpg_states (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  profile_id uuid,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.vocabulary_entries (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  profile_id uuid,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.vocabulary_encounters (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  entry_id uuid,
  occurred_at timestamptz,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

create table public.exercise_outcome_logs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  profile_id uuid,
  occurred_at timestamptz,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Free-text the learner wrote. Kept in its own table precisely so it can be
-- opted into separately from the rest — see the privacy section of the spec.
create table public.companion_chat_messages (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  profile_id uuid,
  occurred_at timestamptz,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Pull cursor (Lot 2) reads server_updated_at, never the device clock: client
-- clocks drift and would silently skip rows.
create index cards_user_cursor_idx on public.cards (user_id, server_updated_at);
create index review_logs_user_cursor_idx on public.review_logs (user_id, server_updated_at);
create index review_logs_user_card_idx on public.review_logs (user_id, card_id);
create index review_logs_confusion_idx on public.review_logs (user_id, answered_value) where answered_value is not null;
create index vocabulary_entries_user_cursor_idx on public.vocabulary_entries (user_id, server_updated_at);
create index vocabulary_encounters_user_cursor_idx on public.vocabulary_encounters (user_id, server_updated_at);
create index exercise_outcome_logs_user_cursor_idx on public.exercise_outcome_logs (user_id, server_updated_at);
create index companion_chat_messages_user_cursor_idx on public.companion_chat_messages (user_id, server_updated_at);
create index profiles_user_cursor_idx on public.profiles (user_id, server_updated_at);
create index rpg_states_user_cursor_idx on public.rpg_states (user_id, server_updated_at);

-- server_updated_at is maintained by the server, never trusted from the client.
create or replace function public.touch_server_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.server_updated_at := now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','cards','review_logs','rpg_states','vocabulary_entries',
    'vocabulary_encounters','exercise_outcome_logs','companion_chat_messages'
  ]
  loop
    execute format(
      'create trigger %I_touch_server_updated_at before insert or update on public.%I
         for each row execute function public.touch_server_updated_at()', t, t);

    -- RLS is the ONLY thing standing between the publishable key and the data.
    -- The key ships in a public repo by design; without these policies it would
    -- grant full access.
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);

    execute format(
      'create policy %I_select_own on public.%I for select using (auth.uid() = user_id)', t, t);
    execute format(
      'create policy %I_insert_own on public.%I for insert with check (auth.uid() = user_id)', t, t);
    execute format(
      'create policy %I_update_own on public.%I for update using (auth.uid() = user_id) with check (auth.uid() = user_id)', t, t);
    execute format(
      'create policy %I_delete_own on public.%I for delete using (auth.uid() = user_id)', t, t);
  end loop;
end;
$$;
