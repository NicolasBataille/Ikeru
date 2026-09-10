-- ⚠️ Rapatriée depuis la base le 2026-08-20 : cette migration était
-- APPLIQUÉE en production sans exister dans le dépôt. Découverte en
-- poussant `text_imports` — le CLI a refusé de pousser tant que
-- l'historique distant contenait des versions sans fichier local.
--
-- Elle n'a PAS été rejouée : le contenu ci-dessous est celui que le
-- serveur a réellement exécuté, relu depuis
-- `supabase_migrations.schema_migrations`. Le dépôt dit désormais la
-- vérité sur ce qui tourne.

-- The trigger function needs no elevated rights: it only stamps a column on
-- the row being written, and the write itself is already gated by RLS.
-- SECURITY DEFINER was gratuitous, and it made the function callable over the
-- REST RPC surface by anon. Neither is wanted.
create or replace function public.touch_server_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.server_updated_at := now();
  return new;
end;
$$;

revoke all on function public.touch_server_updated_at() from public, anon, authenticated;
